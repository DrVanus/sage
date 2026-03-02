import Foundation

public actor CompositePriceService {
    public struct Config {
        public var staleTickerCutoff: TimeInterval = 90 // seconds
        public var outlierK: Double = 3.0               // MAD multiplier
        public var maxVenueWeightCap: Double = 0.5      // cap any single venue to 50%
        public var defaultInterval: MMECandleInterval = .m5
        public var allowedExchangeIDs: [String]? = nil
        public init() {}
    }

    private let adapters: [ExchangeAdapter]
    private let rateService: ExchangeRateService
    private var config: Config

    public init(adapters: [ExchangeAdapter], rateService: ExchangeRateService, config: Config = Config()) {
        self.adapters = adapters
        self.rateService = rateService
        self.config = config
    }

    // MARK: - Public API

    public struct CompositeResult {
        public let price: MMECompositePrice
        public let series: MMECompositeSeries?
        public init(price: MMECompositePrice, series: MMECompositeSeries?) {
            self.price = price
            self.series = series
        }
    }

    public func computeComposite(for baseSymbol: String, preferredQuotes: [String] = ["USD", "USDT", "USDC"]) async -> CompositeResult? {
        let base = baseSymbol.uppercased()
        // 1) Collect pairs
        let pairs = await gatherPairs(baseSymbol: base, preferredQuotes: preferredQuotes)
        guard !pairs.isEmpty else { return nil }
        // 2) Fetch tickers
        let tickers = await fetchTickers(for: pairs)
        let now = Date().timeIntervalSince1970
        let fresh = tickers.filter { t in
            if t.last <= 0 || !t.last.isFinite { return false }
            if t.ts <= 0 { return true }
            return now - t.ts <= config.staleTickerCutoff
        }
        guard !fresh.isEmpty else { return nil }
        // 3) Convert to USD
        let usdTickers = await convertToUSD(tickers: fresh)
        let prices = usdTickers.map { $0.1 }
        _ = usdTickers.map { $0.0.volume24hBase ?? 0 }
        // 4) Outlier filter via MAD
        let mask = robustInlierMask(values: prices, k: config.outlierK)
        var filtered: [(MMETicker, Double)] = []
        for i in 0..<usdTickers.count { if mask[i] { filtered.append(usdTickers[i]) } }
        if filtered.isEmpty { filtered = usdTickers }
        // 5) Weights with venue cap
        let cappedWeights = capWeights(filtered.map { $0.0.pair.exchangeID }, weights: filtered.map { $0.0.volume24hBase ?? 0 }, cap: config.maxVenueWeightCap)
        let wsum = max(1e-9, cappedWeights.reduce(0, +))
        let norm = cappedWeights.map { $0 / wsum }
        // 6) Compute price
        let vwap = zip(filtered, norm).reduce(0.0) { $0 + $1.0.1 * $1.1 }
        let priceUSD: Double
        let method: String
        if vwap.isFinite, vwap > 0, wsum > 0.0 {
            priceUSD = vwap
            method = "VWAP"
        } else {
            priceUSD = median(filtered.map { $0.1 })
            method = "median"
        }
        let constituents: [MMECompositeConstituent] = zip(filtered, norm).map { item, w in
            MMECompositeConstituent(pair: item.0.pair, priceUSD: item.1, weight: w)
        }
        let price = MMECompositePrice(assetSymbol: base, priceUSD: priceUSD, method: method, constituents: constituents, ts: now)
        // 7) Series (optional)
        let series = await buildCompositeSeries(base: base, constituents: constituents, interval: config.defaultInterval)
        return CompositeResult(price: price, series: series)
    }

    // MARK: - Internals

    private func gatherPairs(baseSymbol: String, preferredQuotes: [String]) async -> [MMEMarketPair] {
        let allowed: Set<String>? = { 
            if let ids = config.allowedExchangeIDs, !ids.isEmpty { 
                return Set(ids.map { $0.lowercased() }) 
            } else { 
                return nil 
            } 
        }()
        let targets = preferredQuotes.map { $0.uppercased() }
        var set = Set<MMEMarketPair>()
        for adapter in adapters where (allowed == nil || allowed!.contains(adapter.id.lowercased())) {
            let pairs = await adapter.supportedPairs(for: baseSymbol)
            for p in pairs where targets.contains(p.quoteSymbol.uppercased()) {
                set.insert(p)
            }
        }
        return Array(set)
    }

    private func fetchTickers(for pairs: [MMEMarketPair]) async -> [MMETicker] {
        let allowed: Set<String>? = {
            if let ids = config.allowedExchangeIDs, !ids.isEmpty {
                return Set(ids.map { $0.lowercased() })
            } else {
                return nil
            }
        }()
        return await withTaskGroup(of: [MMETicker].self) { group in
            for adapter in adapters where (allowed == nil || allowed!.contains(adapter.id.lowercased())) {
                let sub = pairs.filter { $0.exchangeID == adapter.id }
                if sub.isEmpty { continue }
                group.addTask {
                    do {
                        return try await adapter.fetchTickers(for: sub)
                    } catch {
                        #if DEBUG
                        print("[CompositePriceService] fetchTickers error: \(error)")
                        #endif
                        return []
                    }
                }
            }
            var out: [MMETicker] = []
            for await arr in group { out.append(contentsOf: arr) }
            return out
        }
    }

    private func convertToUSD(tickers: [MMETicker]) async -> [(MMETicker, Double)] {
        var out: [(MMETicker, Double)] = []
        for t in tickers {
            let q = t.pair.quoteSymbol.uppercased()
            if q == "USD" { out.append((t, t.last)); continue }
            let rate = await rateService.usdRate(for: q) ?? 0
            if rate > 0, rate.isFinite { out.append((t, t.last * rate)) }
        }
        return out
    }

    private func buildCompositeSeries(base: String, constituents: [MMECompositeConstituent], interval: MMECandleInterval) async -> MMECompositeSeries? {
        // Fetch candles for each constituent and merge by timestamp with weight
        let limit = 300
        let perPair: [[MMECandle]] = await withTaskGroup(of: [MMECandle].self) { group in
            for item in constituents {
                if let adapter = adapters.first(where: { $0.id == item.pair.exchangeID }) {
                    group.addTask {
                        do {
                            return try await adapter.fetchCandles(pair: item.pair, interval: interval, limit: limit)
                        } catch {
                            #if DEBUG
                            print("[CompositePriceService] fetchCandles error: \(error)")
                            #endif
                            return []
                        }
                    }
                }
            }
            var res: [[MMECandle]] = []
            for await arr in group { res.append(arr) }
            return res
        }
        var bucket: [TimeInterval: (sum: Double, wsum: Double)] = [:]
        var any = false
        for (candles, item) in zip(perPair, constituents) {
            guard item.weight > 0 else { continue }
            for c in candles {
                if c.close <= 0 || !c.close.isFinite { continue }
                let w = item.weight * max(1e-9, c.volume ?? 1.0)
                var entry = bucket[c.ts] ?? (0, 0)
                entry.sum += c.close * w
                entry.wsum += w
                bucket[c.ts] = entry
                any = true
            }
        }
        guard any else { return nil }
        let sortedKeys = bucket.keys.sorted()
        var closes: [Double] = []
        var times: [TimeInterval] = []
        closes.reserveCapacity(sortedKeys.count)
        times.reserveCapacity(sortedKeys.count)
        for k in sortedKeys {
            let v = bucket[k]!
            let close = v.wsum > 0 ? (v.sum / v.wsum) : 0
            if close > 0, close.isFinite { times.append(k); closes.append(close) }
        }
        guard !closes.isEmpty else { return nil }
        let now = Date().timeIntervalSince1970
        return MMECompositeSeries(assetSymbol: base, interval: interval, closesUSD: closes, timestamps: times, ts: now)
    }

    // MARK: - Math helpers

    private func median(_ arr: [Double]) -> Double {
        guard !arr.isEmpty else { return 0 }
        let s = arr.sorted()
        let n = s.count
        if n % 2 == 1 { return s[n/2] }
        return 0.5 * (s[n/2 - 1] + s[n/2])
    }

    private func mad(_ arr: [Double]) -> Double {
        let med = median(arr)
        let devs = arr.map { abs($0 - med) }
        return median(devs)
    }

    private func robustInlierMask(values: [Double], k: Double) -> [Bool] {
        guard values.count >= 3 else { return Array(repeating: true, count: values.count) }
        let med = median(values)
        let m = mad(values)
        if m <= 1e-12 { return Array(repeating: true, count: values.count) }
        return values.map { abs($0 - med) <= k * 1.4826 * m }
    }

    private func capWeights(_ venues: [String], weights: [Double], cap: Double) -> [Double] {
        // Normalize first, then cap per-venue and renormalize.
        let sum = max(1e-12, weights.reduce(0, +))
        let norm = weights.map { max(0, $0) / sum }
        // Aggregate per-venue
        var venueSum: [String: Double] = [:]
        for (i, v) in venues.enumerated() { venueSum[v, default: 0] += norm[i] }
        // If any venue exceeds cap, scale its members down proportionally and renormalize the rest.
        var scale = Array(repeating: 1.0, count: weights.count)
        for (i, v) in venues.enumerated() {
            let total = venueSum[v] ?? 0
            if total > cap && total > 0 { scale[i] = cap / total }
        }
        var adjusted = zip(norm, scale).map(*)
        let adjustedSum = max(1e-12, adjusted.reduce(0, +))
        adjusted = adjusted.map { $0 / adjustedSum }
        return adjusted
    }
}
