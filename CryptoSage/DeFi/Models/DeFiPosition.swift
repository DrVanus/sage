//
//  DeFiPosition.swift
//  CryptoSage
//
//  Models for DeFi protocol positions (LP, lending, staking).
//

import Foundation

// MARK: - DeFi Position Types

/// Type of DeFi position
public enum DeFiPositionType: String, Codable, CaseIterable {
    case liquidity = "liquidity"       // LP tokens (Uniswap, SushiSwap, etc.)
    case lending = "lending"           // Lending deposits (Aave, Compound)
    case borrowing = "borrowing"       // Active loans
    case staking = "staking"           // Staked tokens (Lido, Rocket Pool)
    case farming = "farming"           // Yield farming positions
    case vault = "vault"               // Vault deposits (Yearn, Beefy)
    case claimable = "claimable"       // Pending rewards
    case nftStaking = "nft_staking"    // NFT staking positions
    
    public var displayName: String {
        switch self {
        case .liquidity: return "Liquidity"
        case .lending: return "Lending"
        case .borrowing: return "Borrowing"
        case .staking: return "Staking"
        case .farming: return "Farming"
        case .vault: return "Vault"
        case .claimable: return "Claimable"
        case .nftStaking: return "NFT Staking"
        }
    }
    
    public var icon: String {
        switch self {
        case .liquidity: return "drop.fill"
        case .lending: return "arrow.up.circle.fill"
        case .borrowing: return "arrow.down.circle.fill"
        case .staking: return "lock.fill"
        case .farming: return "leaf.fill"
        case .vault: return "building.columns.fill"
        case .claimable: return "gift.fill"
        case .nftStaking: return "photo.stack.fill"
        }
    }
}

// MARK: - DeFi Protocol

/// Known DeFi protocol
public struct DeFiProtocol: Identifiable, Codable {
    public let id: String
    public let name: String
    public let chain: Chain
    public let category: DeFiCategory
    public let logoURL: String?
    public let websiteURL: String?
    public let tvl: Double?
    
    public enum DeFiCategory: String, Codable {
        case dex = "dex"
        case lending = "lending"
        case staking = "staking"
        case yield = "yield"
        case derivatives = "derivatives"
        case bridge = "bridge"
        case insurance = "insurance"
        case other = "other"
    }
}

// MARK: - DeFi Position

/// Represents a DeFi position
public struct DeFiPosition: Identifiable, Codable {
    public let id: String
    public let protocol_: DeFiProtocol
    public let type: DeFiPositionType
    public let chain: Chain
    public let tokens: [PositionToken]
    public let valueUSD: Double
    public let apy: Double?
    public let healthFactor: Double?      // For lending positions
    public let unlockDate: Date?          // For locked staking
    public let rewardsUSD: Double?
    public let metadata: PositionMetadata?
    public let lastUpdated: Date
    
    public init(
        id: String = UUID().uuidString,
        protocol_: DeFiProtocol,
        type: DeFiPositionType,
        chain: Chain,
        tokens: [PositionToken],
        valueUSD: Double,
        apy: Double? = nil,
        healthFactor: Double? = nil,
        unlockDate: Date? = nil,
        rewardsUSD: Double? = nil,
        metadata: PositionMetadata? = nil,
        lastUpdated: Date = Date()
    ) {
        self.id = id
        self.protocol_ = protocol_
        self.type = type
        self.chain = chain
        self.tokens = tokens
        self.valueUSD = valueUSD
        self.apy = apy
        self.healthFactor = healthFactor
        self.unlockDate = unlockDate
        self.rewardsUSD = rewardsUSD
        self.metadata = metadata
        self.lastUpdated = lastUpdated
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case protocol_ = "protocol"
        case type, chain, tokens, valueUSD, apy, healthFactor
        case unlockDate, rewardsUSD, metadata, lastUpdated
    }
}

// MARK: - Position Token

/// Token within a DeFi position
public struct PositionToken: Identifiable, Codable {
    public let id: String
    public let symbol: String
    public let name: String
    public let contractAddress: String?
    public let amount: Double
    public let valueUSD: Double?
    public let logoURL: String?
    public let isDebt: Bool             // True for borrowed assets
    
