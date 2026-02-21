// MARK: - OrderBookViewModel.swift
import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
class OrderBookViewModel: ObservableObject {
    /// Shared singleton instance for performance - prevents recreation on tab switches
    static let shared = OrderBookViewModel()
    
    /// INSTANT DISPLAY FIX: Initialize with cached data preloaded
    /// This ensures the order book has data immediately when the Trading view appears
    private init() {
        // Preload BTC cache (most common trading pair) for instant display
        // This runs when the singleton is first accessed, before the Trading view appears
        _ = loadCacheSync(for: "BTC")
        if !bids.isEmpty {
            currentSymbol = "BTC"
            currentPair = "BTC-USD"
            print("[OrderBook] Preloaded \(bids.count) bids, \(asks.count) asks for BTC from cache")
        }
    }
    
    // MEMORY FIX: Ensure proper cleanup of timers and observers on deallocation
    deinit {
        timer?.invalidate()
        wsPingTimer?.invalidate()
        restPollTimer?.invalidate()
        wsWatchdogTimer?.invalidate()
        wsTask?.cancel(with: .goingAway, reason: nil)
        wsReconnectWorkItem?.cancel()
        #if canImport(UIKit)
        for token in lifecycleObservers {
            NotificationCenter.default.removeObserver(token)
        }
        #endif
    }
    // Stable transport state for UI (prevents flapping when timers start/stop)
    enum TransportKind: String { case ws, rest }
    @Published private(set) var transportKind: TransportKind = .ws

    // Explicit markers to update transport state only when it truly changes
    private func markUsingREST() { if transportKind != .rest { transportKind = .rest } }
    private func markUsingWS() { if transportKind != .ws { transportKind = .ws } }

    @Published var currentSymbol: String = ""
    
    // EXCHANGE SELECTION: Track which exchange the user selected for data consistency
    @Published private(set) var selectedExchange: String? = nil
    
    /// Supported exchanges for order book data
    enum SupportedExchange: String, CaseIterable {
        case binance = "binance"
        case coinbase = "coinbase"
        case kraken = "kraken"
        case kucoin = "kucoin"
        
        var displayName: String {
            switch self {
            case .binance: return "Binance"
            case .coinbase: return "Coinbase"
            case .kraken: return "Kraken"
            case .kucoin: return "KuCoin"
            }
        }
    }
    
    // RELIABILITY FIX: Track cold start for immediate initial fetch (bypasses rate limiter)
    private var isFirstFetchForSymbol: Bool = true
    
    struct OrderBookEntry: Equatable, Codable {
        let price: String
        let qty: String
    }

    // Sanitize a raw array of entries: drop invalid/zero sizes, sort by price, and dedupe by price level.
    private func sanitize(entries: [OrderBookEntry], descending: Bool) -> [OrderBookEntry] {
        // Convert to numeric and drop invalid/zero rows
        var tuples: [(Double, String, String)] = [] // (priceDouble, priceString, qtyString)
        tuples.reserveCapacity(entries.count)
        for e in entries {
            guard let p = Double(e.price), p.isFinite, p > 0 else { continue }
            guard let q = Double(e.qty), q.isFinite, q > 0 else { continue }
            tuples.append((p, e.price, e.qty))
        }
        // Sort by price
        tuples.sort { a, b in
            return descending ? (a.0 > b.0) : (a.0 < b.0)
        }
        // Dedupe by rounded price to avoid duplicate IDs in ForEach(id: \.price)
        // Use dynamic precision based on price magnitude for proper handling of low-priced assets
        var seen = Set<Int64>()  // Store as integer hash for precision
        var out: [OrderBookEntry] = []
        out.reserveCapacity(min(tuples.count, maxLevelsPerSide))
        for (p, priceStr, qtyStr) in tuples {
            // Dynamic precision: more decimal places for smaller prices
            // This ensures we don't merge distinct prices for very low-priced tokens
            let precisionMultiplier: Double = {
                if p >= 1000 { return 1e4 }       // 4 decimals for $1000+
                else if p >= 1 { return 1e6 }    // 6 decimals for $1-$1000
                else if p >= 0.001 { return 1e8 } // 8 decimals for $0.001-$1
                else if p >= 0.000001 { return 1e10 } // 10 decimals for very small
                else { return 1e12 }              // 12 decimals for micro-caps
            }()
            let canonical = Int64((p * precisionMultiplier).rounded())
            if seen.insert(canonical).inserted {
                out.append(OrderBookEntry(price: priceStr, qty: qtyStr))
                if out.count >= maxLevelsPerSide { break }
            }
        }
        return out
    }

    // MARK: - Order Book Caching Helpers
    /// Maximum age for cached order book data before it's considered too stale to display.
    /// Cache older than this is discarded entirely (shows loading state until live data arrives).
    /// Cache younger than this is shown immediately as a placeholder while live data loads.
    private let cacheMaxAge: TimeInterval = 30 * 60 // 30 minutes — discard truly ancient data

    private func cacheKeys(for symbol: String) -> (bidsKey: String, asksKey: String, tsKey: String) {
        let base = "OrderBookCache_\(symbol)"
        return ("\(base)_bids", "\(base)_asks", "\(base)_ts")
    }

    /// Synchronously loads cached order book data and returns whether cache was found.
    /// This enables instant display of cached data before network requests complete.
    /// Cache older than `cacheMaxAge` (30 min) is discarded to prevent showing wildly stale prices.
    /// Cache within the TTL is shown as a placeholder while WebSocket/REST fetch fresh data.
    @discardableResult
    private func loadCacheSync(for symbol: String) -> Bool {
        let keys = cacheKeys(for: symbol)

        // STALENESS CHECK: Discard cache older than 30 minutes to prevent
        // showing hours-old order book prices that differ wildly from live data.
        // Cache within 30 min is shown as a placeholder while live data loads.
        let savedAt = UserDefaults.standard.double(forKey: keys.tsKey)
        if savedAt > 0 {
            let age = Date().timeIntervalSince1970 - savedAt
            if age > cacheMaxAge {
                print("[OrderBook] Cache for \(symbol.uppercased()) is \(Int(age))s old (max \(Int(cacheMaxAge))s) — discarded")
                return false
            }
        }

        let decoder = JSONDecoder()
        var loadedBids: [OrderBookEntry] = []
        var loadedAsks: [OrderBookEntry] = []
        if let data = UserDefaults.standard.data(forKey: keys.bidsKey),
           let cached = try? decoder.decode([OrderBookEntry].self, from: data) {
            loadedBids = Array(cached.prefix(100))
        }
        if let data = UserDefaults.standard.data(forKey: keys.asksKey),
           let cached = try? decoder.decode([OrderBookEntry].self, from: data) {
            loadedAsks = Array(cached.prefix(100))
        }
        let hasCache = !loadedBids.isEmpty || !loadedAsks.isEmpty
        // Apply synchronously for instant display
        self.bids = loadedBids
        self.asks = loadedAsks
        if hasCache {
            self.isLoading = false  // Don't show loading state when we have cached data
            print("[OrderBook] Instantly loaded cached book for \(symbol.uppercased()) bids=\(loadedBids.count) asks=\(loadedAsks.count)")
        }
        return hasCache
    }
    
    private func loadCache(for symbol: String) {
        let keys = cacheKeys(for: symbol)

        // STALENESS CHECK: same as loadCacheSync
        let savedAt = UserDefaults.standard.double(forKey: keys.tsKey)
        if savedAt > 0 {
            let age = Date().timeIntervalSince1970 - savedAt
            if age > cacheMaxAge { return }
        }

        let decoder = JSONDecoder()
        var loadedBids: [OrderBookEntry] = []
        var loadedAsks: [OrderBookEntry] = []
        if let data = UserDefaults.standard.data(forKey: keys.bidsKey),
           let cached = try? decoder.decode([OrderBookEntry].self, from: data) {
            loadedBids = Array(cached.prefix(100))
        }
        if let data = UserDefaults.standard.data(forKey: keys.asksKey),
           let cached = try? decoder.decode([OrderBookEntry].self, from: data) {
            loadedAsks = Array(cached.prefix(100))
        }
        // Already on @MainActor, assign directly
        self.bids = loadedBids
        self.asks = loadedAsks
        if !loadedBids.isEmpty || !loadedAsks.isEmpty {
            print("[OrderBook] Loaded cached book for \(symbol.uppercased()) bids=\(loadedBids.count) asks=\(loadedAsks.count)")
        }
    }

