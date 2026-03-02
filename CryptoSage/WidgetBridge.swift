//
//  WidgetBridge.swift
//  CryptoSage
//
//  Bridges main app data to widget extensions via App Groups UserDefaults.
//  Widgets read from the same keys using SharedDataProvider.
//

import Foundation
import WidgetKit

/// Syncs main app data to widgets via App Groups shared UserDefaults.
/// Requires the "group.com.dee.CryptoSage" App Group capability on both targets.
enum WidgetBridge {

    // MARK: - App Group

    private static let suiteName = "group.com.dee.CryptoSage"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    // MARK: - Keys (must match CryptoSageWidget/SharedDataProvider.swift)

    private enum Key {
        static let watchlist       = "widget_watchlist"
        static let portfolioTotal  = "widget_portfolio_total"
        static let fearGreedIndex  = "widget_fear_greed_index"
        static let lastUpdate      = "widget_last_update"
    }

    // MARK: - Watchlist / Market Data

    /// Call after MarketViewModel refreshes allCoins.
    /// Sends top coins (by market cap) to the widget.
    static func syncWatchlist(from coins: [MarketCoin]) {
        guard !coins.isEmpty else { return }
        let top = coins.prefix(10).map { coin in
            WidgetCoinSnapshot(
                id: coin.id,
                symbol: coin.symbol.uppercased(),
                name: coin.name,
                price: coin.priceUsd ?? 0,
                change24h: coin.priceChangePercentage24hInCurrency ?? 0,
                imageURL: coin.imageUrl?.absoluteString
            )
        }
        guard let data = try? JSONEncoder().encode(top) else { return }
        defaults?.set(data, forKey: Key.watchlist)
        defaults?.set(Date(), forKey: Key.lastUpdate)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Portfolio

    /// Call after PortfolioViewModel holdings update.
    static func syncPortfolio(holdings: [Holding]) {
        guard !holdings.isEmpty else { return }
        let totalValue = holdings.reduce(0) { $0 + $1.currentPrice * $1.quantity }
        let change24h = holdings.reduce(0) { total, h in
            let holdingValue = h.currentPrice * h.quantity
            let pctChange = h.dailyChange / 100.0
            return total + holdingValue * pctChange
        }
        let changePercent = totalValue > 0 ? (change24h / (totalValue - change24h)) * 100 : 0

        let sortedByValue = holdings.sorted { ($0.currentPrice * $0.quantity) > ($1.currentPrice * $1.quantity) }
        let topHoldings = sortedByValue.prefix(5).map { h in
            let value = h.currentPrice * h.quantity
            return WidgetHoldingSnapshot(
                id: h.coinSymbol.lowercased(),
                symbol: h.coinSymbol.uppercased(),
                value: value,
                percentage: totalValue > 0 ? (value / totalValue) * 100 : 0
            )
        }

        let portfolio = WidgetPortfolioSnapshot(
            totalValue: totalValue,
            change24h: change24h,
            changePercent: changePercent,
            topHoldings: topHoldings,
            lastUpdate: Date()
        )
        guard let data = try? JSONEncoder().encode(portfolio) else { return }
        defaults?.set(data, forKey: Key.portfolioTotal)
        defaults?.set(Date(), forKey: Key.lastUpdate)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Fear & Greed

    /// Call after ExtendedFearGreedViewModel fetches new data.
    static func syncFearGreed(value: Int, classification: String) {
        let fg = WidgetFearGreedSnapshot(
            value: value,
            classification: classification,
            timestamp: Date()
        )
        guard let data = try? JSONEncoder().encode(fg) else { return }
        defaults?.set(data, forKey: Key.fearGreedIndex)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Codable Snapshots (mirror WidgetCoinData / WidgetPortfolioData / WidgetFearGreedData)

/// Must be decodable by CryptoSageWidget/SharedDataProvider.swift WidgetCoinData
private struct WidgetCoinSnapshot: Codable {
    let id: String
    let symbol: String
    let name: String
    let price: Double
    let change24h: Double
    let imageURL: String?
}

/// Must be decodable by CryptoSageWidget/SharedDataProvider.swift WidgetPortfolioData
private struct WidgetPortfolioSnapshot: Codable {
    let totalValue: Double
    let change24h: Double
    let changePercent: Double
    let topHoldings: [WidgetHoldingSnapshot]
    let lastUpdate: Date
}

/// Must be decodable by CryptoSageWidget/SharedDataProvider.swift WidgetHolding
private struct WidgetHoldingSnapshot: Codable {
    let id: String
    let symbol: String
    let value: Double
    let percentage: Double
}

/// Must be decodable by CryptoSageWidget/SharedDataProvider.swift WidgetFearGreedData
private struct WidgetFearGreedSnapshot: Codable {
    let value: Int
    let classification: String
    let timestamp: Date
}
