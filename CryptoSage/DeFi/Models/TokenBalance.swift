//
//  TokenBalance.swift
//  CryptoSage
//
//  Token balance models for ERC20, SPL, and other token standards.
//

import Foundation

// MARK: - Token Balance Model

/// Represents a token balance in a wallet
public struct TokenBalance: Identifiable, Codable, Equatable {
    public let id: String
    public let contractAddress: String
    public let symbol: String
    public let name: String
    public let decimals: Int
    public let balance: Double          // Human-readable balance
    public let rawBalance: String       // Raw balance (wei/lamports)
    public let chain: Chain
    public let logoURL: String?
    public let priceUSD: Double?
    public let valueUSD: Double?
    public let priceChange24h: Double?
    public let isSpam: Bool
    public let isVerified: Bool
    public let lastUpdated: Date
    
    public init(
        id: String = UUID().uuidString,
        contractAddress: String,
        symbol: String,
        name: String,
        decimals: Int,
        balance: Double,
        rawBalance: String,
        chain: Chain,
        logoURL: String? = nil,
        priceUSD: Double? = nil,
        valueUSD: Double? = nil,
        priceChange24h: Double? = nil,
        isSpam: Bool = false,
        isVerified: Bool = false,
        lastUpdated: Date = Date()
    ) {
        self.id = id
        self.contractAddress = contractAddress
        self.symbol = symbol
        self.name = name
        self.decimals = decimals
        self.balance = balance
        self.rawBalance = rawBalance
        self.chain = chain
        self.logoURL = logoURL
        self.priceUSD = priceUSD
        self.valueUSD = valueUSD
        self.priceChange24h = priceChange24h
        self.isSpam = isSpam
        self.isVerified = isVerified
        self.lastUpdated = lastUpdated
    }
    
    /// Unique identifier combining chain and contract
    public var uniqueKey: String {
        "\(chain.rawValue):\(contractAddress.lowercased())"
    }
}

// MARK: - Native Balance Model

/// Represents native coin balance (ETH, SOL, BTC, etc.)
public struct NativeBalance: Identifiable, Codable, Equatable {
    public let id: String
    public let chain: Chain
    public let symbol: String
    public let name: String
    public let balance: Double
    public let rawBalance: String
    public let priceUSD: Double?
    public let valueUSD: Double?
    public let priceChange24h: Double?
    public let lastUpdated: Date
    
    public init(
        id: String = UUID().uuidString,
        chain: Chain,
        symbol: String,
        name: String,
        balance: Double,
        rawBalance: String,
        priceUSD: Double? = nil,
        valueUSD: Double? = nil,
        priceChange24h: Double? = nil,
        lastUpdated: Date = Date()
    ) {
        self.id = id
        self.chain = chain
        self.symbol = symbol
        self.name = name
        self.balance = balance
        self.rawBalance = rawBalance
        self.priceUSD = priceUSD
        self.valueUSD = valueUSD
        self.priceChange24h = priceChange24h
        self.lastUpdated = lastUpdated
    }
}

// MARK: - Wallet Portfolio Model

/// Aggregated wallet portfolio across all chains
public struct WalletPortfolio: Identifiable, Codable {
    public let id: String
    public let address: String
    public let label: String?
    public var nativeBalances: [NativeBalance]
    public var tokenBalances: [TokenBalance]
    public var totalValueUSD: Double
    public var lastUpdated: Date
    
    public init(
        id: String = UUID().uuidString,
        address: String,
        label: String? = nil,
        nativeBalances: [NativeBalance] = [],
        tokenBalances: [TokenBalance] = [],
        totalValueUSD: Double = 0,
        lastUpdated: Date = Date()
    ) {
        self.id = id
        self.address = address
        self.label = label
        self.nativeBalances = nativeBalances
        self.tokenBalances = tokenBalances
        self.totalValueUSD = totalValueUSD
        self.lastUpdated = lastUpdated
    }
    
    /// Calculate total value from all balances
    public mutating func recalculateTotalValue() {
        let nativeValue = nativeBalances.compactMap { $0.valueUSD }.reduce(0, +)
        let tokenValue = tokenBalances.compactMap { $0.valueUSD }.reduce(0, +)
        totalValueUSD = nativeValue + tokenValue
    }
    
    /// Get balances for a specific chain
    public func balances(for chain: Chain) -> (native: NativeBalance?, tokens: [TokenBalance]) {
        let native = nativeBalances.first { $0.chain == chain }
        let tokens = tokenBalances.filter { $0.chain == chain }
        return (native, tokens)
    }
    
    /// Filter out spam tokens
    public var nonSpamTokens: [TokenBalance] {
        tokenBalances.filter { !$0.isSpam }
    }
    
    /// Get tokens sorted by USD value
    public var tokensByValue: [TokenBalance] {
        nonSpamTokens.sorted { ($0.valueUSD ?? 0) > ($1.valueUSD ?? 0) }
    }
}

// MARK: - Token Metadata

/// Metadata for a token contract
public struct TokenMetadata: Codable, Equatable {
    public let contractAddress: String
    public let chain: Chain
    public let symbol: String
    public let name: String
    public let decimals: Int
    public let logoURL: String?
    public let coingeckoId: String?
    public let isVerified: Bool
    public let totalSupply: String?
    public let website: String?
    public let twitter: String?
    public let description: String?
    
