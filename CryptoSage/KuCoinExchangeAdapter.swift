//
//  KuCoinExchangeAdapter.swift
//  CryptoSage
//
//  Exchange adapter for KuCoin API integration.
//

import Foundation

public final class KuCoinExchangeAdapter: ExchangeAdapter {
    public var id: String { "kucoin" }
    public var name: String { "KuCoin" }

    private let session: URLSession
    private let baseURL: URL

    public init(session: URLSession = .shared) {
        self.session = session
        self.baseURL = URL(string: "https://api.kucoin.com/api/v1")!
    }

    public func supportedPairs(for baseSymbol: String) async -> [MMEMarketPair] {
        let base = baseSymbol.uppercased()
        let quotes = ["USDT", "USDC", "USD", "BTC", "ETH"]
        return quotes.map { MMEMarketPair(exchangeID: id, baseSymbol: base, quoteSymbol: $0) }
    }

    public func fetchTickers(for pairs: [MMEMarketPair]) async throws -> [MMETicker] {
        guard !pairs.isEmpty else { return [] }

        var out: [MMETicker] = []

        // KuCoin has an "allTickers" endpoint that's more efficient
        // First, try to fetch all tickers and filter to our pairs
        let allTickers = try? await fetchAllTickers()

        if let tickers = allTickers, !tickers.isEmpty {
            // Match against requested pairs
            let tickerMap = Dictionary(uniqueKeysWithValues: tickers.map { ($0.symbol, $0) })

            for pair in pairs {
                let symbol = "\(pair.baseSymbol.uppercased())-\(pair.quoteSymbol.uppercased())"
                if let ticker = tickerMap[symbol] {
                    out.append(MMETicker(
                        pair: pair,
                        last: ticker.last,
                        bid: ticker.bid,
                        ask: ticker.ask,
                        volume24hBase: ticker.vol,
                        ts: ticker.ts
                    ))
                }
            }
        } else {
            // Fallback: fetch individual tickers
            for pair in pairs {
                try Task.checkCancellation()

                if let ticker = try? await fetchSingleTicker(pair: pair) {
                    out.append(ticker)
                }

                // Small delay between requests
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }

        return out
    }

    public func fetchCandles(pair: MMEMarketPair, interval: MMECandleInterval, limit: Int) async throws -> [MMECandle] {
        let symbol = "\(pair.baseSymbol.uppercased())-\(pair.quoteSymbol.uppercased())"
        let intervalStr = mapInterval(interval)

        // Calculate time range
        let endTime = Int(Date().timeIntervalSince1970)
        let duration = intervalDurationSeconds(interval) * limit
        let startTime = endTime - duration

        guard let url = URL(string: "\(baseURL)/market/candles?type=\(intervalStr)&symbol=\(symbol)&startAt=\(startTime)&endAt=\(endTime)") else {
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
              let dataArr = json["data"] as? [[Any]] else {
            return []
        }

        var out: [MMECandle] = []
        out.reserveCapacity(min(dataArr.count, limit))

        // KuCoin format: [time, open, close, high, low, volume, turnover]
        for row in dataArr.suffix(limit) {
            guard row.count >= 6 else { continue }

            let tsStr = row[0] as? String
            let ts = tsStr.flatMap(Double.init) ?? 0
            let open = (row[1] as? String).flatMap(Double.init) ?? 0
            let close = (row[2] as? String).flatMap(Double.init) ?? 0
            let high = (row[3] as? String).flatMap(Double.init) ?? 0
            let low = (row[4] as? String).flatMap(Double.init) ?? 0
            let vol = (row[5] as? String).flatMap(Double.init)

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

        // KuCoin returns newest first, reverse to oldest first
        return out.reversed()
    }

    // MARK: - Helpers

    private struct KuCoinTicker {
        let symbol: String
        let last: Double
        let bid: Double?
        let ask: Double?
        let vol: Double?
        let ts: TimeInterval
    }

    private func fetchAllTickers() async throws -> [KuCoinTicker] {
        guard let url = URL(string: "\(baseURL)/market/allTickers") else {
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
              let dataObj = json["data"] as? [String: Any],
              let tickerArr = dataObj["ticker"] as? [[String: Any]] else {
            return []
        }

        let time = (dataObj["time"] as? Double) ?? Date().timeIntervalSince1970 * 1000

        var tickers: [KuCoinTicker] = []
        tickers.reserveCapacity(tickerArr.count)

        for item in tickerArr {
            guard let symbol = item["symbol"] as? String,
                  let lastStr = item["last"] as? String,
                  let last = Double(lastStr), last.isFinite, last > 0 else { continue }

            let bid = (item["buy"] as? String).flatMap(Double.init)
            let ask = (item["sell"] as? String).flatMap(Double.init)
            let vol = (item["vol"] as? String).flatMap(Double.init)

            tickers.append(KuCoinTicker(
                symbol: symbol,
                last: last,
                bid: bid,
                ask: ask,
                vol: vol,
                ts: time / 1000.0
            ))
        }

        return tickers
    }

    private func fetchSingleTicker(pair: MMEMarketPair) async throws -> MMETicker? {
        let symbol = "\(pair.baseSymbol.uppercased())-\(pair.quoteSymbol.uppercased())"

        guard let url = URL(string: "\(baseURL)/market/orderbook/level1?symbol=\(symbol)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("CryptoSage/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any] else {
            return nil
        }

        let lastStr = dataObj["price"] as? String
        let bidStr = dataObj["bestBid"] as? String
        let askStr = dataObj["bestAsk"] as? String
        let sizeStr = dataObj["size"] as? String
        let timeMs = dataObj["time"] as? Double

        guard let last = lastStr.flatMap(Double.init), last.isFinite, last > 0 else {
            return nil
        }

        let bid = bidStr.flatMap(Double.init)
        let ask = askStr.flatMap(Double.init)
        let vol = sizeStr.flatMap(Double.init)
        let ts = (timeMs ?? Date().timeIntervalSince1970 * 1000) / 1000.0

        return MMETicker(pair: pair, last: last, bid: bid, ask: ask, volume24hBase: vol, ts: ts)
    }

    private func mapInterval(_ i: MMECandleInterval) -> String {
        switch i {
        case .m1: return "1min"
        case .m5: return "5min"
        case .m15: return "15min"
        case .h1: return "1hour"
        case .h4: return "4hour"
        case .d1: return "1day"
        }
    }

    private func intervalDurationSeconds(_ i: MMECandleInterval) -> Int {
        switch i {
        case .m1: return 60
        case .m5: return 300
        case .m15: return 900
        case .h1: return 3600
        case .h4: return 14400
        case .d1: return 86400
        }
    }
}
