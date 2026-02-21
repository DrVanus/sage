import Foundation

// PRODUCTION FIX: Silence ALL print() statements in Release builds.
// In DEBUG, print() works normally. In Release (App Store), print() is a no-op.
// This prevents debug logs from leaking to device console and improves performance.
// Uses @_transparent for zero overhead in Release builds.
#if !DEBUG
@_transparent
func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    // No-op in Release builds
}
#endif

final class Diagnostics {
    static let shared = Diagnostics()
    
    /// Set to false to silence all diagnostic logging (useful to reduce console noise during debugging)
    var enabled: Bool = false

    enum Category: String {
        case marketVM = "MarketVM"
        case network = "Network"
        case general = "App"
    }

    private struct Bucket {
        var tokens: Double
        var lastRefill: Date
    }

    private let queue = DispatchQueue(label: "DiagnosticsLogger.queue")
    private var lastLogAt: [String: Date] = [:]
    private var buckets: [String: Bucket] = [:]

    // Defaults for token bucket
    private let defaultCapacity: Double = 5
    private let defaultRefillPerSec: Double = 1

    // Basic log (no throttling)
    func log(_ category: Category, _ message: String) {
        output(category, message)
    }

    // Time-based throttled log (per category+message prefix)
    func log(_ category: Category, _ message: String, minInterval: TimeInterval) {
        let key = keyFor(category: category, message: message)
        let now = Date()
        var shouldLog = false
        queue.sync {
            if let last = lastLogAt[key], now.timeIntervalSince(last) < minInterval {
                shouldLog = false
            } else {
                lastLogAt[key] = now
                shouldLog = true
            }
        }
        if shouldLog { output(category, message) }
    }

    // Token-bucket throttled log (per custom key)
    func logBucketed(_ category: Category, key: String, capacity: Double? = nil, refillPerSec: Double? = nil, _ message: String) {
        let now = Date()
        let cap = capacity ?? defaultCapacity
        let rate = refillPerSec ?? defaultRefillPerSec
        var shouldLog = false
        queue.sync {
            var bucket = buckets[key] ?? Bucket(tokens: cap, lastRefill: now)
            let elapsed = now.timeIntervalSince(bucket.lastRefill)
            let refill = elapsed * rate
            bucket.tokens = min(cap, bucket.tokens + refill)
            bucket.lastRefill = now
            if bucket.tokens >= 1.0 {
                bucket.tokens -= 1.0
                shouldLog = true
            }
            buckets[key] = bucket
        }
        if shouldLog { output(category, message) }
    }

    // MARK: - Helpers
    private func keyFor(category: Category, message: String) -> String {
        let prefix = String(message.prefix(40))
        return "\(category.rawValue)|\(prefix)"
    }

    private func output(_ category: Category, _ message: String) {
        #if DEBUG
        guard enabled else { return }
        print("[\(category.rawValue)] \(message)")
        #endif
    }
}