    public init(
        id: String = UUID().uuidString,
        symbol: String,
        name: String,
        contractAddress: String? = nil,
        amount: Double,
        valueUSD: Double? = nil,
        logoURL: String? = nil,
        isDebt: Bool = false
    ) {
        self.id = id
        self.symbol = symbol
        self.name = name
        self.contractAddress = contractAddress
        self.amount = amount
        self.valueUSD = valueUSD
        self.logoURL = logoURL
        self.isDebt = isDebt
    }
}

// MARK: - Position Metadata

/// Additional metadata for DeFi positions
public struct PositionMetadata: Codable {
    public let poolAddress: String?
    public let poolName: String?
    public let fee: Double?              // Pool fee percentage
    public let tickLower: Int?           // For concentrated liquidity
    public let tickUpper: Int?
    public let liquidity: String?
    public let shares: Double?           // Vault shares
    public let collateralRatio: Double?  // For CDP positions
    public let liquidationPrice: Double?
    
    public init(
        poolAddress: String? = nil,
        poolName: String? = nil,
        fee: Double? = nil,
        tickLower: Int? = nil,
        tickUpper: Int? = nil,
        liquidity: String? = nil,
        shares: Double? = nil,
        collateralRatio: Double? = nil,
        liquidationPrice: Double? = nil
    ) {
        self.poolAddress = poolAddress
        self.poolName = poolName
        self.fee = fee
        self.tickLower = tickLower
        self.tickUpper = tickUpper
        self.liquidity = liquidity
        self.shares = shares
        self.collateralRatio = collateralRatio
        self.liquidationPrice = liquidationPrice
    }
}

// MARK: - Liquidity Position (Uniswap V2/V3 style)

/// LP position details
public struct LiquidityPosition: Identifiable, Codable {
    public let id: String
    public let protocol_: String
    public let poolAddress: String
    public let token0: PositionToken
    public let token1: PositionToken
    public let lpTokenBalance: Double
    public let poolShare: Double         // Percentage of pool
    public let valueUSD: Double
    public let fee: Double               // 0.3% = 0.003
    public let isV3: Bool
    public let tickLower: Int?
    public let tickUpper: Int?
    public let inRange: Bool?            // For V3 positions
    public let uncollectedFees: Double?
    
    public init(
        id: String = UUID().uuidString,
        protocol_: String,
        poolAddress: String,
        token0: PositionToken,
        token1: PositionToken,
        lpTokenBalance: Double,
        poolShare: Double,
        valueUSD: Double,
        fee: Double = 0.003,
        isV3: Bool = false,
        tickLower: Int? = nil,
        tickUpper: Int? = nil,
        inRange: Bool? = nil,
        uncollectedFees: Double? = nil
    ) {
        self.id = id
        self.protocol_ = protocol_
        self.poolAddress = poolAddress
        self.token0 = token0
        self.token1 = token1
        self.lpTokenBalance = lpTokenBalance
        self.poolShare = poolShare
        self.valueUSD = valueUSD
        self.fee = fee
        self.isV3 = isV3
        self.tickLower = tickLower
        self.tickUpper = tickUpper
        self.inRange = inRange
        self.uncollectedFees = uncollectedFees
    }
    
    /// Pool name (e.g., "ETH/USDC")
    public var poolName: String {
        "\(token0.symbol)/\(token1.symbol)"
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case protocol_ = "protocol"
        case poolAddress, token0, token1, lpTokenBalance, poolShare
        case valueUSD, fee, isV3, tickLower, tickUpper, inRange, uncollectedFees
    }
}

// MARK: - Lending Position (Aave/Compound style)

