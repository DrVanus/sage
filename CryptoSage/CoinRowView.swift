import SwiftUI
import Foundation
import Combine
#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

// MARK: - Scroll-aware update throttling
/// Global UI cadence so all rows commit price changes at the same time (e.g., 1 Hz)
/// Uses Combine publisher to avoid triggering SwiftUI view re-renders on every beat
/// SCROLL PERFORMANCE: Pauses beat emission during scroll for smooth scrolling
final class DisplayCadence: ObservableObject {
    static let shared = DisplayCadence()
    /// Current beat value - read-only for views; increments internally
    private(set) var beat: Int = 0
    /// Combine publisher for beat notifications - use .onReceive() instead of @ObservedObject
    let beatPublisher = PassthroughSubject<Int, Never>()
    private var timer: Timer?
    /// Tracks consecutive skipped beats during scroll (to allow occasional updates)
    private var consecutiveSkips: Int = 0
    // PERFORMANCE FIX: Increased from 5 to 8 for longer pauses during scroll
    private let maxConsecutiveSkips: Int = 8  // Allow update after 8 skipped beats (~8 seconds)
    
    private init() {
        // MEMORY FIX v5.0.12: On simulator, use a much longer interval (30s) to avoid
        // the 15 MB/3s memory growth caused by per-row closure allocations + SwiftUI
        // re-renders every 2 seconds. On device the 2s cadence is fine.
        #if targetEnvironment(simulator)
        let cadenceInterval: TimeInterval = 30.0
        #else
        let cadenceInterval: TimeInterval = 2.0
        #endif
        timer = Timer.scheduledTimer(withTimeInterval: cadenceInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.beat &+= 1
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }

                // MEMORY FIX v5.0.12: Skip beats entirely when there is no coin data.
                // Without data every beat just churns empty view state for no reason.
                if MarketViewModel.shared.allCoins.isEmpty {
                    return
                }
                
                // PERFORMANCE FIX v3: Skip during app initialization phase
                // This prevents UI churn during startup
                if ScrollStateManager.shared.shouldSkipExpensiveUpdate() {
                    self.consecutiveSkips += 1
                    return
                }
                
                // PERFORMANCE FIX: During fast scrolling, completely pause beats
                if ScrollStateManager.shared.isFastScrolling {
                    self.consecutiveSkips += 1
                    return
                }
                
                // SCROLL PERFORMANCE: Skip beat emission during normal scroll (with periodic exception)
                if ScrollStateManager.shared.isScrolling {
                    self.consecutiveSkips += 1
                    guard self.consecutiveSkips >= self.maxConsecutiveSkips else { return }
                    self.consecutiveSkips = 0
                } else {
                    self.consecutiveSkips = 0
                }
                
                self.beatPublisher.send(self.beat)
            }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
}

/// A reusable row view for displaying a single coin in a list.
/// PERFORMANCE: Simplified state management to reduce re-renders
struct CoinRowView: View {
    let coin: MarketCoin
    /// Pre-loaded sparkline data passed from parent (avoids disk I/O in body)
    var sparklineData: [Double] = []
    /// Pre-loaded live price from parent (avoids per-row subscriptions)
    var livePrice: Double? = nil
    
    // PERFORMANCE FIX v22: Removed @EnvironmentObject MarketViewModel.
    // This was the SINGLE BIGGEST performance killer on the homepage.
    // MarketViewModel has 18 @Published properties that fire on every 500ms price update.
    // With @EnvironmentObject, EVERY visible CoinRowView (15-20 rows) was invalidated
    // on every single MVM change, causing full body re-evaluation across all rows.
    // Now we access the singleton directly — no SwiftUI observation, no cascade.
    private var viewModel: MarketViewModel { MarketViewModel.shared }
    // DEAD CODE REMOVED: hSizeClass was never used
    private let cadence = DisplayCadence.shared
    
    // === DISPLAY STATE ===
    @State private var displayedPrice: Double? = nil
    // Note: priceColor is reset to adaptive value in lifecycle hooks via basePriceColor
    @State private var priceColor: Color = Color.primary.opacity(0.98)
    // NOTE: Staleness indicator removed from market list view for cleaner UI
    // Price freshness is handled at the data layer; visual indicator was cluttering the list
    @State private var lastPriceForFlash: Double? = nil
    @State private var priceScale: CGFloat = 1.0
    @State private var animationResetTask: Task<Void, Never>? = nil  // Track animation reset to avoid race conditions
    @State private var volumeRefreshTask: Task<Void, Never>? = nil   // Track volume refresh to cancel on disappear
    @State private var deferredInitTask: Task<Void, Never>? = nil    // PERFORMANCE: Deferred initialization task for scroll
    
    // Computed adaptive base price color for resets
    private var basePriceColor: Color { DS.Adaptive.textPrimary.opacity(0.98) }
    
    // === COMPUTED DATA CACHE (from MarketMetricsCache) ===
    // DEAD CODE REMOVED: cachedSpark was duplicate of engineDisplay - consolidated to engineDisplay only
    @State private var engineDisplay: [Double] = []
    @State private var engineIsPositive7D: Bool = false
    @State private var engineDayChangePercent: Double? = nil
    @State private var lastEngineAt: Date? = nil
    
    // === LIVE DATA CACHE (from LivePriceManager) ===
    @State private var cachedDayChange: Double? = nil
    @State private var cachedWeekPositive: Bool? = nil
    @State private var cachedVolume: Double? = nil
    
    // === 7D COLOR STABILIZATION ===
    // Prevents rapid green/red flashing by requiring consistent direction before changing color.
    @State private var weekPositiveConfirmCount: Int = 0
    private let weekPositiveFlipThreshold: Int = 2  // Reduced from 3 for faster color response
    
    // === SPARKLINE DATA ===
    @State private var binanceSparkline: [Double] = []
    // DEAD CODE REMOVED: didFetchBinanceSparkline was set but never read
    
    // === PERFORMANCE: PRE-COMPUTED DISPLAY VALUES ===
    // PERFORMANCE FIX: These values are now computed in onAppear/onChange instead of body
    // to avoid heavy closure evaluation on every view update during scroll.
    @State private var precomputedSparkline: [Double] = []
    @State private var precomputedIsPositive7D: Bool = false
    @State private var precomputedDayChange: Double? = nil
    // PERFORMANCE FIX: Cache priceParts to avoid MarketFormat.priceParts() in body during scroll
    @State private var cachedPriceParts: (currency: String, number: String)? = nil
    
    // PERFORMANCE FIX: Cache fresh coin reference to avoid repeated O(n) lookups
    // This is updated in onAppear and onChange(of: coin.id) instead of doing
    // viewModel.allCoins.first(where:) multiple times per row lifecycle
    @State private var cachedFreshCoin: MarketCoin? = nil
    
    // === SUBSCRIPTION STATE ===
    // PERFORMANCE: Per-row subscription removed - using centralized subscription in MarketView
    // DEAD CODE REMOVED: coinsVersionTick was never updated
    @State private var pendingPrice: Double? = nil
    
