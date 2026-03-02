import Foundation

public struct MarketMetricsEngine {
    
    // MARK: - Orientation Stability Cache
    // Prevents rapid flip-flopping of sparkline direction by requiring strong evidence to change.
    // Once an orientation is decided, it's cached and requires multiple consecutive contrary signals to flip.
    private static let orientationQueue = DispatchQueue(label: "MarketMetricsEngine.OrientationQueue", qos: .userInitiated)
    
    // SPARKLINE FIX: Increased confidence max and confirmations required to prevent flipping
    // Cache: symbol -> (shouldReverse: Bool, confidence: Int, lastUpdate: TimeInterval)
    // confidence: number of consecutive frames supporting this orientation (max 10)
    private static var orientationCache: [String: (shouldReverse: Bool, confidence: Int, lastUpdate: TimeInterval)] = [:]
    private static let orientationCacheTTL: TimeInterval = 600 // 10 minutes TTL (increased from 5)
    private static let orientationConfirmationsRequired: Int = 5 // Need 5 consistent signals before flipping (increased from 3)
    private static var lastPruneTime: TimeInterval = 0
    private static let pruneInterval: TimeInterval = 60 // Prune at most once per minute
    
    /// Determines the stable orientation for a sparkline series.
    /// Uses cached orientation with hysteresis to prevent rapid flip-flopping.
    /// PERFORMANCE FIX: Uses non-blocking read during scroll, blocking only when necessary.
    private static func stableOrientation(
        series: [Double],
        livePrice: Double?,
        provider24hRaw: Double?,
        cacheKey: String
    ) -> Bool {
        // Calculate what orientation we would choose without caching
        let rawShouldReverse = calculateRawOrientation(series: series, livePrice: livePrice, provider24hRaw: provider24hRaw)
        
        let now = Date().timeIntervalSince1970
        
        // PERFORMANCE FIX: During scroll, return raw calculation to avoid blocking
        // The orientation cache is just an optimization - stale values won't cause issues
        if Thread.isMainThread && ScrollStateAtomicStorage.shared.shouldBlock() {
            return rawShouldReverse
        }
        
        return orientationQueue.sync {
            // Check if we have a cached orientation
            if let cached = orientationCache[cacheKey] {
                // Check if cache is still valid (within TTL)
                if now - cached.lastUpdate <= orientationCacheTTL {
                    // Cache hit - check if raw orientation agrees or disagrees
                    if rawShouldReverse == cached.shouldReverse {
                        // SPARKLINE FIX: Raw agrees with cache - reinforce confidence (max 10, increased from 5)
                        let newConfidence = min(10, cached.confidence + 1)
                        orientationCache[cacheKey] = (cached.shouldReverse, newConfidence, now)
                        return cached.shouldReverse
                    } else {
                        // Raw disagrees - only flip if we've accumulated enough contrary evidence
                        if cached.confidence <= 1 {
                            // Confidence is low - flip to new orientation
                            orientationCache[cacheKey] = (rawShouldReverse, 1, now)
                            return rawShouldReverse
                        } else {
                            // Still have confidence - decrease it but keep current orientation
                            orientationCache[cacheKey] = (cached.shouldReverse, cached.confidence - 1, now)
                            return cached.shouldReverse
                        }
                    }
                }
            }
            
            // No valid cache - use raw orientation and initialize cache
            orientationCache[cacheKey] = (rawShouldReverse, orientationConfirmationsRequired, now)
            return rawShouldReverse
        }
    }
    
    /// Calculates the raw orientation decision without any caching or stabilization.
    /// FIX: Made much more conservative - most APIs (Binance, CoinGecko) return data in
    /// chronological order [oldest→newest], so we should default to NOT reversing.
    /// Only reverse when there's extremely strong evidence the data is backwards.
    private static func calculateRawOrientation(series: [Double], livePrice: Double?, provider24hRaw: Double?) -> Bool {
        guard series.count > 1 else { return false }
        
        // Method 1: Scale-compatible live price comparison
        // FIX: Require MUCH stronger evidence before reversing (75% closer, not 12%)
        // In a properly ordered [old→new] series, the LAST value should be closest to live price.
        // Only reverse if the FIRST value is dramatically closer to live price.
        if isScaleCompatible(series, price: livePrice),
           let price = livePrice, price.isFinite, price > 0,
           let first = series.first, let last = series.last,
           first.isFinite, last.isFinite, first > 0, last > 0 {
            let dFirst = abs(first - price)
            let dLast = abs(last - price)
            // Only reverse if first is at least 75% closer to live price than last
            // This is very conservative - most API data is already [old→new]
            // The 0.25 multiplier means first must be 4x closer than last to trigger reversal
            return dFirst < dLast * 0.25
        }
        
        // Method 2: REMOVED - The percent comparison had circular dependency issues.
        // It assumed data order to calculate derived percent, then used that to decide order.
        // This caused incorrect orientation decisions especially during market volatility.
        
        // Default: do NOT reverse
        // Both Binance klines and CoinGecko sparkline_in_7d return chronological order [old→new]
        return false
    }
    
    /// Clears the orientation cache for a specific symbol or all symbols.
    public static func resetOrientationCache(for symbol: String? = nil) {
        orientationQueue.sync {
            if let s = symbol {
                orientationCache.removeValue(forKey: s.uppercased())
            } else {
                orientationCache.removeAll()
            }
        }
    }
    
    /// Prunes stale entries from the orientation cache to prevent unbounded memory growth.
    /// Called automatically during cache operations but can be called manually during memory pressure.
    public static func pruneOrientationCache() {
        let now = Date().timeIntervalSince1970
        orientationQueue.sync {
            // Remove entries older than 2x TTL
            let staleThreshold = now - (orientationCacheTTL * 2)
            orientationCache = orientationCache.filter { $0.value.lastUpdate > staleThreshold }
            
            // If still too large (over 500 entries), remove oldest entries
            if orientationCache.count > 500 {
                let sorted = orientationCache.sorted { $0.value.lastUpdate < $1.value.lastUpdate }
                let keysToRemove = sorted.prefix(orientationCache.count - 400).map { $0.key }
                for key in keysToRemove {
                    orientationCache.removeValue(forKey: key)
                }
            }
        }
    }
    