/// Lending/borrowing position
public struct LendingPosition: Identifiable, Codable {
    public let id: String
    public let protocol_: String
    public let chain: Chain
    public let suppliedAssets: [PositionToken]
    public let borrowedAssets: [PositionToken]
    public let totalSuppliedUSD: Double
    public let totalBorrowedUSD: Double
    public let netValueUSD: Double
    public let healthFactor: Double?     // < 1 = liquidation risk
    public let supplyAPY: Double?
    public let borrowAPY: Double?
    public let rewardsAPY: Double?
    public let pendingRewards: [PositionToken]
    
    public init(
        id: String = UUID().uuidString,
        protocol_: String,
        chain: Chain,
        suppliedAssets: [PositionToken],
        borrowedAssets: [PositionToken],
        totalSuppliedUSD: Double,
        totalBorrowedUSD: Double,
        healthFactor: Double? = nil,
        supplyAPY: Double? = nil,
        borrowAPY: Double? = nil,
        rewardsAPY: Double? = nil,
        pendingRewards: [PositionToken] = []
    ) {
        self.id = id
        self.protocol_ = protocol_
        self.chain = chain
        self.suppliedAssets = suppliedAssets
        self.borrowedAssets = borrowedAssets
        self.totalSuppliedUSD = totalSuppliedUSD
        self.totalBorrowedUSD = totalBorrowedUSD
        self.netValueUSD = totalSuppliedUSD - totalBorrowedUSD
        self.healthFactor = healthFactor
        self.supplyAPY = supplyAPY
        self.borrowAPY = borrowAPY
        self.rewardsAPY = rewardsAPY
        self.pendingRewards = pendingRewards
    }
    
    /// Utilization rate (borrowed / supplied)
    public var utilizationRate: Double {
        guard totalSuppliedUSD > 0 else { return 0 }
        return totalBorrowedUSD / totalSuppliedUSD
    }
    
    /// Whether position is at liquidation risk
    public var isAtRisk: Bool {
        guard let hf = healthFactor else { return false }
        return hf < 1.2
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case protocol_ = "protocol"
        case chain, suppliedAssets, borrowedAssets
        case totalSuppliedUSD, totalBorrowedUSD, netValueUSD
        case healthFactor, supplyAPY, borrowAPY, rewardsAPY, pendingRewards
    }
}

// MARK: - Staking Position

/// Staking position (Lido, Rocket Pool, etc.)
public struct StakingPosition: Identifiable, Codable {
    public let id: String
    public let protocol_: String
    public let chain: Chain
    public let stakedToken: PositionToken
    public let rewardToken: PositionToken?
    public let stakedAmount: Double
    public let valueUSD: Double
    public let apy: Double?
    public let pendingRewards: Double?
    public let pendingRewardsUSD: Double?
    public let lockPeriod: TimeInterval?
    public let unlockDate: Date?
    public let isLiquid: Bool            // stETH vs regular staking
    
    public init(
        id: String = UUID().uuidString,
        protocol_: String,
        chain: Chain,
        stakedToken: PositionToken,
        rewardToken: PositionToken? = nil,
        stakedAmount: Double,
        valueUSD: Double,
        apy: Double? = nil,
        pendingRewards: Double? = nil,
        pendingRewardsUSD: Double? = nil,
        lockPeriod: TimeInterval? = nil,
        unlockDate: Date? = nil,
        isLiquid: Bool = false
    ) {
        self.id = id
        self.protocol_ = protocol_
        self.chain = chain
        self.stakedToken = stakedToken
        self.rewardToken = rewardToken
        self.stakedAmount = stakedAmount
        self.valueUSD = valueUSD
        self.apy = apy
        self.pendingRewards = pendingRewards
        self.pendingRewardsUSD = pendingRewardsUSD
        self.lockPeriod = lockPeriod
        self.unlockDate = unlockDate
        self.isLiquid = isLiquid
    }
    
    /// Whether staking is currently locked
    public var isLocked: Bool {
        guard let unlock = unlockDate else { return false }
        return unlock > Date()
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case protocol_ = "protocol"
        case chain, stakedToken, rewardToken, stakedAmount, valueUSD
        case apy, pendingRewards, pendingRewardsUSD, lockPeriod, unlockDate, isLiquid
    }
}

// MARK: - DeFi Portfolio Summary

