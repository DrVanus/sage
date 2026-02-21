//
//  DeFiViewModels.swift
//  CryptoSage
//
//  ViewModels for DeFi position tracking, NFT collections, and multi-chain portfolios.
//

import SwiftUI
import Combine

// MARK: - Multi-Chain Portfolio ViewModel

@MainActor
class MultiChainPortfolioViewModel: ObservableObject {
    static let shared = MultiChainPortfolioViewModel()
    
    @Published var connectedWallets: [ConnectedChainWallet] = []
    @Published var isLoading = false
    @Published var error: Error?
    
    private let chainRegistry = ChainRegistry.shared
    private let storageKey = "MultiChainWallets"
    
    var totalValue: Double {
        connectedWallets.compactMap(\.totalValueUSD).reduce(0, +)
    }
    
    init() {
        loadWallets()
    }
    
    // MARK: - Wallet Management
    
    func connectWallet(address: String, chainId: String, name: String?) async {
        // Check if wallet already connected
        if connectedWallets.contains(where: { $0.address.lowercased() == address.lowercased() && $0.chainId == chainId }) {
            return
        }
        
        let wallet = ConnectedChainWallet(
            id: UUID().uuidString,
            address: address,
            chainId: chainId,
            name: name,
            tokenBalances: [],
            nftCount: nil,
            totalValueUSD: nil,
            lastUpdated: Date()
        )
        
        connectedWallets.append(wallet)
        saveWallets()
        
        // Fetch balances in background
        await fetchBalances(for: wallet.id)
    }
    
    func disconnectWallet(id: String) {
        connectedWallets.removeAll { $0.id == id }
        saveWallets()
    }
    
    // MARK: - Data Fetching
    
    func fetchBalances(for walletId: String) async {
        guard let index = connectedWallets.firstIndex(where: { $0.id == walletId }) else { return }
        let wallet = connectedWallets[index]
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Get chain from chainId string
            guard let chain = Chain(rawValue: wallet.chainId) else {
                throw DeFiError.unsupportedChain
            }
            
            // Fetch token balances using Chain enum
            let tokenService = DeFiTokenService.shared
            let portfolio = try await tokenService.fetchTokenBalances(
                address: wallet.address,
                chains: [chain]
            )
            
            // Get token balances from portfolio
            let balances = portfolio.tokenBalances
            
            // Calculate total value
            let totalValue = portfolio.totalValueUSD
            
            // Update wallet
            connectedWallets[index].tokenBalances = balances
            connectedWallets[index].totalValueUSD = totalValue
            connectedWallets[index].lastUpdated = Date()
            
            saveWallets()
        } catch {
            self.error = error
        }
    }
    
    func refreshAllWallets() async {
        for wallet in connectedWallets {
            await fetchBalances(for: wallet.id)
        }
    }
    
    // MARK: - Persistence
    
    private func saveWallets() {
        if let data = try? JSONEncoder().encode(connectedWallets) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    private func loadWallets() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let wallets = try? JSONDecoder().decode([ConnectedChainWallet].self, from: data) {
            connectedWallets = wallets
        }
    }
}

// MARK: - Connected Chain Wallet Model

struct ConnectedChainWallet: Codable, Identifiable {
    let id: String
    let address: String
    let chainId: String
    var name: String?
    var tokenBalances: [TokenBalance]
    var nftCount: Int?
    var totalValueUSD: Double?
    var lastUpdated: Date
}

// MARK: - DeFi Positions ViewModel

@MainActor
class DeFiPositionsViewModel: ObservableObject {
    static let shared = DeFiPositionsViewModel()
    
    @Published var positions: [DeFiPosition] = []
    @Published var isLoading = false
    @Published var error: Error?
    
    var totalValue: Double {
        positions.map(\.valueUSD).reduce(0, +)
    }
    
    private let protocolService = DeFiProtocolService.shared
    private let storageKey = "DeFiPositions"
    
    init() {
        loadPositions()
    }
    
    // MARK: - Position Fetching
    
    func fetchPositions(for address: String, chain: String) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            guard let chainEnum = Chain(rawValue: chain) else {
                throw NFTFetchError.unsupportedChain
            }
            