    public init(
        contractAddress: String,
        chain: Chain,
        symbol: String,
        name: String,
        decimals: Int,
        logoURL: String? = nil,
        coingeckoId: String? = nil,
        isVerified: Bool = false,
        totalSupply: String? = nil,
        website: String? = nil,
        twitter: String? = nil,
        description: String? = nil
    ) {
        self.contractAddress = contractAddress
        self.chain = chain
        self.symbol = symbol
        self.name = name
        self.decimals = decimals
        self.logoURL = logoURL
        self.coingeckoId = coingeckoId
        self.isVerified = isVerified
        self.totalSupply = totalSupply
        self.website = website
        self.twitter = twitter
        self.description = description
    }
}

// MARK: - Token Transfer Model

/// Represents a token transfer event
public struct TokenTransfer: Identifiable, Codable {
    public let id: String
    public let txHash: String
    public let blockNumber: Int
    public let timestamp: Date
    public let from: String
    public let to: String
    public let contractAddress: String
    public let symbol: String
    public let name: String
    public let decimals: Int
    public let value: Double
    public let rawValue: String
    public let chain: Chain
    public let gasUsed: String?
    public let gasPrice: String?
    
    public init(
        id: String = UUID().uuidString,
        txHash: String,
        blockNumber: Int,
        timestamp: Date,
        from: String,
        to: String,
        contractAddress: String,
        symbol: String,
        name: String,
        decimals: Int,
        value: Double,
        rawValue: String,
        chain: Chain,
        gasUsed: String? = nil,
        gasPrice: String? = nil
    ) {
        self.id = id
        self.txHash = txHash
        self.blockNumber = blockNumber
        self.timestamp = timestamp
        self.from = from
        self.to = to
        self.contractAddress = contractAddress
        self.symbol = symbol
        self.name = name
        self.decimals = decimals
        self.value = value
        self.rawValue = rawValue
        self.chain = chain
        self.gasUsed = gasUsed
        self.gasPrice = gasPrice
    }
    
    /// Determine if this is an incoming or outgoing transfer for an address
    public func direction(for address: String) -> TransferDirection {
        let addr = address.lowercased()
        if to.lowercased() == addr {
            return .incoming
        } else if from.lowercased() == addr {
            return .outgoing
        }
        return .unknown
    }
}

public enum TransferDirection: String, Codable {
    case incoming
    case outgoing
    case unknown
}

// MARK: - API Response Models

/// Etherscan token balance response
public struct EtherscanTokenBalanceResponse: Codable {
    public let status: String
    public let message: String
    public let result: [EtherscanTokenBalance]?
}

public struct EtherscanTokenBalance: Codable {
    public let contractAddress: String
    public let tokenName: String
    public let tokenSymbol: String
    public let tokenDecimal: String
    public let balance: String
    
    enum CodingKeys: String, CodingKey {
        case contractAddress = "contractAddress"
        case tokenName = "tokenName"
        case tokenSymbol = "tokenSymbol"
        case tokenDecimal = "tokenDecimal"
        case balance = "balance"
    }
}

/// Etherscan token transfer response
public struct EtherscanTokenTxResponse: Codable {
    public let status: String
    public let message: String
    public let result: [EtherscanTokenTx]?
}

public struct EtherscanTokenTx: Codable {
    public let blockNumber: String
    public let timeStamp: String
    public let hash: String
    public let from: String
    public let to: String
    public let contractAddress: String
    public let tokenName: String
    public let tokenSymbol: String
    public let tokenDecimal: String
    public let value: String
    public let gasUsed: String
    public let gasPrice: String
}

/// Helius (Solana) token balance response
public struct HeliusBalanceResponse: Codable {
    public let nativeBalance: HeliusNativeBalance?
    public let tokens: [HeliusTokenBalance]?
}

public struct HeliusNativeBalance: Codable {
    public let lamports: Int64
    public let price_per_sol: Double?
    public let total_price: Double?
}

public struct HeliusTokenBalance: Codable {
    public let mint: String
    public let amount: Int64
    public let decimals: Int
    public let token_account: String?
    public let associated_token_address: String?
    public let name: String?
    public let symbol: String?
    public let logo: String?
    public let price_info: HeliusPriceInfo?
}

public struct HeliusPriceInfo: Codable {
    public let price_per_token: Double?
    public let total_price: Double?
    public let currency: String?
}

// MARK: - Alchemy Response Models

public struct AlchemyTokenBalancesResponse: Codable {
    public let jsonrpc: String
    public let id: Int
    public let result: AlchemyTokenBalancesResult?
}

public struct AlchemyTokenBalancesResult: Codable {
    public let address: String
    public let tokenBalances: [AlchemyTokenBalance]
}

public struct AlchemyTokenBalance: Codable {
    public let contractAddress: String
    public let tokenBalance: String?
    public let error: String?
}

public struct AlchemyTokenMetadataResponse: Codable {
    public let jsonrpc: String
    public let id: Int
    public let result: AlchemyTokenMetadata?
}

public struct AlchemyTokenMetadata: Codable {
    public let name: String?
    public let symbol: String?
    public let decimals: Int?
    public let logo: String?
}
