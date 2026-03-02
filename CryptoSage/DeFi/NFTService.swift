//
//  NFTService.swift
//  CryptoSage
//
//  Service for fetching NFT holdings and valuations.
//

import Foundation
import Combine

// MARK: - NFT Service

/// Service for fetching NFT data from various sources
public final class NFTService: ObservableObject {
    public static let shared = NFTService()
    
    // MARK: - Published Properties
    
    @Published public private(set) var isLoading = false
    @Published public private(set) var lastError: Error?
    @Published public private(set) var portfolios: [String: NFTPortfolio] = [:] // address -> portfolio
    
    // MARK: - Private Properties
    
    private let session: URLSession
    private let chainRegistry = ChainRegistry.shared
    
    // Cache
    private let cacheTTL: TimeInterval = 600 // 10 minutes
    private var cacheTimestamps: [String: Date] = [:]
    
    // MARK: - Initialization
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Public API
    
    /// Fetch all NFTs for an address across supported chains
    public func fetchNFTs(
        address: String,
        chains: [Chain]? = nil
    ) async throws -> NFTPortfolio {
        isLoading = true
        defer { isLoading = false }
        
        let targetChains = chains ?? [.ethereum, .polygon, .solana]
        
        // Check cache
        let cacheKey = address.lowercased()
        if let cached = portfolios[cacheKey],
           let timestamp = cacheTimestamps[cacheKey],
           Date().timeIntervalSince(timestamp) < cacheTTL {
            return cached
        }
        
        var allNFTs: [NFT] = []
        var allCollections: [NFTCollection] = []
        
        // Fetch from each chain in parallel
        await withTaskGroup(of: (Chain, [NFT], [NFTCollection]).self) { group in
            for chain in targetChains {
                group.addTask {
                    do {
                        let (nfts, collections) = try await self.fetchChainNFTs(address: address, chain: chain)
                        return (chain, nfts, collections)
                    } catch {
                        #if DEBUG
                        print("⚠️ Error fetching \(chain.displayName) NFTs: \(error.localizedDescription)")
                        #endif
                        return (chain, [], [])
                    }
                }
            }
            
            for await (_, nfts, collections) in group {
                allNFTs.append(contentsOf: nfts)
                allCollections.append(contentsOf: collections)
            }
        }
        
        // Calculate total value
        let totalValue = allNFTs.compactMap { $0.estimatedValueUSD }.reduce(0, +)
        
        let portfolio = NFTPortfolio(
            address: address,
            nfts: allNFTs,
            collections: allCollections,
            totalEstimatedValueUSD: totalValue
        )
        
        // Cache
        portfolios[cacheKey] = portfolio
        cacheTimestamps[cacheKey] = Date()
        
        return portfolio
    }
    
    /// Fetch NFTs for a specific chain
    public func fetchChainNFTs(
        address: String,
        chain: Chain
    ) async throws -> (nfts: [NFT], collections: [NFTCollection]) {
        switch chain {
        case .ethereum, .polygon, .arbitrum, .optimism, .base:
            return try await fetchEVMNFTs(address: address, chain: chain)
        case .solana:
            return try await fetchSolanaNFTs(address: address)
        default:
            return ([], [])
        }
    }
    
    /// Get collection info
    public func fetchCollection(
        contractAddress: String,
        chain: Chain
    ) async throws -> NFTCollection? {
        // Try OpenSea first
        if let collection = try? await fetchOpenSeaCollection(contractAddress: contractAddress, chain: chain) {
            return collection
        }
        
        return nil
    }
    
    // MARK: - EVM NFT Fetching (OpenSea / Alchemy)
    
    private func fetchEVMNFTs(
        address: String,
        chain: Chain
    ) async throws -> (nfts: [NFT], collections: [NFTCollection]) {
        
        // Try Alchemy first (better rate limits with API key)
        if let alchemyKey = chainRegistry.apiKey(for: ChainAPIService.alchemy.rawValue) {
            return try await fetchAlchemyNFTs(address: address, chain: chain, apiKey: alchemyKey)
        }
        
        // Fallback to OpenSea
        return try await fetchOpenSeaNFTs(address: address, chain: chain)
    }
    
