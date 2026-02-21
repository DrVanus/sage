//
//  GlobalMarketData.swift
//  CSAI1
//
//  Created by DM on 4/30/25.
//

// GlobalMarketData.swift
// Models the JSON returned by CoinGecko’s `/global` endpoint


import Foundation

/// Minimal type-erased decodable to coerce legacy JSON values
private struct AnyDecodable: Decodable {
    let value: Any
    var doubleValue: Double? {
        switch value {
        case let d as Double: return d
        case let i as Int: return Double(i)
        case let s as String: return Double(s)
        default: return nil
        }
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let d = try? container.decode(Double.self) { value = d; return }
        if let i = try? container.decode(Int.self) { value = i; return }
        if let s = try? container.decode(String.self) { value = s; return }
        if let b = try? container.decode(Bool.self) { value = b; return }
        if let dict = try? container.decode([String: AnyDecodable].self) { value = dict; return }
        if let array = try? container.decode([AnyDecodable].self) { value = array; return }
        value = NSNull()
    }
}

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
    
    // MARK: - Memberwise Initializer (for Firebase proxy conversion)
    public init(
        totalMarketCap: [String: Double],
        totalVolume: [String: Double],
        marketCapPercentage: [String: Double],
        marketCapChangePercentage24HUsd: Double,
        activeCryptocurrencies: Int,
        markets: Int
    ) {
        self.totalMarketCap = totalMarketCap
        self.totalVolume = totalVolume
        self.marketCapPercentage = marketCapPercentage
        self.marketCapChangePercentage24HUsd = marketCapChangePercentage24HUsd
        self.activeCryptocurrencies = activeCryptocurrencies
        self.markets = markets
    }

    // MARK: - Decodable with debug
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        func decodeDictOrNumber(_ key: CodingKeys) throws -> [String: Double] {
            if let dict = try? container.decode([String: Double].self, forKey: key) {
                return dict
            }
            if let num = try? container.decode(Double.self, forKey: key) {
                // Repair legacy shape by mapping the number to USD
                return ["usd": num]
            }
            // Some older caches stored strings; try string->double
            if let strDict = try? container.decode([String: String].self, forKey: key) {
                var out: [String: Double] = [:]
                for (k, v) in strDict { if let d = Double(v) { out[k] = d } }
                if !out.isEmpty { return out }
            }
            // As a last resort, decode a generic JSON object and try to coerce
            if let any = try? container.decode([String: AnyDecodable].self, forKey: key) {
                var out: [String: Double] = [:]
                for (k, v) in any { if let d = v.doubleValue { out[k] = d } }
                if !out.isEmpty { return out }
            }
            return [:]
        }

        totalMarketCap = try decodeDictOrNumber(.totalMarketCap)
        totalVolume = try decodeDictOrNumber(.totalVolume)
        marketCapPercentage = (try? container.decode([String: Double].self, forKey: .marketCapPercentage)) ?? [:]
        marketCapChangePercentage24HUsd = (try? container.decode(Double.self, forKey: .marketCapChangePercentage24HUsd)) ?? 0
        activeCryptocurrencies = (try? container.decode(Int.self, forKey: .activeCryptocurrencies)) ?? 0
        markets = (try? container.decode(Int.self, forKey: .markets)) ?? 0

        // Debug log for visibility
        DebugLog.log("GlobalMarketData", "decoded: marketCap=\(totalMarketCap["usd"] ?? 0) volume=\(totalVolume["usd"] ?? 0) btcDom=\(marketCapPercentage["btc"] ?? 0) ethDom=\(marketCapPercentage["eth"] ?? 0)")
    }
}

