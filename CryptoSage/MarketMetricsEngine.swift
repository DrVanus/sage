import Foundation

public struct MarketMetricsEngine {
    // Public API
    public static func canonicalSpark(series: [Double], livePrice: Double?, provider24hRaw: Double?) -> [Double] {
        guard !series.isEmpty else { return series }
        var s = cleanEdges(series)
        s = winsorize(s)
        // Orient
        if isScaleCompatible(s, price: livePrice), let price = livePrice, price.isFinite, price > 0, s.count > 1,
           let first = s.first, let last = s.last, first.isFinite, last.isFinite, first > 0, last > 0 {
            let dFirst = abs(first - price)
            let dLast = abs(last - price)
            if dFirst + 1e-9 < dLast * 0.92 { s.reverse() }
        } else if s.count > 1 {
            let nrm = s
            let rev = Array(s.reversed())
            let d24N = percentFromSparkLinear(nrm, hours: 24) ?? percentFromSpark(nrm, lookbackHours: 24)
            let d24R = percentFromSparkLinear(rev, hours: 24) ?? percentFromSpark(rev, lookbackHours: 24)
            let p24N = normalizePercent(provider24hRaw, hint: d24N)
            let p24R = normalizePercent(provider24hRaw, hint: d24R)
            let errN: Double = (d24N != nil && p24N != nil) ? abs(d24N! - p24N!) : 1e9
            let errR: Double = (d24R != nil && p24R != nil) ? abs(d24R! - p24R!) : 1e9
            s = (errR + 1e-6 < errN) ? rev : nrm
        }
        // Anchor & ensure non-flat
        s = anchorToPrice(s, livePrice: livePrice)
        s = ensureNonFlat(s, hintPercent: normalizePercent(provider24hRaw, hint: nil))
        return s
    }

    public static func derive(symbol: String, spark: [Double], livePrice: Double?, provider1h: Double?, provider24h: Double?, isStable: Bool) -> (oneHFrac: Double, dayFrac: Double, isPositive7D: Bool) {
        // Hints from spark (percent units)
        var hint1h = percentFromSparkLinearAnchored(spark, hours: 1, livePrice: livePrice)
        var hint24h = percentFromSparkLinearAnchored(spark, hours: 24, livePrice: livePrice)
        var hint7d = percentFromSparkLinearAnchored(spark, hours: 24*7, livePrice: livePrice)
        if hint1h == nil { hint1h = percentFromSparkLinear(spark, hours: 1) }
        if hint24h == nil { hint24h = percentFromSparkLinear(spark, hours: 24) }
        if hint7d == nil { hint7d = percentFromSparkLinear(spark, hours: 24*7) }

        // Normalize provider values using hints
        let norm1h = normalizePercent(provider1h, hint: hint1h)
        let norm24h = normalizePercent(provider24h, hint: hint24h)

        // Select best values with plausibility
        let chosen1hPct: Double = {
            if let p = norm1h { return plausiblePercent(p, hint: hint1h, maxAbs: 50.0) }
            if let h = hint1h { return plausiblePercent(h, hint: nil, maxAbs: 50.0) }
            return 0
        }()
        let chosen24hPct: Double = {
            if let p = norm24h { return plausiblePercent(p, hint: hint24h, maxAbs: 80.0) }
            if let h = hint24h { return plausiblePercent(h, hint: nil, maxAbs: 80.0) }
            return 0
        }()

        // Quantize to 0.01% steps away from zero
        var oneH = quantizeAway(chosen1hPct, step: 0.01)
        var day = quantizeAway(chosen24hPct, step: 0.01)

        // Stablecoin rules
        if isStable {
            oneH = sanitizeStable(oneH)
            day = sanitizeStable(day)
        }

        // Convert to fractional for UI
        let oneHFrac = oneH / 100.0
        let dayFrac = day / 100.0

        // 7D sign preference
        let isPositive7D: Bool = {
            if let d7 = percentFromSparkLinearAnchored(spark, hours: 24*7, livePrice: livePrice), d7.isFinite { return d7 >= 0 }
            if let h7 = hint7d, h7.isFinite { return h7 >= 0 }
            if let p = norm24h, p.isFinite { return p >= 0 } // weak fallback
            if spark.count >= 2, let f = spark.first, let l = spark.last { return (l - f) >= 0 }
            return true
        }()
        return (oneHFrac, dayFrac, isPositive7D)
    }

    // MARK: - Helpers (private)
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
        if scale < 0.8 || scale > 1.25 { return data }
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
            if abs(v0) <= 2.0, abs(vFracToPct) <= 80 { return vFracToPct }
            return vPct
        }
        if abs(v0) <= 2.0, abs(vFracToPct) <= 80 { return vFracToPct }
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
    private static func quantizeAway(_ v: Double, step: Double) -> Double {
        guard v.isFinite else { return 0 }
        let s = max(step, 1e-9)
        if v == 0 { return 0 }
        let absV = abs(v)
        if absV < s { return v > 0 ? s : -s }
        let q = (v / s).rounded() * s
        if q == 0 { return v > 0 ? s : -s }
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
        let estPPH = max(1, Int(round(Double(max(1, n - 1)) / (7.0 * 24.0))))
        let lookbackPoints = max(1, estPPH * lookbackHours)
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

    private static func percentFromSparkLinear(_ series: [Double], hours: Int) -> Double? {
        let data = series.filter { $0.isFinite && $0 > 0 }
        guard data.count >= 2 else { return nil }
        let n = data.count
        let spanHours: Double = 168.0
        let clampedHours = max(0.0, min(Double(hours), spanHours))
        let last = data[n - 1]
        let step = spanHours / Double(n - 1)
        let idx = Double(n - 1) - (clampedHours / step)
        let prev: Double
        if idx <= 0 { prev = data.first! }
        else if idx >= Double(n - 1) { prev = data.last! }
        else {
            let i0 = Int(floor(idx)); let i1 = Int(ceil(idx)); let t = idx - Double(i0)
            let v0 = data[i0]; let v1 = data[i1]
            prev = v0 + (v1 - v0) * t
        }
        guard prev > 0 else { return nil }
        let pct = ((last - prev) / prev) * 100.0
        return pct.isFinite ? pct : nil
    }

    private static func percentFromSparkLinearAnchored(_ series: [Double], hours: Int, livePrice: Double?) -> Double? {
        let data = series.filter { $0.isFinite && $0 > 0 }
        guard data.count >= 2 else { return nil }
        let n = data.count
        let spanHours: Double = 168.0
        let clampedHours = max(0.0, min(Double(hours), spanHours))
        let lastRaw = data[n - 1]
        let last = (isScaleCompatible(series, price: livePrice) && (livePrice ?? 0) > 0) ? (livePrice!) : lastRaw
        let step = spanHours / Double(n - 1)
        let idx = Double(n - 1) - (clampedHours / step)
        let prev: Double
        if idx <= 0 { prev = data.first! }
        else if idx >= Double(n - 1) { prev = data.last! }
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
