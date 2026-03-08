import SwiftUI
import Combine
import UniformTypeIdentifiers
// MARK: - Row metrics type used throughout WatchlistSection
// NOTE: oneH and dayChange are Optional to distinguish "no data" from "0% change"
fileprivate typealias RowMetrics = (isStable: Bool, spark: [Double], isPositive7D: Bool, oneH: Double?, dayChange: Double?)
import Foundation

// MARK: - Scroll-aware update throttling
@MainActor private let scrollStateManager = ScrollStateManager.shared

// MARK: - Engine Bookkeeping (class-based, non-triggering)
// Mutations to class properties do NOT trigger SwiftUI body re-evaluations.
// Values are consumed when the debounced `engineCacheTick` @State fires.
@MainActor
private class EngineBookkeeping {
    var inFlight: Set<String> = []
    var computations: Int = 0
    var pendingOut: [String: MetricsEngineOutputs] = [:]
    var isPositiveCache: [String: (decision: Bool, confirmCount: Int, lastUpdate: Date)] = [:]
    var stableMetrics: [String: (spark: [Double], isPositive: Bool, cacheTime: Date)] = [:]
    var stableSpark: [String: [Double]] = [:]
    
    func clearAll() {
        inFlight.removeAll()
        computations = 0
        pendingOut.removeAll()
        isPositiveCache.removeAll()
        stableMetrics.removeAll()
        stableSpark.removeAll()
    }
    
    func clearEngine(for keys: [String]) {
        for key in keys {
            pendingOut.removeValue(forKey: key)
            inFlight.remove(key)
        }
    }
}

// MARK: - Brand Gold Palette (single source of truth)
private enum BrandGold {
    // Unified to centralized BrandColors (Classic Gold)
    static let light = BrandColors.goldLight
    static let base  = BrandColors.goldBase
    static let dark  = BrandColors.goldDark
    static let shadow = BrandColors.goldBase
    
    // Dark mode gradients (with dark edge for depth)
    static var horizontalGradient: LinearGradient { BrandColors.goldHorizontal }
    static var verticalGradient: LinearGradient { BrandColors.goldVertical }
    
    // Light mode gradients (flat, no dark edge - cleaner on white backgrounds)
    static var horizontalGradientLight: LinearGradient { BrandColors.goldHorizontalLight }
    static var verticalGradientLight: LinearGradient { BrandColors.goldVerticalLight }
}

// MARK: - Watchlist column metrics preference (for header alignment)
struct WatchlistColumnMetrics: Equatable {
    var leadingWidth: CGFloat
    var sparkWidth: CGFloat
    var percentWidth: CGFloat
    var percentSpacing: CGFloat
    var innerDividerW: CGFloat   // divider between 1H and 24H in rows
    var outerDividerW: CGFloat   // divider between spark and metrics in rows
}

// THREAD SAFETY FIX v12: Lock-free using nonisolated(unsafe) for eventual consistency
struct WatchlistColumnsKey: PreferenceKey {
    static var defaultValue: WatchlistColumnMetrics = .init(leadingWidth: 0, sparkWidth: 0, percentWidth: 0, percentSpacing: 0, innerDividerW: 0, outerDividerW: 0)
    
    // THREAD SAFETY v12: Lock-free - eventual consistency is fine for layout metrics
    nonisolated(unsafe) private static var _lastUpdateAt: CFTimeInterval = 0
    nonisolated(unsafe) private static var _hasInitialized: Bool = false
    nonisolated(unsafe) private static var _lastValue: WatchlistColumnMetrics = .init(leadingWidth: 0, sparkWidth: 0, percentWidth: 0, percentSpacing: 0, innerDividerW: 0, outerDividerW: 0)
    
    static func reduce(value: inout WatchlistColumnMetrics, nextValue: () -> WatchlistColumnMetrics) {
        let n = nextValue()
        // Prefer the first non-zero metrics; otherwise keep existing
        guard n.sparkWidth > 0, n.percentWidth > 0, n.leadingWidth > 0 else { return }
        
        let now = CACurrentMediaTime()
        let dLead = abs(n.leadingWidth - _lastValue.leadingWidth)
        let dSpark = abs(n.sparkWidth - _lastValue.sparkWidth)
        let dPct = abs(n.percentWidth - _lastValue.percentWidth)
        // Rotation/resizing typically causes a large jump; bypass normal throttling for this case.
        let isLayoutJump = dLead > 24 || dSpark > 24 || dPct > 12
        
        // Keep rapid noise down, but allow immediate orientation reflow.
        if _hasInitialized && !isLayoutJump {
            guard now - _lastUpdateAt >= 0.35 else { return }
        }
        
        guard isLayoutJump || dLead > 3 || dSpark > 3 || dPct > 3 else { return }
        
        value = n
        _lastValue = n
        _lastUpdateAt = now
        _hasInitialized = true
    }
}

fileprivate let changeWidth1h: CGFloat = 48   // slightly wider for better readability
fileprivate let changeWidth24h: CGFloat = 48  // slightly wider for better readability

// Deduplicate while preserving order to avoid ForEach identity issues
private func uniqued(_ ids: [String]) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    out.reserveCapacity(ids.count)
    for id in ids {
        if seen.insert(id).inserted { out.append(id) }
    }
    return out
}

// MARK: - AnimatedPriceText
struct AnimatedPriceText: View {
    let price: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Keep prior price and last rendered string so we only animate when users can actually see a change
    @State private var oldPrice: Double? = nil
    @State private var textColor: Color = DS.Adaptive.textPrimary
    @State private var scaleEffect: CGFloat = 1.0
    @State private var lastDisplay: String = ""
    @State private var appearTime: Date = .distantPast
    @State private var lastAnimationAt: Date = .distantPast
    // PERFORMANCE FIX v2: Track last update to prevent "multiple updates per frame" warning
    @State private var lastPriceUpdateAt: Date = .distantPast
    // PERFORMANCE FIX v10: Flag to skip onChange during initial load burst
    @State private var hasCompletedInitialLoad: Bool = false

    var body: some View {
        let display = formatPrice(price)
        // Clean price display - color flash only, no arrow to avoid layout shifts
        Text(display)
            .foregroundColor(textColor)
            .font(.subheadline.weight(.semibold))
            .fontDesign(.rounded)
            .monospacedDigit()
            .allowsTightening(true)
            .minimumScaleFactor(0.9)
            .baselineOffset(0)
            .scaleEffect(scaleEffect)
            .contentTransition(.numericText())
            .accessibilityLabel("Price")
            .accessibilityValue(display)
        .onAppear {
                // Defer state modification to avoid "Modifying state during view update"
                DispatchQueue.main.async {
                    appearTime = Date()
                    if price > 0 {
                        oldPrice = price
                        lastDisplay = display
                    }
                    // PERFORMANCE FIX v10: Delay enabling onChange to avoid "multiple updates per frame" warning
                    // during the initial data loading burst
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        hasCompletedInitialLoad = true
                    }
                }
            }
            .onChange(of: price) { _, newPrice in
                // PERFORMANCE FIX v11: Skip during global startup phase to prevent
                // "onChange tried to update multiple times per frame" warning
                guard !isInGlobalStartupPhase() else { return }
                
                // PERFORMANCE FIX v10: Skip entirely until initial load completes
                guard hasCompletedInitialLoad else { return }
                
                // PERFORMANCE FIX v4: Skip ALL work during scroll - don't even queue tasks
                // Check shouldBlockHeavyOperation() which uses the cached value for efficiency
                guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
                
                // PERFORMANCE FIX v4: Increased throttle to 200ms to reduce main thread contention
                let now = Date()
                guard now.timeIntervalSince(lastPriceUpdateAt) >= 0.2 else { return }
                lastPriceUpdateAt = now
                
                // PERFORMANCE FIX v4: Only update state, skip expensive computation during light scroll
                // This ensures data stays fresh but doesn't trigger animations
                guard newPrice > 0 else { return }
                let newDisplay = formatPrice(newPrice)
                let prev = oldPrice ?? newPrice
                
                // Always update the cached values (silent update)
                oldPrice = newPrice
                lastDisplay = newDisplay
                
                // PERFORMANCE FIX v4: Skip animations entirely - they cause jank
                // The numericText contentTransition provides enough visual feedback
                // Only animate for very significant changes and when definitely not scrolling
                let delta = abs(newPrice - prev)
                let significantThreshold = newPrice * 0.005 // 0.5% change
                let coldStart = Date().timeIntervalSince(appearTime) < 1.0
                let tooSoon = Date().timeIntervalSince(lastAnimationAt) < 1.0
                
                guard !coldStart && !tooSoon && delta >= significantThreshold && !reduceMotion else { return }
                
                // Double-check scroll state before animation
                guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
                
                let wentUp = newPrice > prev
                lastAnimationAt = Date()
                
                // Simplified animation - just color flash, no scale
                textColor = wentUp ? Color(red: 0.2, green: 0.85, blue: 0.4) : Color(red: 1.0, green: 0.35, blue: 0.35)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    textColor = DS.Adaptive.textPrimary
                }
            }
    }

    /// Formats a price value into a currency string with magnitude-based precision.
    private func formatPrice(_ value: Double) -> String {
        guard value > 0 else { return "—" }
        return MarketFormat.price(value)
    }
}

// MARK: - ChangeView
struct ChangeView: View {
    let label: String
    let change: Double?  // Optional to distinguish "no data" from "0% change"
    let showsLabel: Bool
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }

    init(label: String, change: Double?, showsLabel: Bool = true) {
        self.label = label
        self.change = change
        self.showsLabel = showsLabel
    }

    // Smoothed value used only for 1H to prevent sign flip-flop around zero
    @State private var displayedChange: Double? = nil
    @State private var changeScale: CGFloat = 1.0
    @State private var lastChangeAnimationAt: Date = .distantPast
    // PERFORMANCE FIX v2: Track last update to prevent "multiple updates per frame" warning
    @State private var lastChangeUpdateAt: Date = .distantPast
    // PERFORMANCE FIX v10: Flag to skip onChange during initial load burst
    @State private var hasCompletedInitialLoad: Bool = false
    private var effectiveChange: Double? {
        guard let change = change else { return nil }
        return label == "1H" ? (displayedChange ?? change) : change
    }

    // Hysteresis + light EMA to stabilize tiny jitters (fractional units; 0.0001 == 0.01%)
    private func stabilizeOneHour(prev: Double, new: Double) -> Double {
        let bandExit: Double = 0.0008   // 0.08%: within this, hold previous value
        let alpha: Double = 0.35        // EMA smoothing factor
        var candidate = new
        // If new value is inside the hysteresis band, keep the previous value to avoid color flipping.
        if abs(new) < bandExit { candidate = prev }
        let filtered = prev.isFinite ? (prev * (1 - alpha) + candidate * alpha) : candidate
        // Quantize to 0.01% steps in fractional units to align with formatting
        let stepFrac: Double = 0.0001
        let q = (filtered / stepFrac).rounded() * stepFrac
        return abs(q) < 1e-12 ? 0 : q
    }

    private var processedLabel: String { label.replacingOccurrences(of: ":", with: "") }

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if showsLabel {
                Text(processedLabel)
                    .font(.caption2)
                    .fontDesign(.rounded)
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            
            // Show "—" when data is unavailable, otherwise format the percentage
            if let effectiveChange = effectiveChange {
                // FIX: Defensive clamp to ±300% (as fraction: ±3.0) to prevent absurd displays
                let clampedChange = max(-3.0, min(3.0, effectiveChange))
                let fmt = PercentDisplay.formatFraction(clampedChange)
                let trendColor: Color = {
                    switch fmt.trend {
                    case .positive: return Color(red: 0.2, green: 0.85, blue: 0.4)  // Premium green
                    case .negative: return Color(red: 1.0, green: 0.35, blue: 0.35) // Premium red
                    case .neutral:  return isDark ? Color.white.opacity(0.6) : Color.secondary
                    }
                }()
                
                Text(fmt.text)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(trendColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .scaleEffect(changeScale)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityLabel("\(processedLabel) change")
                    .accessibilityValue(fmt.accessibility)
            } else {
                // No data available - show shimmer placeholder
                ShimmerBar(height: 12, cornerRadius: 3)
                    .frame(width: 50)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityLabel("\(processedLabel) change")
                    .accessibilityValue("loading")
            }
        }
        .onAppear {
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                displayedChange = change
                // PERFORMANCE FIX v10: Delay enabling onChange to avoid "multiple updates per frame" warning
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    hasCompletedInitialLoad = true
                }
            }
        }
        .onChange(of: change) { _, newValue in
            // PERFORMANCE FIX v11: Skip during global startup phase
            guard !isInGlobalStartupPhase() else { return }
            
            // PERFORMANCE FIX v10: Skip entirely until initial load completes
            guard hasCompletedInitialLoad else { return }
            
            // PERFORMANCE FIX v4: Skip ALL work during scroll using cached check
            guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
            
            // PERFORMANCE FIX v4: Increased throttle to 250ms to reduce contention
            let now = Date()
            guard now.timeIntervalSince(lastChangeUpdateAt) >= 0.25 else { return }
            lastChangeUpdateAt = now
            
            guard let newValue = newValue else {
                displayedChange = nil
                return
            }
            
            let oldValue = displayedChange ?? newValue
            
            // Update the displayed value (silent - no animation)
            if label == "1H" {
                displayedChange = stabilizeOneHour(prev: oldValue, new: newValue)
            } else {
                displayedChange = newValue
            }
            
            // PERFORMANCE FIX v4: Remove scale animations entirely during scroll
            // They cause jank and the color change provides enough visual feedback
            // Only animate for very significant changes when definitely not scrolling
            let significantChange = abs(newValue - oldValue) > 0.01 // 1% change (was 0.05%)
            let tooSoon = now.timeIntervalSince(lastChangeAnimationAt) < 1.0
            
            guard significantChange && !tooSoon else { return }
            guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
            
            lastChangeAnimationAt = now
            changeScale = 1.03
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                changeScale = 1.0
            }
        }
        .frame(width: label == "1H" ? changeWidth1h : changeWidth24h, alignment: .trailing)
    }
}

