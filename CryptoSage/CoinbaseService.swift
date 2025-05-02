//
//  CoinbaseService.swift
//  CSAI1
//
//  Created by DM on 3/21/25.
//  Updated with improved error handling, retry logic, coin pair filtering, session reuse,
//  and caching for invalid coin pair logging.
//

import Foundation

/// Model representing price data for a coin.
struct CoinPrice {
    let symbol: String
    let lastPrice: Double
    let openPrice: Double
    let highPrice: Double
    let lowPrice: Double
    let volume: Double?
    let change24h: Double
}

// MARK: – Coinbase Pro 24‑hr Stats Response
struct CoinbaseProStatsResponse: Decodable {
    let open: String
    let high: String
    let low: String
    let last: String
}

struct CoinbaseSpotPriceResponse: Decodable {
    let data: DataField?

    struct DataField: Decodable {
        let base: String
        let currency: String
        let amount: String
    }
}

actor CoinbaseService {
    private let validPairs: Set<String> = [
        "BTC-USD","ETH-USD","USDT-USD","XRP-USD","BNB-USD",
        "USDC-USD","SOL-USD","DOGE-USD","ADA-USD","TRX-USD",
        "WBTC-USD","WETH-USD","WEETH-USD","UNI-USD","DAI-USD",
        "APT-USD","TON-USD","LINK-USD","XLM-USD","WSTETH-USD",
        "AVAX-USD","SUI-USD","SHIB-USD","HBAR-USD","LTC-USD",
        "OM-USD","DOT-USD","BCH-USD","SUSDE-USD","AAVE-USD",
        "ATOM-USD","CRO-USD","NEAR-USD","PEPE-USD","OKB-USD",
        "CBBTC-USD","GT-USD"
    ]
    private var invalidPairsLogged: Set<String> = []

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    func fetchSpotPrice(
        coin: String = "BTC",
        fiat: String = "USD",
        maxRetries: Int = 3,
        allowUnlistedPairs: Bool = false
    ) async -> Double? {
        let pair = "\(coin.uppercased())-\(fiat.uppercased())"
        if !allowUnlistedPairs && !validPairs.contains(pair) {
            invalidPairsLogged.insert(pair)
            return nil
        }
        if !allowUnlistedPairs && invalidPairsLogged.contains(pair) {
            print("⚠️ [CoinbaseService] skipped invalid pair: \(pair)")
        }
        guard let url = URL(string: "https://api.coinbase.com/v2/prices/\(pair)/spot") else {
            return nil
        }

        var attempt = 0
        while attempt < maxRetries {
            attempt += 1
            do {
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    print("❌ [CoinbaseService] HTTP error fetching spot price for \(pair): \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                    return nil
                }
                let resp = try decoder.decode(CoinbaseSpotPriceResponse.self, from: data)
                guard let field = resp.data,
                      let price = Double(field.amount) else {
                    return nil
                }
                return price
            } catch {
                print("❌ [CoinbaseService] network error fetching spot price for \(pair) attempt \(attempt):", error)
                if attempt < maxRetries {
                    try? await Task.sleep(nanoseconds: UInt64(attempt * 2) * 1_000_000_000)
                } else {
                    return nil
                }
            }
        }
        return nil
    }

    /// Fetches 24‑hour open, high, low and last prices from Coinbase Pro and maps into CoinPrice.
    func fetch24hStats(
        coin: String = "BTC",
        fiat: String = "USD"
    ) async throws -> CoinPrice? {
        let symbol = "\(coin.uppercased())\(fiat.uppercased())"
        guard let url = URL(string: "https://api.pro.coinbase.com/products/\(symbol)/stats") else {
            return nil
        }
        // Use async URLSession to avoid manual resume()
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            print("❌ [CoinbaseService] HTTP error fetching 24‑hr stats for \(symbol): \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            return nil
        }
        let resp = try decoder.decode(CoinbaseProStatsResponse.self, from: data)
        guard
            let last = Double(resp.last),
            let open = Double(resp.open),
            let high = Double(resp.high),
            let low = Double(resp.low)
        else {
            return nil
        }
        return CoinPrice(
            symbol: symbol,
            lastPrice: last,
            openPrice: open,
            highPrice: high,
            lowPrice: low,
            volume: nil,
            change24h: last - open
        )
    }
}
