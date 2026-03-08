//
//  HomeView.swift
//  CryptoSage
//
//  Created by DM on 3/27/25.
//

import SwiftUI
import UIKit
import Combine
import os

// DARK MODE FIX: Use adaptive gold color from Design System instead of hardcoded value
private let CS_GOLD: Color = DS.Adaptive.gold

/// Shared placeholder container for images
struct PlaceholderImage<Content: View>: View {
    let content: () -> Content
    var body: some View {
        ZStack {
            // DARK MODE FIX: Use adaptive color for placeholder background
            Rectangle().fill(DS.Adaptive.chipBackground)
            content()
        }
        .frame(width: 120, height: 70)
        .cornerRadius(8)
        .clipped()
    }
}

/// MEMORY FIX: Defers heavy view body evaluation until the section scrolls into view.
/// When offscreen, renders a lightweight Color.clear placeholder of the given height.
/// On `onAppear` the real content is built and stays built (no onDisappear teardown).
/// MEMORY FIX v9: Removed `onDisappear { isVisible = false }` — that caused potential
/// layout oscillation: content height != placeholder height → LazyVStack recalculates →
/// view bounces in/out of viewport → rapid create/destroy loop → exponential memory growth.
struct VisibilityGatedView<Content: View>: View {
    let placeholderHeight: CGFloat
    @ViewBuilder let content: () -> Content
    @State private var isVisible = false

    var body: some View {
        if isVisible {
            content()
        } else {
            Color.clear
                .frame(height: placeholderHeight)
                .onAppear { isVisible = true }
        }
    }
}


// Rows-only body for the watchlist (no header)
private struct WatchlistBodyView: View {
    var sparklineCache: [String: [Double]] = [:]
    var livePrices: [String: Double] = [:]
    var refreshGeneration: Int = 0
    var onSelectCoinForDetail: (MarketCoin) -> Void = { _ in }
    
    var body: some View {
        WatchlistSection(
            onSelectCoinForDetail: onSelectCoinForDetail,
            initialSparklineCache: sparklineCache,
            initialLivePrices: livePrices,
            refreshGeneration: refreshGeneration
        )
    }
}

// New outer composite: PremiumGlassCard with integrated header + column labels + rows
private struct WatchlistComposite: View {
    @Environment(\.colorScheme) private var colorScheme
    // PERFORMANCE FIX v20: Removed @EnvironmentObject var marketVM: MarketViewModel
    // WatchlistComposite only used it to pass .environmentObject(marketVM) to AIPredictionSectionView,
    // but AIPredictionSectionView already receives it from the app-level environment chain.
    // This removal prevents MarketViewModel's 25+ @Published property changes from re-rendering
    // the entire WatchlistComposite (header, card, all coin rows) on every price update.
    
    let leadingWidth: CGFloat
    let sparkWidth: CGFloat
    let percentWidth: CGFloat
    let percentSpacing: CGFloat
    let innerDividerW: CGFloat
    let outerDividerW: CGFloat
    var sparklineCache: [String: [Double]] = [:]
    var livePrices: [String: Double] = [:]
    // WATCHLIST INSTANT-SYNC v2: Generation counter propagated from HomeView
    var refreshGeneration: Int = 0
    var onSelectCoinForDetail: (MarketCoin) -> Void = { _ in }
    
    @State private var hasAppeared = false
    
    // AI Prediction Section state - bindings from parent to render overlay at top level
    @Binding var showTimeframePopover: Bool
    @Binding var timeframeButtonFrame: CGRect
    @Binding var selectedTimeframe: PredictionTimeframe
    
    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        // Main content - no ZStack needed since overlay is rendered at HomeView level
        VStack(spacing: 12) {
            // Watchlist Card
            PremiumGlassCard(showGoldAccent: false, cornerRadius: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    // Integrated header with column labels
                    watchlistHeader
                    
                    // Coin rows (already have gold bars built in on each row)
                    WatchlistBodyView(
                        sparklineCache: sparklineCache,
                        livePrices: livePrices,
                        refreshGeneration: refreshGeneration,
                        onSelectCoinForDetail: onSelectCoinForDetail
                    )
                }
                // Tighten card insets so rows use more vertical space and reduce dead gaps.
                .padding(.top, 2)
                .padding(.bottom, 2)
                .padding(.horizontal, 6)
            }
            
            // AI Prediction Section - Inline (no sheet needed)
            // PERFORMANCE FIX v20: Removed explicit .environmentObject(marketVM) -
            // it's inherited from the app-level environment chain
            AIPredictionSectionView(
                showTimeframePopover: $showTimeframePopover,
                timeframeButtonFrame: $timeframeButtonFrame,
                selectedTimeframeBinding: $selectedTimeframe
            )
        }
        // No card-level gold bar - individual coin rows already have gold accents
        // Subtle appear animation
        .scaleEffect(hasAppeared ? 1.0 : 0.98)
        .opacity(hasAppeared ? 1.0 : 0.0)
        .onAppear {
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.35)) {
                    hasAppeared = true
                }
            }
        }
    }
    
    // MARK: - Integrated Header with Column Labels
    
    private var watchlistHeader: some View {
        // Safe fallback widths that match real WatchlistSection row layout constants.
        // leadingInfo = 3+4+24+6+88 = 125 (< 430pt screen), sparkMin = 140, change = 48
        let resolvedLeadingWidth = leadingWidth > 0 ? leadingWidth : 125
        let resolvedSparkWidth = sparkWidth > 0 ? sparkWidth : 140
        let resolvedPercentWidth = percentWidth > 0 ? percentWidth : 48
        let resolvedPercentSpacing = percentSpacing > 0 ? percentSpacing : 6
        let resolvedInnerDividerW = innerDividerW > 0 ? innerDividerW : 1
        let resolvedOuterDividerW = outerDividerW > 0 ? outerDividerW : 1
        let hasWatchlistItems = !FavoritesManager.shared.favoriteIDs.isEmpty

        return VStack(alignment: .leading, spacing: 1) {
            // Header row with icon and title - consistent with other sections
            HStack(alignment: .center, spacing: 8) {
                GoldHeaderGlyph(systemName: "eye.fill")
                Text("Watchlist")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Spacer()
            }
            
            // Column labels row:
            // keep visible with safe fallback widths so it never disappears during metrics resets.
            HStack(spacing: 0) {
                // Reserve space for the leading column (gold bar + icon + name/price)
                Spacer()
                    .frame(width: max(0, resolvedLeadingWidth))

                // 7D label centered over sparkline
                Text("7D")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.Adaptive.textSecondary.opacity(hasWatchlistItems ? 0.7 : 0.5))
                    .frame(width: max(0, resolvedSparkWidth), alignment: .center)

                // Spacer for divider area
                Spacer()
                    .frame(width: max(0, resolvedOuterDividerW + 8)) // divider + padding

                // 1H and 24H labels
                Text("1H")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.Adaptive.textSecondary.opacity(hasWatchlistItems ? 0.7 : 0.5))
                    .frame(width: max(0, resolvedPercentWidth), alignment: .trailing)
                
                Spacer()
                    .frame(width: max(0, resolvedPercentSpacing + resolvedInnerDividerW))
                
                Text("24H")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.Adaptive.textSecondary.opacity(hasWatchlistItems ? 0.7 : 0.5))
                    .frame(width: max(0, resolvedPercentWidth), alignment: .trailing)
            }
        }
        .padding(.bottom, 1)
    }
}

// MARK: - CoinCardView
struct CoinCardView: View {
    let coin: MarketCoin
    
    @State private var lastPrice: Double? = nil
    @State private var cachedChange24h: Double? = nil
    // PERFORMANCE FIX: Track last onChange time to prevent "tried to update multiple times per frame"
    @State private var lastOnChangeAt: Date = .distantPast