    private func fetchAlchemyNFTs(
        address: String,
        chain: Chain,
        apiKey: String
    ) async throws -> (nfts: [NFT], collections: [NFTCollection]) {
        
        let baseURL = alchemyEndpoint(for: chain, apiKey: apiKey)
        let urlString = "\(baseURL)/getNFTsForOwner?owner=\(address)&withMetadata=true"
        
        guard let url = URL(string: urlString) else {
            throw DeFiError.invalidURL
        }
        
        let (data, _) = try await session.data(from: url)
        let response = try JSONDecoder().decode(AlchemyNFTResponse.self, from: data)
        
        var nfts: [NFT] = []
        var collectionsMap: [String: NFTCollection] = [:]
        
        for alchemyNFT in response.ownedNfts {
            // Parse NFT
            let imageURL = alchemyNFT.media?.first?.gateway ?? alchemyNFT.media?.first?.thumbnail
            
            let nft = NFT(
                contractAddress: alchemyNFT.contract.address,
                tokenId: alchemyNFT.tokenId,
                chain: chain,
                name: alchemyNFT.name,
                description: alchemyNFT.description,
                imageURL: imageURL,
                estimatedValueUSD: alchemyNFT.contract.openSea?.floorPrice,
                tokenStandard: tokenStandardFromString(alchemyNFT.tokenType)
            )
            nfts.append(nft)
            
            // Parse collection if not already seen
            let collectionKey = alchemyNFT.contract.address.lowercased()
            if collectionsMap[collectionKey] == nil, let openSea = alchemyNFT.contract.openSea {
                let collection = NFTCollection(
                    contractAddress: alchemyNFT.contract.address,
                    chain: chain,
                    name: openSea.collectionName ?? alchemyNFT.contract.name ?? "Unknown",
                    description: openSea.description,
                    imageURL: openSea.imageUrl,
                    externalURL: openSea.externalUrl,
                    floorPrice: openSea.floorPrice,
                    floorPriceCurrency: "ETH",
                    twitterUsername: openSea.twitterUsername,
                    discordURL: openSea.discordUrl,
                    isVerified: openSea.safelistRequestStatus == "verified",
                    safelistStatus: openSea.safelistRequestStatus
                )
                collectionsMap[collectionKey] = collection
            }
        }
        
        return (nfts, Array(collectionsMap.values))
    }
    
    private func alchemyEndpoint(for chain: Chain, apiKey: String) -> String {
        switch chain {
        case .ethereum: return "https://eth-mainnet.g.alchemy.com/nft/v3/\(apiKey)"
        case .polygon: return "https://polygon-mainnet.g.alchemy.com/nft/v3/\(apiKey)"
        case .arbitrum: return "https://arb-mainnet.g.alchemy.com/nft/v3/\(apiKey)"
        case .optimism: return "https://opt-mainnet.g.alchemy.com/nft/v3/\(apiKey)"
        case .base: return "https://base-mainnet.g.alchemy.com/nft/v3/\(apiKey)"
        default: return "https://eth-mainnet.g.alchemy.com/nft/v3/\(apiKey)"
        }
    }
    
