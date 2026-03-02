//
//  ConnectionProvider.swift
//  CryptoSage
//
//  Unified protocol for exchange and wallet connections.
//  Supports OAuth, Direct API Keys, and Blockchain address tracking.
//

import Foundation
import Combine

// MARK: - Connection Types

/// The type of connection method used
enum ConnectionType: String, Codable, CaseIterable {
    case oauth = "oauth"           // Coinbase, Kraken, Gemini
    case apiKey = "api_key"        // Binance, KuCoin, Bybit
    case walletAddress = "wallet"  // ETH, BTC, SOL addresses
    case threeCommas = "3commas"   // Legacy 3Commas integration
    
    var displayName: String {
        switch self {
        case .oauth: return "Connect Account"
        case .apiKey: return "API Key"
        case .walletAddress: return "Wallet Address"
        case .threeCommas: return "3Commas"
        }
    }
    
    var description: String {
        switch self {
        case .oauth: return "One-click secure connection"
        case .apiKey: return "Read-only API key from exchange"
        case .walletAddress: return "Just paste your wallet address"
        case .threeCommas: return "For trading bots (advanced)"
        }
    }
}

// MARK: - Exchange/Wallet Info

/// Information about a supported exchange or wallet
struct ExchangeInfo: Identifiable {
    let id: String
    let name: String
    let connectionType: ConnectionType
    let category: ExchangeCategory
    let logoURL: String?
    let supportedChains: [String]? // For wallets only
    let oauthClientId: String?     // For OAuth exchanges only
    let apiDocsURL: String?        // Link to exchange API docs
    
    enum ExchangeCategory: String, Codable {
        case exchange = "exchange"
        case wallet = "wallet"
        case defi = "defi"
    }
}

/// Registry of all supported exchanges and wallets
struct ExchangeRegistry {
    
    // MARK: - OAuth Exchanges (One-click connect)
    
    static let coinbase = ExchangeInfo(
        id: "coinbase",
        name: "Coinbase",
        connectionType: .oauth,
        category: .exchange,
        logoURL: nil,
        supportedChains: nil,
        oauthClientId: nil, // Set via config
        apiDocsURL: "https://docs.cloud.coinbase.com/sign-in-with-coinbase/docs"
    )
    
    static let kraken = ExchangeInfo(
        id: "kraken",
        name: "Kraken",
        connectionType: .oauth,
        category: .exchange,
        logoURL: nil,
        supportedChains: nil,
        oauthClientId: nil,
        apiDocsURL: "https://docs.kraken.com/rest/"
    )
    
    static let gemini = ExchangeInfo(
        id: "gemini",
        name: "Gemini",
        connectionType: .oauth,
        category: .exchange,
        logoURL: nil,
        supportedChains: nil,
        oauthClientId: nil,
        apiDocsURL: "https://docs.gemini.com/"
    )
    
    // MARK: - API Key Exchanges (Manual key entry)
    
    static let binance = ExchangeInfo(
        id: "binance",
        name: "Binance",
        connectionType: .apiKey,
        category: .exchange,
        logoURL: nil,
        supportedChains: nil,
        oauthClientId: nil,
        apiDocsURL: "https://binance-docs.github.io/apidocs/"
    )
    
    static let binanceUS = ExchangeInfo(
        id: "binance_us",
        name: "Binance US",
        connectionType: .apiKey,
        category: .exchange,
        logoURL: nil,
        supportedChains: nil,
        oauthClientId: nil,
        apiDocsURL: "https://docs.binance.us/"
    )
    
    static let kucoin = ExchangeInfo(
        id: "kucoin",
        name: "KuCoin",
        connectionType: .apiKey,
        category: .exchange,
        logoURL: nil,
        supportedChains: nil,
        oauthClientId: nil,
        apiDocsURL: "https://docs.kucoin.com/"
    )
    
    static let bybit = ExchangeInfo(
        id: "bybit",
        name: "Bybit",
        connectionType: .apiKey,
        category: .exchange,
        logoURL: nil,
        supportedChains: nil,
        oauthClientId: nil,
        apiDocsURL: "https://bybit-exchange.github.io/docs/"
    )
    
    static let okx = ExchangeInfo(
        id: "okx",
        name: "OKX",
        connectionType: .apiKey,
        category: .exchange,
        logoURL: nil,
        supportedChains: nil,
        oauthClientId: nil,
        apiDocsURL: "https://www.okx.com/docs-v5/"
    )
    