// MARK: - WatchlistSection
struct WatchlistSection: View {
    // PERFORMANCE FIX v22: Removed @EnvironmentObject MarketViewModel.
    // MarketViewModel has 18 @Published properties firing every 500ms on price updates.
    // With @EnvironmentObject, WatchlistSection's body (including all child CoinRowViews)
    // was invalidated on every single change. Using singleton access breaks the observation chain.
    private var marketVM: MarketViewModel { MarketViewModel.shared }
    // PERFORMANCE FIX v20: Removed @EnvironmentObject var appState: AppState
    // AppState has 18+ @Published properties. WatchlistSection only needs
    // selectedTab (for isActive check) and dismissHomeSubviews.
    // Now uses targeted observation via onReceive and AppState.shared.

    @Environment(\.colorScheme) private var colorScheme
    private var isDarkMode: Bool { colorScheme == .dark }

    @State private var isLoadingWatchlist = false
    @State private var localOrder: [String] = []
    @State private var draggingID: String? = nil
    @State private var shakeAttempts: Int = 0
    @State private var isDragging: Bool = false
    @State private var listResetKey: UUID = UUID()
    @State private var dragWatchTimer: Timer? = nil
    @State private var dragHeartbeat: Date = .distantPast
    @State private var hoverTargetID: String? = nil
    @State private var hoverInsertAfter: Bool = false
    @State private var animatePulse: Bool = false
    @State private var ringCooldownUntil: Date = .distantPast
    @State private var ringActive: Bool = false
    @State private var ringRowID: String? = nil
    @State private var dragSessionID: UUID? = nil // Added for session token
    @State private var ringClearTask: Task<Void, Never>? = nil

    @State private var lastWatchlistFetch: Date = .distantPast
    @State private var isFetchingWatchlist: Bool = false

    var onSelectCoinForDetail: (MarketCoin) -> Void = { _ in }

    // Subscription to LivePriceManager for real-time price/percentage updates
    @State private var livePriceCancellable: AnyCancellable? = nil
    @State private var lastLivePriceUpdateAt: Date = .distantPast

    // PERFORMANCE FIX: Removed unused uiTick and uiRefreshTimer - they were firing every 10s without being used
    // Sparklines and prices now update independently via cached data and AnimatedPriceText

    @State private var engineCacheTick: Int = 0
    // MEMORY FIX v15: Engine bookkeeping moved to a class wrapper.
    // @State mutations trigger SwiftUI body re-evaluations. With 8 coins, each engine
    // completion wrote to 3+ @State dictionaries → 24+ body re-evals → 8 SparklineViews
    // each → ~40 MB/s memory growth → OOM crash. By moving internal bookkeeping to a
    // reference type, mutations don't trigger re-renders. Only the debounced
    // `engineCacheTick` @State triggers the single batched view update.
    @State private var engineOutByID: [String: MetricsEngineOutputs] = [:]
    @State private var engine = EngineBookkeeping()
    private let maxConcurrentEngineComputations = 2
    
    // MARK: - 7D Color Stabilization Cache
    private let colorFlipConfirmationsRequired: Int = 2
    private let colorCacheStaleInterval: TimeInterval = 60.0 // Reset confirmation count after 60s of no updates
    
    // Debounced tick update to coalesce rapid state modifications
    @State private var pendingTickUpdate: DispatchWorkItem?
    // FIX v14c: Increased from 1.0s to 2.0s. With 8 coins computing sequentially
    // (max 2 concurrent), all 8 results arrive within ~4s. A 2s debounce ensures
    // most results are batched into 1-2 UI updates instead of 8 separate ones.
    private let tickDebounceInterval: TimeInterval = 2.0
    
    // Memory pressure notification observer
    @State private var memoryWarningObserver: NSObjectProtocol?
    // FIX v14c: Prevent duplicate runFullOnAppearSetup() on tab return.
    // Without this, every time the user returns to the Home tab, onAppear fires
    // and re-runs the full setup (clearing 6 dictionaries, re-subscribing, fetching),
    // which triggers the metrics cascade and freezes the app.
    @State private var hasCompletedFullSetup = false
    
    // FIX: Debounced watchlist refresh to consolidate the triple handler cascade.
    // When switching to the Home tab, .onAppear, .onChange(refreshGeneration), and
    // .onReceive(selectedTab) all fire simultaneously, each calling effectiveWatchlist
    // and setting cachedWatchlist. This debounce coalesces them into a single refresh.
    @State private var pendingWatchlistRefresh: DispatchWorkItem?
    
    // FIX: Cache for effectiveWatchlist to avoid repeated O(n) computation.
    // effectiveWatchlist iterates 4 arrays (~250+ coins each) on every call.
    // Uses reference type so mutations don't trigger SwiftUI re-renders.
    // Invalidated when favoriteIDs changes (add/remove).
    private class EffectiveWatchlistCache {
        var favoriteIDs: Set<String> = []
        var result: [MarketCoin] = []
    }
    @State private var effectiveCache = EffectiveWatchlistCache()
    
    // PERFORMANCE: Cache the effective watchlist to avoid recomputation during body
    @State private var cachedWatchlist: [MarketCoin] = []
    @State private var lastWatchlistCacheAt: Date = .distantPast
    private let watchlistCacheValidDuration: TimeInterval = 2.0 // Cache valid for 2 seconds (increased to reduce recomputation)
    
    // MEMORY FIX v15: Initialize nil — load async in runFullOnAppearSetup().
    // Synchronous loading of 50 coins at @State init caused ~10 MB allocation BEFORE
    // any body evaluation, making reopens (with populated cache) much heavier than
    // clean installs (empty cache). This is why delete+reinstall worked but reopen crashed.
    @State private var preloadedCacheFallback: [MarketCoin]? = nil
    
    // Adaptive throttle for LivePriceManager updates - increases when APIs are degraded
    // SPARKLINE FIX: Increased from 0.5s to 2.0s normal, 5.0s degraded
    // Sparklines represent 7D data - they don't need sub-second updates
    @State private var lastLivePriceThrottleInterval: TimeInterval = 2.0
    @State private var consecutiveUpdateSkips: Int = 0
    private let normalThrottleInterval: TimeInterval = 2.0
    private let degradedThrottleInterval: TimeInterval = 5.0

    // Only do live work when Home tab is active to keep tab switching smooth
    // PERFORMANCE FIX v20: Use cached state instead of appState.selectedTab
    @State private var isActiveTab: Bool = true
    private var isActive: Bool { isActiveTab }

    // Data readiness gate: render rows only when a meaningful portion of data is present
    // OPTIMIZATION: Very relaxed threshold to show data immediately on first launch
    // Sparklines and prices will load/update in background
    // WATCHLIST SYNC FIX: Use cachedWatchlist (@State) instead of effectiveWatchlist (singleton read).
    // This ensures SwiftUI tracks the dependency and re-renders when the cache is updated.
    private var hasUsableData: Bool {
        // If cachedWatchlist has coins, data is ready
        if !cachedWatchlist.isEmpty { return true }
        // Fallback: check effectiveWatchlist (in case cache hasn't been populated yet)
        return !effectiveWatchlist.isEmpty
    }
    
