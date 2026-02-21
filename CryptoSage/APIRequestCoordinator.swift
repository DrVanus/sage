//
//  APIRequestCoordinator.swift
//  CryptoSage
//
//  Global coordinator for API requests to prevent thundering herd and cascading failures.
//  All network-heavy services should check with this coordinator before making requests.
//

import Foundation

/// Global coordinator that prevents API request storms during app startup and foreground events.
/// Services should call `canMakeRequest(for:)` before initiating network calls to avoid cascading failures.
final class APIRequestCoordinator {
    static let shared = APIRequestCoordinator()
    
    // MARK: - API Services
    enum APIService: String, CaseIterable {
        case coinGecko
        case binance
        case coinbase
        case pumpFun
        case news
        case sentiment
        case category
        case sync
        case exchangeComparison  // Multi-exchange price comparison
        case whaleTracking       // Whale activity tracking
    }
    
    // MARK: - State
    private let lock = NSLock()
    
    /// Last request time per service
    private var lastRequestAt: [APIService: Date] = [:]
    
    /// Request count in current window per service
    private var requestCountInWindow: [APIService: Int] = [:]
    
    /// Window start time per service
    private var windowStartAt: [APIService: Date] = [:]
    
    /// Global app startup timestamp
    private var appStartupAt: Date = Date()
    
    /// Last foreground event timestamp
    private var lastForegroundAt: Date = .distantPast
    
    // FIX: Global concurrent request tracking to prevent connection pool exhaustion
    // PERFORMANCE FIX: Increased from 20 to 25 to reduce blocking during burst periods
    // Note: Due to check-then-record pattern, actual count can temporarily exceed limit
    private var activeRequestCount: Int = 0
    private let maxGlobalConcurrentRequests: Int = 25  // Hard limit on total active requests
    
    // FIX: Track consecutive failures per service for adaptive backoff
    private var consecutiveFailures: [APIService: Int] = [:]
    private let maxConsecutiveFailuresBeforePause: Int = 3
    
    // PERFORMANCE FIX: Throttle "blocked" log messages to prevent console spam
    private var lastBlockLogTime: [APIService: Date] = [:]
    private var lastGlobalLimitLogTime: Date = .distantPast
    private let blockLogThrottleInterval: TimeInterval = 60.0  // PERFORMANCE v26: Increased from 30s to 60s - these are informational only
    
    /// Whether we're in startup grace period (first 8 seconds)
    /// Real-device startup should hydrate quickly; keep only a short anti-burst window.
    private var isInStartupGracePeriod: Bool {
        Date().timeIntervalSince(appStartupAt) < 8.0
    }
    
    /// Whether we recently came to foreground (within 10 seconds)
    /// PERFORMANCE FIX: Extended from 5s to 10s for smoother foreground transitions
    private var isInForegroundGracePeriod: Bool {
        Date().timeIntervalSince(lastForegroundAt) < 10.0
    }
    
    // MARK: - Configuration
    
    /// Minimum interval between requests per service (in seconds)
    /// PERFORMANCE FIX: Increased intervals to reduce network load and improve responsiveness
    private let minRequestIntervals: [APIService: TimeInterval] = [
        .coinGecko: 30.0,      // LIVE DATA FIX v5.1: Was too high and made prices appear frozen when Firestore/proxy were stale
        .binance: 10.0,        // Binance is more permissive - increased from 5
        .coinbase: 15.0,       // Coinbase moderate - increased from 10
        .pumpFun: 120.0,       // PumpFun has issues, be very conservative - increased from 60
        .news: 120.0,          // News doesn't need frequent updates - increased from 60
        .sentiment: 180.0,     // Sentiment is slow-changing - increased from 120
        .category: 600.0,      // Categories rarely change - increased from 300
        .sync: 600.0,          // Background sync is low priority - increased from 300
        .exchangeComparison: 30.0,  // Exchange comparison - moderate frequency
        .whaleTracking: 60.0        // Whale tracking - more frequent for home page
    ]
    
    /// Maximum requests per 60-second window per service
    /// PERFORMANCE FIX: Reduced limits to prevent request floods
    private let maxRequestsPerWindow: [APIService: Int] = [
        .coinGecko: 8,         // LIVE DATA FIX v5.1: Allow recovery requests when Firebase proxy/Firestore are unhealthy
        .binance: 15,          // Reduced from 30
        .coinbase: 10,         // Reduced from 20
        .pumpFun: 2,           // Reduced from 5
        .news: 3,              // Reduced from 5
        .sentiment: 2,         // Reduced from 3
        .category: 1,          // Reduced from 2
        .sync: 1,              // Reduced from 2
        .exchangeComparison: 3, // New - allow 3 per minute
        .whaleTracking: 4       // Increased - allow 4 per minute for home page
    ]
    