    // === UI STATE ===
    @State private var isFavorite: Bool = false
    @State private var showDebugOverlay: Bool = false
    @State private var isViewVisible: Bool = false  // Guard against updates after disappear

    // Constants for column widths
    private let imageSize: CGFloat = 24
    private let starSize: CGFloat = 16

    private func copyToClipboard(_ s: String) {
        #if os(iOS)
        UIPasteboard.general.string = s
        #elseif os(macOS)
        let p = NSPasteboard.general
        p.clearContents()
        p.setString(s, forType: .string)
        #endif
    }
    
    /// PERFORMANCE FIX: Gets the fresh coin data from viewModel or uses cached value.
    /// Call refreshFreshCoin() to update the cache, then use this in lifecycle hooks.
    private var freshCoin: MarketCoin {
        cachedFreshCoin ?? coin
    }
    
    /// CONSISTENCY FIX: Updates the cached fresh coin reference.
    /// Uses LivePriceManager.currentCoinsList FIRST (same source as WatchlistSection)
    /// then falls back to viewModel.allCoins. This ensures both Market page and Watchlist
    /// display identical percentages since they read from the same coin instance.
    private func refreshFreshCoin() {
        cachedFreshCoin = LivePriceManager.shared.currentCoinsList.first(where: { $0.id == coin.id })
            ?? viewModel.allCoins.first(where: { $0.id == coin.id })
    }
    
    /// PERFORMANCE FIX: Full onAppear initialization - deferred during scroll for smooth 60fps
    /// This contains all the heavy work that was previously in onAppear
    private func performFullOnAppearSetup() {
        // PERFORMANCE FIX: Single O(n) lookup to cache fresh coin reference
        refreshFreshCoin()
        
        // DATA SOURCE PRIORITY: Use standardized helper for consistent data sourcing
        refreshCachedValues()
        
        // VOLUME FIX: Use aggressive volume prime if still missing
        // This checks all sources and triggers network priming if needed
        if cachedVolume == nil || cachedVolume == 0 {
            LivePriceManager.shared.aggressiveVolumePrime(for: freshCoin.symbol)
            // Schedule a volume refresh after priming has time to complete
            volumeRefreshTask?.cancel()
            volumeRefreshTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
                guard !Task.isCancelled, isViewVisible else { return }
                // Re-check all sources using cached fresh coin
                refreshFreshCoin()
                if let v = freshCoin.totalVolume, v.isFinite, v > 0 {
                    cachedVolume = v
                } else if let v = LivePriceManager.shared.bestVolumeUSD(for: freshCoin), v > 0 {
                    cachedVolume = v
                }
            }
        }
        
        // PERFORMANCE FIX: Update precomputed display values immediately with cached data
        // This ensures the body has valid values before the async engine computation completes
        updatePrecomputedDisplayValues()
        
        // Compute engine outputs on appear and cache the display spark using MarketMetricsCache
        // UNIFIED PERCENTAGES: All use LivePriceManager-backed extensions for consistency
        let provider24h = freshCoin.best24hPercent
        let provider1h = freshCoin.best1hPercent
        let provider7d = freshCoin.best7dPercent
        let symUpper = freshCoin.symbol.uppercased()
        let isStable = freshCoin.isStable
        let livePriceNow = self.livePrice ?? freshCoin.priceUsd
        let sparklineDataCopy = self.sparklineData