    // Public API
    public static func canonicalSpark(series: [Double], livePrice: Double?, provider24hRaw: Double?, cacheKey: String? = nil) -> [Double] {
        guard !series.isEmpty else { return series }
        var s = cleanEdges(series)
        
        // SPARKLINE DATA INTEGRITY: Do NOT reverse the sparkline array.
        // CoinGecko and Binance APIs always return data in chronological order (oldest → newest).
        // All reversal logic has been removed — trust the data source.
        // Color (red/green) is determined by the actual 7D% percentage, not sparkline visual trend.
        
        // Anchor & ensure non-flat
        s = anchorToPrice(s, livePrice: livePrice)
        s = ensureNonFlat(s, hintPercent: normalizePercent(provider24hRaw, hint: nil))
        return s
    }

    // Build a metrics-only spark (no winsorization or non-flat shaping). Keeps live anchoring.
    // SPARKLINE INVERSION FIX: Removed ALL reversal logic - API data is always chronological.
    private static func metricsSpark(series: [Double], livePrice: Double?, provider24hRaw: Double?, cacheKey: String? = nil) -> [Double] {
        guard !series.isEmpty else { return series }
        var s = cleanEdges(series)
        
        // Anchor to live price if scale-compatible
        s = anchorToPrice(s, livePrice: livePrice)
        return s
    }

    public static func derive(symbol: String, spark: [Double], livePrice: Double?, provider1h: Double?, provider24h: Double?, isStable: Bool) -> (oneHFrac: Double?, dayFrac: Double?, isPositive7D: Bool) {
        let d = deriveDetailed(
            symbol: symbol,
            spark: spark, // spark no longer used for metrics derivation
            livePrice: livePrice,
            provider1h: provider1h,
            provider24h: provider24h,
            isStable: isStable,
            seriesSpanHours: nil
        )
        return (d.oneHFrac, d.dayFrac, d.isPositive7D)
    }

