import Foundation

// Lightweight value container for engine results used by UI
// oneHFrac and dayFrac are optional to distinguish "no data" from "0% change"
struct MetricsEngineOutputs {
    let display: [Double]
    let canonical: [Double]
    let isPositive7D: Bool
    let oneHFrac: Double?  // nil = no data available, UI shows "—"
    let dayFrac: Double?   // nil = no data available, UI shows "—"
}

// Thread-safe global store to allow synchronous cache lookups from UI code
private enum _MetricsCacheStore {
    private static var dict: [String: (Date, MetricsEngineOutputs)] = [:]
    private static let lock = NSLock()
    private static let maxEntries: Int = 500  // Prevent unbounded growth
    private static let ttlSeconds: TimeInterval = 300  // 5 minutes TTL for pruning
    private static var lastPruneAt: Date = .distantPast
    private static let pruneInterval: TimeInterval = 60  // Prune at most once per minute

    static func get(_ key: String) -> (Date, MetricsEngineOutputs)? {
        lock.lock(); defer { lock.unlock() }
        return dict[key]
    }
    
    static func set(_ key: String, value: (Date, MetricsEngineOutputs)) {
        lock.lock(); defer { lock.unlock() }
        dict[key] = value
        // Prune periodically to prevent memory growth
        let now = Date()
        if now.timeIntervalSince(lastPruneAt) >= pruneInterval {
            lastPruneAt = now
            pruneIfNeeded(now: now)
        }
    }
    
    /// Prunes stale entries to prevent unbounded memory growth.
    /// Called under lock - must not acquire lock again.
    private static func pruneIfNeeded(now: Date) {
        // First pass: remove entries older than TTL
        let cutoff = now.addingTimeInterval(-ttlSeconds)
        let staleKeys = dict.keys.filter { key in
            guard let (ts, _) = dict[key] else { return false }
            return ts < cutoff
        }
        for key in staleKeys {
            dict.removeValue(forKey: key)
        }
        
        // If still over limit, remove oldest entries (LRU-style)
        if dict.count > maxEntries {
            let sorted = dict.sorted { $0.value.0 < $1.value.0 }
            let toRemove = dict.count - maxEntries
            for (key, _) in sorted.prefix(toRemove) {
                dict.removeValue(forKey: key)
            }
        }
    }
    
    /// Clears all cached entries. Call during memory pressure.
    static func clearAll() {
        lock.lock(); defer { lock.unlock() }
        dict.removeAll()
    }
}

/// Public function to clear all global metrics caches. Call during memory pressure.
func clearAllMetricsCaches() {
    _MetricsCacheStore.clearAll()
    Task { await MarketMetricsCache.shared.clearCache() }
}

