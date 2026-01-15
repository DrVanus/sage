import Foundation
import Combine

@MainActor
public final class CompositeMarketViewModel: ObservableObject {
    private let router: CompositeMarketRouter

    @Published public private(set) var aggregate: [String: MarketCompositeSnapshot] = [:]
    @Published public private(set) var pairs: [String: [MarketPairSnapshot]] = [:]
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var lastUpdated: Date? = nil
    @Published public private(set) var errorMessage: String? = nil

    // Lightweight freshness cache per symbol
    private var cacheTS: [String: TimeInterval] = [:]
    private let defaultTTL: TimeInterval = 45 // seconds

    public init(router: CompositeMarketRouter = CompositeMarketRouter()) {
        self.router = router
    }

    private func isFresh(symbol: String, ttl: TimeInterval? = nil) -> Bool {
        let t = ttl ?? defaultTTL
        let now = Date().timeIntervalSince1970
        if let ts = cacheTS[symbol.uppercased()] { return (now - ts) < t }
        return false
    }

    public func clear(symbol: String? = nil) {
        if let s = symbol?.uppercased() {
            aggregate.removeValue(forKey: s)
            pairs.removeValue(forKey: s)
            cacheTS.removeValue(forKey: s)
        } else {
            aggregate.removeAll()
            pairs.removeAll()
            cacheTS.removeAll()
        }
    }

    public func load(symbol: String, force: Bool = false) async {
        let sym = symbol.uppercased()
        if !force, isFresh(symbol: sym) { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        async let aggTask = router.loadCompositeSnapshot(for: sym)
        async let pairsTask = router.listPairSnapshots(for: sym, preferredQuotes: ["USD","USDT","FDUSD","BUSD"], limit: 4)
        do {
            let agg = await aggTask
            let pr = await pairsTask
            if let a = agg {
                aggregate[sym] = a
                cacheTS[sym] = Date().timeIntervalSince1970
                lastUpdated = Date()
            }
            pairs[sym] = pr
        }
    }

    public func refresh(symbols: [String], force: Bool = false) async {
        await withTaskGroup(of: Void.self) { group in
            for s in symbols {
                group.addTask { [weak self] in
                    await self?.load(symbol: s, force: force)
                }
            }
            for await _ in group { }
        }
    }
}
