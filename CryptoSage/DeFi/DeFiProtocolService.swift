//
//  DeFiProtocolService.swift
//  CryptoSage
//
//  Service for fetching DeFi protocol positions (Uniswap, Aave, Lido, etc.).
//

import Foundation
import Combine

// MARK: - DeFi Protocol Service

/// Service for fetching DeFi protocol positions
public final class DeFiProtocolService: ObservableObject {
    public static let shared = DeFiProtocolService()
    
    // MARK: - Published Properties
    
    @Published public private(set) var isLoading = false
    @Published public private(set) var lastError: Error?
    @Published public private(set) var portfolioSummary: DeFiPortfolioSummary?
    
    // MARK: - Private Properties
    
    private let session: URLSession
    private let chainRegistry = ChainRegistry.shared
    private var cancellables = Set<AnyCancellable>()
    
    // Cache
    private var positionsCache: [String: [DeFiPosition]] = [:] // address -> positions
    private var cacheTimestamps: [String: Date] = [:]
    private let cacheTTL: TimeInterval = 300 // 5 minutes
    
    // MARK: - Initialization
    
    private init() {
        // SECURITY: Ephemeral session prevents disk caching of DeFi position data
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Public API
    
    /// Fetch all DeFi positions for an address
    public func fetchAllPositions(
        address: String,
        chains: [Chain]? = nil
    ) async throws -> DeFiPortfolioSummary {
        isLoading = true
        defer { isLoading = false }
        
        let targetChains = chains ?? chainRegistry.evmChains + [.solana]
        
        // Check cache
        let cacheKey = "\(address.lowercased())-\(targetChains.map { $0.rawValue }.joined(separator: ","))"
        if let cached = positionsCache[cacheKey],
           let timestamp = cacheTimestamps[cacheKey],
           Date().timeIntervalSince(timestamp) < cacheTTL {
            return DeFiPortfolioSummary.build(from: cached)
        }
        
        var allPositions: [DeFiPosition] = []
        
        // Try DefiLlama first (most comprehensive)
        do {
            let llamaPositions = try await fetchDefiLlamaPositions(address: address)
            allPositions.append(contentsOf: llamaPositions)
        } catch {
            #if DEBUG
            print("⚠️ DefiLlama fetch failed: \(error.localizedDescription)")
            #endif
        }

        // Fetch staking positions (Lido, etc.)
        do {
            let stakingPositions = try await fetchStakingPositions(address: address, chains: targetChains)
            allPositions.append(contentsOf: stakingPositions)
        } catch {
            #if DEBUG
            print("⚠️ Staking positions fetch failed: \(error.localizedDescription)")
            #endif
        }
        
        // Cache results
        positionsCache[cacheKey] = allPositions
        cacheTimestamps[cacheKey] = Date()
        
        let summary = DeFiPortfolioSummary.build(from: allPositions)
        portfolioSummary = summary
        
        return summary
    }
    
    /// Fetch positions from a specific protocol
    public func fetchProtocolPositions(
        address: String,
        protocol_: DeFiProtocol
    ) async throws -> [DeFiPosition] {
        switch protocol_.id {
        case "uniswap-v2", "uniswap-v3":
            return try await fetchUniswapPositions(address: address, isV3: protocol_.id == "uniswap-v3")
        case "aave-v3":
            return try await fetchAavePositions(address: address)
        case "lido":
            return try await fetchLidoPositions(address: address)
        default:
            return []
        }
    }
    
    // MARK: - DeBank Aggregator Integration
    
    private func fetchDefiLlamaPositions(address: String) async throws -> [DeFiPosition] {
        // Use DeFiAggregatorService (DeBank) for comprehensive DeFi positions
        // Check if aggregator API key is available (must access on MainActor)
        let hasKey = await MainActor.run { DeFiAggregatorService.shared.hasAPIKey }
        
        guard hasKey else {
            #if DEBUG
            print("⚠️ DeBank API key not configured, falling back to direct protocol queries")
            #endif
            return []
        }
        
        do {
            // Fetch all protocol positions via DeBank API
            let protocols = try await DeFiAggregatorService.shared.fetchAllProtocolPositions(address: address)
            
            var positions: [DeFiPosition] = []
            
            for protocol_ in protocols {
                for item in protocol_.portfolioItemList ?? [] {
                    // Convert DeBank response to internal DeFiPosition format
                    let position = convertDeBankToPosition(protocol_: protocol_, item: item)
                    positions.append(position)
                }
            }
            
            #if DEBUG
            print("✅ Fetched \(positions.count) DeFi positions via DeBank aggregator")
            #endif
            return positions
            
        } catch {
            #if DEBUG
            print("⚠️ DeBank fetch failed: \(error.localizedDescription)")
            #endif
            return []
        }
    }
    
    /// Convert DeBank protocol data to internal DeFiPosition format
    private func convertDeBankToPosition(protocol_: DeBankComplexProtocol, item: DeBankPortfolioItem) -> DeFiPosition {
        // Determine position type from item name
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
            positionType = .liquidity
        }
        
        // Map chain ID
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
        let category: DeFiProtocol.DeFiCategory
        switch positionType {
        case .liquidity: category = .dex
        case .lending, .borrowing: category = .lending
        case .staking: category = .staking
        case .farming, .vault: category = .yield
        default: category = .other
        }
        
        let defiProtocol = DeFiProtocol(
            id: protocol_.id,
            name: protocol_.name,
            chain: chain,
            category: category,
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
        case "era", "zksync": return .zksync
        case "linea": return .linea
        case "scrl", "scroll": return .scroll
        case "manta": return .manta
        case "mnt", "mantle": return .mantle
        case "blast": return .blast
        case "mode": return .mode
        case "pze": return .polygonZkEvm
        case "tron": return .tron
        default: return .ethereum
        }
    }
    