    private func fetchOpenSeaNFTs(
        address: String,
        chain: Chain
    ) async throws -> (nfts: [NFT], collections: [NFTCollection]) {
        
        let chainParam = openSeaChainParam(for: chain)
        let urlString = "https://api.opensea.io/api/v2/chain/\(chainParam)/account/\(address)/nfts"
        
        guard let url = URL(string: urlString) else {
            throw DeFiError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // Add API key if available
        if let apiKey = chainRegistry.apiKey(for: "opensea") {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw DeFiError.invalidResponse
        }
        
        let openSeaResponse = try JSONDecoder().decode(OpenSeaNFTResponse.self, from: data)
        
        var nfts: [NFT] = []
        
        for osNFT in openSeaResponse.nfts ?? [] {
            let attributes = (osNFT.traits ?? []).map { trait in
                NFTAttribute(
                    traitType: trait.trait_type,
                    value: trait.value,
                    displayType: trait.display_type
                )
            }
            
            let nft = NFT(
                contractAddress: osNFT.contract,
                tokenId: osNFT.identifier,
                chain: chain,
                name: osNFT.name,
                description: osNFT.description,
                imageURL: osNFT.image_url,
                animationURL: osNFT.animation_url,
                attributes: attributes,
                tokenStandard: tokenStandardFromString(osNFT.token_standard)
            )
            nfts.append(nft)
        }
        
        return (nfts, [])
    }
    
    private func fetchOpenSeaCollection(
        contractAddress: String,
        chain: Chain
    ) async throws -> NFTCollection {
        
        let chainParam = openSeaChainParam(for: chain)
        let urlString = "https://api.opensea.io/api/v2/chain/\(chainParam)/contract/\(contractAddress)"
        
        guard let url = URL(string: urlString) else {
            throw DeFiError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        if let apiKey = chainRegistry.apiKey(for: "opensea") {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")
        }
        
        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(OpenSeaCollectionResponse.self, from: data)
        
        return NFTCollection(
            contractAddress: contractAddress,
            chain: chain,
            name: response.name,
            description: response.description,
            imageURL: response.image_url,
            bannerImageURL: response.banner_image_url,
            externalURL: response.project_url,
            totalSupply: response.total_supply,
            twitterUsername: response.twitter_username,
            discordURL: response.discord_url,
            isVerified: response.safelist_status == "verified",
            safelistStatus: response.safelist_status
        )
    }
    
    private func openSeaChainParam(for chain: Chain) -> String {
        switch chain {
        case .ethereum: return "ethereum"
        case .polygon: return "matic"
        case .arbitrum: return "arbitrum"
        case .optimism: return "optimism"
        case .base: return "base"
        default: return "ethereum"
        }
    }
    
    // MARK: - Solana NFT Fetching (Helius)
    
    private func fetchSolanaNFTs(
        address: String
    ) async throws -> (nfts: [NFT], collections: [NFTCollection]) {
        
        guard let heliusKey = chainRegistry.apiKey(for: ChainAPIService.helius.rawValue) else {
            // Fallback: return empty if no API key
            return ([], [])
        }
        
        let urlString = "https://api.helius.xyz/v0/addresses/\(address)/nfts?api-key=\(heliusKey)"
        
        guard let url = URL(string: urlString) else {
            throw DeFiError.invalidURL
        }
        
        let (data, _) = try await session.data(from: url)
        let response = try JSONDecoder().decode(HeliusNFTResponse.self, from: data)
        
        var nfts: [NFT] = []
        
        for heliusNFT in response.items {
            let content = heliusNFT.content
            let metadata = content?.metadata
            
            let attributes = (metadata?.attributes ?? []).compactMap { attr -> NFTAttribute? in
                guard let traitType = attr.trait_type, let value = attr.value else { return nil }
                return NFTAttribute(traitType: traitType, value: value)
            }
            
            let nft = NFT(
                contractAddress: heliusNFT.id, // Mint address
                tokenId: heliusNFT.id,
                chain: .solana,
                name: metadata?.name,
                description: metadata?.description,
                imageURL: content?.links?.image ?? content?.files?.first?.cdn_uri,
                animationURL: content?.links?.animation_url,
                externalURL: content?.links?.external_url,
                attributes: attributes,
                tokenStandard: .metaplex,
                ownerAddress: heliusNFT.ownership?.owner,
                creatorAddress: heliusNFT.creators?.first?.address
            )
            nfts.append(nft)
        }
        
        return (nfts, [])
    }
    
    // MARK: - Helpers
    
    private func tokenStandardFromString(_ standard: String) -> NFTTokenStandard {
        switch standard.uppercased() {
        case "ERC721": return .erc721
        case "ERC1155": return .erc1155
        case "SPL", "SOLANA": return .spl
        case "METAPLEX": return .metaplex
        default: return .unknown
        }
    }
    
    /// Clear cache
    public func clearCache() {
        portfolios.removeAll()
        cacheTimestamps.removeAll()
    }
}

// MARK: - NFT Valuation

extension NFTService {
    
    /// Estimate NFT value based on floor price
    public func estimateValue(for nft: NFT) async -> Double? {
        // Try to get collection floor price
        guard let collection = try? await fetchCollection(
            contractAddress: nft.contractAddress,
            chain: nft.chain
        ) else {
            return nft.estimatedValueUSD
        }
        
        return collection.floorPriceUSD
    }
    
    /// Calculate portfolio value from floor prices
    public func calculatePortfolioValue(_ portfolio: NFTPortfolio) async -> Double {
        var total: Double = 0
        
        for nft in portfolio.nfts {
            if let value = await estimateValue(for: nft) {
                total += value
            }
        }
        
        return total
    }
}

// MARK: - Blur API Integration

extension NFTService {
    
    /// Blur API response models
    struct BlurCollectionResponse: Codable {
        let success: Bool?
        let collection: BlurCollection?
    }
    
    struct BlurCollection: Codable {
        let contractAddress: String?
        let name: String?
        let imageUrl: String?
        let totalSupply: Int?
        let floorPrice: String?
        let floorPriceOneDay: String?
        let floorPriceOneWeek: String?
        let volumeOneDay: String?
        let volumeOneWeek: String?
        let bestBid: String?
        let numberOwners: Int?
    }
    
    struct BlurSalesResponse: Codable {
        let success: Bool?
        let sales: [BlurSale]?
    }
    
    struct BlurSale: Codable {
        let tokenId: String?
        let price: String?
        let ethPrice: String?
        let priceUnit: String?
        let timestamp: Int?
        let fromAddress: String?
        let toAddress: String?
        let txHash: String?
        let marketplace: String?
    }
    
    /// Fetch floor price from Blur API (more accurate than OpenSea for some collections)
    public func fetchBlurFloorPrice(collection contractAddress: String) async throws -> Double? {
        // Blur API endpoint for collection stats
        let urlString = "https://api.blur.io/v1/collections/\(contractAddress.lowercased())"
        guard let url = URL(string: urlString) else { return nil }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CryptoSage/1.0", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return nil
            }
            
            let blurResponse = try JSONDecoder().decode(BlurCollectionResponse.self, from: data)
            
            if let floorPriceStr = blurResponse.collection?.floorPrice,
               let floorPrice = Double(floorPriceStr) {
                return floorPrice
            }
            
            return nil
        } catch {
            #if DEBUG
            print("⚠️ Blur API error: \(error.localizedDescription)")
            #endif
            return nil
        }
    }
    
