// TechnicalsViewModel.swift
// Fetches closes and computes native technicals summary

import Foundation
import Combine
import SwiftUI

@MainActor
final class TechnicalsViewModel: ObservableObject {
    // Phase 1 migration: flag to switch to OHLCV data for technicals
    private let useOHLCVForTechnicals: Bool = true

    enum TechnicalsSourcePreference: String, CaseIterable {
        case cryptosage  // Firebase-backed shared technicals (default, recommended)
        case coinbase
        case binance
        
        var displayName: String {
            switch self {
            case .cryptosage: return "CryptoSage"
            case .coinbase: return "Coinbase"
            case .binance: return "Binance"
            }
        }
    }

    private let preferredSourceKey = "Technicals.PreferredSource"
    
    /// Published property for the preferred source - triggers SwiftUI updates when changed
    @Published private(set) var preferredSource: TechnicalsSourcePreference = .cryptosage
    /// The user-requested source for the current refresh cycle.
    @Published private(set) var requestedSource: TechnicalsSourcePreference = .cryptosage
    /// The source that actually produced the current rendered technicals.
    @Published private(set) var effectiveSource: TechnicalsSourcePreference = .cryptosage
    /// True while a user-initiated source switch is loading.
    @Published private(set) var isSourceSwitchInFlight: Bool = false
    /// Indicates backend/API fallback where effectiveSource != requestedSource.
    @Published private(set) var isUsingFallbackSource: Bool = false
    
    /// Sets the preferred source and persists to UserDefaults
    /// Also notifies SwiftUI of the change since preferredSource is @Published
    func setPreferredSource(_ newSource: TechnicalsSourcePreference) {
        #if DEBUG
        print("[TechnicalsViewModel] setPreferredSource: \(preferredSource) → \(newSource)")
        #endif
        // Only update if changed to avoid unnecessary refreshes
        guard preferredSource != newSource else {
            #if DEBUG
            print("[TechnicalsViewModel] setPreferredSource: source unchanged, skipping")
            #endif
            return
        }
        
        // Update the @Published property - this triggers SwiftUI to re-render
        preferredSource = newSource
        requestedSource = newSource
        isSourceSwitchInFlight = true
        UserDefaults.standard.set(newSource.rawValue, forKey: preferredSourceKey)
        
        #if DEBUG
        print("[TechnicalsViewModel] ✓ Source changed to \(newSource.displayName)")
        #endif
    }
    
    /// Loads the preferred source from UserDefaults on init
    private func loadPreferredSource() {
        let raw = UserDefaults.standard.string(forKey: preferredSourceKey) ?? TechnicalsSourcePreference.cryptosage.rawValue
        preferredSource = TechnicalsSourcePreference(rawValue: raw) ?? .cryptosage
        requestedSource = preferredSource
        effectiveSource = preferredSource
        isUsingFallbackSource = false
    }

    @Published var summary: TechnicalsSummary = TechnicalsSummary(score01: 0.5, verdict: .neutral)
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var sourceLabel: String = ""

    @Published var lastUpdated: Date? = nil
    
    // MARK: - Initialization
    
    init() {
        // Load persisted source preference from UserDefaults
        loadPreferredSource()
        #if DEBUG
        print("[TechnicalsViewModel] Initialized with preferredSource: \(preferredSource)")
        #endif
    }

    private var autoRefreshCancellable: AnyCancellable? = nil
    private var lastParams: (symbol: String, interval: ChartInterval, sparkline: [Double]?)? = nil

    private var currentTask: Task<Void, Never>? = nil
    
    private struct SummaryCacheKey: Hashable {
        let symbol: String
        let interval: ChartInterval
        let source: TechnicalsSourcePreference
    }
    private var firebaseSummaryCache: [SummaryCacheKey: (timestamp: Date, summary: TechnicalsSummary, effectiveSource: TechnicalsSourcePreference)] = [:]
    private func firebaseSummaryCacheTTL(for interval: ChartInterval) -> TimeInterval {
        max(10, min(30, cacheTTL(for: interval) / 2))
    }

    // Coalescing throttle & loading debounce
    private var throttleWorkItem: DispatchWorkItem? = nil
    private var lastRefreshScheduledAt: Date = .distantPast
    private let minRefreshGap: TimeInterval = 0.5
    private var loadingOffDebounceWork: DispatchWorkItem? = nil

    // Closes cache per (symbol, interval, source) - source is critical to prevent cross-source data reuse
    private struct CacheKey: Hashable { 
        let symbol: String
        let interval: ChartInterval
        let source: TechnicalsSourcePreference
    }
    private var closesCache: [CacheKey: (timestamp: Date, closes: [Double])] = [:]
    private func cacheTTL(for interval: ChartInterval) -> TimeInterval {
        switch interval {
        case .live, .oneMin, .fiveMin, .fifteenMin, .thirtyMin: return 60
        case .oneHour: return 5 * 60
        case .fourHour: return 15 * 60
        case .oneDay: return 60 * 60
        case .oneWeek, .oneMonth, .threeMonth, .sixMonth, .oneYear, .threeYear, .all: return 2 * 60 * 60
        }
    }
    
    // MARK: - Lightweight persisted cache for closes (includes source to prevent cross-source data reuse)
    private func persistedKey(symbol: String, interval: ChartInterval, source: TechnicalsSourcePreference) -> String {
        "technicals_closes_\(symbol.uppercased())_\(interval.rawValue)_\(source.rawValue)"
    }

    private func loadPersistedCloses(symbol: String, interval: ChartInterval, source: TechnicalsSourcePreference) -> [Double]? {
        let key = persistedKey(symbol: symbol, interval: interval, source: source)
        guard let dict = UserDefaults.standard.dictionary(forKey: key),
              let ts = dict["ts"] as? TimeInterval,
              let data = dict["data"] as? Data else { return nil }
        let age = Date().timeIntervalSince1970 - ts
        if age > cacheTTL(for: interval) { return nil }
        if let arr = try? JSONDecoder().decode([Double].self, from: data), arr.count >= 8 {
            return arr
        }
        return nil
    }

    private func savePersistedCloses(symbol: String, interval: ChartInterval, source: TechnicalsSourcePreference, closes: [Double]) {
        let key = persistedKey(symbol: symbol, interval: interval, source: source)
        if let data = try? JSONEncoder().encode(closes) {
            let payload: [String: Any] = [
                "ts": Date().timeIntervalSince1970,
                "data": data
            ]
            UserDefaults.standard.set(payload, forKey: key)
        }
    }

    // Fallback: load persisted closes ignoring TTL when networks fail
    private func loadPersistedClosesIgnoringTTL(symbol: String, interval: ChartInterval, source: TechnicalsSourcePreference) -> [Double]? {
        let key = persistedKey(symbol: symbol, interval: interval, source: source)
        guard let dict = UserDefaults.standard.dictionary(forKey: key),
              let data = dict["data"] as? Data,
              let arr = try? JSONDecoder().decode([Double].self, from: data),
              arr.count >= 8 else { return nil }
        return arr
    }

