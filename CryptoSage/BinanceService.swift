//
//  BinanceService.swift
//  CSAI1
//
//  Created by DM on 3/28/25.
//

//
//  BinanceService.swift
//  CSAI1
//
//  Created by You on [Date].
//



import Foundation

actor BinanceService {
    /// Fetch sparkline data (e.g. daily closes for the last 7 days) from Binance for a symbol like "BTCUSDT".
    static func fetchSparkline(symbol: String) async -> [Double] {
        let pair = symbol.uppercased() + "USDT"
        let urlString = "https://api.binance.com/api/v3/klines?symbol=\(pair)&interval=1d&limit=7"
        guard let url = URL(string: urlString) else { return [] }
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                print("❌ [BinanceService] HTTP error fetching sparkline for \(symbol): \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return []
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [[Any]] {
                // The 5th element in each array is the "close" price.
                return json.map { arr in
                    Double(arr[4] as? String ?? "0") ?? 0
                }
            }
        } catch {
            print("❌ [BinanceService] Network error fetching sparkline for \(symbol):", error)
        }
        return []
    }

    /// Fetch 24-hour ticker stats for multiple symbols from Binance.
    static func fetch24hrStats(symbols: [String]) async throws -> [CoinPrice] {
        let pairs = symbols.map { $0.uppercased() + "USDT" }
        // Build JSON-encoded symbols parameter
        let jsonData = try JSONEncoder().encode(pairs)
        guard let symbolsParam = String(data: jsonData, encoding: .utf8) else {
            throw URLError(.badURL)
        }
        var components = URLComponents(string: "https://api.binance.com/api/v3/ticker/24hr")!
        components.queryItems = [
            URLQueryItem(name: "symbols", value: symbolsParam)
        ]
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        // Decode JSON into Ticker24hr objects
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let tickerStats = try decoder.decode([Ticker24hr].self, from: data)
        // Map into shared CoinPrice type (matching CoinbaseService.swift)
        return tickerStats.map { stat in
            let symbol = stat.symbol.replacingOccurrences(of: "USDT", with: "").lowercased()
            let last = Double(stat.lastPrice) ?? 0
            let changePercent = Double(stat.priceChangePercent) ?? 0
            return CoinPrice(
                symbol: symbol,
                lastPrice: last,
                openPrice: last,
                highPrice: last,
                lowPrice: last,
                volume: nil,
                change24h: changePercent
            )
        }
    }

    // Internal model for Binance 24hr ticker stats
    private struct Ticker24hr: Codable {
        let symbol: String
        let priceChange: String
        let priceChangePercent: String
        let lastPrice: String
        enum CodingKeys: String, CodingKey {
            case symbol
            case priceChange = "priceChange"
            case priceChangePercent = "priceChangePercent"
            case lastPrice = "lastPrice"
        }
    }
}
