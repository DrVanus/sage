//
//  SharedDataProvider.swift
//  CryptoSageWidget
//
//  Shared data provider for widget data via App Groups.
//

import Foundation
import WidgetKit

/// App Group identifier for sharing data between main app and widget
let appGroupIdentifier = "group.com.dee.CryptoSage"

/// Keys for shared UserDefaults
enum WidgetDataKey {
    static let watchlist = "widget_watchlist"
    static let portfolioTotal = "widget_portfolio_total"
    static let portfolioChange24h = "widget_portfolio_change_24h"
    static let topHoldings = "widget_top_holdings"
    static let fearGreedIndex = "widget_fear_greed_index"
    static let lastUpdate = "widget_last_update"
}

// MARK: - Widget Data Models

/// Simplified coin data for widgets
struct WidgetCoinData: Codable, Identifiable {
    let id: String
    let symbol: String
    let name: String
    let price: Double
    let change24h: Double
    let imageURL: String?
    
    var formattedPrice: String {
        if price >= 1 {
            return String(format: "$%.2f", price)
        } else if price >= 0.01 {
            return String(format: "$%.4f", price)
        } else {
            return String(format: "$%.6f", price)
        }
    }
    
    var formattedChange: String {
        let sign = change24h >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", change24h))%"
    }
    
    var isPositive: Bool {
        change24h >= 0
    }
}

/// Portfolio summary for widget
struct WidgetPortfolioData: Codable {
    let totalValue: Double
    let change24h: Double
    let changePercent: Double
    let topHoldings: [WidgetHolding]
    let lastUpdate: Date
    
    var formattedTotal: String {
        if totalValue >= 1_000_000 {
            return String(format: "$%.2fM", totalValue / 1_000_000)
        } else if totalValue >= 1_000 {
            return String(format: "$%.1fK", totalValue / 1_000)
        } else {
            return String(format: "$%.2f", totalValue)
        }
    }
    
    var formattedChange: String {
        let sign = changePercent >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", changePercent))%"
    }
    
    var isPositive: Bool {
        changePercent >= 0
    }
}

/// Holding data for portfolio widget
struct WidgetHolding: Codable, Identifiable {
    let id: String
    let symbol: String
    let value: Double
    let percentage: Double
    
    var formattedValue: String {
        String(format: "$%.0f", value)
    }
}

/// Fear & Greed index data
struct WidgetFearGreedData: Codable {
    let value: Int
    let classification: String
    let timestamp: Date
    
    var sentiment: String {
        switch value {
        case 0..<25: return "Extreme Fear"
        case 25..<45: return "Fear"
        case 45..<55: return "Neutral"
        case 55..<75: return "Greed"
        default: return "Extreme Greed"
        }
    }
}

// MARK: - Shared Data Provider

/// Provides data to widgets from App Group shared storage
final class WidgetDataProvider {
    static let shared = WidgetDataProvider()
    
    private let defaults: UserDefaults?
    
    private init() {
        defaults = UserDefaults(suiteName: appGroupIdentifier)
    }
    
    // MARK: - Reading Data (Widget Side)
    
    func getWatchlistData() -> [WidgetCoinData] {
        guard let data = defaults?.data(forKey: WidgetDataKey.watchlist),
              let coins = try? JSONDecoder().decode([WidgetCoinData].self, from: data) else {
            return defaultWatchlist
        }
        return coins
    }
    
    func getPortfolioData() -> WidgetPortfolioData {
        guard let data = defaults?.data(forKey: WidgetDataKey.portfolioTotal),
              let portfolio = try? JSONDecoder().decode(WidgetPortfolioData.self, from: data) else {
            return defaultPortfolio
        }
        return portfolio
    }
    
    func getFearGreedData() -> WidgetFearGreedData {
        guard let data = defaults?.data(forKey: WidgetDataKey.fearGreedIndex),
              let fearGreed = try? JSONDecoder().decode(WidgetFearGreedData.self, from: data) else {
            return defaultFearGreed
        }
        return fearGreed
    }
    
    func getLastUpdate() -> Date? {
        defaults?.object(forKey: WidgetDataKey.lastUpdate) as? Date
    }
    
    // MARK: - Writing Data (Main App Side)
    
    func saveWatchlistData(_ coins: [WidgetCoinData]) {
        guard let data = try? JSONEncoder().encode(coins) else { return }
        defaults?.set(data, forKey: WidgetDataKey.watchlist)
        defaults?.set(Date(), forKey: WidgetDataKey.lastUpdate)
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    func savePortfolioData(_ portfolio: WidgetPortfolioData) {
        guard let data = try? JSONEncoder().encode(portfolio) else { return }
        defaults?.set(data, forKey: WidgetDataKey.portfolioTotal)
        defaults?.set(Date(), forKey: WidgetDataKey.lastUpdate)
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    func saveFearGreedData(_ fearGreed: WidgetFearGreedData) {
        guard let data = try? JSONEncoder().encode(fearGreed) else { return }
        defaults?.set(data, forKey: WidgetDataKey.fearGreedIndex)
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    // MARK: - Default Data (for previews and initial state)
    
    private var defaultWatchlist: [WidgetCoinData] {
        [
            WidgetCoinData(id: "bitcoin", symbol: "BTC", name: "Bitcoin", price: 94500, change24h: 2.5, imageURL: nil),
            WidgetCoinData(id: "ethereum", symbol: "ETH", name: "Ethereum", price: 3350, change24h: -1.2, imageURL: nil),
            WidgetCoinData(id: "solana", symbol: "SOL", name: "Solana", price: 185, change24h: 5.3, imageURL: nil)
        ]
    }
    
    private var defaultPortfolio: WidgetPortfolioData {
        WidgetPortfolioData(
            totalValue: 12500,
            change24h: 350,
            changePercent: 2.8,
            topHoldings: [
                WidgetHolding(id: "btc", symbol: "BTC", value: 8500, percentage: 68),
                WidgetHolding(id: "eth", symbol: "ETH", value: 2500, percentage: 20),
                WidgetHolding(id: "sol", symbol: "SOL", value: 1500, percentage: 12)
            ],
            lastUpdate: Date()
        )
    }
    
    private var defaultFearGreed: WidgetFearGreedData {
        WidgetFearGreedData(value: 65, classification: "Greed", timestamp: Date())
    }
}
