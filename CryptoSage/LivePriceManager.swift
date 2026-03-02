import Foundation
import Combine
import os
#if canImport(UIKit)
import UIKit
#endif

// =============================================================================
// LivePriceManager - SINGLE SOURCE OF TRUTH for market data across the app
// =============================================================================
//
// CRITICAL: To maintain price/percentage consistency across all views (Market,
// Watchlist, Home, Heat Map), ALL components MUST read data through this class.
//
// DATA FLOW ARCHITECTURE:
// =======================
// 1. Firestore real-time listener (PRIMARY - ensures cross-device consistency)
//    - Backend syncs Binance data to Firestore every 1 minute (marketData/heatmap)
//    - iOS uses addSnapshotListener for instant updates when data changes
//    - All devices see identical data simultaneously
//
// 2. HTTP polling (SECONDARY - supplements Firestore)
//    - Firebase proxy for Binance 24hr tickers (30s shared cache)
//    - Direct CoinGecko API for full market data with sparklines
//    - Provides redundancy if Firestore is slow or unavailable
//
// 3. Local cache (FALLBACK - used during startup only)
//    - Cached coins shown briefly while network connects
//    - Prevents blank UI during cold start
//
// PERCENTAGE CONSISTENCY:
// =======================
// All views MUST use these methods to get percentage changes:
//   - bestChange1hPercent(for: MarketCoin)  → returns value in ±100% (clamped)
//   - bestChange24hPercent(for: MarketCoin) → returns value in ±300% (clamped)
//   - bestChange7dPercent(for: MarketCoin)  → returns value in ±500% (clamped)
//
// These methods handle the full fallback chain:
//   1. Provider value (CoinGecko/Binance API)
//   2. Sidecar cache (persisted to disk, survives app restart)
//   3. Sparkline derivation (calculated from 7D price data)
//   4. Background Binance fetch (async, populates cache for next call)
//
// STANDARDIZED CLAMP LIMITS:
// ==========================
//   - 1h changes:  ±100% (crypto can move fast, but >100% in 1h is suspicious)
//   - 24h changes: ±300% (significant moves possible, but >300% is extreme)
//   - 7d changes:  ±500% (longer timeframe allows larger swings)
//
// These limits are enforced at:
//   - Cache write (safeSet*Change methods)
//   - Cache read/validation
//   - Display layer (as defensive clamp)
//
// DO NOT: Access coin.priceChangePercentage24hInCurrency directly in views
// DO NOT: Cache percentages locally without refreshing from LivePriceManager
// DO:     Use coin.best24hPercent (extension that calls LivePriceManager)

final class LivePriceManager {
    static let shared = LivePriceManager()

    private let logger = Logger(subsystem: "CryptoSage", category: "LivePriceManager")
    
    // MEMORY FIX v8: Store observer tokens for proper cleanup
    private var memoryWarningObserver: NSObjectProtocol?
    
    deinit {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // PERFORMANCE FIX: Rate-limit repetitive log messages to reduce console spam
    // when requests are blocked by the coordinator during startup or rate limiting
    //
    // THREAD-SAFETY FIX: _rateLimitedLogTimes is accessed from multiple threads
    // (pollMarketCoins, overlayLivePrices, ingestFirestoreMarketData, etc.).
    // Swift dictionaries are NOT thread-safe — concurrent read+write causes memory
    // corruption, manifesting as "NSIndexPath count: unrecognized selector" crashes.
    // Protected with NSLock for safe concurrent access.
    private var _rateLimitedLogTimes: [String: Date] = [:]
    private let _rateLimitedLogLock = NSLock()
    private func rateLimitedLog(_ key: String, _ message: String, minInterval: TimeInterval = 30.0) {
        let now = Date()
        _rateLimitedLogLock.lock()
        if let last = _rateLimitedLogTimes[key], now.timeIntervalSince(last) < minInterval {
            _rateLimitedLogLock.unlock()
            return // Skip - too soon since last log for this key
        }
        _rateLimitedLogTimes[key] = now
        _rateLimitedLogLock.unlock()
        logger.debug("\(message)")
    }

    // MARK: - Price Source Priority
    // PRICE CONSISTENCY FIX: Track which source provided each price and when
    // Priority: Binance (1) > Coinbase (2) > CoinGecko (3) > derived (4)
    // Only accept lower-priority source if higher-priority is stale (>5 seconds)
    enum PriceSource: Int, Comparable {
        case binance = 1    // Highest priority - real-time WebSocket/API
        case coinbase = 2   // Secondary - real-time WebSocket/API
        case coinGecko = 3  // Polling - aggregated prices
        case derived = 4    // Lowest - calculated from other data
        
        static func < (lhs: PriceSource, rhs: PriceSource) -> Bool {
            return lhs.rawValue < rhs.rawValue // Lower rawValue = higher priority
        }
    }
    
    // Track last price source and timestamp per symbol for priority enforcement
    @MainActor private var lastPriceSource: [String: PriceSource] = [:]
    @MainActor private var lastPriceSourceAt: [String: Date] = [:]
    private let priceSourceStalenessThreshold: TimeInterval = 5.0 // seconds
    
    // PRICE CONSISTENCY FIX: Price buffer for outlier detection using median
    // This prevents large price jumps when switching between sources
    @MainActor private var priceMedianBuffer: [String: [Double]] = [:]
    private let priceBufferSize = 5  // Keep last 5 prices for median calculation
    
    // PRICE CONSISTENCY: Public threshold for UI staleness indicators
    // Note: 90 seconds is more appropriate than 30s because:
    // - CoinGecko API updates every 1-2 minutes
    // - Not all coins have real-time WebSocket feeds
    // - 30s caused frequent gold/silver flickering on coin detail pages
    static let stalePriceThreshold: TimeInterval = 90.0 // Show stale indicator after 90 seconds
    
    /// Check if price data for a symbol is stale (older than 30 seconds)
    /// Returns false if we don't have tracking data yet (benefit of the doubt for new views)
    @MainActor
    func isPriceStale(for symbol: String) -> Bool {
        let symLower = symbol.lowercased()
        
        // Check if we have any timestamp data
        if let lastAt = lastPriceSourceAt[symLower] ?? lastDirectAt[symLower] {
            // We have tracking data - check if it's stale
            return Date().timeIntervalSince(lastAt) > Self.stalePriceThreshold
        }
        
        // No timestamp data - check if we have provider data that was recently fetched
        // This handles the case when a coin detail page is first opened
        // and we have price data from the provider but haven't started tracking it yet
        if let lastProviderAt = lastProviderApplyAt[symLower] {
            return Date().timeIntervalSince(lastProviderAt) > Self.stalePriceThreshold
        }
        
        // No tracking data at all - give benefit of the doubt (don't show stale indicator)
        // This provides better UX when first loading a coin detail page
        return false
    }
    
    /// Get the last update time for a symbol's price
    @MainActor
    func lastPriceUpdate(for symbol: String) -> Date? {
        let symLower = symbol.lowercased()
        return lastPriceSourceAt[symLower] ?? lastDirectAt[symLower]
    }
    
    /// Get the current price source for a symbol
    @MainActor
    func priceSource(for symbol: String) -> PriceSource? {
        return lastPriceSource[symbol.lowercased()]
    }
    
    // QA indicator: event for when we applied derived percent values in a pass
    struct DerivedUsagePulse {
        let timestamp: Date
        let symbols: [String] // lowercase symbols
        let kinds: Set<DerivedKind>
    }
    enum DerivedKind: String, Hashable {
        case h1, h24, d7, sanitized
    }
    // QA indicator: event for when we proactively prime 24h USD volumes
    struct VolumePrimePulse {
        let timestamp: Date
        let symbols: [String] // lowercase symbols
        let reason: VolumePrimeReason
    }
    
    struct SidecarFreshnessSnapshot {
        let percent1hAgeSec: Int?
        let percent24hAgeSec: Int?
        let percent7dAgeSec: Int?
        let volumeAgeSec: Int?
    }
    
    struct DataStalenessAlert {
        let timestamp: Date
        let reason: String
        let firestoreFresh: Bool
        let lastFirestoreSyncAgeSec: Int?
        let recentOverlayFallbackCount: Int
    }
    
    struct StaleSuppressionMetricsSnapshot {
        let timestamp: Date
        let windowSec: Int
        let total: Int
        let sidecar1h: Int
        let sidecar24h: Int
        let sidecar7d: Int
        let sidecarVolume: Int
        let provider24hBlocked: Int
        let providerVolumeBlocked: Int
    }
    
    private enum StaleSuppressionKind: String {
        case sidecar1h = "sidecar_1h"
        case sidecar24h = "sidecar_24h"
        case sidecar7d = "sidecar_7d"
        case sidecarVolume = "sidecar_volume"
        case provider24hBlocked = "provider_24h_blocked"
        case providerVolumeBlocked = "provider_volume_blocked"
    }
    enum VolumePrimeReason: String {
        case emission
        case viewport
    }

    // Map from ticker symbol to CoinGecko ID
    var geckoIDMap: [String: String] = [
        "btc": "bitcoin", "eth": "ethereum", "bnb": "binancecoin",
        "usdt": "tether",
        "busd": "binance-usd", "usdc": "usd-coin", "sol": "solana",
        "ada": "cardano", "xrp": "ripple", "doge": "dogecoin",
        "dot": "polkadot", "avax": "avalanche-2", "matic": "matic-network",
        "link": "chainlink", "xlm": "stellar", "bch": "bitcoin-cash",
        "trx": "tron", "uni": "uniswap", "etc": "ethereum-classic",
        "wbtc": "wrapped-bitcoin", "steth": "staked-ether",
        "wsteth": "wrapped-steth", "sui": "sui", "hype": "hyperliquid",
        "leo": "leo-token", "fil": "filecoin",
        "hbar": "hedera",
        "shib": "shiba-inu",
        "rlc": "iexec-rlc",
        "ltc": "litecoin",
        "atom": "cosmos",
        "icp": "internet-computer",
        "apt": "aptos",
        "arb": "arbitrum",
        "op": "optimism",
        "ton": "the-open-network",
        "near": "near",
        "ftm": "fantom",
        "rndr": "render-token",
        "algo": "algorand",
        "flow": "flow",
        "inj": "injective-protocol",
        "tia": "celestia",
        "sei": "sei-network",
        "grt": "the-graph",
        "egld": "elrond-erd-2",
        "kas": "kaspa",
        "neo": "neo",
        "qnt": "quant",
        "aave": "aave",
        "axs": "axie-infinity",
        "ape": "apecoin",
        "sushi": "sushi",
        "chz": "chiliz",
        "vet": "vechain",
        "eos": "eos",
        "xtz": "tezos",
        "theta": "theta-token",
        "hnt": "helium",
        "gala": "gala",
        "mina": "mina-protocol",
        "ldo": "lido-dao",
        "ens": "ethereum-name-service",
        "bsv": "bitcoin-sv",
        "pepe": "pepe"
    ]

    // Timer for polling
    private var timerCancellable: AnyCancellable?
    
    // Firestore sync cancellables
    var firestoreCancellables = Set<AnyCancellable>()
    
    // Guard against redundant startPolling calls
    private var isPollingActive: Bool = false
    private var currentPollingInterval: TimeInterval = 0

    // Subject to broadcast MarketCoin arrays
    private let coinSubject = PassthroughSubject<[MarketCoin], Never>()
    private let derivedUsageSubject = PassthroughSubject<DerivedUsagePulse, Never>()
    private let volumePrimeSubject = PassthroughSubject<VolumePrimePulse, Never>()
    private let dataStalenessAlertSubject = PassthroughSubject<DataStalenessAlert, Never>()
    private let staleSuppressionMetricsSubject = PassthroughSubject<StaleSuppressionMetricsSnapshot, Never>()
    
    // MARK: - Immediate Price Overlay Trigger
    // Data sources in priority order:
    // 1. Firestore real-time listener (marketData/heatmap) - cross-device sync
    // 2. HTTP overlay via Firebase proxy (getBinance24hrTickers) - 30s shared cache
    // 3. Direct API polling (Binance/CoinGecko) - fallback
    
    /// Trigger an immediate overlay of live prices (uses Firebase proxy with 30s shared cache)
    /// This supplements the Firestore real-time listener with HTTP polling for redundancy.
    @MainActor
    func triggerImmediateOverlay() {
        // HTTP overlay supplements Firestore real-time updates
        Task {
            await overlayLivePrices()
        }
    }
    
    // MARK: - Throttling Tiers (Consolidated)
    // ========================================
    // Tier 1 - Realtime (200ms): Coin detail views, order book integration
    // Tier 2 - Normal (500ms): Market lists, search results
    // Tier 3 - Background (2s): Portfolio, watchlist, heat maps
    // Scroll throttle: 6s during scroll to prevent UI churn during user interaction
    
    // PERFORMANCE FIX v2: Aggressive throttle during scroll to prevent jank
    // - Fast scroll: Skip emissions entirely (user is navigating, doesn't need updates)
    // - Normal scroll: 6s throttle (was 2s - increased to reduce jank)
    // - No scroll: Emit normally
    @MainActor private var lastEmissionDuringScroll: Date = .distantPast
    // PERFORMANCE FIX: Increased from 2.0s to 6.0s for smoother scrolling
    private let scrollEmissionThrottle: TimeInterval = 6.0
    // COLD START FIX: The very first emission must always go through, regardless of scroll state.
    // Without this, HeatMap, WatchlistSection, and other views stay empty if the user scrolls
    // during the first few seconds after launch.
    @MainActor private var hasCompletedFirstEmission: Bool = false
    
    // Startup emission freeze: after the first emission, block further emissions
    // briefly so MarketViewModel settles before receiving updates.
    // 5s is enough for the first emission to populate the UI. Cascade fixes
    // (max 2 concurrent metrics, tick batching) control downstream memory growth.
    @MainActor private var startupEmissionFreezeUntil: Date? = nil
    private var startupEmissionFreezeDuration: TimeInterval {
        AppSettings.isSimulatorLimitedDataMode ? 0.0 : 1.2
    }
    
    /// PERFORMANCE FIX v2: Enhanced scroll-aware emission
    /// - Completely skips during fast scroll or RunLoop tracking
    /// - Heavily throttles during normal scroll (6s)
    /// - No buffering to prevent "slingshot" effect
    @MainActor
    private func emitCoinsIfAppropriate(_ coins: [MarketCoin]) {
        // MEMORY FIX v13: Permanently block ALL emissions after emergency stop.
        // Once the watchdog triggers emergency stop, emitting data to MarketViewModel
        // triggers objectWillChange → SwiftUI re-renders → 38 MB/s memory growth.
        // The app is in survival mode; no new data should flow to views.
        if MarketViewModel.shared.isMemoryEmergency {
            return
        }
        
        let coins = capCoinsForProcessing(coins)
        // COLD START FIX: The first emission must always go through to populate
        // HeatMap, WatchlistSection, MarketViewModel, etc. Without this, these views
        // stay empty if the user scrolls during the first seconds after launch.
        if !hasCompletedFirstEmission && !coins.isEmpty {
            hasCompletedFirstEmission = true
            // MEMORY FIX v11: Start the emission freeze timer after first emission
            if startupEmissionFreezeDuration > 0 {
                startupEmissionFreezeUntil = Date().addingTimeInterval(startupEmissionFreezeDuration)
                logger.info("🧊 [LivePriceManager] First emission sent — freezing further emissions for \(String(format: "%.2f", self.startupEmissionFreezeDuration))s")
            } else {
                startupEmissionFreezeUntil = nil
            }
            coinSubject.send(coins)
            return
        }
        
        // MEMORY FIX v11: Block ALL emissions during the startup freeze window.
        // The first emission already provided cached data to populate the UI.
        // Further emissions during the critical startup window trigger cascading
        // @Published updates in MarketViewModel that cause 72 MB/s memory growth.
        if let freezeEnd = startupEmissionFreezeUntil, Date() < freezeEnd {
            return  // Silently drop — will resume after freeze expires
        }
        
        // Memory gate: only block when available memory is known AND critically low.
        // When os_proc_available_memory() returns 0 (simulator/unknown), always proceed.
        let availMB = Double(os_proc_available_memory()) / (1024 * 1024)
        if availMB > 0 && availMB < 200 {
            logger.warning("🚨 [LivePriceManager] EMISSION BLOCKED: only \(String(format: "%.0f", availMB)) MB available — triggering cleanup")
            handleMemoryWarning()
            return
        }
        
        let scrollManager = ScrollStateManager.shared
        
        // PERFORMANCE FIX: During fast scroll or RunLoop tracking, skip entirely
        // User is actively navigating - price updates would only cause jank
        if scrollManager.isFastScrolling || scrollManager.isTrackingRunLoop {
            return  // Skip completely - user is scrolling fast
        }
        
        // PERFORMANCE FIX: Also skip during any heavy scroll activity
        if scrollManager.shouldSkipExpensiveUpdate() {
            return  // ScrollStateManager says skip this update
        }
        
        // Check if any scrolling is happening
        let isScrolling = scrollManager.isScrolling || scrollManager.isDragging
        let now = Date()
        
        if isScrolling {
            // During scroll: heavy throttle to reduce main thread contention
            guard now.timeIntervalSince(lastEmissionDuringScroll) >= scrollEmissionThrottle else {
                return  // Throttle: too soon since last emission during scroll
            }
            lastEmissionDuringScroll = now
        }
        
        // Emit the update (no buffering - prevents scroll position jumps)
        coinSubject.send(coins)
    }

    // MARK: - Public Combine Publishers (Tiered Throttling)
    // =====================================================
    // Choose the appropriate tier based on your component's update needs:
    //
    // | Tier       | Throttle | Use Case                                    |
    // |------------|----------|---------------------------------------------|
    // | realtime   | 200ms    | Coin detail, order book, active trading     |
    // | normal     | 500ms    | Market lists, search results, navigation    |
    // | background | 2s       | Portfolio, watchlist, heat maps, charts     |
    // | raw        | none     | Internal use only, debugging                |
    //
    // During scroll: emissions throttled to 2s (Tier 3) regardless of subscriber
    
    /// Raw publisher - delivers all emissions. Internal use only - prefer tiered publishers.
    var publisher: AnyPublisher<[MarketCoin], Never> {
        coinSubject.eraseToAnyPublisher()
    }
    
    /// TIER 1 - Realtime publisher (~5Hz) for views requiring fast updates
    /// Use for: CoinDetailView, OrderBookView, active trading screens
    var realtimePublisher: AnyPublisher<[MarketCoin], Never> {
        coinSubject
            .throttle(for: .milliseconds(200), scheduler: DispatchQueue.main, latest: true)
            .eraseToAnyPublisher()
    }
    
    /// TIER 2 - Normal publisher for standard UI components
    /// MEMORY FIX: Increased from 500ms to 3s. Each publish triggers MarketViewModel to
    /// process all coins and update @Published properties, which triggers SwiftUI to
    /// re-evaluate the entire view tree. At 2Hz this created constant memory churn.
    /// 3s interval gives the system time to deallocate old view instances between updates.
    var throttledPublisher: AnyPublisher<[MarketCoin], Never> {
        let throttleMs = AppSettings.isSimulatorLimitedDataMode ? 600 : 3_000
        return coinSubject
            .throttle(for: .milliseconds(throttleMs), scheduler: DispatchQueue.main, latest: true)
            .eraseToAnyPublisher()
    }
    
    /// TIER 3 - Background publisher for expensive UI components
    /// Use for: PortfolioView, WatchlistSection, HeatMap, complex charts
    /// MEMORY FIX: Increased from 2s to 5s to reduce re-render frequency
    var slowPublisher: AnyPublisher<[MarketCoin], Never> {
        let throttleMs = AppSettings.isSimulatorLimitedDataMode ? 1_500 : 5_000
        return coinSubject
            .throttle(for: .milliseconds(throttleMs), scheduler: DispatchQueue.main, latest: true)
            .eraseToAnyPublisher()
    }

    var derivedUsagePublisher: AnyPublisher<DerivedUsagePulse, Never> {
        derivedUsageSubject.eraseToAnyPublisher()
    }

    var volumePrimePublisher: AnyPublisher<VolumePrimePulse, Never> {
        volumePrimeSubject.eraseToAnyPublisher()
    }
    
    var dataStalenessAlertPublisher: AnyPublisher<DataStalenessAlert, Never> {
        dataStalenessAlertSubject.eraseToAnyPublisher()
    }
    
    var staleSuppressionMetricsPublisher: AnyPublisher<StaleSuppressionMetricsSnapshot, Never> {
        staleSuppressionMetricsSubject.eraseToAnyPublisher()
    }

    // Keep a local copy of the latest coins to overlay live prices onto
    // CRASH FIX: Must be @MainActor to prevent concurrent access crashes
    // Keep in sync with MarketViewModel normal runtime cap.
    private static let maxCurrentCoinsCount = 250
    
    /// MEMORY FIX v5: Always cap coins before saving to disk.
    /// Previous builds saved 250+ coins (1.7 MB JSON) which caused a memory spike
    /// when decoded at startup on the NEXT launch, pushing past the jetsam limit.
    /// This is WHY the app worked after delete+reinstall but crashed after rebuild.
    private func saveCoinsCacheCapped(_ coins: [MarketCoin]) {
        let capped = coins.count > Self.maxCurrentCoinsCount ? Array(coins.prefix(Self.maxCurrentCoinsCount)) : coins
        CacheManager.shared.save(capped, to: "coins_cache.json")
    }
    
    /// Async version of saveCoinsCacheCapped for background saving
    private func saveCoinsCacheCappedAsync(_ coins: [MarketCoin]) async {
        let capped = coins.count > Self.maxCurrentCoinsCount ? Array(coins.prefix(Self.maxCurrentCoinsCount)) : coins
        await CacheManager.shared.saveAsync(capped, to: "coins_cache.json")
    }
    
    private func capCoinsForProcessing(_ coins: [MarketCoin]) -> [MarketCoin] {
        coins.count > Self.maxCurrentCoinsCount ? Array(coins.prefix(Self.maxCurrentCoinsCount)) : coins
    }
    
    @MainActor private var currentCoins: [MarketCoin] = [] {
        didSet {
            if currentCoins.count > Self.maxCurrentCoinsCount {
                currentCoins = Array(currentCoins.prefix(Self.maxCurrentCoinsCount))
            }
        }
    }
    
    /// Public read-only access to the current coins list for external consumers (e.g., WatchlistSection).
    @MainActor
    var currentCoinsList: [MarketCoin] {
        currentCoins
    }
    @MainActor private var overlayOffset: Int = 0
    // Secondary timer for frequent price overlays (e.g., Binance 24h ticker)
    private var priceTimerCancellable: AnyCancellable?

    // Backoff control for overlay timer
    // CRASH FIX: All mutable state must be @MainActor to prevent concurrent access
    @MainActor private var overlayFailureCount: Int = 0
    @MainActor private var overlaySuspendUntil: Date? = nil
    private let overlaySuspendCooldown: TimeInterval = 15 * 60 // 15 minutes
    private let overlayMaxConsecutiveFailuresBeforeSuspend = 8
    // PRICE ACCURACY FIX: Reduced overlay interval from 45s to 30s.
    // 45s was too slow — when Firestore data expired at 60s, the next overlay wouldn't fire
    // for up to 45s more, causing up to 105s of staleness. At 30s the max staleness drops
    // to ~90s, and during warm-up it's even faster. This keeps portfolio prices within ~1%
    // of actual market prices. Still respects scroll blocking to avoid jank.
    @MainActor private var overlayBaseIntervalSeconds: TimeInterval = 30
    @MainActor private var overlayMaxIntervalSeconds: TimeInterval = 90   // Reduced from 120s for fresher prices
    @MainActor private var overlayIntervalSeconds: TimeInterval = 30      // PRICE ACCURACY FIX: Reduced from 45s

    // Warm-up mode: for the first few overlay passes, run faster & larger batches
    @MainActor private var overlayWarmupPassesRemaining: Int = 3

    // Prevent overlapping overlay fetches
    // CRASH FIX: Must be @MainActor to prevent concurrent modification
    @MainActor private var overlayInFlight = false
    @MainActor private var latestVolumeUSDBySymbol: [String: Double] = [:]
    @MainActor private var lastVolumeUpdatedAt: [String: Date] = [:]
    @MainActor private var volumeCacheIsDirty: Bool = false
    @MainActor private var volumeCacheLastSaveAt: Date = .distantPast
    private let volumeCacheSaveDebounce: TimeInterval = 5.0 // Save every 5 seconds when dirty
    @MainActor private var staleOverlayFallbackTimestamps: [Date] = []
    @MainActor private var lastDataStalenessAlertAt: Date = .distantPast
    @MainActor private(set) var lastDataStalenessAlert: DataStalenessAlert?
    private let staleOverlayFallbackWindow: TimeInterval = 5 * 60
    private let staleOverlayFallbackAlertThreshold: Int = 3
    private let staleOverlayAlertCooldown: TimeInterval = 2 * 60
    @MainActor private var staleSuppressionEvents: [(kind: StaleSuppressionKind, at: Date)] = []
    @MainActor private var lastSuppressionRecordAtBySymbolKind: [String: Date] = [:]
    private let staleSuppressionWindow: TimeInterval = 60
    private let staleSuppressionPerSymbolCooldown: TimeInterval = 15

    // Direct stream recency & last price per symbol to arbitrate against provider overlays
    // MUST be @MainActor to prevent race conditions/crashes when accessed from multiple contexts
    @MainActor private var lastDirectAt: [String: Date] = [:]
    @MainActor private var lastDirectPriceBySymbol: [String: Double] = [:]

    // Track provider-applied overlay updates to avoid rapid re-applications with tiny deltas
    // MUST be @MainActor to prevent race conditions/crashes
    @MainActor private var lastProviderApplyAt: [String: Date] = [:]
    private let providerApplyCooldownSeconds: TimeInterval = 3.0

    @MainActor private var didRunColdStartHistoryDerivation: Bool = false
    @MainActor private var lastSanitizedSymbols: Set<String> = []
    
    // LOG SPAM FIX: Track if we've already logged about degraded mode to prevent repeated logging
    @MainActor private var didLogDegradedMode: Bool = false
    @MainActor private var didLogBinanceBlocked: Bool = false

    @MainActor private var derivedRankByID: [String: Int] = [:]
    @MainActor private var derivedMaxSupplyByID: [String: Double] = [:]
    @MainActor private var last1hChangeBySymbol: [String: Double] = [:]
    @MainActor private var last24hChangeBySymbol: [String: Double] = [:]
    @MainActor private var last7dChangeBySymbol: [String: Double] = [:]
    
    // DATA CONSISTENCY: Track when 24h values come from Firestore (single source of truth)
    // Values from Firestore should NOT be overwritten by HTTP polling for a grace period
    // This ensures all devices show identical data from the shared Firestore document
    @MainActor private var firestoreValueTimestamps: [String: Date] = [:]
    @MainActor private let firestoreGracePeriod: TimeInterval = 360 // Don't overwrite Firestore values for 6 minutes (matches 5-min CoinGecko sync)
    
    // MEMORY FIX v12: Prevent stale-bypass direct CoinGecko API poll during startup.
    // When Firestore CoinGecko data is stale on first read, the bypass path triggers a
    // heavy multi-page fetch (up to 2500 coins) that runs concurrently with Firestore
    // data ingestion, causing 200MB→2GB memory explosion in 60 seconds.
    // During the first 30 seconds, rely on Firestore + cached data instead.
    @MainActor private let startupStaleBypassGracePeriod: TimeInterval = 30
    
    // STALE DATA FIX: Track startup time to avoid trusting embedded coin percentages
    // Coins may come from MarketViewModel's cached data with hours-old percentages
    // During the grace period, we only trust:
    // 1. Sidecar cache values (which are cleared on startup)
    // 2. Sparkline-derived values
    // 3. Fresh Binance API values
    @MainActor private var startupTime: Date = Date()
    @MainActor private let startupGracePeriod: TimeInterval = 3  // Don't trust embedded percentages for 3s (Firestore delivers in ~1-2s)
    
    @MainActor private var isInStartupGracePeriod: Bool {
        Date().timeIntervalSince(startupTime) < startupGracePeriod
    }
    
    /// Public indicator for whether we've received at least one batch of fresh data
    /// (from Firestore, API poll, or overlay). Used by MarketViewModel to decide
    /// whether primeLivePercents() would produce useful (non-stale) results.
    @MainActor var hasReceivedFreshData: Bool {
        !isInStartupGracePeriod && (hasRunFirstOverlay || !last24hChangeBySymbol.isEmpty)
    }
    
    // PERFORMANCE FIX: Cache sparkline data to avoid calling loadCachedSparklinesSync() on every
    // canonicalSeries() call within augmentedCoinsWithDerivedPercents(). This was causing
    // synchronous disk I/O on MainActor for every coin in the list, blocking the UI.
    @MainActor private var cachedSparklines: [String: [Double]] = [:]
    @MainActor private var sparklineCacheLastLoadedAt: Date = .distantPast
    private let sparklineCacheRefreshInterval: TimeInterval = 60  // Reload from disk every 60s
    
    // MARK: - Safe Dictionary Accessors (SIMPLIFIED - No fire-and-forget Tasks)
    // ARCHITECTURE FIX: Removed all fire-and-forget Tasks that caused race conditions and crashes.
    // Now uses MainActor dictionaries as single source of truth with periodic batch persistence.
    // Persistence happens only on explicit save calls (app background, etc.) - NOT on every update.
    
    @MainActor
    private func isFreshSidecarValue(updatedAt: Date?, maxAge: TimeInterval) -> Bool {
        guard let updatedAt else { return false }
        return Date().timeIntervalSince(updatedAt) <= maxAge
    }
    
    @MainActor private func safeGet1hChange(_ key: String) -> Double? {
        guard !key.isEmpty else { return nil }
        let normalizedKey = normalizeCacheKey(key)
        guard !normalizedKey.isEmpty else { return nil }
        guard let v = last1hChangeBySymbol[normalizedKey] else { return nil }
        guard isFreshSidecarValue(updatedAt: last1hChangeUpdatedAt[normalizedKey], maxAge: maxShortSidecarReadAge) else {
            // Expire stale value immediately so it never leaks into UI.
            recordStaleSuppression(.sidecar1h, symbol: normalizedKey)
            last1hChangeBySymbol.removeValue(forKey: normalizedKey)
            last1hChangeUpdatedAt.removeValue(forKey: normalizedKey)
            return nil
        }
        guard v.isFinite, !v.isNaN, abs(v) <= 100 else {
            // Remove invalid cached value
            last1hChangeBySymbol.removeValue(forKey: normalizedKey)
            return nil
        }
        return v
    }
    
    @MainActor private func safeGet24hChange(_ key: String) -> Double? {
        guard !key.isEmpty else { return nil }
        let normalizedKey = normalizeCacheKey(key)
        guard !normalizedKey.isEmpty else { return nil }
        guard let v = last24hChangeBySymbol[normalizedKey] else { return nil }
        guard isFreshSidecarValue(updatedAt: last24hChangeUpdatedAt[normalizedKey], maxAge: maxShortSidecarReadAge) else {
            // Expire stale value immediately so it never leaks into UI.
            recordStaleSuppression(.sidecar24h, symbol: normalizedKey)
            last24hChangeBySymbol.removeValue(forKey: normalizedKey)
            last24hChangeUpdatedAt.removeValue(forKey: normalizedKey)
            return nil
        }
        // CONSISTENCY FIX: Use ±300% limit to match display layer clamp
        guard v.isFinite, !v.isNaN, abs(v) <= 300 else {
            // Remove invalid cached value
            last24hChangeBySymbol.removeValue(forKey: normalizedKey)
            return nil
        }
        return v
    }
    
    @MainActor private func safeGet7dChange(_ key: String) -> Double? {
        guard !key.isEmpty else { return nil }
        let normalizedKey = normalizeCacheKey(key)
        guard !normalizedKey.isEmpty else { return nil }
        guard let v = last7dChangeBySymbol[normalizedKey] else { return nil }
        guard isFreshSidecarValue(updatedAt: last7dChangeUpdatedAt[normalizedKey], maxAge: maxLongSidecarReadAge) else {
            // Expire stale value immediately so it never leaks into UI.
            recordStaleSuppression(.sidecar7d, symbol: normalizedKey)
            last7dChangeBySymbol.removeValue(forKey: normalizedKey)
            last7dChangeUpdatedAt.removeValue(forKey: normalizedKey)
            return nil
        }
        guard v.isFinite, !v.isNaN, abs(v) <= 500 else {
            // Remove invalid cached value
            last7dChangeBySymbol.removeValue(forKey: normalizedKey)
            return nil
        }
        return v
    }
    
    /// Normalize cache key by removing invalid characters (like $) that would fail validation on load
    /// This prevents "Skipping invalid key" warnings when loading cached data
    private func normalizeCacheKey(_ key: String) -> String {
        // Lowercase, remove $ and other invalid characters, keep only valid ones
        // Valid: letters, numbers, dash, underscore, dot (for bridged tokens like btc.b)
        String(key.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }.prefix(50))
    }
    
    /// CRASH FIX: Added objc_sync_enter for atomic dictionary operations
    /// The NSIndirectTaggedPointerString crash was caused by concurrent dictionary mutation
    @MainActor private func safeSet1hChange(_ key: String, _ value: Double) {
        guard !key.isEmpty else { return }
        guard key.count <= 50 else { return } // Additional safety: reject absurdly long keys
        guard value.isFinite, !value.isNaN, abs(value) <= 100 else { return }
        // Normalize key to prevent invalid characters (like $) from being cached
        let sanitizedKey = normalizeCacheKey(key)
        guard !sanitizedKey.isEmpty else { return }
        last1hChangeBySymbol[sanitizedKey] = value
        last1hChangeUpdatedAt[sanitizedKey] = Date()
        // NO fire-and-forget Task - persistence is handled by batch save
        markPercentCacheDirty()
    }
    
