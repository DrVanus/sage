import Foundation
import Network

// Thread-safe rate-limited logging actor to prevent console spam and data races
private actor _RateLimitedLogger {
    private var logTimes: [String: Date] = [:]
    private var lastFastPathRaceLogAt: Date? = nil
    private var earlyExitLastLogAt: Date? = nil
    private var earlyExitLastReportAt: Date? = nil
    
    func log(_ key: String, _ message: String, minInterval: TimeInterval = 60.0) {
        let now = Date()
        if let lastTime = logTimes[key], now.timeIntervalSince(lastTime) < minInterval {
            return
        }
        logTimes[key] = now
        #if DEBUG
        print(message)
        #endif
    }
    
    func shouldLogFastPathRace() -> Bool {
        let now = Date()
        if let last = lastFastPathRaceLogAt, now.timeIntervalSince(last) <= 60 {
            return false
        }
        lastFastPathRaceLogAt = now
        return true
    }
    
    func shouldLogEarlyExit() -> Bool {
        let now = Date()
        if let last = earlyExitLastLogAt, now.timeIntervalSince(last) <= 60 {
            return false
        }
        earlyExitLastLogAt = now
        return true
    }
    
    func shouldReportEarlyExit() -> Bool {
        let now = Date()
        if let last = earlyExitLastReportAt, now.timeIntervalSince(last) <= 30 {
            return false
        }
        earlyExitLastReportAt = now
        return true
    }
}
private let __rateLimitedLogger = _RateLimitedLogger()

private func _retryAfterTTL(_ http: HTTPURLResponse) -> TimeInterval? {
    // Try to parse Retry-After header as seconds or HTTP-date
    for (k, v) in http.allHeaderFields {
        if let ks = (k as? String)?.lowercased(), ks == "retry-after" {
            if let s = v as? String {
                if let secs = TimeInterval(s.trimmingCharacters(in: .whitespacesAndNewlines)) { return secs }
                let df = DateFormatter()
                df.locale = Locale(identifier: "en_US_POSIX")
                df.timeZone = TimeZone(secondsFromGMT: 0)
                df.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
                if let date = df.date(from: s) {
                    let delta = date.timeIntervalSinceNow
                    if delta.isFinite { return max(0, delta) }
                }
            } else if let n = v as? NSNumber {
                return n.doubleValue
            }
        }
    }
    return nil
}

// Tuned session for Binance requests — uses certificate pinning for MITM protection
private let _binanceSession: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.waitsForConnectivity = false
    config.timeoutIntervalForRequest = 8
    config.timeoutIntervalForResource = 15
    config.httpMaximumConnectionsPerHost = 4
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    config.tlsMinimumSupportedProtocolVersion = .TLSv12
    // SECURITY: Route through certificate pinning manager to prevent MITM attacks
    // on Binance API calls that may include signed trading requests.
    return CertificatePinningManager.shared.createPinnedSession(configuration: config)
}()

private struct _StatsCacheEntry { let data: [CoinPrice]; let timestamp: Date }
private actor _StatsCache {
    private var cache: [String: _StatsCacheEntry] = [:]
    private let ttl: TimeInterval = 60 // seconds
    func get(for key: String) -> [CoinPrice]? {
        if let entry = cache[key], Date().timeIntervalSince(entry.timestamp) < ttl { return entry.data }
        return nil
    }
    func get(for key: String, maxAge: TimeInterval) -> [CoinPrice]? {
        if let entry = cache[key], Date().timeIntervalSince(entry.timestamp) < maxAge { return entry.data }
        return nil
    }
    func set(_ data: [CoinPrice], for key: String) {
        cache[key] = _StatsCacheEntry(data: data, timestamp: Date())
    }
}
private let __statsCache = _StatsCache()

private actor _InflightStats {
    private var tasks: [String: Task<[CoinPrice], Error>] = [:]
    func run(key: String, operation: @escaping () async throws -> [CoinPrice]) async throws -> [CoinPrice] {
        if let existing = tasks[key] {
            return try await existing.value
        }
        let task = Task { try await operation() }
        tasks[key] = task
        defer { tasks[key] = nil }
        return try await task.value
    }
}
private let __inflightStats = _InflightStats()

private struct _SparklineCacheEntry { let data: [Double]; let timestamp: Date }
private actor _SparklineCache {
    private var cache: [String: _SparklineCacheEntry] = [:]
    private let ttl: TimeInterval = 60 // seconds
    func get(for key: String) -> [Double]? {
        if let entry = cache[key], Date().timeIntervalSince(entry.timestamp) < ttl { return entry.data }
        return nil
    }
    func get(for key: String, maxAge: TimeInterval) -> [Double]? {
        if let entry = cache[key], Date().timeIntervalSince(entry.timestamp) < maxAge { return entry.data }
        return nil
    }
    func set(_ data: [Double], for key: String) {
        cache[key] = _SparklineCacheEntry(data: data, timestamp: Date())
    }
}
private let __sparklineCache = _SparklineCache()
private actor _InflightSparkline {
    private var tasks: [String: Task<[Double], Never>] = [:]
    func run(key: String, operation: @escaping () async -> [Double]) async -> [Double] {
        if let existing = tasks[key] {
            return await existing.value
        }
        let task = Task { await operation() }
        tasks[key] = task
        defer { tasks[key] = nil }
        return await task.value
    }
}
private let __inflightSparkline = _InflightSparkline()