    // Professional shimmer skeleton shown until enough market data is available
    private var loadingWatchlistPlaceholder: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 10) {
                    // Coin icon placeholder
                    Circle()
                        .fill(isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                        .frame(width: 28, height: 28)
                    // Name + symbol
                    VStack(alignment: .leading, spacing: 4) {
                        ShimmerBar(height: 12, cornerRadius: 3)
                            .frame(width: 72)
                        ShimmerBar(height: 8, cornerRadius: 2)
                            .frame(width: 36)
                    }
                    Spacer()
                    // Sparkline placeholder
                    ShimmerBar(height: 24, cornerRadius: 4)
                        .frame(width: 80)
                    // Price + change
                    VStack(alignment: .trailing, spacing: 4) {
                        ShimmerBar(height: 12, cornerRadius: 3)
                            .frame(width: 60)
                        ShimmerBar(height: 8, cornerRadius: 2)
                            .frame(width: 40)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isDarkMode ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                .accessibilityHidden(true)
        )
    }

    // Layout constants to stabilize row sizing
    private let sparkWidth: CGFloat = 105  // minimum sparkline width - reduced to fit iPhone 17 Pro screens
    private let coinIconSize: CGFloat = 24  // coin logo size
    private var currentViewportWidth: CGFloat {
        #if os(iOS)
        if let windowScene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
           let window = windowScene.keyWindow {
            return window.bounds.width
        }
        return UIScreen.main.bounds.width
        #else
        return 420
        #endif
    }
    private var priceWidth: CGFloat {
        #if os(iOS)
        let w = currentViewportWidth
        return w >= 430 ? 95 : 88  // tighter to give more room to sparkline
        #else
        return 95
        #endif
    }
    private var nameColWidth: CGFloat { priceWidth }
    // Gold bar (3pt) + spacing (4pt) + icon (24pt) + spacing (6pt) + text width
    private var leadingInfoWidth: CGFloat { 3 + 4 + coinIconSize + 6 + max(priceWidth, nameColWidth) }

    // PERFORMANCE FIX: Increased from 30s to 60s to reduce update frequency and network requests
    // PERFORMANCE FIX v19: Changed from .common to .default so timer automatically pauses during scroll
    // .common includes UITrackingRunLoopMode which fires timer events during scroll, adding main thread work
    @State private var refreshTimer = Timer.publish(every: 60, on: .main, in: .default).autoconnect()
    
    // Timer to periodically refresh sparkline data (every 5 minutes)
    @State private var sparklineRefreshTimer: Timer?
    @State private var lastSparklineRefresh: Date = .distantPast
    
    // MEMORY FIX v15: Initialize empty — load async in runFullOnAppearSetup().
    // Synchronous disk I/O loading sparkline data at @State init made reopens heavy.
    @State private var sparklineCache: [String: [Double]] = [:]
    
    // stableSparklineData, stableMetricsCache, isPositive7DCache moved to EngineBookkeeping class.
    // Mutations to class properties don't trigger SwiftUI re-renders, preventing the 40 MB/s cascade.
    private let metricsCacheValidDuration: TimeInterval = 45.0 // 45 seconds - prevents flickering while still showing reasonably fresh data
    
    // SCROLL PERFORMANCE FIX: Cache the entire row data array to avoid recomputing metrics on every body evaluation
    // This is the key fix for the 21+ second scroll blocking - metrics computation is expensive and shouldn't run during scroll
    @State private var cachedRowData: [RowDataItem] = []
    @State private var lastRowDataComputeAt: Date = .distantPast
    // Re-entry guard: prevents cascading @State mutations from buildRowsView body path
    @State private var isComputingRowData: Bool = false
    // PERFORMANCE FIX: Extended cache duration from 2s to 3s to reduce recomputation frequency
    // During scroll, we use cache indefinitely regardless of this duration
    private let rowDataCacheValidDuration: TimeInterval = 3.0
    
    // Pre-loaded sparkline data passed from parent (supplements initial cache)
    var initialSparklineCache: [String: [Double]] = [:]
    // Pre-loaded live prices from parent (avoids per-component subscriptions)
    var initialLivePrices: [String: Double] = [:]
    // WATCHLIST INSTANT-SYNC v2: Generation counter from HomeView.
    // Incremented whenever favorites change. Triggers .onChange to refresh data even if
    // this view's Combine subscriptions were lost due to LazyVStack lifecycle.
    var refreshGeneration: Int = 0

    // Coins in user's watchlist (fetched by IDs)
    // WATCHLIST INSTANT-SYNC: Merges from all available sources to ensure newly favorited
    // coins appear immediately, even if marketVM.watchlistCoins hasn't been updated yet.
    // Priority (highest wins): watchlistCoins -> LivePriceManager -> allCoins -> cache
    // Always respects user's custom ordering from FavoritesManager.getOrder()
    private var effectiveWatchlist: [MarketCoin] {
        let favoriteIDs = FavoritesManager.shared.favoriteIDs
        if favoriteIDs.isEmpty { return [] }
        
        // FIX: Cache the result when favoriteIDs membership hasn't changed.
        // effectiveWatchlist iterates 4 arrays (~250+ coins each) on every call.
        // During a tab switch it was called 5+ times. The cache invalidates when
        // the set of favorite IDs changes (add/remove), ensuring fresh results for
        // user-initiated changes while avoiding redundant work for price ticks.
        // Uses reference-type cache to avoid triggering SwiftUI re-renders.
        // Also invalidates if cached coins have missing prices (indicates stale initial load).
        if favoriteIDs == effectiveCache.favoriteIDs && !effectiveCache.result.isEmpty {
            let hasValidPrices = effectiveCache.result.allSatisfy { ($0.priceUsd ?? 0) > 0 }
            if hasValidPrices {
                return effectiveCache.result
            }
        }
        
        // Use the user's ordered list (not the unordered Set)
        let orderedFavoriteIDs: [String] = FavoritesManager.shared.getOrder()
        
        // Helper to sort coins by their position in the user's favorites list
        func sortByFavoriteOrder(_ coins: [MarketCoin]) -> [MarketCoin] {
            return coins.sorted { (a: MarketCoin, b: MarketCoin) -> Bool in
                let indexA: Int = orderedFavoriteIDs.firstIndex(of: a.id) ?? Int.max
                let indexB: Int = orderedFavoriteIDs.firstIndex(of: b.id) ?? Int.max
                return indexA < indexB
            }
        }
        
        // WATCHLIST INSTANT-SYNC: Build a merged map from all sources so that newly
        // favorited coins appear immediately even if watchlistCoins is stale.
        // Lower-priority sources are added first; higher-priority ones overwrite.
        // PRICE PRESERVATION FIX: Higher layers only overwrite when they have a valid price,
        // OR when the existing coin also lacks a price (so we at least get metadata).
        // This prevents BTC showing "—" when a higher layer has nil priceUsd but a lower
        // layer (e.g., disk cache) has a valid cached price.
        var coinMap: [String: MarketCoin] = [:]
        
        /// Only overwrite if the new coin has a valid price, or the existing one doesn't
        func mergePreservingPrice(_ coin: MarketCoin) {
            let id = coin.id
            if let existing = coinMap[id] {
                let existingHasPrice = (existing.priceUsd ?? 0) > 0
                let newHasPrice = (coin.priceUsd ?? 0) > 0
                if newHasPrice || !existingHasPrice {
                    coinMap[id] = coin
                }
                // If new coin lacks price but existing has one, keep existing
            } else {
                coinMap[id] = coin
            }
        }
        
        // Layer 1 (lowest): pre-loaded disk cache
        if let cachedCoins = preloadedCacheFallback {
            for coin in cachedCoins where favoriteIDs.contains(coin.id) {
                coinMap[coin.id] = coin  // First layer: always insert
            }
        }
        
        // Layer 2: marketVM.allCoins (full market list, good fallback)
        for coin in marketVM.allCoins where favoriteIDs.contains(coin.id) {
            mergePreservingPrice(coin)
        }
        
        // Layer 2.5: marketVM.filteredCoins (catches coins added via Coinbase search
        // that aren't in allCoins — e.g., obscure coins found through the Market page search)
        for coin in marketVM.filteredCoins where favoriteIDs.contains(coin.id) {
            mergePreservingPrice(coin)
        }
        
        // Layer 3: LivePriceManager (freshest real-time prices)
        let lpmCoins = LivePriceManager.shared.currentCoinsList
        for coin in lpmCoins where favoriteIDs.contains(coin.id) {
            mergePreservingPrice(coin)
        }
        
        // Layer 4 (highest): marketVM.watchlistCoins (enriched with best prices/sparklines)
        for coin in marketVM.watchlistCoins where favoriteIDs.contains(coin.id) {
            mergePreservingPrice(coin)
        }
        
        guard !coinMap.isEmpty else { return [] }
        let result = sortByFavoriteOrder(Array(coinMap.values))
        
        // Update reference-type cache (safe — class mutation doesn't trigger SwiftUI re-renders)
        effectiveCache.favoriteIDs = favoriteIDs
        effectiveCache.result = result
        return result
    }

    // Inserted new computed property to avoid complex inline expression in onChange
    private var watchlistIDs: [String] {
        effectiveWatchlist.map { $0.id }
    }
    
    /// Coalesces rapid tick updates to avoid "Modifying state during view update" warnings.
    /// Applies pending engine results from the class buffer to @State, then triggers re-render.
    @MainActor private func scheduleTickUpdate() {
        pendingTickUpdate?.cancel()
        let work = DispatchWorkItem { [self] in
            // Apply pending engine results to @State in a single batch
            if !self.engine.pendingOut.isEmpty {
                for (key, value) in self.engine.pendingOut {
                    self.engineOutByID[key] = value
                }
                self.engine.pendingOut.removeAll()
            }
            self.engineCacheTick &+= 1
            self.engineCacheTick &= 0x3FFF // keep it small
        }
        pendingTickUpdate = work
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(tickDebounceInterval * 1_000_000_000))
            work.perform()
        }
    }
    
    // PERFORMANCE FIX: Removed scheduleUITickUpdate() - it was unused and caused unnecessary state updates
    // Sparklines and prices now update via caching mechanisms instead of tick-based re-renders
    
    // Clears cached metrics so they recompute on next render for the given symbols
    @MainActor private func clearEngineCache(for ids: [String]) {
        let keys = Set(ids.map { $0.uppercased() })
        for key in keys {
            self.engineOutByID.removeValue(forKey: key)
            self.engine.inFlight.remove(key)
            self.engine.pendingOut.removeValue(forKey: key)
        }
        self.scheduleTickUpdate()
    }
    
    /// Determines if new sparkline data should replace existing cached data.
    /// Protects against replacing good data (60+ points) with degraded data (< 10 points)
    /// when API rate limits cause fallback to synthetic/partial data.
    private func shouldReplaceSparkline(existing: [Double]?, new: [Double]) -> Bool {
        // Always accept if no existing data
        guard let existing = existing, !existing.isEmpty else { return true }
        // Don't replace with empty or very small data (likely degraded/synthetic)
        guard new.count >= 10 else { return false }
        // Don't replace valid data (60+ points) with much smaller data (likely partial fetch)
        guard existing.count < 10 || new.count >= existing.count / 2 else { return false }
        // Accept if new data is similar size or larger
        return true
    }
    
    /// Checks if we're in a degraded API state by looking at sparkline cache quality.
    /// Returns true if most watchlist coins have poor or missing sparkline data.
    @MainActor private func isInDegradedState() -> Bool {
        let coins = effectiveWatchlist
        guard !coins.isEmpty else { return false }
        
        var degradedCount = 0
        for coin in coins {
            // Check if sparkline cache has good data (60+ points)
            if let cached = sparklineCache[coin.id], cached.count >= 60 {
                continue // Good data
            }
            // Check if marketVM has good sparkline
            if let vmCoin = marketVM.allCoins.first(where: { $0.id == coin.id }),
               vmCoin.sparklineIn7d.count >= 60 {
                continue // Good data
            }
            degradedCount += 1
        }
        
        // Consider degraded if more than 40% of coins lack good sparkline data
        return Double(degradedCount) / Double(coins.count) > 0.4
    }
    
    /// Adjusts throttle interval based on API health. Call periodically to adapt to conditions.
    @MainActor private func adjustThrottleIfNeeded() {
        if isInDegradedState() {
            // Increase throttle to reduce load when APIs are struggling
            if lastLivePriceThrottleInterval < degradedThrottleInterval {
                lastLivePriceThrottleInterval = degradedThrottleInterval
            }
        } else {
            // Gradually return to normal throttle
            if lastLivePriceThrottleInterval > normalThrottleInterval {
                lastLivePriceThrottleInterval = normalThrottleInterval
            }
        }
    }
    
    // MARK: - 7D Color Stabilization
    /// Stabilizes the `isPositive7D` decision to prevent rapid green/red color flashing.
    /// Uses hysteresis: requires multiple consecutive confirmations before changing color.
    /// This is critical for coins like Ethereum where the 7D change hovers near zero.
    ///
    /// When a strong provider signal is available (|7D%| > 1%), the stabilizer is bypassed
    /// to ensure the color always matches the authoritative provider data.
    ///
    /// - Parameters:
    ///   - rawDecision: The raw `isPositive7D` computed from API/sparkline data
    ///   - coinID: The coin identifier for cache lookup
    ///   - providerPercent: Optional provider 7D percent; when |value| > 1% the decision is accepted immediately
    /// - Returns: A stabilized `isPositive7D` value that won't flicker
    @MainActor private func stabilizeIsPositive7D(raw rawDecision: Bool, for coinID: String, providerPercent: Double? = nil) -> Bool {
        let now = Date()
        
        // FAST PATH: When the provider signal is strong and clear (|7D%| > 1%),
        // bypass stabilization entirely.
        if let pct = providerPercent, pct.isFinite, abs(pct) > 1.0 {
            engine.isPositiveCache[coinID] = (decision: rawDecision, confirmCount: 0, lastUpdate: now)
            return rawDecision
        }
        
        // Check if we have a cached decision for this coin
        if let cached = engine.isPositiveCache[coinID] {
            if now.timeIntervalSince(cached.lastUpdate) > colorCacheStaleInterval {
                engine.isPositiveCache[coinID] = (decision: rawDecision, confirmCount: 1, lastUpdate: now)
                return rawDecision
            }
            if rawDecision == cached.decision {
                engine.isPositiveCache[coinID] = (decision: cached.decision, confirmCount: 0, lastUpdate: now)
                return cached.decision
            }
            let newConfirmCount = cached.confirmCount + 1
            if newConfirmCount >= colorFlipConfirmationsRequired {
                engine.isPositiveCache[coinID] = (decision: rawDecision, confirmCount: 0, lastUpdate: now)
                return rawDecision
            } else {
                engine.isPositiveCache[coinID] = (decision: cached.decision, confirmCount: newConfirmCount, lastUpdate: now)
                return cached.decision
            }
        } else {
            engine.isPositiveCache[coinID] = (decision: rawDecision, confirmCount: 0, lastUpdate: now)
            return rawDecision
        }
    }
    
    // scheduleColorCacheUpdate() removed — isPositive7DCache is now in the
    // EngineBookkeeping class. Direct writes don't trigger @State re-renders.
    
    /// Fetches sparklines for watchlist coins using the shared service.
    /// Loads any persisted sparklines from disk into local cache for instant display
    private func loadPersistedSparklines() {
        Task {
            let persisted = await WatchlistSparklineService.shared.getAllCachedSparklines()
            guard !persisted.isEmpty else { return }
            
            await MainActor.run {
                var updated = false
                for (id, sparkline) in persisted {
                    // Only update if no existing data - persisted cache is for bootstrap only
                    if self.sparklineCache[id] == nil && !sparkline.isEmpty {
                        self.sparklineCache[id] = sparkline
                        updated = true
                    }
                }
                if updated {
                    // Clear engine cache to use the new sparkline data
                    // Note: clearEngineCache already calls scheduleTickUpdate()
                    self.clearEngineCache(for: Array(persisted.keys))
                }
            }
        }
    }
    
    // FIX: Consolidated watchlist refresh function called from all tab-switch handlers.
    // Debounces to ~50ms so that when .onAppear, .onChange(refreshGeneration), and
    // .onReceive(selectedTab) all fire simultaneously on a tab switch, only ONE actual
    // refresh runs instead of three. This prevents 3-4+ back-to-back body re-evaluations.
    @MainActor private func scheduleWatchlistRefresh() {
        pendingWatchlistRefresh?.cancel()
        let work = DispatchWorkItem { [self] in
            // Invalidate the effectiveWatchlist cache so we get fresh data
            self.effectiveCache.result = []
            let freshWatchlist = self.effectiveWatchlist
            let cachedIDs = Set(self.cachedWatchlist.map { $0.id })
            let freshIDs = Set(freshWatchlist.map { $0.id })
            
            // Only update if membership or count actually changed
            if cachedIDs != freshIDs || self.cachedWatchlist.count != freshWatchlist.count {
                self.cachedWatchlist = freshWatchlist
                self.lastWatchlistCacheAt = Date()
                self.lastRowDataComputeAt = .distantPast
                
                // Reconcile localOrder
                let orderedFreshIDs = freshWatchlist.map { $0.id }
                let currentSet = Set(self.localOrder)
                let newSet = Set(orderedFreshIDs)
                if newSet != currentSet || self.localOrder.isEmpty {
                    var reconciled = self.localOrder.filter { newSet.contains($0) }
                    let additions = orderedFreshIDs.filter { !currentSet.contains($0) }
                    reconciled.append(contentsOf: additions)
                    self.localOrder = uniqued(reconciled)
                }
            } else if self.cachedWatchlist.isEmpty && !freshWatchlist.isEmpty {
                // First population
                self.cachedWatchlist = freshWatchlist
                self.lastWatchlistCacheAt = Date()
                self.lastRowDataComputeAt = .distantPast
            }
        }
        pendingWatchlistRefresh = work
        // 50ms debounce — enough to coalesce simultaneous handler firings,
        // short enough that the user doesn't notice any delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }
    
    // MEMORY FIX v14: Extracted from .onAppear to allow deferred invocation after suppression.
    @MainActor private func runFullOnAppearSetup() {
        // Phase 0: Reconcile watchlist state
        // Invalidate effectiveWatchlist cache to get fresh data on first setup
        self.effectiveCache.result = []
        let freshWatchlist = self.effectiveWatchlist
        if freshWatchlist != self.cachedWatchlist {
            self.cachedWatchlist = freshWatchlist
            self.lastWatchlistCacheAt = Date()
            self.lastRowDataComputeAt = .distantPast
            let freshIDs = freshWatchlist.map { $0.id }
            let currentSet = Set(self.localOrder)
            let newSet = Set(freshIDs)
            if newSet != currentSet || self.localOrder.isEmpty {
                var reconciled = self.localOrder.filter { newSet.contains($0) }
                let additions = freshIDs.filter { !currentSet.contains($0) }
                reconciled.append(contentsOf: additions)
                self.localOrder = uniqued(reconciled)
            }
        }
        
        // Phase 1: Essential state setup (cache clearing + subscriptions)
        DispatchQueue.main.async {
            self.engine.clearAll()
            self.engineOutByID.removeAll()
            self.lastInvalidationTime.removeAll()
            
            // MEMORY FIX v15: Load caches async instead of at @State init.
            // This is why clean install worked but reopen crashed.
            if self.preloadedCacheFallback == nil {
                self.preloadedCacheFallback = CacheManager.shared.load([MarketCoin].self, from: "coins_cache.json")
            }
            if self.sparklineCache.isEmpty {
                self.sparklineCache = WatchlistSparklineService.loadCachedSparklinesSync()
            }
            
            // Invalidate and recompute after caches are loaded (richer data available)
            self.effectiveCache.result = []
            self.cachedWatchlist = self.effectiveWatchlist
            self.lastWatchlistCacheAt = Date()
            
            let allCoins = MarketViewModel.shared.allCoins
            let lpmCoins = LivePriceManager.shared.currentCoinsList
            for coin in self.cachedWatchlist {
                if let vmCoin = allCoins.first(where: { $0.id == coin.id }) {
                    let spark = vmCoin.sparklineIn7d.filter { $0.isFinite && $0 > 0 }
                    if spark.count >= 10 {
                        self.sparklineCache[coin.id] = spark
                        continue
                    }
                }
                if let lpmCoin = lpmCoins.first(where: { $0.id == coin.id }) {
                    let spark = lpmCoin.sparklineIn7d.filter { $0.isFinite && $0 > 0 }
                    if spark.count >= 10 {
                        self.sparklineCache[coin.id] = spark
                        continue
                    }
                }
            }
            
            if !self.initialSparklineCache.isEmpty {
                for (id, sparkline) in self.initialSparklineCache {
                    if (self.sparklineCache[id] == nil || self.sparklineCache[id]?.isEmpty == true) && !sparkline.isEmpty {
                        self.sparklineCache[id] = sparkline
                    }
                }
            }
            
            if self.livePriceCancellable == nil {
                self.livePriceCancellable = LivePriceManager.shared.slowPublisher
                    .receive(on: DispatchQueue.main)
                    .sink { [self] _ in
                        guard isActive, !isDragging else { return }
                        guard !scrollStateManager.shouldBlockHeavyOperation() else { return }
                        self.lastLivePriceUpdateAt = Date()
                        self.scheduleWatchlistRefresh()
                    }
            }
            
            #if os(iOS)
            if self.memoryWarningObserver == nil {
                self.memoryWarningObserver = NotificationCenter.default.addObserver(
                    forName: UIApplication.didReceiveMemoryWarningNotification,
                    object: nil,
                    queue: .main
                ) { [self] _ in
                    Task { @MainActor in
                        self.engineOutByID.removeAll()
                        self.engine.inFlight.removeAll()
                        clearAllMetricsCaches()
                    }
                }
            }
            #endif
        }
        
        // Phase 2: Deferred network calls — load persisted data first, then kick off
        // network fetches in parallel. Tighter delays for sub-second watchlist population.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000) // 0.15s settle
            guard isActive else { return }
            loadPersistedSparklines()
            // Kick off sparkline fetch AND percentage prefetch in parallel
            try? await Task.sleep(nanoseconds: 100_000_000) // +0.10s
            guard isActive else { return }
            fetchSparklines()
            prefetchPercentagesForWatchlist()
            startSparklineRefreshTimer()
            // FIX v14c: Mark setup as complete to prevent re-running on tab return
            self.hasCompletedFullSetup = true

            // FRESH DATA FIX: Run a second prefetch after CoinGecko data has likely arrived.
            // The first prefetch may return sidecar cache values or nil (during grace period).
            // By 10s, CoinGecko via Firebase proxy should have responded with accurate 1h/24h/7d data.
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10s
            guard isActive else { return }
            self.effectiveCache.result = [] // Force effectiveWatchlist to recompute with fresh coins
            prefetchPercentagesForWatchlist()
        }
    }
    
    private func fetchSparklines() {
        let coins = effectiveWatchlist
        guard !coins.isEmpty else { return }
        
        Task {
            let coinData = coins.map { (id: $0.id, symbol: $0.symbol.uppercased()) }
            let fetchedIDs = await WatchlistSparklineService.shared.fetchSparklines(for: coinData)
            var fetchedByID: [String: [Double]] = [:]
            for id in fetchedIDs {
                if let sparkline = await WatchlistSparklineService.shared.getSparkline(for: id) {
                    fetchedByID[id] = sparkline
                }
            }
            
            // Update local cache mirror and trigger UI refresh
            await MainActor.run {
                var anyUpdated = false
                for (id, sparkline) in fetchedByID {
                    if self.shouldReplaceSparkline(existing: self.sparklineCache[id], new: sparkline) {
                        self.sparklineCache[id] = sparkline
                        self.engineOutByID.removeValue(forKey: id.uppercased())
                        self.engine.inFlight.remove(id.uppercased())
                        anyUpdated = true
                    }
                }
                if anyUpdated {
                    self.scheduleTickUpdate()
                }
            }
        }
    }
    
    /// Refreshes sparklines for all watchlist coins (clears cache and re-fetches)
    private func refreshSparklines() {
        let coins = effectiveWatchlist
        guard !coins.isEmpty else { return }
        
        Task {
            let coinData = coins.map { (id: $0.id, symbol: $0.symbol.uppercased()) }
            let fetchedIDs = await WatchlistSparklineService.shared.refreshSparklines(for: coinData)
            var fetchedByID: [String: [Double]] = [:]
            for id in fetchedIDs {
                if let sparkline = await WatchlistSparklineService.shared.getSparkline(for: id) {
                    fetchedByID[id] = sparkline
                }
            }
            
            await MainActor.run {
                var anyUpdated = false
                for (id, sparkline) in fetchedByID {
                    if self.shouldReplaceSparkline(existing: self.sparklineCache[id], new: sparkline) {
                        self.sparklineCache[id] = sparkline
                        self.engineOutByID.removeValue(forKey: id.uppercased())
                        self.engine.inFlight.remove(id.uppercased())
                        anyUpdated = true
                    }
                }
                if anyUpdated {
                    self.scheduleTickUpdate()
                }
            }
        }
    }
    
    /// Proactively fetches percentage changes (1h/24h) for watchlist coins.
    /// ALWAYS fetches to ensure LivePriceManager sidecar cache has the latest values,
    /// even when the coin object has a stale embedded value from a previous session.
    private func prefetchPercentagesForWatchlist() {
        let coins = effectiveWatchlist
        guard !coins.isEmpty else { return }

        // Capture coins for the task to avoid capturing self
        let coinsToFetch = coins

        Task {
            let manager = LivePriceManager.shared

            for coin in coinsToFetch {
                // Always fetch 1h and 24h to refresh LivePriceManager's sidecar cache.
                // Previously only fetched when coin.priceChangePercentage* was nil,
                // which left stale values in the cache when the coin had a wrong embedded value.
                let _ = await manager.bestChange1hPercentAsync(for: coin)
                let _ = await manager.bestChange24hPercentAsync(for: coin)
            }

            // After all fetches complete, trigger a UI refresh + force cache invalidation
            await MainActor.run {
                self.lastRowDataComputeAt = .distantPast // Force cache refresh
                self.scheduleTickUpdate()
            }
        }
    }
    
    /// Starts a timer to periodically refresh sparkline data (every 2 minutes for accuracy)
    private func startSparklineRefreshTimer() {
        #if targetEnvironment(simulator)
        // MEMORY FIX v5.0.12: Skip sparkline refresh timer on simulator — no live data.
        return
        #else
        
        sparklineRefreshTimer?.invalidate()
        sparklineRefreshTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { timer in
            Task { @MainActor in
                // SAFETY: If the timer was already invalidated, stop firing.
                // This guards against the case where onDisappear doesn't fire
                // (e.g., tab switches, sheet dismissals).
                guard timer.isValid else { return }
                if CryptoSageAIApp.isEmergencyStopActive() {
                    timer.invalidate()
                    return
                }
                // Reload from service to ensure cache is current
                loadPersistedSparklines()

                // Fetch fresh data if service says we should refresh
                if await WatchlistSparklineService.shared.shouldRefresh() {
                    refreshSparklines()
                }
            }
        }
        #endif
    }
    
    /// Stops the sparkline refresh timer
    private func stopSparklineRefreshTimer() {
        sparklineRefreshTimer?.invalidate()
        sparklineRefreshTimer = nil
    }

    // Helper to create a sparkline fingerprint for cache invalidation detection
    // NOTE: This fingerprint is orientation-invariant - it produces the same hash
    // regardless of whether the series is reversed. This prevents false invalidations
    // due to orientation changes in MarketMetricsEngine.
    private func sparklineFingerprint(_ series: [Double]) -> Int {
        guard !series.isEmpty else { return 0 }
        var hasher = Hasher()
        hasher.combine(series.count)
        
        // Use min/max/sum which are orientation-invariant
        let validValues = series.filter { $0.isFinite && $0 > 0 }
        guard !validValues.isEmpty else { return 0 }
        
        let minVal = validValues.min() ?? 0
        let maxVal = validValues.max() ?? 0
        let range = maxVal - minVal
        
        // Quantize to avoid tiny floating point differences causing hash changes
        hasher.combine(Int(minVal * 10))
        hasher.combine(Int(maxVal * 10))
        hasher.combine(Int(range * 10))
        
        // Include the count of values for additional specificity
        hasher.combine(validValues.count)
        
        return hasher.finalize()
    }
    
    // Track last invalidation time per coin to prevent rapid re-invalidation cycles
    // SPARKLINE FIX: Increased from 2s to 30s - sparklines showing 7D data should NOT
    // be invalidated every 2 seconds. This was causing the visual glitching.
    @State private var lastInvalidationTime: [String: Date] = [:]
    private let invalidationCooldown: TimeInterval = 30.0 // Minimum 30 seconds between invalidations

    /// Unified color decision for sparkline trend across Watchlist/Market.
    /// Provider values are authoritative so line color matches displayed percentages.
    @MainActor
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

    // *** UPDATED FUNCTION BODY for metrics(for:) ***
    // CRITICAL: This function is called during view body evaluation.
    // It MUST NOT modify state directly - all state changes must be deferred via Task/async
    // to avoid "Modifying state during view update" crashes and infinite re-render loops.
    @MainActor private func metrics(for coin: MarketCoin) -> RowMetrics {
        // MEMORY FIX v14: During startup suppression window, return minimal metrics
        // WITHOUT spawning ANY Task.detached blocks. Normal metrics computation spawns
        // 3-4 Task.detached per coin (stabilizeIsPositive7D → scheduleColorCacheUpdate,
        // stableMetricsCache update, engine computation → engineOutByID, scheduleTickUpdate).
        // Each Task modifies @State dictionaries, triggering body re-evaluation cascades.
        // With 8 visible coins: ~32 @State mutations → continuous body re-evaluations.
        // Each body evaluation allocates ~100 KB for SparklineView (GeometryReader closures,
        // Catmull-Rom paths, AnyView wrappers). At effective ~400 evaluations/sec from
        // cascading mutations, this causes ~40 MB/s memory growth → OOM crash in 90s.
        // By returning static metrics during startup, we eliminate ALL Task spawning
        // and reduce body re-evaluations to only external triggers.
        if shouldSuppressStartupAnimations() {
            let isStable = coin.isStable
            let startupSpark: [Double] = {
                // During startup suppression, still show the best local sparkline we already have.
                let fromCache = (sparklineCache[coin.id] ?? []).filter { $0.isFinite && $0 > 0 }
                let fromCoin = coin.sparklineIn7d.filter { $0.isFinite && $0 > 0 }
                if fromCache.count >= 10 { return fromCache }
                if fromCoin.count >= 10 { return fromCoin }
                return fromCache.count >= fromCoin.count ? fromCache : fromCoin
            }()
            // Use coin's embedded percentages if available, with LivePriceManager sidecar fallback
            let lpm = LivePriceManager.shared
            let p1h: Double? = {
                if let v = coin.priceChangePercentage1hInCurrency, v.isFinite { return v / 100.0 }
                if let v = lpm.bestChange1hPercent(for: coin), v.isFinite { return v / 100.0 }
                return nil
            }()
            let p24h: Double? = {
                if let v = coin.priceChangePercentage24hInCurrency, v.isFinite { return v / 100.0 }
                if let v = lpm.bestChange24hPercent(for: coin), v.isFinite { return v / 100.0 }
                return nil
            }()
            let pos: Bool = {
                if let p7 = coin.priceChangePercentage7dInCurrency, p7.isFinite { return p7 >= 0 }
                if let p24 = coin.priceChangePercentage24hInCurrency, p24.isFinite { return p24 >= 0 }
                if startupSpark.count >= 2,
                   let first = startupSpark.first,
                   let last = startupSpark.last,
                   first.isFinite,
                   last.isFinite,
                   first > 0 {
                    return last >= first
                }
                return true
            }()
            return (isStable, startupSpark, pos, p1h, p24h)
        }

        // Stable coin flag: use model's canonical property
        let isStable = coin.isStable

        // Live price anchor for sparkline orientation/derivation
        // PRICE CONSISTENCY FIX: Use bestPrice() as primary source (checks LivePriceManager internally)
        // This ensures price consistency across all views (HomeView, MarketView, CoinDetailView, TradeView)
        let lpmCoins = LivePriceManager.shared.currentCoinsList
        let liveCoin = lpmCoins.first(where: { $0.id == coin.id || $0.symbol.lowercased() == coin.symbol.lowercased() })
        let live = marketVM.bestPrice(for: coin.id) ?? liveCoin?.priceUsd ?? coin.priceUsd

        // SPARKLINE FIX: Use stable metrics cache first to completely prevent glitching
        // The cache stores the sparkline data AND the computed isPositive7D value together
        // This ensures they always stay in sync and don't flicker independently
        
        // Check if we have valid cached metrics for this coin
        let now = Date()
        if let cached = engine.stableMetrics[coin.id],
           cached.spark.count >= 10,
           now.timeIntervalSince(cached.cacheTime) < metricsCacheValidDuration {
            // Use cached sparkline shape but ALWAYS apply fresh orientation check
            // and use fresh percentage data with fallback chain
            let manager = LivePriceManager.shared
            let sourceForPercents = liveCoin ?? coin
            
            // STALE DATA FIX: Only use LivePriceManager — no fallback to stale coin properties
            let provider1h: Double? = manager.bestChange1hPercent(for: sourceForPercents)
            
            let provider24h: Double? = manager.bestChange24hPercent(for: sourceForPercents)
            
            let provider7dCached: Double? = manager.bestChange7dPercent(for: sourceForPercents)
            
            // Use cached sparkline as-is — do NOT reverse based on percentage signals.
            // Sparkline data from Binance/CoinGecko is already chronological (oldest→newest).
            let cachedSparkCorrected = cached.spark
            
            // FRESH COLOR v25: Use provider data for color instead of stale cached isPositive.
            // FIX: Lowered thresholds so provider values are used even for small changes.
            // Previously, abs(p7) > 1.0 meant small 7D changes fell through to cached.isPositive
            // which could be wrong (set during a previous startup default-to-green).
            let freshIsPositive = unifiedTrendPositive(
                spark: cachedSparkCorrected,
                provider7d: provider7dCached,
                provider24h: provider24h,
                fallback: cached.isPositive
            )
            let stabilizedPos = stabilizeIsPositive7D(raw: freshIsPositive, for: coin.id, providerPercent: provider7dCached)
            
            // Convert percent to fraction, preserving nil for "no data"
            func frac(_ p: Double?) -> Double? {
                guard let p = p, p.isFinite else { return nil }
                return p / 100.0
            }
            
            return (isStable, cachedSparkCorrected, stabilizedPos, frac(provider1h), frac(provider24h))
        }
        
        // Need to compute fresh data
        let rawSpark: [Double] = {
            // Helper to validate sparkline data (minimum 2 points for a valid chart)
            func usable(_ arr: [Double]) -> [Double]? {
                let filtered = arr.filter { $0.isFinite && $0 > 0 }
                return filtered.count >= 2 ? filtered : nil
            }
            
            // DATA CONSISTENCY: Prefer LivePriceManager (Firestore CoinGecko) sparkline FIRST.
            // This is the same data source that the Market page uses, ensuring identical sparklines
            // across Watchlist and Market pages. Single source of truth.
            var bestSpark: [Double] = []
            
            // 1. LivePriceManager's Firestore CoinGecko data (PRIMARY — same as Market page)
            if let lc = liveCoin,
               let spark = usable(lc.sparklineIn7d),
               spark.count >= 10 {
                bestSpark = spark
            }
            
            // 2. Fall back to marketVM.allCoins (also Firestore-fed)
            if bestSpark.count < 40,
               let vmCoin = marketVM.allCoins.first(where: { $0.id == coin.id }),
               let spark = usable(vmCoin.sparklineIn7d),
               spark.count > bestSpark.count + 20 || bestSpark.isEmpty {
                bestSpark = spark
            }
            
            // 3. Try marketVM.lastGoodAllCoins as backup
            if bestSpark.count < 40,
               let lastGoodCoin = marketVM.lastGoodAllCoins.first(where: { $0.id == coin.id }),
               let spark = usable(lastGoodCoin.sparklineIn7d),
               spark.count > bestSpark.count + 20 || bestSpark.isEmpty {
                bestSpark = spark
            }
            
            // 4. Fall back to passed coin's sparkline
            if bestSpark.count < 40,
               let spark = usable(coin.sparklineIn7d),
               spark.count > bestSpark.count + 20 || bestSpark.isEmpty {
                bestSpark = spark
            }

            // Stable cache is a fallback only when fresh providers have no usable data.
            if bestSpark.count < 10,
               let stableSpark = engine.stableSpark[coin.id],
               let stableUsable = usable(stableSpark),
               stableUsable.count >= 10 {
                bestSpark = stableUsable
            }
            
            // Keep stable cache synchronized with materially changed data.
            if bestSpark.count >= 10 {
                let existing = engine.stableSpark[coin.id] ?? []
                let lastChangedMeaningfully: Bool = {
                    guard let oldLast = existing.last, let newLast = bestSpark.last, oldLast > 0 else {
                        return !existing.isEmpty
                    }
                    return abs(newLast - oldLast) / oldLast > 0.001
                }()
                let shouldUpdateStable = existing.isEmpty || bestSpark.count > existing.count || lastChangedMeaningfully
                if shouldUpdateStable {
                    // Write directly to class wrapper — no @State mutation, no re-render
                    engine.stableSpark[coin.id] = bestSpark
                }
            }
            
            return bestSpark
        }()
        
        // Display series: use real sparkline data if available
        // Only use VM's displaySparkline as absolute last resort (may synthesize data)
        // Prefer showing nothing or a minimal line over fake synthetic data
        let displaySpark: [Double] = {
            if !rawSpark.isEmpty {
                return rawSpark
            }
            // Try marketVM's displaySparkline but check if it returns real or synthetic data
            let vmSpark = marketVM.displaySparkline(for: coin)
            // If vmSpark looks like synthetic data (very small count or all same values), return empty
            if vmSpark.count < 10 {
                return rawSpark // Return empty, will show placeholder
            }
            return vmSpark
        }()

        // Use LivePriceManager as primary source, with coin's built-in data as fallback
        // This ensures we show real data immediately on launch before LivePriceManager loads
        let manager = LivePriceManager.shared
        let sourceForPercents = liveCoin ?? coin
        
        // STALE DATA FIX: Only use LivePriceManager as the source of truth for percentages.
        // Do NOT fall back to coin.unified*Percent or coin.priceChangePercentage*InCurrency
        // because those come from MarketViewModel's cached coins which may have stale values
        // (e.g., showing +5% when the real change is -12% after a crash).
        // LivePriceManager has its own startup grace period and staleness protection.
        let provider1h: Double? = manager.bestChange1hPercent(for: sourceForPercents)
        
        let provider24h: Double? = manager.bestChange24hPercent(for: sourceForPercents)
        
        let provider7d: Double? = manager.bestChange7dPercent(for: sourceForPercents)
        
        // SPARKLINE DATA INTEGRITY: Do NOT reverse sparkline arrays based on percentage signals.
        // Binance klines and CoinGecko API always return data in chronological order (oldest→newest).
        // Reversing based on stale percentage data creates fake, numerically backwards charts.
        // Instead, display the sparkline as-is and rely on isPositive color for direction signal.

        let idKey = coin.id.uppercased()
        
        // Check if cached engine output exists
        if let out = engineOutByID[idKey] {
            // Compute orientation-invariant fingerprints for comparison
            let freshFingerprint = sparklineFingerprint(rawSpark.isEmpty ? displaySpark : rawSpark)
            let cachedFingerprint = sparklineFingerprint(out.display)
            
            // Check if we should invalidate: fingerprints differ AND we're not in cooldown
            let now = Date()
            let lastInvalidation = lastInvalidationTime[idKey] ?? .distantPast
            let canInvalidate = now.timeIntervalSince(lastInvalidation) >= invalidationCooldown
            
            // SPARKLINE FIX: Made invalidation much more conservative
            // Only invalidate if:
            // 1. Fingerprints differ (orientation-invariant comparison)
            // 2. We have substantial raw data to replace with (at least 30 points)
            // 3. Cooldown period has passed (prevents rapid cycles)
            // 4. The data count differs SIGNIFICANTLY (at least 20% difference)
            // 5. OR the new data is much better quality (>50 more points)
            let countDiffers = abs(rawSpark.count - out.display.count) > max(20, out.display.count / 5)
            let significantlyBetterData = rawSpark.count > out.display.count + 50
            let hasSubstantialData = rawSpark.count >= 30
            let shouldInvalidate = freshFingerprint != cachedFingerprint && hasSubstantialData && canInvalidate && (countDiffers || significantlyBetterData)
            
            // PERFORMANCE FIX v3: Skip task creation during scroll to prevent jank
            if shouldInvalidate && !ScrollStateManager.shared.isScrolling && !ScrollStateManager.shared.isFastScrolling {
                let capturedIdKey = idKey
                Task.detached { @MainActor in
                    // Record invalidation time to prevent rapid re-invalidation
                    self.lastInvalidationTime[capturedIdKey] = Date()
                    // Wait a bit longer before invalidating to batch rapid updates
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    self.engineOutByID.removeValue(forKey: capturedIdKey)
                    self.engine.inFlight.remove(capturedIdKey)
                }
            }
            
            // Always return cached data (with fresh percentages) while async update happens
            // This prevents visual glitching during recomputation
            // COLOR FIX v24: Provider percentages are the PRIMARY color signal.
            // On startup, sparkline data can be stale from cache (previous session) showing old
            // upward trends when the market has since gone down. Provider 7D% updates faster from
            // Firestore/API and is the authoritative source. Sparkline visual direction is only
            // used as a fallback when no provider data is available.
            let cachedDisplay = out.display
            let sparkForColor = cachedDisplay.isEmpty ? rawSpark : cachedDisplay
            let rawPosOverride = unifiedTrendPositive(
                spark: sparkForColor,
                provider7d: provider7d,
                provider24h: provider24h,
                fallback: out.isPositive7D
            )
            // CRITICAL: Stabilize the color decision to prevent rapid green/red flashing
            // Pass provider 7D percent to bypass stabilization when signal is strong
            let posOverride = stabilizeIsPositive7D(raw: rawPosOverride, for: coin.id, providerPercent: provider7d)
            // Preserve nil when no data is available - engine now returns nil instead of 0
            let oneHFracOverride: Double? = {
                if let p = provider1h, p.isFinite { return p / 100.0 }
                // Use engine value if available (now properly nil when no data)
                if let engineVal = out.oneHFrac, engineVal.isFinite { return engineVal }
                return nil
            }()
            let dayFracOverride: Double? = {
                if let p = provider24h, p.isFinite { return p / 100.0 }
                // Use engine value if available (now properly nil when no data)
                if let engineVal = out.dayFrac, engineVal.isFinite { return engineVal }
                return nil
            }()
            
            // SPARKLINE DATA INTEGRITY: No reversal logic — trust the data source.
            // CoinGecko/Firestore data is always in chronological order (oldest → newest).
            
            return (isStable, cachedDisplay, posOverride, oneHFracOverride, dayFracOverride)
        }

        // Trigger async computation if not already in flight.
        // MEMORY FIX v15: Read gating state from class wrapper (no @State dependency).
        // Write results to class buffer; only the debounced tick applies them to @State.
        let shouldComputeMetrics = !engine.inFlight.contains(idKey) && 
                                   engine.computations < maxConcurrentEngineComputations &&
                                   !ScrollStateManager.shared.isScrolling && 
                                   !ScrollStateManager.shared.isFastScrolling
        if shouldComputeMetrics {
            let capturedIdKey = idKey
            let capturedSymbol = coin.symbol.uppercased()
            let capturedSpark = rawSpark.isEmpty ? displaySpark : rawSpark
            let capturedLive = live
            let capturedProvider1h = provider1h
            let capturedProvider24h = provider24h
            let capturedProvider7d = provider7d
            let capturedIsStable = isStable
            
            Task.detached { @MainActor in
                guard !self.engine.inFlight.contains(capturedIdKey) else { return }
                guard self.engine.computations < self.maxConcurrentEngineComputations else { return }
                self.engine.inFlight.insert(capturedIdKey)
                self.engine.computations += 1
                
                let out = await MarketMetricsCache.shared.compute(
                    symbol: capturedSymbol,
                    rawSeries: capturedSpark,
                    livePrice: capturedLive,
                    provider1h: capturedProvider1h,
                    provider24h: capturedProvider24h,
                    isStable: capturedIsStable,
                    seriesSpanHours: 168.0,
                    targetPoints: 180,
                    provider7d: capturedProvider7d
                )
                // Store result in class buffer — NO @State mutation, NO view re-render
                self.engine.pendingOut[capturedIdKey] = out
                self.engine.inFlight.remove(capturedIdKey)
                self.engine.computations = max(0, self.engine.computations - 1)
                // Debounced tick will apply pendingOut to @State engineOutByID
                self.scheduleTickUpdate()
            }
        }

        // Convert percent to fraction, preserving nil for "no data"
        func frac(_ p: Double?) -> Double? {
            guard let p = p, p.isFinite else { return nil }
            return p / 100.0
        }

        // Return fresh sparkline data immediately (don't wait for async computation)
        let freshSpark: [Double] = rawSpark.isEmpty ? displaySpark : rawSpark
        let fallbackSpark: [Double] = freshSpark.isEmpty ? marketVM.displaySparkline(for: coin) : freshSpark
        
        // SPARKLINE DATA INTEGRITY: No reversal logic — trust the data source.
        // CoinGecko/Firestore data is always in chronological order (oldest → newest).
        
        // COLOR FIX v26: Provider percentages are the PRIMARY color signal.
        // On startup, sparkline data can be stale from cache (previous session) showing old
        // upward trends when the market has since gone down. Provider 7D% updates faster from
        // Firestore/API and is authoritative. Sparkline visual direction is a fallback only.
        let coinFallbackTrend: Bool = {
            if let p7 = coin.priceChangePercentage7dInCurrency, p7.isFinite { return p7 >= 0 }
            if let p24 = coin.priceChangePercentage24hInCurrency, p24.isFinite { return p24 >= 0 }
            return true
        }()
        let rawPos = unifiedTrendPositive(
            spark: fallbackSpark,
            provider7d: provider7d,
            provider24h: provider24h,
            fallback: coinFallbackTrend
        )
        // CRITICAL: Stabilize the color decision to prevent rapid green/red flashing
        // Pass provider 7D percent to bypass stabilization when signal is strong
        let pos = stabilizeIsPositive7D(raw: rawPos, for: coin.id, providerPercent: provider7d)
        
        // Cache the computed metrics in the class wrapper — no @State, no re-render.
        if fallbackSpark.count >= 10 {
            let coinId = coin.id
            if engine.stableMetrics[coinId] == nil ||
               now.timeIntervalSince(engine.stableMetrics[coinId]!.cacheTime) >= metricsCacheValidDuration {
                engine.stableMetrics[coinId] = (spark: fallbackSpark, isPositive: pos, cacheTime: now)
                engine.stableSpark[coinId] = fallbackSpark
            }
        }

        return (isStable, fallbackSpark, pos, frac(provider1h), frac(provider24h))
    }

    private func beginDrag(for coinID: String) -> NSItemProvider {
        draggingID = coinID
        isDragging = true
        dragHeartbeat = Date()
        dragSessionID = UUID()
        ringActive = true
        ringRowID = coinID
        return NSItemProvider(object: coinID as NSString)
    }

    private func rowContainer(coin: MarketCoin, metrics m: RowMetrics) -> some View {
        let reorderDelegate: WatchlistReorderDropDelegate = WatchlistReorderDropDelegate(
            targetID: coin.id,
            localOrder: $localOrder,
            draggingID: $draggingID,
            shakeAttempts: $shakeAttempts,
            isDragging: $isDragging,
            listResetKey: $listResetKey,
            dragHeartbeat: $dragHeartbeat,
            hoverTargetID: $hoverTargetID,
            hoverInsertAfter: $hoverInsertAfter,
            ringCooldownUntil: $ringCooldownUntil,
            ringActive: $ringActive,
            ringRowID: $ringRowID,
            dragSessionID: $dragSessionID,
            onReorder: { newOrder in
                localOrder = newOrder
            }
        )

        // SPARKLINE FIX: Removed uiTick parameter - it was causing unnecessary re-renders
        let row = rowContentInner(
            coin: coin,
            isStable: m.isStable,
            spark: m.spark,
            isPositive7D: m.isPositive7D,
            oneH: m.oneH,
            dayChange: m.dayChange,
            isDragging: isDragging,
            draggingID: draggingID
        )

        return row
            .onDrag { beginDrag(for: coin.id) }
            .onDrop(of: [UTType.plainText], delegate: reorderDelegate)
            .onTapGesture {
                if !isDragging {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    onSelectCoinForDetail(coin)
                }
            }
            // FIX: Removed navigationDestination from here — it was inside a LazyVStack
            // (via RowsListView), which caused SwiftUI warning:
            // "Do not put a navigation destination modifier inside a lazy container"
            // Moved to body (outside the lazy container) for proper navigation stack visibility.
    }

    // PERFORMANCE FIX v19: Made generic instead of using AnyView closure.
    // AnyView erases SwiftUI's structural identity, forcing full re-renders of every
    // visible row on each evaluation. With generic Content, SwiftUI can diff rows
    // efficiently and only re-render rows that actually changed.
    private struct RowsListView<Content: View>: View {
        let rowData: [RowDataItem]
        let endDelegate: WatchlistEndDropDelegate
        let rowContent: (RowDataItem) -> Content

        var body: some View {
            // Simplified: no nested background - parent PremiumGlassCard provides styling
            // PERFORMANCE FIX: Use LazyVStack for on-demand row rendering during scroll
            // This prevents all rows from being rendered upfront, reducing memory and improving scroll performance
            LazyVStack(spacing: 0) {
                ForEach(rowData) { item in
                    rowContent(item)
                        // PERFORMANCE: Disable animations during scroll for smooth 60fps
                        .transaction { $0.animation = nil }
                }
                Color.clear
                    .frame(height: 0.0)
                    .onDrop(of: [UTType.plainText], delegate: endDelegate)
            }
            .padding(.vertical, 0)
            // Horizontal padding removed - handled by parent WatchlistComposite
            // PERFORMANCE: Disable implicit animations on the entire list during scroll
            .transaction { $0.animation = nil }
        }
    }

    // Helper to produce an ordered list of coins from VM and local order
    // PERFORMANCE: Uses cached watchlist to avoid recomputation during body evaluation
    // CRITICAL: This is called during body - must NOT modify state directly
    private func orderedWatchlistCoins() -> [MarketCoin] {
        // Use cached watchlist if still valid (reduces redundant computation)
        let now = Date()
        let watchlist: [MarketCoin]
        let currentFavoriteIDs = FavoritesManager.shared.favoriteIDs
        let cacheIsFresh = now.timeIntervalSince(lastWatchlistCacheAt) < watchlistCacheValidDuration
        
        // WATCHLIST SYNC FIX v2: Validate cache EXACTLY matches current favorites.
        // Previously only checked that cache covers all favorites (subset check), which
        // missed the case where a coin was REMOVED — the removed coin lingered in the cache.
        // Now uses bidirectional check: cache IDs must equal current favorite IDs exactly.
        // This ensures both added AND removed favorites are detected immediately.
        let cachedIDs = Set(cachedWatchlist.map { $0.id })
        let cacheMatchesFavorites = cachedIDs == currentFavoriteIDs
        
        if !cachedWatchlist.isEmpty && cacheIsFresh && cacheMatchesFavorites {
            watchlist = cachedWatchlist
        } else {
            watchlist = effectiveWatchlist
            // NOTE: We intentionally do NOT update the cache here to avoid modifying state during view update.
            // The cache is updated in onAppear and when live price updates arrive.
        }
        
        // Build ordered list from localOrder (fallback to VM order if empty) and ensure uniqueness
        let baseOrder: [String] = localOrder.isEmpty ? watchlist.map { $0.id } : localOrder
        let idOrder: [String] = uniqued(baseOrder)
        let pairs: [(String, MarketCoin)] = watchlist.map { ($0.id, $0) }
        let map: [String: MarketCoin] = Dictionary(pairs, uniquingKeysWith: { first, _ in first })
        var ordered: [MarketCoin] = idOrder.compactMap { map[$0] }
        
        // WATCHLIST INSTANT-SYNC FIX: Append any watchlist coins NOT in localOrder.
        // When a coin is newly favorited, localOrder hasn't been updated yet (it's reconciled
        // asynchronously via .onChange). Without this safety net, newly favorited coins are
        // silently filtered out by compactMap because their ID isn't in idOrder.
        // This ensures new coins always appear immediately (at the end), even before
        // localOrder is reconciled on the next render cycle.
        let orderedSet = Set(idOrder)
        let missing = watchlist.filter { !orderedSet.contains($0.id) }
        if !missing.isEmpty {
            // Respect FavoritesManager order for missing coins
            let favOrder = FavoritesManager.shared.getOrder()
            let sortedMissing = missing.sorted { a, b in
                let idxA = favOrder.firstIndex(of: a.id) ?? Int.max
                let idxB = favOrder.firstIndex(of: b.id) ?? Int.max
                return idxA < idxB
            }
            ordered.append(contentsOf: sortedMissing)
        }
        
        return ordered
    }

    // Helper to build the rows view to keep the main body simple for the type-checker
    // SCROLL PERFORMANCE FIX: Use cached row data to avoid expensive metrics computation during scroll
    // PERFORMANCE FIX v19: Changed from AnyView to some View for structural identity
    private func buildRowsView() -> some View {
        let coinsToShow: [MarketCoin] = orderedWatchlistCoins()
        
        // SCROLL PERFORMANCE FIX: Aggressively use cached data during scroll
        // The metrics computation is expensive (touches multiple dictionaries, LivePriceManager, etc.)
        // During fast scroll, this was causing 1-2 second pauses and visual glitches
        let now = Date()
        let isScrollingOrDragging = scrollStateManager.isScrolling || scrollStateManager.isDragging
        let isFastScrolling = scrollStateManager.isFastScrolling
        let cacheIsValid = !cachedRowData.isEmpty && cachedRowData.count == coinsToShow.count
        let cacheIsFresh = now.timeIntervalSince(lastRowDataComputeAt) < rowDataCacheValidDuration
        
        // PERFORMANCE FIX: Maximum aggressive caching during ANY scroll state
        // This prevents sparklines from "dragging" and other visual glitches during scroll
        // Priority order:
        // 1. ANY scroll activity + valid cache = use cache (even if stale)
        // 2. Fast scrolling = use cache (even if empty - will compute once on first render)
        // 3. Cache is fresh = use cache
        // 4. Not scrolling + cache stale = allow recomputation
        let isAnyScrollActivity = isScrollingOrDragging || isFastScrolling
        let shouldUseCachedData = (isAnyScrollActivity && cacheIsValid) ||
            isFastScrolling ||
            (cacheIsValid && cacheIsFresh)
        
        // MEMORY FIX v17: NEVER modify @State during body evaluation.
        // Previously, buildRowsView() created Task { self.cachedRowData = freshData } which
        // mutated @State, triggering body re-evaluation → another buildRowsView() call →
        // another Task → infinite cascade. Each cycle allocated ~150 KB of view tree objects.
        // Now: body ALWAYS returns cached data. Fresh computation is scheduled asynchronously
        // with a re-entry guard to prevent cascade.
        let rowData: [RowDataItem]
        if shouldUseCachedData {
            // Use cached data - no expensive computation during scroll
            rowData = cachedRowData
        } else if cachedRowData.isEmpty {
            // First render: compute minimal data synchronously (no @State mutation)
            // STALE DATA FIX: Also check LivePriceManager sidecar cache for coins with nil
            // embedded percentages. The sidecar persists across sessions and often has fresh values
            // when the coin objects haven't been augmented yet.
            let lpm = LivePriceManager.shared
            let minimalData = coinsToShow.map { coin -> RowDataItem in
                let isStable = coin.isStable
                let p1h: Double? = {
                    if let v = coin.priceChangePercentage1hInCurrency, v.isFinite { return v / 100.0 }
                    if let v = lpm.bestChange1hPercent(for: coin), v.isFinite { return v / 100.0 }
                    return nil
                }()
                let p24h: Double? = {
                    if let v = coin.priceChangePercentage24hInCurrency, v.isFinite { return v / 100.0 }
                    if let v = lpm.bestChange24hPercent(for: coin), v.isFinite { return v / 100.0 }
                    return nil
                }()
                let pos: Bool = {
                    if let p7 = coin.priceChangePercentage7dInCurrency, p7.isFinite { return p7 >= 0 }
                    if let p24 = coin.priceChangePercentage24hInCurrency, p24.isFinite { return p24 >= 0 }
                    return true
                }()
                return RowDataItem(coin: coin, metrics: (isStable, [], pos, p1h, p24h))
            }
            rowData = minimalData
            // Schedule async computation with re-entry guard (will update cache on next run loop)
            if !isComputingRowData {
                DispatchQueue.main.async { [coinsToShow] in
                    guard !self.isComputingRowData else { return }
                    self.isComputingRowData = true
                    let fresh = coinsToShow.map { RowDataItem(coin: $0, metrics: self.metrics(for: $0)) }
                    self.cachedRowData = fresh
                    self.lastRowDataComputeAt = Date()
                    self.isComputingRowData = false
                }
            }
        } else if !shouldUseCachedData && !isComputingRowData {
            // Cache is stale and idle — schedule async recomputation, use stale cache for now
            rowData = cachedRowData
            DispatchQueue.main.async { [coinsToShow] in
                guard !self.isComputingRowData else { return }
                self.isComputingRowData = true
                let fresh = coinsToShow.map { RowDataItem(coin: $0, metrics: self.metrics(for: $0)) }
                self.cachedRowData = fresh
                self.lastRowDataComputeAt = Date()
                self.isComputingRowData = false
            }
        } else {
            // Computing or scrolling with stale cache — use existing cache
            rowData = cachedRowData
        }

        let endDelegate: WatchlistEndDropDelegate = WatchlistEndDropDelegate(
            localOrder: $localOrder,
            draggingID: $draggingID,
            isDragging: $isDragging,
            listResetKey: $listResetKey,
            dragHeartbeat: $dragHeartbeat,
            hoverTargetID: $hoverTargetID,
            hoverInsertAfter: $hoverInsertAfter,
            ringCooldownUntil: $ringCooldownUntil,
            ringActive: $ringActive,
            ringRowID: $ringRowID,
            dragSessionID: $dragSessionID,
            onReorder: { newOrder in
                localOrder = newOrder
            }
        )

        // PERFORMANCE FIX v19: Removed AnyView wrapping - now uses generic RowsListView
        // This allows SwiftUI to use structural identity for efficient row diffing during scroll
        return RowsListView(rowData: rowData, endDelegate: endDelegate) { item in
            rowContainer(coin: item.coin, metrics: item.metrics)
        }
        .id(listResetKey)
        .frame(maxWidth: .infinity)
        .shake(shakeAttempts)
    }

    var body: some View {
        // WATCHLIST SYNC FIX: Use FavoritesManager.favoriteIDs.isEmpty for the empty check
        // instead of calling the expensive effectiveWatchlist computed property.
        // effectiveWatchlist reads from singletons (MarketViewModel, LivePriceManager) that
        // SwiftUI does NOT track as view dependencies. This means changes to those singletons
        // won't trigger body re-evaluation on their own. By contrast, cachedWatchlist is @State
        // and IS tracked. The .onReceive handlers update cachedWatchlist, which triggers re-renders.
        // The favoriteIDs check is the lightest possible way to detect "has favorites".
        let hasFavorites = !FavoritesManager.shared.favoriteIDs.isEmpty
        VStack(alignment: .leading, spacing: 0) {
            if !hasFavorites {
                emptyWatchlistView
            } else if !cachedWatchlist.isEmpty {
                // Cache is populated — render rows using cached data
                buildRowsView()
            } else if !effectiveWatchlist.isEmpty {
                // WATCHLIST SYNC FIX: Cache is empty but live data sources have coins.
                // This handles the case where the view just appeared (e.g., tab switch)
                // and .onAppear hasn't populated the cache yet. orderedWatchlistCoins()
                // will fall through to effectiveWatchlist internally.
                buildRowsView()
            } else {
                loadingWatchlistPlaceholder
            }
        }
        .padding(.vertical, 0)
        .padding(.top, 0)
        .padding(.bottom, 0)
        .onReceive(refreshTimer) { _ in
            // Defer to avoid "Modifying state during view update"
            Task { @MainActor in
                if CryptoSageAIApp.isEmergencyStopActive() {
                    stopSparklineRefreshTimer()
                    return
                }
                guard isActive, !isDragging else { return }
                // SCROLL PERFORMANCE: Skip data fetches during scroll to keep UI responsive
                guard !scrollStateManager.isScrolling else { return }
                // Throttle: skip if a fetch is running or we fetched very recently
                let recent = Date().timeIntervalSince(lastWatchlistFetch) < 20.0
                guard !isFetchingWatchlist, !recent else { return }
                guard !isFetchingWatchlist else { return }
                isFetchingWatchlist = true
                isLoadingWatchlist = true
                
                await marketVM.loadWatchlistData()
                // Invalidate per-coin metrics so 7D/1H/24H recompute with fresh raw series
                clearEngineCache(for: effectiveWatchlist.map { $0.id })
                
                // Check if sparklines need refresh (every 5 minutes via service)
                let shouldRefresh = await WatchlistSparklineService.shared.shouldRefresh()
                if shouldRefresh {
                    refreshSparklines()
                }
                
                isLoadingWatchlist = false
                isFetchingWatchlist = false
                lastWatchlistFetch = Date()
            }
        }
        // SPARKLINE FIX: Removed marketVM.objectWillChange receiver - it was causing excessive re-renders
        // The sparklines should NOT update on every marketVM change since they show 7D data
        
        // SPARKLINE FIX: Disabled the frequent UI refresh timer updates
        // Sparklines only need to update when new data is fetched, not on a timer
        // Price updates come through LivePriceManager which is already throttled
        // Replaced complex inline onChange with watchlistIDs
        .onChange(of: watchlistIDs) { _, ids in
            // Only react to membership changes (add/remove), not order changes.
            guard !isDragging else { return }
            // Use DispatchQueue to defer state modifications outside view update cycle
            DispatchQueue.main.async {
                let newSet = Set(ids)
                let currentSet = Set(self.localOrder)

                // If the sets differ, reconcile membership while preserving existing local ordering.
                if newSet != currentSet || self.localOrder.isEmpty {
                    // Keep existing items that still exist, in current local order
                    var reconciled = self.localOrder.filter { newSet.contains($0) }
                    // Append any new ids (preserve VM order for new items only)
                    let additions = ids.filter { !currentSet.contains($0) }
                    reconciled.append(contentsOf: additions)
                    self.localOrder = uniqued(reconciled)
                }
            }
        }
        .onChange(of: isDragging) { _, active in
            // Defer state modification to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                if active {
                    dragHeartbeat = Date()
                    startDragWatchdog()
                    // Start hover animations
                    if !globalAnimationsKilled {
                        withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: true)) { animatePulse = true }
                    }
                } else {
                    forceClearDragVisuals()
                }
            }
        }
        .onChange(of: draggingID) { _, newID in
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                if newID == nil {
                    forceClearDragVisuals()
                }
            }
        }
        // PERFORMANCE FIX v20: Use targeted onReceive instead of @EnvironmentObject appState
        .onReceive(AppState.shared.$selectedTab) { tab in
            let wasActive = isActiveTab
            isActiveTab = (tab == .home)
            
            if tab == .home {
                // FIX: Use debounced refresh instead of inline effectiveWatchlist call.
                // This coalesces with .onAppear and .onChange(refreshGeneration) that fire
                // simultaneously on tab switch, preventing 3+ redundant body evaluations.
                scheduleWatchlistRefresh()
                consecutiveUpdateSkips = 0
                // Re-subscribe if needed (deferred to avoid blocking tab switch)
                if livePriceCancellable == nil {
                    Task { @MainActor in
                        livePriceCancellable = LivePriceManager.shared.slowPublisher
                            .receive(on: DispatchQueue.main)
                            .sink { [self] _ in
                                guard isActive, !isDragging else { return }
                                guard !scrollStateManager.shouldBlockHeavyOperation() else { return }
                                lastLivePriceUpdateAt = Date()
                                scheduleWatchlistRefresh()
                            }
                    }
                }
            } else if wasActive {
                // Stop live streams to reduce background churn when not on Home
                livePriceCancellable?.cancel()
                livePriceCancellable = nil
            }
        }
        // Dismiss handling for detail navigation is now owned by HomeView,
        // where the navigationDestination lives outside all lazy containers.
        // WATCHLIST INSTANT-SYNC v2: React to generation counter changes from HomeView.
        // FIX: Delegates to scheduleWatchlistRefresh() to coalesce with .onAppear and
        // .onReceive(selectedTab) that fire simultaneously on tab switch.
        .onChange(of: refreshGeneration) { _, _ in
            scheduleWatchlistRefresh()
        }
        .onAppear {
            // FIX v14c: If full setup already ran, do a lightweight refresh only.
            // FIX: Delegates to scheduleWatchlistRefresh() to coalesce with
            // .onChange(refreshGeneration) and .onReceive(selectedTab).
            if hasCompletedFullSetup {
                scheduleWatchlistRefresh()
                return
            }
            
            // Run full setup immediately — EngineBookkeeping class wrapper prevents cascade.
            runFullOnAppearSetup()
        }
        .onDisappear {
            // Cancel live price subscription to reduce background churn
            livePriceCancellable?.cancel()
            livePriceCancellable = nil
            pendingWatchlistRefresh?.cancel()
            pendingWatchlistRefresh = nil
            ringClearTask?.cancel()
            ringClearTask = nil
            // Stop sparkline refresh timer
            stopSparklineRefreshTimer()
            forceClearDragVisuals()
            
            // Remove memory warning observer
            #if os(iOS)
            if let observer = memoryWarningObserver {
                NotificationCenter.default.removeObserver(observer)
                memoryWarningObserver = nil
            }
            #endif
        }
        // WATCHLIST INSTANT-SYNC FIX: Changed from .onChange to .onReceive.
        // CRITICAL: WatchlistSection has NO @ObservedObject/@EnvironmentObject for FavoritesManager
        // or MarketViewModel (removed in v22 for performance). This means .onChange(of:) NEVER fires
        // because it only evaluates when the view body re-renders, and nothing triggers a re-render.
        // .onReceive subscribes to the Combine publisher directly and fires whenever it emits,
        // REGARDLESS of whether the view body has re-rendered. This is THE fix for newly favorited
        // coins not appearing in the watchlist.
        .onReceive(FavoritesManager.shared.$favoriteIDs.removeDuplicates()) { newFavorites in
            // FIX: Invalidate effectiveWatchlist cache since favoriteIDs changed,
            // then delegate the watchlist/localOrder refresh to the debounced handler.
            self.effectiveCache.result = []
            scheduleWatchlistRefresh()
            
            // SPARKLINE FIX: Immediately populate sparkline cache from CoinGecko
            // for any newly favorited coins that don't have data yet.
            // Note: we compute effectiveWatchlist here for sparkline logic only;
            // the cache was just invalidated so this gives a fresh result.
            let freshWatchlist = self.effectiveWatchlist
            let newCoins = freshWatchlist.filter { coin in
                self.sparklineCache[coin.id] == nil || self.sparklineCache[coin.id]?.count ?? 0 < 10
            }
            
            // Immediately copy CoinGecko sparklines for new coins
            for coin in newCoins {
                // Try MarketViewModel first
                if let vmCoin = self.marketVM.allCoins.first(where: { $0.id == coin.id }) {
                    let spark = vmCoin.sparklineIn7d.filter { $0.isFinite && $0 > 0 }
                    if spark.count >= 10 {
                        self.sparklineCache[coin.id] = spark
                        continue
                    }
                }
                // Try coin's own sparkline
                let spark = coin.sparklineIn7d.filter { $0.isFinite && $0 > 0 }
                if spark.count >= 10 {
                    self.sparklineCache[coin.id] = spark
                }
            }
            
            // Then fetch fresh Binance data asynchronously
            if !newCoins.isEmpty {
                fetchSparklines()
            }
        }
        .simultaneousGesture(TapGesture().onEnded {
            forceClearDragVisuals()
        })
        // WATCHLIST INSTANT-SYNC: Backup listener via NotificationCenter.
        // The primary mechanism is .onReceive($favoriteIDs) above, but that Combine
        // subscription can be lost if LazyVStack destroys this view while the user is
        // on the Market tab. NotificationCenter notifications are observed as a Combine
        // publisher here, but the key difference is that even if this subscription is also
        // lost, the .onAppear handler (which fires when LazyVStack recreates the view)
        // will refresh. This notification ensures that if the view IS still alive but the
        // $favoriteIDs subscription somehow didn't fire, we still get the update.
        // FIX: Delegates to scheduleWatchlistRefresh() to consolidate with other handlers
        .onReceive(NotificationCenter.default.publisher(for: .favoritesDidChange)
            .receive(on: DispatchQueue.main)
        ) { _ in
            // Invalidate cache since favoriteIDs have changed
            self.effectiveCache.result = []
            scheduleWatchlistRefresh()
        }
    }

    // MARK: - PremiumGoldBar (clean, subtle gold accent)
    private struct PremiumGoldBar: View {
        var active: Bool = true // kept for API compatibility; not used
        @Environment(\.colorScheme) private var colorScheme
        
        var body: some View {
            let isDark = colorScheme == .dark
            
            // Simple, elegant gold bar without animation
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            BrandGold.light.opacity(isDark ? 0.85 : 0.75),
                            BrandGold.base.opacity(isDark ? 0.7 : 0.6)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 3)
                .padding(.vertical, 6)
                .accessibilityHidden(true)
        }
    }

    // Helper to write preference without stressing type checker
    private struct MetricsPrefWriter: View {
        let value: WatchlistColumnMetrics
        var body: some View {
            Color.clear.preference(key: WatchlistColumnsKey.self, value: value)
        }
    }

    // Premium row divider with gradient fade
    private struct RowBottomDivider: View {
        @Environment(\.colorScheme) private var colorScheme
        
        var body: some View {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            DS.Adaptive.divider.opacity(0.05),
                            DS.Adaptive.divider.opacity(colorScheme == .dark ? 0.35 : 0.2),
                            DS.Adaptive.divider.opacity(0.05)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 0.5)
                .accessibilityHidden(true)
        }
    }

    // Encapsulated swipe action to reduce generic inference in row builder
    // PERFORMANCE FIX v22: Removed @EnvironmentObject from RemoveFavoriteSwipe
    private struct RemoveFavoriteSwipe: ViewModifier {
        let coinID: String
        func body(content: Content) -> some View {
            content.swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    FavoritesManager.shared.toggle(coinID: coinID)
                    MarketViewModel.shared.favoriteIDs = FavoritesManager.shared.getAllIDs()
                    MarketViewModel.shared.applyAllFiltersAndSort()
                    Task { await MarketViewModel.shared.loadWatchlistData() }
                } label: { Label("Remove", systemImage: "trash") }
            }
        }
    }

    private struct RowLeadingInfo: View {
        let active: Bool
        let symbol: String
        let imageUrl: URL?
        let price: Double
        let priceWidth: CGFloat
        let leadingInfoWidth: CGFloat
        let iconSize: CGFloat

        var body: some View {
            HStack(spacing: 4) {  // tighter spacing
                PremiumGoldBar(active: active)
                CoinImageView(symbol: symbol, url: imageUrl, size: iconSize)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(symbol.uppercased())
                        .font(.subheadline.weight(.bold))
                        .fontDesign(.rounded)
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)  // allow slightly more scaling
                        .frame(maxWidth: priceWidth, alignment: .leading)

                    AnimatedPriceText(price: price)
                        .frame(maxWidth: priceWidth, alignment: .leading)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(width: leadingInfoWidth, alignment: .leading)
        }
    }

    private struct RowTrailingMetrics: View {
        let spark: [Double]
        let isStable: Bool
        let isPositive7D: Bool
        let oneH: Double?  // Optional to distinguish "no data" from "0% change"
        let dayChange: Double?  // Optional to distinguish "no data" from "0% change"
        let sparkActualWidth: CGFloat
        let metricsWidth: CGFloat
        let dividerW: CGFloat
        let innerDivider: CGFloat

        var body: some View {
            HStack(spacing: 0) {
                SparkSegmentView(spark: spark, isStable: isStable, isPositive7D: isPositive7D, width: sparkActualWidth)
                    .padding(.trailing, 4)
                    // SCROLL FIX: Clip the sparkline container to prevent overflow during scroll
                    .clipped()
                divider
                metricsSegment
                    .padding(.leading, 4)
            }
            // SCROLL FIX: Ensure entire trailing metrics section clips its content
            .clipped()
        }

        private var divider: some View {
            Rectangle()
                .fill(DS.Adaptive.divider.opacity(0.4))
                .frame(width: 1, height: 30)  // align with sparkline height (34pt with padding)
                .accessibilityHidden(true)
        }

        private var metricsSegment: some View {
            HStack(spacing: 0) {  // Explicit spacing for precise header alignment
                ChangeView(label: "1H", change: oneH, showsLabel: false)
                    .frame(width: changeWidth1h, alignment: .trailing)
                Spacer().frame(width: 3)  // Explicit 3pt before divider
                Rectangle()
                    .fill(DS.Adaptive.divider.opacity(0.3))
                    .frame(width: 1, height: 16)  // slightly taller for better visual balance
                    .accessibilityHidden(true)
                Spacer().frame(width: 3)  // Explicit 3pt after divider
                ChangeView(label: "24H", change: dayChange, showsLabel: false)
                    .frame(width: changeWidth24h, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .frame(width: metricsWidth, height: 30, alignment: .trailing)  // align with sparkline
        }
    }

    private struct SparkSegmentView: View {
        let spark: [Double]
        let isStable: Bool
        let isPositive7D: Bool
        let width: CGFloat
        
        // SPARKLINE FIX: Generate a stable identity hash from ONLY the sparkline data shape
        // NOT the color (isPositive7D) - color changes should NOT cause re-render of the path
        // This prevents SwiftUI from animating/re-rendering when only the color changes
        private var sparklineIdentity: Int {
            guard !spark.isEmpty else { return 0 }
            var hasher = Hasher()
            // Quantize count to ranges to prevent minor count differences from changing identity
            let quantizedCount = (spark.count / 10) * 10  // Round to nearest 10
            hasher.combine(quantizedCount)
            // Use min/max for orientation-invariant identity, heavily quantized
            let validValues = spark.filter { $0.isFinite && $0 > 0 }
            if let minV = validValues.min() { hasher.combine(Int(minV)) }  // Integer only
            if let maxV = validValues.max() { hasher.combine(Int(maxV)) }  // Integer only
            // DO NOT include isPositive7D - color changes should not change identity
            return hasher.finalize()
        }

        // MEMORY FIX v16: Removed AnyView wrapping from sparkline segment.
        // Each AnyView creates a heap-allocated type-erased box that prevents efficient diffing.
        var body: some View {
            // Require at least 10 points for a proper sparkline
            // Fewer points look "broken" and should show the loading placeholder instead
            if spark.count >= 10 {
                // Premium watchlist sparkline - optimized for clarity and visual appeal
                let lineW: CGFloat = isStable ? SparklineConsistency.listStableLineWidth : SparklineConsistency.listLineWidth
                let fillOp: Double = isStable ? SparklineConsistency.listStableFillOpacity : SparklineConsistency.listFillOpacity
                let vPad: CGFloat = SparklineConsistency.listVerticalPaddingRatio
                let smooth: Int = SparklineConsistency.listSmoothSamplesPerSegment
                
                SparklineView(
                    data: spark,
                    isPositive: isPositive7D,
                    overrideColor: isStable ? Color.gray.opacity(0.5) : nil,
                    height: 34,
                    lineWidth: lineW,
                    verticalPaddingRatio: vPad,
                    fillOpacity: fillOp,
                    gradientStroke: true,
                    showEndDot: true,
                    leadingFade: 0.0,
                    trailingFade: 0.0,
                    showTrailHighlight: false,
                    trailLengthRatio: 0.0,
                    endDotPulse: false,
                    backgroundStyle: .none,
                    cornerRadius: 0,
                    glowOpacity: isStable ? 0.0 : SparklineConsistency.listGlowOpacity,
                    glowLineWidth: SparklineConsistency.listGlowLineWidth,
                    smoothSamplesPerSegment: smooth,
                    maxPlottedPoints: SparklineConsistency.listMaxPlottedPoints,
                    showBackground: false,
                    showExtremaDots: false,
                    neonTrail: false,
                    crispEnds: true,
                    horizontalInset: SparklineConsistency.listHorizontalInset,
                    compact: false,
                    seriesOrder: .oldestToNewest
                )
                .frame(width: width, height: 34)
                // Preserve trailing inset region so the end-dot/glow is not hard-clipped on device.
                .padding(.trailing, SparklineConsistency.listHorizontalInset)
                .clipped()
                .padding(.trailing, -SparklineConsistency.listHorizontalInset)
                .id(sparklineIdentity)
                .transaction { $0.disablesAnimations = true }
                .accessibilityHidden(true)
            } else {
                // Static placeholder when sparkline data is loading
                SparklineLoadingPlaceholder(width: width)
                    .frame(width: width, height: 34)
                    .accessibilityHidden(true)
            }
        }
    }

    // SPARKLINE FIX: Removed uiTick parameter - it was not used and caused unnecessary re-renders
    // MEMORY FIX v16: Replaced AnyView return with @ViewBuilder to eliminate heap allocation.
    @ViewBuilder
    private func rowContentInner(coin: MarketCoin, isStable: Bool, spark: [Double], isPositive7D: Bool, oneH: Double?, dayChange: Double?, isDragging: Bool, draggingID: String?) -> some View {
        // Precompute layout numbers to help the compiler type-check this view quickly.
        let dividerW: CGFloat = 1.0
        let metricsWidth: CGFloat = changeWidth1h + changeWidth24h + CGFloat(7)
        let totalMetricsArea: CGFloat = metricsWidth + CGFloat(9)
        let screenWidth: CGFloat = currentViewportWidth
        let cardHorizontalPadding: CGFloat = 52
        let rawSparkAvailable: CGFloat = screenWidth - cardHorizontalPadding - leadingInfoWidth - totalMetricsArea
        let sparkAvailable: CGFloat = max(rawSparkAvailable, sparkWidth)
        let sparkActualWidth: CGFloat = max(sparkWidth, sparkAvailable)
        let innerDivider: CGFloat = 1.0
        let metricsPref = WatchlistColumnMetrics(
            leadingWidth: leadingInfoWidth,
            sparkWidth: sparkActualWidth,
            percentWidth: changeWidth1h,
            percentSpacing: CGFloat(6),
            innerDividerW: innerDivider,
            outerDividerW: dividerW
        )
        let livePrice: Double = marketVM.bestPrice(for: coin.id)
            ?? coin.priceUsd
            ?? marketVM.bestPrice(forSymbol: coin.symbol)
            ?? initialLivePrices[coin.id]
            ?? 0

        HStack(spacing: 0) {
            RowLeadingInfo(
                active: (isDragging && draggingID == coin.id),
                symbol: coin.symbol,
                imageUrl: coin.imageUrl,
                price: livePrice,
                priceWidth: priceWidth,
                leadingInfoWidth: leadingInfoWidth,
                iconSize: coinIconSize
            )

            RowTrailingMetrics(
                spark: spark,
                isStable: isStable,
                isPositive7D: isPositive7D,
                oneH: oneH,
                dayChange: dayChange,
                sparkActualWidth: sparkActualWidth,
                metricsWidth: metricsWidth,
                dividerW: dividerW,
                innerDivider: innerDivider
            )
        }
        .background(Color.clear)
        .transaction { $0.animation = nil }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 42)
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .modifier(RemoveFavoriteSwipe(coinID: coin.id))
        .overlay(alignment: .bottom) { RowBottomDivider() }
        .background(MetricsPrefWriter(value: metricsPref))
    }

    private func startDragWatchdog() {
        dragWatchTimer?.invalidate()
        let t = Timer(timeInterval: 0.3, repeats: true) { _ in
            MainActor.assumeIsolated {
                if isDragging {
                    let gap = Date().timeIntervalSince(dragHeartbeat)
                    if gap > 1.0 {
                        // Hard reset if the system stops sending updates
                        forceClearDragVisuals()
                    }
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        dragWatchTimer = t
    }
    private func stopDragWatchdog() {
        dragWatchTimer?.invalidate()
        dragWatchTimer = nil
    }

    @MainActor private func forceClearDragVisuals() {
        // End drag immediately, but intentionally keep the ring visible for a short hold.
        stopDragWatchdog()
        isDragging = false
        draggingID = nil
        hoverTargetID = nil
        hoverInsertAfter = false
        animatePulse = false
        ringCooldownUntil = .distantFuture
        dragSessionID = nil
        // Keep current ringRowID and ringActive so the highlight remains.
        // Cancel any previous clear task and schedule a single, cancellable clear.
        ringClearTask?.cancel()
        let holdSeconds: Double = 0.5
        ringClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(holdSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.15)) {
                ringActive = false
            }
            // Clear the id shortly after the fade so the layout settles cleanly.
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            ringRowID = nil
        }
    }

    // MARK: - Empty Watchlist View
    private var emptyWatchlistView: some View {
        HStack(spacing: 10) {
            // Subtle gold-tinted star
            Image(systemName: "star")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(BrandGold.base.opacity(0.5))
            
            // Inline CTA text
            (Text("Tap ")
                .foregroundColor(.white.opacity(0.45))
            + Text("Browse Markets")
                .foregroundColor(BrandGold.base)
                .fontWeight(.medium)
            + Text(" to add coins")
                .foregroundColor(.white.opacity(0.45)))
            .font(.system(size: 13))
            
            // Subtle chevron hint
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(BrandGold.base.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                AppState.shared.selectedTab = .market
            }
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        }
    }

    private struct RowDataItem: Identifiable {
        let coin: MarketCoin
        let metrics: RowMetrics
        var id: String { coin.id }
    }
}

private struct WatchlistReorderDropDelegate: DropDelegate {
    let targetID: String
    @Binding var localOrder: [String]
    @Binding var draggingID: String?
    @Binding var shakeAttempts: Int
    @Binding var isDragging: Bool
    @Binding var listResetKey: UUID
    @Binding var dragHeartbeat: Date
    @Binding var hoverTargetID: String?
    @Binding var hoverInsertAfter: Bool
    @Binding var ringCooldownUntil: Date
    @Binding var ringActive: Bool
    @Binding var ringRowID: String?
    @Binding var dragSessionID: UUID? // Added session token binding
    let onReorder: ([String]) -> Void

    func dropEntered(info: DropInfo) {
        dragHeartbeat = Date()
        guard let from = draggingID else { return }
        guard targetID != from else { hoverTargetID = targetID; hoverInsertAfter = false; return }
        // Determine movement direction using current localOrder indices
        guard let fromIndexRaw = localOrder.firstIndex(of: from),
              let toIndexRaw = localOrder.firstIndex(of: targetID) else { return }
        let movingDown = fromIndexRaw < toIndexRaw
        var newOrder = localOrder
        newOrder.remove(at: fromIndexRaw)
        guard let targetIndexNow = newOrder.firstIndex(of: targetID) else { return }
        let insertIndex = movingDown ? min(targetIndexNow + 1, newOrder.count) : targetIndexNow
        if insertIndex <= newOrder.count {
            newOrder.insert(from, at: insertIndex)
            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                localOrder = newOrder
                hoverTargetID = targetID
                hoverInsertAfter = movingDown
            }
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        }
    }
    
    func dropExited(info: DropInfo) {
        hoverTargetID = nil
        hoverInsertAfter = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if isDragging {
            dragHeartbeat = Date()
            return DropProposal(operation: .move)
        } else {
            return DropProposal(operation: .cancel)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        dragHeartbeat = Date()
        guard draggingID != nil else {
            draggingID = nil
            isDragging = false
            hoverTargetID = nil
            hoverInsertAfter = false
            return false
        }
        onReorder(localOrder)
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        #endif
        draggingID = nil
        isDragging = false
        hoverTargetID = nil
        hoverInsertAfter = false
        return true
    }

    func dropEnded(info: DropInfo) {
        // Clear visuals immediately when drag ends anywhere
        draggingID = nil
        isDragging = false
        hoverTargetID = nil
        hoverInsertAfter = false
    }
}

private struct WatchlistEndDropDelegate: DropDelegate {
    @Binding var localOrder: [String]
    @Binding var draggingID: String?
    @Binding var isDragging: Bool
    @Binding var listResetKey: UUID
    @Binding var dragHeartbeat: Date
    @Binding var hoverTargetID: String?
    @Binding var hoverInsertAfter: Bool
    @Binding var ringCooldownUntil: Date
    @Binding var ringActive: Bool
    @Binding var ringRowID: String?
    @Binding var dragSessionID: UUID? // Added session token binding
    let onReorder: ([String]) -> Void
    
    func dropExited(info: DropInfo) {
        hoverTargetID = nil
        hoverInsertAfter = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if isDragging {
            dragHeartbeat = Date()
            return DropProposal(operation: .move)
        } else {
            return DropProposal(operation: .cancel)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        dragHeartbeat = Date()
        guard draggingID != nil else {
            hoverTargetID = nil
            hoverInsertAfter = false
            isDragging = false
            return false
        }
        onReorder(localOrder)
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        #endif
        draggingID = nil
        isDragging = false
        hoverTargetID = nil
        hoverInsertAfter = false
        return true
    }

    func dropEnded(info: DropInfo) {
        draggingID = nil
        isDragging = false
        hoverTargetID = nil
        hoverInsertAfter = false
    }
}

// MARK: - Sparkline Loading Placeholder
/// MEMORY FIX v16: Static placeholder — NO .repeatForever animation.
/// The previous animated shimmer used .repeatForever which causes SwiftUI to re-evaluate
/// the view body on every animation frame (60 FPS). Each evaluation allocates GeometryReader
/// closures, LinearGradients, and AnyView wrappers that accumulate ~8 MB/s.
/// When sparkline data never arrives (e.g., CoinGecko 401), these run FOREVER → OOM crash.
/// A static wave line is visually clean and costs zero ongoing memory.
private struct SparklineLoadingPlaceholder: View {
    let width: CGFloat
    
    var body: some View {
        WavePlaceholderShape()
            .stroke(Color.gray.opacity(0.18), lineWidth: 1.5)
    }
}

/// A wave-shaped path for the sparkline placeholder
private struct WavePlaceholderShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        let amplitude: CGFloat = 6  // Subtle wave height
        let frequency: CGFloat = 3  // Number of waves
        
        path.move(to: CGPoint(x: 0, y: midY))
        
        for x in stride(from: 0, through: rect.width, by: 2) {
            let relativeX = x / rect.width
            let y = midY + sin(relativeX * .pi * frequency) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
        }
        
        return path
    }
}