    private func saveCache(for symbol: String) {
        let keys = cacheKeys(for: symbol)
        let encoder = JSONEncoder()
        let maxPersistRows = 100
        let trimmedBids = Array(bids.prefix(maxPersistRows))
        let trimmedAsks = Array(asks.prefix(maxPersistRows))
        if let data = try? encoder.encode(trimmedBids) {
            UserDefaults.standard.set(data, forKey: keys.bidsKey)
        }
        if let data = try? encoder.encode(trimmedAsks) {
            UserDefaults.standard.set(data, forKey: keys.asksKey)
        }
        // Save timestamp so we can invalidate stale cache on next load
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: keys.tsKey)
    }

    private func saveCacheThrottled(for symbol: String) {
        let now = Date()
        if now.timeIntervalSince(lastCacheSaveAt) >= 2.0 {
            saveCache(for: symbol)
            lastCacheSaveAt = now
        }
    }

    /// Normalizes pair-like inputs (e.g. BTCUSDT, BTC-USD, BTC_USDT) to a base symbol (BTC).
    private func normalizedBaseSymbol(_ raw: String) -> String {
        let upper = raw.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if upper.isEmpty { return upper }

        if upper.contains("-") {
            return upper.split(separator: "-").first.map(String.init) ?? upper
        }
        if upper.contains("_") {
            return upper.split(separator: "_").first.map(String.init) ?? upper
        }

        let quotes = ["USDT", "USD", "BUSD", "USDC", "FDUSD"]
        if let quote = quotes.first(where: { upper.hasSuffix($0) }), upper.count > quote.count {
            return String(upper.dropLast(quote.count))
        }
        return upper
    }

    @Published var bids: [OrderBookEntry] = []
    @Published var asks: [OrderBookEntry] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    
    /// PRICE ACCURACY: Real-time mid-price computed from best bid/ask.
    /// This is the most accurate exchange-specific price available (sub-second latency via WebSocket).
    /// Used by TradeViewModel to supplement the CoinGecko/Firebase price on the Trading screen,
    /// reducing the lag from 30-60 seconds (CoinGecko polling) to near real-time.
    @Published private(set) var midPrice: Double = 0
    /// Timestamp of last mid-price update for staleness detection
    private(set) var midPriceUpdatedAt: Date = .distantPast

    // Throttling / coalescing
    private var lastFetchAt: Date?
    private let minFetchInterval: TimeInterval = 2.0
    private var isFetching: Bool = false
    private var currentPair: String?
    private var currentRequestKey: String?
    private var urlTask: URLSessionDataTask?

    private var timer: Timer?
    // Ensure lifecycle observers are only registered once
    private var didSetupLifecycleObservers: Bool = false

    // MARK: - WebSocket (Binance primary, Coinbase fallback)
    private var wsSession: URLSession = URLSession(configuration: {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.waitsForConnectivity = true
        return cfg
    }())
    private var wsTask: URLSessionWebSocketTask?
    private var wsPingTimer: Timer?
    private var wsReconnectWorkItem: DispatchWorkItem?
    private var lastWSTickAt: Date = .distantPast
    private var wsConnectedAt: Date = .distantPast
    
    // PERFORMANCE FIX: WebSocket message throttle - increased from 25ms to 100ms
    // Reduces main thread work and prevents "Message send exceeds rate-limit threshold" warnings
    // 100ms (10Hz) is sufficient for order book updates while maintaining smooth scrolling
    private var lastWSMessageProcessedAt: CFTimeInterval = 0
    private let wsMessageMinInterval: CFTimeInterval = 0.100  // Max 10 messages/second processed
    #if canImport(UIKit)
    private var isInBackground: Bool = false
    private var lifecycleObservers: [NSObjectProtocol] = []
    #endif
    private var wsCooldownUntil: Date = .distantPast
    private var wsFailureCount: Int = 0
    private var binanceWSDisabledUntil: Date = .distantPast
    private var binanceHTTPDisabledUntil: Date = .distantPast
    /// FIX v5.0.3: Track how many times Binance returns HTTP 451 (geo-block) this session.
    /// After 3+ blocks, Binance is permanently disabled for the remainder of the session.
    private var binanceGeoBlockCount: Int = 0
    private var binancePermanentlyBlocked: Bool = false
    private func binanceWSEnabled() -> Bool { !binancePermanentlyBlocked && Date() >= binanceWSDisabledUntil && Date() >= binanceHTTPDisabledUntil }
    private func binanceHTTPEnabled() -> Bool { !binancePermanentlyBlocked && Date() >= binanceHTTPDisabledUntil }

    /// FIX v5.0.3: Safely rotate to the next URL in restCandidatesCache, skipping disabled Binance URLs.
    private func rotateToNextValidURL() {
        guard !restCandidatesCache.isEmpty else { return }
        let startIndex = restIndex
        var attempts = 0
        repeat {
            restIndex = (restIndex + 1) % restCandidatesCache.count
            let candidate = restCandidatesCache[restIndex]
            if candidate.host?.contains("binance") != true || binanceHTTPEnabled() {
                restDepthURL = candidate
                saveRESTIndex(for: currentSymbol)
                return
            }
            attempts += 1
        } while restIndex != startIndex && attempts < restCandidatesCache.count
        // All URLs are blocked Binance — fall through (performPoll guard will handle)
        restDepthURL = restCandidatesCache[restIndex]
        saveRESTIndex(for: currentSymbol)
    }

    private var restPollTimer: Timer?
    private var restDepthURL: URL?

    // PERFORMANCE FIX: Increased from 0.9s to 3.0s to reduce UI update frequency
    // This prevents "Message send exceeds rate-limit threshold" warnings
    private var restPollInterval: TimeInterval = 3.0
    private var restErrorStreak: Int = 0
    private var restSuccessStreak: Int = 0
    private var restCandidatesCache: [URL] = []
    private var restPollingSymbol: String = ""
    private var restDisabledUntil: Date = .distantPast
    private func restEnabled() -> Bool { Date() >= restDisabledUntil }
    
    // SCALABILITY: Firebase proxy mode for REST fallback
    // When direct API calls fail repeatedly, use Firebase proxy to avoid rate limits
    private var useFirebaseProxy: Bool = false
    private var firebaseProxyErrorCount: Int = 0
    private let firebaseProxyMaxErrors: Int = 3  // Switch back to direct after 3 consecutive errors
    private var firebaseProxyDisabledUntil: Date = .distantPast
    private func firebaseProxyEnabledNow() -> Bool { Date() >= firebaseProxyDisabledUntil }
    
    // Lifecycle guard so reconnect/poll timers do not continue after the view leaves Trade.
    private var isRealtimeActive: Bool = false
    
    /// CRASH FIX: Safe accessor for REST candidate URLs that handles empty cache
    /// and out-of-bounds index (e.g., stale UserDefaults value from previous session)
    private func safeRESTCandidate(at index: Int) -> URL? {
        guard !restCandidatesCache.isEmpty else { return nil }
        let safeIndex = index % restCandidatesCache.count
        return restCandidatesCache[safeIndex]
    }
    
    private var _lastLogTimes: [String: Date] = [:]
    private func log(_ key: String, _ message: String, minInterval: TimeInterval = 5) {
        let now = Date()
        let last = _lastLogTimes[key] ?? .distantPast
        if now.timeIntervalSince(last) >= minInterval {
            print(message)
            _lastLogTimes[key] = now
        }
    }

    // In-memory book (price -> qty)
    private var bookBids: [String: String] = [:]
    private var bookAsks: [String: String] = [:]
    private var publishTimer: DispatchSourceTimer?
    private var pendingPublish: Bool = false
    private var lastPublishedBids: [OrderBookEntry] = []
    private var lastPublishedAsks: [OrderBookEntry] = []
    private var lastCacheSaveAt: Date = .distantPast

    private let maxRowsToPublish: Int = 40
    private let maxLevelsPerSide: Int = 160

    // Host rotation indices
    private var binanceWSIndex: Int = 0
    private var restIndex: Int = 0

    // MARK: - Persistence helpers for endpoint indices
    private func wsIndexKey(for symbol: String) -> String { "OBM_BinanceWSIndex_\(symbol.uppercased())" }
    private func restIndexKey(for symbol: String) -> String { "OBM_RESTIndex_\(symbol.uppercased())" }
    private func loadEndpointIndices(for symbol: String) {
        let s = symbol.uppercased()
        if let wsVal = UserDefaults.standard.object(forKey: wsIndexKey(for: s)) as? Int { binanceWSIndex = wsVal }
        if let restVal = UserDefaults.standard.object(forKey: restIndexKey(for: s)) as? Int { restIndex = restVal }
    }
    private func saveWSIndex(for symbol: String) {
        UserDefaults.standard.set(binanceWSIndex, forKey: wsIndexKey(for: symbol))
    }
    private func saveRESTIndex(for symbol: String) {
        UserDefaults.standard.set(restIndex, forKey: restIndexKey(for: symbol))
    }

    // PRICE CONSISTENCY FIX: Use selected exchange as primary source
    private enum DataSource: String { 
        case binance = "binance"
        case coinbase = "coinbase" 
        case kraken = "kraken"
        case kucoin = "kucoin"
    }
    private var currentSourceWS: DataSource = .binance
    private var wsWatchdogTimer: Timer?
    private var wsReconnectAttempts: Int = 0
    private var wsBackoff: TimeInterval = 1.0
    private let wsBackoffMax: TimeInterval = 60.0
    
    // SESSION-LEVEL WebSocket health tracking (shared across all OrderBookViewModel instances).
    // When Coinbase WS keeps timing out, this persists across navigations so we don't
    // reset the circuit breaker every time the user re-opens the chart.
    private static var sessionWSFailures: [DataSource: Int] = [:]
    private static let sessionWSMaxFailures = 5 // After 5 failures in session, skip WS for this source
    private static var wsDisabledUntil: [DataSource: Date] = [:]
    
    /// Check if WebSocket should be skipped entirely for this source (session-level)
    private func isWSDisabledForSession(source: DataSource) -> Bool {
        if let until = Self.wsDisabledUntil[source], Date() < until { return true }
        return (Self.sessionWSFailures[source] ?? 0) >= Self.sessionWSMaxFailures
    }
    
    private func recordSessionWSFailure(source: DataSource) {
        let count = (Self.sessionWSFailures[source] ?? 0) + 1
        Self.sessionWSFailures[source] = count
        if count >= Self.sessionWSMaxFailures {
            // Disable WS for this source for 5 minutes
            Self.wsDisabledUntil[source] = Date().addingTimeInterval(300)
            #if DEBUG
            log("ws.session.disabled", "[OrderBook] \(source.rawValue) WS disabled for 5 min after \(count) session failures — using REST only", minInterval: 60)
            #endif
        }
    }
    
    private static func resetSessionWSHealth(for source: DataSource) {
        sessionWSFailures[source] = 0
        wsDisabledUntil[source] = nil
    }

    private func inWSCooldown() -> Bool { Date() < wsCooldownUntil }
    private func noteWSFailure() {
        wsFailureCount += 1
        recordSessionWSFailure(source: currentSourceWS)
        let backoff = min(120.0, pow(2.0, Double(min(wsFailureCount, 6)))) // 2,4,8,16,32,64,120
        wsCooldownUntil = Date().addingTimeInterval(backoff)
        // PERFORMANCE: Rate-limit cooldown logs to once per 30s
        log("ws.cooldown", "[OrderBook] WS cooldown engaged for \(Int(backoff))s after \(wsFailureCount) failures", minInterval: 30)
    }
    private func noteWSSuccess() {
        wsFailureCount = 0
        wsCooldownUntil = .distantPast
        Self.resetSessionWSHealth(for: currentSourceWS)
    }

    #if canImport(UIKit)
    private func setupLifecycleObservers() {
        if didSetupLifecycleObservers { return }
        didSetupLifecycleObservers = true
        let bgToken = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.isInBackground = true
                // Pause WS and rely on REST fallback at a slower cadence
                self.stopWebSocket()
                self.startRESTDepthPolling(symbol: self.currentSymbol)
            }
        }
        self.lifecycleObservers.append(bgToken)
        let fgToken = NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.isInBackground = false
                // Resume WS when foregrounded - use Binance for consistency with Chart
                self.stopRESTDepthPolling()
                self.startWebSocket(for: self.currentSymbol, source: .binance)
            }
        }
        self.lifecycleObservers.append(fgToken)
    }
    #else
    private func setupLifecycleObservers() { /* no-op */ }
    #endif

    /// Start fetching order book data for the given symbol
    /// - Parameters:
    ///   - symbol: The base symbol (e.g., "BTC")
    ///   - exchange: Optional exchange to fetch from. If nil, uses Binance as default.
    ///               Supported exchanges: binance, coinbase, kraken, kucoin
    func startFetchingOrderBook(for symbol: String, exchange: String? = nil) {
        setupLifecycleObservers()
        isRealtimeActive = true
        let normalizedSymbol = normalizedBaseSymbol(symbol)
        self.currentSymbol = normalizedSymbol
        self.selectedExchange = exchange
        loadEndpointIndices(for: normalizedSymbol)
        let pair = normalizedSymbol + "-USD"
        
        // GEO-BLOCKING FIX: If Binance is geo-blocked and no exchange specified,
        // proactively enable Firebase proxy and prefer Coinbase for faster data
        let isGeoBlocked = UserDefaults.standard.bool(forKey: "BinanceGlobalGeoBlocked")
        if isGeoBlocked && exchange == nil {
            enableFirebaseProxyMode()
        }
        
        // Determine which data source to use based on exchange selection
        let dataSource: DataSource = {
            guard let ex = exchange?.lowercased() else {
                // Default: prefer Coinbase when geo-blocked, Binance otherwise
                return isGeoBlocked ? .coinbase : .binance
            }
            switch ex {
            case "coinbase": return .coinbase
            case "kraken": return .kraken
            case "kucoin": return .kucoin
            default: return .binance
            }
        }()
        
        print("[OrderBook] Starting for \(normalizedSymbol) on exchange: \(exchange ?? "binance (default)") | currentPair=\(currentPair ?? "nil") | bids=\(bids.count) | asks=\(asks.count)")

        let exchangeID = exchange?.lowercased() ?? (isGeoBlocked ? "coinbase" : "binance")
        let requestKey = "\(pair)|\(exchangeID)"
        let isSameRequest = (currentRequestKey == requestKey)
        
        // INSTANT DISPLAY FIX: Only load cache when request changes.
        // Reloading cache for identical requests causes unnecessary decode churn.
        let hasCache = isSameRequest ? false : loadCacheSync(for: normalizedSymbol)
        let hasData = !bids.isEmpty
        
        if isSameRequest && hasData {
            // Returning to identical symbol+exchange request with existing data.
            // Resume only missing transports; avoid duplicate startup work.
            print("[OrderBook] Resuming for \(normalizedSymbol) - \(bids.count) bids, \(asks.count) asks visible")
            isLoading = false  // Ensure no loading state shows
            if restPollTimer == nil {
                startRESTDepthPolling(symbol: normalizedSymbol, exchange: exchange)
            }
            if wsTask == nil {
                startWebSocket(for: normalizedSymbol, source: dataSource)
            }
            
            // Restart the periodic refresh timer
            if timer == nil {
                timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        self?.fetchOrderBookThrottled(pair: pair, exchange: exchange)
                    }
                }
            }
            return
        }

        currentRequestKey = requestKey
        currentPair = pair
        
        // Only clear buffers when switching to a DIFFERENT symbol
        if !isSameRequest {
            print("[OrderBook] Switching symbol - clearing old data")
            bookBids.removeAll(); bookAsks.removeAll(); lastPublishedBids = []; lastPublishedAsks = []; pendingPublish = false; lastCacheSaveAt = .distantPast
        }
        
        // RELIABILITY FIX: Reset cold start flag for new symbol
        isFirstFetchForSymbol = true
        
        // Only show loading if we truly have no data to display
        if !hasData { 
            self.isLoading = true 
            print("[OrderBook] No cached data - showing loading state")
        } else {
            self.isLoading = false
            print("[OrderBook] Loaded \(bids.count) bids, \(asks.count) asks from cache")
        }
        
        // RELIABILITY FIX: Immediate first fetch bypasses rate limiter for faster cold start
        if isFirstFetchForSymbol && !hasCache {
            isFirstFetchForSymbol = false
            fetchOrderBook(pair: pair, exchange: exchange)  // Direct call, no throttle check
        } else {
            fetchOrderBookThrottled(pair: pair, exchange: exchange)
        }
        startRESTDepthPolling(symbol: normalizedSymbol, exchange: exchange)
        startWebSocket(for: normalizedSymbol, source: dataSource)

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fetchOrderBookThrottled(pair: pair, exchange: exchange)
            }
        }
    }

    private func fetchOrderBookThrottled(pair: String, exchange: String? = nil) {
        if isFetching { return }
        if let last = lastFetchAt, Date().timeIntervalSince(last) < minFetchInterval { return }
        // FIX: Only check rate limiter for the ACTUAL exchange being used
        // Previously checked .coinbase for ALL exchanges, blocking Binance requests
        // when Coinbase was rate-limited
        let exchangeID = exchange?.lowercased() ?? "binance"
        let apiService: APIRequestCoordinator.APIService = exchangeID == "coinbase" ? .coinbase : .binance
        guard APIRequestCoordinator.shared.canMakeRequest(for: apiService) else {
            return  // Skip when rate limited
        }
        lastFetchAt = Date()
        fetchOrderBook(pair: pair, exchange: exchange)
    }

    func stopFetching() {
        isRealtimeActive = false
        // CACHE PERSISTENCE: Save current data before stopping
        // This ensures we have fresh data to display instantly on next start
        if !bids.isEmpty || !asks.isEmpty {
            saveCache(for: currentSymbol)
            print("[OrderBook] Saved \(bids.count) bids, \(asks.count) asks to cache before stopping")
        }
        
        timer?.invalidate()
        timer = nil
        urlTask?.cancel()
        urlTask = nil
        isFetching = false
        isLoading = false
        stopWebSocket()
        stopRESTDepthPolling()
        #if canImport(UIKit)
        for token in lifecycleObservers { NotificationCenter.default.removeObserver(token) }
        lifecycleObservers.removeAll()
        didSetupLifecycleObservers = false
        #endif
        // NOTE: We intentionally do NOT clear bids/asks here
        // The data remains visible until new data arrives
    }

    private func fetchOrderBook(pair: String, exchange: String? = nil) {
        let base = pair.replacingOccurrences(of: "-USD", with: "").uppercased()
        let exchangeID = exchange?.lowercased() ?? "binance"
        
        // Build URL based on selected exchange
        let urlString: String
        switch exchangeID {
        case "coinbase":
            // PERFORMANCE FIX: Limit Coinbase L2 book to 50 levels per side instead of the full book
            // Previously fetched the entire L2 book (14K+ bids, 29K+ asks) causing massive main-thread parsing
            urlString = "https://api.exchange.coinbase.com/products/\(base)-USD/book?level=2&limit=50"
        case "kraken":
            // Kraken uses XBT for Bitcoin
            let krakenSymbol = base == "BTC" ? "XBT" : base
            urlString = "https://api.kraken.com/0/public/Depth?pair=\(krakenSymbol)USD&count=50"
        case "kucoin":
            urlString = "https://api.kucoin.com/api/v1/market/orderbook/level2_20?symbol=\(base)-USDT"
        default: // binance
            // GEO-BLOCKING FIX: Use Binance mirror when geo-blocked (Binance.US is shut down)
            let isGeoBlocked = UserDefaults.standard.bool(forKey: "BinanceGlobalGeoBlocked")
            urlString = isGeoBlocked
                ? "https://api4.binance.com/api/v3/depth?symbol=\(base)USDT&limit=50"
                : "https://api.binance.com/api/v3/depth?symbol=\(base)USDT&limit=50"
        }
        
        guard let url = URL(string: urlString) else {
            self.errorMessage = "Invalid order book URL."
            self.isFetching = false
            return
        }
        
        print("[OrderBook] Fetching from \(exchangeID): \(url.absoluteString)")
        
        // FIX: Record request with coordinator - use the actual exchange, not always coinbase
        let apiSvc: APIRequestCoordinator.APIService = exchangeID == "coinbase" ? .coinbase : .binance
        APIRequestCoordinator.shared.recordRequest(for: apiSvc)
        
        self.isLoading = true
        self.errorMessage = nil
        self.isFetching = true
        self.urlTask?.cancel()

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            if let nsErr = error as NSError? {
                if nsErr.domain == NSURLErrorDomain && nsErr.code == NSURLErrorCancelled {
                    Task { @MainActor in self.isFetching = false }
                    return
                }
                Task { @MainActor in
                    // PERFORMANCE: Rate-limit fetch error logs
                    self.log("fetch.error", "[OrderBook] Fetch error from \(exchangeID): \(nsErr.localizedDescription)", minInterval: 30)
                    self.fallbackFetchOrderBook(pair: pair)
                }
                return
            }
            guard let data = data else {
                Task { @MainActor in
                    print("[OrderBook] No data from \(exchangeID) order book.")
                    self.fallbackFetchOrderBook(pair: pair)
                }
                return
            }
            
            // Parse response based on exchange format
            Task { @MainActor in
                do {
                    let (parsedBids, parsedAsks) = try self.parseOrderBookResponse(data: data, exchange: exchangeID)
                    let sb = self.sanitize(entries: parsedBids, descending: true)
                    let sa = self.sanitize(entries: parsedAsks, descending: false)
                    
                    // GEO-BLOCKING FIX: Empty response indicates blocked endpoint
                    // Binance returns 0 bids/asks when geo-blocked instead of an error
                    if sb.isEmpty && sa.isEmpty {
                        print("[OrderBook] Empty response from \(exchangeID) (possible geo-block) - trying fallback")
                        self.fallbackFetchOrderBook(pair: pair)
                        return
                    }
                    
                    // PERFORMANCE FIX: During scroll, defer @Published updates to avoid janky
                    // re-renders, but NEVER discard data. Buffer it for immediate application
                    // when scroll ends. Previously this silently dropped data, causing empty order books.
                    if ScrollStateManager.shared.shouldBlockHeavyOperation() && !self.bids.isEmpty {
                        // Already have data showing - just buffer the update for later
                        self.bookBids = sb.reduce(into: [:]) { $0[$1.price] = $1.qty }
                        self.bookAsks = sa.reduce(into: [:]) { $0[$1.price] = $1.qty }
                        self.isFetching = false
                        // Don't set isLoading = false; leave it as-is
                        return
                    }
                    
                    self.bids = sb
                    self.asks = sa
                    self.saveCacheThrottled(for: base)
                    self.isFetching = false
                    self.isLoading = false
                    print("[OrderBook] Successfully loaded from \(exchangeID): bids=\(sb.count) asks=\(sa.count)")
                } catch {
                    print("[OrderBook] Parse error from \(exchangeID): \(error.localizedDescription)")
                    self.fallbackFetchOrderBook(pair: pair)
                }
            }
        }
        self.urlTask = task
        task.resume()
    }
    
    /// Parse order book response from different exchanges
    private func parseOrderBookResponse(data: Data, exchange: String) throws -> ([OrderBookEntry], [OrderBookEntry]) {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "OrderBook", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON"])
        }
        
        var parsedBids: [OrderBookEntry] = []
        var parsedAsks: [OrderBookEntry] = []
        
        switch exchange.lowercased() {
        case "kraken":
            // Kraken format: {"result": {"XXBTZUSD": {"bids": [[price, volume, timestamp], ...], "asks": [...]}}}
            if let result = json["result"] as? [String: Any] {
                // Get the first (and usually only) pair result
                if let pairData = result.values.first as? [String: Any] {
                    if let bidsArr = pairData["bids"] as? [[Any]] {
                        parsedBids = bidsArr.map { arr -> OrderBookEntry in
                            let price = arr.indices.contains(0) ? String(describing: arr[0]) : "0"
                            let qty = arr.indices.contains(1) ? String(describing: arr[1]) : "0"
                            return OrderBookEntry(price: price, qty: qty)
                        }
                    }
                    if let asksArr = pairData["asks"] as? [[Any]] {
                        parsedAsks = asksArr.map { arr -> OrderBookEntry in
                            let price = arr.indices.contains(0) ? String(describing: arr[0]) : "0"
                            let qty = arr.indices.contains(1) ? String(describing: arr[1]) : "0"
                            return OrderBookEntry(price: price, qty: qty)
                        }
                    }
                }
            }
            
        case "kucoin":
            // KuCoin format: {"data": {"bids": [[price, size], ...], "asks": [[price, size], ...]}}
            if let dataObj = json["data"] as? [String: Any] {
                if let bidsArr = dataObj["bids"] as? [[Any]] {
                    parsedBids = bidsArr.map { arr -> OrderBookEntry in
                        let price = arr.indices.contains(0) ? String(describing: arr[0]) : "0"
                        let qty = arr.indices.contains(1) ? String(describing: arr[1]) : "0"
                        return OrderBookEntry(price: price, qty: qty)
                    }
                }
                if let asksArr = dataObj["asks"] as? [[Any]] {
                    parsedAsks = asksArr.map { arr -> OrderBookEntry in
                        let price = arr.indices.contains(0) ? String(describing: arr[0]) : "0"
                        let qty = arr.indices.contains(1) ? String(describing: arr[1]) : "0"
                        return OrderBookEntry(price: price, qty: qty)
                    }
                }
            }
            
        case "coinbase":
            // Coinbase format: {"bids": [[price, qty, ...], ...], "asks": [...]}
            if let bidsArr = json["bids"] as? [[Any]] {
                parsedBids = bidsArr.map { arr -> OrderBookEntry in
                    let price = arr[0] as? String ?? "0"
                    let qty = arr[1] as? String ?? "0"
                    return OrderBookEntry(price: price, qty: qty)
                }
            }
            if let asksArr = json["asks"] as? [[Any]] {
                parsedAsks = asksArr.map { arr -> OrderBookEntry in
                    let price = arr[0] as? String ?? "0"
                    let qty = arr[1] as? String ?? "0"
                    return OrderBookEntry(price: price, qty: qty)
                }
            }
            
        default: // binance
            // Binance format: {"bids": [[price, qty], ...], "asks": [...]}
            if let bidsArr = json["bids"] as? [[Any]] {
                parsedBids = bidsArr.map { arr -> OrderBookEntry in
                    let price = arr.indices.contains(0) ? (arr[0] as? String ?? String(describing: arr[0])) : "0"
                    let qty = arr.indices.contains(1) ? (arr[1] as? String ?? String(describing: arr[1])) : "0"
                    return OrderBookEntry(price: price, qty: qty)
                }
            }
            if let asksArr = json["asks"] as? [[Any]] {
                parsedAsks = asksArr.map { arr -> OrderBookEntry in
                    let price = arr.indices.contains(0) ? (arr[0] as? String ?? String(describing: arr[0])) : "0"
                    let qty = arr.indices.contains(1) ? (arr[1] as? String ?? String(describing: arr[1])) : "0"
                    return OrderBookEntry(price: price, qty: qty)
                }
            }
        }
        
        return (parsedBids, parsedAsks)
    }

    // MARK: - Fallback Order Book Fetch
    private func fallbackFetchOrderBook(pair: String) {
        markUsingREST()
        self.isLoading = true
        self.errorMessage = nil
        self.isFetching = true
        self.urlTask?.cancel()
        
        if !self.restEnabled() {
            self.isLoading = false
            self.isFetching = false
            return
        }

        let base: String = {
            if let dash = pair.firstIndex(of: "-") { return String(pair[..<dash]) } else { return pair }
        }().uppercased()

        var candidates: [String] = []
        if binanceHTTPEnabled() {
            // GEO-BLOCKING FIX: Check if user is in geo-blocked region (persisted from BinanceService)
            // BINANCE-US-FIX: Binance.US is shut down - use global mirrors only
            let isGeoBlocked = UserDefaults.standard.bool(forKey: "BinanceGlobalGeoBlocked")
            if isGeoBlocked {
                // Use Binance mirror when geo-blocked
                candidates.append("https://api4.binance.com/api/v3/depth?symbol=\(base)USDT&limit=50")
                candidates.append("https://api4.binance.com/api/v3/depth?symbol=\(base)USD&limit=50")
            } else {
                // Try global Binance first, then mirror
                candidates.append("https://api.binance.com/api/v3/depth?symbol=\(base)USDT&limit=50")
                candidates.append("https://api.binance.com/api/v3/depth?symbol=\(base)USD&limit=50")
                candidates.append("https://api4.binance.com/api/v3/depth?symbol=\(base)USDT&limit=50")
                candidates.append("https://api4.binance.com/api/v3/depth?symbol=\(base)USD&limit=50")
            }
        }
        // Always include Coinbase as a final candidate so we have a fast, reliable fallback
        // PERFORMANCE FIX: Limit to 50 levels to avoid parsing 14K+ entries on main thread
        candidates.append("https://api.exchange.coinbase.com/products/\(base)-USD/book?level=2&limit=50")

        func attempt(_ index: Int) {
            if index >= candidates.count {
                Task { @MainActor in
                    self.isLoading = false
                    self.errorMessage = "Error loading order book."
                    self.isFetching = false
                }
                return
            }
            guard let url = URL(string: candidates[index]) else {
                attempt(index + 1)
                return
            }
            var req = URLRequest(url: url)
            req.timeoutInterval = 3
            let task = URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
                guard let self = self else { return }
                if let http = response as? HTTPURLResponse, http.statusCode == 451 {
                    Task { @MainActor in
                        self.binanceHTTPDisabledUntil = Date().addingTimeInterval(600)
                        self.binanceGeoBlockCount += 1
                        print("[OrderBook] HTTP 451 from \(http.url?.host ?? "?"); disabling Binance HTTP for 600s (count: \(self.binanceGeoBlockCount))")
                        // FIX v5.0.3: After 3+ geo-blocks, permanently disable Binance for this session
                        if self.binanceGeoBlockCount >= 3 && !self.binancePermanentlyBlocked {
                            self.binancePermanentlyBlocked = true
                            print("[OrderBook] 🛑 Binance permanently blocked for this session after \(self.binanceGeoBlockCount) geo-blocks")
                        }
                    }
                    Task { @MainActor in attempt(index + 1) }
                    return
                }
                if let nsErr = error as NSError? {
                    if nsErr.domain == NSURLErrorDomain && nsErr.code == NSURLErrorCancelled {
                        Task { @MainActor in attempt(index + 1) }
                        return
                    }
                    print("Binance order book error (attempt \(index)):", nsErr.localizedDescription)
                    Task { @MainActor in attempt(index + 1) }
                    return
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let bidsArr = json["bids"] as? [[Any]],
                      let asksArr = json["asks"] as? [[Any]],
                      !bidsArr.isEmpty || !asksArr.isEmpty
                else {
                    Task { @MainActor in attempt(index + 1) }
                    return
                }

                let parsedBids = bidsArr.map { arr -> OrderBookEntry in
                    let price = arr.indices.contains(0) ? (arr[0] as? String ?? String(describing: arr[0])) : "0"
                    let qty   = arr.indices.contains(1) ? (arr[1] as? String ?? String(describing: arr[1])) : "0"
                    return OrderBookEntry(price: price, qty: qty)
                }
                let parsedAsks = asksArr.map { arr -> OrderBookEntry in
                    let price = arr.indices.contains(0) ? (arr[0] as? String ?? String(describing: arr[0])) : "0"
                    let qty   = arr.indices.contains(1) ? (arr[1] as? String ?? String(describing: arr[1])) : "0"
                    return OrderBookEntry(price: price, qty: qty)
                }

                Task { @MainActor in
                    self.errorMessage = nil
                    let sb = self.sanitize(entries: parsedBids, descending: true)
                    let sa = self.sanitize(entries: parsedAsks, descending: false)
                    
                    // PERFORMANCE FIX: Skip @Published updates during scroll, BUT only when
                    // we already have data showing. On initial load (bids empty), always
                    // publish immediately so the order book doesn't stay blank.
                    if ScrollStateManager.shared.shouldBlockHeavyOperation() && !self.bids.isEmpty {
                        // Buffer for later - data already visible to user
                        self.bookBids = sb.reduce(into: [:]) { $0[$1.price] = $1.qty }
                        self.bookAsks = sa.reduce(into: [:]) { $0[$1.price] = $1.qty }
                        self.isLoading = false
                        self.isFetching = false
                        return
                    }
                    
                    self.bids = sb
                    self.asks = sa
                    self.saveCacheThrottled(for: base)
                    self.isLoading = false
                    self.isFetching = false
                }
            }
            Task { @MainActor in self.urlTask = task }
            task.resume()
        }

        attempt(0)
    }

    // MARK: - Host candidates
    private func binanceWSCandidates(for symbol: String) -> [URL] {
        // PERFORMANCE FIX v20: Removed binance.us endpoints — Binance US is shut down.
        // Connecting to dead endpoints caused immediate TCP RSTs, triggering rapid
        // circuit-breaker escalation (5 failures in seconds) and massive tcp_input RST floods.
        // Also skip ALL Binance WS when geo-blocked to avoid wasted connection attempts.
        let isGeoBlocked = UserDefaults.standard.bool(forKey: "BinanceGlobalGeoBlocked")
        if isGeoBlocked { return [] }
        
        // Use diff-depth stream instead of fixed depth20 snapshot stream.
        // This keeps a richer in-memory book (seeded by REST) rather than constantly
        // collapsing updates to the top 20 levels only.
        let stream = symbol.lowercased() + "usdt@depth@100ms"
        let urls = [
            "wss://stream.binance.com:9443/ws/\(stream)",
            "wss://stream.binance.com/ws/\(stream)"
        ]
        return urls.compactMap { URL(string: $0) }
    }

    // MARK: - WebSocket lifecycle
    // PRICE CONSISTENCY FIX: Use selected exchange as data source
    private func startWebSocket(for symbol: String, source: DataSource = .binance) {
        #if canImport(UIKit)
        if isInBackground || inWSCooldown() {
            // Do not start WS; ensure REST fallback is running at a reduced rate
            startRESTDepthPolling(symbol: symbol, exchange: selectedExchange)
            return
        }
        #endif
        
        // SESSION-LEVEL CHECK: If this WS source has failed repeatedly in this session,
        // skip WS entirely and use REST polling (which works reliably).
        if isWSDisabledForSession(source: source) {
            startRESTDepthPolling(symbol: symbol, exchange: selectedExchange)
            return
        }

        if source == .binance && !binanceWSEnabled() {
            print("[OrderBook] Binance WS temporarily disabled; trying Coinbase fallback")
            // Fall back to Coinbase WebSocket instead of just REST
            startWebSocket(for: symbol, source: .coinbase)
            return
        }

        wsReconnectWorkItem?.cancel()
        wsReconnectWorkItem = nil

        stopWebSocket()
        self.currentSourceWS = source
        print("[OrderBook] Starting WebSocket for \(symbol.uppercased()) on \(source.rawValue)")
        wsReconnectAttempts = 0
        wsBackoff = 1.0
        self.wsConnectedAt = Date()
        self.lastWSTickAt = Date()

        let product = symbol.uppercased() + "-USD"
        let krakenSymbol = symbol.uppercased() == "BTC" ? "XBT" : symbol.uppercased()

        switch source {
        case .coinbase:
            guard let url = URL(string: "wss://ws-feed.exchange.coinbase.com") else { return }
            var req = URLRequest(url: url)
            req.setValue("https://exchange.coinbase.com", forHTTPHeaderField: "Origin")
            req.setValue("CryptoSage/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
            let task = wsSession.webSocketTask(with: req)
            wsTask = task
            task.resume()

            let sub: [String: Any] = [
                "type": "subscribe",
                "channels": [
                    ["name": "level2", "product_ids": [product]]
                ]
            ]
            if let data = try? JSONSerialization.data(withJSONObject: sub, options: []),
               let text = String(data: data, encoding: .utf8) {
                task.send(.string(text)) { err in if let err = err { print("WS send error:", err.localizedDescription) } }
            }

            schedulePing()
            scheduleWatchdog()
            receiveWebSocket(product: product)

        case .binance:
            let candidates = binanceWSCandidates(for: symbol)
            guard !candidates.isEmpty else { return }
            let index = max(0, binanceWSIndex) % candidates.count
            let url = candidates[index]
            print("[OrderBook] Connecting WS to: \(url.absoluteString) [idx=\(index)]")

            var req = URLRequest(url: url)
            let originHost = (url.host?.contains("binance.us") == true) ? "https://www.binance.us" : "https://www.binance.com"
            req.setValue(originHost, forHTTPHeaderField: "Origin")
            req.setValue("CryptoSage/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
            let task = wsSession.webSocketTask(with: req)
            wsTask = task
            task.resume()

            schedulePing()
            scheduleWatchdog()
            receiveWebSocket(product: product)
            
        case .kraken:
            // Kraken WebSocket for order book
            guard let url = URL(string: "wss://ws.kraken.com") else { 
                print("[OrderBook] Failed to create Kraken WS URL, falling back to REST")
                startRESTDepthPolling(symbol: symbol, exchange: "kraken")
                return 
            }
            var req = URLRequest(url: url)
            req.setValue("https://www.kraken.com", forHTTPHeaderField: "Origin")
            req.setValue("CryptoSage/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
            let task = wsSession.webSocketTask(with: req)
            wsTask = task
            task.resume()
            
            // Kraken subscription message for book depth
            let krakenPair = "\(krakenSymbol)/USD"
            let sub: [String: Any] = [
                "event": "subscribe",
                "pair": [krakenPair],
                "subscription": ["name": "book", "depth": 25]
            ]
            if let data = try? JSONSerialization.data(withJSONObject: sub, options: []),
               let text = String(data: data, encoding: .utf8) {
                task.send(.string(text)) { err in if let err = err { print("[OrderBook] Kraken WS send error:", err.localizedDescription) } }
            }
            
            schedulePing()
            scheduleWatchdog()
            receiveWebSocket(product: krakenPair)
            
        case .kucoin:
            // KuCoin requires a token from their REST API first - use REST polling instead
            // KuCoin's WebSocket requires a dynamic token which adds complexity
            print("[OrderBook] KuCoin using REST polling (WebSocket requires token)")
            startRESTDepthPolling(symbol: symbol, exchange: "kucoin")
            return
        }
        if self.bids.isEmpty && self.asks.isEmpty { self.startRESTDepthPolling(symbol: symbol, exchange: selectedExchange) }
    }

    private func stopWebSocket() {
        wsPingTimer?.invalidate(); wsPingTimer = nil
        wsWatchdogTimer?.invalidate(); wsWatchdogTimer = nil
        wsReconnectWorkItem?.cancel(); wsReconnectWorkItem = nil
        publishTimer?.cancel(); publishTimer = nil
        wsTask?.cancel(with: .goingAway, reason: nil)
        wsTask = nil
        lastWSTickAt = .distantPast
    }

    private func schedulePing() {
        self.wsPingTimer?.invalidate()
        let t = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.wsTask?.sendPing { _ in }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        self.wsPingTimer = t
    }

    private func scheduleWatchdog() {
        self.wsWatchdogTimer?.invalidate()
        
        // PERFORMANCE FIX v25: Adaptive watchdog interval.
        // Previous behavior: fires every 2s regardless of failure count, causing rapid
        // noteWSFailure() escalation (7 failures in 14s → 128s backoff + retry churn).
        // New behavior: increase watchdog interval as failures accumulate to reduce overhead.
        let watchdogInterval: TimeInterval = wsFailureCount >= 5 ? 10 : (wsFailureCount >= 2 ? 5 : 2)
        
        let t = Timer(timeInterval: watchdogInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                guard self.isRealtimeActive else { return }
                let sinceConnect = Date().timeIntervalSince(self.wsConnectedAt)
                let gap = Date().timeIntervalSince(self.lastWSTickAt)
                let initialGrace: TimeInterval = 8
                guard sinceConnect > initialGrace else { return }
                
                // PERFORMANCE FIX v25: When Binance is geo-blocked, don't keep trying
                // to reconnect to Binance WS. Just stay on Coinbase REST/WS fallback.
                let isGeoBlocked = UserDefaults.standard.bool(forKey: "BinanceGlobalGeoBlocked")

                if gap > 3 {
                    self.wsReconnectAttempts += 1
                    self.noteWSFailure()

                    // Ensure REST fallback is running while WS is unhealthy
                    self.startRESTDepthPolling(symbol: self.currentSymbol)

                    // Exponential backoff for reconnect attempts
                    self.wsBackoff = min(max(self.wsBackoff, 1.5) * 1.2, self.wsBackoffMax)

                    // Log once per watchdog pass
                    self.log("watchdog.inactive", "[OrderBook] WS inactive (\(Int(gap))s). Attempt #\(self.wsReconnectAttempts) on \(self.currentSourceWS)", minInterval: 5)

                    // After prolonged stall, fully tear down and rotate candidate before scheduling reconnect
                    // PRICE CONSISTENCY FIX: Binance is primary, Coinbase is fallback
                    if gap > 10 {
                        self.stopWebSocket()
                        if self.currentSourceWS == .binance {
                            // PERFORMANCE FIX v25: If geo-blocked, skip Binance entirely
                            if isGeoBlocked {
                                self.currentSourceWS = .coinbase
                                self.binanceWSIndex = 0
                            } else {
                                // rotate Binance candidate first, then fall back to Coinbase if all fail
                                self.binanceWSIndex += 1
                                self.saveWSIndex(for: self.currentSymbol)
                                let candidates = self.binanceWSCandidates(for: self.currentSymbol)
                                if self.binanceWSIndex >= candidates.count {
                                    // Tried all Binance endpoints, fall back to Coinbase
                                    print("[OrderBook] All Binance WS endpoints failed; falling back to Coinbase")
                                    self.currentSourceWS = .coinbase
                                    self.binanceWSIndex = 0
                                }
                            }
                        } else {
                            // Currently on Coinbase fallback, try returning to Binance
                            // PERFORMANCE FIX v25: Don't retry Binance if geo-blocked
                            if !isGeoBlocked && self.binanceWSEnabled() {
                                print("[OrderBook] Retrying Binance depth WS after Coinbase stall…")
                                self.currentSourceWS = .binance
                                self.binanceWSIndex = 0
                            } else {
                                self.log("watchdog.coinbase.stay", "[OrderBook] Staying on Coinbase fallback (Binance \(isGeoBlocked ? "geo-blocked" : "WS disabled"))", minInterval: 60)
                            }
                        }
                    }

                    // If currently in cooldown, do not try to restart yet; keep REST polling
                    if self.inWSCooldown() { return }
                    
                    // PERFORMANCE FIX v25: After many failures, stop trying WS entirely
                    // and just rely on REST polling (which is already running as fallback)
                    if self.wsFailureCount >= 10 {
                        self.log("watchdog.rest.only", "[OrderBook] WS failed \(self.wsFailureCount) times; relying on REST polling only", minInterval: 120)
                        // Reschedule with slower interval
                        self.scheduleWatchdog()
                        return
                    }

                    // Schedule a reconnect instead of immediate restart to avoid tight loops
                    let delay = max(1.0, self.wsBackoff)
                    self.scheduleReconnect(after: delay, symbol: self.currentSymbol)
                    return
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        self.wsWatchdogTimer = t
    }

    private func scheduleReconnect(after seconds: Double, symbol: String) {
        if inWSCooldown() || !isRealtimeActive { return }
        // After repeated WS failures, prefer stable REST-only mode while user remains on screen.
        if wsFailureCount >= 6 && restPollTimer != nil { return }

        let jittered = seconds * Double.random(in: 0.85...1.15)
        wsReconnectWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                guard self.isRealtimeActive else { return }
                self.startWebSocket(for: symbol, source: self.currentSourceWS)
            }
        }
        wsReconnectWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + jittered, execute: work)
    }

    private func receiveWebSocket(product: String) {
        guard let task = wsTask else { return }
        task.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let err):
                Task { @MainActor in
                    guard self.isRealtimeActive else { return }
                    // PERFORMANCE: Rate-limit WS error logs to once per 30s
                    self.log("ws.receive.error", "WS receive error: \(err.localizedDescription)", minInterval: 30)
                    let nserr = err as NSError
                    if self.currentSourceWS == .binance {
                        if (nserr.domain == NSURLErrorDomain && nserr.code == -1011) ||
                           (nserr.domain == NSPOSIXErrorDomain) ||
                           (nserr.domain == NSURLErrorDomain && (nserr.code == -1004 || nserr.code == -1001)) {
                            let disableFor: TimeInterval = 60 * 20
                            self.binanceWSDisabledUntil = Date().addingTimeInterval(disableFor)
                            self.log("ws.binance.disabled", "[OrderBook] Disabling Binance WS for \(Int(disableFor))s due to repeated handshake/network errors", minInterval: 60)
                            self.currentSourceWS = .coinbase
                        }
                    }
                    self.noteWSFailure()
                    self.wsReconnectAttempts += 1
                    self.startRESTDepthPolling(symbol: self.currentSymbol)
                    self.wsBackoff = min(self.wsBackoff * 1.8, self.wsBackoffMax)
                    let delay = max(1.0, self.wsBackoff)
                    // Only rotate between exchanges if Binance WS is still enabled.
                    // When Binance is disabled (geo-blocked/network error), stay on Coinbase
                    // to avoid escalating the circuit-breaker with doomed reconnect attempts.
                    if self.binanceWSEnabled() {
                        if self.wsReconnectAttempts % 2 == 0 {
                            self.currentSourceWS = (self.currentSourceWS == .binance) ? .coinbase : .binance
                        }
                        if self.currentSourceWS == .binance {
                            self.binanceWSIndex += 1
                            self.saveWSIndex(for: self.currentSymbol)
                        }
                    } else {
                        // Binance WS disabled — force Coinbase and don't schedule reconnect,
                        // REST polling is already active as fallback.
                        self.currentSourceWS = .coinbase
                    }
                    self.scheduleReconnect(after: delay, symbol: self.currentSymbol)
                }
                return
            case .success(let msg):
                Task { @MainActor in
                    // PERFORMANCE FIX: Throttle message processing to prevent excessive main thread work
                    // which causes "Message send exceeds rate-limit threshold" system warnings
                    let now = CACurrentMediaTime()
                    let shouldProcess = (now - self.lastWSMessageProcessedAt) >= self.wsMessageMinInterval
                    
                    if shouldProcess {
                        self.lastWSMessageProcessedAt = now
                        self.lastWSTickAt = Date()
                        switch msg {
                        case .string(let text):
                            if let data = text.data(using: .utf8) {
                                switch self.currentSourceWS {
                                case .coinbase:
                                    self.handleCoinbaseWSMessage(data: data)
                                case .binance:
                                    self.handleBinanceWSMessage(data: data)
                                case .kraken:
                                    self.handleKrakenWSMessage(data: data)
                                case .kucoin:
                                    // KuCoin uses REST polling
                                    break
                                }
                            }
                        case .data(let data):
                            switch self.currentSourceWS {
                            case .coinbase:
                                self.handleCoinbaseWSMessage(data: data)
                            case .binance:
                                self.handleBinanceWSMessage(data: data)
                            case .kraken:
                                self.handleKrakenWSMessage(data: data)
                            case .kucoin:
                                // KuCoin uses REST polling
                                break
                            }
                        @unknown default:
                            break
                        }
                    }
                    // Always continue receiving (but may skip processing)
                    self.receiveWebSocket(product: product)
                }
            }
        }
    }

    private struct L2Snapshot: Decodable { let type: String; let product_id: String; let bids: [[String]]; let asks: [[String]] }
    private struct L2Update: Decodable { let type: String; let product_id: String; let changes: [[String]] }

    private func handleCoinbaseWSMessage(data: Data) {
        stopRESTDepthPolling()
        if let snap = try? JSONDecoder().decode(L2Snapshot.self, from: data), snap.type == "snapshot" {
            let expected = self.currentSymbol.uppercased() + "-USD"
            guard snap.product_id == expected else { return }
            var b: [String: String] = [:]
            var a: [String: String] = [:]
            for arr in snap.bids { if arr.count >= 2 { b[arr[0]] = arr[1] } }
            for arr in snap.asks { if arr.count >= 2 { a[arr[0]] = arr[1] } }
            bookBids = b; bookAsks = a
            trimInMemoryBook()
            wsBackoff = 1.0
            lastWSTickAt = Date()
            wsReconnectAttempts = 0
            noteWSSuccess()
            markUsingWS()
            schedulePublish()
            return
        }
        if let upd = try? JSONDecoder().decode(L2Update.self, from: data), upd.type == "l2update" {
            let expected = self.currentSymbol.uppercased() + "-USD"
            guard upd.product_id == expected else { return }
            for change in upd.changes {
                guard change.count >= 3 else { continue }
                let side = change[0]
                let price = change[1]
                let size  = change[2]
                if side == "buy" {
                    if size == "0" { bookBids.removeValue(forKey: price) } else { bookBids[price] = size }
                } else {
                    if size == "0" { bookAsks.removeValue(forKey: price) } else { bookAsks[price] = size }
                }
            }
            trimInMemoryBook()
            wsBackoff = 1.0
            lastWSTickAt = Date()
            wsReconnectAttempts = 0
            noteWSSuccess()
            markUsingWS()
            schedulePublish()
            return
        }
    }

    private struct BinanceDepth: Decodable {
        let e: String?
        let b: [[String]]?
        let a: [[String]]?
    }
    
    private struct BinancePartialDepth: Decodable { let lastUpdateId: Int?; let bids: [[String]]?; let asks: [[String]]? }

    private func handleBinanceWSMessage(data: Data) {
        stopRESTDepthPolling()
        let decoder = JSONDecoder()

        var didApply = false

        // 1) Try Partial Book Depth (depth5/10/20) — fields: lastUpdateId, bids, asks
        if let partial = try? decoder.decode(BinancePartialDepth.self, from: data), (partial.bids != nil || partial.asks != nil) {
            if let bidsArr = partial.bids {
                for arr in bidsArr where arr.count >= 2 {
                    let price = arr[0]
                    let size  = arr[1]
                    if size == "0" || size == "0.00000000" { bookBids.removeValue(forKey: price) }
                    else { bookBids[price] = size }
                }
            }
            if let asksArr = partial.asks {
                for arr in asksArr where arr.count >= 2 {
                    let price = arr[0]
                    let size  = arr[1]
                    if size == "0" || size == "0.00000000" { bookAsks.removeValue(forKey: price) }
                    else { bookAsks[price] = size }
                }
            }
            didApply = true
        }

        // 2) Try Diff Depth Update (depth@100ms) — fields: b, a
        if !didApply, let depth = try? decoder.decode(BinanceDepth.self, from: data) {
            if let bidsArr = depth.b {
                for arr in bidsArr where arr.count >= 2 {
                    let price = arr[0]
                    let size  = arr[1]
                    if size == "0" || size == "0.00000000" { bookBids.removeValue(forKey: price) }
                    else { bookBids[price] = size }
                }
            }
            if let asksArr = depth.a {
                for arr in asksArr where arr.count >= 2 {
                    let price = arr[0]
                    let size  = arr[1]
                    if size == "0" || size == "0.00000000" { bookAsks.removeValue(forKey: price) }
                    else { bookAsks[price] = size }
                }
            }
            didApply = true
        }

        // If neither decoder matched, ignore silently (could be ping/other message)
        guard didApply else { return }

        trimInMemoryBook()
        wsBackoff = 1.0
        lastWSTickAt = Date()
        wsReconnectAttempts = 0
        noteWSSuccess()
        markUsingWS()
        schedulePublish()
    }
    
    // MARK: - Kraken WebSocket Handler
    /// Handles Kraken WebSocket order book messages
    /// Kraken sends: [channelID, {"bs": [[price, volume, timestamp], ...], "as": [[price, volume, timestamp], ...]}, "book-25", "XBT/USD"]
    /// Or updates: [channelID, {"b": [[price, volume, timestamp, "r"]], "a": [...]}, "book-25", "XBT/USD"]
    private func handleKrakenWSMessage(data: Data) {
        stopRESTDepthPolling()
        
        // Try to parse as JSON array (Kraken sends arrays, not objects)
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return }
        
        // Check if it's a subscription confirmation or heartbeat
        if let dict = json as? [String: Any] {
            if let event = dict["event"] as? String {
                if event == "subscriptionStatus" {
                    print("[OrderBook][Kraken] Subscription confirmed")
                }
                // Ignore heartbeats, system status, etc.
                return
            }
        }
        
        // Parse order book data (comes as an array)
        guard let arr = json as? [Any], arr.count >= 2 else { return }
        
        // Find the book data (it's a dictionary in the array)
        var bookData: [String: Any]? = nil
        for item in arr {
            if let dict = item as? [String: Any] {
                bookData = dict
                break
            }
        }
        
        guard let book = bookData else { return }
        
        var didApply = false
        
        // Handle snapshot (bs = bids snapshot, as = asks snapshot)
        if let bidsSnap = book["bs"] as? [[Any]] {
            bookBids.removeAll()
            for entry in bidsSnap where entry.count >= 2 {
                let price = String(describing: entry[0])
                let volume = String(describing: entry[1])
                if volume != "0" && volume != "0.00000000" {
                    bookBids[price] = volume
                }
            }
            didApply = true
        }
        
        if let asksSnap = book["as"] as? [[Any]] {
            bookAsks.removeAll()
            for entry in asksSnap where entry.count >= 2 {
                let price = String(describing: entry[0])
                let volume = String(describing: entry[1])
                if volume != "0" && volume != "0.00000000" {
                    bookAsks[price] = volume
                }
            }
            didApply = true
        }
        
        // Handle updates (b = bids update, a = asks update)
        if let bidsUpdate = book["b"] as? [[Any]] {
            for entry in bidsUpdate where entry.count >= 2 {
                let price = String(describing: entry[0])
                let volume = String(describing: entry[1])
                if volume == "0" || volume == "0.00000000" {
                    bookBids.removeValue(forKey: price)
                } else {
                    bookBids[price] = volume
                }
            }
            didApply = true
        }
        
        if let asksUpdate = book["a"] as? [[Any]] {
            for entry in asksUpdate where entry.count >= 2 {
                let price = String(describing: entry[0])
                let volume = String(describing: entry[1])
                if volume == "0" || volume == "0.00000000" {
                    bookAsks.removeValue(forKey: price)
                } else {
                    bookAsks[price] = volume
                }
            }
            didApply = true
        }
        
        guard didApply else { return }
        
        trimInMemoryBook()
        wsBackoff = 1.0
        lastWSTickAt = Date()
        wsReconnectAttempts = 0
        noteWSSuccess()
        markUsingWS()
        schedulePublish()
    }

    private func startRESTDepthPolling(symbol: String, exchange: String? = nil) {
        let normalized = symbol.uppercased()
        let exchangeID = exchange?.lowercased() ?? "binance"
        if self.restPollTimer != nil && self.restPollingSymbol == normalized { return }
        let shouldLog = !(self.restPollTimer != nil && self.restPollingSymbol == normalized)
        stopRESTDepthPolling()
        self.restPollingSymbol = normalized
        self.markUsingREST()
        // PERFORMANCE: Rate-limit REST polling logs
        if shouldLog { log("rest.start", "[OrderBook] Starting REST depth polling for \(normalized) on \(exchangeID)", minInterval: 30) }
        if !self.restEnabled() {
            if shouldLog { log("rest.disabled", "[OrderBook] REST polling temporarily disabled (cooldown) for \(normalized)", minInterval: 30) }
            return
        }

        if self.bids.isEmpty && self.asks.isEmpty {
            self.isLoading = true
            // RELIABILITY FIX: Use faster initial polling when order book is empty
            self.restPollInterval = 0.3  // 300ms for cold start, will back off on success
        }

        // Reset success streak when (re)starting fallback
        self.restSuccessStreak = 0

        let base = normalized
        var urls: [URL] = []
        
        // Build URL candidates based on selected exchange - prioritize selected exchange first
        switch exchangeID {
        case "kraken":
            let krakenSymbol = base == "BTC" ? "XBT" : base
            if let u = URL(string: "https://api.kraken.com/0/public/Depth?pair=\(krakenSymbol)USD&count=50") { urls.append(u) }
            // Fallback to other exchanges
            // PERFORMANCE FIX: Limit Coinbase L2 to 50 levels (was unlimited, fetching 14K+ entries)
            if let cb = URL(string: "https://api.exchange.coinbase.com/products/\(base)-USD/book?level=2&limit=50") { urls.append(cb) }
            
        case "kucoin":
            if let u = URL(string: "https://api.kucoin.com/api/v1/market/orderbook/level2_20?symbol=\(base)-USDT") { urls.append(u) }
            // Fallback to other exchanges
            // PERFORMANCE FIX: Limit Coinbase L2 to 50 levels
            if let cb = URL(string: "https://api.exchange.coinbase.com/products/\(base)-USD/book?level=2&limit=50") { urls.append(cb) }
            
        case "coinbase":
            // PERFORMANCE FIX: Limit Coinbase L2 to 50 levels (was unlimited, fetching 14K+ entries)
            if let cb = URL(string: "https://api.exchange.coinbase.com/products/\(base)-USD/book?level=2&limit=50") { urls.append(cb) }
            // Fallback to Binance (prefer US if geo-blocked)
            if self.binanceHTTPEnabled() {
                // BINANCE-US-FIX: Binance.US is shut down - use global mirror
                let isGeoBlocked = UserDefaults.standard.bool(forKey: "BinanceGlobalGeoBlocked")
                if isGeoBlocked {
                    if let u = URL(string: "https://api4.binance.com/api/v3/depth?symbol=\(base)USDT&limit=50") { urls.append(u) }
                } else {
                    if let u = URL(string: "https://api.binance.com/api/v3/depth?symbol=\(base)USDT&limit=50") { urls.append(u) }
                }
            }
            
        default: // binance
            if self.binanceHTTPEnabled() {
                // BINANCE-US-FIX: Binance.US is shut down - use global mirrors only
                let isGeoBlocked = UserDefaults.standard.bool(forKey: "BinanceGlobalGeoBlocked")
                if isGeoBlocked {
                    if let u = URL(string: "https://api4.binance.com/api/v3/depth?symbol=\(base)USDT&limit=50") { urls.append(u) }
                    if let u = URL(string: "https://api4.binance.com/api/v3/depth?symbol=\(base)USD&limit=50") { urls.append(u) }
                } else {
                    if let u = URL(string: "https://api.binance.com/api/v3/depth?symbol=\(base)USDT&limit=50") { urls.append(u) }
                    if let u = URL(string: "https://api4.binance.com/api/v3/depth?symbol=\(base)USDT&limit=50") { urls.append(u) }
                    if let u = URL(string: "https://api.binance.com/api/v3/depth?symbol=\(base)USD&limit=50") { urls.append(u) }
                }
            }
            // PERFORMANCE FIX: Limit Coinbase L2 to 50 levels
            if let cb = URL(string: "https://api.exchange.coinbase.com/products/\(base)-USD/book?level=2&limit=50") { urls.append(cb) }
        }
        
        self.restCandidatesCache = urls

        func discoverWorkingEndpoint(completion: @escaping (URL?) -> Void) {
            func tryNext(_ index: Int) {
                if index >= self.restCandidatesCache.count { completion(nil); return }
                let url = self.restCandidatesCache[(self.restIndex + index) % self.restCandidatesCache.count]
                // PERFORMANCE FIX v20: Skip Binance probes when already known-blocked.
                // Previously fired HTTP requests to Binance even when BinanceGlobalGeoBlocked was set,
                // wasting a round-trip just to get a 451 back.
                // FIX v5.0.3: Also skip when permanently blocked or HTTP is disabled
                if url.host?.contains("binance") == true && (self.binancePermanentlyBlocked || UserDefaults.standard.bool(forKey: "BinanceGlobalGeoBlocked") || !self.binanceHTTPEnabled()) {
                    return tryNext(index + 1)
                }
                var req = URLRequest(url: url)
                req.timeoutInterval = 3
                URLSession.shared.dataTask(with: req) { data, resp, err in
                    if let http = resp as? HTTPURLResponse, http.statusCode == 451, (url.host?.contains("binance") == true) {
                        Task { @MainActor in
                            self.binanceHTTPDisabledUntil = Date().addingTimeInterval(600)
                            self.binanceGeoBlockCount += 1
                            print("[OrderBook][REST] Discovery 451 from \(url.host ?? "?"); disabling Binance HTTP for 600s (count: \(self.binanceGeoBlockCount))")
                            // FIX v5.0.3: After 3+ geo-blocks, permanently disable Binance for this session
                            if self.binanceGeoBlockCount >= 3 && !self.binancePermanentlyBlocked {
                                self.binancePermanentlyBlocked = true
                                print("[OrderBook] 🛑 Binance permanently blocked for this session after \(self.binanceGeoBlockCount) geo-blocks")
                            }
                            // FIX v5.0.3: Purge Binance URLs from cache on discovery 451
                            self.restCandidatesCache.removeAll { $0.host?.contains("binance") == true }
                        }
                        Task { @MainActor in tryNext(index + 1) }
                        return
                    }
                    if let err = err {
                        print("[OrderBook][REST] discovery error: \(url.host ?? "?") — \(err.localizedDescription)")
                        Task { @MainActor in tryNext(index + 1) }
                        return
                    }
                    guard let http = resp as? HTTPURLResponse else {
                        print("[OrderBook][REST] discovery no HTTP resp for \(url)")
                        Task { @MainActor in tryNext(index + 1) }
                        return
                    }
                    guard (200...299).contains(http.statusCode), let data = data, data.count > 0 else {
                        print("[OrderBook][REST] discovery bad status=\(http.statusCode) for \(url)")
                        Task { @MainActor in tryNext(index + 1) }
                        return
                    }
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], json["bids"] != nil || json["asks"] != nil {
                        completion(url); return
                    }
                    print("[OrderBook][REST] discovery parse fail for \(url)")
                    Task { @MainActor in tryNext(index + 1) }
                }.resume()
            }
            tryNext(0)
        }

        func performPoll() {
            guard self.isRealtimeActive else { return }
            // SCALABILITY: Use Firebase proxy when enabled (after repeated direct API failures)
            if self.useFirebaseProxy {
                if !self.firebaseProxyEnabledNow() {
                    self.log("firebase.cooldown", "[OrderBook][Firebase] proxy cooldown active; skipping this poll", minInterval: 20)
                    return
                }
                self.fetchViaFirebaseProxy(symbol: symbol)
                return
            }
            
            let makeRequest: (URL) -> Void = { url in
                var req = URLRequest(url: url)
                req.timeoutInterval = 4
                URLSession.shared.dataTask(with: req) { data, resp, err in
                    if let http = resp as? HTTPURLResponse, http.statusCode == 451, (url.host?.contains("binance") == true) {
                        DispatchQueue.main.async {
                            self.binanceHTTPDisabledUntil = Date().addingTimeInterval(600)
                            self.binanceGeoBlockCount += 1
                            print("[OrderBook][REST] Poll 451 from \(url.host ?? "?"); disabling Binance HTTP for 600s (count: \(self.binanceGeoBlockCount))")
                            // FIX v5.0.3: After 3+ geo-blocks, permanently disable Binance for this session
                            if self.binanceGeoBlockCount >= 3 && !self.binancePermanentlyBlocked {
                                self.binancePermanentlyBlocked = true
                                print("[OrderBook] 🛑 Binance permanently blocked for this session after \(self.binanceGeoBlockCount) geo-blocks")
                            }
                            // SCALABILITY: Enable Firebase proxy on geo-block
                            self.enableFirebaseProxyMode()
                            // FIX v5.0.3: Purge Binance URLs from candidate cache so URL
                            // rotation can never re-select a known-blocked endpoint.
                            self.restCandidatesCache.removeAll { $0.host?.contains("binance") == true }
                            // PERFORMANCE FIX: Limit Coinbase L2 to 50 levels
                            if let cb = URL(string: "https://api.exchange.coinbase.com/products/\(base)-USD/book?level=2&limit=50") {
                                self.restDepthURL = cb
                            }
                            // Reset index after purge
                            if !self.restCandidatesCache.isEmpty {
                                self.restIndex = 0
                            }
                        }
                        return
                    }
                    if let err = err {
                        DispatchQueue.main.async {
                            print("[OrderBook][REST] poll error: \(err.localizedDescription)")
                            self.restErrorStreak += 1
                            self.restSuccessStreak = 0
                            self.restPollInterval = min(3.0, 0.9 * pow(1.4, Double(self.restErrorStreak)))
                            // FIX v5.0.3: Use safe rotation that skips disabled Binance URLs
                            self.rotateToNextValidURL()
                            if self.restErrorStreak >= 5 {
                                // SCALABILITY: Switch to Firebase proxy after repeated failures
                                self.enableFirebaseProxyMode()
                                let disableFor = min(120.0, 15.0 * pow(1.5, Double(self.restErrorStreak - 4)))
                                self.restDisabledUntil = Date().addingTimeInterval(disableFor)
                                print("[OrderBook][REST] disabling direct REST for \(Int(disableFor))s, using Firebase proxy")
                            }
                        }
                        return
                    }
                    guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode), let data = data else {
                        DispatchQueue.main.async {
                            print("[OrderBook][REST] poll bad response for \(url.absoluteString)")
                            self.restErrorStreak += 1
                            self.restSuccessStreak = 0
                            self.restPollInterval = min(3.0, 0.9 * pow(1.4, Double(self.restErrorStreak)))
                            // FIX v5.0.3: Use safe rotation that skips disabled Binance URLs
                            self.rotateToNextValidURL()
                            if self.restErrorStreak >= 5 {
                                // SCALABILITY: Switch to Firebase proxy after repeated failures
                                self.enableFirebaseProxyMode()
                                let disableFor = min(120.0, 15.0 * pow(1.5, Double(self.restErrorStreak - 4)))
                                self.restDisabledUntil = Date().addingTimeInterval(disableFor)
                                print("[OrderBook][REST] disabling direct REST for \(Int(disableFor))s, using Firebase proxy")
                            }
                        }
                        return
                    }
                    // Determine exchange from URL for proper parsing
                    let urlExchange: String = {
                        let host = url.host ?? ""
                        if host.contains("kraken") { return "kraken" }
                        if host.contains("kucoin") { return "kucoin" }
                        if host.contains("coinbase") { return "coinbase" }
                        return "binance"
                    }()
                    
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        var b: [String: String] = [:]
                        var a: [String: String] = [:]
                        
                        // Parse based on exchange format
                        switch urlExchange {
                        case "kraken":
                            // Kraken format: {"result": {"XXBTZUSD": {"bids": [...], "asks": [...]}}}
                            if let result = json["result"] as? [String: Any],
                               let pairData = result.values.first as? [String: Any] {
                                if let bidsArr = pairData["bids"] as? [[Any]] {
                                    for arr in bidsArr where arr.count >= 2 { 
                                        b[String(describing: arr[0])] = String(describing: arr[1]) 
                                    }
                                }
                                if let asksArr = pairData["asks"] as? [[Any]] {
                                    for arr in asksArr where arr.count >= 2 { 
                                        a[String(describing: arr[0])] = String(describing: arr[1]) 
                                    }
                                }
                            }
                            
                        case "kucoin":
                            // KuCoin format: {"data": {"bids": [...], "asks": [...]}}
                            if let dataObj = json["data"] as? [String: Any] {
                                if let bidsArr = dataObj["bids"] as? [[Any]] {
                                    for arr in bidsArr where arr.count >= 2 { 
                                        b[String(describing: arr[0])] = String(describing: arr[1]) 
                                    }
                                }
                                if let asksArr = dataObj["asks"] as? [[Any]] {
                                    for arr in asksArr where arr.count >= 2 { 
                                        a[String(describing: arr[0])] = String(describing: arr[1]) 
                                    }
                                }
                            }
                            
                        default: // binance, coinbase (standard format)
                            if let bidsArr = json["bids"] as? [[Any]] {
                                for arr in bidsArr where arr.count >= 2 { 
                                    b[String(describing: arr[0])] = String(describing: arr[1]) 
                                }
                            }
                            if let asksArr = json["asks"] as? [[Any]] {
                                for arr in asksArr where arr.count >= 2 { 
                                    a[String(describing: arr[0])] = String(describing: arr[1]) 
                                }
                            }
                        }
                        
                        DispatchQueue.main.async {
                            self.bookBids = b
                            self.bookAsks = a
                            self.trimInMemoryBook()
                            self.log("rest.updated", "[OrderBook] REST depth updated (\(symbol.uppercased())) from \(urlExchange) bids=\(b.count) asks=\(a.count)", minInterval: 3)
                            self.restErrorStreak = 0
                            self.restSuccessStreak += 1
                            // PERFORMANCE FIX: Increased min from 2.0s to 3.0s and max from 5s to 8s
                            // On successive successes, gradually back off polling interval up to 8s
                            // This dramatically reduces network/CPU load while order book is stable
                            self.restPollInterval = min(8.0, max(3.0, 2.0 * pow(1.3, Double(self.restSuccessStreak))))
                            self.schedulePublish()
                            self.restDisabledUntil = .distantPast
                        }
                    } else {
                        DispatchQueue.main.async {
                            print("[OrderBook][REST] poll JSON parse failed for \(url.host ?? "?")")
                            self.restErrorStreak += 1
                            self.restSuccessStreak = 0
                            self.restPollInterval = min(3.0, 0.9 * pow(1.4, Double(self.restErrorStreak)))
                            // FIX v5.0.3: Use safe rotation that skips disabled Binance URLs
                            self.rotateToNextValidURL()
                            if self.restErrorStreak >= 5 {
                                let disableFor = min(120.0, 15.0 * pow(1.5, Double(self.restErrorStreak - 4)))
                                self.restDisabledUntil = Date().addingTimeInterval(disableFor)
                                print("[OrderBook][REST] disabling REST polling for \(Int(disableFor))s due to error streak=\(self.restErrorStreak)")
                            }
                        }
                    }
                }.resume()
            }

            DispatchQueue.main.async {
                if let url = self.restDepthURL {
                    // FIX v5.0.3: Skip Binance URLs when HTTP is disabled (geo-blocked).
                    // Previously, URL rotation could re-select a Binance URL from the cache
                    // even after receiving HTTP 451, causing an infinite polling loop.
                    if url.host?.contains("binance") == true && !self.binanceHTTPEnabled() {
                        // Try to find a non-Binance URL from the cache
                        if let fallback = self.restCandidatesCache.first(where: { $0.host?.contains("binance") != true }) {
                            self.restDepthURL = fallback
                            makeRequest(fallback)
                        } else if let cb = URL(string: "https://api.exchange.coinbase.com/products/\(base)-USD/book?level=2&limit=50") {
                            self.restDepthURL = cb
                            makeRequest(cb)
                        }
                        return
                    }
                    makeRequest(url)
                }
            }
        }

        func scheduleNextPoll() {
            let jitter = Double.random(in: 0.85...1.15)
            // RELIABILITY FIX: Allow faster polling (0.3s) for cold start when order book is empty
            let minInterval = (self.bids.isEmpty && self.asks.isEmpty) ? 0.3 : 0.6
            let base = max(minInterval, min(3.0, self.restPollInterval))
            #if canImport(UIKit)
            let multiplier: Double = (self.isInBackground || self.inWSCooldown()) ? 2.5 : 1.0
            #else
            let multiplier: Double = 1.0
            #endif
            let interval = base * multiplier * jitter

            DispatchQueue.main.async {
                self.restPollTimer?.invalidate()
                let t = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
                    guard let self = self else { return }
                    DispatchQueue.main.async {
                        // PERFORMANCE FIX v17: Skip poll during scroll to reduce main thread work
                        // The order book data can wait until scroll ends
                        // CRITICAL FIX: Always allow polling when order book is empty
                        // Otherwise the initial data never loads if the user scrolls on the Trading tab
                        let hasNoData = self.bids.isEmpty && self.asks.isEmpty
                        if !hasNoData && ScrollStateManager.shared.shouldBlockHeavyOperation() {
                            scheduleNextPoll() // Reschedule without polling
                            return
                        }
                        performPoll()
                        scheduleNextPoll()
                    }
                }
                RunLoop.main.add(t, forMode: .common)
                self.restPollTimer = t
            }
        }

        DispatchQueue.main.async {
            if self.restDepthURL == nil {
                discoverWorkingEndpoint { url in
                    DispatchQueue.main.async {
                        if let url = url {
                            self.restDepthURL = url
                        } else if !self.restCandidatesCache.isEmpty {
                            // CRASH FIX: Clamp restIndex to valid bounds before accessing
                            self.restIndex = self.restIndex % self.restCandidatesCache.count
                            self.restDepthURL = self.restCandidatesCache[self.restIndex]
                        } else {
                            print("[OrderBook][REST] No REST candidates available - cannot start polling")
                            return
                        }
                        if let url = self.restDepthURL { print("[OrderBook][REST] using \(url.absoluteString)") }
                        // Immediate first poll for faster cold start
                        performPoll()
                        scheduleNextPoll()
                    }
                }
            } else {
                // Immediate first poll if we already have an endpoint
                performPoll()
                scheduleNextPoll()
            }
        }
    }

    private func stopRESTDepthPolling() {
        self.restPollTimer?.invalidate()
        self.restPollTimer = nil
        self.restDepthURL = nil
        self.restPollingSymbol = ""
    }
    
    // MARK: - Firebase Proxy Fallback (Scalable)
    
    /// Fetch order book via Firebase proxy - prevents rate limiting at scale
    /// This is used as a fallback when direct API calls fail repeatedly
    private func fetchViaFirebaseProxy(symbol: String) {
        Task { @MainActor in
            do {
                // EXCHANGE SELECTION: Pass selected exchange to Firebase proxy
                let response = try await FirebaseService.shared.getOrderBookDepth(symbol: symbol, limit: 50, exchange: selectedExchange)
                
                // Parse response and update book
                var b: [String: String] = [:]
                var a: [String: String] = [:]
                
                for bid in response.bids where bid.count >= 2 {
                    b[bid[0]] = bid[1]
                }
                for ask in response.asks where ask.count >= 2 {
                    a[ask[0]] = ask[1]
                }
                
                self.bookBids = b
                self.bookAsks = a
                self.trimInMemoryBook()
                
                self.log("firebase.updated", "[OrderBook][Firebase] depth updated (\(symbol.uppercased())) bids=\(b.count) asks=\(a.count) source=\(response.source ?? "?")", minInterval: 3)
                
                // Reset error tracking on success
                self.firebaseProxyErrorCount = 0
                self.restErrorStreak = 0
                self.restSuccessStreak += 1
                self.restPollInterval = min(5.0, max(2.0, 1.5 * pow(1.25, Double(self.restSuccessStreak))))
                self.schedulePublish()
                self.restDisabledUntil = .distantPast
                self.firebaseProxyDisabledUntil = .distantPast
                
            } catch {
                self.log("firebase.error", "[OrderBook][Firebase] proxy error: \(error.localizedDescription)", minInterval: 10)
                self.firebaseProxyErrorCount += 1
                let cooldown = min(60.0, pow(2.0, Double(min(self.firebaseProxyErrorCount + 1, 6))))
                self.firebaseProxyDisabledUntil = Date().addingTimeInterval(cooldown)
                
                // After too many Firebase errors, switch back to direct API
                if self.firebaseProxyErrorCount >= self.firebaseProxyMaxErrors {
                    self.useFirebaseProxy = false
                    self.firebaseProxyErrorCount = 0
                    self.restDisabledUntil = Date().addingTimeInterval(8)
                    print("[OrderBook] Switching back to direct API after Firebase errors")
                }
            }
        }
    }
    
    /// Switch to Firebase proxy mode after repeated direct API failures
    /// This provides scalable fallback when Binance/Coinbase block or rate limit
    private func enableFirebaseProxyMode() {
        guard !useFirebaseProxy else { return }
        useFirebaseProxy = true
        firebaseProxyErrorCount = 0
        print("[OrderBook] Enabled Firebase proxy mode for scalability")
    }

    private func trimInMemoryBook() {
        let limit = maxLevelsPerSide

        // Trim bids to top N (highest prices)
        let sortedBidKeys: [String] = bookBids.keys.compactMap { priceStr in
            if let d = Double(priceStr) { return (priceStr, d) } else { return nil }
        }.sorted { $0.1 > $1.1 }.map { $0.0 }
        if sortedBidKeys.count > limit {
            let keep = Set(sortedBidKeys.prefix(limit))
            let keysSnapshot = Array(bookBids.keys)
            for k in keysSnapshot where !keep.contains(k) {
                bookBids.removeValue(forKey: k)
            }
        }

        // Trim asks to top N (lowest prices)
        let sortedAskKeys: [String] = bookAsks.keys.compactMap { priceStr in
            if let d = Double(priceStr) { return (priceStr, d) } else { return nil }
        }.sorted { $0.1 < $1.1 }.map { $0.0 }
        if sortedAskKeys.count > limit {
            let keep = Set(sortedAskKeys.prefix(limit))
            let keysSnapshot = Array(bookAsks.keys)
            for k in keysSnapshot where !keep.contains(k) {
                bookAsks.removeValue(forKey: k)
            }
        }
    }

    private func schedulePublish() {
        // Mark that we have fresh book data to publish; the timer will coalesce bursts.
        pendingPublish = true
        if publishTimer == nil {
            let t = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
            // PERFORMANCE FIX: Reduced from 20Hz (50ms) to 2Hz (500ms)
            // This significantly reduces UI update frequency while still providing responsive order book
            // The visual difference is minimal but the performance impact is substantial
            t.schedule(deadline: .now() + .milliseconds(500), repeating: .milliseconds(500))
            t.setEventHandler { [weak self] in
                guard let self = self else { return }
                if self.pendingPublish {
                    self.pendingPublish = false
                    self.publishTopOfBook()
                }
            }
            publishTimer = t
            t.resume()
        }
    }

    private func publishTopOfBook() {
        let top = maxRowsToPublish

        // Build sorted bids (highest first) preserving original price strings for stability
        var bidTriples: [(Double, String, String)] = [] // (priceDouble, priceString, qty)
        bidTriples.reserveCapacity(bookBids.count)
        for (priceStr, qty) in bookBids {
            if let d = Double(priceStr) { bidTriples.append((d, priceStr, qty)) }
        }
        bidTriples.sort { $0.0 > $1.0 }
        let bidSlice = bidTriples.prefix(top)
        let newBids: [OrderBookEntry] = bidSlice.map { OrderBookEntry(price: $0.1, qty: $0.2) }

        // Build sorted asks (lowest first) preserving original price strings for stability
        var askTriples: [(Double, String, String)] = []
        askTriples.reserveCapacity(bookAsks.count)
        for (priceStr, qty) in bookAsks {
            if let d = Double(priceStr) { askTriples.append((d, priceStr, qty)) }
        }
        askTriples.sort { $0.0 < $1.0 }
        let askSlice = askTriples.prefix(top)
        let newAsks: [OrderBookEntry] = askSlice.map { OrderBookEntry(price: $0.1, qty: $0.2) }

        // If nothing to show, skip publishing
        if newBids.isEmpty && newAsks.isEmpty { return }

        // Deduplicate to avoid multiple updates per frame; only publish if content changed
        if newBids == lastPublishedBids && newAsks == lastPublishedAsks { return }
        
        // PERFORMANCE FIX: Skip @Published updates during scroll to prevent view re-renders
        // This is the most frequently called path (WebSocket/REST polling every 2s)
        // BUT: Always publish when bids are empty (initial load) so order book doesn't stay blank
        if ScrollStateManager.shared.shouldBlockHeavyOperation() && !self.bids.isEmpty {
            return
        }

        // Already on @MainActor (publishTimer runs on main queue), assign directly
        self.isLoading = false
        self.bids = newBids
        self.asks = newAsks
        self.lastPublishedBids = newBids
        self.lastPublishedAsks = newAsks
        self.saveCacheThrottled(for: self.currentSymbol)

        // PRICE ACCURACY: Calculate mid-price from best bid/ask for real-time price display.
        // This supplements the CoinGecko/Firebase price on the Trading screen, giving it
        // sub-second accuracy instead of the 30-60 second CoinGecko polling delay.
        if let bestBidPrice = Double(newBids.first?.price ?? ""),
           let bestAskPrice = Double(newAsks.first?.price ?? ""),
           bestBidPrice > 0, bestAskPrice > 0,
           bestAskPrice >= bestBidPrice,
           bestBidPrice.isFinite, bestAskPrice.isFinite {
            let spread = (bestAskPrice - bestBidPrice) / bestBidPrice
            // Only update mid-price if spread is reasonable (<1%) — indicates valid market
            if spread < 0.01 {
                let newMid = (bestBidPrice + bestAskPrice) / 2.0
                // Avoid micro-updates that trigger unnecessary view redraws
                if abs(newMid - self.midPrice) / max(self.midPrice, 1) > 0.00005 {
                    self.midPrice = newMid
                    self.midPriceUpdatedAt = Date()
                }
            }
        }

        // NOTE: Order book bid/ask prices are exchange-specific (Binance, Coinbase, etc.)
        // and are intentionally NOT fed into LivePriceManager or MarketViewModel.bestPrice().
        // All displayed prices (Market, Watchlist, Home, Trading header) come from CoinGecko
        // via Firebase/Firestore for consistency. The order book shows the exchange's own
        // bid/ask spread, which naturally differs from the aggregated CoinGecko price.
        // HOWEVER: The midPrice property IS used by TradeViewModel to supplement the display
        // price on the Trading screen specifically, where real-time accuracy matters most.
    }
}