/// Aggregated DeFi portfolio
public struct DeFiPortfolioSummary: Codable {
    public var totalValueUSD: Double
    public var totalDebtUSD: Double
    public var netValueUSD: Double
    public var totalPendingRewardsUSD: Double
    public var positionsByType: [DeFiPositionType: Double]
    public var positionsByProtocol: [String: Double]
    public var positionsByChain: [Chain: Double]
    public var positions: [DeFiPosition]
    public var lastUpdated: Date
    
    public init(
        totalValueUSD: Double = 0,
        totalDebtUSD: Double = 0,
        totalPendingRewardsUSD: Double = 0,
        positionsByType: [DeFiPositionType: Double] = [:],
        positionsByProtocol: [String: Double] = [:],
        positionsByChain: [Chain: Double] = [:],
        positions: [DeFiPosition] = [],
        lastUpdated: Date = Date()
    ) {
        self.totalValueUSD = totalValueUSD
        self.totalDebtUSD = totalDebtUSD
        self.netValueUSD = totalValueUSD - totalDebtUSD
        self.totalPendingRewardsUSD = totalPendingRewardsUSD
        self.positionsByType = positionsByType
        self.positionsByProtocol = positionsByProtocol
        self.positionsByChain = positionsByChain
        self.positions = positions
        self.lastUpdated = lastUpdated
    }
    
    /// Build summary from positions
    public static func build(from positions: [DeFiPosition]) -> DeFiPortfolioSummary {
        var summary = DeFiPortfolioSummary()
        
        for position in positions {
            summary.totalValueUSD += position.valueUSD
            if position.type == .borrowing {
                summary.totalDebtUSD += position.valueUSD
            }
            if let rewards = position.rewardsUSD {
                summary.totalPendingRewardsUSD += rewards
            }
            
            summary.positionsByType[position.type, default: 0] += position.valueUSD
            summary.positionsByProtocol[position.protocol_.name, default: 0] += position.valueUSD
            summary.positionsByChain[position.chain, default: 0] += position.valueUSD
        }
        
        summary.netValueUSD = summary.totalValueUSD - summary.totalDebtUSD
        summary.positions = positions
        summary.lastUpdated = Date()
        
        return summary
    }
}

// MARK: - Protocol Registry

/// Registry of known DeFi protocols (40+ protocols across multiple chains)
public struct DeFiProtocolRegistry {
    
    // MARK: - Ethereum DEXes
    
    public static let uniswapV2 = DeFiProtocol(
        id: "uniswap-v2", name: "Uniswap V2", chain: .ethereum, category: .dex,
        logoURL: "https://app.uniswap.org/favicon.ico", websiteURL: "https://app.uniswap.org", tvl: nil
    )
    
    public static let uniswapV3 = DeFiProtocol(
        id: "uniswap-v3", name: "Uniswap V3", chain: .ethereum, category: .dex,
        logoURL: "https://app.uniswap.org/favicon.ico", websiteURL: "https://app.uniswap.org", tvl: nil
    )
    
    public static let curve = DeFiProtocol(
        id: "curve", name: "Curve Finance", chain: .ethereum, category: .dex,
        logoURL: "https://curve.fi/favicon.ico", websiteURL: "https://curve.fi", tvl: nil
    )
    
    public static let balancer = DeFiProtocol(
        id: "balancer", name: "Balancer", chain: .ethereum, category: .dex,
        logoURL: "https://balancer.fi/favicon.ico", websiteURL: "https://app.balancer.fi", tvl: nil
    )
    
    public static let sushiswap = DeFiProtocol(
        id: "sushiswap", name: "SushiSwap", chain: .ethereum, category: .dex,
        logoURL: "https://sushi.com/favicon.ico", websiteURL: "https://sushi.com", tvl: nil
    )
    
    public static let oneInch = DeFiProtocol(
        id: "1inch", name: "1inch", chain: .ethereum, category: .dex,
        logoURL: "https://1inch.io/favicon.ico", websiteURL: "https://app.1inch.io", tvl: nil
    )
    
