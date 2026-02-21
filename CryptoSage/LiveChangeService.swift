import Foundation

public final class LiveChangeService {
    public static let shared = LiveChangeService()

    internal struct MinuteEntry {
        let minute: Int
        var price: Double
    }

    private let queue = DispatchQueue(label: "LiveChangeService.queue")
    private var history: [String: [MinuteEntry]] = [:]
    // MEMORY FIX: Reduced from 8 days (11,520 minutes) to 2 days (2,880 minutes).
    // With 250+ symbols at 11,520 entries each, history alone could consume 200+ MB.
    // 2 days still provides full 24h lookback with buffer for calculation accuracy.
    private let maxMinutes = 2 * 24 * 60
    
    // PERFORMANCE FIX: Cached change values to avoid queue.sync blocking during scroll
    // These are updated asynchronously and read without blocking
    private var cachedChanges: [String: [Int: Double]] = [:]  // [symbol: [lookbackHours: percent]]
    private var cachedCoverage: [String: [Int: Bool]] = [:]   // [symbol: [hours: hasCoverage]]
    private let cacheQueue = DispatchQueue(label: "LiveChangeService.cacheQueue", attributes: .concurrent)
    
    // ROBUSTNESS: Memory pressure tracking
    // MEMORY FIX: More aggressive pruning - every 60s instead of 300s, lower threshold
    private var lastPruneAt: Date = .distantPast
    private let pruneCooldown: TimeInterval = 60 // Prune at most every 1 minute
    private let maxSymbolsBeforePrune: Int = 300 // MEMORY FIX: Reduced from 500 to 300

    private func minuteKey(for date: Date) -> Int {
        let timeInterval = date.timeIntervalSince1970
        return Int(timeInterval / 60.0)
    }

    public func ingest(prices: [String: Double], at date: Date = Date()) {
        queue.async {
            let minute = self.minuteKey(for: date)
            for (symbol, price) in prices {
                guard price.isFinite, price > 0 else { continue }
                // ROBUSTNESS: Validate symbol length to prevent bad data
                guard !symbol.isEmpty, symbol.count <= 20 else { continue }
                let sym = symbol.uppercased()
                var entries = self.history[sym] ?? []
                if let last = entries.last, last.minute == minute {
                    entries[entries.count - 1].price = price
                } else {
                    entries.append(MinuteEntry(minute: minute, price: price))
                }
                while let first = entries.first, first.minute < minute - self.maxMinutes {
                    entries.removeFirst()
                }
                self.history[sym] = entries
            }
            
            // ROBUSTNESS: Periodic memory pruning for long-running sessions
            self.pruneIfNeeded()
        }
    }
    
    // MARK: - Memory Management
    