    public static func deriveDetailed(
        symbol: String,
        spark: [Double],
        livePrice: Double?,
        provider1h: Double?,
        provider24h: Double?,
        isStable: Bool,
        seriesSpanHours: Double? = nil,
        provider7d: Double? = nil
    ) -> (oneHFrac: Double?, dayFrac: Double?, isPositive7D: Bool, sevenDFrac: Double?) {
        // Provider-first with live-anchor fallbacks and spark-derived backup. Metrics do NOT depend on display smoothing.
        let sym = symbol.uppercased()
        if let lp = livePrice, lp.isFinite, lp > 0 { recordAnchor(symbol: sym, price: lp) }

        // Span hint for spark-derived interpolation
        let span = max(1.0, seriesSpanHours ?? 168.0)

        // Derive from our live anchor store (percent units)
        let a1h = percentFromAnchors(symbol: sym, lookbackHours: 1)
        let a24 = percentFromAnchors(symbol: sym, lookbackHours: 24)
        let a7d = percentFromAnchors(symbol: sym, lookbackHours: 24*7)

        // Spark-derived as a last resort (anchored to live when scale-compatible), span-aware and refusing horizons longer than span
        let s1h = percentFromSparkLinearAnchored(spark, hours: 1, livePrice: livePrice, spanHours: span)
            ?? percentFromSparkLinear(spark, hours: 1, spanHours: span)
            ?? percentFromSpark(spark, lookbackHours: 1, spanHours: span)
        let s24 = percentFromSparkLinearAnchored(spark, hours: 24, livePrice: livePrice, spanHours: span)
            ?? percentFromSparkLinear(spark, hours: 24, spanHours: span)
            ?? percentFromSpark(spark, lookbackHours: 24, spanHours: span)
        let s7d = percentFromSparkLinearAnchored(spark, hours: 24*7, livePrice: livePrice, spanHours: span)
            ?? percentFromSparkLinear(spark, hours: 24*7, spanHours: span)
            ?? percentFromSpark(spark, lookbackHours: 24*7, spanHours: span)

        // Seed-normalize provider values using best available hints (anchors or spark) before we have final reconciled deltas
        let p1hSeed = normalizePercent(provider1h, hint: a1h)
        let p24Seed = normalizePercent(provider24h, hint: a24)
        let p7dSeed = normalizePercent(provider7d, hint: a7d)
        
        // LIVE adjustments: prefer live-price-based deltas using provider-seeded prev prices
        var liveAdj1h: Double? = nil
        var liveAdj24: Double? = nil
        var liveAdj7d: Double? = nil
        if let lp = livePrice, lp.isFinite, lp > 0 {
            if let prev = ensurePrevFixed(symbol: sym, hours: 1, live: lp, providerPct: p1hSeed) { liveAdj1h = ((lp - prev) / prev) * 100.0 }
            if let prev = ensurePrevFixed(symbol: sym, hours: 24, live: lp, providerPct: p24Seed) { liveAdj24 = ((lp - prev) / prev) * 100.0 }
            if let prev = ensurePrevFixed(symbol: sym, hours: 24*7, live: lp, providerPct: p7dSeed) { liveAdj7d = ((lp - prev) / prev) * 100.0 }
        }
        // Guard live adjustments with plausibility checks vs derived hints to avoid bad provider seeds
        if let prov = p1hSeed, let hint = a1h, prov.isFinite, hint.isFinite {
            let ratio = abs(prov) / max(abs(hint), 1e-6)
            let signMismatch = (prov >= 0) != (hint >= 0)
            if signMismatch || ratio > 6.0 || abs(prov) > 40.0 { liveAdj1h = nil }
            if abs(prov) < 0.02 && abs(hint) >= 0.2 { liveAdj1h = nil }
        }
        if let prov = p24Seed, let hint = a24, prov.isFinite, hint.isFinite {
            let ratio = abs(prov) / max(abs(hint), 1e-6)
            let signMismatch = (prov >= 0) != (hint >= 0)
            if signMismatch || ratio > 6.0 || abs(prov) > 120.0 { liveAdj24 = nil }
            if abs(prov) < 0.02 && abs(hint) >= 0.3 { liveAdj24 = nil }
        }
        if let prov = p7dSeed, let hint = a7d, prov.isFinite, hint.isFinite {
            let ratio = abs(prov) / max(abs(hint), 1e-6)
            let signMismatch = (prov >= 0) != (hint >= 0)
            if signMismatch || ratio > 6.0 || abs(prov) > 300.0 { liveAdj7d = nil }
        }

        // Prefer anchors (live history) first, then spark-derived, then LIVE baseline deltas (provider-seeded)
        let d1h = a1h ?? s1h ?? liveAdj1h
        let d24 = a24 ?? s24 ?? liveAdj24
        let d7d = a7d ?? s7d ?? liveAdj7d

        // Final normalization guided by the reconciled/derived deltas for maximum disambiguation
        let p1hNorm = normalizePercent(provider1h, hint: d1h)
        let p24Norm = normalizePercent(provider24h, hint: d24)
        let p7dNorm = normalizePercent(provider7d, hint: d7d)

        // Reconcile provider vs derived for robustness
        // Returns nil when no data is available (instead of 0) to distinguish "no data" from "0% change"
        func reconcile(_ provider: Double?, _ derived: Double?, maxAbs: Double) -> Double? {
            if let prov = provider, let der = derived, prov.isFinite, der.isFinite {
                let nearZeroProv = abs(prov) < 0.02
                let meaningfulDer = abs(der) >= 0.05
                let magFar = (abs(der) >= 0.05) && ((max(abs(prov), 1e-6) / max(abs(der), 1e-6)) > 4.0)
                if magFar { return der }
                if abs(prov) > (maxAbs * 0.6) && abs(der) <= (maxAbs * 0.2) { return der }
                if nearZeroProv && meaningfulDer { return der }
                let signMismatch = (prov >= 0) != (der >= 0)
                let magClose = (max(abs(prov), 1e-6) / max(abs(der), 1e-6)) < 1.8 && (max(abs(der), 1e-6) / max(abs(prov), 1e-6)) < 1.8
                if signMismatch && magClose { return der }
                if abs(prov) > maxAbs && abs(der) <= maxAbs { return der }
                return prov
            }
            if let prov = provider, prov.isFinite { return prov }
            if let der = derived, der.isFinite { return der }
            return nil  // No data available - UI will show "—" instead of "0.00%"
        }

        // FIX: Use consistent limits across app: ±50% (1h), ±300% (24h), ±500% (7d)
        // reconcile() now returns nil when no data is available
        var oneH: Double? = reconcile(p1hNorm, d1h, maxAbs: 50.0)
        var day: Double? = reconcile(p24Norm, d24, maxAbs: 300.0)
        var seven: Double? = reconcile(p7dNorm, d7d, maxAbs: 500.0)

        // Insert stabilizeOutputs call here (only if we have values)
        if let oneHVal = oneH, let dayVal = day {
            let stabilized = stabilizeOutputs(symbol: sym, oneH: oneHVal, day: dayVal)
            oneH = stabilized.0
            day  = stabilized.1
        }

        // Final plausibility clamp and quantization (percent units). Preserve true zeros.
        // FIX: Use consistent limits across app: ±50% (1h), ±300% (24h), ±500% (7d)
        if let val = oneH { oneH = quantizeAway(plausiblePercent(val, hint: d1h, maxAbs: 50.0), step: 0.01, preserveZero: true) }
        if let val = day { day = quantizeAway(plausiblePercent(val, hint: d24, maxAbs: 300.0), step: 0.01, preserveZero: true) }
        if let val = seven { seven = quantizeAway(plausiblePercent(val, hint: d7d, maxAbs: 500.0), step: 0.01, preserveZero: true) }

        // Stablecoin soft rules
        if isStable {
            if let val = oneH { oneH = sanitizeStable(val) }
            if let val = day { day = sanitizeStable(val) }
            if let val = seven { seven = sanitizeStable(val) }
        }

        // Convert to fractional for UI - preserve nil for "no data"
        let oneHFrac: Double? = oneH.flatMap { $0.isFinite ? $0 / 100.0 : nil }
        let dayFrac: Double? = day.flatMap { $0.isFinite ? $0 / 100.0 : nil }
        let sevenDFrac: Double? = seven.flatMap { $0.isFinite ? $0 / 100.0 : nil }

        // 7D sign preference: reconciled 7D, else anchor 7D, else spark 7D, else reconciled 24H, else anchor 24H, else spark 24H, else provider 1H
        let isPositive7D: Bool = {
            if let s = seven, s.isFinite { return s >= 0 }
            if let a = a7d, a.isFinite { return a >= 0 }
            if let s = s7d, s.isFinite { return s >= 0 }
            if let d = day, d.isFinite { return d >= 0 }
            if let dA = a24, dA.isFinite { return dA >= 0 }
            if let dS = s24, dS.isFinite { return dS >= 0 }
            if let h = p1hNorm, h.isFinite { return h >= 0 }
            return true
        }()

        return (oneHFrac, dayFrac, isPositive7D, sevenDFrac)
    }

