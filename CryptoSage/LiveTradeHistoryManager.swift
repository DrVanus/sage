//
//  LiveTradeHistoryManager.swift
//  CryptoSage
//
//  Manages history of live trades executed on real exchanges.
//

import Foundation
import Combine

// MARK: - Live Trade Model

/// Model for a live trade record
public struct LiveTrade: Codable, Identifiable {
    public let id: UUID
    public let symbol: String
    public let side: TradeSide
    public let quantity: Double
    public let price: Double
    public let totalValue: Double
    public let orderType: String
    public let exchange: String
    public let orderId: String?
    public let status: String
    public let timestamp: Date
    public let fees: Double?
    
    public init(
        id: UUID = UUID(),
        symbol: String,
        side: TradeSide,
        quantity: Double,
        price: Double,
        orderType: String,
        exchange: String,
        orderId: String? = nil,
        status: String = "FILLED",
        timestamp: Date = Date(),
        fees: Double? = nil
    ) {
        self.id = id
        self.symbol = symbol
        self.side = side
        self.quantity = quantity
        self.price = price
        self.totalValue = quantity * price
        self.orderType = orderType
        self.exchange = exchange
        self.orderId = orderId
        self.status = status
        self.timestamp = timestamp
        self.fees = fees
    }
    
    /// Create from an OrderResult
    public static func from(
        result: OrderResult,
        symbol: String,
        side: TradeSide,
        quantity: Double,
        price: Double,
        orderType: OrderType
    ) -> LiveTrade {
        return LiveTrade(
            symbol: symbol,
            side: side,
            quantity: result.filledQuantity ?? quantity,
            price: result.averagePrice ?? price,
            orderType: orderType.rawValue,
            exchange: result.exchange,
            orderId: result.orderId,
            status: result.status?.rawValue ?? "FILLED",
            timestamp: result.timestamp
        )
    }
}

// MARK: - Live Trade History Manager

/// Singleton manager for tracking live trade history
@MainActor
public final class LiveTradeHistoryManager: ObservableObject {
    public static let shared = LiveTradeHistoryManager()
    
    // MARK: - Storage Keys
    private static let historyKey = "LiveTradeHistory"
    private static let maxHistoryCount = 1000
    
    // MARK: - Published Properties
    
    /// History of all live trades (most recent first)
    @Published public private(set) var tradeHistory: [LiveTrade] = []
    
    // MARK: - Initialization
    
    private init() {
        loadTradeHistory()
    }
    
    // MARK: - Public Methods
    
    /// Record a new live trade
    public func recordTrade(_ trade: LiveTrade) {
        tradeHistory.insert(trade, at: 0) // Most recent first
        saveTradeHistory()
    }
    
    /// Record a trade from an order result
    public func recordTrade(
        from result: OrderResult,
        symbol: String,
        side: TradeSide,
        quantity: Double,
        price: Double,
        orderType: OrderType
    ) {
        guard result.success else { return }
        
        let trade = LiveTrade.from(
            result: result,
            symbol: symbol,
            side: side,
            quantity: quantity,
            price: price,
            orderType: orderType
        )
        recordTrade(trade)
    }
    
    /// Get recent trades (limited)
    public func recentTrades(limit: Int = 10) -> [LiveTrade] {
        Array(tradeHistory.prefix(limit))
    }
    
    /// Get trades filtered by exchange
    public func trades(forExchange exchange: String?) -> [LiveTrade] {
        guard let exchange = exchange, !exchange.isEmpty else { return tradeHistory }
        return tradeHistory.filter { $0.exchange.lowercased() == exchange.lowercased() }
    }
    
    /// Get trades filtered by side
    public func trades(side: TradeSide?) -> [LiveTrade] {
        guard let side = side else { return tradeHistory }
        return tradeHistory.filter { $0.side == side }
    }
    
    /// Get trades filtered by symbol
    public func trades(forSymbol symbol: String?) -> [LiveTrade] {
        guard let symbol = symbol, !symbol.isEmpty else { return tradeHistory }
        let upperSymbol = symbol.uppercased()
        return tradeHistory.filter { $0.symbol.uppercased().contains(upperSymbol) }
    }
    
