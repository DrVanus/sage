//
//  EnhancedTradingEngine.swift
//  CryptoSage
//
//  Main orchestrator for Coinbase Advanced Trade integration
//  Coordinates all trading services and provides unified API
//

import Foundation
import SwiftUI
import Combine

/// Main trading engine that orchestrates all Coinbase trading services
@MainActor
public final class EnhancedTradingEngine: ObservableObject {
    public static let shared = EnhancedTradingEngine()

    // MARK: - Published State

    @Published public var isInitialized: Bool = false
    @Published public var isConnected: Bool = false
    @Published public var connectionStatus: ConnectionStatus = .disconnected
    @Published public var lastError: TradingError?

    // Trading state
    @Published public var isPaperTrading: Bool = true
    @Published public var tradingEnabled: Bool = false

    // Portfolio state
    @Published public var portfolioValue: Double = 0.0
    @Published public var portfolioChange24h: Double = 0.0
    @Published public var totalUnrealizedPL: Double = 0.0

    // Order state
    @Published public var activeOrders: [CoinbaseOrder] = []
    @Published public var recentTrades: [TradeRecord] = []

    // Account state
    @Published public var accounts: [CoinbaseAccount] = []

    // MARK: - Services

    private let coinbaseService = CoinbaseAdvancedTradeService.shared
    private let tradingVM = CoinbaseTradingViewModel.shared
    private let portfolioSync = CoinbasePortfolioSyncService.shared
    private let websocketService = CoinbaseWebSocketService.shared
    private let dcaService = CoinbaseDCAService.shared
    private let jwtAuth = CoinbaseJWTAuthService.shared

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Connection Status

    public enum ConnectionStatus: String {
        case disconnected = "Disconnected"
        case connecting = "Connecting..."
        case connected = "Connected"
        case error = "Connection Error"
        case syncing = "Syncing..."
    }

    // MARK: - Initialization

    private init() {
        setupBindings()
        checkCredentials()
    }

    private func setupBindings() {
        // Sync trading VM state
        tradingVM.$isPaperTrading
            .assign(to: &$isPaperTrading)

        tradingVM.$isConnected
            .assign(to: &$isConnected)

        tradingVM.$accounts
            .assign(to: &$accounts)

        tradingVM.$openOrders
            .assign(to: &$activeOrders)

        // Calculate portfolio metrics
        $accounts
            .map { accounts in
                accounts.reduce(0) { total, account in
                    let balance = account.totalBalance
                    // Get price from LivePriceManager
                    let price = MainActor.assumeIsolated {
                        MarketViewModel.shared.bestPrice(forSymbol: account.currency) ?? 0
                    }
                    return total + (balance * price)
                }
            }
            .assign(to: &$portfolioValue)
    }

    private func checkCredentials() {
        tradingEnabled = TradingCredentialsManager.shared.hasCredentials(for: .coinbase)
        if tradingEnabled {
            isInitialized = true
        }
    }

    // MARK: - Initialization & Connection

    /// Initialize the trading engine and connect to Coinbase
    public func initialize() async throws {
        connectionStatus = .connecting

        do {
            // Test connection
            let connected = try await coinbaseService.testConnection()

            if connected {
                isConnected = true
                connectionStatus = .connected
                isInitialized = true

                // Load initial data
                await loadInitialData()

                // Start services
                await startBackgroundServices()

                print("✅ Enhanced Trading Engine initialized successfully")
            } else {
                throw TradingError.connectionFailed
            }
        } catch {
            connectionStatus = .error
            lastError = .connectionFailed
            throw error
        }
    }

    private func loadInitialData() async {
        connectionStatus = .syncing

        await withTaskGroup(of: Void.self) { group in
            // Load accounts
            group.addTask {
                await self.tradingVM.loadAccounts()
            }

            // Load open orders
            group.addTask {
                await self.tradingVM.loadOpenOrders()
            }

            // Initial portfolio sync
            group.addTask {
                await self.portfolioSync.syncPortfolio()
            }
        }

        connectionStatus = .connected
    }