private actor _EndpointHealth {
    // BINANCE-US-FIX: Binance.US is shut down - "us" now points to global mirror
    enum RESTBase: String { case global = "api.binance.com", us = "api4.binance.com" }
    private var preferredBaseUntil: (base: RESTBase, until: Date)?
    private var blockedUntil: [RESTBase: Date] = [:]
    private let preferenceTTL: TimeInterval = 10 * 60 // 10 minutes
    // STALE DATA FIX: Reduced block duration to recover faster from temporary failures
    // Users need fresh percentage data quickly - 30 seconds is enough to avoid hammering
    private let blockTTL: TimeInterval = 30 // 30 seconds (was 3 minutes)
    private var consecutiveSuccess: [RESTBase: Int] = [:]
    private var consecutiveFailures: [RESTBase: Int] = [:]
    private let promoteThreshold: Int = 3
    private let demoteThreshold: Int = 2

    // Throttling for log spam
    private var lastPreferredLogAt: Date? = nil
    private var lastBlockedLogAt: [RESTBase: Date] = [:]
    private let logMinInterval: TimeInterval = 60 // seconds
    
    // GEO-BLOCKING: Track if user is in a region where Binance.com is blocked
    // This persists across app sessions to avoid repeated 451 failures
    private static let geoBlockedKey = "BinanceGlobalGeoBlocked"
    private var isGlobalGeoBlocked: Bool = UserDefaults.standard.bool(forKey: geoBlockedKey)
    private var lastGeoBlockLogAt: Date? = nil

    private func restBase(for host: String?) -> RESTBase? {
        guard let h = host?.lowercased() else { return nil }
        if h == RESTBase.us.rawValue || h.hasSuffix(".binance.us") { return .us }
        if h == RESTBase.global.rawValue || h.hasSuffix(".binance.com") { return .global }
        return nil
    }
    
    /// Called when HTTP 451 is received from a global Binance endpoint.
    /// Immediately prefers Binance US and persists this preference.
    func markGeoBlocked(host: String?) {
        guard let base = restBase(for: host), base == .global else { return }
        let now = Date()
        
        // Mark global as geo-blocked
        if !isGlobalGeoBlocked {
            isGlobalGeoBlocked = true
            // Persist synchronously to ensure it's saved before next launch
            UserDefaults.standard.set(true, forKey: Self.geoBlockedKey)
            #if DEBUG
            print("🌍 [EndpointHealth] Geo-blocking detected - preferring Binance US for future requests")
            #endif
        }
        
        // Immediately prefer Binance US
        preferredBaseUntil = (.us, now.addingTimeInterval(preferenceTTL * 6)) // 1 hour preference
        consecutiveSuccess[.us, default: 0] = promoteThreshold // Skip warmup
        
        // Block global endpoints for longer when geo-blocked
        blockedUntil[.global] = now.addingTimeInterval(300) // 5 minutes
        
        // Rate-limit logging
        let shouldLog = lastGeoBlockLogAt.map { now.timeIntervalSince($0) > 60 } ?? true
        if shouldLog {
            #if DEBUG
            print("🌍 [EndpointHealth] Global Binance geo-blocked (451) - using Binance US")
            #endif
            lastGeoBlockLogAt = now
        }
    }
    
    /// Returns true if the user is in a geo-blocked region
    func isInGeoBlockedRegion() -> Bool {
        return isGlobalGeoBlocked
    }

    func markPreferred(host: String?) {
        guard let base = restBase(for: host) else { return }
        let now = Date()
        // Update success/failure counters
        consecutiveSuccess[base, default: 0] += 1
        consecutiveFailures[base] = 0
        // If this base is already preferred and unexpired, just extend TTL and rate-limit logging
        if let pref = preferredBaseUntil, pref.base == base, pref.until > now {
            preferredBaseUntil = (base, now.addingTimeInterval(preferenceTTL))
            let shouldLog: Bool = {
                if let last = lastPreferredLogAt { return now.timeIntervalSince(last) > logMinInterval }
                return true
            }()
            if shouldLog {
                #if DEBUG
                print("ℹ️ [EndpointHealth] Preferred REST base: \(base.rawValue) for \(Int(preferenceTTL))s")
                #endif
                lastPreferredLogAt = now
            }
            return
        }
        // Only promote to preferred after enough consecutive successes to avoid flapping
        let successes = consecutiveSuccess[base] ?? 0
        guard successes >= promoteThreshold else { return }
        preferredBaseUntil = (base, now.addingTimeInterval(preferenceTTL))
        #if DEBUG
        print("ℹ️ [EndpointHealth] Preferred REST base: \(base.rawValue) for \(Int(preferenceTTL))s")
        #endif
        lastPreferredLogAt = now
        // Reset the other base's success count to reduce oscillation
        for other in [RESTBase.global, RESTBase.us] where other != base {
            consecutiveSuccess[other] = 0
        }
    }

    func markBlocked(host: String?, ttl: TimeInterval? = nil) {
        guard let base = restBase(for: host) else { return }
        let now = Date()
        // Update counters
        consecutiveFailures[base, default: 0] += 1
        consecutiveSuccess[base] = 0
        let failures = consecutiveFailures[base] ?? 0
        let multiplier = max(1, (failures / demoteThreshold) + 1)
        let duration = (ttl ?? blockTTL) * Double(min(3, multiplier))
        let newBlockEnd = now.addingTimeInterval(duration)
        // Never shorten an existing block (e.g. geo-block set a longer one)
        if let existingBlock = blockedUntil[base], existingBlock > newBlockEnd {
            // Keep the longer block
        } else {
            blockedUntil[base] = newBlockEnd
        }
        if let pref = preferredBaseUntil, pref.base == base { preferredBaseUntil = nil }
        let shouldLog: Bool = {
            if let last = lastBlockedLogAt[base] { return now.timeIntervalSince(last) > logMinInterval }
            return true
        }()
        if shouldLog {
            #if DEBUG
            print("⚠️ [EndpointHealth] Blocked REST base: \(base.rawValue) for \(Int(duration))s")
            #endif
            lastBlockedLogAt[base] = now
        }
    }

    // Track consecutive HTTP 400 errors and block after threshold
    private var http400Count: [RESTBase: Int] = [:]
    // STALE DATA FIX: Reduced block duration to recover faster - users need fresh percentage data
    private let http400BlockThreshold: Int = 5
    private let http400BlockTTL: TimeInterval = 30 // 30 seconds (was 2 minutes)

    func recordHttp400(host: String?) {
        guard let base = restBase(for: host) else { return }
        let now = Date()
        http400Count[base, default: 0] += 1
        consecutiveSuccess[base] = 0
        let count = http400Count[base] ?? 0
        if count >= http400BlockThreshold {
            // Block this endpoint for 2 minutes after repeated 400 errors
            blockedUntil[base] = now.addingTimeInterval(http400BlockTTL)
            if let pref = preferredBaseUntil, pref.base == base { preferredBaseUntil = nil }
            http400Count[base] = 0 // Reset counter after blocking
            let shouldLog: Bool = {
                if let last = lastBlockedLogAt[base] { return now.timeIntervalSince(last) > logMinInterval }
                return true
            }()
            if shouldLog {
                #if DEBUG
                print("⚠️ [EndpointHealth] Blocked REST base: \(base.rawValue) for \(Int(http400BlockTTL))s after \(http400BlockThreshold) HTTP 400 errors")
                #endif
                lastBlockedLogAt[base] = now
            }
        }
    }

    func clearHttp400Count(host: String?) {
        guard let base = restBase(for: host) else { return }
        http400Count[base] = 0
    }
    
    // MARK: - Binance US Unsupported Symbols Tracking
    
    /// Persistence key for unsupported symbols
    private static let unsupportedSymbolsKey = "BinanceUSUnsupportedSymbols"
    
    /// Symbols known to be unsupported on Binance US (causes HTTP 400)
    /// Persisted to UserDefaults to avoid re-learning on every app launch
    private var binanceUSUnsupportedSymbols: Set<String> = {
        if let saved = UserDefaults.standard.stringArray(forKey: unsupportedSymbolsKey) {
            return Set(saved)
        }
        return []
    }()
    
    /// Mark symbols as unsupported on Binance US (extracted from HTTP 400 error responses)
    /// Returns the count of newly marked symbols (0 if all were already marked)
    func markUnsupportedOnUS(symbols: [String]) -> Int {
        let uppercased = Set(symbols.map { $0.uppercased() })
        let newSymbols = uppercased.subtracting(binanceUSUnsupportedSymbols)
        if newSymbols.isEmpty { return 0 }
        binanceUSUnsupportedSymbols.formUnion(newSymbols)
        // Persist to UserDefaults to avoid re-learning on next launch
        UserDefaults.standard.set(Array(binanceUSUnsupportedSymbols), forKey: Self.unsupportedSymbolsKey)
        return newSymbols.count
    }
    
    /// Filter symbols to only those supported on the given base
    /// For Binance US, removes known unsupported symbols
    func filterSupportedSymbols(_ symbols: [String], for host: String?) -> [String] {
        guard let base = restBase(for: host), base == .us else { return symbols }
        return symbols.filter { !binanceUSUnsupportedSymbols.contains($0.uppercased()) }
    }
    
    /// Check if a host is Binance US
    func isBinanceUS(host: String?) -> Bool {
        guard let base = restBase(for: host) else { return false }
        return base == .us
    }

    private func isBlocked(_ base: RESTBase, now: Date = Date()) -> Bool {
        if let until = blockedUntil[base], until > now { return true }
        // PERFORMANCE FIX: If user is geo-blocked, treat ALL direct Binance endpoints as blocked.
        // Both .global (api.binance.com) and .us (api4.binance.com) are the same geo-blocked
        // infrastructure — Binance US is shut down. Without this, the .us endpoint expires its
        // blockedUntil after 300s and gets retried, only to 451 again on every foreground event.
        // The Firebase proxy (getBinance24hrTickers) handles Binance data for geo-blocked users.
        if isGlobalGeoBlocked { return true }
        return false
    }

    /// Returns true if all provided URLs are currently blocked, enabling early-exit to avoid unnecessary requests.
    func areAllBlocked(urls: [URL]) -> Bool {
        let now = Date()
        for url in urls {
            guard let base = restBase(for: url.host) else { continue }
            if !isBlocked(base, now: now) { return false }
        }
        return true
    }

    func orderByPreference(urls: [URL]) -> [URL] {
        let now = Date()
        
        // GEO-BLOCKING: If user is in a geo-blocked region, prefer Binance US
        let effectivePreferred: RESTBase? = {
            // Check for active preference first
            if let pref = preferredBaseUntil, pref.until > now { return pref.base }
            // If no active preference but geo-blocked, prefer US
            if isGlobalGeoBlocked { return .us }
            return nil
        }()
        
        var indexed = Array(urls.enumerated())
        if effectivePreferred == nil {
            indexed.shuffle()
        }
        // Determine if we have any non-blocked candidates
        let hasNonBlocked: Bool = indexed.contains { pair in
            let base = restBase(for: pair.element.host)
            return !(base.map { isBlocked($0, now: now) } ?? false)
        }
        // Sort with non-blocked first, honoring preferred base when set
        indexed.sort { lhs, rhs in
            let lBase = restBase(for: lhs.element.host)
            let rBase = restBase(for: rhs.element.host)
            let lBlocked = lBase.map { isBlocked($0, now: now) } ?? false
            let rBlocked = rBase.map { isBlocked($0, now: now) } ?? false
            if lBlocked != rBlocked { return !lBlocked && rBlocked } // non-blocked first
            if let p = effectivePreferred {
                let lPref = (lBase == p)
                let rPref = (rBase == p)
                if lPref != rPref { return lPref && !rPref }
            }
            // preserve prior order (shuffled or original)
            return lhs.offset < rhs.offset
        }
        // If we have at least one non-blocked candidate, filter blocked ones out entirely.
        let working = hasNonBlocked ? indexed.filter { pair in
            let base = restBase(for: pair.element.host)
            return !(base.map { isBlocked($0, now: now) } ?? false)
        } : indexed
        return working.map { $0.element }
    }
}
private let __endpointHealth = _EndpointHealth()

