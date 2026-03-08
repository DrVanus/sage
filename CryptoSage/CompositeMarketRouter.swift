import Foundation

public struct MarketCompositeSnapshot {
    public let symbol: String
    public let priceUSD: Double
    public let method: String
    public let canonical: [Double]
    public let display: [Double]
    public let oneHFrac: Double?   // nil = no data available
    public let dayFrac: Double?    // nil = no data available
    public let sevenDFrac: Double?
    public let isPositive7D: Bool
    public let constituents: [MMECompositeConstituent]
}

public struct MarketPairSnapshot {
    public let exchangeID: String
    public let baseSymbol: String
    public let quoteSymbol: String
    public let lastUSD: Double
    public let oneHFrac: Double?   // nil = no data available
    public let dayFrac: Double?    // nil = no data available
    public let sevenDFrac: Double?
}

public actor CompositeMarketRouter {
    private let adapters: [ExchangeAdapter]
    private let rateService: ExchangeRateService
    private let composite: CompositePriceService

    // Circuit breaker: skip adapters that fail repeatedly
    private var adapterFailureCounts: [String: Int] = [:]
    private var adapterCooldownUntil: [String: Date] = [:]
    private let circuitBreakerThreshold = 3  // failures before cooldown
    private let circuitBreakerCooldown: TimeInterval = 120  // 2 min cooldown

    // Error log throttling: suppress duplicate errors per exchange
    private var lastErrorLogAt: [String: Date] = [:]
    private let errorLogSuppressWindow: TimeInterval = 10.0  // one error log per exchange per 10s

    // MARK: - Cross-Call Circuit Breaker (thread-safe)
    // Prevents redundant network calls when many concurrent calls to
    // listPairSnapshotsFast() interleave due to actor reentrancy.
    // Task group closures run outside actor isolation, so they need
    // a thread-safe mechanism to check if an adapter is blocked.
    private static let _blockedLock = NSLock()
    private static var _fastBlocked: Set<String> = []

    private static func isFastBlocked(_ id: String) -> Bool {
        _blockedLock.withLock { _fastBlocked.contains(id) }
    }

    private static func setFastBlocked(_ id: String, duration: TimeInterval) {
        _blockedLock.withLock { _fastBlocked.insert(id) }
        Task.detached {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            _blockedLock.withLock { _ = _fastBlocked.remove(id) }
        }
    }

    private static func clearFastBlocked(_ id: String) {
        _blockedLock.withLock { _ = _fastBlocked.remove(id) }
    }

    public init(adapters: [ExchangeAdapter]? = nil, rateService: ExchangeRateService? = nil) {
        // Default to all available exchange adapters for comprehensive market data
        let adps: [ExchangeAdapter] = adapters ?? [
            BinanceExchangeAdapter(),
            CoinbaseExchangeAdapter(),
            KrakenExchangeAdapter(),
            KuCoinExchangeAdapter(),
            BybitExchangeAdapter(),
            OKXExchangeAdapter(),
            GateIOExchangeAdapter(),
            GeminiExchangeAdapter(),
            MEXCExchangeAdapter()
        ]
        let rates = rateService ?? InMemoryExchangeRateService()
        self.adapters = adps
        self.rateService = rates
        var cfg = CompositePriceService.Config()
        cfg.allowedExchangeIDs = AppSettings.compositeAllowedExchanges()
        self.composite = CompositePriceService(adapters: adps, rateService: rates, config: cfg)
    }

    // Load aggregated (composite) snapshot for a symbol
    public func loadCompositeSnapshot(for symbol: String) async -> MarketCompositeSnapshot? {
        guard let result = await composite.computeComposite(for: symbol) else { return nil }
        let price = result.price.priceUSD
        let closes = result.series?.closesUSD ?? []
        let ts = result.series?.timestamps ?? []
        let out = MarketMetricsEngine.computeAllFromCloses(
            symbol: symbol.uppercased(),
            closes: closes,
            timestamps: ts,
            livePrice: price,
            provider1h: nil,
            provider24h: nil,
            isStable: false
        )
        return MarketCompositeSnapshot(
            symbol: symbol.uppercased(),
            priceUSD: price,
            method: result.price.method,
            canonical: out.canonical,
            display: out.display,
            oneHFrac: out.oneHFrac,
            dayFrac: out.dayFrac,
            sevenDFrac: out.sevenDFrac,
            isPositive7D: out.isPositive7D,
            constituents: result.price.constituents
        )
    }

    // List top N pair snapshots (per-exchange) with basic metrics derived from candles
    public func listPairSnapshots(for baseSymbol: String, preferredQuotes: [String] = ["USD","USDT","FDUSD","BUSD"], limit: Int = 4) async -> [MarketPairSnapshot] {
        let base = baseSymbol.uppercased()
        // Gather pairs
        var pairsSet = Set<MMEMarketPair>()
        for adapter in adapters {
            let ps = await adapter.supportedPairs(for: base)
            for p in ps where preferredQuotes.contains(p.quoteSymbol.uppercased()) { pairsSet.insert(p) }
        }
        let pairs = Array(pairsSet)
        if pairs.isEmpty { return [] }
        // Fetch tickers per adapter (with circuit breaker to skip failing adapters)
        let now = Date()
        let tickers: [MMETicker] = await withTaskGroup(of: (String, [MMETicker]).self) { group in
            for adapter in adapters {
                let adapterID = adapter.id
                // Circuit breaker: skip adapters in cooldown
                if let cooldownEnd = adapterCooldownUntil[adapterID], now < cooldownEnd {
                    continue
                }
                let sub = pairs.filter { $0.exchangeID == adapterID }
                if sub.isEmpty { continue }
                group.addTask {
                    // Cross-call check: another concurrent call may have tripped the breaker
                    if Self.isFastBlocked(adapterID) { return (adapterID, []) }
                    do {
                        let result = try await adapter.fetchTickers(for: sub)
                        return (adapterID, result)
                    } catch {
                        // Error logged when circuit breaker trips (avoids 10x spam from concurrent tasks)
                        return (adapterID, [])
                    }
                }
            }
            var out: [MMETicker] = []
            for await (adapterID, arr) in group {
                if arr.isEmpty {
                    // Track failures for circuit breaker
                    adapterFailureCounts[adapterID, default: 0] += 1
                    if adapterFailureCounts[adapterID, default: 0] >= circuitBreakerThreshold {
                        let alreadyBlocked = adapterCooldownUntil[adapterID].map { now < $0 } ?? false
                        adapterCooldownUntil[adapterID] = now.addingTimeInterval(circuitBreakerCooldown)
                        if !alreadyBlocked {
                            Self.setFastBlocked(adapterID, duration: circuitBreakerCooldown)
                            #if DEBUG
                            print("[CompositeMarketRouter] ⚡ Circuit breaker tripped for \(adapterID) — cooling down 2min")
                            #endif
                        }
                    }
                } else {
                    adapterFailureCounts[adapterID] = 0  // reset on success
                    adapterCooldownUntil.removeValue(forKey: adapterID)
                    Self.clearFastBlocked(adapterID)
                    out.append(contentsOf: arr)
                }
            }
            return out
        }
        // Convert to USD and pick top by volume
        var rows: [(pair: MMEMarketPair, lastUSD: Double, vol: Double?, ts: TimeInterval)] = []
        for t in tickers {
            let q = t.pair.quoteSymbol.uppercased()
            let rate = (q == "USD") ? 1.0 : (await rateService.usdRate(for: q) ?? 0)
            if rate > 0, t.last > 0, t.last.isFinite {
                rows.append((t.pair, t.last * rate, t.volume24hBase, t.ts))
            }
        }
        if rows.isEmpty { return [] }
        // Sort by volume desc (fallback to price)
        rows.sort { (a, b) in
            let va = a.vol ?? 0
            let vb = b.vol ?? 0
            if va == vb { return a.lastUSD > b.lastUSD }
            return va > vb
        }
        let selected = Array(rows.prefix(max(1, limit)))
        // Fetch candles and compute metrics for each selected pair
        var snapshots: [MarketPairSnapshot] = []
        snapshots.reserveCapacity(selected.count)
        for item in selected {
            guard let adapter = adapters.first(where: { $0.id == item.pair.exchangeID }) else { continue }
            do {
                // 5m * 300 ~ 25h coverage; enough for 1H/24H deltas
                let candles = try await adapter.fetchCandles(pair: item.pair, interval: .m5, limit: 300)
                let closes = candles.map { $0.close }
                let times = candles.map { $0.ts }
                let d = MarketMetricsEngine.computeAllFromCloses(
                    symbol: base,
                    closes: closes,
                    timestamps: times,
                    livePrice: item.lastUSD,
                    provider1h: nil,
                    provider24h: nil,
                    isStable: false
                )
                snapshots.append(MarketPairSnapshot(
                    exchangeID: item.pair.exchangeID,
                    baseSymbol: base,
                    quoteSymbol: item.pair.quoteSymbol,
                    lastUSD: item.lastUSD,
                    oneHFrac: d.oneHFrac,
                    dayFrac: d.dayFrac,
                    sevenDFrac: d.sevenDFrac
                ))
            } catch {
                continue
            }
        }
        return snapshots
    }
    
    /// FAST version: List pair snapshots using tickers only - NO candle fetching
    /// This is 10-50x faster than listPairSnapshots because it skips the expensive candle fetching loop.
    /// Price changes can be provided externally from MarketViewModel which already has this data.
    public func listPairSnapshotsFast(for baseSymbol: String, preferredQuotes: [String] = ["USD","USDT","FDUSD","BUSD"], limit: Int = 4) async -> [MarketPairSnapshot] {
        let base = baseSymbol.uppercased()
        
        // Gather pairs from all adapters
        var pairsSet = Set<MMEMarketPair>()
        for adapter in adapters {
            let ps = await adapter.supportedPairs(for: base)
            for p in ps where preferredQuotes.contains(p.quoteSymbol.uppercased()) {
                pairsSet.insert(p)
            }
        }
        let pairs = Array(pairsSet)
        if pairs.isEmpty { return [] }
        
        // Fetch tickers from all adapters in parallel (with circuit breaker)
        let now = Date()
        let tickers: [MMETicker] = await withTaskGroup(of: (String, [MMETicker]).self) { group in
            for adapter in adapters {
                let adapterID = adapter.id
                // Circuit breaker: skip adapters in cooldown
                if let cooldownEnd = adapterCooldownUntil[adapterID], now < cooldownEnd {
                    continue
                }
                let sub = pairs.filter { $0.exchangeID == adapterID }
                if sub.isEmpty { continue }
                group.addTask {
                    // Cross-call check: another concurrent call may have tripped the breaker
                    if Self.isFastBlocked(adapterID) { return (adapterID, []) }
                    do {
                        let result = try await adapter.fetchTickers(for: sub)
                        return (adapterID, result)
                    } catch {
                        // Error logged when circuit breaker trips (avoids 10x spam from concurrent tasks)
                        return (adapterID, [])
                    }
                }
            }
            var out: [MMETicker] = []
            for await (adapterID, arr) in group {
                if arr.isEmpty {
                    adapterFailureCounts[adapterID, default: 0] += 1
                    if adapterFailureCounts[adapterID, default: 0] >= circuitBreakerThreshold {
                        let alreadyBlocked = adapterCooldownUntil[adapterID].map { now < $0 } ?? false
                        adapterCooldownUntil[adapterID] = now.addingTimeInterval(circuitBreakerCooldown)
                        if !alreadyBlocked {
                            Self.setFastBlocked(adapterID, duration: circuitBreakerCooldown)
                            #if DEBUG
                            print("[CompositeMarketRouter] ⚡ Circuit breaker tripped for \(adapterID) — cooling down 2min")
                            #endif
                        }
                    }
                } else {
                    adapterFailureCounts[adapterID] = 0
                    adapterCooldownUntil.removeValue(forKey: adapterID)
                    Self.clearFastBlocked(adapterID)
                    out.append(contentsOf: arr)
                }
            }
            return out
        }

        // Convert to USD
        var rows: [(pair: MMEMarketPair, lastUSD: Double, vol: Double?, ts: TimeInterval)] = []
        for t in tickers {
            let q = t.pair.quoteSymbol.uppercased()
            let rate = (q == "USD") ? 1.0 : (await rateService.usdRate(for: q) ?? 0)
            if rate > 0, t.last > 0, t.last.isFinite {
                rows.append((t.pair, t.last * rate, t.volume24hBase, t.ts))
            }
        }
        if rows.isEmpty { return [] }
        
        // Sort by volume desc (fallback to price)
        rows.sort { (a, b) in
            let va = a.vol ?? 0
            let vb = b.vol ?? 0
            if va == vb { return a.lastUSD > b.lastUSD }
            return va > vb
        }
        
        // Take top pairs by limit
        let selected = Array(rows.prefix(max(1, limit)))
        
        // Return snapshots directly WITHOUT fetching candles (the slow part)
        // Price changes will be filled in by the caller from MarketViewModel
        return selected.map { item in
            MarketPairSnapshot(
                exchangeID: item.pair.exchangeID,
                baseSymbol: base,
                quoteSymbol: item.pair.quoteSymbol,
                lastUSD: item.lastUSD,
                oneHFrac: nil, // Will be populated by caller from MarketViewModel
                dayFrac: nil,  // Will be populated by caller from MarketViewModel
                sevenDFrac: nil
            )
        }
    }
}