    // MARK: - Uniswap Positions
    
    private func fetchUniswapPositions(address: String, isV3: Bool) async throws -> [DeFiPosition] {
        var positions: [DeFiPosition] = []
        
        if isV3 {
            // Uniswap V3 - Query TheGraph
            positions.append(contentsOf: try await fetchUniswapV3FromGraph(address: address))
        } else {
            // Uniswap V2 - Check for LP tokens
            // This would require checking LP token balances
        }
        
        return positions
    }
    
    private func fetchUniswapV3FromGraph(address: String) async throws -> [DeFiPosition] {
        // TheGraph Uniswap V3 subgraph
        let graphURL = "https://api.thegraph.com/subgraphs/name/uniswap/uniswap-v3"
        guard let url = URL(string: graphURL) else {
            throw DeFiError.invalidURL
        }
        
        let query = """
        {
            positions(where: {owner: "\(address.lowercased())"}, first: 100) {
                id
                owner
                pool {
                    id
                    token0 { symbol name decimals }
                    token1 { symbol name decimals }
                    feeTier
                }
                liquidity
                tickLower { tickIdx }
                tickUpper { tickIdx }
                depositedToken0
                depositedToken1
                collectedFeesToken0
                collectedFeesToken1
            }
        }
        """
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["query": query]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await session.data(for: request)
        
        // Parse response
        struct GraphResponse: Codable {
            struct Data: Codable {
                struct Position: Codable {
                    let id: String
                    let liquidity: String
                    let depositedToken0: String
                    let depositedToken1: String
                    let pool: Pool
                    let tickLower: Tick
                    let tickUpper: Tick
                    
                    struct Pool: Codable {
                        let id: String
                        let token0: Token
                        let token1: Token
                        let feeTier: String
                    }
                    
                    struct Token: Codable {
                        let symbol: String
                        let name: String
                        let decimals: String
                    }
                    
                    struct Tick: Codable {
                        let tickIdx: String
                    }
                }
                let positions: [Position]
            }
            let data: Data?
        }
        
        let response = try JSONDecoder().decode(GraphResponse.self, from: data)
        
        guard let positionsData = response.data?.positions else { return [] }
        
        var positions: [DeFiPosition] = []
        
        for pos in positionsData {
            guard Double(pos.liquidity) ?? 0 > 0 else { continue }
            
            let token0Decimals = Int(pos.pool.token0.decimals) ?? 18
            let token1Decimals = Int(pos.pool.token1.decimals) ?? 18
            
            let amount0 = (Double(pos.depositedToken0) ?? 0) / pow(10, Double(token0Decimals))
            let amount1 = (Double(pos.depositedToken1) ?? 0) / pow(10, Double(token1Decimals))
            
            let position = DeFiPosition(
                id: pos.id,
                protocol_: DeFiProtocolRegistry.uniswapV3,
                type: .liquidity,
                chain: .ethereum,
                tokens: [
                    PositionToken(
                        symbol: pos.pool.token0.symbol,
                        name: pos.pool.token0.name,
                        amount: amount0
                    ),
                    PositionToken(
                        symbol: pos.pool.token1.symbol,
                        name: pos.pool.token1.name,
                        amount: amount1
                    )
                ],
                valueUSD: 0, // Would need price oracle
                metadata: PositionMetadata(
                    poolAddress: pos.pool.id,
                    poolName: "\(pos.pool.token0.symbol)/\(pos.pool.token1.symbol)",
                    fee: Double(pos.pool.feeTier).map { $0 / 10000 },
                    tickLower: Int(pos.tickLower.tickIdx),
                    tickUpper: Int(pos.tickUpper.tickIdx),
                    liquidity: pos.liquidity
                )
            )
            positions.append(position)
        }
        
        return positions
    }
    