    /// Get trades with combined filters
    public func filteredTrades(
        exchange: String? = nil,
        side: TradeSide? = nil,
        symbol: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) -> [LiveTrade] {
        var result = tradeHistory
        
        if let exchange = exchange, !exchange.isEmpty {
            result = result.filter { $0.exchange.lowercased() == exchange.lowercased() }
        }
        
        if let side = side {
            result = result.filter { $0.side == side }
        }
        
        if let symbol = symbol, !symbol.isEmpty {
            let upperSymbol = symbol.uppercased()
            result = result.filter { $0.symbol.uppercased().contains(upperSymbol) }
        }
        
        if let startDate = startDate {
            result = result.filter { $0.timestamp >= startDate }
        }
        
        if let endDate = endDate {
            result = result.filter { $0.timestamp <= endDate }
        }
        
        return result
    }
    
    /// Clear all trade history
    public func clearHistory() {
        tradeHistory = []
        saveTradeHistory()
    }
    
    /// Delete a specific trade
    public func deleteTrade(_ trade: LiveTrade) {
        tradeHistory.removeAll { $0.id == trade.id }
        saveTradeHistory()
    }
    
    // MARK: - Statistics
    
    /// Total number of trades
    public var totalTradeCount: Int {
        tradeHistory.count
    }
    
    /// Number of buy trades
    public var buyTradeCount: Int {
        tradeHistory.filter { $0.side == .buy }.count
    }
    
    /// Number of sell trades
    public var sellTradeCount: Int {
        tradeHistory.filter { $0.side == .sell }.count
    }
    
    /// Total volume traded (sum of all trade values)
    public var totalVolumeTraded: Double {
        tradeHistory.map { $0.totalValue }.reduce(0, +)
    }
    
    /// Average trade size in USD value
    public var averageTradeSize: Double {
        guard !tradeHistory.isEmpty else { return 0.0 }
        let total = tradeHistory.map { $0.totalValue }.reduce(0, +)
        return total / Double(tradeHistory.count)
    }
    
    /// Date of first trade
    public var tradingSinceDate: Date? {
        tradeHistory.last?.timestamp
    }
    
    /// Get unique exchanges used
    public var exchangesUsed: [String] {
        Array(Set(tradeHistory.map { $0.exchange })).sorted()
    }
    
    /// Get unique symbols traded
    public var uniqueSymbolsTraded: [String] {
        Array(Set(tradeHistory.map { $0.symbol })).sorted()
    }
    
    /// Total fees paid
    public var totalFeesPaid: Double {
        tradeHistory.compactMap { $0.fees }.reduce(0, +)
    }
    
    /// Volume by exchange
    public var volumeByExchange: [String: Double] {
        var volumes: [String: Double] = [:]
        for trade in tradeHistory {
            volumes[trade.exchange, default: 0] += trade.totalValue
        }
        return volumes
    }
    
    // MARK: - Export
    
    /// Export trade history as CSV
    public func exportAsCSV() -> String {
        var csv = "Date,Symbol,Side,Quantity,Price,Total Value,Order Type,Exchange,Order ID,Status,Fees\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        for trade in tradeHistory {
            let date = dateFormatter.string(from: trade.timestamp)
            let fees = trade.fees.map { String(format: "%.4f", $0) } ?? ""
            let orderId = trade.orderId ?? ""
            let line = "\(date),\(trade.symbol),\(trade.side.rawValue),\(trade.quantity),\(trade.price),\(trade.totalValue),\(trade.orderType),\(trade.exchange),\(orderId),\(trade.status),\(fees)\n"
            csv += line
        }
        
        return csv
    }
    
    // MARK: - Persistence
    
    private func saveTradeHistory() {
        // Keep only the most recent trades to prevent excessive storage
        let trimmedHistory = Array(tradeHistory.prefix(Self.maxHistoryCount))
        if let data = try? JSONEncoder().encode(trimmedHistory) {
            UserDefaults.standard.set(data, forKey: Self.historyKey)
        }
    }
    
    private func loadTradeHistory() {
        if let data = UserDefaults.standard.data(forKey: Self.historyKey),
           let history = try? JSONDecoder().decode([LiveTrade].self, from: data) {
            self.tradeHistory = history
        }
    }
}