    // Produce a sparkline optimized for display (resampled and lightly smoothed)
    public static func displaySpark(canonical: [Double], livePrice: Double?, targetPoints: Int = 180) -> [Double] {
        var s = canonical
        guard !s.isEmpty else { return s }
        // Re-anchor softly in case upstream live price changed between calls
        s = anchorToPrice(s, livePrice: livePrice)
        // Downsample using simple decimation to preserve natural shape
        let target = max(24, min(max(2, targetPoints), 600))
        s = downsampleDecimated(s, target: target)
        // Light smoothing to reduce jaggies; keep endpoints
        let passes = s.count > 200 ? 2 : 1
        s = smoothWeighted(s, passes: passes)
        // Ensure non-flat (guided by 0 sign if no hint)
        s = ensureNonFlat(s, hintPercent: nil)
        // Guarantee non-negative
        return s.map { max(0, $0.isFinite ? $0 : 0) }
    }

    // Unified convenience: compute canonical spark, display spark, and 1H/24H/7D in one call
    public static func computeAll(
        symbol: String,
        rawSeries: [Double],
        livePrice: Double?,
        provider1h: Double?,
        provider24h: Double?,
        isStable: Bool,
        targetPoints: Int = 180
    ) -> (canonical: [Double], display: [Double], oneHFrac: Double?, dayFrac: Double?, isPositive7D: Bool) {
        let cacheKey = symbol.uppercased()
        let canonical = canonicalSpark(series: rawSeries, livePrice: livePrice, provider24hRaw: provider24h, cacheKey: cacheKey)
        let metrics = metricsSpark(series: rawSeries, livePrice: livePrice, provider24hRaw: provider24h, cacheKey: cacheKey)
        let display = displaySpark(canonical: canonical, livePrice: livePrice, targetPoints: targetPoints)
        let d = derive(symbol: symbol, spark: metrics, livePrice: livePrice, provider1h: provider1h, provider24h: provider24h, isStable: isStable)
        // COLOR FIX: Use percentage-derived isPositive7D instead of sparkline visual trend.
        // d.isPositive7D is calculated from actual 7D% → 24H% → 1H% data, which is always correct.
        // Sparkline visual trend can be wrong due to anchoring, micro-wiggle, or edge effects.
        let isPos = d.isPositive7D
        return (canonical, display, d.oneHFrac, d.dayFrac, isPos)
    }

    public static func computeAllV2(
        symbol: String,
        rawSeries: [Double],
        livePrice: Double?,
        provider1h: Double?,
        provider24h: Double?,
        isStable: Bool,
        seriesSpanHours: Double? = nil,
        targetPoints: Int = 180,
        provider7d: Double? = nil
    ) -> (canonical: [Double], display: [Double], oneHFrac: Double?, dayFrac: Double?, sevenDFrac: Double?, isPositive7D: Bool) {
        let cacheKey = symbol.uppercased()
        let canonical = canonicalSpark(series: rawSeries, livePrice: livePrice, provider24hRaw: provider24h, cacheKey: cacheKey)
        
        // SPARKLINE DATA INTEGRITY: Do NOT reverse the canonical sparkline array.
        // Binance klines and CoinGecko API always return data in chronological order (oldest→newest).
        // Reversing based on percentage signals creates fake, numerically backwards charts that
        // differ across devices depending on cache age. Rely on isPositive color for direction.
        
        let display = displaySpark(canonical: canonical, livePrice: livePrice, targetPoints: targetPoints)
        let metrics = metricsSpark(series: rawSeries, livePrice: livePrice, provider24hRaw: provider24h, cacheKey: cacheKey)
        let d = deriveDetailed(symbol: symbol, spark: metrics, livePrice: livePrice, provider1h: provider1h, provider24h: provider24h, isStable: isStable, seriesSpanHours: seriesSpanHours)
        // COLOR FIX: Use percentage-derived isPositive7D instead of sparkline visual trend.
        let isPos = d.isPositive7D
        return (canonical, display, d.oneHFrac, d.dayFrac, d.sevenDFrac, isPos)
    }

    // MARK: - Timestamped Series Utilities
    // Estimate the span (in hours) of a series given its timestamps (epoch seconds).
    public static func estimateSpanHours(timestamps: [TimeInterval]) -> Double? {
        guard timestamps.count >= 2 else { return nil }
        // Use min/max to be robust to slight disorder
        let lo = timestamps.min() ?? 0
        let hi = timestamps.max() ?? 0
        guard hi > lo, hi.isFinite, lo.isFinite else { return nil }
        let spanSeconds = hi - lo
        if spanSeconds <= 0 { return nil }
        return spanSeconds / 3600.0
    }

    // Convenience that consumes raw closes with timestamps and computes canonical/display + metrics using inferred span.
    public static func computeAllFromCloses(
        symbol: String,
        closes: [Double],
        timestamps: [TimeInterval],
        livePrice: Double?,
        provider1h: Double?,
        provider24h: Double?,
        isStable: Bool,
        targetPoints: Int = 180
    ) -> (canonical: [Double], display: [Double], oneHFrac: Double?, dayFrac: Double?, sevenDFrac: Double?, isPositive7D: Bool) {
        // Infer span from timestamps; fall back to 7 days if not available
        let span = estimateSpanHours(timestamps: timestamps) ?? 168.0
        let cacheKey = symbol.uppercased()
        let canonical = canonicalSpark(series: closes, livePrice: livePrice, provider24hRaw: provider24h, cacheKey: cacheKey)
        let display = displaySpark(canonical: canonical, livePrice: livePrice, targetPoints: targetPoints)
        let metrics = metricsSpark(series: closes, livePrice: livePrice, provider24hRaw: provider24h, cacheKey: cacheKey)
        let d = deriveDetailed(
            symbol: symbol,
            spark: metrics,
            livePrice: livePrice,
            provider1h: provider1h,
            provider24h: provider24h,
            isStable: isStable,
            seriesSpanHours: span
        )
        // COLOR FIX: Use percentage-derived isPositive7D instead of sparkline visual trend.
        let isPos = d.isPositive7D
        return (canonical, display, d.oneHFrac, d.dayFrac, d.sevenDFrac, isPos)
    }