        Task { @MainActor in
            // Guard against updates after view disappears
            guard self.isViewVisible else { return }
            
            // PERFORMANCE: Use pre-loaded sparkline data from parent instead of disk I/O
            // Initialize binanceSparkline from passed prop if available
            if self.binanceSparkline.isEmpty && !sparklineDataCopy.isEmpty {
                self.binanceSparkline = sparklineDataCopy
            }
            
            // Use sparkline data for engine computation - NO disk I/O
            let sparkForEngine: [Double] = {
                if !sparklineDataCopy.isEmpty && sparklineDataCopy.count >= 10 { return sparklineDataCopy }
                if !self.binanceSparkline.isEmpty { return self.binanceSparkline }
                return []
            }()
            
            let out = await MarketMetricsCache.shared.compute(
                symbol: symUpper,
                rawSeries: sparkForEngine,
                livePrice: livePriceNow,
                provider1h: provider1h,
                provider24h: provider24h,
                isStable: isStable,
                seriesSpanHours: nil,
                targetPoints: 180,
                provider7d: provider7d
            )
            // Re-check visibility after async compute
            guard self.isViewVisible else { return }
            // Already on @MainActor, assign directly
            // DEAD CODE REMOVED: cachedSpark assignment - was duplicate of engineDisplay
            self.engineDisplay = out.display
            self.engineIsPositive7D = out.isPositive7D
            self.engineDayChangePercent = out.dayFrac.flatMap { $0.isFinite ? ($0 * 100.0) : nil }
            self.lastEngineAt = Date()
            self.displayedPrice = freshCoin.bestDisplayPrice(live: livePriceNow) ?? (out.display.last ?? freshCoin.priceUsd)
            self.pendingPrice = self.displayedPrice
            self.priceColor = self.basePriceColor
            self.lastPriceForFlash = self.displayedPrice
            
            // PERFORMANCE FIX: Update precomputed values after engine results are available
            self.updatePrecomputedDisplayValues()
        }
    }
    
    // MARK: - Standardized Data Source Priority Helpers
    // These functions ensure consistent priority order across all lifecycle hooks:
    // 1. Cached fresh coin (from viewModel.allCoins)
    // 2. LivePriceManager cache
    // 3. Coin prop (passed from parent)
    
    /// Gets the best available 24h change percent using standardized priority.
    private func getBest24hChangePercent() -> Double? {
        return LivePriceManager.shared.bestChange24hPercent(for: freshCoin)
    }
    
    /// Gets the best available 7d change percent using standardized priority.
    private func getBest7dChangePercent() -> Double? {
        return LivePriceManager.shared.bestChange7dPercent(for: freshCoin.symbol)
    }
    
    /// Gets the best available volume using standardized priority.
    private func getBestVolume() -> Double? {
        // Production path: trust LivePriceManager freshness-gated lookup only.
        if let v = LivePriceManager.shared.bestVolumeUSD(for: freshCoin), v > 0 { return v }
        return nil
    }
    
    /// Refreshes all cached values using standardized priority.
    private func refreshCachedValues() {
        cachedDayChange = getBest24hChangePercent()
        if let p7d = getBest7dChangePercent(), p7d.isFinite {
            updateCachedWeekPositive(newValue: p7d >= 0)
        }
        cachedVolume = getBestVolume()
    }

    /// Unified trend-color decision used by Market rows.
    /// Keep this aligned with WatchlistSection to avoid red/green mismatches.
    private func unifiedTrendPositive(
        spark: [Double],
        provider7d: Double?,
        provider24h: Double?,
        fallback: Bool
    ) -> Bool {
        return SparklineConsistency.trendPositive(
            spark: spark,
            provider7d: provider7d,
            provider24h: provider24h,
            fallback: fallback
        )
    }
    
    /// PERFORMANCE FIX: Pre-computes display values from all available data sources.
    /// Called in onAppear and onChange to avoid heavy closures in body during scroll.
    private func updatePrecomputedDisplayValues() {
        // CONSISTENCY FIX: Use freshCoin (from viewModel.allCoins) instead of stale coin prop
        // This ensures Market Page data matches Watchlist data, since both pull from the same
        // updated data source. The coin prop may be a snapshot from a previous render cycle.
        let sourceCoin = freshCoin
        
        // Compute displaySpark from best available source
        // ACCURACY FIX v23: CoinGecko's sparklineIn7d is the gold standard for 7D sparklines.
        // It covers the full 7-day period with hourly resolution (168 pts) and is the same
        // source the Watchlist uses. ALWAYS prefer it over Binance klines, which may be
        // stale disk-cached data from a previous session showing outdated trends.
        let spark: [Double] = {
            // 1. CoinGecko sparkline — ALWAYS preferred when available (fresh from Firestore)
            let coinSparkline = sourceCoin.sparklineIn7d.filter { $0.isFinite && $0 > 0 }
            if coinSparkline.count >= 10 { return coinSparkline }
            // 2. Binance klines or engine display as fallback (only when CoinGecko unavailable)
            if !sparklineData.isEmpty && sparklineData.count >= 10 { return sparklineData }
            if !binanceSparkline.isEmpty && binanceSparkline.count >= 10 { return binanceSparkline }
            if !engineDisplay.isEmpty && engineDisplay.count >= 10 { return engineDisplay }
            // 3. Lowest quality fallbacks
            if coinSparkline.count >= 2 { return coinSparkline }
            if !sparklineData.isEmpty && sparklineData.count >= 2 { return sparklineData }
            return []
        }()
        
        // COLOR FIX v24: Use LivePriceManager as primary source, then fall back to coin's
        // embedded values. The sidecar cache can be cleared periodically on foreground,
        // so we also check coin's direct properties as a safety net.
        let p7d: Double? = LivePriceManager.shared.bestChange7dPercent(for: sourceCoin)
        let p24d: Double? = LivePriceManager.shared.bestChange24hPercent(for: sourceCoin)
        
        // SPARKLINE DATA INTEGRITY: Do NOT reverse sparkline arrays.
        // Binance klines and CoinGecko API return data in chronological order (oldest→newest).
        // Reversing based on percentage signals creates fake, numerically backwards charts.
        // Rely on isPositive color for direction signal instead.
        
        precomputedSparkline = spark
        
        // Compute isPositive7D
        // COLOR FIX v24: Provider percentages are the PRIMARY color signal.
        // On startup, sparkline data is often stale from cache (previous session) and can
        // show upward trends even though the market has since gone down. Provider 7D/24H%
        // updates faster from Firestore/API and is the authoritative source of truth.
        // Sparkline visual direction is only used as a fallback when no provider data exists.
        // Also checks coin's embedded values directly as safety net when LivePriceManager
        // returns nil (e.g., sidecar cache just cleared + grace period active).
        let fallbackTrend: Bool = {
            if let cached = cachedWeekPositive { return cached }
            if !engineDisplay.isEmpty { return engineIsPositive7D }
            return (sourceCoin.unified24hPercent ?? sourceCoin.changePercent24Hr ?? 0) >= 0
        }()
        let positive = unifiedTrendPositive(
            spark: spark,
            provider7d: p7d,
            provider24h: p24d,
            fallback: fallbackTrend
        )
        precomputedIsPositive7D = positive
        
        // CONSISTENCY FIX: Always use LivePriceManager as primary source (like WatchlistSection does)
        // This ensures Market Page percentages match Watchlist percentages
        // FIX: Use freshCoin (sourceCoin) for consistent data access
        let isStablecoin = sourceCoin.isStable
        let dayChange: Double? = {
            // Helper to validate change values - reject exactly 0.0 for non-stablecoins
            // as this often indicates missing/stale data rather than actual 0% change
            func isValidChange(_ value: Double?) -> Bool {
                guard let v = value, v.isFinite else { return false }
                // Accept 0.0 only for stablecoins (where 0% change is expected)
                if v == 0.0 && !isStablecoin { return false }
                return true
            }
            
            // FIX: Defensive clamp for 24h change (reasonable max is ±300%)
            // This prevents display of absurd values like +313747%
            func clamp24h(_ value: Double) -> Double {
                return max(-300, min(300, value))
            }
            
            // 1. Primary: LivePriceManager (same source as WatchlistSection)
            // Uses sourceCoin (freshCoin) to ensure same data as Watchlist
            if let live = LivePriceManager.shared.bestChange24hPercent(for: sourceCoin), isValidChange(live) { return clamp24h(live) }
            // 2. Cached value from refreshCachedValues()
            if let cached = cachedDayChange, isValidChange(cached) { return clamp24h(cached) }
            // 3. Engine-derived value
            if let engine = engineDayChangePercent, isValidChange(engine) { return clamp24h(engine) }
            // 4. Provider value (CoinGecko - may be stale)
            if let provider = sourceCoin.priceChangePercentage24hInCurrency, isValidChange(provider) { return clamp24h(provider) }
            if let unified = sourceCoin.unified24hPercent, isValidChange(unified) { return clamp24h(unified) }
            // 5. Last resort - changePercent24Hr (also validate)
            if let change = sourceCoin.changePercent24Hr, isValidChange(change) { return clamp24h(change) }
            return nil // No valid data - will show "—"
        }()
        precomputedDayChange = dayChange
        
        // PERFORMANCE FIX: Pre-compute price parts to avoid MarketFormat.priceParts() in body
        // Use displayedPrice, fall back to coin's best available price
        let priceForParts: Double = displayedPrice 
            ?? livePrice 
            ?? coin.priceUsd 
            ?? (engineDisplay.last ?? coin.sparklineIn7d.last) 
            ?? 0
        cachedPriceParts = MarketFormat.priceParts(priceForParts)
        
                // NOTE: Staleness check removed - was showing clock icon on too many rows
                // Price freshness is handled at the data layer without visual clutter
    }
    
    /// Stabilizes the 7D positivity decision to prevent rapid green/red color flashing.
    /// Uses hysteresis: requires multiple consecutive confirmations before changing color.
    /// This is critical for coins like Ethereum where the 7D change hovers near zero.
    private func updateCachedWeekPositive(newValue: Bool?) {
        guard let newValue = newValue else { return }
        
        // If no cached value yet, accept the new value immediately
        guard let currentCached = cachedWeekPositive else {
            cachedWeekPositive = newValue
            weekPositiveConfirmCount = 0
            return
        }
        
        // If the new value matches the current cached value, reinforce it
        if newValue == currentCached {
            weekPositiveConfirmCount = 0
            return
        }
        
        // New value differs - accumulate confirmations before flipping
        weekPositiveConfirmCount += 1
        if weekPositiveConfirmCount >= weekPositiveFlipThreshold {
            // Enough confirmations - flip to the new value
            cachedWeekPositive = newValue
            weekPositiveConfirmCount = 0
        }
        // Otherwise, keep the current cached value (don't flip yet)
    }

    var body: some View {
        // Local helpers to avoid accessing @EnvironmentObject from stored/computed properties
        func formatVolumeRaw(_ v: Double) -> String {
            return MarketFormat.price(v)
        }

        // PERFORMANCE FIX: Avoid viewModel.bestPrice() during scroll - use cached/passed values only
        // The livePrice parameter and displayedPrice state should already have the best price
        _ = livePrice ?? displayedPrice

        // Engine-first metrics (computed in lifecycle; use cached state here)
        let isStable: Bool = coin.isStable

        // PERFORMANCE FIX: Use pre-computed values from onAppear/onChange instead of inline closures
        // This avoids heavy closure evaluation on every body update during scroll
        // ORIENTATION FIX: When precomputed values aren't ready yet (before onAppear),
        // apply a lightweight orientation guard to the raw sparklineData fallback.
        // Uses 7D%, 24H%, and live price proximity to ensure correct orientation immediately.
        // SPARKLINE DATA INTEGRITY: No reversal logic — trust the data source.
        // CoinGecko/Firestore data is always in chronological order (oldest → newest).
        let displaySpark: [Double] = {
            if !precomputedSparkline.isEmpty { return precomputedSparkline }
            return sparklineData
        }()
        let isPositive7D: Bool = {
            // When precomputed values aren't ready, use provider percentages for color
            // COLOR FIX v24: Provider data first — sparkline data may be stale from cache
            if precomputedSparkline.isEmpty {
                let p7 = coin.priceChangePercentage7dInCurrency ?? coin.unified7dPercent
                let p24 = coin.priceChangePercentage24hInCurrency ?? coin.unified24hPercent
                return unifiedTrendPositive(
                    spark: displaySpark,
                    provider7d: p7,
                    provider24h: p24,
                    fallback: precomputedIsPositive7D
                )
            }
            // COLOR REFRESH FIX: Even when precomputed values ARE ready, if the precomputed
            // isPositive7D was computed during grace period (nil provider data), it may be wrong.
            // Do a quick check against the coin's embedded values as a safety net.
            let precomputed = precomputedIsPositive7D
            if let p24 = coin.priceChangePercentage24hInCurrency, p24.isFinite, abs(p24) > 0.5 {
                // If the 24h change strongly disagrees with the precomputed value, override
                let fresh24Positive = p24 >= 0
                if fresh24Positive != precomputed { return fresh24Positive }
            }
            return precomputed
        }()
        // 24H LOADING FIX: When precomputed value isn't ready yet, use coin's embedded 24H%
        // This prevents showing "—" for several seconds while the full computation runs.
        let dayChangePercentRaw: Double? = precomputedDayChange ?? {
            // Lightweight fallback: only trust embedded snapshot values when Firestore CoinGecko
            // feed is currently fresh; otherwise show nil and wait for fresh sidecar/provider update.
            guard FirestoreMarketSync.shared.isCoinGeckoDataFresh else { return nil }
            let sourceCoin = freshCoin
            let isStablecoin = sourceCoin.isStable
            func validChange(_ value: Double?) -> Double? {
                guard let p = value, p.isFinite else { return nil }
                if p == 0.0 && !isStablecoin { return nil }
                return max(-300, min(300, p))
            }
            if let p = validChange(sourceCoin.priceChangePercentage24hInCurrency) { return p }
            if let p = validChange(sourceCoin.unified24hPercent) { return p }
            if let p = validChange(sourceCoin.changePercent24Hr) { return p }
            return nil
        }()
        let dayChangeFrac: Double? = dayChangePercentRaw.map { $0 / 100.0 }

        // PERFORMANCE FIX: Use cached price parts instead of computing in body
        let parts = cachedPriceParts ?? MarketFormat.priceParts(displayedPrice ?? coin.priceUsd ?? 0) ?? ("$", "0.00")

        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                // 1) Coin icon + symbol/name
                HStack(spacing: 6) {
                    CoinImageView(symbol: coin.symbol, url: coin.imageUrl, size: imageSize)
                        .frame(width: imageSize, height: imageSize)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(DS.Adaptive.stroke, lineWidth: 1))
                        .accessibilityHidden(true) // Icon is decorative; label on parent
                    VStack(alignment: .leading, spacing: 2) {
                        Text(coin.symbol.uppercased())
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(DS.Adaptive.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text(coin.name)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(DS.Adaptive.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
                .frame(width: MarketColumns.coinColumnWidth, alignment: .leading)
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(coin.name), \(coin.symbol.uppercased())")
                .contextMenu {
                    Button {
                        copyToClipboard(coin.symbol.uppercased())
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                    } label: { Label("Copy symbol", systemImage: "number") }

                    Button {
                        copyToClipboard(coin.name)
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                    } label: { Label("Copy name", systemImage: "textformat") }

                    Divider()
                    Button {
                        NotificationCenter.default.post(name: .showPairsForSymbol, object: coin.symbol.uppercased())
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                    } label: { Label("View pairs & composite", systemImage: "chart.xyaxis.line") }
                    #if DEBUG
                    Divider()
                    Button {
                        showDebugOverlay.toggle()
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                    } label: { Label(showDebugOverlay ? "Hide row debug" : "Show row debug", systemImage: "ladybug.fill") }
                    #endif
                }
                // SCROLL FIX: Removed explicit .onLongPressGesture(minimumDuration: 0.35)
                // The .contextMenu above already provides long-press copy functionality.
                // The redundant gesture recognizer was competing with the ScrollView's scroll
                // gesture, causing a ~350ms delay when starting a slow scroll from this area.

                Spacer().frame(width: MarketColumns.gutter)

                // 2) 7-day sparkline - premium rendering with glow and end dot
                // Require at least 10 points for a smooth sparkline
                // Fewer points (e.g., 7 daily CoinGecko points) look choppy/broken
                if displaySpark.count >= 10 {
                    SparklineView(
                        data: displaySpark,
                        isPositive: isPositive7D,
                        overrideColor: isStable ? Color.gray.opacity(0.5) : nil,
                        height: 30,  // Taller for visible gradient fill (matches Watchlist quality)
                        lineWidth: isStable ? SparklineConsistency.listStableLineWidth : SparklineConsistency.listLineWidth,
                        verticalPaddingRatio: SparklineConsistency.listVerticalPaddingRatio,
                        fillOpacity: isStable ? SparklineConsistency.listStableFillOpacity : SparklineConsistency.listFillOpacity,
                        gradientStroke: true,
                        showEndDot: true,  // End dot shows current price position
                        leadingFade: 0.0,
                        trailingFade: 0.0,
                        showTrailHighlight: false,
                        trailLengthRatio: 0.0,
                        minWidth: MarketColumns.sparklineWidth,
                        endDotPulse: false,  // No pulse for cleaner list appearance
                        showMinMaxTicks: false,
                        preferredWidth: MarketColumns.sparklineWidth,
                        showBaseline: false,
                        backgroundStyle: .none,
                        cornerRadius: 0,
                        glowOpacity: isStable ? 0.0 : SparklineConsistency.listGlowOpacity,
                        glowLineWidth: SparklineConsistency.listGlowLineWidth,
                        smoothSamplesPerSegment: SparklineConsistency.listSmoothSamplesPerSegment,
                        maxPlottedPoints: SparklineConsistency.listMaxPlottedPoints,
                        rawMode: false,
                        showBackground: false,
                        gridEnabled: false,
                        showExtremaDots: false,
                        neonTrail: false,
                        crispEnds: true,
                        horizontalInset: SparklineConsistency.listHorizontalInset,
                        compact: false,  // Full mode for glow effect
                        seriesOrder: .oldestToNewest
                    )
                    .frame(width: MarketColumns.sparklineWidth, height: 30)
                    // Preserve trailing inset region so the end-dot/glow is not hard-clipped on device.
                    .padding(.trailing, SparklineConsistency.listHorizontalInset)
                    .clipped()
                    .padding(.trailing, -SparklineConsistency.listHorizontalInset)
                    // NOTE: drawingGroup() removed - SparklineView already uses it internally
                    // Double drawingGroup was causing blur artifacts
                    .padding(.horizontal, 0)
                    .allowsHitTesting(false)
                    .accessibilityLabel("7-day price trend")
                    .accessibilityValue(isPositive7D ? "Upward trend" : "Downward trend")
                    Spacer().frame(width: MarketColumns.gutter)
                } else {
                    // Shimmer placeholder while sparkline data is loading
                    MarketSparklineLoadingPlaceholder(width: MarketColumns.sparklineWidth)
                        .frame(width: MarketColumns.sparklineWidth, height: 24)
                        .allowsHitTesting(false)
                        .accessibilityLabel("Loading price trend data")
                    Spacer().frame(width: MarketColumns.gutter)
                }

                // 3) Price column (ellipses removed, consistent sizing)
                // Reserve a consistent width based on a wide template, but allow scaling before truncation.
                ZStack(alignment: .trailing) {
                    Text("$88,888.88")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .opacity(0)
                        .accessibilityHidden(true)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(parts.currency)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .kerning(-0.2)
                            .foregroundColor(DS.Adaptive.textPrimary.opacity(0.95))
                        Text(parts.number)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(priceColor)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.80)
                .allowsTightening(true)
                .scaleEffect(priceScale, anchor: .trailing)
                .clipped()
                // MEMORY FIX: .drawingGroup() removed - GPU offscreen buffer savings
                .padding(.trailing, 2)
                .contentShape(Rectangle()) // PERFORMANCE: Explicit bounds for context menu anchor
                .contextMenu {
                    Button {
                        copyToClipboard("\(parts.currency)\(parts.number)")
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                    } label: { Label("Copy price", systemImage: "doc.on.doc") }

                    Button {
                        copyToClipboard(coin.symbol.uppercased())
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                    } label: { Label("Copy symbol", systemImage: "number") }
                }
                // SCROLL FIX: Removed explicit .onLongPressGesture(minimumDuration: 0.35)
                // The .contextMenu above already provides long-press copy functionality.
                // The redundant gesture recognizer was competing with the ScrollView's scroll
                // gesture, causing a ~350ms delay when starting a slow scroll from this area.
                .accessibilityLabel(Text("Price \(parts.currency)\(parts.number)"))
                .contentTransition(.numericText())
                .frame(width: MarketColumns.priceWidth, alignment: .trailing)
                Spacer().frame(width: MarketColumns.gutter)

                // 4) 24h change column - Clean colored text, no pill
                let fmt24 = dayChangeFrac.map { PercentDisplay.formatFraction($0) }
                Group {
                    if let fmt24 {
                        Text(fmt24.text)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor({
                                switch fmt24.trend {
                                case .positive: return Color(red: 0.2, green: 0.85, blue: 0.4)
                                case .negative: return Color(red: 1.0, green: 0.35, blue: 0.35)
                                case .neutral:  return DS.Adaptive.textTertiary
                                }
                            }())
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .accessibilityLabel("24 hour change")
                            .accessibilityValue(fmt24.accessibility)
                    } else {
                        Text("—")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(DS.Adaptive.textTertiary)
                            .accessibilityLabel(Text("24 hour change unavailable"))
                    }
                }
                .contentTransition(.numericText())
                // PERFORMANCE FIX v14: Animation disabled - contentTransition provides enough feedback
                // The .animation() modifier was causing jank during scroll even with guards in onChange
                .frame(width: MarketColumns.changeWidth, alignment: .trailing)
                Spacer().frame(width: MarketColumns.gutter)

                // 5) Volume column
                // Prefer provider-reported 24h USD volume; fall back to cached value from lifecycle hooks.
                let volumeValue: Double? = {
                    // Strict path: only show freshness-gated value.
                    if let v = LivePriceManager.shared.bestVolumeUSD(for: freshCoin), v > 0 { return v }
                    return cachedVolume
                }()
                let volText: String = {
                    guard let v = volumeValue, v > 0 else { return "—" }
                    return MarketFormat.compactVolume(v)
                }()
                if let v = volumeValue, v > 0 {
                    let currencySymbol = Locale.current.currencySymbol ?? "$"
                    Text(volText)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(DS.Adaptive.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(width: MarketColumns.volumeWidth, alignment: .trailing)
                        .padding(.horizontal, 0)
                        .contentShape(Rectangle()) // PERFORMANCE: Explicit bounds for context menu anchor
                        .contextMenu {
                            Button {
                                copyToClipboard("\(currencySymbol)\(volText)")
                                #if os(iOS)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                #endif
                            } label: { Label("Copy volume", systemImage: "doc.on.doc") }

                            Button {
                                copyToClipboard(formatVolumeRaw(v))
                                #if os(iOS)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                #endif
                            } label: { Label("Copy raw volume", systemImage: "number") }
                        }
                        // SCROLL FIX: Removed explicit .onLongPressGesture(minimumDuration: 0.35)
                        // The .contextMenu above already provides long-press copy functionality.
                        // The redundant gesture recognizer was competing with the ScrollView's scroll
                        // gesture, causing a ~350ms delay when starting a slow scroll from this area.
                } else {
                    Text(volText)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(DS.Adaptive.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(width: MarketColumns.volumeWidth, alignment: .trailing)
                        .padding(.horizontal, 0)
                }
                Spacer().frame(width: MarketColumns.gutter)

                // 6) Favorite star column
                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    // Toggle favorite and update local state to avoid re-render cascade
                    FavoritesManager.shared.toggle(coinID: coin.id)
                    isFavorite = FavoritesManager.shared.isFavorite(coinID: coin.id)
                    // Sync favoriteIDs immediately for filter consistency
                    viewModel.favoriteIDs = FavoritesManager.shared.getAllIDs()
                    viewModel.applyAllFiltersAndSort()
                    // WATCHLIST FIX: Removed redundant loadWatchlistData() call.
                    // MarketViewModel subscribes to FavoritesManager.$favoriteIDs and automatically
                    // calls loadWatchlistDataImmediate() which bypasses coalescing delay.
                    // The old loadWatchlistData() used publishWatchlistCoinsCoalesced() which
                    // adds up to 1 second delay during scroll, causing slow watchlist updates.
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .resizable()
                        .scaledToFit()
                        .frame(width: starSize, height: starSize)
                        .foregroundStyle(
                            isFavorite
                                ? AnyShapeStyle(LinearGradient(
                                    colors: [BrandColors.goldLight, BrandColors.goldBase],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                  ))
                                : AnyShapeStyle(DS.Adaptive.textSecondary)
                        )
                }
                .frame(width: max(MarketColumns.starColumnWidth, 36), alignment: .center)
                .padding(.trailing, 0)
                .contentShape(Rectangle())
                .padding(.vertical, 0)
                .buttonStyle(.plain)
                .accessibilityLabel(isFavorite ? "Remove \(coin.symbol.uppercased()) from favorites" : "Add \(coin.symbol.uppercased()) to favorites")
                .accessibilityHint("Double tap to toggle")
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 0)
            .contentShape(Rectangle())

            GeometryReader { proxy in
                let scale: CGFloat = {
                    #if os(iOS)
                    UIScreen.main.scale
                    #elseif os(macOS)
                    NSScreen.main?.backingScaleFactor ?? 2.0
                    #else
                    2.0
                    #endif
                }()
                let hairline = 1.0 / scale
                Rectangle()
                    .fill(DS.Adaptive.divider)
                    .frame(height: hairline)
                    .position(x: proxy.size.width / 2, y: hairline / 2)
            }
            .frame(height: 1) // reserve layout space without stacking
        }
        .id(coin.id)
        // PERFORMANCE: Disable implicit animations for non-price data changes (smooth scrolling)
        // Note: displayedPrice animation is handled by the inner Text view's .contentTransition()
        .animation(.none, value: cachedDayChange)
        .onAppear {
            // Defer ALL state modifications to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                // Mark view as visible FIRST to enable state updates
                isViewVisible = true
                
                // Reset animation state immediately to prevent stale glow from previous row reuse
                animationResetTask?.cancel()
                animationResetTask = nil
                priceScale = 1.0
                priceColor = basePriceColor
                lastPriceForFlash = nil  // Will be set after displayedPrice is computed
                
                // Initialize favorite state (avoids @ObservedObject cascade)
                isFavorite = FavoritesManager.shared.isFavorite(coinID: coin.id)

                // PERFORMANCE: Per-row subscription removed - centralized in MarketView
                // Rows now use passed-in livePrice prop for updates

                // PERFORMANCE FIX: During scroll, only do lightweight state setup
                // Defer heavy work (metrics computation, volume priming) until scroll ends
                if ScrollStateManager.shared.isScrolling || ScrollStateManager.shared.isFastScrolling {
                    // Lightweight setup only - use cached/passed data
                    refreshFreshCoin()
                    refreshCachedValues()
                    updatePrecomputedDisplayValues()
                    
                    // Schedule full initialization after scroll ends
                    deferredInitTask?.cancel()
                    deferredInitTask = Task { @MainActor in
                        // Wait for scroll to end (check every 200ms)
                        while ScrollStateManager.shared.isScrolling || ScrollStateManager.shared.isFastScrolling {
                            try? await Task.sleep(nanoseconds: 200_000_000)
                            guard !Task.isCancelled, self.isViewVisible else { return }
                        }
                        // Add small delay after scroll ends to batch multiple row initializations
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        guard !Task.isCancelled, self.isViewVisible else { return }
                        performFullOnAppearSetup()
                    }
                    return
                }
                
                // Not scrolling - perform full initialization immediately
                performFullOnAppearSetup()
            }
        }
        .onDisappear {
            // Defer state modifications to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                // Mark view as invisible FIRST to prevent race conditions with async tasks
                isViewVisible = false
                // Cancel any pending tasks to prevent memory leaks
                animationResetTask?.cancel()
                animationResetTask = nil
                volumeRefreshTask?.cancel()
                volumeRefreshTask = nil
                deferredInitTask?.cancel()  // PERFORMANCE: Cancel deferred init when scrolling away
                deferredInitTask = nil
                // PERFORMANCE: No per-row subscription to cancel - using centralized subscription
            }
        }
        .onChange(of: coin.id) { _, _ in
            // Defer ALL state modifications to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                // Reset animation state immediately when coin changes (row reuse)
                animationResetTask?.cancel()
                animationResetTask = nil
                priceScale = 1.0
                priceColor = basePriceColor
                lastPriceForFlash = nil
                displayedPrice = nil  // Reset so new coin gets fresh price
                pendingPrice = nil
                
                // PERFORMANCE FIX: Single O(n) lookup to refresh cached fresh coin reference
                refreshFreshCoin()
                
                // Get FRESH coin data from viewModel (not stale coin property)
                // UNIFIED PERCENTAGES: All use LivePriceManager-backed extensions for consistency
                let provider24h = freshCoin.best24hPercent
                let provider1h = freshCoin.best1hPercent
                let provider7d = freshCoin.best7dPercent
                let symUpper = freshCoin.symbol.uppercased()
                let isStable = freshCoin.isStable
                let livePriceNow = self.livePrice ?? freshCoin.priceUsd
                let sparklineDataCopy = self.sparklineData

                // DATA SOURCE PRIORITY: Use standardized helper for consistent data sourcing
                // When coin changes, reset the 7d stabilization counter
                weekPositiveConfirmCount = 0
                refreshCachedValues()
                
                // PERFORMANCE FIX: Update precomputed values immediately when coin changes
                updatePrecomputedDisplayValues()

                Task { @MainActor in
                    // Guard against updates after view disappears
                    guard self.isViewVisible else { return }
                    
                    // PERFORMANCE: Use pre-loaded sparkline data - NO disk I/O
                    let sparkForEngine: [Double] = {
                        if !sparklineDataCopy.isEmpty && sparklineDataCopy.count >= 10 { return sparklineDataCopy }
                        if !self.binanceSparkline.isEmpty { return self.binanceSparkline }
                        return []
                    }()
                    
                    guard !sparkForEngine.isEmpty else { return }
                    
                    let out = await MarketMetricsCache.shared.compute(
                        symbol: symUpper,
                        rawSeries: sparkForEngine,
                        livePrice: livePriceNow,
                        provider1h: provider1h,
                        provider24h: provider24h,
                        isStable: isStable,
                        seriesSpanHours: nil,
                        targetPoints: 180,
                        provider7d: provider7d
                    )
                    // Re-check visibility after async compute
                    guard self.isViewVisible else { return }
                    // DEAD CODE REMOVED: cachedSpark assignment - was duplicate of engineDisplay
                    self.engineDisplay = out.display
                    self.engineIsPositive7D = out.isPositive7D
                    self.engineDayChangePercent = out.dayFrac.flatMap { $0.isFinite ? ($0 * 100.0) : nil }
                    self.lastEngineAt = Date()
                    
                    // Set initial price for new coin (without triggering flash animation)
                    let newPrice = freshCoin.bestDisplayPrice(live: livePriceNow) ?? out.display.last ?? freshCoin.priceUsd
                    self.displayedPrice = newPrice
                    self.pendingPrice = newPrice
                    self.lastPriceForFlash = newPrice  // Set reference so future changes compare correctly
                    
                    // PERFORMANCE FIX: Update precomputed values after engine results
                    self.updatePrecomputedDisplayValues()
                }
            }
        }
        // PERFORMANCE: Removed .onChange(of: coinsVersionTick) - price updates now come via livePrice prop
        .onChange(of: livePrice) { _, newPrice in
            // PERFORMANCE FIX v12: Skip during global startup phase
            guard !isInGlobalStartupPhase() else { return }
            
            // PERFORMANCE FIX v3: Skip entirely during scroll to prevent "multiple updates per frame"
            guard !ScrollStateManager.shared.isScrolling && !ScrollStateManager.shared.isFastScrolling else { return }
            
            // Defer ALL state modifications to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                guard isViewVisible else { return }
                // Update displayed price when parent passes new live price
                if let price = newPrice, price.isFinite, price > 0 {
                    let eps = max(0.0000001, abs(price) * 0.000001)
                    if let current = displayedPrice, abs(current - price) >= eps {
                        pendingPrice = price
                    } else if displayedPrice == nil {
                        pendingPrice = price
                    }
                }
                // DATA SOURCE PRIORITY: Use standardized helper for consistent data sourcing
                refreshCachedValues()
            }
        }
        .onReceive(cadence.beatPublisher) { beat in
            // Defer ALL state modifications to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                // Guard against updates after view disappears
                guard isViewVisible else { return }
                // PERFORMANCE FIX: Completely skip during fast scroll (user is rapidly navigating)
                guard !ScrollStateManager.shared.isFastScrolling else { return }
                // SCROLL PERFORMANCE: Skip expensive updates during scroll
                guard !ScrollStateManager.shared.shouldSkipExpensiveUpdate() else { return }
                
                // DATA SOURCE PRIORITY: Use standardized helper for volume refresh
                let freshVol = getBestVolume()
                
                // Update cached volume if we found a value
                if let vol = freshVol, vol > 0, cachedVolume != vol {
                    cachedVolume = vol
                }
                
                // Determine if volume is still missing after all checks
                let volumeMissing = (cachedVolume == nil || cachedVolume == 0) && (cachedFreshCoin?.totalVolume ?? coin.totalVolume ?? 0) <= 0
                
                // Every ~2 beats, if volume is still missing, try aggressive priming
                if beat % 2 == 0 && volumeMissing {
                    // SCROLL PERFORMANCE: Skip volume priming during scroll
                    guard !ScrollStateManager.shared.isScrolling else { return }
                    LivePriceManager.shared.aggressiveVolumePrime(for: coin.symbol)
                    // Refresh cached volume after short delay
                    volumeRefreshTask?.cancel()
                    volumeRefreshTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        guard !Task.isCancelled, isViewVisible else { return }
                        // Re-check all sources using cached fresh coin
                        refreshFreshCoin()
                        if let v = freshCoin.totalVolume, v.isFinite, v > 0 {
                            cachedVolume = v
                        } else if let v = LivePriceManager.shared.bestVolumeUSD(for: freshCoin), v > 0 {
                            cachedVolume = v
                        }
                    }
                }
                // COLOR REFRESH FIX: Periodically re-check isPositive7D with fresh provider data.
                // On startup, precomputedIsPositive7D may have been computed when provider 7D%/24H%
                // were nil (sidecar cache cleared, grace period, CoinGecko not yet loaded). Once
                // fresh data arrives from Firestore/API, we need to update the color.
                // Every ~3 beats (~6 seconds), refresh the fresh coin and re-derive the color.
                if beat % 3 == 0 {
                    refreshFreshCoin()
                    let fc = freshCoin
                    let freshP7d = LivePriceManager.shared.bestChange7dPercent(for: fc)
                    let freshP24d = LivePriceManager.shared.bestChange24hPercent(for: fc)
                    let sparkForColor = !precomputedSparkline.isEmpty
                        ? precomputedSparkline
                        : (!sparklineData.isEmpty ? sparklineData : binanceSparkline)
                    let fallback = precomputedIsPositive7D
                    let np = unifiedTrendPositive(
                        spark: sparkForColor,
                        provider7d: freshP7d ?? fc.priceChangePercentage7dInCurrency,
                        provider24h: freshP24d ?? fc.priceChangePercentage24hInCurrency,
                        fallback: fallback
                    )
                    if np != precomputedIsPositive7D {
                        precomputedIsPositive7D = np
                        // Also refresh 24h change in case it was stale
                        refreshCachedValues()
                        updatePrecomputedDisplayValues()
                    }
                }
                
                // Poll latest price from the view model each beat so rows tick in sync
                let latestCandidate = coin.bestDisplayPrice(live: viewModel.bestPrice(for: coin.id)) ?? (engineDisplay.last)
                if let latest = latestCandidate {
                    let eps = max(0.0000001, abs(latest) * 0.000001)
                    if let old = pendingPrice {
                        if abs(old - latest) >= eps { pendingPrice = latest }
                    } else {
                        pendingPrice = latest
                    }
                }
                // Commit the pending value on the cadence beat
                guard let p = pendingPrice else { return }
                if let current = displayedPrice {
                    let epsilon = max(0.0000001, abs(p) * 0.000001)
                    if abs(current - p) < epsilon { return }
                }
                displayedPrice = p
            }
        }
        .onChange(of: displayedPrice) { _, new in
            // PERFORMANCE FIX v12: Skip during global startup phase
            guard !isInGlobalStartupPhase() else { return }
            
            // Defer ALL state modifications to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                // Guard against updates after view disappears
                guard isViewVisible else { return }
                guard let new = new else { return }
                
                // PERFORMANCE FIX: Update cached price parts when price changes
                cachedPriceParts = MarketFormat.priceParts(new)
                
                // SCROLL PERFORMANCE: Skip animations during scroll, just update the reference
                if ScrollStateManager.shared.isScrolling {
                    lastPriceForFlash = new
                    return
                }
                
                let old = lastPriceForFlash ?? new
                let delta = new - old
                // Magnitude-based threshold to avoid flicker on tiny updates
                let absThreshold: Double = {
                    if new >= 20000 { return 1.0 }
                    if new >= 1000  { return 0.2 }
                    if new >= 100   { return 0.05 }
                    if new >= 1     { return 0.005 }
                    return 0.00005
                }()
                if abs(delta) >= absThreshold {
                    let up = delta > 0
                    
                    // Cancel any pending reset animation to avoid race conditions
                    animationResetTask?.cancel()
                    
                    // Quick spring animation with subtle scale for price tick feedback
                    withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.75)) {
                        priceColor = up ? Color(red: 0.2, green: 0.85, blue: 0.4) : Color(red: 1.0, green: 0.35, blue: 0.35)
                        priceScale = up ? 1.02 : 0.98
                    }
                    
                    // Schedule reset animation with cancellation support
                    animationResetTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 350_000_000) // 350ms hold
                        // Check if this task was cancelled (newer animation started)
                        guard !Task.isCancelled else { return }
                        // Re-check visibility after sleep before resetting animation
                        guard isViewVisible else { return }
                        withAnimation(.easeOut(duration: 0.3)) {
                            priceColor = basePriceColor
                            priceScale = 1.0
                        }
                    }
                }
                lastPriceForFlash = new
            }
        }
        .background(DS.Adaptive.background.opacity(0.001))
        .overlay(alignment: .topLeading) {
            if showDebugOverlay {
                let liveNow = viewModel.bestPrice(for: coin.id)
                // Use cached values to avoid calling LivePriceManager during body
                let src = (cachedDayChange != nil) ? "live" : ((engineDayChangePercent != nil) ? "engine" : "—")
                let volSrc: String = {
                    if let v = coin.totalVolume, v.isFinite, v > 0 { return "prov" }
                    if let v = cachedVolume, v.isFinite, v > 0 { return "live" }
                    return "—"
                }()
                RowDebugOverlay(
                    symbol: coin.symbol.uppercased(),
                    lastEngineAt: lastEngineAt,
                    changeSource: src,
                    changeValue: cachedDayChange ?? engineDayChangePercent,
                    livePrice: liveNow,
                    displayedPrice: displayedPrice,
                    pendingPrice: pendingPrice,
                    volumeSource: volSrc
                )
                .padding(.top, 2)
                .padding(.leading, 2)
            }
        }
    }

    private struct RowDebugOverlay: View {
        let symbol: String
        let lastEngineAt: Date?
        let changeSource: String
        let changeValue: Double?
        let livePrice: Double?
        let displayedPrice: Double?
        let pendingPrice: Double?
        // DEAD CODE REMOVED: coinsVersionTick was never updated, removed from debug overlay
        let volumeSource: String

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text("⛽︎ \(symbol)")
                if let t = lastEngineAt {
                    Text("eng: \(relative(t))")
                } else {
                    Text("eng: —")
                }
                HStack(spacing: 4) {
                    Text("chg24:")
                    Text(changeSource).foregroundColor(.white.opacity(0.8))
                    if let v = changeValue { Text(String(format: "%@%.2f%%", v >= 0 ? "+" : "-", abs(v))).monospacedDigit() }
                }
                HStack(spacing: 6) {
                    Group {
                        Text("live=") + Text(fmt(livePrice)).monospacedDigit()
                    }
                    Group {
                        Text("disp=") + Text(fmt(displayedPrice)).monospacedDigit()
                    }
                    Group {
                        Text("pend=") + Text(fmt(pendingPrice)).monospacedDigit()
                    }
                }
                HStack(spacing: 6) {
                    Text("vol:")
                    Text(volumeSource).foregroundColor(.white.opacity(0.8))
                }
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.60))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.6)
            )
            .allowsHitTesting(false)
        }

        private func fmt(_ v: Double?) -> String {
            guard let v, v.isFinite, v > 0 else { return "—" }
            return MarketFormat.price(v)
        }
        private func relative(_ d: Date) -> String {
            let s = Int(Date().timeIntervalSince(d))
            if s < 2 { return "just now" }
            if s < 60 { return "\(s)s ago" }
            let m = s / 60
            if m < 60 { return "\(m)m ago" }
            let h = m / 60
            return "\(h)h ago"
        }
    }
}