            let summary = try await protocolService.fetchAllPositions(
                address: address,
                chains: [chainEnum]
            )
            
            // Get positions from summary
            let newPositions = summary.positions
            
            // Merge with existing (keep positions from other chains)
            let existingOther = positions.filter { $0.chain != chainEnum }
            positions = existingOther + newPositions
            
            savePositions()
        } catch {
            self.error = error
        }
    }
    
    // MARK: - Persistence
    
    private func savePositions() {
        if let data = try? JSONEncoder().encode(positions) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    private func loadPositions() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([DeFiPosition].self, from: data) {
            positions = saved
        }
    }
}

// MARK: - NFT Collection ViewModel

@MainActor
class NFTCollectionViewModel: ObservableObject {
    static let shared = NFTCollectionViewModel()
    
    @Published var nfts: [NFT] = []
    @Published var collectionGroups: [NFTCollectionGroup] = []
    @Published var isLoading = false
    @Published var error: Error?
    
    var totalEstimatedValue: Double {
        nfts.compactMap(\.estimatedValueUSD).reduce(0, +)
    }
    
    private let nftService = NFTService.shared
    private let storageKey = "NFTCollectionData"
    
    init() {
        loadNFTs()
    }
    
    // MARK: - NFT Fetching
    
    func fetchNFTs(for address: String, chain: String) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            guard let chainEnum = Chain(rawValue: chain) else {
                throw NFTFetchError.unsupportedChain
            }
            
            let portfolio = try await nftService.fetchNFTs(address: address, chains: [chainEnum])
            
            // Merge - replace existing from same address/chain
            let existingOther = nfts.filter { $0.ownerAddress != address }
            nfts = existingOther + portfolio.nfts
            
            // Group into collections
            updateCollections()
            
            saveNFTs()
        } catch {
            self.error = error
        }
    }
    
    private func updateCollections() {
        let grouped = Dictionary(grouping: nfts) { $0.collection?.id ?? $0.contractAddress }
        collectionGroups = grouped.map { (address, items) in
            NFTCollectionGroup(
                contractAddress: address,
                name: items.first?.collection?.name ?? "Unknown",
                imageURL: items.first?.collection?.imageURL.flatMap { URL(string: $0) },
                nfts: items,
                floorPrice: items.first?.collection?.floorPrice,
                totalValue: items.compactMap(\.estimatedValueUSD).reduce(0, +)
            )
        }
    }
    
    // MARK: - Persistence
    
    private func saveNFTs() {
        if let data = try? JSONEncoder().encode(nfts) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    private func loadNFTs() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([NFT].self, from: data) {
            nfts = saved
            updateCollections()
        }
    }
}

// MARK: - NFT Collection Group (for UI grouping)

struct NFTCollectionGroup: Identifiable {
    let id = UUID()
    let contractAddress: String
    let name: String
    let imageURL: URL?
    let nfts: [NFT]
    let floorPrice: Double?
    let totalValue: Double
}

// MARK: - NFT Fetch Error

enum NFTFetchError: LocalizedError {
    case unsupportedChain
    case networkError
    case invalidResponse
    case rateLimited
    
    var errorDescription: String? {
        switch self {
        case .unsupportedChain: return "This blockchain is not supported"
        case .networkError: return "Network error occurred"
        case .invalidResponse: return "Invalid response from server"
        case .rateLimited: return "Too many requests - please try again later"
        }
    }
}

// MARK: - Demo Data Provider

/// Provides sample data for demo mode display
enum DemoDataProvider {
    
    // MARK: - Demo Wallets
    
