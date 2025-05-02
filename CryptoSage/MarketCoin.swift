//
//  MarketCoin.swift
//  CryptoSage
//

import Foundation

/// Represents a single coin from Coingecko’s `/coins/markets` endpoint,
/// with additional computed fields for compatibility with existing views.
struct MarketCoin: Identifiable, Codable {
    // MARK: - Core JSON fields from CoinGecko
    let id: String
    let symbol: String
    let name: String
    /// URL of the coin’s image
    let imageUrl: URL?
    var priceUsd: Double?
    let marketCap: Double?
    let totalVolume: Double?
    let priceChangePercentage1hInCurrency: Double
    let priceChangePercentage24hInCurrency: Double
    let priceChangePercentage7dInCurrency: Double
    let sparklineIn7d: [Double]
    let marketCapRank: Int?
    let maxSupply: Double

    // MARK: - Legacy compatibility properties
    var volumeUsd24Hr: Double? { totalVolume }
    var changePercent24Hr: Double? { priceChangePercentage24hInCurrency }
    var hourlyChange: Double { priceChangePercentage1hInCurrency }
    var dailyChange: Double { priceChangePercentage24hInCurrency }
    var weeklyChange: Double { priceChangePercentage7dInCurrency }
    var iconUrl: URL? { imageUrl }

    // MARK: - CodingKeys (map Swift names to JSON keys)
    enum CodingKeys: String, CodingKey {
        case id, symbol, name
        case imageUrl = "image"
        case priceUsd = "current_price"
        case marketCap = "market_cap"
        case totalVolume = "total_volume"
        case priceChangePercentage1hInCurrency = "price_change_percentage_1h_in_currency"
        case priceChangePercentage24hInCurrency = "price_change_percentage_24h_in_currency"
        case priceChangePercentage7dInCurrency = "price_change_percentage_7d_in_currency"
        case sparklineIn7d = "sparkline_in_7d"
        case marketCapRank = "market_cap_rank"
        case maxSupply = "max_supply"
    }

    /// Creates a MarketCoin from a CoinGeckoCoin model
    init(gecko: CoinGeckoCoin) {
        self.id = gecko.id
        self.symbol = gecko.symbol
        self.name = gecko.name
        self.imageUrl = URL(string: gecko.image)
        self.priceUsd = gecko.currentPrice
        self.marketCap = gecko.marketCap
        self.totalVolume = gecko.totalVolume
        self.priceChangePercentage1hInCurrency = gecko.priceChangePercentage1h ?? 0.0
        self.priceChangePercentage24hInCurrency = gecko.priceChangePercentage24h ?? 0.0
        self.priceChangePercentage7dInCurrency = gecko.priceChangePercentage7d ?? 0.0
        self.sparklineIn7d = gecko.sparklineIn7d?.price ?? []
        self.marketCapRank = gecko.marketCapRank
        self.maxSupply = gecko.maxSupply ?? 0.0
    }
}