// MARK: - Previews and Sample Data
#if DEBUG
struct CoinRowView_Previews: PreviewProvider {
    static var previews: some View {
        // Sample JSON matching MarketCoin properties
        let json = """
        {
            "id": "bitcoin",
            "symbol": "btc",
            "name": "Bitcoin",
            "image": "https://assets.coingecko.com/coins/images/1/large/bitcoin.png",
            "current_price": 106344,
            "total_volume": 27200000000,
            "price_change_percentage_24h": 1.92
        }
        """
        // Decode JSON into a MarketCoin instance
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        // SAFETY FIX: Use try? with fallback for preview safety
        guard let sampleCoin = try? decoder.decode(MarketCoin.self, from: data) else {
            fatalError("Preview JSON decode failed - check sample data")
        }

        return CoinRowView(coin: sampleCoin)
            .environmentObject(MarketViewModel.shared)
            .previewLayout(.sizeThatFits)
            .background(Color.black)
    }
}
#endif

// MARK: - Sparkline Loading Placeholder
/// Professional shimmer placeholder shown while sparkline data is loading.
/// Displays a subtle animated wave pattern that indicates data is being fetched.
private struct MarketSparklineLoadingPlaceholder: View {
    let width: CGFloat
    @State private var animationPhase: CGFloat = 0
    