// MARK: - OrderBookViewModel (base/quote/data source helpers)
extension OrderBookViewModel {
    var baseCurrency: String { currentSymbol.uppercased() }
    // Keep the chart quote stable so the WebView doesn't reload on source toggles.
    var chartQuoteCurrency: String { "USDT" }
    // For backward compatibility, map quoteCurrency to the stable chart quote.
    var quoteCurrency: String { chartQuoteCurrency }
    // Use the explicit transport state rather than checking timers, which can flap often.
    var dataSourceLabel: String { transportKind == .rest ? "REST" : "WS" }
    var showDepthSkeleton: Bool { isLoading && bids.isEmpty && asks.isEmpty }

    var bestBid: String? { bids.first?.price }
    var bestAsk: String? { asks.first?.price }
    var hasRecentWSTick: Bool { Date().timeIntervalSince(lastWSTickAt) < 5 }
    
    // MARK: - Order Book Imbalance (Buy/Sell Pressure)
    /// Returns imbalance ratio from -1 (all sell pressure) to +1 (all buy pressure)
    var imbalanceRatio: Double {
        let bidDepth = bids.prefix(10).reduce(0.0) { sum, entry in
            sum + (Double(entry.qty) ?? 0)
        }
        let askDepth = asks.prefix(10).reduce(0.0) { sum, entry in
            sum + (Double(entry.qty) ?? 0)
        }
        let total = bidDepth + askDepth
        guard total > 0 else { return 0 }
        return (bidDepth - askDepth) / total
    }
    