    /// CRASH FIX: Added defensive key sanitization and bounds checking
    /// DATA CONSISTENCY: Respects Firestore grace period - won't overwrite Firestore values with HTTP data
    /// CONSISTENCY FIX: Clamping limit increased to ±300% to match display layer
    /// This ensures cached values won't be rejected when UI displays them at ±300% clamp
    @MainActor private func safeSet24hChange(_ key: String, _ value: Double, fromFirestore: Bool = false) {
        guard !key.isEmpty else { return }
        guard key.count <= 50 else { return } // Additional safety: reject absurdly long keys
        // CONSISTENCY FIX: Use ±300% limit to match display layer clamp (CoinRowView, WatchlistSection, etc.)
        // Previous ±200% limit caused values between 200-300% to be rejected from cache
        // but then shown as clamped values in UI, causing inconsistency
        guard value.isFinite, !value.isNaN, abs(value) <= 300 else { return }
        // Normalize key to prevent invalid characters (like $) from being cached
        let sanitizedKey = normalizeCacheKey(key)
        guard !sanitizedKey.isEmpty else { return }
        
        // DATA CONSISTENCY: Protect Firestore values from being overwritten by HTTP polling
        // Firestore is the single source of truth for cross-device consistency
        if !fromFirestore {
            if let firestoreTime = firestoreValueTimestamps[sanitizedKey] {
                let elapsed = Date().timeIntervalSince(firestoreTime)
                if elapsed < firestoreGracePeriod {
                    // Skip - Firestore value is still fresh, don't overwrite with HTTP data
                    return
                }
            }
        }
        
        last24hChangeBySymbol[sanitizedKey] = value
        last24hChangeUpdatedAt[sanitizedKey] = Date()
        // NO fire-and-forget Task - persistence is handled by batch save
        markPercentCacheDirty()
    }
    
    /// CRASH FIX: Added defensive key sanitization and bounds checking
    @MainActor private func safeSet7dChange(_ key: String, _ value: Double) {
        guard !key.isEmpty else { return }
        guard key.count <= 50 else { return } // Additional safety: reject absurdly long keys
        guard value.isFinite, !value.isNaN, abs(value) <= 500 else { return }
        // Normalize key to prevent invalid characters (like $) from being cached
        let sanitizedKey = normalizeCacheKey(key)
        guard !sanitizedKey.isEmpty else { return }
        last7dChangeBySymbol[sanitizedKey] = value
        last7dChangeUpdatedAt[sanitizedKey] = Date()
        // NO fire-and-forget Task - persistence is handled by batch save
        markPercentCacheDirty()
    }
    
    @MainActor
    private func safeSetVolumeUSD(_ key: String, _ value: Double, markDirty: Bool = false) {
        guard !key.isEmpty, value.isFinite, value > 0 else { return }
        let sanitizedKey = normalizeCacheKey(key)
        guard !sanitizedKey.isEmpty else { return }
        latestVolumeUSDBySymbol[sanitizedKey] = value
        lastVolumeUpdatedAt[sanitizedKey] = Date()
        if markDirty { volumeCacheIsDirty = true }
    }
    
    @MainActor
    private func sidecarAgeSeconds(_ updatedAt: Date?) -> Int? {
        guard let updatedAt else { return nil }
        return max(0, Int(Date().timeIntervalSince(updatedAt)))
    }
    
    @MainActor
    func sidecarFreshness(for symbol: String) -> SidecarFreshnessSnapshot {
        let key = normalizeCacheKey(symbol)
        return SidecarFreshnessSnapshot(
            percent1hAgeSec: sidecarAgeSeconds(last1hChangeUpdatedAt[key]),
            percent24hAgeSec: sidecarAgeSeconds(last24hChangeUpdatedAt[key]),
            percent7dAgeSec: sidecarAgeSeconds(last7dChangeUpdatedAt[key]),
            volumeAgeSec: sidecarAgeSeconds(lastVolumeUpdatedAt[key])
        )
    }
    
    @MainActor
    private func recordStaleOverlayFallback(reason: String, firestoreFresh: Bool) {
        guard !firestoreFresh else { return }
        let now = Date()
        staleOverlayFallbackTimestamps.append(now)
        staleOverlayFallbackTimestamps.removeAll { now.timeIntervalSince($0) > staleOverlayFallbackWindow }
        
        let recentCount = staleOverlayFallbackTimestamps.count
        guard recentCount >= staleOverlayFallbackAlertThreshold else { return }
        guard now.timeIntervalSince(lastDataStalenessAlertAt) >= staleOverlayAlertCooldown else { return }
        
        let syncAge = FirestoreMarketSync.shared.lastSyncAt.map { max(0, Int(now.timeIntervalSince($0))) }
        let alert = DataStalenessAlert(
            timestamp: now,
            reason: reason,
            firestoreFresh: firestoreFresh,
            lastFirestoreSyncAgeSec: syncAge,
            recentOverlayFallbackCount: recentCount
        )
        lastDataStalenessAlertAt = now
        lastDataStalenessAlert = alert
        dataStalenessAlertSubject.send(alert)
        logger.warning("⚠️ [LivePriceManager] Stale-data alert: reason=\(reason, privacy: .public), fallbackCount=\(recentCount), firestoreSyncAge=\(syncAge ?? -1)s")
    }
    
    @MainActor
    private func staleSuppressionSnapshot(now: Date = Date()) -> StaleSuppressionMetricsSnapshot {
        staleSuppressionEvents.removeAll { now.timeIntervalSince($0.at) > staleSuppressionWindow }
        let sidecar1h = staleSuppressionEvents.filter { $0.kind == .sidecar1h }.count
        let sidecar24h = staleSuppressionEvents.filter { $0.kind == .sidecar24h }.count
        let sidecar7d = staleSuppressionEvents.filter { $0.kind == .sidecar7d }.count
        let sidecarVolume = staleSuppressionEvents.filter { $0.kind == .sidecarVolume }.count
        let provider24hBlocked = staleSuppressionEvents.filter { $0.kind == .provider24hBlocked }.count
        let providerVolumeBlocked = staleSuppressionEvents.filter { $0.kind == .providerVolumeBlocked }.count
        let total = sidecar1h + sidecar24h + sidecar7d + sidecarVolume + provider24hBlocked + providerVolumeBlocked
        return StaleSuppressionMetricsSnapshot(
            timestamp: now,
            windowSec: Int(staleSuppressionWindow),
            total: total,
            sidecar1h: sidecar1h,
            sidecar24h: sidecar24h,
            sidecar7d: sidecar7d,
            sidecarVolume: sidecarVolume,
            provider24hBlocked: provider24hBlocked,
            providerVolumeBlocked: providerVolumeBlocked
        )
    }
    
    /// Debug-only telemetry: counts how often stale values are intentionally suppressed.
    @MainActor
    private func recordStaleSuppression(_ kind: StaleSuppressionKind, symbol: String?) {
        guard debugPercentSourcing else { return }
        let now = Date()
        if let symbol {
            let key = "\(kind.rawValue):\(normalizeCacheKey(symbol))"
            if let lastAt = lastSuppressionRecordAtBySymbolKind[key],
               now.timeIntervalSince(lastAt) < staleSuppressionPerSymbolCooldown {
                return
            }
            lastSuppressionRecordAtBySymbolKind[key] = now
            lastSuppressionRecordAtBySymbolKind = lastSuppressionRecordAtBySymbolKind.filter {
                now.timeIntervalSince($0.value) <= staleSuppressionWindow
            }
        }
        staleSuppressionEvents.append((kind: kind, at: now))
        let snapshot = staleSuppressionSnapshot(now: now)
        staleSuppressionMetricsSubject.send(snapshot)
    }
    
    @MainActor
    func staleSuppressionMetricsSnapshot() -> StaleSuppressionMetricsSnapshot? {
        guard debugPercentSourcing else { return nil }
        return staleSuppressionSnapshot()
    }
    
    // MARK: - Batch Persistence (Safe, No Race Conditions)
    
    @MainActor private var percentCacheIsDirty = false
    @MainActor private var percentCacheLastSaveAt: Date = .distantPast
    private let percentCacheSaveDebounce: TimeInterval = 10.0 // Save at most every 10 seconds
    
    @MainActor private func markPercentCacheDirty() {
        percentCacheIsDirty = true
    }
    
    /// Loads persisted percent cache from disk into MainActor dictionaries on startup
    /// Uses safe loading with extra validation to prevent crashes from corrupted cache files
    /// CRASH FIX: Added comprehensive validation and corruption recovery
    @MainActor
    func loadPersistedPercentCache() async {
        // STALE DATA FIX: Skip loading if polling has already started
        // When startPolling() runs, it clears all percent caches to avoid showing stale values.
        // If this async Task completes AFTER startPolling(), we would reload stale data.
        guard !isPollingActive else {
            logger.info("⏭️ [LivePriceManager] Skipping percent cache load - polling already active")
            return
        }
        
        // CRASH RECOVERY: Clear caches if they've been marked as corrupted
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "percent_cache_corrupted") {
            logger.warning("⚠️ [LivePriceManager] Cache was marked corrupted - clearing and resetting")
            CacheManager.shared.clearPercentCaches()
            defaults.set(false, forKey: "percent_cache_corrupted")
            return
        }
        
        // MEMORY FIX: Cap each percent cache to 100 entries during loading.
        // 100 covers the top coins by market cap; rest populated from live data.
        let maxPercentCacheEntries = 100
        