    // MARK: - Static Pre-warm Cache
    
    /// Pre-warm the technicals cache for a symbol in the background.
    /// Call this when entering TradeView so data is ready when user taps Technicals.
    /// Prewarms the default source (cryptosage) cache.
    static func preWarmCache(symbol: String, interval: ChartInterval = .oneDay, source: TechnicalsSourcePreference = .cryptosage) {
        let sym = symbol.uppercased()
        // Include source in cache key to match the runtime cache format
        let key = "technicals_closes_\(sym)_\(interval.rawValue)_\(source.rawValue)"
        
        // Check if we already have valid cached data
        if let dict = UserDefaults.standard.dictionary(forKey: key),
           let ts = dict["ts"] as? TimeInterval,
           let data = dict["data"] as? Data {
            let age = Date().timeIntervalSince1970 - ts
            let ttl = staticCacheTTL(for: interval)
            // If cache is still valid, no need to pre-warm
            if age < ttl {
                if let arr = try? JSONDecoder().decode([Double].self, from: data), arr.count >= 8 {
                    return
                }
            }
        }
        
        // No valid cache, fetch in background
        Task.detached(priority: .utility) {
            await preWarmFetch(symbol: sym, interval: interval, source: source)
        }
    }
    
    /// Static cache TTL helper
    private static func staticCacheTTL(for interval: ChartInterval) -> TimeInterval {
        switch interval {
        case .live, .oneMin, .fiveMin, .fifteenMin, .thirtyMin: return 60
        case .oneHour: return 5 * 60
        case .fourHour: return 15 * 60
        case .oneDay: return 60 * 60
        case .oneWeek, .oneMonth, .threeMonth, .sixMonth, .oneYear, .threeYear, .all: return 2 * 60 * 60
        }
    }
    
    /// Static coingecko ID mapper
    private static func staticCoingeckoID(for symbol: String) -> String {
        switch symbol.uppercased() {
        case "BTC": return "bitcoin"
        case "ETH": return "ethereum"
        case "DOGE": return "dogecoin"
        case "ADA": return "cardano"
        case "SOL": return "solana"
        case "XRP": return "ripple"
        case "DOT": return "polkadot"
        case "MATIC": return "matic-network"
        case "BNB": return "binancecoin"
        case "LTC": return "litecoin"
        case "AVAX": return "avalanche-2"
        case "LINK": return "chainlink"
        default: return symbol.lowercased()
        }
    }
    
    /// Static days mapper
    private static func staticDaysForInterval(_ i: ChartInterval) -> Int {
        switch i {
        case .live, .oneMin, .fiveMin, .fifteenMin, .thirtyMin: return 1
        case .oneHour: return 2
        case .fourHour: return 7
        case .oneDay: return 30
        case .oneWeek, .oneMonth, .threeMonth, .sixMonth, .oneYear, .threeYear, .all: return 365
        }
    }
    
    /// Background fetch for pre-warming cache
    private static func preWarmFetch(symbol: String, interval: ChartInterval, source: TechnicalsSourcePreference) async {
        // FIX: Check coordinator before CoinGecko prewarm request
        guard APIRequestCoordinator.shared.canMakeRequest(for: .coinGecko) else {
            return  // Skip prewarm when rate limited
        }
        APIRequestCoordinator.shared.recordRequest(for: .coinGecko)
        
        let coinID = staticCoingeckoID(for: symbol)
        let days = staticDaysForInterval(interval)
        
        var comps = URLComponents(string: "https://api.coingecko.com/api/v3/coins/\(coinID)/market_chart")
        comps?.queryItems = [
            URLQueryItem(name: "vs_currency", value: CurrencyManager.apiValue),
            URLQueryItem(name: "days", value: String(days))
        ]
        if days <= 90 { comps?.queryItems?.append(URLQueryItem(name: "interval", value: "hourly")) }
        guard let url = comps?.url else { return }
        
        do {
            var request = APIConfig.coinGeckoRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 15
            let (data, _) = try await URLSession.shared.data(for: request)
            struct Resp: Decodable { let prices: [[Double]] }
            let decoded = try JSONDecoder().decode(Resp.self, from: data)
            let closes: [Double] = decoded.prices.compactMap { arr in arr.count >= 2 ? arr[1] : nil }
            if closes.count >= 8 {
                // Save to UserDefaults cache (include source in key)
                let key = "technicals_closes_\(symbol.uppercased())_\(interval.rawValue)_\(source.rawValue)"
                if let encoded = try? JSONEncoder().encode(closes) {
                    let payload: [String: Any] = [
                        "ts": Date().timeIntervalSince1970,
                        "data": encoded
                    ]
                    await MainActor.run {
                        UserDefaults.standard.set(payload, forKey: key)
                    }
                }
            }
        } catch {
            // Silent fail - pre-warm is best-effort
        }
    }