    static let huobi = ExchangeInfo(
        id: "huobi",
        name: "Huobi",
        connectionType: .apiKey,
        category: .exchange,
        logoURL: nil,
        supportedChains: nil,
        oauthClientId: nil,
        apiDocsURL: "https://huobiapi.github.io/docs/"
    )
    
    static let bitstamp = ExchangeInfo(
        id: "bitstamp",
        name: "Bitstamp",
        connectionType: .apiKey,
        category: .exchange,
        logoURL: nil,
        supportedChains: nil,
        oauthClientId: nil,
        apiDocsURL: "https://www.bitstamp.net/api/"
    )
    
    static let gateio = ExchangeInfo(
        id: "gateio",
        name: "Gate.io",
        connectionType: .apiKey,
        category: .exchange,
        logoURL: nil,
        supportedChains: nil,
        oauthClientId: nil,
        apiDocsURL: "https://www.gate.io/docs/developers/apiv4/"
    )
    
    static let mexc = ExchangeInfo(
        id: "mexc",
        name: "MEXC",
        connectionType: .apiKey,
        category: .exchange,
        logoURL: nil,
        supportedChains: nil,
        oauthClientId: nil,
        apiDocsURL: "https://mexcdevelop.github.io/apidocs/"
    )
    
    static let htx = ExchangeInfo(
        id: "htx",
        name: "HTX",
        connectionType: .apiKey,
        category: .exchange,
        logoURL: nil,
        supportedChains: nil,
        oauthClientId: nil,
        apiDocsURL: "https://www.htx.com/en-us/opend/"
    )
    
    static let cryptocom = ExchangeInfo(
        id: "cryptocom",
        name: "Crypto.com",
        connectionType: .apiKey,
        category: .exchange,
        logoURL: nil,
        supportedChains: nil,
        oauthClientId: nil,
        apiDocsURL: "https://exchange-docs.crypto.com/"
    )
    
    static let bitget = ExchangeInfo(
        id: "bitget",
        name: "Bitget",
        connectionType: .apiKey,
        category: .exchange,
        logoURL: nil,
        supportedChains: nil,
        oauthClientId: nil,
        apiDocsURL: "https://bitgetlimited.github.io/apidoc/"
    )
    
    static let bitfinex = ExchangeInfo(
        id: "bitfinex",
        name: "Bitfinex",
        connectionType: .apiKey,
        category: .exchange,
        logoURL: nil,
        supportedChains: nil,
        oauthClientId: nil,
        apiDocsURL: "https://docs.bitfinex.com/"
    )
    
    // MARK: - Wallet Addresses (No keys needed)
    
    static let ethereumWallet = ExchangeInfo(
        id: "ethereum_wallet",
        name: "Ethereum Wallet",
        connectionType: .walletAddress,
        category: .wallet,
        logoURL: nil,
        supportedChains: ["ETH", "ERC20"],
        oauthClientId: nil,
        apiDocsURL: nil
    )
    
    static let bitcoinWallet = ExchangeInfo(
        id: "bitcoin_wallet",
        name: "Bitcoin Wallet",
        connectionType: .walletAddress,
        category: .wallet,
        logoURL: nil,
        supportedChains: ["BTC"],
        oauthClientId: nil,
        apiDocsURL: nil
    )
    
    static let solanaWallet = ExchangeInfo(
        id: "solana_wallet",
        name: "Solana Wallet",
        connectionType: .walletAddress,
        category: .wallet,
        logoURL: nil,
        supportedChains: ["SOL", "SPL"],
        oauthClientId: nil,
        apiDocsURL: nil
    )
    
    static let polygonWallet = ExchangeInfo(
        id: "polygon_wallet",
        name: "Polygon Wallet",
        connectionType: .walletAddress,
        category: .wallet,
        logoURL: nil,
        supportedChains: ["MATIC", "ERC20"],
        oauthClientId: nil,
        apiDocsURL: nil
    )
    
    static let arbitrumWallet = ExchangeInfo(
        id: "arbitrum_wallet",
        name: "Arbitrum Wallet",
        connectionType: .walletAddress,
        category: .wallet,
        logoURL: nil,
        supportedChains: ["ARB", "ETH"],
        oauthClientId: nil,
        apiDocsURL: nil
    )
    
