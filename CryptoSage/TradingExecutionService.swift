//
//  TradingExecutionService.swift
//  CryptoSage
//
//  THIRD-PARTY CLIENT - Direct Exchange API Integration for Spot Trading
//  ======================================================================
//  This service connects DIRECTLY to exchange APIs from the user's device.
//  
//  Security Model:
//  - API keys stored locally in Apple's Secure Keychain (never transmitted)
//  - All requests go directly from device → exchange (no backend server)
//  - HMAC signatures computed locally on-device
//  - Supports read-only or full trading API permissions
//  
//  Supported Exchanges (Spot Trading):
//  - Binance / Binance US (api.binance.com / api.binance.us)
//  - Coinbase Advanced Trade (api.coinbase.com)
//  - Kraken (api.kraken.com)
//  - KuCoin (api.kucoin.com)
//

import Foundation
import CommonCrypto

// MARK: - Order Models

/// Result of submitting an order
public struct OrderResult: Codable {
    public let success: Bool
    public let orderId: String?
    public let status: OrderStatus?
    public let filledQuantity: Double?
    public let averagePrice: Double?
    public let errorMessage: String?
    public let exchange: String
    public let timestamp: Date
    
    public init(
        success: Bool,
        orderId: String? = nil,
        status: OrderStatus? = nil,
        filledQuantity: Double? = nil,
        averagePrice: Double? = nil,
        errorMessage: String? = nil,
        exchange: String,
        timestamp: Date = Date()
    ) {
        self.success = success
        self.orderId = orderId
        self.status = status
        self.filledQuantity = filledQuantity
        self.averagePrice = averagePrice
        self.errorMessage = errorMessage
        self.exchange = exchange
        self.timestamp = timestamp
    }
}

/// Order status
public enum OrderStatus: String, Codable {
    case new = "NEW"
    case partiallyFilled = "PARTIALLY_FILLED"
    case filled = "FILLED"
    case canceled = "CANCELED"
    case rejected = "REJECTED"
    case expired = "EXPIRED"
    case pending = "PENDING"
}

/// Account balance for a specific asset
public struct AssetBalance: Codable, Identifiable {
    public var id: String { asset }
    public let asset: String
    public let free: Double
    public let locked: Double
    
    public var total: Double { free + locked }
    
    public init(asset: String, free: Double, locked: Double) {
        self.asset = asset
        self.free = free
        self.locked = locked
    }
}

/// Open/pending order on an exchange
public struct OpenOrder: Codable, Identifiable, Equatable {
    public let id: String               // Order ID from exchange
    public let exchange: TradingExchange
    public let symbol: String           // e.g., "BTCUSDT"
    public let side: TradeSide
    public let type: OrderType
    public let price: Double
    public let quantity: Double
    public let filledQuantity: Double
    public let status: OrderStatus
    public let createdAt: Date
    
    /// Remaining quantity to be filled
    public var remainingQuantity: Double { quantity - filledQuantity }
    
    /// Percentage of order that has been filled (0-100)
    public var filledPercent: Double { 
        guard quantity > 0 else { return 0 }
        return (filledQuantity / quantity) * 100 
    }
    
    /// Display-friendly base asset (e.g., "BTC" from "BTCUSDT")
    public var baseAsset: String {
        // Remove common quote currencies
        let quotes = ["USDT", "USD", "USDC", "BUSD", "EUR", "GBP", "BTC", "ETH"]
        var base = symbol.uppercased()
        for quote in quotes {
            if base.hasSuffix(quote) {
                base = String(base.dropLast(quote.count))
                break
            }
        }
        return base
    }
    
    /// Display-friendly quote asset (e.g., "USDT" from "BTCUSDT")
    public var quoteAsset: String {
        let quotes = ["USDT", "USD", "USDC", "BUSD", "EUR", "GBP"]
        let upper = symbol.uppercased()
        for quote in quotes {
            if upper.hasSuffix(quote) {
                return quote
            }
        }
        // Default fallback
        return "USD"
    }
    
    /// Total value of the order in quote currency
    public var totalValue: Double { price * quantity }
    
    /// Remaining value to be filled
    public var remainingValue: Double { price * remainingQuantity }
    
    public init(
        id: String,
        exchange: TradingExchange,
        symbol: String,
        side: TradeSide,
        type: OrderType,
        price: Double,
        quantity: Double,
        filledQuantity: Double = 0,
        status: OrderStatus = .new,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.exchange = exchange
        self.symbol = symbol
        self.side = side
        self.type = type
        self.price = price
        self.quantity = quantity
        self.filledQuantity = filledQuantity
        self.status = status
        self.createdAt = createdAt
    }
    
    public static func == (lhs: OpenOrder, rhs: OpenOrder) -> Bool {
        lhs.id == rhs.id && lhs.exchange == rhs.exchange
    }
}

/// Result of canceling an order
public struct CancelOrderResult {
    public let success: Bool
    public let orderId: String
    public let exchange: TradingExchange
    public let errorMessage: String?
    
    public init(success: Bool, orderId: String, exchange: TradingExchange, errorMessage: String? = nil) {
        self.success = success
        self.orderId = orderId
        self.exchange = exchange
        self.errorMessage = errorMessage
    }
}

/// Trading credentials for an exchange
public struct TradingCredentials: Codable {
    public let exchange: TradingExchange
    public let apiKey: String
    public let apiSecret: String
    public let passphrase: String?
    
    public init(exchange: TradingExchange, apiKey: String, apiSecret: String, passphrase: String? = nil) {
        self.exchange = exchange
        self.apiKey = apiKey
        self.apiSecret = apiSecret
        self.passphrase = passphrase
    }
}

/// Supported trading exchanges
public enum TradingExchange: String, Codable, CaseIterable, Identifiable {
    case binance = "binance"
    case binanceUS = "binance_us"
    case coinbase = "coinbase"
    case kraken = "kraken"
    case kucoin = "kucoin"
    case bybit = "bybit"
    case okx = "okx"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .binance: return "Binance"
        case .binanceUS: return "Binance US"
        case .coinbase: return "Coinbase"
        case .kraken: return "Kraken"
        case .kucoin: return "KuCoin"
        case .bybit: return "Bybit"
        case .okx: return "OKX"
        }
    }
    
    public var restBaseURL: URL {
        switch self {
        case .binance: return URL(string: "https://api.binance.com")!
        // BINANCE-US-FIX: Binance.US is shut down - disabled for trading
        case .binanceUS: return URL(string: "https://api4.binance.com")!
        case .coinbase: return URL(string: "https://api.exchange.coinbase.com")!
        case .kraken: return URL(string: "https://api.kraken.com")!
        case .kucoin: return URL(string: "https://api.kucoin.com")!
        case .bybit: return URL(string: "https://api.bybit.com")!
        case .okx: return URL(string: "https://www.okx.com")!
        }
    }
    
    public var requiresPassphrase: Bool {
        switch self {
        case .coinbase, .kucoin, .okx: return true
        default: return false
        }
    }
    
    /// Whether this exchange supports futures/derivatives trading
    public var supportsFutures: Bool {
        switch self {
        case .binance, .kucoin, .bybit, .okx: return true
        case .coinbase: return true  // Coinbase INTX perpetual-style futures (US eligible)
        case .binanceUS, .kraken: return false
        }
    }
    
    /// Description of futures support
    public var futuresDescription: String? {
        switch self {
        case .binance: return "USDT Perpetuals, up to 125x leverage"
        case .kucoin: return "USDT Perpetuals, up to 100x leverage"
        case .bybit: return "USDT Perpetuals, up to 100x leverage"
        case .okx: return "USDT Perpetuals, up to 125x leverage"
        case .coinbase: return "INTX Perpetual-Style Futures, up to 50x leverage (US eligible)"
        default: return nil
        }
    }
}

// MARK: - Trading Credentials Manager

/// Manages trading API credentials securely in Keychain
public final class TradingCredentialsManager {
    public static let shared = TradingCredentialsManager()
    private init() {}
    
    private let keychainService = "CryptoSage.Trading"
    
    // MARK: - Public API
    
    /// Save trading credentials for an exchange
    public func saveCredentials(_ credentials: TradingCredentials) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(credentials)
        let dataString = data.base64EncodedString()
        try KeychainHelper.shared.save(dataString, service: keychainService, account: credentials.exchange.rawValue)
    }
    
    /// Load trading credentials for an exchange
    public func loadCredentials(for exchange: TradingExchange) -> TradingCredentials? {
        do {
            let dataString = try KeychainHelper.shared.read(service: keychainService, account: exchange.rawValue)
            guard let data = Data(base64Encoded: dataString) else { return nil }
            let decoder = JSONDecoder()
            return try decoder.decode(TradingCredentials.self, from: data)
        } catch {
            return nil
        }
    }
    
    /// Delete trading credentials for an exchange
    public func deleteCredentials(for exchange: TradingExchange) throws {
        try KeychainHelper.shared.delete(service: keychainService, account: exchange.rawValue)
    }
    
    /// Check if credentials exist for an exchange
    public func hasCredentials(for exchange: TradingExchange) -> Bool {
        return loadCredentials(for: exchange) != nil
    }
    
    /// Check if demo mode is enabled (uses thread-safe static accessor from DemoModeManager)
    private var isDemoMode: Bool {
        DemoModeManager.isEnabled
    }
    
    /// Get all exchanges with saved credentials (or mock exchanges in demo mode)
    public func getConnectedExchanges() -> [TradingExchange] {
        // Return mock exchanges in demo mode
        if isDemoMode {
            return [.binance, .coinbase]
        }
        return TradingExchange.allCases.filter { hasCredentials(for: $0) }
    }
    
    /// Get the default/preferred exchange for trading
    public var defaultExchange: TradingExchange? {
        let connected = getConnectedExchanges()
        // Prefer US exchange for US users
        if ComplianceManager.shared.isUSUser {
            if connected.contains(.binanceUS) { return .binanceUS }
            if connected.contains(.coinbase) { return .coinbase }
        }
        return connected.first
    }
}

// MARK: - Trading Execution Service

