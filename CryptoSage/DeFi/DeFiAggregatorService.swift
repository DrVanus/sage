//
//  DeFiAggregatorService.swift
//  CryptoSage
//
//  Unified DeFi aggregator service using DeBank API.
//  Provides access to 1000+ DeFi protocols across 100+ chains.
//

import Foundation
import Combine

// MARK: - Aggregator Provider

/// Supported DeFi aggregator providers
public enum DeFiAggregatorProvider: String, CaseIterable {
    case debank = "debank"
    case zapper = "zapper"
    
    var displayName: String {
        switch self {
        case .debank: return "DeBank"
        case .zapper: return "Zapper"
        }
    }
    
    var baseURL: String {
        switch self {
        case .debank: return "https://pro-openapi.debank.com/v1"
        case .zapper: return "https://api.zapper.xyz/v2"
        }
    }
}

// MARK: - DeBank Response Models

/// DeBank chain info
public struct DeBankChain: Codable, Identifiable {
    public let id: String
    public let communityId: Int?
    public let name: String
    public let logoUrl: String?
    public let nativeTokenId: String?
    public let wrappedTokenId: String?
    public let isSupport: Bool?
    
    enum CodingKeys: String, CodingKey {
        case id, name
        case communityId = "community_id"
        case logoUrl = "logo_url"
        case nativeTokenId = "native_token_id"
        case wrappedTokenId = "wrapped_token_id"
        case isSupport = "is_support"
    }
}

/// DeBank token balance
public struct DeBankToken: Codable, Identifiable {
    public let id: String
    public let chain: String
    public let name: String
    public let symbol: String
    public let displaySymbol: String?
    public let optimizedSymbol: String?
    public let decimals: Int
    public let logoUrl: String?
    public let protocolId: String?
    public let price: Double?
    public let isVerified: Bool?
    public let isCore: Bool?
    public let isWallet: Bool?
    public let amount: Double
    public let rawAmount: String?
    
    enum CodingKeys: String, CodingKey {
        case id, chain, name, symbol, decimals, price, amount
        case displaySymbol = "display_symbol"
        case optimizedSymbol = "optimized_symbol"
        case logoUrl = "logo_url"
        case protocolId = "protocol_id"
        case isVerified = "is_verified"
        case isCore = "is_core"
        case isWallet = "is_wallet"
        case rawAmount = "raw_amount"
    }
    
    /// USD value of the token balance
    public var valueUSD: Double {
        (price ?? 0) * amount
    }
}

/// DeBank protocol info
public struct DeBankProtocol: Codable, Identifiable {
    public let id: String
    public let chain: String
    public let name: String
    public let siteUrl: String?
    public let logoUrl: String?
    public let hasSupported_portfolio: Bool?
    public let tvl: Double?
    
    enum CodingKeys: String, CodingKey {
        case id, chain, name, tvl
        case siteUrl = "site_url"
        case logoUrl = "logo_url"
        case hasSupported_portfolio = "has_supported_portfolio"
    }
}

/// DeBank portfolio item (generic position)
public struct DeBankPortfolioItem: Codable {
    public let stats: DeBankStats?
    public let updateAt: Int?
    public let name: String?
    public let detailTypes: [String]?
    public let detail: DeBankDetail?
    
    enum CodingKeys: String, CodingKey {
        case stats, name, detail
        case updateAt = "update_at"
        case detailTypes = "detail_types"
    }
}

public struct DeBankStats: Codable {
    public let assetUsdValue: Double?
    public let debtUsdValue: Double?
    public let netUsdValue: Double?
    
    enum CodingKeys: String, CodingKey {
        case assetUsdValue = "asset_usd_value"
        case debtUsdValue = "debt_usd_value"
        case netUsdValue = "net_usd_value"
    }
}

public struct DeBankDetail: Codable {
    public let supplyTokenList: [DeBankToken]?
    public let borrowTokenList: [DeBankToken]?
    public let rewardTokenList: [DeBankToken]?
    public let tokenList: [DeBankToken]?
    public let healthRate: Double?
    public let description: String?
    
    enum CodingKeys: String, CodingKey {
        case supplyTokenList = "supply_token_list"
        case borrowTokenList = "borrow_token_list"
        case rewardTokenList = "reward_token_list"
        case tokenList = "token_list"
        case healthRate = "health_rate"
        case description
    }
}

/// DeBank complex protocol response
public struct DeBankComplexProtocol: Codable, Identifiable {
    public let id: String
    public let chain: String
    public let name: String
    public let siteUrl: String?
    public let logoUrl: String?
    public let portfolioItemList: [DeBankPortfolioItem]?
    
