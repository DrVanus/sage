import Foundation

final class Diagnostics {
    static let shared = Diagnostics()

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
        print("[\(category.rawValue)] \(message)")
    }
}
