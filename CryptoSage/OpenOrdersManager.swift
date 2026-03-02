//
//  OpenOrdersManager.swift
//  CryptoSage
//
//  Singleton manager for tracking and managing open/pending orders across all connected exchanges.
//

import Foundation
import Combine

/// Manages open orders state across all connected exchanges
@MainActor
public final class OpenOrdersManager: ObservableObject {
    
    // MARK: - Singleton
    
    public static let shared = OpenOrdersManager()
    
    // MARK: - Published State
    
    /// All open orders from all connected exchanges (real orders)
    @Published public private(set) var realOrders: [OpenOrder] = []
    
    /// Demo orders shown when demo mode is active
    @Published public private(set) var demoOrders: [OpenOrder] = []
    
    /// Returns demo orders when in demo mode, otherwise real orders
    public var orders: [OpenOrder] {
        DemoModeManager.isEnabled ? demoOrders : realOrders
    }
    
    /// Whether orders are currently being fetched
    @Published public private(set) var isLoading: Bool = false
    
    /// Last error message, if any
    @Published public var errorMessage: String?
    
    /// Last refresh timestamp
    @Published public private(set) var lastRefresh: Date?
    
    // MARK: - Private State
    
    private var refreshTask: Task<Void, Never>?
    private var autoRefreshTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    /// Auto-refresh interval in seconds (30 seconds)
    private let autoRefreshInterval: TimeInterval = 30
    
    // MARK: - Initialization
    