    static var demoWallets: [ConnectedChainWallet] {
        [
            // Ethereum Main Wallet
            ConnectedChainWallet(
                id: "demo-eth-wallet",
                address: "0x742d35Cc6634C0532925a3b844Bc454e4438f44e",
                chainId: "ethereum",
                name: "Main Ethereum Wallet",
                tokenBalances: [
                    TokenBalance(
                        id: "demo-eth",
                        contractAddress: "0x0000000000000000000000000000000000000000",
                        symbol: "ETH",
                        name: "Ethereum",
                        decimals: 18,
                        balance: 2.5,
                        rawBalance: "2500000000000000000",
                        chain: .ethereum,
                        logoURL: nil,
                        priceUSD: 3200.0,
                        valueUSD: 8000.0,
                        priceChange24h: 2.5,
                        isSpam: false,
                        isVerified: true
                    ),
                    TokenBalance(
                        id: "demo-usdc",
                        contractAddress: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
                        symbol: "USDC",
                        name: "USD Coin",
                        decimals: 6,
                        balance: 1250.0,
                        rawBalance: "1250000000",
                        chain: .ethereum,
                        logoURL: nil,
                        priceUSD: 1.0,
                        valueUSD: 1250.0,
                        priceChange24h: 0.01,
                        isSpam: false,
                        isVerified: true
                    ),
                    TokenBalance(
                        id: "demo-link",
                        contractAddress: "0x514910771AF9Ca656af840dff83E8264EcF986CA",
                        symbol: "LINK",
                        name: "Chainlink",
                        decimals: 18,
                        balance: 75.0,
                        rawBalance: "75000000000000000000",
                        chain: .ethereum,
                        logoURL: nil,
                        priceUSD: 14.50,
                        valueUSD: 1087.50,
                        priceChange24h: -1.2,
                        isSpam: false,
                        isVerified: true
                    )
                ],
                nftCount: 3,
                totalValueUSD: 10337.50,
                lastUpdated: Date()
            ),
            
            // Polygon Wallet
            ConnectedChainWallet(
                id: "demo-polygon-wallet",
                address: "0x8B3392483BA26D65E331Db86D4F430E9B3814E5E",
                chainId: "polygon",
                name: "Polygon DeFi Wallet",
                tokenBalances: [
                    TokenBalance(
                        id: "demo-matic",
                        contractAddress: "0x0000000000000000000000000000000000001010",
                        symbol: "MATIC",
                        name: "Polygon",
                        decimals: 18,
                        balance: 850.0,
                        rawBalance: "850000000000000000000",
                        chain: .polygon,
                        logoURL: nil,
                        priceUSD: 0.85,
                        valueUSD: 722.50,
                        priceChange24h: 3.2,
                        isSpam: false,
                        isVerified: true
                    ),
                    TokenBalance(
                        id: "demo-usdt-poly",
                        contractAddress: "0xc2132D05D31c914a87C6611C10748AEb04B58e8F",
                        symbol: "USDT",
                        name: "Tether USD",
                        decimals: 6,
                        balance: 500.0,
                        rawBalance: "500000000",
                        chain: .polygon,
                        logoURL: nil,
                        priceUSD: 1.0,
                        valueUSD: 500.0,
                        priceChange24h: 0.0,
                        isSpam: false,
                        isVerified: true
                    )
                ],
                nftCount: 0,
                totalValueUSD: 1222.50,
                lastUpdated: Date()
            ),
            
            // Solana Wallet
            ConnectedChainWallet(
                id: "demo-solana-wallet",
                address: "9WzDXwBbmPdCBoccJLLpXKNFsLzFTRckBv1CiEqfnLab",
                chainId: "solana",
                name: "Solana Wallet",
                tokenBalances: [
                    TokenBalance(
                        id: "demo-sol",
                        contractAddress: "So11111111111111111111111111111111111111112",
                        symbol: "SOL",
                        name: "Solana",
                        decimals: 9,
                        balance: 25.0,
                        rawBalance: "25000000000",
                        chain: .solana,
                        logoURL: nil,
                        priceUSD: 145.0,
                        valueUSD: 3625.0,
                        priceChange24h: 4.5,
                        isSpam: false,
                        isVerified: true
                    ),
                    TokenBalance(
                        id: "demo-ray",
                        contractAddress: "4k3Dyjzvzp8eMZWUXbBCjEvwSkkk59S5iCNLY3QrkX6R",
                        symbol: "RAY",
                        name: "Raydium",
                        decimals: 6,
                        balance: 120.0,
                        rawBalance: "120000000",
                        chain: .solana,
                        logoURL: nil,
                        priceUSD: 1.85,
                        valueUSD: 222.0,
                        priceChange24h: 1.8,
                        isSpam: false,
                        isVerified: true
                    )
                ],
                nftCount: 2,
                totalValueUSD: 3847.0,
                lastUpdated: Date()
            )
        ]
    }
    
