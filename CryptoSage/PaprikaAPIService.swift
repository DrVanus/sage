//
//  PaprikaAPIService.swift
//  CSAI1
//
//  Minimal service stub for future CoinPaprika integration.
//  Not currently wired into the app. Use as a fallback or alternative
//  data source if desired, and map results into MarketCoin.
//

import Foundation

/// Service wrapper for CoinPaprika endpoints (minimal subset).
final class PaprikaAPIService {
    static let shared = PaprikaAPIService()
    private init() {}

    // MARK: - Decoder
    /// CoinPaprika typically uses ISO8601 for date fields, but some variants exist.
    /// We set up a tolerant decoder: ISO8601 first, then a custom formatter fallback.
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        // Try ISO8601 first
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            // ISO8601 attempt
            if let date = ISO8601DateFormatter().date(from: raw) {
                return date
            }
            // Common fallback formats (e.g., "2020-01-01T00:00:00Z", "2020-01-01")
            let fmts = [
                "yyyy-MM-dd'T'HH:mm:ssXXXXX",
                "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
                "yyyy-MM-dd"
            ]
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            for f in fmts {
                df.dateFormat = f
                if let d = df.date(from: raw) { return d }
            }
            // If parsing fails, throw to allow optional Date? to decode as nil when appropriate
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized date format: \(raw)")
        }
        return decoder
    }()

    // MARK: - Endpoints
    /// Fetch a single ticker by id. Example id: "btc-bitcoin"
    /// Example: https://api.coinpaprika.com/v1/tickers/btc-bitcoin?quotes=USD
    func fetchTicker(id: String, quotes: [String] = ["USD"]) async throws -> CoinPaprikaData {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "api.coinpaprika.com"
        comps.path = "/v1/tickers/\(id)"
        if !quotes.isEmpty {
            comps.queryItems = [URLQueryItem(name: "quotes", value: quotes.joined(separator: ","))]
        }
        guard let url = comps.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try Self.decoder.decode(CoinPaprikaData.self, from: data)
    }

    /// Fetch multiple tickers concurrently; returns only successful results.
    func fetchTickers(ids: [String], quotes: [String] = ["USD"]) async -> [CoinPaprikaData] {
        if ids.isEmpty { return [] }
        return await withTaskGroup(of: CoinPaprikaData?.self) { group in
            for id in ids {
                group.addTask {
                    do { return try await self.fetchTicker(id: id, quotes: quotes) }
                    catch { return nil }
                }
            }
            var results: [CoinPaprikaData] = []
            for await item in group { if let item { results.append(item) } }
            return results
        }
    }
}

// MARK: - Integration Notes
// When wiring this into the app, map CoinPaprikaData into your MarketCoin model, e.g.:
// - id: paprika.id
// - symbol: paprika.symbol
// - name: paprika.name
// - priceUsd: paprika.quotes?["USD"].price
// - totalVolume: paprika.quotes?["USD"].volume24h
// - changePercent24Hr: paprika.quotes?["USD"].percentChange24h
// - (and any other fields you wish to surface)