    /// Startup delay per service (stagger initial requests)
    /// STALE DATA FIX: Reduced delays for critical APIs to get fresh percentage data faster
    /// Users see wrong percentages if we delay too long - better to fetch immediately
    /// PERFORMANCE FIX v5.0.15: Further reduced news/sentiment delays to match faster phase loading
    private let startupDelays: [APIService: TimeInterval] = [
        .coinGecko: 0.5,       // PRIMARY DATA - fetch immediately for fresh percentages (was 2.0)
        .binance: 0.9,         // Overlay prices - near-immediate after CoinGecko
        .coinbase: 0.7,        // Faster reliability fallback
        .pumpFun: 20.0,        // Optional data - later
        .news: 1.5,            // Home-critical content
        .sentiment: 2.0,       // Home-critical content
        .category: 20.0,       // Background data (reduced from 25)
        .sync: 25.0,           // Low priority background (reduced from 30)
        .exchangeComparison: 4.0,   // So section can appear promptly
        .whaleTracking: 2.0         // Whale data important for home page
    ]

    private func startupDelay(for service: APIService) -> TimeInterval {
        let base = startupDelays[service] ?? 5.0
        #if targetEnvironment(simulator)
        // Simulator runs with safer pipelines now; reduce startup wait to improve first paint parity.
        return min(base, 0.6)
        #endif
        return base
    }
    
    private init() {
        resetCounters()
    }
    
    // MARK: - Public API
    
    /// Called when app launches
    func appDidLaunch() {
        lock.lock()
        appStartupAt = Date()
        resetCounters()
        lock.unlock()
        #if DEBUG
        print("🚀 [APIRequestCoordinator] App launched - enforcing staggered startup")
        #endif
    }
    
    /// Called when app comes to foreground
    func appDidBecomeForeground() {
        lock.lock()
        let wasInForegroundGrace = isInForegroundGracePeriod
        lastForegroundAt = Date()
        lock.unlock()
        
        if !wasInForegroundGrace {
            #if DEBUG
            print("🔄 [APIRequestCoordinator] App foregrounded - applying rate limits")
            #endif
        }
    }
    
    /// Check if a request can be made for the given service.
    /// Returns true if allowed, false if should be skipped/delayed.
    func canMakeRequest(for service: APIService) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        let now = Date()
        
        // FIX: Check global concurrent request limit first
        if activeRequestCount >= maxGlobalConcurrentRequests {
            #if DEBUG
            // PERFORMANCE FIX: Throttle logging to prevent console spam
            if now.timeIntervalSince(lastGlobalLimitLogTime) >= blockLogThrottleInterval {
                lastGlobalLimitLogTime = now
                print("🛑 [APIRequestCoordinator] \(service.rawValue) blocked (global limit: \(activeRequestCount)/\(maxGlobalConcurrentRequests))")
            }
            #endif
            return false
        }
        
        // FIX: Check if service is paused due to consecutive failures
        let failures = consecutiveFailures[service] ?? 0
        if failures >= maxConsecutiveFailuresBeforePause {
            // Allow retry after extended backoff (failures * minInterval)
            let minInterval = minRequestIntervals[service] ?? 10.0
            let backoffTime = Double(failures) * minInterval
            if let lastReq = lastRequestAt[service], now.timeIntervalSince(lastReq) < backoffTime {
                #if DEBUG
                // PERFORMANCE FIX: Throttle logging to prevent console spam
                if now.timeIntervalSince(lastBlockLogTime[service] ?? .distantPast) >= blockLogThrottleInterval {
                    lastBlockLogTime[service] = now
                    print("🛑 [APIRequestCoordinator] \(service.rawValue) paused (failures: \(failures), backoff: \(Int(backoffTime))s)")
                }
                #endif
                return false
            }
        }
        
        // Check startup delay
        if isInStartupGracePeriod {
            let delay = startupDelay(for: service)
            if now.timeIntervalSince(appStartupAt) < delay {
                #if DEBUG
                // PERFORMANCE FIX: Throttle startup blocked logs per service to prevent console spam
                // (e.g., Binance was logging 9+ times during the 1.5s startup delay)
                if now.timeIntervalSince(lastBlockLogTime[service] ?? .distantPast) >= blockLogThrottleInterval {
                    lastBlockLogTime[service] = now
                    print("⏳ [APIRequestCoordinator] \(service.rawValue) blocked during startup (wait \(Int(delay - now.timeIntervalSince(appStartupAt)))s)")
                }
                #endif
                return false
            }
        }
        