    // MARK: - Ethereum Lending
    
    public static let aaveV3 = DeFiProtocol(
        id: "aave-v3", name: "Aave V3", chain: .ethereum, category: .lending,
        logoURL: "https://aave.com/favicon.ico", websiteURL: "https://app.aave.com", tvl: nil
    )
    
    public static let compound = DeFiProtocol(
        id: "compound", name: "Compound", chain: .ethereum, category: .lending,
        logoURL: "https://compound.finance/favicon.ico", websiteURL: "https://app.compound.finance", tvl: nil
    )
    
    public static let morpho = DeFiProtocol(
        id: "morpho", name: "Morpho", chain: .ethereum, category: .lending,
        logoURL: "https://morpho.org/favicon.ico", websiteURL: "https://app.morpho.org", tvl: nil
    )
    
    public static let spark = DeFiProtocol(
        id: "spark", name: "Spark Protocol", chain: .ethereum, category: .lending,
        logoURL: "https://spark.fi/favicon.ico", websiteURL: "https://app.spark.fi", tvl: nil
    )
    
    public static let maker = DeFiProtocol(
        id: "maker", name: "MakerDAO", chain: .ethereum, category: .lending,
        logoURL: "https://makerdao.com/favicon.ico", websiteURL: "https://oasis.app", tvl: nil
    )
    
    public static let fluidLending = DeFiProtocol(
        id: "fluid", name: "Fluid", chain: .ethereum, category: .lending,
        logoURL: "https://fluid.instadapp.io/favicon.ico", websiteURL: "https://fluid.instadapp.io", tvl: nil
    )
    
    // MARK: - Ethereum Liquid Staking
    
    public static let lido = DeFiProtocol(
        id: "lido", name: "Lido", chain: .ethereum, category: .staking,
        logoURL: "https://lido.fi/favicon.ico", websiteURL: "https://lido.fi", tvl: nil
    )
    
    public static let rocketPool = DeFiProtocol(
        id: "rocket-pool", name: "Rocket Pool", chain: .ethereum, category: .staking,
        logoURL: "https://rocketpool.net/favicon.ico", websiteURL: "https://stake.rocketpool.net", tvl: nil
    )
    
    public static let fraxEth = DeFiProtocol(
        id: "frax-ether", name: "Frax Ether", chain: .ethereum, category: .staking,
        logoURL: "https://frax.finance/favicon.ico", websiteURL: "https://app.frax.finance", tvl: nil
    )
    
    public static let eigenlayer = DeFiProtocol(
        id: "eigenlayer", name: "EigenLayer", chain: .ethereum, category: .staking,
        logoURL: "https://eigenlayer.xyz/favicon.ico", websiteURL: "https://app.eigenlayer.xyz", tvl: nil
    )
    
    public static let etherfi = DeFiProtocol(
        id: "ether.fi", name: "ether.fi", chain: .ethereum, category: .staking,
        logoURL: "https://ether.fi/favicon.ico", websiteURL: "https://app.ether.fi", tvl: nil
    )
    
    public static let kelp = DeFiProtocol(
        id: "kelp", name: "Kelp DAO", chain: .ethereum, category: .staking,
        logoURL: "https://kelpdao.xyz/favicon.ico", websiteURL: "https://kelpdao.xyz", tvl: nil
    )
    
    // MARK: - Ethereum Yield
    
    public static let yearn = DeFiProtocol(
        id: "yearn", name: "Yearn Finance", chain: .ethereum, category: .yield,
        logoURL: "https://yearn.fi/favicon.ico", websiteURL: "https://yearn.fi", tvl: nil
    )
    
    public static let convex = DeFiProtocol(
        id: "convex", name: "Convex Finance", chain: .ethereum, category: .yield,
        logoURL: "https://convexfinance.com/favicon.ico", websiteURL: "https://convexfinance.com", tvl: nil
    )
    
    public static let pendle = DeFiProtocol(
        id: "pendle", name: "Pendle", chain: .ethereum, category: .yield,
        logoURL: "https://pendle.finance/favicon.ico", websiteURL: "https://app.pendle.finance", tvl: nil
    )
    