    // MARK: - Live Anchors (provider-independent history for 1H/24H/7D)
    // We keep a lightweight in-memory history of live prices per symbol to compute time-based deltas
    // without relying on sparklines. This store is pruned automatically and is thread-safe via a serial queue.
    private static let anchorQueue = DispatchQueue(label: "MarketMetricsEngine.AnchorQueue", qos: .userInitiated)
    private static var anchorSeries: [String: [(t: TimeInterval, p: Double)]] = [:]
    private static let anchorRetention: TimeInterval = 8 * 24 * 3600 // keep up to 8 days of samples
    private static let anchorMaxPerSymbol: Int = 4000

    // Public helper to clear live anchors and provider-seeded baselines
    public static func resetAnchors(for symbol: String? = nil) {
        anchorQueue.sync {
            if let s = symbol {
                anchorSeries[s] = []
                prevFixed1h[s] = nil
                prevFixed24h[s] = nil
                prevFixed7d[s] = nil
            } else {
                anchorSeries.removeAll()
                prevFixed1h.removeAll()
                prevFixed24h.removeAll()
                prevFixed7d.removeAll()
            }
        }
    }

    private static func recordAnchor(symbol: String, price: Double, at time: TimeInterval = Date().timeIntervalSince1970) {
        guard price.isFinite, price > 0 else { return }
        anchorQueue.sync {
            var arr = anchorSeries[symbol] ?? []
            arr.append((time, price))
            let cutoff = time - anchorRetention
            if let firstIdx = arr.firstIndex(where: { $0.t >= cutoff }) {
                if firstIdx > 0 { arr.removeFirst(firstIdx) }
            } else if !arr.isEmpty {
                if let lastElement = arr.last { arr = [lastElement] }
            }
            if arr.count > anchorMaxPerSymbol { arr.removeFirst(arr.count - anchorMaxPerSymbol) }
            anchorSeries[symbol] = arr
        }
    }

    private static func percentFromAnchors(symbol: String, lookbackHours: Double, now: TimeInterval = Date().timeIntervalSince1970) -> Double? {
        let hours = max(0.0, lookbackHours)
        let targetT = now - hours * 3600.0
        var arr: [(t: TimeInterval, p: Double)] = []
        anchorQueue.sync { arr = anchorSeries[symbol] ?? [] }
        guard arr.count >= 2, let last = arr.last else { return nil }
        guard let arrFirst = arr.first else { return nil }
        if targetT <= arrFirst.t { return nil }
        if targetT >= last.t { return nil }
        var lo = 0
        var hi = arr.count - 1
        while lo + 1 < hi {
            let mid = (lo + hi) / 2
            if arr[mid].t <= targetT { lo = mid } else { hi = mid }
        }
        let a = arr[lo]
        let b = arr[hi]
        let denom = max(1e-9, b.t - a.t)
        let t = (targetT - a.t) / denom
        let prev = a.p + (b.p - a.p) * t
        guard prev > 0 else { return nil }
        let pct = ((last.p - prev) / prev) * 100.0
        return pct.isFinite ? pct : nil
    }

    // MARK: - Live Baselines (provider-seeded prev price to keep deltas live)
    private static var prevFixed1h: [String: (t: TimeInterval, p: Double)] = [:]
    private static var prevFixed24h: [String: (t: TimeInterval, p: Double)] = [:]
    private static var prevFixed7d: [String: (t: TimeInterval, p: Double)] = [:]

    private static func prevFixedTTL(_ hours: Double) -> TimeInterval {
        if hours <= 1 { return 90 }          // refresh ~90s for 1H
        if hours <= 24 { return 5 * 60 }     // refresh ~5m for 24H
        return 30 * 60                       // refresh ~30m for 7D
    }

    private static func ensurePrevFixed(symbol: String, hours: Double, live: Double, providerPct: Double?) -> Double? {
        guard live.isFinite, live > 0, let pct = providerPct, pct.isFinite else { return nil }
        let now = Date().timeIntervalSince1970
        let prev = live / max(1e-12, (1.0 + pct / 100.0))
        return anchorQueue.sync {
            var store: [String: (t: TimeInterval, p: Double)]
            let ttl = prevFixedTTL(hours)
            switch hours {
            case ..<1.5: store = prevFixed1h
            case ..<36:  store = prevFixed24h
            default:     store = prevFixed7d
            }
            let current = store[symbol]
            let needsRefresh: Bool = {
                guard let cur = current else { return true }
                if now - cur.t > ttl { return true }
                let diff = abs(prev - cur.p) / max(1e-9, cur.p)
                return diff > 0.02 // >2% drift implies provider changed materially; refresh
            }()
            if needsRefresh {
                let entry = (t: now, p: prev)
                switch hours {
                case ..<1.5: prevFixed1h[symbol] = entry
                case ..<36:  prevFixed24h[symbol] = entry
                default:     prevFixed7d[symbol] = entry
                }
                return entry.p
            } else {
                return current!.p
            }
        }
    }

    // Added static vars for stabilization
    private static var lastOutputs: [String: (t: TimeInterval, oneH: Double, day: Double)] = [:]
    private static var outputsTTL: TimeInterval = 300 // seconds

    // Public helpers for stabilization cache
    public static func setOutputsTTL(_ seconds: TimeInterval) {
        anchorQueue.sync { outputsTTL = max(30, seconds) }
    }

    public static func resetStabilizer(for symbol: String? = nil) {
        anchorQueue.sync {
            if let s = symbol { lastOutputs.removeValue(forKey: s) }
            else { lastOutputs.removeAll() }
        }
    }