    /// Fetch recent sales history for an NFT collection
    public func fetchSalesHistory(
        collection contractAddress: String,
        tokenId: String? = nil,
        limit: Int = 20
    ) async throws -> [NFTSale] {
        // Try Blur first, then OpenSea
        var sales: [NFTSale] = []
        
        // Blur sales endpoint
        var urlString = "https://api.blur.io/v1/collections/\(contractAddress.lowercased())/sales?limit=\(limit)"
        if let tokenId = tokenId {
            urlString += "&tokenId=\(tokenId)"
        }
        
        guard let url = URL(string: urlString) else { return [] }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return []
            }
            
            let blurResponse = try JSONDecoder().decode(BlurSalesResponse.self, from: data)
            
            for sale in blurResponse.sales ?? [] {
                let nftSale = NFTSale(
                    tokenId: sale.tokenId ?? "",
                    contractAddress: contractAddress,
                    priceETH: Double(sale.ethPrice ?? "") ?? 0,
                    priceUSD: nil, // Would need to convert
                    timestamp: Date(timeIntervalSince1970: TimeInterval(sale.timestamp ?? 0)),
                    fromAddress: sale.fromAddress ?? "",
                    toAddress: sale.toAddress ?? "",
                    txHash: sale.txHash,
                    marketplace: sale.marketplace ?? "blur"
                )
                sales.append(nftSale)
            }
        } catch {
            #if DEBUG
            print("⚠️ Failed to fetch Blur sales: \(error.localizedDescription)")
            #endif
        }
        
        return sales
    }
    
    /// Get best floor price by checking multiple sources
    public func getBestFloorPrice(collection contractAddress: String, chain: Chain) async -> Double? {
        // Fetch from both sources concurrently using Tasks to handle errors
        let blurTask = Task<Double?, Never> {
            return try? await self.fetchBlurFloorPrice(collection: contractAddress)
        }
        
        let openSeaTask = Task<NFTCollection?, Never> {
            return try? await self.fetchCollection(contractAddress: contractAddress, chain: chain)
        }
        
        let blurPrice = await blurTask.value
        let collection = await openSeaTask.value
        
        // Return the lower (more accurate/aggressive) floor
        let openSeaFloor = collection?.floorPrice
        
        switch (blurPrice, openSeaFloor) {
        case (.some(let blur), .some(let opensea)):
            return min(blur, opensea)
        case (.some(let blur), .none):
            return blur
        case (.none, .some(let opensea)):
            return opensea
        case (.none, .none):
            return nil
        }
    }
}