    /// Buy pressure as percentage (0-100)
    var buyPressurePercent: Double {
        return (imbalanceRatio + 1) / 2 * 100
    }
    
    // MARK: - Price Level Aggregation
    /// Aggregates order book entries by price grouping (tick size)
    /// - Parameters:
    ///   - entries: Raw order book entries
    ///   - tickSize: Price grouping size (e.g., 1.0 for $1 buckets)
    ///   - isBids: True for bids (rounds down), false for asks (rounds up)
    /// - Returns: Aggregated entries with combined quantities
    func aggregateByPriceLevel(_ entries: [OrderBookEntry], tickSize: Double, isBids: Bool) -> [OrderBookEntry] {
        guard tickSize > 0 else { return entries }
        
        // Group quantities by rounded price
        var aggregated: [Double: Double] = [:] // price -> total qty
        
        for entry in entries {
            guard let price = Double(entry.price), let qty = Double(entry.qty) else { continue }
            
            // Round to tick size: bids round down, asks round up
            let roundedPrice: Double
            if isBids {
                roundedPrice = (price / tickSize).rounded(.down) * tickSize
            } else {
                roundedPrice = (price / tickSize).rounded(.up) * tickSize
            }
            
            aggregated[roundedPrice, default: 0] += qty
        }
        
        // Sort and convert back to entries
        let sorted = aggregated.sorted { a, b in
            isBids ? (a.key > b.key) : (a.key < b.key)
        }
        
        return sorted.map { price, qty in
            // Format price to appropriate decimal places based on tick size
            let priceStr: String
            if tickSize >= 1 {
                priceStr = String(format: "%.0f", price)
            } else if tickSize >= 0.1 {
                priceStr = String(format: "%.1f", price)
            } else {
                priceStr = String(format: "%.2f", price)
            }
            
            // Format quantity with up to 8 decimal places, trimming trailing zeros
            let qtyStr = formatQuantity(qty)
            
            return OrderBookEntry(price: priceStr, qty: qtyStr)
        }
    }
    
