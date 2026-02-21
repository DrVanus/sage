//
//  ChartDataPoint.swift
//  CSAI1
//
//  Created by DM on 4/23/25.
//

// Live window duration in seconds for the live chart interval
private let liveWindow: TimeInterval = 300
import Foundation
import SwiftUI
import Charts
import Combine
import UIKit
import os
// moved date/axis helpers to dedicated files

// MARK: - Quote preference (Auto / USD / USDT)
private enum QuotePreferenceMode: String {
    case auto, usd, usdt
}
private struct QuotePreferenceStore {
    private static let key = "QuotePreference"
    static var mode: QuotePreferenceMode {
        get {
            let raw = UserDefaults.standard.string(forKey: key) ?? "auto"
            return QuotePreferenceMode(rawValue: raw) ?? .auto
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }
    /// Returns whether USD should be preferred over USDT for the current context.
    /// - Parameter isUSUser: If true (Binance.US or US region), we bias to USD when in `.auto` mode.
    static func prefersUSD(isUSUser: Bool) -> Bool {
        switch mode {
        case .usd:  return true
        case .usdt: return false
        case .auto: return isUSUser
        }
    }
}

// MARK: - Binance helpers (symbol normalization, endpoints, candidates)
private enum ExchangeAPI: String {
    case binance   = "https://api.binance.com"
    // BINANCE-US-FIX: Binance.US is shut down - use global mirror instead
    case binanceUS = "https://api4.binance.com"
}

private func normalizeToBinanceSymbol(_ raw: String) -> String {
    // Trim, uppercase, and remove separators like "/" and "-"
    raw.trimmingCharacters(in: .whitespacesAndNewlines)
        .uppercased()
        .replacingOccurrences(of: "/", with: "")
        .replacingOccurrences(of: "-", with: "")
}

private func candidateSymbols(for raw: String, preferUSD: Bool = false) -> [String] {
    let base = normalizeToBinanceSymbol(raw)
    // If caller already provided a suffix, keep it and add the alternate as fallback
    if base.hasSuffix("USDT") || base.hasSuffix("USD") {
        let root = base.replacingOccurrences(of: "USDT", with: "").replacingOccurrences(of: "USD", with: "")
        let usdt = root + "USDT"
        let usd  = root + "USD"
        return preferUSD ? [usd, usdt] : [usdt, usd]
    } else {
        let usdt = base + "USDT"
        let usd  = base + "USD"
        return preferUSD ? [usd, usdt] : [usdt, usd]
    }
}

// MARK: – Data Model
struct ChartDataPoint: Identifiable, Equatable {
    // PERFORMANCE FIX: Use stable ID based on timestamp instead of random UUID.
    // UUID() creates a new ID each time data is loaded from cache, fetched from API,
    // or resampled, causing SwiftUI's Chart to tear down and rebuild every LineMark/AreaMark
    // from scratch instead of smoothly diffing. A deterministic ID lets SwiftUI recognize
    // unchanged points and only update what actually changed — eliminating the visual
    // "break" during timeframe switches.
    var id: Double { date.timeIntervalSince1970 }
    let date: Date
    let close: Double
    let volume: Double

    init(date: Date, close: Double, volume: Double = 0) {
        self.date = date
        self.close = close
        self.volume = volume
    }

    // Custom Equatable comparing only meaningful fields (date, close, volume).
    // Without this, Swift's synthesized Equatable would use the default memberwise
    // comparison which is correct here, but being explicit ensures future-proofing
    // and documents the intent.
    static func == (lhs: ChartDataPoint, rhs: ChartDataPoint) -> Bool {
        lhs.date == rhs.date && lhs.close == rhs.close && lhs.volume == rhs.volume
    }
}

// MARK: – Interval Enum
enum ChartInterval: String, CaseIterable {
    case live = "LIVE"
    case oneMin = "1m", fiveMin = "5m", fifteenMin = "15m", thirtyMin = "30m"
    case oneHour = "1H", fourHour = "4H", oneDay = "1D", oneWeek = "1W"
    case oneMonth = "1M", threeMonth = "3M", sixMonth = "6M", oneYear = "1Y", threeYear = "3Y", all = "ALL"
    
    /// Case-unique key for disk cache filenames.
    /// Prevents collision between "1m" (oneMin) and "1M" (oneMonth) on case-insensitive
    /// filesystems like macOS APFS default, where both map to the same file.
    var cacheSafeKey: String {
        switch self {
        case .live:        return "live"
        case .oneMin:      return "1min"
        case .fiveMin:     return "5min"
        case .fifteenMin:  return "15min"
        case .thirtyMin:   return "30min"
        case .oneHour:     return "1hour"
        case .fourHour:    return "4hour"
        case .oneDay:      return "1day"
        case .oneWeek:     return "1week"
        case .oneMonth:    return "1month"
        case .threeMonth:  return "3month"
        case .sixMonth:    return "6month"
        case .oneYear:     return "1year"
        case .threeYear:   return "3year"
        case .all:         return "all"
        }
    }
    
    var binanceInterval: String {
        // HIGH-RESOLUTION DATA: Fetch granular candles for detailed price action
        // This matches professional trading apps (TradingView, Coinbase Pro)
        switch self {
        case .live:         return "1m"
        case .oneMin:       return "1m"
        case .fiveMin:      return "1m"   // 1m candles for 5m view (5x more detail)
        case .fifteenMin:   return "5m"   // 5m candles for 15m view (3x more detail)
        case .thirtyMin:    return "5m"   // 5m candles for 30m view (6x more detail)
        case .oneHour:      return "15m"  // 15m candles for 1H view (4x more detail)
        case .fourHour:     return "30m"  // 30m candles for 4H view (8x more detail)
        case .oneDay:       return "5m"   // 5m candles for 1D view (high detail)
        case .oneWeek:      return "15m"  // 15m candles for 1W view (4x more detail)
        case .oneMonth:     return "4h"   // 4h candles for 1M view (6x more detail than daily)
        case .threeMonth:   return "1d"   // daily candles for 3M timeframe
        case .sixMonth:     return "1d"   // daily candles for 6M timeframe
        case .oneYear:      return "1d"   // daily candles for 1Y timeframe
        case .threeYear:    return "1w"   // weekly candles for 3 years
        case .all:          return "1w"   // weekly candles for all-time view
        }
    }
    
    /// Number of candles to display on the chart (visible portion)
    /// HIGH-RESOLUTION: Increased to accommodate granular candle data for detailed price action
    var visibleCandles: Int {
        switch self {
        case .live:       return Int(liveWindow / 60)  // 5 minutes of 1m candles = 5
        case .oneMin:     return 90    // 90 one-minute candles = 1.5 hours
        case .fiveMin:    return 480   // 480 one-minute candles = 8 hours (1m candles)
        case .fifteenMin: return 360   // 360 five-minute candles = 30 hours (5m candles)
        case .thirtyMin:  return 432   // 432 five-minute candles = 36 hours (5m candles)
        case .oneHour:    return 288   // 288 fifteen-minute candles = 3 days (15m candles)
        case .fourHour:   return 504   // 504 thirty-minute candles = 10.5 days (30m candles)
        case .oneDay:     return 288   // 288 five-minute candles = 24 hours (5m candles)
        case .oneWeek:    return 672   // 672 fifteen-minute candles = 7 days (15m candles)
        case .oneMonth:   return 270   // 270 four-hour candles = 45 days (4h candles)
        case .threeMonth: return 120   // 120 daily candles = 120 days
        case .sixMonth:   return 180   // 180 daily candles = 6 months
        case .oneYear:    return 365   // 365 daily candles = 1 year
        case .threeYear:  return 156   // 156 weekly candles = exactly 3 years
        case .all:        return 520   // ~10 years of weekly candles
        }
    }
    
    /// Total candles to fetch from API (visible + warm-up buffer for indicators)
    /// All values must stay under Binance's 1000 candle limit
    var binanceLimit: Int {
        // Add warm-up buffer for indicator calculations (SMA, EMA, BB, etc.)
        let warmupBuffer = 50
        switch self {
        case .live:       return Int(liveWindow / 60) + warmupBuffer  // 5 min window = 5 candles + buffer
        case .oneMin:     return visibleCandles + warmupBuffer  // 140
        case .fiveMin:    return visibleCandles + warmupBuffer  // 530 (1m candles, high detail)
        case .fifteenMin: return visibleCandles + warmupBuffer  // 410 (5m candles)
        case .thirtyMin:  return visibleCandles + warmupBuffer  // 482 (5m candles)
        case .oneHour:    return visibleCandles + warmupBuffer  // 338 (15m candles)
        case .fourHour:   return visibleCandles + warmupBuffer  // 554 (30m candles)
        case .oneDay:     return visibleCandles + warmupBuffer  // 338 (5m candles)
        case .oneWeek:    return visibleCandles + warmupBuffer  // 722 (15m candles)
        case .oneMonth:   return visibleCandles + warmupBuffer  // 320 (4h candles)
        case .threeMonth: return visibleCandles + warmupBuffer  // 170
        case .sixMonth:   return visibleCandles + warmupBuffer  // 230
        case .oneYear:    return visibleCandles + warmupBuffer  // 415
        case .threeYear:  return visibleCandles + warmupBuffer  // 206 (156 + 50)
        case .all:        return 1000  // Maximum for all-time view (Binance limit)
        }
    }
    
    var hideCrosshairTime: Bool {
        switch self {
        case .oneMonth, .threeMonth, .sixMonth, .oneYear, .threeYear, .all:
            return true
        default:
            return false
        }
    }

    /// Duration of one candle in seconds (matches binanceInterval for high-resolution data)
    var secondsPerInterval: TimeInterval {
        switch self {
        case .live, .oneMin:      return 60          // 1 minute
        case .fiveMin:            return 60          // 1m candles for 5m view
        case .fifteenMin:         return 300         // 5m candles for 15m view
        case .thirtyMin:          return 300         // 5m candles for 30m view
        case .oneHour:            return 900         // 15m candles for 1H view
        case .fourHour:           return 1800        // 30m candles for 4H view
        case .oneDay:             return 300         // 5m candles for 1D view
        case .oneWeek:            return 900         // 15m candles for 1W view
        case .oneMonth:           return 14400       // 4h candles for 1M view
        case .threeMonth:         return 86_400      // daily candles
        case .sixMonth:           return 86_400      // daily candles
        case .oneYear:            return 86_400      // daily candles
        case .threeYear:          return 604_800     // weekly candles
        case .all:                return 604_800     // weekly candles
        }
    }
    
    /// Computed lookback window based on visible candles (for backward compatibility)
    /// Returns explicit durations for all timeframes to ensure proper X-domain calculation
    var lookbackSeconds: TimeInterval {
        switch self {
        case .live:
            return liveWindow
        case .oneYear:
            return 365 * 86_400  // 365 days
        case .threeYear:
            return 3 * 365 * 86_400  // ~3 years (1095 days)
        case .all:
            // Use data bounds for ALL - return 0 to signal "use data extent"
            return 0
        default:
            // Calculate from visible candles * seconds per candle
            return TimeInterval(visibleCandles) * secondsPerInterval
        }
    }
    
    /// The actual time window in seconds that the percentage badge should represent
    /// This differs from lookbackSeconds which controls how much data is fetched/displayed
    var badgeTimeWindowSeconds: TimeInterval {
        switch self {
        case .live:       return liveWindow  // ~5 minutes
        case .oneMin:     return 60          // 1 minute
        case .fiveMin:    return 300         // 5 minutes
        case .fifteenMin: return 900         // 15 minutes
        case .thirtyMin:  return 1800        // 30 minutes
        case .oneHour:    return 3600        // 1 hour
        case .fourHour:   return 14400       // 4 hours
        case .oneDay:     return 86400       // 24 hours
        case .oneWeek:    return 604800      // 7 days
        case .oneMonth:   return 2592000     // 30 days
        case .threeMonth: return 7776000     // 90 days
        case .sixMonth:   return 15552000    // 180 days
        case .oneYear:    return 31536000    // 365 days
        case .threeYear:  return 94608000    // 3 years
        case .all:        return 0           // Use full range
        }
    }

    /// Maximum acceptable age for the latest candle on this timeframe.
    /// Used to reject stale source/cache data so each timeframe feels current.
    var maxAllowedDataAge: TimeInterval {
        switch self {
        case .live:         return 2 * 60        // 2 minutes
        case .oneMin:       return 10 * 60       // 10 minutes
        case .fiveMin:      return 20 * 60       // 20 minutes
        case .fifteenMin:   return 45 * 60       // 45 minutes
        case .thirtyMin:    return 1 * 3600      // 1 hour
        case .oneHour:      return 3 * 3600      // 3 hours
        case .fourHour:     return 6 * 3600      // 6 hours
        case .oneDay:       return 6 * 3600      // 6 hours
        case .oneWeek:      return 12 * 3600     // 12 hours
        case .oneMonth:     return 72 * 3600     // 3 days
        case .threeMonth:   return 7 * 86400     // 7 days
        case .sixMonth:     return 7 * 86400     // 7 days
        case .oneYear:      return 14 * 86400    // 14 days
        case .threeYear:    return 30 * 86400    // 30 days
        case .all:          return 45 * 86400    // 45 days
        }
    }
}

// MARK: – ViewModel
@MainActor class CryptoChartViewModel: ObservableObject {
    /// Number of days to always display on the chart for non-live intervals
    private let desiredDays: Int = 7
    /// Extra candles to fetch for indicator warm-up (BB, RSI, etc. need N periods before producing values)
    /// Set to 200 to ensure sufficient warm-up for SMA 200, Bollinger Bands, and other long-period indicators.
    /// This prevents the left-side gap where indicator lines don't start at the chart's left edge.
    private let indicatorWarmupBuffer: Int = 200
    @Published var dataPoints   : [ChartDataPoint] = [] {
        didSet { dataVersion &+= 1 }   // auto-bump on every assignment
    }
    /// Monotonically increasing counter that bumps every time `dataPoints` is replaced.
    /// The view observes this instead of `dataPoints.count` to reliably detect data refreshes
    /// even when the old and new arrays happen to have the same count.
    @Published var dataVersion  : Int = 0
    @Published var isLoading    = false
    @Published var errorMessage : String? = nil
    @Published var volumeScaleMax: Double? = nil
    /// Indicates volume data is stable (fresh API data received, not just cache)
    /// This prevents volume chart from rendering with partial cached data then readjusting
    @Published var volumeDataStable: Bool = false
    
    /// SEAMLESS UX: Indicates a background refresh is in progress (keeps old data visible)
    /// Used when switching timeframes - shows subtle indicator instead of full loading overlay
    @Published var isRefreshing: Bool = false
    
    /// Preferred exchange for data fetching. When "coinbase" is set, the chart fetches from Coinbase first.
    /// For other exchanges (binance, kraken, kucoin), the chart uses the default Binance/Coinbase data sources.
    /// The order book (OrderBookViewModel) fetches directly from the user's selected exchange.
    var preferredExchange: String? = nil
    
    /// Fallback closure called when Coinbase-preferred chart fetch fails.
    /// Triggers the standard Firebase → Binance pipeline as a last resort.
    var coinbaseFallbackClosure: (() -> Void)? = nil
    
    /// When true, the Coinbase-preferred path is bypassed in fetchData.
    /// Set during fallback to Firebase/Binance pipeline to prevent infinite recursion.
    var coinbaseFallbackActive: Bool = false

    // Remember which API worked and which pair we resolved (for live websocket and subsequent calls)
    private var isUS: Bool = false
    private var lastResolvedPair: String? = nil
    private var lastResolvedCoinbaseProduct: String? = nil
    private let prewarmQueue = DispatchQueue(label: "CryptoChartViewModel.prewarm")
    private let prewarmDelay: TimeInterval = 0.35

    private var lastLiveUpdate: Date = .init(timeIntervalSince1970: 0)
    
    // Track current symbol for feeding prices to LivePriceManager's rolling window
    private var currentLiveSymbol: String? = nil

    // Combine throttling for live data
    private var liveSubject = PassthroughSubject<ChartDataPoint, Never>()
    private var cancellables = Set<AnyCancellable>()
    
    // TIMEFRAME SWITCH FIX: Guards live data from corrupting non-live chart data.
    // Set to true when startLive() is called, false when stopLive() is called.
    // The liveSubject sink checks this flag before appending data points.
    private(set) var isLiveModeActive: Bool = false
    // TIMEFRAME SWITCH FIX: Generation counter for live sessions.
    // Incremented every time stopLive() is called. The liveSubject sink captures
    // the current generation at send-time and ignores data from old generations.
    // This prevents stale throttled data (up to 1s delayed) from corrupting the chart.
    private var liveGeneration: Int = 0
    
    // FIX: Timeout timer to prevent infinite loading states
    private var loadingTimeoutWork: DispatchWorkItem? = nil
    private let loadingTimeout: TimeInterval = 10 // PERFORMANCE FIX: Reduced from 20s to 10s for faster feedback
    
    // PERFORMANCE FIX: Auto-retry with exponential backoff
    private(set) var autoRetryCount: Int = 0
    let maxAutoRetries: Int = 3
    private let autoRetryDelays: [TimeInterval] = [2.0, 5.0, 10.0] // Exponential backoff
    @Published var isRetrying: Bool = false  // Shows "Reconnecting..." in UI
    private var pendingRetryWork: DispatchWorkItem? = nil
    private var lastRetrySymbol: String = ""
    private var lastRetryInterval: ChartInterval = .oneDay

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        // FIX: Increased timeouts to prevent premature failures during network congestion
        cfg.timeoutIntervalForRequest  = 15  // Increased from 10
        cfg.timeoutIntervalForResource = 20  // Increased from 10
        cfg.waitsForConnectivity = true
        // FIX: Limit concurrent connections to prevent connection pool exhaustion
        cfg.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: cfg)
    }()
    
    /// FAST WEBSOCKET SESSION: Dedicated URLSession for WebSocket connections with aggressive
    /// timeouts. The WebSocket handshake (HTTP upgrade) should complete in 1-3 seconds on any
    /// reasonable connection. Using the main session's 15-second timeout caused each failed
    /// endpoint to burn 15 seconds before trying the next one. With 4+ Binance endpoints to
    /// cycle through before reaching Coinbase, this meant 40-60 seconds of flat line.
    /// 5-second timeout cuts this to ~20 seconds worst case (4 endpoints × 5s).
    private let wsSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = 5   // Fast fail for WS handshake
        cfg.timeoutIntervalForResource = 8   // Slightly longer for full resource
        cfg.waitsForConnectivity = false     // Don't wait - fail fast to try next endpoint
        cfg.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: cfg)
    }()

    private var liveSocket: URLSessionWebSocketTask? = nil
    private var liveEndpoints: [URL] = []
    private var livePingTimer: Timer? = nil
    private var liveWatchdogTimer: Timer? = nil
    private var currentLiveEndpointIndex: Int = 0
    
    // PARALLEL FAST CONNECT: Coinbase WebSocket opened simultaneously with Binance
    // cycling. Whichever connects first wins. This cuts live startup from 15-25s to 1-2s.
    private var coinbaseFastTrackSocket: URLSessionWebSocketTask? = nil
    
    // RELIABILITY FIX: Track connection state for watchdog grace period
    private var liveWatchdogStartedAt: Date = .distantPast
    private var liveConnectionEstablished: Bool = false
    // SAFETY NET: Timestamp of current live session start. Any data points older than
    // this are from a previous fetch/session and must be trimmed. This catches leaks
    // from code paths that might bypass the isLiveModeActive guard.
    private(set) var liveSessionStartedAt: Date = .distantPast
    // PERFORMANCE FIX: Increased grace period from 15s to 30s for slower networks
    // FAST WS FIX: Reduced from 30s to 15s since wsSession now has 5s timeout per endpoint.
    // Full cycle through all endpoints (4 Binance + 1 Coinbase × 5s) completes in ~25s max.
    private let liveInitialGracePeriod: TimeInterval = 15

    private var fetchSequence: Int = 0

    // PERFORMANCE FIX: Added cache size limit to prevent unbounded memory growth
    // nonisolated(unsafe): These statics are protected by memoryCacheQueue (concurrent + barrier writes)
    nonisolated(unsafe) private static var memoryCache: [String: [ChartDataPoint]] = [:]
    nonisolated(unsafe) private static var memoryCacheAccessOrder: [String] = []  // LRU tracking
    nonisolated private static let memoryCacheMaxSize = 100  // Max 100 chart data sets in memory
    nonisolated private static let memoryCacheQueue = DispatchQueue(label: "CryptoChartViewModel.memoryCache", attributes: .concurrent)
    
    // FIX: In-flight request deduplication to prevent concurrent fetches for the same chart
    // This prevents request flooding when multiple views request the same symbol/interval
    // nonisolated(unsafe): These statics are protected by inflightLock (NSLock)
    nonisolated(unsafe) private static var inflightFetches: [String: Date] = [:]  // key -> start time
    nonisolated private static let inflightLock = NSLock()
    nonisolated private static let inflightMaxAge: TimeInterval = 15  // Consider stale after 15s (reduced from 30s to unblock faster)
    
    /// Check if a fetch is already in progress for this key, and register if not
    private static func registerInflightFetch(key: String) -> Bool {
        inflightLock.lock()
        defer { inflightLock.unlock() }
        
        // Clean up stale entries
        let now = Date()
        inflightFetches = inflightFetches.filter { now.timeIntervalSince($0.value) < inflightMaxAge }
        
        if inflightFetches[key] != nil {
            // Already in flight
            return false
        }
        inflightFetches[key] = now
        return true
    }
    
    /// Mark a fetch as complete
    static func completeInflightFetch(key: String) {
        inflightLock.lock()
        defer { inflightLock.unlock() }
        inflightFetches.removeValue(forKey: key)
    }

    fileprivate struct CachedPoint: Codable { let t: Double; let c: Double; let v: Double }
    
    /// Public accessor for memory cache - enables instant pre-loading in views
    static func getMemoryCache(key: String) -> [ChartDataPoint]? {
        var result: [ChartDataPoint]?
        memoryCacheQueue.sync { result = memoryCache[key] }
        return result
    }

    private let logger = Logger(subsystem: "CryptoSage", category: "CryptoChartViewModel")
    
    // PERFORMANCE: Cached ISO8601 formatter for Coinbase WebSocket timestamps.
    // Avoids allocating a new formatter on every incoming trade message.
    nonisolated(unsafe) private static let coinbaseTimestampFormatter: ISO8601DateFormatter = {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt
    }()

    private var wsBackoffAttempt: Int = 0
    private var wsLastErrorLogAt: Date = .distantPast
    private var wsConsecutiveFailures: Int = 0
    private let wsBackoffMaxDelay: TimeInterval = 30
    
    // RELIABILITY: Maximum total endpoint attempts before giving up entirely
    // This prevents infinite reconnection loops that drain battery and network
    private var wsTotalEndpointAttempts: Int = 0
    private let wsMaxTotalAttempts: Int = 15  // 5 endpoints × 3 cycles max

    func cacheKey(symbol: String, interval: ChartInterval) -> String {
        // CACHE COLLISION FIX: Use case-unique suffix instead of rawValue directly.
        // On case-insensitive filesystems (macOS APFS default), "BTC-1m.json" and
        // "BTC-1M.json" are the SAME file. This caused 1-minute data to be loaded
        // as 1-month data (and vice versa), corrupting chart display.
        // Using unambiguous suffixes prevents this collision.
        return "\(symbol.uppercased())-\(interval.cacheSafeKey)"
    }
    private func cacheDirectory() -> URL {
        // SAFETY FIX: Guard against nil to prevent crash
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            // Fallback to temporary directory if caches unavailable
            return FileManager.default.temporaryDirectory.appendingPathComponent("ChartCache", isDirectory: true)
        }
        let dir = base.appendingPathComponent("ChartCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private func cacheURL(for key: String) -> URL {
        cacheDirectory().appendingPathComponent("\(key).json")
    }
    private func saveCache(points: [ChartDataPoint], key: String) {
        let payload = points.map { CachedPoint(t: $0.date.timeIntervalSince1970, c: $0.close, v: $0.volume) }
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: cacheURL(for: key), options: .atomic)
        }
        // PERFORMANCE FIX: LRU eviction to prevent unbounded memory growth
        Self.memoryCacheQueue.async(flags: .barrier) {
            // Update access order (move key to end = most recently used)
            Self.memoryCacheAccessOrder.removeAll { $0 == key }
            Self.memoryCacheAccessOrder.append(key)
            Self.memoryCache[key] = points
            
            // Evict oldest entries if over limit
            while Self.memoryCache.count > Self.memoryCacheMaxSize,
                  let oldestKey = Self.memoryCacheAccessOrder.first {
                Self.memoryCacheAccessOrder.removeFirst()
                Self.memoryCache.removeValue(forKey: oldestKey)
            }
        }
    }
    func loadCache(key: String) -> [ChartDataPoint]? {
        var mem: [ChartDataPoint]?
        Self.memoryCacheQueue.sync { mem = Self.memoryCache[key] }
        if let mem = mem {
            // PERFORMANCE FIX: Update LRU access order on cache hit
            Self.memoryCacheQueue.async(flags: .barrier) {
                Self.memoryCacheAccessOrder.removeAll { $0 == key }
                Self.memoryCacheAccessOrder.append(key)
            }
            return mem
        }
        let url = cacheURL(for: key)
        guard let data = try? Data(contentsOf: url),
              let arr = try? JSONDecoder().decode([CachedPoint].self, from: data) else { return nil }
        let pts = arr.map { ChartDataPoint(date: Date(timeIntervalSince1970: $0.t), close: $0.c, volume: $0.v) }.sorted { $0.date < $1.date }
        // PERFORMANCE FIX: LRU eviction when loading from disk
        Self.memoryCacheQueue.async(flags: .barrier) {
            Self.memoryCacheAccessOrder.removeAll { $0 == key }
            Self.memoryCacheAccessOrder.append(key)
            Self.memoryCache[key] = pts
            
            while Self.memoryCache.count > Self.memoryCacheMaxSize,
                  let oldestKey = Self.memoryCacheAccessOrder.first {
                Self.memoryCacheAccessOrder.removeFirst()
                Self.memoryCache.removeValue(forKey: oldestKey)
            }
        }
        return pts
    }
    
    /// LIVE MODE SEEDING: Preload cached data for a specific interval to seed the chart
    /// This ensures LIVE mode starts with existing 1m data instead of an empty chart
    /// Returns true if cached data was found and loaded
    func preloadCachedData(symbol: String, interval: ChartInterval) -> Bool {
        // LIVE MODE GUARD: Don't overwrite live WebSocket data with cached candle data
        guard !isLiveModeActive else { return false }
        let key = self.cacheKey(symbol: symbol, interval: interval)
        if let cached = self.loadCache(key: key), cached.count >= 10 {
            self.dataPoints = cached
            self.volumeScaleMax = self.volumeCeiling(from: cached)
            self.isLoading = false
            return true
        }
        return false
    }
    
    /// FIX: Graceful fallback to cached data on network errors
    /// Returns true if fallback succeeded (cached data was found and used)
    private func fallbackToCache(symbol: String, interval: ChartInterval, errorContext: String) -> Bool {
        let key = self.cacheKey(symbol: symbol, interval: interval)
        if let cached = self.loadCache(key: key), !cached.isEmpty {
            self.cancelLoadingTimeout()
            // LIVE MODE GUARD: Don't overwrite live WebSocket data with 1m candle cache.
            // The live chart builds from real-time ticks; replacing them with cached candle
            // closes would re-introduce the price spike. Only update if not in live mode.
            if !self.isLiveModeActive {
                self.dataPoints = cached
            }
            self.volumeScaleMax = self.volumeCeiling(from: cached)
            self.isLoading = false
            // Don't show error message since we have cached data to display
            self.errorMessage = nil
            self.logger.info("[Chart] Fallback to cache for \(key) due to: \(errorContext)")
            // Complete in-flight tracking
            Self.completeInflightFetch(key: key)
            return true
        }
        return false
    }
    
    /// FIX: Show error with in-flight tracking cleanup
    private func showErrorAndComplete(symbol: String, interval: ChartInterval, message: String) {
        let key = self.cacheKey(symbol: symbol, interval: interval)
        self.cancelLoadingTimeout()
        self.errorMessage = message
        self.isLoading = false
        self.isRefreshing = false  // SEAMLESS UX: Clear refresh indicator on error
        Self.completeInflightFetch(key: key)
    }

    init() {
        liveSubject
            .throttle(for: .seconds(1), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] pt in
                guard let self = self else { return }
                // TIMEFRAME SWITCH FIX: Capture the current generation BEFORE the async dispatch.
                // If stopLive() is called between now and when the async block runs,
                // liveGeneration will have been incremented, and this stale point is discarded.
                let capturedGeneration = self.liveGeneration
                // Defer state modifications to avoid "Modifying state during view update"
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    // TIMEFRAME SWITCH FIX: Discard data from old live sessions.
                    // This prevents stale throttled WebSocket data (up to 1s delay)
                    // from corrupting chart data after switching to a non-live timeframe.
                    guard self.isLiveModeActive,
                          capturedGeneration == self.liveGeneration else { return }
                    
                    // NATURAL TRANSITION: Don't adjust seed prices when the first tick arrives.
                    // The chart draws a smooth line from the seed price to the real tick price.
                    // This creates a natural visual transition instead of a jarring Y-domain
                    // shift that makes the chart appear to "jump" or "break". The flat seed
                    // portion scrolls off the left edge naturally within 15-30 seconds as new
                    // ticks accumulate and the live window advances.
                    
                    // SAFETY NET: Remove any data points from before this live session.
                    // This catches leaks from code paths (Firebase, Coinbase, CoinGecko,
                    // direct Binance parse) that might bypass the isLiveModeActive guard
                    // due to timing/race conditions. Only data from the current session
                    // (seed points + WebSocket ticks) should remain.
                    let sessionCutoff = self.liveSessionStartedAt.addingTimeInterval(-35)
                    if self.dataPoints.contains(where: { $0.date < sessionCutoff }) {
                        self.dataPoints.removeAll { $0.date < sessionCutoff }
                    }
                    
                    self.dataPoints.append(pt)
                    // Trim points outside the live window by TIME.
                    let cutoff = pt.date.addingTimeInterval(-liveWindow)
                    self.dataPoints.removeAll { $0.date < cutoff }
                    self.isLoading = false
                }
            }
            .store(in: &cancellables)
    }

    func startLive(symbol: String, preserveExisting: Bool = true) {
        // TIMEFRAME SWITCH FIX: Mark live mode as active so the liveSubject sink accepts data
        isLiveModeActive = true
        
        // Store symbol for feeding prices to LivePriceManager
        currentLiveSymbol = symbol.uppercased()
            .replacingOccurrences(of: "USDT", with: "")
            .replacingOccurrences(of: "USD", with: "")
        
        // Clean up any previous fast-track socket
        coinbaseFastTrackSocket?.cancel(with: .goingAway, reason: nil)
        coinbaseFastTrackSocket = nil
        
        // RELIABILITY FIX: Initialize update timestamp BEFORE async work and watchdog
        // This prevents the watchdog from triggering prematurely during endpoint resolution
        lastLiveUpdate = Date()
        liveConnectionEstablished = false
        
        // LIVE SESSION INIT: Record session start time for the safety net data filter.
        // If existing data is present (count > 3), backdate so the safety net preserves it.
        // Otherwise, use "now" so only fresh WebSocket ticks are kept.
        if preserveExisting, dataPoints.count > 3, let earliest = dataPoints.first?.date {
            liveSessionStartedAt = earliest.addingTimeInterval(-5)
        } else {
            liveSessionStartedAt = Date()
        }
        
        Task {
            let eps = await ExchangeHostPolicy.shared.currentEndpoints()

            // Helper to append /ws and /stream forms to a base URL preserving scheme and port
            func wsCandidates(from base: URL, stream: String) -> [URL] {
                var out: [URL] = []
                if let comp = URLComponents(url: base, resolvingAgainstBaseURL: false) {
                    // /ws/<stream>
                    var c1 = comp
                    let basePath = c1.path.hasSuffix("/") ? String(c1.path.dropLast()) : c1.path
                    c1.path = basePath + "/ws/" + stream
                    if let u1 = c1.url { out.append(u1) }
                    // /stream?streams=<stream>
                    var c2 = comp
                    let basePath2 = c2.path.hasSuffix("/") ? String(c2.path.dropLast()) : c2.path
                    c2.path = basePath2 + "/stream"
                    c2.queryItems = [URLQueryItem(name: "streams", value: stream)]
                    if let u2 = c2.url { out.append(u2) }
                }
                return out
            }

            // Build stream key
            let defaultPair: String = {
                let preferUSD = QuotePreferenceStore.prefersUSD(isUSUser: isUS)
                if isUS || preferUSD {
                    return candidateSymbols(for: symbol, preferUSD: true).first ?? (symbol.uppercased() + "USD")
                } else {
                    return candidateSymbols(for: symbol, preferUSD: false).first ?? (symbol.uppercased() + "USDT")
                }
            }()
            let pair = (lastResolvedPair ?? defaultPair).lowercased()
            let stream = pair + "@trade"

            // Primary endpoints from current policy
            var candidates: [URL] = wsCandidates(from: eps.wsBase, stream: stream)

            // Also append the alternate region as fallback to ensure quick failover
            let altEndpoints: [ExchangeEndpoints] = (eps.wsBase.host?.contains(".us") == true) ? [ExchangeEndpoints.global] : [ExchangeEndpoints.us]
            for alt in altEndpoints {
                candidates.append(contentsOf: wsCandidates(from: alt.wsBase, stream: stream))
            }
            
            // COINBASE FALLBACK: Add Coinbase WebSocket as final fallback when all Binance endpoints fail
            // Coinbase WebSocket is more reliable in US regions where Binance may be geo-blocked
            // URL format: wss://ws-feed.exchange.coinbase.com (subscribe via JSON message)
            if let coinbaseWS = URL(string: "wss://ws-feed.exchange.coinbase.com") {
                candidates.append(coinbaseWS)
            }
            
            // Store the Coinbase product ID for subscription
            let baseSymbol = symbol.uppercased()
                .replacingOccurrences(of: "USDT", with: "")
                .replacingOccurrences(of: "USD", with: "")
            self.coinbaseProductId = baseSymbol + "-USD"

            self.liveEndpoints = candidates

            // PROFESSIONAL: Never show loading animation - keep displaying current data
            // Only clear data if we truly have nothing to show (prevents jarring transitions)
            self.errorMessage = nil
            // NEVER show loading if we have any data - professional app experience
            if !self.dataPoints.isEmpty {
                self.isLoading = false
                // Keep existing data visible while live connects
            } else {
                // Only show loading on truly empty state
                self.isLoading = true
            }
            // Safety timeout - clear loading if still stuck after 3 seconds
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self = self else { return }
                if self.liveSocket != nil && self.dataPoints.isEmpty { self.isLoading = false }
            }

            self.scheduleLivePing()
            self.scheduleLiveWatchdog()
            self.wsBackoffAttempt = 0
            self.wsConsecutiveFailures = 0
            self.wsTotalEndpointAttempts = 0  // Reset total attempts on fresh start
            
            // PARALLEL FAST CONNECT: Start Coinbase WebSocket simultaneously with Binance.
            // Coinbase typically connects in 1-2 seconds, while Binance can take 15-25
            // seconds when geo-blocked (cycling through 4 failed endpoints before reaching
            // Coinbase as the last fallback). By trying both in parallel, the chart gets
            // real live data within 1-2 seconds instead of 15-25 seconds.
            self.startCoinbaseFastTrack()
            
            self.connectLive(at: 0)
        }
    }

    private func connectLive(at index: Int) {
        // TIMEFRAME SWITCH FIX: Do not start new connections if live mode was deactivated
        guard isLiveModeActive else { return }
        
        // RELIABILITY: Track total connection attempts to prevent infinite loops
        wsTotalEndpointAttempts += 1
        
        // Check if we've exhausted maximum total attempts
        if wsTotalEndpointAttempts > wsMaxTotalAttempts {
            self.logger.warning("[LiveWS] Maximum connection attempts (\(self.wsMaxTotalAttempts)) exhausted")
            if self.dataPoints.isEmpty {
                self.errorMessage = "Unable to connect to live stream. Please check your internet connection."
            }
            self.isLoading = false
            self.isRefreshing = false  // SEAMLESS UX: Clear refresh indicator
            self.isRetrying = false
            self.autoRetryCount = 0
            self.wsTotalEndpointAttempts = 0
            return
        }
        
        guard index < liveEndpoints.count else {
            // PERFORMANCE FIX: Auto-retry for live stream failures
            if self.autoRetryCount < self.maxAutoRetries && self.dataPoints.isEmpty {
                self.triggerAutoRetry(symbol: self.lastRetrySymbol, interval: .live)
            } else if self.dataPoints.isEmpty {
                self.errorMessage = "Unable to connect to live stream. Tried all available endpoints."
                self.isLoading = false
                self.isRefreshing = false  // SEAMLESS UX: Clear refresh indicator
                self.isRetrying = false
                self.autoRetryCount = 0
            } else {
                // Have cached data, fail silently
                self.isLoading = false
                self.isRefreshing = false  // SEAMLESS UX: Clear refresh indicator
            }
            return
        }
        currentLiveEndpointIndex = index

        // Cancel any existing socket before reconnecting
        liveSocket?.cancel(with: .goingAway, reason: nil)
        lastLiveUpdate = Date()

        let url = liveEndpoints[index]
        
        // Detect if this is a Coinbase WebSocket endpoint
        let isCoinbase = url.host?.contains("coinbase") == true
        self.isCoinbaseWebSocket = isCoinbase
        
        if isCoinbase {
            // COINBASE FALLBACK: Binance WebSocket failed, using Coinbase as fallback
            print("[LiveWS] 🔄 Binance WS failed - switching to Coinbase WebSocket fallback")
            logger.info("[LiveWS] Using Coinbase WebSocket fallback for \(self.coinbaseProductId)")
            
            // Coinbase requires custom headers and subscription message
            var request = URLRequest(url: url)
            request.setValue("https://exchange.coinbase.com", forHTTPHeaderField: "Origin")
            request.setValue("CryptoSage/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
            liveSocket = wsSession.webSocketTask(with: request)
            liveSocket?.resume()
            
            // Send subscription message for Coinbase WebSocket
            let subscribeMessage: [String: Any] = [
                "type": "subscribe",
                "channels": [
                    ["name": "ticker", "product_ids": [coinbaseProductId]]
                ]
            ]
            if let data = try? JSONSerialization.data(withJSONObject: subscribeMessage),
               let text = String(data: data, encoding: .utf8) {
                liveSocket?.send(.string(text)) { [weak self] error in
                    Task { @MainActor in
                        guard let self = self else { return }
                        if let error = error {
                            self.logger.error("[LiveWS] Coinbase subscribe error: \(error.localizedDescription)")
                        } else {
                            self.logger.debug("[LiveWS] Coinbase subscribed to \(self.coinbaseProductId)")
                        }
                    }
                }
            }
        } else {
            // Standard Binance WebSocket connection
            liveSocket = wsSession.webSocketTask(with: url)
            liveSocket?.resume()
        }
        
        wsConsecutiveFailures = 0
        // Begin receiving; on failure we will try the next endpoint
        receiveLive(currentIndex: index)
    }

    private func receiveLive(currentIndex: Int) {
        // TIMEFRAME SWITCH FIX: Capture generation before async receive callback.
        let capturedGen = self.liveGeneration
        
        liveSocket?.receive { [weak self] result in
            Task { @MainActor in
            guard let self = self else { return }
            // TIMEFRAME SWITCH FIX: Bail if live mode was stopped since enqueue.
            guard self.isLiveModeActive, capturedGen == self.liveGeneration else { return }
            switch result {
            case .failure(let err):
                // Throttle error logs to at most once per 5 seconds
                let now = Date()
                if now.timeIntervalSince(self.wsLastErrorLogAt) > 5 {
                    self.logger.error("WebSocket receive error: \(String(describing: err))")
                    self.wsLastErrorLogAt = now
                }

                // If handshake/HTTP upgrade failed (-1011) or we’re still on .com, try pinning to US for a while
                self.wsConsecutiveFailures += 1
                if self.wsConsecutiveFailures >= 2 {
                    if let url = self.liveEndpoints[safe: currentIndex], url.host?.contains("binance.com") == true {
                        await ExchangeHostPolicy.shared.setRegion(.us, stickyFor: 3600)
                    }
                }

                // FAST FALLBACK FIX: Use short fixed delay when moving to a DIFFERENT endpoint
                // (new host = different service). Only use exponential backoff when retrying the
                // same service. This cuts Coinbase fallback time from ~32s to ~4s.
                let nextIndex = currentIndex + 1
                let currentHost = self.liveEndpoints[safe: currentIndex]?.host ?? ""
                let nextHost = self.liveEndpoints[safe: nextIndex]?.host ?? ""
                let isSameHost = !currentHost.isEmpty && currentHost == nextHost
                
                let delay: TimeInterval
                if isSameHost {
                    // Same host: exponential backoff (retrying same service)
                    self.wsBackoffAttempt += 1
                    let baseDelay = min(pow(2.0, Double(self.wsBackoffAttempt)), self.wsBackoffMaxDelay)
                    let jitter = Double.random(in: 0...0.5)
                    delay = baseDelay + jitter
                } else {
                    // Different host: quick switch (1s) to try next service fast
                    self.wsBackoffAttempt = 0  // Reset backoff for new service
                    delay = 1.0
                }

                DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                    Task { @MainActor in
                        guard let self = self,
                              self.isLiveModeActive,
                              capturedGen == self.liveGeneration else { return }
                        self.connectLive(at: nextIndex)
                    }
                }
                return

            case .success(.data(let data)):
                self.handleLiveData(data)
                self.wsBackoffAttempt = 0

            case .success(.string(let text)):
                if let data = text.data(using: .utf8) {
                    self.handleLiveData(data)
                    self.wsBackoffAttempt = 0
                }

            @unknown default:
                break
            }
            // Keep receiving on the same endpoint (only if still in same live session)
            guard self.isLiveModeActive, capturedGen == self.liveGeneration else { return }
            self.receiveLive(currentIndex: currentIndex)
            } // end Task { @MainActor in
        }
    }

    private func scheduleLivePing() {
        Task { @MainActor in
            self.livePingTimer?.invalidate()
            self.livePingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.liveSocket?.sendPing { _ in }
                }
            }
        }
    }

    private func scheduleLiveWatchdog() {
        Task { @MainActor in
            self.liveWatchdogTimer?.invalidate()
            self.liveWatchdogStartedAt = Date()
            self.liveWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self = self else { return }
                    guard self.liveSocket != nil else { return }
                    
                    // RELIABILITY FIX: Skip watchdog during initial grace period to allow connection to establish
                    let sinceStart = Date().timeIntervalSince(self.liveWatchdogStartedAt)
                    guard sinceStart > self.liveInitialGracePeriod else { return }
                    
                    // RELIABILITY FIX: Don't trigger reconnect until we've received at least one message
                    // TIMEFRAME SWITCH FIX: Bail if live mode was deactivated
                    guard self.isLiveModeActive else { return }
                    guard self.liveConnectionEstablished else { return }
                    
                    let elapsed = Date().timeIntervalSince(self.lastLiveUpdate)
                    if elapsed > 10 {
                        self.connectLive(at: self.currentLiveEndpointIndex + 1)
                    }
                }
            }
        }
    }

    private func invalidateLiveTimers() {
        Task { @MainActor in
            self.livePingTimer?.invalidate()
            self.liveWatchdogTimer?.invalidate()
            self.livePingTimer = nil
            self.liveWatchdogTimer = nil
        }
    }
    
    // MARK: - Coinbase Fast Track (Parallel Connection)
    
    /// Opens a Coinbase WebSocket simultaneously with the Binance endpoint cycling.
    /// Coinbase typically connects in 1-2 seconds, while Binance can take 15-25 seconds
    /// when geo-blocked. Whichever connection delivers data first wins.
    private func startCoinbaseFastTrack() {
        guard let url = URL(string: "wss://ws-feed.exchange.coinbase.com") else { return }
        
        var request = URLRequest(url: url)
        request.setValue("https://exchange.coinbase.com", forHTTPHeaderField: "Origin")
        request.setValue("CryptoSage/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        
        coinbaseFastTrackSocket = wsSession.webSocketTask(with: request)
        coinbaseFastTrackSocket?.resume()
        
        // Subscribe to ticker for the current product
        let subscribe: [String: Any] = [
            "type": "subscribe",
            "channels": [["name": "ticker", "product_ids": [coinbaseProductId]]]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: subscribe),
           let text = String(data: data, encoding: .utf8) {
            coinbaseFastTrackSocket?.send(.string(text)) { [weak self] error in
                Task { @MainActor in
                    if let error = error {
                        self?.logger.error("[LiveWS] Coinbase fast-track subscribe error: \(error.localizedDescription)")
                    }
                }
            }
        }
        
        receiveCoinbaseFastTrack()
    }
    
    private func receiveCoinbaseFastTrack() {
        let capturedGen = self.liveGeneration
        
        coinbaseFastTrackSocket?.receive { [weak self] result in
            Task { @MainActor in
                guard let self = self, self.isLiveModeActive,
                      capturedGen == self.liveGeneration else { return }
                
                // If Binance already connected and is delivering data, cancel fast-track
                if self.liveConnectionEstablished && self.coinbaseFastTrackSocket != nil {
                    self.coinbaseFastTrackSocket?.cancel(with: .goingAway, reason: nil)
                    self.coinbaseFastTrackSocket = nil
                    return
                }
                
                switch result {
                case .success(.string(let text)):
                    if let data = text.data(using: .utf8) {
                        self.handleCoinbaseFastTrackData(data, capturedGen: capturedGen)
                    }
                case .success(.data(let data)):
                    self.handleCoinbaseFastTrackData(data, capturedGen: capturedGen)
                case .failure:
                    // Coinbase fast-track failed — Binance cycling continues as normal
                    self.coinbaseFastTrackSocket = nil
                    return
                @unknown default:
                    break
                }
                
                // Continue receiving
                self.receiveCoinbaseFastTrack()
            }
        }
    }
    
    private func handleCoinbaseFastTrackData(_ data: Data, capturedGen: Int) {
        guard isLiveModeActive, capturedGen == liveGeneration else { return }
        
        // Parse Coinbase ticker message
        guard let msg = try? JSONDecoder().decode(CoinbaseTickerMessage.self, from: data),
              msg.type == "ticker",
              let priceStr = msg.price,
              let price = Double(priceStr),
              price > 0 else {
            // Non-ticker message (subscription confirmation, heartbeat) — ignore
            return
        }
        
        // FAST-TRACK WON: Coinbase connected first. Promote it to the main socket.
        if !liveConnectionEstablished {
            logger.info("[LiveWS] Coinbase fast-track connected first — promoting to main socket")
            
            // Cancel the Binance sequential cycling socket
            liveSocket?.cancel(with: .goingAway, reason: nil)
            
            // Increment generation to invalidate ALL in-flight Binance receive callbacks.
            // Without this, stale Binance failure callbacks could trigger connectLive()
            // and overwrite the now-working Coinbase socket.
            liveGeneration &+= 1
            
            // Promote fast-track socket to main liveSocket
            liveSocket = coinbaseFastTrackSocket
            coinbaseFastTrackSocket = nil
            isCoinbaseWebSocket = true
            liveConnectionEstablished = true
            lastLiveUpdate = Date()
            
            // Start the regular receiveLive loop on the promoted socket.
            // The fast-track receive loop will die on next iteration because
            // coinbaseFastTrackSocket is now nil.
            receiveLive(currentIndex: 0)
        }
        
        // Parse timestamp (use cached formatter for performance)
        var timestamp = Date()
        if let timeStr = msg.time {
            if let parsed = Self.coinbaseTimestampFormatter.date(from: timeStr) {
                timestamp = parsed
            }
        }
        
        // Feed to the same pipeline as regular live data
        let pt = ChartDataPoint(date: timestamp, close: price)
        liveSubject.send(pt)
        lastLiveUpdate = Date()
        
        // Feed price to LivePriceManager
        if let sym = currentLiveSymbol, !sym.isEmpty {
            LivePriceManager.shared.update(symbol: sym, price: price, source: .coinbase)
        }
    }

    // helper to parse and append a live data point
    private func handleLiveData(_ data: Data) {
        // TIMEFRAME SWITCH FIX: Bail out immediately if live mode was deactivated.
        // WebSocket callbacks can arrive on background threads after stopLive() was called.
        guard isLiveModeActive else { return }
        
        // COINBASE WEBSOCKET: Parse Coinbase ticker messages
        if isCoinbaseWebSocket {
            if let msg = try? JSONDecoder().decode(CoinbaseTickerMessage.self, from: data) {
                // Skip non-ticker messages (subscriptions, heartbeat, etc.)
                guard msg.type == "ticker", let priceStr = msg.price, let price = Double(priceStr) else {
                    // Log subscription confirmation but don't treat as failure
                    if msg.type == "subscriptions" {
                        logger.debug("[LiveWS] Coinbase subscription confirmed")
                        liveConnectionEstablished = true
                    }
                    return
                }
                
                // VALIDATION: Skip invalid prices (must be positive)
                guard price > 0 else { return }
                
                // Parse timestamp or use current time
                // PERFORMANCE: Use cached static formatter instead of allocating on every message
                var timestamp = Date()
                if let timeStr = msg.time {
                    if let parsed = Self.coinbaseTimestampFormatter.date(from: timeStr) {
                        timestamp = parsed
                    }
                }
                
                let pt = ChartDataPoint(date: timestamp, close: price)
                liveConnectionEstablished = true
                lastLiveUpdate = Date()
                liveSubject.send(pt)
                
                // Feed price to LivePriceManager with Coinbase source
                if let sym = currentLiveSymbol, !sym.isEmpty {
                    LivePriceManager.shared.update(symbol: sym, price: price, source: .coinbase)
                }
                return
            }
            return
        }
        
        // BINANCE WEBSOCKET: Try to decode bare trade message first
        if let msg = try? JSONDecoder().decode(TradeMessage.self, from: data),
           let price = Double(msg.p), price > 0 {  // VALIDATION: Price must be positive
            let pt = ChartDataPoint(date: Date(timeIntervalSince1970: msg.T / 1000), close: price)
            // RELIABILITY FIX: Mark connection as established on first successful message
            liveConnectionEstablished = true
            lastLiveUpdate = Date()
            // Cancel Coinbase fast-track if still running — Binance won
            if coinbaseFastTrackSocket != nil {
                coinbaseFastTrackSocket?.cancel(with: .goingAway, reason: nil)
                coinbaseFastTrackSocket = nil
            }
            // Send to throttled pipeline (1/sec) — no additional rate-limiting here.
            // The liveSubject throttle handles deduplication, removing the previous
            // double-throttle that could reduce update rate to 1 per 2 seconds.
            liveSubject.send(pt)
            // PRICE CONSISTENCY FIX: Feed price to LivePriceManager with Binance source
            if let sym = currentLiveSymbol, !sym.isEmpty {
                LivePriceManager.shared.update(symbol: sym, price: price, source: .binance)
            }
            return
        }
        // Try to decode streamed envelope { stream, data: { ... } }
        if let env = try? JSONDecoder().decode(StreamEnvelope.self, from: data),
           let price = Double(env.data.p), price > 0 {  // VALIDATION: Price must be positive
            let pt = ChartDataPoint(date: Date(timeIntervalSince1970: env.data.T / 1000), close: price)
            // RELIABILITY FIX: Mark connection as established on first successful message
            liveConnectionEstablished = true
            lastLiveUpdate = Date()
            // Cancel Coinbase fast-track if still running — Binance won
            if coinbaseFastTrackSocket != nil {
                coinbaseFastTrackSocket?.cancel(with: .goingAway, reason: nil)
                coinbaseFastTrackSocket = nil
            }
            liveSubject.send(pt)
            // PRICE CONSISTENCY FIX: Feed price to LivePriceManager with Binance source
            if let sym = currentLiveSymbol, !sym.isEmpty {
                LivePriceManager.shared.update(symbol: sym, price: price, source: .binance)
            }
            return
        }
    }

    func stopLive() {
        // TIMEFRAME SWITCH FIX: Deactivate live mode and increment generation FIRST,
        // before any other cleanup. This ensures any in-flight throttled liveSubject
        // data is immediately discarded by the sink, preventing chart corruption.
        isLiveModeActive = false
        liveGeneration &+= 1
        
        liveSocket?.cancel(with: .goingAway, reason: nil)
        liveSocket = nil
        // Cancel Coinbase fast-track if still running
        coinbaseFastTrackSocket?.cancel(with: .goingAway, reason: nil)
        coinbaseFastTrackSocket = nil
        invalidateLiveTimers()
        currentLiveEndpointIndex = 0
        // RELIABILITY FIX: Reset connection state for clean restart
        liveConnectionEstablished = false
        isCoinbaseWebSocket = false
        // Reset WebSocket retry counters for clean state
        wsBackoffAttempt = 0
        wsConsecutiveFailures = 0
        wsTotalEndpointAttempts = 0
    }

    /// Reset resolved exchange routing when switching to a new symbol
    func resetResolutionForNewSymbol() {
        self.lastResolvedPair = nil
        self.lastResolvedCoinbaseProduct = nil
        self.isUS = false
        self.volumeScaleMax = nil
        self.volumeDataStable = false
    }
    
    // MARK: - Loading Timeout Management
    
    /// Start a timeout timer that will force loading to stop after the timeout period
    /// This prevents the chart from being stuck in a loading state indefinitely
    /// PERFORMANCE FIX: Now triggers auto-retry with exponential backoff instead of immediate error
    private func startLoadingTimeout(for symbol: String, interval: ChartInterval) {
        // Cancel any existing timeout
        loadingTimeoutWork?.cancel()
        
        // Store symbol/interval for retry
        lastRetrySymbol = symbol
        lastRetryInterval = interval
        
        // Create new timeout work item
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                // Only trigger timeout if still loading with no data
                if self.isLoading && self.dataPoints.isEmpty {
                    // PERFORMANCE FIX: Auto-retry with exponential backoff
                    if self.autoRetryCount < self.maxAutoRetries {
                        self.triggerAutoRetry(symbol: symbol, interval: interval)
                    } else {
                        // Max retries exhausted - show error
                        self.isLoading = false
                        self.isRefreshing = false  // SEAMLESS UX: Clear refresh indicator
                        self.isRetrying = false
                        self.autoRetryCount = 0
                        self.errorMessage = "Request timed out. Check your internet connection and try again."
                        print("[CryptoChartViewModel] Loading timeout for \(symbol) \(interval.rawValue) after \(self.maxAutoRetries) retries")
                    }
                }
            }
        }
        loadingTimeoutWork = work
        
        // Schedule the timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + loadingTimeout, execute: work)
    }
    
    /// PERFORMANCE FIX: Trigger auto-retry with exponential backoff
    /// This provides seamless retry without requiring user interaction
    private func triggerAutoRetry(symbol: String, interval: ChartInterval) {
        let retryIndex = min(autoRetryCount, autoRetryDelays.count - 1)
        let delay = autoRetryDelays[retryIndex]
        autoRetryCount += 1
        
        isRetrying = true
        isLoading = false // Stop loading indicator during delay
        
        print("[CryptoChartViewModel] Auto-retry \(autoRetryCount)/\(maxAutoRetries) for \(symbol) \(interval.rawValue) in \(delay)s")
        
        pendingRetryWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                guard self.isRetrying else { return } // User may have navigated away
                self.isRetrying = false
                self.loadChartData(symbol: symbol, interval: interval, forceReload: true)
            }
        }
        pendingRetryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
    
    /// Cancel the loading timeout (called when loading completes successfully or with error)
    /// PERFORMANCE FIX: Also resets retry state on success to prevent stale retry counters
    private func cancelLoadingTimeout() {
        loadingTimeoutWork?.cancel()
        loadingTimeoutWork = nil
        // Reset retry state on successful load
        autoRetryCount = 0
        isRetrying = false
        pendingRetryWork?.cancel()
        pendingRetryWork = nil
    }
    
    /// Cancel any pending auto-retry (called when user navigates away)
    func cancelAutoRetry() {
        pendingRetryWork?.cancel()
        pendingRetryWork = nil
        isRetrying = false
        autoRetryCount = 0
        loadingTimeoutWork?.cancel()
        loadingTimeoutWork = nil
    }

    private struct TradeMessage: Decodable {
        let p: String
        let T: TimeInterval
    }
    private struct StreamEnvelope: Decodable {
        let stream: String?
        let data: TradeMessage
    }
    
    // MARK: - Coinbase WebSocket Message Structures
    // Coinbase uses a different message format for their WebSocket feed
    private struct CoinbaseTickerMessage: Decodable {
        let type: String
        let price: String?
        let time: String?
        let product_id: String?
    }
    
    // Track if we're connected to Coinbase (different message handling)
    private var isCoinbaseWebSocket: Bool = false
    private var coinbaseProductId: String = ""

    /// Recursively fetches Binance klines to cover the desired time range, handling pagination and 451 fallback.
    private func fetchKlinesRecursively(
        baseURL: String,
        pair: String,
        interval: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        accumulated: [[Any]],
        completion: @escaping ([[Any]]) -> Void
    ) {
        // Build URL with startTime and endTime, limit=1000
        let urlStr = "\(baseURL)/api/v3/klines?symbol=\(pair)&interval=\(interval)&startTime=\(Int(startTime))&endTime=\(Int(endTime))&limit=1000"
        guard let url = URL(string: urlStr) else {
            self.errorMessage = "Invalid URL for pagination"
            completion(accumulated)
            return
        }
        session.dataTask(with: url) { [weak self] data, response, error in
            Task { @MainActor in
                guard let self = self else { return }
                if let http = response as? HTTPURLResponse, http.statusCode == 451 {
                    // Switch to Binance US; prefer USD pair if available
                    await ExchangeHostPolicy.shared.onHTTPStatus(451)
                    self.isUS = true
                    let altPair: String = {
                        if pair.hasSuffix("USDT") {
                            let root = String(pair.dropLast(4))
                            return root + "USD"
                        } else if pair.hasSuffix("USD") {
                            let root = String(pair.dropLast(3))
                            return root + "USDT"
                        } else {
                            return pair
                        }
                    }()
                    self.fetchKlinesRecursively(
                        baseURL: ExchangeAPI.binanceUS.rawValue,
                        pair: altPair,
                        interval: interval,
                        startTime: startTime,
                        endTime: endTime,
                        accumulated: accumulated,
                        completion: completion
                    )
                    return
                }
                if let err = error {
                    self.errorMessage = err.localizedDescription
                    completion(accumulated)
                    return
                }
                guard let data = data else {
                    self.errorMessage = "No data during pagination"
                    completion(accumulated)
                    return
                }
                // Decode JSON to [[Any]]
                guard let raw = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else {
                    self.errorMessage = "Bad JSON during pagination"
                    completion(accumulated)
                    return
                }
                // If no more data or earliest timestamp <= startTime, finish accumulation
                if raw.isEmpty {
                    completion(accumulated)
                    return
                }
                // Combine accumulated with this batch
                let combined = raw + accumulated
                // Earliest entry timestamp in ms
                if let firstEntry = raw.first, let t0 = firstEntry[0] as? Double {
                    let earliestTs = t0
                    if earliestTs <= startTime || raw.count < 1000 {
                        // We have covered the desired range or no more pages
                        completion(combined)
                    } else {
                        // Need to fetch previous batch: set new endTime to earliestTs - 1 ms
                        let newEnd = earliestTs - 1
                        self.fetchKlinesRecursively(
                            baseURL: baseURL,
                            pair: pair,
                            interval: interval,
                            startTime: startTime,
                            endTime: newEnd,
                            accumulated: combined,
                            completion: completion
                        )
                    }
                } else {
                    completion(combined)
                }
            }
        }.resume()
    }

    /// PERFORMANCE FIX: Wrapper for auto-retry that clears error and loads data
    /// forceReload: true skips cache check for retry scenarios
    func loadChartData(symbol: String, interval: ChartInterval, forceReload: Bool = false) {
        errorMessage = nil
        if forceReload {
            // For retries, increment fetch sequence to ensure fresh attempt
            fetchSequence += 1
        }
        fetchData(symbol: symbol, interval: interval)
    }
    
    func fetchData(symbol: String, interval: ChartInterval, indicatorBuffer: Int = 50) {
        // VALIDATION: Ensure symbol is valid before making any network requests
        let trimmedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSymbol.isEmpty else {
            logger.warning("[Chart] fetchData called with empty symbol")
            self.errorMessage = "Invalid symbol"
            self.isLoading = false
            self.isRefreshing = false  // SEAMLESS UX: Clear refresh indicator
            return
        }
        
        fetchSequence += 1
        let currentSeq = fetchSequence
        #if DEBUG
        print("[Chart] fetchData START: \(symbol) \(interval.rawValue) seq=\(currentSeq), hasData=\(!dataPoints.isEmpty), preferred=\(preferredExchange ?? "nil")")
        #endif
        
        // Cancel any existing timeout from previous fetch
        cancelLoadingTimeout()
        
        // FIX: Clear any previous error immediately when starting a new fetch
        // This ensures errors from other timeframes (e.g., "Unable to connect to live stream") 
        // don't persist when switching timeframes, even if this fetch returns early
        self.errorMessage = nil
        
        // Use dynamic indicator buffer (passed from view based on enabled indicator periods)
        let dynamicBuffer = max(indicatorBuffer, indicatorWarmupBuffer)
        
        // Reset volume stability flag - will be set true when fresh API data arrives
        self.volumeDataStable = false

        // PROFESSIONAL APP: NEVER show loading animation - always display data instantly
        // Keep showing current chart while new data loads in background
        // This variable tracks if we have ANY data to show (cache or current)
        var hasDataToShow = !self.dataPoints.isEmpty
        
        let key = self.cacheKey(symbol: symbol, interval: interval)
        
        // FIX: Check if this fetch is already in progress (deduplication)
        // If another fetch for the same symbol/interval is active, skip this one
        // but still try to use cached data
        let canFetch = Self.registerInflightFetch(key: key)
        if !canFetch {
            // Another fetch is in progress - use cache if available
            if let cached = self.loadCache(key: key), cached.count >= 10 {
                if isLiveModeActive {
                    // LIVE MODE: Don't overwrite live seed/WebSocket data with candle cache.
                    // The flat seed + WebSocket ticks strategy provides smooth startup.
                } else {
                    self.dataPoints = cached
                }
                self.volumeScaleMax = self.volumeCeiling(from: cached)
                self.isLoading = false
                self.isRefreshing = false  // FIX: Clear refresh indicator on duplicate fetch
                logger.debug("[Chart] Skipping duplicate fetch for \(key), using cache")
            }
            return
        }
        
        // INSTANT DISPLAY: Always show cached data immediately — NEVER show a loading screen.
        // Fresh data loads in the background and replaces this seamlessly.
        // Professional apps (TradingView, Coinbase) always show cached data first.
        if let cached = self.loadCache(key: key), cached.count >= 10 {
            // LIVE MODE: Don't overwrite live seed/WebSocket data with candle cache.
            // The flat seed + WebSocket ticks strategy provides smooth startup without
            // the Y-domain rescaling that stale candle data causes.
            if isLiveModeActive {
                // Keep live data untouched. Candle data is cached to disk for indicator warm-up.
            } else if self.dataPoints.count != cached.count || self.dataPoints.last?.date != cached.last?.date {
                // PERFORMANCE FIX: Only assign cached data if it differs from what's already displayed.
                // During timeframe switching, loadCachedDataForInterval already loaded this cache.
                // Re-assigning bumps dataVersion, triggering a redundant O(n) indicator recompute.
                self.dataPoints = cached
            }
            self.volumeScaleMax = self.volumeCeiling(from: cached)
            self.isLoading = false
            hasDataToShow = true
            
            // Mark as refreshing if cache is stale (shows subtle indicator, not loading screen)
            // Per-interval thresholds ensure shorter timeframes trigger refresh sooner
            if let latestDate = cached.last?.date {
                let age = Date().timeIntervalSince(latestDate)
                let maxFreshAge = interval.maxAllowedDataAge
                if age > maxFreshAge {
                    self.isRefreshing = true  // Background refresh indicator
                    logger.debug("[Chart] Showing stale cache for \(key) — refreshing in background")
                }
            }
            logger.debug("[Chart] Instant display from cache for \(key) (\(cached.count) points)")
        }
        
        // IMPORTANT: Never show loading animation if we have ANY data displaying
        // Only show loading on truly empty state (app just launched, no data ever loaded)
        if hasDataToShow {
            self.isLoading = false
        }
        
        // EXCHANGE PREFERENCE: If user selected Coinbase, skip Binance and go directly to Coinbase
        // This ensures the chart data matches the user's selected exchange for consistency
        if let exchange = preferredExchange?.lowercased(), exchange == "coinbase", !coinbaseFallbackActive {
            logger.info("[Chart] Using preferred exchange: Coinbase")
            if !hasDataToShow {
                self.isLoading = true
                self.startLoadingTimeout(for: symbol, interval: interval)
            }
            self.errorMessage = nil
            
            // Calculate limit for Coinbase fetch
            let limitCalc: Int = {
                if interval == .oneMin || interval == .fiveMin {
                    return min(interval.binanceLimit + dynamicBuffer, 1000)
                } else if interval.secondsPerInterval > 0 {
                    let totalSeconds = interval.lookbackSeconds
                    let calc = Int(totalSeconds / interval.secondsPerInterval)
                    return calc < 1 ? interval.binanceLimit + dynamicBuffer : min(calc + dynamicBuffer, 1000)
                } else {
                    return min(interval.binanceLimit + dynamicBuffer, 1000)
                }
            }()
            let limit = max(limitCalc, 16)
            
            // FALLBACK FIX: When Coinbase is the preferred exchange but ALL candle attempts
            // fail (network errors, API changes, rate limits), fall back to the standard
            // Firebase → Binance pipeline instead of showing "No data" error.
            // This closure is called by fetchFromCoinbase when all product candidates are exhausted.
            let coinbaseFallback: (() -> Void)? = { [weak self] in
                guard let self = self else { return }
                // Check sequence is still valid before starting fallback
                guard self.fetchSequence == currentSeq else { return }
                self.logger.info("[Chart] Coinbase preferred fetch failed, falling back to Firebase/Binance pipeline")
                // Clear the inflight key so the fallback can register it
                Self.completeInflightFetch(key: key)
                // Set flag to bypass Coinbase-preferred path on re-entry (prevents infinite loop)
                self.coinbaseFallbackActive = true
                self.fetchData(symbol: symbol, interval: interval, indicatorBuffer: dynamicBuffer)
            }
            self.coinbaseFallbackClosure = coinbaseFallback
            self.fetchFromCoinbase(symbol: symbol, interval: interval, limit: limit, currentSeq: currentSeq)
            return
        }
        
        // FIREBASE FIRST: Try Firebase cache for shared data across all users
        // This reduces API rate limits and ensures all users see the same data
        // Falls back to direct API calls if Firebase fails
        if FirebaseService.shared.shouldUseFirebase && interval != .live {
            // FIX: Set loading state BEFORE creating async Task to prevent race condition
            // where view renders with empty data and isLoading=false, showing error overlay
            // This must happen synchronously before the Task is created
            if !hasDataToShow {
                self.isLoading = true
                self.startLoadingTimeout(for: symbol, interval: interval)
            }
            self.errorMessage = nil
            
            Task { @MainActor in
                // RACE CONDITION FIX: Check if a newer fetch has been started since this one.
                // Without this guard, a slow Firebase response for an OLD timeframe can
                // overwrite the chart data after the user has already switched to a new
                // timeframe, causing the "broken chart" where old data renders with new
                // axis labels (e.g., 1H data displayed as 30m).
                guard self.fetchSequence == currentSeq else {
                    Self.completeInflightFetch(key: key)
                    return
                }
                do {
                    // Map interval to Firebase interval string
                    let firebaseInterval = self.firebaseIntervalString(for: interval)
                    
                    // Use CoinGecko endpoint for 3Y/ALL timeframes
                    if interval == .all || interval == .threeYear {
                        let coinId = self.coingeckoID(for: symbol)
                        let days: Any = interval == .all ? "max" : 1095
                        
                        let response = try await FirebaseService.shared.getChartDataCoinGecko(
                            coinId: coinId,
                            days: days
                        )
                        
                        // Build volume lookup by day
                        var volumeMap: [Int: Double] = [:]
                        for vol in response.volumes {
                            let dayKey = Int(vol.t / 1000 / 86400)
                            volumeMap[dayKey] = vol.v
                        }
                        
                        // Convert to ChartDataPoints (filter zero/negative prices)
                        var pts: [ChartDataPoint] = response.prices.compactMap { pricePoint in
                            guard pricePoint.p > 0 else { return nil }
                            let dayKey = Int(pricePoint.t / 1000 / 86400)
                            let volume = volumeMap[dayKey] ?? 0
                            return ChartDataPoint(
                                date: pricePoint.date,
                                close: pricePoint.p,
                                volume: max(0, volume)
                            )
                        }
                        
                        pts.sort { $0.date < $1.date }
                        
                        // DATA CONSISTENCY FIX: Filter CoinGecko data to correct time window
                        // For 3Y, only keep last ~3.9 years (with 30% warm-up buffer). For ALL, keep everything.
                        let cgLookback = interval.lookbackSeconds
                        if cgLookback > 0 {
                            let cgCutoff = Date().addingTimeInterval(-(cgLookback * 1.3))
                            pts = pts.filter { $0.date >= cgCutoff }
                        }
                        
                        // Resample to weekly for consistency
                        let weeklyPts = self.resample(points: pts, to: 604800)
                        
                        // FRESHNESS CHECK for CoinGecko data
                        let isCoinGeckoFresh: Bool = {
                            guard let latestDate = weeklyPts.last?.date else { return false }
                            // Longer threshold for weekly candles (3Y/ALL)
                            return Date().timeIntervalSince(latestDate) <= 14 * 86400 // 14 days
                        }()
                        
                        if weeklyPts.count >= 10 && isCoinGeckoFresh {
                            // RACE CONDITION FIX: Re-check sequence before assigning data.
                            // A newer timeframe switch may have started while Firebase was loading.
                            guard self.fetchSequence == currentSeq else {
                                Self.completeInflightFetch(key: key)
                                self.saveCache(points: weeklyPts, key: key) // Still cache for future use
                                return
                            }
                            self.logger.info("[Chart] Firebase SUCCESS for \(symbol) \(interval.rawValue): \(weeklyPts.count) points (CoinGecko)")
                            Self.completeInflightFetch(key: key)
                            self.cancelLoadingTimeout()
                            // LIVE MODE GUARD: Don't overwrite WebSocket data with candle data.
                            // The data is still cached below for indicator warm-up.
                            if !self.isLiveModeActive {
                                self.dataPoints = weeklyPts
                            }
                            self.volumeScaleMax = self.volumeCeiling(from: weeklyPts)
                            self.isLoading = false
                            self.isRefreshing = false
                            self.errorMessage = nil
                            self.volumeDataStable = true
                            self.saveCache(points: weeklyPts, key: key)
                            self.prewarmCache(for: symbol, excluding: interval)
                            return // Success - exit
                        } else if weeklyPts.count >= 10 {
                            self.logger.info("[Chart] Firebase CoinGecko data STALE for \(symbol) \(interval.rawValue) — falling back to direct API")
                        }
                    } else {
                        // Use Binance endpoint for other intervals
                        // Pass the needed limit so Firebase fetches enough candles for the timeframe
                        let neededLimit = min(interval.binanceLimit + dynamicBuffer, 1000)
                        let response = try await FirebaseService.shared.getChartData(
                            symbol: symbol,
                            interval: firebaseInterval,
                            limit: neededLimit
                        )
                        
                        // Convert to ChartDataPoints (filter zero/negative prices)
                        var pts: [ChartDataPoint] = response.points.compactMap { candle in
                            guard candle.c > 0 else { return nil }
                            return ChartDataPoint(
                                date: candle.date,
                                close: candle.c,
                                volume: max(0, candle.v)
                            )
                        }
                        
                        // DATA CONSISTENCY FIX: Filter Firebase data to correct time window.
                        // Firebase may return more data than needed for the selected interval.
                        // Without filtering, a 1Y chart could show 5+ years of data.
                        // Add 30% buffer beyond lookback for indicator warm-up calculations.
                        let lookback = interval.lookbackSeconds
                        if lookback > 0 {
                            let cutoffDate = Date().addingTimeInterval(-(lookback * 1.3))
                            pts = pts.filter { $0.date >= cutoffDate }
                        }
                        
                        // FRESHNESS CHECK: Verify the latest data point is recent enough.
                        // Without this, stale Firebase data (days/weeks old) can slip through
                        // the time-window filter and display as apparently-current but outdated.
                        // Per-interval thresholds ensure the data is fresh enough relative to
                        // the timeframe's window size — e.g., 2-hour-old data is unacceptable
                        // for a 5m chart (8-hour window) but fine for a 1W chart.
                        let isFirebaseBinanceFresh: Bool = {
                            guard let latestDate = pts.last?.date else { return false }
                            return Date().timeIntervalSince(latestDate) <= interval.maxAllowedDataAge
                        }()
                        
                        if pts.count >= 10 && isFirebaseBinanceFresh {
                            // RACE CONDITION FIX: Re-check sequence before assigning data.
                            // A newer timeframe switch may have started while Firebase was loading.
                            guard self.fetchSequence == currentSeq else {
                                Self.completeInflightFetch(key: key)
                                self.saveCache(points: pts, key: key) // Still cache for future use
                                return
                            }
                            self.logger.info("[Chart] Firebase SUCCESS for \(symbol) \(interval.rawValue): \(pts.count) points")
                            #if DEBUG
                            print("[Chart] Firebase DATA ASSIGNED: \(symbol) \(interval.rawValue) pts=\(pts.count) seq=\(currentSeq) currentSeq=\(self.fetchSequence)")
                            #endif
                            Self.completeInflightFetch(key: key)
                            self.cancelLoadingTimeout()
                            // LIVE MODE GUARD: Don't overwrite WebSocket data with candle data.
                            // The data is still cached below for indicator warm-up.
                            if !self.isLiveModeActive {
                                self.dataPoints = pts.sorted { $0.date < $1.date }
                            }
                            self.volumeScaleMax = self.volumeCeiling(from: pts)
                            self.isLoading = false
                            self.isRefreshing = false
                            self.errorMessage = nil
                            self.volumeDataStable = true
                            self.saveCache(points: pts, key: key)
                            self.prewarmCache(for: symbol, excluding: interval)
                            return // Success - exit
                        } else if pts.count >= 10 {
                            self.logger.info("[Chart] Firebase data STALE for \(symbol) \(interval.rawValue) — latest point too old, falling back to direct API")
                        }
                    }
                    
                    self.logger.info("[Chart] Firebase returned insufficient data for \(symbol), falling back to direct API")
                } catch {
                    // Firebase failed - will fall through to direct API calls
                    self.logger.info("[Chart] Firebase FAILED for \(symbol) \(interval.rawValue): \(error.localizedDescription) - using direct API")
                }
                
                // RACE CONDITION FIX: Check sequence before falling back to direct API.
                // If user already switched timeframes, don't start another fetch for the old interval.
                guard self.fetchSequence == currentSeq else {
                    Self.completeInflightFetch(key: key)
                    return
                }
                // Firebase failed or returned insufficient data - continue with direct API calls
                self.fetchDataDirectAPI(symbol: symbol, interval: interval, indicatorBuffer: indicatorBuffer, currentSeq: currentSeq, hasDataToShow: hasDataToShow, key: key)
            }
            return
        }

        if interval == .live {
            self.stopLive()    // tear down any previous stream
            // PROFESSIONAL: Always preserve existing data - never show loading animation
            self.startLive(symbol: symbol, preserveExisting: true)
            self.prewarmCache(for: symbol, excluding: .live)
            return
        }
        
        // Special handling for ALL and 3Y timeframes: use CoinGecko for complete historical data
        // CoinGecko has data going back to 2013 for Bitcoin, providing much better coverage than Binance
        if interval == .all || interval == .threeYear {
            // NEVER show loading if we have any data - professional app experience
            if !hasDataToShow {
                self.isLoading = true
                self.startLoadingTimeout(for: symbol, interval: interval)
            }
            self.errorMessage = nil
            
            // Determine days parameter: nil for ALL (max), 1095 for 3Y (3 years)
            let days: Int? = interval == .threeYear ? 1095 : nil
            let timeframeName = interval == .threeYear ? "3Y" : "ALL"
            
            // Try CoinGecko first for complete historical data
            self.fetchFromCoinGecko(symbol: symbol, interval: interval, days: days, currentSeq: currentSeq) { [weak self] in
                guard let self = self else { return }
                // Fallback to Binance if CoinGecko fails
                print("[\(timeframeName)] CoinGecko failed, falling back to Binance")
                let nowMs = Date().timeIntervalSince1970 * 1000
                let startTime: TimeInterval = interval == .threeYear
                    ? nowMs - TimeInterval(156 * 7 * 86_400 * 1000)  // 156 weeks = 3 years
                    : 1262304000 * 1000  // epoch 2010 for ALL
                let bases: [ExchangeAPI] = [.binance, .binanceUS]
                var attempts: [(ExchangeAPI, String, URL)] = []
                let preferUSD = QuotePreferenceStore.prefersUSD(isUSUser: self.isUS)
                for base in bases {
                    let localPairs = (base == .binanceUS)
                        ? candidateSymbols(for: symbol, preferUSD: true)
                        : candidateSymbols(for: symbol, preferUSD: preferUSD)
                    for p in localPairs {
                        let urlStr = "\(base.rawValue)/api/v3/klines?symbol=\(p)&interval=1w&startTime=\(Int(startTime))&limit=1000"
                        if let url = URL(string: urlStr) {
                            attempts.append((base, p, url))
                        }
                    }
                }
                self.attemptKlineRequests(attempts, currentSeq: currentSeq) { [weak self] data, base, pair in
                    guard let self = self else { return }
                    guard self.fetchSequence == currentSeq else { return }
                    if let data, let base, let pair {
                        self.isUS = (base == .binanceUS)
                        self.lastResolvedPair = pair
                        self.parseAndCache(data: data, symbol: symbol, interval: interval, expectedSeq: currentSeq)
                        self.prewarmCache(for: symbol, excluding: interval)
                    } else {
                        self.fetchFromCoinbase(symbol: symbol, interval: interval, limit: 1000, currentSeq: currentSeq)
                    }
                }
            }
            return
        }
        
        // Special handling for 1Y: use daily candles with startTime
        // Fetch limits include warmup buffer (50 candles) for indicator calculations
        if interval == .oneYear {
            let nowMs = Date().timeIntervalSince1970 * 1000
            // 365 visible + 50 warmup = 415 daily candles (~14 months)
            let requestInterval = "1d"
            let requestLimit = 415
            let startTimeMs: TimeInterval = nowMs - TimeInterval(415 * 86_400 * 1000)

            // Try both USDT and USD on Binance.com first; if 451 or empty, fall back to Binance US (prefer USD)
            let bases: [ExchangeAPI] = [.binance, .binanceUS]
            // NEVER show loading if we have any data - professional app experience
            if !hasDataToShow {
                self.isLoading = true
                self.startLoadingTimeout(for: symbol, interval: interval)
            }
            self.errorMessage = nil
            var attempts: [(ExchangeAPI, String, URL)] = []
            let preferUSD = QuotePreferenceStore.prefersUSD(isUSUser: self.isUS)
            for base in bases {
                let localPairs = (base == .binanceUS)
                    ? candidateSymbols(for: symbol, preferUSD: true)
                    : candidateSymbols(for: symbol, preferUSD: preferUSD)
                for p in localPairs {
                    // Build URL with startTime for precise data range fetching
                    let urlStr = "\(base.rawValue)/api/v3/klines?symbol=\(p)&interval=\(requestInterval)&startTime=\(Int(startTimeMs))&limit=\(requestLimit)"
                    if let url = URL(string: urlStr) {
                        attempts.append((base, p, url))
                    }
                }
            }
            self.attemptKlineRequests(attempts, currentSeq: currentSeq) { [weak self] data, base, pair in
                guard let self = self else { return }
                // If a newer request started, ignore
                guard self.fetchSequence == currentSeq else { return }
                if let data, let base, let pair {
                    self.isUS = (base == .binanceUS)
                    self.lastResolvedPair = pair
                    // NOTE: isLoading = false is set inside parseAndCache() after data assignment
                    self.parseAndCache(data: data, symbol: symbol, interval: interval, expectedSeq: currentSeq)
                    self.prewarmCache(for: symbol, excluding: interval)
                } else {
                    // Fallback to Coinbase candles
                    self.fetchFromCoinbase(symbol: symbol, interval: interval, limit: requestLimit, currentSeq: currentSeq)
                }
            }
            return
        }
        let nowMs = Date().timeIntervalSince1970 * 1000
        let startMs = nowMs - (interval.lookbackSeconds * 1000)

        // Compute how many candles needed for the chosen lookback
        let candlesNeeded: Int
        if interval.secondsPerInterval > 0, interval.lookbackSeconds > 0 {
            candlesNeeded = Int(interval.lookbackSeconds / interval.secondsPerInterval)
        } else {
            candlesNeeded = 0
        }
        let secondsPerInterval = interval.secondsPerInterval
        // Only use recursive fetch if not .oneMin or .fiveMin
        if secondsPerInterval > 0 && candlesNeeded > 1000 && interval != .oneMin && interval != .fiveMin {
            // Use recursive fetch to cover full range
            // NEVER show loading if we have any data - professional app experience
            if !hasDataToShow {
                self.isLoading = true
                self.startLoadingTimeout(for: symbol, interval: interval)
            }
            self.errorMessage = nil
            let preferUSD = QuotePreferenceStore.prefersUSD(isUSUser: self.isUS)
            let pairForRecursion = candidateSymbols(for: symbol, preferUSD: preferUSD).first ?? (symbol.uppercased() + (preferUSD ? "USD" : "USDT"))
            fetchKlinesRecursively(
                baseURL: isUS ? ExchangeAPI.binanceUS.rawValue : ExchangeAPI.binance.rawValue,
                pair: pairForRecursion,
                interval: interval.binanceInterval,
                startTime: startMs,
                endTime: nowMs,
                accumulated: [],
                completion: { [weak self] rawCombined in
                    Task { @MainActor in
                        guard let self = self else { return }
                        guard self.fetchSequence == currentSeq else { return }
                        
                        // Parse combined data
                        var pts: [ChartDataPoint] = []
                        for entry in rawCombined {
                            guard entry.count >= 6,
                                  let t = entry[0] as? Double else { continue }
                            let date = Date(timeIntervalSince1970: t / 1000)
                            let closeRaw = entry[4]
                            let rawVolume = entry[5]
                            let close: Double? = {
                                if let d = closeRaw as? Double { return d }
                                if let s = closeRaw as? String { return Double(s) }
                                return nil
                            }()
                            let volume: Double? = {
                                if let d = rawVolume as? Double { return d }
                                if let s = rawVolume as? String { return Double(s) }
                                return nil
                            }()
                            // VALIDATION: Skip zero/negative prices
                            if let c = close, c > 0 {
                                pts.append(.init(date: date, close: c, volume: max(0, volume ?? 0)))
                            }
                        }
                        
                        // FIX: Handle empty data case
                        if pts.isEmpty {
                            self.cancelLoadingTimeout()
                            self.errorMessage = "No chart data available for this timeframe"
                            self.isLoading = false
                            self.isRefreshing = false  // SEAMLESS UX: Clear refresh indicator
                            return
                        }
                        
                        self.cancelLoadingTimeout()
                        pts.sort { $0.date < $1.date }
                        let key = self.cacheKey(symbol: symbol, interval: interval)
                        self.saveCache(points: pts, key: key)
                        // Only update volumeScaleMax if it wasn't already set from cache
                        let newCeiling = self.volumeCeiling(from: pts)
                        let currentCount = self.dataPoints.count
                        if self.volumeScaleMax == nil || self.volumeScaleMax! < 1 || 
                           (currentCount == 0) || (pts.count > currentCount * 2) {
                            self.volumeScaleMax = newCeiling
                        }
                        self.prewarmCache(for: symbol, excluding: interval)
                        // LIVE MODE GUARD: Don't overwrite WebSocket data with candle data.
                        if !self.isLiveModeActive {
                            self.dataPoints = pts
                        }
                        self.isLoading = false
                        self.isRefreshing = false  // SEAMLESS UX: Clear refresh indicator
                        // Mark volume data as stable now that fresh API data has been processed
                        self.volumeDataStable = true
                    }
                }
            )
        } else {
            // Simple single-fetch case
            
            let limitCalc: Int
            if interval == .oneMin || interval == .fiveMin {
                // Use fixed binanceLimit for high-frequency intervals to avoid too many candles
                // Add dynamic warm-up buffer for indicator calculations
                limitCalc = min(interval.binanceLimit + dynamicBuffer, 1000)
            } else if interval.secondsPerInterval > 0 {
                let totalSeconds = interval.lookbackSeconds
                let calc = Int(totalSeconds / interval.secondsPerInterval)
                // Ensure at least 1 candle if calc < 1
                if calc < 1 {
                    limitCalc = interval.binanceLimit + dynamicBuffer
                } else {
                    // Add dynamic warm-up buffer for indicator calculations (BB, RSI, SMA 200, etc.)
                    limitCalc = min(calc + dynamicBuffer, 1000)
                }
            } else {
                // For intervals like .all, use default binanceLimit with dynamic warm-up buffer
                limitCalc = min(interval.binanceLimit + dynamicBuffer, 1000)
            }
            
            let minUseful = 16
            let limit = max(limitCalc, minUseful)

            // Try both USDT and USD on Binance.com first, then Binance US
            let bases: [ExchangeAPI] = [.binance, .binanceUS]
            // NEVER show loading if we have any data - professional app experience
            if !hasDataToShow {
                self.isLoading = true
                self.startLoadingTimeout(for: symbol, interval: interval)
            }
            self.errorMessage = nil
            var attempts: [(ExchangeAPI, String, URL)] = []
            let preferUSD = QuotePreferenceStore.prefersUSD(isUSUser: self.isUS)
            // FIX: Include startTime to lock the data to the correct time window.
            // Without startTime, Binance returns the latest N completed candles which can
            // be stale if served from a CDN/proxy cache. Including startTime ensures we get
            // candles from the intended lookback window regardless of upstream caching.
            let nowMs = Int(Date().timeIntervalSince1970 * 1000)
            let lookbackMs = Int(interval.lookbackSeconds * 1.3 * 1000) // 30% buffer for indicator warm-up
            let startMs = nowMs - lookbackMs
            for base in bases {
                let localPairs = (base == .binanceUS)
                    ? candidateSymbols(for: symbol, preferUSD: true)
                    : candidateSymbols(for: symbol, preferUSD: preferUSD)
                for p in localPairs {
                    let urlStr = "\(base.rawValue)/api/v3/klines?symbol=\(p)&interval=\(interval.binanceInterval)&startTime=\(startMs)&limit=\(limit)"
                    if let url = URL(string: urlStr) {
                        attempts.append((base, p, url))
                    }
                }
            }
            self.attemptKlineRequests(attempts, currentSeq: currentSeq) { [weak self] data, base, pair in
                guard let self = self else { return }
                // If a newer request started, ignore
                guard self.fetchSequence == currentSeq else { return }
                if let data, let base, let pair {
                    self.isUS = (base == .binanceUS)
                    self.lastResolvedPair = pair
                    // NOTE: isLoading = false is set inside parseAndCache() after data assignment
                    self.parseAndCache(data: data, symbol: symbol, interval: interval, expectedSeq: currentSeq)
                    self.prewarmCache(for: symbol, excluding: interval)
                } else {
                    // Fallback to Coinbase candles
                    self.fetchFromCoinbase(symbol: symbol, interval: interval, limit: limit, currentSeq: currentSeq)
                }
            }
        }
    }
    
    /// Parse API response data, cache it, and update the chart.
    /// `expectedSeq` enables stale-response detection: if the fetchSequence has moved on
    /// by the time we finish parsing, we cache the data but do NOT update `dataPoints`,
    /// preventing old-interval data from overwriting a newer timeframe's chart.
    private func parseAndCache(data: Data, symbol: String, interval: ChartInterval, expectedSeq: Int? = nil) {
        do {
            guard let raw = try JSONSerialization.jsonObject(with: data) as? [[Any]] else {
                self.cancelLoadingTimeout()
                self.errorMessage = "Bad JSON response from server"
                self.isLoading = false  // FIX: Must set isLoading = false on error
                return
            }
            var pts: [ChartDataPoint] = []
            for entry in raw {
                guard entry.count >= 6, let t = entry[0] as? Double else { continue }
                let date = Date(timeIntervalSince1970: t / 1000)
                let closeRaw = entry[4]
                let rawVolume = entry[5]
                let close: Double? = {
                    if let d = closeRaw as? Double { return d }
                    if let s = closeRaw as? String { return Double(s) }
                    return nil
                }()
                let volume: Double? = {
                    if let d = rawVolume as? Double { return d }
                    if let s = rawVolume as? String { return Double(s) }
                    return nil
                }()
                // VALIDATION: Skip invalid data points
                // - Prices must be positive (zero or negative would break the chart)
                // - Timestamps must be reasonable (not in the distant future)
                if let c = close, c > 0 {
                    let now = Date()
                    let futureLimit = now.addingTimeInterval(86400) // Allow up to 1 day in future (for timezone issues)
                    if date <= futureLimit {
                        pts.append(.init(date: date, close: c, volume: max(0, volume ?? 0)))
                    }
                }
            }
            
            // FIX: Handle case where parsing succeeded but no valid data points were extracted
            if pts.isEmpty {
                self.cancelLoadingTimeout()
                self.errorMessage = "No chart data available for this timeframe"
                self.isLoading = false
                self.isRefreshing = false  // SEAMLESS UX: Clear refresh indicator
                return
            }
            
            pts.sort { $0.date < $1.date }
            
            // DATA CONSISTENCY FIX: Filter parsed data to correct time window.
            // Ensures the chart only shows data appropriate for the selected interval.
            // Add 30% buffer beyond lookback for indicator warm-up calculations.
            let lookback = interval.lookbackSeconds
            if lookback > 0 {
                let cutoffDate = Date().addingTimeInterval(-(lookback * 1.3))
                pts = pts.filter { $0.date >= cutoffDate }
            }
            
            // FRESHNESS SAFETY NET: Verify the API actually returned recent data.
            // If the latest data point is too old for the selected timeframe,
            // something is wrong upstream (API proxy, Firebase relay, etc.).
            // Still save to cache (it's the best we have) but log a warning.
            // Per-interval thresholds to catch stale data sooner on short timeframes.
            if let latestDate = pts.last?.date {
                let dataAge = Date().timeIntervalSince(latestDate)
                let maxFreshAge = interval.maxAllowedDataAge
                if dataAge > maxFreshAge {
                    self.logger.warning("[Chart] Direct API returned STALE data for \(symbol) \(interval.rawValue): latest point age \(Int(dataAge))s (max \(Int(maxFreshAge))s)")
                }
            }
            
            let key = self.cacheKey(symbol: symbol, interval: interval)
            self.saveCache(points: pts, key: key)
            // FIX: Complete in-flight tracking on successful parse
            Self.completeInflightFetch(key: key)
            self.cancelLoadingTimeout()
            
            // RACE CONDITION FIX: If a newer fetch has started (user switched timeframes),
            // don't overwrite dataPoints with old-interval data. The data is already cached
            // to disk above, so it will be available for future instant-switch loads.
            if let seq = expectedSeq, self.fetchSequence != seq {
                self.logger.debug("[Chart] Discarding stale parseAndCache result for \(symbol) \(interval.rawValue) (seq \(seq) != current \(self.fetchSequence))")
                return
            }
            
            // Only update volumeScaleMax if it wasn't already set from cache
            // This prevents the visual "readjustment" when fresh data arrives
            let newCeiling = self.volumeCeiling(from: pts)
            let currentCount = self.dataPoints.count
            if self.volumeScaleMax == nil || self.volumeScaleMax! < 1 || 
               (currentCount == 0) || (pts.count > currentCount * 2) {
                self.volumeScaleMax = newCeiling
            }
            // LIVE MODE: NEVER overwrite live data with candle data from this fetch.
            if self.isLiveModeActive {
                // Keep live data untouched. Candle data is cached for indicator warm-up.
            } else {
                self.dataPoints = pts
            }
            self.isLoading = false
            self.isRefreshing = false
            // Mark volume data as stable now that fresh API data has been processed
            self.volumeDataStable = true
        } catch {
            // FIX: Complete in-flight tracking on error
            let key = self.cacheKey(symbol: symbol, interval: interval)
            Self.completeInflightFetch(key: key)
            self.cancelLoadingTimeout()
            self.errorMessage = "Failed to parse chart data: \(error.localizedDescription)"
            self.isLoading = false  // FIX: Must set isLoading = false on error
            self.isRefreshing = false  // SEAMLESS UX: Clear refresh indicator on error too
        }
    }

    private func parse(data: Data) {
        do {
            guard let raw = try JSONSerialization.jsonObject(with: data) as? [[Any]] else {
                self.cancelLoadingTimeout()
                self.errorMessage = "Bad JSON response"
                self.isLoading = false  // FIX: Must set isLoading = false on error
                return
            }
            var pts: [ChartDataPoint] = []
            for entry in raw {
                guard entry.count >= 5,
                      let t = entry[0] as? Double
                else { continue }
                let closeRaw = entry[4]
                let date = Date(timeIntervalSince1970: t / 1000)
                let close: Double? = {
                    if let d = closeRaw as? Double { return d }
                    if let s = closeRaw as? String { return Double(s) }
                    return nil
                }()
                let rawVolume = entry.count > 5 ? entry[5] : nil
                let volume: Double? = {
                    guard let rv = rawVolume else { return nil }
                    if let d = rv as? Double { return d }
                    if let s = rv as? String { return Double(s) }
                    return nil
                }()
                // VALIDATION: Match parseAndCache – skip zero/negative prices
                if let c = close, c > 0 {
                    pts.append(.init(date: date, close: c, volume: max(0, volume ?? 0)))
                }
            }
            
            // FIX: Handle empty data case
            if pts.isEmpty {
                self.cancelLoadingTimeout()
                self.errorMessage = "No chart data available"
                self.isLoading = false
                self.isRefreshing = false  // SEAMLESS UX: Clear refresh indicator
                return
            }
            
            pts.sort { $0.date < $1.date }
            self.cancelLoadingTimeout()
            // Only update volumeScaleMax if it wasn't already set from cache
            let newCeiling = self.volumeCeiling(from: pts)
            let currentCount = self.dataPoints.count
            if self.volumeScaleMax == nil || self.volumeScaleMax! < 1 || 
               (currentCount == 0) || (pts.count > currentCount * 2) {
                self.volumeScaleMax = newCeiling
            }
            // LIVE MODE GUARD: Don't overwrite WebSocket data with candle data.
            if !self.isLiveModeActive {
                self.dataPoints = pts
            }
            self.isLoading = false  // FIX: Set isLoading = false on success too
            // Mark volume data as stable now that fresh API data has been processed
            self.volumeDataStable = true
        } catch {
            self.cancelLoadingTimeout()
            self.errorMessage = error.localizedDescription
            self.isLoading = false  // FIX: Must set isLoading = false on error
        }
    }

    /// If Binance.com returns HTTP 451, try Binance.US
    private func fetchDataFromUS(symbol: String, interval: ChartInterval) {
        let pairs = candidateSymbols(for: symbol, preferUSD: true)
        // PROFESSIONAL: Never show loading if we have data to display
        if self.dataPoints.isEmpty {
            self.isLoading = true
        }
        self.errorMessage = nil
        // FIX: Include startTime for correct time window
        let usNowMs = Int(Date().timeIntervalSince1970 * 1000)
        let usLookbackMs = Int(interval.lookbackSeconds * 1.3 * 1000)
        let usStartMs = usLookbackMs > 0 ? usNowMs - usLookbackMs : 0
        var success = false
        for p in pairs {
            var urlStr = "\(ExchangeAPI.binanceUS.rawValue)/api/v3/klines?symbol=\(p)&interval=\(interval.binanceInterval)&limit=\(interval.binanceLimit)"
            if usStartMs > 0 {
                urlStr += "&startTime=\(usStartMs)"
            }
            guard let url = URL(string: urlStr) else { continue }
            let semaphore = DispatchSemaphore(value: 0)
            session.dataTask(with: url) { [weak self] data, _, error in
                defer { semaphore.signal() }
                guard let self = self else { return }
                if let data = data, let arr = try? JSONSerialization.jsonObject(with: data) as? [[Any]], !arr.isEmpty {
                    success = true
                    Task { @MainActor in
                        self.isUS = true
                        self.lastResolvedPair = p
                        self.cancelLoadingTimeout()
                        self.isLoading = false
                        self.parse(data: data)
                    }
                }
            }.resume()
            _ = semaphore.wait(timeout: .now() + 10)
            if success { break }
        }
        if !success {
            // FIX: Try fallback to cached data before showing error
            if !self.fallbackToCache(symbol: symbol, interval: interval, errorContext: "No data from US") {
                self.showErrorAndComplete(symbol: symbol, interval: interval, message: "No data from US for \(symbol).")
            }
        }
    }

    private func attemptKlineRequests(
        _ attempts: [(ExchangeAPI, String, URL)],
        currentSeq: Int,
        completion: @escaping (Data?, ExchangeAPI?, String?) -> Void
    ) {
        func attempt(index: Int, retried429: Bool) {
            guard index < attempts.count else {
                completion(nil, nil, nil)
                return
            }
            let (base, pair, url) = attempts[index]
            
            // NOTE: Chart requests are user-initiated priority requests - NO coordinator blocking
            // The coordinator should only limit background/prewarm requests, not direct user interactions
            
            session.dataTask(with: url) { [weak self] data, response, error in
                Task { @MainActor in
                    guard let self = self else { return }
                    // If a newer request started, ignore this entire chain
                    if self.fetchSequence != currentSeq {
                        completion(nil, nil, nil)
                        return
                    }
                    
                    // Handle timeout errors - try next attempt
                    if let error = error as NSError?, error.code == NSURLErrorTimedOut {
                        attempt(index: index + 1, retried429: false)
                        return
                    }
                    
                    if let http = response as? HTTPURLResponse {
                        if http.statusCode == 451 {
                            await ExchangeHostPolicy.shared.onHTTPStatus(451)
                            self.isUS = true
                            // Move to next attempt (likely Binance US entry exists later in attempts)
                            attempt(index: index + 1, retried429: false)
                            return
                        }
                        if http.statusCode == 429 {
                            // Gentle retry once after a short delay, then move on
                            if !retried429 {
                                DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
                                    attempt(index: index, retried429: true)
                                }
                                return
                            } else {
                                attempt(index: index + 1, retried429: false)
                                return
                            }
                        }
                    }
                    if let data = data,
                       let arr = try? JSONSerialization.jsonObject(with: data) as? [[Any]],
                       !arr.isEmpty {
                        completion(data, base, pair)
                    } else {
                        attempt(index: index + 1, retried429: false)
                    }
                }
            }.resume()
        }
        attempt(index: 0, retried429: false)
    }

    // Non-guarded attempt chain used for background cache warming
    private func attemptKlineRequestsNoGuard(
        _ attempts: [(ExchangeAPI, String, URL)],
        completion: @escaping (Data?, ExchangeAPI?, String?) -> Void
    ) {
        func attempt(index: Int, retried429: Bool) {
            guard index < attempts.count else {
                completion(nil, nil, nil)
                return
            }
            let (base, pair, url) = attempts[index]
            
            // FIX: Check APIRequestCoordinator before making prewarm request
            let service: APIRequestCoordinator.APIService = (base == .binanceUS) ? .binance : .binance
            if !APIRequestCoordinator.shared.canMakeRequest(for: service) {
                // Rate limited - skip this prewarm attempt (non-critical)
                completion(nil, nil, nil)
                return
            }
            APIRequestCoordinator.shared.recordRequest(for: service)
            
            session.dataTask(with: url) { [weak self] data, response, error in
                Task { @MainActor in
                    guard let _ = self else { return }
                    
                    // FIX: Handle timeout errors for prewarm
                    if let error = error as NSError?, error.code == NSURLErrorTimedOut {
                        APIRequestCoordinator.shared.recordFailure(for: service)
                        completion(nil, nil, nil)
                        return
                    }
                    
                    if let http = response as? HTTPURLResponse, http.statusCode == 451 {
                        attempt(index: index + 1, retried429: false)
                        return
                    }
                    if let http = response as? HTTPURLResponse, http.statusCode == 429 {
                        APIRequestCoordinator.shared.recordFailure(for: service)
                        if !retried429 {
                            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                                attempt(index: index, retried429: true)
                            }
                            return
                        } else {
                            attempt(index: index + 1, retried429: false)
                            return
                        }
                    }
                    if let data = data,
                       let arr = try? JSONSerialization.jsonObject(with: data) as? [[Any]],
                       !arr.isEmpty {
                        // FIX: Record success for prewarm request
                        APIRequestCoordinator.shared.recordSuccess(for: service)
                        completion(data, base, pair)
                    } else {
                        attempt(index: index + 1, retried429: false)
                    }
                }
            }.resume()
        }
        attempt(index: 0, retried429: false)
    }

    // Parse-only for cache warming (does not touch UI state)
    private func parseForCacheOnly(data: Data, symbol: String, interval: ChartInterval) {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else { return }
        var pts: [ChartDataPoint] = []
        for entry in raw {
            guard entry.count >= 6, let t = entry[0] as? Double else { continue }
            let date = Date(timeIntervalSince1970: t / 1000)
            let closeRaw = entry[4]
            let rawVolume = entry[5]
            let close: Double? = {
                if let d = closeRaw as? Double { return d }
                if let s = closeRaw as? String { return Double(s) }
                return nil
            }()
            let volume: Double? = {
                if let d = rawVolume as? Double { return d }
                if let s = rawVolume as? String { return Double(s) }
                return nil
            }()
            // VALIDATION: Skip zero/negative prices
            if let c = close, c > 0 { pts.append(.init(date: date, close: c, volume: max(0, volume ?? 0))) }
        }
        pts.sort { $0.date < $1.date }
        
        // DATA CONSISTENCY FIX: Filter prewarmed data to correct time window
        let lookback = interval.lookbackSeconds
        if lookback > 0 {
            let cutoffDate = Date().addingTimeInterval(-(lookback * 1.3))
            pts = pts.filter { $0.date >= cutoffDate }
        }
        
        let key = self.cacheKey(symbol: symbol, interval: interval)
        self.saveCache(points: pts, key: key)
    }

    // Compute a stable volume ceiling using the 98th percentile to avoid single-bar outliers
    func volumeCeiling(from pts: [ChartDataPoint]) -> Double {
        let vols = pts.map { $0.volume }.sorted()
        guard !vols.isEmpty else { return 1 }
        let idx = Int(Double(vols.count - 1) * 0.98)
        let val = vols[max(0, min(vols.count - 1, idx))]
        return max(1, val)
    }

    private func neighbors(for interval: ChartInterval) -> [ChartInterval] {
        switch interval {
        case .live:       return [.oneMin, .fiveMin, .fifteenMin]
        case .oneMin:     return [.fiveMin, .fifteenMin, .thirtyMin]
        case .fiveMin:    return [.oneMin, .fifteenMin, .thirtyMin]
        case .thirtyMin:  return [.fifteenMin, .oneHour, .fourHour]
        case .fifteenMin: return [.fiveMin, .thirtyMin, .oneHour]
        case .oneHour:    return [.thirtyMin, .fourHour, .oneDay]
        case .fourHour:   return [.oneHour, .oneDay, .oneWeek]
        case .oneDay:     return [.fourHour, .oneWeek, .oneMonth]
        case .oneWeek:    return [.oneDay, .oneMonth, .threeMonth]
        case .oneMonth:   return [.oneWeek, .threeMonth, .sixMonth]
        case .threeMonth: return [.oneMonth, .sixMonth, .oneYear]
        case .sixMonth:   return [.threeMonth, .oneYear]
        case .oneYear:    return [.sixMonth, .threeYear]
        case .threeYear:  return [.oneYear, .all]
        case .all:        return [.threeYear]
        }
    }

    /// Warm caches for nearby intervals so subsequent taps feel instant.
    /// FIX: Throttled to prevent request flooding
    func prewarmCache(for symbol: String, excluding interval: ChartInterval) {
        // DEBOUNCE FIX: Skip prewarming during rapid timeframe switching.
        // Capture the current fetchSequence and verify it hasn't changed before making requests.
        let seqAtStart = self.fetchSequence
        
        // FIX: Limit to 2 neighbors max to prevent too many concurrent prewarm requests
        let targets = Array(neighbors(for: interval).prefix(2))
        let pairsPrimary = candidateSymbols(for: symbol)
        let pairsUS = candidateSymbols(for: symbol, preferUSD: true)
        
        // FIX: Check if we should prewarm at all based on coordinator state
        // During high load periods, skip prewarming entirely to prioritize primary requests
        if !APIRequestCoordinator.shared.canMakeRequest(for: .binance) {
            return  // Skip prewarm when rate limited
        }
        
        for (idx, target) in targets.enumerated() {
            // Skip if we already have cached data for this target
            let key = self.cacheKey(symbol: symbol, interval: target)
            if self.loadCache(key: key) != nil { continue }

            // Build a lightweight limit for warming (tighter cap to reduce rate limits)
            let limitCalc: Int = {
                if target == .oneMin || target == .fiveMin { return min(target.binanceLimit, 60) }
                if target.secondsPerInterval > 0 && target.lookbackSeconds > 0 {
                    let calc = Int(target.lookbackSeconds / target.secondsPerInterval)
                    return max(16, min(calc, 120))
                }
                return max(16, min(target.binanceLimit, 120))
            }()

            // FIX: Increased stagger delay from 0.35s to 2.0s to reduce burst load
            let staggerDelay = 2.0 * Double(idx + 1)
            prewarmQueue.asyncAfter(deadline: .now() + staggerDelay) { [weak self] in
                guard let self = self else { return }
                
                // DEBOUNCE FIX: If the user has switched timeframes since prewarm was scheduled,
                // skip this prewarm — it's for a stale interval and would waste API calls.
                guard self.fetchSequence == seqAtStart else { return }
                
                // FIX: Re-check coordinator before each prewarm request
                guard APIRequestCoordinator.shared.canMakeRequest(for: .binance) else {
                    return  // Skip if rate limited
                }
                
                var attempts: [(ExchangeAPI, String, URL)] = []
                // FIX: Only try primary exchange first, not both in parallel
                let base: ExchangeAPI = self.isUS ? .binanceUS : .binance
                let locals = base == .binanceUS ? pairsUS : pairsPrimary
                // FIX: Include startTime for prewarm fetches to ensure correct time window
                let pwNowMs = Int(Date().timeIntervalSince1970 * 1000)
                let pwLookbackMs = Int(target.lookbackSeconds * 1.3 * 1000)
                let pwStartMs = pwLookbackMs > 0 ? pwNowMs - pwLookbackMs : 0
                for p in locals {
                    var urlStr = "\(base.rawValue)/api/v3/klines?symbol=\(p)&interval=\(target.binanceInterval)&limit=\(limitCalc)"
                    if pwStartMs > 0 {
                        urlStr += "&startTime=\(pwStartMs)"
                    }
                    if let url = URL(string: urlStr) { attempts.append((base, p, url)) }
                }
                
                self.attemptKlineRequestsNoGuard(attempts) { [weak self] data, base, pair in
                    guard let self = self, let data = data else { return }
                    self.parseForCacheOnly(data: data, symbol: symbol, interval: target)
                }
            }
        }
    }
    
    // Coinbase granularity mapping: choose the finest supported bucket that is not
    // coarser than the requested chart candle size for the selected timeframe.
    // Supported Coinbase granularities: 60, 300, 900, 3600, 21600, 86400
    private func coinbaseGranularity(for interval: ChartInterval) -> Int {
        let supported = [60, 300, 900, 3600, 21600, 86400]
        let requested = Int(interval.secondsPerInterval)
        guard requested > 0 else { return 300 }
        return supported.last(where: { $0 <= requested }) ?? supported[0]
    }

    // Normalize a symbol for Coinbase by removing separators and common quote suffixes
    private func coinbaseBaseSymbol(from raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: "-", with: "")
        for suffix in ["USDT", "USDC", "USD"] {
            if s.hasSuffix(suffix) {
                s = String(s.dropLast(suffix.count))
                break
            }
        }
        return s
    }

    // Build candidate Coinbase product IDs in preferred order
    private func coinbaseProductCandidates(for raw: String) -> [String] {
        let base = coinbaseBaseSymbol(from: raw)
        // Prefer USD, then USDT, then USDC
        return ["\(base)-USD", "\(base)-USDT", "\(base)-USDC"]
    }

    // Resample higher-frequency points to a coarser bucket size (e.g., 15m -> 30m)
    private func resample(points: [ChartDataPoint], to bucketSeconds: Int) -> [ChartDataPoint] {
        // SAFETY FIX: Safely unwrap first element
        guard bucketSeconds > 0, points.count > 1, let firstPoint = points.first else { return points }
        var result: [ChartDataPoint] = []
        var currentBucket: Int = -1
        var bucketVolume: Double = 0
        var bucketLastClose: Double = 0
        var bucketLastDate: Date = firstPoint.date

        for pt in points {
            let t = Int(pt.date.timeIntervalSince1970)
            let b = t / bucketSeconds
            if currentBucket == -1 {
                currentBucket = b
            }
            if b != currentBucket {
                // close out previous bucket
                result.append(ChartDataPoint(date: bucketLastDate, close: bucketLastClose, volume: bucketVolume))
                // start new bucket
                currentBucket = b
                bucketVolume = 0
            }
            bucketVolume += pt.volume
            bucketLastClose = pt.close
            bucketLastDate = pt.date
        }
        // append last bucket
        result.append(ChartDataPoint(date: bucketLastDate, close: bucketLastClose, volume: bucketVolume))
        return result
    }
    
    // PERFORMANCE: Downsample points for efficient indicator rendering
    // Uses LTTB-like algorithm to preserve visual shape while reducing point count
    // This prevents rendering 500+ chart marks which kills performance
    private func downsampleForRendering(_ points: [ChartDataPoint], maxPoints: Int) -> [ChartDataPoint] {
        guard points.count > maxPoints else { return points }
        
        // Simple stride-based downsampling that preserves first and last points
        // More sophisticated LTTB could be added but stride is fast and effective
        var result: [ChartDataPoint] = []
        result.reserveCapacity(maxPoints)
        
        let step = Double(points.count - 1) / Double(maxPoints - 1)
        for i in 0..<maxPoints {
            let index = min(Int(Double(i) * step), points.count - 1)
            result.append(points[index])
        }
        
        return result
    }

    private func fetchFromCoinbase(symbol: String, interval: ChartInterval, limit: Int, currentSeq: Int) {
        var products = coinbaseProductCandidates(for: symbol)
        if let last = lastResolvedCoinbaseProduct, !products.contains(last) {
            products.insert(last, at: 0)
        }
        let gran = coinbaseGranularity(for: interval)
        let requestedSec = Int(interval.secondsPerInterval)
        // IN-FLIGHT FIX: Track key for completion when all Coinbase attempts exhausted
        let inflightKey = self.cacheKey(symbol: symbol, interval: interval)

        func attempt(index: Int, currentLimit: Int, retried429: Bool) {
            guard index < products.count else {
                // IN-FLIGHT FIX: Complete tracking when Coinbase is the last fallback and all attempts fail.
                Self.completeInflightFetch(key: inflightKey)
                
                // FALLBACK FIX: If a preferred-exchange fallback was registered, try the
                // Firebase → Binance pipeline before showing "No data" error.
                // This handles the case where Coinbase candles API is down/blocked
                // but Firebase/Binance can still provide chart data.
                if let fallback = self.coinbaseFallbackClosure {
                    self.coinbaseFallbackClosure = nil  // Prevent infinite loop
                    self.logger.info("[Chart] All Coinbase products failed for \(symbol) — triggering Firebase/Binance fallback")
                    fallback()
                    return
                }
                
                // FIX: Try fallback to cached data before showing error
                if self.dataPoints.isEmpty {
                    if !self.fallbackToCache(symbol: symbol, interval: interval, errorContext: "All Binance/Coinbase attempts failed") {
                        self.showErrorAndComplete(symbol: symbol, interval: interval, message: "No data for \(symbol) on Binance/Coinbase.")
                    }
                } else {
                    // Already have data points from cache, just clear loading state
                    self.cancelLoadingTimeout()
                    self.isLoading = false
                    self.errorMessage = nil
                }
                return
            }
            let product = products[index]
            // Scale limit upward when we need to resample from a finer granularity
            let scale = (requestedSec > 0 && requestedSec > gran) ? max(1, requestedSec / gran) : 1
            // Allow more candles for timeframes that need higher resolution data
            // 1D needs 338 candles (288 visible + 50 warmup), 1W needs 722 candles
            let maxLimit: Int = {
                switch interval {
                case .oneDay:
                    return 400  // 1D needs 338 five-minute candles for 24 hours
                case .oneWeek:
                    return 750  // 1W needs 722 fifteen-minute candles for 7 days
                case .fourHour:
                    return 600  // 4H needs 554 thirty-minute candles
                case .oneYear, .threeYear, .all:
                    return 1000  // Allow more candles for long timeframes
                default:
                    return 500  // Increased default to handle most timeframes
                }
            }()
            let effectiveLimit = max(16, min(maxLimit, currentLimit * scale))
            // FIX: Include start/end time parameters to lock Coinbase data to the correct window.
            // Without these, Coinbase returns the latest candles which can be stale if CDN-cached.
            let cbEndDate = Date()
            let cbStartDate = cbEndDate.addingTimeInterval(-(interval.lookbackSeconds * 1.3))
            let cbISO = ISO8601DateFormatter()
            cbISO.formatOptions = [.withInternetDateTime]
            let cbStartStr = cbISO.string(from: cbStartDate)
            let cbEndStr = cbISO.string(from: cbEndDate)
            guard let url = URL(string: "https://api.exchange.coinbase.com/products/\(product)/candles?granularity=\(gran)&start=\(cbStartStr)&end=\(cbEndStr)&limit=\(effectiveLimit)") else {
                attempt(index: index + 1, currentLimit: currentLimit, retried429: false)
                return
            }
            
            // FIX: Check coordinator before making Coinbase request
            if !APIRequestCoordinator.shared.canMakeRequest(for: .coinbase) {
                // Rate limited - try next product after delay
                DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                    Task { @MainActor in
                        attempt(index: index + 1, currentLimit: currentLimit, retried429: false)
                    }
                }
                return
            }
            APIRequestCoordinator.shared.recordRequest(for: .coinbase)
            
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("CSAI/1.0", forHTTPHeaderField: "User-Agent")

            session.dataTask(with: req) { [weak self] data, response, error in
                Task { @MainActor in
                    guard let self = self else { return }
                    // If a newer request started, ignore
                    guard self.fetchSequence == currentSeq else {
                        self.logger.debug("[Chart][Coinbase] Discarding stale response for \(product) (seq mismatch)")
                        return
                    }
                    
                    // FIX: Handle ALL network errors (timeout, connection lost, etc.)
                    if let error = error {
                        let nsError = error as NSError
                        self.logger.warning("[Chart][Coinbase] Network error for \(product): \(error.localizedDescription) (code: \(nsError.code))")
                        if nsError.code == NSURLErrorTimedOut {
                            APIRequestCoordinator.shared.recordFailure(for: .coinbase)
                        }
                        // Try next product candidate
                        attempt(index: index + 1, currentLimit: limit, retried429: false)
                        return
                    }

                    if let http = response as? HTTPURLResponse {
                        // LOG: Show HTTP status for debugging chart load failures
                        if http.statusCode != 200 {
                            self.logger.warning("[Chart][Coinbase] HTTP \(http.statusCode) for \(product)")
                        }
                        if http.statusCode == 429 {
                            APIRequestCoordinator.shared.recordFailure(for: .coinbase)
                            // Rate limited: back off once by halving the limit for this product
                            let nextLimit = max(16, currentLimit / 2)
                            if !retried429 && nextLimit < currentLimit {
                                attempt(index: index, currentLimit: nextLimit, retried429: true)
                                return
                            } else {
                                attempt(index: index + 1, currentLimit: limit, retried429: false)
                                return
                            }
                        }
                        // Handle other error status codes (400, 403, 500, etc.)
                        if http.statusCode != 200 && http.statusCode != 404 {
                            // Non-success, non-404: try next product
                            attempt(index: index + 1, currentLimit: limit, retried429: false)
                            return
                        }
                        if http.statusCode == 404 {
                            // Product not found on Coinbase, try next candidate
                            attempt(index: index + 1, currentLimit: limit, retried429: false)
                            return
                        }
                    }

                    if let data = data,
                       let arr = try? JSONSerialization.jsonObject(with: data) as? [[Any]],
                       !arr.isEmpty {
                        // Coinbase returns newest first; map then sort ascending
                        var pts: [ChartDataPoint] = []
                        for entry in arr {
                            guard entry.count >= 6 else { continue }
                            // Format: [ time, low, high, open, close, volume ]
                            let tSec: Double = {
                                if let d = entry[0] as? Double { return d }
                                if let i = entry[0] as? Int { return Double(i) }
                                if let s = entry[0] as? String, let d = Double(s) { return d }
                                return 0
                            }()
                            let closeAny = entry[4]
                            let volAny = entry[5]
                            let close: Double? = {
                                if let d = closeAny as? Double { return d }
                                if let s = closeAny as? String { return Double(s) }
                                return nil
                            }()
                            let volume: Double? = {
                                if let d = volAny as? Double { return d }
                                if let s = volAny as? String { return Double(s) }
                                return nil
                            }()
                            // VALIDATION: Skip zero/negative prices
                            if let c = close, c > 0 {
                                let date = Date(timeIntervalSince1970: tSec)
                                pts.append(.init(date: date, close: c, volume: max(0, volume ?? 0)))
                            }
                        }
                        pts.sort { $0.date < $1.date }

                        // If Coinbase granularity differs from the requested interval, resample to match visuals
                        if requestedSec > 0 && requestedSec != gran {
                            pts = self.resample(points: pts, to: requestedSec)
                        }
                        
                        // DATA CONSISTENCY FIX: Filter Coinbase data to correct time window.
                        let cbLookback = interval.lookbackSeconds
                        if cbLookback > 0 {
                            let cbCutoff = Date().addingTimeInterval(-(cbLookback * 1.3))
                            pts = pts.filter { $0.date >= cbCutoff }
                        }

                        // Reject stale Coinbase candles and continue fallback chain.
                        if let latestDate = pts.last?.date {
                            let dataAge = Date().timeIntervalSince(latestDate)
                            let maxFreshAge = interval.maxAllowedDataAge
                            if dataAge > maxFreshAge {
                                self.logger.warning("[Chart][Coinbase] STALE candles for \(product) \(interval.rawValue): latest \(Int(dataAge))s old (max \(Int(maxFreshAge))s) — trying fallback")
                                attempt(index: index + 1, currentLimit: limit, retried429: false)
                                return
                            }
                        }

                        let key = self.cacheKey(symbol: symbol, interval: interval)
                        self.saveCache(points: pts, key: key)
                        // FIX: Record success to decrement active request count
                        APIRequestCoordinator.shared.recordSuccess(for: .coinbase)
                        // FIX: Complete in-flight tracking on Coinbase success
                        Self.completeInflightFetch(key: key)
                        // RACE CONDITION FIX: Re-check sequence.
                        guard self.fetchSequence == currentSeq else { return }
                        
                        self.cancelLoadingTimeout()
                        self.isLoading = false
                        self.errorMessage = nil
                        // Only update volumeScaleMax if it wasn't already set from cache
                        let newCeiling = self.volumeCeiling(from: pts)
                        let currentCount = self.dataPoints.count
                        if self.volumeScaleMax == nil || self.volumeScaleMax! < 1 || 
                           (currentCount == 0) || (pts.count > currentCount * 2) {
                            self.volumeScaleMax = newCeiling
                        }
                        // LIVE MODE GUARD: Don't overwrite WebSocket data with candle data.
                        if !self.isLiveModeActive {
                            self.dataPoints = pts
                        }
                        // Mark volume data as stable now that fresh API data has been processed
                        self.volumeDataStable = true
                        // Remember the working product for next time
                        self.lastResolvedCoinbaseProduct = product
                    } else {
                        // Try next Coinbase product candidate
                        let dataLen = data?.count ?? 0
                        let preview = data.flatMap { String(data: $0.prefix(200), encoding: .utf8) } ?? "nil"
                        self.logger.warning("[Chart][Coinbase] No valid candle data from \(product) (data bytes: \(dataLen), preview: \(preview))")
                        attempt(index: index + 1, currentLimit: limit, retried429: false)
                    }
                }
            }.resume()
        }

        // Kick off attempts across product candidates
        attempt(index: 0, currentLimit: max(16, limit), retried429: false)
    }
    
    // MARK: - Firebase Chart Cache Helpers
    
    /// Map ChartInterval to Firebase interval string
    /// IMPORTANT: Must match binanceInterval to get the correct candle granularity
    /// E.g., 1D view needs 5-minute candles (288 candles = 24 hours), not daily candles
    private func firebaseIntervalString(for interval: ChartInterval) -> String {
        // Return the same granularity as binanceInterval for consistency
        // This ensures Firebase returns the same candle resolution as direct Binance calls
        return interval.binanceInterval
    }
    
    /// Fallback: Direct API fetch when Firebase is unavailable
    /// Contains the original direct API fetching logic
    private func fetchDataDirectAPI(symbol: String, interval: ChartInterval, indicatorBuffer: Int, currentSeq: Int, hasDataToShow: Bool, key: String) {
        let pairs = candidateSymbols(for: symbol, preferUSD: QuotePreferenceStore.prefersUSD(isUSUser: self.isUS))
        
        // Live interval handled by caller, not this method
        guard interval != .live else { return }
        
        // Special handling for ALL and 3Y timeframes: use CoinGecko for complete historical data
        if interval == .all || interval == .threeYear {
            if !hasDataToShow {
                self.isLoading = true
                self.startLoadingTimeout(for: symbol, interval: interval)
            }
            self.errorMessage = nil
            
            let days: Int? = interval == .threeYear ? 1095 : nil
            let timeframeName = interval == .threeYear ? "3Y" : "ALL"
            
            self.fetchFromCoinGecko(symbol: symbol, interval: interval, days: days, currentSeq: currentSeq) { [weak self] in
                guard let self = self else { return }
                print("[\(timeframeName)] CoinGecko failed, falling back to Binance")
                let nowMs = Date().timeIntervalSince1970 * 1000
                let startTime: TimeInterval = interval == .threeYear
                    ? nowMs - TimeInterval(156 * 7 * 86_400 * 1000)
                    : 1262304000 * 1000
                let bases: [ExchangeAPI] = [.binance, .binanceUS]
                var attempts: [(ExchangeAPI, String, URL)] = []
                let preferUSD = QuotePreferenceStore.prefersUSD(isUSUser: self.isUS)
                for base in bases {
                    let localPairs = (base == .binanceUS)
                        ? candidateSymbols(for: symbol, preferUSD: true)
                        : candidateSymbols(for: symbol, preferUSD: preferUSD)
                    for p in localPairs {
                        let urlStr = "\(base.rawValue)/api/v3/klines?symbol=\(p)&interval=1w&startTime=\(Int(startTime))&limit=1000"
                        if let url = URL(string: urlStr) {
                            attempts.append((base, p, url))
                        }
                    }
                }
                self.attemptKlineRequests(attempts, currentSeq: currentSeq) { [weak self] data, base, pair in
                    guard let self = self else { return }
                    guard self.fetchSequence == currentSeq else { return }
                    if let data, let base, let pair {
                        self.isUS = (base == .binanceUS)
                        self.lastResolvedPair = pair
                        self.parseAndCache(data: data, symbol: symbol, interval: interval, expectedSeq: currentSeq)
                        self.prewarmCache(for: symbol, excluding: interval)
                    } else {
                        self.fetchFromCoinbase(symbol: symbol, interval: interval, limit: 1000, currentSeq: currentSeq)
                    }
                }
            }
            return
        }
        
        // For other intervals, use the standard Binance fetch logic
        self.fetchDataBinanceWithFallback(symbol: symbol, interval: interval, indicatorBuffer: indicatorBuffer, currentSeq: currentSeq, hasDataToShow: hasDataToShow, pairs: pairs)
    }
    
    /// Standard Binance fetch with Coinbase fallback
    private func fetchDataBinanceWithFallback(symbol: String, interval: ChartInterval, indicatorBuffer: Int, currentSeq: Int, hasDataToShow: Bool, pairs: [String]) {
        // Special handling for 1Y: use daily candles with startTime
        if interval == .oneYear {
            let nowMs = Date().timeIntervalSince1970 * 1000
            let requestInterval = "1d"
            let requestLimit = 415
            let startTimeMs: TimeInterval = nowMs - TimeInterval(415 * 86_400 * 1000)

            let bases: [ExchangeAPI] = [.binance, .binanceUS]
            if !hasDataToShow {
                self.isLoading = true
                self.startLoadingTimeout(for: symbol, interval: interval)
            }
            self.errorMessage = nil
            var attempts: [(ExchangeAPI, String, URL)] = []
            let preferUSD = QuotePreferenceStore.prefersUSD(isUSUser: self.isUS)
            for base in bases {
                let localPairs = (base == .binanceUS)
                    ? candidateSymbols(for: symbol, preferUSD: true)
                    : candidateSymbols(for: symbol, preferUSD: preferUSD)
                for p in localPairs {
                    let urlStr = "\(base.rawValue)/api/v3/klines?symbol=\(p)&interval=\(requestInterval)&startTime=\(Int(startTimeMs))&limit=\(requestLimit)"
                    if let url = URL(string: urlStr) {
                        attempts.append((base, p, url))
                    }
                }
            }
            self.attemptKlineRequests(attempts, currentSeq: currentSeq) { [weak self] data, base, pair in
                guard let self = self else { return }
                guard self.fetchSequence == currentSeq else { return }
                if let data, let base, let pair {
                    self.isUS = (base == .binanceUS)
                    self.lastResolvedPair = pair
                    self.parseAndCache(data: data, symbol: symbol, interval: interval, expectedSeq: currentSeq)
                    self.prewarmCache(for: symbol, excluding: interval)
                } else {
                    self.fetchFromCoinbase(symbol: symbol, interval: interval, limit: requestLimit, currentSeq: currentSeq)
                }
            }
            return
        }
        
        // Standard interval handling (not 1Y, ALL, or 3Y)
        let binInt = interval.binanceInterval
        let limit = interval.binanceLimit
        let bases: [ExchangeAPI] = [.binance, .binanceUS]
        
        if !hasDataToShow {
            self.isLoading = true
            self.startLoadingTimeout(for: symbol, interval: interval)
        }
        self.errorMessage = nil
        
        var attempts: [(ExchangeAPI, String, URL)] = []
        let preferUSD = QuotePreferenceStore.prefersUSD(isUSUser: self.isUS)
        // FIX: Include startTime to lock the data to the correct time window.
        // Prevents stale CDN/proxy cached responses from shifting the X-axis.
        let bfNowMs = Int(Date().timeIntervalSince1970 * 1000)
        let bfLookbackMs = Int(interval.lookbackSeconds * 1.3 * 1000) // 30% buffer for indicator warm-up
        let bfStartMs = bfNowMs - bfLookbackMs
        for base in bases {
            let localPairs = (base == .binanceUS)
                ? candidateSymbols(for: symbol, preferUSD: true)
                : candidateSymbols(for: symbol, preferUSD: preferUSD)
            for p in localPairs {
                let urlStr = "\(base.rawValue)/api/v3/klines?symbol=\(p)&interval=\(binInt)&startTime=\(bfStartMs)&limit=\(limit)"
                if let url = URL(string: urlStr) {
                    attempts.append((base, p, url))
                }
            }
        }
        self.attemptKlineRequests(attempts, currentSeq: currentSeq) { [weak self] data, base, pair in
            guard let self = self else { return }
            guard self.fetchSequence == currentSeq else { return }
            if let data, let base, let pair {
                self.isUS = (base == .binanceUS)
                self.lastResolvedPair = pair
                self.parseAndCache(data: data, symbol: symbol, interval: interval, expectedSeq: currentSeq)
                self.prewarmCache(for: symbol, excluding: interval)
            } else {
                self.fetchFromCoinbase(symbol: symbol, interval: interval, limit: limit, currentSeq: currentSeq)
            }
        }
    }
    
    // MARK: - CoinGecko Fetch (for ALL timeframe with full historical data)
    
    /// Map common ticker symbols to CoinGecko IDs
    private func coingeckoID(for symbol: String) -> String {
        let s = symbol.uppercased()
            .replacingOccurrences(of: "USDT", with: "")
            .replacingOccurrences(of: "USD", with: "")
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: "-", with: "")
        switch s {
        case "BTC": return "bitcoin"
        case "ETH": return "ethereum"
        case "SOL": return "solana"
        case "XRP": return "ripple"
        case "DOGE": return "dogecoin"
        case "ADA": return "cardano"
        case "AVAX": return "avalanche-2"
        case "DOT": return "polkadot"
        case "LINK": return "chainlink"
        case "MATIC", "POL": return "matic-network"
        case "SHIB": return "shiba-inu"
        case "LTC": return "litecoin"
        case "UNI": return "uniswap"
        case "ATOM": return "cosmos"
        case "XLM": return "stellar"
        case "BCH": return "bitcoin-cash"
        case "FIL": return "filecoin"
        case "APT": return "aptos"
        case "ARB": return "arbitrum"
        case "OP": return "optimism"
        case "NEAR": return "near"
        case "INJ": return "injective-protocol"
        case "SUI": return "sui"
        case "SEI": return "sei-network"
        case "TIA": return "celestia"
        case "PEPE": return "pepe"
        case "WIF": return "dogwifcoin"
        case "BONK": return "bonk"
        default: return s.lowercased()
        }
    }
    
    /// Fetch historical data from CoinGecko for ALL and 3Y timeframes.
    /// CoinGecko has data going back to 2013 for Bitcoin, providing complete history.
    /// - Parameters:
    ///   - symbol: The trading symbol (e.g., "BTC")
    ///   - interval: The chart interval (.all or .threeYear)
    ///   - days: Number of days of history to fetch. Pass nil for "max" (all available data)
    ///   - currentSeq: Current fetch sequence for request deduplication
    ///   - fallback: Closure to call if CoinGecko fails
    private func fetchFromCoinGecko(symbol: String, interval: ChartInterval, days: Int?, currentSeq: Int, fallback: @escaping () -> Void) {
        let coinID = coingeckoID(for: symbol)
        
        // IN-FLIGHT FIX: Complete in-flight tracking in all exit paths.
        // fetchFromCoinGecko is often the last fallback in the chain (Binance → Coinbase → CoinGecko).
        // If it fails without completing in-flight tracking, subsequent fetches for this key
        // are permanently blocked by the deduplication system, causing "data never loads".
        let inflightKey = self.cacheKey(symbol: symbol, interval: interval)
        
        // Build CoinGecko market_chart URL
        // For ALL: use days=max for complete history
        // For 3Y: use days=1095 (3 years) for precise timeframe
        let daysValue = days.map { String($0) } ?? "max"
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.coingecko.com"
        components.path = "/api/v3/coins/\(coinID)/market_chart"
        components.queryItems = [
            URLQueryItem(name: "vs_currency", value: CurrencyManager.apiValue),
            URLQueryItem(name: "days", value: daysValue)
        ]
        
        guard let url = components.url else {
            Self.completeInflightFetch(key: inflightKey)
            fallback()
            return
        }
        
        var request = APIConfig.coinGeckoRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        
        session.dataTask(with: request) { [weak self] data, response, error in
            Task { @MainActor in
                guard let self = self else { return }
                
                // Check if this request is still relevant
                guard self.fetchSequence == currentSeq else { return }
                
                let timeframeName = interval == .threeYear ? "3Y" : "ALL"
                
                // Handle network errors
                if let error = error {
                    print("[CoinGecko] Error fetching \(timeframeName) data: \(error.localizedDescription)")
                    Self.completeInflightFetch(key: inflightKey)
                    fallback()
                    return
                }
                
                // Check HTTP response
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("[CoinGecko] Invalid response type for \(timeframeName) timeframe")
                    Self.completeInflightFetch(key: inflightKey)
                    fallback()
                    return
                }
                
                // Handle rate limiting (429) and other errors
                if httpResponse.statusCode == 429 {
                    print("[CoinGecko] Rate limited (429) for \(timeframeName) timeframe - falling back to Binance")
                    Self.completeInflightFetch(key: inflightKey)
                    fallback()
                    return
                }
                
                guard httpResponse.statusCode == 200 else {
                    print("[CoinGecko] HTTP \(httpResponse.statusCode) for \(timeframeName) timeframe")
                    Self.completeInflightFetch(key: inflightKey)
                    fallback()
                    return
                }
                
                guard let data = data else {
                    print("[CoinGecko] No data received for \(timeframeName) timeframe")
                    Self.completeInflightFetch(key: inflightKey)
                    fallback()
                    return
                }
                
                // Parse CoinGecko response: { "prices": [[timestamp, price], ...], "market_caps": [...], "total_volumes": [...] }
                do {
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    guard let pricesArray = json?["prices"] as? [[Double]],
                          let volumesArray = json?["total_volumes"] as? [[Double]] else {
                        print("[CoinGecko] Missing prices/volumes in response for \(timeframeName)")
                        Self.completeInflightFetch(key: inflightKey)
                        fallback()
                        return
                    }
                    
                    // Build volume lookup by timestamp (rounded to day)
                    var volumeMap: [Int: Double] = [:]
                    for vol in volumesArray {
                        if vol.count >= 2 {
                            let dayKey = Int(vol[0] / 1000 / 86400) // Round to day
                            volumeMap[dayKey] = vol[1]
                        }
                    }
                    
                    // Convert to ChartDataPoint array
                    var pts: [ChartDataPoint] = []
                    for price in pricesArray {
                        if price.count >= 2 {
                            let timestamp = price[0] / 1000 // Convert ms to seconds
                            let date = Date(timeIntervalSince1970: timestamp)
                            let closePrice = price[1]
                            // VALIDATION: Skip zero/negative prices to prevent chart drop-offs
                            guard closePrice > 0 else { continue }
                            let dayKey = Int(timestamp / 86400)
                            let volume = volumeMap[dayKey] ?? 0
                            pts.append(ChartDataPoint(date: date, close: closePrice, volume: volume))
                        }
                    }
                    
                    // Validate we got meaningful data (at least ~2 years of weekly data for 3Y, ~5 years for ALL)
                    let minPoints = interval == .threeYear ? 80 : 100
                    guard pts.count >= minPoints else {
                        print("[CoinGecko] Insufficient data points for \(timeframeName): \(pts.count) (need \(minPoints))")
                        Self.completeInflightFetch(key: inflightKey)
                        fallback()
                        return
                    }
                    
                    pts.sort { $0.date < $1.date }
                    
                    // Resample to weekly for consistency with the ALL timeframe display
                    // This reduces data density and matches the expected candle interval
                    let weeklyPoints = self.resample(points: pts, to: 604800) // 7 days in seconds
                    
                    let key = self.cacheKey(symbol: symbol, interval: interval)
                    self.saveCache(points: weeklyPoints, key: key)
                    Self.completeInflightFetch(key: inflightKey)
                    
                    // RACE CONDITION FIX: Check sequence before assigning data
                    guard self.fetchSequence == currentSeq else { return }
                    
                    self.cancelLoadingTimeout()
                    self.isLoading = false
                    self.errorMessage = nil
                    let newCeiling = self.volumeCeiling(from: weeklyPoints)
                    if self.volumeScaleMax == nil || self.volumeScaleMax! < 1 {
                        self.volumeScaleMax = newCeiling
                    }
                    // LIVE MODE GUARD: Don't overwrite WebSocket data with candle data.
                    if !self.isLiveModeActive {
                        self.dataPoints = weeklyPoints
                    }
                    self.volumeDataStable = true
                    print("[CoinGecko] Successfully loaded \(timeframeName) data: \(weeklyPoints.count) weekly points from \(weeklyPoints.first?.date ?? Date()) to \(weeklyPoints.last?.date ?? Date())")
                } catch {
                    print("[CoinGecko] JSON parsing error for \(timeframeName): \(error)")
                    Self.completeInflightFetch(key: inflightKey)
                    fallback()
                }
            }
        }.resume()
    }
}

// MARK: – View
struct CryptoChartView: View {
    let symbol  : String
    let interval: ChartInterval
    let height  : CGFloat
    /// When true, the volume sub-chart pads its right edge to align with the price chart's trailing axis/price badge.
    /// When false, the volume bars extend fully to the right (no extra trailing padding).
    let alignVolumeToPriceAxis: Bool
    /// When true, shows a price change percentage badge in the top-left corner of the chart.
    /// Set to false on coin detail pages where the percentage is already shown in the header.
    let showPercentageBadge: Bool
    /// Optional live price from parent view (e.g., TradeView). When provided and user is at rightmost
    /// chart position, the crosshair tooltip will show this live price instead of the candle close price
    /// for a seamless, professional sync with the header price.
    let livePrice: Double?
    /// Optional exchange preference. When provided, the chart will try to fetch data from this exchange first.
    /// Currently supported for chart data: "coinbase" (fetches directly from Coinbase API).
    /// Other exchanges (binance, kraken, kucoin) use Binance/Coinbase as the data source.
    /// Note: The order book always fetches from the user's selected exchange for accurate depth data.
    let preferredExchange: String?

    init(symbol: String, interval: ChartInterval, height: CGFloat, alignVolumeToPriceAxis: Bool = true, showPercentageBadge: Bool = true, livePrice: Double? = nil, preferredExchange: String? = nil) {
        self.symbol = symbol
        self.interval = interval
        self.height = height
        self.alignVolumeToPriceAxis = alignVolumeToPriceAxis
        self.showPercentageBadge = showPercentageBadge
        self.livePrice = livePrice
        self.preferredExchange = preferredExchange
    }

    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var vm             = CryptoChartViewModel()
    @State private var showCrosshair        = false
    @State private var crosshairDataPoint   : ChartDataPoint? = nil
    // Normalized x position (0-1) for crosshair alignment across all chart panes
    // This ensures pixel-perfect alignment regardless of individual chart rendering differences
    @State private var crosshairXFraction   : CGFloat = 0
    @State private var now: Date = Date()
    @State private var shouldAnimate = false
    @State private var pulse = false
    @State private var showLiveDotOverlay = true
    @AppStorage("Chart.ShowVolume") private var showVolumeOverlay: Bool = true
    // When true, volume is integrated as semi-transparent overlay at bottom of price chart (TradingView-style)
    // When false, volume is shown as a separate pane below the price chart
    @AppStorage("Chart.VolumeIntegrated") private var volumeIntegrated: Bool = true
    // Persist last measured insets so they're available immediately on next view appearance
    // This eliminates layout shifts when returning to the chart
    @AppStorage("Chart.CachedTrailingInset") private var cachedTrailingInset: Double = 40
    @AppStorage("Chart.CachedLeadingInset") private var cachedLeadingInset: Double = 4
    @AppStorage("Chart.CachedPlotWidth") private var cachedPlotWidth: Double = 300
    // Runtime inset values - start from cached values
    @State private var pricePlotTrailingInset: CGFloat = 40
    @State private var pricePlotLeadingInset: CGFloat = 4
    @State private var plotAreaWidth: CGFloat = 300
    // Bottom inset: distance from plot area bottom to chart frame bottom (includes x-axis labels + internal gap)
    // Used for precise clipping when sub-charts are below
    @State private var pricePlotBottomInset: CGFloat = 22
    // Flag to track if we've measured the plot area this session
    @State private var hasValidInsets: Bool = false

    // Haptic feedback state tracking
    @State private var lastHapticIndex: Int? = nil
    @State private var lastAboveBaseline: Bool? = nil
    // HAPTIC FIX: Session min/max track USER'S EXPLORED RANGE, not chart extremes
    @State private var hapticSessionMin: Double? = nil
    @State private var hapticSessionMax: Double? = nil
    @State private var hapticSessionStarted: Bool = false

    @State private var currentSymbol: String = ""
    @State private var stableMaxVolume: Double = 1
    
    // SEAMLESS TIMEFRAME SWITCH: Track which interval the currently displayed data belongs to.
    // During a timeframe switch, `interval` updates immediately but data takes time to load.
    // Using `displayInterval` for axis rendering ensures labels always match the visible data,
    // preventing the "broken chart flash" where new-interval labels are applied to old-interval data.
    @State private var displayInterval: ChartInterval = .oneHour
    
    // STABILITY: Cached Y-domain to prevent constant chart readjustment from live price updates
    // Only updates when prices exceed current bounds by a significant margin
    @State private var stableYDomainCache: ClosedRange<Double>?
    @State private var stableXDomainCache: ClosedRange<Date>?   // Freeze X-domain during timeframe switch
    @State private var lastYDomainUpdateAt: Date = .distantPast
    /// Timestamp of the most recent timeframe switch. Used to reduce the Y-domain stability
    /// interval from 8s to 2s for the first 10 seconds after a switch, preventing the visible
    /// "readjustment" where the chart renders at wrong scale before correcting itself.
    @State private var lastTimeframeSwitchAt: Date = .distantPast
    /// Set true on symbol change — forces Y-domain recomputation when first data arrives.
    /// This prevents stale cache data's Y-domain from persisting after fresh data replaces it.
    @State private var needsYDomainRefresh: Bool = false
    // HYSTERESIS: Track consecutive buffer exceedances before triggering rescale
    // This prevents rescaling from brief price spikes, requiring sustained movement
    @State private var consecutiveBufferExceedances: Int = 0
    private let requiredConsecutiveExceedances: Int = 2  // Require 2 consecutive exceedances to rescale
    
    // Flag to track when initial layout is ready (prevents animation during @AppStorage initialization)
    @State private var isLayoutReady: Bool = false
    
    // PROFESSIONAL UX: No visible loading indicators during timeframe switching.
    // Old data remains visible until new data seamlessly replaces it.
    // Removed debounced refresh indicator for a cleaner, professional experience.
    
    // SEAMLESS TIMEFRAME SWITCH: Flag to bypass Y-domain stability cache while waiting for new data
    // When true, yDomain always recomputes fresh from current data, ensuring the live price line
    // is correctly positioned the instant new timeframe data arrives
    @State private var pendingDataSwitch: Bool = false
    /// Tracks whether we've already retried due to stale data, to prevent infinite retry loops.
    @State private var didRetryForStaleData: Bool = false

    // RACE CONDITION FIX: Cancellable work items for the 4s and 15s safety timeouts
    // during timeframe switches. Without cancellation, rapid switching (e.g., 1m->5m->15m)
    // causes stale timeouts from earlier switches to fire and clear caches for the wrong interval.
    @State private var switchSafetyTimeout4s: DispatchWorkItem? = nil
    @State private var switchSafetyTimeout15s: DispatchWorkItem? = nil
    
    // DEBOUNCE FIX: Cancellable work item for the network fetch triggered by timeframe switch.
    // Rapid switching (e.g., 1D→4H→1W→30m) without debouncing fires 4 simultaneous fetches.
    // Only the LAST switch should trigger a network request; earlier ones are cancelled.
    @State private var debouncedFetchWork: DispatchWorkItem? = nil
    // Track the previous interval so we can cancel its in-flight fetch on switch
    @State private var previousInterval: ChartInterval? = nil
    
    // PERFORMANCE: Cached indicator computations to avoid recalculating on every render
    // Indicators are only recomputed when source data changes (tracked by indicatorDataVersion)
    @State private var cachedSMAPoints: [ChartDataPoint] = []
    @State private var cachedEMAPoints: [ChartDataPoint] = []
    @State private var cachedBBUpper: [ChartDataPoint] = []
    @State private var cachedBBMiddle: [ChartDataPoint] = []
    @State private var cachedBBLower: [ChartDataPoint] = []
    @State private var cachedVWAPPoints: [ChartDataPoint] = []
    @State private var indicatorDataVersion: Int = 0  // Track data changes
    @State private var indicatorSettingsVersion: Int = 0  // Track settings changes
    
    // PERFORMANCE: Cached resampled data points to avoid recalculating on every render
    // Resampling is expensive for large datasets; cache invalidates when data count or domain changes
    @State private var cachedResampledPoints: [ChartDataPoint] = []
    @State private var lastResampledDataCount: Int = 0
    @State private var lastResampledDomainHash: Int = 0  // Track domain to invalidate on timeframe change
    
    // PERFORMANCE: Cached volume stats to avoid recalculating on every render
    // These are used for volume overlay scaling and bar widths
    @State private var cachedMaxVolume: Double = 1
    @State private var cachedTypicalInterval: TimeInterval = 300  // Default 5 min
    @State private var lastVolumeStatsDataCount: Int = 0
    
    // PERFORMANCE: Cached visible points (filtered by X domain) to avoid filtering on every render
    @State private var cachedVisibleSMAPoints: [ChartDataPoint] = []
    @State private var cachedVisibleEMAPoints: [ChartDataPoint] = []
    @State private var cachedVisibleBBUpper: [ChartDataPoint] = []
    @State private var cachedVisibleBBMiddle: [ChartDataPoint] = []
    @State private var cachedVisibleBBLower: [ChartDataPoint] = []
    @State private var cachedVisibleVWAPPoints: [ChartDataPoint] = []
    @State private var lastCachedXDomain: ClosedRange<Date>?
    
    // *** Added user-configurable toggles per instruction #1 ***
    @AppStorage("Chart.ShowSeparators") private var userShowSeparators: Bool = true
    @AppStorage("Chart.ShowNowLine") private var userShowNowLine: Bool = true
    @AppStorage("Chart.WeekendShading") private var userWeekendShading: Bool = false
    @AppStorage("Chart.LiveLinearInterpolation") private var userLiveLinearInterpolation: Bool = false

    @AppStorage("Chart.Indicators.SMA.Enabled") private var indSMAEnabled: Bool = false
    @AppStorage("Chart.Indicators.SMA.Period") private var indSMAPeriod: Int = 20
    @AppStorage("Chart.Indicators.EMA.Enabled") private var indEMAEnabled: Bool = false
    @AppStorage("Chart.Indicators.EMA.Period") private var indEMAPeriod: Int = 50
    
    // Bollinger Bands settings
    @AppStorage("Chart.Indicators.BB.Enabled") private var indBBEnabled: Bool = false
    @AppStorage("Chart.Indicators.BB.Period") private var indBBPeriod: Int = 20
    @AppStorage("Chart.Indicators.BB.Dev") private var indBBDev: Double = 2.0
    
    // RSI settings
    @AppStorage("Chart.Indicators.RSI.Enabled") private var indRSIEnabled: Bool = false
    @AppStorage("Chart.Indicators.RSI.Period") private var indRSIPeriod: Int = 14

    // MACD settings
    @AppStorage("Chart.Indicators.MACD.Enabled") private var indMACDEnabled: Bool = false
    @AppStorage("Chart.Indicators.MACD.Fast") private var indMACDFast: Int = 12
    @AppStorage("Chart.Indicators.MACD.Slow") private var indMACDSlow: Int = 26
    @AppStorage("Chart.Indicators.MACD.Signal") private var indMACDSignal: Int = 9

    // Stochastic settings
    @AppStorage("Chart.Indicators.Stoch.Enabled") private var indStochEnabled: Bool = false
    @AppStorage("Chart.Indicators.Stoch.K") private var indStochK: Int = 14
    @AppStorage("Chart.Indicators.Stoch.D") private var indStochD: Int = 3

    // Advanced indicators (VWAP, ATR, OBV, MFI)
    @AppStorage("Chart.Indicators.VWAP.Enabled") private var indVWAPEnabled: Bool = false
    @AppStorage("Chart.Indicators.ATR.Enabled") private var indATREnabled: Bool = false
    @AppStorage("Chart.Indicators.ATR.Period") private var indATRPeriod: Int = 14
    @AppStorage("Chart.Indicators.OBV.Enabled") private var indOBVEnabled: Bool = false
    @AppStorage("Chart.Indicators.MFI.Enabled") private var indMFIEnabled: Bool = false
    @AppStorage("Chart.Indicators.MFI.Period") private var indMFIPeriod: Int = 14

    // *** Inserted new @AppStorage for legend visibility ***
    @AppStorage("Chart.Indicators.ShowLegend") private var indShowLegend: Bool = true
    
    // Volume MA settings
    @AppStorage("Chart.Volume.MA.Enabled") private var volumeMAEnabled: Bool = false
    @AppStorage("Chart.Volume.MA.Period") private var volumeMAPeriod: Int = 20

    // Added computed property to count active indicators
    private var activeIndicatorCount: Int { (indSMAEnabled ? 1 : 0) + (indEMAEnabled ? 1 : 0) + (indBBEnabled ? 1 : 0) + (indRSIEnabled ? 1 : 0) + (indMACDEnabled ? 1 : 0) + (indStochEnabled ? 1 : 0) + (volumeMAEnabled ? 1 : 0) + (indVWAPEnabled ? 1 : 0) + (indATREnabled ? 1 : 0) + (indOBVEnabled ? 1 : 0) + (indMFIEnabled ? 1 : 0) }
    
    // Count only overlay indicators (SMA/EMA/BB/VWAP) that have legend badges
    private var overlayIndicatorCount: Int { (indSMAEnabled ? 1 : 0) + (indEMAEnabled ? 1 : 0) + (indBBEnabled ? 1 : 0) + (indVWAPEnabled ? 1 : 0) }
    
    // Maximum period of all enabled indicators (for dynamic warm-up buffer calculation)
    private var maxIndicatorPeriod: Int {
        var maxPeriod = 0
        if indSMAEnabled { maxPeriod = max(maxPeriod, indSMAPeriod) }
        if indEMAEnabled { maxPeriod = max(maxPeriod, indEMAPeriod) }
        if indBBEnabled { maxPeriod = max(maxPeriod, indBBPeriod) }
        if indRSIEnabled { maxPeriod = max(maxPeriod, indRSIPeriod) }
        // MACD needs slow + signal periods for full calculation
        if indMACDEnabled { maxPeriod = max(maxPeriod, indMACDSlow + indMACDSignal) }
        if indStochEnabled { maxPeriod = max(maxPeriod, indStochK + indStochD) }
        if volumeMAEnabled { maxPeriod = max(maxPeriod, volumeMAPeriod) }
        // Advanced indicators
        if indATREnabled { maxPeriod = max(maxPeriod, indATRPeriod) }
        if indMFIEnabled { maxPeriod = max(maxPeriod, indMFIPeriod) }
        return maxPeriod
    }
    
    // Count of enabled oscillator indicators (RSI, MACD, Stochastic, ATR, MFI, OBV)
    private var enabledOscillatorCount: Int {
        (indRSIEnabled ? 1 : 0) + (indMACDEnabled ? 1 : 0) + (indStochEnabled ? 1 : 0) + (indATREnabled ? 1 : 0) + (indMFIEnabled ? 1 : 0) + (indOBVEnabled ? 1 : 0)
    }
    
    // Dynamic height for oscillator panes based on how many are enabled
    // More aggressive compression when many oscillators are stacked
    private var oscillatorHeight: CGFloat {
        switch enabledOscillatorCount {
        case 1: return 72   // Give single oscillator more room for readability
        case 2: return 55
        case 3: return 44
        case 4: return 38
        case 5: return 34
        default: return enabledOscillatorCount >= 6 ? 30 : 72
        }
    }
    
    // Compact mode when 2+ oscillators are stacked
    private var isCompactOscillatorMode: Bool {
        enabledOscillatorCount >= 2
    }
    
    // Extra compact mode when 3+ oscillators are stacked
    private var isExtraCompactMode: Bool {
        enabledOscillatorCount >= 3
    }
    
    // Volume pane height - taller when showing x-axis labels at bottom
    private var volumePaneHeight: CGFloat {
        isVolumeBottomChart ? 70 : 52  // Add 18px for x-axis labels when at bottom
    }
    
    // Total height consumed by indicator panes below the price chart
    private var indicatorPanesHeight: CGFloat {
        var total: CGFloat = 0
        // Volume pane (only when shown as separate pane, not integrated)
        // Use displayInterval to prevent layout jumps during timeframe transitions
        if displayInterval != .live && showVolumeOverlay && !volumeIntegrated {
            total += volumePaneHeight // No spacing - VStack uses 0
        }
        // Each oscillator pane
        let oscillatorCount = enabledOscillatorCount
        if displayInterval != .live && oscillatorCount > 0 {
            total += CGFloat(oscillatorCount) * oscillatorHeight
        }
        return total
    }
    
    // True when there are sub-charts (volume or oscillators) below the price chart
    // Used to hide x-axis labels on price chart to prevent overlap
    private var hasSubChartsBelow: Bool {
        guard displayInterval != .live else { return false }
        // Volume only counts as sub-chart when shown as separate pane (not integrated)
        let hasVolumePaneBelow = showVolumeOverlay && !volumeIntegrated
        return hasVolumePaneBelow || enabledOscillatorCount > 0
    }
    
    // Height reserved for x-axis labels when shown at the bottom of a chart
    private let xAxisLabelHeight: CGFloat = 18
    
    // Actual measured bottom inset from the price chart (includes x-axis labels + ticks + internal gap)
    // Falls back to xAxisLabelHeight if not yet measured
    private var effectiveBottomInset: CGFloat {
        hasSubChartsBelow ? pricePlotBottomInset : xAxisLabelHeight
    }
    
    // Remaining height for the main price chart
    // Always subtracts the bottom inset because:
    // - Without sub-charts: visible x-axis labels occupy this space
    // - With sub-charts: invisible labels are rendered for alignment but CLIPPED via frame+clipped
    private var priceChartHeight: CGFloat {
        let base = max(80, height - indicatorPanesHeight)
        return max(80, base - effectiveBottomInset)
    }

    // Hide the in-plot settings control by default; parent can surface a toolbar button instead
    @State private var showInPlotSettingsButton: Bool = false
    @State private var showInPlotSettingsPopover: Bool = false

    // LIVE MODE SMOOTHNESS: Use 1-second updates for smooth scrolling in LIVE mode
    // The 5-second interval was causing noticeable X-axis jumps; 1-second is smooth like TradingView
    // Performance is maintained because updates are guarded to only fire in LIVE mode or when "Now" line is shown
    // LIVE CHART FIX: Use .common RunLoop mode so the timer keeps firing during scroll gestures.
    // With .default, scrolling the order book or page freezes the live chart's `now` state,
    // causing the X-axis domain to stop advancing and the chart to visually freeze.
    // The handler is lightweight (just updating a Date) and guarded to only fire in live mode.
    @State private var nowTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // Cached price formatters to avoid rebuilding on every tick/label
    private static let priceFormatterLarge: NumberFormatter = {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.minimumFractionDigits = 2
        fmt.maximumFractionDigits = 2
        return fmt
    }()
    /// Comma-separated whole number formatter for Y-axis labels on tight ranges
    /// e.g., "70,300" instead of "70.3K" when ticks are too close for abbreviated format
    private static let axisCommaFormatter: NumberFormatter = {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.minimumFractionDigits = 0
        fmt.maximumFractionDigits = 0
        return fmt
    }()
    private static let priceFormatterSmall: NumberFormatter = {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.minimumFractionDigits = 2
        fmt.maximumFractionDigits = 8
        return fmt
    }()
    private static let yAxisWholeFormatter: NumberFormatter = {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.minimumFractionDigits = 0
        fmt.maximumFractionDigits = 0
        return fmt
    }()
    private static let yAxisTinyFormatter: NumberFormatter = {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.minimumFractionDigits = 2
        fmt.maximumFractionDigits = 4
        return fmt
    }()

    // Helper to update plot insets synchronously to prevent layout shifts
    // IMPORTANT: Only updates on initial measurement or major size changes (e.g., rotation)
    // This prevents live data updates from causing sub-charts to shift
    private func updatePlotInsets(from geo: GeometryProxy, proxy: ChartProxy, forceUpdate: Bool = false) {
        guard let plotAnchor = proxy.plotFrame else { return }
        let plotRect = geo[plotAnchor]
        let leading = plotRect.origin.x
        let trailing = geo.size.width - (plotRect.origin.x + plotRect.size.width)
        let plotWidth = plotRect.size.width
        let bottomInset = geo.size.height - (plotRect.origin.y + plotRect.size.height)
        
        // Guard against invalid measurements (can happen during view setup)
        guard plotWidth > 10, trailing >= 0, leading >= 0 else { return }
        
        // Once we have valid insets, only update on major size changes (>15pt = likely rotation/resize)
        // This prevents live data updates from causing micro-shifts in sub-charts
        if hasValidInsets && !forceUpdate {
            let majorChange = abs(plotAreaWidth - plotWidth) > 15
            guard majorChange else { return }
        }
        
        // Update inset values
        pricePlotTrailingInset = trailing
        pricePlotLeadingInset = leading
        plotAreaWidth = plotWidth
        // Bottom inset includes x-axis labels + ticks + internal Swift Charts gap
        if bottomInset > 0 {
            pricePlotBottomInset = bottomInset
        }
        
        // Cache the measured insets for next time
        // This eliminates layout shift on subsequent visits to the chart
        cachedTrailingInset = Double(trailing)
        cachedLeadingInset = Double(leading)
        cachedPlotWidth = Double(plotWidth)
        
        // Mark that we have valid measurements - sub-charts can now render with proper insets
        if !hasValidInsets {
            hasValidInsets = true
        }
    }

    private func reloadChart(for symbol: String, interval: ChartInterval, symbolChanged: Bool = false) {
        vm.errorMessage = nil
        vm.stopLive()
        // TIMEFRAME SWITCH FIX: Cancel any pending auto-retry from previous timeframe.
        // Without this, a retry scheduled for the old interval could fire after the switch
        // and overwrite the new interval's data.
        vm.cancelAutoRetry()
        // PERFORMANCE: Only reset pair resolution when the SYMBOL changes.
        // On timeframe switches (same symbol), the resolved pair (e.g., BTCUSDT)
        // is still valid. Resetting it forces fetchData to re-resolve from scratch,
        // adding latency to every timeframe switch.
        if symbolChanged {
            vm.resetResolutionForNewSymbol()
        }
        // TIMEFRAME SWITCH FIX: Force-clear any stale in-flight registrations for this
        // symbol+interval combo. This prevents the deduplication logic from blocking
        // a new fetch when rapidly switching between the same timeframes (e.g., 1m->5m->1m).
        let infightKey = vm.cacheKey(symbol: symbol, interval: interval)
        CryptoChartViewModel.completeInflightFetch(key: infightKey)
        // Note: Do NOT reset stableMaxVolume to 1 here - it causes initial tiny bars
        // The volumeScaleMax is now computed immediately from cache in fetchData()
        // Pass maxIndicatorPeriod for dynamic warm-up buffer (ensures SMA 200 etc. have enough data)
        let buffer = maxIndicatorPeriod
        
        // EXCHANGE SELECTION: Set preferred exchange on view model
        // NOTE: coinbaseFallbackActive is NOT reset here (on timeframe switches).
        // Once Coinbase candle API fails for a symbol, it will fail for ALL timeframes.
        // Retrying Coinbase on every timeframe switch adds seconds of latency.
        // The flag is only reset when the SYMBOL changes (see onChange(of: symbol)).
        vm.coinbaseFallbackClosure = nil
        vm.preferredExchange = preferredExchange
        
        // PROFESSIONAL: NEVER show loading animation if we have ANY data to display
        // This creates seamless timeframe switching like TradingView/Coinbase Pro
        // The view model handles loading state internally based on cache availability
        
        if interval == .live {
            // LIVE MODE: Seed chart with a flat line at the current price, then start
            // WebSocket. The chart builds organically from real ticks.
            //
            // WHY NOT CANDLE PRE-FILL: Cached 1m candle data is often stale (prices from
            // minutes ago). When the first real WebSocket tick arrives at a different price,
            // the Y-domain has to rescale — causing the chart to visually jump from "line
            // in the middle" to "line at the bottom" before settling. A flat seed at the
            // CURRENT price ensures the chart starts correctly positioned. The brief flat
            // line (1-5 seconds until WebSocket connects) is far less jarring than the
            // 30-second rescaling dance that stale candle data causes.
            let now = Date()
            let currentLive: Double = {
                if let lp = livePrice, lp > 0 { return lp }
                if let mp = MarketViewModel.shared.bestPrice(forSymbol: symbol), mp > 0 { return mp }
                return 0
            }()
            
            if currentLive > 0 {
                // Flat seed: 2 points at the current price, spanning 3 seconds.
                // With the parallel Coinbase fast-track, real ticks arrive in 1-2 seconds,
                // so the seed only needs to cover a very short gap. The short span (3s)
                // ensures the flat portion scrolls off the left edge quickly.
                let seedPoints = [
                    ChartDataPoint(date: now.addingTimeInterval(-3), close: currentLive),
                    ChartDataPoint(date: now, close: currentLive)
                ]
                vm.dataPoints = seedPoints
            }
            
            vm.isLoading = false
            // Sync displayInterval immediately so axis labels use live formatting
            displayInterval = .live
            
            // Start the live WebSocket stream (preserveExisting keeps seed data)
            vm.startLive(symbol: symbol, preserveExisting: true)
            
            // Background 1m fetch for indicator warm-up data (SMA, EMA, etc.)
            // The parseAndCache completion now filters to the live window when
            // isLiveModeActive is true, so this won't overwrite the live data.
            vm.fetchData(symbol: symbol, interval: .oneMin, indicatorBuffer: buffer)
        } else {
            vm.fetchData(symbol: symbol, interval: interval, indicatorBuffer: buffer)
        }
    }

    // Professional abbreviated format with consistent decimal precision
    // Matches professional trading platforms like TradingView
    private func formatShort(_ v: Double) -> String {
        let absV = abs(v)
        let sign = v < 0 ? "-" : ""
        
        // Helper to format with appropriate precision based on the normalized value
        func format(_ value: Double, suffix: String) -> String {
            // For values >= 100 in the unit (e.g., 100K+), show 0 decimals
            // For values 10-99 in the unit (e.g., 90K), show 1 decimal for precision
            // For values < 10 in the unit (e.g., 5K), show 2 decimals
            let formatted: String
            if value >= 100 {
                formatted = String(format: "%.0f", value)
            } else if value >= 10 {
                // Show 1 decimal, but trim .0 for cleaner look
                let raw = String(format: "%.1f", value)
                formatted = raw.hasSuffix(".0") ? String(raw.dropLast(2)) : raw
            } else {
                // Show 2 decimals for small values, trim trailing zeros
                let raw = String(format: "%.2f", value)
                let trimmed = raw.hasSuffix("0") ? String(raw.dropLast()) : raw
                formatted = trimmed.hasSuffix(".0") ? String(trimmed.dropLast(2)) : trimmed
            }
            return sign + formatted + suffix
        }
        
        switch absV {
        case 1_000_000_000_000...:
            return format(absV / 1_000_000_000_000, suffix: "T")
        case 1_000_000_000...:
            return format(absV / 1_000_000_000, suffix: "B")
        case 1_000_000...:
            return format(absV / 1_000_000, suffix: "M")
        case 1_000...:
            return format(absV / 1_000, suffix: "K")
        default:
            // For values < 1000, use whole numbers
            return sign + String(Int(round(absV)))
        }
    }

    private func formatPrice(_ value: Double) -> String {
        let absV = abs(value)
        let formatter: NumberFormatter = (absV >= 1.0) ? Self.priceFormatterLarge : Self.priceFormatterSmall
        if let s = formatter.string(from: NSNumber(value: value)) {
            return s
        }
        // Fallbacks
        if absV >= 1.0 {
            return String(format: "%.2f", value)
        } else {
            return String(format: "%.8f", value)
        }
    }
    
    /// Format volume for display in tooltip (e.g., "1.2M", "523K", "12.5B")
    private func formatVolume(_ value: Double) -> String {
        guard value >= 1 else { return "<1" }  // Show "<1" for very small volumes
        let absV = abs(value)
        
        switch absV {
        case 1_000_000_000_000...:
            let v = absV / 1_000_000_000_000
            return v >= 100 ? String(format: "%.0fT", v) : String(format: "%.1fT", v)
        case 1_000_000_000...:
            let v = absV / 1_000_000_000
            return v >= 100 ? String(format: "%.0fB", v) : String(format: "%.1fB", v)
        case 1_000_000...:
            let v = absV / 1_000_000
            return v >= 100 ? String(format: "%.0fM", v) : String(format: "%.1fM", v)
        case 1_000...:
            let v = absV / 1_000
            return v >= 100 ? String(format: "%.0fK", v) : String(format: "%.1fK", v)
        default:
            return String(format: "%.0f", absV)
        }
    }

    private func formatYAxisPrice(_ value: Double) -> String {
        let absV = abs(value)
        
        // For large values (>= 1000), use range-aware formatting
        // Tight ranges on high-value assets (e.g., BTC $70K with $200 visible range)
        // need more precise labels to avoid duplicates like "70.3K, 70.3K, 70.4K, 70.4K"
        if absV >= 1000 {
            let domainRange = yDomain.upperBound - yDomain.lowerBound
            let approxTickStep = domainRange / 5.0  // ~4-5 ticks on Y-axis
            
            // When tick step < $200 and values are in K range, abbreviated "K" format
            // with 1 decimal produces duplicate labels. Use more precise formatting.
            if approxTickStep < 200 && absV < 1_000_000 && domainRange > 0 {
                if approxTickStep < 10 {
                    // Extremely tight range (< $50 total): use full comma format
                    // e.g., "70,295" "70,300" "70,305"
                    return Self.axisCommaFormatter.string(from: NSNumber(value: round(value))) ?? String(format: "%.0f", value)
                } else {
                    // Moderately tight (< $1000 total): use 2-decimal K format
                    // e.g., "70.25K" "70.30K" "70.35K" "70.40K"
                    let kValue = value / 1000
                    let sign = value < 0 ? "-" : ""
                    return sign + String(format: "%.2fK", abs(kValue))
                }
            }
            
            return self.formatShort(value)
        }
        
        // For medium values (1-999), show appropriate decimal places
        // Professional charts typically show 2-3 significant decimal places
        if absV >= 100 {
            // 100-999: show 2 decimals (e.g., "450.50")
            return String(format: "%.2f", value)
        } else if absV >= 10 {
            // 10-99: show 2-3 decimals (e.g., "45.50" or "45.505")
            return String(format: "%.2f", value)
        } else if absV >= 1 {
            // 1-9: show 3 decimals for better precision (e.g., "4.920")
            return String(format: "%.3f", value)
        }
        
        // For small values (< 1), show appropriate decimal places
        if absV >= 0.1 {
            // 0.1-0.99: show 4 decimals
            return String(format: "%.4f", value)
        } else if absV >= 0.01 {
            // 0.01-0.099: show 5 decimals
            return String(format: "%.5f", value)
        } else if absV >= 0.001 {
            // 0.001-0.0099: show 6 decimals
            return String(format: "%.6f", value)
        } else if absV >= 0.0001 {
            // Very small: show 7 decimals
            return String(format: "%.7f", value)
        } else {
            // Extremely small: show 8 decimals (crypto minimums)
            return String(format: "%.8f", value)
        }
    }

    private var yDomain: ClosedRange<Double> {
        // STABILITY FIX: Use stable cached domain to prevent constant chart readjustment
        // Only recalculate when prices exceed current bounds or on significant time interval
        
        // CRITICAL FIX: INTERMEDIATE RENDER FRAME PROTECTION
        // When `interval` changes (prop from parent), SwiftUI re-renders the view body
        // BEFORE onChange(of: interval) fires. During this intermediate frame:
        //   - `interval` has the NEW value (e.g., .fourHour)
        //   - `displayInterval` still has the OLD value (e.g., .oneMonth)
        //   - `vm.dataPoints` still has OLD timeframe data
        //   - `stableYDomainCache` has the OLD timeframe's Y-range
        // If we compute a new Y-domain here, we'd filter old data with new interval's
        // lookback, getting a distorted Y-range that causes the visible "readjustment"
        // when onChange finally fires and sets the correct domain.
        // FIX: When displayInterval != interval, we're in this intermediate state.
        // Return the stable cache to freeze the chart until onChange processes the switch.
        if displayInterval != interval {
            if let cached = stableYDomainCache {
                return cached
            }
            // Fallback: no cache yet (first appear) - compute from current state
            return computeIdealYDomain()
        }
        
        // SEAMLESS TIMEFRAME SWITCH: pendingDataSwitch means onChange has fired and
        // set the flag, but new data hasn't arrived yet. Keep the old chart frozen.
        if pendingDataSwitch {
            if let cached = stableYDomainCache {
                return cached
            }
            return computeIdealYDomain()
        }
        
        // LIVE MODE STABILITY: Use more aggressive stability settings for live charts
        // This prevents the constant rescaling that makes live charts hard to read
        let isLive = displayInterval == .live
        
        // If no stable cache, compute ideal domain but DON'T cache it here.
        // Caching via DispatchQueue.main.async causes a one-frame delay where the cached
        // domain becomes stale if data changes (e.g., symbol switch: BTC data arrives but
        // cached domain is from SOL). The proper caching happens in onChange(of: vm.dataVersion)
        // which fires synchronously when dataPoints is updated.
        guard let stable = stableYDomainCache else {
            return computeIdealYDomain()
        }
        
        // CRITICAL: Check if the current live price is within the stable domain
        // If the live price is outside the domain, the dashed price line will be clipped or misaligned
        // Force recomputation immediately when this happens, regardless of time intervals
        let resolvedLivePrice: Double = {
            if let lp = livePrice, lp > 0 { return lp }
            if let mp = MarketViewModel.shared.bestPrice(forSymbol: symbol), mp > 0 { return mp }
            return 0
        }()
        let livePriceInBounds = resolvedLivePrice <= 0 ||
            (resolvedLivePrice >= stable.lowerBound && resolvedLivePrice <= stable.upperBound)
        
        // LIVE DATA BOUNDS CHECK: Also verify the actual chart data (not just external price signals)
        // is within the stable domain. The resolvedLivePrice comes from MarketViewModel/parent view
        // which can be stale or zero during WebSocket startup. But vm.dataPoints contains the REAL
        // WebSocket ticks being plotted. If these are outside the domain, the chart line renders
        // below/above the visible area — this was the root cause of the "line drops below axis" bug.
        let chartDataInBounds: Bool = {
            guard isLive else { return true }  // Only applies to live mode
            guard let lastClose = vm.dataPoints.last?.close, lastClose > 0 else { return true }
            return lastClose >= stable.lowerBound && lastClose <= stable.upperBound
        }()
        
        // PERFORMANCE: Skip expensive ideal domain computation when within minimum update interval
        // and crosshair is not active (during crosshair, we always return stable anyway)
        // EXCEPTION: For live mode, recompute immediately when live price escapes bounds
        let timeSinceLastUpdate = Date().timeIntervalSince(lastYDomainUpdateAt)
        // LIVE STARTUP FIX: Use progressively longer stability intervals as the live session
        // matures. During the first 10 seconds, allow very rapid updates (0.5s) so the
        // Y-domain tracks the first real WebSocket ticks with minimal delay. From 10-60s,
        // use a moderate interval (2s) for settling. After 60s, lock down to 20s for
        // smooth, professional live chart behavior without constant rescaling.
        let liveSessionAge: TimeInterval = (isLive && vm.liveSessionStartedAt != .distantPast)
            ? Date().timeIntervalSince(vm.liveSessionStartedAt) : .infinity
        // Y-DOMAIN FAST SETTLE: After a timeframe switch, use a much shorter stability
        // interval (2s instead of 8s) for the first 10 seconds. This allows the Y-domain
        // to rapidly adjust to the new data range without the long 8-second delay that
        // caused the visible "readjustment" bug during timeframe switches.
        let recentSwitch = Date().timeIntervalSince(lastTimeframeSwitchAt) < 10.0
        let minUpdateInterval: TimeInterval = isLive
            ? (liveSessionAge < 10 ? 0.5 : (liveSessionAge < 60 ? 2.0 : 20.0))
            : (recentSwitch ? 2.0 : 8.0)
        if showCrosshair {
            return stable
        }
        
        // LIVE IMMEDIATE RESCALE: If actual chart data is outside the visible domain,
        // force immediate recomputation regardless of all timers and hysteresis.
        // This is the critical fix for the "line below axis" bug during live startup.
        if isLive && !chartDataInBounds {
            let freshDomain = computeIdealYDomain()
            Task { @MainActor in
                self.stableYDomainCache = freshDomain
                self.lastYDomainUpdateAt = Date()
                self.consecutiveBufferExceedances = 0
            }
            return freshDomain
        }
        
        // NON-LIVE CHARTS: Hold stable during the grace period after a timeframe switch.
        // This prevents fresh network data (arriving 1-3 seconds later) from triggering
        // a subtle Y-domain readjustment. The cached Y-domain is accurate enough.
        // EXCEPTION: Bypass ALL stability checks when data bounds are dramatically outside
        // the stable domain — e.g., switching from 30m→6M where stable is $69K-$71K but
        // 6M data spans $70K-$125K. In this case compute and return ideal domain immediately.
        if !isLive && timeSinceLastUpdate < minUpdateInterval {
            let stableSpan = stable.upperBound - stable.lowerBound
            let dramaticThreshold = stableSpan * 2.0  // Data must exceed 2x the domain range beyond bounds
            let needsBypass: Bool = {
                guard stableSpan > 0 else { return true }
                // O(1) check: first data point (oldest), last data point (newest)
                if let first = vm.dataPoints.first?.close,
                   (first < stable.lowerBound - dramaticThreshold ||
                    first > stable.upperBound + dramaticThreshold) {
                    return true
                }
                if let last = vm.dataPoints.last?.close,
                   (last < stable.lowerBound - dramaticThreshold ||
                    last > stable.upperBound + dramaticThreshold) {
                    return true
                }
                return false
            }()
            if !needsBypass {
                return stable
            }
            // Data range dramatically changed — skip all hysteresis and rescale now
            let bypassDomain = computeIdealYDomain()
            Task { @MainActor in
                self.stableYDomainCache = bypassDomain
                self.lastYDomainUpdateAt = Date()
                self.consecutiveBufferExceedances = 0
            }
            return bypassDomain
        }
        // LIVE CHARTS: Hold stable unless live price has escaped bounds
        // (price line would be clipped, so we must rescale immediately)
        if isLive && livePriceInBounds && timeSinceLastUpdate < minUpdateInterval && consecutiveBufferExceedances < requiredConsecutiveExceedances {
            return stable
        }
        
        // Time has elapsed or we have pending exceedances - compute ideal domain
        let idealDomain = computeIdealYDomain()
        
        // Check if prices are within the stable domain with buffer
        // STABILITY FIX: Increased buffers to reduce rescaling frequency
        // LIVE mode uses 15% buffer (was 10%) to reduce frequent rescaling from normal price fluctuations
        // Non-live modes use 7% buffer (was 5%) for tighter but still stable tracking
        let stableRange = stable.upperBound - stable.lowerBound
        let bufferPercent = isLive ? 0.15 : 0.07
        
        // MINIMUM ABSOLUTE BUFFER: For high-value assets like BTC, ensure buffer isn't too small
        // When the displayed range is tight (e.g., $700 for BTC), percentage buffers are tiny
        // Use 0.5% of the max price as a floor (was 0.3%) to prevent rescaling from minor fluctuations
        let maxPrice = max(idealDomain.upperBound, stable.upperBound)
        let absoluteMinBuffer = maxPrice * 0.005
        let buffer = max(stableRange * bufferPercent, absoluteMinBuffer)
        
        let pricesWithinBounds = idealDomain.lowerBound >= (stable.lowerBound - buffer) &&
                                  idealDomain.upperBound <= (stable.upperBound + buffer)
        
        // HYSTERESIS: Track consecutive buffer exceedances before triggering rescale
        // This prevents rescaling from brief price spikes, requiring sustained movement
        // EXCEPTION: Bypass hysteresis entirely when live price is outside the domain
        // The dashed price line must always be correctly positioned
        if !pricesWithinBounds {
            // Price is outside buffer - increment counter
            Task { @MainActor in
                self.consecutiveBufferExceedances += 1
            }
            
            // If live price is outside domain, force immediate rescale (skip hysteresis + time check)
            // Otherwise, apply normal hysteresis rules
            if livePriceInBounds {
                if consecutiveBufferExceedances < requiredConsecutiveExceedances || timeSinceLastUpdate < minUpdateInterval {
                    return stable
                }
            }
            // When !livePriceInBounds, fall through to rescale immediately
        } else {
            // Price is within buffer - reset hysteresis counter
            if consecutiveBufferExceedances > 0 {
                Task { @MainActor in
                    self.consecutiveBufferExceedances = 0
                }
            }
            
            // PRICES WITHIN BOUNDS: Domain is valid. Keep it stable.
            // For non-live charts: return stable when within bounds UNLESS the domain
            // is excessively wide compared to the actual data. This prevents charts from
            // getting stuck with blown-out Y-axes after transitions or stale data.
            // Example: stable 60K-72K (12K range) but data is 71.1K-71.3K (200 range) → tighten
            // For live charts: allow periodic tightening so the domain tracks price movement.
            if !isLive {
                let idealRange = idealDomain.upperBound - idealDomain.lowerBound
                let excessivelyWide = idealRange > 0 && stableRange > idealRange * 5.0
                if excessivelyWide && timeSinceLastUpdate >= 2.0 {
                    // Domain is >5x wider than needed — tighten to ideal domain
                    // idealDomain already includes padding and nice number snapping
                    Task { @MainActor in
                        self.stableYDomainCache = idealDomain
                        self.lastYDomainUpdateAt = Date()
                        self.consecutiveBufferExceedances = 0
                    }
                    return idealDomain
                }
                return stable
            }
            if timeSinceLastUpdate < minUpdateInterval {
                return stable
            }
        }
        
        // Prices exceeded buffer for required consecutive times OR enough time has passed - update stable domain
        // Use a slightly expanded domain to reduce future updates
        // CRITICAL FIX: Use idealRange (from the NEW data) for expansion, NOT stableRange (from the OLD domain).
        // Previously, stableRange came from the old timeframe's domain, causing wildly wrong expansion
        // (e.g., switching 1M→1W: old stableRange = $55K, expansion = $1.65K on a $5K ideal range).
        let idealRange = idealDomain.upperBound - idealDomain.lowerBound
        let expansionPercent = isLive ? 0.05 : 0.03
        let expandedLo = idealDomain.lowerBound - idealRange * expansionPercent
        let expandedHi = idealDomain.upperBound + idealRange * expansionPercent
        let expandedDomain = expandedLo...expandedHi
        
        Task { @MainActor in
            self.stableYDomainCache = expandedDomain
            self.lastYDomainUpdateAt = Date()
            self.consecutiveBufferExceedances = 0  // Reset counter after rescale
        }
        
        return expandedDomain
    }
    
    /// Computes the ideal Y-domain based on current visible data (without stability caching)
    private func computeIdealYDomain() -> ClosedRange<Double> {
        // Filter to only include prices from visible data points (within xDomain)
        // This excludes warm-up data fetched for indicator calculations
        let domain = xDomain
        let visiblePoints = vm.dataPoints.filter { 
            $0.date >= domain.lowerBound && $0.date <= domain.upperBound 
        }
        var prices = visiblePoints.map(\.close)
        
        // Use displayInterval for all rendering decisions to match displayed data
        let effectiveInterval = displayInterval
        
        // For LIVE mode: if no visible points in rolling window, use all available data
        // This prevents showing 0...1 while waiting for fresh websocket data
        if prices.isEmpty && effectiveInterval == .live && !vm.dataPoints.isEmpty {
            prices = vm.dataPoints.map(\.close)
        }
        
        // CRITICAL: Include the live price in Y-domain calculation
        // Without this, the dashed price line can appear at the chart edge or misalign
        // when the live price has moved beyond the latest candle data (e.g., during sharp selloffs)
        // This ensures the price line is always visible and properly positioned within the chart
        // Y-DOMAIN STABILITY FIX: Only include live price if it's within a reasonable range
        // of the current data. If the live price is wildly different (stale data, API error),
        // including it would blow out the Y-domain and cause flickering/compression.
        // LIVE SEED STATE: When the chart has only seed points (≤3 flat points at the
        // same price), return a very tight Y-domain centered exactly on the seed price.
        // This ensures the flat line appears perfectly centered during the 5-20 seconds
        // before WebSocket connects. We skip resolvedLivePrice and indicators because:
        //  - resolvedLivePrice can differ from the seed price (different data source timing),
        //    which shifts the domain and makes the line appear off-center
        //  - Indicators have no meaningful data during seed state
        // The tight domain ($14 range for BTC at $70K) will rapidly expand via the 0.5s
        // Y-domain stability interval as soon as real WebSocket ticks arrive.
        if effectiveInterval == .live && visiblePoints.count <= 3 && !visiblePoints.isEmpty {
            let seedPrice = visiblePoints[0].close
            let allFlat = visiblePoints.allSatisfy { abs($0.close - seedPrice) < 0.01 }
            if allFlat {
                let tightPad = max(seedPrice * 0.0001, 1)  // $7 for BTC at $70K
                return (seedPrice - tightPad)...(seedPrice + tightPad)
            }
        }
        
        let resolvedLivePrice: Double = {
            if let lp = livePrice, lp > 0 { return lp }
            if let mp = MarketViewModel.shared.bestPrice(forSymbol: symbol), mp > 0 { return mp }
            return 0
        }()
        if resolvedLivePrice > 0, let priceMin = prices.min(), let priceMax = prices.max() {
            let priceRange = priceMax - priceMin
            let midPrice = (priceMax + priceMin) / 2
            // Only include live price if within 2x the data range from the center
            // This prevents absurd Y-domain expansion from stale/erroneous live prices
            let tolerance = max(priceRange * 2.0, midPrice * 0.05) // At least 5% of mid price
            if abs(resolvedLivePrice - midPrice) <= tolerance {
                prices.append(resolvedLivePrice)
            }
        } else if resolvedLivePrice > 0 {
            prices.append(resolvedLivePrice)
        }
        
        // INDICATOR Y-DOMAIN CAPPING: First compute price-only bounds, then selectively
        // include indicator values with a cap on how much they can expand the domain.
        //
        // ROOT CAUSE FIX: Indicators like SMA/EMA can lag far behind during major price moves
        // (e.g., SMA 200 at $85K when BTC is at $70K after a selloff). Without capping,
        // these far-off indicator values blow out the Y-domain, compressing the actual price
        // data into a thin sliver (sometimes < 35% of the chart). The niceYDomain function
        // then amplifies this by snapping to large tick intervals (e.g., $10K steps).
        //
        // With capping, indicators can expand the domain by at most 40% of the price range
        // in each direction. This keeps BB bands and close indicators fully visible while
        // preventing lagging SMA/EMA from dominating the chart layout.
        
        // 1. Get price-only bounds (candle closes + live price, no indicators)
        guard let priceLo = prices.min(), let priceHi = prices.max() else {
            return 1...2
        }
        let priceRange = priceHi - priceLo
        
        // 2. Calculate the maximum expansion indicators are allowed to add
        // 40% of price range, with a floor of 0.5% of the price to handle flat-line cases
        let maxIndicatorExpansion = max(priceRange * 0.40, priceHi * 0.005)
        let indicatorFloor = priceLo - maxIndicatorExpansion
        let indicatorCeiling = priceHi + maxIndicatorExpansion
        
        // 3. Include indicator values, clamped to the allowed expansion range
        if indSMAEnabled {
            let smaVals = smaIndicatorPointsOnDemand.map { min(max($0.close, indicatorFloor), indicatorCeiling) }
            prices.append(contentsOf: smaVals)
        }
        if indEMAEnabled {
            let emaVals = emaIndicatorPointsOnDemand.map { min(max($0.close, indicatorFloor), indicatorCeiling) }
            prices.append(contentsOf: emaVals)
        }
        if indBBEnabled {
            let bbBands = bollingerBandsOnDemand
            let bbUpper = bbBands.upper.map { min(max($0.close, indicatorFloor), indicatorCeiling) }
            let bbLower = bbBands.lower.map { min(max($0.close, indicatorFloor), indicatorCeiling) }
            prices.append(contentsOf: bbUpper)
            prices.append(contentsOf: bbLower)
        }
        if indVWAPEnabled {
            let vwapVals = vwapIndicatorPointsOnDemand.map { min(max($0.close, indicatorFloor), indicatorCeiling) }
            prices.append(contentsOf: vwapVals)
        }
        
        // Compute final bounds (now includes capped indicator values)
        guard let lo = prices.min(), let hi = prices.max() else {
            return 1...2
        }
        let range = hi - lo
        // 4% padding for tight chart rendering while maintaining Y-axis label clearance
        let percentPad = range * 0.04
        // Minimum padding prevents zero-padding for flat lines, but must be capped
        // relative to the data range to prevent excessive whitespace on tight ranges
        // (e.g., BTC at $70K with only $100 range on 30m chart would get $105 padding without cap)
        let absoluteMinPad = max(hi, 1) * 0.0015
        let minPad = range > 0 ? min(absoluteMinPad, range * 0.20) : absoluteMinPad
        let pad = max(percentPad, minPad)
        
        // When volume is integrated as overlay, add extra bottom padding (25% of range)
        // This reserves space for volume bars and keeps price action clearly visible
        let bottomPad: Double = (showVolumeOverlay && volumeIntegrated && effectiveInterval != .live) ? range * 0.25 : pad
        
        let rawLo = lo - bottomPad
        let rawHi = hi + pad
        
        // LIVE MODE: Skip nice number snapping entirely. The niceYDomain() function
        // snaps bounds to "nice" step values (e.g., 100, 200, 500) which causes the
        // Y-domain to blow out from a tight $10-20 range to $200+ range for BTC at $69K.
        // This is the root cause of the chart line appearing "in the middle" or "at the
        // bottom" during live startup. For live mode, use raw padded bounds for a tight,
        // data-following Y-axis like professional trading platforms (TradingView, Coinbase).
        if effectiveInterval == .live {
            // Use tighter padding for live: 8% of range with a small absolute floor.
            // The floor (0.008% = ~$5.6 for BTC at $70K) ensures a non-degenerate domain
            // when the range is nearly zero (e.g., first few ticks at the same price).
            // This is much tighter than the non-live floor (0.15%), keeping the chart
            // tightly tracking the price action like professional live charts.
            let livePad = range > 0 ? max(range * 0.08, hi * 0.00008) : max(hi * 0.0001, 1)
            let liveLo = lo - livePad
            let liveHi = hi + livePad
            return liveLo...liveHi
        }
        
        // For long timeframes (1Y, ALL), skip nice number snapping
        // This prevents the Y-axis from snapping to 0 and wasting chart space
        // Instead, use raw data bounds with tight padding for a professional look
        if effectiveInterval == .oneYear || effectiveInterval == .all {
            // Use 2.5% padding for long-term charts to maximize data visibility
            let tightPad = range * 0.025
            // Add extra bottom padding for integrated volume overlay
            let volumeBottomPad = (showVolumeOverlay && volumeIntegrated) ? range * 0.25 : tightPad
            let longLo = max(0, lo - volumeBottomPad)
            let longHi = hi + tightPad
            return longLo...longHi
        }
        
        // Apply nice number rounding for cleaner tick values on shorter timeframes
        return niceYDomain(rawLo: rawLo, rawHi: rawHi)
    }
    
    /// Computes a "nice" Y-axis domain that produces clean tick values (e.g., 92K, 93K, 94K)
    private func niceYDomain(rawLo: Double, rawHi: Double) -> ClosedRange<Double> {
        let range = rawHi - rawLo
        // SAFETY: If range is zero (all prices identical), create a small artificial range
        // centered on the price. This prevents a degenerate domain that breaks chart rendering.
        guard range > 0 else {
            let mid = (rawLo + rawHi) / 2
            // FLAT LINE FALLBACK: Create a small artificial range centered on the price.
            // Live mode uses a very tight range (0.015% = ~$10 for BTC at $69K) so the
            // flat seed line renders near the center. As real ticks arrive with actual
            // variance, the Y-domain will expand naturally to fit.
            // Non-live modes use 1% (~$690 for BTC) since they display candle data.
            let pct: Double = displayInterval == .live ? 0.00015 : 0.01
            let fallbackPad = max(abs(mid) * pct, 1)
            return (mid - fallbackPad)...(mid + fallbackPad)
        }
        
        // CRITICAL: For price charts, never let the domain go below 90% of the minimum
        // This ensures data fills the chart like professional trading platforms
        let absoluteMinimum = rawLo > 0 ? rawLo * 0.90 : rawLo - abs(rawLo) * 0.10
        
        // Target approximately 4-5 ticks on Y-axis for cleaner appearance
        let targetTicks = 4.5
        let roughStep = range / targetTicks
        
        // Guard against extremely small or zero roughStep to prevent log10 crash
        guard roughStep > 1e-15 else { return rawLo...rawHi }
        
        // Find the order of magnitude and normalize
        let magnitude = pow(10, floor(log10(roughStep)))
        guard magnitude > 0, magnitude.isFinite else { return rawLo...rawHi }
        let normalized = roughStep / magnitude
        
        // Snap to nice step values: 1, 2, 2.5, 5, 10
        // Prefer smaller steps (1, 2) for tighter, more informative axes
        let niceStep: Double
        if normalized <= 1.2 {
            niceStep = 1.0 * magnitude
        } else if normalized <= 2.2 {
            niceStep = 2.0 * magnitude
        } else if normalized <= 3.0 {
            niceStep = 2.5 * magnitude
        } else if normalized <= 5.5 {
            niceStep = 5.0 * magnitude
        } else {
            niceStep = 10.0 * magnitude
        }
        
        // Snap domain bounds to multiples of niceStep
        var niceLo = floor(rawLo / niceStep) * niceStep
        let niceHi = ceil(rawHi / niceStep) * niceStep
        
        // CRITICAL: Never go below absoluteMinimum to prevent 0 baseline
        niceLo = max(niceLo, absoluteMinimum)
        
        // Limit expansion to 10% of range (reduced from 15%) for tighter chart fit
        let maxExpansion = range * 0.10
        let finalLo = max(niceLo, rawLo - maxExpansion)
        let finalHi = min(niceHi, rawHi + maxExpansion)
        
        return finalLo...finalHi
    }

    private var xDomain: ClosedRange<Date> {
        // SEAMLESS TIMEFRAME SWITCH: While waiting for new data, keep the OLD X-domain
        // so the chart stays visually stable. Without this, the new interval's lookbackSeconds
        // is applied to old data, causing mismatched axis labels and a "broken flash".
        if pendingDataSwitch, let cached = stableXDomainCache {
            return cached
        }
        
        // CRITICAL FIX: INTERMEDIATE RENDER FRAME PROTECTION
        // When displayInterval != interval, SwiftUI is rendering the view body BEFORE
        // onChange(of: interval) has fired. The data still belongs to the OLD timeframe.
        // Use displayInterval (not interval) for all lookback calculations so the domain
        // matches the currently displayed data. This prevents computing a 10.5-day window
        // (.fourHour) on 1-month data, which would distort the chart for one frame.
        let effectiveInterval = displayInterval
        
        // Guard against empty data - use sensible default
        guard !vm.dataPoints.isEmpty,
              let dataFirst = vm.dataPoints.first?.date,
              let dataLast = vm.dataPoints.last?.date else {
            let now = Date()
            return now.addingTimeInterval(-86_400)...now
        }
        
        // LIVE mode: Always anchor the right edge at "now" and span liveWindow to the left.
        // This creates a steady scrolling window where new ticks appear at the right edge
        // and old data slides off the left edge, similar to TradingView's live chart.
        // Using `now` (updated by the timer) instead of `dataLast` prevents the x-axis
        // from jumping around as live ticks arrive at irregular intervals.
        if effectiveInterval == .live {
            let rightEdge = max(now, dataLast)
            
            // CRITICAL FIX: Use the span from the first data point to the right edge (now),
            // NOT just dataLast - dataFirst. When WebSocket is slow to connect, dataLast stays
            // at the seed timestamp while `now` advances. Using dataSpan alone causes the
            // window to stay small (30s) while rightEdge marches forward, pushing ALL data
            // points behind the visible domain → chart shows empty/flat.
            // By measuring from dataFirst to rightEdge, the window always grows to encompass
            // all data, keeping seed points visible while waiting for live data.
            let fullSpan = rightEdge.timeIntervalSince(dataFirst)
            
            // Window grows organically from the actual data span up to liveWindow.
            // Phase 1 (0-60s):   window = 60s minimum → professional starting width, line grows
            //                    into the visible area from left to right like TradingView
            // Phase 2 (1-5 min): window = fullSpan → chart fills edge-to-edge naturally
            // Phase 3 (5+ min):  window = liveWindow (300s) → steady 5-minute rolling view
            // The 60-second minimum prevents the chart from feeling "too fast" and cramped
            // during the first minute when there are only a few seconds of actual data.
            let windowDuration = max(60, min(fullSpan, liveWindow))
            let leftEdge = rightEdge.addingTimeInterval(-windowDuration)
            return leftEdge...rightEdge
        }
        
        // For ALL timeframe, use full data extent
        if effectiveInterval == .all {
            return dataFirst...dataLast
        }
        
        // For 3Y timeframe, use full data extent (similar to ALL)
        // This ensures we show all available historical data without gaps
        if effectiveInterval == .threeYear {
            return dataFirst...dataLast
        }
        
        // Calculate expected window based on timeframe
        // This ensures the chart shows the correct time span for the selected interval
        let expectedWindow = effectiveInterval.lookbackSeconds
        guard expectedWindow > 0 else {
            return dataFirst...dataLast
        }
        
        // Domain ends at most recent data point, spans backward by expectedWindow
        // This fixes the "compressed data" issue where charts showed data crammed to the left
        let windowStart = dataLast.addingTimeInterval(-expectedWindow)
        let actualStart = max(windowStart, dataFirst)
        
        return actualStart...dataLast
    }

    private var xDomainPrice: ClosedRange<Date> {
        // Use the data-driven xDomain directly
        // The domain exactly matches the actual data bounds, so no extension is needed
        // This ensures data fills the chart properly without gaps
        return xDomain
    }

    // *** ADDITION: Computed helpers for day separators and "Now" line as per instructions ***
    private var visibleSpanSeconds: TimeInterval {
        xDomainPrice.upperBound.timeIntervalSince(xDomainPrice.lowerBound)
    }
    private func isDateInDomain(_ d: Date) -> Bool {
        d >= xDomainPrice.lowerBound && d <= xDomainPrice.upperBound
    }
    // Updated per instruction #2
    private var shouldShowDaySeparators: Bool {
        // Show daily separators when enabled and the visible span is within ~2 weeks
        return userShowSeparators && visibleSpanSeconds <= 14 * 86_400
    }
    private var daySeparatorDates: [Date] {
        guard shouldShowDaySeparators else { return [] }
        let cal = Calendar.current
        var ticks: [Date] = []
        var start = cal.startOfDay(for: xDomainPrice.lowerBound)
        if start < xDomainPrice.lowerBound {
            guard let next = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
            start = next
        }
        var cursor = start
        while cursor <= xDomainPrice.upperBound {
            ticks.append(cursor)
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return ticks
    }
    // Updated per instruction #3
    private var shouldShowNowLine: Bool {
        // Draw a subtle "Now" line when enabled for short/medium ranges and now is inside the domain
        return userShowNowLine && isDateInDomain(now) && visibleSpanSeconds <= 14 * 86_400
    }

    // *** Added weekend shading computation as per instruction #4 ***
    // Optional weekend shading bands for 1W/1M
    private var weekendBands: [(Date, Date)] {
        guard userWeekendShading, (interval == .oneWeek || interval == .oneMonth) else { return [] }
        let cal = Calendar.current
        var bands: [(Date, Date)] = []
        // Start at the next Saturday midnight from the lower bound
        var cursor = cal.startOfDay(for: xDomainPrice.lowerBound)
        // Advance to Saturday (weekday 7 in Gregorian where Sunday=1)
        while cal.component(.weekday, from: cursor) != 7 {
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { return bands }
            cursor = next
            if cursor > xDomainPrice.upperBound { return bands }
        }
        while cursor < xDomainPrice.upperBound {
            let start = cursor
            guard let end = cal.date(byAdding: .day, value: 2, to: start) else { break } // until Monday 00:00
            let clampedStart = max(start, xDomainPrice.lowerBound)
            let clampedEnd = min(end, xDomainPrice.upperBound)
            if clampedStart < clampedEnd {
                bands.append((clampedStart, clampedEnd))
            }
            guard let nextSat = cal.date(byAdding: .day, value: 7, to: start) else { break }
            cursor = nextSat
        }
        return bands
    }

    private var priceInterpolation: InterpolationMethod {
        // Use monotone interpolation for accurate price representation
        // Monotone preserves actual trend direction without creating artificial peaks/valleys
        // This is the industry standard for financial charts (TradingView, Robinhood, Coinbase)
        switch interval {
        case .live:
            return userLiveLinearInterpolation ? .linear : .monotone
        default:
            return .monotone
        }
    }

    private var shouldShowAreaFill: Bool {
        // Enable area fill for ALL timeframes except live for visual depth
        // This creates the signature "filled area under the line" look of professional charts
        return displayInterval != .live
    }
    
    /// Adaptive line width scale based on timeframe data density
    /// Reduced values for sharper, crisper lines
    /// Adaptive line width scale - reduced values for crisper lines
    /// More uniform across timeframes for consistent visual appearance
    private var adaptiveLineScale: CGFloat {
        switch displayInterval {
        case .live:
            return 0.60  // Thin for crisp real-time display
        case .oneHour, .fourHour:
            return 0.62  // Slightly thicker for hourly views
        case .oneDay:
            return 0.65  // Medium for daily view
        case .oneWeek:
            return 0.68  // Standard for weekly (flagship timeframe)
        case .oneMonth, .threeMonth, .sixMonth:
            return 0.66  // Medium for monthly views
        case .oneYear, .threeYear, .all:
            return 0.62  // Crisper for long timeframes with many points
        default:
            return 0.64
        }
    }
    
    private var areaGradient: LinearGradient {
        // Premium multi-stop gradient with visible undertone (TradingView-inspired)
        // Gold fills area under line with gradual fade for rich, professional appearance
        // Enhanced top opacity (0.48) ensures visible gold even when price is near chart bottom
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: DS.Colors.gold.opacity(0.48), location: 0.0),    // Top - more vibrant gold
                .init(color: DS.Colors.gold.opacity(0.35), location: 0.20),   // Upper - sustain color
                .init(color: DS.Colors.gold.opacity(0.22), location: 0.45),   // Mid - still visible
                .init(color: DS.Colors.gold.opacity(0.10), location: 0.70),   // Lower - gentle fade
                .init(color: DS.Colors.gold.opacity(0.03), location: 0.90),   // Near bottom - subtle
                .init(color: Color.clear, location: 1.0)                      // Bottom - fully clear
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    // Highest/Lowest markers within the currently visible x-domain
    private var inViewExtrema: (min: ChartDataPoint, max: ChartDataPoint)? {
        // Disabled per request: always return nil to suppress high/low markers.
        return nil
    }
    
    // MARK: - Data Resampling for Smooth Rendering (Matching Sparkline Quality)
    
    /// Maximum number of points to plot - increased for better price detail
    /// Higher density captures more price action granularity
    private var maxPlottedPoints: Int {
        switch interval {
        case .live:
            return 90   // More detail for real-time trading
        case .oneMin, .fiveMin, .fifteenMin, .thirtyMin:
            return 120  // Short timeframes need high detail
        case .oneHour, .fourHour:
            return 140  // Hourly views - more granular
        case .oneDay, .oneWeek:
            return 150  // Daily/weekly - maximum detail
        case .oneMonth, .threeMonth, .sixMonth:
            return 120  // Monthly views - good detail
        case .oneYear:
            return 150  // 1Y needs good detail for daily candles
        case .threeYear:
            return 180  // 3Y needs more points for weekly candles
        case .all:
            return 250  // ALL needs highest detail for full history
        }
    }
    
    /// Resamples data points to match sparkline density (48-96 points)
    /// This is critical for matching the smooth appearance of sparklines
    /// PERFORMANCE: Uses caching to avoid recalculating on every render
    /// FIX: Now properly aggregates volume within each bucket instead of just sampling
    /// This ensures volume bars represent total volume for the time period, not individual candles
    private var resampledDataPoints: [ChartDataPoint] {
        let domain = xDomain
        
        // LIVE MODE: Skip resampling entirely. LIVE data has ≤300 points (1/sec × 5 min)
        // which Swift Charts handles easily. Resampling smooths out micro-movements and
        // — critically — bucket-aggregation can shift the last plotted point's close price
        // away from the actual latest trade, causing the dashed line / dot to appear at
        // a different Y level than the chart line endpoint.
        if displayInterval == .live {
            var livePts = vm.dataPoints.filter {
                $0.date >= domain.lowerBound && $0.date <= domain.upperBound && $0.close > 0
            }
            if livePts.isEmpty && !vm.dataPoints.isEmpty {
                livePts = vm.dataPoints.filter { $0.close > 0 }
            }
            return livePts
        }
        
        // Compute domain hash to detect timeframe changes
        // This ensures cache is invalidated when switching between timeframes
        var domainHasher = Hasher()
        domainHasher.combine(domain.lowerBound.timeIntervalSince1970)
        domainHasher.combine(domain.upperBound.timeIntervalSince1970)
        let currentDomainHash = domainHasher.finalize()
        
        // Filter to points within the visible domain
        // This fixes the "compressed data" issue where points outside the timeframe window
        // were being included in resampling calculations
        var visiblePoints = vm.dataPoints.filter {
            $0.date >= domain.lowerBound && $0.date <= domain.upperBound
        }
        
        // SAFEGUARD: If filtering removed all points but we have data, use all data
        // This prevents empty charts when there's a domain/data mismatch (e.g., during loading)
        if visiblePoints.isEmpty && !vm.dataPoints.isEmpty {
            visiblePoints = vm.dataPoints
        }
        
        // SAFETY: Remove any zero/negative close prices that slipped through parsing
        // These corrupt the chart line by pulling it to the bottom
        let filteredPoints = visiblePoints.filter { $0.close > 0 }
        // Guard: If filtering removed ALL points, keep the original set rather than
        // returning an empty array (which would break the chart rendering entirely)
        if !filteredPoints.isEmpty {
            visiblePoints = filteredPoints
        }
        
        let maxPoints = maxPlottedPoints
        
        // PERFORMANCE: Return cached result if visible data AND domain haven't changed
        // The domain hash check prevents using stale cache when switching timeframes
        if visiblePoints.count == lastResampledDataCount && 
           currentDomainHash == lastResampledDomainHash && 
           !cachedResampledPoints.isEmpty {
            return cachedResampledPoints
        }
        
        // No resampling needed if under limit
        guard visiblePoints.count > maxPoints, maxPoints > 1 else {
            // Cache the result
            Task { @MainActor in
                self.cachedResampledPoints = visiblePoints
                self.lastResampledDataCount = visiblePoints.count
                self.lastResampledDomainHash = currentDomainHash
            }
            return visiblePoints
        }
        
        // VOLUME FIX: Use bucket-based aggregation to properly sum volumes
        // This ensures each resampled bar represents the total volume for that time period
        // instead of just one sampled candle's volume (which was causing inconsistent/missing volume)
        
        // Calculate points per bucket
        let pointsPerBucket = max(1, (visiblePoints.count + maxPoints - 1) / maxPoints)
        
        var result: [ChartDataPoint] = []
        result.reserveCapacity(maxPoints + 1)
        
        var bucketIndex = 0
        while bucketIndex * pointsPerBucket < visiblePoints.count {
            let startIdx = bucketIndex * pointsPerBucket
            let endIdx = min(startIdx + pointsPerBucket, visiblePoints.count)
            
            // Aggregate volume and use last point's close/date for this bucket
            var bucketVolume: Double = 0
            var bucketLastClose: Double = 0
            var bucketLastDate: Date = visiblePoints[startIdx].date
            
            for i in startIdx..<endIdx {
                let pt = visiblePoints[i]
                bucketVolume += pt.volume
                bucketLastClose = pt.close
                bucketLastDate = pt.date
            }
            
            // Create aggregated data point for this bucket
            result.append(ChartDataPoint(
                date: bucketLastDate,
                close: bucketLastClose,
                volume: bucketVolume
            ))
            
            bucketIndex += 1
        }
        
        // PERFORMANCE: Cache the resampled result
        Task { @MainActor in
            self.cachedResampledPoints = result
            self.lastResampledDataCount = visiblePoints.count
            self.lastResampledDomainHash = currentDomainHash
        }
        
        return result
    }
    
    /// Shared render source for the price chart and all indicator panes.
    /// Keeping every pane on the same x-anchored dataset prevents timeframe drift.
    private var alignedRenderPoints: [ChartDataPoint] {
        let domain = xDomainPrice
        let aligned = resampledDataPoints.filter {
            $0.date >= domain.lowerBound && $0.date <= domain.upperBound && $0.close > 0
        }
        if !aligned.isEmpty {
            return aligned
        }
        let visibleRaw = vm.dataPoints.filter {
            $0.date >= domain.lowerBound && $0.date <= domain.upperBound && $0.close > 0
        }
        if !visibleRaw.isEmpty {
            return visibleRaw
        }
        // Keep this in-domain only; returning out-of-domain fallback points can
        // desynchronize panes during interval transitions.
        return []
    }
    
    // MARK: - Price Change Calculation
    
    /// Computes the price change percentage for the actual timeframe (e.g., 1H = last 1 hour)
    /// This uses the badgeTimeWindowSeconds to calculate change over the correct time window,
    /// not the full visible chart range which may span multiple days.
    private var priceChangeForTimeframe: (percentage: Double, isPositive: Bool)? {
        // For ALL timeframe, don't show percentage badge - it's unreliable because:
        // - Depends on how far back the API returns data
        // - Different coins have different inception dates
        // - "All time" percentage is misleading for most users
        if interval == .all {
            return nil
        }
        
        guard !vm.dataPoints.isEmpty else { return nil }
        
        // Use the last data point's timestamp as reference (not Date()) since data may not be fresh
        guard let lastDataPoint = vm.dataPoints.last else { return nil }
        let referenceTime = lastDataPoint.date
        // USE `interval` (not displayInterval) so the badge percentage IMMEDIATELY reflects
        // the user's selected timeframe window, even before new data arrives from the network.
        // The guard at line ~4685 (windowPoints.count >= 2) handles the case where the
        // current data doesn't span the new timeframe's window.
        let timeWindow = interval.badgeTimeWindowSeconds
        
        // For zero window timeframes, use full data range
        if timeWindow == 0 {
            guard let first = vm.dataPoints.first?.close,
                  first > 0 else { return nil }
            let change = ((lastDataPoint.close - first) / first) * 100
            return (change, change >= 0)
        }
        
        // Find data points within the actual time window (e.g., last 4 hours for 4H)
        // Using referenceTime ensures we measure from the latest available data, not system time
        let windowStart = referenceTime.addingTimeInterval(-timeWindow)
        let windowPoints = vm.dataPoints.filter { $0.date >= windowStart }
        
        // Ensure we have at least 2 points to calculate a meaningful change
        // If we don't have enough data for the actual timeframe, don't show badge at all
        // (showing visible range change with timeframe label would be misleading)
        guard windowPoints.count >= 2,
              let firstPoint = windowPoints.first,
              let lastPoint = windowPoints.last,
              firstPoint.close > 0 else {
            // Not enough data for this timeframe - hide the badge rather than show misleading info
            return nil
        }
        
        // Verify the data actually spans close to the expected time window (at least 80%)
        // This prevents showing misleading percentages when API returns limited history
        let actualSpan = lastPoint.date.timeIntervalSince(firstPoint.date)
        let expectedSpan = timeWindow
        let spanRatio = actualSpan / expectedSpan
        
        // For long timeframes (3M+), require at least 80% of expected span to show percentage
        // This prevents showing "3Y: -15%" when data only spans 1 year
        if timeWindow > 7776000 && spanRatio < 0.8 { // 7776000 = 90 days in seconds
            return nil
        }
        
        let change = ((lastPoint.close - firstPoint.close) / firstPoint.close) * 100
        return (change, change >= 0)
    }
    
    /// Returns the timeframe label for the price change badge
    private var timeframeLabel: String {
        // USE `interval` (not displayInterval) so the badge label IMMEDIATELY reflects
        // the user's selected timeframe. displayInterval lags behind interval when switching
        // (it waits for network data), which caused the bug where switching from 15m to 30m
        // kept showing "(15m)" for several seconds.
        switch interval {
        case .live: return "Live"
        case .oneMin: return "1m"
        case .fiveMin: return "5m"
        case .fifteenMin: return "15m"
        case .thirtyMin: return "30m"
        case .oneHour: return "1H"
        case .fourHour: return "4H"
        case .oneDay: return "24H"
        case .oneWeek: return "1W"
        case .oneMonth: return "1M"
        case .threeMonth: return "3M"
        case .sixMonth: return "6M"
        case .oneYear: return "1Y"
        case .threeYear: return "3Y"
        case .all: return "All"
        }
    }

    // High/Low markers removed per request

    // MARK: – Chart Subviews Extraction

    // MARK: - Chart Content Helpers (broken up to help compiler)
    
    @ChartContentBuilder
    private var chartBackgroundContent: some ChartContent {
        // Weekend shading behind price lines
        if !weekendBands.isEmpty {
            ForEach(Array(weekendBands.enumerated()), id: \.offset) { _, pair in
                RectangleMark(
                    xStart: .value("WeekendStart", pair.0),
                    xEnd:   .value("WeekendEnd",   pair.1),
                    yStart: .value("Low",  self.yDomain.lowerBound),
                    yEnd:   .value("High", self.yDomain.upperBound)
                )
                .foregroundStyle(Color.white.opacity(0.04))
            }
        }
        // Faint day separators behind price lines (very subtle to avoid visual noise)
        if !daySeparatorDates.isEmpty {
            ForEach(daySeparatorDates, id: \.self) { d in
                RuleMark(x: .value("Day", d))
                    .foregroundStyle(DS.Colors.grid.opacity(0.06))
                    .lineStyle(StrokeStyle(lineWidth: 0.5))
            }
        }
    }
    
    /// Extended plot points that include domain boundaries and live price alignment.
    ///
    /// CRITICAL FIX: The LAST plotted point's close value is updated to the live price
    /// so that the chart line connects seamlessly with the horizontal live price line.
    /// Without this, the chart line ends at the last candle close (e.g., $71,000) while
    /// the horizontal price line sits at the live price (e.g., $70,644), creating a
    /// visible misalignment at the right edge of the chart.
    ///
    /// Note: The xDomain upper bound typically equals the last data point's date, so
    /// the "trailing edge" condition (last.date < domain.upperBound) rarely triggers.
    /// Instead, we directly update the last point's close to the live price.
    private var extendedPlotPoints: [ChartDataPoint] {
        let plotPoints = alignedRenderPoints
        guard !plotPoints.isEmpty else { return [] }
        var pts = plotPoints
        let domain = xDomainPrice
        
        // ─── LIVE MODE: SIMPLE PASS-THROUGH ───
        // In LIVE mode the data is already raw (unsampled) WebSocket ticks.
        // Do NOT add synthetic leading/trailing points or snap the last point
        // to a live price from a different source. The chart line, dashed line,
        // and yellow dot must all read from the same final point to be perfectly
        // aligned. Synthetic points at domain edges caused a visible gap between
        // the chart line endpoint and the dot/dashed line in earlier versions.
        if displayInterval == .live {
            return pts
        }
        
        // ─── NON-LIVE MODES: Edge-to-edge fill + live price alignment ───
        
        // If first point starts slightly after domain start, add a synthetic point at domain start
        // to ensure the chart line fills the chart from edge to edge.
        // GUARD: Only do this when the gap is small (< 15% of domain span). A large gap means
        // the xDomain is wider than the data (e.g., stale cache from another timeframe).
        // In that case, DON'T draw a long flat line — just let the data start where it starts.
        if let first = pts.first, first.date > domain.lowerBound {
            let domainSpan = domain.upperBound.timeIntervalSince(domain.lowerBound)
            let gapFromLeft = first.date.timeIntervalSince(domain.lowerBound)
            let gapFraction = domainSpan > 0 ? gapFromLeft / domainSpan : 1.0
            if gapFraction < 0.15 {
                let edgePoint = ChartDataPoint(date: domain.lowerBound, close: first.close, volume: 0)
                pts.insert(edgePoint, at: 0)
            }
        }
        
        // LIVE PRICE ALIGNMENT: Resolve the current live price
        // FIX: Never fall back to 0 – use last chart close as the ultimate fallback
        // so the chart line always ends at a valid price level.
        let lastChartClose = pts.last?.close ?? 0
        let resolvedLive: Double = {
            if let lp = livePrice, lp > 0 { return lp }
            if let mp = MarketViewModel.shared.bestPrice(forSymbol: symbol), mp > 0 { return mp }
            return lastChartClose  // Use last known price instead of 0
        }()
        
        // FRESHNESS CHECK: Only apply live price alignment when data is recent.
        // If the last data point is stale (e.g., from months/years ago due to API issues
        // or cache), snapping it to the live price creates a jarring vertical spike.
        let lastPointAge = pts.last.map { Date().timeIntervalSince($0.date) } ?? .infinity
        // Threshold: 10 candle-widths or 2 hours, whichever is larger.
        // (Increased from 5x / 1hr to avoid stale-looking charts when the API lags slightly)
        let freshnessThreshold = max(displayInterval.secondsPerInterval * 10, 7200)
        let isDataFresh = lastPointAge <= freshnessThreshold
        
        // If last point ends before domain end, add a synthetic trailing point
        if let last = pts.last, last.date < domain.upperBound {
            let trailingPrice = (isDataFresh && resolvedLive > 0) ? resolvedLive : last.close
            let edgePoint = ChartDataPoint(date: domain.upperBound, close: trailingPrice, volume: 0)
            pts.append(edgePoint)
        } else if isDataFresh, resolvedLive > 0, let lastIdx = pts.indices.last {
            // CRITICAL: When the last data point IS at the domain edge (most common case),
            // update its close value to the live price. This ensures the chart line endpoint
            // matches the horizontal live price line exactly.
            let lastPt = pts[lastIdx]
            pts[lastIdx] = ChartDataPoint(date: lastPt.date, close: resolvedLive, volume: lastPt.volume)
        }
        
        return pts
    }
    
    /// The price that the chart line actually ends at (last extendedPlotPoints value).
    /// Used by chartAnnotationContent so the dashed RuleMark always matches the chart line endpoint.
    /// This prevents visual misalignment between the dashed price line and the chart's trailing edge.
    private var chartEndpointPrice: Double {
        if let lastPt = extendedPlotPoints.last {
            return lastPt.close
        }
        // Fallback: resolve live price the same way the header does
        if let lp = livePrice, lp > 0 { return lp }
        if let mp = MarketViewModel.shared.bestPrice(forSymbol: symbol), mp > 0 { return mp }
        return vm.dataPoints.last?.close ?? 0
    }
    
    @ChartContentBuilder
    private var chartPriceContent: some ChartContent {
        // Use extended points for edge-to-edge rendering
        let plotPoints = extendedPlotPoints
        
        // Area fill first (renders behind price line)
        // Opacity matched to sparkline's fillOpacity: 0.22
        if shouldShowAreaFill {
            ForEach(plotPoints) { pt in
                AreaMark(x: .value("Time", pt.date),
                         yStart: .value("Low", yDomain.lowerBound),
                         yEnd: .value("High", pt.close))
                    .foregroundStyle(areaGradient)
            }
        }
        
        // Line rendering - single crisp stroke for professional TradingView/Robinhood-quality appearance
        // No glow layers - just a clean, sharp price line with subtle shadow for depth
        ForEach(plotPoints) { pt in
            LineMark(x: .value("Time", pt.date), y: .value("Price", pt.close), series: .value("Series", "Price"))
                .interpolationMethod(priceInterpolation)
                .foregroundStyle(DS.Colors.gold)
                .lineStyle(StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round))
        }
    }
    
    // MARK: - Integrated Volume Overlay (TradingView-style)
    // Renders volume bars at the bottom 25% of the price chart as semi-transparent overlay
    // VOLUME FIX: Calculates max from resampled (aggregated) volumes for proper scaling
    @ChartContentBuilder
    private var chartVolumeOverlayContent: some ChartContent {
        if showVolumeOverlay && volumeIntegrated && displayInterval != .live {
            // FIX: Use resampledDataPoints instead of raw vm.dataPoints
            // This ensures volume bars are consistent with the price line and properly sized
            // Using raw data points caused thousands of tiny bars on long timeframes
            let points = resampledDataPoints
            let domain = yDomain
            let priceRange = domain.upperBound - domain.lowerBound
            
            // Volume occupies bottom 22% of chart height
            let volumeTopY = domain.lowerBound + priceRange * 0.22
            let volumeBaseY = domain.lowerBound
            
            // VOLUME FIX: Calculate max volume from RESAMPLED points, not raw data
            // Since we now aggregate volumes during resampling, we must scale against
            // the aggregated values to prevent all bars from being at 100%
            let maxVolume: Double = {
                let volumes = points.map { $0.volume }.sorted()
                guard !volumes.isEmpty else { return max(cachedMaxVolume, 1) }
                // Use 98th percentile for consistency with volumeCeiling()
                let idx = Int(Double(volumes.count - 1) * 0.98)
                let val = volumes[max(0, min(volumes.count - 1, idx))]
                return max(1, val)
            }()
            
            // Use softer colors for overlay (not to distract from price)
            let upColor = Color(red: 0.18, green: 0.70, blue: 0.45)    // Softer green
            let downColor = Color(red: 0.80, green: 0.30, blue: 0.30)  // Softer red
            
            // Calculate halfInterval from resampled points for proper edge bar widths
            // Reduced multiplier (0.35 instead of 0.5) for thinner bars with visible gaps
            // This improves crosshair alignment - user can see distinct bars as they scrub
            let halfInterval: TimeInterval = {
                if points.count >= 2 {
                    // Use median interval of first few resampled points
                    var intervals: [TimeInterval] = []
                    for i in 1..<min(points.count, 10) {
                        let diff = points[i].date.timeIntervalSince(points[i-1].date)
                        if diff > 0 { intervals.append(diff) }
                    }
                    intervals.sort()
                    let medianInterval = intervals.isEmpty ? 300 : intervals[intervals.count / 2]
                    return medianInterval * 0.35  // Reduced from 0.5 for thinner bars
                }
                return cachedTypicalInterval * 0.35  // Consistent with above
            }()
            
            ForEach(Array(points.enumerated()), id: \.element.id) { idx, pt in
                let prevClose = idx > 0 ? points[idx - 1].close : pt.close
                let isUp = pt.close >= prevClose
                let barColor = idx == 0 ? Color.gray : (isUp ? upColor : downColor)
                
                // Map volume to Y-position in bottom 22% of chart
                let normalizedVolume = pt.volume > 0 ? min(pt.volume / maxVolume, 1.0) : 0.05
                let barTopY = volumeBaseY + (volumeTopY - volumeBaseY) * normalizedVolume
                
                // Calculate bar width - use narrower bars (70% of interval) to create visible gaps
                // This ensures each bar is distinct and crosshair alignment feels responsive
                let xDomain = self.xDomainPrice  // Use X domain for date comparisons
                let startDate: Date = {
                    if idx == 0 {
                        // First bar: extend to domain start to fill left gap
                        // Use whichever is earlier: domain start or half-interval before first point
                        let normalStart = pt.date.addingTimeInterval(-halfInterval)
                        return normalStart < xDomain.lowerBound ? normalStart : xDomain.lowerBound
                    }
                    // Inset from midpoint to create gap between bars
                    return pt.date.addingTimeInterval(-halfInterval)
                }()
                
                let endDate: Date = {
                    if idx == points.count - 1 {
                        // Last bar: extend to domain end to fill right edge
                        let normalEnd = pt.date.addingTimeInterval(halfInterval)
                        return normalEnd > xDomain.upperBound ? normalEnd : xDomain.upperBound
                    }
                    // Inset from midpoint to create gap between bars
                    return pt.date.addingTimeInterval(halfInterval)
                }()
                
                RectangleMark(
                    xStart: .value("Start", startDate),
                    xEnd: .value("End", endDate),
                    yStart: .value("Base", volumeBaseY),
                    yEnd: .value("Top", barTopY)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            barColor.opacity(0.35),  // Top - more visible
                            barColor.opacity(0.15)   // Bottom - fades out
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            
            // Crosshair dot for volume overlay - shows red/green based on price direction
            // VOLUME FIX: Use date-based matching instead of ID-based matching
            // Since resampled points have new UUIDs, we need to find the closest point by date
            if showCrosshair, let cp = crosshairDataPoint {
                // Find the closest point in resampled data by date (not by ID)
                let matchedIndex: Int? = {
                    guard !points.isEmpty else { return nil }
                    var closestIdx = 0
                    var closestDiff = abs(points[0].date.timeIntervalSince(cp.date))
                    for i in 1..<points.count {
                        let diff = abs(points[i].date.timeIntervalSince(cp.date))
                        if diff < closestDiff {
                            closestDiff = diff
                            closestIdx = i
                        }
                    }
                    return closestIdx
                }()
                
                if let idx = matchedIndex {
                    let pt = points[idx]
                    let prevClose = idx > 0 ? points[idx - 1].close : pt.close
                    let isUp = pt.close >= prevClose
                    let dotColor = idx == 0 ? Color.gray : (isUp ? upColor : downColor)
                    
                    // Calculate volume bar position for highlight
                    let normalizedVolume = pt.volume > 0 ? min(pt.volume / maxVolume, 1.0) : 0.05
                    let barTopY = volumeBaseY + (volumeTopY - volumeBaseY) * normalizedVolume
                    
                    // Calculate the bar's date range for the highlight rectangle
                    let highlightStartDate = pt.date.addingTimeInterval(-halfInterval)
                    let highlightEndDate = pt.date.addingTimeInterval(halfInterval)
                    
                    // Highlighted rectangle overlay on selected volume bar
                    // This makes the selected bar visually pop with brighter opacity
                    RectangleMark(
                        xStart: .value("HLStart", highlightStartDate),
                        xEnd: .value("HLEnd", highlightEndDate),
                        yStart: .value("HLBase", volumeBaseY),
                        yEnd: .value("HLTop", barTopY)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                dotColor.opacity(0.65),  // Brighter top for selected bar
                                dotColor.opacity(0.35)   // Still visible at bottom
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    
                    // Outer glow dot at top of bar
                    PointMark(
                        x: .value("Time", pt.date),
                        y: .value("VolTop", barTopY)
                    )
                    .symbolSize(50)
                    .foregroundStyle(dotColor.opacity(0.35))
                    
                    // Inner solid point at top of bar
                    PointMark(
                        x: .value("Time", pt.date),
                        y: .value("VolTopInner", barTopY)
                    )
                    .symbolSize(22)
                    .foregroundStyle(dotColor)
                }
            }
        }
    }
    
    @ChartContentBuilder
    private var chartIndicatorContent: some ChartContent {
        // FIX: Use on-demand computed indicator points that read @AppStorage directly
        // This ensures indicators render immediately when toggled, without waiting for onChange
        // The computeIndicatorPointsOnDemand() method checks enabled state and computes synchronously
        
        // SMA indicator - bright blue with monotone interpolation for accuracy
        // FIX: Read directly from computed property that checks indSMAEnabled
        let smaPointsToRender = smaIndicatorPointsOnDemand
        ForEach(smaPointsToRender) { p in
            LineMark(x: .value("Time", p.date), y: .value("SMA", p.close), series: .value("Series", "SMA"))
                .interpolationMethod(.monotone)
                .foregroundStyle(DS.Colors.smaLine)
                .lineStyle(StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round))
        }
        
        // EMA indicator - vibrant orange with monotone interpolation for accuracy
        // FIX: Read directly from computed property that checks indEMAEnabled
        let emaPointsToRender = emaIndicatorPointsOnDemand
        ForEach(emaPointsToRender) { p in
            LineMark(x: .value("Time", p.date), y: .value("EMA", p.close), series: .value("Series", "EMA"))
                .interpolationMethod(.monotone)
                .foregroundStyle(DS.Colors.emaLine)
                .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        }
        
        // Bollinger Bands - lines only (no area fill to avoid artifacts with gold gradient)
        // Professional trading apps (TradingView, Bloomberg) render BB as clean lines
        let bbBands = bollingerBandsOnDemand
        let bbUpper = bbBands.upper
        let bbMiddle = bbBands.middle
        let bbLower = bbBands.lower
        
        // Upper band - solid line
        ForEach(bbUpper) { p in
            LineMark(x: .value("Time", p.date), y: .value("BBU", p.close), series: .value("Series", "BBUpper"))
                .interpolationMethod(.monotone)
                .foregroundStyle(DS.Colors.bbLine.opacity(0.85))
                .lineStyle(StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        }
        
        // Middle band - SMA center line, dashed
        ForEach(bbMiddle) { p in
            LineMark(x: .value("Time", p.date), y: .value("BBM", p.close), series: .value("Series", "BBMiddle"))
                .interpolationMethod(.monotone)
                .foregroundStyle(DS.Colors.bbLine)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [5, 3]))
        }
        
        // Lower band - solid line
        ForEach(bbLower) { p in
            LineMark(x: .value("Time", p.date), y: .value("BBL", p.close), series: .value("Series", "BBLower"))
                .interpolationMethod(.monotone)
                .foregroundStyle(DS.Colors.bbLine.opacity(0.85))
                .lineStyle(StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        }
        
        // VWAP indicator - cyan/teal line with monotone interpolation
        // FIX: Read directly from computed property that checks indVWAPEnabled
        let vwapPointsToRender = vwapIndicatorPointsOnDemand
        ForEach(vwapPointsToRender) { p in
            LineMark(x: .value("Time", p.date), y: .value("VWAP", p.close), series: .value("Series", "VWAP"))
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.cyan)
                .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        }
    }
    
    @ChartContentBuilder
    private var chartAnnotationContent: some ChartContent {
        // Subtle "Now" vertical line with fade-in/out
        RuleMark(x: .value("Now", now))
            .foregroundStyle(Color.yellow.opacity(0.22))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
            .opacity(shouldShowNowLine ? 1 : 0)

        // Last price guideline with glow effect (hidden when crosshair is active)
        // Professional platforms (TradingView, Bloomberg) show prominent current price line
        // ALIGNMENT FIX: Use chartEndpointPrice so the dashed line is ALWAYS at the same Y
        // as the chart line's trailing edge. This prevents any visual gap between the chart
        // line endpoint and the horizontal dashed line, regardless of freshness state.
        if !showCrosshair, !vm.dataPoints.isEmpty {
            let currentPrice = chartEndpointPrice
            // Outer glow layer for premium effect - wider for visibility on large Y-ranges
            RuleMark(y: .value("LastGlow", currentPrice))
                .foregroundStyle(DS.Colors.gold.opacity(0.18))
                .lineStyle(StrokeStyle(lineWidth: 4.0))
            // Main price line - dashed, higher contrast for visibility
            RuleMark(y: .value("Last", currentPrice))
                .foregroundStyle(DS.Colors.gold.opacity(0.70))
                .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [6, 3]))
        }

        // NOTE: Removed trailing indicator badges (SMA, EMA, BB, VWAP) to prevent overlapping
        // when indicator values are close together. The top-left legend already shows which
        // indicators are active with their periods. This provides a cleaner, professional look.

        // Professional crosshair marks - dashed lines like TradingView/Bloomberg
        // Adaptive color for light/dark mode visibility
        let crosshairLineColor = colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.5)
        if showCrosshair, let cp = crosshairDataPoint {
            // Vertical crosshair line (dashed for professional look)
            RuleMark(x: .value("Time", cp.date))
                .foregroundStyle(crosshairLineColor)
                .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [4, 3]))
            
            // Horizontal crosshair line at price level
            RuleMark(y: .value("CrosshairPrice", cp.close))
                .foregroundStyle(crosshairLineColor)
                .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [4, 3]))
            
            // Intersection point marker with glow effect
            PointMark(
                x: .value("Time", cp.date),
                y: .value("Price", cp.close)
            )
            .symbolSize(50)
            .foregroundStyle(DS.Colors.gold.opacity(0.3))  // Outer glow
            
            PointMark(
                x: .value("Time", cp.date),
                y: .value("Price", cp.close)
            )
            .symbolSize(25)
            .foregroundStyle(DS.Colors.gold)  // Inner solid point
        }
    }

    private var priceChartView: some View {
        Chart {
            chartBackgroundContent
            chartVolumeOverlayContent  // Volume behind price line (TradingView-style)
            chartPriceContent
            chartIndicatorContent
            chartAnnotationContent
        }
        .transaction { transaction in
            transaction.animation = nil  // Disable all chart animations to prevent readjustment glitches
        }
        .chartYScale(domain: self.yDomain)
        // Final polish: keep enough vertical breathing room for readability,
        // but avoid wasting headroom at the top of the chart.
        .chartYScale(range: .plotDimension(padding: 8))
        .chartYAxis {
            // Professional Y-axis with refined grid lines (TradingView/Bloomberg style)
            // Subtle dashed lines that don't distract from price action
            AxisMarks(position: .trailing) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                    .foregroundStyle(DS.Colors.grid.opacity(0.55))
                AxisTick(stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(DS.Colors.tick.opacity(0.5))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(self.formatYAxisPrice(v))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(DS.Colors.axisLabel)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            // ALIGNMENT FIX: Fixed label width ensures every sub-chart
                            // (RSI, MACD, Volume, etc.) can use the SAME width, giving
                            // identical Y-axis area → identical plot area → perfect x-axis alignment.
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
        }
        .chartXAxis {
            // Professional X-axis with subtle vertical grid lines
            // CRITICAL FIX: Use displayInterval (not self.interval) to ensure axis labels
            // always match the currently displayed data. During a timeframe switch,
            // self.interval has already changed but the data hasn't loaded yet.
            // displayInterval stays at the old value until new data arrives.
            let xAxis = ChartXAxisProvider(interval: self.displayInterval, domain: self.xDomainPrice, plotWidth: self.plotAreaWidth, uses24hClock: ChartDateFormatters.uses24hClock)
            AxisMarks(values: xAxis.ticks()) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                    .foregroundStyle(DS.Colors.grid.opacity(0.4))
                // ALIGNMENT: Always render ticks and labels so Swift Charts allocates
                // the same internal plot area layout whether or not sub-charts are below.
                // When sub-charts handle the visible labels, make these invisible but
                // still occupy space so the plot area width matches sub-charts exactly.
                // NOTE: Removing these (using conditional if) breaks Swift Charts layout
                // when indicators are active, causing incorrect Y-axis scaling.
                AxisTick(stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(hasSubChartsBelow ? .clear : DS.Colors.tick.opacity(0.5))
                AxisValueLabel {
                    if let dt = value.as(Date.self) {
                        Text(xAxis.label(for: dt))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(hasSubChartsBelow ? .clear : DS.Colors.axisLabel)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
        }
        .chartForegroundStyleScale([
            "Price": DS.Colors.gold,
            "PriceGlow": DS.Colors.goldGlow,
            "PriceGlowOuter": DS.Colors.goldGlowOuter,
            "SMA": DS.Colors.smaLine,
            "EMA": DS.Colors.emaLine,
            "BBUpper": DS.Colors.bbLine,
            "BBMiddle": DS.Colors.bbLine.opacity(0.5),
            "BBLower": DS.Colors.bbLine,
            "VWAP": Color.cyan
        ])
        .chartLegend(.hidden)
        .chartXScale(domain: xDomainPrice)
        // Add a small, intentional edge buffer so the latest segment/marker
        // never appears clipped against the trailing axis boundary.
        .chartXScale(range: .plotDimension(padding: 24))
        .chartPlotStyle { plotArea in
            plotArea
                .background(
                    ZStack {
                        // Base gradient background
                        LinearGradient(
                            colors: [DS.Colors.chartBgTop, DS.Colors.chartBgBottom],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        
                        // Premium top highlight (glass effect like TradingView Pro)
                        // Adaptive: subtle white in dark mode, very subtle warm tint in light mode
                        LinearGradient(
                            colors: [Color.white.opacity(colorScheme == .dark ? 0.04 : 0.02), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                        
                        // Subtle inner shadow at bottom for depth (Apple-style)
                        // Adaptive: black in dark mode, lighter in light mode
                        VStack {
                            Spacer()
                            LinearGradient(
                                colors: [Color.clear, Color.black.opacity(colorScheme == .dark ? 0.10 : 0.04)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 18)
                        }
                    }
                )
                // Professional edge definition lines - adaptive for light/dark mode
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color.white.opacity(0.08), Color.white.opacity(0.02)]
                                    : [Color.black.opacity(0.04), Color.black.opacity(0.01)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 0.5)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(DS.Colors.grid.opacity(colorScheme == .dark ? 0.2 : 0.15))
                        .frame(height: 0.5)
                        .allowsHitTesting(false)
                }
        }
        // Note: Removed .drawingGroup() to prevent Y-axis label clipping at chart edges
        .chartOverlay { proxy in
            GeometryReader { geo in
                // Measure trailing and leading inset of the price plot without breaking ViewBuilder
                Color.clear
                    .onAppear {
                        updatePlotInsets(from: geo, proxy: proxy)
                    }
                    .onChange(of: geo.size) { _, _ in
                        // Recalculate on size changes (e.g., rotation)
                        updatePlotInsets(from: geo, proxy: proxy)
                    }
                    .onChange(of: interval) { _, _ in
                        // Force recalculate when timeframe changes - different price ranges may have different Y-axis label widths
                        // This ensures indicator charts stay aligned with the main chart across all timeframes
                        updatePlotInsets(from: geo, proxy: proxy, forceUpdate: true)
                    }
                    .onChange(of: vm.dataVersion) { _, _ in
                        // CRITICAL FIX: Only consume pendingDataSwitch when REAL data arrives (count > 0).
                        // dataVersion bumps on every dataPoints assignment - even when count is unchanged.
                        guard vm.dataPoints.count > 0 else { return }
                        #if DEBUG
                        print("[Chart] dataVersion changed: pts=\(vm.dataPoints.count) displayInterval=\(displayInterval.rawValue) interval=\(interval.rawValue) pending=\(pendingDataSwitch)")
                        #endif
                        
                        // RACE CONDITION FIX: Cancel safety timeouts now that real data has arrived.
                        // This prevents stale timeouts from firing after data is already displayed.
                        switchSafetyTimeout4s?.cancel()
                        switchSafetyTimeout4s = nil
                        switchSafetyTimeout15s?.cancel()
                        switchSafetyTimeout15s = nil
                        
                        // RACE CONDITION FIX: Detect interval change even if pendingDataSwitch was
                        // already cleared by the 15-second safety timeout. Without this, when data
                        // arrives after the timeout, caches are never cleared and the chart renders
                        // new data with stale domains/resampled points from the old timeframe.
                        let intervalChanged = displayInterval != interval
                        
                        // DISPLAY INTERVAL SYNC: New data has arrived, so the displayed data now
                        // matches the current interval. Update displayInterval so axis labels
                        // immediately reflect the correct timeframe for the new data.
                        displayInterval = interval
                        
                        // SEAMLESS TIMEFRAME SWITCH: When new data arrives after a timeframe/symbol switch,
                        // clear ALL caches so the chart renders fresh from the new data in one go.
                        // Using dataVersion (not count) ensures this fires even when old and new arrays
                        // have the same number of elements (e.g., switching between similar timeframes).
                        // RACE CONDITION FIX: Also clear caches when intervalChanged is true, which
                        // handles the case where the 15s timeout cleared pendingDataSwitch before
                        // data arrived. Without this, stale caches persist across timeframe switches.
                        // Y-DOMAIN FAST SETTLE: Also refresh when fresh API data arrives within 10s
                        // of a timeframe switch. When cached data was loaded instantly in onChange(of: interval),
                        // pendingDataSwitch is already false and displayInterval matches interval.
                        // But the background API fetch returns fresher data that should update the Y-domain.
                        let recentSwitchNeedsRefresh = Date().timeIntervalSince(lastTimeframeSwitchAt) < 10.0
                        if pendingDataSwitch || intervalChanged || recentSwitchNeedsRefresh {
                            // SMOOTH TRANSITION (INTERVAL CHANGE): Clear X-domain cache first so
                            // xDomain recomputes from the new data. Then compute the ideal Y-domain
                            // and set it DIRECTLY as the new stable cache.
                            stableXDomainCache = nil
                            consecutiveBufferExceedances = 0
                            pendingDataSwitch = false
                            // Clear all rendering caches - they'll recompute from new data below
                            cachedResampledPoints = []
                            lastResampledDataCount = 0
                            lastResampledDomainHash = 0
                            lastVolumeStatsDataCount = 0
                            clearAllIndicatorCaches()
                            // Compute and set Y-domain in one step (no nil intermediate)
                            let freshDomain = computeIdealYDomain()
                            stableYDomainCache = freshDomain
                            lastYDomainUpdateAt = Date()
                        } else if needsYDomainRefresh {
                            // SYMBOL CHANGE: Fresh data arrived for the new symbol.
                            // Force Y-domain recomputation so the chart immediately shows
                            // correct axes for the new coin's price range.
                            // Without this, stale cache data's domain could persist through
                            // the Y-domain hysteresis, causing a delayed readjustment.
                            needsYDomainRefresh = false
                            cachedResampledPoints = []
                            lastResampledDataCount = 0
                            lastResampledDomainHash = 0
                            lastVolumeStatsDataCount = 0
                            clearAllIndicatorCaches()
                            let freshDomain = computeIdealYDomain()
                            stableYDomainCache = freshDomain
                            lastYDomainUpdateAt = Date()
                            consecutiveBufferExceedances = 0
                        }
                        // ENSURE Y-DOMAIN IS CACHED: If stableYDomainCache is still nil after
                        // the above handlers, compute and cache it now. This handles the initial
                        // load case where neither pendingDataSwitch nor needsYDomainRefresh is set.
                        if stableYDomainCache == nil {
                            let freshDomain = computeIdealYDomain()
                            stableYDomainCache = freshDomain
                            lastYDomainUpdateAt = Date()
                        }
                        
                        // LIVE Y-DOMAIN FIX: When live WebSocket data arrives that's outside the
                        // cached Y-domain, force immediate recomputation. The first real tick
                        // may be at a different price than the seed, so the Y-domain needs to
                        // expand to cover the full range from seed price to tick price.
                        if displayInterval == .live,
                           let stable = stableYDomainCache,
                           let lastClose = vm.dataPoints.last?.close, lastClose > 0 {
                            let dataOutOfBounds = lastClose < stable.lowerBound || lastClose > stable.upperBound
                            // Also check first point in case data was replaced
                            let firstOutOfBounds: Bool = {
                                guard let firstClose = vm.dataPoints.first?.close, firstClose > 0 else { return false }
                                return firstClose < stable.lowerBound || firstClose > stable.upperBound
                            }()
                            if dataOutOfBounds || firstOutOfBounds {
                                let freshDomain = computeIdealYDomain()
                                stableYDomainCache = freshDomain
                                lastYDomainUpdateAt = Date()
                                consecutiveBufferExceedances = 0
                            }
                        }
                        
                        // STALENESS AUTO-RETRY: Detect when loaded data is too old for the selected
                        // timeframe and trigger ONE background refresh. This catches edge cases where
                        // Firebase or the API returned stale data that passed time-window filtering.
                        if !didRetryForStaleData, let latestDate = vm.dataPoints.last?.date {
                            let dataAge = Date().timeIntervalSince(latestDate)
                            let staleThreshold = interval.maxAllowedDataAge
                            if dataAge > staleThreshold {
                                didRetryForStaleData = true
                                #if DEBUG
                                print("[Chart] Data is stale (\(Int(dataAge))s old, threshold \(Int(staleThreshold))s) — triggering one-time refresh for \(symbol) \(interval.rawValue)")
                                #endif
                                // Small delay so the current render cycle completes first
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    vm.fetchData(symbol: symbol, interval: interval)
                                }
                            }
                        }
                        
                        // Recalculate when data loads - Y-axis labels may change based on price range
                        updatePlotInsets(from: geo, proxy: proxy, forceUpdate: true)
                        // CRITICAL: Force recompute indicators when data changes to ensure sync with toggles
                        // Using force=true guarantees indicators match their toggle states
                        recomputeIndicatorsIfNeeded(force: true)
                        updateVisiblePointsCacheIfNeeded(force: true)
                        updateVolumeStatsCacheIfNeeded()
                    }
                    .onChange(of: currentIndicatorSettingsHash) { _, _ in
                        // FIX: Force recompute indicators when settings change
                        // Using force=true bypasses version checks to avoid SwiftUI state race conditions
                        recomputeIndicatorsIfNeeded(force: true)
                        updateVisiblePointsCacheIfNeeded(force: true)
                    }

                // PRICE SYNC FIX: Position the live dot at the chart line's ACTUAL endpoint
                // (from extendedPlotPoints), not at vm.dataPoints.last. The chart line
                // includes synthetic trailing points and live-price alignment that shift
                // the endpoint's X/Y. Using the raw dataPoints.last causes the dot to
                // appear behind or disconnected from the chart line.
                if showLiveDotOverlay && displayInterval == .live,
                   let plotAnchor = proxy.plotFrame,
                   let chartEndpoint = extendedPlotPoints.last,
                   let xPos = proxy.position(forX: chartEndpoint.date) {
                     let dotPrice = chartEndpoint.close
                     if let yPos = proxy.position(forY: dotPrice) {
                       Circle()
                         .fill(Color.yellow)
                         .frame(width: 8, height: 8)
                         .scaleEffect(pulse ? 1.5 : 1)
                         .position(x: geo[plotAnchor].origin.x + xPos,
                                   y: geo[plotAnchor].origin.y + yPos)
                         .onAppear {
                             // Defer to avoid "Modifying state during view update"
                             Task { @MainActor in
                                 withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                                     pulse.toggle()
                                 }
                             }
                         }
                         .allowsHitTesting(false)
                     }
                }

                // New floating callout for crosshair data point
                if showCrosshair, let cp = crosshairDataPoint,
                   let plotAnchor = proxy.plotFrame,
                   let xPos = proxy.position(forX: cp.date),
                   let yPos = proxy.position(forY: cp.close) {
                    let origin = geo[plotAnchor].origin
                    let plotFrame = geo[plotAnchor]
                    let baseX = origin.x + xPos
                    let baseY = origin.y + yPos
                    let bubbleWidth: CGFloat = 150
                    // Dynamic height based on enabled indicators + volume row
                    let indicatorCount = (indSMAEnabled ? 1 : 0) + (indEMAEnabled ? 1 : 0) + (indBBEnabled ? 1 : 0) + (indVWAPEnabled ? 1 : 0)
                    let showVolumeInTooltip = cp.volume >= 1  // Only show if volume is meaningful (>= 1)
                    let bubbleHeight: CGFloat = 52 + (showVolumeInTooltip ? 16 : 0) + CGFloat(indicatorCount) * 16
                    
                    // Use plot area bounds for clamping (not full geo.size)
                    // This keeps tooltip aligned with the crosshair line within the chart area
                    let plotLeftEdge = origin.x
                    let plotRightEdge = origin.x + plotFrame.size.width
                    let plotTopEdge = origin.y
                    let plotBottomEdge = origin.y + plotFrame.size.height
                    let leftBound = plotLeftEdge + bubbleWidth / 2 + 2
                    let rightBound = plotRightEdge - bubbleWidth / 2 - 2
                    
                    // Keep tooltip centered on crosshair line, clamped within plot area bounds
                    let clampedX = min(max(baseX, leftBound), rightBound)
                    let rawY = baseY - bubbleHeight / 2 - 12
                    let topBound = plotTopEdge + bubbleHeight / 2 + 4
                    let bottomBound = plotBottomEdge - bubbleHeight / 2 - 4
                    let clampedY = min(max(rawY, topBound), bottomBound)

                    ZStack {
                        // Premium glass-like background - adaptive for light/dark mode
                        let tooltipBgColors: [Color] = colorScheme == .dark
                            ? [Color(red: 0.12, green: 0.12, blue: 0.14).opacity(0.95),
                               Color(red: 0.06, green: 0.06, blue: 0.08).opacity(0.95)]
                            : [Color.white.opacity(0.98),
                               Color(red: 0.96, green: 0.96, blue: 0.97).opacity(0.98)]
                        let tooltipTextColor: Color = colorScheme == .dark ? .white.opacity(0.8) : .primary.opacity(0.7)
                        
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: tooltipBgColors,
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(
                                        LinearGradient(
                                            colors: [DS.Colors.gold.opacity(0.5), DS.Colors.gold.opacity(0.2)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ),
                                        lineWidth: 1
                                    )
                            )
                        VStack(spacing: 3) {
                            Text(self.formatPrice(cp.close))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(DS.Colors.gold)
                            Text(ChartDateFormatters.crosshairDateLabel(for: displayInterval, date: cp.date))
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(tooltipTextColor)
                            
                            // Volume display for the time bucket
                            if showVolumeInTooltip {
                                HStack(spacing: 5) {
                                    Image(systemName: "chart.bar.fill")
                                        .font(.system(size: 8))
                                        .foregroundColor(Color(red: 0.18, green: 0.70, blue: 0.45).opacity(0.9))
                                    Text("Vol: \(formatVolume(cp.volume))")
                                        .font(.system(size: 10, weight: .medium, design: .rounded))
                                        .foregroundColor(tooltipTextColor.opacity(0.85))
                                }
                            }
                            
                            // Indicator values at crosshair point (compact display)
                            if let smaVal = smaValueAt(date: cp.date) {
                                HStack(spacing: 5) {
                                    Circle().fill(DS.Colors.smaLine).frame(width: 6, height: 6)
                                    Text("SMA \(indSMAPeriod): \(formatPrice(smaVal))")
                                        .font(.system(size: 10, weight: .medium, design: .rounded))
                                        .foregroundColor(DS.Colors.smaLine.opacity(0.9))
                                }
                            }
                            if let emaVal = emaValueAt(date: cp.date) {
                                HStack(spacing: 5) {
                                    Circle().fill(DS.Colors.emaLine).frame(width: 6, height: 6)
                                    Text("EMA \(indEMAPeriod): \(formatPrice(emaVal))")
                                        .font(.system(size: 10, weight: .medium, design: .rounded))
                                        .foregroundColor(DS.Colors.emaLine.opacity(0.9))
                                }
                            }
                            if let bbVals = bbValuesAt(date: cp.date) {
                                HStack(spacing: 5) {
                                    Circle().fill(DS.Colors.bbLine).frame(width: 6, height: 6)
                                    Text("BB: \(formatPrice(bbVals.lower)) - \(formatPrice(bbVals.upper))")
                                        .font(.system(size: 10, weight: .medium, design: .rounded))
                                        .foregroundColor(DS.Colors.bbLine.opacity(0.9))
                                }
                            }
                            if let vwapVal = vwapValueAt(date: cp.date) {
                                HStack(spacing: 5) {
                                    Circle().fill(Color.cyan).frame(width: 6, height: 6)
                                    Text("VWAP: \(formatPrice(vwapVal))")
                                        .font(.system(size: 10, weight: .medium, design: .rounded))
                                        .foregroundColor(Color.cyan.opacity(0.9))
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
                    .frame(width: bubbleWidth, height: bubbleHeight)
                    .position(x: clampedX, y: clampedY)
                    .allowsHitTesting(false)
                }

                // Price change percentage badge (top-left of chart)
                // Only shown when showPercentageBadge is true (hidden on coin detail pages where header shows the change)
                if showPercentageBadge && !showCrosshair, let change = priceChangeForTimeframe, let plotAnchor = proxy.plotFrame {
                    let origin = geo[plotAnchor].origin
                    // Rich emerald green / deep red matching volume colors
                    let changeColor = change.isPositive ? Color(red: 0.08, green: 0.85, blue: 0.45) : Color(red: 0.95, green: 0.18, blue: 0.18)
                    let sign = change.isPositive ? "+" : ""
                    let formattedChange = String(format: "%.2f", change.percentage)
                    
                    // Adaptive badge colors for light/dark mode
                    let badgeBgColors: [Color] = colorScheme == .dark 
                        ? [Color.black.opacity(0.8), Color.black.opacity(0.7)]
                        : [Color.white.opacity(0.95), Color(red: 0.96, green: 0.96, blue: 0.97).opacity(0.95)]
                    let timeframeLabelColor: Color = colorScheme == .dark 
                        ? .white.opacity(0.55) 
                        : .black.opacity(0.5)
                    
                    HStack(spacing: 5) {
                        Image(systemName: change.isPositive ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(changeColor)
                        Text("\(sign)\(formattedChange)%")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(changeColor)
                        Text("(\(timeframeLabel))")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(timeframeLabelColor)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: badgeBgColors,
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .overlay(Capsule().stroke(changeColor.opacity(colorScheme == .dark ? 0.35 : 0.45), lineWidth: 1))
                    )
                    .position(x: origin.x + 68, y: origin.y + 18)
                    .allowsHitTesting(false)
                }

                // Loading badge removed per user request — seamless timeframe switching
                // with no loading indicators, matching professional trading apps

                // Compact indicator legend - positioned at bottom-left of chart
                // This avoids overlapping with the price change badge at top-left
                if indShowLegend && overlayIndicatorCount > 0 && !showCrosshair, let plotAnchor = proxy.plotFrame {
                    let plotFrame = geo[plotAnchor]
                    
                    // Professional TradingView-style inline legend at bottom-left
                    HStack(spacing: 6) {
                        if indSMAEnabled {
                            HStack(spacing: 3) {
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(DS.Colors.smaLine)
                                    .frame(width: 12, height: 2)
                                Text("SMA \(indSMAPeriod)")
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .foregroundColor(DS.Colors.smaLine)
                            }
                        }
                        if indEMAEnabled {
                            HStack(spacing: 3) {
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(DS.Colors.emaLine)
                                    .frame(width: 12, height: 2)
                                Text("EMA \(indEMAPeriod)")
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .foregroundColor(DS.Colors.emaLine)
                            }
                        }
                        if indBBEnabled {
                            HStack(spacing: 3) {
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(DS.Colors.bbLine)
                                    .frame(width: 12, height: 2)
                                Text("BB \(indBBPeriod)")
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .foregroundColor(DS.Colors.bbLine)
                            }
                        }
                        if indVWAPEnabled {
                            HStack(spacing: 3) {
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.cyan)
                                    .frame(width: 12, height: 2)
                                Text("VWAP")
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .foregroundColor(Color.cyan)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(colorScheme == .dark
                                  ? Color(red: 0.08, green: 0.08, blue: 0.10)
                                  : Color(red: 0.95, green: 0.95, blue: 0.96))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06), lineWidth: 0.5)
                    )
                    .fixedSize(horizontal: true, vertical: false)
                    // Position at bottom-left of chart, above any volume overlay
                    .position(
                        x: plotFrame.origin.x + 70,
                        y: plotFrame.origin.y + plotFrame.height - 18
                    )
                    .allowsHitTesting(false)
                }

                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                // Begin haptic session when drag starts
                                #if os(iOS)
                                if !showCrosshair {
                                    ChartHaptics.shared.begin()
                                    // HAPTIC FIX: Initialize to nil - will be set to first touched value
                                    // This tracks USER'S explored range, not chart extremes
                                    hapticSessionMin = nil
                                    hapticSessionMax = nil
                                    hapticSessionStarted = false
                                }
                                #endif

                                guard let plotAnchor = proxy.plotFrame else { return }
                                let plotFrame = geo[plotAnchor]
                                let origin = plotFrame.origin
                                let rawX = value.location.x - origin.x
                                // Clamp x to plot bounds so edge touches select first/last data points
                                let x = min(max(rawX, 0), plotFrame.width)
                                if let date: Date = proxy.value(atX: x) {
                                    // Use the unified aligned render points for crosshair snapping.
                                    let resampled = self.alignedRenderPoints
                                    if let nearest = self.findClosest(to: date, useResampled: true),
                                       let idx = resampled.firstIndex(where: { $0.id == nearest.id }) {

                                        // Tick haptic when data point index changes
                                        // Fires once per volume bar for meaningful feedback
                                        #if os(iOS)
                                        if lastHapticIndex != idx {
                                            ChartHaptics.shared.tickIfNeeded()
                                            lastHapticIndex = idx
                                        }
                                        #endif

                                        // Zero-crossing haptic (relative to baseline - first value)
                                        #if os(iOS)
                                        if let baseline = resampled.first?.close {
                                            let isAbove = nearest.close >= baseline
                                            if let prev = lastAboveBaseline, prev != isAbove {
                                                ChartHaptics.shared.majorIfNeeded(intensity: 0.9)
                                            }
                                            lastAboveBaseline = isAbove
                                        }
                                        #endif

                                        // HAPTIC FIX: Track user's exploration range, not chart extremes
                                        #if os(iOS)
                                        if !hapticSessionStarted {
                                            // First value touched - initialize tracking
                                            hapticSessionMin = nearest.close
                                            hapticSessionMax = nearest.close
                                            hapticSessionStarted = true
                                        } else {
                                            // Major haptic when hitting new session min/max
                                            if let mn = hapticSessionMin, nearest.close < mn {
                                                hapticSessionMin = nearest.close
                                                ChartHaptics.shared.majorIfNeeded(intensity: 0.9)
                                            }
                                            if let mx = hapticSessionMax, nearest.close > mx {
                                                hapticSessionMax = nearest.close
                                                ChartHaptics.shared.majorIfNeeded(intensity: 0.9)
                                            }
                                        }
                                        #endif

                                        // Check if at rightmost (most recent) point - use live price for seamless sync with header
                                        let isRightmost = idx == resampled.count - 1
                                        if isRightmost, let live = livePrice, live > 0 {
                                            // Create a synthetic point with live price for tooltip, preserving original date
                                            crosshairDataPoint = ChartDataPoint(date: nearest.date, close: live, volume: nearest.volume)
                                        } else {
                                            crosshairDataPoint = nearest
                                        }
                                        // Store normalized x position for sub-chart alignment
                                        // CRITICAL: Use the data point's actual x position, not the raw touch position
                                        // This ensures sub-chart lines align with the main chart's RuleMark(x: cp.date)
                                        if let dataPointXPos = proxy.position(forX: nearest.date) {
                                            crosshairXFraction = plotFrame.width > 0 ? dataPointXPos / plotFrame.width : 0
                                        } else {
                                            crosshairXFraction = plotFrame.width > 0 ? x / plotFrame.width : 0
                                        }
                                        showCrosshair = true
                                    }
                                }
                            }
                            .onEnded { _ in
                                #if os(iOS)
                                ChartHaptics.shared.end()
                                #endif
                                showCrosshair = false
                                crosshairXFraction = 0
                                lastHapticIndex = nil
                                lastAboveBaseline = nil
                                hapticSessionMin = nil
                                hapticSessionMax = nil
                                hapticSessionStarted = false
                            }
                    )
                
                // In-plot settings menu (top-left of plot area, above gestures)
                if showInPlotSettingsButton, let plotAnchor = proxy.plotFrame {
                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        showInPlotSettingsPopover = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 13, weight: .semibold))
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(.secondary)
                            .padding(8)
                            // PERFORMANCE FIX v19: Replaced .ultraThinMaterial
                            .background(DS.Adaptive.chipBackground, in: Circle())
                            .overlay(Circle().stroke(DS.Colors.badgeStroke.opacity(0.6), lineWidth: 0.5))
                            .accessibilityLabel("Chart settings")
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showInPlotSettingsPopover, arrowEdge: .top) {
                        InPlotChartSettingsPopover(
                            isPresented: $showInPlotSettingsPopover,
                            showSeparators: $userShowSeparators,
                            showNowLine: $userShowNowLine,
                            weekendShading: $userWeekendShading,
                            liveLinearInterpolation: $userLiveLinearInterpolation,
                            smaEnabled: $indSMAEnabled,
                            smaPeriod: $indSMAPeriod,
                            emaEnabled: $indEMAEnabled,
                            emaPeriod: $indEMAPeriod
                        )
                        .presentationCompactAdaptation(.popover)
                    }
                    .position(x: geo[plotAnchor].origin.x + 16,
                              y: geo[plotAnchor].origin.y + 16)
                    .zIndex(2)
                }
            }
        }
    }

    // Safe inset values that use cached values until measured
    // This prevents sub-charts from shifting when actual measurements arrive
    private var safeLeadingInset: CGFloat {
        hasValidInsets ? pricePlotLeadingInset : CGFloat(cachedLeadingInset)
    }
    private var safeTrailingInset: CGFloat {
        hasValidInsets ? pricePlotTrailingInset : CGFloat(cachedTrailingInset)
    }
    private var safePlotWidth: CGFloat {
        hasValidInsets ? plotAreaWidth : CGFloat(cachedPlotWidth)
    }

    // True when volume chart is the bottom-most sub-chart (no oscillators enabled)
    private var isVolumeBottomChart: Bool {
        enabledOscillatorCount == 0
    }
    
    // Determine which oscillator is the bottom-most (for showing x-axis)
    // Order: RSI, MACD, Stoch, OBV, ATR, MFI - the last enabled one shows x-axis
    private var isRSIBottomOscillator: Bool {
        indRSIEnabled && !indMACDEnabled && !indStochEnabled && !indOBVEnabled && !indATREnabled && !indMFIEnabled
    }
    private var isMACDBottomOscillator: Bool {
        indMACDEnabled && !indStochEnabled && !indOBVEnabled && !indATREnabled && !indMFIEnabled
    }
    private var isStochBottomOscillator: Bool {
        indStochEnabled && !indOBVEnabled && !indATREnabled && !indMFIEnabled
    }
    private var isOBVBottomOscillator: Bool {
        indOBVEnabled && !indATREnabled && !indMFIEnabled
    }
    private var isATRBottomOscillator: Bool {
        indATREnabled && !indMFIEnabled
    }
    private var isMFIBottomOscillator: Bool {
        indMFIEnabled
    }
    
    // Volume chart with TradingView-style rendering
    // Uses internal Y-axis spacing to match main chart's plot area for crosshair alignment
    // VOLUME FIX: Uses resampledDataPoints for consistency with integrated overlay
    // This ensures volume aggregation is consistent across both display modes
    private var volumeChartView: some View {
        // Use resampled data for proper volume aggregation on long timeframes
        let volumeData = alignedRenderPoints
        
        // Calculate volumeYMax from resampled data (not raw) for proper scaling
        let resampledVolumeYMax: Double = {
            let volumes = volumeData.map { $0.volume }.sorted()
            guard !volumes.isEmpty else { return volumeYMax }
            let idx = Int(Double(volumes.count - 1) * 0.98)
            let val = volumes[max(0, min(volumes.count - 1, idx))]
            return max(1, val)
        }()
        
        return CryptoVolumeView(
            dataPoints: volumeData,  // Use resampled data with aggregated volumes
            xDomain: xDomainPrice,
            halfCandleSpan: halfCandleSpan,
            volumeYMax: resampledVolumeYMax,
            showCrosshair: $showCrosshair,
            crosshairDataPoint: $crosshairDataPoint,
            crosshairXFraction: $crosshairXFraction,
            height: 70,
            volumeMAPeriod: volumeMAEnabled ? volumeMAPeriod : 0,
            trailingInset: safeTrailingInset,  // Pass actual Y-axis width for internal alignment
            leadingInset: safeLeadingInset,
            showXAxis: isVolumeBottomChart,
            interval: displayInterval,  // CRITICAL FIX: Use displayInterval for axis label consistency
            plotWidth: safePlotWidth
        )
        .transaction { $0.animation = nil } // Suppress animation on volume data changes
    }

    // RSI chart pane with dynamic height based on oscillator count
    // Uses internal Y-axis spacing to match main chart's plot area for crosshair alignment
    private var rsiChartView: some View {
        #if DEBUG
        _ = debugAssertPaneAlignment(name: "RSI", points: alignedRenderPoints, interval: displayInterval)
        #endif
        return RSIOscillatorView(
            dataPoints: alignedRenderPoints,
            xDomain: xDomainPrice,
            rsiPeriod: indRSIPeriod,
            showCrosshair: $showCrosshair,
            crosshairDataPoint: $crosshairDataPoint,
            crosshairXFraction: $crosshairXFraction,
            height: oscillatorHeight,
            isCompact: isCompactOscillatorMode,
            trailingInset: safeTrailingInset,
            leadingInset: safeLeadingInset,
            showXAxis: isRSIBottomOscillator,
            interval: displayInterval,  // CRITICAL FIX: Use displayInterval for axis label consistency
            plotWidth: safePlotWidth
        )
        .transaction { $0.animation = nil }
    }

    // MACD chart pane with dynamic height based on oscillator count
    // Uses internal Y-axis spacing to match main chart's plot area for crosshair alignment
    private var macdChartView: some View {
        #if DEBUG
        _ = debugAssertPaneAlignment(name: "MACD", points: alignedRenderPoints, interval: displayInterval)
        #endif
        return MACDOscillatorView(
            dataPoints: alignedRenderPoints,
            xDomain: xDomainPrice,
            fastPeriod: indMACDFast,
            slowPeriod: indMACDSlow,
            signalPeriod: indMACDSignal,
            showCrosshair: $showCrosshair,
            crosshairDataPoint: $crosshairDataPoint,
            crosshairXFraction: $crosshairXFraction,
            height: oscillatorHeight,
            isCompact: isCompactOscillatorMode,
            trailingInset: safeTrailingInset,
            leadingInset: safeLeadingInset,
            showXAxis: isMACDBottomOscillator,
            interval: displayInterval,  // CRITICAL FIX: Use displayInterval for axis label consistency
            plotWidth: safePlotWidth
        )
        .transaction { $0.animation = nil }
    }

    // Stochastic chart pane with dynamic height based on oscillator count
    // Uses internal Y-axis spacing to match main chart's plot area for crosshair alignment
    private var stochChartView: some View {
        #if DEBUG
        _ = debugAssertPaneAlignment(name: "Stochastic", points: alignedRenderPoints, interval: displayInterval)
        #endif
        return StochasticOscillatorView(
            dataPoints: alignedRenderPoints,
            xDomain: xDomainPrice,
            kPeriod: indStochK,
            dPeriod: indStochD,
            showCrosshair: $showCrosshair,
            crosshairDataPoint: $crosshairDataPoint,
            crosshairXFraction: $crosshairXFraction,
            height: oscillatorHeight,
            isCompact: isCompactOscillatorMode,
            trailingInset: safeTrailingInset,
            leadingInset: safeLeadingInset,
            showXAxis: isStochBottomOscillator,
            interval: displayInterval,  // CRITICAL FIX: Use displayInterval for axis label consistency
            plotWidth: safePlotWidth
        )
        .transaction { $0.animation = nil }
    }

    // OBV chart pane with dynamic height based on oscillator count
    // Uses internal Y-axis spacing to match main chart's plot area for crosshair alignment
    private var obvChartView: some View {
        #if DEBUG
        _ = debugAssertPaneAlignment(name: "OBV", points: alignedRenderPoints, interval: displayInterval)
        #endif
        return OBVOscillatorView(
            dataPoints: alignedRenderPoints,
            xDomain: xDomainPrice,
            showCrosshair: $showCrosshair,
            crosshairDataPoint: $crosshairDataPoint,
            crosshairXFraction: $crosshairXFraction,
            height: oscillatorHeight,
            isCompact: isCompactOscillatorMode,
            trailingInset: safeTrailingInset,
            leadingInset: safeLeadingInset,
            showXAxis: isOBVBottomOscillator,
            interval: displayInterval,  // CRITICAL FIX: Use displayInterval for axis label consistency
            plotWidth: safePlotWidth
        )
        .transaction { $0.animation = nil }
    }

    // ATR chart pane with dynamic height based on oscillator count
    // Uses internal Y-axis spacing to match main chart's plot area for crosshair alignment
    private var atrChartView: some View {
        #if DEBUG
        _ = debugAssertPaneAlignment(name: "ATR", points: alignedRenderPoints, interval: displayInterval)
        #endif
        return ATROscillatorView(
            dataPoints: alignedRenderPoints,
            xDomain: xDomainPrice,
            atrPeriod: indATRPeriod,
            showCrosshair: $showCrosshair,
            crosshairDataPoint: $crosshairDataPoint,
            crosshairXFraction: $crosshairXFraction,
            height: oscillatorHeight,
            isCompact: isCompactOscillatorMode,
            trailingInset: safeTrailingInset,
            leadingInset: safeLeadingInset,
            showXAxis: isATRBottomOscillator,
            interval: displayInterval,  // CRITICAL FIX: Use displayInterval for axis label consistency
            plotWidth: safePlotWidth
        )
        .transaction { $0.animation = nil }
    }

    // MFI chart pane with dynamic height based on oscillator count
    // Uses internal Y-axis spacing to match main chart's plot area for crosshair alignment
    private var mfiChartView: some View {
        #if DEBUG
        _ = debugAssertPaneAlignment(name: "MFI", points: alignedRenderPoints, interval: displayInterval)
        #endif
        return MFIOscillatorView(
            dataPoints: alignedRenderPoints,
            xDomain: xDomainPrice,
            mfiPeriod: indMFIPeriod,
            showCrosshair: $showCrosshair,
            crosshairDataPoint: $crosshairDataPoint,
            crosshairXFraction: $crosshairXFraction,
            height: oscillatorHeight,
            isCompact: isCompactOscillatorMode,
            trailingInset: safeTrailingInset,
            leadingInset: safeLeadingInset,
            showXAxis: isMFIBottomOscillator,
            interval: displayInterval,  // CRITICAL FIX: Use displayInterval for axis label consistency
            plotWidth: safePlotWidth
        )
        .transaction { $0.animation = nil }
    }

    private var chartContent: some View {
        // Show chart directly without skeleton placeholder
        // Sub-charts use safeLeadingInset/safeTrailingInset which provide consistent defaults
        // until actual measurements arrive, preventing visible layout shifts
        // Explicit heights ensure proper layout distribution on initial render
        #if DEBUG
        _ = debugValidateAlignmentInvariants()
        #endif
        return ZStack {
            VStack(spacing: 0) {
                priceChartView
                    // PERFORMANCE FIX: Only recreate chart when displayed data's interval actually changes
                    // Using displayInterval instead of interval prevents premature recreation during
                    // timeframe switches where data hasn't loaded yet. The chart only recreates when
                    // new data arrives and displayInterval is updated, producing a single clean transition.
                    .id("priceChart-\(displayInterval.rawValue)")
                    // GAP FIX: When sub-charts are below, render chart taller to include invisible
                    // x-axis labels (needed for Swift Charts alignment), then clip them away.
                    // Uses measured pricePlotBottomInset for precise clipping (includes internal gap + ticks + labels).
                    // When NO sub-charts are below, skip clipping so Y-axis labels render fully at edges.
                    .frame(height: hasSubChartsBelow ? priceChartHeight + pricePlotBottomInset : priceChartHeight)
                    .if(hasSubChartsBelow) { view in
                        view
                            .frame(height: priceChartHeight, alignment: .top)
                            .clipped()
                    }
                // Show separate volume pane only when not using integrated overlay
                // Use displayInterval to prevent sub-charts from appearing/disappearing
                // during the intermediate frame before onChange processes the switch
                if displayInterval != .live && showVolumeOverlay && !volumeIntegrated {
                    volumeChartView
                        .frame(height: volumePaneHeight)
                }
                if displayInterval != .live && indRSIEnabled {
                    rsiChartView
                        .frame(height: oscillatorHeight)
                }
                if displayInterval != .live && indMACDEnabled {
                    macdChartView
                        .frame(height: oscillatorHeight)
                }
                if displayInterval != .live && indStochEnabled {
                    stochChartView
                        .frame(height: oscillatorHeight)
                }
                if displayInterval != .live && indOBVEnabled {
                    obvChartView
                        .frame(height: oscillatorHeight)
                }
                if displayInterval != .live && indATREnabled {
                    atrChartView
                        .frame(height: oscillatorHeight)
                }
                if displayInterval != .live && indMFIEnabled {
                    mfiChartView
                        .frame(height: oscillatorHeight)
                }
            }
            .padding(.bottom, 4)  // Minimal padding for axis label clearance
            
            // PROFESSIONAL UX: No visible loading indicator during timeframe switch.
            // Old chart data stays visible until new data seamlessly replaces it.
            // This matches professional trading apps like TradingView and Coinbase Pro.
            
            // PROFESSIONAL UX: No loading spinner. The dark chart frame shows until data arrives
            // (typically 1-2 seconds). This matches TradingView/Coinbase Pro behavior where
            // the chart area is simply empty until data loads, rather than showing a spinner.
            // The price display above already shows the app is working.
            
            // PERFORMANCE FIX: Reconnecting state - show during auto-retry
            if vm.isRetrying && vm.dataPoints.isEmpty {
                chartReconnectingOverlay
            }
            // Error state overlay - show when data failed to load (after all retries exhausted)
            else if let error = vm.errorMessage, !vm.isLoading && !vm.isRetrying && !vm.isRefreshing {
                chartErrorOverlay(message: error, isNetworkError: !NetworkReachability.shared.isReachable)
            } else if vm.dataPoints.isEmpty && !vm.isLoading && !vm.isRetrying && !vm.isRefreshing {
                // Empty state with no explicit error - check network connectivity first
                if !NetworkReachability.shared.isReachable {
                    chartErrorOverlay(message: "No internet connection", isNetworkError: true)
                } else {
                    chartErrorOverlay(message: "Unable to load chart data", isNetworkError: false)
                }
            }
        }
        // Prevent layout animation during data updates and initial @AppStorage loading
        .animation(nil, value: indicatorPanesHeight)
        .animation(nil, value: priceChartHeight)
        .transaction { $0.animation = nil }
    }
    
    /// Loading overlay view - shown when chart data is being fetched
    private var chartLoadingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: DS.Colors.gold))
                .scaleEffect(1.2)
            
            Text("Loading chart...")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0.8),
                    Color.black.opacity(0.85)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    /// PERFORMANCE FIX: Reconnecting overlay - shown during auto-retry
    /// This provides visual feedback that the app is actively trying to reconnect
    private var chartReconnectingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: DS.Colors.gold.opacity(0.8)))
                .scaleEffect(1.0)
            
            Text("Reconnecting...")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.6))
            
            Text("Attempt \(vm.autoRetryCount)/\(vm.maxAutoRetries)")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0.75),
                    Color.black.opacity(0.8)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    // PROFESSIONAL UX: Removed chartRefreshingIndicator entirely.
    // No visible loading indicator during timeframe switching.
    // Old chart data stays visible until new data seamlessly replaces it,
    // matching the behavior of professional trading platforms.
    
    /// Error overlay view with retry button - shown when chart data fails to load
    @ViewBuilder
    private func chartErrorOverlay(message: String, isNetworkError: Bool = false) -> some View {
        VStack(spacing: 16) {
            Image(systemName: isNetworkError ? "wifi.slash" : "chart.line.downtrend.xyaxis")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(DS.Colors.gold.opacity(0.6))
            
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            
            Button {
                // Retry loading chart data
                reloadChart(for: symbol, interval: interval)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Retry")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(DS.Colors.gold)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DS.Colors.gold.opacity(0.15))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(DS.Colors.gold.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            // Semi-transparent overlay to ensure error is visible over chart background
            LinearGradient(
                colors: [
                    Color.black.opacity(0.85),
                    Color.black.opacity(0.9)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // Pre-load cached data synchronously before first render to prevent empty chart flash
    private func preloadCacheIfNeeded() {
        // Only preload if we haven't loaded data yet for this symbol/interval
        guard vm.dataPoints.isEmpty || currentSymbol != symbol else { return }
        
        // INSTANT DISPLAY: First try the strict freshness-checked cache (ideal path)
        if loadCachedDataForInterval(interval) { return }
        
        // FALLBACK: If the strict cache rejects data (stale), load ANY cached data
        // to prevent showing "Loading chart...". Stale data is better than a loading
        // screen — fresh data will replace it in the background.
        // LIVE MODE GUARD: Don't overwrite WebSocket data with candle cache.
        guard !vm.isLiveModeActive else { return }
        // CACHE KEY FIX: Use cacheSafeKey to match the ViewModel's cacheKey() function.
        // rawValue "1m" and "1M" collide on case-insensitive filesystems (iOS/macOS),
        // causing 1-minute data to be loaded for 1-month timeframe (and vice versa).
        let key = "\(symbol.uppercased())-\(interval.cacheSafeKey)"
        if let staleCache = vm.loadCache(key: key), staleCache.count >= 10 {
            // STALENESS GUARD: Filter stale cache to the correct time window so the X-axis
            // doesn't show labels from a previous session (e.g., evening data at 2 PM).
            var filtered = staleCache
            let lookback = interval.lookbackSeconds
            if lookback > 0 {
                let cutoffDate = Date().addingTimeInterval(-(lookback * 1.3))
                filtered = filtered.filter { $0.date >= cutoffDate }
            }
            guard filtered.count >= 5 else { return }
            vm.dataPoints = filtered
            vm.isLoading = false
            vm.isRefreshing = true  // Subtle indicator that refresh is happening
        }
    }
    
    /// SEAMLESS TRANSITION: Load cached data for a specific interval
    /// Returns true if cached data was loaded successfully, false otherwise
    /// This enables instant timeframe switching when cached data is available
    @discardableResult
    private func loadCachedDataForInterval(_ targetInterval: ChartInterval) -> Bool {
        // LIVE MODE: Never load cached candle data for LIVE interval.
        // LIVE builds its chart entirely from WebSocket ticks + a synthetic seed.
        guard targetInterval != .live else { return false }
        // CACHE COLLISION FIX: Use cacheSafeKey to match the ViewModel's cacheKey() function.
        // This ensures consistent key construction between view and view model.
        let key = "\(symbol.uppercased())-\(targetInterval.cacheSafeKey)"
        // SAFETY FIX: Guard against nil to prevent crash
        guard let cachesBase = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return false }
        let cacheDir = cachesBase.appendingPathComponent("ChartCache", isDirectory: true)
        let cacheURL = cacheDir.appendingPathComponent("\(key).json")
        
        // Cache freshness check: don't use stale cached data
        // Per-interval thresholds ensure short-timeframe caches are rejected sooner
        let maxStaleAge: TimeInterval = {
            targetInterval.maxAllowedDataAge
        }()
        
        // Helper to check if cached data is fresh
        func isCacheFresh(_ points: [ChartDataPoint]) -> Bool {
            guard let latestDate = points.last?.date else { return false }
            return Date().timeIntervalSince(latestDate) <= maxStaleAge
        }
        
        // Helper to filter data to the correct time window for the target interval
        // This prevents showing data from the wrong time range (e.g., 5-year data for a 1Y chart)
        func filterToTimeWindow(_ points: [ChartDataPoint]) -> [ChartDataPoint] {
            let lookback = targetInterval.lookbackSeconds
            guard lookback > 0 else { return points } // ALL timeframe - no filtering
            let cutoffDate = Date().addingTimeInterval(-(lookback * 1.3))
            return points.filter { $0.date >= cutoffDate }
        }
        
        // Try to load from memory cache first (fastest)
        if let cached = CryptoChartViewModel.getMemoryCache(key: key), !cached.isEmpty, isCacheFresh(cached) {
            let filtered = filterToTimeWindow(cached)
            guard !filtered.isEmpty else { return false }
            // STALENESS GUARD: Check if memory cache covers enough of the expected window
            let memExpectedWindow = targetInterval.lookbackSeconds
            var memNeedsRefresh = false
            if memExpectedWindow > 0, let first = filtered.first?.date, let last = filtered.last?.date {
                let dataSpan = last.timeIntervalSince(first)
                if dataSpan < memExpectedWindow * 0.5 {
                    memNeedsRefresh = true
                }
            }
            vm.dataPoints = filtered
            // FIX: Set volumeScaleMax from cached data so volume bars render correctly
            // immediately. Without this, volume bars used the previous timeframe's scale
            // until fetchData ran and set it from its own cache.
            vm.volumeScaleMax = vm.volumeCeiling(from: filtered)
            vm.isLoading = false
            vm.isRefreshing = memNeedsRefresh
            return true
        }
        
        // PERFORMANCE FIX: Check disk cache file freshness BEFORE reading/decoding.
        // FileManager.attributesOfItem is ~100x faster than reading + decoding the full JSON.
        // This avoids blocking the main thread on stale cache files during timeframe switching.
        if let attrs = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
           let modDate = attrs[.modificationDate] as? Date {
            let fileAge = Date().timeIntervalSince(modDate)
            // If the file itself is older than the stale threshold, skip the expensive read
            if fileAge > maxStaleAge * 1.5 {
                return false
            }
        }
        
        // PERFORMANCE: Use ViewModel's loadCache which checks memory first, then disk,
        // and auto-populates memory cache from disk. This avoids duplicate disk I/O
        // and ensures future switches to this interval hit the fast memory path.
        guard let pts = vm.loadCache(key: key), pts.count >= 10 else { return false }
        
        // Only use cache if it's fresh
        guard isCacheFresh(pts) else { return false }
        
        // DATA CONSISTENCY FIX: Filter cached data to correct time window
        let filtered = filterToTimeWindow(pts)
        guard !filtered.isEmpty else { return false }
        
        // STALENESS GUARD: Verify the cached data span covers a reasonable portion of the
        // expected time window. If the data only covers a small fraction (e.g., 2 hours of
        // an 8-hour 5m window), the X-axis labels would be compressed and misleading.
        // Still show the data (better than loading screen), but mark as refreshing.
        let expectedWindow = targetInterval.lookbackSeconds
        var needsRefresh = false
        if expectedWindow > 0, let first = filtered.first?.date, let last = filtered.last?.date {
            let dataSpan = last.timeIntervalSince(first)
            if dataSpan < expectedWindow * 0.5 {
                needsRefresh = true  // Data covers less than half the expected window
            }
        }
        
        vm.dataPoints = filtered
        // FIX: Set volumeScaleMax from cached data (same fix as memory cache above)
        vm.volumeScaleMax = vm.volumeCeiling(from: filtered)
        vm.isLoading = false
        vm.isRefreshing = needsRefresh
        return true
    }
    
    var body: some View {
        chartContent
            // Height is now calculated explicitly for each sub-view (priceChartHeight + indicator panes)
            // This ensures proper layout distribution on initial render without compression issues
            .frame(height: height)
            // Suppress all animations until layout is stable (prevents visual shift from @AppStorage loading)
            .transaction { t in
                if !isLayoutReady {
                    t.animation = nil
                }
            }
            // Note: Removed .clipped() to allow Y-axis labels to render fully at top/bottom edges
            // Y-axis labels can extend ~8pt beyond the chart bounds
            .onAppear {
                // Pre-load cache synchronously for instant display
                preloadCacheIfNeeded()
                self.currentSymbol = self.symbol
                // Initialize displayInterval to match the current interval on first appear
                self.displayInterval = self.interval
                // Initialize previousInterval so the first onChange(of: interval) can cancel
                // the onAppear fetch's inflight key (prevents dedup blocking on first switch)
                self.previousInterval = self.interval
                
                // CHART READJUST FIX: Treat initial load like a timeframe switch so that
                // when fresh API data arrives (~1s later), the recentSwitchNeedsRefresh path
                // in onChange(of: vm.dataVersion) triggers a clean Y-domain recomputation
                // with all caches cleared — instead of the gradual hysteresis adjustment
                // that causes the visible "readjust" shift.
                self.lastTimeframeSwitchAt = Date()
                
                self.reloadChart(for: self.symbol, interval: self.interval, symbolChanged: true)
                
                // CRITICAL FIX: Force recompute indicators on appear to sync with toggle states
                // Without force=true, cached indicator data may not match current toggle states
                // This ensures indicators are only shown when their toggles are actually ON
                recomputeIndicatorsIfNeeded(force: true)
                updateVisiblePointsCacheIfNeeded(force: true)
                updateVolumeStatsCacheIfNeeded()
                
                // CHART READJUST FIX: Increased from 50ms to 300ms to give time for the first
                // API data to arrive and plot insets to settle before animations are enabled.
                // At 50ms, the layout was "ready" before fresh data replaced cache data, so the
                // inset change (from new Y-axis label widths) animated visibly as a shift.
                // 300ms allows the data pipeline + inset measurement to complete invisibly.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
                    isLayoutReady = true
                }
            }
            .onChange(of: symbol) { _, newSymbol in
                // Clear error immediately when switching symbols (before async defer)
                vm.errorMessage = nil
                
                // TIMEFRAME SWITCH FIX: Stop live WebSocket immediately on symbol change.
                // The deferred reloadChart also calls stopLive, but the immediate call
                // prevents stale live data from the throttled pipeline corrupting the chart.
                if displayInterval == .live {
                    vm.stopLive()
                }
                vm.cancelAutoRetry()
                
                // SYMBOL SWITCH: Unlike interval changes (same coin, different timeframe),
                // symbol changes mean a COMPLETELY different coin with a different price range.
                // Freezing the old Y/X domain caches here would render the new coin's data
                // on the old coin's axes (e.g., BTC at $70K plotted on SOL's $87 Y-axis),
                // creating dramatic visual spikes. Instead, clear ALL caches immediately
                // so the new data renders with correct, fresh domains from the first frame.
                stableXDomainCache = nil
                stableYDomainCache = nil
                cachedResampledPoints = []
                lastResampledDataCount = 0
                lastResampledDomainHash = 0
                lastVolumeStatsDataCount = 0
                clearAllIndicatorCaches()
                consecutiveBufferExceedances = 0
                lastYDomainUpdateAt = .distantPast
                
                // Don't use pendingDataSwitch for symbol changes — it freezes old domains.
                // Instead, let new cached/fresh data render immediately with fresh domains.
                pendingDataSwitch = false
                didRetryForStaleData = false  // Reset for new symbol
                needsYDomainRefresh = true    // Force Y-domain recompute when fresh data arrives
                
                // SYMBOL CHANGE: Reset Coinbase fallback flag.
                // Coinbase failure is per-symbol, so when switching to a new coin,
                // try Coinbase first again (it might work for the new symbol).
                vm.coinbaseFallbackActive = false
                vm.coinbaseFallbackClosure = nil
                
                // Defer to avoid "Modifying state during view update"
                Task { @MainActor in
                    // Reload immediately on symbol change (reset pair resolution)
                    self.reloadChart(for: newSymbol, interval: self.interval, symbolChanged: true)
                }
            }
            .onChange(of: interval) { _, newInterval in
                #if DEBUG
                print("[Chart] onChange(interval): \(displayInterval.rawValue) → \(newInterval.rawValue) for \(symbol), dataPoints=\(vm.dataPoints.count)")
                #endif
                
                // Clear error immediately when switching timeframes (before async defer)
                vm.errorMessage = nil
                
                // Y-DOMAIN FAST SETTLE: Record the switch time so yDomain uses a shorter
                // stability interval (2s instead of 8s) for the first 10 seconds after switch.
                lastTimeframeSwitchAt = Date()
                
                // RACE CONDITION FIX: Cancel ALL stale work from previous switches.
                // Without this, rapidly switching 1m->5m->15m causes stale timeouts/fetches
                // from earlier switches to fire and corrupt state.
                switchSafetyTimeout4s?.cancel()
                switchSafetyTimeout4s = nil
                switchSafetyTimeout15s?.cancel()
                switchSafetyTimeout15s = nil
                debouncedFetchWork?.cancel()
                debouncedFetchWork = nil
                
                // STALE FETCH CANCELLATION: Cancel in-flight fetch for the PREVIOUS interval.
                // Without this, the old fetch continues running and when it completes, it
                // overwrites vm.dataPoints with old-interval data. Even with fetchSequence
                // guards, the in-flight deduplication key stays locked until the old fetch
                // completes or times out (30s), wasting resources and blocking re-fetches.
                if let prevInterval = previousInterval, prevInterval != newInterval {
                    let staleKey = vm.cacheKey(symbol: symbol, interval: prevInterval)
                    CryptoChartViewModel.completeInflightFetch(key: staleKey)
                }
                previousInterval = newInterval
                
                // TIMEFRAME SWITCH FIX: If switching FROM live mode, stop the WebSocket
                // IMMEDIATELY (synchronously) — not in the deferred DispatchQueue.main.async.
                if displayInterval == .live && newInterval != .live {
                    vm.stopLive()
                    vm.cancelAutoRetry()
                }
                
                // Snapshot the current X-domain BEFORE the interval changes its lookbackSeconds.
                if !vm.dataPoints.isEmpty {
                    stableXDomainCache = xDomain
                }
                pendingDataSwitch = true
                didRetryForStaleData = false
                
                // SEAMLESS TRANSITION: Try to load cached data for the new interval first
                let hasCachedData = loadCachedDataForInterval(newInterval)
                
                if hasCachedData {
                    // PERFORMANCE FIX: Only set essential state here. The dataPoints assignment
                    // in loadCachedDataForInterval already bumped dataVersion, so onChange(of: vm.dataVersion)
                    // will fire next and handle cache clearing + Y-domain computation.
                    // We just need to update display state so the current render frame shows correct labels.
                    stableXDomainCache = nil
                    pendingDataSwitch = false
                    displayInterval = newInterval
                    consecutiveBufferExceedances = 0
                }
                
                if !hasCachedData {
                    if newInterval == .live {
                        let nowDate = Date()
                        let nowPrice: Double = {
                            if let lp = livePrice, lp > 0 { return lp }
                            if let mp = MarketViewModel.shared.bestPrice(forSymbol: symbol), mp > 0 { return mp }
                            return 0
                        }()
                        
                        if nowPrice > 0 {
                            let seed = [
                                ChartDataPoint(date: nowDate.addingTimeInterval(-15), close: nowPrice),
                                ChartDataPoint(date: nowDate, close: nowPrice)
                            ]
                            vm.dataPoints = seed
                        }
                        
                        if !vm.dataPoints.isEmpty {
                            vm.isLoading = false
                            stableXDomainCache = nil
                            displayInterval = .live
                            pendingDataSwitch = false
                            cachedResampledPoints = []
                            lastResampledDataCount = 0
                            lastResampledDomainHash = 0
                            lastVolumeStatsDataCount = 0
                            clearAllIndicatorCaches()
                            let freshDomain = computeIdealYDomain()
                            stableYDomainCache = freshDomain
                            lastYDomainUpdateAt = Date()
                            consecutiveBufferExceedances = 0
                        }
                    } else {
                        // NO cached data: keep old chart data visible while network data loads.
                        // DISPLAY INTERVAL FIX: Update displayInterval immediately even without cache.
                        // The old approach kept displayInterval at the previous interval until network
                        // data arrived, causing the badge to show the wrong timeframe label (e.g., "(15m)"
                        // when user selected 30m). The stableXDomainCache and stableYDomainCache already
                        // freeze the chart visuals during the transition, so updating displayInterval
                        // only affects the badge label, x-axis formatting, and crosshair formatting —
                        // all of which SHOULD reflect the user's selection immediately.
                        displayInterval = newInterval
                        // Re-compute caches for the new displayInterval
                        cachedResampledPoints = []
                        lastResampledDataCount = 0
                        lastResampledDomainHash = 0
                        lastVolumeStatsDataCount = 0
                        clearAllIndicatorCaches()
                        vm.isLoading = true
                    }
                }
                
                // Safety timeout: update display after 1.5 seconds if data hasn't arrived.
                // PERFORMANCE FIX: Reduced from 2.5s. Firebase typically responds in 1-2s,
                // and a frozen chart feels sluggish. At 1.5s, the chart unfreezes quickly.
                let work4s = DispatchWorkItem { [self] in
                    if self.pendingDataSwitch {
                        let canUseOldData: Bool = {
                            guard let first = self.vm.dataPoints.first?.date,
                                  let last = self.vm.dataPoints.last?.date else { return false }
                            let dataSpan = last.timeIntervalSince(first)
                            let newLookback = Double(self.interval.lookbackSeconds)
                            if newLookback == 0 { return dataSpan > 30 * 86400 }
                            return dataSpan >= newLookback * 0.1
                        }()
                        
                        if canUseOldData {
                            self.stableXDomainCache = nil
                            self.displayInterval = self.interval
                            self.cachedResampledPoints = []
                            self.lastResampledDataCount = 0
                            self.lastResampledDomainHash = 0
                            self.lastVolumeStatsDataCount = 0
                            self.clearAllIndicatorCaches()
                            let freshDomain = self.computeIdealYDomain()
                            self.stableYDomainCache = freshDomain
                            self.lastYDomainUpdateAt = Date()
                            self.consecutiveBufferExceedances = 0
                        }
                    }
                }
                switchSafetyTimeout4s = work4s
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work4s)
                
                // Final safety net: after 15 seconds, fully sync displayInterval.
                let work15s = DispatchWorkItem { [self] in
                    if self.pendingDataSwitch || self.displayInterval != self.interval {
                        self.pendingDataSwitch = false
                        self.stableXDomainCache = nil
                        self.displayInterval = self.interval
                        self.cachedResampledPoints = []
                        self.lastResampledDataCount = 0
                        self.lastResampledDomainHash = 0
                        self.lastVolumeStatsDataCount = 0
                        self.clearAllIndicatorCaches()
                        let freshDomain = self.computeIdealYDomain()
                        self.stableYDomainCache = freshDomain
                        self.lastYDomainUpdateAt = Date()
                        self.consecutiveBufferExceedances = 0
                        self.vm.isLoading = false
                    }
                }
                switchSafetyTimeout15s = work15s
                DispatchQueue.main.asyncAfter(deadline: .now() + 15.0, execute: work15s)
                
                // IMMEDIATE FETCH: Trigger network fetch right away (no debounce).
                // The fetchSequence guard inside fetchData already handles rapid switching
                // by discarding stale responses. A 200ms debounce was previously used here
                // but caused timeframe switches to appear "stuck" because the DispatchWorkItem
                // closure could be lost in certain SwiftUI view lifecycle scenarios.
                // Using DispatchQueue.main.async (not asyncAfter) ensures the fetch runs
                // on the next run loop without any artificial delay.
                debouncedFetchWork?.cancel()
                let fetchWork = DispatchWorkItem { [self] in
                    #if DEBUG
                    print("[Chart] fetchWork EXECUTING: reloadChart for \(self.symbol) interval=\(newInterval.rawValue)")
                    #endif
                    self.reloadChart(for: self.symbol, interval: newInterval)
                }
                debouncedFetchWork = fetchWork
                DispatchQueue.main.async(execute: fetchWork)
            }
            .onReceive(nowTimer) { date in
                // PERFORMANCE: Only update 'now' when in live mode or when "Now" line is enabled
                // This prevents unnecessary re-renders for non-live timeframes
                guard displayInterval == .live || userShowNowLine else { return }
                
                // Defer to avoid "Modifying state during view update"
                Task { @MainActor in
                    // Keep `now` updated for live window and the "Now" line
                    self.now = date
                }
            }
            // PROFESSIONAL UX: No visible refresh indicator.
            // vm.isRefreshing is still used internally for state tracking,
            // but no UI element is shown. Old chart stays visible until replaced.
            .onDisappear {
                self.vm.stopLive()
                // Reset pending data switch flag to prevent stale state on reappear
                self.pendingDataSwitch = false
                self.stableXDomainCache = nil
                // Cancel any pending safety timeouts and debounced fetches
                self.switchSafetyTimeout4s?.cancel()
                self.switchSafetyTimeout4s = nil
                self.switchSafetyTimeout15s?.cancel()
                self.switchSafetyTimeout15s = nil
                self.debouncedFetchWork?.cancel()
                self.debouncedFetchWork = nil
            }
    }

    // MARK: – Indicators (SMA/EMA)
    
    // PERFORMANCE: Compute current settings hash to detect when indicator settings change
    // CRITICAL: Must include ALL indicator toggles and parameters to ensure proper cache invalidation
    private var currentIndicatorSettingsHash: Int {
        var hasher = Hasher()
        // Overlay indicators (SMA, EMA, BB, VWAP)
        hasher.combine(indSMAEnabled)
        hasher.combine(indSMAPeriod)
        hasher.combine(indEMAEnabled)
        hasher.combine(indEMAPeriod)
        hasher.combine(indBBEnabled)
        hasher.combine(indBBPeriod)
        hasher.combine(indBBDev)
        hasher.combine(indVWAPEnabled)
        // Oscillator indicators (RSI, MACD, Stochastic, OBV, ATR, MFI)
        hasher.combine(indRSIEnabled)
        hasher.combine(indRSIPeriod)
        hasher.combine(indMACDEnabled)
        hasher.combine(indMACDFast)
        hasher.combine(indMACDSlow)
        hasher.combine(indMACDSignal)
        hasher.combine(indStochEnabled)
        hasher.combine(indStochK)
        hasher.combine(indStochD)
        hasher.combine(indOBVEnabled)
        hasher.combine(indATREnabled)
        hasher.combine(indATRPeriod)
        hasher.combine(indMFIEnabled)
        hasher.combine(indMFIPeriod)
        // Volume settings
        hasher.combine(showVolumeOverlay)
        hasher.combine(volumeIntegrated)
        hasher.combine(volumeMAEnabled)
        hasher.combine(volumeMAPeriod)
        return hasher.finalize()
    }
    
    // MARK: - Indicator Cache Management
    
    /// Clears all indicator caches to ensure clean state.
    /// Call this when switching symbols, timeframes, or when indicators need full reset.
    private func clearAllIndicatorCaches() {
        // Clear computed indicator arrays
        cachedSMAPoints = []
        cachedEMAPoints = []
        cachedBBUpper = []
        cachedBBMiddle = []
        cachedBBLower = []
        cachedVWAPPoints = []
        
        // Clear visible (filtered) indicator arrays
        cachedVisibleSMAPoints = []
        cachedVisibleEMAPoints = []
        cachedVisibleBBUpper = []
        cachedVisibleBBMiddle = []
        cachedVisibleBBLower = []
        cachedVisibleVWAPPoints = []
        
        // Reset version tracking to force recomputation
        indicatorDataVersion = 0
        indicatorSettingsVersion = 0
        lastCachedXDomain = nil
    }
    
    // PERFORMANCE: Recompute all indicators only when data or settings change
    /// - Parameter force: If true, bypasses version checks and always recomputes.
    ///   Use force=true when called from onChange handlers to avoid race conditions
    ///   with SwiftUI's state batching.
    private func recomputeIndicatorsIfNeeded(force: Bool = false) {
        let newDataVersion = vm.dataVersion   // Uses version counter instead of count
        let newSettingsVersion = currentIndicatorSettingsHash
        
        // Check if we need to recompute (data or settings changed)
        // Force parameter bypasses this check - used when onChange fires
        if !force {
            guard newDataVersion != indicatorDataVersion || newSettingsVersion != indicatorSettingsVersion else {
                return
            }
        }
        
        indicatorDataVersion = newDataVersion
        indicatorSettingsVersion = newSettingsVersion
        
        let points = vm.dataPoints
        guard !points.isEmpty else {
            cachedSMAPoints = []
            cachedEMAPoints = []
            cachedBBUpper = []
            cachedBBMiddle = []
            cachedBBLower = []
            cachedVWAPPoints = []
            return
        }
        
        let closes = points.map { $0.close }
        
        // Compute SMA if enabled
        if indSMAEnabled {
            let ma = simpleMovingAverage(values: closes, period: max(2, indSMAPeriod))
            var pts: [ChartDataPoint] = []
            pts.reserveCapacity(ma.count)
            for (i, val) in ma.enumerated() {
                if let v = val {
                    pts.append(ChartDataPoint(date: points[i].date, close: v))
                }
            }
            cachedSMAPoints = pts
        } else {
            cachedSMAPoints = []
        }
        
        // Compute EMA if enabled
        if indEMAEnabled {
            let ma = exponentialMovingAverage(values: closes, period: max(2, indEMAPeriod))
            var pts: [ChartDataPoint] = []
            pts.reserveCapacity(ma.count)
            for (i, val) in ma.enumerated() {
                if let v = val {
                    pts.append(ChartDataPoint(date: points[i].date, close: v))
                }
            }
            cachedEMAPoints = pts
        } else {
            cachedEMAPoints = []
        }
        
        // Compute Bollinger Bands ONCE if enabled (not 3x!)
        if indBBEnabled {
            let bands = bollingerBandsSeries(values: closes, period: max(2, indBBPeriod), k: indBBDev)
            var upperPts: [ChartDataPoint] = []
            var middlePts: [ChartDataPoint] = []
            var lowerPts: [ChartDataPoint] = []
            upperPts.reserveCapacity(bands.upper.count)
            middlePts.reserveCapacity(bands.middle.count)
            lowerPts.reserveCapacity(bands.lower.count)
            
            for i in 0..<bands.middle.count {
                let date = points[i].date
                if let m = bands.middle[i] {
                    middlePts.append(ChartDataPoint(date: date, close: m))
                }
                if let u = bands.upper[i] {
                    upperPts.append(ChartDataPoint(date: date, close: u))
                }
                if let l = bands.lower[i] {
                    lowerPts.append(ChartDataPoint(date: date, close: l))
                }
            }
            cachedBBUpper = upperPts
            cachedBBMiddle = middlePts
            cachedBBLower = lowerPts
        } else {
            cachedBBUpper = []
            cachedBBMiddle = []
            cachedBBLower = []
        }
        
        // Compute VWAP if enabled
        if indVWAPEnabled {
            var vwapValues: [ChartDataPoint] = []
            vwapValues.reserveCapacity(points.count)
            var cumulativeTPV: Double = 0
            var cumulativeVolume: Double = 0
            
            for pt in points {
                cumulativeTPV += pt.close * pt.volume
                cumulativeVolume += pt.volume
                if cumulativeVolume > 0 {
                    let vwap = cumulativeTPV / cumulativeVolume
                    vwapValues.append(ChartDataPoint(date: pt.date, close: vwap))
                }
            }
            cachedVWAPPoints = vwapValues
        } else {
            cachedVWAPPoints = []
        }
        
        // Invalidate visible points cache when full indicators are recomputed
        lastCachedXDomain = nil
    }
    
    // PERFORMANCE: Update visible points cache only when X domain changes
    /// - Parameter force: If true, always refilters visible points regardless of domain change
    private func updateVisiblePointsCacheIfNeeded(force: Bool = false) {
        let currentDomain = xDomainPrice
        
        // Check if domain changed (unless force is true)
        if !force {
            if let last = lastCachedXDomain,
               last.lowerBound == currentDomain.lowerBound,
               last.upperBound == currentDomain.upperBound {
                return
            }
        }
        
        lastCachedXDomain = currentDomain
        
        // Filter cached indicator points to visible domain
        cachedVisibleSMAPoints = cachedSMAPoints.filter { $0.date >= currentDomain.lowerBound && $0.date <= currentDomain.upperBound }
        cachedVisibleEMAPoints = cachedEMAPoints.filter { $0.date >= currentDomain.lowerBound && $0.date <= currentDomain.upperBound }
        cachedVisibleBBUpper = cachedBBUpper.filter { $0.date >= currentDomain.lowerBound && $0.date <= currentDomain.upperBound }
        cachedVisibleBBMiddle = cachedBBMiddle.filter { $0.date >= currentDomain.lowerBound && $0.date <= currentDomain.upperBound }
        cachedVisibleBBLower = cachedBBLower.filter { $0.date >= currentDomain.lowerBound && $0.date <= currentDomain.upperBound }
        cachedVisibleVWAPPoints = cachedVWAPPoints.filter { $0.date >= currentDomain.lowerBound && $0.date <= currentDomain.upperBound }
    }
    
    // PERFORMANCE: Update volume stats cache only when data changes
    // This prevents recalculating maxVolume and typicalInterval on every render
    // STABILITY: Uses 98th percentile and only updates if change is significant (>20%)
    private func updateVolumeStatsCacheIfNeeded() {
        let currentDataCount = vm.dataVersion
        
        // Check if data version changed (reliable invalidation even when count stays the same)
        guard currentDataCount != lastVolumeStatsDataCount else { return }
        
        // FIX: Use domain-filtered points for accurate volume scaling
        // This ensures the maxVolume is calculated from visible data only
        let domain = xDomain
        let points = vm.dataPoints.filter { 
            $0.date >= domain.lowerBound && $0.date <= domain.upperBound 
        }
        
        // Fallback to all points if filtering results in empty
        let volumePoints = points.isEmpty ? vm.dataPoints : points
        
        // Calculate volume ceiling using 98th percentile (same as volumeCeiling method)
        // This avoids outliers from affecting the scale
        let volumes = volumePoints.map { $0.volume }.sorted()
        let newMaxVolume: Double
        if volumes.isEmpty {
            newMaxVolume = 1
        } else {
            let idx = Int(Double(volumes.count - 1) * 0.98)
            let val = volumes[max(0, min(volumes.count - 1, idx))]
            newMaxVolume = max(1, val)
        }
        
        // STABILITY: Only update if change is significant (>20%) or if uninitialized
        // This prevents visual jumps from small volume fluctuations
        let significantChange = cachedMaxVolume < 1 || 
                                abs(newMaxVolume - cachedMaxVolume) / cachedMaxVolume > 0.20
        if significantChange {
            cachedMaxVolume = newMaxVolume
        }
        
        // Calculate typical interval (median of first 20 intervals)
        if volumePoints.count >= 2 {
            var intervals: [TimeInterval] = []
            for i in 1..<min(volumePoints.count, 20) {
                let diff = volumePoints[i].date.timeIntervalSince(volumePoints[i-1].date)
                if diff > 0 { intervals.append(diff) }
            }
            intervals.sort()
            cachedTypicalInterval = intervals.isEmpty ? 300 : intervals[intervals.count / 2]
        } else {
            cachedTypicalInterval = 300 // Default 5 min
        }
        
        lastVolumeStatsDataCount = currentDataCount
    }
    
    private func simpleMovingAverage(values: [Double], period: Int) -> [Double?] {
        guard period > 1, values.count >= period else { return Array(repeating: nil, count: values.count) }
        var out = Array(repeating: Double?.none, count: values.count)
        var sum: Double = values[0..<period].reduce(0, +)
        out[period - 1] = sum / Double(period)
        if values.count > period {
            for i in period..<values.count {
                sum += values[i]
                sum -= values[i - period]
                out[i] = sum / Double(period)
            }
        }
        return out
    }

    private func exponentialMovingAverage(values: [Double], period: Int) -> [Double?] {
        guard period > 1, values.count >= period else { return Array(repeating: nil, count: values.count) }
        let k = 2.0 / (Double(period) + 1.0)
        var out = Array(repeating: Double?.none, count: values.count)
        // seed with SMA of the first period
        var seed = 0.0
        for i in 0..<period { seed += values[i] }
        var emaPrev = seed / Double(period)
        out[period - 1] = emaPrev
        if values.count > period {
            for i in period..<values.count {
                let ema = values[i] * k + emaPrev * (1 - k)
                out[i] = ema
                emaPrev = ema
            }
        }
        return out
    }

    // PERFORMANCE: Use cached values instead of recomputing on every access
    private var smaPoints: [ChartDataPoint] { cachedSMAPoints }
    private var emaPoints: [ChartDataPoint] { cachedEMAPoints }

    // Added helpers for last SMA and EMA points for badge display
    // Use on-demand computed points so badge shows the last visible value (not warm-up data)
    // FIX: Use on-demand properties for immediate response to toggle changes
    private var lastSMAPoint: ChartDataPoint? { smaIndicatorPointsOnDemand.last }
    private var lastEMAPoint: ChartDataPoint? { emaIndicatorPointsOnDemand.last }
    
    // MARK: - Filtered Indicator Points (visible domain only)
    // PERFORMANCE: Use cached visible points instead of filtering on every access
    
    private var visibleSMAPoints: [ChartDataPoint] { cachedVisibleSMAPoints }
    private var visibleEMAPoints: [ChartDataPoint] { cachedVisibleEMAPoints }
    private var visibleBBUpperPoints: [ChartDataPoint] { cachedVisibleBBUpper }
    private var visibleBBMiddlePoints: [ChartDataPoint] { cachedVisibleBBMiddle }
    private var visibleBBLowerPoints: [ChartDataPoint] { cachedVisibleBBLower }
    private var visibleVWAPPoints: [ChartDataPoint] { cachedVisibleVWAPPoints }
    
    // MARK: - On-Demand Indicator Points (FIX for toggle sync issue)
    // These computed properties check enabled state directly and compute synchronously
    // This ensures indicators render immediately when toggled without waiting for onChange
    
    /// SMA points computed on-demand - returns empty if disabled, computes fresh if cache empty
    private var smaIndicatorPointsOnDemand: [ChartDataPoint] {
        guard indSMAEnabled else { return [] }
        // Use cached if available and non-empty
        if !cachedVisibleSMAPoints.isEmpty { return cachedVisibleSMAPoints }
        // Otherwise compute fresh (this handles the case where toggle just changed)
        return computeSMAPointsSync()
    }
    
    /// EMA points computed on-demand - returns empty if disabled, computes fresh if cache empty
    private var emaIndicatorPointsOnDemand: [ChartDataPoint] {
        guard indEMAEnabled else { return [] }
        // Use cached if available and non-empty
        if !cachedVisibleEMAPoints.isEmpty { return cachedVisibleEMAPoints }
        // Otherwise compute fresh (this handles the case where toggle just changed)
        return computeEMAPointsSync()
    }
    
    /// PERFORMANCE: Unified Bollinger Bands computed on-demand - computes all three bands in ONE call
    /// This eliminates the triple computation that was causing lag when toggling BB on/off
    private var bollingerBandsOnDemand: (upper: [ChartDataPoint], middle: [ChartDataPoint], lower: [ChartDataPoint]) {
        guard indBBEnabled else { return ([], [], []) }
        
        // Priority 1: Use visible cache if populated (fastest - already filtered)
        if !cachedVisibleBBUpper.isEmpty && !cachedVisibleBBMiddle.isEmpty && !cachedVisibleBBLower.isEmpty {
            return (cachedVisibleBBUpper, cachedVisibleBBMiddle, cachedVisibleBBLower)
        }
        
        // Priority 2: Use full cache if populated (needs filtering but faster than recompute)
        if !cachedBBUpper.isEmpty && !cachedBBMiddle.isEmpty && !cachedBBLower.isEmpty {
            let domain = xDomainPrice
            let upper = cachedBBUpper.filter { $0.date >= domain.lowerBound && $0.date <= domain.upperBound }
            let middle = cachedBBMiddle.filter { $0.date >= domain.lowerBound && $0.date <= domain.upperBound }
            let lower = cachedBBLower.filter { $0.date >= domain.lowerBound && $0.date <= domain.upperBound }
            return (upper, middle, lower)
        }
        
        // Priority 3: Compute fresh (slowest - only when toggle just changed and caches are empty)
        return computeBBPointsSync()
    }
    
    /// BB Upper points computed on-demand (legacy accessor for compatibility)
    /// Note: These call bollingerBandsOnDemand which caches, so multiple calls are OK
    private var bbUpperPointsOnDemand: [ChartDataPoint] {
        bollingerBandsOnDemand.upper
    }
    
    /// BB Middle points computed on-demand (legacy accessor for compatibility)
    private var bbMiddlePointsOnDemand: [ChartDataPoint] {
        bollingerBandsOnDemand.middle
    }
    
    /// BB Lower points computed on-demand (legacy accessor for compatibility)
    private var bbLowerPointsOnDemand: [ChartDataPoint] {
        bollingerBandsOnDemand.lower
    }
    
    /// VWAP points computed on-demand
    private var vwapIndicatorPointsOnDemand: [ChartDataPoint] {
        guard indVWAPEnabled else { return [] }
        if !cachedVisibleVWAPPoints.isEmpty { return cachedVisibleVWAPPoints }
        return computeVWAPPointsSync()
    }
    
    /// Synchronously compute SMA points filtered to visible domain
    private func computeSMAPointsSync() -> [ChartDataPoint] {
        let points = vm.dataPoints
        guard !points.isEmpty else { return [] }
        let closes = points.map { $0.close }
        let ma = simpleMovingAverage(values: closes, period: max(2, indSMAPeriod))
        var pts: [ChartDataPoint] = []
        pts.reserveCapacity(ma.count)
        for (i, val) in ma.enumerated() {
            if let v = val {
                pts.append(ChartDataPoint(date: points[i].date, close: v))
            }
        }
        // Filter to visible domain
        let domain = xDomainPrice
        return pts.filter { $0.date >= domain.lowerBound && $0.date <= domain.upperBound }
    }
    
    /// Synchronously compute EMA points filtered to visible domain
    private func computeEMAPointsSync() -> [ChartDataPoint] {
        let points = vm.dataPoints
        guard !points.isEmpty else { return [] }
        let closes = points.map { $0.close }
        let ma = exponentialMovingAverage(values: closes, period: max(2, indEMAPeriod))
        var pts: [ChartDataPoint] = []
        pts.reserveCapacity(ma.count)
        for (i, val) in ma.enumerated() {
            if let v = val {
                pts.append(ChartDataPoint(date: points[i].date, close: v))
            }
        }
        // Filter to visible domain
        let domain = xDomainPrice
        return pts.filter { $0.date >= domain.lowerBound && $0.date <= domain.upperBound }
    }
    
    /// Synchronously compute Bollinger Bands points filtered to visible domain
    private func computeBBPointsSync() -> (upper: [ChartDataPoint], middle: [ChartDataPoint], lower: [ChartDataPoint]) {
        let points = vm.dataPoints
        guard !points.isEmpty else { return ([], [], []) }
        let closes = points.map { $0.close }
        let bands = bollingerBandsSeries(values: closes, period: max(2, indBBPeriod), k: indBBDev)
        
        var upperPts: [ChartDataPoint] = []
        var middlePts: [ChartDataPoint] = []
        var lowerPts: [ChartDataPoint] = []
        upperPts.reserveCapacity(bands.upper.count)
        middlePts.reserveCapacity(bands.middle.count)
        lowerPts.reserveCapacity(bands.lower.count)
        
        for i in 0..<bands.middle.count {
            let date = points[i].date
            if let m = bands.middle[i] {
                middlePts.append(ChartDataPoint(date: date, close: m))
            }
            if let u = bands.upper[i] {
                upperPts.append(ChartDataPoint(date: date, close: u))
            }
            if let l = bands.lower[i] {
                lowerPts.append(ChartDataPoint(date: date, close: l))
            }
        }
        
        // Filter to visible domain
        let domain = xDomainPrice
        let filteredUpper = upperPts.filter { $0.date >= domain.lowerBound && $0.date <= domain.upperBound }
        let filteredMiddle = middlePts.filter { $0.date >= domain.lowerBound && $0.date <= domain.upperBound }
        let filteredLower = lowerPts.filter { $0.date >= domain.lowerBound && $0.date <= domain.upperBound }
        
        return (filteredUpper, filteredMiddle, filteredLower)
    }
    
    /// Synchronously compute VWAP points filtered to visible domain
    private func computeVWAPPointsSync() -> [ChartDataPoint] {
        let points = vm.dataPoints
        guard !points.isEmpty else { return [] }
        
        var vwapValues: [ChartDataPoint] = []
        vwapValues.reserveCapacity(points.count)
        var cumulativeTPV: Double = 0
        var cumulativeVolume: Double = 0
        
        for pt in points {
            cumulativeTPV += pt.close * pt.volume
            cumulativeVolume += pt.volume
            if cumulativeVolume > 0 {
                let vwap = cumulativeTPV / cumulativeVolume
                vwapValues.append(ChartDataPoint(date: pt.date, close: vwap))
            }
        }
        
        // Filter to visible domain
        let domain = xDomainPrice
        return vwapValues.filter { $0.date >= domain.lowerBound && $0.date <= domain.upperBound }
    }
    
    // MARK: - Crosshair Indicator Value Lookups
    
    /// Look up SMA value at the crosshair data point's date
    private func smaValueAt(date: Date) -> Double? {
        guard indSMAEnabled else { return nil }
        return smaPoints.first(where: { $0.date == date })?.close
    }
    
    /// Look up EMA value at the crosshair data point's date
    private func emaValueAt(date: Date) -> Double? {
        guard indEMAEnabled else { return nil }
        return emaPoints.first(where: { $0.date == date })?.close
    }
    
    /// Look up BB values (upper, middle, lower) at the crosshair data point's date
    private func bbValuesAt(date: Date) -> (upper: Double, middle: Double, lower: Double)? {
        guard indBBEnabled else { return nil }
        guard let upper = bbUpperPoints.first(where: { $0.date == date })?.close,
              let middle = bbMiddlePoints.first(where: { $0.date == date })?.close,
              let lower = bbLowerPoints.first(where: { $0.date == date })?.close else {
            return nil
        }
        return (upper, middle, lower)
    }
    
    // MARK: – Bollinger Bands Calculation
    
    /// Computes Bollinger Bands series (middle SMA, upper, lower) for the entire dataset
    /// PERFORMANCE: True O(n) algorithm using rolling sums for both mean and variance
    /// Uses identity: Var(X) = E[X²] - E[X]² to avoid inner loops
    private func bollingerBandsSeries(values: [Double], period: Int, k: Double) -> (middle: [Double?], upper: [Double?], lower: [Double?]) {
        let count = values.count
        guard period > 1, count >= period else {
            let empty = Array(repeating: Double?.none, count: count)
            return (empty, empty, empty)
        }
        
        var middle = Array(repeating: Double?.none, count: count)
        var upper = Array(repeating: Double?.none, count: count)
        var lower = Array(repeating: Double?.none, count: count)
        
        let n = Double(period)
        
        // Initialize rolling sums for first window
        var rollingSum: Double = 0
        var rollingSumSquares: Double = 0
        for i in 0..<period {
            rollingSum += values[i]
            rollingSumSquares += values[i] * values[i]
        }
        
        // First point
        let firstMean = rollingSum / n
        let firstVariance = max(0, (rollingSumSquares / n) - (firstMean * firstMean))
        let firstStddev = sqrt(firstVariance)
        middle[period - 1] = firstMean
        upper[period - 1] = firstMean + k * firstStddev
        lower[period - 1] = firstMean - k * firstStddev
        
        // Process remaining points using rolling window - O(n)
        for i in period..<count {
            let oldValue = values[i - period]
            let newValue = values[i]
            
            // Update rolling sums by removing old value and adding new value
            rollingSum = rollingSum - oldValue + newValue
            rollingSumSquares = rollingSumSquares - (oldValue * oldValue) + (newValue * newValue)
            
            let mean = rollingSum / n
            // Variance = E[X²] - E[X]² with max(0, ...) to handle floating point errors
            let variance = max(0, (rollingSumSquares / n) - (mean * mean))
            let stddev = sqrt(variance)
            
            middle[i] = mean
            upper[i] = mean + k * stddev
            lower[i] = mean - k * stddev
        }
        
        return (middle, upper, lower)
    }
    
    // PERFORMANCE: Use cached values instead of recomputing on every access
    private var bbMiddlePoints: [ChartDataPoint] { cachedBBMiddle }
    private var bbUpperPoints: [ChartDataPoint] { cachedBBUpper }
    private var bbLowerPoints: [ChartDataPoint] { cachedBBLower }
    
    // Use on-demand computed points so badge shows the last visible value
    // FIX: Use on-demand properties for immediate response to toggle changes
    private var lastBBMiddlePoint: ChartDataPoint? { bbMiddlePointsOnDemand.last }
    private var lastBBUpperPoint: ChartDataPoint? { bbUpperPointsOnDemand.last }
    private var lastBBLowerPoint: ChartDataPoint? { bbLowerPointsOnDemand.last }

    // PERFORMANCE: Use cached values instead of recomputing on every access
    private var vwapPoints: [ChartDataPoint] { cachedVWAPPoints }
    
    // Use on-demand computed points so badge shows the last visible value
    // FIX: Use on-demand properties for immediate response to toggle changes
    private var lastVWAPPoint: ChartDataPoint? { vwapIndicatorPointsOnDemand.last }
    
    /// Look up VWAP value at the crosshair data point's date
    private func vwapValueAt(date: Date) -> Double? {
        guard indVWAPEnabled else { return nil }
        return vwapPoints.first(where: { $0.date == date })?.close
    }

    // MARK: - OBV Calculation
    
    /// Computes On Balance Volume series
    private var obvPoints: [ChartDataPoint] {
        guard indOBVEnabled else { return [] }
        let points = vm.dataPoints
        guard points.count >= 2 else { return [] }
        
        var obvValues: [ChartDataPoint] = []
        var obvValue: Double = 0
        
        // First point starts at 0
        obvValues.append(ChartDataPoint(date: points[0].date, close: 0))
        
        for i in 1..<points.count {
            if points[i].close > points[i-1].close {
                obvValue += points[i].volume
            } else if points[i].close < points[i-1].close {
                obvValue -= points[i].volume
            }
            // If close == prevClose, OBV stays the same
            obvValues.append(ChartDataPoint(date: points[i].date, close: obvValue))
        }
        
        return obvValues
    }
    
    private var lastOBVPoint: ChartDataPoint? { obvPoints.last }

    // MARK: – Helpers

    /// Finds the closest data point to a given date
    /// - Parameters:
    ///   - date: The target date to find
    ///   - useResampled: If true, searches resampled points (aligned with volume bars). If false, uses raw data.
    /// - Returns: The closest ChartDataPoint, or nil if no points available
    private func findClosest(to date: Date, useResampled: Bool = true) -> ChartDataPoint? {
        // Use resampled points by default for better alignment with volume bars
        // This ensures the crosshair snaps at the same granularity as the volume overlay
        let domain = xDomainPrice
        let sourcePoints = useResampled ? alignedRenderPoints : vm.dataPoints
        let points = sourcePoints.filter { $0.date >= domain.lowerBound && $0.date <= domain.upperBound }
        guard !points.isEmpty else { return nil }
        
        // Binary search for insertion point
        var low = 0
        var high = points.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let midDate = points[mid].date
            if midDate == date {
                return points[mid]
            } else if midDate < date {
                low = mid + 1
            } else {
                if mid == 0 { break }
                high = mid - 1
            }
        }
        // low is the index of the first element greater than the target date
        let idx = max(0, min(points.count - 1, low))
        if idx == 0 { return points[0] }
        if idx >= points.count { return points.last }
        let prev = points[idx - 1]
        let next = points[idx]
        // Choose the closer of the two neighboring points
        let dtPrev = date.timeIntervalSince(prev.date)
        let dtNext = next.date.timeIntervalSince(date)
        return dtPrev <= dtNext ? prev : next
    }
    
    #if DEBUG
    private func debugLogAlignmentWarning(_ message: String) {
        struct Throttle {
            static var lastLogAtByMessage: [String: CFAbsoluteTime] = [:]
        }
        let now = CFAbsoluteTimeGetCurrent()
        let minInterval: CFAbsoluteTime = 2.0
        if let last = Throttle.lastLogAtByMessage[message], (now - last) < minInterval {
            return
        }
        Throttle.lastLogAtByMessage[message] = now
        print(message)
    }
    
    @discardableResult
    private func debugAssertPaneAlignment(name: String, points: [ChartDataPoint], interval: ChartInterval) -> Bool {
        let domain = xDomainPrice
        let inDomain = points.allSatisfy { $0.date >= domain.lowerBound && $0.date <= domain.upperBound }
        let isSorted = zip(points, points.dropFirst()).allSatisfy { $0.date <= $1.date }
        let hasPositiveClose = points.allSatisfy { $0.close > 0 }
        let ok = inDomain && isSorted && hasPositiveClose && (interval == displayInterval)
        if !ok {
            debugLogAlignmentWarning("[ChartAlignment] \(name) pane misalignment detected: inDomain=\(inDomain) sorted=\(isSorted) positiveClose=\(hasPositiveClose) interval=\(interval.rawValue) display=\(displayInterval.rawValue)")
        }
        return ok
    }
    
    @discardableResult
    private func debugValidateAlignmentInvariants() -> Bool {
        let points = alignedRenderPoints
        let paneOK = debugAssertPaneAlignment(name: "SharedAlignedData", points: points, interval: displayInterval)
        let crosshairOK: Bool = {
            guard showCrosshair, let cp = crosshairDataPoint else { return true }
            return cp.date >= xDomainPrice.lowerBound && cp.date <= xDomainPrice.upperBound
        }()
        if !crosshairOK {
            debugLogAlignmentWarning("[ChartAlignment] Crosshair date is outside current xDomain.")
        }
        return paneOK && crosshairOK
    }
    #endif

    private var maxVolume: Double {
        vm.dataPoints.map(\.volume).max() ?? 1
    }

    /// Placeholder for a globally consistent max‐volume across timeframes.
    /// Currently returns the same as `maxVolume`. Later, one can adjust to use a stored or pre‐fetched value.
    private var overallMaxVolume: Double {
        if let cap = vm.volumeScaleMax, cap > 0 { return cap }
        return maxVolume
    }

    // Computed volume Y-axis maximum for proper scaling
    private var volumeYMax: Double {
        // Prioritize vm.volumeScaleMax (98th percentile) when available
        if let vmCap = vm.volumeScaleMax, vmCap > 0 {
            return vmCap
        }
        // Fallback: compute 95th percentile directly from current dataPoints
        // This prevents the "readjustment" caused by falling back to 1
        let volumes = vm.dataPoints.compactMap { $0.volume > 0 ? $0.volume : nil }
        guard !volumes.isEmpty else {
            // Only fall back to stableMaxVolume if we truly have no data
            return stableMaxVolume > 1 ? stableMaxVolume : 1000 // Reasonable default for initial render
        }
        let sorted = volumes.sorted()
        let p95Index = min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.95))
        let percentile95 = sorted[max(0, p95Index)]
        let mean = sorted.reduce(0, +) / Double(sorted.count)
        // Ensure reasonable bounds: at least 2x mean, capped at absolute max
        return max(percentile95, mean * 2)
    }

    // Replace candleSpan implementation with a stable static mapping per instructions
    private var candleSpan: TimeInterval {
        // Stabilize the candle width by using fixed spans per interval
        // Use displayInterval to match the currently displayed data during transitions
        switch displayInterval {
        case .oneYear:   return 86_400       // daily bars
        case .threeYear: return 604_800      // weekly bars
        case .all:       return 2_592_000    // ~30 days
        case .live:      return 60
        default:
            let s = displayInterval.secondsPerInterval
            return s > 0 ? s : 60
        }
    }

    // Reduced from 0.49 to 0.35 for thinner volume bars with visible gaps
    // This improves crosshair alignment - each finger movement changes the selected bar
    private var halfCandleSpan: TimeInterval { candleSpan * 0.35 }
}

// MARK: – View Extension for Conditional Modifier
extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

struct ChartQuickSettingsButton: View {
    @AppStorage("Chart.ShowSeparators") private var userShowSeparators: Bool = true
    @AppStorage("Chart.ShowNowLine") private var userShowNowLine: Bool = true
    @AppStorage("Chart.WeekendShading") private var userWeekendShading: Bool = false
    @AppStorage("Chart.LiveLinearInterpolation") private var userLiveLinearInterpolation: Bool = false
    @AppStorage("Chart.Indicators.SMA.Enabled") private var indSMAEnabled: Bool = false
    @AppStorage("Chart.Indicators.SMA.Period") private var indSMAPeriod: Int = 20
    @AppStorage("Chart.Indicators.EMA.Enabled") private var indEMAEnabled: Bool = false
    @AppStorage("Chart.Indicators.EMA.Period") private var indEMAPeriod: Int = 50
    
    // Bollinger Bands settings
    @AppStorage("Chart.Indicators.BB.Enabled") private var indBBEnabled: Bool = false
    @AppStorage("Chart.Indicators.BB.Period") private var indBBPeriod: Int = 20
    @AppStorage("Chart.Indicators.BB.Dev") private var indBBDev: Double = 2.0

    // Added new @AppStorage property for legend visibility
    @AppStorage("Chart.Indicators.ShowLegend") private var indShowLegend: Bool = true
    
    // Volume settings
    @AppStorage("Chart.VolumeIntegrated") private var volumeIntegrated: Bool = true
    @AppStorage("Chart.Volume.MA.Enabled") private var volumeMAEnabled: Bool = false
    @AppStorage("Chart.Volume.MA.Period") private var volumeMAPeriod: Int = 20

    // RSI settings
    @AppStorage("Chart.Indicators.RSI.Enabled") private var indRSIEnabled: Bool = false
    @AppStorage("Chart.Indicators.RSI.Period") private var indRSIPeriod: Int = 14

    // MACD settings
    @AppStorage("Chart.Indicators.MACD.Enabled") private var indMACDEnabled: Bool = false
    @AppStorage("Chart.Indicators.MACD.Fast") private var indMACDFast: Int = 12
    @AppStorage("Chart.Indicators.MACD.Slow") private var indMACDSlow: Int = 26
    @AppStorage("Chart.Indicators.MACD.Signal") private var indMACDSignal: Int = 9

    // Stochastic settings
    @AppStorage("Chart.Indicators.Stoch.Enabled") private var indStochEnabled: Bool = false
    @AppStorage("Chart.Indicators.Stoch.K") private var indStochK: Int = 14
    @AppStorage("Chart.Indicators.Stoch.D") private var indStochD: Int = 3
    
    @State private var showSettingsPopover: Bool = false

    // Computed property for active indicators count
    private var activeCount: Int { (indSMAEnabled ? 1 : 0) + (indEMAEnabled ? 1 : 0) + (indBBEnabled ? 1 : 0) + (indRSIEnabled ? 1 : 0) + (indMACDEnabled ? 1 : 0) + (indStochEnabled ? 1 : 0) + (volumeMAEnabled ? 1 : 0) }

    var body: some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            showSettingsPopover = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(8)
                    // PERFORMANCE FIX v19: Replaced .ultraThinMaterial
                    .background(DS.Adaptive.chipBackground, in: Capsule())
                if activeCount > 0 {
                    Text("\(activeCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.black)
                        .padding(4)
                        .background(DS.Colors.gold, in: Circle())
                        .offset(x: 6, y: -6)
                }
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showSettingsPopover, arrowEdge: .bottom) {
            ChartSettingsPopover(
                isPresented: $showSettingsPopover,
                showSeparators: $userShowSeparators,
                showNowLine: $userShowNowLine,
                weekendShading: $userWeekendShading,
                liveLinearInterpolation: $userLiveLinearInterpolation,
                smaEnabled: $indSMAEnabled,
                smaPeriod: $indSMAPeriod,
                emaEnabled: $indEMAEnabled,
                emaPeriod: $indEMAPeriod,
                bbEnabled: $indBBEnabled,
                bbPeriod: $indBBPeriod,
                showLegend: $indShowLegend,
                rsiEnabled: $indRSIEnabled,
                rsiPeriod: $indRSIPeriod,
                macdEnabled: $indMACDEnabled,
                macdFast: $indMACDFast,
                macdSlow: $indMACDSlow,
                macdSignal: $indMACDSignal,
                stochEnabled: $indStochEnabled,
                stochK: $indStochK,
                stochD: $indStochD,
                volumeIntegrated: $volumeIntegrated,
                volumeMAEnabled: $volumeMAEnabled,
                volumeMAPeriod: $volumeMAPeriod,
                onReset: {
                    indSMAEnabled = false
                    indEMAEnabled = false
                    indBBEnabled = false
                    indRSIEnabled = false
                    indMACDEnabled = false
                    indStochEnabled = false
                    indSMAPeriod = 20
                    indEMAPeriod = 50
                    indBBPeriod = 20
                    indBBDev = 2.0
                    indRSIPeriod = 14
                    indMACDFast = 12
                    indMACDSlow = 26
                    indMACDSignal = 9
                    indStochK = 14
                    indStochD = 3
                    volumeIntegrated = true  // Default to integrated mode
                    volumeMAEnabled = false
                    volumeMAPeriod = 20
                }
            )
            .presentationCompactAdaptation(.popover)
        }
    }
}

// MARK: - In-Plot Chart Settings Popover (Simplified)
private struct InPlotChartSettingsPopover: View {
    @Binding var isPresented: Bool
    @Binding var showSeparators: Bool
    @Binding var showNowLine: Bool
    @Binding var weekendShading: Bool
    @Binding var liveLinearInterpolation: Bool
    @Binding var smaEnabled: Bool
    @Binding var smaPeriod: Int
    @Binding var emaEnabled: Bool
    @Binding var emaPeriod: Int
    
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Header
                HStack {
                    Text("Chart Settings")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 0.5)
                    .padding(.horizontal, 6)
                
                // Chart options
                sectionHeader("Display")
                toggleRow("Day separators", isOn: $showSeparators)
                toggleRow("\"Now\" line", isOn: $showNowLine)
                toggleRow("Weekend shading", isOn: $weekendShading)
                toggleRow("Live interpolation", isOn: $liveLinearInterpolation)
                
                // Indicators
                sectionHeader("Indicators")
                toggleRow("SMA (\(smaPeriod))", isOn: $smaEnabled)
                presetRow(values: [7, 20, 50, 200], current: smaPeriod, onSelect: { smaPeriod = $0 })
                toggleRow("EMA (\(emaPeriod))", isOn: $emaEnabled)
                presetRow(values: [9, 12, 26, 50], current: emaPeriod, onSelect: { emaPeriod = $0 })
            }
            .padding(8)
        }
        .frame(maxHeight: 320)
        // PERFORMANCE FIX v19: Replaced .ultraThinMaterial
        .background(DS.Adaptive.chipBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            LinearGradient(colors: [Color.white.opacity(0.10), .clear], startPoint: .top, endPoint: .center)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.75)
                .allowsHitTesting(false)
        )
        .frame(width: 220)
    }
    
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(DS.Colors.gold)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }
    
    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            isOn.wrappedValue.toggle()
        } label: {
            HStack {
                Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isOn.wrappedValue ? DS.Colors.gold : Color.white.opacity(0.4))
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.9))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private func presetRow(values: [Int], current: Int, onSelect: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 4) {
            ForEach(values, id: \.self) { value in
                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    onSelect(value)
                } label: {
                    Text("\(value)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(current == value ? Color.black : Color.white.opacity(0.8))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(current == value ? DS.Colors.gold : Color.white.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }
}

// MARK: - Chart Settings Popover (Full)
private struct ChartSettingsPopover: View {
    @Binding var isPresented: Bool
    @Binding var showSeparators: Bool
    @Binding var showNowLine: Bool
    @Binding var weekendShading: Bool
    @Binding var liveLinearInterpolation: Bool
    @Binding var smaEnabled: Bool
    @Binding var smaPeriod: Int
    @Binding var emaEnabled: Bool
    @Binding var emaPeriod: Int
    @Binding var bbEnabled: Bool
    @Binding var bbPeriod: Int
    @Binding var showLegend: Bool
    @Binding var rsiEnabled: Bool
    @Binding var rsiPeriod: Int
    @Binding var macdEnabled: Bool
    @Binding var macdFast: Int
    @Binding var macdSlow: Int
    @Binding var macdSignal: Int
    @Binding var stochEnabled: Bool
    @Binding var stochK: Int
    @Binding var stochD: Int
    @Binding var volumeIntegrated: Bool
    @Binding var volumeMAEnabled: Bool
    @Binding var volumeMAPeriod: Int
    let onReset: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Header
                HStack {
                    Text("Chart Settings")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 0.5)
                    .padding(.horizontal, 6)
                
                // Chart options
                sectionHeader("Display")
                toggleRow("Day separators", isOn: $showSeparators)
                toggleRow("\"Now\" line", isOn: $showNowLine)
                toggleRow("Weekend shading", isOn: $weekendShading)
                toggleRow("Live interpolation", isOn: $liveLinearInterpolation)
                
                // Price Indicators
                sectionHeader("Price Indicators")
                toggleRow("SMA (\(smaPeriod))", isOn: $smaEnabled)
                presetRow(values: [7, 20, 50, 200], current: smaPeriod, onSelect: { smaPeriod = $0 })
                toggleRow("EMA (\(emaPeriod))", isOn: $emaEnabled)
                presetRow(values: [9, 12, 26, 50], current: emaPeriod, onSelect: { emaPeriod = $0 })
                toggleRow("BB (\(bbPeriod))", isOn: $bbEnabled)
                presetRow(values: [10, 20, 50], current: bbPeriod, onSelect: { bbPeriod = $0 })
                toggleRow("Show legend", isOn: $showLegend)
                
                // Oscillators
                sectionHeader("Oscillators")
                toggleRow("RSI (\(rsiPeriod))", isOn: $rsiEnabled)
                presetRow(values: [7, 14, 21], current: rsiPeriod, onSelect: { rsiPeriod = $0 })
                toggleRow("MACD (\(macdFast)/\(macdSlow)/\(macdSignal))", isOn: $macdEnabled)
                toggleRow("Stochastic (\(stochK)/\(stochD))", isOn: $stochEnabled)
                
                // Volume Display
                sectionHeader("Volume")
                // Toggle between overlay (on chart) and separate pane (below chart like indicators)
                HStack {
                    Text("Display")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                    Spacer()
                    Picker("", selection: $volumeIntegrated) {
                        Text("Overlay").tag(true)
                        Text("Pane").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 130)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                
                toggleRow("Volume MA (\(volumeMAPeriod))", isOn: $volumeMAEnabled)
                presetRow(values: [10, 20, 50], current: volumeMAPeriod, onSelect: { volumeMAPeriod = $0 })
                
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 0.5)
                    .padding(.horizontal, 6)
                    .padding(.top, 4)
                
                // Reset button
                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    #endif
                    onReset()
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12, weight: .medium))
                        Text("Reset all")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Color.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red.opacity(0.15))
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            }
            .padding(8)
        }
        .frame(maxHeight: 400)
        // PERFORMANCE FIX v19: Replaced .ultraThinMaterial
        .background(DS.Adaptive.chipBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            LinearGradient(colors: [Color.white.opacity(0.10), .clear], startPoint: .top, endPoint: .center)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.75)
                .allowsHitTesting(false)
        )
        .frame(width: 260)
    }
    
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(DS.Colors.gold)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }
    
    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            isOn.wrappedValue.toggle()
        } label: {
            HStack {
                Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isOn.wrappedValue ? DS.Colors.gold : Color.white.opacity(0.4))
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.9))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private func presetRow(values: [Int], current: Int, onSelect: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 4) {
            ForEach(values, id: \.self) { value in
                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    onSelect(value)
                } label: {
                    Text("\(value)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(current == value ? Color.black : Color.white.opacity(0.8))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(current == value ? DS.Colors.gold : Color.white.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }
}

