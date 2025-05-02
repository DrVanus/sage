//
//  GlobalMarketData.swift
//  CSAI1
//
//  Created by DM on 4/30/25.
//


// GlobalMarketData.swift
// Models the JSON returned by CoinGecko’s `/global` endpoint


import Foundation

/// Wrapper for CoinGecko’s `/global` endpoint.
public struct GlobalDataResponse: Codable {
    public let data: GlobalMarketData
}


/// Represents the “data” object inside the CoinGecko /global response.
public struct GlobalMarketData: Codable {
    /// Total market cap by currency (e.g. ["usd": 1.2e12])
    public let totalMarketCap: [String: Double]
    /// Total 24h volume by currency
    public let totalVolume: [String: Double]
    /// Market cap dominance percentages (e.g. ["btc": 48.2, "eth": 18.5])
    public let marketCapPercentage: [String: Double]
    /// 24h change in USD (%) for total market cap
    public let marketCapChangePercentage24HUsd: Double
    /// Number of active cryptocurrencies tracked
    public let activeCryptocurrencies: Int
    /// Number of markets/exchanges tracked
    public let markets: Int

    private enum CodingKeys: String, CodingKey {
        case totalMarketCap               = "total_market_cap",
             totalVolume                  = "total_volume",
             marketCapPercentage          = "market_cap_percentage",
             marketCapChangePercentage24HUsd = "market_cap_change_percentage_24h_usd",
             activeCryptocurrencies       = "active_cryptocurrencies",
             markets                     = "markets"
    }

    // MARK: - Decodable with debug
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalMarketCap = try container.decode([String: Double].self, forKey: .totalMarketCap)
        totalVolume = try container.decode([String: Double].self, forKey: .totalVolume)
        marketCapPercentage = try container.decode([String: Double].self, forKey: .marketCapPercentage)
        marketCapChangePercentage24HUsd = try container.decode(Double.self, forKey: .marketCapChangePercentage24HUsd)
        activeCryptocurrencies = try container.decode(Int.self, forKey: .activeCryptocurrencies)
        markets = try container.decode(Int.self, forKey: .markets)
        print("✅ GlobalMarketData decoded:",
              "marketCap=\(totalMarketCap["usd"] ?? 0)",
              "volume=\(totalVolume["usd"] ?? 0)",
              "btcDom=\(marketCapPercentage["btc"] ?? 0)",
              "ethDom=\(marketCapPercentage["eth"] ?? 0)",
              "cryptos=\(activeCryptocurrencies)",
              "24hChange=\(marketCapChangePercentage24HUsd)")
    }
}