/// Main service for executing trades on exchanges
public actor TradingExecutionService {
    public static let shared = TradingExecutionService()
    private init() {}
    
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()
    
    // MARK: - Paper Trading Check
    
    /// Check if paper trading is enabled (thread-safe)
    private var isPaperTradingEnabled: Bool {
        PaperTradingManager.isEnabled
    }
    
    // MARK: - Public API
    
    /// Submit a market order (or paper trade if paper trading is enabled)
    public func submitMarketOrder(
        exchange: TradingExchange,
        symbol: String,
        side: TradeSide,
        quantity: Double
    ) async throws -> OrderResult {
        // Intercept for paper trading
        if isPaperTradingEnabled {
            return await submitPaperTrade(symbol: symbol, side: side, quantity: quantity, orderType: "MARKET")
        }
        
        // SAFETY: Block live trading at service level when disabled
        guard AppConfig.liveTradingEnabled else {
            return OrderResult(
                success: false,
                errorMessage: AppConfig.liveTradingDisabledMessage,
                exchange: exchange.rawValue
            )
        }
        
        guard TradingRiskAcknowledgmentManager.shared.canTrade else {
            return OrderResult(
                success: false,
                errorMessage: "Please accept Terms and acknowledge trading risks before live trading.",
                exchange: exchange.rawValue
            )
        }
        
        guard let credentials = TradingCredentialsManager.shared.loadCredentials(for: exchange) else {
            return OrderResult(
                success: false,
                errorMessage: "No credentials found for \(exchange.displayName). Please add your API keys in Settings.",
                exchange: exchange.rawValue
            )
        }
        
        switch exchange {
        case .binance, .binanceUS:
            return try await submitBinanceOrder(
                credentials: credentials,
                symbol: symbol,
                side: side,
                type: .market,
                quantity: quantity,
                price: nil
            )
        case .coinbase:
            return try await submitCoinbaseOrder(
                credentials: credentials,
                symbol: symbol,
                side: side,
                type: .market,
                quantity: quantity,
                price: nil
            )
        case .kraken:
            return try await submitKrakenOrder(
                credentials: credentials,
                symbol: symbol,
                side: side,
                type: .market,
                quantity: quantity,
                price: nil
            )
        case .kucoin:
            return try await submitKuCoinOrder(
                credentials: credentials,
                symbol: symbol,
                side: side,
                type: .market,
                quantity: quantity,
                price: nil
            )
        case .bybit:
            return try await submitBybitOrder(
                credentials: credentials,
                symbol: symbol,
                side: side,
                type: .market,
                quantity: quantity,
                price: nil
            )
        case .okx:
            return try await submitOKXOrder(
                credentials: credentials,
                symbol: symbol,
                side: side,
                type: .market,
                quantity: quantity,
                price: nil
            )
        }
    }
    
    /// Submit a limit order (or paper trade if paper trading is enabled)
    public func submitLimitOrder(
        exchange: TradingExchange,
        symbol: String,
        side: TradeSide,
        quantity: Double,
        price: Double
    ) async throws -> OrderResult {
        // Intercept for paper trading
        if isPaperTradingEnabled {
            return await submitPaperTrade(symbol: symbol, side: side, quantity: quantity, price: price, orderType: "LIMIT")
        }
        
        // SAFETY: Block live trading at service level when disabled
        guard AppConfig.liveTradingEnabled else {
            return OrderResult(
                success: false,
                errorMessage: AppConfig.liveTradingDisabledMessage,
                exchange: exchange.rawValue
            )
        }
        
        guard TradingRiskAcknowledgmentManager.shared.canTrade else {
            return OrderResult(
                success: false,
                errorMessage: "Please accept Terms and acknowledge trading risks before live trading.",
                exchange: exchange.rawValue
            )
        }
        
        guard let credentials = TradingCredentialsManager.shared.loadCredentials(for: exchange) else {
            return OrderResult(
                success: false,
                errorMessage: "No credentials found for \(exchange.displayName). Please add your API keys in Settings.",
                exchange: exchange.rawValue
            )
        }
        
        switch exchange {
        case .binance, .binanceUS:
            return try await submitBinanceOrder(
                credentials: credentials,
                symbol: symbol,
                side: side,
                type: .limit,
                quantity: quantity,
                price: price
            )
        case .coinbase:
            return try await submitCoinbaseOrder(
                credentials: credentials,
                symbol: symbol,
                side: side,
                type: .limit,
                quantity: quantity,
                price: price
            )
        case .kraken:
            return try await submitKrakenOrder(
                credentials: credentials,
                symbol: symbol,
                side: side,
                type: .limit,
                quantity: quantity,
                price: price
            )
        case .kucoin:
            return try await submitKuCoinOrder(
                credentials: credentials,
                symbol: symbol,
                side: side,
                type: .limit,
                quantity: quantity,
                price: price
            )
        case .bybit:
            return try await submitBybitOrder(
                credentials: credentials,
                symbol: symbol,
                side: side,
                type: .limit,
                quantity: quantity,
                price: price
            )
        case .okx:
            return try await submitOKXOrder(
                credentials: credentials,
                symbol: symbol,
                side: side,
                type: .limit,
                quantity: quantity,
                price: price
            )
        }
    }
    
    /// Submit a stop order (triggers at stop price, executes as market)
    /// - Parameters:
    ///   - exchange: The exchange to submit to
    ///   - symbol: Trading pair symbol (e.g., "BTCUSDT")
    ///   - side: Buy or sell
    ///   - quantity: Amount to trade
    ///   - stopPrice: Price at which the stop order triggers
    public func submitStopOrder(
        exchange: TradingExchange,
        symbol: String,
        side: TradeSide,
        quantity: Double,
        stopPrice: Double
    ) async throws -> OrderResult {
        // Intercept for paper trading
        if isPaperTradingEnabled {
            return await submitPaperTrade(symbol: symbol, side: side, quantity: quantity, price: stopPrice, orderType: "STOP")
        }
        
        // SAFETY: Block live trading at service level when disabled
        guard AppConfig.liveTradingEnabled else {
            return OrderResult(
                success: false,
                errorMessage: AppConfig.liveTradingDisabledMessage,
                exchange: exchange.rawValue
            )
        }
        
        guard TradingRiskAcknowledgmentManager.shared.canTrade else {
            return OrderResult(
                success: false,
                errorMessage: "Please accept Terms and acknowledge trading risks before live trading.",
                exchange: exchange.rawValue
            )
        }
        
        guard let credentials = TradingCredentialsManager.shared.loadCredentials(for: exchange) else {
            return OrderResult(
                success: false,
                errorMessage: "No credentials found for \(exchange.displayName). Please add your API keys in Settings.",
                exchange: exchange.rawValue
            )
        }
        
        switch exchange {
        case .binance, .binanceUS:
            return try await submitBinanceStopOrder(
                credentials: credentials,
                symbol: symbol,
                side: side,
                quantity: quantity,
                stopPrice: stopPrice,
                limitPrice: nil
            )
        case .coinbase:
            return try await submitCoinbaseStopOrder(
                credentials: credentials,
                symbol: symbol,
                side: side,
                quantity: quantity,
                stopPrice: stopPrice,
                limitPrice: nil
            )
        case .kraken:
            return try await submitKrakenStopOrder(
                credentials: credentials,
                symbol: symbol,
                side: side,
                quantity: quantity,
                stopPrice: stopPrice,
                limitPrice: nil
            )
        case .kucoin:
            return try await submitKuCoinStopOrder(
                credentials: credentials,
                symbol: symbol,
                side: side,
                quantity: quantity,
                stopPrice: stopPrice,
                limitPrice: nil
            )
        case .bybit:
            return try await submitBybitStopOrder(
                credentials: credentials,
                symbol: symbol,
                side: side,
                quantity: quantity,
                stopPrice: stopPrice,
                limitPrice: nil
            )
        case .okx:
            return try await submitOKXStopOrder(
                credentials: credentials,
                symbol: symbol,
                side: side,
                quantity: quantity,
                stopPrice: stopPrice,
                limitPrice: nil
            )
        }
    }
    
    /// Submit a stop-limit order (triggers at stop price, executes at limit price)
    /// - Parameters:
    ///   - exchange: The exchange to submit to
    ///   - symbol: Trading pair symbol (e.g., "BTCUSDT")
    ///   - side: Buy or sell
    ///   - quantity: Amount to trade
    ///   - stopPrice: Price at which the stop order triggers
    ///   - limitPrice: Price at which to place the limit order once triggered
    public func submitStopLimitOrder(
        exchange: TradingExchange,
        symbol: String,
        side: TradeSide,
        quantity: Double,
        stopPrice: Double,
        limitPrice: Double
    ) async throws -> OrderResult {
        // Intercept for paper trading
        if isPaperTradingEnabled {
            return await submitPaperTrade(symbol: symbol, side: side, quantity: quantity, price: limitPrice, orderType: "STOP_LIMIT")
        }
        
        // SAFETY: Block live trading at service level when disabled
        guard AppConfig.liveTradingEnabled else {
            return OrderResult(
                success: false,
                errorMessage: AppConfig.liveTradingDisabledMessage,
                exchange: exchange.rawValue
            )
        }
        
        guard TradingRiskAcknowledgmentManager.shared.canTrade else {
            return OrderResult(
                success: false,
                errorMessage: "Please accept Terms and acknowledge trading risks before live trading.",
                exchange: exchange.rawValue
            )
        }
        
        guard let credentials = TradingCredentialsManager.shared.loadCredentials(for: exchange) else {
            return OrderResult(
                success: false,
                errorMessage: "No credentials found for \(exchange.displayName). Please add your API keys in Settings.",
                exchange: exchange.rawValue
            )
        }
        
        switch exchange {
        case .binance, .binanceUS:
            return try await submitBinanceStopOrder(
                credentials: credentials,
                symbol: symbol,
                side: side,
                quantity: quantity,
                stopPrice: stopPrice,
                limitPrice: limitPrice
            )
        case .coinbase:
            return try await submitCoinbaseStopOrder(
                credentials: credentials,
                symbol: symbol,
                side: side,
                quantity: quantity,
                stopPrice: stopPrice,
                limitPrice: limitPrice
            )
        case .kraken:
            return try await submitKrakenStopOrder(
                credentials: credentials,
                symbol: symbol,
                side: side,
                quantity: quantity,
                stopPrice: stopPrice,
                limitPrice: limitPrice
            )
        case .kucoin:
            return try await submitKuCoinStopOrder(
                credentials: credentials,
                symbol: symbol,
                side: side,
                quantity: quantity,
                stopPrice: stopPrice,
                limitPrice: limitPrice
            )
        case .bybit:
            return try await submitBybitStopOrder(
                credentials: credentials,
                symbol: symbol,
                side: side,
                quantity: quantity,
                stopPrice: stopPrice,
                limitPrice: limitPrice
            )
        case .okx:
            return try await submitOKXStopOrder(
                credentials: credentials,
                symbol: symbol,
                side: side,
                quantity: quantity,
                stopPrice: stopPrice,
                limitPrice: limitPrice
            )
        }
    }
    
    /// Fetch account balances
    public func fetchBalances(exchange: TradingExchange) async throws -> [AssetBalance] {
        guard let credentials = TradingCredentialsManager.shared.loadCredentials(for: exchange) else {
            throw TradingError.noCredentials(exchange: exchange.displayName)
        }
        
        switch exchange {
        case .binance, .binanceUS:
            return try await fetchBinanceBalances(credentials: credentials)
        case .coinbase:
            return try await fetchCoinbaseBalances(credentials: credentials)
        case .kraken:
            return try await fetchKrakenBalances(credentials: credentials)
        case .kucoin:
            return try await fetchKuCoinBalances(credentials: credentials)
        case .bybit:
            return try await fetchBybitBalances(credentials: credentials)
        case .okx:
            return try await fetchOKXBalances(credentials: credentials)
        }
    }
    
    /// Fetch balance for a specific asset
    public func fetchBalance(exchange: TradingExchange, asset: String) async throws -> AssetBalance? {
        let balances = try await fetchBalances(exchange: exchange)
        return balances.first { $0.asset.uppercased() == asset.uppercased() }
    }
    
    /// Test API connection
    public func testConnection(exchange: TradingExchange) async throws -> Bool {
        guard let credentials = TradingCredentialsManager.shared.loadCredentials(for: exchange) else {
            return false
        }
        
        switch exchange {
        case .binance, .binanceUS:
            return try await testBinanceConnection(credentials: credentials)
        case .coinbase:
            return try await testCoinbaseConnection(credentials: credentials)
        case .kraken:
            return try await testKrakenConnection(credentials: credentials)
        case .kucoin:
            return try await testKuCoinConnection(credentials: credentials)
        case .bybit:
            return try await testBybitConnection(credentials: credentials)
        case .okx:
            return try await testOKXConnection(credentials: credentials)
        }
    }
    
    // MARK: - Open Orders API
    
    /// Fetch all open orders for an exchange, optionally filtered by symbol
    public func fetchOpenOrders(exchange: TradingExchange, symbol: String? = nil) async throws -> [OpenOrder] {
        guard let credentials = TradingCredentialsManager.shared.loadCredentials(for: exchange) else {
            throw TradingError.noCredentials(exchange: exchange.displayName)
        }
        
        switch exchange {
        case .binance, .binanceUS:
            return try await fetchBinanceOpenOrders(credentials: credentials, symbol: symbol)
        case .coinbase:
            return try await fetchCoinbaseOpenOrders(credentials: credentials, symbol: symbol)
        case .kraken:
            return try await fetchKrakenOpenOrders(credentials: credentials, symbol: symbol)
        case .kucoin:
            return try await fetchKuCoinOpenOrders(credentials: credentials, symbol: symbol)
        case .bybit:
            return try await fetchBybitOpenOrders(credentials: credentials, symbol: symbol)
        case .okx:
            return try await fetchOKXOpenOrders(credentials: credentials, symbol: symbol)
        }
    }
    
    /// Fetch open orders from all connected exchanges
    public func fetchAllOpenOrders() async -> [OpenOrder] {
        let connectedExchanges = TradingCredentialsManager.shared.getConnectedExchanges()
        var allOrders: [OpenOrder] = []
        
        await withTaskGroup(of: [OpenOrder].self) { group in
            for exchange in connectedExchanges {
                group.addTask {
                    do {
                        return try await self.fetchOpenOrders(exchange: exchange)
                    } catch {
                        print("[TradingExecutionService] Failed to fetch orders from \(exchange.displayName): \(error)")
                        return []
                    }
                }
            }
            
            for await orders in group {
                allOrders.append(contentsOf: orders)
            }
        }
        
        // Sort by creation date, newest first
        return allOrders.sorted { $0.createdAt > $1.createdAt }
    }
    
    /// Cancel a specific order
    public func cancelOrder(exchange: TradingExchange, orderId: String, symbol: String) async throws -> CancelOrderResult {
        guard let credentials = TradingCredentialsManager.shared.loadCredentials(for: exchange) else {
            return CancelOrderResult(
                success: false,
                orderId: orderId,
                exchange: exchange,
                errorMessage: "No credentials found for \(exchange.displayName)"
            )
        }
        
        switch exchange {
        case .binance, .binanceUS:
            return try await cancelBinanceOrder(credentials: credentials, orderId: orderId, symbol: symbol)
        case .coinbase:
            return try await cancelCoinbaseOrder(credentials: credentials, orderId: orderId)
        case .kraken:
            return try await cancelKrakenOrder(credentials: credentials, orderId: orderId)
        case .kucoin:
            return try await cancelKuCoinOrder(credentials: credentials, orderId: orderId)
        case .bybit:
            return try await cancelBybitOrder(credentials: credentials, orderId: orderId, symbol: symbol)
        case .okx:
            return try await cancelOKXOrder(credentials: credentials, orderId: orderId, symbol: symbol)
        }
    }
    
    /// Cancel all open orders for a symbol on an exchange
    public func cancelAllOrders(exchange: TradingExchange, symbol: String) async throws -> [CancelOrderResult] {
        let openOrders = try await fetchOpenOrders(exchange: exchange, symbol: symbol)
        var results: [CancelOrderResult] = []
        
        for order in openOrders {
            let result = try await cancelOrder(exchange: exchange, orderId: order.id, symbol: order.symbol)
            results.append(result)
        }
        
        return results
    }
    
    // MARK: - Paper Trading Implementation
    
    /// Submit a paper trade (simulated trade with virtual money)
    /// This method executes trades using the PaperTradingManager instead of real exchanges.
    /// For market orders, if no price is provided, it will attempt to fetch a live price.
    @MainActor
    private func submitPaperTrade(
        symbol: String,
        side: TradeSide,
        quantity: Double,
        price: Double? = nil,
        orderType: String = "MARKET"
    ) -> OrderResult {
        var tradePrice = price ?? 0
        
        // If no price provided (market orders routed here), fetch one from live data
        if tradePrice <= 0 || !tradePrice.isFinite {
            // Extract base symbol from pair (e.g., "BTCUSDT" -> "BTC")
            let baseSymbol = PaperTradingManager.shared.parseSymbol(symbol).base
            
            // Try bestPrice(forSymbol:) which checks all sources
            if let freshPrice = MarketViewModel.shared.bestPrice(forSymbol: baseSymbol),
               freshPrice > 0, freshPrice.isFinite {
                tradePrice = freshPrice
            }
            // Fallback: check allCoins
            else if let coin = MarketViewModel.shared.allCoins.first(where: {
                $0.symbol.uppercased() == baseSymbol.uppercased()
            }), let p = coin.priceUsd, p > 0, p.isFinite {
                tradePrice = p
            }
        }
        
        guard tradePrice > 0, tradePrice.isFinite else {
            return OrderResult(
                success: false,
                errorMessage: "Unable to determine current market price for \(symbol). Please ensure you have an active network connection and try again.",
                exchange: "Paper Trading"
            )
        }
        
        return PaperTradingManager.shared.executePaperTrade(
            symbol: symbol,
            side: side,
            quantity: quantity,
            price: tradePrice,
            orderType: orderType
        )
    }
    
    // MARK: - Binance Implementation
    
    private func submitBinanceOrder(
        credentials: TradingCredentials,
        symbol: String,
        side: TradeSide,
        type: OrderType,
        quantity: Double,
        price: Double?
    ) async throws -> OrderResult {
        let pair = normalizeBinancePair(symbol)
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        
        // SECURITY: Generate a unique client order ID to prevent double-execution.
        // If a network timeout causes us to retry or the user retries, Binance will
        // reject the duplicate order instead of executing it twice.
        let clientOrderId = "CS\(timestamp)\(Int.random(in: 1000...9999))"
        
        var params: [(String, String)] = [
            ("symbol", pair),
            ("side", side.rawValue),
            ("type", type.rawValue),
            ("quantity", formatQuantity(quantity)),
            ("timestamp", String(timestamp)),
            // SECURITY: recvWindow limits how long after timestamp the request is valid.
            // Prevents replay attacks — request rejected if received >5s after signing.
            ("recvWindow", "5000"),
            // SECURITY: newClientOrderId prevents duplicate order execution on network retry.
            ("newClientOrderId", clientOrderId)
        ]
        
        if type == .limit, let price = price {
            params.append(("price", formatPrice(price)))
            params.append(("timeInForce", "GTC"))
        }
        
        let queryString = params.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        let signature = hmacSHA256(message: queryString, key: credentials.apiSecret)
        let signedQuery = queryString + "&signature=\(signature)"
        
        let url = credentials.exchange.restBaseURL.appendingPathComponent("/api/v3/order")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = signedQuery.data(using: .utf8)
        request.setValue(credentials.apiKey, forHTTPHeaderField: "X-MBX-APIKEY")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return OrderResult(success: false, errorMessage: "Invalid response", exchange: credentials.exchange.rawValue)
        }
        
        if httpResponse.statusCode == 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let orderId = json["orderId"] as? Int64
                let status = json["status"] as? String
                let executedQty = (json["executedQty"] as? String).flatMap { Double($0) }
                let avgPrice = (json["cummulativeQuoteQty"] as? String).flatMap { Double($0) }
                
                // Calculate average price from cumulative quote qty / executed qty
                let calculatedAvgPrice: Double? = {
                    guard let cumQuoteQty = avgPrice, let execQty = executedQty, execQty > 0 else {
                        return nil
                    }
                    return cumQuoteQty / execQty
                }()
                
                return OrderResult(
                    success: true,
                    orderId: orderId.map { String($0) },
                    status: OrderStatus(rawValue: status ?? "NEW"),
                    filledQuantity: executedQty,
                    averagePrice: calculatedAvgPrice,
                    exchange: credentials.exchange.rawValue
                )
            }
        }
        
        // Parse error
        let errorMsg = parseErrorMessage(data: data, statusCode: httpResponse.statusCode)
        return OrderResult(success: false, errorMessage: errorMsg, exchange: credentials.exchange.rawValue)
    }
    
    private func fetchBinanceBalances(credentials: TradingCredentials) async throws -> [AssetBalance] {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let queryString = "timestamp=\(timestamp)"
        let signature = hmacSHA256(message: queryString, key: credentials.apiSecret)
        let signedQuery = queryString + "&signature=\(signature)"
        
        var components = URLComponents(url: credentials.exchange.restBaseURL.appendingPathComponent("/api/v3/account"), resolvingAgainstBaseURL: false)!
        components.query = signedQuery
        
        guard let url = components.url else {
            throw TradingError.apiError(message: "Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(credentials.apiKey, forHTTPHeaderField: "X-MBX-APIKEY")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TradingError.apiError(message: "Failed to fetch balances")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let balances = json["balances"] as? [[String: Any]] else {
            throw TradingError.parseError
        }
        
        return balances.compactMap { item -> AssetBalance? in
            guard let asset = item["asset"] as? String,
                  let freeStr = item["free"] as? String,
                  let lockedStr = item["locked"] as? String,
                  let free = Double(freeStr),
                  let locked = Double(lockedStr),
                  (free + locked) > 0 else {
                return nil
            }
            return AssetBalance(asset: asset, free: free, locked: locked)
        }
    }
    
    private func testBinanceConnection(credentials: TradingCredentials) async throws -> Bool {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let queryString = "timestamp=\(timestamp)"
        let signature = hmacSHA256(message: queryString, key: credentials.apiSecret)
        let signedQuery = queryString + "&signature=\(signature)"
        
        var components = URLComponents(url: credentials.exchange.restBaseURL.appendingPathComponent("/api/v3/account"), resolvingAgainstBaseURL: false)!
        components.query = signedQuery
        
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue(credentials.apiKey, forHTTPHeaderField: "X-MBX-APIKEY")
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else { return false }
        return httpResponse.statusCode == 200
    }
    
    /// Fetch open orders from Binance
    private func fetchBinanceOpenOrders(credentials: TradingCredentials, symbol: String?) async throws -> [OpenOrder] {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        var queryParams = "timestamp=\(timestamp)"
        
        if let symbol = symbol {
            let pair = normalizeBinancePair(symbol)
            queryParams = "symbol=\(pair)&\(queryParams)"
        }
        
        let signature = hmacSHA256(message: queryParams, key: credentials.apiSecret)
        let signedQuery = queryParams + "&signature=\(signature)"
        
        var components = URLComponents(url: credentials.exchange.restBaseURL.appendingPathComponent("/api/v3/openOrders"), resolvingAgainstBaseURL: false)!
        components.query = signedQuery
        
        guard let url = components.url else {
            throw TradingError.apiError(message: "Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(credentials.apiKey, forHTTPHeaderField: "X-MBX-APIKEY")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorMsg = parseErrorMessage(data: data, statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
            throw TradingError.apiError(message: errorMsg)
        }
        
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw TradingError.parseError
        }
        
        return jsonArray.compactMap { item -> OpenOrder? in
            guard let orderId = item["orderId"] as? Int64,
                  let symbolStr = item["symbol"] as? String,
                  let sideStr = item["side"] as? String,
                  let typeStr = item["type"] as? String,
                  let priceStr = item["price"] as? String,
                  let origQtyStr = item["origQty"] as? String,
                  let executedQtyStr = item["executedQty"] as? String,
                  let statusStr = item["status"] as? String,
                  let timeMs = item["time"] as? Int64 else {
                return nil
            }
            
            return OpenOrder(
                id: String(orderId),
                exchange: credentials.exchange,
                symbol: symbolStr,
                side: TradeSide(rawValue: sideStr) ?? .buy,
                type: OrderType(rawValue: typeStr) ?? .limit,
                price: Double(priceStr) ?? 0,
                quantity: Double(origQtyStr) ?? 0,
                filledQuantity: Double(executedQtyStr) ?? 0,
                status: OrderStatus(rawValue: statusStr) ?? .new,
                createdAt: Date(timeIntervalSince1970: Double(timeMs) / 1000)
            )
        }
    }
    
    /// Cancel an order on Binance
    private func cancelBinanceOrder(credentials: TradingCredentials, orderId: String, symbol: String) async throws -> CancelOrderResult {
        let pair = normalizeBinancePair(symbol)
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let queryParams = "symbol=\(pair)&orderId=\(orderId)&timestamp=\(timestamp)"
        let signature = hmacSHA256(message: queryParams, key: credentials.apiSecret)
        let signedQuery = queryParams + "&signature=\(signature)"
        
        let url = credentials.exchange.restBaseURL.appendingPathComponent("/api/v3/order")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.httpBody = signedQuery.data(using: .utf8)
        request.setValue(credentials.apiKey, forHTTPHeaderField: "X-MBX-APIKEY")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return CancelOrderResult(success: false, orderId: orderId, exchange: credentials.exchange, errorMessage: "Invalid response")
        }
        
        if httpResponse.statusCode == 200 {
            return CancelOrderResult(success: true, orderId: orderId, exchange: credentials.exchange)
        }
        
        let errorMsg = parseErrorMessage(data: data, statusCode: httpResponse.statusCode)
        return CancelOrderResult(success: false, orderId: orderId, exchange: credentials.exchange, errorMessage: errorMsg)
    }
    
    /// Submit a stop order on Binance
    /// For sells: STOP_LOSS (market) or STOP_LOSS_LIMIT
    /// For buys: Uses same order types but reversed logic
    private func submitBinanceStopOrder(
        credentials: TradingCredentials,
        symbol: String,
        side: TradeSide,
        quantity: Double,
        stopPrice: Double,
        limitPrice: Double?
    ) async throws -> OrderResult {
        let pair = normalizeBinancePair(symbol)
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        
        // Determine order type based on whether limit price is provided
        let orderType: String
        if limitPrice != nil {
            orderType = "STOP_LOSS_LIMIT"
        } else {
            orderType = "STOP_LOSS"
        }
        
        var params: [(String, String)] = [
            ("symbol", pair),
            ("side", side.rawValue),
            ("type", orderType),
            ("quantity", formatQuantity(quantity)),
            ("stopPrice", formatPrice(stopPrice)),
            ("timestamp", String(timestamp))
        ]
        
        if let limitPrice = limitPrice {
            params.append(("price", formatPrice(limitPrice)))
            params.append(("timeInForce", "GTC"))
        }
        
        let queryString = params.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        let signature = hmacSHA256(message: queryString, key: credentials.apiSecret)
        let signedQuery = queryString + "&signature=\(signature)"
        
        let url = credentials.exchange.restBaseURL.appendingPathComponent("/api/v3/order")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = signedQuery.data(using: .utf8)
        request.setValue(credentials.apiKey, forHTTPHeaderField: "X-MBX-APIKEY")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return OrderResult(success: false, errorMessage: "Invalid response", exchange: credentials.exchange.rawValue)
        }
        
        if httpResponse.statusCode == 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let orderId = json["orderId"] as? Int64
                let status = json["status"] as? String
                let executedQty = (json["executedQty"] as? String).flatMap { Double($0) }
                
                return OrderResult(
                    success: true,
                    orderId: orderId.map { String($0) },
                    status: OrderStatus(rawValue: status ?? "NEW"),
                    filledQuantity: executedQty,
                    exchange: credentials.exchange.rawValue
                )
            }
        }
        
        let errorMsg = parseErrorMessage(data: data, statusCode: httpResponse.statusCode)
        return OrderResult(success: false, errorMessage: errorMsg, exchange: credentials.exchange.rawValue)
    }
    
    // MARK: - Coinbase Implementation
    
    private func validateCoinbaseProductAndAccount(
        credentials: TradingCredentials,
        productId: String,
        quantity: Double
    ) async -> String? {
        do {
            let isConnected = try await testCoinbaseConnection(credentials: credentials)
            guard isConnected else {
                return "Coinbase account connection failed. Verify API key permissions and account eligibility."
            }
            
            let product = try await CoinbaseAdvancedTradeService.shared.getProduct(productId: productId)
            if product.status.lowercased() != "online" {
                return "Coinbase product \(productId) is not online for trading."
            }
            
            if let minSize = Double(product.baseMinSize), quantity < minSize {
                return "Order size is below Coinbase minimum (\(product.baseMinSize) \(product.baseCurrencyId))."
            }
            
            if let maxSize = Double(product.baseMaxSize), quantity > maxSize {
                return "Order size exceeds Coinbase maximum (\(product.baseMaxSize) \(product.baseCurrencyId))."
            }
        } catch {
            return "Coinbase pre-trade validation failed: \(error.localizedDescription)"
        }
        
        return nil
    }
    
    private func submitCoinbaseOrder(
        credentials: TradingCredentials,
        symbol: String,
        side: TradeSide,
        type: OrderType,
        quantity: Double,
        price: Double?
    ) async throws -> OrderResult {
        let productId = normalizeCoinbaseProductId(symbol)
        if let validationError = await validateCoinbaseProductAndAccount(
            credentials: credentials,
            productId: productId,
            quantity: quantity
        ) {
            return OrderResult(success: false, errorMessage: validationError, exchange: credentials.exchange.rawValue)
        }
        
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let method = "POST"
        let path = "/orders"
        
        var body: [String: Any] = [
            "product_id": productId,
            "side": side.rawValue.lowercased(),
            "size": formatQuantity(quantity)
        ]
        
        if type == .market {
            body["type"] = "market"
        } else if type == .limit, let price = price {
            body["type"] = "limit"
            body["price"] = formatPrice(price)
            body["time_in_force"] = "GTC"
        }
        
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let bodyString = String(data: bodyData, encoding: .utf8) ?? ""
        
        let message = timestamp + method + path + bodyString
        let signature = hmacSHA256Base64(message: message, key: credentials.apiSecret)
        
        let url = credentials.exchange.restBaseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(credentials.apiKey, forHTTPHeaderField: "CB-ACCESS-KEY")
        request.setValue(signature, forHTTPHeaderField: "CB-ACCESS-SIGN")
        request.setValue(timestamp, forHTTPHeaderField: "CB-ACCESS-TIMESTAMP")
        if let passphrase = credentials.passphrase {
            request.setValue(passphrase, forHTTPHeaderField: "CB-ACCESS-PASSPHRASE")
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return OrderResult(success: false, errorMessage: "Invalid response", exchange: credentials.exchange.rawValue)
        }
        
        if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let orderId = json["id"] as? String
                let status = json["status"] as? String
                let filledSize = (json["filled_size"] as? String).flatMap { Double($0) }
                let executedValue = (json["executed_value"] as? String).flatMap { Double($0) }
                
                // Calculate average price from executed value / filled size
                let calculatedAvgPrice: Double? = {
                    guard let execVal = executedValue, let fs = filledSize, fs > 0 else {
                        return nil
                    }
                    return execVal / fs
                }()
                
                return OrderResult(
                    success: true,
                    orderId: orderId,
                    status: mapCoinbaseStatus(status),
                    filledQuantity: filledSize,
                    averagePrice: calculatedAvgPrice,
                    exchange: credentials.exchange.rawValue
                )
            }
        }
        
        let errorMsg = parseErrorMessage(data: data, statusCode: httpResponse.statusCode)
        return OrderResult(success: false, errorMessage: errorMsg, exchange: credentials.exchange.rawValue)
    }
    
    private func fetchCoinbaseBalances(credentials: TradingCredentials) async throws -> [AssetBalance] {
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let method = "GET"
        let path = "/accounts"
        
        let message = timestamp + method + path
        let signature = hmacSHA256Base64(message: message, key: credentials.apiSecret)
        
        let url = credentials.exchange.restBaseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(credentials.apiKey, forHTTPHeaderField: "CB-ACCESS-KEY")
        request.setValue(signature, forHTTPHeaderField: "CB-ACCESS-SIGN")
        request.setValue(timestamp, forHTTPHeaderField: "CB-ACCESS-TIMESTAMP")
        if let passphrase = credentials.passphrase {
            request.setValue(passphrase, forHTTPHeaderField: "CB-ACCESS-PASSPHRASE")
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TradingError.apiError(message: "Failed to fetch balances")
        }
        
        guard let accounts = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw TradingError.parseError
        }
        
        return accounts.compactMap { item -> AssetBalance? in
            guard let currency = item["currency"] as? String,
                  let balanceStr = item["balance"] as? String,
                  let availableStr = item["available"] as? String,
                  let balance = Double(balanceStr),
                  let available = Double(availableStr),
                  balance > 0 else {
                return nil
            }
            return AssetBalance(asset: currency, free: available, locked: balance - available)
        }
    }
    
    private func testCoinbaseConnection(credentials: TradingCredentials) async throws -> Bool {
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let method = "GET"
        let path = "/accounts"
        
        let message = timestamp + method + path
        let signature = hmacSHA256Base64(message: message, key: credentials.apiSecret)
        
        let url = credentials.exchange.restBaseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(credentials.apiKey, forHTTPHeaderField: "CB-ACCESS-KEY")
        request.setValue(signature, forHTTPHeaderField: "CB-ACCESS-SIGN")
        request.setValue(timestamp, forHTTPHeaderField: "CB-ACCESS-TIMESTAMP")
        if let passphrase = credentials.passphrase {
            request.setValue(passphrase, forHTTPHeaderField: "CB-ACCESS-PASSPHRASE")
        }
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else { return false }
        return httpResponse.statusCode == 200
    }
    
    /// Fetch open orders from Coinbase
    private func fetchCoinbaseOpenOrders(credentials: TradingCredentials, symbol: String?) async throws -> [OpenOrder] {
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let method = "GET"
        var path = "/orders?status=open&status=pending"
        
        if let symbol = symbol {
            let productId = normalizeCoinbaseProductId(symbol)
            path += "&product_id=\(productId)"
        }
        
        let message = timestamp + method + path
        let signature = hmacSHA256Base64(message: message, key: credentials.apiSecret)
        
        let url = credentials.exchange.restBaseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(credentials.apiKey, forHTTPHeaderField: "CB-ACCESS-KEY")
        request.setValue(signature, forHTTPHeaderField: "CB-ACCESS-SIGN")
        request.setValue(timestamp, forHTTPHeaderField: "CB-ACCESS-TIMESTAMP")
        if let passphrase = credentials.passphrase {
            request.setValue(passphrase, forHTTPHeaderField: "CB-ACCESS-PASSPHRASE")
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorMsg = parseErrorMessage(data: data, statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
            throw TradingError.apiError(message: errorMsg)
        }
        
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw TradingError.parseError
        }
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        return jsonArray.compactMap { item -> OpenOrder? in
            guard let orderId = item["id"] as? String,
                  let productId = item["product_id"] as? String,
                  let sideStr = item["side"] as? String,
                  let typeStr = item["type"] as? String else {
                return nil
            }
            
            let price = Double(item["price"] as? String ?? "0") ?? 0
            let size = Double(item["size"] as? String ?? "0") ?? 0
            let filledSize = Double(item["filled_size"] as? String ?? "0") ?? 0
            let statusStr = item["status"] as? String ?? "open"
            let createdAtStr = item["created_at"] as? String ?? ""
            let createdAt = dateFormatter.date(from: createdAtStr) ?? Date()
            
            return OpenOrder(
                id: orderId,
                exchange: credentials.exchange,
                symbol: productId.replacingOccurrences(of: "-", with: ""),
                side: sideStr.lowercased() == "buy" ? .buy : .sell,
                type: typeStr.lowercased() == "market" ? .market : .limit,
                price: price,
                quantity: size,
                filledQuantity: filledSize,
                status: mapCoinbaseStatus(statusStr) ?? .new,
                createdAt: createdAt
            )
        }
    }
    
    /// Cancel an order on Coinbase
    private func cancelCoinbaseOrder(credentials: TradingCredentials, orderId: String) async throws -> CancelOrderResult {
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let method = "DELETE"
        let path = "/orders/\(orderId)"
        
        let message = timestamp + method + path
        let signature = hmacSHA256Base64(message: message, key: credentials.apiSecret)
        
        let url = credentials.exchange.restBaseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(credentials.apiKey, forHTTPHeaderField: "CB-ACCESS-KEY")
        request.setValue(signature, forHTTPHeaderField: "CB-ACCESS-SIGN")
        request.setValue(timestamp, forHTTPHeaderField: "CB-ACCESS-TIMESTAMP")
        if let passphrase = credentials.passphrase {
            request.setValue(passphrase, forHTTPHeaderField: "CB-ACCESS-PASSPHRASE")
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return CancelOrderResult(success: false, orderId: orderId, exchange: credentials.exchange, errorMessage: "Invalid response")
        }
        
        if httpResponse.statusCode == 200 || httpResponse.statusCode == 204 {
            return CancelOrderResult(success: true, orderId: orderId, exchange: credentials.exchange)
        }
        
        let errorMsg = parseErrorMessage(data: data, statusCode: httpResponse.statusCode)
        return CancelOrderResult(success: false, orderId: orderId, exchange: credentials.exchange, errorMessage: errorMsg)
    }
    
    /// Submit a stop order on Coinbase
    private func submitCoinbaseStopOrder(
        credentials: TradingCredentials,
        symbol: String,
        side: TradeSide,
        quantity: Double,
        stopPrice: Double,
        limitPrice: Double?
    ) async throws -> OrderResult {
        let productId = normalizeCoinbaseProductId(symbol)
        if let validationError = await validateCoinbaseProductAndAccount(
            credentials: credentials,
            productId: productId,
            quantity: quantity
        ) {
            return OrderResult(success: false, errorMessage: validationError, exchange: credentials.exchange.rawValue)
        }
        
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let method = "POST"
        let path = "/orders"
        
        var body: [String: Any] = [
            "product_id": productId,
            "side": side.rawValue.lowercased(),
            "size": formatQuantity(quantity),
            "stop": side == .sell ? "loss" : "entry",  // loss for sell stop, entry for buy stop
            "stop_price": formatPrice(stopPrice)
        ]
        
        if let limitPrice = limitPrice {
            // Stop-limit order
            body["type"] = "limit"
            body["price"] = formatPrice(limitPrice)
            body["time_in_force"] = "GTC"
        } else {
            // Stop-market order
            body["type"] = "market"
        }
        
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let bodyString = String(data: bodyData, encoding: .utf8) ?? ""
        
        let message = timestamp + method + path + bodyString
        let signature = hmacSHA256Base64(message: message, key: credentials.apiSecret)
        
        let url = credentials.exchange.restBaseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(credentials.apiKey, forHTTPHeaderField: "CB-ACCESS-KEY")
        request.setValue(signature, forHTTPHeaderField: "CB-ACCESS-SIGN")
        request.setValue(timestamp, forHTTPHeaderField: "CB-ACCESS-TIMESTAMP")
        if let passphrase = credentials.passphrase {
            request.setValue(passphrase, forHTTPHeaderField: "CB-ACCESS-PASSPHRASE")
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return OrderResult(success: false, errorMessage: "Invalid response", exchange: credentials.exchange.rawValue)
        }
        
        if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let orderId = json["id"] as? String
                let status = json["status"] as? String
                
                return OrderResult(
                    success: true,
                    orderId: orderId,
                    status: mapCoinbaseStatus(status),
                    exchange: credentials.exchange.rawValue
                )
            }
        }
        
        let errorMsg = parseErrorMessage(data: data, statusCode: httpResponse.statusCode)
        return OrderResult(success: false, errorMessage: errorMsg, exchange: credentials.exchange.rawValue)
    }
    
    // MARK: - Kraken Implementation
    
    private func submitKrakenOrder(
        credentials: TradingCredentials,
        symbol: String,
        side: TradeSide,
        type: OrderType,
        quantity: Double,
        price: Double?
    ) async throws -> OrderResult {
        let pair = normalizeKrakenPair(symbol)
        let nonce = String(Int64(Date().timeIntervalSince1970 * 1000))
        
        var postData: [(String, String)] = [
            ("nonce", nonce),
            ("ordertype", type == .market ? "market" : "limit"),
            ("type", side == .buy ? "buy" : "sell"),
            ("volume", formatQuantity(quantity)),
            ("pair", pair)
        ]
        
        if type == .limit, let price = price {
            postData.append(("price", formatPrice(price)))
        }
        
        let postString = postData.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        
        let path = "/0/private/AddOrder"
        let signature = krakenSignature(
            path: path,
            nonce: nonce,
            postData: postString,
            secret: credentials.apiSecret
        )
        
        let url = credentials.exchange.restBaseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = postString.data(using: .utf8)
        request.setValue(credentials.apiKey, forHTTPHeaderField: "API-Key")
        request.setValue(signature, forHTTPHeaderField: "API-Sign")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return OrderResult(success: false, errorMessage: "Invalid response", exchange: credentials.exchange.rawValue)
        }
        
        if httpResponse.statusCode == 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let result = json["result"] as? [String: Any],
               let txid = result["txid"] as? [String],
               let orderId = txid.first {
                return OrderResult(
                    success: true,
                    orderId: orderId,
                    status: .new,
                    exchange: credentials.exchange.rawValue
                )
            }
            
            // Check for errors in Kraken response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errors = json["error"] as? [String],
               !errors.isEmpty {
                return OrderResult(
                    success: false,
                    errorMessage: errors.joined(separator: ", "),
                    exchange: credentials.exchange.rawValue
                )
            }
        }
        
        let errorMsg = parseErrorMessage(data: data, statusCode: httpResponse.statusCode)
        return OrderResult(success: false, errorMessage: errorMsg, exchange: credentials.exchange.rawValue)
    }
    
    private func fetchKrakenBalances(credentials: TradingCredentials) async throws -> [AssetBalance] {
        let nonce = String(Int64(Date().timeIntervalSince1970 * 1000))
        let postData = "nonce=\(nonce)"
        let path = "/0/private/Balance"
        
        let signature = krakenSignature(
            path: path,
            nonce: nonce,
            postData: postData,
            secret: credentials.apiSecret
        )
        
        let url = credentials.exchange.restBaseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = postData.data(using: .utf8)
        request.setValue(credentials.apiKey, forHTTPHeaderField: "API-Key")
        request.setValue(signature, forHTTPHeaderField: "API-Sign")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TradingError.apiError(message: "Failed to fetch balances")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: String] else {
            throw TradingError.parseError
        }
        
        return result.compactMap { (asset, balanceStr) -> AssetBalance? in
            guard let balance = Double(balanceStr), balance > 0 else { return nil }
            // Convert Kraken asset codes (e.g., XXBT -> BTC, ZUSD -> USD)
            let normalizedAsset = normalizeKrakenAsset(asset)
            return AssetBalance(asset: normalizedAsset, free: balance, locked: 0)
        }
    }
    
    private func testKrakenConnection(credentials: TradingCredentials) async throws -> Bool {
        let nonce = String(Int64(Date().timeIntervalSince1970 * 1000))
        let postData = "nonce=\(nonce)"
        let path = "/0/private/Balance"
        
        let signature = krakenSignature(
            path: path,
            nonce: nonce,
            postData: postData,
            secret: credentials.apiSecret
        )
        
        let url = credentials.exchange.restBaseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = postData.data(using: .utf8)
        request.setValue(credentials.apiKey, forHTTPHeaderField: "API-Key")
        request.setValue(signature, forHTTPHeaderField: "API-Sign")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return false
        }
        
        // Check for Kraken-specific errors
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errors = json["error"] as? [String],
           !errors.isEmpty {
            return false
        }
        
        return true
    }
    
    /// Fetch open orders from Kraken
    private func fetchKrakenOpenOrders(credentials: TradingCredentials, symbol: String?) async throws -> [OpenOrder] {
        let nonce = String(Int64(Date().timeIntervalSince1970 * 1000))
        let postData = "nonce=\(nonce)"
        let path = "/0/private/OpenOrders"
        
        let signature = krakenSignature(
            path: path,
            nonce: nonce,
            postData: postData,
            secret: credentials.apiSecret
        )
        
        let url = credentials.exchange.restBaseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = postData.data(using: .utf8)
        request.setValue(credentials.apiKey, forHTTPHeaderField: "API-Key")
        request.setValue(signature, forHTTPHeaderField: "API-Sign")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TradingError.apiError(message: "Failed to fetch Kraken open orders")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let openOrders = result["open"] as? [String: [String: Any]] else {
            // Check for Kraken errors
            if let errors = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? [String],
               !errors.isEmpty {
                throw TradingError.apiError(message: errors.joined(separator: ", "))
            }
            throw TradingError.parseError
        }
        
        var orders: [OpenOrder] = []
        
        for (orderId, orderData) in openOrders {
            guard let descr = orderData["descr"] as? [String: Any],
                  let pair = descr["pair"] as? String,
                  let orderType = descr["type"] as? String,
                  let priceStr = descr["price"] as? String,
                  let volStr = orderData["vol"] as? String,
                  let volExecStr = orderData["vol_exec"] as? String else {
                continue
            }
            
            let status = orderData["status"] as? String ?? "open"
            let opentm = orderData["opentm"] as? Double ?? Date().timeIntervalSince1970
            
            // Filter by symbol if provided
            if let symbol = symbol {
                let krakenPair = normalizeKrakenPair(symbol)
                if !pair.contains(krakenPair) && !krakenPair.contains(pair) {
                    continue
                }
            }
            
            orders.append(OpenOrder(
                id: orderId,
                exchange: credentials.exchange,
                symbol: pair,
                side: orderType.lowercased() == "buy" ? .buy : .sell,
                type: .limit,
                price: Double(priceStr) ?? 0,
                quantity: Double(volStr) ?? 0,
                filledQuantity: Double(volExecStr) ?? 0,
                status: mapKrakenStatus(status),
                createdAt: Date(timeIntervalSince1970: opentm)
            ))
        }
        
        return orders
    }
    
    /// Cancel an order on Kraken
    private func cancelKrakenOrder(credentials: TradingCredentials, orderId: String) async throws -> CancelOrderResult {
        let nonce = String(Int64(Date().timeIntervalSince1970 * 1000))
        let postData = "nonce=\(nonce)&txid=\(orderId)"
        let path = "/0/private/CancelOrder"
        
        let signature = krakenSignature(
            path: path,
            nonce: nonce,
            postData: postData,
            secret: credentials.apiSecret
        )
        
        let url = credentials.exchange.restBaseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = postData.data(using: .utf8)
        request.setValue(credentials.apiKey, forHTTPHeaderField: "API-Key")
        request.setValue(signature, forHTTPHeaderField: "API-Sign")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return CancelOrderResult(success: false, orderId: orderId, exchange: credentials.exchange, errorMessage: "Invalid response")
        }
        
        if httpResponse.statusCode == 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errors = json["error"] as? [String],
               !errors.isEmpty {
                return CancelOrderResult(success: false, orderId: orderId, exchange: credentials.exchange, errorMessage: errors.joined(separator: ", "))
            }
            return CancelOrderResult(success: true, orderId: orderId, exchange: credentials.exchange)
        }
        
        return CancelOrderResult(success: false, orderId: orderId, exchange: credentials.exchange, errorMessage: "HTTP \(httpResponse.statusCode)")
    }
    
    /// Map Kraken order status to our OrderStatus
    nonisolated private func mapKrakenStatus(_ status: String) -> OrderStatus {
        switch status.lowercased() {
        case "open", "pending": return .new
        case "closed": return .filled
        case "canceled", "cancelled": return .canceled
        case "expired": return .expired
        default: return .new
        }
    }
    
    /// Submit a stop order on Kraken
    private func submitKrakenStopOrder(
        credentials: TradingCredentials,
        symbol: String,
        side: TradeSide,
        quantity: Double,
        stopPrice: Double,
        limitPrice: Double?
    ) async throws -> OrderResult {
        let pair = normalizeKrakenPair(symbol)
        let nonce = String(Int64(Date().timeIntervalSince1970 * 1000))
        
        // Kraken order types: stop-loss, stop-loss-limit
        let orderType: String
        if limitPrice != nil {
            orderType = "stop-loss-limit"
        } else {
            orderType = "stop-loss"
        }
        
        var postData: [(String, String)] = [
            ("nonce", nonce),
            ("ordertype", orderType),
            ("type", side == .buy ? "buy" : "sell"),
            ("volume", formatQuantity(quantity)),
            ("pair", pair),
            ("price", formatPrice(stopPrice))  // Trigger price for stop orders
        ]
        
        if let limitPrice = limitPrice {
            // For stop-loss-limit, price2 is the limit price
            postData.append(("price2", formatPrice(limitPrice)))
        }
        
        let postString = postData.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        
        let path = "/0/private/AddOrder"
        let signature = krakenSignature(
            path: path,
            nonce: nonce,
            postData: postString,
            secret: credentials.apiSecret
        )
        
        let url = credentials.exchange.restBaseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = postString.data(using: .utf8)
        request.setValue(credentials.apiKey, forHTTPHeaderField: "API-Key")
        request.setValue(signature, forHTTPHeaderField: "API-Sign")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return OrderResult(success: false, errorMessage: "Invalid response", exchange: credentials.exchange.rawValue)
        }
        
        if httpResponse.statusCode == 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let result = json["result"] as? [String: Any],
               let txid = result["txid"] as? [String],
               let orderId = txid.first {
                return OrderResult(
                    success: true,
                    orderId: orderId,
                    status: .new,
                    exchange: credentials.exchange.rawValue
                )
            }
            
            // Check for errors in Kraken response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errors = json["error"] as? [String],
               !errors.isEmpty {
                return OrderResult(
                    success: false,
                    errorMessage: errors.joined(separator: ", "),
                    exchange: credentials.exchange.rawValue
                )
            }
        }
        
        let errorMsg = parseErrorMessage(data: data, statusCode: httpResponse.statusCode)
        return OrderResult(success: false, errorMessage: errorMsg, exchange: credentials.exchange.rawValue)
    }
    
    // MARK: - KuCoin Implementation
    
    private func submitKuCoinOrder(
        credentials: TradingCredentials,
        symbol: String,
        side: TradeSide,
        type: OrderType,
        quantity: Double,
        price: Double?
    ) async throws -> OrderResult {
        let productId = normalizeKuCoinSymbol(symbol)
        let timestamp = String(Int64(Date().timeIntervalSince1970 * 1000))
        let clientOid = UUID().uuidString
        
        var body: [String: Any] = [
            "clientOid": clientOid,
            "side": side == .buy ? "buy" : "sell",
            "symbol": productId,
            "type": type == .market ? "market" : "limit",
            "size": formatQuantity(quantity)
        ]
        
        if type == .limit, let price = price {
            body["price"] = formatPrice(price)
        }
        
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let bodyString = String(data: bodyData, encoding: .utf8) ?? ""
        
        let path = "/api/v1/orders"
        let method = "POST"
        let message = timestamp + method + path + bodyString
        let signature = hmacSHA256Base64KuCoin(message: message, key: credentials.apiSecret)
        let passphrase = hmacSHA256Base64KuCoin(message: credentials.passphrase ?? "", key: credentials.apiSecret)
        
        let url = credentials.exchange.restBaseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(credentials.apiKey, forHTTPHeaderField: "KC-API-KEY")
        request.setValue(signature, forHTTPHeaderField: "KC-API-SIGN")
        request.setValue(timestamp, forHTTPHeaderField: "KC-API-TIMESTAMP")
        request.setValue(passphrase, forHTTPHeaderField: "KC-API-PASSPHRASE")
        request.setValue("2", forHTTPHeaderField: "KC-API-KEY-VERSION")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return OrderResult(success: false, errorMessage: "Invalid response", exchange: credentials.exchange.rawValue)
        }
        
        if httpResponse.statusCode == 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let code = json["code"] as? String,
               code == "200000",
               let resultData = json["data"] as? [String: Any],
               let orderId = resultData["orderId"] as? String {
                return OrderResult(
                    success: true,
                    orderId: orderId,
                    status: .new,
                    exchange: credentials.exchange.rawValue
                )
            }
        }
        
        let errorMsg = parseKuCoinError(data: data, statusCode: httpResponse.statusCode)
        return OrderResult(success: false, errorMessage: errorMsg, exchange: credentials.exchange.rawValue)
    }
    
    private func fetchKuCoinBalances(credentials: TradingCredentials) async throws -> [AssetBalance] {
        let timestamp = String(Int64(Date().timeIntervalSince1970 * 1000))
        let path = "/api/v1/accounts"
        let method = "GET"
        
        let message = timestamp + method + path
        let signature = hmacSHA256Base64KuCoin(message: message, key: credentials.apiSecret)
        let passphrase = hmacSHA256Base64KuCoin(message: credentials.passphrase ?? "", key: credentials.apiSecret)
        
        let url = credentials.exchange.restBaseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(credentials.apiKey, forHTTPHeaderField: "KC-API-KEY")
        request.setValue(signature, forHTTPHeaderField: "KC-API-SIGN")
        request.setValue(timestamp, forHTTPHeaderField: "KC-API-TIMESTAMP")
        request.setValue(passphrase, forHTTPHeaderField: "KC-API-PASSPHRASE")
        request.setValue("2", forHTTPHeaderField: "KC-API-KEY-VERSION")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TradingError.apiError(message: "Failed to fetch balances")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = json["code"] as? String,
              code == "200000",
              let accounts = json["data"] as? [[String: Any]] else {
            throw TradingError.parseError
        }
        
        // Group by currency and aggregate balances from all account types
        var balanceMap: [String: (free: Double, locked: Double)] = [:]
        
        for account in accounts {
            guard let currency = account["currency"] as? String,
                  let availableStr = account["available"] as? String,
                  let holdsStr = account["holds"] as? String,
                  let available = Double(availableStr),
                  let holds = Double(holdsStr) else {
                continue
            }
            
            let existing = balanceMap[currency] ?? (0, 0)
            balanceMap[currency] = (existing.free + available, existing.locked + holds)
        }
        
        return balanceMap.compactMap { (currency, amounts) -> AssetBalance? in
            guard amounts.free + amounts.locked > 0 else { return nil }
            return AssetBalance(asset: currency, free: amounts.free, locked: amounts.locked)
        }
    }
    
    private func testKuCoinConnection(credentials: TradingCredentials) async throws -> Bool {
        let timestamp = String(Int64(Date().timeIntervalSince1970 * 1000))
        let path = "/api/v1/accounts"
        let method = "GET"
        
        let message = timestamp + method + path
        let signature = hmacSHA256Base64KuCoin(message: message, key: credentials.apiSecret)
        let passphrase = hmacSHA256Base64KuCoin(message: credentials.passphrase ?? "", key: credentials.apiSecret)
        
        let url = credentials.exchange.restBaseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(credentials.apiKey, forHTTPHeaderField: "KC-API-KEY")
        request.setValue(signature, forHTTPHeaderField: "KC-API-SIGN")
        request.setValue(timestamp, forHTTPHeaderField: "KC-API-TIMESTAMP")
        request.setValue(passphrase, forHTTPHeaderField: "KC-API-PASSPHRASE")
        request.setValue("2", forHTTPHeaderField: "KC-API-KEY-VERSION")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return false
        }
        
        // Check KuCoin response code
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let code = json["code"] as? String {
            return code == "200000"
        }
        
        return false
    }
    
    /// Fetch open orders from KuCoin
    private func fetchKuCoinOpenOrders(credentials: TradingCredentials, symbol: String?) async throws -> [OpenOrder] {
        let timestamp = String(Int64(Date().timeIntervalSince1970 * 1000))
        var path = "/api/v1/orders?status=active"
        
        if let symbol = symbol {
            let kucoinSymbol = normalizeKuCoinSymbol(symbol)
            path += "&symbol=\(kucoinSymbol)"
        }
        
        let method = "GET"
        let message = timestamp + method + path
        let signature = hmacSHA256Base64KuCoin(message: message, key: credentials.apiSecret)
        let passphrase = hmacSHA256Base64KuCoin(message: credentials.passphrase ?? "", key: credentials.apiSecret)
        
        let url = credentials.exchange.restBaseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(credentials.apiKey, forHTTPHeaderField: "KC-API-KEY")
        request.setValue(signature, forHTTPHeaderField: "KC-API-SIGN")
        request.setValue(timestamp, forHTTPHeaderField: "KC-API-TIMESTAMP")
        request.setValue(passphrase, forHTTPHeaderField: "KC-API-PASSPHRASE")
        request.setValue("2", forHTTPHeaderField: "KC-API-KEY-VERSION")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TradingError.apiError(message: "Failed to fetch KuCoin open orders")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = json["code"] as? String,
              code == "200000",
              let dataObj = json["data"] as? [String: Any],
              let items = dataObj["items"] as? [[String: Any]] else {
            throw TradingError.parseError
        }
        
        return items.compactMap { item -> OpenOrder? in
            guard let orderId = item["id"] as? String,
                  let symbolStr = item["symbol"] as? String,
                  let sideStr = item["side"] as? String,
                  let typeStr = item["type"] as? String else {
                return nil
            }
            
            let price = Double(item["price"] as? String ?? "0") ?? 0
            let size = Double(item["size"] as? String ?? "0") ?? 0
            let dealSize = Double(item["dealSize"] as? String ?? "0") ?? 0
            let createdAt = item["createdAt"] as? Int64 ?? Int64(Date().timeIntervalSince1970 * 1000)
            
            return OpenOrder(
                id: orderId,
                exchange: credentials.exchange,
                symbol: symbolStr.replacingOccurrences(of: "-", with: ""),
                side: sideStr.lowercased() == "buy" ? .buy : .sell,
                type: typeStr.lowercased() == "market" ? .market : .limit,
                price: price,
                quantity: size,
                filledQuantity: dealSize,
                status: .new,
                createdAt: Date(timeIntervalSince1970: Double(createdAt) / 1000)
            )
        }
    }
    
    /// Cancel an order on KuCoin
    private func cancelKuCoinOrder(credentials: TradingCredentials, orderId: String) async throws -> CancelOrderResult {
        let timestamp = String(Int64(Date().timeIntervalSince1970 * 1000))
        let path = "/api/v1/orders/\(orderId)"
        let method = "DELETE"
        
        let message = timestamp + method + path
        let signature = hmacSHA256Base64KuCoin(message: message, key: credentials.apiSecret)
        let passphrase = hmacSHA256Base64KuCoin(message: credentials.passphrase ?? "", key: credentials.apiSecret)
        
        let url = credentials.exchange.restBaseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(credentials.apiKey, forHTTPHeaderField: "KC-API-KEY")
        request.setValue(signature, forHTTPHeaderField: "KC-API-SIGN")
        request.setValue(timestamp, forHTTPHeaderField: "KC-API-TIMESTAMP")
        request.setValue(passphrase, forHTTPHeaderField: "KC-API-PASSPHRASE")
        request.setValue("2", forHTTPHeaderField: "KC-API-KEY-VERSION")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return CancelOrderResult(success: false, orderId: orderId, exchange: credentials.exchange, errorMessage: "Invalid response")
        }
        
        if httpResponse.statusCode == 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let code = json["code"] as? String,
               code == "200000" {
                return CancelOrderResult(success: true, orderId: orderId, exchange: credentials.exchange)
            }
        }
        
        let errorMsg = parseErrorMessage(data: data, statusCode: httpResponse.statusCode)
        return CancelOrderResult(success: false, orderId: orderId, exchange: credentials.exchange, errorMessage: errorMsg)
    }
    
    /// Submit a stop order on KuCoin
    /// KuCoin uses a separate stop order API endpoint
    private func submitKuCoinStopOrder(
        credentials: TradingCredentials,
        symbol: String,
        side: TradeSide,
        quantity: Double,
        stopPrice: Double,
        limitPrice: Double?
    ) async throws -> OrderResult {
        let productId = normalizeKuCoinSymbol(symbol)
        let timestamp = String(Int64(Date().timeIntervalSince1970 * 1000))
        let clientOid = UUID().uuidString
        
        var body: [String: Any] = [
            "clientOid": clientOid,
            "side": side == .buy ? "buy" : "sell",
            "symbol": productId,
            "size": formatQuantity(quantity),
            "stopPrice": formatPrice(stopPrice),
            "stop": side == .sell ? "loss" : "entry"  // loss for sell stop, entry for buy stop
        ]
        
        if let limitPrice = limitPrice {
            // Stop-limit order
            body["type"] = "limit"
            body["price"] = formatPrice(limitPrice)
        } else {
            // Stop-market order
            body["type"] = "market"
        }
        
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let bodyString = String(data: bodyData, encoding: .utf8) ?? ""
        
        let path = "/api/v1/stop-order"
        let method = "POST"
        let message = timestamp + method + path + bodyString
        let signature = hmacSHA256Base64KuCoin(message: message, key: credentials.apiSecret)
        let passphrase = hmacSHA256Base64KuCoin(message: credentials.passphrase ?? "", key: credentials.apiSecret)
        
        let url = credentials.exchange.restBaseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(credentials.apiKey, forHTTPHeaderField: "KC-API-KEY")
        request.setValue(signature, forHTTPHeaderField: "KC-API-SIGN")
        request.setValue(timestamp, forHTTPHeaderField: "KC-API-TIMESTAMP")
        request.setValue(passphrase, forHTTPHeaderField: "KC-API-PASSPHRASE")
        request.setValue("2", forHTTPHeaderField: "KC-API-KEY-VERSION")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return OrderResult(success: false, errorMessage: "Invalid response", exchange: credentials.exchange.rawValue)
        }
        
        if httpResponse.statusCode == 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let code = json["code"] as? String,
               code == "200000",
               let resultData = json["data"] as? [String: Any],
               let orderId = resultData["orderId"] as? String {
                return OrderResult(
                    success: true,
                    orderId: orderId,
                    status: .new,
                    exchange: credentials.exchange.rawValue
                )
            }
        }
        
        let errorMsg = parseKuCoinError(data: data, statusCode: httpResponse.statusCode)
        return OrderResult(success: false, errorMessage: errorMsg, exchange: credentials.exchange.rawValue)
    }
    
    // MARK: - Helpers
    
    private func normalizeBinancePair(_ symbol: String) -> String {
        var upper = symbol.uppercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "/", with: "")
        // Binance uses "BTCUSDT" format. Ensure USDT suffix.
        if upper.hasSuffix("USDT") {
            return upper
        }
        // FIX: "BTCUSD" (no T) should become "BTCUSDT" — Binance doesn't have *USD pairs
        if upper.hasSuffix("USD") {
            upper = String(upper.dropLast(3)) + "USDT"
            return upper
        }
        return upper + "USDT"
    }
    
    private func normalizeCoinbaseProductId(_ symbol: String) -> String {
        let upper = symbol.uppercased()
        // Coinbase uses "BTC-USD" format (NOT "BTC-USDT")
        // FIX: Check for "-USDT" BEFORE "-USD" to avoid substring match bug
        // (previously "BTC-USDT".contains("-USD") was true, passing "BTC-USDT" through unchanged)
        if upper.hasSuffix("-USDT") {
            let base = String(upper.dropLast(5)) // drop "-USDT"
            return base + "-USD"
        }
        if upper.hasSuffix("-USD") {
            return upper
        }
        if upper.hasSuffix("USDT") {
            let base = String(upper.dropLast(4))
            return base + "-USD"
        }
        if upper.hasSuffix("USD") {
            let base = String(upper.dropLast(3))
            return base + "-USD"
        }
        // Handle underscore format (e.g., "BTC_USDT")
        if upper.contains("_") {
            let base = upper.components(separatedBy: "_").first ?? upper
            return base + "-USD"
        }
        return upper + "-USD"
    }
    
    private func formatQuantity(_ quantity: Double) -> String {
        // Guard against NaN/Infinity/negative — these would produce invalid API requests
        guard quantity > 0, quantity.isFinite else { return "0" }
        if quantity < 0.001 {
            return String(format: "%.8f", quantity)
        } else if quantity < 1 {
            return String(format: "%.6f", quantity)
        } else {
            return String(format: "%.4f", quantity)
        }
    }
    
    private func formatPrice(_ price: Double) -> String {
        // Guard against NaN/Infinity/negative — these would produce invalid API requests
        guard price > 0, price.isFinite else { return "0" }
        if price < 0.01 {
            return String(format: "%.8f", price)
        } else if price < 1 {
            return String(format: "%.6f", price)
        } else if price < 100 {
            return String(format: "%.4f", price)
        } else {
            return String(format: "%.2f", price)
        }
    }
    
    private func hmacSHA256(message: String, key: String) -> String {
        guard let keyData = key.data(using: .utf8),
              let messageData = message.data(using: .utf8) else {
            return ""
        }
        
        var macData = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        macData.withUnsafeMutableBytes { macPtr in
            keyData.withUnsafeBytes { keyPtr in
                messageData.withUnsafeBytes { messagePtr in
                    CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256),
                           keyPtr.baseAddress, keyData.count,
                           messagePtr.baseAddress, messageData.count,
                           macPtr.baseAddress)
                }
            }
        }
        
        return macData.map { String(format: "%02hhx", $0) }.joined()
    }
    
    private func hmacSHA256Base64(message: String, key: String) -> String {
        guard let keyData = Data(base64Encoded: key),
              let messageData = message.data(using: .utf8) else {
            return ""
        }
        
        var macData = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        macData.withUnsafeMutableBytes { macPtr in
            keyData.withUnsafeBytes { keyPtr in
                messageData.withUnsafeBytes { messagePtr in
                    CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256),
                           keyPtr.baseAddress, keyData.count,
                           messagePtr.baseAddress, messageData.count,
                           macPtr.baseAddress)
                }
            }
        }
        
        return macData.base64EncodedString()
    }
    
    private func mapCoinbaseStatus(_ status: String?) -> OrderStatus? {
        guard let status = status else { return nil }
        switch status.lowercased() {
        case "pending": return .pending
        case "open": return .new
        case "active": return .partiallyFilled
        case "done": return .filled
        case "cancelled", "canceled": return .canceled
        case "rejected": return .rejected
        default: return .new
        }
    }
    
    private func parseErrorMessage(data: Data, statusCode: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let msg = json["msg"] as? String { return msg }
            if let message = json["message"] as? String { return message }
            if let error = json["error"] as? String { return error }
        }
        return "Request failed with status code \(statusCode)"
    }
    
    // MARK: - Kraken Helpers
    
    private func normalizeKrakenPair(_ symbol: String) -> String {
        // Extract base symbol from various formats: "BTCUSDT", "BTC-USD", "BTC_USDT", "BTC"
        var base = symbol.uppercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "/", with: "")
        // Strip quote asset suffixes
        for suffix in ["USDT", "USD", "ZUSD"] {
            if base.hasSuffix(suffix) && base.count > suffix.count {
                base = String(base.dropLast(suffix.count))
                break
            }
        }
        
        // Kraken-specific pair mappings (Kraken uses X/Z prefixed names for major pairs)
        let krakenPairs: [String: String] = [
            "BTC": "XXBTZUSD", "XBT": "XXBTZUSD",
            "ETH": "XETHZUSD",
            "SOL": "SOLUSD",
            "ADA": "ADAUSD",
            "DOT": "DOTUSD",
            "XRP": "XXRPZUSD",
            "DOGE": "XDGUSD",
            "LINK": "LINKUSD",
            "LTC": "XLTCZUSD",
            "UNI": "UNIUSD",
            "AVAX": "AVAXUSD",
            "MATIC": "MATICUSD",
            "ATOM": "ATOMUSD",
            "SHIB": "SHIBUSD",
            "BNB": "BNBUSD",
        ]
        
        if let krakenPair = krakenPairs[base] {
            return krakenPair
        }
        // Default: append USD for unknown coins
        return base + "USD"
    }
    
    private func normalizeKrakenAsset(_ asset: String) -> String {
        // Kraken uses X-prefixed codes for some assets
        let mapping: [String: String] = [
            "XXBT": "BTC",
            "XBT": "BTC",
            "XETH": "ETH",
            "ZUSD": "USD",
            "ZEUR": "EUR",
            "XXRP": "XRP",
            "XLTC": "LTC",
            "XXLM": "XLM",
            "XDOGE": "DOGE"
        ]
        return mapping[asset.uppercased()] ?? asset
    }
    
    private func krakenSignature(path: String, nonce: String, postData: String, secret: String) -> String {
        // Kraken signature: HMAC-SHA512(path + SHA256(nonce + postData), base64_decode(secret))
        guard let secretData = Data(base64Encoded: secret) else { return "" }
        
        let noncePostData = nonce + postData
        let sha256Hash = sha256(noncePostData)
        
        guard let pathData = path.data(using: .utf8) else { return "" }
        let signatureInput = pathData + sha256Hash
        
        var macData = Data(count: Int(CC_SHA512_DIGEST_LENGTH))
        macData.withUnsafeMutableBytes { macPtr in
            secretData.withUnsafeBytes { keyPtr in
                signatureInput.withUnsafeBytes { messagePtr in
                    CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA512),
                           keyPtr.baseAddress, secretData.count,
                           messagePtr.baseAddress, signatureInput.count,
                           macPtr.baseAddress)
                }
            }
        }
        
        return macData.base64EncodedString()
    }
    
    private func sha256(_ string: String) -> Data {
        guard let data = string.data(using: .utf8) else { return Data() }
        var hash = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        hash.withUnsafeMutableBytes { hashPtr in
            data.withUnsafeBytes { dataPtr in
                _ = CC_SHA256(dataPtr.baseAddress, CC_LONG(data.count), hashPtr.bindMemory(to: UInt8.self).baseAddress)
            }
        }
        return hash
    }
    
    // MARK: - KuCoin Helpers
    
    private func normalizeKuCoinSymbol(_ symbol: String) -> String {
        let upper = symbol.uppercased()
        // KuCoin uses format like BTC-USDT
        if upper.contains("-") {
            return upper
        }
        if upper.hasSuffix("USDT") {
            let base = String(upper.dropLast(4))
            return base + "-USDT"
        }
        if upper.hasSuffix("USD") {
            let base = String(upper.dropLast(3))
            return base + "-USDT"  // KuCoin primarily uses USDT
        }
        return upper + "-USDT"
    }
    
    private func hmacSHA256Base64KuCoin(message: String, key: String) -> String {
        guard let keyData = key.data(using: .utf8),
              let messageData = message.data(using: .utf8) else {
            return ""
        }
        
        var macData = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        macData.withUnsafeMutableBytes { macPtr in
            keyData.withUnsafeBytes { keyPtr in
                messageData.withUnsafeBytes { messagePtr in
                    CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256),
                           keyPtr.baseAddress, keyData.count,
                           messagePtr.baseAddress, messageData.count,
                           macPtr.baseAddress)
                }
            }
        }
        
        return macData.base64EncodedString()
    }
    
    private func parseKuCoinError(data: Data, statusCode: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let msg = json["msg"] as? String { return msg }
            if let code = json["code"] as? String, code != "200000" {
                return "KuCoin error code: \(code)"
            }
        }
        return "Request failed with status code \(statusCode)"
    }
    
    // MARK: - Bybit Implementation
    
    private func submitBybitOrder(
        credentials: TradingCredentials,
        symbol: String,
        side: TradeSide,
        type: OrderType,
        quantity: Double,
        price: Double?
    ) async throws -> OrderResult {
        let normalizedSymbol = normalizeBybitSymbol(symbol)
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let recvWindow = "5000"
        
        var params: [String: Any] = [
            "category": "spot",
            "symbol": normalizedSymbol,
            "side": side == .buy ? "Buy" : "Sell",
            "orderType": type == .market ? "Market" : "Limit",
            "qty": String(format: "%.8f", quantity)
        ]
        
        if type == .limit, let price = price {
            params["price"] = String(format: "%.8f", price)
            params["timeInForce"] = "GTC"
        }
        
        let jsonData = try JSONSerialization.data(withJSONObject: params)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
        
        let signString = timestamp + credentials.apiKey + recvWindow + jsonString
        let signature = hmacSHA256HexBybit(message: signString, key: credentials.apiSecret)
        
        var request = URLRequest(url: URL(string: "https://api.bybit.com/v5/order/create")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(credentials.apiKey, forHTTPHeaderField: "X-BAPI-API-KEY")
        request.setValue(timestamp, forHTTPHeaderField: "X-BAPI-TIMESTAMP")
        request.setValue(signature, forHTTPHeaderField: "X-BAPI-SIGN")
        request.setValue(recvWindow, forHTTPHeaderField: "X-BAPI-RECV-WINDOW")
        request.httpBody = jsonData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return OrderResult(success: false, errorMessage: "Invalid response", exchange: "bybit")
        }
        
        if httpResponse.statusCode == 200,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let retCode = json["retCode"] as? Int, retCode == 0,
           let result = json["result"] as? [String: Any],
           let orderId = result["orderId"] as? String {
            return OrderResult(success: true, orderId: orderId, exchange: "bybit")
        }
        
        let errorMsg = parseBybitError(data: data, statusCode: httpResponse.statusCode)
        return OrderResult(success: false, errorMessage: errorMsg, exchange: "bybit")
    }
    
    private func submitBybitStopOrder(
        credentials: TradingCredentials,
        symbol: String,
        side: TradeSide,
        quantity: Double,
        stopPrice: Double,
        limitPrice: Double?
    ) async throws -> OrderResult {
        let normalizedSymbol = normalizeBybitSymbol(symbol)
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let recvWindow = "5000"
        
        var params: [String: Any] = [
            "category": "spot",
            "symbol": normalizedSymbol,
            "side": side == .buy ? "Buy" : "Sell",
            "orderType": limitPrice != nil ? "Limit" : "Market",
            "qty": String(format: "%.8f", quantity),
            "triggerPrice": String(format: "%.8f", stopPrice),
            "triggerDirection": side == .buy ? 1 : 2  // 1=rise, 2=fall
        ]
        
        if let limitPrice = limitPrice {
            params["price"] = String(format: "%.8f", limitPrice)
            params["timeInForce"] = "GTC"
        }
        
        let jsonData = try JSONSerialization.data(withJSONObject: params)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
        
        let signString = timestamp + credentials.apiKey + recvWindow + jsonString
        let signature = hmacSHA256HexBybit(message: signString, key: credentials.apiSecret)
        
        var request = URLRequest(url: URL(string: "https://api.bybit.com/v5/order/create")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(credentials.apiKey, forHTTPHeaderField: "X-BAPI-API-KEY")
        request.setValue(timestamp, forHTTPHeaderField: "X-BAPI-TIMESTAMP")
        request.setValue(signature, forHTTPHeaderField: "X-BAPI-SIGN")
        request.setValue(recvWindow, forHTTPHeaderField: "X-BAPI-RECV-WINDOW")
        request.httpBody = jsonData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return OrderResult(success: false, errorMessage: "Invalid response", exchange: "bybit")
        }
        
        if httpResponse.statusCode == 200,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let retCode = json["retCode"] as? Int, retCode == 0,
           let result = json["result"] as? [String: Any],
           let orderId = result["orderId"] as? String {
            return OrderResult(success: true, orderId: orderId, exchange: "bybit")
        }
        
        let errorMsg = parseBybitError(data: data, statusCode: httpResponse.statusCode)
        return OrderResult(success: false, errorMessage: errorMsg, exchange: "bybit")
    }
    
    private func fetchBybitBalances(credentials: TradingCredentials) async throws -> [AssetBalance] {
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let recvWindow = "5000"
        let queryString = "accountType=UNIFIED"
        
        let signString = timestamp + credentials.apiKey + recvWindow + queryString
        let signature = hmacSHA256HexBybit(message: signString, key: credentials.apiSecret)
        
        var request = URLRequest(url: URL(string: "https://api.bybit.com/v5/account/wallet-balance?\(queryString)")!)
        request.httpMethod = "GET"
        request.setValue(credentials.apiKey, forHTTPHeaderField: "X-BAPI-API-KEY")
        request.setValue(timestamp, forHTTPHeaderField: "X-BAPI-TIMESTAMP")
        request.setValue(signature, forHTTPHeaderField: "X-BAPI-SIGN")
        request.setValue(recvWindow, forHTTPHeaderField: "X-BAPI-RECV-WINDOW")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TradingError.apiError(message: "Failed to fetch Bybit balances")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let retCode = json["retCode"] as? Int, retCode == 0,
              let result = json["result"] as? [String: Any],
              let list = result["list"] as? [[String: Any]] else {
            throw TradingError.parseError
        }
        
        var balances: [AssetBalance] = []
        for account in list {
            if let coins = account["coin"] as? [[String: Any]] {
                for coin in coins {
                    guard let asset = coin["coin"] as? String,
                          let walletBalance = coin["walletBalance"] as? String,
                          let free = Double(walletBalance),
                          free > 0 else { continue }
                    
                    let locked = Double(coin["locked"] as? String ?? "0") ?? 0
                    balances.append(AssetBalance(asset: asset, free: free, locked: locked))
                }
            }
        }
        
        return balances
    }
    
    private func testBybitConnection(credentials: TradingCredentials) async throws -> Bool {
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let recvWindow = "5000"
        let queryString = "accountType=UNIFIED"
        
        let signString = timestamp + credentials.apiKey + recvWindow + queryString
        let signature = hmacSHA256HexBybit(message: signString, key: credentials.apiSecret)
        
        var request = URLRequest(url: URL(string: "https://api.bybit.com/v5/account/wallet-balance?\(queryString)")!)
        request.httpMethod = "GET"
        request.setValue(credentials.apiKey, forHTTPHeaderField: "X-BAPI-API-KEY")
        request.setValue(timestamp, forHTTPHeaderField: "X-BAPI-TIMESTAMP")
        request.setValue(signature, forHTTPHeaderField: "X-BAPI-SIGN")
        request.setValue(recvWindow, forHTTPHeaderField: "X-BAPI-RECV-WINDOW")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return false
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let retCode = json["retCode"] as? Int, retCode == 0 {
            return true
        }
        
        return false
    }
    
    private func fetchBybitOpenOrders(credentials: TradingCredentials, symbol: String?) async throws -> [OpenOrder] {
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let recvWindow = "5000"
        
        var queryParams = "category=spot"
        if let symbol = symbol {
            queryParams += "&symbol=\(normalizeBybitSymbol(symbol))"
        }
        
        let signString = timestamp + credentials.apiKey + recvWindow + queryParams
        let signature = hmacSHA256HexBybit(message: signString, key: credentials.apiSecret)
        
        var request = URLRequest(url: URL(string: "https://api.bybit.com/v5/order/realtime?\(queryParams)")!)
        request.httpMethod = "GET"
        request.setValue(credentials.apiKey, forHTTPHeaderField: "X-BAPI-API-KEY")
        request.setValue(timestamp, forHTTPHeaderField: "X-BAPI-TIMESTAMP")
        request.setValue(signature, forHTTPHeaderField: "X-BAPI-SIGN")
        request.setValue(recvWindow, forHTTPHeaderField: "X-BAPI-RECV-WINDOW")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TradingError.apiError(message: "Failed to fetch Bybit open orders")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let retCode = json["retCode"] as? Int, retCode == 0,
              let result = json["result"] as? [String: Any],
              let list = result["list"] as? [[String: Any]] else {
            throw TradingError.parseError
        }
        
        var orders: [OpenOrder] = []
        for order in list {
            guard let orderId = order["orderId"] as? String,
                  let sym = order["symbol"] as? String,
                  let sideStr = order["side"] as? String,
                  let typeStr = order["orderType"] as? String,
                  let qtyStr = order["qty"] as? String,
                  let qty = Double(qtyStr) else { continue }
            
            let price = Double(order["price"] as? String ?? "0") ?? 0
            let createdTime = order["createdTime"] as? String ?? ""
            let createdAt = Double(createdTime).map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
            
            let filledQty = Double(order["cumExecQty"] as? String ?? "0") ?? 0
            let statusStr = order["orderStatus"] as? String ?? ""
            let status: OrderStatus = {
                switch statusStr.lowercased() {
                case "new", "created": return .new
                case "partiallyfilled": return .partiallyFilled
                case "filled": return .filled
                case "cancelled", "canceled": return .canceled
                case "rejected": return .rejected
                case "expired": return .expired
                default: return .new
                }
            }()
            
            orders.append(OpenOrder(
                id: orderId,
                exchange: .bybit,
                symbol: sym,
                side: sideStr.lowercased() == "buy" ? .buy : .sell,
                type: typeStr.lowercased() == "market" ? .market : .limit,
                price: price,
                quantity: qty,
                filledQuantity: filledQty,
                status: status,
                createdAt: createdAt
            ))
        }
        
        return orders
    }
    
    private func cancelBybitOrder(credentials: TradingCredentials, orderId: String, symbol: String) async throws -> CancelOrderResult {
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let recvWindow = "5000"
        
        let params: [String: Any] = [
            "category": "spot",
            "symbol": normalizeBybitSymbol(symbol),
            "orderId": orderId
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: params)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
        
        let signString = timestamp + credentials.apiKey + recvWindow + jsonString
        let signature = hmacSHA256HexBybit(message: signString, key: credentials.apiSecret)
        
        var request = URLRequest(url: URL(string: "https://api.bybit.com/v5/order/cancel")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(credentials.apiKey, forHTTPHeaderField: "X-BAPI-API-KEY")
        request.setValue(timestamp, forHTTPHeaderField: "X-BAPI-TIMESTAMP")
        request.setValue(signature, forHTTPHeaderField: "X-BAPI-SIGN")
        request.setValue(recvWindow, forHTTPHeaderField: "X-BAPI-RECV-WINDOW")
        request.httpBody = jsonData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return CancelOrderResult(success: false, orderId: orderId, exchange: .bybit, errorMessage: "Invalid response")
        }
        
        if httpResponse.statusCode == 200,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let retCode = json["retCode"] as? Int, retCode == 0 {
            return CancelOrderResult(success: true, orderId: orderId, exchange: .bybit)
        }
        
        let errorMsg = parseBybitError(data: data, statusCode: httpResponse.statusCode)
        return CancelOrderResult(success: false, orderId: orderId, exchange: .bybit, errorMessage: errorMsg)
    }
    
    // MARK: - Bybit Helpers
    
    private func normalizeBybitSymbol(_ symbol: String) -> String {
        let upper = symbol.uppercased()
        // Bybit uses format like BTCUSDT (no separator)
        if upper.contains("-") {
            return upper.replacingOccurrences(of: "-", with: "")
        }
        if upper.contains("/") {
            return upper.replacingOccurrences(of: "/", with: "")
        }
        if !upper.hasSuffix("USDT") && !upper.hasSuffix("USD") && !upper.hasSuffix("USDC") {
            return upper + "USDT"
        }
        return upper
    }
    
    private func hmacSHA256HexBybit(message: String, key: String) -> String {
        guard let keyData = key.data(using: .utf8),
              let messageData = message.data(using: .utf8) else {
            return ""
        }
        
        var macData = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        macData.withUnsafeMutableBytes { macPtr in
            keyData.withUnsafeBytes { keyPtr in
                messageData.withUnsafeBytes { messagePtr in
                    CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256),
                           keyPtr.baseAddress, keyData.count,
                           messagePtr.baseAddress, messageData.count,
                           macPtr.baseAddress)
                }
            }
        }
        
        return macData.map { String(format: "%02x", $0) }.joined()
    }
    
    private func parseBybitError(data: Data, statusCode: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let retMsg = json["retMsg"] as? String, !retMsg.isEmpty && retMsg != "OK" {
                return retMsg
            }
            if let retCode = json["retCode"] as? Int, retCode != 0 {
                return "Bybit error code: \(retCode)"
            }
        }
        return "Request failed with status code \(statusCode)"
    }
    
    // MARK: - OKX Implementation
    
    private func submitOKXOrder(
        credentials: TradingCredentials,
        symbol: String,
        side: TradeSide,
        type: OrderType,
        quantity: Double,
        price: Double?
    ) async throws -> OrderResult {
        let normalizedSymbol = normalizeOKXSymbol(symbol)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        
        var params: [String: Any] = [
            "instId": normalizedSymbol,
            "tdMode": "cash",  // Spot trading
            "side": side == .buy ? "buy" : "sell",
            "ordType": type == .market ? "market" : "limit",
            "sz": String(format: "%.8f", quantity)
        ]
        
        if type == .limit, let price = price {
            params["px"] = String(format: "%.8f", price)
        }
        
        let jsonData = try JSONSerialization.data(withJSONObject: params)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
        
        let signString = timestamp + "POST" + "/api/v5/trade/order" + jsonString
        let signature = hmacSHA256Base64OKX(message: signString, key: credentials.apiSecret)
        
        var request = URLRequest(url: URL(string: "https://www.okx.com/api/v5/trade/order")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(credentials.apiKey, forHTTPHeaderField: "OK-ACCESS-KEY")
        request.setValue(signature, forHTTPHeaderField: "OK-ACCESS-SIGN")
        request.setValue(timestamp, forHTTPHeaderField: "OK-ACCESS-TIMESTAMP")
        request.setValue(credentials.passphrase ?? "", forHTTPHeaderField: "OK-ACCESS-PASSPHRASE")
        request.httpBody = jsonData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return OrderResult(success: false, errorMessage: "Invalid response", exchange: "okx")
        }
        
        if httpResponse.statusCode == 200,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let code = json["code"] as? String, code == "0",
           let dataArray = json["data"] as? [[String: Any]],
           let first = dataArray.first,
           let orderId = first["ordId"] as? String {
            return OrderResult(success: true, orderId: orderId, exchange: "okx")
        }
        
        let errorMsg = parseOKXError(data: data, statusCode: httpResponse.statusCode)
        return OrderResult(success: false, errorMessage: errorMsg, exchange: "okx")
    }
    
    private func submitOKXStopOrder(
        credentials: TradingCredentials,
        symbol: String,
        side: TradeSide,
        quantity: Double,
        stopPrice: Double,
        limitPrice: Double?
    ) async throws -> OrderResult {
        let normalizedSymbol = normalizeOKXSymbol(symbol)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        
        var params: [String: Any] = [
            "instId": normalizedSymbol,
            "tdMode": "cash",
            "side": side == .buy ? "buy" : "sell",
            "ordType": limitPrice != nil ? "conditional" : "trigger",
            "sz": String(format: "%.8f", quantity),
            "triggerPx": String(format: "%.8f", stopPrice),
            "triggerPxType": "last"  // Trigger on last price
        ]
        
        if let limitPrice = limitPrice {
            params["ordPx"] = String(format: "%.8f", limitPrice)
        } else {
            params["ordPx"] = "-1"  // Market order when triggered
        }
        
        let jsonData = try JSONSerialization.data(withJSONObject: params)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
        
        let signString = timestamp + "POST" + "/api/v5/trade/order-algo" + jsonString
        let signature = hmacSHA256Base64OKX(message: signString, key: credentials.apiSecret)
        
        var request = URLRequest(url: URL(string: "https://www.okx.com/api/v5/trade/order-algo")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(credentials.apiKey, forHTTPHeaderField: "OK-ACCESS-KEY")
        request.setValue(signature, forHTTPHeaderField: "OK-ACCESS-SIGN")
        request.setValue(timestamp, forHTTPHeaderField: "OK-ACCESS-TIMESTAMP")
        request.setValue(credentials.passphrase ?? "", forHTTPHeaderField: "OK-ACCESS-PASSPHRASE")
        request.httpBody = jsonData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return OrderResult(success: false, errorMessage: "Invalid response", exchange: "okx")
        }
        
        if httpResponse.statusCode == 200,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let code = json["code"] as? String, code == "0",
           let dataArray = json["data"] as? [[String: Any]],
           let first = dataArray.first,
           let orderId = first["algoId"] as? String {
            return OrderResult(success: true, orderId: orderId, exchange: "okx")
        }
        
        let errorMsg = parseOKXError(data: data, statusCode: httpResponse.statusCode)
        return OrderResult(success: false, errorMessage: errorMsg, exchange: "okx")
    }
    
    private func fetchOKXBalances(credentials: TradingCredentials) async throws -> [AssetBalance] {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let signString = timestamp + "GET" + "/api/v5/account/balance"
        let signature = hmacSHA256Base64OKX(message: signString, key: credentials.apiSecret)
        
        var request = URLRequest(url: URL(string: "https://www.okx.com/api/v5/account/balance")!)
        request.httpMethod = "GET"
        request.setValue(credentials.apiKey, forHTTPHeaderField: "OK-ACCESS-KEY")
        request.setValue(signature, forHTTPHeaderField: "OK-ACCESS-SIGN")
        request.setValue(timestamp, forHTTPHeaderField: "OK-ACCESS-TIMESTAMP")
        request.setValue(credentials.passphrase ?? "", forHTTPHeaderField: "OK-ACCESS-PASSPHRASE")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TradingError.apiError(message: "Failed to fetch OKX balances")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = json["code"] as? String, code == "0",
              let dataArray = json["data"] as? [[String: Any]] else {
            throw TradingError.parseError
        }
        
        var balances: [AssetBalance] = []
        for account in dataArray {
            if let details = account["details"] as? [[String: Any]] {
                for detail in details {
                    guard let asset = detail["ccy"] as? String,
                          let availBalStr = detail["availBal"] as? String,
                          let availBal = Double(availBalStr),
                          availBal > 0 else { continue }
                    
                    let frozenBalStr = detail["frozenBal"] as? String ?? "0"
                    let frozenBal = Double(frozenBalStr) ?? 0
                    
                    balances.append(AssetBalance(asset: asset, free: availBal, locked: frozenBal))
                }
            }
        }
        
        return balances
    }
    
    private func testOKXConnection(credentials: TradingCredentials) async throws -> Bool {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let signString = timestamp + "GET" + "/api/v5/account/balance"
        let signature = hmacSHA256Base64OKX(message: signString, key: credentials.apiSecret)
        
        var request = URLRequest(url: URL(string: "https://www.okx.com/api/v5/account/balance")!)
        request.httpMethod = "GET"
        request.setValue(credentials.apiKey, forHTTPHeaderField: "OK-ACCESS-KEY")
        request.setValue(signature, forHTTPHeaderField: "OK-ACCESS-SIGN")
        request.setValue(timestamp, forHTTPHeaderField: "OK-ACCESS-TIMESTAMP")
        request.setValue(credentials.passphrase ?? "", forHTTPHeaderField: "OK-ACCESS-PASSPHRASE")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return false
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let code = json["code"] as? String, code == "0" {
            return true
        }
        
        return false
    }
    
    private func fetchOKXOpenOrders(credentials: TradingCredentials, symbol: String?) async throws -> [OpenOrder] {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        var path = "/api/v5/trade/orders-pending"
        if let symbol = symbol {
            path += "?instId=\(normalizeOKXSymbol(symbol))"
        }
        
        let signString = timestamp + "GET" + path
        let signature = hmacSHA256Base64OKX(message: signString, key: credentials.apiSecret)
        
        var request = URLRequest(url: URL(string: "https://www.okx.com\(path)")!)
        request.httpMethod = "GET"
        request.setValue(credentials.apiKey, forHTTPHeaderField: "OK-ACCESS-KEY")
        request.setValue(signature, forHTTPHeaderField: "OK-ACCESS-SIGN")
        request.setValue(timestamp, forHTTPHeaderField: "OK-ACCESS-TIMESTAMP")
        request.setValue(credentials.passphrase ?? "", forHTTPHeaderField: "OK-ACCESS-PASSPHRASE")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TradingError.apiError(message: "Failed to fetch OKX open orders")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = json["code"] as? String, code == "0",
              let dataArray = json["data"] as? [[String: Any]] else {
            throw TradingError.parseError
        }
        
        var orders: [OpenOrder] = []
        for orderData in dataArray {
            guard let orderId = orderData["ordId"] as? String,
                  let instId = orderData["instId"] as? String,
                  let sideStr = orderData["side"] as? String,
                  let ordTypeStr = orderData["ordType"] as? String,
                  let pxStr = orderData["px"] as? String,
                  let szStr = orderData["sz"] as? String,
                  let filledSzStr = orderData["accFillSz"] as? String,
                  let stateStr = orderData["state"] as? String,
                  let cTimeStr = orderData["cTime"] as? String else { continue }
            
            let side: TradeSide = sideStr == "buy" ? .buy : .sell
            let type: OrderType = ordTypeStr == "market" ? .market : .limit
            let price = Double(pxStr) ?? 0
            let quantity = Double(szStr) ?? 0
            let filledQuantity = Double(filledSzStr) ?? 0
            let createdAt = Date(timeIntervalSince1970: (Double(cTimeStr) ?? 0) / 1000)
            
            let status: OrderStatus = {
                switch stateStr {
                case "live": return .new
                case "partially_filled": return .partiallyFilled
                case "filled": return .filled
                case "canceled": return .canceled
                default: return .pending
                }
            }()
            
            orders.append(OpenOrder(
                id: orderId,
                exchange: .okx,
                symbol: instId,
                side: side,
                type: type,
                price: price,
                quantity: quantity,
                filledQuantity: filledQuantity,
                status: status,
                createdAt: createdAt
            ))
        }
        
        return orders
    }
    
    private func cancelOKXOrder(credentials: TradingCredentials, orderId: String, symbol: String) async throws -> CancelOrderResult {
        let normalizedSymbol = normalizeOKXSymbol(symbol)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        
        let params: [String: Any] = [
            "instId": normalizedSymbol,
            "ordId": orderId
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: params)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
        
        let signString = timestamp + "POST" + "/api/v5/trade/cancel-order" + jsonString
        let signature = hmacSHA256Base64OKX(message: signString, key: credentials.apiSecret)
        
        var request = URLRequest(url: URL(string: "https://www.okx.com/api/v5/trade/cancel-order")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(credentials.apiKey, forHTTPHeaderField: "OK-ACCESS-KEY")
        request.setValue(signature, forHTTPHeaderField: "OK-ACCESS-SIGN")
        request.setValue(timestamp, forHTTPHeaderField: "OK-ACCESS-TIMESTAMP")
        request.setValue(credentials.passphrase ?? "", forHTTPHeaderField: "OK-ACCESS-PASSPHRASE")
        request.httpBody = jsonData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return CancelOrderResult(success: false, orderId: orderId, exchange: .okx, errorMessage: "Invalid response")
        }
        
        if httpResponse.statusCode == 200,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let code = json["code"] as? String, code == "0" {
            return CancelOrderResult(success: true, orderId: orderId, exchange: .okx)
        }
        
        let errorMsg = parseOKXError(data: data, statusCode: httpResponse.statusCode)
        return CancelOrderResult(success: false, orderId: orderId, exchange: .okx, errorMessage: errorMsg)
    }
    
    // MARK: - OKX Helpers
    
    private func normalizeOKXSymbol(_ symbol: String) -> String {
        let upper = symbol.uppercased()
        // OKX uses format like BTC-USDT (with hyphen)
        if upper.contains("-") {
            return upper
        }
        // Convert BTCUSDT to BTC-USDT
        let quotes = ["USDT", "USDC", "USD", "BTC", "ETH"]
        for quote in quotes {
            if upper.hasSuffix(quote) {
                let base = String(upper.dropLast(quote.count))
                return "\(base)-\(quote)"
            }
        }
        return upper
    }
    
    private func hmacSHA256Base64OKX(message: String, key: String) -> String {
        let messageData = Data(message.utf8)
        let keyData = Data(key.utf8)
        
        var macData = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        keyData.withUnsafeBytes { keyBytes in
            messageData.withUnsafeBytes { messageBytes in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256),
                       keyBytes.baseAddress, keyData.count,
                       messageBytes.baseAddress, messageData.count,
                       &macData)
            }
        }
        
        return Data(macData).base64EncodedString()
    }
    
    private func parseOKXError(data: Data, statusCode: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let msg = json["msg"] as? String, !msg.isEmpty {
                return msg
            }
            if let dataArray = json["data"] as? [[String: Any]],
               let first = dataArray.first,
               let sMsg = first["sMsg"] as? String, !sMsg.isEmpty {
                return sMsg
            }
            if let code = json["code"] as? String, code != "0" {
                return "OKX error code: \(code)"
            }
        }
        return "Request failed with status code \(statusCode)"
    }
}

