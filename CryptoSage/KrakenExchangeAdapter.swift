//
//  KrakenExchangeAdapter.swift
//  CryptoSage
//
//  Exchange adapter for Kraken API integration.
//

import Foundation

public final class KrakenExchangeAdapter: ExchangeAdapter {
    public var id: String { "kraken" }
    public var name: String { "Kraken" }

    private let session: URLSession
    private let baseURL: URL

    public init(session: URLSession = .shared) {
        self.session = session
        self.baseURL = URL(string: "https://api.kraken.com/0/public")!
    }

    public func supportedPairs(for baseSymbol: String) async -> [MMEMarketPair] {
        let base = baseSymbol.uppercased()
        // Kraken uses different symbols - BTC is XBT, etc.
        _ = mapToKrakenSymbol(base)
        let quotes = ["USD", "USDT", "USDC", "EUR"]
        return quotes.map { MMEMarketPair(exchangeID: id, baseSymbol: base, quoteSymbol: $0) }
    }

    public func fetchTickers(for pairs: [MMEMarketPair]) async throws -> [MMETicker] {
        guard !pairs.isEmpty else { return [] }

        var out: [MMETicker] = []
        let batchSize = 20

        for startIndex in stride(from: 0, to: pairs.count, by: batchSize) {
            try Task.checkCancellation()

            let endIndex = min(startIndex + batchSize, pairs.count)
            let batch = Array(pairs[startIndex..<endIndex])

            // Build comma-separated pair list for Kraken API
            let pairStrings = batch.map { pair in
                let base = mapToKrakenSymbol(pair.baseSymbol.uppercased())
                let quote = mapToKrakenSymbol(pair.quoteSymbol.uppercased())
                return "\(base)\(quote)"
            }
            let pairParam = pairStrings.joined(separator: ",")

            guard let url = URL(string: "\(baseURL)/Ticker?pair=\(pairParam)") else { continue }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 15
            request.setValue("CryptoSage/1.0", forHTTPHeaderField: "User-Agent")

            do {
                let (data, response) = try await session.data(for: request)

                guard let http = response as? HTTPURLResponse else { continue }

                // Handle rate limiting
                if http.statusCode == 429 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    continue
                }

                guard (200...299).contains(http.statusCode) else { continue }

                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let result = json["result"] as? [String: Any] else { continue }

                // Parse each ticker result
                for pair in batch {
                    let base = mapToKrakenSymbol(pair.baseSymbol.uppercased())
                    let quote = mapToKrakenSymbol(pair.quoteSymbol.uppercased())
                    let krakenPair = "\(base)\(quote)"

                    // Kraken returns pairs with various key formats, try common ones
                    let tickerData = result[krakenPair] as? [String: Any]
                        ?? result["X\(base)Z\(quote)"] as? [String: Any]
                        ?? result["X\(base)\(quote)"] as? [String: Any]
                        ?? result["\(base)Z\(quote)"] as? [String: Any]

                    if let ticker = tickerData {
                        // Kraken returns arrays for most values: [price, whole_lot_volume]
                        // "c" = close (last trade), "b" = bid, "a" = ask, "v" = volume
                        let lastArr = ticker["c"] as? [Any]
                        let bidArr = ticker["b"] as? [Any]
                        let askArr = ticker["a"] as? [Any]
                        let volArr = ticker["v"] as? [Any]

                        let last = (lastArr?.first as? String).flatMap(Double.init) ?? 0
                        let bid = (bidArr?.first as? String).flatMap(Double.init)
                        let ask = (askArr?.first as? String).flatMap(Double.init)
                        // Volume array: [today, last 24h] - we want last 24h
                        let vol = (volArr?.last as? String).flatMap(Double.init)
                        let ts = Date().timeIntervalSince1970

                        if last > 0, last.isFinite {
                            out.append(MMETicker(pair: pair, last: last, bid: bid, ask: ask, volume24hBase: vol, ts: ts))
                        }
                    }
                }

            } catch {
                #if DEBUG
                print("[KrakenExchangeAdapter] Batch fetch error: \(error)")
                #endif
                continue
            }

            // Small delay between batches
            if endIndex < pairs.count {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        return out
    }

    public func fetchCandles(pair: MMEMarketPair, interval: MMECandleInterval, limit: Int) async throws -> [MMECandle] {
        let base = mapToKrakenSymbol(pair.baseSymbol.uppercased())
        let quote = mapToKrakenSymbol(pair.quoteSymbol.uppercased())
        let krakenPair = "\(base)\(quote)"
        let intervalMins = mapInterval(interval)

        guard let url = URL(string: "\(baseURL)/OHLC?pair=\(krakenPair)&interval=\(intervalMins)") else {
            return []
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("CryptoSage/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return []
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any] else {
            return []
        }

        // Find the candle data - Kraken returns it keyed by pair name
        var candleData: [[Any]]?
        for (key, value) in result {
            if key != "last", let arr = value as? [[Any]] {
                candleData = arr
                break
            }
        }

        guard let candles = candleData else { return [] }

        var out: [MMECandle] = []
        out.reserveCapacity(min(candles.count, limit))

        // Kraken OHLC format: [time, open, high, low, close, vwap, volume, count]
        for row in candles.suffix(limit) {
            guard row.count >= 7 else { continue }

            let ts = (row[0] as? Double) ?? (row[0] as? Int).map(Double.init) ?? 0
            let open = (row[1] as? String).flatMap(Double.init) ?? 0
            let high = (row[2] as? String).flatMap(Double.init) ?? 0
            let low = (row[3] as? String).flatMap(Double.init) ?? 0
            let close = (row[4] as? String).flatMap(Double.init) ?? 0
            let vol = (row[6] as? String).flatMap(Double.init)

            if close.isFinite, close > 0, open.isFinite, high.isFinite, low.isFinite {
                out.append(MMECandle(
                    pair: pair,
                    interval: interval,
                    open: open,
                    high: high,
                    low: low,
                    close: close,
                    volume: vol,
                    ts: ts
                ))
            }
        }

        return out
    }

    // MARK: - Helpers

    /// Map standard symbols to Kraken's naming convention
    private func mapToKrakenSymbol(_ symbol: String) -> String {
        switch symbol {
        case "BTC": return "XBT"
        case "DOGE": return "XDG"
        default: return symbol
        }
    }

    /// Map from Kraken symbol back to standard
    private func mapFromKrakenSymbol(_ symbol: String) -> String {
        switch symbol {
        case "XBT": return "BTC"
        case "XDG": return "DOGE"
        default: return symbol
        }
    }

    /// Map candle interval to Kraken minutes
    private func mapInterval(_ i: MMECandleInterval) -> Int {
        switch i {
        case .m1: return 1
        case .m5: return 5
        case .m15: return 15
        case .h1: return 60
        case .h4: return 240
        case .d1: return 1440
        }
    }
}