    var body: some View {
        VStack(spacing: 6) {
            coinIconView(for: coin, size: 32)

            Text(coin.symbol.uppercased())
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
                .lineLimit(1)

            // PERFORMANCE FIX: Use cached lastPrice instead of MarketViewModel.shared access in body
            // The singleton access was causing excessive SwiftUI dependency tracking and re-renders
            // lastPrice is populated in onAppear and updated in onChange
            if let priceValue = lastPrice ?? coin.priceUsd {
                Text(formatPrice(priceValue))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .lineLimit(1)
                    .monospacedDigit()
                    .tracking(-0.2)
                    .baselineOffset(1)
                    // PERFORMANCE FIX: GPU-accelerated numeric text transition
                    .contentTransition(.numericText(countsDown: false))
            } else {
                ShimmerBar(height: 14, cornerRadius: 3)
                    .frame(width: 60)
            }
            
            // CONSISTENCY FIX: Use cached value from LivePriceManager as single source of truth
            // This ensures the same 24h percentage is shown across Watchlist, Market, and Home views
            // Fallback to coin properties only when LivePriceManager hasn't indexed this coin yet
            let raw24: Double? = cachedChange24h ?? coin.unified24hPercent ?? coin.changePercent24Hr
            // CONSISTENCY FIX: Use same ±300% clamp as CoinRowView and WatchlistSection
            // SAFETY FIX: Avoid force unwrap by using safe optional binding
            let clamped24: Double = {
                guard let value = raw24, value.isFinite else { return 0 }
                return max(-300, min(300, value))
            }()
            let frac24: Double = clamped24 / 100.0
            let fmt24 = PercentDisplay.formatFraction(frac24)
            Text(fmt24.text)
                .font(.system(size: 12))
                .foregroundColor({
                    switch fmt24.trend {
                    case .positive: return .green
                    case .negative: return .red
                    case .neutral:  return DS.Adaptive.textSecondary
                    }
                }())
                .accessibilityLabel("24 hour change")
                .accessibilityValue(fmt24.accessibility)
        }
        .frame(width: 90, height: 120)
        .padding(6)
        .background(DS.Adaptive.cardBackground)
        .cornerRadius(10)
        .onAppear {
            // Defer state modification to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                // PRICE CONSISTENCY FIX: Use bestPrice() for consistent pricing
                if let p = MarketViewModel.shared.bestPrice(for: coin.id) ?? coin.priceUsd {
                    lastPrice = p
                }
                // Cache 24h change from LivePriceManager
                cachedChange24h = LivePriceManager.shared.bestChange24hPercent(for: coin)
            }
        }
        // PERFORMANCE FIX v19: Removed onChange(of: coin.priceUsd) entirely.
        // This was the source of "onChange(of: Double) tried to update multiple times per frame"
        // warnings during startup when all trending coins' prices load simultaneously.
        // HomeCoinCards are static display cards in a horizontal scroll - they don't need
        // real-time price updates. The onAppear snapshot is sufficient.
    }

    @ViewBuilder
    private func coinIconView(for coin: MarketCoin, size: CGFloat) -> some View {
        if let rawURL = coin.iconUrl {
            let url = upgradeToHTTPS(rawURL)
            CachingAsyncImage(url: url, referer: nil)
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(
                    Circle().stroke(DS.Adaptive.stroke, lineWidth: 1)
                )
        } else {
            Circle()
                // DARK MODE FIX: Use adaptive color for placeholder
                .fill(DS.Adaptive.chipBackground)
                .frame(width: size, height: size)
        }
    }

    private func formatPrice(_ value: Double) -> String {
        return MarketFormat.price(value)
    }
}

// MARK: - HomeView
struct HomeView: View {
    enum PortfolioRange: String, CaseIterable, Hashable {
        case day = "1D"
        case week = "1W"
        case month = "1M"
        case year = "1Y"
        case all = "ALL"

        var days: Int {
            switch self {
            case .day: return 1
            case .week: return 7
            case .month: return 30
            case .year: return 365
            case .all: return Int.max
            }
        }
    }

    @EnvironmentObject var vm: HomeViewModel
    // PERFORMANCE FIX v20: Removed @EnvironmentObject var appState: AppState
    // ROOT CAUSE OF HOME PAGE SCROLL JANK:
    // AppState has 18+ @Published properties (selectedTab, isKeyboardVisible, 5 nav paths,
    // dismissHomeSubviews, pendingTradeConfig, etc.). Every change to ANY of them fires
    // objectWillChange and forces HomeView.body to re-evaluate the entire LazyVStack
    // with 15+ sections. HomeView only needs appState.dismissHomeSubviews (in an onChange,
    // not even in body), so we use a Notification-based approach instead.
    // This is THE reason the Market page scrolls fine but the Home page doesn't -
    // Market doesn't observe AppState at its top level.
    @Binding var selectedTab: CustomTab
    @EnvironmentObject var chatVM: ChatViewModel  // Only 2 @Published (inputText, messages) - low impact

    // PERFORMANCE FIX v19: Removed @StateObject for NotificationsManager.
    // It has 5+ @Published properties that fire whenever alerts are evaluated,
    // causing HomeView body to re-evaluate even though we only need the badge count.
    // Use a @State snapshot updated via onReceive instead.
    @State private var hasPendingNotificationsCached: Bool = false
    // PERFORMANCE FIX v19: Removed @EnvironmentObject for MarketViewModel and CryptoNewsFeedViewModel.
    // These had 25+ and 15+ @Published properties respectively, causing HomeView's entire body
    // to re-evaluate on EVERY property change (allCoins, coins, filteredCoins, articles, etc.)
    // even though HomeView only uses marketVM.watchlistCoins and newsVM.isLoading.
    // Child views (WatchlistSection, etc.) still receive them via the environment chain.
    // HomeView now accesses them via singletons to avoid observing all their publishers.
    // PERFORMANCE FIX v22: EventsViewModel moved to EventsSectionWrapper (below)
    // Previously owned by HomeView, its 4 @Published properties caused full body re-evaluation
    // even when the events section was off-screen.
    // PERFORMANCE FIX v20: Removed @ObservedObject private var demoModeManager = DemoModeManager.shared
    // It was declared but NEVER referenced in HomeView's body, yet caused re-renders on every
    // DemoModeManager change.
    
    // MARK: - State Properties (organized by category)
    // PERFORMANCE NOTE: States are organized into logical groups with comments.
    // SwiftUI batches updates to @State properties declared nearby.
    // Further consolidation into structs would break $ bindings used by sheets/navigation.
    
    // === PERFORMANCE FIX v22: CACHED SINGLETON SNAPSHOTS ===
    // Reading @Published properties from singletons inside body creates hidden SwiftUI observation
    // dependencies that re-evaluate the entire HomeView body (16+ sections) on every change.
    // These @State snapshots are updated via debounced onReceive handlers instead.
    // MEMORY FIX: Previously initialized with MarketViewModel.shared.allCoins which:
    // 1. Triggered MarketViewModel.shared init if not yet created (cascading heavy work)
    // 2. Copied the entire 250+ coin array into @State during view construction
    // 3. This happened synchronously during app init, adding to memory pressure
    // Now starts empty - populated via onReceive debounced handler when data arrives.
    @State private var cachedTrendingCoins: [MarketCoin] = []
    @State private var cachedNewsIsLoading: Bool = false
    /// FIX v23: Track whether trending coins have been populated at least once.
    /// The first population must bypass the scroll guard to prevent an empty trending section
    /// if the user scrolls during the initial 3-second debounce window.
    @State private var hasTrendingBeenPopulated: Bool = false
    
    // === NAVIGATION / SHEET STATES ===
    // These use $ bindings for .sheet/.fullScreenCover so must remain individual @State
    @State private var showSettings = false
    @State private var showNotifications = false
    @State private var showAllEvents = false
    /// FIX v5.0.3: Moved from PortfolioSectionView to HomeView level so the
    /// navigationDestination is outside the LazyVStack (fixes SwiftUI warning).
    @State private var showAllAIInsights = false
    /// Coin detail navigation for Trending section. Hosted at HomeView level (outside LazyVStack).
    @State private var selectedTrendingCoin: MarketCoin? = nil
    /// Coin detail navigation for Watchlist section. Hosted at HomeView level (outside LazyVStack).
    @State private var selectedWatchlistCoin: MarketCoin? = nil
    /// Stock detail/navigation states hosted at HomeView level (outside LazyVStack).
    @State private var selectedMarketStock: CachedStock? = nil
    @State private var showStockMarketView: Bool = false
    /// Commodity detail/navigation states hosted at HomeView level (outside LazyVStack).
    @State private var selectedCommodityHolding: Holding? = nil
    @State private var selectedMarketCommodity: CachedStock? = nil
    @State private var selectedLiveCommodity: CommodityInfo? = nil
    @State private var showCommoditiesMarketView: Bool = false
    /// Whale full view navigation hosted at HomeView level (outside LazyVStack).
    @State var showWhaleActivityFullView: Bool = false
    // showBreakdownSheet and showChangeAsAmount removed — no longer used
    @State private var showSocialTab: Bool = false
    @State private var socialTabInitialSection: SocialTabView.SocialSection = .leaderboard
    