    public static let beefy = DeFiProtocol(
        id: "beefy", name: "Beefy Finance", chain: .ethereum, category: .yield,
        logoURL: "https://beefy.com/favicon.ico", websiteURL: "https://app.beefy.com", tvl: nil
    )
    
    // MARK: - Ethereum Derivatives
    
    public static let dydx = DeFiProtocol(
        id: "dydx", name: "dYdX", chain: .ethereum, category: .derivatives,
        logoURL: "https://dydx.exchange/favicon.ico", websiteURL: "https://trade.dydx.exchange", tvl: nil
    )
    
    public static let synthetix = DeFiProtocol(
        id: "synthetix", name: "Synthetix", chain: .ethereum, category: .derivatives,
        logoURL: "https://synthetix.io/favicon.ico", websiteURL: "https://synthetix.io", tvl: nil
    )
    
    // MARK: - Arbitrum
    
    public static let gmx = DeFiProtocol(
        id: "gmx", name: "GMX", chain: .arbitrum, category: .derivatives,
        logoURL: "https://gmx.io/favicon.ico", websiteURL: "https://app.gmx.io", tvl: nil
    )
    
    public static let camelot = DeFiProtocol(
        id: "camelot", name: "Camelot", chain: .arbitrum, category: .dex,
        logoURL: "https://camelot.exchange/favicon.ico", websiteURL: "https://app.camelot.exchange", tvl: nil
    )
    
    public static let radiant = DeFiProtocol(
        id: "radiant", name: "Radiant Capital", chain: .arbitrum, category: .lending,
        logoURL: "https://radiant.capital/favicon.ico", websiteURL: "https://app.radiant.capital", tvl: nil
    )
    
    public static let vertex = DeFiProtocol(
        id: "vertex", name: "Vertex Protocol", chain: .arbitrum, category: .derivatives,
        logoURL: "https://vertexprotocol.com/favicon.ico", websiteURL: "https://app.vertexprotocol.com", tvl: nil
    )
    
    // MARK: - BNB Chain
    
    public static let pancakeswap = DeFiProtocol(
        id: "pancakeswap", name: "PancakeSwap", chain: .bsc, category: .dex,
        logoURL: "https://pancakeswap.finance/favicon.ico", websiteURL: "https://pancakeswap.finance", tvl: nil
    )
    
    public static let venus = DeFiProtocol(
        id: "venus", name: "Venus Protocol", chain: .bsc, category: .lending,
        logoURL: "https://venus.io/favicon.ico", websiteURL: "https://app.venus.io", tvl: nil
    )
    
    public static let alpaca = DeFiProtocol(
        id: "alpaca", name: "Alpaca Finance", chain: .bsc, category: .yield,
        logoURL: "https://alpacafinance.org/favicon.ico", websiteURL: "https://app.alpacafinance.org", tvl: nil
    )
    
    // MARK: - Avalanche
    
    public static let traderJoe = DeFiProtocol(
        id: "trader-joe", name: "Trader Joe", chain: .avalanche, category: .dex,
        logoURL: "https://traderjoexyz.com/favicon.ico", websiteURL: "https://traderjoexyz.com", tvl: nil
    )
    
    public static let benqi = DeFiProtocol(
        id: "benqi", name: "BENQI", chain: .avalanche, category: .lending,
        logoURL: "https://benqi.fi/favicon.ico", websiteURL: "https://app.benqi.fi", tvl: nil
    )
    
    // MARK: - Polygon
    
    public static let quickswap = DeFiProtocol(
        id: "quickswap", name: "QuickSwap", chain: .polygon, category: .dex,
        logoURL: "https://quickswap.exchange/favicon.ico", websiteURL: "https://quickswap.exchange", tvl: nil
    )
    
    // MARK: - Optimism
    
    public static let velodrome = DeFiProtocol(
        id: "velodrome", name: "Velodrome", chain: .optimism, category: .dex,
        logoURL: "https://velodrome.finance/favicon.ico", websiteURL: "https://velodrome.finance", tvl: nil
    )
    