    private init() {
        // Seed demo orders immediately if demo mode is already enabled
        if DemoModeManager.isEnabled {
            seedDemoOrders()
        }
        
        // Observe credential changes to refresh orders when exchanges connect/disconnect
        NotificationCenter.default.publisher(for: .init("ExchangeCredentialsChanged"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { await self?.refreshAllOrders() }
            }
            .store(in: &cancellables)
        
        // Observe demo mode changes to seed/clear demo orders
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                if DemoModeManager.isEnabled {
                    self.seedDemoOrders()
                } else {
                    self.clearDemoOrders()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public API
    
    /// Refresh orders from all connected exchanges
    public func refreshAllOrders() async {
        // Cancel any existing refresh
        refreshTask?.cancel()
        
        refreshTask = Task {
            await performRefresh()
        }
        
        await refreshTask?.value
    }
    
    /// Refresh orders for a specific symbol across all exchanges
    public func refreshOrders(for symbol: String) async {
        isLoading = true
        errorMessage = nil
        
        let newOrders = await TradingExecutionService.shared.fetchAllOpenOrders()
        // Filter to the specific symbol
        let symbolUpper = symbol.uppercased()
        self.realOrders = newOrders.filter { 
            $0.symbol.uppercased().contains(symbolUpper) || 
            $0.baseAsset.uppercased() == symbolUpper 
        }
        lastRefresh = Date()
        
        isLoading = false
    }
    
    /// Cancel a specific order
    /// - Returns: true if cancellation was successful
    @discardableResult
    public func cancelOrder(_ order: OpenOrder) async -> Bool {
        do {
            let result = try await TradingExecutionService.shared.cancelOrder(
                exchange: order.exchange,
                orderId: order.id,
                symbol: order.symbol
            )
            
            if result.success {
                // Remove from local state immediately for responsive UI
                realOrders.removeAll { $0.id == order.id && $0.exchange == order.exchange }
                return true
            } else {
                errorMessage = result.errorMessage ?? "Failed to cancel order"
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            #if DEBUG
            print("[OpenOrdersManager] Failed to cancel order \(order.id): \(error)")
            #endif
            return false
        }
    }
    
    /// Cancel all open orders for a specific symbol
    public func cancelAllOrders(for symbol: String) async -> Int {
        let symbolOrders = orders(for: symbol)
        var cancelledCount = 0
        
        for order in symbolOrders {
            if await cancelOrder(order) {
                cancelledCount += 1
            }
        }
        
        return cancelledCount
    }
    
    /// Cancel all open orders for a specific exchange
    public func cancelAllOrders(for exchange: TradingExchange) async -> Int {
        let exchangeOrders = orders(for: exchange)
        var cancelledCount = 0
        
        for order in exchangeOrders {
            if await cancelOrder(order) {
                cancelledCount += 1
            }
        }
        
        return cancelledCount
    }
    
    // MARK: - Filtered Accessors
    
    /// Get orders for a specific symbol
    public func orders(for symbol: String) -> [OpenOrder] {
        let symbolUpper = symbol.uppercased()
        return orders.filter { 
            $0.symbol.uppercased().contains(symbolUpper) || 
            $0.baseAsset.uppercased() == symbolUpper 
        }
    }
    
    /// Get orders for a specific exchange
    public func orders(for exchange: TradingExchange) -> [OpenOrder] {
        orders.filter { $0.exchange == exchange }
    }
    
    /// Get buy orders only
    public var buyOrders: [OpenOrder] {
        orders.filter { $0.side == .buy }
    }
    
    /// Get sell orders only
    public var sellOrders: [OpenOrder] {
        orders.filter { $0.side == .sell }
    }
    
    /// Total count of open orders
    public var totalCount: Int {
        orders.count
    }
    
    /// Total value of all open orders (in quote currency, approximate)
    public var totalValue: Double {
        orders.reduce(0) { $0 + $1.totalValue }
    }
    
    // MARK: - Demo Mode
    
    /// Seeds sample demo orders for display when demo mode is active
    public func seedDemoOrders() {
        guard demoOrders.isEmpty else { return }
        
        let now = Date()
        
        // Sample BTC buy order - limit order at a discount
        let btcBuyOrder = OpenOrder(
            id: "demo-btc-buy-001",
            exchange: .binance,
            symbol: "BTCUSDT",
            side: .buy,
            type: .limit,
            price: 41250.00,
            quantity: 0.15,
            filledQuantity: 0.05,
            status: .partiallyFilled,
            createdAt: now.addingTimeInterval(-7200) // 2 hours ago
        )
        
        // Sample ETH sell order - limit order at premium
        let ethSellOrder = OpenOrder(
            id: "demo-eth-sell-002",
            exchange: .coinbase,
            symbol: "ETHUSD",
            side: .sell,
            type: .limit,
            price: 2450.00,
            quantity: 2.5,
            filledQuantity: 0,
            status: .new,
            createdAt: now.addingTimeInterval(-3600) // 1 hour ago
        )
        
        // Sample SOL buy order
        let solBuyOrder = OpenOrder(
            id: "demo-sol-buy-003",
            exchange: .binance,
            symbol: "SOLUSDT",
            side: .buy,
            type: .limit,
            price: 95.50,
            quantity: 25.0,
            filledQuantity: 10.0,
            status: .partiallyFilled,
            createdAt: now.addingTimeInterval(-1800) // 30 mins ago
        )
        
        // Sample DOGE sell order
        let dogeSellOrder = OpenOrder(
            id: "demo-doge-sell-004",
            exchange: .binance,
            symbol: "DOGEUSDT",
            side: .sell,
            type: .limit,
            price: 0.125,
            quantity: 10000.0,
            filledQuantity: 0,
            status: .new,
            createdAt: now.addingTimeInterval(-900) // 15 mins ago
        )
        
        demoOrders = [btcBuyOrder, ethSellOrder, solBuyOrder, dogeSellOrder]
        objectWillChange.send()
    }
    
    /// Clears all demo orders
    public func clearDemoOrders() {
        demoOrders.removeAll()
        objectWillChange.send()
    }
    
    // MARK: - Auto-Refresh
    
    /// Start auto-refreshing orders at regular intervals
    public func startAutoRefresh() {
        stopAutoRefresh()
        
        autoRefreshTask = Task {
            while !Task.isCancelled {
                await refreshAllOrders()
                try? await Task.sleep(nanoseconds: UInt64(autoRefreshInterval * 1_000_000_000))
            }
        }
    }
    
    /// Stop auto-refreshing orders
    public func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }
    
    // MARK: - Private Methods
    
    private func performRefresh() async {
        isLoading = true
        errorMessage = nil
        
        let newOrders = await TradingExecutionService.shared.fetchAllOpenOrders()
        
        // Only update if task wasn't cancelled
        if !Task.isCancelled {
            self.realOrders = newOrders
            self.lastRefresh = Date()
        }
        
        isLoading = false
    }
}

// MARK: - Convenience Extensions

extension OpenOrdersManager {
    
    /// Check if there are any open orders
    public var hasOpenOrders: Bool {
        !orders.isEmpty
    }
    
    /// Check if there are open orders for a specific symbol
    public func hasOpenOrders(for symbol: String) -> Bool {
        !orders(for: symbol).isEmpty
    }
    
    /// Get the count of open orders for a specific symbol
    public func orderCount(for symbol: String) -> Int {
        orders(for: symbol).count
    }
    
    /// Get unique symbols that have open orders
    public var symbolsWithOrders: [String] {
        Array(Set(orders.map { $0.baseAsset })).sorted()
    }
    
    /// Get unique exchanges that have open orders (sorted by display name for consistent UI)
    public var exchangesWithOrders: [TradingExchange] {
        Array(Set(orders.map { $0.exchange })).sorted { $0.displayName < $1.displayName }
    }
}