    private func startBackgroundServices() async {
        // Start portfolio auto-sync (every 2 minutes)
        await portfolioSync.startPolling()

        // Connect WebSocket for real-time prices
        let products = ["BTC-USD", "ETH-USD", "SOL-USD", "DOGE-USD", "XRP-USD"]
        try? await websocketService.connect(products: products, feeds: [.ticker])

        print("✅ Background services started")
    }

    /// Disconnect and cleanup
    public func disconnect() async {
        await portfolioSync.stopPolling()
        await websocketService.disconnect()

        isConnected = false
        connectionStatus = .disconnected

        print("🔌 Trading engine disconnected")
    }

    // MARK: - Order Placement

    /// Place a market order
    public func placeMarketOrder(
        productId: String,
        side: TradeSide,
        size: Double,
        isSizeInQuote: Bool = false
    ) async throws {
        guard isConnected || isPaperTrading else {
            throw TradingError.notConnected
        }

        try await tradingVM.placeMarketOrder(
            productId: productId,
            side: side,
            size: size,
            isSizeInQuote: isSizeInQuote
        )

        // Record trade
        let trade = TradeRecord(
            productId: productId,
            side: side,
            type: .market,
            size: size,
            price: nil,
            timestamp: Date(),
            isPaperTrade: isPaperTrading
        )
        recentTrades.insert(trade, at: 0)
    }

    /// Place a limit order
    public func placeLimitOrder(
        productId: String,
        side: TradeSide,
        size: Double,
        price: Double,
        postOnly: Bool = false
    ) async throws {
        guard isConnected || isPaperTrading else {
            throw TradingError.notConnected
        }

        try await tradingVM.placeLimitOrder(
            productId: productId,
            side: side,
            size: size,
            price: price,
            postOnly: postOnly
        )

        // Record trade
        let trade = TradeRecord(
            productId: productId,
            side: side,
            type: .limit,
            size: size,
            price: price,
            timestamp: Date(),
            isPaperTrade: isPaperTrading
        )
        recentTrades.insert(trade, at: 0)
    }

    /// Place a stop-loss order
    public func placeStopLossOrder(
        productId: String,
        side: TradeSide,
        size: Double,
        stopPrice: Double
    ) async throws -> CoinbaseOrderResponse {
        guard isConnected || isPaperTrading else {
            throw TradingError.notConnected
        }

        let response = try await coinbaseService.placeStopLossOrder(
            productId: productId,
            side: side.rawValue.uppercased(),
            size: size,
            stopPrice: stopPrice
        )

        if !response.success {
            throw TradingError.orderFailed(response.errorResponse?.message ?? "Unknown error")
        }

        // Record trade
        let trade = TradeRecord(
            productId: productId,
            side: side,
            type: .stopLoss,
            size: size,
            price: stopPrice,
            timestamp: Date(),
            isPaperTrade: isPaperTrading
        )
        recentTrades.insert(trade, at: 0)

        return response
    }

    /// Place a stop-limit order
    public func placeStopLimitOrder(
        productId: String,
        side: TradeSide,
        size: Double,
        stopPrice: Double,
        limitPrice: Double
    ) async throws -> CoinbaseOrderResponse {
        guard isConnected || isPaperTrading else {
            throw TradingError.notConnected
        }

        let response = try await coinbaseService.placeStopLimitOrder(
            productId: productId,
            side: side.rawValue.uppercased(),
            size: size,
            stopPrice: stopPrice,
            limitPrice: limitPrice
        )

        if !response.success {
            throw TradingError.orderFailed(response.errorResponse?.message ?? "Unknown error")
        }

        // Record trade
        let trade = TradeRecord(
            productId: productId,
            side: side,
            type: .stopLimit,
            size: size,
            price: limitPrice,
            timestamp: Date(),
            isPaperTrade: isPaperTrading
        )
        recentTrades.insert(trade, at: 0)

        return response
    }