    // MARK: - Aave Positions
    
    private func fetchAavePositions(address: String) async throws -> [DeFiPosition] {
        // Aave V3 TheGraph subgraph
        let graphURL = "https://api.thegraph.com/subgraphs/name/aave/protocol-v3"
        guard let url = URL(string: graphURL) else {
            throw DeFiError.invalidURL
        }
        
        let query = """
        {
            userReserves(where: {user: "\(address.lowercased())"}) {
                id
                reserve {
                    symbol
                    name
                    decimals
                    underlyingAsset
                    liquidityRate
                    variableBorrowRate
                }
                currentATokenBalance
                currentVariableDebt
                currentStableDebt
            }
        }
        """
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["query": query]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await session.data(for: request)
        
        struct AaveResponse: Codable {
            struct Data: Codable {
                struct UserReserve: Codable {
                    let id: String
                    let currentATokenBalance: String
                    let currentVariableDebt: String
                    let currentStableDebt: String
                    let reserve: Reserve
                    
                    struct Reserve: Codable {
                        let symbol: String
                        let name: String
                        let decimals: Int
                        let underlyingAsset: String
                        let liquidityRate: String
                        let variableBorrowRate: String
                    }
                }
                let userReserves: [UserReserve]
            }
            let data: Data?
        }
        
        let response = try JSONDecoder().decode(AaveResponse.self, from: data)
        
        guard let reserves = response.data?.userReserves else { return [] }
        
        var suppliedAssets: [PositionToken] = []
        var borrowedAssets: [PositionToken] = []
        let totalSupplied: Double = 0
        let totalBorrowed: Double = 0
        
        for reserve in reserves {
            let decimals = reserve.reserve.decimals
            let supplied = Double(reserve.currentATokenBalance) ?? 0
            let suppliedAmount = supplied / pow(10, Double(decimals))
            
            let variableDebt = Double(reserve.currentVariableDebt) ?? 0
            let stableDebt = Double(reserve.currentStableDebt) ?? 0
            let totalDebt = (variableDebt + stableDebt) / pow(10, Double(decimals))
            
            if suppliedAmount > 0.000001 {
                suppliedAssets.append(PositionToken(
                    symbol: reserve.reserve.symbol,
                    name: reserve.reserve.name,
                    contractAddress: reserve.reserve.underlyingAsset,
                    amount: suppliedAmount
                ))
                // Would need price to calculate USD value
            }
            
            if totalDebt > 0.000001 {
                borrowedAssets.append(PositionToken(
                    symbol: reserve.reserve.symbol,
                    name: reserve.reserve.name,
                    contractAddress: reserve.reserve.underlyingAsset,
                    amount: totalDebt,
                    isDebt: true
                ))
            }
        }
        
        var positions: [DeFiPosition] = []
        
        // Create lending position if user has supplied assets
        if !suppliedAssets.isEmpty {
            positions.append(DeFiPosition(
                protocol_: DeFiProtocolRegistry.aaveV3,
                type: .lending,
                chain: .ethereum,
                tokens: suppliedAssets,
                valueUSD: totalSupplied,
                apy: nil // Would calculate from liquidityRate
            ))
        }
        
        // Create borrowing position if user has debt
        if !borrowedAssets.isEmpty {
            positions.append(DeFiPosition(
                protocol_: DeFiProtocolRegistry.aaveV3,
                type: .borrowing,
                chain: .ethereum,
                tokens: borrowedAssets,
                valueUSD: totalBorrowed
            ))
        }
        
        return positions
    }
    