    /// Prunes old/stale symbol data to prevent unbounded memory growth
    private func pruneIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastPruneAt) > pruneCooldown else { return }
        guard history.count > maxSymbolsBeforePrune else { return }
        
        let currentMinute = minuteKey(for: now)
        let staleThreshold = currentMinute - maxMinutes
        
        // Remove symbols with no recent data
        var keysToRemove: [String] = []
        for (sym, entries) in history {
            if entries.isEmpty {
                keysToRemove.append(sym)
            } else if let last = entries.last, last.minute < staleThreshold {
                keysToRemove.append(sym)
            }
        }
        
        for key in keysToRemove {
            history.removeValue(forKey: key)
        }
        
        lastPruneAt = now
        
        #if DEBUG
        if !keysToRemove.isEmpty {
            print("🧹 [LiveChangeService] Pruned \(keysToRemove.count) stale symbols, \(history.count) remaining")
        }
        #endif
    }

    public func change(symbol: String, lookbackHours: Int, livePrice: Double?) -> Double? {
        let sym = symbol.uppercased()
        
        // PERFORMANCE FIX: Try to return cached value first (non-blocking read on concurrent queue)
        // This prevents main thread blocking during scroll
        var cachedValue: Double? = nil
        cacheQueue.sync {
            cachedValue = cachedChanges[sym]?[lookbackHours]
        }
        
        // If we have a cached value and no live price override, return it immediately
        if let cached = cachedValue, livePrice == nil {
            return cached
        }
        
        // PERFORMANCE FIX: On main thread, NEVER block with queue.sync.
        // Return cached value immediately and schedule async background computation.
        // This eliminates 100-300ms main thread blocking that caused scroll jank.
        if Thread.isMainThread {
            // Schedule async computation to populate/refresh cache for next call
            let capturedLivePrice = livePrice
            queue.async { [weak self] in
                guard let self = self else { return }
                guard let entries = self.history[sym], !entries.isEmpty else { return }
                let currentMinute = self.minuteKey(for: Date())
                let targetMinute = currentMinute - lookbackHours * 60
                var foundEntry: MinuteEntry? = nil
                for entry in entries.reversed() {
                    if entry.minute <= targetMinute {
                        foundEntry = entry
                        break
                    }
                }
                guard let prevEntry = foundEntry else { return }
                let prev = prevEntry.price
                let curr = capturedLivePrice ?? entries.last!.price
                guard prev > 0, curr.isFinite, curr > 0 else { return }
                let computed = ((curr - prev) / prev) * 100.0
                self.cacheQueue.async(flags: .barrier) {
                    if self.cachedChanges[sym] == nil {
                        self.cachedChanges[sym] = [:]
                    }
                    self.cachedChanges[sym]?[lookbackHours] = computed
                }
            }
            return cachedValue  // Return cached value (may be nil) while async computation runs
        }
        
        // Background thread path: blocking is acceptable
        let result = queue.sync { () -> Double? in
            guard let entries = history[sym], !entries.isEmpty else { return nil }
            let currentMinute = minuteKey(for: Date())
            let targetMinute = currentMinute - lookbackHours * 60
            var foundEntry: MinuteEntry? = nil
            for entry in entries.reversed() {
                if entry.minute <= targetMinute {
                    foundEntry = entry
                    break
                }
            }
            guard let prevEntry = foundEntry else { return nil }
            let prev = prevEntry.price
            let curr = livePrice ?? entries.last!.price
            guard prev > 0, curr.isFinite, curr > 0 else { return nil }
            return ((curr - prev) / prev) * 100.0
        }
        
        // Update cache asynchronously
        if let computed = result {
            cacheQueue.async(flags: .barrier) { [weak self] in
                if self?.cachedChanges[sym] == nil {
                    self?.cachedChanges[sym] = [:]
                }
                self?.cachedChanges[sym]?[lookbackHours] = computed
            }
        }
        
        return result
    }
    
    /// PERFORMANCE FIX: Non-blocking change lookup using cached values only
    /// Returns nil if no cached value exists (caller should use async version or fallback)
    public func cachedChange(symbol: String, lookbackHours: Int) -> Double? {
        let sym = symbol.uppercased()
        var result: Double? = nil
        cacheQueue.sync {
            result = cachedChanges[sym]?[lookbackHours]
        }
        return result
    }

    public func haveCoverage(symbol: String, hours: Int) -> Bool {
        let sym = symbol.uppercased()
        
        // PERFORMANCE FIX: Try cached value first (non-blocking read on concurrent queue)
        var cachedValue: Bool? = nil
        cacheQueue.sync {
            cachedValue = cachedCoverage[sym]?[hours]
        }
        if let cached = cachedValue {
            return cached
        }
        
        // PERFORMANCE FIX: On main thread, NEVER block with queue.sync.
        // Return false immediately and schedule async background computation.
        // This eliminates main thread blocking that caused scroll jank.
        if Thread.isMainThread {
            queue.async { [weak self] in
                guard let self = self else { return }
                guard let entries = self.history[sym], entries.count >= 2 else { return }
                let first = entries.first!
                let last = entries.last!
                let spanMinutes = last.minute - first.minute + 1
                let requiredMinutes = Int(Double(hours) * 60.0 * 0.8)
                let computed = spanMinutes >= requiredMinutes
                self.cacheQueue.async(flags: .barrier) {
                    if self.cachedCoverage[sym] == nil {
                        self.cachedCoverage[sym] = [:]
                    }
                    self.cachedCoverage[sym]?[hours] = computed
                }
            }
            return false  // Return false while async computation runs; next call will have cached result
        }
        
        // Background thread path: blocking is acceptable
        let result = queue.sync { () -> Bool in
            guard let entries = history[sym], entries.count >= 2 else { return false }
            let first = entries.first!
            let last = entries.last!
            let spanMinutes = last.minute - first.minute + 1
            let requiredMinutes = Int(Double(hours) * 60.0 * 0.8)
            return spanMinutes >= requiredMinutes
        }
        
        // Update cache asynchronously
        cacheQueue.async(flags: .barrier) { [weak self] in
            if self?.cachedCoverage[sym] == nil {
                self?.cachedCoverage[sym] = [:]
            }
            self?.cachedCoverage[sym]?[hours] = result
        }
        
        return result
    }
    
    // Seed minute history from an evenly-spaced series covering spanHours (defaults to ~7 days).
    // The series is interpreted oldest->newest. If livePrice is provided and the last series value
    // is scale-compatible, the series is linearly scaled so the last value equals livePrice.
    func seed(symbol: String, series: [Double], livePrice: Double?, spanHours: Double = 168.0) {
        let sym = symbol.uppercased()
        guard series.count >= 2 else { return }
        let now = Date()
        let currentMinute = minuteKey(for: now)

        // Build a cleaned copy with only finite, positive values; keep zeros out to avoid bad anchors
        let cleaned: [Double] = series.map { v in (v.isFinite && v > 0) ? v : 0 }
        guard cleaned.contains(where: { $0 > 0 }) else { return }

        // Determine scale to anchor last value to live price if plausible
        var scale: Double = 1.0
        if let live = livePrice, live.isFinite, live > 0 {
            if let last = cleaned.last, last > 0 {
                let ratio = live / last
                let ar = abs(ratio)
                if ar > 0.25 && ar < 4.0 { scale = ratio }
            }
        }

        // Compute minute spacing based on spanHours and sample count
        let totalSteps = series.count - 1
        let stepMinutes = max(1, Int(round(spanHours * 60.0 / Double(totalSteps))))

        // Build seeded entries (oldest -> newest mapped to minutes ending at now)
        var seeded: [MinuteEntry] = []
        seeded.reserveCapacity(series.count)
        for i in 0..<series.count {
            let v = cleaned[i]
            guard v > 0 else { continue }
            let minute = currentMinute - ((totalSteps - i) * stepMinutes)
            let price = v * scale
            guard price.isFinite, price > 0 else { continue }
            seeded.append(MinuteEntry(minute: minute, price: price))
        }
        guard !seeded.isEmpty else { return }

        queue.async {
            let arr = self.history[sym] ?? []
            // Merge: keep the latest value per minute (seeded then existing can override)
            var map: [Int: Double] = [:]
            for e in arr { map[e.minute] = e.price }
            for e in seeded { map[e.minute] = e.price }
            var merged: [MinuteEntry] = map.keys.sorted().map { MinuteEntry(minute: $0, price: map[$0]!) }

            // Trim to retention window
            let minAllowed = currentMinute - self.maxMinutes
            if let firstIdx = merged.firstIndex(where: { $0.minute >= minAllowed }) {
                if firstIdx > 0 { merged.removeFirst(firstIdx) }
            }
            self.history[sym] = merged
        }
    }
    
    // Seed a single anchor point using a provider percent for a given lookback window.
    // This makes our computed change exactly match the provider immediately.
    // PERFORMANCE FIX v2: Uses async during scroll to avoid blocking main thread
    func seed(symbol: String, lookbackHours: Int, currentPrice: Double, percent: Double) {
        let sym = symbol.uppercased()
        guard lookbackHours > 0, currentPrice.isFinite, currentPrice > 0, percent.isFinite else { return }
        let now = Date()
        let currentMinute = minuteKey(for: now)
        let targetMinute = currentMinute - max(1, lookbackHours) * 60
        // prev = curr / (1 + pct)
        let prev = currentPrice / (1.0 + (percent / 100.0))
        guard prev.isFinite, prev > 0 else { return }

        // PERFORMANCE FIX: Always use async on main thread to avoid blocking.
        // Seeding data is not time-critical - eventual consistency is fine.
        // Only use sync on background threads where blocking is acceptable.
        let work = { [weak self] in
            guard let self = self else { return }
            var arr = self.history[sym] ?? []
            // Ensure current minute entry exists with currentPrice
            if let last = arr.last, last.minute == currentMinute {
                arr[arr.count - 1] = MinuteEntry(minute: currentMinute, price: currentPrice)
            } else {
                arr.append(MinuteEntry(minute: currentMinute, price: currentPrice))
            }
            // Upsert the target minute entry
            if let idx = arr.firstIndex(where: { $0.minute == targetMinute }) {
                arr[idx] = MinuteEntry(minute: targetMinute, price: prev)
            } else {
                arr.append(MinuteEntry(minute: targetMinute, price: prev))
                arr.sort { $0.minute < $1.minute }
            }
            // Trim to retention
            let minAllowed = currentMinute - self.maxMinutes
            if let firstIdx = arr.firstIndex(where: { $0.minute >= minAllowed }) {
                if firstIdx > 0 { arr.removeFirst(firstIdx) }
            }
            self.history[sym] = arr
        }
        
        if Thread.isMainThread {
            queue.async { work() }
        } else {
            queue.sync { work() }
        }
    }
    
    /// MEMORY FIX: Aggressively clear all history and cached changes.
    /// Called by the memory watchdog when memory pressure is critical.
    public func clearAll() {
        queue.async { [weak self] in
            self?.history.removeAll()
        }
        cacheQueue.async(flags: .barrier) { [weak self] in
            self?.cachedChanges.removeAll()
            self?.cachedCoverage.removeAll()
        }
    }
    
    /// Deterministic variant for critical memory pressure.
    /// Clears data synchronously so the watchdog can reclaim memory before jetsam.
    public func clearAllSynchronously() {
        queue.sync { [weak self] in
            self?.history.removeAll()
        }
        cacheQueue.sync(flags: .barrier) { [weak self] in
            self?.cachedChanges.removeAll()
            self?.cachedCoverage.removeAll()
        }
    }
}