// MARK: - Rarity Scoring

extension NFTService {
    
    /// Calculate rarity score for an NFT based on its traits
    public func calculateRarityScore(for nft: NFT, collectionTraits: [String: [String: Int]]? = nil) -> NFTRarityResult? {
        guard !nft.attributes.isEmpty else { return nil }
        
        // If we have collection trait distribution, use that for accurate scoring
        if let traits = collectionTraits {
            return calculateRarityWithDistribution(nft: nft, traitDistribution: traits)
        }
        
        // Otherwise, use a simplified scoring based on attribute count
        return calculateSimplifiedRarity(nft: nft)
    }
    
    private func calculateRarityWithDistribution(nft: NFT, traitDistribution: [String: [String: Int]]) -> NFTRarityResult {
        var traitScores: [NFTTraitRarity] = []
        var totalScore: Double = 0
        var totalTraits = 0
        
        for attribute in nft.attributes {
            guard let traitValues = traitDistribution[attribute.traitType],
                  let count = traitValues[attribute.value] else {
                continue
            }
            
            let totalInCategory = traitValues.values.reduce(0, +)
            guard totalInCategory > 0 else { continue }
            
            // Rarity percentage (lower = rarer)
            let rarityPercent = Double(count) / Double(totalInCategory) * 100
            
            // Score (inverse of rarity - rarer traits get higher scores)
            let score = 1.0 / (rarityPercent / 100)
            
            traitScores.append(NFTTraitRarity(
                traitType: attribute.traitType,
                value: attribute.value,
                rarityPercent: rarityPercent,
                count: count,
                totalInCategory: totalInCategory
            ))
            
            totalScore += score
            totalTraits += 1
        }
        
        // Normalize score (0-100 scale)
        let normalizedScore = totalTraits > 0 ? min(100, (totalScore / Double(totalTraits)) * 10) : 0
        
        // Determine rank tier
        let rank: NFTRarityRank
        switch normalizedScore {
        case 90...: rank = .legendary
        case 75..<90: rank = .epic
        case 50..<75: rank = .rare
        case 25..<50: rank = .uncommon
        default: rank = .common
        }
        
        return NFTRarityResult(
            totalScore: normalizedScore,
            rank: rank,
            traitRarities: traitScores,
            missingTraits: []
        )
    }
    