    var body: some View {
        ZStack {
            // Base line placeholder - shows a faint wave shape
            MarketWavePlaceholderShape()
                .stroke(Color.gray.opacity(0.12), lineWidth: 1.2)
            
            // Animated shimmer overlay
            MarketWavePlaceholderShape()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.gray.opacity(0.0),
                            Color.gray.opacity(0.20),
                            Color.gray.opacity(0.0)
                        ],
                        startPoint: UnitPoint(x: animationPhase - 0.3, y: 0.5),
                        endPoint: UnitPoint(x: animationPhase + 0.3, y: 0.5)
                    ),
                    lineWidth: 1.5
                )
        }
        .onAppear {
            #if !targetEnvironment(simulator)
            // MEMORY FIX v9: Block during startup animation suppression window
            // MEMORY FIX v10: NO retry — shimmer starts when user scrolls
            guard !shouldSuppressStartupAnimations() else { return }
            guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                        animationPhase = 1.3
                    }
                }
                return
            }
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                animationPhase = 1.3
            }
            #endif
            // MEMORY FIX v5.0.13: Shimmer disabled on simulator — sparkline data never arrives,
            // so .repeatForever animations run indefinitely at 60fps, each frame re-evaluating
            // LinearGradient -> accumulating ~8 MB/s.
        }
        #if !targetEnvironment(simulator)
        // PERFORMANCE FIX v21: Pause shimmer sweep during scroll
        .onReceive(ScrollStateManager.shared.$isScrolling.removeDuplicates()) { scrolling in
            if scrolling {
                animationPhase = -0.3
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard !shouldSuppressStartupAnimations() else { return }
                    guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
                    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                        animationPhase = 1.3
                    }
                }
            }
        }
        #endif
    }
}

/// A wave-shaped path for the market sparkline placeholder
private struct MarketWavePlaceholderShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        let amplitude: CGFloat = 4  // Subtle wave height
        let frequency: CGFloat = 2.5  // Number of waves
        
        path.move(to: CGPoint(x: 0, y: midY))
        
        for x in stride(from: 0, through: rect.width, by: 2) {
            let relativeX = x / rect.width
            let y = midY + sin(relativeX * .pi * frequency) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
        }
        
        return path
    }
}