        // Use safe loading method that returns empty dict on corruption
        let loaded1h = CacheManager.shared.loadStringDoubleDict(from: "percent_cache_1h.json")
        var loadCount = 0
        for (key, value) in loaded1h {
            guard last1hChangeBySymbol.count < maxPercentCacheEntries else { break }
            guard !key.isEmpty, key.count <= 50, key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }) else {
                continue
            }
            guard abs(value) <= 100 else { continue }
            if last1hChangeBySymbol[key] == nil {
                last1hChangeBySymbol[key] = value
                loadCount += 1
            }
        }
        
        let loaded24h = CacheManager.shared.loadStringDoubleDict(from: "percent_cache_24h.json")
        for (key, value) in loaded24h {
            guard last24hChangeBySymbol.count < maxPercentCacheEntries else { break }
            guard !key.isEmpty, key.count <= 50, key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }) else {
                continue
            }
            guard abs(value) <= 300 else { continue }
            if last24hChangeBySymbol[key] == nil {
                last24hChangeBySymbol[key] = value
                loadCount += 1
            }
        }
        
        let loaded7d = CacheManager.shared.loadStringDoubleDict(from: "percent_cache_7d.json")
        for (key, value) in loaded7d {
            guard last7dChangeBySymbol.count < maxPercentCacheEntries else { break }
            guard !key.isEmpty, key.count <= 50, key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }) else {
                continue
            }
            guard abs(value) <= 500 else { continue }
            if last7dChangeBySymbol[key] == nil {
                last7dChangeBySymbol[key] = value
                loadCount += 1
            }
        }
        
        let count = last1hChangeBySymbol.count + last24hChangeBySymbol.count + last7dChangeBySymbol.count
        if count > 0 {
            logger.info("📦 [LivePriceManager] Loaded percent cache: \(count) values")
        }
        
        // VOLUME FIX: Also load persisted volume cache to show last known volumes on startup
        let loadedVolumes = CacheManager.shared.loadStringDoubleDict(from: "volume_cache.json")
        var volumeLoadCount = 0
        for (key, value) in loadedVolumes {
            guard !key.isEmpty, key.count <= 50, key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }) else {
                continue
            }
            // Volume should be positive and finite
            guard value.isFinite, value > 0 else { continue }
            if latestVolumeUSDBySymbol[key] == nil {
                safeSetVolumeUSD(key, value)
                volumeLoadCount += 1
            }
        }
        if volumeLoadCount > 0 {
            logger.info("📦 [LivePriceManager] Loaded volume cache: \(volumeLoadCount) values")
        }
        
        // VOLUME FIX: Also seed volume cache from coins_cache.json if volume cache was empty/small
        // This ensures we have volume data from the last good market data fetch
        if latestVolumeUSDBySymbol.count < 50 {
            if let cachedCoins: [MarketCoin] = CacheManager.shared.load([MarketCoin].self, from: "coins_cache.json") {
                var seedCount = 0
                for coin in cachedCoins {
                    let key = coin.symbol.lowercased()
                    guard !key.isEmpty else { continue }
                    // Only seed if we don't already have a value
                    if latestVolumeUSDBySymbol[key] == nil {
                        if let vol = coin.totalVolume, vol.isFinite, vol > 0 {
                            safeSetVolumeUSD(key, vol)
                            seedCount += 1
                        }
                    }
                }
                if seedCount > 0 {
                    logger.info("📦 [LivePriceManager] Seeded volume cache from coins_cache: \(seedCount) values")
                    volumeCacheIsDirty = true  // Save the seeded values
                }
            }
        }
    }
    
    /// CRASH RECOVERY: Call this on crash detection to prevent corrupt cache from crashing again
    @MainActor
    func markCacheAsCorrupted() {
        UserDefaults.standard.set(true, forKey: "percent_cache_corrupted")
        logger.error("🚨 [LivePriceManager] Cache marked as corrupted for cleanup on next launch")
    }
    
    /// Saves percent cache to disk if dirty and debounce period has passed
    /// Call this on app background or periodically - NOT on every value update
    @MainActor
    func savePercentCacheIfNeeded() {
        let now = Date()
        
        // Save percent cache if dirty
        if percentCacheIsDirty && now.timeIntervalSince(percentCacheLastSaveAt) >= percentCacheSaveDebounce {
            // Filter and save - all on MainActor, no Tasks needed
            let filtered1h = last1hChangeBySymbol.filter { !$0.key.isEmpty && $0.value.isFinite && !$0.value.isNaN && abs($0.value) <= 100 }
            // CONSISTENCY FIX: Use ±300% limit to match display layer clamp
            let filtered24h = last24hChangeBySymbol.filter { !$0.key.isEmpty && $0.value.isFinite && !$0.value.isNaN && abs($0.value) <= 300 }
            let filtered7d = last7dChangeBySymbol.filter { !$0.key.isEmpty && $0.value.isFinite && !$0.value.isNaN && abs($0.value) <= 500 }
            
            CacheManager.shared.save(filtered1h, to: "percent_cache_1h.json")
            CacheManager.shared.save(filtered24h, to: "percent_cache_24h.json")
            CacheManager.shared.save(filtered7d, to: "percent_cache_7d.json")
            
            percentCacheIsDirty = false
            percentCacheLastSaveAt = now
        }
        
        // VOLUME FIX: Also save volume cache if dirty
        if volumeCacheIsDirty && now.timeIntervalSince(volumeCacheLastSaveAt) >= volumeCacheSaveDebounce {
            let filteredVolumes = latestVolumeUSDBySymbol.filter { !$0.key.isEmpty && $0.value.isFinite && $0.value > 0 }
            CacheManager.shared.save(filteredVolumes, to: "volume_cache.json")
            volumeCacheIsDirty = false
            volumeCacheLastSaveAt = now
        }
    }
    
    /// Force save percent cache immediately (call on app termination)
    @MainActor
    func forcePercentCacheSave() {
        let filtered1h = last1hChangeBySymbol.filter { !$0.key.isEmpty && $0.value.isFinite && !$0.value.isNaN && abs($0.value) <= 100 }
        // CONSISTENCY FIX: Use ±300% limit to match display layer clamp
        let filtered24h = last24hChangeBySymbol.filter { !$0.key.isEmpty && $0.value.isFinite && !$0.value.isNaN && abs($0.value) <= 300 }
        let filtered7d = last7dChangeBySymbol.filter { !$0.key.isEmpty && $0.value.isFinite && !$0.value.isNaN && abs($0.value) <= 500 }
        
        CacheManager.shared.save(filtered1h, to: "percent_cache_1h.json")
        CacheManager.shared.save(filtered24h, to: "percent_cache_24h.json")
        CacheManager.shared.save(filtered7d, to: "percent_cache_7d.json")
        
        percentCacheIsDirty = false
        percentCacheLastSaveAt = Date()
        
        // VOLUME FIX: Also force save volume cache
        let filteredVolumes = latestVolumeUSDBySymbol.filter { !$0.key.isEmpty && $0.value.isFinite && $0.value > 0 }
        CacheManager.shared.save(filteredVolumes, to: "volume_cache.json")
        volumeCacheIsDirty = false
        volumeCacheLastSaveAt = Date()
    }
    
    // Staleness tracking: when percent values were last updated from the API
    @MainActor private var last1hChangeUpdatedAt: [String: Date] = [:]
    @MainActor private var last24hChangeUpdatedAt: [String: Date] = [:]
    @MainActor private var last7dChangeUpdatedAt: [String: Date] = [:]
    @MainActor private var previousProviderValue24h: [String: Double] = [:]
    // Staleness threshold: if value hasn't changed in this many poll cycles, consider stale
    private let stalenessThresholdSeconds: TimeInterval = 600 // 10 minutes

    @MainActor private var historyInFlight: Set<String> = []
    @MainActor private var historyLastAttemptAt: [String: Date] = [:]
    private let historyAttemptCooldown: TimeInterval = 10 * 60

    // Toggle detailed arbitration logging
    private let debugArbitration: Bool = false
    private var debugPercentSourcing: Bool = false
    
    /// Enables or disables detailed percent sourcing debug logs.
    /// Call `LivePriceManager.shared.setPercentDebugLogging(true)` to enable.
    func setPercentDebugLogging(_ enabled: Bool) {
        debugPercentSourcing = enabled
        if enabled {
            Task { @MainActor [weak self] in
                self?.staleSuppressionEvents.removeAll()
                self?.lastSuppressionRecordAtBySymbolKind.removeAll()
            }
            logger.info("🔍 [LivePriceManager] Percent sourcing debug logging ENABLED")
        }
    }

    // Coalesced emitter state
    // PERFORMANCE FIX: Increased from 1.0s to 1.5s to reduce UI update frequency and improve scrolling
    private let minEmitSpacing: TimeInterval = 1.5
    @MainActor private var lastEmitAt: Date?
    @MainActor private var scheduledEmitWorkItem: DispatchWorkItem?
    @MainActor private var pendingCoins: [MarketCoin]?
    @MainActor private var lastEmittedBySymbol: [String: Double] = [:]

    // Sidecar persistence (debounced)
    private let percentSidecarSaveDebounce: TimeInterval = 1.0
    @MainActor private var percentSidecarSaveWorkItem: DispatchWorkItem?

    // Debounce between poll and overlay emissions
    // THREAD-SAFETY FIX: Marked @MainActor — these are written inside MainActor.run
    // blocks but were read from background threads, creating data races.
    @MainActor private var lastOverlayEmitAt: Date?
    @MainActor private var lastPollEmitAt: Date?
    private let pollVsOverlayDebounceSeconds: TimeInterval = 1.5

    // Prefer recent direct prices over provider overlays for a short window
    private let directHoldoffSeconds: TimeInterval = 30

    // Gate and throttle on-demand volume fetches per symbol to avoid bursts
    private actor _VolumeFetchGate {
        private var inFlight: Set<String> = []
        private var lastAttempt: [String: Date] = [:]
        func shouldStart(symbol: String, cooldown: TimeInterval) -> Bool {
            let now = Date()
            if inFlight.contains(symbol) { return false }
            if let last = lastAttempt[symbol], now.timeIntervalSince(last) < cooldown { return false }
            inFlight.insert(symbol)
            lastAttempt[symbol] = now
            return true
        }
        func finish(symbol: String) { inFlight.remove(symbol) }
    }
    private let volumeGate = _VolumeFetchGate()
    private let volumeAttemptCooldown: TimeInterval = 10 // seconds (reduced from 45 for faster initial volume display)

    @MainActor private var lastVolumePrimeAt: Date?
    private let volumePrimeMinInterval: TimeInterval = 15 // seconds

    // Simple flag gate to prevent overlapping async work
    private actor _FlagGate {
        private var busy = false
        func tryStart() -> Bool {
            if busy { return false }
            busy = true
            return true
        }
        func finish() { busy = false }
    }
    private let overlayGate = _FlagGate()
    private let basesGate = _FlagGate()
    
    // NOTE: Removed PercentCacheActor - it caused race condition crashes.
    // Now using simplified MainActor-only approach with batch persistence.

    // Conservative whitelist of Binance base symbols we attempt to overlay via 24h ticker
    private let binanceOverlaySupportedSymbols: Set<String> = [
        "BTC","ETH","BNB","SOL","XRP","ADA","DOGE","TRX","DOT","AVAX",
        "LINK","MATIC","LTC","BCH","ATOM","ETC","XLM","ICP","APT","ARB",
        "OP","SUI","TON","NEAR","FTM","FIL","HBAR","RNDR","AAVE","UNI",
        "ALGO","FLOW","INJ","TIA","SEI","GRT","EGLD","KAS","NEO","QNT"
    ]

    @MainActor private var binanceSupportedBases: Set<String> = []
    @MainActor private var binanceSupportedBasesLastRefresh: Date?
    private let binanceSupportedBasesRefreshInterval: TimeInterval = 6 * 60 * 60 // 6 hours
    private let binanceCommonQuotes: Set<String> = ["USDT","USD","BUSD","USDC","FDUSD"]
    
    // PERFORMANCE FIX: Cache of symbols that have failed volume lookups on Binance
    // Prevents repeated failed network requests for the same invalid symbols
    // Cache is cleared periodically to allow retries for symbols that may have temporarily failed
    @MainActor private var binanceInvalidBases: Set<String> = []
    private let binanceInvalidBasesMaxAge: TimeInterval = 900 // Clear after 15 minutes for faster retries
    @MainActor private var binanceInvalidBasesLastClear: Date = Date()
    
    // PERFORMANCE FIX v17: Track invalid base logging to reduce console spam
    @MainActor private var binanceInvalidBasesLoggedThisSession: Int = 0

    // Known-problematic or venue-specific bases that frequently 400 or are not tradable on Binance public endpoints
    // These symbols don't have USDT/USD pairs on Binance and generate repeated API errors
    private let binanceOverlayBlocklist: Set<String> = [
        // Exchange-specific tokens not on Binance
        "LEO","OKB","HTX","BGB","WBT","CBBTC",
        // Privacy coins (delisted or never listed)
        "XMR","PI",
        // Wrapped/staked tokens (trade on DEXes, not CEXes)
        "STETH","WSTETH","WEETH","RSETH","WBETH","WETH",
        // Stablecoin variants and synthetic assets
        "USDT0","BSC-USD","USDF","USDE","SUSDE","SUSDS","C1USD","BFUSD",
        // Other problematic symbols
        "JLP","M","ASTER","KHYPE","COAI","RAIN","CC","FIGR_HELOC"
    ]

    // Use MarketCoin.stableBases and MarketCoin.MarketCoin.stableSymbols as canonical source

    /// Clamp helper for 24h percent on stablecoins. Returns 0 when |value| is within the neutral band.
    /// Values are in percent units (e.g., 0.25 == 0.25%).
    @inline(__always)
    private func clampStable24h(symbol: String, value: Double?) -> Double? {
        guard let v = value, v.isFinite else { return value }
        if MarketCoin.stableSymbols.contains(symbol.uppercased()) {
            // Neutral band for stables: treat small drift as 0 to avoid misleading signals
            let neutralBand: Double = 0.5 // percent
            if abs(v) < neutralBand { return 0 }
        }
        return v
    }

    // Maximum retention for sidecar cache entries before pruning them from memory.
    // Read-time freshness is enforced by the stricter short/long sidecar read ages below.
    private let maxSidecarCacheAge: TimeInterval = 6 * 60 * 60 // 6 hours
    // Hard freshness budget for UI-facing sidecar reads.
    private let maxShortSidecarReadAge: TimeInterval = 3 * 60 // 3 minutes (1h/24h)
    private let maxLongSidecarReadAge: TimeInterval = 20 * 60 // 20 minutes (7d)
    private let maxVolumeSidecarReadAge: TimeInterval = 4 * 60 // 4 minutes
    @MainActor private var lastSidecarInvalidationAt: Date?
    
    // MEMORY FIX v2: Lowered from 500 to 300 — most apps track ~250 coins max
    // Each dictionary entry is small but 10+ dictionaries × 500 entries each adds up
    private let maxSymbolCacheEntries = 300
    
    init() {
        // PERFORMANCE FIX v18: Defer disk I/O from init to unblock the splash screen.
        // LivePriceManager.shared is accessed during MarketViewModel.init() in the
        // CryptoSageAIApp.init() chain - BEFORE the splash screen can even render.
        
        // Only load Binance bases synchronously (small file, needed for price matching)
        if let cached: [String] = CacheManager.shared.load([String].self, from: "binance_supported_bases.json"), !cached.isEmpty {
            binanceSupportedBases = Set(cached.map { $0.uppercased() })
        }
        
        // Keep Firestore subscription setup synchronous - it's just Combine wiring (fast)
        // and must be ready before startListening() fires in startHeavyLoading Phase 2.5.
        #if targetEnvironment(simulator)
        if AppSettings.isSimulatorLimitedDataMode {
            // Limited simulator profile uses throttled HTTP overlay/polling only.
            #if DEBUG
            print("🧪 [LivePriceManager] Simulator limited profile: skipping Firestore subscriptions")
            #endif
        } else {
            setupFirestoreSubscription()
            #if DEBUG
            print("🧪 [LivePriceManager] Simulator full-data profile: Firestore subscriptions enabled")
            #endif
        }
        #else
        setupFirestoreSubscription()
        #endif
        
        // MEMORY FIX: Listen for memory warnings and prune caches aggressively
        // MEMORY FIX v8: Store observer token so it can be removed in deinit
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleMemoryWarning()
            }
        }
        
        // Defer file I/O to after first frame renders
        Task { @MainActor [weak self] in
            // Small yield to let the main thread breathe
            await Task.yield()
            
            // Clean up old corrupted cache files (one-time migration)
            CacheManager.shared.delete("percent_1h_sidecar.json")
            CacheManager.shared.delete("percent_24h_sidecar.json")
            CacheManager.shared.delete("percent_7d_sidecar.json")
            
            // Load persisted percent cache
            await self?.loadPersistedPercentCache()
        }
    }
    
    // MEMORY FIX: Aggressively prune caches when system is under memory pressure
    // MEMORY FIX: Changed from private to internal so app-level memory watchdog can call it
    @MainActor
    func handleMemoryWarning() {
        logger.warning("⚠️ [LivePriceManager] Memory warning received - pruning caches")
        
        // Clear ALL non-essential caches (aggressive)
        priceMedianBuffer.removeAll()
        cachedSparklines.removeAll()
        sparklineCacheLastLoadedAt = .distantPast
        _rateLimitedLogLock.lock()
        _rateLimitedLogTimes.removeAll()
        _rateLimitedLogLock.unlock()
        lastPriceSource.removeAll()
        lastPriceSourceAt.removeAll()
        lastDirectAt.removeAll()
        lastDirectPriceBySymbol.removeAll()
        lastProviderApplyAt.removeAll()
        firestoreValueTimestamps.removeAll()
        derivedRankByID.removeAll()
        derivedMaxSupplyByID.removeAll()
        // MEMORY FIX v2: Also clear volume cache - it can be rebuilt from API responses
        latestVolumeUSDBySymbol.removeAll()
        lastVolumeUpdatedAt.removeAll()
        volumeCacheIsDirty = false
        // MEMORY FIX v4: Clear timestamp tracking dictionaries too
        last1hChangeBySymbol.removeAll()
        last24hChangeBySymbol.removeAll()
        last7dChangeBySymbol.removeAll()
        last1hChangeUpdatedAt.removeAll()
        last24hChangeUpdatedAt.removeAll()
        last7dChangeUpdatedAt.removeAll()
        lastEmittedBySymbol.removeAll()
        lastSanitizedSymbols.removeAll()
        latestCoinsForEmission = nil
        // MEMORY FIX v4: Reset emission pipeline state so it can restart cleanly
        isAugmentationInFlight = false
        pendingRawCoins = nil
        emitCoinsDebounceTask?.cancel()
        emitCoinsDebounceTask = nil
        // MEMORY FIX v14: Also clear currentCoins — this is a full copy of market data
        // that can be repopulated from the next API/Firestore response.
        currentCoins = []
        
        logger.info("✅ [LivePriceManager] Cache pruning complete after memory warning")

        // Schedule a recovery poll to repopulate cleared percent-change data.
        // Without this, all 24h/7d/1h change values show as zero until the next poll cycle.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3s delay to let memory settle
            guard let self, !Task.isCancelled else { return }
            self.logger.info("🔄 [LivePriceManager] Triggering recovery poll after memory warning")
            await self.pollMarketCoinsPublic()
        }
    }
    
    // MEMORY FIX: Prune per-symbol dictionaries that exceed the entry limit
    @MainActor
    private func pruneSymbolCachesIfNeeded() {
        if lastPriceSource.count > maxSymbolCacheEntries {
            lastPriceSource.removeAll()
            lastPriceSourceAt.removeAll()
        }
        if priceMedianBuffer.count > maxSymbolCacheEntries {
            priceMedianBuffer.removeAll()
        }
        if lastDirectAt.count > maxSymbolCacheEntries {
            lastDirectAt.removeAll()
            lastDirectPriceBySymbol.removeAll()
        }
        if lastProviderApplyAt.count > maxSymbolCacheEntries {
            lastProviderApplyAt.removeAll()
        }
        if firestoreValueTimestamps.count > maxSymbolCacheEntries {
            firestoreValueTimestamps.removeAll()
        }
        if cachedSparklines.count > maxSymbolCacheEntries {
            cachedSparklines.removeAll()
            sparklineCacheLastLoadedAt = .distantPast
        }
        // MEMORY FIX v2: Prune volume cache too
        if latestVolumeUSDBySymbol.count > maxSymbolCacheEntries {
            latestVolumeUSDBySymbol.removeAll()
        }
    }
    
    /// PERFORMANCE FIX: One-time setup for Firestore subscription
    /// Called once during initialization - Firestore listener itself is started at app level
    /// This prevents the listener from being stopped/started on every tab switch
    private func setupFirestoreSubscription() {
        // Guard against duplicate subscriptions — clear existing before re-subscribing
        if !firestoreCancellables.isEmpty {
            firestoreCancellables.removeAll()
        }
        // Subscribe to Firestore ticker updates with coalescing (Binance heatmap data)
        // MEMORY FIX v7: Use DispatchQueue.main.async instead of Task { @MainActor in }.
        // Task creates new entries on Swift Concurrency's cooperative queue. When Firestore
        // delivers rapid updates (multiple per second), these Tasks accumulate and prevent
        // the run loop from iterating — starving timers, autorelease pool drains, and UI events.
        // DispatchQueue.main.async integrates with the run loop, allowing other events between blocks.
        // MEMORY FIX v7: Removed nested Task { @MainActor in } and replaced with
        // direct GCD scheduling. Each Task creates a new entry on Swift Concurrency's
        // cooperative queue. When Firestore delivers rapid updates, these Tasks accumulate
        // and prevent the run loop from iterating — starving timers and autorelease pool drains.
        FirestoreMarketSync.shared.tickerPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tickers in
                guard let self = self else { return }
                // MEMORY FIX v7: Use MainActor.assumeIsolated instead of Task { @MainActor in }.
                // We're already on the main thread from .receive(on: DispatchQueue.main).
                // Task { @MainActor in } creates cooperative executor entries that starve the run loop.
                // assumeIsolated lets us call @MainActor methods without creating a new Task.
                MainActor.assumeIsolated {
                    self.queueTickerUpdates(tickers)
                }
            }
            .store(in: &firestoreCancellables)
        
        // Subscribe to CoinGecko market data from Firestore (PRIMARY market data source)
        // This replaces direct CoinGecko polling as the main data source
        // Data includes: prices, sparklines, 1h/24h/7d percentages for top 250 coins
        FirestoreMarketSync.shared.coingeckoCoinsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] coins in
                guard let self = self else { return }
                MainActor.assumeIsolated {
                    self.ingestFirestoreMarketData(coins)
                }
            }
            .store(in: &firestoreCancellables)
        
        logger.info("🔥 [LivePriceManager] Firestore subscriptions set up (heatmap + CoinGecko markets)")
    }
    
    // MARK: - Firestore CoinGecko Market Data Ingestion
    
    /// Timestamp of the last successful Firestore CoinGecko data ingestion
    @MainActor private var lastFirestoreCoinGeckoIngestAt: Date?
    
    @MainActor
    private func isSemanticallySameMarketList(_ lhs: [MarketCoin], _ rhs: [MarketCoin]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (a, b) in zip(lhs, rhs) {
            if a.id != b.id { return false }
            let ap = a.priceUsd ?? 0
            let bp = b.priceUsd ?? 0
            if abs(ap - bp) > max(0.01, max(abs(ap), abs(bp)) * 0.0005) { return false }
            let a24 = a.priceChangePercentage24hInCurrency ?? 0
            let b24 = b.priceChangePercentage24hInCurrency ?? 0
            if abs(a24 - b24) > 0.05 { return false }
            let a1 = a.priceChangePercentage1hInCurrency ?? 0
            let b1 = b.priceChangePercentage1hInCurrency ?? 0
            if abs(a1 - b1) > 0.05 { return false }
            if a.sparklineIn7d.count != b.sparklineIn7d.count { return false }
        }
        return true
    }
    
    /// Ingest full CoinGecko market data received from Firestore
    /// This is the PRIMARY data path - all devices read the same server-cached snapshot.
    /// It replaces the currentCoins array and populates all sidecar caches.
    @MainActor
    private func ingestFirestoreMarketData(_ incomingCoins: [MarketCoin]) {
        guard !incomingCoins.isEmpty else { return }
        rateLimitedLog("liveSource.firestore", "📡 [LivePriceManager] source=firestore freshness=fresh count=\(incomingCoins.count)", minInterval: 20.0)
        
        // MEMORY FIX v12: Skip ingestion when available memory is critically low.
        // When the app is already under memory pressure, ingesting new data (building
        // merge dictionaries, updating sidecar caches, emitting to MarketViewModel)
        // only makes things worse. The watchdog's emergency stop should handle cleanup
        // while we avoid feeding more data into the pipeline.
        let availMB = Double(os_proc_available_memory()) / (1024 * 1024)
        if availMB > 0 && availMB < 500 {
            logger.warning("🛡️ [LivePriceManager] Skipping Firestore ingestion — low memory (\(Int(availMB)) MB available)")
            return
        }
        
        // MEMORY FIX v11: Skip ingestion during startup emission freeze.
        // The first emission already populated the data pipeline. Further Firestore
        // ingestions during the freeze window would be processed (allocating memory
        // for coin arrays, sidecar caches, etc.) only to have the emission blocked.
        // Skip the processing entirely to save memory.
        if let freezeEnd = startupEmissionFreezeUntil, Date() < freezeEnd {
            return
        }
        
        // Keep full live universe aligned with MarketViewModel/Startup caps.
        let coins = incomingCoins.count > Self.maxCurrentCoinsCount ? Array(incomingCoins.prefix(Self.maxCurrentCoinsCount)) : incomingCoins
        
        #if DEBUG
        // MEMORY LOGGING: Track memory at each Firestore data ingestion
        var _memInfo = mach_task_basic_info()
        var _memCount = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let _memResult = withUnsafeMutablePointer(to: &_memInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(_memCount)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &_memCount)
            }
        }
        if _memResult == KERN_SUCCESS {
            let mb = Double(_memInfo.resident_size) / (1024 * 1024)
            logger.info("🧠 MEMORY [ingestFirestoreMarketData \(coins.count) coins]: \(String(format: "%.1f", mb)) MB")
        }
        #endif
        
        // PERFORMANCE FIX v21: Block heavy ingestion during scroll to prevent main thread jank.
        // The 250-coin merge (dictionary build + iteration) is too heavy for scroll frames.
        // FirestoreMarketSync.scheduleScrollEndFlush() queues the data and re-delivers it
        // when scroll ends, so no data is lost.
        // Exception: Always allow the first ingestion so initial data populates views.
        if hasCompletedFirstEmission && ScrollStateManager.shared.shouldBlockHeavyOperation() {
            return
        }
        
        let now = Date()
        let previousCount = currentCoins.count
        
        // PRICE SANITY: Minimum thresholds for well-known coins to prevent bad data propagation.
        // If an API or Firestore returns BTC at ~$1 (data bug), we reject it and keep the previous value.
        let minPriceThresholds: [String: Double] = [
            "bitcoin": 1000, "ethereum": 50, "binancecoin": 10, "solana": 1
        ]
        
        // Merge with existing data: preserve non-zero prices and healthy sparklines
        var merged = coins
        if !currentCoins.isEmpty {
            var prevByID: [String: MarketCoin] = [:]
            prevByID.reserveCapacity(currentCoins.count)
            for c in currentCoins { prevByID[c.id] = c }
            
            for i in 0..<merged.count {
                let coin = merged[i]
                guard let prev = prevByID[coin.id] else { continue }
                
                // If incoming price is missing/zero, carry forward last known non-zero
                let incoming = coin.priceUsd ?? 0
                if incoming <= 0, let prevPrice = prev.priceUsd, prevPrice > 0 {
                    merged[i].priceUsd = prevPrice
                }
                
                // PRICE SANITY: Reject obviously wrong prices for well-known coins
                if let threshold = minPriceThresholds[coin.id],
                   let price = merged[i].priceUsd, price > 0 && price < threshold {
                    // Price is suspiciously low — keep previous good value if available
                    if let prevPrice = prev.priceUsd, prevPrice >= threshold {
                        logger.warning("⚠️ [LivePriceManager] Rejected \(coin.id) price $\(String(format: "%.4f", price)) — keeping previous $\(String(format: "%.2f", prevPrice))")
                        merged[i].priceUsd = prevPrice
                    } else {
                        logger.warning("⚠️ [LivePriceManager] Rejected \(coin.id) price $\(String(format: "%.4f", price)) — no valid fallback, clearing")
                        merged[i].priceUsd = nil
                    }
                }
                
                // Also check if there's a fresher real-time price from order book
                let symLower = coin.symbol.lowercased()
                if let directAt = lastDirectAt[symLower],
                   now.timeIntervalSince(directAt) < 10.0,
                   let directPrice = lastDirectPriceBySymbol[symLower],
                   directPrice > 0 {
                    // PRICE SANITY: Also check direct prices
                    if let threshold = minPriceThresholds[coin.id], directPrice < threshold {
                        logger.warning("⚠️ [LivePriceManager] Rejected direct price for \(coin.id): $\(String(format: "%.4f", directPrice))")
                    } else {
                        merged[i].priceUsd = directPrice
                    }
                }
            }
        }
        
        // PROCESSING DEDUPE v5.2: Avoid full sidecar updates and re-emissions if the
        // incoming list is semantically unchanged. This prevents repeated heavy passes
        // when Firestore replays equivalent snapshots.
        if isSemanticallySameMarketList(merged, currentCoins) {
            lastFirestoreCoinGeckoIngestAt = now
            return
        }
        
        // Update sidecar caches from the Firestore data (ensures consistency)
        for coin in merged {
            let key = coin.symbol.lowercased()
            
            // Update 1h cache
            if let v = coin.priceChangePercentage1hInCurrency, v.isFinite, abs(v) <= 100 {
                safeSet1hChange(key, v)
                last1hChangeUpdatedAt[key] = now
                firestoreValueTimestamps[key] = now
            }
            
            // Update 24h cache
            if let v = coin.priceChangePercentage24hInCurrency, v.isFinite, abs(v) <= 300 {
                safeSet24hChange(key, v)
                last24hChangeUpdatedAt[key] = now
                firestoreValueTimestamps[key] = now
            }
            
            // Update 7d cache
            if let v = coin.priceChangePercentage7dInCurrency, v.isFinite, abs(v) <= 500 {
                safeSet7dChange(key, v)
                last7dChangeUpdatedAt[key] = now
            }
            
            // Update price tracking
            lastPriceSource[key] = .coinGecko
            lastPriceSourceAt[key] = now
        }
        
        // MERGE FIX: When Firestore CoinGecko sends fewer coins than we already have
        // (e.g., 50 vs 250), merge the fresh data INTO the existing list rather than
        // replacing it. Otherwise EMIT #2 shrinks the market list from 250 to 50,
        // losing 200 coins from the UI until the next full poll.
        if !currentCoins.isEmpty && merged.count < currentCoins.count {
            // Build lookup of fresh Firestore data by ID
            var freshByID: [String: MarketCoin] = [:]
            freshByID.reserveCapacity(merged.count)
            for c in merged { freshByID[c.id] = c }
            
            // Start with the full existing list and overlay fresh data where available
            var fullMerged = currentCoins
            for i in 0..<fullMerged.count {
                if let fresh = freshByID[fullMerged[i].id] {
                    fullMerged[i] = fresh
                }
            }
            // Append any new coins from Firestore that weren't in the existing list
            let existingIDs = Set(fullMerged.map { $0.id })
            for c in merged where !existingIDs.contains(c.id) {
                fullMerged.append(c)
            }
            currentCoins = fullMerged
            lastFirestoreCoinGeckoIngestAt = now
            emitCoins(fullMerged)
        } else {
            // Firestore has same or more coins — safe to replace
            currentCoins = merged
            lastFirestoreCoinGeckoIngestAt = now
            emitCoins(merged)
        }
        
        // Cache to disk for cold-start fallback
        // MEMORY FIX: Use async save to avoid blocking the main thread.
        // MEMORY FIX v5: Cap before saving to prevent bloated cache on next launch
        // MERGE FIX: Cache the full coin list (currentCoins) not just the incoming subset
        let coinsToCache = currentCoins
        Task.detached(priority: .utility) { [weak self] in
            await self?.saveCoinsCacheCappedAsync(coinsToCache)
        }
        
        let emittedCount = currentCoins.count
        logger.info("🔥 [LivePriceManager] Ingested \(merged.count) coins from Firestore CoinGecko → emitted \(emittedCount) total (prev: \(previousCount))")
    }
    
    /// Clears percentage sidecar caches for symbols that haven't been updated in maxSidecarCacheAge.
    /// This ensures stale values don't persist indefinitely.
    @MainActor
    func invalidateStaleSidecarEntries() {
        let now = Date()
        guard lastSidecarInvalidationAt == nil || now.timeIntervalSince(lastSidecarInvalidationAt!) > 60 * 60 else { return }
        lastSidecarInvalidationAt = now
        
        // Clear stale entries from MainActor dictionaries based on update timestamps
        // Collect keys first to avoid mutating dictionary while iterating (exclusivity violation)
        let keysToRemove1h = last1hChangeUpdatedAt.filter { now.timeIntervalSince($0.value) > maxSidecarCacheAge }.map { $0.key }
        for key in keysToRemove1h {
            last1hChangeBySymbol.removeValue(forKey: key)
            last1hChangeUpdatedAt.removeValue(forKey: key)
        }
        let cleared1h = keysToRemove1h.count
        
        let keysToRemove24h = last24hChangeUpdatedAt.filter { now.timeIntervalSince($0.value) > maxSidecarCacheAge }.map { $0.key }
        for key in keysToRemove24h {
            last24hChangeBySymbol.removeValue(forKey: key)
            last24hChangeUpdatedAt.removeValue(forKey: key)
        }
        let cleared24h = keysToRemove24h.count
        
        let keysToRemove7d = last7dChangeUpdatedAt.filter { now.timeIntervalSince($0.value) > maxSidecarCacheAge }.map { $0.key }
        for key in keysToRemove7d {
            last7dChangeBySymbol.removeValue(forKey: key)
            last7dChangeUpdatedAt.removeValue(forKey: key)
        }
        let cleared7d = keysToRemove7d.count
        
        if cleared1h > 0 || cleared24h > 0 || cleared7d > 0 {
            logger.info("🧹 [LivePriceManager] Invalidated stale sidecar entries: 1h=\(cleared1h), 24h=\(cleared24h), 7d=\(cleared7d)")
        }
    }
    
    /// Rate-limit for sidecar cache clear log to reduce spam
    @MainActor private var lastSidecarClearLogAt: Date = .distantPast
    private let sidecarClearLogMinInterval: TimeInterval = 60.0 // Log at most once per minute
    
    /// Force-clears all sidecar caches (called on app foreground to ensure fresh data)
    /// PERFORMANCE FIX v21: Increased cooldown from 30s to 90s to prevent repeated cache nuking.
    /// The logs show "Cleared sidecar caches" appearing multiple times per session, each time
    /// wiping all percentage data and forcing expensive re-derivation. 90s gives Firestore/API
    /// time to fully repopulate before allowing another clear.
    @MainActor private var lastSidecarClearAt: Date = .distantPast
    private let sidecarClearCooldown: TimeInterval = 90.0
    
    @MainActor
    func clearAllSidecarCaches() {
        let now = Date()
        guard now.timeIntervalSince(lastSidecarClearAt) >= sidecarClearCooldown else { return }
        lastSidecarClearAt = now
        
        // STALE DATA FIX v2: Only evict stale percentage data, preserving recent values.
        // Previously removeAll() wiped ALL percentages on foreground, causing MarketMovers
        // and HeatMap to show "0 coins with real % data" until the next Firestore/Binance
        // overlay repopulated them (up to 30-60s). Now we only evict entries older than 5
        // minutes — this ensures stale overnight data is refreshed while keeping data that
        // was fetched in the current session.
        let staleThreshold: TimeInterval = 300 // 5 minutes
        
        // Evict stale 1h entries
        let stale1h = last1hChangeUpdatedAt.filter { now.timeIntervalSince($0.value) > staleThreshold }
        for key in stale1h.keys {
            last1hChangeUpdatedAt.removeValue(forKey: key)
            last1hChangeBySymbol.removeValue(forKey: key)
        }
        
        // Evict stale 24h entries
        let stale24h = last24hChangeUpdatedAt.filter { now.timeIntervalSince($0.value) > staleThreshold }
        for key in stale24h.keys {
            last24hChangeUpdatedAt.removeValue(forKey: key)
            last24hChangeBySymbol.removeValue(forKey: key)
            previousProviderValue24h.removeValue(forKey: key)
        }
        
        // Evict stale 7d entries
        let stale7d = last7dChangeUpdatedAt.filter { now.timeIntervalSince($0.value) > staleThreshold }
        for key in stale7d.keys {
            last7dChangeUpdatedAt.removeValue(forKey: key)
            last7dChangeBySymbol.removeValue(forKey: key)
        }
        
        let evictedCount = stale1h.count + stale24h.count + stale7d.count
        
        // Rate-limited logging to avoid console spam
        if now.timeIntervalSince(lastSidecarClearLogAt) >= sidecarClearLogMinInterval {
            logger.info("♻️ [LivePriceManager] Cleared \(evictedCount) stale sidecar entries on foreground")
            lastSidecarClearLogAt = now
        }
    }

    /// Tracks whether we've done the initial cold-start cache clear
    /// SPARKLINE FIX: Only clear cache once per app launch, not on every startPolling() call
    @MainActor private var hasDoneColdStartClear: Bool = false
    
    /// Begin polling MarketCoin data every 120 seconds by default
    /// CRASH FIX: Moved to @MainActor to safely access currentCoins
    /// SCALABILITY: Triggers immediate overlay for instant data, then starts regular polling
    @MainActor
    func startPolling(interval: TimeInterval = 60) {
        guard !CryptoSageAIApp.isEmergencyStopActive() else {
            logger.info("🛑 [LivePriceManager] startPolling skipped — emergency stop active")
            return
        }
        let effective = max(30, interval)
        
        // Skip if already polling at the same or faster interval
        if isPollingActive && currentPollingInterval <= effective {
            return
        }
        
        stopPolling()
        isPollingActive = true
        currentPollingInterval = effective
        
        // SCALABILITY FIX: Trigger immediate overlay for instant live prices
        // The overlay system uses Firebase proxy with a 30-second shared cache.
        // All users benefit from shared data - cost effective and fast.
        triggerImmediateOverlay()
        
        // SPARKLINE FIX: Only clear cache on TRUE cold start (first call after app launch)
        // Previously this ran on every startPolling() call (tab switches, foreground returns, etc.)
        // which caused sparklines and percentages to flicker/disappear repeatedly.
        // Now we only clear once per app session on the very first call.
        let isColdStart = !hasDoneColdStartClear
        if isColdStart {
            hasDoneColdStartClear = true
            let hadCachedPercentages = !last24hChangeBySymbol.isEmpty
            last1hChangeBySymbol.removeAll()
            last24hChangeBySymbol.removeAll()
            last7dChangeBySymbol.removeAll()
            last1hChangeUpdatedAt.removeAll()
            last24hChangeUpdatedAt.removeAll()
            if hadCachedPercentages {
                logger.info("♻️ [LivePriceManager] Cleared stale percent cache on startup")
            }
        }
        
        // FIX: Prefer MarketViewModel.shared.allCoins as the primary source for initial coins
        // This is guaranteed to be populated because CryptoSageAIApp.startHeavyLoading() 
        // awaits loadFromCacheOnly() before calling startPolling()
        if currentCoins.isEmpty {
            // Structural startup seed only from already-loaded in-memory state.
            // Do not silently hydrate price data from disk cache in live-only mode.
            let marketVMCoins = MarketViewModel.shared.allCoins
            if !marketVMCoins.isEmpty {
                self.currentCoins = marketVMCoins
                self.emitCoins(marketVMCoins)
                logger.info("📡 [LivePriceManager] Seeded \(marketVMCoins.count) coins from in-memory MarketViewModel")
            }
        }
        // STALE DATA FIX: On cold start, poll immediately to get fresh data ASAP.
        // Only apply thundering-herd jitter on subsequent polling restarts (tab switches, etc.)
        let jitter = isColdStart ? 0.0 : Double.random(in: 0...5.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + jitter) {
            _ = Task { [weak self] in await self?.pollMarketCoins() }
        }
        timerCancellable = Timer
            .publish(every: effective, on: .main, in: .common)
            .autoconnect()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                _ = Task { await self?.pollMarketCoins() }
                // FIX v14: Prune unbounded dictionaries every 5 minutes to prevent slow leak
                if let self = self, Date().timeIntervalSince(self.lastPruneAt) > 300 {
                    self.pruneStaleData()
                }
            }
        // Start frequent price overlay updates
        // MEMORY FIX v5: Defer overlay timer by 15 seconds. Previously started immediately,
        // which meant overlay fires + CoinGecko poll + Firestore emission all ran simultaneously
        // during startup, creating competing emission cycles. With the augmentation gate only
        // one processes at a time, but the others queue up and hold retained closures.
        overlayWarmupPassesRemaining = 3
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000) // 6s after polling starts
            self?.startPriceOverlayTimer()
        }
        
        // PERFORMANCE FIX: Firestore sync is now managed at app level, not tied to polling lifecycle
        // This prevents listener churn on tab switches. Subscription is set up once in init().
    }

    // Stop the polling timer
    // CRASH FIX: Made @MainActor since it modifies shared state accessed by startPolling
    @MainActor
    func stopPolling() {
        timerCancellable?.cancel()
        timerCancellable = nil
        priceTimerCancellable?.cancel()
        priceTimerCancellable = nil
        isPollingActive = false
        currentPollingInterval = 0
        
        // PERFORMANCE FIX: Firestore sync is NOT stopped here anymore
        // Keeping Firestore listener alive at app level prevents listener churn on tab switches
        // The listener is only stopped on app termination
    }
    
    // MARK: - Periodic Data Pruning
    
    // FIX v14: Track last prune time to run every 5 minutes
    @MainActor private var lastPruneAt: Date = Date()
    
    /// Prunes unbounded dictionaries that grow over time and cause a slow memory leak.
    /// Called from the poll timer. Caps symbol-keyed dictionaries to 200 entries.
    @MainActor func pruneStaleData() {
        let maxEntries = 200
        var freedCount = 0
        
        func capDict<V>(_ dict: inout [String: V], name: String) {
            if dict.count > maxEntries {
                let excess = dict.count - maxEntries
                // Remove oldest entries (arbitrary since no timestamp; just trim)
                let keysToRemove = Array(dict.keys.prefix(excess))
                for key in keysToRemove { dict.removeValue(forKey: key) }
                freedCount += excess
            }
        }
        
        capDict(&last1hChangeBySymbol, name: "last1hChange")
        capDict(&last24hChangeBySymbol, name: "last24hChange")
        capDict(&last7dChangeBySymbol, name: "last7dChange")
        capDict(&lastPriceSource, name: "lastPriceSource")
        capDict(&lastPriceSourceAt, name: "lastPriceSourceAt")
        capDict(&firestoreValueTimestamps, name: "firestoreValueTimestamps")
        capDict(&lastDirectAt, name: "lastDirectAt")
        capDict(&lastDirectPriceBySymbol, name: "lastDirectPriceBySymbol")
        capDict(&lastProviderApplyAt, name: "lastProviderApplyAt")
        capDict(&latestVolumeUSDBySymbol, name: "latestVolumeUSD")
        capDict(&lastVolumeUpdatedAt, name: "lastVolumeUpdatedAt")
        capDict(&derivedRankByID, name: "derivedRank")
        capDict(&derivedMaxSupplyByID, name: "derivedMaxSupply")
        capDict(&last1hChangeUpdatedAt, name: "last1hUpdatedAt")
        capDict(&last24hChangeUpdatedAt, name: "last24hUpdatedAt")
        capDict(&last7dChangeUpdatedAt, name: "last7dUpdatedAt")
        capDict(&previousProviderValue24h, name: "prevProvider24h")
        capDict(&historyLastAttemptAt, name: "historyLastAttempt")
        capDict(&lastEmittedBySymbol, name: "lastEmitted")
        capDict(&priceMedianBuffer, name: "priceMedianBuffer")
        capDict(&cachedSparklines, name: "cachedSparklines")
        
        // Cap pendingTickerUpdates more aggressively
        if pendingTickerUpdates.count > 200 {
            let excess = pendingTickerUpdates.count - 200
            pendingTickerUpdates.removeAll()
            freedCount += excess
            logger.warning("⚠️ [LivePriceManager] Pruned pendingTickerUpdates (exceeded 200)")
        }
        
        if freedCount > 0 {
            logger.info("🧹 [LivePriceManager] Pruned \(freedCount) stale dictionary entries")
        }
        lastPruneAt = Date()
    }
    
    // MARK: - Firestore Sync Integration
    
    // PERFORMANCE FIX v15: Increased coalescing delay to reduce UI updates from Firestore
    // Firestore backend updates every 5 seconds, but we don't need UI updates that frequently
    // Pending ticker updates that will be processed in the next coalescing window
    @MainActor private var pendingTickerUpdates: [String: FirestoreMarketSync.FirestoreTicker] = [:]
    @MainActor private var tickerCoalescingTask: Task<Void, Never>?
    // PERFORMANCE FIX v21: Increased from 2s to 4s. Logs show ticker updates arriving every
    // few seconds from Firestore, each triggering full coin array rebuild. 4s window batches
    // more updates together, reducing main-thread work by ~50%.
    private let tickerCoalesceDelay: TimeInterval = 4.0
    
    /// Start Firestore sync listener (call from app level, not view lifecycle)
    /// PERFORMANCE FIX: This is now called once at app startup, not on every tab switch
    /// The subscription is set up in init(), so this only starts the listener if not already running
    func startFirestoreSync() {
        FirestoreMarketSync.shared.startListening()
        logger.info("🔥 [LivePriceManager] Firestore sync started (app level)")
    }
    
    /// PERFORMANCE FIX: Queue ticker updates for coalescing instead of processing immediately
    /// This batches rapid updates from Firestore/WebSocket into single processing passes
    @MainActor
    private func queueTickerUpdates(_ tickers: [String: FirestoreMarketSync.FirestoreTicker]) {
        // Merge new updates into pending (newer values overwrite older)
        for (key, value) in tickers {
            pendingTickerUpdates[key] = value
        }
        
        // MEMORY FIX: Cap pending updates to prevent unbounded growth during network issues
        // FIX v14: Reduced cap from 500 to 200 to limit memory growth
        if pendingTickerUpdates.count > 200 {
            pendingTickerUpdates.removeAll()
            logger.warning("⚠️ [LivePriceManager] Pruned pendingTickerUpdates (exceeded 200)")
        }
        
        // Cancel existing coalescing task and schedule new one
        tickerCoalescingTask?.cancel()
        tickerCoalescingTask = Task { @MainActor [weak self] in
            // Wait for coalescing window
            try? await Task.sleep(nanoseconds: UInt64(self?.tickerCoalesceDelay ?? 0.15) * 1_000_000_000)
            guard !Task.isCancelled, let self = self else { return }
            
            // Process all pending updates in one batch
            let updates = self.pendingTickerUpdates
            self.pendingTickerUpdates = [:]
            
            guard !updates.isEmpty else { return }
            self.applyFirestoreTickers(updates)
        }
    }
    
    /// Stop Firestore sync - ONLY call on app termination, not on view lifecycle events
    /// PERFORMANCE FIX: This should NOT be called on tab switches to prevent listener churn
    func stopFirestoreSync() {
        FirestoreMarketSync.shared.stopListening()
        firestoreCancellables.removeAll()
        logger.info("🔥 [LivePriceManager] Firestore sync stopped (app termination)")
    }
    
    /// Apply Firestore ticker data as a price overlay
    /// This is called when FirestoreMarketSync receives updates
    /// DATA CONSISTENCY: Firestore is the SINGLE SOURCE OF TRUTH for 24h AND 1h percentages
    /// Values from Firestore take absolute priority over HTTP polling and CoinGecko
    @MainActor
    private func applyFirestoreTickers(_ tickers: [String: FirestoreMarketSync.FirestoreTicker]) {
        guard !tickers.isEmpty else { return }
        
        // PERFORMANCE FIX v17: During ANY scroll, completely skip heavy processing
        // This was a major cause of "System gesture gate timed out" - creating 85+ MarketCoin
        // objects on the main thread while user was scrolling.
        // The data will be refreshed when scroll ends via the normal polling cycle.
        // Firestore sends fresh data every ~30-60s, so missing one batch is imperceptible.
        let isScrolling = ScrollStateManager.shared.shouldBlockHeavyOperation()
        
        // During ANY scroll, completely defer - don't even process data
        // Previously this only deferred during "fast" scroll, but regular scroll was still janky
        if isScrolling {
            return  // PERFORMANCE v26: Removed per-scroll log - this fires constantly during scroll
        }
        
        var updatedCount = 0
        var updated1hCount = 0
        let now = Date()
        
        // PERFORMANCE FIX: Build lowercase lookup map once (O(n) where n = tickers count)
        var tickerLookup: [String: FirestoreMarketSync.FirestoreTicker] = [:]
        tickerLookup.reserveCapacity(tickers.count * 2)  // Account for both cases
        for (symbol, ticker) in tickers {
            let symLower = symbol.lowercased()
            tickerLookup[symLower] = ticker
            tickerLookup[symbol] = ticker  // Keep original case too
            
            // Update the 24h change cache (primary use for heat map)
            // DATA CONSISTENCY: Mark this value as from Firestore so HTTP polling won't overwrite it
            if ticker.change24h.isFinite && !ticker.change24h.isNaN {
                last24hChangeBySymbol[symLower] = ticker.change24h
                last24hChangeUpdatedAt[symLower] = now
                firestoreValueTimestamps[symLower] = now  // Mark as Firestore source
                updatedCount += 1
            }
            
            // NEW: Update the 1h change cache from Firestore (when available)
            // This ensures all devices show consistent 1H percentages for top coins
            // DATA CONSISTENCY: Firestore 1H values take priority over CoinGecko (which can be stale)
            if let change1h = ticker.change1h, change1h.isFinite && !change1h.isNaN {
                // Sanity check: 1H changes should be within ±50%
                if abs(change1h) <= 50 {
                    safeSet1hChange(symLower, change1h)
                    last1hChangeUpdatedAt[symLower] = now
                    updated1hCount += 1
                }
            }
            
            // Update price tracking for staleness detection
            lastPriceSource[symLower] = .binance  // Firestore data comes from Binance
            lastPriceSourceAt[symLower] = now
        }
        
        // PERFORMANCE FIX: Incremental update - only modify coins with matching tickers
        // Instead of map() which creates new array, we use direct indexing
        guard !currentCoins.isEmpty else { return }
        
        var updated = currentCoins
        var coinUpdatedCount = 0
        
        for i in 0..<updated.count {
            let coin = updated[i]
            let symLower = coin.symbol.lowercased()
            
            // O(1) lookup instead of dictionary access for each key variant
            guard let ticker = tickerLookup[symLower] else { continue }
            
            // Determine the best 1H value: prefer Firestore, fall back to existing coin value
            let best1hValue: Double? = {
                if let fs1h = ticker.change1h, fs1h.isFinite && abs(fs1h) <= 50 {
                    return fs1h  // Firestore value is authoritative
                }
                return coin.priceChangePercentage1hInCurrency  // Keep existing value
            }()
            
            // PRICE CONSISTENCY FIX: Check if there's a fresher real-time price from order book
            // Firestore syncs every 1 minute, but order book WebSocket updates every 100ms
            // Don't overwrite recent order book prices with stale Firestore prices
            let bestPrice: Double = {
                // Check if we have a recent direct price update (from order book WebSocket)
                if let directAt = lastDirectAt[symLower],
                   now.timeIntervalSince(directAt) < 10.0,  // Direct price is less than 10 seconds old
                   let directPrice = lastDirectPriceBySymbol[symLower],
                   directPrice > 0 {
                    // Keep the fresher order book price instead of Firestore price
                    return directPrice
                }
                
                // SANITY CHECK: Reject Firestore ticker prices that are wildly different
                // from the existing CoinGecko price. This catches backend data issues where
                // e.g. a stablecoin price gets mapped to BTC (BTC showing $0.9996 instead of $97K).
                // Only applies when we already have a valid price to compare against.
                if ticker.price > 0, let existingPrice = coin.priceUsd, existingPrice > 0 {
                    let ratio = ticker.price / existingPrice
                    // If the Firestore price is >90% lower or >10x higher than existing, reject it
                    // (normal price movements are <50% in a single Firestore sync interval of ~1 min)
                    if ratio < 0.1 || ratio > 10.0 {
                        return existingPrice  // Keep existing price, Firestore data is suspect
                    }
                }
                
                // Use Firestore price if available, otherwise keep existing
                return ticker.price > 0 ? ticker.price : (coin.priceUsd ?? 0)
            }()
            
            // VOLUME CONSISTENCY FIX: Prefer provider aggregate volume over single-exchange ticker volume.
            // Firestore/Binance ticker volume is venue-specific and can be much lower than provider
            // aggregate market volume. Keep the existing provider value when available, then choose the
            // best fallback between ticker and sidecar with sanity guards to avoid regressions.
            let bestVolume: Double? = {
                if let v = coin.totalVolume, v.isFinite, v > 0 { return v }
                
                let tickerVol: Double? = {
                    guard ticker.quoteVolume.isFinite, ticker.quoteVolume > 0 else { return nil }
                    return ticker.quoteVolume
                }()
                let sidecarVol: Double? = {
                    guard let v = latestVolumeUSDBySymbol[symLower], v.isFinite, v > 0 else { return nil }
                    return v
                }()
                
                // If both fallback sources exist, prefer the larger one.
                // This protects against transient low/partial exchange volumes.
                if let tv = tickerVol, let sv = sidecarVol {
                    if tv < (sv * 0.05) { return sv } // reject severe down-shock from ticker
                    return max(tv, sv)
                }
                
                // If we only have ticker volume, reject clearly implausible values for large-cap assets.
                // Example: a top coin showing a tiny volume due to symbol/pair mismatch.
                if let tv = tickerVol {
                    if let cap = coin.marketCap, cap.isFinite, cap > 1_000_000_000, tv < (cap * 0.00005) {
                        return sidecarVol
                    }
                    return tv
                }
                
                return sidecarVol
            }()
            
            // Only create new MarketCoin if we actually have an update
            updated[i] = MarketCoin(
                id: coin.id,
                symbol: coin.symbol,
                name: coin.name,
                imageUrl: coin.imageUrl,
                priceUsd: bestPrice,
                marketCap: coin.marketCap,
                totalVolume: bestVolume,
                priceChangePercentage1hInCurrency: best1hValue,
                priceChangePercentage24hInCurrency: ticker.change24h,
                priceChangePercentage7dInCurrency: coin.priceChangePercentage7dInCurrency,
                sparklineIn7d: coin.sparklineIn7d,
                marketCapRank: coin.marketCapRank,
                maxSupply: coin.maxSupply,
                circulatingSupply: coin.circulatingSupply,
                totalSupply: coin.totalSupply
            )
            coinUpdatedCount += 1
        }
        
        // Only emit if we actually updated any coins
        if coinUpdatedCount > 0 {
            currentCoins = updated
            
            // PERFORMANCE FIX v8: Skip UI updates (emitCoins) during scroll to prevent jank
            // The data is still updated in currentCoins, just not pushed to views
            // Views will get fresh data when scroll ends
            if !isScrolling {
                emitCoins(updated)
            }
        }
        
        // PERFORMANCE v26: Rate-limit ticker application logging to reduce console noise
        // This fires every 30s from Firestore; logging every time is excessive
        rateLimitedLog("applyFirestoreTickers.applied",
                       "🔥 [LivePriceManager] Applied \(updatedCount) Firestore ticker updates (\(coinUpdatedCount) coins)",
                       minInterval: 60.0)
        
        // When Firestore delivers Binance data, prevent the coordinator's failure counter
        // from spiraling (e.g., when direct Binance is geo-blocked but Firestore works fine)
        if updatedCount > 0 {
            APIRequestCoordinator.shared.resetFailuresIfStale(for: .binance)
        }
    }
    
    /// Public wrapper to trigger a market data poll.
    /// Used by HeatMap and other components that need to request a fresh data fetch.
    public func pollMarketCoinsPublic() async {
        await pollMarketCoins()
    }

    /// Polls market data and emits via coinSubject
    /// This fetches full market data including sparklines, market caps, etc.
    /// Live prices are also fetched via Firebase proxy for instant updates.
    ///
    /// RATE LIMIT FIX: When Firestore CoinGecko data is fresh (< 6 min old), skip direct API polling.
    /// The server-side syncCoinGeckoToFirestore function fetches CoinGecko data with the
    /// Demo API key every 5 minutes and pushes it to all clients via Firestore listeners.
    /// This reduces direct CoinGecko API calls from dozens-per-user to near-zero,
    /// keeping the app well within CoinGecko's free monthly quota.
    @MainActor private var lastStaleRecoveryKickAt: Date?
    @MainActor private var lastSuccessfulMarketPollAt: Date?
    
    @MainActor
    private func shouldRunStaleRecoveryKick(minInterval: TimeInterval) -> Bool {
        let now = Date()
        if let last = lastStaleRecoveryKickAt, now.timeIntervalSince(last) < minInterval {
            return false
        }
        lastStaleRecoveryKickAt = now
        return true
    }
    
    private func pollMarketCoins() async {
        guard !CryptoSageAIApp.isEmergencyStopActive() else { return }

        let shouldSkipRapidPoll: Bool = await MainActor.run {
            guard let last = self.lastSuccessfulMarketPollAt else { return false }
            return Date().timeIntervalSince(last) < 45
        }
        if shouldSkipRapidPoll {
            rateLimitedLog("pollMarketCoins.recentSuccess", "⏳ [LivePriceManager] Skipping poll - recent successful market refresh", minInterval: 15.0)
            return
        }

        // RATE LIMIT FIX: Skip direct CoinGecko polling when Firestore data is fresh.
        // PARTIAL-UNIVERSE GUARD: If Firestore only delivered a thin subset (e.g., 50 coins),
        // do not keep skipping forever — force one direct poll to restore full market coverage.
        if FirestoreMarketSync.shared.isCoinGeckoDataFresh {
            let lastIngest = await MainActor.run { self.lastFirestoreCoinGeckoIngestAt }
            let currentCount = await MainActor.run { self.currentCoins.count }
            let firestoreCount = FirestoreMarketSync.shared.coinGeckoCount
            let isPartialUniverse = currentCount < 120 && firestoreCount >= 200
            if isPartialUniverse {
                rateLimitedLog(
                    "pollMarketCoins.partialUniverse",
                    "⚠️ [LivePriceManager] Firestore marked fresh but local universe is partial (\(currentCount)/\(firestoreCount)) — forcing direct CoinGecko expansion",
                    minInterval: 60.0
                )
            }
            if let ingest = lastIngest, Date().timeIntervalSince(ingest) < 360, !isPartialUniverse {
                rateLimitedLog("pollMarketCoins.firestoreFresh", "🔥 [LivePriceManager] Skipping direct CoinGecko poll - Firestore data is fresh (\(Int(Date().timeIntervalSince(ingest)))s ago)")
                return
            }
        }
        
        // Check coordinator before polling to respect startup delays and rate limits
        if !APIRequestCoordinator.shared.canMakeRequest(for: .coinGecko) {
            // LIVE DATA FIX v5.1: When Firestore CoinGecko feed is stale, allow an occasional
            // direct poll bypass so prices/sparklines don't remain frozen on cached values.
            // MEMORY FIX v12: Block the stale bypass during the first 30 seconds of app launch.
            // During startup the heavy multi-page CoinGecko fetch runs concurrently with
            // Firestore data ingestion and ensureBaseline, causing 200MB→2GB memory explosion.
            // Rely on Firestore + cached data during this window instead.
            let isInStaleBypassGrace: Bool = await MainActor.run {
                Date().timeIntervalSince(self.startupTime) < self.startupStaleBypassGracePeriod
            }
            if !FirestoreMarketSync.shared.isCoinGeckoDataFresh && !isInStaleBypassGrace {
                let shouldBypass: Bool = await MainActor.run {
                    self.shouldRunStaleRecoveryKick(minInterval: 60.0)
                }
                if shouldBypass {
                    rateLimitedLog("pollMarketCoins.bypass.staleFirestore", "⚠️ [LivePriceManager] Firestore CoinGecko stale - bypassing coordinator for direct poll", minInterval: 90.0)
                } else {
                    rateLimitedLog("pollMarketCoins.blocked", "⏳ [LivePriceManager] pollMarketCoins blocked by coordinator", minInterval: 120.0)
                    return
                }
            } else if isInStaleBypassGrace && !FirestoreMarketSync.shared.isCoinGeckoDataFresh {
                let elapsed = await MainActor.run { Date().timeIntervalSince(self.startupTime) }
                rateLimitedLog("pollMarketCoins.startupGrace", "🛡️ [LivePriceManager] Firestore stale but within startup grace (\(Int(30 - elapsed))s left) — deferring direct poll", minInterval: 10.0)
                return
            } else {
                // PERFORMANCE FIX: Rate-limit this log to avoid console spam
                rateLimitedLog("pollMarketCoins.blocked", "⏳ [LivePriceManager] pollMarketCoins blocked by coordinator", minInterval: 120.0)
                return
            }
        }
        
        // Periodically clean up stale sidecar entries
        await MainActor.run { self.invalidateStaleSidecarEntries() }
        
        do {
            var coins = try await CryptoAPIService.shared.fetchMarketCoins()
            rateLimitedLog("liveSource.directApi", "📡 [LivePriceManager] source=direct_api freshness=fresh count=\(coins.count)", minInterval: 20.0)
            await MainActor.run {
                self.lastSuccessfulMarketPollAt = Date()
            }

            let currentSnapshot: [MarketCoin] = await MainActor.run { self.currentCoins }

            // If the payload has obviously degraded sparklines, avoid overwriting current healthy state
            if CryptoAPIService.isDegradedSparklinePayload(coins) {
                // Try to keep prior currentCoins if they look healthy
                if !CryptoAPIService.isDegradedSparklinePayload(currentSnapshot), !currentSnapshot.isEmpty {
                    // Do not replace, just return
                    return
                }
            }

            if coins.count < 20 {
                logger.warning("⚠️ [LivePriceManager] Live poll returned thin payload (\(coins.count) coins) - keeping live-only behavior")
            }
            
            // Hard cap poll payload before any heavy merge/cache work.
            coins = capCoinsForProcessing(coins)
            
            // PRICE SANITY (first-poll safe): Even on the very first poll where currentSnapshot
            // is empty, reject obviously wrong prices for well-known coins. This catches backend
            // data bugs (e.g., BTC returning at $0.9996 from a stale/corrupt Firebase proxy cache).
            let firstPollMinPriceThresholds: [String: Double] = [
                "bitcoin": 1000, "ethereum": 50, "binancecoin": 10, "solana": 1
            ]
            for i in 0..<coins.count {
                if let threshold = firstPollMinPriceThresholds[coins[i].id],
                   let price = coins[i].priceUsd, price > 0 && price < threshold {
                    logger.warning("⚠️ [LivePriceManager] FIRST POLL: Rejected \(coins[i].id) price $\(String(format: "%.4f", price)) (below threshold $\(Int(threshold)))")
                    coins[i].priceUsd = nil  // Clear bad price, will be populated by next source
                }
            }

            // Preserve non-zero prices from previous list to avoid $0.00 flicker on rate-limited payloads
            if !currentSnapshot.isEmpty {
                var merged = coins
                // Build fast lookup by lowercase symbol
                var prevBySymbol: [String: MarketCoin] = [:]
                for c in currentSnapshot { prevBySymbol[c.symbol.lowercased()] = c }
                
                // PRICE SANITY: Minimum thresholds for well-known coins to prevent bad data propagation.
                // If the Firebase proxy or CoinGecko returns BTC at ~$1 (backend data bug),
                // reject it and keep the previous known good price.
                let minPriceThresholds: [String: Double] = [
                    "bitcoin": 1000, "ethereum": 50, "binancecoin": 10, "solana": 1
                ]
                
                // Collect updates to batch them (avoids race condition from many separate Tasks)
                var sidecar24hUpdates: [(key: String, value: Double)] = []
                var sidecar1hUpdates: [(key: String, value: Double)] = []
                
                for i in 0..<merged.count {
                    let key = merged[i].symbol.lowercased()
                    if let prev = prevBySymbol[key] {
                        // If incoming price is missing/zero, carry forward last known non-zero
                        let incoming = merged[i].priceUsd ?? 0
                        if incoming <= 0, let prevPrice = prev.priceUsd, prevPrice > 0 {
                            merged[i].priceUsd = prevPrice
                        }
                        
                        // PRICE SANITY: Reject obviously wrong prices for well-known coins
                        if let threshold = minPriceThresholds[merged[i].id],
                           let price = merged[i].priceUsd, price > 0 && price < threshold,
                           let prevPrice = prev.priceUsd, prevPrice >= threshold {
                            logger.warning("⚠️ [LivePriceManager] pollMarketCoins rejected \(merged[i].id) price $\(String(format: "%.4f", price)) — keeping $\(String(format: "%.2f", prevPrice))")
                            merged[i].priceUsd = prevPrice
                        }
                        // If incoming 1h change is missing, carry forward previous value
                        // FIX: CoinGecko API sometimes returns nil for 1h percentage even when requested.
                        // Without carry-forward, the app falls back to sparkline derivation which can be inaccurate.
                        if (merged[i].priceChangePercentage1hInCurrency == nil || merged[i].priceChangePercentage1hInCurrency?.isFinite == false), let prevCh = prev.priceChangePercentage1hInCurrency, prevCh.isFinite {
                            let clamped = max(-50.0, min(50.0, prevCh))
                            sidecar1hUpdates.append((key: key, value: clamped))
                            merged[i] = merged[i].with1hChange(clamped)
                        }
                        // If incoming 24h change is missing, carry forward previous value and update sidecar
                        if (merged[i].priceChangePercentage24hInCurrency == nil || merged[i].priceChangePercentage24hInCurrency?.isFinite == false), let prevCh = prev.priceChangePercentage24hInCurrency, prevCh.isFinite {
                            // Re-enable sidecar update: cache the previous known value for fallback
                            let clamped = max(-95.0, min(95.0, prevCh))
                            // Batch the update instead of creating a Task for each
                            sidecar24hUpdates.append((key: key, value: clamped))
                            // Also update the merged coin to carry forward the percentage
                            merged[i] = merged[i].with24hChange(clamped)
                        }
                    }
                }
                
                // Apply all sidecar updates in a single MainActor run to avoid race conditions
                if !sidecar24hUpdates.isEmpty || !sidecar1hUpdates.isEmpty {
                    await MainActor.run { [weak self, sidecar24hUpdates, sidecar1hUpdates] in
                        guard let self = self else { return }
                        for update in sidecar24hUpdates {
                            self.safeSet24hChange(update.key, update.value)
                        }
                        for update in sidecar1hUpdates {
                            self.safeSet1hChange(update.key, update.value)
                        }
                    }
                }
                
                coins = merged

                // Stabilize sparklines: prefer previous healthy sparkline unless the new one is clearly better
                if !currentSnapshot.isEmpty {
                    var stabilized = coins

                    func sparkRange(_ arr: [Double]) -> (min: Double, max: Double, span: Double) {
                        guard let mn = arr.min(), let mx = arr.max() else { return (0,0,0) }
                        return (mn, mx, mx - mn)
                    }
                    func isTooFlat(_ arr: [Double]) -> Bool {
                        let r = sparkRange(arr)
                        let denom = max(abs(r.max), 1.0)
                        return (denom == 0) ? true : (r.span / denom) < max(0.00002, 1.0 / Double(max(2000, arr.count * 2000)))
                    }

                    // Fast lookup by lowercase symbol for previous snapshot
                    var prevBySymbol: [String: MarketCoin] = [:]
                    prevBySymbol.reserveCapacity(currentSnapshot.count)
                    for c in currentSnapshot { prevBySymbol[c.symbol.lowercased()] = c }

                    for i in 0..<stabilized.count {
                        let sym = stabilized[i].symbol.lowercased()
                        guard let prev = prevBySymbol[sym] else { continue }
                        let newArr = stabilized[i].sparklineIn7d
                        let prevArr = prev.sparklineIn7d
                        // If we have no previous sparkline, nothing to stabilize
                        if prevArr.isEmpty { continue }

                        // Decide if we should keep previous sparkline
                        let keepPrev: Bool = {
                            if newArr.isEmpty { return true }
                            // If the new array is much shorter than the previous, likely degraded resolution
                            if newArr.count < Int(Double(prevArr.count) * 0.8) { return true }
                            // If the new array is suspiciously flat compared to previous, keep previous
                            if isTooFlat(newArr) && !isTooFlat(prevArr) { return true }
                            // If both have data but the new one has fewer than 7 points, keep previous
                            if newArr.count < 7 { return true }
                            return false
                        }()

                        if keepPrev {
                            // Reconstruct coin cloning previous sparkline while keeping latest numeric fields
                            let c = stabilized[i]
                            let clone = MarketCoin(
                                id: c.id,
                                symbol: c.symbol,
                                name: c.name,
                                imageUrl: c.imageUrl,
                                priceUsd: c.priceUsd,
                                marketCap: c.marketCap,
                                totalVolume: c.totalVolume,
                                priceChangePercentage1hInCurrency: c.priceChangePercentage1hInCurrency,
                                priceChangePercentage24hInCurrency: c.priceChangePercentage24hInCurrency,
                                priceChangePercentage7dInCurrency: c.priceChangePercentage7dInCurrency,
                                sparklineIn7d: prevArr,
                                marketCapRank: c.marketCapRank,
                                maxSupply: c.maxSupply,
                                circulatingSupply: c.circulatingSupply,
                                totalSupply: c.totalSupply
                            )
                            stabilized[i] = clone
                        }
                    }
                    coins = stabilized
                }
            }

            // Prefer recent direct WS prices over provider snapshots to avoid source thrash
            // Access @MainActor properties safely to prevent race conditions
            let coinsSnapshotForOverrides = coins
            let directPriceOverrides: [(index: Int, price: Double)] = await MainActor.run {
                let now = Date()
                var overrides: [(index: Int, price: Double)] = []
                for i in 0..<coinsSnapshotForOverrides.count {
                    let symLower = coinsSnapshotForOverrides[i].symbol.lowercased()
                    if let last = self.lastDirectAt[symLower], let direct = self.lastDirectPriceBySymbol[symLower], direct.isFinite, direct > 0 {
                        if now.timeIntervalSince(last) < self.directHoldoffSeconds {
                            overrides.append((index: i, price: direct))
                        } else if now.timeIntervalSince(last) < 30 {
                            let prov = coinsSnapshotForOverrides[i].priceUsd ?? 0
                            let rel = abs(direct - prov) / max(1e-9, max(abs(direct), abs(prov)))
                            if prov <= 0 || rel > 0.003 {
                                overrides.append((index: i, price: direct))
                            }
                        }
                    }
                }
                return overrides
            }
            // Apply overrides outside MainActor
            for override in directPriceOverrides {
                coins[override.index].priceUsd = override.price
            }
            
            // *** BINANCE OVERLAY: Fetch fresh 24h stats from Binance to replace stale CoinGecko percentages ***
            // Note: Filter out precious metals as Binance doesn't support them - use Coinbase for those
            do {
                let symbols = coins.prefix(100)
                    .map { $0.symbol.uppercased() }
                    .filter { !PreciousMetalsHelper.isPreciousMetal($0) }
                    .filter { Self.isValidBinanceSymbol($0) }
                if let binanceStats = try? await BinanceService.fetch24hrStats(symbols: Array(symbols)) {
                    // Build lookup by symbol
                    var binanceBySymbol: [String: CoinPrice] = [:]
                    for stat in binanceStats {
                        binanceBySymbol[stat.symbol.lowercased()] = stat
                    }
                    
                    // Overlay Binance data onto coins
                    for i in 0..<coins.count {
                        let key = coins[i].symbol.lowercased()
                        if let binance = binanceBySymbol[key] {
                            // Update price if Binance has a more recent value
                            if binance.lastPrice > 0 {
                                let currentPrice = coins[i].priceUsd ?? 0
                                // Only update if price is missing or Binance price is significantly different
                                if currentPrice <= 0 || abs(binance.lastPrice - currentPrice) / max(currentPrice, 1e-9) > 0.001 {
                                    coins[i].priceUsd = binance.lastPrice
                                }
                            }
                            
                            // Update 24h percentage from Binance (this is the key fix!)
                            if binance.change24h.isFinite {
                                let clamped = max(-95.0, min(95.0, binance.change24h))
                                coins[i] = coins[i].updating(
                                    totalVolume: binance.volume ?? coins[i].totalVolume,
                                    priceChangePercentage24hInCurrency: clamped
                                )
                            }
                        }
                    }
                }
            }

            let toSend = coins
            // Take a snapshot of current coins on the main actor for safe comparison
            let oldSnapshot: [MarketCoin] = await MainActor.run { self.currentCoins }

            let meaningful = hasMeaningfulPriceChange(old: oldSnapshot, new: toSend)
            await MainActor.run {
                let suppressDueToRecentOverlay: Bool = {
                    if let last = self.lastOverlayEmitAt { return Date().timeIntervalSince(last) < self.pollVsOverlayDebounceSeconds }
                    return false
                }()
                self.currentCoins = toSend
                // PERFORMANCE FIX v9: Skip UI updates during scroll
                let isScrolling = ScrollStateManager.shared.shouldBlockHeavyOperation()
                if meaningful && !suppressDueToRecentOverlay && !isScrolling {
                    self.emitCoins(toSend)
                    self.lastPollEmitAt = Date()
                }
            }

            // Seed/refresh the volume cache from provider-reported values on the main actor so UI reads are safe
            let precomputedVolumes: [String: Double] = {
                var dict: [String: Double] = [:]
                dict.reserveCapacity(coins.count)
                for c in coins {
                    if let v = c.totalVolume, v.isFinite, v > 0 {
                        dict[c.symbol.lowercased()] = v
                    }
                }
                return dict
            }()
            await MainActor.run { [precomputedVolumes] in
                // Merge in one shot to minimize time on the main actor and avoid re-entrancy churn
                var anyVolumeAdded = false
                for (k, v) in precomputedVolumes {
                    if latestVolumeUSDBySymbol[k] != v {
                        safeSetVolumeUSD(k, v)
                        anyVolumeAdded = true
                    }
                }
                if anyVolumeAdded { volumeCacheIsDirty = true }
            }

            let coinsSnapshotForCache = capCoinsForProcessing(coins)
            await MainActor.run {
                let now = Date()
                var cached1h = 0
                var cached24h = 0
                var cached7d = 0
                
                for c in coinsSnapshotForCache {
                    let key = c.symbol.lowercased()
                    
                    // FRESHNESS FIX: Update price source timestamp when we receive valid data from poll
                    // This ensures staleness indicator reflects actual data freshness from all sources
                    if let price = c.priceUsd, price.isFinite, price > 0 {
                        lastPriceSource[key] = .coinGecko
                        lastPriceSourceAt[key] = now
                    }
                    
                    // Track 1h change with staleness (using safe accessors to prevent crashes)
                    if let v1 = c.priceChangePercentage1hInCurrency, v1.isFinite {
                        // Drop absurd 1h values and clamp to a sane band before caching
                        if abs(v1) <= 50 {
                            let prev1h = safeGet1hChange(key)
                            let hasChanged1h = (prev1h == nil) || (abs((prev1h ?? 0) - v1) > 0.01)
                            if hasChanged1h {
                                last1hChangeUpdatedAt[key] = now
                            }
                            safeSet1hChange(key, v1)
                            cached1h += 1
                        }
                    }
                    
                    // Track 24h change with staleness (using safe accessors to prevent crashes)
                    if let v24 = c.priceChangePercentage24hInCurrency, v24.isFinite {
                        // Clamp to ±95% to avoid polluting the sidecar with extreme spikes
                        let clamped = max(-95.0, min(95.0, v24))
                        
                        // Track staleness: update timestamp only when value actually changes
                        let prevVal = previousProviderValue24h[key]
                        let hasChanged = (prevVal == nil) || (abs((prevVal ?? 0) - clamped) > 0.01)
                        if hasChanged {
                            last24hChangeUpdatedAt[key] = now
                            previousProviderValue24h[key] = clamped
                        }
                        
                        safeSet24hChange(key, clamped)
                        cached24h += 1
                    }
                    
                    // Track 7d change with staleness (using safe accessors to prevent crashes)
                    if let v7d = c.priceChangePercentage7dInCurrency, v7d.isFinite {
                        let clamped7d = max(-95.0, min(95.0, v7d))
                        let prev7d = safeGet7dChange(key)
                        let hasChanged7d = (prev7d == nil) || (abs((prev7d ?? 0) - clamped7d) > 0.1)
                        if hasChanged7d {
                            last7dChangeUpdatedAt[key] = now
                        }
                        safeSet7dChange(key, clamped7d)
                        cached7d += 1
                    }
                }
                
                // DIAGNOSTIC: Log percent cache updates (rate-limited to reduce console noise)
                if cached1h > 0 || cached24h > 0 {
                    self.rateLimitedLog("percentCacheUpdate", "📊 [LivePriceManager] Cached percentages: 1h=\(cached1h), 24h=\(cached24h), 7d=\(cached7d) from \(coinsSnapshotForCache.count) coins", minInterval: 60)
                }
                
                self.schedulePercentSidecarSave()
            }
            
            // Derive and cache Rank/Max Supply for coins when provider omits them
            func bestCap(_ c: MarketCoin) -> Double {
                if let cap = c.marketCap, cap.isFinite, cap > 0 { return cap }
                if let p = c.priceUsd, p.isFinite, p > 0 {
                    if let circ = c.circulatingSupply, circ.isFinite, circ > 0 {
                        let v = p * circ; if v.isFinite, v > 0 { return v }
                    }
                    if let total = c.totalSupply, total.isFinite, total > 0 {
                        let v = p * total; if v.isFinite, v > 0 { return v }
                    }
                    if let maxS = c.maxSupply, maxS.isFinite, maxS > 0 {
                        let v = p * maxS; if v.isFinite, v > 0 { return v }
                    }
                }
                return 0
            }

            var rankMap: [String: Int] = [:]
            let sortedByCap = coins.sorted { bestCap($0) > bestCap($1) }
            for (idx, c) in sortedByCap.enumerated() {
                if (c.marketCapRank ?? 0) <= 0 { rankMap[c.id] = idx + 1 }
            }

            var maxSupplyMap: [String: Double] = [:]
            for c in coins {
                if let ms = c.maxSupply, ms.isFinite, ms > 0 {
                    // keep provider value
                } else if let derived = (c.totalSupply ?? c.circulatingSupply), derived.isFinite, derived > 0 {
                    maxSupplyMap[c.id] = derived
                }
            }
            let rankMapSnapshot = rankMap
            let maxSupplyMapSnapshot = maxSupplyMap
            await MainActor.run {
                self.derivedRankByID = rankMapSnapshot
                self.derivedMaxSupplyByID = maxSupplyMapSnapshot
            }
            
            saveCoinsCacheCapped(toSend)  // MEMORY FIX v5: Cap before disk save
        } catch {
            logger.error("❌ [LivePriceManager] pollMarketCoins live fetch failed: \(error.localizedDescription)")
        }
    }

    // Ensure we have a reasonably fresh set of Binance-supported base assets
    private func ensureBinanceSupportedBases() async {
        // Try loading from cache if empty
        let basesEmpty = await MainActor.run { self.binanceSupportedBases.isEmpty }
        if basesEmpty,
           let cached: [String] = CacheManager.shared.load([String].self, from: "binance_supported_bases.json"),
           !cached.isEmpty {
            await MainActor.run { self.binanceSupportedBases = Set(cached.map { $0.uppercased() }) }
        }
        // Check staleness
        let lastRefresh = await MainActor.run { self.binanceSupportedBasesLastRefresh }
        let shouldRefresh: Bool = {
            guard let last = lastRefresh else { return true }
            return Date().timeIntervalSince(last) > binanceSupportedBasesRefreshInterval
        }()
        // If we already have bases and they are fresh enough, nothing to do
        let haveBases = await MainActor.run { !self.binanceSupportedBases.isEmpty }
        if haveBases && !shouldRefresh { return }

        // Kick a background refresh if not already in progress; do not await
        let started = await basesGate.tryStart()
        guard started else { return }
        Task { [weak self] in
            defer { Task { await self?.basesGate.finish() } }
            await self?.refreshBinanceSupportedBases()
        }
    }

    // Fetch exchangeInfo from Binance(.com/.us) and build the supported base set
    private func refreshBinanceSupportedBases() async {
        do {
            let endpoints = await ExchangeHostPolicy.shared.currentEndpoints()
            func buildURL(from base: URL) -> URL? {
                var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
                components?.path = (base.path.hasSuffix("/") ? String(base.path.dropLast()) : base.path) + "/exchangeInfo"
                return components?.url
            }
            guard let initial = buildURL(from: endpoints.restBase) else { return }

            let (data, _) = try await ExchangeHTTP.getWithPolicyFallback(
                initial: initial,
                session: URLSession.shared,
                buildFromEndpoints: { eps in buildURL(from: eps.restBase)! }
            )

            // Parse minimal fields from exchangeInfo
            var bases: Set<String> = []
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let symbols = obj["symbols"] as? [[String: Any]] {
                for sym in symbols {
                    guard let status = sym["status"] as? String, status == "TRADING" else { continue }
                    guard let base = (sym["baseAsset"] as? String)?.uppercased(), !base.isEmpty else { continue }
                    guard let quote = (sym["quoteAsset"] as? String)?.uppercased(), self.binanceCommonQuotes.contains(quote) else { continue }
                    bases.insert(base)
                }
            }
            if !bases.isEmpty {
                let basesSnapshot = bases
                await MainActor.run {
                    self.binanceSupportedBases = basesSnapshot
                    self.binanceSupportedBasesLastRefresh = Date()
                }
                CacheManager.shared.save(Array(bases).sorted(), to: "binance_supported_bases.json")
                logger.info("ℹ️ [LivePriceManager] Refreshed Binance supported bases count=\(bases.count)")
            }
        } catch {
            logger.error("❌ [LivePriceManager] refreshBinanceSupportedBases failed: \(error.localizedDescription)")
        }
    }

    private func binanceTickerPrice(for pair: String) async -> Double? {
        let endpoints = await ExchangeHostPolicy.shared.currentEndpoints()
        func buildURL(from base: URL) -> URL? {
            var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
            components?.path = (base.path.hasSuffix("/") ? String(base.path.dropLast()) : base.path) + "/ticker/price"
            components?.queryItems = [URLQueryItem(name: "symbol", value: pair)]
            return components?.url
        }
        guard let initial = buildURL(from: endpoints.restBase) else { return nil }
        do {
            let (data, _) = try await ExchangeHTTP.getWithPolicyFallback(
                initial: initial,
                session: URLSession.shared,
                buildFromEndpoints: { eps in buildURL(from: eps.restBase)! }
            )
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let priceStr = obj["price"] as? String,
               let val = Double(priceStr), val > 0 {
                return val
            }
        } catch {
            // ignore and return nil
        }
        return nil
    }

    private func binanceTickerPriceForBestQuote(base: String, preferredQuotes: [String]? = nil) async -> Double? {
        let endpoints = await ExchangeHostPolicy.shared.currentEndpoints()
        // Changed line as per instructions:
        let host = endpoints.restBase.host?.lowercased() ?? ""
        let defaultQuotes: [String] = host.contains("binance.us") ? ["USD","USDT","USDC"] : ["USDT","FDUSD","BUSD","USDC","USD"]
        let quotes = preferredQuotes ?? defaultQuotes
        for (index, q) in quotes.enumerated() {
            // PERFORMANCE FIX: Add small delay between quote attempts to avoid rapid request storms
            if index > 0 {
                try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms between attempts
            }
            let pair = base.uppercased() + q
            if let val = await binanceTickerPrice(for: pair), val.isFinite, val > 0 {
                return val
            }
        }
        return nil
    }

    private func coinbaseTickerPrice(for base: String) async -> Double? {
        let pair = base.uppercased() + "-USD"
        guard let url = URL(string: "https://api.exchange.coinbase.com/products/\(pair)/ticker") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let priceStr = obj["price"] as? String,
               let val = Double(priceStr), val > 0 {
                return val
            }
        } catch {
            // QUALITY FIX: Log network errors for debugging (silent failures are hard to diagnose)
            #if DEBUG
            print("[LivePriceManager] coinbaseTickerPrice error for \(pair): \(error.localizedDescription)")
            #endif
        }
        return nil
    }
    
    // MARK: - Binance 1h Change Derivation
    
    /// Cache for Binance 1h change fetches to avoid repeated API calls
    private actor Binance1hFetchGate {
        private var inFlight: Set<String> = []
        private var lastAttempt: [String: Date] = [:]
        private var cachedResults: [String: Double] = [:]
        private let cooldown: TimeInterval = 60 // 1 minute cooldown between retries
        private let cacheExpiry: TimeInterval = 120 // 2 minutes cache expiry
        
        func shouldFetch(_ symbol: String) -> Bool {
            if inFlight.contains(symbol) { return false }
            if let last = lastAttempt[symbol], Date().timeIntervalSince(last) < cooldown { return false }
            return true
        }
        
        func startFetch(_ symbol: String) {
            inFlight.insert(symbol)
            lastAttempt[symbol] = Date()
        }
        
        func finishFetch(_ symbol: String, result: Double?) {
            inFlight.remove(symbol)
            if let r = result, r.isFinite {
                cachedResults[symbol] = r
            }
        }
        
        func getCached(_ symbol: String) -> Double? {
            guard let last = lastAttempt[symbol],
                  Date().timeIntervalSince(last) < cacheExpiry,
                  let result = cachedResults[symbol],
                  result.isFinite else { return nil }
            return result
        }
    }
    private let binance1hGate = Binance1hFetchGate()
    
    /// Fetches the 1-hour percentage change from Binance klines API.
    /// Uses 1-minute candles over the last 65 minutes to calculate the change.
    /// Returns nil if the fetch fails or the symbol is not available on Binance.
    func fetchBinance1hChange(symbol: String) async -> Double? {
        let upperSymbol = symbol.uppercased()
        
        // Check if blocked
        if binanceOverlayBlocklist.contains(upperSymbol) { return nil }
        
        // Check cache first
        if let cached = await binance1hGate.getCached(upperSymbol) {
            return cached
        }
        
        // Check if we should fetch
        guard await binance1hGate.shouldFetch(upperSymbol) else { return nil }
        await binance1hGate.startFetch(upperSymbol)
        
        defer {
            Task { await self.binance1hGate.finishFetch(upperSymbol, result: nil) }
        }
        
        // Build trading pair variants to try
        let pairsToTry: [String]
        if upperSymbol.hasSuffix("USDT") || upperSymbol.hasSuffix("USD") || upperSymbol.hasSuffix("USDC") {
            pairsToTry = [upperSymbol]
        } else {
            pairsToTry = [upperSymbol + "USDT", upperSymbol + "FDUSD", upperSymbol + "USD"]
        }
        
        // Binance endpoints to try (Binance.US is shut down - use global mirrors only)
        let endpoints = [
            "https://api.binance.com/api/v3/klines",
            "https://api1.binance.com/api/v3/klines",
            "https://api4.binance.com/api/v3/klines"
        ]
        
        for pair in pairsToTry {
            for endpoint in endpoints {
                guard var components = URLComponents(string: endpoint) else { continue }
                // Fetch 65 1-minute candles (to cover 1 hour + buffer)
                components.queryItems = [
                    URLQueryItem(name: "symbol", value: pair),
                    URLQueryItem(name: "interval", value: "1m"),
                    URLQueryItem(name: "limit", value: "65")
                ]
                guard let url = components.url else { continue }
                
                do {
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 8
                    let (data, response) = try await URLSession.shared.data(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else { continue }
                    
                    guard let json = try JSONSerialization.jsonObject(with: data) as? [[Any]] else { continue }
                    guard json.count >= 60 else { continue } // Need at least 60 candles for 1h
                    
                    // Binance klines format: [open_time, open, high, low, close, volume, close_time, ...]
                    // Get the close price from 60 minutes ago (index 0) and the latest close (last element)
                    let indexForOneHourAgo = max(0, json.count - 61)
                    
                    func parseClose(_ arr: [Any]) -> Double? {
                        guard arr.count > 4 else { return nil }
                        if let s = arr[4] as? String, let v = Double(s), v > 0 { return v }
                        if let v = arr[4] as? Double, v > 0 { return v }
                        return nil
                    }
                    
                    guard let priceOneHourAgo = parseClose(json[indexForOneHourAgo]),
                          let currentPrice = parseClose(json[json.count - 1]),
                          priceOneHourAgo > 0, currentPrice > 0 else { continue }
                    
                    let percentChange = ((currentPrice / priceOneHourAgo) - 1.0) * 100.0
                    
                    guard percentChange.isFinite, abs(percentChange) <= 100 else { continue }
                    
                    // Cache and return the result
                    Task { await self.binance1hGate.finishFetch(upperSymbol, result: percentChange) }
                    return percentChange
                } catch {
                    continue
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Binance 24h Change Fetch
    
    /// Cache for Binance 24h change fetches
    private actor Binance24hFetchGate {
        private var inFlight: Set<String> = []
        private var lastAttempt: [String: Date] = [:]
        private var cachedResults: [String: Double] = [:]
        private let cooldown: TimeInterval = 30 // 30 second cooldown between retries (shorter than 1h)
        private let cacheExpiry: TimeInterval = 60 // 1 minute cache expiry (24h changes less frequently)
        
        func shouldFetch(_ symbol: String) -> Bool {
            if inFlight.contains(symbol) { return false }
            if let last = lastAttempt[symbol], Date().timeIntervalSince(last) < cooldown { return false }
            return true
        }
        
        func startFetch(_ symbol: String) {
            inFlight.insert(symbol)
            lastAttempt[symbol] = Date()
        }
        
        func finishFetch(_ symbol: String, result: Double?) {
            inFlight.remove(symbol)
            if let r = result, r.isFinite {
                cachedResults[symbol] = r
            }
        }
        
        func getCached(_ symbol: String) -> Double? {
            guard let last = lastAttempt[symbol],
                  Date().timeIntervalSince(last) < cacheExpiry,
                  let result = cachedResults[symbol],
                  result.isFinite else { return nil }
            return result
        }
    }
    private let binance24hGate = Binance24hFetchGate()
    
    /// Fetches the 24-hour percentage change from Binance 24hr ticker API.
    /// This is a direct fetch that returns the priceChangePercent from the ticker.
    /// Returns nil if the fetch fails or the symbol is not available on Binance.
    /// Validates that a symbol is plausibly a Binance trading pair base.
    /// Filters out tokens like PC0000031, BUIDL, FDIT that will never exist on Binance.
    private static func isValidBinanceSymbol(_ symbol: String) -> Bool {
        let s = symbol.uppercased()
        // Must be 2-10 characters (Binance symbols are short)
        guard s.count >= 2, s.count <= 10 else { return false }
        // Must be purely alphabetic (no numbers, hyphens, etc.)
        guard s.allSatisfy({ $0.isLetter }) else { return false }
        return true
    }
    
    func fetchBinance24hChange(symbol: String) async -> Double? {
        let upperSymbol = symbol.uppercased()
        
        // Check if blocked
        if binanceOverlayBlocklist.contains(upperSymbol) { return nil }
        
        // Filter invalid symbols that will never exist on Binance (e.g., PC0000031, BUIDL)
        if !Self.isValidBinanceSymbol(upperSymbol) { return nil }
        
        // PERFORMANCE FIX v25: Early-exit when Binance is geo-blocked.
        // When the user is in a geo-blocked region (HTTP 451), ALL direct Binance endpoints
        // (api.binance.com, api4.binance.com, api1.binance.com) are unreachable.
        // Without this guard, the app fires 100+ individual per-symbol requests that each
        // hang for 8 seconds before timing out, saturating the URL session connection pool
        // and starving legitimate requests (charts, order book, Firebase proxies).
        // The geo-block flag is set by BinanceService.markGeoBlocked() and persisted to disk.
        if UserDefaults.standard.bool(forKey: "BinanceGlobalGeoBlocked") {
            return nil
        }
        
        // Check cache first
        if let cached = await binance24hGate.getCached(upperSymbol) {
            return cached
        }
        
        // Check if we should fetch
        guard await binance24hGate.shouldFetch(upperSymbol) else { return nil }
        await binance24hGate.startFetch(upperSymbol)
        
        // Build trading pair variants to try
        let pairsToTry: [String]
        if upperSymbol.hasSuffix("USDT") || upperSymbol.hasSuffix("USD") || upperSymbol.hasSuffix("USDC") {
            pairsToTry = [upperSymbol]
        } else {
            pairsToTry = [upperSymbol + "USDT", upperSymbol + "FDUSD", upperSymbol + "USD"]
        }
        
        let endpoints = await ExchangeHostPolicy.shared.currentEndpoints()
        
        for pair in pairsToTry {
            var components = URLComponents(url: endpoints.restBase, resolvingAgainstBaseURL: false)
            let basePath = endpoints.restBase.path
            components?.path = (basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath) + "/ticker/24hr"
            components?.queryItems = [URLQueryItem(name: "symbol", value: pair)]
            
            guard let url = components?.url else { continue }
            
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 8
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else { continue }
                
                // PERFORMANCE FIX v25: Detect geo-blocking on individual requests too
                // and short-circuit all future attempts
                if httpResponse.statusCode == 451 {
                    UserDefaults.standard.set(true, forKey: "BinanceGlobalGeoBlocked")
                    Task { await self.binance24hGate.finishFetch(upperSymbol, result: nil) }
                    return nil
                }
                
                guard httpResponse.statusCode == 200 else { continue }
                
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                
                // Extract priceChangePercent from the 24hr ticker response
                var percentChange: Double?
                if let pctStr = json["priceChangePercent"] as? String, let pct = Double(pctStr) {
                    percentChange = pct
                } else if let pct = json["priceChangePercent"] as? Double {
                    percentChange = pct
                }
                
                // CONSISTENCY FIX: Use ±300% limit to match display layer clamp
                if let pct = percentChange, pct.isFinite, abs(pct) <= 300 {
                    // Cache and return the result
                    Task { await self.binance24hGate.finishFetch(upperSymbol, result: pct) }
                    return pct
                }
            } catch {
                continue
            }
        }
        
        // Try fallback endpoints if primary failed (Binance.US is shut down - use global mirrors only)
        // PERFORMANCE FIX v25: Skip fallbacks too when geo-blocked (re-check in case first attempt set the flag)
        if UserDefaults.standard.bool(forKey: "BinanceGlobalGeoBlocked") {
            Task { await self.binance24hGate.finishFetch(upperSymbol, result: nil) }
            return nil
        }
        
        let fallbackEndpoints = [
            "https://api.binance.com/api/v3/ticker/24hr",
            "https://api1.binance.com/api/v3/ticker/24hr"
        ]
        
        for pair in pairsToTry {
            for endpoint in fallbackEndpoints {
                guard var components = URLComponents(string: endpoint) else { continue }
                components.queryItems = [URLQueryItem(name: "symbol", value: pair)]
                guard let url = components.url else { continue }
                
                do {
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 8
                    let (data, response) = try await URLSession.shared.data(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse else { continue }
                    
                    // PERFORMANCE FIX v25: Detect geo-blocking on fallback endpoints
                    if httpResponse.statusCode == 451 {
                        UserDefaults.standard.set(true, forKey: "BinanceGlobalGeoBlocked")
                        Task { await self.binance24hGate.finishFetch(upperSymbol, result: nil) }
                        return nil
                    }
                    
                    guard httpResponse.statusCode == 200 else { continue }
                    
                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                    
                    var percentChange: Double?
                    if let pctStr = json["priceChangePercent"] as? String, let pct = Double(pctStr) {
                        percentChange = pct
                    } else if let pct = json["priceChangePercent"] as? Double {
                        percentChange = pct
                    }
                    
                    // CONSISTENCY FIX: Use ±300% limit to match display layer clamp
                    if let pct = percentChange, pct.isFinite, abs(pct) <= 300 {
                        Task { await self.binance24hGate.finishFetch(upperSymbol, result: pct) }
                        return pct
                    }
                } catch {
                    continue
                }
            }
        }
        
        Task { await self.binance24hGate.finishFetch(upperSymbol, result: nil) }
        return nil
    }
    
    /// Fetch prices for multiple symbols from Coinbase in parallel
    /// Used as fallback when Binance is blocked or degraded
    private func fetchCoinbaseBatchPrices(symbols: [String]) async -> [String: Double] {
        // FIX: Check APIRequestCoordinator before making Coinbase batch requests
        // This prevents flooding Coinbase when used as fallback for Binance failures
        guard APIRequestCoordinator.shared.canMakeRequest(for: .coinbase) else {
            #if DEBUG
            print("[LivePriceManager] fetchCoinbaseBatchPrices blocked by coordinator")
            #endif
            return [:]
        }
        APIRequestCoordinator.shared.recordRequest(for: .coinbase)
        
        // Coinbase doesn't have a batch ticker endpoint, so we fetch in parallel with rate limiting
        // FIX: Reduced max concurrent from 10 to 5 to prevent connection flooding
        let maxConcurrent = 5
        let chunks = stride(from: 0, to: symbols.count, by: maxConcurrent).map {
            Array(symbols[$0..<min($0 + maxConcurrent, symbols.count)])
        }
        
        var results: [String: Double] = [:]
        
        for chunk in chunks {
            // FIX: Re-check coordinator for each chunk to respect rate limits
            guard APIRequestCoordinator.shared.canMakeRequest(for: .coinbase) else {
                break  // Stop if rate limited
            }
            
            await withTaskGroup(of: (String, Double?).self) { group in
                for symbol in chunk {
                    group.addTask {
                        let price = await self.coinbaseTickerPrice(for: symbol)
                        return (symbol.lowercased(), price)
                    }
                }
                
                for await (symbol, price) in group {
                    if let p = price, p > 0 {
                        results[symbol] = p
                    }
                }
            }
            
            // FIX: Increased delay between chunks from 100ms to 500ms
            if chunks.count > 1 {
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            }
        }
        
        return results
    }

    // Fetch 24h ticker for a specific pair and return quoteVolume (treated as USD-equivalent for USD/USDT/USDC/BUSD quotes)
    private func binanceTicker24hrVolume(for pair: String) async -> Double? {
        // PERFORMANCE FIX v25: Skip when Binance is geo-blocked to avoid timeout floods
        if UserDefaults.standard.bool(forKey: "BinanceGlobalGeoBlocked") { return nil }
        
        let endpoints = await ExchangeHostPolicy.shared.currentEndpoints()
        func buildURL(from base: URL) -> URL? {
            var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
            components?.path = (base.path.hasSuffix("/") ? String(base.path.dropLast()) : base.path) + "/ticker/24hr"
            components?.queryItems = [URLQueryItem(name: "symbol", value: pair)]
            return components?.url
        }
        guard let initial = buildURL(from: endpoints.restBase) else { return nil }
        do {
            let (data, _) = try await ExchangeHTTP.getWithPolicyFallback(
                initial: initial,
                session: URLSession.shared,
                // SAFETY FIX: Guard against nil URL in fallback builder
                buildFromEndpoints: { eps in buildURL(from: eps.restBase) ?? initial }
            )
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let qvStr = obj["quoteVolume"] as? String, let qv = Double(qvStr), qv > 0 { return qv }
                if let qvNum = obj["quoteVolume"] as? Double, qvNum > 0 { return qvNum }
            }
        } catch {
            // PERFORMANCE FIX v17: Removed per-pair error logging to reduce console spam
            // These errors are expected for coins that don't exist on Binance
            // The "Marked X as invalid" summary message is sufficient feedback
        }
        return nil
    }

    // Pick the best available USD-like quote for 24h volume on Binance and return the quoteVolume
    private func binanceTicker24hrVolumeUSDForBestQuote(base: String, preferredQuotes: [String]? = nil) async -> Double? {
        let baseUpper = base.uppercased()
        
        // PERFORMANCE FIX: Check if this symbol is known to be invalid
        // Clear old invalid entries periodically
        let invalidCheck = await MainActor.run { () -> (isInvalid: Bool, supportedBases: Set<String>) in
            // Periodically clear invalid cache (every hour)
            if Date().timeIntervalSince(binanceInvalidBasesLastClear) > binanceInvalidBasesMaxAge {
                binanceInvalidBases.removeAll()
                binanceInvalidBasesLastClear = Date()
            }
            return (binanceInvalidBases.contains(baseUpper), binanceSupportedBases)
        }
        
        // Skip if already known to be invalid
        if invalidCheck.isInvalid {
            return nil
        }
        
        // PERFORMANCE FIX: Check against known supported bases if available
        // If we have the supported bases list and this symbol is not in it, skip immediately
        if !invalidCheck.supportedBases.isEmpty && !invalidCheck.supportedBases.contains(baseUpper) {
            // Mark as invalid to avoid future checks
            _ = await MainActor.run { binanceInvalidBases.insert(baseUpper) }
            // NOTE: Log message removed to reduce console spam
            // These are expected for wrapped tokens (WBTC, WETH, etc.) and stablecoins
            return nil
        }
        
        let endpoints = await ExchangeHostPolicy.shared.currentEndpoints()
        let host = endpoints.restBase.host?.lowercased() ?? ""
        let defaultQuotes: [String] = host.contains("binance.us") ? ["USD","USDT","USDC"] : ["USDT","FDUSD","BUSD","USDC","USD"]
        let quotes = preferredQuotes ?? defaultQuotes
        
        var hadAnyError = false
        for (index, q) in quotes.enumerated() {
            // PERFORMANCE FIX: Add small delay between quote attempts to avoid rapid request storms
            // Skip delay for first attempt
            if index > 0 {
                try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms between attempts
            }
            let pair = baseUpper + q
            if let vol = await binanceTicker24hrVolume(for: pair), vol.isFinite, vol > 0 {
                return vol
            }
            hadAnyError = true // At least one attempt failed or returned no data
        }
        
        // PERFORMANCE FIX: If all quote currencies failed, mark this base as invalid
        // This prevents 5+ network requests per symbol on future attempts
        if hadAnyError {
            await MainActor.run {
                binanceInvalidBases.insert(baseUpper)
                binanceInvalidBasesLoggedThisSession += 1
                #if DEBUG
                // PERFORMANCE FIX v17: Only log summary every 10 invalids to reduce spam
                if binanceInvalidBasesLoggedThisSession == 1 {
                    print("[LivePriceManager] Marking coins as invalid on Binance (expected for wrapped/venue-specific tokens)...")
                } else if binanceInvalidBasesLoggedThisSession % 10 == 0 {
                    print("[LivePriceManager] \(binanceInvalidBasesLoggedThisSession) coins marked invalid on Binance this session")
                }
                #endif
            }
        }
        
        return nil
    }
    
    // Rate limiting for Coinbase fallback logs (prevent console spam)
    private var lastCoinbaseFallbackLogAt: Date = .distantPast
    private let coinbaseFallbackLogMinInterval: TimeInterval = 120 // Log at most every 2 minutes
    
    /// Overlay prices using Firebase proxy (shared cache across all users)
    /// Returns true if overlay was successfully applied, false if Firebase unavailable or failed
    @MainActor
    private func overlayWithFirebaseProxy(snapshot: [MarketCoin]) async throws -> Bool {
        guard FirebaseService.shared.isConfigured else { return false }
        guard !snapshot.isEmpty else { return false }
        
        // Collect symbols for the Firebase request
        let stableLower: Set<String> = Set(MarketCoin.stableSymbols.map { $0.lowercased() })
        let eligibleSymbols = snapshot
            .filter { !stableLower.contains($0.symbol.lowercased()) }
            .filter { Self.isValidBinanceSymbol($0.symbol) } // Filter invalid symbols
            .map { $0.symbol.uppercased() + "USDT" }
            .prefix(100) // Limit to 100 symbols to avoid huge requests
        
        guard !eligibleSymbols.isEmpty else { return false }
        
        // Fetch from Firebase proxy (cached for 30 seconds across all users)
        let tickers = try await FirebaseService.shared.getParsedBinanceTickers(symbols: Array(eligibleSymbols))
        
        guard !tickers.isEmpty else { return false }
        
        // Build lookup by base symbol
        var tickerBySymbol: [String: BinanceTicker] = [:]
        for ticker in tickers {
            let sUpper = ticker.symbol.uppercased()
            tickerBySymbol[sUpper.lowercased()] = ticker
            // Map BTCUSDT -> BTC
            let commonQuotes = ["USDT", "USD", "BUSD", "USDC"]
            for q in commonQuotes where sUpper.hasSuffix(q) {
                let base = String(sUpper.dropLast(q.count))
                if !base.isEmpty { tickerBySymbol[base.lowercased()] = ticker }
            }
        }
        
        guard !tickerBySymbol.isEmpty else { return false }
        
        // Apply overlay to current coins
        var coins = snapshot
        var anyChanged = false
        
        for i in 0..<coins.count {
            let symLower = coins[i].symbol.lowercased()
            if let ticker = tickerBySymbol[symLower] {
                let old = coins[i]
                var changed = false
                
                // FRESHNESS FIX: Always update timestamp when we receive valid ticker data
                // This indicates "we received fresh data" regardless of whether price changed significantly
                // Prevents false staleness indicators when prices are stable
                if ticker.lastPrice.isFinite && ticker.lastPrice > 0 {
                    lastPriceSource[symLower] = .binance
                    lastPriceSourceAt[symLower] = Date()
                }
                
                // Update price if significantly different
                if canApplyProviderPrice(symLower: symLower, candidate: ticker.lastPrice, old: old.priceUsd) {
                    coins[i].priceUsd = ticker.lastPrice
                    lastProviderApplyAt[symLower] = Date()
                    changed = true
                }
                
                // STALE DATA FIX: Always apply fresh 24h% from Firebase proxy, not just when nil.
                // Cached coins may have stale percentages that need overwriting with live data.
                if ticker.priceChangePercent.isFinite {
                    let c = coins[i]
                    coins[i] = MarketCoin(
                        id: c.id,
                        symbol: c.symbol,
                        name: c.name,
                        imageUrl: c.imageUrl,
                        priceUsd: c.priceUsd,
                        marketCap: c.marketCap,
                        totalVolume: c.totalVolume,
                        priceChangePercentage1hInCurrency: c.priceChangePercentage1hInCurrency,
                        priceChangePercentage24hInCurrency: ticker.priceChangePercent,
                        priceChangePercentage7dInCurrency: c.priceChangePercentage7dInCurrency,
                        sparklineIn7d: c.sparklineIn7d,
                        marketCapRank: c.marketCapRank,
                        maxSupply: c.maxSupply,
                        circulatingSupply: c.circulatingSupply,
                        totalSupply: c.totalSupply
                    )
                    safeSet24hChange(symLower, ticker.priceChangePercent)
                    changed = true
                }
                
                if changed { anyChanged = true }
            }
        }
        
        // Emit updated coins if any changed
        if anyChanged {
            currentCoins = coins
            emitCoins(coins)
            lastOverlayEmitAt = Date()
        }
        
        return true
    }
    
    /// Overlay prices using Coinbase when Binance is blocked
    /// Called in degraded mode to maintain price updates
    private func overlayWithCoinbaseFallback(snapshot: [MarketCoin]) async {
        guard !snapshot.isEmpty else { return }
        
        // Collect non-stable symbols for price updates
        let stableLower: Set<String> = Set(MarketCoin.stableSymbols.map { $0.lowercased() })
        let eligibleSymbols = snapshot
            .filter { !stableLower.contains($0.symbol.lowercased()) }
            .prefix(20) // Limit to avoid hammering Coinbase
            .map { $0.symbol.uppercased() }
        
        guard !eligibleSymbols.isEmpty else { return }
        
        // Rate-limit informational logs to reduce console spam
        let now = Date()
        if now.timeIntervalSince(lastCoinbaseFallbackLogAt) >= coinbaseFallbackLogMinInterval {
            logger.info("ℹ️ [LivePriceManager] Using Coinbase fallback for \(eligibleSymbols.count) symbols")
            lastCoinbaseFallbackLogAt = now
        }
        
        // Fetch prices from Coinbase
        let coinbasePrices = await fetchCoinbaseBatchPrices(symbols: eligibleSymbols)
        
        guard !coinbasePrices.isEmpty else {
            // Only log no-prices warning occasionally
            if now.timeIntervalSince(lastCoinbaseFallbackLogAt) >= coinbaseFallbackLogMinInterval {
                logger.info("⚠️ [LivePriceManager] Coinbase fallback returned no prices")
            }
            return
        }
        
        let updatedSnapshot = snapshot
        
        // Apply price updates on MainActor to safely access @MainActor properties
        let (updatedResult, anyChange) = await MainActor.run { [self, coinbasePrices] () -> ([MarketCoin], Bool) in
            var mutableUpdated = updatedSnapshot
            var changed = false
            for i in 0..<mutableUpdated.count {
                let symLower = mutableUpdated[i].symbol.lowercased()
                if let price = coinbasePrices[symLower] {
                    // FRESHNESS FIX: Always update timestamp when we receive valid price data
                    // This indicates "we received fresh data" regardless of whether price changed significantly
                    if price.isFinite && price > 0 {
                        self.lastPriceSource[symLower] = .coinbase
                        self.lastPriceSourceAt[symLower] = Date()
                    }
                    
                    if self.canApplyProviderPrice(symLower: symLower, candidate: price, old: mutableUpdated[i].priceUsd) {
                        mutableUpdated[i].priceUsd = price
                        self.lastProviderApplyAt[symLower] = Date()
                        changed = true
                    }
                }
            }
            return (mutableUpdated, changed)
        }
        
        if anyChange {
            let toSend = updatedResult
            let oldSnapshot: [MarketCoin] = await MainActor.run { self.currentCoins }
            let meaningful = hasMeaningfulPriceChange(old: oldSnapshot, new: toSend)
            await MainActor.run {
                let suppressDueToRecentPoll: Bool = {
                    if let last = self.lastPollEmitAt { return Date().timeIntervalSince(last) < self.pollVsOverlayDebounceSeconds }
                    return false
                }()
                self.currentCoins = toSend
                if meaningful && !suppressDueToRecentPoll {
                    self.emitCoins(toSend)
                    self.lastOverlayEmitAt = Date()
                }
            }
            saveCoinsCacheCapped(toSend)  // MEMORY FIX v5: Cap before disk save
            // Rate-limit success logs
            if now.timeIntervalSince(lastCoinbaseFallbackLogAt) >= coinbaseFallbackLogMinInterval {
                logger.info("✅ [LivePriceManager] Coinbase fallback updated \(coinbasePrices.count) prices")
            }
        }
    }

    // Start a secondary timer to overlay live prices using Binance 24h ticker
    // CRASH FIX: Made @MainActor since it accesses @MainActor overlay interval properties
    @MainActor
    private func startPriceOverlayTimer() {
        priceTimerCancellable?.cancel()
        // PERFORMANCE FIX: Increased minimum from 10s to 30s to reduce scroll jank
        let interval = max(30, max(overlayBaseIntervalSeconds, min(overlayIntervalSeconds, overlayMaxIntervalSeconds)))
        // PERFORMANCE FIX v20: Changed from .common to .default so the timer pauses during scroll.
        // The overlay function already had a scroll-blocking check, but firing the timer
        // during scroll created unnecessary Task objects that immediately returned.
        priceTimerCancellable = Timer
            .publish(every: interval, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                _ = Task { await self?.overlayLivePrices() }
            }
    }

    // STALE DATA FIX: Track if first overlay has run to bypass coordinator on startup
    @MainActor private var hasRunFirstOverlay: Bool = false
    
    // Fetch live prices for the current coin symbols and overlay onto currentCoins
    // CRASH FIX: Made @MainActor to safely access all @MainActor properties
    @MainActor
    private func overlayLivePrices() async {
        // MEMORY FIX v13: Block overlay processing during memory emergency.
        // In-flight Binance Cloud Function responses can still arrive after emergency stop.
        // Processing them creates new MarketCoin objects and calls emitCoins(), which would
        // trigger objectWillChange cascades.
        if MarketViewModel.shared.isMemoryEmergency { return }
        
        // PERFORMANCE FIX: Skip overlay during scroll to prevent scroll jank
        // Heavy API calls and data processing compete with scroll rendering for CPU time
        if ScrollStateManager.shared.shouldBlockHeavyOperation() {
            return
        }
        
        // FIX v23: Skip overlay when Firestore real-time listener is providing fresh data.
        // Firestore listeners deliver the SAME Binance ticker data that the overlay fetches,
        // so running both is redundant and doubles the emission/processing pipeline work.
        // Only fall back to overlay when Firestore data is stale (>90s old).
        let firestoreFresh = FirestoreMarketSync.shared.isDataFresh
        if !firestoreFresh {
            let allowStaleKick = shouldRunStaleRecoveryKick(minInterval: 30.0)
            if hasRunFirstOverlay && !allowStaleKick {
                rateLimitedLog("overlayLivePrices.skipped.staleCooldown",
                               "⏳ [LivePriceManager] Skipping overlay - stale recovery cooldown active",
                               minInterval: 30.0)
                return
            }
        }
        if hasRunFirstOverlay && firestoreFresh {
            rateLimitedLog("overlayLivePrices.skipped.firestoreFresh",
                           "🔥 [LivePriceManager] Skipping overlay - Firestore ticker data is fresh",
                           minInterval: 120.0)  // PERFORMANCE v26: Reduced from 30s to 120s - this is normal operation, not worth logging often
            return
        }
        
        // STALE DATA FIX: Allow first overlay to bypass coordinator check
        // This ensures we get fresh percentage data immediately instead of showing stale cache
        let shouldBypassCoordinator = !hasRunFirstOverlay
        hasRunFirstOverlay = true
        
        // Check coordinator before overlay to respect startup delays and rate limits
        if !shouldBypassCoordinator && !APIRequestCoordinator.shared.canMakeRequest(for: .binance) {
            // PERFORMANCE FIX: Rate-limit this log to once per 30s to avoid console spam
            rateLimitedLog("overlayLivePrices.blocked", "⏳ [LivePriceManager] overlayLivePrices blocked by coordinator", minInterval: 120.0)
            return
        }
        
        let snapshot: [MarketCoin] = self.currentCoins

        // Bail early if offline
        if !NetworkMonitor.shared.isOnline { return }

        // Check for degraded mode and Binance blocked status
        let isDegraded = await MainActor.run { APIHealthManager.shared.isDegradedMode }
        let binanceStatus = await MainActor.run { APIHealthManager.shared.status(for: .binance) }
        let binanceBlocked: Bool = {
            if case .blocked = binanceStatus { return true }
            return false
        }()
        
        // Avoid hammering if we have no coins yet
        guard !snapshot.isEmpty else { return }
        
        // If Binance is blocked, use Coinbase fallback regardless of degraded mode
        if binanceBlocked {
            // Also slow down when Binance is blocked
            if overlayIntervalSeconds < 60 {
                overlayIntervalSeconds = 60
                startPriceOverlayTimer()
            }
            // LOG SPAM FIX: Only log once when first entering blocked state
            if !didLogBinanceBlocked {
                didLogBinanceBlocked = true
                didLogDegradedMode = false // Reset so we log if we transition to degraded later
                logger.info("⚠️ [LivePriceManager] Binance blocked - slowing overlay to 60s and using Coinbase fallback")
            }
            recordStaleOverlayFallback(reason: "binance-blocked-coinbase-fallback", firestoreFresh: firestoreFresh)
            await overlayWithCoinbaseFallback(snapshot: snapshot)
            return
        } else {
            // Binance no longer blocked - reset the flag
            didLogBinanceBlocked = false
        }
        
        // In degraded mode (but Binance not blocked), slow down polling
        if isDegraded {
            if overlayIntervalSeconds < 120 {
                overlayIntervalSeconds = 120
                startPriceOverlayTimer()
            }
            // LOG SPAM FIX: Only log once when first entering degraded mode
            if !didLogDegradedMode {
                didLogDegradedMode = true
                logger.info("⚠️ [LivePriceManager] Degraded mode detected - slowing overlay to 120s")
            }
        } else {
            // No longer in degraded mode - reset the flag
            didLogDegradedMode = false
        }

        // Circuit breaker: skip overlay if recently suspended due to repeated failures
        if let until = overlaySuspendUntil {
            let now = Date()
            if now < until {
                return
            } else {
                // Suspension expired; clear and reset failure counter
                overlaySuspendUntil = nil
                overlayFailureCount = 0
            }
        }

        // Avoid overlapping runs via actor gate
        let started = await overlayGate.tryStart()
        guard started else { return }
        defer { Task { await overlayGate.finish() } }
        
        // RATE LIMIT FIX: Try Firebase proxy first - all users share the same cached response (30s cache)
        // This eliminates per-user rate limiting issues at scale
        do {
            let firebaseSuccess = try await overlayWithFirebaseProxy(snapshot: snapshot)
            if firebaseSuccess {
                logger.info("✅ [LivePriceManager] Overlay via Firebase proxy succeeded")
                overlayFailureCount = 0 // Reset failure counter on success
                return // Successfully applied Firebase overlay, no need for direct API calls
            }
        } catch {
            // Firebase failed, continue to direct Binance API calls below
            rateLimitedLog("overlayFirebase.failed", "⚠️ [LivePriceManager] Firebase proxy failed, using direct API: \(error.localizedDescription)")
            recordStaleOverlayFallback(reason: "firebase-proxy-failed", firestoreFresh: firestoreFresh)
        }

        // Make sure our supported base list is available/refreshed
        await ensureBinanceSupportedBases()
        
        // Inserted code per instructions:
        let endpointsNow = await ExchangeHostPolicy.shared.currentEndpoints()
        let hostLower = endpointsNow.restBase.host?.lowercased() ?? ""
        let useBatch24hr = !hostLower.contains("binance.us")

        let basesSnapshot: Set<String> = await MainActor.run { self.binanceSupportedBases }

        // Collect up to 50 non-stable symbols for live updates
        let stable = MarketCoin.stableBases
        // Prefer dynamically discovered bases; fall back to a small seed list if unavailable
        let allowedBases: Set<String> = basesSnapshot.isEmpty ? binanceOverlaySupportedSymbols : basesSnapshot
        let allSymbols = Array(Set(snapshot.map { $0.symbol.uppercased() }))

        // Replaced block per instructions:
        let window: Int = {
            let onBinanceUS = hostLower.contains("binance.us")
            if overlayWarmupPassesRemaining > 0 { return onBinanceUS ? 8 : 12 }
            return onBinanceUS ? 6 : 8
        }()

        // Filter out precious metals from Binance calls - they need Coinbase
        let preciousMetals = allSymbols.filter { PreciousMetalsHelper.isPreciousMetal($0) }
        
        let symbols = allSymbols
            .filter { !stable.contains($0) }
            .filter { !binanceOverlayBlocklist.contains($0) }
            .filter { allowedBases.contains($0) }
            .filter { !PreciousMetalsHelper.isPreciousMetal($0) } // Exclude precious metals from Binance

        if symbols.isEmpty && preciousMetals.isEmpty {
            logger.info("ℹ️ [LivePriceManager] No eligible symbols for overlay after filters. allowedBases=\(allowedBases.count, privacy: .public) snapshot=\(snapshot.count, privacy: .public)")
            return
        }

        if overlayOffset == 0 {
            overlayOffset = Int.random(in: 0..<(max(1, symbols.count)))
        }
        if overlayOffset >= symbols.count { overlayOffset = 0 }
        let end = min(symbols.count, overlayOffset + window)
        var slice = Array(symbols[overlayOffset..<end])
        if slice.isEmpty { slice = Array(symbols.prefix(min(window, symbols.count))) }
        overlayOffset = end
        let batch = slice
        guard !batch.isEmpty else { return }

        // PERFORMANCE FIX: Removed aggressive 3s warmup - was causing UI lag.
        // Now warm-up just uses the base interval (15s) which is sufficient for initial data.
        if overlayWarmupPassesRemaining > 0 {
            overlayWarmupPassesRemaining -= 1
            // No special faster interval during warmup anymore - use base interval
        }
        if overlayIntervalSeconds != overlayBaseIntervalSeconds {
            // Return to base interval after warm-up
            overlayIntervalSeconds = overlayBaseIntervalSeconds
            startPriceOverlayTimer()
        }

        // Replaced entire do-catch block per instructions:
        if useBatch24hr {
            do {
                let stats = try await BinanceService.fetch24hrStats(symbols: batch)

                // Build a lookup with both last price, 24h change percent, and volume, keyed by base symbol and pair variants
                struct OverlayInfo { let price: Double; let pct24h: Double?; let volumeUSD: Double? }
                var infoBySymbol: [String: OverlayInfo] = [:]
                for st in stats {
                    let sUpper = st.symbol.uppercased()
                    let info = OverlayInfo(price: st.lastPrice, pct24h: st.change24h, volumeUSD: st.volume)
                    // Raw key as returned
                    infoBySymbol[sUpper.lowercased()] = info
                    // Common quote suffixes -> base asset mapping
                    let commonQuotes = ["USDT", "USD", "BUSD", "USDC"]
                    for q in commonQuotes where sUpper.hasSuffix(q) {
                        let base = String(sUpper.dropLast(q.count))
                        if !base.isEmpty { infoBySymbol[base.lowercased()] = info }
                    }
                }

                if infoBySymbol.isEmpty {
                    logger.info("ℹ️ [LivePriceManager] Overlay returned no symbols for batch: \(batch.joined(separator: ","), privacy: .public)")
                }

                // Update our side-car caches from overlay results on the main actor
                await MainActor.run {
                    var anyVolumeAdded = false
                    for (symLower, info) in infoBySymbol {
                        if let vol = info.volumeUSD, vol.isFinite, vol > 0 {
                            if latestVolumeUSDBySymbol[symLower] != vol {
                                safeSetVolumeUSD(symLower, vol)
                                anyVolumeAdded = true
                            }
                        }
                    }
                    if anyVolumeAdded { volumeCacheIsDirty = true }
                }

                // Process overlay results on MainActor to safely access @MainActor properties
                // Copy data needed for the MainActor block
                let snapshotCopy = snapshot
                let infoBySymbolCopy = infoBySymbol
                
                struct OverlayResult {
                    var coins: [MarketCoin]
                    var anyChanged: Bool
                    var overlayPct24h: [String: Double]
                }
                
                let result: OverlayResult = await MainActor.run {
                    var overlayPct24h: [String: Double] = [:]
                    var anyChanged = false
                    var coins = snapshotCopy
                    
                    for i in 0..<coins.count {
                        let symLower = coins[i].symbol.lowercased()
                        if let info = infoBySymbolCopy[symLower] {
                            let old = coins[i]
                            var changed = false

                            // Always update price when it differs significantly
                            if self.canApplyProviderPrice(symLower: symLower, candidate: info.price, old: old.priceUsd) {
                                coins[i].priceUsd = info.price
                                self.lastProviderApplyAt[symLower] = Date()
                                changed = true
                            }

                            // Apply 24h percent from overlay if provider value is missing
                            if let pct24 = info.pct24h, pct24.isFinite {
                                if coins[i].priceChangePercentage24hInCurrency == nil {
                                    let c = coins[i]
                                    coins[i] = MarketCoin(
                                        id: c.id,
                                        symbol: c.symbol,
                                        name: c.name,
                                        imageUrl: c.imageUrl,
                                        priceUsd: c.priceUsd,
                                        marketCap: c.marketCap,
                                        totalVolume: c.totalVolume,
                                        priceChangePercentage1hInCurrency: c.priceChangePercentage1hInCurrency,
                                        priceChangePercentage24hInCurrency: pct24,
                                        priceChangePercentage7dInCurrency: c.priceChangePercentage7dInCurrency,
                                        sparklineIn7d: c.sparklineIn7d,
                                        marketCapRank: c.marketCapRank,
                                        maxSupply: c.maxSupply,
                                        circulatingSupply: c.circulatingSupply,
                                        totalSupply: c.totalSupply
                                    )
                                    if self.debugPercentSourcing {
                                        self.logger.debug("[Pct] 24h from overlay for \(old.symbol, privacy: .public)")
                                    }
                                    overlayPct24h[symLower] = pct24
                                    changed = true
                                }
                            }

                            if changed { anyChanged = true }
                        }
                    }
                    
                    // Also cache the percent changes
                    for (k, v) in overlayPct24h { self.safeSet24hChange(k, v) }
                    self.schedulePercentSidecarSave()
                    
                    return OverlayResult(coins: coins, anyChanged: anyChanged, overlayPct24h: overlayPct24h)
                }
                
                var updated = result.coins
                var anyChange = result.anyChanged
                _ = result.overlayPct24h

                // Reset backoff on successful overlay fetch
                overlayFailureCount = 0
                if overlayIntervalSeconds != overlayBaseIntervalSeconds {
                    overlayIntervalSeconds = overlayBaseIntervalSeconds
                    startPriceOverlayTimer()
                }

                // If nothing changed or some symbols in this batch are still zero/missing, proactively run the per-symbol fallback
                let batchLower = Set(batch.map { $0.lowercased() })
                let stillZeroInBatch = updated.contains { coin in
                    batchLower.contains(coin.symbol.lowercased()) && ((coin.priceUsd ?? 0) <= 0)
                }
                if !anyChange || stillZeroInBatch {
                    var fallbackUpdated = updated

                    // Limit to the current batch to avoid hammering
                    let allowedBases: Set<String> = basesSnapshot.isEmpty ? binanceOverlaySupportedSymbols : basesSnapshot
                    let stableLower: Set<String> = Set(MarketCoin.stableSymbols.map { $0.lowercased() })
                    let targets = Set(batch
                        .filter { allowedBases.contains($0.uppercased()) }
                        .filter { !stableLower.contains($0.lowercased()) }
                        .filter { !binanceOverlayBlocklist.contains($0.uppercased()) }
                        .map { $0.lowercased() })

                    // Collect price updates first, then apply on MainActor
                    var priceUpdates: [(index: Int, symLower: String, price: Double, oldPrice: Double?)] = []
                    for i in 0..<fallbackUpdated.count {
                        let symLower = fallbackUpdated[i].symbol.lowercased()
                        guard targets.contains(symLower) else { continue }
                        let base = symLower.uppercased()
                        var val: Double? = await binanceTickerPriceForBestQuote(base: base)
                        if val == nil {
                            val = await coinbaseTickerPrice(for: base)
                        }
                        if let v = val {
                            priceUpdates.append((index: i, symLower: symLower, price: v, oldPrice: fallbackUpdated[i].priceUsd))
                        }
                    }
                    // Apply updates on MainActor to safely access @MainActor properties
                    await MainActor.run { [self] in
                        for update in priceUpdates {
                            if self.canApplyProviderPrice(symLower: update.symLower, candidate: update.price, old: update.oldPrice) {
                                fallbackUpdated[update.index].priceUsd = update.price
                                self.lastProviderApplyAt[update.symLower] = Date()
                            }
                        }
                    }

                    var fallbackChanged = false
                    for i in 0..<fallbackUpdated.count {
                        if fallbackUpdated[i].priceUsd != updated[i].priceUsd { fallbackChanged = true; break }
                    }
                    if fallbackChanged {
                        updated = fallbackUpdated
                        anyChange = true
                    }
                }

                if anyChange {
                    let toSend = updated
                    // Compare against current snapshot and debounce vs recent poll
                    let oldSnapshot: [MarketCoin] = await MainActor.run { self.currentCoins }
                    let meaningful = hasMeaningfulPriceChange(old: oldSnapshot, new: toSend)
                    await MainActor.run {
                        let suppressDueToRecentPoll: Bool = {
                            if let last = self.lastPollEmitAt { return Date().timeIntervalSince(last) < self.pollVsOverlayDebounceSeconds }
                            return false
                        }()
                        self.currentCoins = toSend
                        if meaningful && !suppressDueToRecentPoll {
                            self.emitCoins(toSend)
                            self.lastOverlayEmitAt = Date()
                        }
                    }
                    saveCoinsCacheCapped(toSend)  // MEMORY FIX v5: Cap before disk save
                }
            } catch {
                // IMPROVED FALLBACK: When both Firebase proxy AND Binance batch API fail,
                // immediately try Coinbase fallback to ensure users always see price data
                rateLimitedLog("overlay.binanceFailed", "⚠️ [LivePriceManager] Binance batch failed: \(error.localizedDescription), trying Coinbase fallback")
                
                // First, try Coinbase fallback for quick price updates
                await overlayWithCoinbaseFallback(snapshot: snapshot)
                
                // Exponential backoff with cap and small jitter
                overlayFailureCount += 1
                let factor = pow(2.0, Double(min(overlayFailureCount, 4))) // cap exponent growth
                let target = min(overlayBaseIntervalSeconds * factor, overlayMaxIntervalSeconds)
                // Add jitter +/- 10% to avoid thundering herd
                let jitter = target * (Double.random(in: -0.1...0.1))
                let newInterval = max(overlayBaseIntervalSeconds, min(target + jitter, overlayMaxIntervalSeconds))

                overlayWarmupPassesRemaining = 0

                if newInterval.rounded() != overlayIntervalSeconds.rounded() {
                    overlayIntervalSeconds = newInterval
                    startPriceOverlayTimer()
                }
                // Suspend overlays for a longer window after repeated failures to reduce thrash
                if overlayFailureCount >= overlayMaxConsecutiveFailuresBeforeSuspend {
                    overlaySuspendUntil = Date().addingTimeInterval(overlaySuspendCooldown)
                    overlayFailureCount = 0
                    logger.info("⚠️ [LivePriceManager] Overlay suspended for \(Int(self.overlaySuspendCooldown))s after repeated failures")
                    
                    // CACHE FALLBACK: Emit cached coins when all APIs fail to ensure UI shows data
                    let cachedCoins: [MarketCoin] = await MainActor.run { self.currentCoins }
                    if !cachedCoins.isEmpty {
                        rateLimitedLog("overlay.usingCache", "ℹ️ [LivePriceManager] All APIs failed - displaying cached data")
                        await MainActor.run {
                            self.emitCoins(cachedCoins)
                        }
                    }
                }

                // Fallback: try individual ticker/price for zero-priced/non-stable coins to avoid $0.00

                var updated = snapshot

                // Build a target list: prefer the same batch we just tried; otherwise any non-stable with missing/zero price
                let stableLower: Set<String> = Set(MarketCoin.stableSymbols.map { $0.lowercased() })
                let targetSymbols: [String] = {
                    let batchLower = Set(batch.map { $0.lowercased() })
                    let allowedBasesLocal = allowedBases
                    let batchTargets = updated
                        .filter { batchLower.contains($0.symbol.lowercased()) }
                        .filter { !stableLower.contains($0.symbol.lowercased()) }
                        .filter { allowedBasesLocal.contains($0.symbol.uppercased()) }
                        .filter { !binanceOverlayBlocklist.contains($0.symbol.uppercased()) }
                        .filter { ($0.priceUsd ?? 0) <= 0 }
                        .map { $0.symbol.lowercased() }
                    if !batchTargets.isEmpty { return Array(Set(batchTargets)) }
                    let broad = updated
                        .filter { !stableLower.contains($0.symbol.lowercased()) }
                        .filter { allowedBasesLocal.contains($0.symbol.uppercased()) }
                        .filter { !binanceOverlayBlocklist.contains($0.symbol.uppercased()) }
                        .filter { ($0.priceUsd ?? 0) <= 0 }
                        .prefix(50)
                        .map { $0.symbol.lowercased() }
                    return Array(Set(broad))
                }()

                // Collect price updates first
                var perSymbolUpdates: [(index: Int, symLower: String, price: Double, oldPrice: Double?)] = []
                for i in 0..<updated.count {
                    let symLower = updated[i].symbol.lowercased()
                    guard targetSymbols.contains(symLower) else { continue }
                    let base = symLower.uppercased()
                    var val: Double? = await binanceTickerPriceForBestQuote(base: base)
                    if val == nil {
                        val = await coinbaseTickerPrice(for: base)
                    }
                    if let v = val {
                        perSymbolUpdates.append((index: i, symLower: symLower, price: v, oldPrice: updated[i].priceUsd))
                    }
                }
                // Apply on MainActor to safely access @MainActor properties
                await MainActor.run { [self] in
                    for update in perSymbolUpdates {
                        if self.canApplyProviderPrice(symLower: update.symLower, candidate: update.price, old: update.oldPrice) {
                            updated[update.index].priceUsd = update.price
                            self.lastProviderApplyAt[update.symLower] = Date()
                        }
                    }
                }

                var changed = false
                for i in 0..<updated.count {
                    if updated[i].priceUsd != snapshot[i].priceUsd { changed = true; break }
                }
                if changed {
                    let toSend = updated
                    // Compare against current snapshot and debounce vs recent poll
                    let oldSnapshot: [MarketCoin] = await MainActor.run { self.currentCoins }
                    let meaningful = hasMeaningfulPriceChange(old: oldSnapshot, new: toSend)
                    await MainActor.run {
                        let suppressDueToRecentPoll: Bool = {
                            if let last = self.lastPollEmitAt { return Date().timeIntervalSince(last) < self.pollVsOverlayDebounceSeconds }
                            return false
                        }()
                        self.currentCoins = toSend
                        if meaningful && !suppressDueToRecentPoll {
                            self.emitCoins(toSend)
                            self.lastOverlayEmitAt = Date()
                        }
                    }
                    saveCoinsCacheCapped(toSend)  // MEMORY FIX v5: Cap before disk save
                }
            }
        } else {
            // On binance.us, skip the batch 24h stats endpoint (often returns HTTP 400) and overlay per-symbol prices instead.
            // Reset backoff since we're not using the failing batch path here.
            overlayFailureCount = 0
            if overlayIntervalSeconds != overlayBaseIntervalSeconds {
                overlayIntervalSeconds = overlayBaseIntervalSeconds
                startPriceOverlayTimer()
            }

            var updated = snapshot
            let batchLower = Set(batch.map { $0.lowercased() })
            
            // Collect price updates first
            var batchPriceUpdates: [(index: Int, symLower: String, price: Double, oldPrice: Double?)] = []
            for i in 0..<updated.count {
                let symLower = updated[i].symbol.lowercased()
                guard batchLower.contains(symLower) else { continue }
                let base = symLower.uppercased()
                var val: Double? = await binanceTickerPriceForBestQuote(base: base)
                if val == nil {
                    val = await coinbaseTickerPrice(for: base)
                }
                if let v = val {
                    batchPriceUpdates.append((index: i, symLower: symLower, price: v, oldPrice: updated[i].priceUsd))
                }
            }
            
            // Apply on MainActor and track if anything changed
            let anyChange = await MainActor.run { [self] in
                var changed = false
                for update in batchPriceUpdates {
                    if self.canApplyProviderPrice(symLower: update.symLower, candidate: update.price, old: update.oldPrice) {
                        updated[update.index].priceUsd = update.price
                        self.lastProviderApplyAt[update.symLower] = Date()
                        changed = true
                    }
                }
                return changed
            }

            if anyChange {
                // Opportunistically prime volumes for these symbols if missing
                await MainActor.run {
                    for base in batch {
                        let lower = base.lowercased()
                        if (self.latestVolumeUSDBySymbol[lower] ?? 0) <= 0 {
                            self.primeVolumeIfNeeded(for: base)
                        }
                    }
                }
                let toSend = updated
                // Compare against current snapshot and debounce vs recent poll
                let oldSnapshot: [MarketCoin] = await MainActor.run { self.currentCoins }
                let meaningful = hasMeaningfulPriceChange(old: oldSnapshot, new: toSend)
                await MainActor.run {
                    let suppressDueToRecentPoll: Bool = {
                        if let last = self.lastPollEmitAt { return Date().timeIntervalSince(last) < self.pollVsOverlayDebounceSeconds }
                        return false
                    }()
                    self.currentCoins = toSend
                    if meaningful && !suppressDueToRecentPoll {
                        self.emitCoins(toSend)
                        self.lastOverlayEmitAt = Date()
                    }
                }
                saveCoinsCacheCapped(toSend)  // MEMORY FIX v5: Cap before disk save
            }
        }
    }

    /// Push a direct price update for a symbol into the live stream.
    /// Thread-safe: marshals to the main queue for state mutation and emission.
    /// PRICE CONSISTENCY FIX: Added source parameter for priority-based updates
    /// - source: The price source (binance, coinbase, coinGecko, derived). Defaults to .binance for backward compatibility.
    ///   Higher priority sources always win. Lower priority sources only accepted if higher priority is stale (>5s).
    func update(symbol: String, price: Double, source: PriceSource = .binance, change24h: Double? = nil) {
        guard price.isFinite, price > 0 else { return }
        let symUpper = symbol.uppercased()
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let symLower = symUpper.lowercased()
            
            // PRICE CONSISTENCY: Check source priority before accepting update
            if let lastSource = self.lastPriceSource[symLower],
               let lastAt = self.lastPriceSourceAt[symLower] {
                let staleness = Date().timeIntervalSince(lastAt)
                // If current source has lower priority than last source
                if source > lastSource && staleness < self.priceSourceStalenessThreshold {
                    // Reject update from lower-priority source unless higher-priority is stale
                    return
                }
            }
            
            // PRICE CONSISTENCY FIX: Check against median buffer for outlier detection
            if !self.isAcceptablePriceVsMedian(symbol: symLower, newPrice: price) {
                return  // Reject outlier
            }
            
            var updated = self.currentCoins
            var changed = false
            for i in 0..<updated.count {
                if updated[i].symbol.uppercased() == symUpper {
                    var localChanged = false
                    if self.shouldAcceptPrice(old: updated[i].priceUsd, new: price) {
                        updated[i].priceUsd = price
                        self.lastDirectAt[symLower] = Date()
                        self.lastDirectPriceBySymbol[symLower] = price
                        // Track source for priority enforcement
                        self.lastPriceSource[symLower] = source
                        self.lastPriceSourceAt[symLower] = Date()
                        // Record price in median buffer for future outlier detection
                        self.recordPriceInMedianBuffer(symbol: symLower, price: price)
                        localChanged = true
                    }
                    if let ch = change24h, ch.isFinite {
                        var adj = ch
                        if abs(adj) > 95 { adj = (adj >= 0 ? 95.0 : -95.0) }
                        let c = updated[i]
                        updated[i] = MarketCoin(
                            id: c.id,
                            symbol: c.symbol,
                            name: c.name,
                            imageUrl: c.imageUrl,
                            priceUsd: c.priceUsd,
                            marketCap: c.marketCap,
                            totalVolume: c.totalVolume,
                            priceChangePercentage1hInCurrency: c.priceChangePercentage1hInCurrency,
                            priceChangePercentage24hInCurrency: adj,
                            priceChangePercentage7dInCurrency: c.priceChangePercentage7dInCurrency,
                            sparklineIn7d: c.sparklineIn7d,
                            marketCapRank: c.marketCapRank,
                            maxSupply: c.maxSupply,
                            circulatingSupply: c.circulatingSupply,
                            totalSupply: c.totalSupply
                        )
                        self.safeSet24hChange(symLower, adj)
                        if self.debugPercentSourcing {
                            self.logger.debug("[Pct] 24h from direct update for \(c.symbol, privacy: .public) source=\(String(describing: source), privacy: .public)")
                        }
                        self.schedulePercentSidecarSave()
                        localChanged = true
                    }
                    changed = localChanged
                    break
                }
            }
            if changed {
                self.currentCoins = updated
                self.emitCoins(updated)
                self.saveCoinsCacheCapped(updated)  // MEMORY FIX v5: Cap before disk save
            }
        }
    }

    @MainActor private func scheduleHistoryDerivationIfNeeded(for coin: MarketCoin) {
        let symLower = coin.symbol.lowercased()
        let needs24 = (coin.priceChangePercentage24hInCurrency == nil)
        let needs7d = (coin.priceChangePercentage7dInCurrency == nil)
        // If nothing missing, no work
        if !needs24 && !needs7d { return }
        // Throttle attempts per symbol
        if let last = historyLastAttemptAt[symLower], Date().timeIntervalSince(last) < historyAttemptCooldown { return }
        if historyInFlight.contains(symLower) { return }
        historyInFlight.insert(symLower)
        historyLastAttemptAt[symLower] = Date()
        let coinID = coin.id
        Task { [weak self] in
            await self?._derivePercentsFromHistory(symbolLower: symLower, coinID: coinID)
        }
    }
    private func _derivePercentsFromHistory(symbolLower: String, coinID: String) async {
        // Fetch a 7d history from CoinGecko and compute 1h/24h/7d percent deltas
        let series = await CryptoAPIService.shared.fetchPriceHistory(coinID: coinID, timeframe: .oneWeek)
        guard !series.isEmpty else {
            _ = await MainActor.run { [symbolLower] in
                self.historyInFlight.remove(symbolLower)
            }
            return
        }
        let d1h = derivePercentChange(from: series, overHours: 1)
        let d24 = derivePercentChange(from: series, overHours: 24)
        let d7d = derivePercentChange(from: series, overHours: 24 * 7)
        await MainActor.run { [weak self] in
            guard let self = self else { return }
            // Update sidecars if we have values (using safe setters)
            if let v = d1h, v.isFinite { self.safeSet1hChange(symbolLower, v) }
            if let v = d24, v.isFinite { self.safeSet24hChange(symbolLower, v) }
            if let v = d7d, v.isFinite { self.safeSet7dChange(symbolLower, v) }
            self.schedulePercentSidecarSave()

            // Overlay into currentCoins if fields are still missing
            var updated = self.currentCoins
            var changed = false
            for i in 0..<updated.count where updated[i].symbol.lowercased() == symbolLower {
                var c = updated[i]
                let v1 = c.priceChangePercentage1hInCurrency
                let v24 = c.priceChangePercentage24hInCurrency
                let v7 = c.priceChangePercentage7dInCurrency
                let new1 = (v1 == nil ? d1h : v1)
                let new24 = (v24 == nil ? d24 : v24)
                let new7 = (v7 == nil ? d7d : v7)
                if new1 != v1 || new24 != v24 || new7 != v7 { // optional inequality is fine here
                    c = MarketCoin(
                        id: c.id,
                        symbol: c.symbol,
                        name: c.name,
                        imageUrl: c.imageUrl,
                        priceUsd: c.priceUsd,
                        marketCap: c.marketCap,
                        totalVolume: c.totalVolume,
                        priceChangePercentage1hInCurrency: new1,
                        priceChangePercentage24hInCurrency: new24,
                        priceChangePercentage7dInCurrency: new7,
                        sparklineIn7d: c.sparklineIn7d,
                        marketCapRank: c.marketCapRank,
                        maxSupply: c.maxSupply,
                        circulatingSupply: c.circulatingSupply,
                        totalSupply: c.totalSupply
                    )
                    updated[i] = c
                    changed = true
                }
                break
            }
            if changed {
                self.currentCoins = updated
                // MEMORY FIX v4: Do NOT call emitCoins() here.
                // Previously, each history derivation completion triggered the full
                // emission pipeline (debounce → snapshot → Task.detached → augment → finishEmission).
                // With 20+ history derivations during cold start, this created 20+ overlapping
                // emission cascades, each spawning background tasks with large retained closures.
                // The derived values are already in the sidecar caches and currentCoins —
                // the next natural emission cycle will pick them up.
            }
            self.historyInFlight.remove(symbolLower)
        }
    }

    // MARK: - Emission augmentation

    // PERFORMANCE FIX: Cache snapshot struct for background processing
    // Captures MainActor-isolated caches to allow heavy processing off main thread
    private struct PercentCacheSnapshot: @unchecked Sendable {
        let change1h: [String: Double]
        let change24h: [String: Double]
        let change7d: [String: Double]
        let sparklines: [String: [Double]]
    }
    
    /// PERFORMANCE FIX: Capture cache snapshot for background processing
    /// Must be called on MainActor, returns Sendable snapshot
    @MainActor
    private func capturePercentCacheSnapshot() -> PercentCacheSnapshot {
        // Refresh sparkline cache if stale before capturing
        let now = Date()
        if now.timeIntervalSince(sparklineCacheLastLoadedAt) >= sparklineCacheRefreshInterval {
            cachedSparklines = WatchlistSparklineService.loadCachedSparklinesSync()
            sparklineCacheLastLoadedAt = now
        }
        
        return PercentCacheSnapshot(
            change1h: last1hChangeBySymbol,
            change24h: last24hChangeBySymbol,
            change7d: last7dChangeBySymbol,
            sparklines: cachedSparklines
        )
    }
    
    /// PERFORMANCE FIX: Process coins on background thread using cache snapshot
    /// This moves the heavy O(n) loop off MainActor to prevent UI blocking
    private nonisolated func augmentCoinsInBackground(
        _ coins: [MarketCoin],
        snapshot: PercentCacheSnapshot
    ) -> (coins: [MarketCoin], derived1h: Set<String>, derived24h: Set<String>, derived7d: Set<String>, sanitized: Set<String>) {
        var out = coins
        var derived1hSyms: Set<String> = []
        var derived24hSyms: Set<String> = []
        var derived7dSyms: Set<String> = []
        var sanitizedSyms: Set<String> = []
        
        for i in 0..<out.count {
            let key = out[i].symbol.lowercased()
            
            // Sanitize obviously bad or duplicated provider percents
            do {
                let p1 = out[i].priceChangePercentage1hInCurrency
                let p24 = out[i].priceChangePercentage24hInCurrency
                let p7 = out[i].priceChangePercentage7dInCurrency
                
                func approxEqual(_ a: Double?, _ b: Double?) -> Bool {
                    guard let a = a, let b = b else { return false }
                    return abs(a - b) < 0.0001
                }
                
                let allHave = (p1 != nil && p24 != nil && p7 != nil)
                let allEqual = allHave && approxEqual(p1, p24) && approxEqual(p1, p7)
                let allZero = allHave && abs(p1 ?? 0) < 1e-9 && abs(p24 ?? 0) < 1e-9 && abs(p7 ?? 0) < 1e-9
                let isNonFinite: (Double?) -> Bool = { v in
                    guard let v = v else { return false }
                    return !v.isFinite
                }
                let isAbsurd: (Double?) -> Bool = { v in
                    guard let v = v else { return false }
                    return v.isFinite && abs(v) > 10000
                }
                
                var n1 = p1
                var n24 = p24
                var n7 = p7
                
                if allEqual || allZero {
                    n1 = nil; n24 = nil; n7 = nil
                } else {
                    if isNonFinite(p1) || isAbsurd(p1) { n1 = nil }
                    if isNonFinite(p24) || isAbsurd(p24) { n24 = nil }
                    if isNonFinite(p7) || isAbsurd(p7) { n7 = nil }
                }
                
                if n1 != p1 || n24 != p24 || n7 != p7 {
                    let c = out[i]
                    out[i] = MarketCoin(
                        id: c.id, symbol: c.symbol, name: c.name, imageUrl: c.imageUrl,
                        priceUsd: c.priceUsd, marketCap: c.marketCap, totalVolume: c.totalVolume,
                        priceChangePercentage1hInCurrency: n1,
                        priceChangePercentage24hInCurrency: n24,
                        priceChangePercentage7dInCurrency: n7,
                        sparklineIn7d: c.sparklineIn7d, marketCapRank: c.marketCapRank,
                        maxSupply: c.maxSupply, circulatingSupply: c.circulatingSupply, totalSupply: c.totalSupply
                    )
                    sanitizedSyms.insert(key)
                }
            }
            
            // Clamp provider 24h percent for stables
            if let existing24 = out[i].priceChangePercentage24hInCurrency {
                let c = out[i]
                let clamped = Self.clampStable24hBackground(symbol: c.symbol, value: existing24)
                if clamped != existing24 {
                    out[i] = MarketCoin(
                        id: c.id, symbol: c.symbol, name: c.name, imageUrl: c.imageUrl,
                        priceUsd: c.priceUsd, marketCap: c.marketCap, totalVolume: c.totalVolume,
                        priceChangePercentage1hInCurrency: c.priceChangePercentage1hInCurrency,
                        priceChangePercentage24hInCurrency: clamped,
                        priceChangePercentage7dInCurrency: c.priceChangePercentage7dInCurrency,
                        sparklineIn7d: c.sparklineIn7d, marketCapRank: c.marketCapRank,
                        maxSupply: c.maxSupply, circulatingSupply: c.circulatingSupply, totalSupply: c.totalSupply
                    )
                }
            }
            
            // 1h percent: prefer provider, else sidecar from snapshot
            if out[i].priceChangePercentage1hInCurrency == nil {
                if let cached1h = snapshot.change1h[key] {
                    let c = out[i]
                    out[i] = MarketCoin(
                        id: c.id, symbol: c.symbol, name: c.name, imageUrl: c.imageUrl,
                        priceUsd: c.priceUsd, marketCap: c.marketCap, totalVolume: c.totalVolume,
                        priceChangePercentage1hInCurrency: cached1h,
                        priceChangePercentage24hInCurrency: c.priceChangePercentage24hInCurrency,
                        priceChangePercentage7dInCurrency: c.priceChangePercentage7dInCurrency,
                        sparklineIn7d: c.sparklineIn7d, marketCapRank: c.marketCapRank,
                        maxSupply: c.maxSupply, circulatingSupply: c.circulatingSupply, totalSupply: c.totalSupply
                    )
                } else if let derived1h = Self.derivePercentFromSnapshotBackground(coin: out[i], hours: 1, snapshot: snapshot) {
                    let c = out[i]
                    out[i] = MarketCoin(
                        id: c.id, symbol: c.symbol, name: c.name, imageUrl: c.imageUrl,
                        priceUsd: c.priceUsd, marketCap: c.marketCap, totalVolume: c.totalVolume,
                        priceChangePercentage1hInCurrency: derived1h,
                        priceChangePercentage24hInCurrency: c.priceChangePercentage24hInCurrency,
                        priceChangePercentage7dInCurrency: c.priceChangePercentage7dInCurrency,
                        sparklineIn7d: c.sparklineIn7d, marketCapRank: c.marketCapRank,
                        maxSupply: c.maxSupply, circulatingSupply: c.circulatingSupply, totalSupply: c.totalSupply
                    )
                    derived1hSyms.insert(key)
                }
            }
            
            // 24h percent: prefer provider, else sidecar from snapshot
            if out[i].priceChangePercentage24hInCurrency == nil {
                if let cached24h = snapshot.change24h[key] {
                    let c = out[i]
                    out[i] = MarketCoin(
                        id: c.id, symbol: c.symbol, name: c.name, imageUrl: c.imageUrl,
                        priceUsd: c.priceUsd, marketCap: c.marketCap, totalVolume: c.totalVolume,
                        priceChangePercentage1hInCurrency: c.priceChangePercentage1hInCurrency,
                        priceChangePercentage24hInCurrency: Self.clampStable24hBackground(symbol: c.symbol, value: cached24h),
                        priceChangePercentage7dInCurrency: c.priceChangePercentage7dInCurrency,
                        sparklineIn7d: c.sparklineIn7d, marketCapRank: c.marketCapRank,
                        maxSupply: c.maxSupply, circulatingSupply: c.circulatingSupply, totalSupply: c.totalSupply
                    )
                } else if let derived24h = Self.derivePercentFromSnapshotBackground(coin: out[i], hours: 24, snapshot: snapshot) {
                    let c = out[i]
                    out[i] = MarketCoin(
                        id: c.id, symbol: c.symbol, name: c.name, imageUrl: c.imageUrl,
                        priceUsd: c.priceUsd, marketCap: c.marketCap, totalVolume: c.totalVolume,
                        priceChangePercentage1hInCurrency: c.priceChangePercentage1hInCurrency,
                        priceChangePercentage24hInCurrency: Self.clampStable24hBackground(symbol: c.symbol, value: derived24h),
                        priceChangePercentage7dInCurrency: c.priceChangePercentage7dInCurrency,
                        sparklineIn7d: c.sparklineIn7d, marketCapRank: c.marketCapRank,
                        maxSupply: c.maxSupply, circulatingSupply: c.circulatingSupply, totalSupply: c.totalSupply
                    )
                    derived24hSyms.insert(key)
                }
            }
            
            // 7d percent: prefer provider, else sidecar from snapshot
            if out[i].priceChangePercentage7dInCurrency == nil {
                if let cached7d = snapshot.change7d[key] {
                    let c = out[i]
                    out[i] = MarketCoin(
                        id: c.id, symbol: c.symbol, name: c.name, imageUrl: c.imageUrl,
                        priceUsd: c.priceUsd, marketCap: c.marketCap, totalVolume: c.totalVolume,
                        priceChangePercentage1hInCurrency: c.priceChangePercentage1hInCurrency,
                        priceChangePercentage24hInCurrency: c.priceChangePercentage24hInCurrency,
                        priceChangePercentage7dInCurrency: cached7d,
                        sparklineIn7d: c.sparklineIn7d, marketCapRank: c.marketCapRank,
                        maxSupply: c.maxSupply, circulatingSupply: c.circulatingSupply, totalSupply: c.totalSupply
                    )
                } else if let derived7d = Self.derivePercentFromSnapshotBackground(coin: out[i], hours: 24*7, snapshot: snapshot) {
                    let c = out[i]
                    out[i] = MarketCoin(
                        id: c.id, symbol: c.symbol, name: c.name, imageUrl: c.imageUrl,
                        priceUsd: c.priceUsd, marketCap: c.marketCap, totalVolume: c.totalVolume,
                        priceChangePercentage1hInCurrency: c.priceChangePercentage1hInCurrency,
                        priceChangePercentage24hInCurrency: c.priceChangePercentage24hInCurrency,
                        priceChangePercentage7dInCurrency: derived7d,
                        sparklineIn7d: c.sparklineIn7d, marketCapRank: c.marketCapRank,
                        maxSupply: c.maxSupply, circulatingSupply: c.circulatingSupply, totalSupply: c.totalSupply
                    )
                    derived7dSyms.insert(key)
                }
            }
        }
        
        return (out, derived1hSyms, derived24hSyms, derived7dSyms, sanitizedSyms)
    }
    
    /// PERFORMANCE FIX: Background-safe stablecoin clamping (no MainActor dependency)
    private nonisolated static func clampStable24hBackground(symbol: String, value: Double) -> Double {
        let sym = symbol.lowercased()
        let stableSymbols: Set<String> = ["usdt", "usdc", "busd", "tusd", "dai", "usdp", "gusd", "frax", "lusd", "usdd", "fdusd", "pyusd"]
        guard stableSymbols.contains(sym) else { return value }
        return max(-2.0, min(2.0, value))
    }
    
    /// PERFORMANCE FIX: Background-safe percent derivation from snapshot.
    /// FIX: Now uses the same smart step calculation as derivedPercentFromSeries()
    /// instead of the hardcoded 168-hour span that was causing wrong 1H values.
    private nonisolated static func derivePercentFromSnapshotBackground(
        coin: MarketCoin,
        hours: Double,
        snapshot: PercentCacheSnapshot
    ) -> Double? {
        // Get sparkline from snapshot
        var series: [Double] = []
        
        // Check cached sparklines by ID
        if let spark = snapshot.sparklines[coin.id], spark.count >= 24 {
            series = spark.filter { $0.isFinite && $0 > 0 }
        }
        
        // Check by exact symbol key (avoid broad substring collisions)
        if series.count < 24 {
            let symLower = coin.symbol.lowercased()
            if let symbolSpark = snapshot.sparklines[symLower], symbolSpark.count >= 24 {
                let clean = symbolSpark.filter { $0.isFinite && $0 > 0 }
                if clean.count >= 24 {
                    series = clean
                }
            }
        }
        
        // Fallback to coin's built-in sparkline
        if series.count < 24 && !coin.sparklineIn7d.isEmpty {
            series = coin.sparklineIn7d.filter { $0.isFinite && $0 > 0 }
        }
        
        guard series.count >= 2 else { return nil }
        
        // Derive percent from series
        let clean = series
        let n = clean.count
        let anchorPrice = coin.priceUsd
        
        // Unit ratio validation
        if let anchor = anchorPrice, anchor > 0 {
            let windowCount = min(8, clean.count)
            let recent = Array(clean.suffix(windowCount)).sorted()
            let median = recent[windowCount / 2]
            let unitRatio = max(median, anchor) / max(1e-9, min(median, anchor))
            
            let maxUnitRatio: Double = {
                if hours <= 1 { return 1.3 }
                if hours <= 24 { return 1.8 }
                return 2.5
            }()
            
            if unitRatio > maxUnitRatio { return nil }
        }
        
        // SMART STEP CALCULATION: Detect actual data resolution (same logic as derivedPercentFromSeries)
        let stepHours: Double = {
            if n >= 140 && n <= 200 { return 1.0 }      // Hourly data (~168 pts)
            else if n >= 35 && n < 140 { return 4.0 }   // 4-hour intervals (~42 pts)
            else if n >= 5 && n < 35 { return 24.0 }    // Daily data (~7 pts)
            else { return (24.0 * 7.0) / Double(max(1, n - 1)) }  // Fallback
        }()
        
        // CRITICAL FIX: Reject when sparkline resolution is too coarse for requested timeframe.
        // Without this, daily data (stepHours=24) was being used to "derive" 1H changes,
        // actually showing ~24H changes labeled as 1H (e.g., -8.81% for BTC 1H).
        guard stepHours <= hours else { return nil }
        
        // Validate sufficient data coverage
        let estimatedTotalHours = Double(n - 1) * stepHours
        let minimumCoverageRequired = hours * 0.8
        guard estimatedTotalHours >= minimumCoverageRequired else { return nil }
        
        // Calculate lookback index
        var stepsBack = Int(round(hours / stepHours))
        if stepsBack < 1 { stepsBack = 1 }
        if stepsBack > n - 1 { stepsBack = n - 1 }
        let baseIndex = n - 1 - stepsBack
        let base = clean[baseIndex]
        
        // STALENESS CHECK: For 1H, reject if anchor diverges too much from sparkline end
        // This catches cases where sparkline is stale (hours old) and anchor has moved significantly
        let sparklineLast = clean.last ?? base
        let refVal: Double
        if let anchor = anchorPrice, anchor > 0, anchor.isFinite {
            if hours <= 1 {
                let divergence = abs(anchor - sparklineLast) / sparklineLast
                if divergence > 0.03 { return nil } // 3% threshold - sparkline is stale
            }
            refVal = anchor
        } else {
            refVal = sparklineLast
        }
        
        guard base > 0, refVal > 0, base.isFinite, refVal.isFinite else { return nil }
        
        let pct = ((refVal / base) - 1.0) * 100.0
        guard pct.isFinite else { return nil }
        
        // Timeframe-appropriate clamping
        let maxChange: Double = {
            if hours <= 1 { return 50.0 }
            if hours <= 24 { return 300.0 }
            return 500.0
        }()
        return max(-maxChange, min(maxChange, pct))
    }

    // PERFORMANCE FIX: Made @MainActor to safely access cached sparklines.
    // Uses in-memory cache that's refreshed periodically instead of calling
    // loadCachedSparklinesSync() on every call (which was blocking MainActor with disk I/O).
    @MainActor
    private func canonicalSeries(for coin: MarketCoin) -> [Double] {
        // STALE DATA FIX v23: CoinGecko sparklineIn7d is ALWAYS preferred — it's fresh
        // from Firestore and updated in real-time. The Binance disk cache may contain
        // data from previous sessions (days/weeks old) showing outdated trends.
        // Priority: CoinGecko (fresh from Firestore) > Binance cache (may be stale)
        
        // 1. CoinGecko sparkline (fresh from Firestore, 168 pts, 7D hourly)
        if !coin.sparklineIn7d.isEmpty {
            let clean = coin.sparklineIn7d.filter { $0.isFinite && $0 > 0 }
            if clean.count >= 24 { return clean }
        }
        
        // 2. Binance cache as fallback only when CoinGecko data is insufficient
        let now = Date()
        if now.timeIntervalSince(sparklineCacheLastLoadedAt) >= sparklineCacheRefreshInterval {
            cachedSparklines = WatchlistSparklineService.loadCachedSparklinesSync()
            sparklineCacheLastLoadedAt = now
        }
        
        if let binanceSpark = cachedSparklines[coin.id], binanceSpark.count >= 24 {
            let clean = binanceSpark.filter { $0.isFinite && $0 > 0 }
            if clean.count >= 24 { return clean }
        }
        
        // 3. Symbol-key fallback from Binance cache (exact key only).
        // Avoid broad substring matching here because it can map to the wrong asset.
        let symLower = coin.symbol.lowercased()
        if let symbolSpark = cachedSparklines[symLower], symbolSpark.count >= 24 {
            let clean = symbolSpark.filter { $0.isFinite && $0 > 0 }
            if clean.count >= 24 { return clean }
        }
        
        return []
    }

    private func derivedPercentFromSeries(_ series: [Double], hours: Double, anchorPrice: Double?) -> Double? {
        // Sanitize input and ensure we have enough samples to compute a change
        let clean = series.filter { $0.isFinite && $0 > 0 }
        guard clean.count >= 2 else { return nil }
        
        let n = clean.count

        // FIX: Unit ratio validation - reject mismatched sparkline/anchor units
        // This prevents absurd percentages (e.g., +313747%) when sparkline is normalized (0-1)
        // but anchor price is in USD (e.g., $2750)
        // Use timeframe-specific thresholds: stricter for 1H, more lenient for 7D
        if let anchor = anchorPrice, anchor > 0 {
            let windowCount = min(8, clean.count)
            let recent = Array(clean.suffix(windowCount)).sorted()
            let median = recent[windowCount / 2]
            let unitRatio = max(median, anchor) / max(1e-9, min(median, anchor))
            
            // Timeframe-specific thresholds: volatile assets can swing 50%+ in a week
            let maxUnitRatio: Double = {
                if hours <= 1 { return 1.3 }      // 1H: strict - prices shouldn't differ by 30%
                if hours <= 24 { return 1.8 }     // 24H: moderate - allow for daily volatility
                return 2.5                         // 7D: lenient - significant swings are possible
            }()
            
            if unitRatio > maxUnitRatio {
                if debugPercentSourcing {
                    logger.debug("[Pct] Unit ratio \(unitRatio) exceeds \(maxUnitRatio) for \(hours)h lookback - rejecting")
                }
                return nil
            }
        }

        // SMART STEP CALCULATION: Detect actual data coverage based on point count
        // instead of always assuming 7 days
        //
        // Common sparkline formats:
        // - 168 points (140-200): Hourly data over 7 days (Binance hourly klines)
        // - 42 points (35-55): 4-hour intervals over 7 days (Binance 4h klines)
        // - 7 points (5-14): Daily data over 7 days (Binance daily klines)
        // - Other: Calculate proportionally with validation
        
        let (estimatedTotalHours, stepHours): (Double, Double) = {
            if n >= 140 && n <= 200 {
                // Hourly data: ~168 points = 7 days
                // Each step = 1 hour
                let totalH = Double(n - 1)  // n-1 steps, each ~1 hour
                return (totalH, 1.0)
            } else if n >= 35 && n < 140 {
                // 4-hour interval data: ~42 points = 7 days
                // Each step = 4 hours
                let totalH = Double(n - 1) * 4.0
                return (totalH, 4.0)
            } else if n >= 5 && n < 35 {
                // Daily or sparse data: ~7 points = 7 days
                // Each step = 24 hours
                let totalH = Double(n - 1) * 24.0
                return (totalH, 24.0)
            } else {
                // Fallback: assume 7-day coverage (legacy behavior)
                let totalH = 24.0 * 7.0
                let step = totalH / Double(max(1, n - 1))
                return (totalH, step)
            }
        }()
        
        guard stepHours.isFinite && stepHours > 0 else { return nil }
        
        // CRITICAL FIX: Reject derivation when sparkline resolution is too coarse
        // If stepHours > hours, we CANNOT accurately derive the percentage
        // Example: Daily data (stepHours=24) cannot derive 1H change - would show 24H change as 1H!
        // This was causing BTC to show -5.61% for 1H when it should be ~0%
        if stepHours > hours {
            if debugPercentSourcing {
                logger.debug("[Pct] Resolution too coarse: stepHours=\(stepHours)h, requested=\(hours)h - skipping derivation")
            }
            return nil
        }
        
        // Validate that we have enough data coverage for the requested timeframe
        // For 1H lookback, we need at least 1 hour of data (1 step for hourly, less for 4h)
        // For 24H lookback, we need at least 24 hours of data
        let minimumCoverageRequired = hours * 0.8  // Require 80% of requested timeframe
        if estimatedTotalHours < minimumCoverageRequired {
            if debugPercentSourcing {
                logger.debug("[Pct] Insufficient coverage: \(estimatedTotalHours)h available, \(minimumCoverageRequired)h needed for \(hours)h lookback")
            }
            return nil
        }

        // Convert the hour window to a number of steps in the series
        let stepsBackRaw = hours / stepHours
        var stepsBack = Int(round(stepsBackRaw))
        if stepsBack < 1 { stepsBack = 1 }
        if stepsBack > n - 1 { stepsBack = n - 1 }

        let baseIndex = n - 1 - stepsBack
        let base = clean[baseIndex]
        
        // ACCURACY FIX: For short timeframes (1H), be conservative about anchor/sparkline mismatch
        // If the anchor price (live) differs significantly from sparkline's last point,
        // the sparkline is likely stale and the derivation would inflate the percentage.
        // Example: sparkline last=$2150 (2h old), live=$2230, 1h base=$2100
        // Bad: (2230-2100)/2100 = +6.2% (but actual 1h change is only +1.3%)
        // The mismatch indicates we're measuring over a longer window than intended.
        let sparklineLast = clean.last ?? base
        let anchor: Double
        if let a = anchorPrice, a.isFinite, a > 0 {
            // For 1H derivations, reject if anchor differs more than 3% from sparkline end
            // This catches cases where sparkline is stale (e.g., 2+ hours old)
            if hours <= 1 {
                let anchorSparklineDivergence = abs(a - sparklineLast) / sparklineLast
                if anchorSparklineDivergence > 0.03 { // 3% threshold
                    if debugPercentSourcing {
                        logger.debug("[Pct] Anchor diverges \(String(format: "%.1f", anchorSparklineDivergence * 100))% from sparkline end - rejecting 1h derivation for accuracy")
                    }
                    return nil // Reject: sparkline is likely stale
                }
            }
            anchor = a
        } else {
            anchor = sparklineLast
        }

        guard base > 0, anchor > 0 else { return nil }
        let pct = ((anchor / base) - 1.0) * 100.0
        guard pct.isFinite else { return nil }
        
        // FIX: Clamp output to reasonable bounds based on timeframe
        // This provides a safety net for any edge cases that slip past validation
        let maxChange: Double = {
            if hours <= 1 { return 50.0 }      // 1h: max ±50%
            if hours <= 24 { return 300.0 }    // 24h: max ±300%
            return 500.0                        // 7d+: max ±500%
        }()
        return max(-maxChange, min(maxChange, pct))
    }

    /// Replaced implementation per instructions
    private func derivePercentChange(from spark: [Double], overHours hours: Double) -> Double? {
        let series = spark.filter { $0.isFinite && $0 > 0 }
        guard series.count >= 3 else { return nil }
        return derivedPercentFromSeries(series, hours: hours, anchorPrice: series.last)
    }

    /// Derive percent change using coin's current price as anchor when available.
    /// PERFORMANCE FIX: Made @MainActor since canonicalSeries is now @MainActor.
    @MainActor
    private func derivedPercentFromCoin(_ coin: MarketCoin, hours: Double) -> Double? {
        let series = canonicalSeries(for: coin)
        guard !series.isEmpty else { return nil }
        return derivedPercentFromSeries(series, hours: hours, anchorPrice: coin.priceUsd)
    }

    /// Returns a copy of `coins` where 1h/24h percent fields are replaced by best-available values (provider or sidecar only).
    /// No sparkline derivation is performed here to keep emission work light on the MainActor.
    @MainActor private func augmentedCoinsWithDerivedPercents(_ coins: [MarketCoin]) -> [MarketCoin] {
        // MEMORY FIX: Periodically prune symbol caches to prevent unbounded growth
        pruneSymbolCachesIfNeeded()
        
        var out = coins

        var derived1hSyms: Set<String> = []
        var derived24hSyms: Set<String> = []
        var derived7dSyms: Set<String> = []
        var sanitizedSyms: Set<String> = []

        for i in 0..<out.count {
            let key = out[i].symbol.lowercased()
            // Sanitize obviously bad or duplicated provider percents (all equal/zero/non-finite/absurd)
            do {
                let p1 = out[i].priceChangePercentage1hInCurrency
                let p24 = out[i].priceChangePercentage24hInCurrency
                let p7 = out[i].priceChangePercentage7dInCurrency
                func approxEqual(_ a: Double?, _ b: Double?) -> Bool {
                    guard let a = a, let b = b else { return false }
                    return abs(a - b) < 0.0001
                }
                let allHave = (p1 != nil && p24 != nil && p7 != nil)
                let allEqual = allHave && approxEqual(p1, p24) && approxEqual(p1, p7)
                let allZero = allHave && abs(p1 ?? 0) < 1e-9 && abs(p24 ?? 0) < 1e-9 && abs(p7 ?? 0) < 1e-9
                let isNonFinite: (Double?) -> Bool = { v in
                    guard let v = v else { return false }
                    return !v.isFinite
                }
                let isAbsurd: (Double?) -> Bool = { v in
                    guard let v = v else { return false }
                    return v.isFinite && abs(v) > 10000
                }

                var n1 = p1
                var n24 = p24
                var n7 = p7

                if allEqual || allZero {
                    n1 = nil; n24 = nil; n7 = nil
                } else {
                    if isNonFinite(p1) || isAbsurd(p1) { n1 = nil }
                    if isNonFinite(p24) || isAbsurd(p24) { n24 = nil }
                    if isNonFinite(p7) || isAbsurd(p7) { n7 = nil }
                }

                if n1 != p1 || n24 != p24 || n7 != p7 {
                    if debugPercentSourcing {
                        var reasons: [String] = []
                        if allEqual { reasons.append("allEqual") }
                        if allZero { reasons.append("allZero") }
                        if isNonFinite(p1) || isNonFinite(p24) || isNonFinite(p7) { reasons.append("nonFinite") }
                        if isAbsurd(p1) || isAbsurd(p24) || isAbsurd(p7) { reasons.append("absurd") }
                        logger.debug("[Pct] Sanitized provider percents for \(out[i].symbol, privacy: .public) reasons=\(reasons.joined(separator: ","), privacy: .public)")
                    }
                    let c = out[i]
                    out[i] = MarketCoin(
                        id: c.id,
                        symbol: c.symbol,
                        name: c.name,
                        imageUrl: c.imageUrl,
                        priceUsd: c.priceUsd,
                        marketCap: c.marketCap,
                        totalVolume: c.totalVolume,
                        priceChangePercentage1hInCurrency: n1,
                        priceChangePercentage24hInCurrency: n24,
                        priceChangePercentage7dInCurrency: n7,
                        sparklineIn7d: c.sparklineIn7d,
                        marketCapRank: c.marketCapRank,
                        maxSupply: c.maxSupply,
                        circulatingSupply: c.circulatingSupply,
                        totalSupply: c.totalSupply
                    )
                    sanitizedSyms.insert(out[i].symbol.lowercased())
                }
            }
            // Clamp provider 24h percent for stables if present
            if let existing24 = out[i].priceChangePercentage24hInCurrency {
                let c = out[i]
                let clamped = clampStable24h(symbol: c.symbol, value: existing24)
                if clamped != existing24 {
                    out[i] = MarketCoin(
                        id: c.id,
                        symbol: c.symbol,
                        name: c.name,
                        imageUrl: c.imageUrl,
                        priceUsd: c.priceUsd,
                        marketCap: c.marketCap,
                        totalVolume: c.totalVolume,
                        priceChangePercentage1hInCurrency: c.priceChangePercentage1hInCurrency,
                        priceChangePercentage24hInCurrency: clamped,
                        priceChangePercentage7dInCurrency: c.priceChangePercentage7dInCurrency,
                        sparklineIn7d: c.sparklineIn7d,
                        marketCapRank: c.marketCapRank,
                        maxSupply: c.maxSupply,
                        circulatingSupply: c.circulatingSupply,
                        totalSupply: c.totalSupply
                    )
                }
            }
            // 1h percent: prefer provider, else sidecar, else derive from sparkline
            if out[i].priceChangePercentage1hInCurrency == nil {
                if let cached1h = safeGet1hChange(key) {
                    let c = out[i]
                    out[i] = MarketCoin(
                        id: c.id,
                        symbol: c.symbol,
                        name: c.name,
                        imageUrl: c.imageUrl,
                        priceUsd: c.priceUsd,
                        marketCap: c.marketCap,
                        totalVolume: c.totalVolume,
                        priceChangePercentage1hInCurrency: cached1h,
                        priceChangePercentage24hInCurrency: c.priceChangePercentage24hInCurrency,
                        priceChangePercentage7dInCurrency: c.priceChangePercentage7dInCurrency,
                        sparklineIn7d: c.sparklineIn7d,
                        marketCapRank: c.marketCapRank,
                        maxSupply: c.maxSupply,
                        circulatingSupply: c.circulatingSupply,
                        totalSupply: c.totalSupply
                    )
                    if debugPercentSourcing { logger.debug("[Pct] 1h from sidecar for \(c.symbol, privacy: .public)") }
                } else if let derived1h = derivedPercentFromCoin(out[i], hours: 1) {
                    let c = out[i]
                    out[i] = MarketCoin(
                        id: c.id,
                        symbol: c.symbol,
                        name: c.name,
                        imageUrl: c.imageUrl,
                        priceUsd: c.priceUsd,
                        marketCap: c.marketCap,
                        totalVolume: c.totalVolume,
                        priceChangePercentage1hInCurrency: derived1h,
                        priceChangePercentage24hInCurrency: c.priceChangePercentage24hInCurrency,
                        priceChangePercentage7dInCurrency: c.priceChangePercentage7dInCurrency,
                        sparklineIn7d: c.sparklineIn7d,
                        marketCapRank: c.marketCapRank,
                        maxSupply: c.maxSupply,
                        circulatingSupply: c.circulatingSupply,
                        totalSupply: c.totalSupply
                    )
                    safeSet1hChange(key, derived1h)
                    if debugPercentSourcing { logger.debug("[Pct] 1h derived for \(c.symbol, privacy: .public)") }
                    schedulePercentSidecarSave()
                    derived1hSyms.insert(c.symbol.lowercased())
                }
            }
            // 24h percent: prefer provider, else sidecar, else derive from sparkline
            if out[i].priceChangePercentage24hInCurrency == nil {
                if let cached24h = safeGet24hChange(key) {
                    let c = out[i]
                    out[i] = MarketCoin(
                        id: c.id,
                        symbol: c.symbol,
                        name: c.name,
                        imageUrl: c.imageUrl,
                        priceUsd: c.priceUsd,
                        marketCap: c.marketCap,
                        totalVolume: c.totalVolume,
                        priceChangePercentage1hInCurrency: c.priceChangePercentage1hInCurrency,
                        priceChangePercentage24hInCurrency: clampStable24h(symbol: c.symbol, value: cached24h),
                        priceChangePercentage7dInCurrency: c.priceChangePercentage7dInCurrency,
                        sparklineIn7d: c.sparklineIn7d,
                        marketCapRank: c.marketCapRank,
                        maxSupply: c.maxSupply,
                        circulatingSupply: c.circulatingSupply,
                        totalSupply: c.totalSupply
                    )
                    if debugPercentSourcing { logger.debug("[Pct] 24h from sidecar for \(c.symbol, privacy: .public)") }
                } else if let derived24h = derivedPercentFromCoin(out[i], hours: 24) {
                    let c = out[i]
                    out[i] = MarketCoin(
                        id: c.id,
                        symbol: c.symbol,
                        name: c.name,
                        imageUrl: c.imageUrl,
                        priceUsd: c.priceUsd,
                        marketCap: c.marketCap,
                        totalVolume: c.totalVolume,
                        priceChangePercentage1hInCurrency: c.priceChangePercentage1hInCurrency,
                        priceChangePercentage24hInCurrency: clampStable24h(symbol: c.symbol, value: derived24h),
                        priceChangePercentage7dInCurrency: c.priceChangePercentage7dInCurrency,
                        sparklineIn7d: c.sparklineIn7d,
                        marketCapRank: c.marketCapRank,
                        maxSupply: c.maxSupply,
                        circulatingSupply: c.circulatingSupply,
                        totalSupply: c.totalSupply
                    )
                    safeSet24hChange(key, derived24h)
                    if debugPercentSourcing { logger.debug("[Pct] 24h derived for \(c.symbol, privacy: .public)") }
                    schedulePercentSidecarSave()
                    derived24hSyms.insert(c.symbol.lowercased())
                }
            }
            // 7d percent: prefer provider, else sidecar, else derive from sparkline
            if out[i].priceChangePercentage7dInCurrency == nil {
                if let cached7d = safeGet7dChange(key) {
                    let c = out[i]
                    out[i] = MarketCoin(
                        id: c.id,
                        symbol: c.symbol,
                        name: c.name,
                        imageUrl: c.imageUrl,
                        priceUsd: c.priceUsd,
                        marketCap: c.marketCap,
                        totalVolume: c.totalVolume,
                        priceChangePercentage1hInCurrency: c.priceChangePercentage1hInCurrency,
                        priceChangePercentage24hInCurrency: c.priceChangePercentage24hInCurrency,
                        priceChangePercentage7dInCurrency: cached7d,
                        sparklineIn7d: c.sparklineIn7d,
                        marketCapRank: c.marketCapRank,
                        maxSupply: c.maxSupply,
                        circulatingSupply: c.circulatingSupply,
                        totalSupply: c.totalSupply
                    )
                    if debugPercentSourcing { logger.debug("[Pct] 7d from sidecar for \(c.symbol, privacy: .public)") }
                } else if let derived7d = derivedPercentFromCoin(out[i], hours: 24*7) {
                    let c = out[i]
                    out[i] = MarketCoin(
                        id: c.id,
                        symbol: c.symbol,
                        name: c.name,
                        imageUrl: c.imageUrl,
                        priceUsd: c.priceUsd,
                        marketCap: c.marketCap,
                        totalVolume: c.totalVolume,
                        priceChangePercentage1hInCurrency: c.priceChangePercentage1hInCurrency,
                        priceChangePercentage24hInCurrency: c.priceChangePercentage24hInCurrency,
                        priceChangePercentage7dInCurrency: derived7d,
                        sparklineIn7d: c.sparklineIn7d,
                        marketCapRank: c.marketCapRank,
                        maxSupply: c.maxSupply,
                        circulatingSupply: c.circulatingSupply,
                        totalSupply: c.totalSupply
                    )
                    safeSet7dChange(key, derived7d)
                    if debugPercentSourcing { logger.debug("[Pct] 7d derived for \(c.symbol, privacy: .public)") }
                    schedulePercentSidecarSave()
                    derived7dSyms.insert(c.symbol.lowercased())
                }
            }
            if out[i].priceChangePercentage24hInCurrency == nil || out[i].priceChangePercentage7dInCurrency == nil {
                scheduleHistoryDerivationIfNeeded(for: out[i])
            }
        }

        // Update last sanitized set and emit a QA pulse if any derived values were applied this pass
        lastSanitizedSymbols = sanitizedSyms
        let unionSyms = derived1hSyms.union(derived24hSyms).union(derived7dSyms)
        if !unionSyms.isEmpty {
            var kinds: Set<DerivedKind> = []
            if !derived1hSyms.isEmpty { kinds.insert(.h1) }
            if !derived24hSyms.isEmpty { kinds.insert(.h24) }
            if !derived7dSyms.isEmpty { kinds.insert(.d7) }
            if !sanitizedSyms.isEmpty { kinds.insert(.sanitized) }
            let pulse = DerivedUsagePulse(timestamp: Date(), symbols: Array(unionSyms).sorted(), kinds: kinds)
            derivedUsageSubject.send(pulse)
        }

        return out
    }

    // MARK: - Coalesced emission
    /// Coalesces and throttles emissions to reduce UI churn.
    /// Ensures execution on the main queue and respects `minEmitSpacing`.
    /// Note: Internal access for FirestoreMarketSync extension to use
    /// PERFORMANCE FIX: Now uses background processing for heavy augmentation
    ///
    /// FIX v23: Added input-side debounce (300ms) to coalesce rapid-fire calls from
    /// multiple data sources (Firestore tickers, CoinGecko, overlay) that fire within
    /// milliseconds of each other. Previously each call spawned a separate
    /// Task.detached for 250-coin augmentation; now they're batched into one.
    @MainActor private var emitCoinsDebounceTask: Task<Void, Never>?
    @MainActor private var latestCoinsForEmission: [MarketCoin]?
    
    // MEMORY FIX v4: Gate to prevent overlapping augmentation tasks.
    // Without this, rapid data arrivals (Firestore + overlay + history derivation)
    // spawn unbounded Task.detached closures, each holding ~1 MB of coin arrays
    // and cache snapshots. Over 86 seconds, hundreds of overlapping tasks
    // accumulated 3+ GB of retained closures, causing jetsam kill.
    @MainActor private var isAugmentationInFlight: Bool = false
    
    // MEMORY FIX v5: Counter to track emission cycles for diagnostics
    @MainActor private var emissionCycleCount: Int = 0
    
    @MainActor func emitCoins(_ coins: [MarketCoin]) {
        let coins = capCoinsForProcessing(coins)
        // PERFORMANCE FIX: If there's already a pending emission, just update the raw coins
        // and let the scheduled emission handle processing
        if scheduledEmitWorkItem != nil {
            pendingRawCoins = coins
            return
        }
        
        // MEMORY FIX v4: If augmentation is already in flight, just store latest coins.
        // The completion of the current augmentation will NOT recursively spawn another —
        // instead, the next natural emitCoins call will pick up the latest data.
        if isAugmentationInFlight {
            latestCoinsForEmission = coins
            return
        }
        
        // MEMORY FIX v5: Log emission cycles with memory for diagnostics
        emissionCycleCount += 1
        if emissionCycleCount <= 10 || emissionCycleCount % 5 == 0 {
            var _memInfo = mach_task_basic_info()
            var _memCount = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
            let _ = withUnsafeMutablePointer(to: &_memInfo) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(_memCount)) {
                    task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &_memCount)
                }
            }
            let mb = Double(_memInfo.resident_size) / (1024 * 1024)
            logger.info("📡 EMIT #\(self.emissionCycleCount): \(coins.count) coins, \(String(format: "%.0f", mb)) MB, augInFlight=\(self.isAugmentationInFlight)")
            
            // Memory safety: only block when available memory is known AND critically low,
            // or when resident memory is extreme. Avail==0 means unknown (simulator), proceed.
            let _availMB = Double(os_proc_available_memory()) / (1024 * 1024)
            let availKnown = _availMB > 0
            let blockByAvail = availKnown && _availMB < 200
            let usedMemoryThresholdMB: Double = 1500.0
            let blockByUsed = mb > usedMemoryThresholdMB
            let shouldBlock = blockByAvail || blockByUsed
            if shouldBlock {
                logger.warning("🚨 EMIT BLOCKED: \(String(format: "%.0f", mb)) MB used, \(String(format: "%.0f", _availMB)) MB avail. Dropping emission to protect against jetsam.")
                handleMemoryWarning()
                return
            }
        }
        
        // FIX v23: Input-side debounce — store the latest coins and schedule processing
        // after a 300ms window. Multiple calls within the window coalesce into one.
        latestCoinsForEmission = coins
        emitCoinsDebounceTask?.cancel()
        emitCoinsDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms coalesce window
            guard !Task.isCancelled, let self = self else { return }
            guard let coinsToEmit = self.latestCoinsForEmission else { return }
            self.latestCoinsForEmission = nil
            self.emitCoinsDebounceTask = nil
            
            // MEMORY FIX v4: Prevent overlapping background tasks
            guard !self.isAugmentationInFlight else { return }
            self.isAugmentationInFlight = true
            
            // PERFORMANCE FIX: Capture cache snapshot on MainActor (fast - just copying dictionaries)
            let snapshot = self.capturePercentCacheSnapshot()
            
            // PERFORMANCE FIX: Process coins on background thread to avoid blocking UI
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                
                // Heavy processing happens on background thread
                let result = self.augmentCoinsInBackground(coinsToEmit, snapshot: snapshot)
                
                // Return to MainActor for state updates and emission
                await MainActor.run {
                    self.isAugmentationInFlight = false
                    self.finishEmission(
                        enrichedCoins: result.coins,
                        derived1hSyms: result.derived1h,
                        derived24hSyms: result.derived24h,
                        derived7dSyms: result.derived7d,
                        sanitizedSyms: result.sanitized
                    )
                    
                    // MEMORY FIX v4: After finishing, check if new coins arrived while
                    // we were processing. If so, schedule them through the normal pipeline
                    // (with debounce) rather than recursively spawning another Task.detached.
                    if let waiting = self.latestCoinsForEmission {
                        self.latestCoinsForEmission = nil
                        self.emitCoins(waiting)
                    }
                }
            }
        }
    }
    
    /// Raw coins waiting to be processed (for coalescing during background processing)
    @MainActor private var pendingRawCoins: [MarketCoin]?
    
    /// PERFORMANCE FIX: Complete emission on MainActor after background processing
    @MainActor private func finishEmission(
        enrichedCoins: [MarketCoin],
        derived1hSyms: Set<String>,
        derived24hSyms: Set<String>,
        derived7dSyms: Set<String>,
        sanitizedSyms: Set<String>
    ) {
        let enriched = enrichedCoins
        
        // MEMORY FIX v4: If new raw coins arrived during background processing,
        // DON'T recursively spawn another Task.detached. Instead, stash them in
        // latestCoinsForEmission so the augmentation completion callback picks them up.
        // The old recursive pattern spawned unbounded chains of Task.detached calls,
        // each holding ~1 MB of retained closures (coin arrays + cache snapshots).
        // Over 86 seconds, this accumulated 3+ GB of memory.
        if let pending = pendingRawCoins {
            pendingRawCoins = nil
            // Stash for the augmentation completion callback (NOT emitCoins — that would
            // double-schedule since the callback also checks latestCoinsForEmission).
            latestCoinsForEmission = pending
            // Still process the CURRENT enriched coins below (don't return early)
        }
        
        // Update caches with derived values
        for sym in derived1hSyms {
            if let coin = enriched.first(where: { $0.symbol.lowercased() == sym }),
               let val = coin.priceChangePercentage1hInCurrency {
                safeSet1hChange(sym, val)
            }
        }
        for sym in derived24hSyms {
            if let coin = enriched.first(where: { $0.symbol.lowercased() == sym }),
               let val = coin.priceChangePercentage24hInCurrency {
                safeSet24hChange(sym, val)
            }
        }
        for sym in derived7dSyms {
            if let coin = enriched.first(where: { $0.symbol.lowercased() == sym }),
               let val = coin.priceChangePercentage7dInCurrency {
                safeSet7dChange(sym, val)
            }
        }
        
        // Schedule sidecar save if we derived any values
        if !derived1hSyms.isEmpty || !derived24hSyms.isEmpty || !derived7dSyms.isEmpty {
            schedulePercentSidecarSave()
        }
        
        // Update last sanitized set and emit QA pulse
        lastSanitizedSymbols = sanitizedSyms
        let unionSyms = derived1hSyms.union(derived24hSyms).union(derived7dSyms)
        if !unionSyms.isEmpty {
            var kinds: Set<DerivedKind> = []
            if !derived1hSyms.isEmpty { kinds.insert(.h1) }
            if !derived24hSyms.isEmpty { kinds.insert(.h24) }
            if !derived7dSyms.isEmpty { kinds.insert(.d7) }
            if !sanitizedSyms.isEmpty { kinds.insert(.sanitized) }
            let pulse = DerivedUsagePulse(timestamp: Date(), symbols: Array(unionSyms).sorted(), kinds: kinds)
            derivedUsageSubject.send(pulse)
        }
        
        // Schedule history derivation for coins still missing data
        for coin in enriched {
            if coin.priceChangePercentage24hInCurrency == nil || coin.priceChangePercentage7dInCurrency == nil {
                scheduleHistoryDerivationIfNeeded(for: coin)
            }
        }
        
        // One-time cold-start: proactively derive history for top symbols with missing/sanitized percents
        if !didRunColdStartHistoryDerivation {
            self.coldStartKickHistoryDerivationIfNeeded(on: enriched)
        }

        let now = Date()
        let since = lastEmitAt.map { now.timeIntervalSince($0) } ?? .infinity

        // Check if there's already a scheduled emission
        if scheduledEmitWorkItem != nil {
            pendingCoins = enriched
            return
        }

        // Distinct-until-changed guard vs last emitted snapshot
        if !lastEmittedBySymbol.isEmpty {
            var newMap: [String: Double] = [:]
            newMap.reserveCapacity(enriched.count)
            for c in enriched {
                let key = c.symbol.lowercased()
                let price = (c.priceUsd?.isFinite == true && (c.priceUsd ?? 0) > 0) ? (c.priceUsd ?? 0) : 0
                newMap[key] = price
            }
            let oldKeys = Set(lastEmittedBySymbol.keys)
            let newKeys = Set(newMap.keys)
            var meaningful = false
            if oldKeys != newKeys {
                meaningful = true
            } else {
                // PERFORMANCE FIX: Increased from 0.22% to 0.35% to reduce UI churn
                let relThreshold = 0.0035 // ~0.35%, higher threshold to reduce update frequency
                for (k, newP) in newMap {
                    let oldP = lastEmittedBySymbol[k] ?? 0
                    if (oldP <= 0 && newP > 0) || (oldP > 0 && newP <= 0) { meaningful = true; break }
                    if oldP > 0 && newP > 0 {
                        let rel = abs(newP - oldP) / max(1e-9, max(abs(newP), abs(oldP)))
                        if rel >= relThreshold { meaningful = true; break }
                    }
                }
            }
            if !meaningful {
                // Update internal state so sidecar lookups read derived percents, but skip scheduling a send
                self.currentCoins = enriched
                return
            }
        }

        pendingCoins = enriched
        let baseDelay = since >= minEmitSpacing ? 0 : max(0, minEmitSpacing - since)
        // PERFORMANCE FIX: Increased minimum delay from 0.02s to 0.10s (100ms)
        // This reduces rapid-fire emissions that cause UI jank during scroll
        let delay: TimeInterval = max(0.10, baseDelay)

        // CRASH FIX: Use Task instead of DispatchWorkItem to ensure MainActor isolation
        scheduledEmitWorkItem = DispatchWorkItem { }  // Placeholder to track scheduling
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self = self else { return }
            
            let payload = self.pendingCoins ?? enriched
            self.pendingCoins = nil
            self.scheduledEmitWorkItem = nil
            // Store the enriched payload so bestChange* lookups read derived percents as well
            self.currentCoins = payload
            
            var outMap: [String: Double] = [:]
            outMap.reserveCapacity(payload.count)
            for c in payload {
                let key = c.symbol.lowercased()
                let price = (c.priceUsd?.isFinite == true && (c.priceUsd ?? 0) > 0) ? (c.priceUsd ?? 0) : 0
                outMap[key] = price
            }
            self.lastEmittedBySymbol = outMap

            // PERFORMANCE FIX: Use scroll-aware emission to avoid UI jank during scroll
            self.emitCoinsIfAppropriate(payload)
            self.lastEmitAt = Date()

            // Opportunistically prime missing volumes for top coins without blocking UI
            self.scheduleVolumePrimeIfNeeded(payload)
        }
    }

    // MARK: - Sidecar persistence (simplified - no async Tasks)
    @MainActor private func schedulePercentSidecarSave() {
        // Debounce percent cache save - uses the new simplified batch save approach
        percentSidecarSaveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            // This runs on main queue, safe to call MainActor method
            self?.savePercentCacheIfNeeded()
        }
        percentSidecarSaveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + percentSidecarSaveDebounce, execute: work)
    }

    // MARK: - Volume priming

    /// Prime 24h USD-equivalent volume for a single base symbol if missing.
    /// Uses a gate and cooldown to avoid bursts and updates the sidecar cache on success.
    /// Tries Binance first, then Coinbase as fallback for broader coverage.
    @MainActor
    func primeVolumeIfNeeded(for base: String, reason: VolumePrimeReason = .emission) {
        let symLower = base.lowercased()
        // If we already have a positive cached volume, nothing to do
        if (latestVolumeUSDBySymbol[symLower] ?? 0) > 0 { return }

        Task { [weak self] in
            guard let self = self else { return }
            let canStart = await self.volumeGate.shouldStart(symbol: symLower, cooldown: self.volumeAttemptCooldown)
            guard canStart else { return }

            var vol: Double? = nil
            
            // Try Binance 24h ticker volume for best USD-like quote
            if let binanceVol = await self.binanceTicker24hrVolumeUSDForBestQuote(base: base), binanceVol.isFinite, binanceVol > 0 {
                vol = binanceVol
            }
            
            // Fallback to Coinbase if Binance didn't provide volume
            if vol == nil || vol == 0 {
                if let coinbaseStats = await CoinbaseService.shared.fetch24hStats(coin: base.uppercased(), fiat: "USD"),
                   let coinbaseVol = coinbaseStats.volume, coinbaseVol.isFinite, coinbaseVol > 0 {
                    vol = coinbaseVol
                }
            }
            
            // If we got volume from either source, update the cache
            if let vol = vol, vol.isFinite, vol > 0 {
                await MainActor.run {
                    // Update sidecar cache
                    self.safeSetVolumeUSD(symLower, vol)
                    self.volumeCacheIsDirty = true  // Mark for persistence

                    // Opportunistically patch into currentCoins if provider volume is missing
                    var updated = self.currentCoins
                    for i in 0..<updated.count where updated[i].symbol.lowercased() == symLower {
                        let c = updated[i]
                        if (c.totalVolume ?? 0) <= 0 {
                            updated[i] = MarketCoin(
                                id: c.id,
                                symbol: c.symbol,
                                name: c.name,
                                imageUrl: c.imageUrl,
                                priceUsd: c.priceUsd,
                                marketCap: c.marketCap,
                                totalVolume: vol,
                                priceChangePercentage1hInCurrency: c.priceChangePercentage1hInCurrency,
                                priceChangePercentage24hInCurrency: c.priceChangePercentage24hInCurrency,
                                priceChangePercentage7dInCurrency: c.priceChangePercentage7dInCurrency,
                                sparklineIn7d: c.sparklineIn7d,
                                marketCapRank: c.marketCapRank,
                                maxSupply: c.maxSupply,
                                circulatingSupply: c.circulatingSupply,
                                totalSupply: c.totalSupply
                            )
                            self.currentCoins = updated // do not emit; next pass will include it
                        }
                        break
                    }

                    // QA pulse for visibility
                    let pulse = VolumePrimePulse(timestamp: Date(), symbols: [symLower], reason: reason)
                    self.volumePrimeSubject.send(pulse)
                }
            }
            await self.volumeGate.finish(symbol: symLower)
        }
    }

    /// Coalesced volume priming for the current viewport. Throttled to avoid frequent bursts.
    @MainActor
    private func scheduleVolumePrimeIfNeeded(_ coins: [MarketCoin]) {
        let now = Date()
        if let last = lastVolumePrimeAt, now.timeIntervalSince(last) < volumePrimeMinInterval { return }
        lastVolumePrimeAt = now

        // Select a small set of top symbols that still lack volume information
        var targets: [String] = []
        targets.reserveCapacity(16)
        for c in coins {
            let lower = c.symbol.lowercased()
            let haveSidecar = (latestVolumeUSDBySymbol[lower] ?? 0) > 0
            let haveProvider = (c.totalVolume ?? 0) > 0
            if !haveSidecar && !haveProvider {
                targets.append(c.symbol.uppercased())
            }
            if targets.count >= 16 { break }
        }
        if targets.isEmpty { return }

        // Fire individual primes (gated) without blocking UI
        for base in targets {
            primeVolumeIfNeeded(for: base, reason: .viewport)
        }

        // Emit a single aggregated QA pulse for this batch
        let pulse = VolumePrimePulse(timestamp: Date(), symbols: targets.map { $0.lowercased() }, reason: .viewport)
        volumePrimeSubject.send(pulse)
    }

    // MARK: - Cold-start helpers

    /// On first emission, proactively kick history derivation for top coins with missing/sanitized percent changes.
    @MainActor
    private func coldStartKickHistoryDerivationIfNeeded(on coins: [MarketCoin]) {
        if didRunColdStartHistoryDerivation { return }
        didRunColdStartHistoryDerivation = true

        // Build candidate list: missing 24h/7d or previously sanitized provider values
        let sanitized = lastSanitizedSymbols
        var ranked: [(coin: MarketCoin, rank: Int)] = []
        ranked.reserveCapacity(coins.count)
        for c in coins {
            let symLower = c.symbol.lowercased()
            let missing = (c.priceChangePercentage24hInCurrency == nil) || (c.priceChangePercentage7dInCurrency == nil) || sanitized.contains(symLower)
            if missing {
                let r = bestRank(for: c) ?? Int.max
                ranked.append((c, r))
            }
        }
        if ranked.isEmpty { return }

        // Prefer highest-ranked assets first
        ranked.sort { $0.rank < $1.rank }
        // MEMORY FIX v4: Reduced from 20 to 5 concurrent history derivations.
        // Each derivation spawns a Task that fetches price history via HTTP,
        // holding the response data in memory. With 20 concurrent derivations,
        // the accumulated response data contributed to memory pressure.
        let top = ranked.prefix(5).map { $0.coin }
        for coin in top {
            scheduleHistoryDerivationIfNeeded(for: coin)
        }
    }

    // MARK: - Provider overlay arbitration
    /// Decide whether a provider-sourced price can be applied over the current price,
    /// taking into account recent direct prices and a cooldown to avoid tiny-delta thrash.
    @MainActor
    private func canApplyProviderPrice(symLower: String, candidate: Double, old: Double?) -> Bool {
        guard candidate.isFinite, candidate > 0 else { return false }
        
        // If seeding from zero/missing price, accept any positive candidate immediately.
        if !(old?.isFinite == true && (old ?? 0) > 0) {
            return true
        }

        let now = Date()

        // Avoid rapid re-application with tiny deltas within cooldown
        if let lastApply = lastProviderApplyAt[symLower] {
            let elapsed = now.timeIntervalSince(lastApply)
            if elapsed < providerApplyCooldownSeconds {
                if let old = old, old.isFinite, old > 0 {
                    if !shouldAcceptPrice(old: old, new: candidate) {
                        if debugArbitration { logger.debug("[Arb] cooldown block for \(symLower)") }
                        return false
                    }
                }
            }
        }

        // Prefer recent direct (WS) prices over provider overlays for a short holdoff
        if let dAt = lastDirectAt[symLower], let dPrice = lastDirectPriceBySymbol[symLower], dPrice.isFinite, dPrice > 0 {
            let age = now.timeIntervalSince(dAt)
            if age < directHoldoffSeconds {
                // If we already have a valid price, do not override during the holdoff window
                if let old = old, old.isFinite, old > 0 {
                    if debugArbitration { logger.debug("[Arb] block provider for \(symLower) due to recent direct price") }
                    return false
                } else {
                    // If we're seeding from zero, only accept if very close to the recent direct value
                    let rel = abs(candidate - dPrice) / max(1e-9, max(abs(candidate), abs(dPrice)))
                    if rel > 0.005 { // 0.5%
                        if debugArbitration { logger.debug("[Arb] seed block for \(symLower) candidate far from direct") }
                        return false
                    }
                }
            }
        }

        // Default: accept if the change is meaningful, or we are seeding a missing/zero price
        if let old = old, old.isFinite, old > 0 {
            return shouldAcceptPrice(old: old, new: candidate)
        } else {
            return true
        }
    }

    // MARK: - Diffing & threshold helpers
    
    /// PRICE CONSISTENCY FIX: Check if a price is acceptable compared to recent median
    /// This prevents large price jumps when switching between sources (e.g., $74k vs $76k for BTC)
    @MainActor
    private func isAcceptablePriceVsMedian(symbol: String, newPrice: Double) -> Bool {
        let buffer = priceMedianBuffer[symbol] ?? []
        guard buffer.count >= 3 else { return true }  // Need at least 3 prices to calculate median
        
        let sorted = buffer.sorted()
        let median: Double
        if sorted.count % 2 == 0 {
            median = (sorted[sorted.count/2 - 1] + sorted[sorted.count/2]) / 2.0
        } else {
            median = sorted[sorted.count/2]
        }
        
        // Reject prices that deviate more than 5% from median
        // For BTC at $76k, this is ~$3800 - enough to filter bad data but allow real moves
        let deviation = abs(newPrice - median) / max(median, 1e-9)
        let maxDeviation: Double = 0.05  // 5% threshold
        
        return deviation <= maxDeviation
    }
    
    /// PRICE CONSISTENCY FIX: Record a price in the median buffer for a symbol
    @MainActor
    private func recordPriceInMedianBuffer(symbol: String, price: Double) {
        var buffer = priceMedianBuffer[symbol] ?? []
        buffer.append(price)
        if buffer.count > priceBufferSize {
            buffer.removeFirst()
        }
        priceMedianBuffer[symbol] = buffer
    }
    
    /// Decide whether to accept a new price over an old price based on relative delta.
    /// Used by both direct (WS) updates and provider overlays to avoid tiny-delta thrash.
    /// PRICE CONSISTENCY FIX: Also rejects outliers that deviate too much from recent prices
    @inline(__always)
    private func shouldAcceptPrice(old: Double?, new: Double) -> Bool {
        guard new.isFinite, new > 0 else { return false }
        guard let old = old, old.isFinite, old > 0 else { return true }

        let maxMag = max(abs(old), abs(new))
        if maxMag <= 0 { return true }
        let absDiff = abs(new - old)
        let rel = absDiff / max(1e-9, maxMag)

        // PRICE CONSISTENCY FIX: Reject outliers that deviate more than 3% from old price
        // This prevents $2000 jumps on BTC (~2.5% at $80k) from source switching
        // Real market moves this large take time; sudden jumps are usually source discrepancies
        let maxDeviationThreshold = 0.03 // 3% max jump allowed
        if rel > maxDeviationThreshold {
            // Log but don't spam - this is a significant event
            return false  // Reject outlier
        }

        // Updated threshold per instructions - minimum change to emit
        let relThreshold = 0.0015 // 0.15%

        if rel >= relThreshold { return true }

        // For very small prices, allow a tiny absolute epsilon to register
        if maxMag < 0.1, absDiff > 0.00005 { return true }

        return false
    }

    /// Returns true if `new` differs from `old` enough to warrant emitting to the UI.
    /// Compares symbol membership and price deltas with a conservative threshold.
    private func hasMeaningfulPriceChange(old: [MarketCoin], new: [MarketCoin]) -> Bool {
        // Quick empty vs non-empty checks
        if old.isEmpty && !new.isEmpty { return true }
        if !old.isEmpty && new.isEmpty { return true }

        // Compare symbol sets
        let oldKeys = Set(old.map { $0.symbol.lowercased() })
        let newKeys = Set(new.map { $0.symbol.lowercased() })
        if oldKeys != newKeys { return true }

        // Build lookup of old prices
        var oldBySymbol: [String: Double] = [:]
        oldBySymbol.reserveCapacity(old.count)
        for c in old {
            let key = c.symbol.lowercased()
            if let p = c.priceUsd, p.isFinite, p > 0 {
                oldBySymbol[key] = p
            } else {
                oldBySymbol[key] = 0
            }
        }

        // PERFORMANCE FIX: Increased from 0.22% to 0.35% to reduce UI churn
        let relThreshold = 0.0035 // ~0.35%
        for c in new {
            let key = c.symbol.lowercased()
            let newP = (c.priceUsd?.isFinite == true && (c.priceUsd ?? 0) > 0) ? (c.priceUsd ?? 0) : 0
            let oldP = oldBySymbol[key] ?? 0

            // Transition between zero and non-zero is always meaningful
            if (oldP <= 0 && newP > 0) || (oldP > 0 && newP <= 0) { return true }

            if oldP > 0 && newP > 0 {
                let rel = abs(newP - oldP) / max(1e-9, max(abs(newP), abs(oldP)))
                if rel >= relThreshold { return true }
            }
        }
        return false
    }

    /// Best-available rank for a given coin (provider value preferred; falls back to derived by market cap)
    @MainActor
    func bestRank(for coin: MarketCoin) -> Int? {
        return coin.marketCapRank ?? derivedRankByID[coin.id]
    }

    /// Best-available max supply for a given coin (provider value preferred; falls back to total/circulating supply)
    @MainActor
    func bestMaxSupply(for coin: MarketCoin) -> Double? {
        return coin.maxSupply ?? derivedMaxSupplyByID[coin.id]
    }
    
    // MARK: - Best volume lookup
    /// Best-available 24h USD-equivalent volume for a coin.
    /// Prefers provider aggregate volume, then sidecar cache fallback.
    /// Returns nil if unavailable - callers should use primeVolumeIfNeeded in lifecycle hooks if needed.
    @MainActor
    func bestVolumeUSD(for coin: MarketCoin) -> Double? {
        // 1) Provider aggregate volume first (do not blank/override with venue-only values).
        if let v = coin.totalVolume, v.isFinite, v > 0 { return v }
        if let v = coin.volumeUsd24Hr, v.isFinite, v > 0 { return v }

        // 2) Sidecar cache lookup by symbol (freshness-gated).
        let key = coin.symbol.lowercased()
        if let v = latestVolumeUSDBySymbol[key], v.isFinite, v > 0 {
            if isFreshSidecarValue(updatedAt: lastVolumeUpdatedAt[key], maxAge: maxVolumeSidecarReadAge) {
                return v
            }
            recordStaleSuppression(.sidecarVolume, symbol: key)
            latestVolumeUSDBySymbol.removeValue(forKey: key)
            lastVolumeUpdatedAt.removeValue(forKey: key)
        }
        // No side effects during getter beyond telemetry; callers should explicitly prime in lifecycle hooks.
        return nil
    }
    
    /// Returns the best available volume for a symbol, checking all caches.
    /// Use this for display when you don't have a MarketCoin object.
    @MainActor
    func bestVolumeUSD(forSymbol symbol: String) -> Double? {
        let key = symbol.lowercased()
        // 1) Prefer provider aggregate volume from current coin snapshots.
        if let coin = currentCoins.first(where: { $0.symbol.lowercased() == key }) {
            if let v = coin.totalVolume, v.isFinite, v > 0 { return v }
            if let v = coin.volumeUsd24Hr, v.isFinite, v > 0 { return v }
        }

        // 2) Sidecar cache fallback (freshness-gated).
        if let v = latestVolumeUSDBySymbol[key], v.isFinite, v > 0 {
            if isFreshSidecarValue(updatedAt: lastVolumeUpdatedAt[key], maxAge: maxVolumeSidecarReadAge) {
                return v
            }
            recordStaleSuppression(.sidecarVolume, symbol: key)
            latestVolumeUSDBySymbol.removeValue(forKey: key)
            lastVolumeUpdatedAt.removeValue(forKey: key)
        }
        return nil
    }
    
    /// Aggressively prime volume for a symbol, checking multiple sources.
    /// This is a more aggressive version that tries all sources immediately.
    @MainActor
    func aggressiveVolumePrime(for symbol: String) {
        let symLower = symbol.lowercased()
        // Already have it? Skip.
        if (latestVolumeUSDBySymbol[symLower] ?? 0) > 0 { return }
        
        // Check if coin has provider volume we haven't cached yet
        if let coin = currentCoins.first(where: { $0.symbol.lowercased() == symLower }),
           let v = coin.totalVolume, v.isFinite, v > 0 {
            safeSetVolumeUSD(symLower, v)
            volumeCacheIsDirty = true
            return
        }
        
        // Otherwise, trigger the network priming
        primeVolumeIfNeeded(for: symbol, reason: .viewport)
    }

    // MARK: - Best change percent lookups

    /// Best-available 1h percent change for a coin.
    /// ACCURACY FIX: Provider values (CoinGecko API) take priority over cache.
    /// Cache is only used when provider data is unavailable.
    /// All views (Market, Heat Map, Watchlist) will get the same value for the same symbol.
    @MainActor
    func bestChange1hPercent(for coin: MarketCoin) -> Double? {
        let key = coin.symbol.lowercased()
        var val: Double?
        var source: String = "none"
        
        // 1. PRIMARY: Provider value (CoinGecko API data) is most accurate.
        // FIX v25: Trust provider values even during startup grace period.
        // Cached MarketCoin objects contain percentages from the last CoinGecko API fetch,
        // which are far more professional than showing "—" dashes for 3 seconds.
        // The values may be a few minutes stale but are directionally correct and will be
        // replaced by fresh Firestore/API data within 1-2 seconds.
        if let v = coin.priceChangePercentage1hInCurrency, v.isFinite, abs(v) <= 50 {
            val = v
            source = "provider"
            // CONSISTENCY FIX: Only overwrite cache when the value differs meaningfully.
            if let cached = safeGet1hChange(key), cached.isFinite {
                let diff = abs(v - cached)
                if diff < 0.3 {
                    val = cached
                    source = "cache-stable"
                } else {
                    safeSet1hChange(key, v)
                }
            } else {
                safeSet1hChange(key, v)
            }
        }
        
        // 2. FALLBACK: Use sidecar cache if no provider value
        // This provides consistency across views when API data isn't available
        if val == nil {
            if let cached = safeGet1hChange(key), cached.isFinite {
                val = cached
                source = "cache"
            }
        }
        
        // 3. LAST RESORT: Derive from sparkline
        // Only derive if we have no other source - sparkline derivation can be inaccurate
        // due to sparkline staleness vs live price anchor mismatch.
        // STALE DATA FIX: During startup grace period, sparklines are from stale cache and
        // would produce wrong percentage values. Keep this guard for derivation only.
        if val == nil && !isInStartupGracePeriod {
            let series = canonicalSeries(for: coin)
            
            // DIAGNOSTIC: Log sparkline characteristics when deriving
            if debugPercentSourcing {
                logger.debug("[Pct] 1h deriving for \(coin.symbol, privacy: .public): series=\(series.count) pts, anchor=\(coin.priceUsd ?? 0)")
            }
            
            if let derived = derivedPercentFromSeries(series, hours: 1, anchorPrice: coin.priceUsd), derived.isFinite {
                val = derived
                source = "derived(\(series.count)pts)"
                // Cache derived values so all views get the same value
                if abs(derived) <= 50 {
                    safeSet1hChange(key, derived)
                }
            }
        }
        
        // DIAGNOSTIC: Log final result
        if debugPercentSourcing, let v = val {
            logger.debug("[Pct] 1h for \(coin.symbol, privacy: .public): \(v)% from \(source, privacy: .public)")
        }
        
        // 4. Trigger background Binance 1h fetch for next time
        // This ensures we populate the cache for subsequent calls
        // NOTE: When fetch completes, we re-emit the coins to trigger UI refresh
        if val == nil {
            let symbolForFetch = coin.symbol
            let keyForCache = key
            Task { [weak self] in
                if let change = await self?.fetchBinance1hChange(symbol: symbolForFetch),
                   change.isFinite, abs(change) <= 50 {
                    await MainActor.run { [weak self] in
                        guard let self = self else { return }
                        self.safeSet1hChange(keyForCache, change)
                        if self.debugPercentSourcing {
                            self.logger.debug("[Pct] 1h from Binance klines for \(symbolForFetch, privacy: .public): \(change)")
                        }
                        // PERFORMANCE FIX: Use scroll-aware emission to avoid UI jank during scroll
                        if !self.currentCoins.isEmpty {
                            self.emitCoinsIfAppropriate(self.currentCoins)
                        }
                    }
                }
            }
        }
        
        // 5. Return nil when no data available - let caller use previous value
        if val == nil {
            if debugPercentSourcing {
                logger.warning("⚠️ [Pct] Returning nil for \(coin.symbol, privacy: .public) 1h - no cache/provider/sparkline; Binance fetch triggered")
            }
            return nil
        }
        
        return val
    }
    /// Best-available 1h percent change for a symbol.
    @MainActor
    func bestChange1hPercent(for symbol: String) -> Double? {
        let key = symbol.lowercased()
        if let coin = currentCoins.first(where: { $0.symbol.lowercased() == key }) {
            return bestChange1hPercent(for: coin)
        }
        // FIXED: Return nil when data is actually missing
        // Previously returned 0 which caused tiles to show neutral gray (appearing black)
        return safeGet1hChange(key)
    }
    
    /// Async variant that awaits Binance 1h fetch if no other source is available.
    /// Returns nil when no data is available - UI will show "—" instead of misleading "0.00%".
    func bestChange1hPercentAsync(for coin: MarketCoin) async -> Double? {
        let key = coin.symbol.lowercased()
        
        // 1. Provider value
        if let v = coin.priceChangePercentage1hInCurrency, v.isFinite {
            await MainActor.run { safeSet1hChange(key, v) }
            return v
        }
        
        // 2. Sparkline derivation
        let series = await MainActor.run { canonicalSeries(for: coin) }
        if let derived = derivedPercentFromSeries(series, hours: 1, anchorPrice: coin.priceUsd), derived.isFinite {
            await MainActor.run { safeSet1hChange(key, derived) }
            return derived
        }
        
        // 3. Sidecar cache
        if let cached = await MainActor.run(body: { safeGet1hChange(key) }), cached.isFinite {
            return cached
        }
        
        // 4. Binance klines fetch (await this one)
        if let change = await fetchBinance1hChange(symbol: coin.symbol),
           change.isFinite, abs(change) <= 50 {
            await MainActor.run { safeSet1hChange(key, change) }
            return change
        }
        
        // 5. No data available - return nil so UI shows "—" instead of misleading "0.00%"
        return nil
    }

    /// Best-available 24h percent change for a coin.
    /// Uses sidecar cache as primary source for cross-view consistency.
    /// All views (Market, Heat Map, Watchlist) will get the same value for the same symbol.
    /// CONSISTENCY FIX: Cache-first ensures different MarketCoin instances show same percentage.
    /// ACCURACY FIX: Provider values (CoinGecko/Binance API) take priority over cache.
    /// Applies stablecoin clamping to avoid misleading small-drift signals.
    @MainActor
    func bestChange24hPercent(for coin: MarketCoin) -> Double? {
        let key = coin.symbol.lowercased()
        var val: Double?
        var source: String = "none"
        let providerSnapshotFresh = FirestoreMarketSync.shared.isCoinGeckoDataFresh
        
        // 1. PRIMARY: Provider value only when snapshot freshness is healthy.
        if providerSnapshotFresh, let v = coin.priceChangePercentage24hInCurrency, v.isFinite, abs(v) <= 100 {
            // Treat non-stable exact 0.0 as suspicious/missing, not authoritative.
            // This avoids locking rows to 0.00% when some upstream payloads omit real 24h%.
            if v == 0.0 && !coin.isStable {
                if let cached = safeGet24hChange(key), cached.isFinite {
                    val = cached
                    source = "cache-over-zero"
                }
            } else {
                val = v
                source = "provider"
                // CONSISTENCY FIX: Only overwrite cache when the value differs meaningfully.
                // Different coin instances (from different API fetches) may have slightly different
                // embedded 24h% values (e.g., -12.89% vs -12.91%). If we overwrite the cache on
                // every call, the Watchlist and Market page show different percentages because they
                // use different coin instances. By preserving the cached value when the difference
                // is tiny (< 0.5%), both views converge on the same displayed percentage.
                if let cached = safeGet24hChange(key), cached.isFinite {
                    let diff = abs(v - cached)
                    if diff < 0.5 {
                        // Use existing cached value for cross-view consistency
                        val = cached
                        source = "cache-stable"
                    } else {
                        // Meaningful change - update cache
                        safeSet24hChange(key, v)
                    }
                } else {
                    // No cached value yet - seed the cache
                    safeSet24hChange(key, v)
                }
            }
        } else if !providerSnapshotFresh,
                  let v = coin.priceChangePercentage24hInCurrency, v.isFinite, abs(v) <= 100 {
            recordStaleSuppression(.provider24hBlocked, symbol: coin.symbol)
        }
        
        // 2. FALLBACK: Use sidecar cache if no provider value
        // This provides consistency across views when API data isn't available
        if val == nil {
            if let cached = safeGet24hChange(key), cached.isFinite {
                val = cached
                source = "cache"
            }
        }
        
        // 3. LAST RESORT: Derive from sparkline
        // Only derive if we have no other source - sparkline derivation can be inaccurate.
        // STALE DATA FIX: During startup grace period, sparklines are from stale cache and
        // would produce wrong percentage values. Keep this guard for derivation only.
        if val == nil && !isInStartupGracePeriod {
            let series = canonicalSeries(for: coin)
            
            // DIAGNOSTIC: Log sparkline characteristics when deriving
            if debugPercentSourcing {
                logger.debug("[Pct] 24h deriving for \(coin.symbol, privacy: .public): series=\(series.count) pts, anchor=\(coin.priceUsd ?? 0)")
            }
            
            if let derived = derivedPercentFromSeries(series, hours: 24, anchorPrice: coin.priceUsd), derived.isFinite {
                val = derived
                source = "derived(\(series.count)pts)"
                // Cache derived values so all views get the same value
                if abs(derived) <= 100 {
                    safeSet24hChange(key, derived)
                }
            }
        }
        
        // DIAGNOSTIC: Log final result
        if debugPercentSourcing, let v = val {
            logger.debug("[Pct] 24h for \(coin.symbol, privacy: .public): \(v)% from \(source, privacy: .public)")
        }
        
        // 4. Trigger background Binance 24h fetch for next time
        // This ensures we populate the cache for subsequent calls
        // NOTE: When fetch completes, we re-emit the coins to trigger UI refresh
        if val == nil {
            let symbolForFetch = coin.symbol
            let keyForCache = key
            Task { [weak self] in
                // CONSISTENCY FIX: Use ±300% limit to match display layer clamp
                if let change = await self?.fetchBinance24hChange(symbol: symbolForFetch),
                   change.isFinite, abs(change) <= 300 {
                    await MainActor.run { [weak self] in
                        guard let self = self else { return }
                        self.safeSet24hChange(keyForCache, change)
                        if self.debugPercentSourcing {
                            self.logger.debug("[Pct] 24h from Binance ticker for \(symbolForFetch, privacy: .public): \(change)")
                        }
                        // PERFORMANCE FIX: Use scroll-aware emission to avoid UI jank during scroll
                        if !self.currentCoins.isEmpty {
                            self.emitCoinsIfAppropriate(self.currentCoins)
                        }
                    }
                }
            }
        }
        
        // 5. Return nil when no data available - let caller use previous value
        // Previously returned 0 which caused tiles to show neutral gray (appearing black)
        if val == nil {
            if debugPercentSourcing {
                logger.warning("⚠️ [Pct] Returning nil for \(coin.symbol, privacy: .public) 24h - no provider/sparkline/cache; Binance fetch triggered")
            }
            return nil
        }
        
        return clampStable24h(symbol: coin.symbol, value: val)
    }

    /// Best-available 24h percent change for a symbol.
    @MainActor
    func bestChange24hPercent(for symbol: String) -> Double? {
        let key = symbol.lowercased()
        if let coin = currentCoins.first(where: { $0.symbol.lowercased() == key }) {
            return bestChange24hPercent(for: coin)
        }
        // FIXED: Return nil when data is actually missing
        // Previously returned 0 which conflated "no data" with "0% change"
        guard let cached = safeGet24hChange(key) else { return nil }
        return clampStable24h(symbol: symbol, value: cached)
    }
    
    /// Async variant that awaits Binance 24h fetch if no other source is available.
    /// Returns nil when no data is available - UI will show "—" instead of misleading "0.00%".
    func bestChange24hPercentAsync(for coin: MarketCoin) async -> Double? {
        let key = coin.symbol.lowercased()
        
        // 1. Provider value
        if let v = coin.priceChangePercentage24hInCurrency, v.isFinite {
            await MainActor.run { safeSet24hChange(key, v) }
            return clampStable24h(symbol: coin.symbol, value: v)
        }
        
        // 2. Sparkline derivation
        let series = await MainActor.run { canonicalSeries(for: coin) }
        if let derived = derivedPercentFromSeries(series, hours: 24, anchorPrice: coin.priceUsd), derived.isFinite {
            await MainActor.run { safeSet24hChange(key, derived) }
            return clampStable24h(symbol: coin.symbol, value: derived)
        }
        
        // 3. Sidecar cache
        if let cached = await MainActor.run(body: { safeGet24hChange(key) }), cached.isFinite {
            return clampStable24h(symbol: coin.symbol, value: cached)
        }
        
        // 4. Binance 24h ticker fetch (await this one)
        // CONSISTENCY FIX: Use ±300% limit to match display layer clamp
        if let change = await fetchBinance24hChange(symbol: coin.symbol),
           change.isFinite, abs(change) <= 300 {
            await MainActor.run { safeSet24hChange(key, change) }
            return clampStable24h(symbol: coin.symbol, value: change)
        }
        
        // 5. No data available - return nil so UI shows "—" instead of misleading "0.00%"
        return nil
    }

    /// Best-available 7d percent change for a coin.
    /// ACCURACY FIX: Provider values (CoinGecko API) take priority over cache.
    /// All views (Market, Heat Map, Watchlist) will get the same value for the same symbol.
    @MainActor
    func bestChange7dPercent(for coin: MarketCoin) -> Double? {
        let key = coin.symbol.lowercased()
        var val: Double?
        var source: String = "none"
        
        // 1. PRIMARY: Provider value (CoinGecko API data) is most accurate.
        // FIX v25: Trust provider values even during startup grace period.
        // Cached 7D percentages from the last session are directionally correct and
        // much more professional than showing "—" dashes or defaulting sparkline to green.
        // CONSISTENCY FIX: Use ±500% limit for 7d changes (crypto can move significantly over a week)
        if let v = coin.priceChangePercentage7dInCurrency, v.isFinite, abs(v) <= 500 {
            val = v
            source = "provider"
            // CONSISTENCY FIX: Only overwrite cache when the value differs meaningfully.
            if let cached = safeGet7dChange(key), cached.isFinite {
                let diff = abs(v - cached)
                if diff < 1.0 {
                    val = cached
                    source = "cache-stable"
                } else {
                    safeSet7dChange(key, v)
                }
            } else {
                safeSet7dChange(key, v)
            }
        }
        
        // 2. FALLBACK: Use sidecar cache if no provider value
        // This provides consistency across views when API data isn't available
        if val == nil {
            if let cached = safeGet7dChange(key), cached.isFinite {
                val = cached
                source = "cache"
            }
        }
        
        // 3. LAST RESORT: Derive from sparkline
        // Only derive if we have no other source - sparkline derivation can be inaccurate.
        // STALE DATA FIX: During startup grace period, sparklines are from stale cache and
        // would produce wrong percentage values. Keep this guard for derivation only.
        if val == nil && !isInStartupGracePeriod {
            let series = canonicalSeries(for: coin)
            
            // DIAGNOSTIC: Log sparkline characteristics when deriving
            if debugPercentSourcing {
                logger.debug("[Pct] 7d deriving for \(coin.symbol, privacy: .public): series=\(series.count) pts, anchor=\(coin.priceUsd ?? 0)")
            }
            
            if let derived = derivedPercentFromSeries(series, hours: 24 * 7, anchorPrice: coin.priceUsd), derived.isFinite {
                val = derived
                source = "derived(\(series.count)pts)"
                // Cache derived values so all views get the same value
                if abs(derived) <= 500 {
                    safeSet7dChange(key, derived)
                }
            }
        }
        
        // DIAGNOSTIC: Log final result
        if debugPercentSourcing, let v = val {
            logger.debug("[Pct] 7d for \(coin.symbol, privacy: .public): \(v)% from \(source, privacy: .public)")
        }
        
        // 4. Return nil when no data available - let caller use previous value
        if val == nil {
            if debugPercentSourcing {
                logger.warning("⚠️ [Pct] Returning nil for \(coin.symbol, privacy: .public) 7d - no cache/provider/sparkline")
            }
            return nil
        }
        
        return val
    }

    /// Best-available 7d percent change for a symbol.
    @MainActor
    func bestChange7dPercent(for symbol: String) -> Double? {
        let key = symbol.lowercased()
        if let coin = currentCoins.first(where: { $0.symbol.lowercased() == key }) {
            return bestChange7dPercent(for: coin)
        }
        // FIXED: Return nil when data is actually missing
        // Previously returned 0 which caused tiles to show neutral gray (appearing black)
        // when they should indicate "no data available"
        return safeGet7dChange(key)
    }
}