    // Added private stabilizer helpers
    private static func stabilizePercent(prev: Double?, new: Double, band: Double, alpha: Double) -> Double {
        guard new.isFinite else { return prev ?? 0 }
        if let p = prev, p.isFinite {
            // Hold inside hysteresis band to prevent flicker, else apply light EMA
            if abs(new - p) < band { return p }
            return p * (1 - alpha) + new * alpha
        }
        return new
    }

    private static func stabilizeOutputs(symbol: String, oneH: Double, day: Double) -> (Double, Double) {
        let now = Date().timeIntervalSince1970
        let prev: (t: TimeInterval, oneH: Double, day: Double)? = anchorQueue.sync { lastOutputs[symbol] }
        let prevValid = prev != nil && (now - (prev!.t)) <= outputsTTL ? prev : nil
        let prev1h = prevValid?.oneH
        let prev24 = prevValid?.day
        // Hysteresis bands in percent units
        let s1 = stabilizePercent(prev: prev1h, new: oneH, band: 0.03, alpha: 0.35)   // 0.03% band for 1H
        let s24 = stabilizePercent(prev: prev24, new: day,  band: 0.05, alpha: 0.30)   // 0.05% band for 24H
        anchorQueue.sync { lastOutputs[symbol] = (t: now, oneH: s1, day: s24) }
        return (s1, s24)
    }

    // MARK: - Helpers (private)

    // Downsample using simple decimation (LTTB-lite) for natural sparkline rendering
    private static func downsampleDecimated(_ series: [Double], target: Int) -> [Double] {
        let n = series.count
        if n <= target { return series }
        
        // Simple stride-based decimation that preserves natural shape
        let stride = max(1, n / target)
        var out: [Double] = []
        out.reserveCapacity(target + 1)
        
        var i = 0
        while i < n && out.count < target {
            out.append(series[i])
            i += stride
        }
        
        // Always include the last point for accurate endpoint
        if let last = series.last, out.last != last {
            if out.count >= target {
                out[out.count - 1] = last
            } else {
                out.append(last)
            }
        }
        
        return out
    }

    // Simple weighted smoothing (0.25, 0.5, 0.25) with fixed endpoints
    private static func smoothWeighted(_ s: [Double], passes: Int) -> [Double] {
        guard s.count > 2, passes > 0 else { return s }
        var out = s
        for _ in 0..<passes {
            var tmp = out
            let n = out.count
            for i in 1..<(n - 1) {
                let a = out[i - 1]
                let b = out[i]
                let c = out[i + 1]
                tmp[i] = max(0, (0.25 * a) + (0.5 * b) + (0.25 * c))
            }
            out = tmp
        }
        return out
    }

    private static func cleanEdges(_ data: [Double]) -> [Double] {
        guard !data.isEmpty else { return data }
        let finite = data.map { $0.isFinite ? $0 : 0 }
        if let firstIdx = finite.firstIndex(where: { $0 > 0 }), let lastIdx = finite.lastIndex(where: { $0 > 0 }), firstIdx <= lastIdx {
            var slice = Array(finite[firstIdx...lastIdx])
            for i in 0..<slice.count { if !slice[i].isFinite || slice[i] < 0 { slice[i] = 0 } }
            return slice
        } else { return finite }
    }

    private static func winsorize(_ data: [Double]) -> [Double] {
        let vals = data.filter { $0.isFinite }
        guard vals.count > 8 else { return data }
        let sorted = vals.sorted()
        func q(_ p: Double) -> Double {
            let i = max(0, min(sorted.count - 1, Int(Double(sorted.count - 1) * p)))
            return sorted[i]
        }
        let q10 = q(0.10), q25 = q(0.25), q75 = q(0.75), q90 = q(0.90)
        let iqr = max(1e-12, q75 - q25)
        let lowFence = q25 - 3.0 * iqr
        let highFence = q75 + 3.0 * iqr
        let hasLow = q10 < lowFence
        let hasHigh = q90 > highFence
        guard hasLow || hasHigh else { return data }
        let low = min(lowFence, q10)
        let high = max(highFence, q90)
        guard high > low else { return data }
        return data.map { min(max($0, low), high) }
    }

    private static func isScaleCompatible(_ data: [Double], price: Double?) -> Bool {
        guard let price = price, price.isFinite, price > 0 else { return false }
        guard data.count > 1 else { return false }
        if let last = data.reversed().first(where: { $0.isFinite && $0 > 0 }) {
            let ar = abs(last / price)
            return ar > 0.25 && ar < 4.0
        }
        return false
    }

    private static func anchorToPrice(_ data: [Double], livePrice: Double?) -> [Double] {
        guard !data.isEmpty, let price = livePrice, price.isFinite, price > 0 else { return data }
        guard isScaleCompatible(data, price: livePrice) else { return data }
        guard let last = data.reversed().first(where: { $0.isFinite && $0 > 0 }) else { return data }
        let scale = price / last
        if scale < 0.6 || scale > 1.6 { return data }
        return data.map { v in v.isFinite ? max(0, v * scale) : v }
    }

    private static func ensureNonFlat(_ data: [Double], hintPercent: Double?) -> [Double] {
        let n = data.count
        guard n > 1 else { return data }
        let baseline = data.reversed().first(where: { $0.isFinite && $0 > 0 }) ?? data.max()
        guard let base = baseline, base.isFinite else { return data }
        let minV = data.min() ?? base
        let maxV = data.max() ?? base
        let rel = (maxV - minV) / max(base, 1e-9)
        if rel >= 0.0006 { return data }
        let dir: Double = { if let h = hintPercent, h.isFinite { return h >= 0 ? 1.0 : -1.0 }; return 0.0 }()
        let amp = max(base * 0.0008, 1e-8)
        var out = data
        if dir != 0 {
            let denom = Double(max(n - 1, 1))
            for i in 0..<n {
                let t = (Double(i) / denom) - 0.5
                let delta = dir * t * 2.0 * amp
                let v = out[i].isFinite ? out[i] : base
                out[i] = max(0, v + delta)
            }
        } else {
            let denom = Double(max(n - 1, 1))
            for i in 0..<n {
                let phase = (Double(i) / denom) * .pi
                let delta = sin(phase) * amp * 0.6
                let v = out[i].isFinite ? out[i] : base
                out[i] = max(0, v + delta)
            }
        }
        return out
    }

