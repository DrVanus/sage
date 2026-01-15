import Foundation

public final class BinanceExchangeAdapter: ExchangeAdapter {
    public var id: String { "binance" }
    public var name: String { "Binance" }

    private let session: URLSession
    private let baseURL: URL
    private let candleService: BinanceCandleService

    public init(session: URLSession = .shared) {
        self.session = session
        self.baseURL = URL(string: "https://api.binance.com/api/v3")!
        self.candleService = BinanceCandleService(session: session)
    }

    public func supportedPairs(for baseSymbol: String) async -> [MMEMarketPair] {
        let base = baseSymbol.uppercased()
        // Provide a small set of common quotes; Composite service will filter by preferredQuotes.
        let quotes = ["USDT", "FDUSD", "BUSD", "USD"]
        return quotes.map { MMEMarketPair(exchangeID: id, baseSymbol: base, quoteSymbol: $0) }
    }

    public func fetchTickers(for pairs: [MMEMarketPair]) async throws -> [MMETicker] {
        guard !pairs.isEmpty else { return [] }
        return await withTaskGroup(of: MMETicker?.self) { group in
            for p in pairs {
                group.addTask { [session, baseURL] in
                    do {
                        let sym = p.baseSymbol.uppercased() + p.quoteSymbol.uppercased()
                        let (last, vol, ts) = try await fetch24hr(session: session, base: baseURL, symbol: sym)
                        return MMETicker(pair: p, last: last, bid: nil, ask: nil, volume24hBase: vol, ts: ts)
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
        let mapped = mapInterval(interval)
        let symbol = pair.baseSymbol.uppercased() + pair.quoteSymbol.uppercased()
        let candles = try await candleService.fetchCandles(symbol: symbol, interval: mapped, limit: limit)
        return candles.map { c in
            MMECandle(
                pair: pair,
                interval: interval,
                open: c.open,
                high: c.high,
                low: c.low,
                close: c.close,
                volume: c.volume,
                ts: c.closeTime.timeIntervalSince1970
            )
        }
    }

    // MARK: - Helpers

    private func mapInterval(_ i: MMECandleInterval) -> CandleInterval {
        switch i {
        case .m1: return .oneMinute
        case .m5: return .fiveMinutes
        case .m15: return .fifteenMinutes
        case .h1: return .oneHour
        case .h4: return .fourHours
        case .d1: return .oneDay
        }
    }

    private func fetch24hr(session: URLSession, base: URL, symbol: String) async throws -> (last: Double, vol: Double?, ts: TimeInterval) {
        func buildURL(_ base: URL) -> URL { base.appendingPathComponent("ticker/24hr").appending(queryItems: [URLQueryItem(name: "symbol", value: symbol)]) }
        func makeRequest(_ url: URL) -> URLRequest { var r = URLRequest(url: url); r.timeoutInterval = 10; r.cachePolicy = .reloadIgnoringLocalCacheData; return r }

        var url = buildURL(base)
        var request = makeRequest(url)
        var (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // Fallback via ExchangeHostPolicy if available
            let endpoints = await ExchangeHostPolicy.shared.currentEndpoints()
            let retryURL = buildURL(endpoints.restBase)
            (data, response) = try await session.data(for: makeRequest(retryURL))
        }
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 451 {
            await ExchangeHostPolicy.shared.onHTTPStatus(451)
            let endpoints = await ExchangeHostPolicy.shared.currentEndpoints()
            let retryURL = buildURL(endpoints.restBase)
            let req = makeRequest(retryURL)
            let res = try await session.data(for: req)
            data = res.0; response = res.1
        }
        guard let final = response as? HTTPURLResponse, (200...299).contains(final.statusCode) else { throw URLError(.badServerResponse) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw URLError(.cannotParseResponse) }
        let lastStr = json["lastPrice"] as? String
        let volStr = json["volume"] as? String
        let closeTimeMs = (json["closeTime"] as? Double) ?? (json["closeTime"] as? NSNumber)?.doubleValue
        guard let last = lastStr.flatMap(Double.init) else { throw URLError(.cannotParseResponse) }
        let vol = volStr.flatMap(Double.init)
        let ts = (closeTimeMs ?? Date().timeIntervalSince1970 * 1000.0) / 1000.0
        return (last, vol, ts)
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