    static let baseWallet = ExchangeInfo(
        id: "base_wallet",
        name: "Base Wallet",
        connectionType: .walletAddress,
        category: .wallet,
        logoURL: nil,
        supportedChains: ["BASE", "ETH"],
        oauthClientId: nil,
        apiDocsURL: nil
    )
    
    static let avalancheWallet = ExchangeInfo(
        id: "avalanche_wallet",
        name: "Avalanche Wallet",
        connectionType: .walletAddress,
        category: .wallet,
        logoURL: nil,
        supportedChains: ["AVAX"],
        oauthClientId: nil,
        apiDocsURL: nil
    )
    
    static let bnbWallet = ExchangeInfo(
        id: "bnb_wallet",
        name: "BNB Chain Wallet",
        connectionType: .walletAddress,
        category: .wallet,
        logoURL: nil,
        supportedChains: ["BNB", "BEP20"],
        oauthClientId: nil,
        apiDocsURL: nil
    )
    
    // MARK: - All Exchanges
    
    static let oauthExchanges: [ExchangeInfo] = [
        coinbase, kraken, gemini
    ]
    
    static let apiKeyExchanges: [ExchangeInfo] = [
        binance, binanceUS, kucoin, bybit, okx, gateio, mexc, htx, cryptocom, bitget, bitfinex
    ]
    
    static let wallets: [ExchangeInfo] = [
        ethereumWallet, bitcoinWallet, solanaWallet, polygonWallet, arbitrumWallet, baseWallet, avalancheWallet, bnbWallet
    ]
    
    static let allExchanges: [ExchangeInfo] = oauthExchanges + apiKeyExchanges
    
    static let all: [ExchangeInfo] = allExchanges + wallets
    
    /// Get exchange info by ID
    static func get(id: String) -> ExchangeInfo? {
        all.first { $0.id == id }
    }
    
    /// Get exchange info by name (case-insensitive)
    static func get(name: String) -> ExchangeInfo? {
        let lowercased = name.lowercased()
        return all.first { $0.name.lowercased() == lowercased || $0.id == lowercased }
    }
    
    /// Get connection type for an exchange name
    static func connectionType(for name: String) -> ConnectionType {
        get(name: name)?.connectionType ?? .apiKey
    }
}

// MARK: - Connection Result

/// Result of a connection attempt
struct ConnectionResult {
    let success: Bool
    let accountId: String?
    let accountName: String?
    let error: ConnectionError?
    let balances: [PortfolioBalance]?
}

/// Portfolio balance from a connected account
struct PortfolioBalance: Identifiable, Codable {
    let id: String
    let symbol: String
    let name: String
    let balance: Double
    let usdValue: Double?
    let chain: String?
    
    init(id: String = UUID().uuidString, symbol: String, name: String, balance: Double, usdValue: Double? = nil, chain: String? = nil) {
        self.id = id
        self.symbol = symbol
        self.name = name
        self.balance = balance
        self.usdValue = usdValue
        self.chain = chain
    }
}

/// Errors that can occur during connection
enum ConnectionError: LocalizedError {
    case invalidCredentials
    case networkError(Error)
    case oauthCancelled
    case oauthFailed(String)
    case invalidAddress
    case unsupportedExchange
    case rateLimited
    case serverError(Int)
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid credentials. Please check your API key and secret."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .oauthCancelled:
            return "Connection was cancelled."
        case .oauthFailed(let message):
            return "Authentication failed: \(message)"
        case .invalidAddress:
            return "Invalid wallet address format."
        case .unsupportedExchange:
            return "This exchange is not yet supported."
        case .rateLimited:
            return "Rate limited. Please try again later."
        case .serverError(let code):
            return "Server error (HTTP \(code)). Please try again."
        case .unknown(let message):
            return message
        }
    }
}

// MARK: - Connection Provider Protocol

/// Protocol that all connection providers must implement
protocol ConnectionProvider {
    /// The type of connection this provider handles
    var connectionType: ConnectionType { get }
    
    /// Supported exchange IDs
    var supportedExchanges: [String] { get }
    
    /// Check if this provider supports a given exchange
    func supports(exchangeId: String) -> Bool
    