    // Percent helpers (percent units)
    private static func normalizePercent(_ raw: Double?, hint: Double?) -> Double? {
        guard let v0 = raw, v0.isFinite else { return hint }
        let vPct = v0
        let vFracToPct = v0 * 100.0
        if let h = hint, h.isFinite { if abs(v0) >= 90, abs(h) <= 20 { return h } }
        if let h = hint, h.isFinite {
            let d0 = abs(vPct - h), d1 = abs(vFracToPct - h)
            if d1 + 1e-6 < d0 * 0.7 { return vFracToPct }
            if d0 + 1e-6 < d1 * 0.7 { return vPct }
            // Only upscale when the raw looks like a tiny fraction (<=0.2%) and the upscaled value is still plausible
            if abs(v0) <= 0.2, abs(vFracToPct) <= 20 { return vFracToPct }
            return vPct
        }
        // Without a hint, prefer keeping the provider value as-is. Only upscale if it looks like a very small fraction.
        if abs(v0) <= 0.2, abs(vFracToPct) <= 20 { return vFracToPct }
        if abs(v0) > 200, abs(v0 / 100.0) <= 80 { return v0 / 100.0 }
        return vPct
    }
    private static func plausiblePercent(_ value: Double, hint: Double?, maxAbs: Double) -> Double {
        if let h = hint, h.isFinite { if abs(value) > maxAbs && abs(h) <= maxAbs { return h } }
        if abs(value) > (maxAbs * 2) {
            let down = value / 100.0
            if abs(down) <= maxAbs { return down }
        }
        return max(-maxAbs, min(maxAbs, value.isFinite ? value : 0))
    }
    private static func quantizeAway(_ v: Double, step: Double, preserveZero: Bool = true) -> Double {
        guard v.isFinite else { return 0 }
        let s = max(step, 1e-9)
        if v == 0 { return 0 }
        let absV = abs(v)
        if absV < s { return preserveZero ? 0 : (v > 0 ? s : -s) }
        let q = (v / s).rounded() * s
        if q == 0 { return preserveZero ? 0 : (v > 0 ? s : -s) }
        return q
    }
    private static func sanitizeStable(_ v: Double) -> Double {
        let absV = abs(v)
        if absV < 0.05 { return 0 }
        let cap = 5.0
        if absV > cap { return v.sign == .minus ? -cap : cap }
        return v
    }

    // Derivations from spark (percent units)
    private static func percentFromSpark(_ series: [Double], lookbackHours: Int) -> Double? {
        let data = series.filter { $0.isFinite }
        let n = data.count
        guard n >= 3, lookbackHours > 0 else { return nil }
        
        // SMART STEP CALCULATION: Detect actual data coverage based on point count
        // Common sparkline formats:
        // - 168 points (140-200): Hourly data over 7 days
        // - 42 points (35-55): 4-hour intervals over 7 days
        // - 7 points (5-14): Daily data over 7 days
        let (estimatedTotalHours, stepHours): (Double, Double) = {
            if n >= 140 && n <= 200 {
                return (Double(n - 1), 1.0)  // Hourly data
            } else if n >= 35 && n < 140 {
                return (Double(n - 1) * 4.0, 4.0)  // 4-hour interval
            } else if n >= 5 && n < 35 {
                return (Double(n - 1) * 24.0, 24.0)  // Daily data
            } else {
                let totalH = 24.0 * 7.0
                let step = totalH / Double(max(1, n - 1))
                return (totalH, step)  // Fallback
            }
        }()
        
        // CRITICAL FIX: Reject derivation when sparkline resolution is too coarse
        // If stepHours > lookbackHours, we CANNOT accurately derive the percentage
        // Example: Daily data (stepHours=24) cannot derive 1H change - would show 24H change as 1H!
        if stepHours > Double(lookbackHours) { return nil }
        
        // Validate minimum coverage for requested timeframe
        let minimumCoverageRequired = Double(lookbackHours) * 0.8
        if estimatedTotalHours < minimumCoverageRequired { return nil }
        
        let lookbackPoints = max(1, Int(round(Double(lookbackHours) / stepHours)))
        let clamped = min(lookbackPoints, max(1, n - 1))
        let nominalIndex = max(0, (n - 1) - clamped)
        func findUsable(around idx: Int, maxSteps: Int = 12) -> Int? {
            var best: Int? = nil
            var step = 0
            while step <= maxSteps { let back = idx - step; if back >= 0, data[back] > 0, data[back].isFinite { best = back; break }; step += 1 }
            if best == nil { step = 1; while step <= maxSteps { let f = idx + step; if f < n, data[f] > 0, data[f].isFinite { best = f; break }; step += 1 } }
            if best == nil { best = data.firstIndex(where: { $0 > 0 && $0.isFinite }) }
            return best
        }
        var lastIndex = n - 1
        if !(data[lastIndex] > 0 && data[lastIndex].isFinite) {
            if let idx = (stride(from: lastIndex, through: 0, by: -1).first { data[$0] > 0 && data[$0].isFinite }) { lastIndex = idx } else { return nil }
        }
        guard let prevIndex = findUsable(around: nominalIndex) else { return nil }
        let last = data[lastIndex]
        let prev = data[prevIndex]
        guard prev > 0, last.isFinite else { return nil }
        return ((last - prev) / prev) * 100.0
    }
    private static func percentFromSpark(_ series: [Double], lookbackHours: Int, spanHours: Double) -> Double? {
        let data = series.filter { $0.isFinite }
        let n = data.count
        guard n >= 3, lookbackHours > 0 else { return nil }
        // If the requested horizon exceeds the series span, refuse to compute
        if Double(lookbackHours) > spanHours * 0.98 { return nil }

        // Estimate points per hour from the provided span instead of assuming 7 days
        let estPPH = max(1, Int(round(Double(max(1, n - 1)) / max(1.0, spanHours))))
        
        // CRITICAL FIX: Calculate step hours and reject if resolution too coarse
        let stepHours = spanHours / Double(max(1, n - 1))
        if stepHours > Double(lookbackHours) { return nil }
        
        let lookbackPoints = max(1, estPPH * lookbackHours)
        let clamped = min(lookbackPoints, max(1, n - 1))
        let nominalIndex = max(0, (n - 1) - clamped)

        func findUsable(around idx: Int, maxSteps: Int = 12) -> Int? {
            var best: Int? = nil
            var step = 0
            while step <= maxSteps {
                let back = idx - step
                if back >= 0, data[back] > 0, data[back].isFinite { best = back; break }
                step += 1
            }
            if best == nil {
                step = 1
                while step <= maxSteps {
                    let f = idx + step
                    if f < n, data[f] > 0, data[f].isFinite { best = f; break }
                    step += 1
                }
            }
            if best == nil { best = data.firstIndex(where: { $0 > 0 && $0.isFinite }) }
            return best
        }

        var lastIndex = n - 1
        if !(data[lastIndex] > 0 && data[lastIndex].isFinite) {
            if let idx = (stride(from: lastIndex, through: 0, by: -1).first { data[$0] > 0 && data[$0].isFinite }) {
                lastIndex = idx
            } else {
                return nil
            }
        }
        guard let prevIndex = findUsable(around: nominalIndex) else { return nil }
        let last = data[lastIndex]
        let prev = data[prevIndex]
        guard prev > 0, last.isFinite else { return nil }
        return ((last - prev) / prev) * 100.0
    }

