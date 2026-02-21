import Foundation

/// Centralized logging utility with runtime-controllable output.
/// Set `DebugLog.enabled = true` to enable verbose logging during debugging.
/// Default is `false` to keep console clean during normal development.
enum DebugLog {
    /// Master switch - set to false to silence ALL debug logging
    static var enabled: Bool = false
    
    /// Per-category overrides - set specific categories to true for targeted debugging
    private static var categoryOverrides: [String: Bool] = [
        "Sentiment": true  // Enable sentiment logging to diagnose issues
    ]
    
    // PERFORMANCE FIX: Rate-limit repetitive log messages to prevent console spam
    // Categories that should be throttled to once per 30 seconds per unique message key
    private static var throttledCategories: Set<String> = ["Sentiment"]
    private static var lastLogTimes: [String: Date] = [:]
    private static let throttleInterval: TimeInterval = 30.0
    private static let logQueue = DispatchQueue(label: "DebugLog.queue")
    
    /// Log a message (only if enabled and in DEBUG builds)
    static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        #if DEBUG
        print(message())
        #endif
    }
    
    /// Log a message with a category prefix
    static func log(_ category: String, _ message: @autoclosure () -> String) {
        // Check category-specific override first, then master switch
        let shouldLog = categoryOverrides[category] ?? enabled
        guard shouldLog else { return }
        
        #if DEBUG
        // PERFORMANCE FIX: Rate-limit certain categories to reduce console spam
        if throttledCategories.contains(category) {
            let msg = message() // Evaluate message once
            // Create a key based on category + message prefix (first 50 chars) for deduplication
            let keyPrefix = String(msg.prefix(50))
            let key = "\(category):\(keyPrefix)"
            
            var shouldPrint = false
            logQueue.sync {
                let now = Date()
                if let lastTime = lastLogTimes[key],
                   now.timeIntervalSince(lastTime) < throttleInterval {
                    shouldPrint = false
                } else {
                    lastLogTimes[key] = now
                    shouldPrint = true
                }
            }
            
            if shouldPrint {
                print("[\(category)] \(msg)")
            }
        } else {
            print("[\(category)] \(message())")
        }
        #endif
    }
    
    /// Enable or disable logging for a specific category
    static func setEnabled(_ enabled: Bool, for category: String) {
        categoryOverrides[category] = enabled
    }
    
    /// Log an error message (always shown in DEBUG, regardless of enabled flag)
    /// Use sparingly for critical errors only
    static func error(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("❌ \(message())")
        #endif
    }
}