    // MARK: - Base
    
    public static let aerodrome = DeFiProtocol(
        id: "aerodrome", name: "Aerodrome", chain: .base, category: .dex,
        logoURL: "https://aerodrome.finance/favicon.ico", websiteURL: "https://aerodrome.finance", tvl: nil
    )
    
    public static let moonwell = DeFiProtocol(
        id: "moonwell", name: "Moonwell", chain: .base, category: .lending,
        logoURL: "https://moonwell.fi/favicon.ico", websiteURL: "https://moonwell.fi", tvl: nil
    )
    
    // MARK: - Blast
    
    public static let thruster = DeFiProtocol(
        id: "thruster", name: "Thruster", chain: .blast, category: .dex,
        logoURL: "https://thruster.finance/favicon.ico", websiteURL: "https://app.thruster.finance", tvl: nil
    )
    
    public static let juice = DeFiProtocol(
        id: "juice", name: "Juice Finance", chain: .blast, category: .lending,
        logoURL: "https://juice.finance/favicon.ico", websiteURL: "https://app.juice.finance", tvl: nil
    )
    
    public static let hyperliquid = DeFiProtocol(
        id: "hyperliquid", name: "Hyperliquid", chain: .arbitrum, category: .derivatives,
        logoURL: "https://hyperliquid.xyz/favicon.ico", websiteURL: "https://app.hyperliquid.xyz", tvl: nil
    )
    
    // MARK: - Solana
    
    public static let raydium = DeFiProtocol(
        id: "raydium", name: "Raydium", chain: .solana, category: .dex,
        logoURL: "https://raydium.io/favicon.ico", websiteURL: "https://raydium.io", tvl: nil
    )
    
    public static let orca = DeFiProtocol(
        id: "orca", name: "Orca", chain: .solana, category: .dex,
        logoURL: "https://orca.so/favicon.ico", websiteURL: "https://orca.so", tvl: nil
    )
    
    public static let marinade = DeFiProtocol(
        id: "marinade", name: "Marinade Finance", chain: .solana, category: .staking,
        logoURL: "https://marinade.finance/favicon.ico", websiteURL: "https://marinade.finance", tvl: nil
    )
    
    public static let jito = DeFiProtocol(
        id: "jito", name: "Jito", chain: .solana, category: .staking,
        logoURL: "https://jito.network/favicon.ico", websiteURL: "https://jito.network", tvl: nil
    )
    
    public static let jupiter = DeFiProtocol(
        id: "jupiter", name: "Jupiter", chain: .solana, category: .dex,
        logoURL: "https://jup.ag/favicon.ico", websiteURL: "https://jup.ag", tvl: nil
    )
    
    public static let kamino = DeFiProtocol(
        id: "kamino", name: "Kamino Finance", chain: .solana, category: .lending,
        logoURL: "https://kamino.finance/favicon.ico", websiteURL: "https://app.kamino.finance", tvl: nil
    )
    
    public static let marginfi = DeFiProtocol(
        id: "marginfi", name: "marginfi", chain: .solana, category: .lending,
        logoURL: "https://marginfi.com/favicon.ico", websiteURL: "https://app.marginfi.com", tvl: nil
    )
    
    public static let drift = DeFiProtocol(
        id: "drift", name: "Drift Protocol", chain: .solana, category: .derivatives,
        logoURL: "https://drift.trade/favicon.ico", websiteURL: "https://app.drift.trade", tvl: nil
    )
    
    // MARK: - Cosmos Ecosystem
    
    public static let osmosisAmm = DeFiProtocol(
        id: "osmosis", name: "Osmosis", chain: .osmosis, category: .dex,
        logoURL: "https://osmosis.zone/favicon.ico", websiteURL: "https://app.osmosis.zone", tvl: nil
    )
    
    public static let astroport = DeFiProtocol(
        id: "astroport", name: "Astroport", chain: .cosmos, category: .dex,
        logoURL: "https://astroport.fi/favicon.ico", websiteURL: "https://astroport.fi", tvl: nil
    )
    