    // === RISK SCAN STATES ===
    // PERFORMANCE FIX: Consolidated 5 individual @State properties into a single struct
    // to reduce SwiftUI tracking overhead. These states change together during scan lifecycle.
    struct RiskScanState {
        var result: RiskScanResult? = nil
        var isScanning: Bool = false
        var showReport: Bool = false
        var lastScanAt: Date? = nil
        var showOverlay: Bool = false
    }
    @State private var riskScan = RiskScanState()
    
    // === PRICE ANIMATION STATES ===
    @State private var stabilizedIsUp: Bool = true
    
    // === SCROLL / POSITION STATES ===
    @State private var lastSeenArticleID: String?
    
    // === DATA / DISPLAY STATES ===
    @State private var selectedRange: PortfolioRange = .month
    
    // === TIMEFRAME PICKER OVERLAY STATE ===
    @State private var showTimeframePicker: Bool = false
    @State private var timeframePickerAnchor: CGRect = .zero
    
    // === SENTIMENT SOURCE PICKER OVERLAY STATE ===
    // Observed via onReceive so the overlay renders above the ScrollView (avoids clipping)
    @State private var sentimentSourcePickerVisible: Bool = false
    
    // === AI PREDICTION TIMEFRAME PICKER STATE (managed at HomeView level for proper overlay) ===
    // PERFORMANCE FIX: Consolidated 3 @State properties into a single struct
    struct PredictionPickerState {
        var showPicker: Bool = false
        var buttonFrame: CGRect = .zero
        var selectedTimeframe: PredictionTimeframe = .day
    }
    @State private var predictionPicker = PredictionPickerState()
    // PERSIST: Remember user's selected timeframe between app sessions
    @AppStorage("AIPrediction.SelectedTimeframe") private var persistedTimeframeRaw: String = "1d"
    
    // === LOAD TRACKING STATES ===
    @State private var isInitialLoadComplete: Bool = false

    // === COLUMN METRICS STATES ===
    // PERFORMANCE FIX: Use the existing WatchlistColumnMetrics from WatchlistSection
    // instead of 6 separate @State properties. Default values approximate actual row metrics.
    @State private var wlMetrics = WatchlistColumnMetrics(
        leadingWidth: 125,   // 3+4+24+6+88 (gold bar + spacing + icon + spacing + text)
        sparkWidth: 105,     // Reduced from 140 to fit iPhone 17 Pro screens (393pt width)
        percentWidth: 48,    // Matches changeWidth1h/changeWidth24h
        percentSpacing: 6,   // Matches row HStack spacing
        innerDividerW: 1.0,  // Matches innerDivider in rows
        outerDividerW: 1.0   // Matches dividerW in rows
    )
    
    // Convenience accessors for backwards compatibility (avoids changing all usage sites)
    private var wlLeadingWidth: CGFloat { wlMetrics.leadingWidth }
    private var wlSparkWidth: CGFloat { wlMetrics.sparkWidth }
    private var wlPercentWidth: CGFloat { wlMetrics.percentWidth }
    private var wlPercentSpacing: CGFloat { wlMetrics.percentSpacing }
    private var wlInnerDividerW: CGFloat { wlMetrics.innerDividerW }
    private var wlOuterDividerW: CGFloat { wlMetrics.outerDividerW }
    
    // === WATCHLIST PERFORMANCE CACHES ===
    // PERFORMANCE FIX: Consolidated into struct to reduce @State property count
    struct HomeWatchlistCache: Equatable {
        var sparklines: [String: [Double]] = [:]  // Pre-loaded sparkline cache
        var livePrices: [String: Double] = [:]    // Centralized live prices
    }
    @State private var watchlistCache = HomeWatchlistCache()
    
    // Convenience accessors for backwards compatibility
    private var watchlistSparklineCache: [String: [Double]] { watchlistCache.sparklines }
    private var watchlistLivePrices: [String: Double] { watchlistCache.livePrices }
    
    // === SECTION VISIBILITY CACHE ===
    // PERFORMANCE FIX: Cache section visibility in @State instead of computed property
    // This avoids recomputing HomeSectionsLayout.visibleSections() (which reads UserDefaults)
    // on every body evaluation. Updated on appear and when watchlist changes.
    @State private var cachedHomeSections: [HomeSection] = []
    
    // Phased section loading to avoid rendering all sections simultaneously.
    // Phase 1 (immediate): +watchlist.
    // Phase 2 (+3s): +news.
    // Phase 3 (+30s): all remaining sections (delayed to let data pipeline populate).
    @State private var sectionLoadingPhase: Int = 0
    @AppStorage("StartupSafeModeEnabled") private var startupSafeModeEnabled: Bool = false
    
    // WATCHLIST INSTANT-SYNC FIX: Track pending section refresh when scroll guard blocks an update.
    // Without this, onReceive handlers silently drop watchlist updates during scroll with no retry,
    // causing newly favorited coins to not appear until a background event triggers recomputation.
    @State private var hasPendingWatchlistSectionUpdate: Bool = false
    
    // WATCHLIST INSTANT-SYNC v2: Generation counter incremented when favorites change.
    // Passed to WatchlistComposite so that even if the WatchlistSection was destroyed by
    // LazyVStack (losing its Combine subscriptions), the new value triggers a refresh
    // via .onChange when the view is recreated. HomeView is always in the hierarchy
    // (not inside a lazy container), so it always receives the notification.
    @State private var watchlistRefreshGeneration: Int = 0
    
    // APP LIFECYCLE: Track scene phase to refresh layout when returning from background
    // This prevents the "blank area" bug where LazyVStack doesn't re-render after backgrounding
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("hideBalances") private var hideBalances: Bool = false
    
    // HOME SECTION TOGGLES: Observe EVERY section visibility preference used by
    // HomeSectionPreferences so .onChange(of: sectionToggleFingerprint) fires immediately
    // when the user changes any toggle — bypassing the scroll-guarded didChangeNotification.
    @AppStorage("Home.showPortfolio")           private var secShowPortfolio: Bool = true
    @AppStorage("showStocksInPortfolio")        private var secShowStocksEnabled: Bool = false
    @AppStorage("Home.showStocksOverview")      private var secShowStocksOverview: Bool = true
    @AppStorage("Home.showStockWatchlist")      private var secShowStockWatchlist: Bool = true
    @AppStorage("Home.showWatchlist")           private var secShowWatchlist: Bool = true
    @AppStorage("Home.showMarketStats")         private var secShowMarketStats: Bool = false
    @AppStorage("Home.showSentiment")           private var secShowSentiment: Bool = true
    @AppStorage("Home.showHeatmap")             private var secShowHeatmap: Bool = true
    @AppStorage("Home.showTrending")            private var secShowTrending: Bool = true
    @AppStorage("Home.showArbitrage")           private var secShowArbitrage: Bool = true
    @AppStorage("Home.showWhaleActivity")       private var secShowWhaleActivity: Bool = true
    @AppStorage("Home.showEvents")              private var secShowEvents: Bool = true
    @AppStorage("Home.showNews")                private var secShowNews: Bool = true
    @AppStorage("Home.showAIInsights")          private var secShowAIInsights: Bool = true
    @AppStorage("Home.showAIPredictions")       private var secShowAIPredictions: Bool = true
    @AppStorage("Home.showCommoditiesOverview") private var secShowCommodities: Bool = true
    @AppStorage("Home.showPromos")              private var secShowPromos: Bool = true
    @AppStorage("Home.showTransactions")        private var secShowTransactions: Bool = true
    @AppStorage("Home.showCommunity")           private var secShowCommunity: Bool = true
    @AppStorage("Home.showAgentTrading")        private var secShowAgentTrading: Bool = true