    // MARK: - Staking Positions (Lido, etc.)
    
    private func fetchStakingPositions(address: String, chains: [Chain]) async throws -> [DeFiPosition] {
        var positions: [DeFiPosition] = []
        
        // Check for stETH (Lido)
        if chains.contains(.ethereum) {
            if let lidoPosition = try await fetchLidoPosition(address: address) {
                positions.append(lidoPosition)
            }
        }
        
        // Check for Marinade (Solana)
        if chains.contains(.solana) {
            if let marinadePosition = try await fetchMarinadePosition(address: address) {
                positions.append(marinadePosition)
            }
        }
        
        return positions
    }
    
    private func fetchLidoPositions(address: String) async throws -> [DeFiPosition] {
        guard let position = try await fetchLidoPosition(address: address) else {
            return []
        }
        return [position]
    }
    
    private func fetchLidoPosition(address: String) async throws -> DeFiPosition? {
        // Check stETH balance via Etherscan or RPC
        // stETH contract: 0xae7ab96520DE3A18E5e111B5EaijFeB42D5c9CC8
        
        // For now, return nil - would need to actually check on-chain
        // In production, use Alchemy/Infura to call balanceOf
        
        return nil
    }
    
    private func fetchMarinadePosition(address: String) async throws -> DeFiPosition? {
        // Check for mSOL balance
        // This would require Helius or Solana RPC
        
        return nil
    }
    
    // MARK: - Zapper API Integration (if API key available)
    
    private func fetchZapperPositions(address: String, apiKey: String) async throws -> [DeFiPosition] {
        // Switch to Zapper provider and check API key (must access on MainActor)
        await MainActor.run {
            let aggregator = DeFiAggregatorService.shared
            if aggregator.provider != .zapper {
                aggregator.setProvider(.zapper)
            }
        }
        
        // Check if API key is set
        let hasKey = await MainActor.run { DeFiAggregatorService.shared.hasAPIKey }
        guard hasKey else {
            #if DEBUG
            print("⚠️ Zapper API key not configured")
            #endif
            return []
        }
        
        do {
            let protocols = try await DeFiAggregatorService.shared.fetchAllProtocolPositions(address: address)
            
            var positions: [DeFiPosition] = []
            
            for protocol_ in protocols {
                for item in protocol_.portfolioItemList ?? [] {
                    let position = convertDeBankToPosition(protocol_: protocol_, item: item)
                    positions.append(position)
                }
            }
            
            #if DEBUG
            print("✅ Fetched \(positions.count) DeFi positions via Zapper")
            #endif
            return positions
            
        } catch {
            #if DEBUG
            print("⚠️ Zapper fetch failed: \(error.localizedDescription)")
            #endif
            return []
        }
    }
    
    // MARK: - Unified Aggregator Fetch
    
    /// Fetch all positions using the best available aggregator (DeBank preferred)
    public func fetchAllPositionsViaAggregator(address: String) async throws -> DeFiPortfolioSummary {
        // Check API key availability on MainActor
        let hasKey = await MainActor.run { DeFiAggregatorService.shared.hasAPIKey }
        
        if hasKey {
            // Use aggregator for comprehensive coverage
            return try await DeFiAggregatorService.shared.fetchPortfolioSummary(address: address)
        } else {
            // Fall back to direct protocol queries
            return try await fetchAllPositions(address: address)
        }
    }
    
    // MARK: - Clear Cache
    
    public func clearCache() {
        positionsCache.removeAll()
        cacheTimestamps.removeAll()
    }
}

// MARK: - Protocol-Specific Extensions

extension DeFiProtocolService {
    
    /// Get supported protocols for a chain
    public func supportedProtocols(for chain: Chain) -> [DeFiProtocol] {
        DeFiProtocolRegistry.protocols(for: chain)
    }
    
    /// Check if an address has any DeFi positions (quick check)
    public func hasPositions(address: String) async -> Bool {
        // Quick heuristic check - could be optimized
        if let cached = portfolioSummary, !cached.positions.isEmpty {
            return true
        }
        return false
    }
}