    public static let marsProtocol = DeFiProtocol(
        id: "mars", name: "Mars Protocol", chain: .cosmos, category: .lending,
        logoURL: "https://marsprotocol.io/favicon.ico", websiteURL: "https://app.marsprotocol.io", tvl: nil
    )
    
    // MARK: - Sui
    
    public static let cetus = DeFiProtocol(
        id: "cetus", name: "Cetus", chain: .sui, category: .dex,
        logoURL: "https://cetus.zone/favicon.ico", websiteURL: "https://app.cetus.zone", tvl: nil
    )
    
    public static let turbos = DeFiProtocol(
        id: "turbos", name: "Turbos Finance", chain: .sui, category: .dex,
        logoURL: "https://turbos.finance/favicon.ico", websiteURL: "https://app.turbos.finance", tvl: nil
    )
    
    public static let scallop = DeFiProtocol(
        id: "scallop", name: "Scallop", chain: .sui, category: .lending,
        logoURL: "https://scallop.io/favicon.ico", websiteURL: "https://app.scallop.io", tvl: nil
    )
    
    // MARK: - Aptos
    
    public static let liquidswap = DeFiProtocol(
        id: "liquidswap", name: "LiquidSwap", chain: .aptos, category: .dex,
        logoURL: "https://liquidswap.com/favicon.ico", websiteURL: "https://liquidswap.com", tvl: nil
    )
    
    public static let thala = DeFiProtocol(
        id: "thala", name: "Thala Labs", chain: .aptos, category: .dex,
        logoURL: "https://thala.fi/favicon.ico", websiteURL: "https://app.thala.fi", tvl: nil
    )
    
    // MARK: - All Protocols Array
    
    public static let all: [DeFiProtocol] = [
        // Ethereum DEXes
        uniswapV2, uniswapV3, curve, balancer, sushiswap, oneInch,
        // Ethereum Lending
        aaveV3, compound, morpho, spark, maker, fluidLending,
        // Ethereum Liquid Staking
        lido, rocketPool, fraxEth, eigenlayer, etherfi, kelp,
        // Ethereum Yield
        yearn, convex, pendle, beefy,
        // Ethereum Derivatives
        dydx, synthetix,
        // Arbitrum
        gmx, camelot, radiant, vertex, hyperliquid,
        // BNB Chain
        pancakeswap, venus, alpaca,
        // Avalanche
        traderJoe, benqi,
        // Polygon
        quickswap,
        // Optimism
        velodrome,
        // Base
        aerodrome, moonwell,
        // Blast
        thruster, juice,
        // Solana
        raydium, orca, marinade, jito, jupiter, kamino, marginfi, drift,
        // Cosmos
        osmosisAmm, astroport, marsProtocol,
        // Sui
        cetus, turbos, scallop,
        // Aptos
        liquidswap, thala
    ]
    
    /// Find protocol by ID
    public static func find(id: String) -> DeFiProtocol? {
        all.first { $0.id == id }
    }
    
    /// Find protocol by name (case-insensitive)
    public static func find(name: String) -> DeFiProtocol? {
        all.first { $0.name.lowercased() == name.lowercased() }
    }
    
    /// Get protocols for a specific chain
    public static func protocols(for chain: Chain) -> [DeFiProtocol] {
        all.filter { $0.chain == chain }
    }
    
    /// Get protocols by category
    public static func protocols(category: DeFiProtocol.DeFiCategory) -> [DeFiProtocol] {
        all.filter { $0.category == category }
    }
    
    /// Get all DEXes
    public static var dexes: [DeFiProtocol] {
        protocols(category: .dex)
    }
    
    /// Get all lending protocols
    public static var lendingProtocols: [DeFiProtocol] {
        protocols(category: .lending)
    }
    
    /// Get all staking protocols
    public static var stakingProtocols: [DeFiProtocol] {
        protocols(category: .staking)
    }
    
    /// Get all yield protocols
    public static var yieldProtocols: [DeFiProtocol] {
        protocols(category: .yield)
    }
}