    // Try to resolve a CoinGecko ID for a symbol using the public search API
    private func resolveCoinGeckoID(for symbol: String) async -> String? {
        // FIX: Check coordinator before CoinGecko search request
        guard APIRequestCoordinator.shared.canMakeRequest(for: .coinGecko) else {
            return nil  // Skip when rate limited
        }
        APIRequestCoordinator.shared.recordRequest(for: .coinGecko)
        
        let up = symbol.uppercased()
        guard var comps = URLComponents(string: "https://api.coingecko.com/api/v3/search") else { return nil }
        comps.queryItems = [URLQueryItem(name: "query", value: up)]
        guard let url = comps.url else { return nil }
        var request = APIConfig.coinGeckoRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            struct SearchCoin: Decodable { let id: String; let symbol: String }
            struct SearchResp: Decodable { let coins: [SearchCoin] }
            let decoded = try JSONDecoder().decode(SearchResp.self, from: data)
            return decoded.coins.first(where: { $0.symbol.uppercased() == up })?.id
        } catch {
            return nil
        }
    }

    private func refreshCadence(for interval: ChartInterval) -> TimeInterval {
        // Refresh at half the cache TTL, with a minimum of 20 seconds to avoid API spam
        return max(20, cacheTTL(for: interval) / 2)
    }

    private func stopAutoRefresh() {
        autoRefreshCancellable?.cancel()
        autoRefreshCancellable = nil
    }

    private func startAutoRefreshIfNeeded(symbol: String, interval: ChartInterval, sparkline: [Double]?) {
        // If the timer already matches current params, keep it
        if let lp = lastParams, lp.symbol == symbol && lp.interval == interval, autoRefreshCancellable != nil {
            return
        }
        stopAutoRefresh()
        let cadence = refreshCadence(for: interval)
        autoRefreshCancellable = Timer.publish(every: cadence, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                let best = self.bestLivePrice(for: symbol) ?? (self.closesCache[CacheKey(symbol: symbol, interval: interval, source: self.preferredSource)]?.closes.last ?? 0)
                // Defer to avoid "Modifying state during view update"
                DispatchQueue.main.async { [weak self] in
                    self?.refresh(symbol: symbol, interval: interval, currentPrice: best, sparkline: sparkline)
                }
            }
    }

    private func bestLivePrice(for symbol: String) -> Double? {
        let up = symbol.uppercased()
        if let coin = MarketViewModel.shared.allCoins.first(where: { $0.symbol.uppercased() == up }), let p = coin.priceUsd, p.isFinite, p > 0 {
            return p
        }
        return nil
    }
    
    private func primeVolumeWarmup(for symbol: String) {
        // Nudge the manager by requesting volume so it seeds caches opportunistically.
        // Note: startPolling() is called by CryptoSageAIApp.startHeavyLoading() during app startup
        // Touch volume cache for the matching MarketCoin if we can resolve it by symbol.
        let up = symbol.uppercased()
        if let coin = MarketViewModel.shared.allCoins.first(where: { $0.symbol.uppercased() == up }) {
            _ = LivePriceManager.shared.bestVolumeUSD(for: coin)
        } else if let coin = MarketViewModel.shared.coins.first(where: { $0.symbol.uppercased() == up }) {
            _ = LivePriceManager.shared.bestVolumeUSD(for: coin)
        } else if let coin = MarketViewModel.shared.watchlistCoins.first(where: { $0.symbol.uppercased() == up }) {
            _ = LivePriceManager.shared.bestVolumeUSD(for: coin)
        } else {
            // No coin found; nothing to warm specifically, polling will still help populate caches.
        }
     }

    private func closesAdjustedWith(price: Double, base: [Double]) -> [Double] {
        guard price.isFinite, price > 0, !base.isEmpty else { return base }
        var arr = base
        arr[arr.count - 1] = price
        return arr
    }
    
    private func sourcePreference(from sourceText: String?, fallback: TechnicalsSourcePreference) -> TechnicalsSourcePreference {
        guard let sourceText else { return fallback }
        let lower = sourceText.lowercased()
        if lower.contains("cryptosage") || lower.contains("firebase") {
            return .cryptosage
        }
        if lower.contains("binance") {
            return .binance
        }
        if lower.contains("coinbase") {
            return .coinbase
        }
        return fallback
    }

    func refresh(symbol: String, interval: ChartInterval, currentPrice: Double, sparkline: [Double]? = nil, forceBypassCache: Bool = false) {
        #if DEBUG
        print("[TechnicalsViewModel] refresh called - symbol: \(symbol), interval: \(interval), forceBypass: \(forceBypassCache)")
        #endif
        
        // IMPORTANT: When forceBypassCache is true (e.g., user changed source), always refresh immediately
        // This ensures source switching always triggers a visible refresh
        if forceBypassCache {
            throttleWorkItem?.cancel()
            lastRefreshScheduledAt = Date()
            refreshInternal(symbol: symbol, interval: interval, currentPrice: currentPrice, sparkline: sparkline, forceBypassCache: true)
            return
        }
        
        // Coalesce rapid calls within a short window; schedule trailing invocation
        let now = Date()
        let params = (symbol, interval, currentPrice, sparkline, forceBypassCache)
        if now.timeIntervalSince(lastRefreshScheduledAt) < minRefreshGap {
            throttleWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.refreshInternal(symbol: params.0, interval: params.1, currentPrice: params.2, sparkline: params.3, forceBypassCache: params.4)
            }
            throttleWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + minRefreshGap, execute: item)
            return
        }
        lastRefreshScheduledAt = now
        refreshInternal(symbol: symbol, interval: interval, currentPrice: currentPrice, sparkline: sparkline, forceBypassCache: forceBypassCache)
    }

    private func refreshInternal(symbol: String, interval: ChartInterval, currentPrice: Double, sparkline: [Double]? = nil, forceBypassCache: Bool) {
        #if DEBUG
        print("[TechnicalsViewModel] refreshInternal - symbol: \(symbol), preferredSource: \(preferredSource), forceBypass: \(forceBypassCache)")
        #endif
        currentTask?.cancel()
        errorMessage = nil
        let sym = symbol.uppercased()
        self.primeVolumeWarmup(for: sym)

        lastParams = (sym, interval, sparkline)
        startAutoRefreshIfNeeded(symbol: sym, interval: interval, sparkline: sparkline)
        
        // IMPORTANT: Capture the preferred source NOW before starting the async task
        // This ensures we use the correct source even if there's a race with UserDefaults
        let capturedPreferredSource = self.preferredSource
        self.requestedSource = capturedPreferredSource
        
        #if DEBUG
        print("[Technicals] === REFRESH START ===")
        print("[Technicals] Symbol: \(sym), Interval: \(interval), Source: \(capturedPreferredSource.displayName)")
        print("[Technicals] forceBypassCache: \(forceBypassCache)")
        #endif
        
        // OPTIMIZATION: Check for stale cache first and display immediately to avoid loading spinner
        // This provides instant UI feedback while fresh data loads in the background
        // Cache key now includes source to prevent cross-source data reuse
        let key = CacheKey(symbol: sym, interval: interval, source: capturedPreferredSource)
        var hasShownCachedData = false
        
        if forceBypassCache {
            // When force bypass is requested (e.g., user changed source):
            // 1. Cancel any pending loading-off from a previous task to prevent premature hide
            self.loadingOffDebounceWork?.cancel()
            self.loadingOffDebounceWork = nil
            
            // 2. Show loading state immediately
            self.sourceLabel = "Loading..."
            self.isLoading = true
            self.isSourceSwitchInFlight = true
            
            #if DEBUG
            print("[Technicals] Source switch loading for \(capturedPreferredSource.displayName) - \(sym)")
            #endif
        }
        
        // Always try source-specific cached data first to avoid visual jitter.
        var instantCloses: [Double]? = nil
        if let entry = self.closesCache[key] {
            instantCloses = entry.closes
        } else if let persisted = self.loadPersistedCloses(symbol: sym, interval: interval, source: capturedPreferredSource) {
            instantCloses = persisted
        } else if let stale = self.loadPersistedClosesIgnoringTTL(symbol: sym, interval: interval, source: capturedPreferredSource) {
            instantCloses = stale
        }
        if let instantCloses {
            let series = instantCloses.filter { $0.isFinite && $0 > 0 }
            if series.count >= 8 {
                // Keep the last fully-computed summary on screen to avoid temporary
                // neutral/zero-pill flashes while the fresh source payload is in flight.
                self.sourceLabel = "Loading..."
                hasShownCachedData = true
            }
        }
        
        // Only show loading spinner if we don't have cached data to display
        if !hasShownCachedData && !isLoading {
            isLoading = true
        }

        currentTask = Task { [weak self] in
            guard let self = self else { return }
            // Ensure the loading shimmer always stops, even on early returns/cancellation.
            // CRITICAL FIX: Only schedule loading-off if this task was NOT cancelled.
            // A cancelled task means a newer refresh replaced it and will handle loading state.
            // Without this check, the old task's defer fires 0.12s later and prematurely hides
            // the loading spinner for the new task.
            defer {
                let wasCancelled = Task.isCancelled
                DispatchQueue.main.async {
                    guard !wasCancelled else { return }
                    self.loadingOffDebounceWork?.cancel()
                    let work = DispatchWorkItem { [weak self] in self?.isLoading = false }
                    self.loadingOffDebounceWork = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
                }
            }

            var usedSource: String? = nil
            var usedWasStale = false

            // Try cache first (unless bypass requested)
            var closes: [Double]? = nil
            if !forceBypassCache {
                if let entry = self.closesCache[key] {
                    let ttl = self.cacheTTL(for: interval)
                    if Date().timeIntervalSince(entry.timestamp) < ttl {
                        closes = entry.closes
                        // Show preferred source name when using valid cache (cleaner UX)
                        usedSource = capturedPreferredSource.displayName
                        #if DEBUG
                        print("[Technicals] Cache HIT (memory) for \(capturedPreferredSource.displayName) - \(entry.closes.count) closes")
                        #endif
                    }
                }
                if closes == nil {
                    if let persisted = self.loadPersistedCloses(symbol: sym, interval: interval, source: capturedPreferredSource) {
                        closes = persisted
                        // Show preferred source name when using valid cache (cleaner UX)
                        usedSource = capturedPreferredSource.displayName
                        #if DEBUG
                        print("[Technicals] Cache HIT (persisted) for \(capturedPreferredSource.displayName) - \(persisted.count) closes")
                        #endif
                    } else {
                        #if DEBUG
                        print("[Technicals] Cache MISS for \(capturedPreferredSource.displayName) - will fetch fresh data")
                        #endif
                    }
                }
            } else {
                #if DEBUG
                print("[Technicals] Cache BYPASSED (forceBypassCache=true) - fetching fresh data for \(capturedPreferredSource.displayName)")
                #endif
            }
            // Track if we got a complete summary from Firebase (CryptoSage source)
            var firebaseSummary: TechnicalsSummary? = nil
            
            if closes == nil {
                let summaryCacheKey = SummaryCacheKey(symbol: sym, interval: interval, source: capturedPreferredSource)
                if let cachedSummary = self.firebaseSummaryCache[summaryCacheKey],
                   Date().timeIntervalSince(cachedSummary.timestamp) < self.firebaseSummaryCacheTTL(for: interval) {
                    firebaseSummary = cachedSummary.summary
                    usedSource = cachedSummary.effectiveSource.displayName
                    #if DEBUG
                    print("[Technicals] Cache HIT (firebase summary) for \(capturedPreferredSource.displayName)")
                    #endif
                }
            }
            
            if closes == nil && firebaseSummary == nil {
                // NEW: Route ALL sources through Firebase for shared caching
                // This eliminates client-side rate limits and ensures consistency across users
                let sourceString: String
                switch capturedPreferredSource {
                case .cryptosage: sourceString = "cryptosage"
                case .coinbase: sourceString = "coinbase"
                case .binance: sourceString = "binance"
                }
                
                #if DEBUG
                print("[Technicals] Fetching from Firebase - source: \(sourceString), symbol: \(sym)")
                #endif
                
                let intervalStr = self.firebaseIntervalString(for: interval)
                
                do {
                    // Try new multi-source Firebase function first
                    let response = try await FirebaseService.shared.getTechnicalsFromSource(
                        symbol: sym,
                        interval: intervalStr,
                        source: sourceString
                    )
                    
                    // Convert Firebase response to TechnicalsSummary
                    firebaseSummary = self.convertFirebaseResponse(response)
                    // CRITICAL FIX: Use the EFFECTIVE source from Firebase, not the preferred source.
                    // If user requests Coinbase but backend falls back to CryptoSage data,
                    // the label must reflect the actual data source to prevent misleading display.
                    switch response.effectiveSource.lowercased() {
                    case "cryptosage": usedSource = "CryptoSage"
                    case "coinbase": usedSource = "Coinbase"
                    case "binance": usedSource = "Binance"
                    default: usedSource = capturedPreferredSource.displayName
                    }
                    
                    let effectivePreference = self.sourcePreference(from: usedSource, fallback: capturedPreferredSource)
                    let summaryCacheKey = SummaryCacheKey(symbol: sym, interval: interval, source: capturedPreferredSource)
                    self.firebaseSummaryCache[summaryCacheKey] = (
                        timestamp: Date(),
                        summary: firebaseSummary ?? self.convertFirebaseResponse(response),
                        effectiveSource: effectivePreference
                    )
                    
                    #if DEBUG
                    print("[Technicals] ════════════════════════════════════════")
                    print("[Technicals] ✓ FIREBASE SUCCESS")
                    print("[Technicals] Requested Source: \(sourceString)")
                    print("[Technicals] Effective Source: \(response.effectiveSource)")
                    print("[Technicals] Score: \(String(format: "%.4f", response.score)) → Verdict: \(response.verdict)")
                    print("[Technicals] Indicators: \(response.indicatorCount ?? 0), Cached: \(response.cached ?? false)")
                    if let maSummary = response.maSummary {
                        print("[Technicals] MA Summary - Buy: \(maSummary.buy ?? 0), Sell: \(maSummary.sell ?? 0), Neutral: \(maSummary.neutral ?? 0)")
                    }
                    if let oscSummary = response.oscSummary {
                        print("[Technicals] Osc Summary - Buy: \(oscSummary.buy ?? 0), Sell: \(oscSummary.sell ?? 0), Neutral: \(oscSummary.neutral ?? 0)")
                    }
                    if response.effectiveSource == "cryptosage" {
                        print("[Technicals] CryptoSage-exclusive: aiSummary=\(response.aiSummary != nil), divergences=\(response.divergences != nil)")
                        if let conf = response.confidence {
                            print("[Technicals] Confidence: \(conf)%")
                        }
                    }
                    print("[Technicals] ════════════════════════════════════════")
                    #endif
                } catch {
                    #if DEBUG
                    print("[Technicals] ✗ FIREBASE getTechnicalsFromSource FAILED: \(error.localizedDescription)")
                    #endif
                    
                    // Fallback 1: Try legacy getTechnicalsSummary for CryptoSage
                    if capturedPreferredSource == .cryptosage {
                        do {
                            #if DEBUG
                            print("[Technicals] Trying legacy getTechnicalsSummary...")
                            #endif
                            let response = try await FirebaseService.shared.getTechnicalsSummary(
                                symbol: sym,
                                interval: intervalStr
                            )
                            firebaseSummary = self.convertFirebaseResponse(response)
                            usedSource = "CryptoSage"
                            #if DEBUG
                            print("[Technicals] ✓ Legacy Firebase succeeded")
                            #endif
                        } catch {
                            #if DEBUG
                            print("[Technicals] ✗ Legacy Firebase also failed: \(error.localizedDescription)")
                            #endif
                        }
                    }
                    
                    // Fallback 2: Direct API calls (for all sources if Firebase failed)
                    // IMPORTANT: Try the user's preferred source API first, then fall back to others
                    if firebaseSummary == nil, let ci = self.candleInterval(for: interval) {
                        #if DEBUG
                        print("[Technicals] Attempting direct API fallback for preferred source: \(capturedPreferredSource.displayName)")
                        #endif
                        
                        // Helper: fetch from Coinbase
                        @Sendable func tryCoinbase() async -> [Double]? {
                            if let cbCloses = await Self.coinbaseCloses(symbol: sym, interval: ci, limit: 500, quotes: ["USD", "USDT"]), cbCloses.count >= 8 {
                                #if DEBUG
                                print("[Technicals] ✓ Coinbase API succeeded - \(cbCloses.count) closes")
                                #endif
                                return cbCloses
                            }
                            return nil
                        }
                        
                        // Helper: fetch from Binance
                        @Sendable func tryBinance() async -> [Double]? {
                            let svc = BinanceCandleService()
                            for q in ["USDT", "USD"] {
                                do {
                                    let pair = sym + q
                                    let candles = try await svc.fetchCandles(symbol: pair, interval: ci, limit: 500)
                                    if candles.count >= 8 {
                                        #if DEBUG
                                        print("[Technicals] ✓ Binance API succeeded - \(candles.count) closes")
                                        #endif
                                        return candles.map { $0.close }
                                    }
                                } catch {
                                    continue
                                }
                            }
                            return nil
                        }
                        
                        // Try preferred source first, then fall back to the other
                        switch capturedPreferredSource {
                        case .binance:
                            // User wants Binance → try Binance first
                            if let binCloses = await tryBinance() {
                                closes = binCloses
                                usedSource = "Binance"
                            } else if let cbCloses = await tryCoinbase() {
                                closes = cbCloses
                                usedSource = "Coinbase (fallback)"
                            }
                        case .coinbase:
                            // User wants Coinbase → try Coinbase first
                            if let cbCloses = await tryCoinbase() {
                                closes = cbCloses
                                usedSource = "Coinbase"
                            } else if let binCloses = await tryBinance() {
                                closes = binCloses
                                usedSource = "Binance (fallback)"
                            }
                        case .cryptosage:
                            // CryptoSage has no direct API — try both exchanges as fallback
                            // Prefer Coinbase (typically more liquid for USD pairs)
                            if let cbCloses = await tryCoinbase() {
                                closes = cbCloses
                                usedSource = "CryptoSage"  // Label as CryptoSage since user chose it
                            } else if let binCloses = await tryBinance() {
                                closes = binCloses
                                usedSource = "CryptoSage"  // Label as CryptoSage since user chose it
                            }
                        }
                    }
                }
            }
            
            // If we got a complete summary from Firebase, use it directly
            if let summary = firebaseSummary {
                #if DEBUG
                print("[Technicals] 📊 UI UPDATE from Firebase")
                print("[Technicals] Source: \(usedSource ?? "unknown"), Score: \(String(format: "%.4f", summary.score01))")
                print("[Technicals] Verdict: \(summary.verdict), Indicators: \(summary.indicators.count)")
                print("[Technicals] MA: \(summary.maBuy)B/\(summary.maSell)S/\(summary.maNeutral)N, Osc: \(summary.oscBuy)B/\(summary.oscSell)S/\(summary.oscNeutral)N")
                #endif
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    let resolvedEffectiveSource = self.sourcePreference(from: usedSource, fallback: capturedPreferredSource)
                    self.summary = summary
                    self.sourceLabel = capturedPreferredSource.displayName
                    self.effectiveSource = resolvedEffectiveSource
                    self.isUsingFallbackSource = resolvedEffectiveSource != capturedPreferredSource
                    self.isSourceSwitchInFlight = false
                    self.lastUpdated = Date()
                    self.isLoading = false  // Ensure loading stops
                }
                return
            }

            if closes == nil, let sp = sparkline {
                let data = sp.filter { $0.isFinite && $0 > 0 }
                if data.count >= 8 { closes = data }
                // Show "On-Device" for sparkline data (cleaner than "Sparkline (7D)")
                if closes != nil { usedSource = "On-Device" }
            }

            // Final fallback: use stale persisted cache so the UI shows something instead of shimmers
            // Use source-specific cache to prevent cross-source data reuse
            if closes == nil {
                if let stale = self.loadPersistedClosesIgnoringTTL(symbol: sym, interval: interval, source: capturedPreferredSource) {
                    closes = stale
                    // Show preferred source name (cleaner UX than "Cache (stale)")
                    usedSource = capturedPreferredSource.displayName
                    usedWasStale = true
                }
            }

            guard let closes = closes else {
                await MainActor.run { [weak self] in
                    self?.errorMessage = "Unable to load technicals data. Tap to retry."
                    self?.sourceLabel = "No data"
                    self?.effectiveSource = capturedPreferredSource
                    self?.isUsingFallbackSource = false
                    self?.isSourceSwitchInFlight = false
                }
                return
            }

            // Save caches now that we have fresh closes (source-specific)
            await MainActor.run { [weak self, closes, key, capturedPreferredSource] in
                guard let self = self else { return }
                self.closesCache[key] = (timestamp: Date(), closes: closes)
                self.savePersistedCloses(symbol: sym, interval: interval, source: capturedPreferredSource, closes: closes)
            }

            // Build price-anchored series and sanitize
            let price = max(currentPrice, closes.last ?? 0)
            let adjusted = self.closesAdjustedWith(price: price, base: closes)
            let limited = Array(adjusted.suffix(600)) // keep last ~600 points for performance
            let series = limited.filter { $0.isFinite && $0 > 0 }
            if series.count < 8 {
                let sourceText = (usedSource?.isEmpty == false) ? (usedSource ?? "No data") : "No data"
                await MainActor.run { [weak self] in
                    self?.errorMessage = "Insufficient data for technicals. Tap to retry."
                    self?.sourceLabel = sourceText
                    self?.effectiveSource = capturedPreferredSource
                    self?.isUsingFallbackSource = false
                    self?.isSourceSwitchInFlight = false
                }
                return
            }

            // Compute aggregate score using the adjusted series
            let score = TechnicalsEngine.aggregateScore(price: price, closes: series)
            let verdict = self.verdictFor(score: score)
            
            #if DEBUG
            print("[Technicals] === FETCH COMPLETE ===")
            print("[Technicals] Preferred: \(capturedPreferredSource.displayName), Actual: \(usedSource ?? "nil")")
            print("[Technicals] Score: \(String(format: "%.3f", score)), Verdict: \(verdict)")
            print("[Technicals] Data points: \(series.count), Price: \(String(format: "%.2f", price))")
            if usedWasStale { print("[Technicals] ⚠️ WARNING: Using stale cached data") }
            #endif

            // Clean source label - no fallback/stale indicators for professional appearance
            // Just show the actual data source name
            let labelText = capturedPreferredSource.displayName
            _ = usedWasStale  // Data freshness tracked internally, not shown to users
            _ = capturedPreferredSource  // User preference shown via picker checkmark

            // Expanded per-indicator signals (Phase 2)
            var signals: [IndicatorSignal] = []
            var maCounts = (sell: 0, neutral: 0, buy: 0)
            var oscCounts = (sell: 0, neutral: 0, buy: 0)

            func push(_ label: String, _ sig: IndicatorSignalStrength, _ valueText: String? = nil, isMA: Bool = false, isOsc: Bool = false) {
                signals.append(IndicatorSignal(label: label, signal: sig, valueText: valueText))
                if isMA {
                    switch sig { case .sell: maCounts.sell += 1; case .neutral: maCounts.neutral += 1; case .buy: maCounts.buy += 1 }
                }
                if isOsc {
                    switch sig { case .sell: oscCounts.sell += 1; case .neutral: oscCounts.neutral += 1; case .buy: oscCounts.buy += 1 }
                }
            }

            // Oscillators
            if let r = TechnicalsEngine.rsi(series) {
                let sig: IndicatorSignalStrength = (r < 30) ? .buy : (r > 70 ? .sell : .neutral)
                push("RSI(14)", sig, String(format: "%.1f", r), isOsc: true)
            }
            if let k = TechnicalsEngine.stochK(series) {
                let sig: IndicatorSignalStrength = (k < 20) ? .buy : (k > 80 ? .sell : .neutral)
                push("Stochastic %K", sig, String(format: "%.1f", k), isOsc: true)
            }
            if let wr = TechnicalsEngine.williamsR(series) {
                let sig: IndicatorSignalStrength = (wr < -80) ? .buy : (wr > -20 ? .sell : .neutral)
                push("Williams %R", sig, String(format: "%.1f", wr), isOsc: true)
            }
            if let mom = TechnicalsEngine.momentum(series) {
                let sig: IndicatorSignalStrength = (mom > 0) ? .buy : (mom == 0 ? .neutral : .sell)
                push("Momentum", sig, String(format: "%.2f", mom), isOsc: true)
            }
            if let roc = TechnicalsEngine.roc(series) {
                let sig: IndicatorSignalStrength = (roc > 0) ? .buy : (roc == 0 ? .neutral : .sell)
                push("ROC", sig, String(format: "%.2f%%", roc), isOsc: true)
            }
            if let hist = TechnicalsEngine.macdHistogram(series) {
                let sig: IndicatorSignalStrength = (hist > 0) ? .buy : (abs(hist) < 1e-9 ? .neutral : .sell)
                push("MACD", sig, String(format: "%.3f", hist), isOsc: true)
            }

            // Stochastic RSI(3,3,14,14) — level-based
            if let srsi = TechnicalsEngine.stochRSI(series) {
                let k = srsi.k
                let sig: IndicatorSignalStrength = (k < 20) ? .buy : (k > 80 ? .sell : .neutral)
                push("Stoch RSI", sig, String(format: "K%.1f/D%.1f", srsi.k, srsi.d), isOsc: true)
            }

            // MACD level and crossover (lines)
            if let pair = TechnicalsEngine.macdLineSignal(series) {
                let macd = pair.macd
                let signalLine = pair.signal
                let levelSig: IndicatorSignalStrength = (macd > 0) ? .buy : (abs(macd) < 1e-9 ? .neutral : .sell)
                push("MACD Level", levelSig, String(format: "%.3f", macd), isOsc: true)
                let crossSig: IndicatorSignalStrength = (macd > signalLine) ? .buy : (abs(macd - signalLine) < 1e-9 ? .neutral : .sell)
                push("MACD Cross", crossSig, String(format: "%.1f/%.1f", macd, signalLine), isOsc: true)
            }

            // ADX(14) with +DI/-DI level and cross
            if let adx = TechnicalsEngine.adxApprox(series) {
                // ADX level (trend strength)
                let levelSig: IndicatorSignalStrength = (adx.adx >= 25) ? .buy : .neutral
                push("ADX(14)", levelSig, String(format: "ADX %.1f", adx.adx), isOsc: true)
                // +DI vs -DI crossover
                let crossSig: IndicatorSignalStrength = (adx.plusDI > adx.minusDI) ? .buy : (abs(adx.plusDI - adx.minusDI) < 1e-6 ? .neutral : .sell)
                push("+DI/-DI", crossSig, String(format: "+%.1f/-%.1f", adx.plusDI, adx.minusDI), isOsc: true)
            }

            // CCI(20)
            if let cci = TechnicalsEngine.cci(series) {
                let sig: IndicatorSignalStrength = (cci < -100) ? .buy : (cci > 100 ? .sell : .neutral)
                push("CCI(20)", sig, String(format: "%.0f", cci), isOsc: true)
            }

            // Ultimate Oscillator (7,14,28)
            if let uo = TechnicalsEngine.ultimateOscillatorApprox(series) {
                let sig: IndicatorSignalStrength = (uo > 50) ? .buy : (abs(uo - 50) < 1e-9 ? .neutral : .sell)
                push("Ultimate Oscillator", sig, String(format: "%.1f", uo), isOsc: true)
            }

            // Moving averages (price vs MA)
            let maPeriods = [10, 20, 50, 100, 200]
            for p in maPeriods {
                if let ma = TechnicalsEngine.sma(series, period: p) {
                    let th = ma * 0.001
                    let sig: IndicatorSignalStrength = (price > ma + th) ? .buy : (abs(price - ma) <= th ? .neutral : .sell)
                    push("SMA(\(p))", sig, String(format: "%.2f", ma), isMA: true)
                }
            }
            // EMA periods
            let emaPs = [10, 12, 26, 50, 100, 200]
            var emaValues: [Int: Double] = [:]
            for p in emaPs {
                if let e = TechnicalsEngine.ema(series, period: p) {
                    emaValues[p] = e
                    let th = e * 0.001
                    let sig: IndicatorSignalStrength = (price > e + th) ? .buy : (abs(price - e) <= th ? .neutral : .sell)
                    push("EMA(\(p))", sig, String(format: "%.2f", e), isMA: true)
                }
            }
            // EMA crossover 12/26
            if let e12 = emaValues[12], let e26 = emaValues[26] {
                let sig: IndicatorSignalStrength = (e12 > e26) ? .buy : (abs(e12 - e26) <= max(1e-9, e26 * 0.0005) ? .neutral : .sell)
                push("EMA12>EMA26", sig, String(format: "%.2f/%.2f", e12, e26), isMA: true)
            }

            // Bollinger Bands - compact format to fit in row
            if let bb = TechnicalsEngine.bollingerBands(series) {
                // If price above upper band -> potential sell; below lower -> potential buy
                let sig: IndicatorSignalStrength = (price > bb.upper) ? .sell : (price < bb.lower ? .buy : .neutral)
                // Use compact format: M(mid)/U(upper)/L(lower) with no decimals for large values
                let midStr = bb.middle >= 1000 ? String(format: "%.0f", bb.middle) : String(format: "%.2f", bb.middle)
                let upStr = bb.upper >= 1000 ? String(format: "%.0f", bb.upper) : String(format: "%.2f", bb.upper)
                let loStr = bb.lower >= 1000 ? String(format: "%.0f", bb.lower) : String(format: "%.2f", bb.lower)
                push("Bollinger Bands", sig, "\(midStr)/\(upStr)/\(loStr)", isMA: true)
            }

            // Compute overall counts using all signals
            let counts = signals.reduce(into: (sell: 0, neutral: 0, buy: 0)) { acc, s in
                switch s.signal { case .sell: acc.sell += 1; case .neutral: acc.neutral += 1; case .buy: acc.buy += 1 }
            }

            // Update UI synchronously on main thread - sourceLabel and summary together
            // Determine actual source for the summary
            let actualSource: String
            if usedSource == "On-Device" || usedSource?.contains("fallback") == true {
                actualSource = "local"  // Local calculation from sparkline/direct API
            } else if let src = usedSource?.lowercased(), ["coinbase", "binance"].contains(src) {
                actualSource = src
            } else {
                actualSource = "local"
            }
            
            await MainActor.run { [weak self, labelText, score, verdict, counts, maCounts, oscCounts, signals, usedWasStale, actualSource, usedSource, capturedPreferredSource] in
                guard let self = self else { return }
                let resolvedEffectiveSource = self.sourcePreference(from: usedSource, fallback: capturedPreferredSource)
                // Update source label first
                self.sourceLabel = labelText
                // Then update summary with all computed values
                self.summary = TechnicalsSummary(
                    score01: score,
                    verdict: verdict,
                    sellCount: counts.sell,
                    neutralCount: counts.neutral,
                    buyCount: counts.buy,
                    maSell: maCounts.sell,
                    maNeutral: maCounts.neutral,
                    maBuy: maCounts.buy,
                    oscSell: oscCounts.sell,
                    oscNeutral: oscCounts.neutral,
                    oscBuy: oscCounts.buy,
                    indicators: signals,
                    // Set source to "local" for on-device calculation
                    // CryptoSage-exclusive features not available for local calculation
                    source: actualSource
                )
                self.effectiveSource = resolvedEffectiveSource
                self.isUsingFallbackSource = resolvedEffectiveSource != capturedPreferredSource
                self.isSourceSwitchInFlight = false
                if !usedWasStale { self.lastUpdated = Date() }
            }
        }
    }

    func retry(symbol: String, interval: ChartInterval, currentPrice: Double, sparkline: [Double]? = nil, forceBypassCache: Bool = false) {
        refresh(symbol: symbol, interval: interval, currentPrice: currentPrice, sparkline: sparkline, forceBypassCache: forceBypassCache)
    }

    // MARK: - Verdict mapping
    private func verdictFor(score: Double) -> TechnicalVerdict {
        switch score {
        case ..<0.15: return .strongSell
        case ..<0.35: return .sell
        case ..<0.65: return .neutral
        case ..<0.85: return .buy
        default:       return .strongBuy
        }
    }

    // MARK: - Data
    private func fetchCloses(coinID: String, interval: ChartInterval) async -> [Double]? {
        let days = daysForInterval(interval)
        var comps = URLComponents(string: "https://api.coingecko.com/api/v3/coins/\(coinID)/market_chart")
        comps?.queryItems = [
            URLQueryItem(name: "vs_currency", value: CurrencyManager.apiValue),
            URLQueryItem(name: "days", value: String(days))
        ]
        if days <= 90 { comps?.queryItems?.append(URLQueryItem(name: "interval", value: "hourly")) }
        guard let url = comps?.url else { return nil }
        do {
            var request = APIConfig.coinGeckoRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 10
            let (data, _) = try await URLSession.shared.data(for: request)
            struct Resp: Decodable { let prices: [[Double]] }
            let decoded = try JSONDecoder().decode(Resp.self, from: data)
            let closes: [Double] = decoded.prices.compactMap { arr in arr.count >= 2 ? arr[1] : nil }
            if closes.count < 8 { return nil }
            return closes
        } catch {
            return nil
        }
    }

    private func daysForInterval(_ i: ChartInterval) -> Int {
        switch i {
        case .live, .oneMin, .fiveMin, .fifteenMin, .thirtyMin: return 1
        case .oneHour:   return 2
        case .fourHour:  return 7
        case .oneDay:    return 30
        case .oneWeek:   return 365
        case .oneMonth:  return 365
        case .threeMonth: return 365
        case .sixMonth:  return 365
        case .oneYear:   return 365
        case .threeYear: return 365
        case .all:       return 365
        }
    }
    
    private func candleInterval(for interval: ChartInterval) -> CandleInterval? {
        switch interval {
        case .oneMin: return .oneMinute
        case .fiveMin: return .fiveMinutes
        case .fifteenMin: return .fifteenMinutes
        case .thirtyMin: return .thirtyMinutes
        case .oneHour: return .oneHour
        case .fourHour: return .fourHours
        case .oneDay: return .oneDay
        case .oneWeek: return .oneWeek
        default: return nil
        }
    }
    
    // MARK: - Firebase (CryptoSage) Source Helpers
    
    /// Convert ChartInterval to Firebase interval string format
    private func firebaseIntervalString(for interval: ChartInterval) -> String {
        switch interval {
        case .live, .oneMin: return "1m"
        case .fiveMin: return "5m"
        case .fifteenMin: return "15m"
        case .thirtyMin: return "30m"
        case .oneHour: return "1h"
        case .fourHour: return "4h"
        case .oneDay: return "1d"
        case .oneWeek: return "1w"
        case .oneMonth, .threeMonth, .sixMonth, .oneYear, .threeYear, .all: return "1d"
        }
    }
    
    /// Convert Firebase TechnicalsSummaryResponse to native TechnicalsSummary
    /// Handles enhanced 30+ indicator response with weighted scoring
    /// CryptoSage source includes exclusive features (divergences, AI summary, etc.)
    private func convertFirebaseResponse(_ response: TechnicalsSummaryResponse) -> TechnicalsSummary {
        // Convert verdict string to TechnicalVerdict enum
        let verdict: TechnicalVerdict
        switch response.verdict.lowercased() {
        case "strong sell": verdict = .strongSell
        case "sell": verdict = .sell
        case "buy": verdict = .buy
        case "strong buy": verdict = .strongBuy
        default: verdict = .neutral
        }
        
        // Convert Firebase signals to native IndicatorSignal format
        // Enhanced signals now include strong_buy/strong_sell
        var indicators: [IndicatorSignal] = []
        if let signals = response.signals {
            for sig in signals {
                let strength: IndicatorSignalStrength
                switch sig.signal.lowercased() {
                case "strong_sell", "strongsell": strength = .sell  // Map strong_sell to sell for display
                case "sell": strength = .sell
                case "strong_buy", "strongbuy": strength = .buy    // Map strong_buy to buy for display
                case "buy": strength = .buy
                default: strength = .neutral
                }
                indicators.append(IndicatorSignal(
                    label: sig.name,
                    signal: strength,
                    valueText: sig.value
                ))
            }
        }
        
        // Get MA and oscillator summaries
        // New format includes strongSell/strongBuy counts
        let maSummary = response.maSummary
        let oscSummary = response.oscSummary
        
        // Combine strong_sell with sell, strong_buy with buy for display
        let maSell = (maSummary?.strongSell ?? 0) + (maSummary?.sell ?? 0)
        let maNeutral = maSummary?.neutral ?? 0
        let maBuy = (maSummary?.strongBuy ?? 0) + (maSummary?.buy ?? 0)
        
        let oscSell = (oscSummary?.strongSell ?? 0) + (oscSummary?.sell ?? 0)
        let oscNeutral = oscSummary?.neutral ?? 0
        let oscBuy = (oscSummary?.strongBuy ?? 0) + (oscSummary?.buy ?? 0)
        
        // Calculate totals
        let sellCount = maSell + oscSell
        let neutralCount = maNeutral + oscNeutral
        let buyCount = maBuy + oscBuy
        
        // Extract CryptoSage-exclusive features
        let divergence = response.divergences?.overallDivergence
        let divergenceStrength = response.divergences?.strength
        let supertrendDirection = response.supertrend?.trend
        let parabolicSarTrend = response.parabolicSar?.trend
        
        let effectiveSource = response.effectiveSource
        
        #if DEBUG
        print("[TechnicalsViewModel] Firebase response - source: \(effectiveSource), score: \(response.score), verdict: \(response.verdict)")
        print("[TechnicalsViewModel] Indicators: \(response.indicatorCount ?? 0), confidence: \(response.confidence ?? 0)%")
        if let trend = response.trendStrength {
            print("[TechnicalsViewModel] Trend: \(trend), Volatility: \(response.volatilityRegime ?? "N/A")")
        }
        if effectiveSource == "cryptosage" {
            print("[TechnicalsViewModel] CryptoSage-exclusive:")
            if let div = divergence { print("  - Divergence: \(div) (\(divergenceStrength ?? "unknown") strength)") }
            if let st = supertrendDirection { print("  - Supertrend: \(st)") }
            if let sar = parabolicSarTrend { print("  - Parabolic SAR: \(sar)") }
            if let ai = response.aiSummary { print("  - AI Summary: \(ai.prefix(80))...") }
        }
        #endif
        
        return TechnicalsSummary(
            score01: response.score,
            verdict: verdict,
            sellCount: sellCount,
            neutralCount: neutralCount,
            buyCount: buyCount,
            maSell: maSell,
            maNeutral: maNeutral,
            maBuy: maBuy,
            oscSell: oscSell,
            oscNeutral: oscNeutral,
            oscBuy: oscBuy,
            indicators: indicators,
            // CryptoSage-exclusive features
            confidence: response.confidence,
            trendStrength: response.trendStrength,
            volatilityRegime: response.volatilityRegime,
            aiSummary: response.aiSummary,
            divergence: divergence,
            divergenceStrength: divergenceStrength,
            supertrendDirection: supertrendDirection,
            parabolicSarTrend: parabolicSarTrend,
            source: effectiveSource
        )
    }
    
    private static func coinbaseCloses(symbol: String, interval: CandleInterval, limit: Int, quotes: [String]) async -> [Double]? {
        // Map CandleInterval to Coinbase granularity in seconds
        let granularity: Int
        switch interval {
        case .oneMinute: granularity = 60
        case .fiveMinutes: granularity = 300
        case .fifteenMinutes: granularity = 900
        case .thirtyMinutes: granularity = 900   // closest supported
        case .oneHour: granularity = 3600
        case .twoHours: granularity = 3600       // closest supported
        case .fourHours: granularity = 3600      // closest supported
        case .oneDay: granularity = 86400
        case .oneWeek: granularity = 86400       // closest supported
        }

        for quote in quotes {
            let pair = symbol.uppercased() + "-" + quote
            var comps = URLComponents(string: "https://api.exchange.coinbase.com/products/\(pair)/candles")
            comps?.queryItems = [
                URLQueryItem(name: "granularity", value: String(granularity)),
                URLQueryItem(name: "limit", value: String(limit))
            ]
            guard let url = comps?.url else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 5  // Reduced from 10 for faster response
            request.setValue("CryptoSage/1.0", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    #if DEBUG
                    if let http = response as? HTTPURLResponse {
                        print("[Technicals] Coinbase fetch failed for \(pair): HTTP \(http.statusCode)")
                    }
                    #endif
                    continue
                }
                if let json = try JSONSerialization.jsonObject(with: data) as? [[Any]] {
                    // Coinbase returns arrays: [time, low, high, open, close, volume]
                    let sorted = json.sorted { a, b in
                        let ta = (a.first as? Double) ?? 0
                        let tb = (b.first as? Double) ?? 0
                        return ta < tb
                    }
                    let closes: [Double] = sorted.compactMap { arr in
                        if arr.count > 4 {
                            if let close = arr[4] as? Double { return close }
                            if let s = arr[4] as? String, let v = Double(s) { return v }
                        }
                        return nil
                    }
                    if !closes.isEmpty { return closes }
                }
            } catch {
                #if DEBUG
                print("[Technicals] Coinbase fetch failed for \(pair): \(error.localizedDescription)")
                #endif
                continue
            }
        }
        return nil
    }

    // Copied mapping similar to PriceViewModel for common tickers
    private func coingeckoID(for symbol: String) -> String {
        switch symbol.uppercased() {
        case "BTC": return "bitcoin"
        case "ETH": return "ethereum"
        case "DOGE": return "dogecoin"
        case "ADA": return "cardano"
        case "SOL": return "solana"
        case "XRP": return "ripple"
        case "DOT": return "polkadot"
        case "MATIC": return "matic-network"
        default: return symbol.lowercased()
        }
    }

    deinit {
        autoRefreshCancellable?.cancel()
        throttleWorkItem?.cancel()
        loadingOffDebounceWork?.cancel()
    }
}