    // MARK: - Demo NFTs
    
    static var demoNFTs: [NFT] {
        // Using OpenSea's CDN URLs which are faster and more reliable than IPFS
        let apeCollection = NFTCollection(
            id: "demo-bored-apes",
            contractAddress: "0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D",
            chain: .ethereum,
            name: "Bored Ape Yacht Club",
            description: "BAYC is a collection of 10,000 unique Bored Ape NFTs",
            imageURL: "https://i.seadn.io/gae/Ju9CkWtV-1Okvf45wo8UctR-M9He2PjILP0oOvxE89AyiPPGtrR3gysu1Zgy0hjd2xKIgjJJtWIc0ybj4Vd7wv8t3pxDGHoJBzDB?w=500&auto=format",
            floorPrice: 28.5,
            floorPriceCurrency: "ETH",
            totalVolume: 850000.0,
            isVerified: true
        )
        
        let artBlocksCollection = NFTCollection(
            id: "demo-art-blocks",
            contractAddress: "0xa7d8d9ef8D8Ce8992Df33D8b8CF4Aebabd5bD270",
            chain: .ethereum,
            name: "Art Blocks Curated",
            description: "Generative art on Ethereum",
            imageURL: "https://media.artblocks.io/78000000.png",
            floorPrice: 0.85,
            floorPriceCurrency: "ETH",
            totalVolume: 125000.0,
            isVerified: true
        )
        
        let gamingCollection = NFTCollection(
            id: "demo-gaming",
            contractAddress: "0x7Bd29408f11D2bFC23c34f18275bBf23bB716Bc7",
            chain: .ethereum,
            name: "Loot (for Adventurers)",
            description: "Loot is randomized adventurer gear",
            imageURL: "https://i.seadn.io/gae/vw-gp8yUYkQsxQN5xbHrWEhY7rQWQZhIjgcRTxRMgF9ucL--M8PXnxXq2hfTFvv3JLHhkBgCWZ5JedJSdTb85pVTPOqlRbKAQYv1?w=500&auto=format",
            floorPrice: 1.2,
            floorPriceCurrency: "ETH",
            totalVolume: 45000.0,
            isVerified: true
        )
        
        return [
            NFT(
                id: "demo-nft-1",
                contractAddress: "0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D",
                tokenId: "3749",
                chain: .ethereum,
                name: "Bored Ape #3749",
                description: "A unique Bored Ape with rare traits",
                imageURL: "https://i.seadn.io/gae/L1M7U0Vf4LErrYNHbLOsV6yVoKnBuJPVUfBA9HdahOVHvcMMKWOa1dZmSOP5t_ELfi5tDpDrNmPIqjwE0cIdMGqqehB3CWZTjno?w=500&auto=format",
                collection: apeCollection,
                estimatedValueUSD: 91200.0,
                tokenStandard: .erc721,
                ownerAddress: "0x742d35Cc6634C0532925a3b844Bc454e4438f44e"
            ),
            NFT(
                id: "demo-nft-2",
                contractAddress: "0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D",
                tokenId: "8421",
                chain: .ethereum,
                name: "Bored Ape #8421",
                description: "A Bored Ape with golden fur",
                imageURL: "https://i.seadn.io/gae/H-eyNE1MwL5ohL-tCfn_Xa1Sl9M9B4612tLYeUlQubzt4ewAIsHhsjp1BE4cQxVikXXcITBqH2I6nKYMa3pnNMcNhE7mMZ29LoGS-A?w=500&auto=format",
                collection: apeCollection,
                estimatedValueUSD: 95800.0,
                tokenStandard: .erc721,
                ownerAddress: "0x742d35Cc6634C0532925a3b844Bc454e4438f44e"
            ),
            NFT(
                id: "demo-nft-3",
                contractAddress: "0xa7d8d9ef8D8Ce8992Df33D8b8CF4Aebabd5bD270",
                tokenId: "78000154",
                chain: .ethereum,
                name: "Fidenza #154",
                description: "Fidenza by Tyler Hobbs",
                imageURL: "https://media.artblocks.io/78000154.png",
                collection: artBlocksCollection,
                estimatedValueUSD: 12500.0,
                tokenStandard: .erc721,
                ownerAddress: "0x742d35Cc6634C0532925a3b844Bc454e4438f44e"
            ),
            NFT(
                id: "demo-nft-4",
                contractAddress: "0xa7d8d9ef8D8Ce8992Df33D8b8CF4Aebabd5bD270",
                tokenId: "78000892",
                chain: .ethereum,
                name: "Fidenza #892",
                description: "Fidenza by Tyler Hobbs",
                imageURL: "https://media.artblocks.io/78000892.png",
                collection: artBlocksCollection,
                estimatedValueUSD: 8900.0,
                tokenStandard: .erc721,
                ownerAddress: "0x742d35Cc6634C0532925a3b844Bc454e4438f44e"
            ),
            NFT(
                id: "demo-nft-5",
                contractAddress: "0x7Bd29408f11D2bFC23c34f18275bBf23bB716Bc7",
                tokenId: "4521",
                chain: .ethereum,
                name: "Loot Bag #4521",
                description: "Divine Robe of Giants, Dragonskin Belt...",
                imageURL: "https://i.seadn.io/gae/vw-gp8yUYkQsxQN5xbHrWEhY7rQWQZhIjgcRTxRMgF9ucL--M8PXnxXq2hfTFvv3JLHhkBgCWZ5JedJSdTb85pVTPOqlRbKAQYv1?w=500&auto=format",
                collection: gamingCollection,
                estimatedValueUSD: 3840.0,
                tokenStandard: .erc721,
                ownerAddress: "0x742d35Cc6634C0532925a3b844Bc454e4438f44e"
            )
        ]
    }
    