        // Check minimum interval
        if let lastReq = lastRequestAt[service] {
            let minInterval = minRequestIntervals[service] ?? 10.0
            // During foreground grace, apply stricter limits
            let effectiveInterval = isInForegroundGracePeriod ? minInterval * 2 : minInterval
            if now.timeIntervalSince(lastReq) < effectiveInterval {
                return false
            }
        }
        
        // Check window limit
        let windowStart = windowStartAt[service] ?? now
        if now.timeIntervalSince(windowStart) > 60.0 {
            // Reset window
            windowStartAt[service] = now
            requestCountInWindow[service] = 0
        }
        
        let count = requestCountInWindow[service] ?? 0
        let maxRequests = maxRequestsPerWindow[service] ?? 10
        if count >= maxRequests {
            #if DEBUG
            // PERFORMANCE FIX: Throttle logging to prevent console spam
            if now.timeIntervalSince(lastBlockLogTime[service] ?? .distantPast) >= blockLogThrottleInterval {
                lastBlockLogTime[service] = now
                print("🛑 [APIRequestCoordinator] \(service.rawValue) rate limited (\(count)/\(maxRequests) in window)")
            }
            #endif
            return false
        }
        
        return true
    }
    
    /// Record that a request was made for the given service
    func recordRequest(for service: APIService) {
        lock.lock()
        defer { lock.unlock() }
        
        let now = Date()
        lastRequestAt[service] = now
        
        // FIX: Increment active request count
        activeRequestCount += 1
        
        // Update window counter
        if windowStartAt[service] == nil {
            windowStartAt[service] = now
        }
        requestCountInWindow[service] = (requestCountInWindow[service] ?? 0) + 1
    }
    
    /// Record that a request completed successfully
    func recordSuccess(for service: APIService) {
        lock.lock()
        defer { lock.unlock() }
        
        // FIX: Decrement active request count
        activeRequestCount = max(0, activeRequestCount - 1)
        
        // FIX: Reset consecutive failures on success
        consecutiveFailures[service] = 0
    }
    
    /// Record a failure for the given service (applies additional backoff)
    func recordFailure(for service: APIService) {
        lock.lock()
        defer { lock.unlock() }
        
        // FIX: Decrement active request count
        activeRequestCount = max(0, activeRequestCount - 1)
        
        // FIX: Track consecutive failures for adaptive backoff
        // Cap at 8 to prevent infinite backoff spiral (e.g., Binance geo-blocked)
        let currentFailures = min((consecutiveFailures[service] ?? 0) + 1, 8)
        consecutiveFailures[service] = currentFailures
        
        // Push last request time forward to enforce additional backoff
        // FIX: Increase backoff with consecutive failures, capped at 5x base
        let now = Date()
        let baseBackoff = minRequestIntervals[service] ?? 10.0
        let backoffMultiplier = min(Double(currentFailures + 1), 5.0)  // Cap at 5x
        let backoffTime = baseBackoff * backoffMultiplier
        lastRequestAt[service] = now.addingTimeInterval(backoffTime)
        
        #if DEBUG
        // Throttle failure logging after 3 failures to reduce console noise
        if currentFailures <= 3 {
            print("⚠️ [APIRequestCoordinator] \(service.rawValue) failure #\(currentFailures) - backoff \(Int(backoffTime))s")
        }
        #endif
    }
    
    /// Reset failures for a service when an alternative data path succeeds
    /// (e.g., Firestore delivers Binance data when direct API is geo-blocked)
    func resetFailuresIfStale(for service: APIService) {
        lock.lock()
        defer { lock.unlock() }
        let failures = consecutiveFailures[service] ?? 0
        // Only reset if failures are high enough to cause extended pauses
        if failures > maxConsecutiveFailuresBeforePause {
            consecutiveFailures[service] = maxConsecutiveFailuresBeforePause
        }
    }
    
    /// Get recommended delay before the next request for a service
    func recommendedDelay(for service: APIService) -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        
        let now = Date()
        
        // During startup, return the startup delay
        if isInStartupGracePeriod {
            let delay = startupDelay(for: service)
            let remaining = delay - now.timeIntervalSince(appStartupAt)
            if remaining > 0 { return remaining }
        }
        
        // Check last request time
        if let lastReq = lastRequestAt[service] {
            let minInterval = minRequestIntervals[service] ?? 10.0
            let elapsed = now.timeIntervalSince(lastReq)
            if elapsed < minInterval {
                return minInterval - elapsed
            }
        }
        
        return 0
    }
    
    // MARK: - Private
    
    private func resetCounters() {
        for service in APIService.allCases {
            requestCountInWindow[service] = 0
            windowStartAt[service] = nil
        }
    }
}