    enum CodingKeys: String, CodingKey {
        case id, chain, name
        case siteUrl = "site_url"
        case logoUrl = "logo_url"
        case portfolioItemList = "portfolio_item_list"
    }
}

/// DeBank NFT
public struct DeBankNFT: Codable, Identifiable {
    public var id: String { "\(chain):\(contractId):\(innerId)" }
    public let chain: String
    public let contractId: String
    public let innerId: String
    public let name: String?
    public let description: String?
    public let contentType: String?
    public let content: String?
    public let thumbnailUrl: String?
    public let detailUrl: String?
    public let contractName: String?
    public let collectionId: String?
    public let attributes: [DeBankNFTAttribute]?
    public let payToken: DeBankToken?
    public let usdPrice: Double?
    
    enum CodingKeys: String, CodingKey {
        case chain, name, description, content, attributes
        case contractId = "contract_id"
        case innerId = "inner_id"
        case contentType = "content_type"
        case thumbnailUrl = "thumbnail_url"
        case detailUrl = "detail_url"
        case contractName = "contract_name"
        case collectionId = "collection_id"
        case payToken = "pay_token"
        case usdPrice = "usd_price"
    }
}

public struct DeBankNFTAttribute: Codable {
    public let traitType: String?
    public let value: String?
    
    enum CodingKeys: String, CodingKey {
        case traitType = "trait_type"
        case value
    }
}

/// DeBank user total balance response
public struct DeBankTotalBalance: Codable {
    public let totalUsdValue: Double
    public let chainList: [DeBankChainBalance]?
    
    enum CodingKeys: String, CodingKey {
        case totalUsdValue = "total_usd_value"
        case chainList = "chain_list"
    }
}

public struct DeBankChainBalance: Codable, Identifiable {
    public var id: String { chainId }
    public let chainId: String
    public let usdValue: Double
    
    enum CodingKeys: String, CodingKey {
        case chainId = "id"
        case usdValue = "usd_value"
    }
}

// MARK: - Aggregator Error

public enum DeFiAggregatorError: LocalizedError {
    case noAPIKey
    case invalidAddress
    case networkError(Error)
    case decodingError(Error)
    case rateLimited
    case serverError(Int)
    case providerUnavailable
    
    public var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "DeFi aggregator API key not configured"
        case .invalidAddress:
            return "Invalid wallet address"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        case .rateLimited:
            return "Rate limited. Please try again later."
        case .serverError(let code):
            return "Server error: \(code)"
        case .providerUnavailable:
            return "DeFi aggregator service unavailable"
        }
    }
}

// MARK: - DeFi Aggregator Service

/// Unified service for fetching DeFi positions across all protocols and chains
@MainActor
public final class DeFiAggregatorService: ObservableObject {
    public static let shared = DeFiAggregatorService()
    
    // MARK: - Published Properties
    
    @Published public private(set) var isLoading = false
    @Published public private(set) var lastError: DeFiAggregatorError?
    @Published public private(set) var provider: DeFiAggregatorProvider = .debank
    @Published public private(set) var supportedChains: [DeBankChain] = []
    @Published public private(set) var supportedProtocols: [DeBankProtocol] = []
    
    // MARK: - Private Properties
    
    private let session: URLSession
    private let keychainService = "CryptoSage.APIKeys"
    private let debankKeyAccount = "debank_api_key"
    private let zapperKeyAccount = "zapper_api_key"
    
    // Cache
    private var tokenCache: [String: [DeBankToken]] = [:]
    private var protocolCache: [String: [DeBankComplexProtocol]] = [:]
    private var nftCache: [String: [DeBankNFT]] = [:]
    private var cacheTimestamps: [String: Date] = [:]
    private let cacheTTL: TimeInterval = 300 // 5 minutes
    
    // MARK: - Initialization
    
