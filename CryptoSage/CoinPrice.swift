//
//  CoinPrice.swift
//  CryptoSage
//
//  Shared model representing price data for a coin.
//  Note: change24h is expressed as a percent (+/-), not absolute delta.
//

import Foundation

/// Represents a snapshot of price-related data for a cryptocurrency.
struct CoinPrice: Codable, Sendable, Equatable, Hashable, Identifiable {
    /// Stable identity for lists; uses the symbol as the unique key.
    var id: String { symbol }

    /// Lowercased symbol (e.g., "btc") or base symbol depending on context.
    let symbol: String
    /// Last traded price in USD (or the chosen fiat).
    let lastPrice: Double
    /// Opening price 24 hours ago.
    let openPrice: Double
    /// High price over the last 24 hours.
    let highPrice: Double
    /// Low price over the last 24 hours.
    let lowPrice: Double
    /// 24h volume in USD when available; otherwise nil.
    let volume: Double?
    /// 24h change as a percent (positive/negative). For example, +3.5 means +3.5%.
    let change24h: Double

    /// Absolute 24h change (last - open).
    var changeAbsolute: Double { lastPrice - openPrice }
    
    /// Uppercased symbol for display purposes.
    var displaySymbol: String { symbol.uppercased() }

    /// Returns a copy with an updated last price and derived fields adjusted conservatively.
    /// - Note: Recomputes change24h based on the stored openPrice; adjusts high/low bounds to include the new last.
    func updating(lastPrice newLast: Double) -> CoinPrice {
        let newHigh = max(highPrice, newLast)
        let newLow = min(lowPrice, newLast)
        let pct = openPrice > 0 ? ((newLast - openPrice) / openPrice) * 100.0 : change24h
        return CoinPrice(
            symbol: symbol,
            lastPrice: newLast,
            openPrice: openPrice,
            highPrice: newHigh,
            lowPrice: newLow,
            volume: volume,
            change24h: pct
        )
    }
}

extension CoinPrice {
    // MARK: - SwiftUI Preview / Test Samples
    static let sampleBTC = CoinPrice(
        symbol: "btc",
        lastPrice: 64_000,
        openPrice: 62_000,
        highPrice: 64_500,
        lowPrice: 61_500,
        volume: 12_300_000_000,
        change24h: ((64_000 - 62_000) / 62_000) * 100.0
    )

    static let sampleETH = CoinPrice(
        symbol: "eth",
        lastPrice: 3_250,
        openPrice: 3_150,
        highPrice: 3_300,
        lowPrice: 3_100,
        volume: 6_500_000_000,
        change24h: ((3_250 - 3_150) / 3_150) * 100.0
    )

    // MARK: - Formatting Helpers
    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        return f
    }()

    /// Formatted last price string in USD.
    var lastPriceString: String {
        CoinPrice.currencyFormatter.string(from: lastPrice as NSNumber) ?? "$\(lastPrice)"
    }

    /// Formatted 24h change percent with two decimal places.
    var changePercentString: String {
        String(format: "%.2f%%", change24h)
    }

    // MARK: - Convenience Updaters
    /// Returns a copy with an updated USD volume.
    func updating(volume newVolume: Double?) -> CoinPrice {
        CoinPrice(
            symbol: symbol,
            lastPrice: lastPrice,
            openPrice: openPrice,
            highPrice: highPrice,
            lowPrice: lowPrice,
            volume: newVolume,
            change24h: change24h
        )
    }

    // MARK: - Convenience Initializers
    /// Initializes a CoinPrice computing high/low bounds and percent change from last/open.
    init(symbol: String, lastPrice: Double, openPrice: Double, volume: Double? = nil) {
        let high = max(lastPrice, openPrice)
        let low = min(lastPrice, openPrice)
        let pct = openPrice > 0 ? ((lastPrice - openPrice) / openPrice) * 100.0 : 0
        self.symbol = symbol
        self.lastPrice = lastPrice
        self.openPrice = openPrice
        self.highPrice = high
        self.lowPrice = low
        self.volume = volume
        self.change24h = pct
    }
}
