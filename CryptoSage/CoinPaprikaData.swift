//
//  CoinPaprikaData.swift
//  CSAI1
//
//  Created by DM on 3/30/25.
//
//  Refactored models for CoinPaprika responses.
//  These are not currently wired into the app, but are ready for a future
//  Paprika API integration.
//

import Foundation

// MARK: - Paprika Models

/// Represents a single coin/ticker payload returned by CoinPaprika.
/// Example endpoint: /v1/tickers/{id}?quotes=USD
struct CoinPaprikaData: Decodable {
    let id: String
    let symbol: String
    let name: String
    let rank: Int?

    let circulatingSupply: Double?
    let totalSupply: Double?
    let maxSupply: Double?
    let betaValue: Double?

    let firstDataAt: Date?
    let lastUpdated: Date?

    /// Quotes keyed by currency code (e.g., "USD", "BTC")
    let quotes: [String: PaprikaQuote]?

    enum CodingKeys: String, CodingKey {
        case id, symbol, name, rank, quotes
        case circulatingSupply = "circulating_supply"
        case totalSupply = "total_supply"
        case maxSupply = "max_supply"
        case betaValue = "beta_value"
        case firstDataAt = "first_data_at"
        case lastUpdated = "last_updated"
    }
}

/// A quote (price/volume/changes) for a specific currency (e.g., USD) in CoinPaprika.
struct PaprikaQuote: Decodable {
    let price: Double?
    let volume24h: Double?
    let marketCap: Double?
    let fullyDilutedMarketCap: Double?
    let percentChange1h: Double?
    let percentChange24h: Double?
    let percentChange7d: Double?

    enum CodingKeys: String, CodingKey {
        case price
        case volume24h = "volume_24h"
        case marketCap = "market_cap"
        case fullyDilutedMarketCap = "fully_diluted_market_cap"
        case percentChange1h = "percent_change_1h"
        case percentChange24h = "percent_change_24h"
        case percentChange7d = "percent_change_7d"
    }
}
