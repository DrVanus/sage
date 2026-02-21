import Foundation

// Lightweight on-device history for the sentiment score (Crypto CJI / Derived).
// Stores a bounded series with 5-minute buckets, provides interpolation and
// a small calibration helper to keep distribution comparable to common indexes.
public actor SentimentHistoryStore {
    public static let shared = SentimentHistoryStore()

    private struct Point: Codable { let ts: Int; let v: Double }
    private var points: [Point] = []

    private let storageKey = "SentimentHistoryStore.points.v2"  // Bumped to clear potentially corrupted data
    private let bucketSeconds: Int = 300 // 5 minutes
    private let maxDays: Int = 120
    private let hardCap: Int = 5000

    public init() {
        // Inline load logic: actor init cannot call actor-isolated methods
        if let data = UserDefaults.standard.data(forKey: storageKey) {
            if let arr = try? JSONDecoder().decode([Point].self, from: data) {
                points = arr.sorted { $0.ts < $1.ts }
            }
        }
    }

    // MARK: - Public API
    public func record(value: Double, at date: Date = Date()) {
        let ts = Int(date.timeIntervalSince1970)
        let bucket = ts / bucketSeconds
        if let last = points.last, (last.ts / bucketSeconds) == bucket {
            // Replace last point in the same bucket
            points[points.count - 1] = Point(ts: ts, v: value)
        } else {
            points.append(Point(ts: ts, v: value))
        }
        prune(now: ts)
        save()
    }

    public func sample(at date: Date) -> Double? {
        let ts = Int(date.timeIntervalSince1970)
        return sample(ts: ts)
    }

    public func series(from start: Date, to end: Date, count: Int) -> [(timestamp: Int, value: Double)] {
        let n = max(2, count)
        guard !points.isEmpty else { return [] }
        let startTs = Int(start.timeIntervalSince1970)
        let endTs = Int(end.timeIntervalSince1970)
        guard endTs > startTs else { return [] }
        // Require a minimum amount of history to avoid flat series on cold start
        if points.count < 3 { return [] }
        let spanSeconds = points.last!.ts - points.first!.ts
        if spanSeconds < 12 * 3600 { return [] } // < 12 hours of history -> treat as insufficient

        var out: [(Int, Double)] = []
        for i in 0..<n {
            let frac = Double(i) / Double(n - 1)
            let ts = Int(Double(startTs) + frac * Double(endTs - startTs))
            if let v = sample(ts: ts) {
                out.append((ts, v))
            } else if let v = nearest(ts: ts) {
                out.append((ts, v))
            }
        }
        return out
    }

    // MARK: - Calibration helpers
    // Compute a symmetric scale around 50 so that p10 ≈ targetLow and p90 ≈ targetHigh.
    // Returns 1.0 if insufficient data.
    public func scaleFactorForCalibration(values: [Double], targetLow: Double, targetHigh: Double) -> Double {
        guard values.count >= 8 else { return 1.0 }
        let sorted = values.sorted()
        func pct(_ p: Double) -> Double {
            let idx = max(0, min(sorted.count - 1, Int(Double(sorted.count - 1) * p)))
            return sorted[idx]
        }
        let p10 = pct(0.10)
        let p90 = pct(0.90)
        // Avoid division by near-zero; keep neutral anchored at 50
        var sCandidates: [Double] = []
        if p90 > 50 { sCandidates.append(((targetHigh - 50.0) / (p90 - 50.0))) }
        if p10 < 50 { sCandidates.append(((50.0 - targetLow) / (50.0 - p10))) }
        guard let s = sCandidates.min(), s.isFinite else { return 1.0 }
        return max(0.85, min(1.15, s))
    }

    public func scaleFactorForCalibration(values: [Double]) -> Double {
        return scaleFactorForCalibration(values: values, targetLow: 20.0, targetHigh: 80.0)
    }

    public func applyCalibration(_ v: Int, scale s: Double) -> Int {
        let y = 50.0 + (Double(v) - 50.0) * s
        let clamped = max(0.0, min(100.0, y))
        return Int(round(clamped))
    }

    // MARK: - Internals
    private func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey) {
            if let arr = try? JSONDecoder().decode([Point].self, from: data) {
                points = arr.sorted { $0.ts < $1.ts }
            }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(points) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func sample(ts: Int) -> Double? {
        guard !points.isEmpty else { return nil }
        if ts < points.first!.ts { return nil }
        if ts > points.last!.ts { return points.last!.v }
        // Binary search for bracketing points
        var lo = 0
        var hi = points.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let t = points[mid].ts
            if t == ts { return points[mid].v }
            if t < ts { lo = mid + 1 } else { hi = mid - 1 }
        }
        let i1 = max(1, lo)
        let p0 = points[i1 - 1]
        let p1 = points[i1]
        let t = Double(ts - p0.ts) / Double(max(1, p1.ts - p0.ts))
        return p0.v + t * (p1.v - p0.v)
    }

    private func nearest(ts: Int) -> Double? {
        guard !points.isEmpty else { return nil }
        // Binary search nearest
        var lo = 0
        var hi = points.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let t = points[mid].ts
            if t == ts { return points[mid].v }
            if t < ts { lo = mid + 1 } else { hi = mid - 1 }
        }
        let i = min(points.count - 1, max(0, lo))
        if i == 0 { return points[0].v }
        if i >= points.count { return points.last!.v }
        let a = points[i - 1]
        let b = points[i]
        return (abs(a.ts - ts) <= abs(b.ts - ts)) ? a.v : b.v
    }

    private func prune(now: Int) {
        // Drop points older than maxDays
        let cutoff = now - maxDays * 24 * 3600
        points.removeAll { $0.ts < cutoff }

        // Coarsen points older than 7 days to 30-minute buckets
        let weekCut = now - 7 * 24 * 3600

        // We'll build a dictionary keyed by 30-minute bucket for old points to drop non-aligned buckets
        var coarsened: [Point] = []
        coarsened.reserveCapacity(points.count)

        var lastOldBucket: Int?
        for p in points {
            if p.ts < weekCut {
                // Only keep points aligned to 30 min buckets (1800 seconds)
                let bucket30 = p.ts / 1800
                let alignedTs = bucket30 * 1800
                if p.ts == alignedTs {
                    // Avoid duplicates in same bucket - keep last point encountered for that bucket
                    if lastOldBucket != bucket30 {
                        coarsened.append(p)
                        lastOldBucket = bucket30
                    } else {
                        // Replace last appended point for this bucket
                        coarsened[coarsened.count - 1] = p
                    }
                }
                // else drop point not aligned to 30min bucket
            } else {
                // For recent points (less than 7 days old), keep as is
                coarsened.append(p)
            }
        }
        points = coarsened

        // Enforce hard cap by keeping last hardCap points
        if points.count > hardCap {
            points = Array(points.suffix(hardCap))
        }
    }
}
