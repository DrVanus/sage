import Foundation

// Centralized helpers for "best" change percentages used across the app.
// These prefer the live rolling window from LivePriceManager, and fall back to
// provider (CoinGecko) values exposed via MarketCoin.unified*.
extension MarketCoin {
    /// Best-available 24h percent change: LivePriceManager first, then provider.
    var best24hPercent: Double? {
        LivePriceManager.shared.bestChange24hPercent(forSymbol: symbol) ?? unified24hPercent
    }

    /// Best-available 1h percent change: LivePriceManager first, then provider.
    var best1hPercent: Double? {
        LivePriceManager.shared.bestChange1hPercent(forSymbol: symbol) ?? unified1hPercent
    }

    /// Best-available 7d percent change: LivePriceManager first, then provider.
    var best7dPercent: Double? {
        LivePriceManager.shared.bestChange7dPercent(forSymbol: symbol) ?? unified7dPercent
    }

    // Fractions (e.g., 0.051 == 5.1%) derived from best percents.
    var best24hFraction: Double? { best24hPercent.map { $0 / 100.0 } }
    var best1hFraction: Double? { best1hPercent.map { $0 / 100.0 } }
    var best7dFraction: Double? { best7dPercent.map { $0 / 100.0 } }
}