    /// Connect to an exchange/wallet
    /// - Parameters:
    ///   - exchangeId: The exchange or wallet ID
    ///   - credentials: Connection-specific credentials (API keys, OAuth tokens, wallet address)
    /// - Returns: Connection result with account info and initial balances
    func connect(exchangeId: String, credentials: ConnectionCredentials) async throws -> ConnectionResult
    
    /// Disconnect from an exchange/wallet
    func disconnect(accountId: String) async throws
    
    /// Fetch current balances for a connected account
    func fetchBalances(accountId: String) async throws -> [PortfolioBalance]
    
    /// Validate credentials without fully connecting
    func validateCredentials(exchangeId: String, credentials: ConnectionCredentials) async throws -> Bool
}

// MARK: - Connection Credentials

/// Credentials for different connection types
enum ConnectionCredentials {
    case oauth(accessToken: String, refreshToken: String?, expiresAt: Date?)
    case apiKey(key: String, secret: String, passphrase: String?)
    case walletAddress(address: String, chain: String)
    case threeCommas(apiKey: String, secret: String)
    
    var type: ConnectionType {
        switch self {
        case .oauth: return .oauth
        case .apiKey: return .apiKey
        case .walletAddress: return .walletAddress
        case .threeCommas: return .threeCommas
        }
    }
}

// MARK: - Connection Manager Extension

extension ConnectedAccountsManager {
    
    /// Get the appropriate connection provider for an exchange
    func provider(for exchangeId: String) -> ConnectionProvider? {
        let connectionType = ExchangeRegistry.connectionType(for: exchangeId)
        return provider(for: connectionType)
    }
    
    /// Get provider by connection type
    /// Returns the real implementation classes, not the stubs.
    func provider(for type: ConnectionType) -> ConnectionProvider? {
        switch type {
        case .oauth:
            return OAuthConnectionProviderImpl.shared
        case .apiKey:
            return DirectAPIConnectionProviderImpl.shared
        case .walletAddress:
            return BlockchainConnectionProviderImpl.shared
        case .threeCommas:
            return ThreeCommasConnectionProvider.shared
        }
    }
}

// MARK: - 3Commas Connection Provider (wraps ThreeCommasAPI)
class ThreeCommasConnectionProvider: ConnectionProvider {
    static let shared = ThreeCommasConnectionProvider()
    
    var connectionType: ConnectionType { .threeCommas }
    var supportedExchanges: [String] { [] } // 3Commas handles its own exchange list
    
    func supports(exchangeId: String) -> Bool {
        // 3Commas supports many exchanges through their platform
        return true
    }
    
    func connect(exchangeId: String, credentials: ConnectionCredentials) async throws -> ConnectionResult {
        guard case .threeCommas(let apiKey, let secret) = credentials else {
            throw ConnectionError.invalidCredentials
        }
        
        let success = try await ThreeCommasAPI.shared.connect(apiKey: apiKey, apiSecret: secret)
        
        if success {
            return ConnectionResult(
                success: true,
                accountId: "3commas-\(UUID().uuidString.prefix(8))",
                accountName: "3Commas",
                error: nil,
                balances: nil
            )
        } else {
            throw ConnectionError.invalidCredentials
        }
    }
    
    func disconnect(accountId: String) async throws {
        // Clear stored 3Commas credentials from Keychain
        try? KeychainHelper.shared.delete(service: "CryptoSage.3Commas", account: "api_key")
        try? KeychainHelper.shared.delete(service: "CryptoSage.3Commas", account: "api_secret")
    }
    
    func fetchBalances(accountId: String) async throws -> [PortfolioBalance] {
        let accounts = try await ThreeCommasAPI.shared.listAccounts()
        guard let firstAccount = accounts.first else { return [] }
        
        let balances = try await ThreeCommasAPI.shared.loadAccountBalances(accountId: firstAccount.id)
        
        return balances.map { balance in
            PortfolioBalance(
                symbol: balance.currency,
                name: balance.currency,
                balance: balance.balance
            )
        }
    }
    
    func validateCredentials(exchangeId: String, credentials: ConnectionCredentials) async throws -> Bool {
        guard case .threeCommas(let apiKey, let secret) = credentials else {
            return false
        }
        return try await ThreeCommasAPI.shared.connect(apiKey: apiKey, apiSecret: secret)
    }
}
