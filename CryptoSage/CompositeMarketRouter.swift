import Foundation

public struct MarketCompositeSnapshot {
    public let symbol: String
    public let priceUSD: Double
    public let method: String
    public let canonical: [Double]
    public let display: [Double]
    public let oneHFrac: Double
    public let dayFrac: Double
    public let sevenDFrac: Double?
    public let isPositive7D: Bool
    public let constituents: [MMECompositeConstituent]
}

public struct MarketPairSnapshot {
    public let exchangeID: String
    public let baseSymbol: String
    public let quoteSymbol: String
    public let lastUSD: Double
    public let oneHFrac: Double
    public let dayFrac: Double
    public let sevenDFrac: Double?
}

public actor CompositeMarketRouter {
    private let adapters: [ExchangeAdapter]
    private let rateService: ExchangeRateService
    private let composite: CompositePriceService

    public init(adapters: [ExchangeAdapter]? = nil, rateService: ExchangeRateService? = nil) {
        let adps: [ExchangeAdapter] = adapters ?? [BinanceExchangeAdapter(), CoinbaseExchangeAdapter()]
        let rates = rateService ?? InMemoryExchangeRateService()
        self.adapters = adps
        self.rateService = rates
        self.composite = CompositePriceService(adapters: adps, rateService: rates)
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
        // Fetch tickers per adapter
        let tickers: [MMETicker] = await withTaskGroup(of: [MMETicker].self) { group in
            for adapter in adapters {
                let sub = pairs.filter { $0.exchangeID == adapter.id }
                if sub.isEmpty { continue }
                group.addTask {
                    do { return try await adapter.fetchTickers(for: sub) } catch { return [] }
                }
            }
            var out: [MMETicker] = []
            for await arr in group { out.append(contentsOf: arr) }
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
}