    private func calculateSimplifiedRarity(nft: NFT) -> NFTRarityResult {
        // Simplified scoring based on trait count and uniqueness heuristics
        let traitCount = nft.attributes.count
        
        // More traits typically means rarer (for most collections)
        let baseScore = min(50, Double(traitCount) * 5)
        
        // Check for potentially rare trait types
        let rareKeywords = ["1/1", "unique", "legendary", "mythic", "genesis", "founder"]
        var bonusScore: Double = 0
        
        for attribute in nft.attributes {
            let lowerValue = attribute.value.lowercased()
            for keyword in rareKeywords {
                if lowerValue.contains(keyword) {
                    bonusScore += 15
                    break
                }
            }
        }
        
        let totalScore = min(100, baseScore + bonusScore)
        
        let rank: NFTRarityRank
        switch totalScore {
        case 80...: rank = .legendary
        case 60..<80: rank = .epic
        case 40..<60: rank = .rare
        case 20..<40: rank = .uncommon
        default: rank = .common
        }
        
        return NFTRarityResult(
            totalScore: totalScore,
            rank: rank,
            traitRarities: [],
            missingTraits: []
        )
    }
    
    /// Fetch trait distribution for a collection (for accurate rarity calculation)
    public func fetchCollectionTraitDistribution(
        contractAddress: String,
        chain: Chain
    ) async throws -> [String: [String: Int]] {
        // This would typically come from an API like Alchemy's getContractMetadata
        // or by parsing all NFTs in the collection
        
        // For now, return empty - in production, integrate with rarity APIs like:
        // - Rarity Sniper API
        // - OpenSea's collection traits endpoint
        // - Alchemy's NFT metadata
        
        return [:]
    }
}

// MARK: - NFT Sale History Models

/// Represents a single NFT sale
public struct NFTSale: Identifiable, Codable {
    public let id: String
    public let tokenId: String
    public let contractAddress: String
    public let priceETH: Double
    public let priceUSD: Double?
    public let timestamp: Date
    public let fromAddress: String
    public let toAddress: String
    public let txHash: String?
    public let marketplace: String
    
    public init(
        id: String = UUID().uuidString,
        tokenId: String,
        contractAddress: String,
        priceETH: Double,
        priceUSD: Double?,
        timestamp: Date,
        fromAddress: String,
        toAddress: String,
        txHash: String?,
        marketplace: String
    ) {
        self.id = id
        self.tokenId = tokenId
        self.contractAddress = contractAddress
        self.priceETH = priceETH
        self.priceUSD = priceUSD
        self.timestamp = timestamp
        self.fromAddress = fromAddress
        self.toAddress = toAddress
        self.txHash = txHash
        self.marketplace = marketplace
    }
}

// MARK: - NFT Rarity Models

/// Rarity rank tiers
public enum NFTRarityRank: String, Codable, CaseIterable {
    case common = "Common"
    case uncommon = "Uncommon"
    case rare = "Rare"
    case epic = "Epic"
    case legendary = "Legendary"
    
    public var color: String {
        switch self {
        case .common: return "gray"
        case .uncommon: return "green"
        case .rare: return "blue"
        case .epic: return "purple"
        case .legendary: return "gold"
        }
    }
}

/// Rarity calculation result
public struct NFTRarityResult: Codable {
    public let totalScore: Double // 0-100
    public let rank: NFTRarityRank
    public let traitRarities: [NFTTraitRarity]
    public let missingTraits: [String] // Traits not present in this NFT
    
    /// Percentile in collection (if available)
    public var percentile: Double? = nil
    
    /// Estimated rank in collection (if available)
    public var estimatedRank: Int? = nil
}

/// Rarity info for a single trait
public struct NFTTraitRarity: Codable, Identifiable {
    public var id: String { "\(traitType):\(value)" }
    public let traitType: String
    public let value: String
    public let rarityPercent: Double // Percentage of collection with this trait
    public let count: Int // Number of NFTs with this trait
    public let totalInCategory: Int // Total NFTs with any value for this trait type
    
    /// Whether this is considered a rare trait (<5%)
    public var isRare: Bool {
        rarityPercent < 5.0
    }
}