    private static func percentFromSparkLinear(_ series: [Double], hours: Int, spanHours: Double? = nil) -> Double? {
        let data = series.filter { $0.isFinite && $0 > 0 }
        guard data.count >= 2 else { return nil }
        let n = data.count
        
        // SMART SPAN DETECTION: Auto-detect if not provided
        let effectiveSpan: Double = spanHours ?? {
            if n >= 140 && n <= 200 { return Double(n - 1) }  // Hourly data
            else if n >= 35 && n < 140 { return Double(n - 1) * 4.0 }  // 4-hour interval
            else if n >= 5 && n < 35 { return Double(n - 1) * 24.0 }  // Daily data
            else { return 168.0 }  // Fallback to 7 days
        }()
        
        let step = effectiveSpan / Double(n - 1)
        
        // CRITICAL FIX: Reject derivation when resolution is too coarse for requested timeframe
        // Example: Daily data (step=24h) cannot derive 1H change accurately
        if step > Double(hours) { return nil }
        
        let clampedHours = max(0.0, min(Double(hours), effectiveSpan))

        // Refuse horizons longer than the provided span to avoid fabricating deltas
        if Double(hours) > effectiveSpan * 0.98 { return nil }

        let last = data[n - 1]
        let idx = Double(n - 1) - (clampedHours / step)
        let prev: Double
        if idx <= 0 { prev = data[0] }
        else if idx >= Double(n - 1) { prev = data[n - 1] }
        else {
            let i0 = Int(floor(idx)); let i1 = Int(ceil(idx)); let t = idx - Double(i0)
            let v0 = data[i0]; let v1 = data[i1]
            prev = v0 + (v1 - v0) * t
        }
        guard prev > 0 else { return nil }
        let pct = ((last - prev) / prev) * 100.0
        return pct.isFinite ? pct : nil
    }

    private static func percentFromSparkLinearAnchored(_ series: [Double], hours: Int, livePrice: Double?, spanHours: Double? = nil) -> Double? {
        let data = series.filter { $0.isFinite && $0 > 0 }
        guard data.count >= 2 else { return nil }
        let n = data.count
        
        // SMART SPAN DETECTION: Auto-detect if not provided
        let effectiveSpan: Double = spanHours ?? {
            if n >= 140 && n <= 200 { return Double(n - 1) }  // Hourly data
            else if n >= 35 && n < 140 { return Double(n - 1) * 4.0 }  // 4-hour interval
            else if n >= 5 && n < 35 { return Double(n - 1) * 24.0 }  // Daily data
            else { return 168.0 }  // Fallback to 7 days
        }()
        
        let step = effectiveSpan / Double(n - 1)
        
        // CRITICAL FIX: Reject derivation when resolution is too coarse for requested timeframe
        // Example: Daily data (step=24h) cannot derive 1H change accurately
        if step > Double(hours) { return nil }
        
        let lastRaw = data[n - 1]
        let last: Double
        if let lp = livePrice, isScaleCompatible(series, price: lp), lp > 0 { last = lp } else { last = lastRaw }
        let clampedHours = max(0.0, min(Double(hours), effectiveSpan))

        // Refuse horizons longer than the provided span to avoid fabricating deltas
        if Double(hours) > effectiveSpan * 0.98 { return nil }
        let idx = Double(n - 1) - (clampedHours / step)
        let prev: Double
        if idx <= 0 { prev = data[0] }
        else if idx >= Double(n - 1) { prev = data[n - 1] }
        else {
            let i0 = Int(floor(idx)); let i1 = Int(ceil(idx)); let t = idx - Double(i0)
            let v0 = data[i0]; let v1 = data[i1]
            prev = v0 + (v1 - v0) * t
        }
        guard prev > 0 else { return nil }
        let pct = ((last - prev) / prev) * 100.0
        return pct.isFinite ? pct : nil
    }
}