actor MarketMetricsCache {
    static let shared = MarketMetricsCache()

    // Secondary cache (actor-isolated); not strictly necessary but kept to satisfy internal memoization
    private var cache: [String: (Date, MetricsEngineOutputs)] = [:]
    private let ttl: TimeInterval = 60 // seconds
    
    /// Clears the actor-internal cache. Called during memory pressure.
    func clearCache() {
        cache.removeAll()
    }

    // Build a stable key from inputs (symbol uppercased, series count/first/last, quantized inputs)
    private func makeKey(symbol: String, rawSeries: [Double], livePrice: Double?, provider1h: Double?, provider24h: Double?, isStable: Bool, targetPoints: Int) -> String {
        let up = symbol.uppercased()
        let count = rawSeries.count
        let first = rawSeries.first ?? .nan
        let last = rawSeries.last ?? .nan
        let k = [
            up,
            String(count),
            quantize(first),
            quantize(last),
            quantize(livePrice),
            quantize(provider1h),
            quantize(provider24h),
            isStable ? "S" : "N",
            String(targetPoints)
        ].joined(separator: "|")
        return k
    }

    // Quantize a Double? to a short string for keys
    private func quantize(_ v: Double?) -> String {
        guard let v = v, v.isFinite else { return "n" }
        return String(format: "%.6g", v)
    }

    // Synchronous cache lookup used by UI without awaiting actor
    static func cached(symbol: String, rawSeries: [Double], livePrice: Double?, provider1h: Double?, provider24h: Double?, isStable: Bool, targetPoints: Int) -> MetricsEngineOutputs? {
        // Build the same key logic here (duplicate minimal logic to avoid actor hop)
        func q(_ v: Double?) -> String { v.map { String(format: "%.6g", $0) } ?? "n" }
        let up = symbol.uppercased()
        let key = [
            up,
            String(rawSeries.count),
            q(rawSeries.first),
            q(rawSeries.last),
            q(livePrice),
            q(provider1h),
            q(provider24h),
            isStable ? "S" : "N",
            String(targetPoints)
        ].joined(separator: "|")
        if let (ts, out) = _MetricsCacheStore.get(key) {
            // Optional TTL check can be omitted for pure memoization; keep it permissive
            if Date().timeIntervalSince(ts) <= 300 { return out }
        }
        return nil
    }

    // Async compute with memoization and LiveChangeService seeding
    func compute(symbol: String, rawSeries: [Double], livePrice: Double?, provider1h: Double?, provider24h: Double?, isStable: Bool, seriesSpanHours: Double?, targetPoints: Int, provider7d: Double? = nil) async -> MetricsEngineOutputs {
        let key = makeKey(symbol: symbol, rawSeries: rawSeries, livePrice: livePrice, provider1h: provider1h, provider24h: provider24h, isStable: isStable, targetPoints: targetPoints)

        // Fast path: check global store first (fresh only)
        if let (ts, out) = _MetricsCacheStore.get(key), Date().timeIntervalSince(ts) <= ttl {
            // Also mirror into actor cache
            cache[key] = (ts, out)
            // Override isPositive7D if provider7d is available (more accurate than spark-derived)
            if let p7 = provider7d, p7.isFinite {
                let corrected = MetricsEngineOutputs(
                    display: out.display,
                    canonical: out.canonical,
                    isPositive7D: p7 >= 0,
                    oneHFrac: out.oneHFrac,
                    dayFrac: out.dayFrac
                )
                return corrected
            }
            return out
        }
        // Actor cache
        if let (ts, out) = cache[key], Date().timeIntervalSince(ts) <= ttl {
            _MetricsCacheStore.set(key, value: (ts, out))
            // Override isPositive7D if provider7d is available
            if let p7 = provider7d, p7.isFinite {
                let corrected = MetricsEngineOutputs(
                    display: out.display,
                    canonical: out.canonical,
                    isPositive7D: p7 >= 0,
                    oneHFrac: out.oneHFrac,
                    dayFrac: out.dayFrac
                )
                return corrected
            }
            return out
        }

        // Compute via engine
        let res = MarketMetricsEngine.computeAllV2(
            symbol: symbol.uppercased(),
            rawSeries: rawSeries,
            livePrice: livePrice,
            provider1h: provider1h,
            provider24h: provider24h,
            isStable: isStable,
            seriesSpanHours: seriesSpanHours,
            targetPoints: targetPoints,
            provider7d: provider7d
        )

        // Prefer provider 7D for isPositive7D if available
        let finalIsPositive7D: Bool = {
            if let p7 = provider7d, p7.isFinite { return p7 >= 0 }
            return res.isPositive7D
        }()

        let outputs = MetricsEngineOutputs(
            display: res.display,
            canonical: res.canonical,
            isPositive7D: finalIsPositive7D,
            oneHFrac: res.oneHFrac,
            dayFrac: res.dayFrac
        )
        let now = Date()
        cache[key] = (now, outputs)
        _MetricsCacheStore.set(key, value: (now, outputs))

        // Seed LiveChangeService for consistent deltas elsewhere
        let sym = symbol.uppercased()
        let canonical = res.canonical
        await MainActor.run { [sym, canonical, livePrice] in
            DispatchQueue.main.async {
                if !LiveChangeService.shared.haveCoverage(symbol: sym, hours: 24) {
                    LiveChangeService.shared.seed(symbol: sym, series: canonical, livePrice: livePrice)
                } else if !LiveChangeService.shared.haveCoverage(symbol: sym, hours: 1) {
                    LiveChangeService.shared.seed(symbol: sym, series: canonical, livePrice: livePrice)
                }
            }
        }
        return outputs
    }
}