    /// Cancel an order
    public func cancelOrder(orderId: String) async throws {
        try await tradingVM.cancelOrder(orderId: orderId)
        await tradingVM.loadOpenOrders()
    }

    // MARK: - DCA Management

    /// Setup a DCA strategy
    public func setupDCAStrategy(
        productId: String,
        amountUSD: Double,
        frequency: DCAStrategy.DCAFrequency
    ) async throws {
        let strategy = DCAStrategy(
            productId: productId,
            amountUSD: amountUSD,
            frequency: frequency,
            isActive: true,
            nextExecutionDate: Date()
        )

        try await dcaService.addStrategy(strategy)
        print("✅ DCA strategy created: \(productId) - $\(amountUSD) \(frequency.rawValue)")
    }

    /// Get all DCA strategies
    public func getDCAStrategies() async -> [DCAStrategy] {
        await dcaService.getAllStrategies()
    }

    /// Remove a DCA strategy
    public func removeDCAStrategy(id: UUID) async throws {
        try await dcaService.removeStrategy(id: id)
    }

    // MARK: - Portfolio Management

    /// Manually sync portfolio
    public func syncPortfolio() async {
        await portfolioSync.syncPortfolio()
        await tradingVM.loadAccounts()
    }

    /// Get balance for a specific currency
    public func getBalance(for currency: String) -> Double {
        tradingVM.getBalance(for: currency)
    }

    /// Calculate total portfolio value in USD
    public func calculatePortfolioValue() -> Double {
        portfolioValue
    }

    // MARK: - Real-Time Data

    /// Subscribe to real-time price updates
    public func subscribeToPriceUpdates(products: [String]) async throws {
        try await websocketService.connect(products: products, feeds: [.ticker])
    }

    /// Get price update publisher
    public var priceUpdatePublisher: AnyPublisher<WSTicker, Never> {
        websocketService.tickerPublisher
    }

    // MARK: - Risk Management

    /// Check if trading is allowed (risk checks)
    public func canTrade() -> Bool {
        guard tradingEnabled else { return false }
        guard isConnected || isPaperTrading else { return false }
        return TradingRiskAcknowledgmentManager.shared.canTrade
    }

    /// Enable/disable paper trading mode
    public func setPaperTrading(_ enabled: Bool) {
        isPaperTrading = enabled
        tradingVM.isPaperTrading = enabled
    }

    // MARK: - Statistics

    /// Get trading statistics
    public func getTradingStats() -> TradingStats {
        let totalTrades = recentTrades.count
        let paperTrades = recentTrades.filter { $0.isPaperTrade }.count
        let liveTrades = totalTrades - paperTrades

        return TradingStats(
            totalTrades: totalTrades,
            paperTrades: paperTrades,
            liveTrades: liveTrades,
            portfolioValue: portfolioValue,
            portfolioChange24h: portfolioChange24h,
            unrealizedPL: totalUnrealizedPL,
            activeOrders: activeOrders.count,
            connectedExchanges: isConnected ? 1 : 0
        )
    }
}

// MARK: - Supporting Types

public struct TradeRecord: Identifiable, Codable {
    public let id: UUID
    public let productId: String
    public let side: TradeSide
    public let type: OrderType
    public let size: Double
    public let price: Double?
    public let timestamp: Date
    public let isPaperTrade: Bool

    public init(
        id: UUID = UUID(),
        productId: String,
        side: TradeSide,
        type: OrderType,
        size: Double,
        price: Double?,
        timestamp: Date,
        isPaperTrade: Bool
    ) {
        self.id = id
        self.productId = productId
        self.side = side
        self.type = type
        self.size = size
        self.price = price
        self.timestamp = timestamp
        self.isPaperTrade = isPaperTrade
    }
}

public struct TradingStats {
    public let totalTrades: Int
    public let paperTrades: Int
    public let liveTrades: Int
    public let portfolioValue: Double
    public let portfolioChange24h: Double
    public let unrealizedPL: Double
    public let activeOrders: Int
    public let connectedExchanges: Int
}