    /// Helper to format quantity with appropriate precision
    private func formatQuantity(_ qty: Double) -> String {
        if qty >= 1000 {
            return String(format: "%.2f", qty)
        } else if qty >= 1 {
            return String(format: "%.4f", qty)
        } else {
            return String(format: "%.8f", qty).replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
        }
    }
    
    // MARK: - Cumulative Depth Calculation
    /// Calculates cumulative depth up to each index
    /// - Parameters:
    ///   - entries: Order book entries
    ///   - upToIndex: Index to calculate cumulative depth up to
    /// - Returns: Cumulative notional value (price * qty) up to and including the index
    func cumulativeDepth(for entries: [OrderBookEntry], upToIndex: Int) -> Double {
        guard upToIndex >= 0, upToIndex < entries.count else { return 0 }
        return entries.prefix(upToIndex + 1).reduce(0) { sum, entry in
            let price = Double(entry.price) ?? 0
            let qty = Double(entry.qty) ?? 0
            return sum + (price * qty)
        }
    }
    
    /// Returns array of cumulative depths for all entries
    func cumulativeDepths(for entries: [OrderBookEntry]) -> [Double] {
        var cumulative: Double = 0
        return entries.map { entry in
            let price = Double(entry.price) ?? 0
            let qty = Double(entry.qty) ?? 0
            cumulative += price * qty
            return cumulative
        }
    }
    
    /// Maximum quantity in the visible order book (for size-weighted coloring)
    var maxBidQty: Double {
        bids.prefix(40).compactMap { Double($0.qty) }.max() ?? 1
    }
    
    var maxAskQty: Double {
        asks.prefix(40).compactMap { Double($0.qty) }.max() ?? 1
    }
    
    /// Average quantity for whale detection
    var avgBidQty: Double {
        let qtys = bids.prefix(40).compactMap { Double($0.qty) }
        guard !qtys.isEmpty else { return 1 }
        return qtys.reduce(0, +) / Double(qtys.count)
    }
    
    var avgAskQty: Double {
        let qtys = asks.prefix(40).compactMap { Double($0.qty) }
        guard !qtys.isEmpty else { return 1 }
        return qtys.reduce(0, +) / Double(qtys.count)
    }
}

