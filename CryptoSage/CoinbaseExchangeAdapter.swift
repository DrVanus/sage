import Foundation

public final class CoinbaseExchangeAdapter: ExchangeAdapter {
    public var id: String { "coinbase" }
    public var name: String { "Coinbase" }

    private let session: URLSession
    private let baseURL: URL

    public init(session: URLSession = .shared) {
        self.session = session
        self.baseURL = URL(string: "https://api.exchange.coinbase.com")!
    }

    public func supportedPairs(for baseSymbol: String) async -> [MMEMarketPair] {
        let base = baseSymbol.uppercased()
        let quotes = ["USD", "USDT"]
        return quotes.map { MMEMarketPair(exchangeID: id, baseSymbol: base, quoteSymbol: $0) }
    }

    public func fetchTickers(for pairs: [MMEMarketPair]) async throws -> [MMETicker] {
        guard !pairs.isEmpty else { return [] }
        return await withTaskGroup(of: MMETicker?.self) { group in
            for p in pairs {
                group.addTask { [session, baseURL] in
                    do {
                        let sym = p.baseSymbol.uppercased() + "-" + p.quoteSymbol.uppercased()
                        if let t = try await fetchTicker(session: session, base: baseURL, product: sym) {
                            return MMETicker(pair: p, last: t.last, bid: nil, ask: nil, volume24hBase: t.volumeBase, ts: t.ts)
                        }
                        return nil
                    } catch {
                        return nil
                    }
                }
            }
            var out: [MMETicker] = []
            for await item in group { if let t = item { out.append(t) } }
            return out
        }
    }

    public func fetchCandles(pair: MMEMarketPair, interval: MMECandleInterval, limit: Int) async throws -> [MMECandle] {
        let gran = mapGranularity(interval)
        let product = pair.baseSymbol.uppercased() + "-" + pair.quoteSymbol.uppercased()
        let url = baseURL.appendingPathComponent("products").appendingPathComponent(product).appendingPathComponent("candles").appending(queryItems: [
            URLQueryItem(name: "granularity", value: String(gran)),
            URLQueryItem(name: "limit", value: String(limit))
        ])
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 10
        req.setValue("CryptoSage/1.0", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return [] }
        guard let arr = try JSONSerialization.jsonObject(with: data) as? [[Any]] else { return [] }
        // Coinbase returns arrays: [ time, low, high, open, close, volume ]
        let sorted = arr.sorted { a, b in
            let ta = (a.first as? Double) ?? 0
            let tb = (b.first as? Double) ?? 0
            return ta < tb
        }
        var out: [MMECandle] = []
        out.reserveCapacity(sorted.count)
        for row in sorted {
            if row.count >= 6 {
                let t = (row[0] as? Double) ?? 0
                let low = (row[1] as? Double) ?? Double.nan
                let high = (row[2] as? Double) ?? Double.nan
                let open = (row[3] as? Double) ?? Double.nan
                let close = (row[4] as? Double) ?? Double.nan
                let vol = (row[5] as? Double)
                if close.isFinite, close > 0, open.isFinite, high.isFinite, low.isFinite {
                    out.append(
                        MMECandle(
                            pair: pair,
                            interval: interval,
                            open: open,
                            high: high,
                            low: low,
                            close: close,
                            volume: vol,
                            ts: t
                        )
                    )
                }
            }
        }
        return out
    }

    // MARK: - Helpers

    private func mapGranularity(_ i: MMECandleInterval) -> Int {
        switch i {
        case .m1: return 60
        case .m5: return 300
        case .m15: return 900
        case .h1: return 3600
        case .h4: return 14400
        case .d1: return 86400
        }
    }

    private func fetchTicker(session: URLSession, base: URL, product: String) async throws -> (last: Double, volumeBase: Double?, ts: TimeInterval)? {
        // Try /ticker first
        let tickerURL = base.appendingPathComponent("products").appendingPathComponent(product).appendingPathComponent("ticker")
        var req = URLRequest(url: tickerURL)
        req.httpMethod = "GET"
        req.timeoutInterval = 10
        req.setValue("CryptoSage/1.0", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
               let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let priceStr = json["price"] as? String
                let volStr = json["volume"] as? String
                let timeStr = json["time"] as? String
                let last = priceStr.flatMap(Double.init) ?? 0
                let vol = volStr.flatMap(Double.init)
                let ts = timeStr.flatMap { ISO8601DateFormatter().date(from: $0)?.timeIntervalSince1970 } ?? Date().timeIntervalSince1970
                if last > 0, last.isFinite { return (last, vol, ts) }
            }
        } catch {
            // Fall through to /stats
        }
        // Fallback: /stats
        let statsURL = base.appendingPathComponent("products").appendingPathComponent(product).appendingPathComponent("stats")
        var req2 = URLRequest(url: statsURL)
        req2.httpMethod = "GET"
        req2.timeoutInterval = 10
        req2.setValue("CryptoSage/1.0", forHTTPHeaderField: "User-Agent")
        req2.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: req2)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
               let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let lastStr = json["last"] as? String
                let volStr = json["volume"] as? String
                let last = lastStr.flatMap(Double.init) ?? 0
                let vol = volStr.flatMap(Double.init)
                let ts = Date().timeIntervalSince1970
                if last > 0, last.isFinite { return (last, vol, ts) }
            }
        } catch {
            return nil
        }
        return nil
    }
}

// Small URL extension for query items
private extension URL {
    func appending(queryItems: [URLQueryItem]) -> URL {
        guard var comps = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        comps.queryItems = (comps.queryItems ?? []) + queryItems
        return comps.url ?? self
    }
}