private actor _RateLimiter {
    private struct Bucket { var tokens: Double; var lastRefill: Date }
    private var buckets: [String: Bucket] = [:]
    private let maxTokens: Double = 10
    private let refillPerSec: Double = 2
    func acquire(for host: String?) async {
        guard let host = host else { return }
        var bucket = buckets[host] ?? Bucket(tokens: maxTokens, lastRefill: Date())
        func refill(_ b: inout Bucket) {
            let now = Date()
            let delta = now.timeIntervalSince(b.lastRefill)
            if delta > 0 {
                b.tokens = min(maxTokens, b.tokens + delta * refillPerSec)
                b.lastRefill = now
            }
        }
        refill(&bucket)
        while bucket.tokens < 1 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            refill(&bucket)
        }
        bucket.tokens -= 1
        buckets[host] = bucket
    }
}
private let __rateLimiter = _RateLimiter()

private final class _Reachability {
    static let shared = _Reachability()
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "ReachabilityMonitor")
    private var _reachable: Bool = true
    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.queue.async {
                self?._reachable = (path.status == .satisfied)
            }
        }
        monitor.start(queue: queue)
    }
    func isReachable() -> Bool {
        var val = true
        queue.sync { val = _reachable }
        return val
    }
}
private func _waitForReachability(maxWait: TimeInterval = 2.0) async {
    if _Reachability.shared.isReachable() { return }
    let deadline = Date().addingTimeInterval(maxWait)
    while Date() < deadline {
        if _Reachability.shared.isReachable() { return }
        try? await Task.sleep(nanoseconds: 200_000_000)
    }
}

