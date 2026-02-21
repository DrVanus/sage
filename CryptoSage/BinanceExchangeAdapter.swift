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
        let quotes = ["USDT", "USDC", "FDUSD", "USD"]
        return quotes.map { MMEMarketPair(exchangeID: id, baseSymbol: base, quoteSymbol: $0) }
    }

    public func fetchTickers(for pairs: [MMEMarketPair]) async throws -> [MMETicker] {
        guard !pairs.isEmpty else { return [] }

        var out: [MMETicker] = []
        let batchSize = 50 // batched request size
        let fallbackBatchSize = 10 // limit per-symbol concurrency on fallback
        var index = 0

        while index < pairs.count {
            try Task.checkCancellation()

            let end = min(index + batchSize, pairs.count)
            let chunkPairs = Array(pairs[index..<end])
            let symbols = chunkPairs.map { $0.baseSymbol.uppercased() + $0.quoteSymbol.uppercased() }

            // Attempt batch with a single jittered retry before falling back
            var batchDict: [String: (last: Double, bid: Double?, ask: Double?, vol: Double?, ts: TimeInterval)] = [:]
            var batchSucceeded = false

            do {
                batchDict = try await fetch24hrBatch(session: session, base: baseURL, symbols: symbols)
                batchSucceeded = true
            } catch {
                let jitterNs = UInt64(Int.random(in: 80_000_000...200_000_000)) // 80-200ms
                try? await Task.sleep(nanoseconds: jitterNs)
                do {
                    batchDict = try await fetch24hrBatch(session: session, base: baseURL, symbols: symbols)
                    batchSucceeded = true
                } catch {
                    batchSucceeded = false
                }
            }

            if batchSucceeded {
                // Append results we have
                for p in chunkPairs {
                    let sym = p.baseSymbol.uppercased() + p.quoteSymbol.uppercased()
                    if let res = batchDict[sym] {
                        out.append(MMETicker(pair: p, last: res.last, bid: res.bid, ask: res.ask, volume24hBase: res.vol, ts: res.ts))
                    }
                }

                // Fill in any missing symbols with per-symbol fallback in sub-batches
                let missingPairs = chunkPairs.filter { batchDict[$0.baseSymbol.uppercased() + $0.quoteSymbol.uppercased()] == nil }
                if !missingPairs.isEmpty {
                    var fbIndex = 0
                    while fbIndex < missingPairs.count {
                        try Task.checkCancellation()

                        let fbEnd = min(fbIndex + fallbackBatchSize, missingPairs.count)
                        let subChunk = Array(missingPairs[fbIndex..<fbEnd])

                        let partial: [MMETicker] = await withTaskGroup(of: MMETicker?.self) { group in
                            for p in subChunk {
                                group.addTask { [weak self] in
                                    guard let self = self else { return nil }
                                    if Task.isCancelled { return nil }
                                    do {
                                        let sym = p.baseSymbol.uppercased() + p.quoteSymbol.uppercased()
                                        let (last, bid, ask, vol, ts) = try await self.fetch24hr(session: self.session, base: self.baseURL, symbol: sym)
                                        return MMETicker(pair: p, last: last, bid: bid, ask: ask, volume24hBase: vol, ts: ts)
                                    } catch {
                                        return nil
                                    }
                                }
                            }

                            var inner: [MMETicker] = []
                            for await item in group { if let t = item { inner.append(t) } }
                            return inner
                        }

                        out.append(contentsOf: partial)
                        fbIndex = fbEnd

                        let subJitterNs = UInt64(Int.random(in: 40_000_000...120_000_000)) // 40-120ms
                        try? await Task.sleep(nanoseconds: subJitterNs)
                    }
                }
            } else {
                // Fallback: process the whole chunk per-symbol in smaller sub-batches
                var fbIndex = 0
                while fbIndex < chunkPairs.count {
                    try Task.checkCancellation()

                    let fbEnd = min(fbIndex + fallbackBatchSize, chunkPairs.count)
                    let subChunk = Array(chunkPairs[fbIndex..<fbEnd])

                    let partial: [MMETicker] = await withTaskGroup(of: MMETicker?.self) { group in
                        for p in subChunk {
                            group.addTask { [weak self] in
                                guard let self = self else { return nil }
                                if Task.isCancelled { return nil }
                                do {
                                    let sym = p.baseSymbol.uppercased() + p.quoteSymbol.uppercased()
                                    let (last, bid, ask, vol, ts) = try await self.fetch24hr(session: self.session, base: self.baseURL, symbol: sym)
                                    return MMETicker(pair: p, last: last, bid: bid, ask: ask, volume24hBase: vol, ts: ts)
                                } catch {
                                    return nil
                                }
                            }
                        }

                        var inner: [MMETicker] = []
                        for await item in group { if let t = item { inner.append(t) } }
                        return inner
                    }

                    out.append(contentsOf: partial)
                    fbIndex = fbEnd

                    let subJitterNs = UInt64(Int.random(in: 40_000_000...120_000_000)) // 40-120ms
                    try? await Task.sleep(nanoseconds: subJitterNs)
                }
            }

            index = end
            let batchJitterNs = UInt64(Int.random(in: 80_000_000...150_000_000)) // 80-150ms
            try? await Task.sleep(nanoseconds: batchJitterNs)
        }

        return out
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

    private func fetch24hr(session: URLSession, base: URL, symbol: String) async throws -> (last: Double, bid: Double?, ask: Double?, vol: Double?, ts: TimeInterval) {
        // PERFORMANCE FIX v25: Skip per-symbol Binance requests when geo-blocked
        // This function is called in tight loops (fallback for missing batch results)
        // and each request hangs for 8s when Binance is unreachable
        if UserDefaults.standard.bool(forKey: "BinanceGlobalGeoBlocked") {
            throw URLError(.cannotConnectToHost)
        }
        
        func buildURL(_ base: URL) -> URL {
            base
                .appendingPathComponent("ticker/24hr")
                .appending(queryItems: [URLQueryItem(name: "symbol", value: symbol)])
        }

        func makeFromEndpoints(_ endpoints: ExchangeEndpoints) -> URL {
            buildURL(endpoints.restBase)
        }

        let initial = buildURL(base)
        let (data, _) = try await ExchangeHTTP.getWithPolicyFallback(
            initial: initial,
            session: session,
            buildFromEndpoints: makeFromEndpoints
        )

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }

        let lastStr = json["lastPrice"] as? String
        let bidStr = json["bidPrice"] as? String
        let askStr = json["askPrice"] as? String
        let volStr = json["volume"] as? String
        let closeTimeMs = (json["closeTime"] as? Double) ?? (json["closeTime"] as? NSNumber)?.doubleValue

        guard let last = lastStr.flatMap(Double.init), last.isFinite, last > 0 else {
            throw URLError(.cannotParseResponse)
        }

        let bid = bidStr.flatMap(Double.init)
        let ask = askStr.flatMap(Double.init)
        let vol = volStr.flatMap(Double.init)
        let ts = (closeTimeMs ?? Date().timeIntervalSince1970 * 1000.0) / 1000.0

        return (last, bid, ask, vol, ts)
    }

    private func fetch24hrBatch(session: URLSession, base: URL, symbols: [String]) async throws -> [String: (last: Double, bid: Double?, ask: Double?, vol: Double?, ts: TimeInterval)] {
        guard !symbols.isEmpty else { return [:] }

        // Encode symbols as JSON array for the `symbols` query parameter
        let symbolsData = try JSONSerialization.data(withJSONObject: symbols, options: [])
        guard let symbolsJSON = String(data: symbolsData, encoding: .utf8) else {
            throw URLError(.badURL)
        }

        func buildURL(_ base: URL) -> URL {
            base
                .appendingPathComponent("ticker/24hr")
                .appending(queryItems: [URLQueryItem(name: "symbols", value: symbolsJSON)])
        }

        func makeFromEndpoints(_ endpoints: ExchangeEndpoints) -> URL { buildURL(endpoints.restBase) }

        let initial = buildURL(base)
        let (data, _) = try await ExchangeHTTP.getWithPolicyFallback(
            initial: initial,
            session: session,
            buildFromEndpoints: makeFromEndpoints
        )

        let obj = try JSONSerialization.jsonObject(with: data)
        var result: [String: (Double, Double?, Double?, Double?, TimeInterval)] = [:]

        if let arr = obj as? [[String: Any]] {
            for item in arr {
                guard
                    let symbol = item["symbol"] as? String,
                    let lastStr = item["lastPrice"] as? String,
                    let last = Double(lastStr), last.isFinite, last > 0
                else { continue }

                let bid = (item["bidPrice"] as? String).flatMap(Double.init)
                let ask = (item["askPrice"] as? String).flatMap(Double.init)
                let vol = (item["volume"] as? String).flatMap(Double.init)
                let closeTimeMs = (item["closeTime"] as? Double) ?? (item["closeTime"] as? NSNumber)?.doubleValue
                let ts = (closeTimeMs ?? Date().timeIntervalSince1970 * 1000.0) / 1000.0

                result[symbol] = (last, bid, ask, vol, ts)
            }
            return result
        } else if let dict = obj as? [String: Any] {
            // Occasionally the API may return a single object
            if
                let symbol = dict["symbol"] as? String,
                let lastStr = dict["lastPrice"] as? String,
                let last = Double(lastStr), last.isFinite, last > 0
            {
                let bid = (dict["bidPrice"] as? String).flatMap(Double.init)
                let ask = (dict["askPrice"] as? String).flatMap(Double.init)
                let vol = (dict["volume"] as? String).flatMap(Double.init)
                let closeTimeMs = (dict["closeTime"] as? Double) ?? (dict["closeTime"] as? NSNumber)?.doubleValue
                let ts = (closeTimeMs ?? Date().timeIntervalSince1970 * 1000.0) / 1000.0

                result[symbol] = (last, bid, ask, vol, ts)
                return result
            } else {
                throw URLError(.cannotParseResponse)
            }
        } else {
            throw URLError(.cannotParseResponse)
        }
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