    // SECTION ORDER: Track version bumps from drag-and-drop reordering in HomeCustomizationView
    @AppStorage("Home.sectionOrderVersion")    private var sectionOrderVersion: Int = 0

    // PERFORMANCE FIX v19: Use cached badge state instead of computed property
    // The old computed property read notificationsManager.untriggeredAlertsCount which accessed
    // @Published arrays, causing SwiftUI to track the dependency and re-render on every change.
    private var hasPendingNotifications: Bool {
        hasPendingNotificationsCached
    }

    var body: some View {
        ZStack {
            DS.Adaptive.background.ignoresSafeArea()
            ScrollView(.vertical, showsIndicators: false) {
                homeContentStack
                    .frame(maxWidth: .infinity)
                    // PERFORMANCE FIX v21: Removed .trackScrolling() GeometryReader.
                    // Scroll tracking now handled by UIKit KVO bridge (zero SwiftUI layout overhead).
                    // GeometryReader was computing frames during every scroll event,
                    // adding work to SwiftUI's layout pass. The KVO bridge observes
                    // UIScrollView.contentOffset at the UIKit layer instead.
            }
            // PERFORMANCE FIX v21: UIKit scroll bridge replaces GeometryReader + coordinateSpace.
            // This bridges into the real UIScrollView underneath and applies:
            // - Deceleration rate 0.994 (snappier than default 0.998, Coinbase-like)
            // - KVO-based scroll tracking (zero SwiftUI overhead)
            .withUIKitScrollBridge()
            // UX: Dismiss keyboard when scrolling (matches Market and AI Chat pages)
            .scrollDismissesKeyboard(.interactively)
            
            // Full-screen scanning overlay
            if riskScan.showOverlay {
                ScanningOverlayView(scanResult: riskScan.result)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(100)
            }
            
            // Timeframe picker overlay (rendered at top level to avoid clipping)
            // CONSISTENCY: Uses shared CSAnchoredGridMenu for professional UX (press states, selection confirmation)
            if showTimeframePicker {
                CSAnchoredGridMenu(
                    isPresented: $showTimeframePicker,
                    anchorRect: timeframePickerAnchor,
                    items: PortfolioRange.allCases,
                    selectedItem: selectedRange,
                    titleForItem: { $0.rawValue },
                    onSelect: { selectedRange = $0 },
                    columns: 3,
                    preferredWidth: 200,
                    edgePadding: 16,
                    title: "Timeframe"
                )
                .zIndex(99)
            }
            
            // AI Prediction timeframe picker overlay (rendered at top level to prevent scroll movement)
            if predictionPicker.showPicker {
                CSAnchoredGridMenu(
                    isPresented: $predictionPicker.showPicker,
                    anchorRect: predictionPicker.buttonFrame,
                    items: PredictionTimeframe.allCases,
                    selectedItem: predictionPicker.selectedTimeframe,
                    titleForItem: { $0.displayName },
                    onSelect: { newTimeframe in
                        predictionPicker.selectedTimeframe = newTimeframe
                        // Persist the selection for next app launch
                        persistedTimeframeRaw = newTimeframe.rawValue
                    },
                    columns: 3,
                    preferredWidth: 200,
                    edgePadding: 16,
                    title: "Prediction Timeframe"
                )
                .zIndex(98)
            }
            
            // Sentiment source picker overlay (rendered at top level to avoid ScrollView clipping)
            if sentimentSourcePickerVisible {
                let sentimentVM = ExtendedFearGreedViewModel.shared
                SourcePickerPopover(
                    isPresented: Binding(
                        get: { sentimentVM.showSourcePicker },
                        set: { sentimentVM.showSourcePicker = $0 }
                    ),
                    selected: sentimentVM.selectedSource,
                    anchorRect: sentimentVM.sourcePickerAnchorFrame
                ) { src in
                    sentimentVM.selectedSource = src
                    Task { await sentimentVM.fetchData() }
                }
                .ignoresSafeArea()
                .zIndex(101)
            }
            
        }
        .withBannerAd() // Show ads for free tier users
        .animation(.easeInOut(duration: 0.3), value: riskScan.showOverlay)
        .animation(.easeInOut(duration: 0.2), value: showTimeframePicker)
        .animation(.easeInOut(duration: 0.2), value: predictionPicker.showPicker)
        .animation(.easeInOut(duration: 0.2), value: sentimentSourcePickerVisible)
        // Sync sentiment source picker state from shared ViewModel
        .onReceive(ExtendedFearGreedViewModel.shared.$showSourcePicker) { show in
            if sentimentSourcePickerVisible != show {
                sentimentSourcePickerVisible = show
            }
        }
        // SYNC: Restore persisted prediction timeframe synchronously on appear
        // This ensures child views (AIPredictionCard) see the correct timeframe immediately
        .onAppear {
            // MEMORY FIX v6: Defer state mutations to avoid "Modifying state during view update".
            // Synchronous @State mutations in onAppear fire during SwiftUI body evaluation,
            // producing warnings and contributing to cascading re-renders.
            Task { @MainActor in
                if let restoredTimeframe = PredictionTimeframe(rawValue: persistedTimeframeRaw) {
                    predictionPicker.selectedTimeframe = restoredTimeframe
                }
                // PERFORMANCE FIX v19: Snapshot notification badge on appear
                hasPendingNotificationsCached = NotificationsManager.shared.untriggeredAlertsCount > 0
            }
        }
        // PERFORMANCE FIX v19: Update notification badge with debounce to avoid frequent re-renders
        // Only triggers HomeView re-render when the badge state actually changes (true <-> false)
        .onReceive(NotificationsManager.shared.objectWillChange.debounce(for: .seconds(2), scheduler: DispatchQueue.main)) { _ in
            let newValue = NotificationsManager.shared.untriggeredAlertsCount > 0
            if newValue != hasPendingNotificationsCached {
                hasPendingNotificationsCached = newValue
            }
        }
        // Navigation destinations placed here (outside LazyVStack) to fix SwiftUI warning
        .navigationDestination(isPresented: $showNotifications) {
            NotificationsView()
        }
        .navigationDestination(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(vm.portfolioVM)
        }
        // FIX v23: AllEventsView navigation restored to HomeView level.
        // Previously in EventsSectionWrapper inside LazyVStack — .navigationDestination
        // inside a lazy container is unreliable: if the events section scrolls off-screen,
        // SwiftUI may destroy the destination modifier and navigation breaks.
        .navigationDestination(isPresented: $showAllEvents) {
            StandaloneAllEventsView()
        }
        // FIX v5.0.3: AllAIInsightsView navigation moved from PortfolioSectionView (inside
        // LazyVStack) to HomeView level. Placing .navigationDestination inside a lazy container
        // causes SwiftUI to warn and will be ignored in a future release.
        .navigationDestination(isPresented: $showAllAIInsights) {
            AllAIInsightsView()
        }
        .navigationDestination(item: $selectedTrendingCoin) { coin in
            CoinDetailView(coin: coin)
        }
        .navigationDestination(item: $selectedWatchlistCoin) { coin in
            CoinDetailView(coin: coin)
        }
        .navigationDestination(isPresented: Binding(
            get: { selectedMarketStock != nil },
            set: { if !$0 { selectedMarketStock = nil } }
        )) {
            if let stock = selectedMarketStock {
                StockDetailView(
                    ticker: stock.symbol,
                    companyName: stock.name,
                    assetType: stock.assetType,
                    holding: nil
                )
            }
        }
        .navigationDestination(isPresented: $showStockMarketView) {
            StockMarketView()
                .environmentObject(vm.portfolioVM)
        }
        .navigationDestination(isPresented: Binding(
            get: { selectedCommodityHolding != nil },
            set: { if !$0 { selectedCommodityHolding = nil } }
        )) {
            if let commodity = selectedCommodityHolding {
                if let info = CommoditySymbolMapper.getCommodity(for: commodity.coinSymbol) {
                    CommodityDetailView(commodityInfo: info, holding: commodity)
                        .environmentObject(vm.portfolioVM)
                } else {
                    StockDetailView(
                        ticker: commodity.displaySymbol,
                        companyName: commodity.displayName,
                        assetType: .commodity,
                        holding: commodity
                    )
                }
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { selectedMarketCommodity != nil },
            set: { if !$0 { selectedMarketCommodity = nil } }
        )) {
            if let commodity = selectedMarketCommodity {
                if let info = CommoditySymbolMapper.getCommodity(for: commodity.symbol) {
                    CommodityDetailView(commodityInfo: info, holding: nil)
                        .environmentObject(vm.portfolioVM)
                } else {
                    StockDetailView(
                        ticker: commodity.symbol,
                        companyName: commodity.name,
                        assetType: .commodity,
                        holding: nil
                    )
                }
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { selectedLiveCommodity != nil },
            set: { if !$0 { selectedLiveCommodity = nil } }
        )) {
            if let commodityInfo = selectedLiveCommodity {
                CommodityDetailView(commodityInfo: commodityInfo, holding: nil)
                    .environmentObject(vm.portfolioVM)
            }
        }
        .navigationDestination(isPresented: $showCommoditiesMarketView) {
            CommoditiesMarketView()
                .environmentObject(vm.portfolioVM)
        }
        .navigationDestination(isPresented: $showWhaleActivityFullView) {
            WhaleActivityView(showCloseButton: false)
                .navigationBarHidden(true)
        }
        .fullScreenCover(isPresented: $showSocialTab) {
            SocialTabView(initialSection: socialTabInitialSection, onDismiss: { showSocialTab = false })
        }
        // NAVIGATION FIX: Dismiss all subviews when Home tab is tapped (pop-to-root)
        // PERFORMANCE FIX v20: Use targeted onReceive on just the $dismissHomeSubviews publisher
        // instead of @EnvironmentObject var appState: AppState which observes ALL 18+ @Published.
        // This was THE ROOT CAUSE of home page scroll jank - every AppState change
        // (tab switches, keyboard visibility, nav path changes) forced a full body re-evaluation.
        .onReceive(AppState.shared.$dismissHomeSubviews) { shouldDismiss in
            if shouldDismiss {
                // Dismiss all navigation destinations
                showSettings = false
                showNotifications = false
                showAllEvents = false
                showAllAIInsights = false
                selectedTrendingCoin = nil
                selectedWatchlistCoin = nil
                selectedMarketStock = nil
                showStockMarketView = false
                selectedCommodityHolding = nil
                selectedMarketCommodity = nil
                selectedLiveCommodity = nil
                showCommoditiesMarketView = false
                showWhaleActivityFullView = false
                showSocialTab = false
                riskScan.showReport = false
                
                // Reset the trigger after handling
                DispatchQueue.main.async {
                    AppState.shared.dismissHomeSubviews = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSocialTab)) { notification in
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                // Parse the target section from notification object
                if let sectionString = notification.object as? String {
                    switch sectionString {
                    case "feed":
                        socialTabInitialSection = .feed
                    case "leaderboard":
                        socialTabInitialSection = .leaderboard
                    case "discover":
                        socialTabInitialSection = .discover
                    default:
                        socialTabInitialSection = .leaderboard
                    }
                } else {
                    socialTabInitialSection = .leaderboard
                }
                showSocialTab = true
            }
        }
        // Keep Home layout recoverable: do not force persistent section stripping.
        .onReceive(NotificationCenter.default.publisher(for: .memoryEmergencySectionsStrip)) { _ in
            Task { @MainActor in
                // Recompute with current phase but keep normal section progression intact.
                cachedHomeSections = computeHomeSections()
                #if DEBUG
                print("⚠️ [HomeView] Memory emergency signal received — keeping normal section pipeline")
                #endif
            }
        }
        .task {
            // PERFORMANCE FIX: Skip heavy work if already initialized (tab switch)
            // This prevents redundant disk I/O and computation on every tab switch
            guard !isInitialLoadComplete else { return }
            
            // PERFORMANCE: Defer heavy loading work to allow UI to render first
            // This prevents freezing on app launch by letting the main thread breathe
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms initial delay for UI to render
            
            // PERFORMANCE FIX: Compute sections once on appear (not in computed property)
            // This avoids repeated UserDefaults reads during view body evaluation
            await MainActor.run {
                if cachedHomeSections.isEmpty {
                    cachedHomeSections = computeHomeSections()
                }
                // NOTE: Prediction timeframe is restored synchronously in .onAppear (above)
                // to ensure it's set before child views initialize
            }

            // Phased loading — keep first paint fast, but avoid "late section pop-in".
            // Phase 1 (immediate): +watchlist
            // Phase 2 (+200ms): +news +commodities +trending +sentiment
            // Phase 3 (+700ms total): all remaining sections
            Task {
                // Phase 1: immediate — show watchlist right away
                await MainActor.run {
                    if sectionLoadingPhase < 1 {
                        sectionLoadingPhase = 1
                        cachedHomeSections = computeHomeSections()
                        #if DEBUG
                        print("📐 [HomeView] Phase 1: +watchlist — \(currentMemoryMB()) MB")
                        #endif
                    }
                }

                // PERFORMANCE FIX: Load Phase 1 data progressively
                await vm.loadDataProgressively(phase: 1)

                #if targetEnvironment(simulator)
                if AppSettings.isSimulatorLimitedDataMode {
                    // Professional simulator startup: reveal nearly full layout immediately.
                    try? await Task.sleep(nanoseconds: 80_000_000)
                    await MainActor.run {
                        if sectionLoadingPhase < 2 {
                            withAnimation(.easeOut(duration: 0.22)) {
                                sectionLoadingPhase = 2
                                cachedHomeSections = computeHomeSections()
                            }
                            #if DEBUG
                            print("📐 [HomeView] Phase 2 (simulator limited): +news +commodities +movers +sentiment — \(currentMemoryMB()) MB")
                            #endif
                        }
                    }
                    // Load Phase 2 data
                    await vm.loadDataProgressively(phase: 2)

                    try? await Task.sleep(nanoseconds: 120_000_000)
                    await MainActor.run {
                        if sectionLoadingPhase < 3 {
                            withAnimation(.easeOut(duration: 0.22)) {
                                sectionLoadingPhase = 3
                                cachedHomeSections = computeHomeSections()
                            }
                            #if DEBUG
                            print("📐 [HomeView] Phase 3 (simulator limited-lite): most sections — \(currentMemoryMB()) MB")
                            let visible = cachedHomeSections.map(\.rawValue).joined(separator: ",")
                            print("🧪 [HomeView] Simulator Phase 3-lite sections (\(cachedHomeSections.count)): \(visible)")
                            #endif
                        }
                    }

                    // Load Phase 3 data for simulator
                    await vm.loadDataProgressively(phase: 3)
                    #if DEBUG
                    print("🧪 [HomeView] Simulator limited profile: Phase 3-lite enabled")
                    #endif
                } else {
                    // Simulator full mode: same progressive loading as real device
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    await MainActor.run {
                        if sectionLoadingPhase < 2 {
                            withAnimation(.easeOut(duration: 0.18)) {
                                sectionLoadingPhase = 2
                                cachedHomeSections = computeHomeSections()
                            }
                            #if DEBUG
                            print("📐 [HomeView] Phase 2: +news +commodities +trending +sentiment — \(currentMemoryMB()) MB")
                            #endif
                        }
                    }
                    await vm.loadDataProgressively(phase: 2)
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    await MainActor.run {
                        if sectionLoadingPhase < 3 {
                            withAnimation(.easeOut(duration: 0.18)) {
                                sectionLoadingPhase = 3
                                cachedHomeSections = computeHomeSections()
                            }
                            #if DEBUG
                            print("📐 [HomeView] Phase 3: Full layout complete — \(currentMemoryMB()) MB")
                            #endif
                        }
                    }
                    await vm.loadDataProgressively(phase: 3)
                }
                #else
                // Real device: progressive loading to prevent UI blocking
                // PERFORMANCE FIX: Don't jump to Phase 3 immediately - this causes all 16+ sections
                // to load data simultaneously, creating network congestion and main thread blocking

                // Phase 2: Add core content sections
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
                await MainActor.run {
                    if sectionLoadingPhase < 2 {
                        withAnimation(.easeOut(duration: 0.18)) {
                            sectionLoadingPhase = 2
                            cachedHomeSections = computeHomeSections()
                        }
                        #if DEBUG
                        print("📐 [HomeView] Phase 2: +news +commodities +trending +sentiment — \(currentMemoryMB()) MB")
                        #endif
                    }
                }

                // PERFORMANCE FIX: Load Phase 2 data progressively
                await vm.loadDataProgressively(phase: 2)

                // Phase 3: Add remaining heavy sections with proper spacing
                try? await Task.sleep(nanoseconds: 500_000_000) // +500ms more (700ms total)
                await MainActor.run {
                    if sectionLoadingPhase < 3 {
                        withAnimation(.easeOut(duration: 0.18)) {
                            sectionLoadingPhase = 3
                            cachedHomeSections = computeHomeSections()
                        }
                        #if DEBUG
                        print("📐 [HomeView] Phase 3: Full layout complete — \(currentMemoryMB()) MB")
                        #endif
                    }
                }

                // PERFORMANCE FIX: Load Phase 3 data progressively
                await vm.loadDataProgressively(phase: 3)
                #endif
            }
            
            // Pre-load watchlist sparklines after initial shell is visible.
            let persisted = await WatchlistSparklineService.shared.getAllCachedSparklines()
            if !persisted.isEmpty {
                await MainActor.run {
                    watchlistCache.sparklines = persisted
                    isInitialLoadComplete = true
                }
            } else {
                await MainActor.run {
                    isInitialLoadComplete = true
                }
            }
        }
        // Safe mode is permanently disabled — no onChange handler needed
        // PERFORMANCE FIX: Update cached sections when watchlist changes
        // This is rare (user adds/removes favorites) so the overhead is minimal
        // SCROLL FIX: Skip during scroll to prevent scroll position reset
        // WATCHLIST INSTANT-SYNC: Reduced debounce from 500ms to 100ms so the watchlist
        // section appears/disappears promptly when the user adds their first favorite
        // or removes their last one. computeHomeSections() is very lightweight.
        // WATCHLIST INSTANT-SYNC FIX: Queue a pending update instead of silently dropping
        // when scroll guard blocks. The pending update is drained when scrolling ends.
        .onReceive(MarketViewModel.shared.$watchlistCoins.debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)) { _ in
            // Prevent section updates during scroll - this can reset scroll position
            guard !ScrollStateManager.shared.isScrolling else {
                hasPendingWatchlistSectionUpdate = true
                return
            }
            let newSections = computeHomeSections()
            if newSections != cachedHomeSections {
                cachedHomeSections = newSections
            }
        }
        // WATCHLIST INSTANT-SYNC: Also observe FavoritesManager directly so section
        // visibility updates immediately when the user adds/removes a favorite,
        // without waiting for MarketViewModel's watchlistCoins to propagate.
        // WATCHLIST INSTANT-SYNC FIX: Removed scroll guard — computeHomeSections() is
        // very lightweight (reads a few bools + set count), and favoriting is an explicit
        // user action that must give immediate visual feedback. The scroll guard was causing
        // newly favorited coins to never appear on the watchlist until a background event
        // triggered recomputation, sometimes taking minutes.
        .onReceive(FavoritesManager.shared.$favoriteIDs.removeDuplicates()) { _ in
            let newSections = computeHomeSections()
            if newSections != cachedHomeSections {
                cachedHomeSections = newSections
            }
        }
        // WATCHLIST INSTANT-SYNC v2: Listen for favorites changes via NotificationCenter.
        // This is the most reliable path because HomeView is always in the hierarchy
        // (unlike WatchlistSection which can be destroyed by LazyVStack). Incrementing
        // the generation counter forces a re-render of the WatchlistComposite section,
        // which in turn triggers WatchlistSection's .onAppear to refresh its data.
        .onReceive(NotificationCenter.default.publisher(for: .favoritesDidChange)
            .receive(on: DispatchQueue.main)
        ) { _ in
            watchlistRefreshGeneration += 1
        }
        // WATCHLIST INSTANT-SYNC FIX: Drain pending watchlist section updates when scroll ends.
        // This ensures updates that were blocked by the scroll guard in the watchlistCoins
        // handler are replayed once scrolling stops, preventing permanently lost updates.
        .onReceive(ScrollStateManager.shared.$isScrolling.removeDuplicates()) { isScrolling in
            if !isScrolling && hasPendingWatchlistSectionUpdate {
                hasPendingWatchlistSectionUpdate = false
                let newSections = computeHomeSections()
                if newSections != cachedHomeSections {
                    cachedHomeSections = newSections
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).debounce(for: .seconds(2), scheduler: DispatchQueue.main)) { _ in
            // PERFORMANCE FIX v17: Skip during scroll - UserDefaults notifications fire frequently
            // from background services writing caches, which triggers computeHomeSections() during scroll
            // Section visibility toggles only change when user is in Settings (not scrolling home)
            // MEMORY FIX v8: Increased debounce from 300ms to 2s. Section toggles are rare user actions
            // that don't need sub-second responsiveness. Background services writing to UserDefaults
            // were triggering this handler dozens of times per minute, each causing a view re-render.
            guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
            
            // Section visibility may depend on UserDefaults (section toggles in settings)
            let newSections = computeHomeSections()
            if newSections != cachedHomeSections {
                cachedHomeSections = newSections
            }
        }
        // Cache allCoins snapshot for trending / market movers section.
        // Debounced to 2s — fast enough for visible first paint, scroll guard + memory check
        // prevent excess work. Phase 2 gating defers processing until UI is ready.
        .onReceive(MarketViewModel.shared.$allCoins.debounce(for: .seconds(2), scheduler: DispatchQueue.main)) { coins in
            guard sectionLoadingPhase >= 2 else { return }
            guard !coins.isEmpty else { return }
            if hasTrendingBeenPopulated {
                guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
            }
            // Memory check: skip only when memory is known AND critically low
            let _avail = Double(os_proc_available_memory()) / (1024 * 1024)
            if _avail > 0 && _avail < 300 { return }
            cachedTrendingCoins = coins
            if !hasTrendingBeenPopulated { hasTrendingBeenPopulated = true }
        }
        // PERFORMANCE FIX v22: Cache news loading state
        .onReceive(CryptoNewsFeedViewModel.shared.$isLoading.removeDuplicates()) { loading in
            cachedNewsIsLoading = loading
        }
        // SECTION TOGGLE FIX: Immediately refresh layout when ANY section toggle changes.
        // Each toggle is observed via @AppStorage so SwiftUI detects the change even if
        // the UserDefaults.didChangeNotification handler was blocked by the scroll guard.
        .onChange(of: sectionToggleFingerprint) { _, _ in
            cachedHomeSections = computeHomeSections()
        }
        // SECTION ORDER FIX: Refresh layout when section order changes via drag-and-drop.
        // HomeSectionOrderManager bumps this version whenever the user reorders sections.
        .onChange(of: sectionOrderVersion) { _, _ in
            cachedHomeSections = computeHomeSections()
        }
        // WATCHLIST INSTANT-SYNC FIX: Force-refresh sections when switching TO the Home tab.
        // When the user favorites a coin on the Market tab and switches back to Home,
        // the onReceive handlers may have already fired (and been consumed or scroll-blocked).
        // This ensures the Home tab always shows the latest favorites on every tab switch.
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .home {
                let freshSections = computeHomeSections()
                if freshSections != cachedHomeSections {
                    cachedHomeSections = freshSections
                }
                // Also drain any pending update flag
                hasPendingWatchlistSectionUpdate = false
            }
        }
        // APP LIFECYCLE FIX: Refresh layout when returning from background
        // This prevents the "blank area" bug where LazyVStack doesn't re-render sections
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // Force refresh of cached sections after returning from background
                // This ensures all LazyVStack content is properly rendered
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    let freshSections = computeHomeSections()
                    if freshSections != cachedHomeSections || cachedHomeSections.isEmpty {
                        cachedHomeSections = freshSections
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            // Refresh layout caches immediately on rotation so sections do not stay misaligned.
            DispatchQueue.main.async {
                MarketColumns.invalidateCache()
                wlMetrics = .init(
                    leadingWidth: 125,
                    sparkWidth: 140,
                    percentWidth: 48,
                    percentSpacing: 6,
                    innerDividerW: 1,
                    outerDividerW: 1
                )
                let freshSections = computeHomeSections()
                if freshSections != cachedHomeSections {
                    cachedHomeSections = freshSections
                }
            }
        }
    }

    /// Lightweight fingerprint that changes whenever ANY section toggle changes.
    /// Used by .onChange to bypass the scroll-guarded UserDefaults.didChangeNotification handler.
    /// Combining into a single Equatable value avoids needing 19 separate .onChange handlers.
    private var sectionToggleFingerprint: [Bool] {
        [
            secShowPortfolio, secShowStocksEnabled, secShowStocksOverview, secShowStockWatchlist,
            secShowWatchlist, secShowMarketStats, secShowSentiment, secShowHeatmap, secShowTrending,
            secShowArbitrage, secShowWhaleActivity, secShowEvents, secShowNews, secShowAIInsights,
            secShowAIPredictions, secShowCommodities, secShowPromos, secShowTransactions, secShowCommunity
        ]
    }

    // PERFORMANCE FIX: Compute sections once, not on every body evaluation
    // This function is called on appear and when watchlist changes
    private func computeHomeSections() -> [HomeSection] {
        let context = HomeContext(
            hasWatchlistItems: !MarketViewModel.shared.watchlistCoins.isEmpty || !FavoritesManager.shared.favoriteIDs.isEmpty,
            featureFlags: FeatureFlags(arbitrageEnabled: true)
        )
        let allSections = HomeSectionsLayout.visibleSections(context: context)

        #if targetEnvironment(simulator)
        guard AppSettings.isSimulatorLimitedDataMode else {
            return allSections
        }

        // Phased loading for smoother first paint (simulator limited mode only).
        // Phase 1 (immediate): +watchlist.
        // Phase 2 (+~1s): +news +commodities.
        // Phase 3 (+~4s): all sections.
        switch sectionLoadingPhase {
        case 0:
            let phase0Sections: Set<HomeSection> = [.portfolio, .footer]
            return allSections.filter { phase0Sections.contains($0) }
        case 1:
            // Watchlist ONLY — no news. Added immediately.
            let phase1Sections: Set<HomeSection> = [
                .portfolio, .watchlist, .footer
            ]
            return allSections.filter { phase1Sections.contains($0) }
        case 2:
            // Add key context quickly after first paint.
            let phase2Sections: Set<HomeSection> = [
                .portfolio, .watchlist, .trending, .sentiment, .news, .commoditiesOverview, .footer
            ]
            return allSections.filter { phase2Sections.contains($0) }
        default:
            // Keep simulator stable by omitting only whale activity in limited mode.
            // Heatmap remains enabled for parity with device behavior.
            let omitted: Set<HomeSection> = [.whaleActivity]
            return allSections.filter { !omitted.contains($0) }
        }
        #else
        return allSections
        #endif
    }
    
    private var homeContentStack: some View {
        // Use cached sections from @State (computed in .task and updated by onChange handlers).
        // Fallback: compute on first render to avoid blank content during the 100ms .task delay.
        // Once cachedHomeSections is populated, the fallback never executes.
        let sections = cachedHomeSections.isEmpty ? computeHomeSections() : cachedHomeSections

        // PERFORMANCE FIX: Hoist the scroll-block check once per render instead of calling
        // ScrollStateManager.shared.shouldBlockHeavyOperation() inside each section's .transaction.
        // With 16+ sections, that was 16+ function calls per render pass. One check is enough.
        let blockAnimations = ScrollStateManager.shared.shouldBlockHeavyOperation()

        // PERFORMANCE: Disable animations during scroll for smooth 60fps
        // Spacing: 12pt between dashboard cards for breathing room + shadow clearance
        return LazyVStack(alignment: .leading, spacing: 12) {
            // Header bar always visible regardless of section toggles
            HomeHeaderBar(
                showNotifications: $showNotifications,
                showSettings: $showSettings,
                hasPendingNotifications: hasPendingNotifications
            )
            .id("homeHeader")
            
            ForEach(sections, id: \.self) { section in
                Group {
                    switch section {
                    case .portfolio:
                        // Portfolio summary card with integrated AI Insights
                        PortfolioSectionView(
                            selectedRange: $selectedRange,
                            showTimeframePicker: $showTimeframePicker,
                            timeframePickerAnchor: $timeframePickerAnchor,
                            showAllInsights: $showAllAIInsights,
                            onOpenChat: { prompt in
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                chatVM.inputText = prompt
                                selectedTab = .ai
                            }
                        )
                        .environmentObject(vm)
                        .id("portfolio")

                        // Agent signal card — only shows when agent is connected
                        if AgentConnectionService.shared.isConnected,
                           let signal = AgentConnectionService.shared.latestSignals.first {
                            NavigationLink(destination: AgentSignalFeedView()) {
                                AgentSignalCompactCard(signal: signal)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                        }

                    case .agentTrading:
                        // Agent trading home card — shown only when agent is connected
                        AgentHomeCard()
                            .id("agentTrading")

                    case .aiInsights:
                        // AI Insights now integrated into Portfolio card above
                        EmptyView()

                    case .aiPredictions:
                        // AI Predictions now integrated into Watchlist section as CTA button
                        EmptyView()
                    
                    case .stocksOverview:
                        StocksOverviewSection(
                            onOpenMarketStock: { stock in
                                selectedMarketStock = stock
                            },
                            onOpenMarketView: {
                                showStockMarketView = true
                            }
                        )
                            .id("stocksOverview")
                    
                    case .stockWatchlist:
                        // Only show if user has stocks in watchlist
                        if !StockWatchlistManager.shared.isEmpty {
                            StockWatchlistSection()
                                .id("stockWatchlist")
                        }
                    
                    case .commoditiesOverview:
                        CommoditiesOverviewSection(
                            onOpenCommodityHolding: { holding in
                                selectedCommodityHolding = holding
                            },
                            onOpenMarketCommodity: { commodity in
                                selectedMarketCommodity = commodity
                            },
                            onOpenLiveCommodity: { commodityInfo in
                                selectedLiveCommodity = commodityInfo
                            },
                            onOpenMarketView: {
                                showCommoditiesMarketView = true
                            }
                        )
                            .id("commoditiesOverview")

                    case .watchlist:
                        WatchlistComposite(
                            leadingWidth: wlLeadingWidth,
                            sparkWidth: wlSparkWidth,
                            percentWidth: wlPercentWidth,
                            percentSpacing: wlPercentSpacing,
                            innerDividerW: wlInnerDividerW,
                            outerDividerW: wlOuterDividerW,
                            sparklineCache: watchlistSparklineCache,
                            livePrices: watchlistLivePrices,
                            refreshGeneration: watchlistRefreshGeneration,
                            onSelectCoinForDetail: { coin in
                                selectedWatchlistCoin = coin
                            },
                            showTimeframePopover: $predictionPicker.showPicker,
                            timeframeButtonFrame: $predictionPicker.buttonFrame,
                            selectedTimeframe: $predictionPicker.selectedTimeframe
                        )
                        .onPreferenceChange(WatchlistColumnsKey.self) { (m: WatchlistColumnMetrics) in
                            // Defer state modification to avoid "Modifying state during view update"
                            // PERFORMANCE FIX: Single struct assignment instead of 6 individual property updates
                            DispatchQueue.main.async {
                                if m.sparkWidth > 0, m.percentWidth > 0, m.leadingWidth > 0 {
                                    wlMetrics = m
                                }
                            }
                        }
                        .id("watchlist")

                    case .marketStats:
                        marketStatsSection
                            .id("marketStats")

                    case .sentiment:
                        sentimentSection
                            .id("sentiment")

                    case .heatmap:
                        heatmapSection
                            .id("heatmap")

                    case .promos:
                        ActionCenterSection(
                            result: riskScan.result,
                            isScanning: riskScan.isScanning,
                            lastScan: riskScan.lastScanAt,
                            overlayActive: riskScan.showOverlay,
                            onScan: { Task { await runRiskScan() } },
                            onViewReport: { riskScan.showReport = true }
                        )
                        .id("aiInvite")
                        .sheet(isPresented: $riskScan.showReport) {
                            RiskReportView(result: riskScan.result, lastScanned: riskScan.lastScanAt)
                        }

                    case .trending:
                        trendingSection
                            .id("trending")

                    case .arbitrage:
                        arbitrageSection
                            .id("arbitrage")

                    case .whaleActivity:
                        whaleActivitySection
                            .id("whaleActivity")

                    case .events:
                        eventsSection
                            .id("events")

                    case .news:
                        newsPreviewSection
                            // PERFORMANCE FIX v22: Use cached isLoading instead of singleton access
                            // CryptoNewsFeedViewModel.shared.isLoading is @Published - accessing it in body
                            // creates a hidden observation dependency that re-evaluates all 16+ sections on every news fetch.
                            .redacted(reason: cachedNewsIsLoading ? RedactionReasons.placeholder : RedactionReasons())

                    case .transactions:
                        transactionsSection
                            .id("transactions")

                    case .community:
                        communitySection
                            .id("community")
                    
                    case .communityLinks:
                        communitySocialLinksSection
                            .id("communityLinks")

                    case .footer:
                        footer
                            .id("footer")
                    }
                }
                .padding(.horizontal, 16)  // Standardized: ALL sections get uniform horizontal padding
                // PERFORMANCE FIX v21: Rasterize section layers during scroll.
                // This is THE key UIKit technique: tells Core Animation to cache each section
                // as a pre-rendered bitmap. During scroll, the GPU only MOVES these bitmaps
                // instead of re-compositing all the layers (background + gradient + shadow + text)
                // every frame. Automatically disabled when scroll stops for crisp rendering.
                // MEMORY FIX: Removed .rasterizeDuringScroll() - each section's rasterized bitmap
                // at 3x resolution costs ~6 MB. With 16 sections that's ~96 MB during scroll.
                // .rasterizeDuringScroll()
                .transaction { transaction in
                    if blockAnimations {
                        transaction.animation = nil
                        transaction.disablesAnimations = true
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 32)
        // Smooth phase transitions while retaining scroll-safe behavior.
        .animation(blockAnimations ? .none : .easeOut(duration: 0.22), value: sectionLoadingPhase)
    }

    // PERFORMANCE FIX v22: Moved from HomeView+Subviews.swift to access @State cachedTrendingCoins
    var trendingSection: some View {
        TrendingSectionView(coins: cachedTrendingCoins, maxItemsPerList: 6, selectedCoin: $selectedTrendingCoin)
    }
    
    private var marketStatsSection: some View {
        MarketStatsView()
    }

    private var sentimentSection: some View {
        MarketSentimentView()
    }

    private var heatmapSection: some View {
        // MEMORY FIX: Visibility-gated — heatmap body is only evaluated when
        // the section is scrolled into the visible area. When offscreen, a
        // lightweight placeholder is shown instead, saving ~50-100 MB of
        // transient array/layout allocations per SwiftUI render cycle.
        VisibilityGatedView(placeholderHeight: 260) {
            MarketHeatMapSection()
        }
    }

    private var newsPreviewSection: some View {
        PremiumNewsSection(viewModel: CryptoNewsFeedViewModel.shared, lastSeenArticleID: $lastSeenArticleID)
    }

    private var eventsSection: some View {
        // PERFORMANCE FIX v22: EventsViewModel is now owned by wrapper, not HomeView
        EventsSectionWrapper(showAll: $showAllEvents)
    }

    private func runRiskScan() async {
        guard !vm.portfolioVM.holdings.isEmpty else {
            await MainActor.run {
                self.riskScan.isScanning = true
                self.riskScan.showOverlay = true
            }
            // Show the full scan animation even when empty (5 seconds)
            try? await Task.sleep(nanoseconds: 5_500_000_000)
            await MainActor.run {
                self.riskScan.result = RiskScanResult(
                    score: 0,
                    level: .low,
                    highlights: [RiskHighlight(title: "No holdings", detail: "Add assets to your portfolio to analyze risk.", severity: .low)],
                    metrics: RiskMetrics.zero
                )
                self.riskScan.lastScanAt = Date()
                self.riskScan.isScanning = false
                self.riskScan.showOverlay = false
                self.riskScan.showReport = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            return
        }
        if riskScan.isScanning { return }
        await MainActor.run { self.riskScan.isScanning = true }
        await MainActor.run { self.riskScan.showOverlay = true }
        let start = Date()
        
        // Step 1: Run algorithmic scan
        var result = await MainActor.run { RiskScanner.scan(portfolioVM: vm.portfolioVM, marketVM: MarketViewModel.shared) }
        
        // Step 2: Generate AI recommendations (non-blocking, with fallback)
        // Only call AI for subscribers or demo mode users
        let canUseAI = DemoModeManager.shared.isDemoMode || SubscriptionManager.shared.hasTier(.pro)
        if canUseAI {
            do {
                let aiAnalysis = try await AIRiskInsightService.shared.generateAnalysis(
                    for: result,
                    portfolioVM: vm.portfolioVM
                )
                // Merge AI recommendations into result
                result.aiAnalysis = aiAnalysis.summary
                result.aiRecommendations = aiAnalysis.recommendations.map { $0.text }
            } catch {
                // AI failed - continue with algorithmic recommendations only
                #if DEBUG
                print("[HomeView] AI risk analysis failed: \(error.localizedDescription)")
                #endif
            }
        }
        
        // Ensure the scan animation has time to play (minimum 5.5 seconds for premium feel)
        let minDuration: TimeInterval = 5.5
        let elapsed = Date().timeIntervalSince(start)
        if elapsed < minDuration {
            let remain = minDuration - elapsed
            try? await Task.sleep(nanoseconds: UInt64(remain * 1_000_000_000))
        }
        await MainActor.run {
            self.riskScan.result = result
            self.riskScan.isScanning = false
            self.riskScan.showOverlay = false
            self.riskScan.lastScanAt = Date()
            self.riskScan.showReport = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}

// PERFORMANCE FIX v22: EventsViewModel is now owned by this wrapper, not HomeView.
// Previously HomeView owned EventsViewModel as @StateObject — its 4 @Published properties
// (items, isLoading, errorMessage, lastUpdated) fired objectWillChange on HomeView's body,
// causing 16+ sections to re-evaluate even when events section was off-screen in LazyVStack.
// By isolating it in a wrapper, only the events section re-renders on events data changes.
struct EventsSectionWrapper: View {
    @StateObject private var eventsVM = EventsViewModel()
    @Binding var showAll: Bool
    
    var body: some View {
        EventsSectionView(vm: eventsVM, showAll: $showAll)
        // FIX v23: .navigationDestination moved to HomeView level (outside LazyVStack)
        // to prevent unreliable navigation when this section scrolls off-screen.
    }
}

/// Standalone wrapper that owns its own EventsViewModel.
/// Used by HomeView's .navigationDestination(isPresented: $showAllEvents) at the top level.
struct StandaloneAllEventsView: View {
    @StateObject private var vm = EventsViewModel()
    var body: some View {
        AllEventsView(vm: vm)
    }
}

// Helpers used throughout
private func upgradeToHTTPS(_ url: URL?) -> URL? {
    guard let url else { return nil }
    guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
    if comps.scheme?.lowercased() == "http" { comps.scheme = "https"; return comps.url ?? url }
    return url
}

// MARK: - Preview
struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView(selectedTab: .constant(.home))
            .environmentObject(ChatViewModel())
            .environmentObject(MarketViewModel.shared)
            .environmentObject(CryptoNewsFeedViewModel.shared)
            .environmentObject(HomeViewModel())
    }
}