    private init() {
        // SECURITY: Ephemeral session prevents disk caching of aggregated DeFi portfolio data
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - API Key Management
    
    /// Get the current API key for the selected provider
    public var apiKey: String? {
        let account = provider == .debank ? debankKeyAccount : zapperKeyAccount
        return try? KeychainHelper.shared.read(service: keychainService, account: account)
    }
    
    /// Check if API key is configured
    public var hasAPIKey: Bool {
        guard let key = apiKey else { return false }
        return !key.isEmpty
    }
    
    /// Save API key for the selected provider
    public func setAPIKey(_ key: String, for provider: DeFiAggregatorProvider) throws {
        let account = provider == .debank ? debankKeyAccount : zapperKeyAccount
        try KeychainHelper.shared.save(key, service: keychainService, account: account)
    }
    
    /// Remove API key
    public func removeAPIKey(for provider: DeFiAggregatorProvider) {
        let account = provider == .debank ? debankKeyAccount : zapperKeyAccount
        try? KeychainHelper.shared.delete(service: keychainService, account: account)
    }
    
    /// Switch provider
    public func setProvider(_ provider: DeFiAggregatorProvider) {
        self.provider = provider
        clearCache()
    }
    
    // MARK: - Public API
    
    /// Fetch all supported chains from DeBank
    public func fetchSupportedChains() async throws -> [DeBankChain] {
        guard hasAPIKey else { throw DeFiAggregatorError.noAPIKey }
        
        let urlString = "\(provider.baseURL)/chain/list"
        let data = try await makeRequest(urlString: urlString)
        
        let chains = try JSONDecoder().decode([DeBankChain].self, from: data)
        supportedChains = chains.filter { $0.isSupport == true }
        
        return supportedChains
    }
    
    /// Fetch user's total balance across all chains
    public func fetchTotalBalance(address: String) async throws -> DeBankTotalBalance {
        guard hasAPIKey else { throw DeFiAggregatorError.noAPIKey }
        guard isValidAddress(address) else { throw DeFiAggregatorError.invalidAddress }
        
        let urlString = "\(provider.baseURL)/user/total_balance?id=\(address.lowercased())"
        let data = try await makeRequest(urlString: urlString)
        
        return try JSONDecoder().decode(DeBankTotalBalance.self, from: data)
    }
    
    /// Fetch all token balances for an address
    public func fetchTokenBalances(address: String, chainId: String? = nil) async throws -> [DeBankToken] {
        guard hasAPIKey else { throw DeFiAggregatorError.noAPIKey }
        guard isValidAddress(address) else { throw DeFiAggregatorError.invalidAddress }
        
        let cacheKey = "tokens:\(address.lowercased()):\(chainId ?? "all")"
        if let cached = tokenCache[cacheKey], isCacheValid(for: cacheKey) {
            return cached
        }
        
        var urlString = "\(provider.baseURL)/user/all_token_list?id=\(address.lowercased())"
        if let chain = chainId {
            urlString = "\(provider.baseURL)/user/token_list?id=\(address.lowercased())&chain_id=\(chain)"
        }
        
        let data = try await makeRequest(urlString: urlString)
        let tokens = try JSONDecoder().decode([DeBankToken].self, from: data)
        
        // Cache results
        tokenCache[cacheKey] = tokens
        cacheTimestamps[cacheKey] = Date()
        
        return tokens
    }
    
    /// Fetch all DeFi protocol positions for an address
    public func fetchAllProtocolPositions(address: String) async throws -> [DeBankComplexProtocol] {
        guard hasAPIKey else { throw DeFiAggregatorError.noAPIKey }
        guard isValidAddress(address) else { throw DeFiAggregatorError.invalidAddress }
        
        let cacheKey = "protocols:\(address.lowercased())"
        if let cached = protocolCache[cacheKey], isCacheValid(for: cacheKey) {
            return cached
        }
        
        let urlString = "\(provider.baseURL)/user/all_complex_protocol_list?id=\(address.lowercased())"
        let data = try await makeRequest(urlString: urlString)
        let protocols = try JSONDecoder().decode([DeBankComplexProtocol].self, from: data)
        
        // Cache results
        protocolCache[cacheKey] = protocols
        cacheTimestamps[cacheKey] = Date()
        
        return protocols
    }
    
    /// Fetch protocol positions on a specific chain
    public func fetchChainProtocolPositions(address: String, chainId: String) async throws -> [DeBankComplexProtocol] {
        guard hasAPIKey else { throw DeFiAggregatorError.noAPIKey }
        guard isValidAddress(address) else { throw DeFiAggregatorError.invalidAddress }
        
        let urlString = "\(provider.baseURL)/user/complex_protocol_list?id=\(address.lowercased())&chain_id=\(chainId)"
        let data = try await makeRequest(urlString: urlString)
        
        return try JSONDecoder().decode([DeBankComplexProtocol].self, from: data)
    }
    
    /// Fetch all NFTs for an address
    public func fetchNFTs(address: String) async throws -> [DeBankNFT] {
        guard hasAPIKey else { throw DeFiAggregatorError.noAPIKey }
        guard isValidAddress(address) else { throw DeFiAggregatorError.invalidAddress }
        
        let cacheKey = "nfts:\(address.lowercased())"
        if let cached = nftCache[cacheKey], isCacheValid(for: cacheKey) {
            return cached
        }
        
        let urlString = "\(provider.baseURL)/user/all_nft_list?id=\(address.lowercased())"
        let data = try await makeRequest(urlString: urlString)
        let nfts = try JSONDecoder().decode([DeBankNFT].self, from: data)
        
        // Cache results
        nftCache[cacheKey] = nfts
        cacheTimestamps[cacheKey] = Date()
        
        return nfts
    }
    
    /// Fetch NFTs on a specific chain
    public func fetchChainNFTs(address: String, chainId: String) async throws -> [DeBankNFT] {
        guard hasAPIKey else { throw DeFiAggregatorError.noAPIKey }
        guard isValidAddress(address) else { throw DeFiAggregatorError.invalidAddress }
        
        let urlString = "\(provider.baseURL)/user/nft_list?id=\(address.lowercased())&chain_id=\(chainId)"
        let data = try await makeRequest(urlString: urlString)
        
        return try JSONDecoder().decode([DeBankNFT].self, from: data)
    }
    
    /// Fetch all supported protocols (global list)
    public func fetchSupportedProtocols(chainId: String? = nil) async throws -> [DeBankProtocol] {
        guard hasAPIKey else { throw DeFiAggregatorError.noAPIKey }
        
        var urlString = "\(provider.baseURL)/protocol/list"
        if let chain = chainId {
            urlString += "?chain_id=\(chain)"
        }
        
        let data = try await makeRequest(urlString: urlString)
        let protocols = try JSONDecoder().decode([DeBankProtocol].self, from: data)
        
        if chainId == nil {
            supportedProtocols = protocols
        }
        
        return protocols
    }
    
    // MARK: - Unified Portfolio Fetch
    
    /// Fetch complete DeFi portfolio summary for an address
    public func fetchPortfolioSummary(address: String) async throws -> DeFiPortfolioSummary {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        
        guard hasAPIKey else {
            lastError = .noAPIKey
            throw DeFiAggregatorError.noAPIKey
        }
        
        do {
            // Fetch all data in parallel
            async let tokensTask = fetchTokenBalances(address: address)
            async let protocolsTask = fetchAllProtocolPositions(address: address)
            
            let (_, protocols) = try await (tokensTask, protocolsTask)
            
            // Convert to DeFiPosition format
            var positions: [DeFiPosition] = []
            
            for protocol_ in protocols {
                for item in protocol_.portfolioItemList ?? [] {
                    let position = convertToPosition(
                        protocol_: protocol_,
                        item: item
                    )
                    positions.append(position)
                }
            }
            
            // Build summary
            let summary = DeFiPortfolioSummary.build(from: positions)
            
            return summary
            
        } catch let error as DeFiAggregatorError {
            lastError = error
            throw error
        } catch {
            let aggregatorError = DeFiAggregatorError.networkError(error)
            lastError = aggregatorError
            throw aggregatorError
        }
    }
    
    // MARK: - Private Helpers
    
    private func makeRequest(urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw DeFiAggregatorError.providerUnavailable
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // Add API key header
        if let key = apiKey {
            if provider == .debank {
                request.setValue(key, forHTTPHeaderField: "AccessKey")
            } else {
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            }
        }
        
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw DeFiAggregatorError.providerUnavailable
            }
            
            switch httpResponse.statusCode {
            case 200..<300:
                return data
            case 401:
                throw DeFiAggregatorError.noAPIKey
            case 429:
                throw DeFiAggregatorError.rateLimited
            default:
                throw DeFiAggregatorError.serverError(httpResponse.statusCode)
            }
        } catch let error as DeFiAggregatorError {
            throw error
        } catch {
            throw DeFiAggregatorError.networkError(error)
        }
    }
    
    private func isValidAddress(_ address: String) -> Bool {
        // EVM address
        if address.hasPrefix("0x") && address.count == 42 {
            return true
        }
        // Solana address (Base58, 32-44 chars)
        if address.count >= 32 && address.count <= 44 && !address.hasPrefix("0x") {
            return true
        }
        return false
    }
    
    private func isCacheValid(for key: String) -> Bool {
        guard let timestamp = cacheTimestamps[key] else { return false }
        return Date().timeIntervalSince(timestamp) < cacheTTL
    }
    
    private func clearCache() {
        tokenCache.removeAll()
        protocolCache.removeAll()
        nftCache.removeAll()
        cacheTimestamps.removeAll()
    }
    
    /// Convert DeBank response to internal DeFiPosition format
    private func convertToPosition(protocol_: DeBankComplexProtocol, item: DeBankPortfolioItem) -> DeFiPosition {
        // Determine position type
        let positionType: DeFiPositionType
        let name = item.name?.lowercased() ?? ""
        
        if name.contains("lending") || name.contains("supplied") || name.contains("deposit") {
            positionType = .lending
        } else if name.contains("borrow") || name.contains("debt") {
            positionType = .borrowing
        } else if name.contains("staking") || name.contains("staked") {
            positionType = .staking
        } else if name.contains("farming") || name.contains("yield") {
            positionType = .farming
        } else if name.contains("liquidity") || name.contains("lp") || name.contains("pool") {
            positionType = .liquidity
        } else if name.contains("vault") {
            positionType = .vault
        } else if name.contains("reward") || name.contains("claimable") {
            positionType = .claimable
        } else {
            positionType = .liquidity // Default
        }
        
        // Convert chain
        let chain = chainFromDeBankId(protocol_.chain)
        
        // Build tokens list
        var tokens: [PositionToken] = []
        
        if let supplyTokens = item.detail?.supplyTokenList {
            for t in supplyTokens {
                tokens.append(PositionToken(
                    symbol: t.symbol,
                    name: t.name,
                    contractAddress: t.id,
                    amount: t.amount,
                    valueUSD: t.valueUSD,
                    logoURL: t.logoUrl
                ))
            }
        }
        
        if let tokenList = item.detail?.tokenList {
            for t in tokenList {
                tokens.append(PositionToken(
                    symbol: t.symbol,
                    name: t.name,
                    contractAddress: t.id,
                    amount: t.amount,
                    valueUSD: t.valueUSD,
                    logoURL: t.logoUrl
                ))
            }
        }
        
        if let borrowTokens = item.detail?.borrowTokenList {
            for t in borrowTokens {
                tokens.append(PositionToken(
                    symbol: t.symbol,
                    name: t.name,
                    contractAddress: t.id,
                    amount: t.amount,
                    valueUSD: t.valueUSD,
                    logoURL: t.logoUrl,
                    isDebt: true
                ))
            }
        }
        
        // Calculate rewards
        var rewardsUSD: Double? = nil
        if let rewardTokens = item.detail?.rewardTokenList {
            rewardsUSD = rewardTokens.reduce(0) { $0 + $1.valueUSD }
        }
        
        // Create protocol info
        let defiProtocol = DeFiProtocol(
            id: protocol_.id,
            name: protocol_.name,
            chain: chain,
            category: categoryFromType(positionType),
            logoURL: protocol_.logoUrl,
            websiteURL: protocol_.siteUrl,
            tvl: nil
        )
        
        return DeFiPosition(
            protocol_: defiProtocol,
            type: positionType,
            chain: chain,
            tokens: tokens,
            valueUSD: item.stats?.assetUsdValue ?? 0,
            healthFactor: item.detail?.healthRate,
            rewardsUSD: rewardsUSD
        )
    }
    
    private func chainFromDeBankId(_ id: String) -> Chain {
        switch id.lowercased() {
        case "eth": return .ethereum
        case "bsc": return .bsc
        case "matic", "polygon": return .polygon
        case "arb": return .arbitrum
        case "op": return .optimism
        case "base": return .base
        case "avax": return .avalanche
        case "ftm": return .fantom
        case "sol": return .solana
        case "zksync", "era": return .zksync
        default: return .ethereum
        }
    }
    
    private func categoryFromType(_ type: DeFiPositionType) -> DeFiProtocol.DeFiCategory {
        switch type {
        case .liquidity: return .dex
        case .lending, .borrowing: return .lending
        case .staking: return .staking
        case .farming, .vault: return .yield
        default: return .other
        }
    }
}

// MARK: - Convenience Extensions

extension DeFiAggregatorService {
    
    /// Check if DeBank free API is available (limited features, no API key needed)
    public var canUseFreeAPI: Bool {
        // DeBank Cloud API has some free endpoints
        return true
    }
    
    /// Get total portfolio value for an address
    public func getTotalValue(address: String) async throws -> Double {
        let balance = try await fetchTotalBalance(address: address)
        return balance.totalUsdValue
    }
    
    /// Get chain breakdown for an address
    public func getChainBreakdown(address: String) async throws -> [String: Double] {
        let balance = try await fetchTotalBalance(address: address)
        var breakdown: [String: Double] = [:]
        
        for chainBalance in balance.chainList ?? [] {
            breakdown[chainBalance.chainId] = chainBalance.usdValue
        }
        
        return breakdown
    }
}