    // MARK: - Demo DeFi Positions
    
    static var demoPositions: [DeFiPosition] {
        [
            // Uniswap V3 LP
            DeFiPosition(
                id: "demo-uni-lp",
                protocol_: DeFiProtocolRegistry.uniswapV3,
                type: .liquidity,
                chain: .ethereum,
                tokens: [
                    PositionToken(
                        id: "uni-eth",
                        symbol: "ETH",
                        name: "Ethereum",
                        amount: 0.65,
                        valueUSD: 2080.0
                    ),
                    PositionToken(
                        id: "uni-usdc",
                        symbol: "USDC",
                        name: "USD Coin",
                        amount: 2120.0,
                        valueUSD: 2120.0
                    )
                ],
                valueUSD: 4200.0,
                apy: 18.5,
                metadata: PositionMetadata(
                    poolName: "ETH/USDC 0.3%",
                    fee: 0.003
                )
            ),
            
            // Aave Lending
            DeFiPosition(
                id: "demo-aave-supply",
                protocol_: DeFiProtocolRegistry.aaveV3,
                type: .lending,
                chain: .ethereum,
                tokens: [
                    PositionToken(
                        id: "aave-usdc",
                        symbol: "USDC",
                        name: "USD Coin",
                        amount: 2800.0,
                        valueUSD: 2800.0
                    )
                ],
                valueUSD: 2800.0,
                apy: 4.2,
                healthFactor: 2.8,
                rewardsUSD: 12.50
            ),
            
            // Lido Staking
            DeFiPosition(
                id: "demo-lido-stake",
                protocol_: DeFiProtocolRegistry.lido,
                type: .staking,
                chain: .ethereum,
                tokens: [
                    PositionToken(
                        id: "lido-steth",
                        symbol: "stETH",
                        name: "Staked Ether",
                        amount: 1.56,
                        valueUSD: 4992.0
                    )
                ],
                valueUSD: 4992.0,
                apy: 3.8,
                rewardsUSD: 45.20
            )
        ]
    }
    
    // MARK: - Computed Values
    
    static var demoTotalWalletValue: Double {
        demoWallets.compactMap(\.totalValueUSD).reduce(0, +)
    }
    
    static var demoTotalNFTValue: Double {
        demoNFTs.compactMap(\.estimatedValueUSD).reduce(0, +)
    }
    
    static var demoTotalDeFiValue: Double {
        demoPositions.map(\.valueUSD).reduce(0, +)
    }
}