actor BinanceService {
    // MARK: - Endpoints
    private static let globalREST = URL(string: "https://api.binance.com")!
    // BINANCE-US-FIX: Binance.US is shut down - use global mirror as fallback
    private static let usREST = URL(string: "https://api4.binance.com")!
    private static let coinbaseREST = URL(string: "https://api.exchange.coinbase.com")!

    private static let globalRESTCandidates: [URL] = [
        URL(string: "https://api.binance.com")!,
        URL(string: "https://api1.binance.com")!,
        URL(string: "https://api2.binance.com")!,
        URL(string: "https://api3.binance.com")!
    ]

    // MARK: - Helpers
    
    /// All known Binance quote currencies, ordered by priority (longest first for suffix matching)
    private static let knownQuoteCurrencies = ["FDUSD", "USDT", "BUSD", "USDC", "TUSD", "USD"]
    
    /// Validates that a symbol is a valid Binance base symbol
    /// Returns nil if the symbol contains invalid characters or is malformed
    private static func isValidBaseSymbol(_ symbol: String) -> Bool {
        // Must be alphanumeric (Binance symbols don't have underscores, dashes, etc.)
        guard !symbol.isEmpty else { return false }
        let alphanumeric = CharacterSet.alphanumerics
        return symbol.unicodeScalars.allSatisfy { alphanumeric.contains($0) }
    }
    
    /// Extracts the base symbol from a trading pair, returning nil if invalid
    /// Examples: "BTCUSDT" -> "BTC", "ETHFDUSD" -> "ETH", "BTC" -> "BTC"
    private static func extractBaseSymbol(from symbol: String) -> String? {
        let up = symbol.uppercased()
        
        // Check if it ends with a known quote currency
        for quote in knownQuoteCurrencies {
            if up.hasSuffix(quote) {
                let base = String(up.dropLast(quote.count))
                // Validate the base is not empty and doesn't contain another quote currency
                if !base.isEmpty && isValidBaseSymbol(base) {
                    // Ensure the base itself isn't a quote currency (e.g., "USDTUSD")
                    let baseIsQuote = knownQuoteCurrencies.contains(base)
                    if !baseIsQuote {
                        return base
                    }
                }
            }
        }
        
        // No known quote currency suffix - the input might be a base symbol already
        if isValidBaseSymbol(up) {
            return up
        }
        
        return nil
    }
    
    /// Normalizes a symbol so callers can pass either "BTC" or "BTCUSDT".
    /// PERFORMANCE FIX: Now handles all quote currencies (FDUSD, BUSD, USDC, USD, USDT)
    /// and validates symbol format to prevent malformed API requests.
    private static func normalizedPair(from symbol: String) -> String? {
        let up = symbol.uppercased()
        
        // Skip symbols with invalid characters (underscores, special chars)
        guard isValidBaseSymbol(up) else {
            return nil
        }
        
        // Extract base symbol (handles already-paired symbols like "BTCUSDT")
        guard let base = extractBaseSymbol(from: up) else {
            return nil
        }
        
        // Return the normalized pair with USDT
        return base + "USDT"
    }

    /// Try a list of URLs in order, returning the first 200 OK response.
    private static func dataFrom(urls: [URL], overallTimeout: TimeInterval = 12) async throws -> (Data, HTTPURLResponse) {
        var lastError: Error?
        var lastResponse: HTTPURLResponse?

        // Early-exit: if all endpoints are currently blocked, skip network attempts entirely
        if await __endpointHealth.areAllBlocked(urls: urls) {
            // Throttle both logging and APIHealthManager reporting to reduce overhead (thread-safe via actor)
            #if DEBUG
            if await __rateLimitedLogger.shouldLogEarlyExit() {
                print("⏭️ [BinanceService] All endpoints blocked; skipping request (early-exit)")
            }
            #endif
            
            // Only report to API health manager periodically to reduce main thread work
            if await __rateLimitedLogger.shouldReportEarlyExit() {
                Task { @MainActor in
                    APIHealthManager.shared.reportBlocked(.binance, until: Date().addingTimeInterval(300), reason: "All endpoints blocked")
                }
            }
            throw URLError(.cannotConnectToHost, userInfo: [NSLocalizedDescriptionKey: "All Binance endpoints are currently blocked"])
        }

        let urls = await __endpointHealth.orderByPreference(urls: urls)
        let orderedCandidates = urls

        let deadline = Date().addingTimeInterval(overallTimeout)
        func sleepCapped(_ seconds: Double) async {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0.1 { return }
            let d = min(seconds, max(0, remaining - 0.05))
            if d > 0 {
                try? await Task.sleep(nanoseconds: UInt64(d * 1_000_000_000))
            }
        }

        // Fast path: race the first few candidates in parallel with a shorter timeout.
        if orderedCandidates.count >= 2 {
            let firstFew = Array(orderedCandidates.prefix(2))
            do {
                let result = try await withThrowingTaskGroup(of: (Data, HTTPURLResponse).self) { group in
                    for u in firstFew {
                        group.addTask {
                            try? Task.checkCancellation()
                            await _waitForReachability()
                            await __rateLimiter.acquire(for: u.host)
                            var request = URLRequest(url: u)
                            request.httpMethod = "GET"
                            request.timeoutInterval = 5
                            request.setValue("CryptoSage/1.0", forHTTPHeaderField: "User-Agent")
                            request.setValue("application/json", forHTTPHeaderField: "Accept")
                            let (data, response) = try await _binanceSession.data(for: request)
                            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                            if http.statusCode == 451 {
                                // GEO-BLOCKING: markGeoBlocked already blocks for 300s + prefers US for 1h
                                await __endpointHealth.markGeoBlocked(host: http.url?.host)
                                #if DEBUG
                                RateLimitDiagnostics.record(host: http.url?.host, code: 451, ttl: 300)
                                #endif
                                // PERFORMANCE FIX: Throw immediately so this task exits the race group
                                // instead of returning a 451 response that just gets discarded.
                                throw URLError(.userAuthenticationRequired)
                            } else if http.statusCode == 429 {
                                let ttl = min(max(_retryAfterTTL(http) ?? 120, 30), 600)
                                await __endpointHealth.markBlocked(host: http.url?.host, ttl: ttl)
                                #if DEBUG
                                RateLimitDiagnostics.record(host: http.url?.host, code: 429, ttl: ttl)
                                #endif
                            } else if (500...599).contains(http.statusCode) {
                                await __endpointHealth.markBlocked(host: http.url?.host, ttl: 60)
                                #if DEBUG
                                RateLimitDiagnostics.record(host: http.url?.host, code: http.statusCode, ttl: 60)
                                #endif
                            }
                            return (data, http)
                        }
                    }
                    // Return the first successful 200 response
                    while let next = try? await group.next() {
                        let (data, http) = next
                        if http.statusCode == 200 {
                            group.cancelAll()
                            return (data, http)
                        }
                    }
                    throw URLError(.badServerResponse)
                }
                // Mark the successful host as preferred for a while
                await __endpointHealth.markPreferred(host: result.1.url?.host)
                await __endpointHealth.clearHttp400Count(host: result.1.url?.host)
                try? await Task.sleep(nanoseconds: 30_000_000) // 30ms jitter to smooth bursts
                return result
            } catch {
                #if DEBUG
                if await __rateLimitedLogger.shouldLogFastPathRace() {
                    print("⚠️ [BinanceService] Fast-path race failed, falling back to sequential attempts…")
                }
                #endif
                // If the fast race failed, fall back to the robust sequential logic below.
            }
        }

        func shouldRetry(for http: HTTPURLResponse) -> Bool {
            if http.statusCode == 429 { return true }
            if http.statusCode == 418 || http.statusCode == 409 { return true }
            return (500...599).contains(http.statusCode)
        }

        func isTransient(_ error: URLError) -> Bool {
            let transient: Set<URLError.Code> = [
                .timedOut,
                .networkConnectionLost,
                .cannotFindHost,
                .cannotConnectToHost,
                .dnsLookupFailed,
                .notConnectedToInternet,
                .cannotLoadFromNetwork,
                .resourceUnavailable,
                .secureConnectionFailed,
                .serverCertificateHasBadDate,
                .serverCertificateUntrusted,
                .serverCertificateHasUnknownRoot,
                .serverCertificateNotYetValid,
                .clientCertificateRejected,
                .clientCertificateRequired,
                .appTransportSecurityRequiresSecureConnection,
                .callIsActive,
                .dataNotAllowed,
                .internationalRoamingOff,
                .requestBodyStreamExhausted,
                .zeroByteResource,
                .backgroundSessionWasDisconnected
            ]
            // Treat POSIX connection refused as transient so we retry/backoff
            if error.errorCode == 61 { return true }
            return transient.contains(error.code)
        }

        var isFirst = true
        for url in orderedCandidates {
            try? Task.checkCancellation()
            if Date() >= deadline { throw URLError(.timedOut) }
            if !isFirst {
                await sleepCapped(Double.random(in: 0.15...0.30))
            }
            isFirst = false
            
            var connRefusedCount = 0
            
            var attempt = 0
            while attempt < 3 { // up to 3 tries per candidate
                try? Task.checkCancellation()
                if Date() >= deadline { throw URLError(.timedOut) }
                do {
                    await _waitForReachability()
                    await __rateLimiter.acquire(for: url.host)
                    var request = URLRequest(url: url)
                    request.httpMethod = "GET"
                    request.timeoutInterval = 8
                    request.setValue("CryptoSage/1.0", forHTTPHeaderField: "User-Agent")
                    request.setValue("application/json", forHTTPHeaderField: "Accept")
                    let (data, response) = try await _binanceSession.data(for: request)
                    guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                    lastResponse = http
                    if http.statusCode == 200 {
                        await __endpointHealth.markPreferred(host: http.url?.host)
                        await __endpointHealth.clearHttp400Count(host: http.url?.host)
                        // Report healthy status to global API health manager
                        Task { @MainActor in
                            APIHealthManager.shared.reportHealthy(.binance)
                        }
                        return (data, http)
                    }
                    if http.statusCode == 451 { // Geo-blocked — markGeoBlocked handles block + US preference
                        await __endpointHealth.markGeoBlocked(host: http.url?.host)
                        #if DEBUG
                        // Rate-limit 451 logs per host to prevent console spam
                        let host = http.url?.host ?? "unknown"
                        await __rateLimitedLogger.log("http451.\(host)", "⚠️ [BinanceService] HTTP 451 from \(host) — geo-blocked for 300s", minInterval: 60.0)
                        RateLimitDiagnostics.record(host: http.url?.host, code: 451, ttl: 300)
                        #endif
                        // PERFORMANCE FIX: After geo-block, skip ALL remaining global candidates.
                        // Previously only broke from the inner retry loop, then tried api1/api2/api3
                        // which are all the same geo-blocked infrastructure — wasting 3+ round-trips.
                        if await __endpointHealth.areAllBlocked(urls: orderedCandidates) {
                            throw URLError(.userAuthenticationRequired) // All endpoints blocked
                        }
                        break // Just break inner retry loop; outer loop will skip blocked URLs
                    }
                    if http.statusCode == 400 { // Bad Request - often indicates endpoint issues
                        await __endpointHealth.recordHttp400(host: http.url?.host)
                        // Try to parse error response to identify unsupported symbols for Binance US
                        if await __endpointHealth.isBinanceUS(host: http.url?.host) {
                            // Binance error format: {"code":-1121,"msg":"Invalid symbol."}
                            // or sometimes includes symbol list in the message
                            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let msg = json["msg"] as? String {
                                // Extract symbols from URL query to mark as unsupported
                                if msg.lowercased().contains("invalid symbol") || msg.lowercased().contains("bad symbol") {
                                    if let urlComps = URLComponents(url: url, resolvingAgainstBaseURL: false),
                                       let symbolsParam = urlComps.queryItems?.first(where: { $0.name == "symbols" })?.value,
                                       let symbolsData = symbolsParam.data(using: .utf8),
                                       let symbols = try? JSONDecoder().decode([String].self, from: symbolsData) {
                                        // Mark symbols as unsupported (returns count of newly marked symbols)
                                        let newCount = await __endpointHealth.markUnsupportedOnUS(symbols: symbols)
                                        #if DEBUG
                                        if newCount > 0 {
                                            await __rateLimitedLogger.log("http400.usfilter", "ℹ️ [BinanceService] HTTP 400 from Binance US - marked \(newCount) new symbols for filtering", minInterval: 30.0)
                                        }
                                        #endif
                                    }
                                }
                            }
                        }
                        // Non-retryable HTTP; try next candidate URL
                        break
                    }
                    if shouldRetry(for: http) {
                        if http.statusCode == 429 {
                            let ttl = min(max(_retryAfterTTL(http) ?? 120, 30), 600)
                            await __endpointHealth.markBlocked(host: http.url?.host, ttl: ttl)
                            #if DEBUG
                            RateLimitDiagnostics.record(host: http.url?.host, code: 429, ttl: ttl)
                            #endif
                        } else if (500...599).contains(http.statusCode) && attempt >= 1 {
                            await __endpointHealth.markBlocked(host: http.url?.host, ttl: 60)
                            #if DEBUG
                            RateLimitDiagnostics.record(host: http.url?.host, code: http.statusCode, ttl: 60)
                            #endif
                        }
                        // exponential backoff with jitter, capped per-attempt
                        let base: Double = min(2.5, pow(2.0, Double(attempt)) * 0.5)
                        let delay = base + Double.random(in: 0...(base * 0.3)) + Double.random(in: 0.05...0.15)
                        await sleepCapped(delay)
                        attempt += 1
                        continue
                    } else {
                        // Non-retryable HTTP; try next candidate URL
                        break
                    }
                } catch {
                    lastError = error
                    if let urlErr = error as? URLError, isTransient(urlErr) {
                        if urlErr.errorCode == 61 { // Connection refused
                            connRefusedCount += 1
                            if connRefusedCount >= 2 {
                                await __endpointHealth.markBlocked(host: url.host, ttl: 600) // 10 minutes
                                #if DEBUG
                                RateLimitDiagnostics.record(host: url.host, code: 61, ttl: 600)
                                #endif
                            }
                        }
                        let base: Double = min(2.5, pow(2.0, Double(attempt)) * 0.5)
                        let delay = base + Double.random(in: 0...(base * 0.3)) + Double.random(in: 0.05...0.15)
                        await sleepCapped(delay)
                        attempt += 1
                        continue
                    }
                    // Non-transient error; try next candidate URL
                    break
                }
            }
        }
        #if DEBUG
        // Rate-limit this error log to prevent console spam during rate limiting
        await __rateLimitedLogger.log("binance.allfailed", "❌ [BinanceService] All candidates failed for request. Last HTTP=\(lastResponse?.statusCode.description ?? "nil") lastError=\(String(describing: lastError))", minInterval: 30.0)
        #endif
        // Report degraded status to global API health manager
        Task { @MainActor in
            APIHealthManager.shared.reportDegraded(.binance, reason: "Request failures")
        }
        if let http = lastResponse {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "HTTP status \(http.statusCode)"])
        }
        if let err = lastError { throw err }
        throw URLError(.badServerResponse)
    }

    /// Fetch sparkline data (e.g. daily closes for the last 7 days) for a base symbol like "BTC" or a full pair like "BTCUSDT".
    static func fetchSparkline(symbol: String) async -> [Double] {
        // PERFORMANCE FIX: Check coordinator to prevent startup storm
        guard APIRequestCoordinator.shared.canMakeRequest(for: .binance) else {
            // Fall back to Coinbase if Binance is rate-limited
            return await coinbaseSparkline(symbol: symbol)
        }
        APIRequestCoordinator.shared.recordRequest(for: .binance)
        
        // FIX: Handle invalid symbols gracefully
        guard let pair = normalizedPair(from: symbol) else {
            // Invalid symbol format - fall back to Coinbase
            APIRequestCoordinator.shared.recordSuccess(for: .binance)
            return await coinbaseSparkline(symbol: symbol)
        }
        if let cached = await __sparklineCache.get(for: pair) { return cached }
        return await __inflightSparkline.run(key: pair) {
            if let cached2 = await __sparklineCache.get(for: pair) { return cached2 }
            func klinesURL(base: URL) -> URL? {
                var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)
                comps?.path = "/api/v3/klines"
                comps?.queryItems = [
                    URLQueryItem(name: "symbol", value: pair),
                    URLQueryItem(name: "interval", value: "1d"),
                    URLQueryItem(name: "limit", value: "7")
                ]
                return comps?.url
            }
            let bases: [URL] = [usREST] + globalRESTCandidates
            let urls = await __endpointHealth.orderByPreference(urls: bases.compactMap { klinesURL(base: $0) })
            do {
                try? Task.checkCancellation()
                await _waitForReachability()
                let (data, response) = try await dataFrom(urls: urls)
                guard response.statusCode == 200 else {
                    if let stale = await __sparklineCache.get(for: pair, maxAge: 300) { return stale }
                    let cb = await coinbaseSparkline(symbol: symbol)
                    if !cb.isEmpty { await __sparklineCache.set(cb, for: pair) }
                    return cb
                }
                var binanceCloses: [Double] = []
                if let json = try JSONSerialization.jsonObject(with: data) as? [[Any]] {
                    // Binance klines: [open time, open, high, low, close, volume, close time, ...]
                    // Order is oldest-first; extract the close at index 4.
                    binanceCloses = json.compactMap { arr in
                        if arr.count > 4 {
                            if let s = arr[4] as? String, let v = Double(s) { return v }
                            if let v = arr[4] as? Double { return v }
                        }
                        return nil
                    }
                }
                if !binanceCloses.isEmpty && binanceCloses.allSatisfy({ $0 > 0 }) {
                    await __sparklineCache.set(binanceCloses, for: pair)
                    return binanceCloses
                } else {
                    if let stale = await __sparklineCache.get(for: pair, maxAge: 300) { return stale }
                    let cb = await coinbaseSparkline(symbol: symbol)
                    if !cb.isEmpty { await __sparklineCache.set(cb, for: pair) }
                    return cb
                }
            } catch {
                if let stale = await __sparklineCache.get(for: pair, maxAge: 300) { return stale }
                let cb = await coinbaseSparkline(symbol: symbol)
                if !cb.isEmpty { await __sparklineCache.set(cb, for: pair) }
                return cb
            }
        }
    }

    /// Fetch 24-hour ticker stats for multiple symbols from Binance (with US fallback).
    static func fetch24hrStats(symbols: [String]) async throws -> [CoinPrice] {
        if symbols.isEmpty { return [] }
        
        // PERFORMANCE FIX: Check coordinator to prevent startup storm and cascading failures
        guard APIRequestCoordinator.shared.canMakeRequest(for: .binance) else {
            #if DEBUG
            await __rateLimitedLogger.log("fetch24hrStats.blocked", "⏳ [BinanceService] fetch24hrStats blocked by coordinator", minInterval: 30)
            #endif
            throw URLError(.cancelled) // Let caller handle fallback
        }
        APIRequestCoordinator.shared.recordRequest(for: .binance)
        
        // Normalize symbols and build a stable cache key
        let normalizedSymbols = Array(Set(symbols.map { $0.uppercased() })).sorted()
        let key = normalizedSymbols.joined(separator: ",")
        if let cached = await __statsCache.get(for: key) { return cached }

        // Helper to map Binance Ticker24hr[] into [CoinPrice]
        func mapTickerToCoinPrices(_ tickerStats: [Ticker24hr]) -> [CoinPrice] {
            if tickerStats.isEmpty { return [] }
            return tickerStats.compactMap { stat in
                let raw = stat.symbol
                let symbol = raw.replacingOccurrences(of: "USDT", with: "").lowercased()
                guard let last = Double(stat.lastPrice), last > 0 else { return nil }
                let change = Double(stat.priceChange) ?? 0
                let openFromField = Double(stat.openPrice) ?? 0
                // Choose an open price: prefer Binance's field when sane; else derive from last and change
                var open = openFromField > 0 ? openFromField : (last - change)
                if !(open.isFinite && open > 0) { open = last }
                // Derived percent from chosen open
                let derived = open > 0 ? ((last - open) / open * 100) : 0
                // Prefer Binance percent only if it closely matches derived
                let pctField = Double(stat.priceChangePercent) ?? .nan
                var percent = derived
                if pctField.isFinite, abs(pctField - derived) <= 5 { percent = pctField }
                // Clamp by asset class
                let symLower = symbol
                let stable: Set<String> = ["usdt","usdc","dai","tusd","usdd","usde","fdusd","usdp","gusd","susd"]
                let megaCaps: Set<String> = ["btc","eth","bnb","xrp","sol","ada","doge","ton","trx","dot","link","ltc","bch"]
                if stable.contains(symLower) {
                    if abs(percent) > 1.0 { percent = 0 }
                } else if megaCaps.contains(symLower) {
                    if percent > 30 { percent = 30 }
                    if percent < -30 { percent = -30 }
                } else {
                    if percent > 300 { percent = 300 }
                    if percent < -300 { percent = -300 }
                }
                if abs(percent) > 2000 { percent = 0 }
                let qv = Double(stat.quoteVolume ?? "") ?? 0
                let usdVol: Double
                if qv <= 0 {
                    let baseVol = Double(stat.volume ?? "") ?? 0
                    usdVol = baseVol * last
                } else {
                    usdVol = qv
                }
                let safeUsdVol = usdVol.isFinite && usdVol > 0 ? min(usdVol, last * 1_000_000_000) : 0
                return CoinPrice(
                    symbol: symbol,
                    lastPrice: last,
                    openPrice: open,
                    highPrice: max(last, open),
                    lowPrice: min(last, open),
                    volume: (safeUsdVol > 0 ? safeUsdVol : nil),
                    change24h: percent
                )
            }
        }

        // Build URL candidates for a batch of symbols
        // Filters symbols for Binance US to avoid HTTP 400 errors from unsupported pairs
        func makeCandidates(for pairs: [String]) async -> [URL] {
            func makeURL(base: URL, symbolList: [String]) -> URL? {
                guard !symbolList.isEmpty else { return nil }
                var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
                components?.path = "/api/v3/ticker/24hr"
                if let jsonData = try? JSONEncoder().encode(symbolList),
                   let symbolsParam = String(data: jsonData, encoding: .utf8) {
                    components?.queryItems = [URLQueryItem(name: "symbols", value: symbolsParam)]
                } else {
                    return nil
                }
                return components?.url
            }
            
            // Filter pairs for Binance US (remove known unsupported symbols)
            let filteredForUS = await __endpointHealth.filterSupportedSymbols(pairs, for: usREST.host)
            
            var urls: [URL] = []
            // Add Binance US URL with filtered symbols (if any remain after filtering)
            if let usURL = makeURL(base: usREST, symbolList: filteredForUS) {
                urls.append(usURL)
            }
            // Add global endpoints with full symbol list
            for base in globalRESTCandidates {
                if let url = makeURL(base: base, symbolList: pairs) {
                    urls.append(url)
                }
            }
            
            return await __endpointHealth.orderByPreference(urls: urls)
        }

        // Attempt a single batch request to Binance for the provided symbol list
        func attemptBatch(_ syms: [String]) async throws -> [CoinPrice] {
            // FIX: Use compactMap to filter out invalid symbols
            let pairs = syms.compactMap { normalizedPair(from: $0) }
            guard !pairs.isEmpty else {
                throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "No valid symbols after normalization"])
            }
            let candidates = await makeCandidates(for: pairs)
            let (data, _) = try await dataFrom(urls: candidates)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let tickerStats = try decoder.decode([Ticker24hr].self, from: data)
            let mapped = mapTickerToCoinPrices(tickerStats)
            guard !mapped.isEmpty else {
                throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Empty ticker payload"])
            }
            return mapped
        }

        // Chunk helper
        func chunks<T>(_ array: [T], size: Int) -> [[T]] {
            guard size > 0 else { return [array] }
            var out: [[T]] = []
            out.reserveCapacity((array.count + size - 1) / size)
            var idx = 0
            while idx < array.count {
                let end = min(idx + size, array.count)
                out.append(Array(array[idx..<end]))
                idx = end
            }
            return out
        }

        // If the symbol list is modest, try one batch first; otherwise go straight to chunking to be kind to the API.
        let maxBatch = 60
        var combined: [CoinPrice] = []
        var lastError: Error? = nil

        if normalizedSymbols.count <= maxBatch {
            do {
                let batch = try await attemptBatch(normalizedSymbols)
                combined = batch
            } catch {
                lastError = error
                // Fall back to chunked fetching on failure
                // (helps when a single large payload or endpoint flakiness causes errors)
            }
        }

        if combined.isEmpty {
            let chunkedSyms = chunks(normalizedSymbols, size: maxBatch)
            for (i, chunk) in chunkedSyms.enumerated() {
                do {
                    let part = try await attemptBatch(chunk)
                    combined.append(contentsOf: part)
                } catch {
                    lastError = error
                    #if DEBUG
                    RateLimitDiagnostics.record(host: "api.binance.com", code: 429, ttl: 60)
                    #endif
                    // FIX: Check coordinator before Coinbase fallback to prevent flooding
                    // Only attempt Coinbase fallback if coordinator allows
                    if APIRequestCoordinator.shared.canMakeRequest(for: .coinbase) {
                        APIRequestCoordinator.shared.recordRequest(for: .coinbase)
                        // As a last resort for this chunk, use Coinbase per-symbol fallback to salvage partial coverage
                        // FIX: Limit concurrent Coinbase requests to prevent flooding
                        let limitedChunk = Array(chunk.prefix(5))  // Max 5 at a time
                        let coinbaseResults: [CoinPrice] = await withTaskGroup(of: CoinPrice?.self) { group in
                            for s in limitedChunk { group.addTask { await coinbase24h(symbol: s) } }
                            var tmp: [CoinPrice] = []
                            for await res in group { if let r = res { tmp.append(r) } }
                            return tmp
                        }
                        combined.append(contentsOf: coinbaseResults)
                    }
                }
                // Small jitter between chunks to smooth bursts
                if i < chunkedSyms.count - 1 {
                    try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.08...0.16) * 1_000_000_000))
                }
            }
        }

        // Deduplicate by symbol (prefer first occurrence which should be Binance data)
        if !combined.isEmpty {
            var seen: Set<String> = []
            let merged = combined.filter { cp in
                if seen.contains(cp.symbol) { return false }
                seen.insert(cp.symbol)
                return true
            }
            await __statsCache.set(merged, for: key)
            return merged
        }

        // If we reach here, everything failed — try stale cache before giving up
        if let stale = await __statsCache.get(for: key, maxAge: 300) { return stale }
        if let err = lastError { throw err }
        throw URLError(.badServerResponse)
    }


    // Internal model for Binance 24hr ticker stats
    private struct Ticker24hr: Codable {
        let symbol: String
        let priceChange: String
        let priceChangePercent: String
        let lastPrice: String
        let openPrice: String
        let quoteVolume: String?
        let volume: String?
        enum CodingKeys: String, CodingKey {
            case symbol
            case priceChange = "priceChange"
            case priceChangePercent = "priceChangePercent"
            case lastPrice = "lastPrice"
            case openPrice = "openPrice"
            case quoteVolume = "quoteVolume"
            case volume = "volume"
        }
    }

    private static func coinbaseSparkline(symbol: String) async -> [Double] {
        let pair = symbol.uppercased() + "-USD"
        var comps = URLComponents(url: coinbaseREST, resolvingAgainstBaseURL: false)
        comps?.path = "/products/\(pair)/candles"
        comps?.queryItems = [
            URLQueryItem(name: "granularity", value: "86400"),
            URLQueryItem(name: "limit", value: "7")
        ]
        guard let url = comps?.url else { return [] }

        do {
            await _waitForReachability()
            try? Task.checkCancellation()
            await __rateLimiter.acquire(for: url.host)
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 8
            request.setValue("CryptoSage/1.0", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await _binanceSession.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return []
            }
            if let json = try JSONSerialization.jsonObject(with: data) as? [[Any]] {
                // Each inner array: [time, low, high, open, close, volume]
                // Coinbase returns newest-first; sort by time ascending to match UI expectations.
                func ts(_ a: [Any]) -> Double {
                    if let d = a.first as? Double { return d }
                    if let s = a.first as? String, let d = Double(s) { return d }
                    return 0
                }
                let sorted = json.sorted { ts($0) < ts($1) }
                let closes = sorted.compactMap { arr -> Double? in
                    guard arr.count > 4 else { return nil }
                    if let close = arr[4] as? Double { return close }
                    if let closeStr = arr[4] as? String, let close = Double(closeStr) { return close }
                    return nil
                }
                return closes
            }
        } catch {
            #if DEBUG
            print("❌ [BinanceService] Coinbase sparkline error for \(symbol):", error)
            #endif
        }
        return []
    }

    private static func coinbase24h(symbol: String) async -> CoinPrice? {
        let pair = symbol.uppercased() + "-USD"

        var statsComps = URLComponents(url: coinbaseREST, resolvingAgainstBaseURL: false)
        statsComps?.path = "/products/\(pair)/stats"
        guard let statsURL = statsComps?.url else { return nil }

        struct CoinbaseStats: Codable {
            let open: String
            let high: String
            let low: String
            let last: String
            let volume: String?
        }

        do {
            await _waitForReachability()
            try? Task.checkCancellation()
            await __rateLimiter.acquire(for: statsURL.host)
            var request = URLRequest(url: statsURL)
            request.httpMethod = "GET"
            request.timeoutInterval = 8
            request.setValue("CryptoSage/1.0", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await _binanceSession.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let decoder = JSONDecoder()
            let stats = try decoder.decode(CoinbaseStats.self, from: data)

            let lastPrice = Double(stats.last) ?? 0
            let openPrice = Double(stats.open) ?? 0
            let highPrice = Double(stats.high) ?? 0
            let lowPrice = Double(stats.low) ?? 0
            let change24h: Double
            if openPrice > 0 {
                change24h = ((lastPrice - openPrice) / openPrice) * 100
            } else {
                change24h = 0
            }

            let baseVolume = Double(stats.volume ?? "") ?? 0
            let volumeUSD = (baseVolume > 0 && lastPrice > 0) ? (baseVolume * lastPrice) : 0
            let saneChange = (change24h.isFinite && abs(change24h) <= 2000) ? change24h : 0

            return CoinPrice(
                symbol: symbol.lowercased(),
                lastPrice: lastPrice,
                openPrice: openPrice > 0 ? openPrice : lastPrice,
                highPrice: highPrice,
                lowPrice: lowPrice,
                volume: (volumeUSD > 0 ? volumeUSD : nil),
                change24h: saneChange
            )
        } catch {
            // Attempt fallback to /ticker endpoint for price only
            var tickerComps = URLComponents(url: coinbaseREST, resolvingAgainstBaseURL: false)
            tickerComps?.path = "/products/\(pair)/ticker"
            guard let tickerURL = tickerComps?.url else { return nil }

            struct CoinbaseTicker: Codable {
                let price: String
            }

            do {
                await _waitForReachability()
                try? Task.checkCancellation()
                await __rateLimiter.acquire(for: tickerURL.host)
                var request = URLRequest(url: tickerURL)
                request.httpMethod = "GET"
                request.timeoutInterval = 8
                request.setValue("CryptoSage/1.0", forHTTPHeaderField: "User-Agent")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, response) = try await _binanceSession.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    return nil
                }
                let decoder = JSONDecoder()
                let ticker = try decoder.decode(CoinbaseTicker.self, from: data)
                let lastPrice = Double(ticker.price) ?? 0
                return CoinPrice(
                    symbol: symbol.lowercased(),
                    lastPrice: lastPrice,
                    openPrice: lastPrice,
                    highPrice: lastPrice,
                    lowPrice: lastPrice,
                    volume: nil,
                    change24h: 0
                )
            } catch {
                #if DEBUG
                print("❌ [BinanceService] Coinbase 24h fetch failed for \(symbol):", error)
                #endif
                return nil
            }
        }
    }
}

