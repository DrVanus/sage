import SwiftUI
import Combine
import UniformTypeIdentifiers
import Network
#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

// Local gold palette for drag highlights in Favorites
private enum MarketGold {
    static let light = Color(red: 0.9647, green: 0.8275, blue: 0.3961)
    static let dark  = Color(red: 0.8314, green: 0.6863, blue: 0.2157)
    static let shadow = light
    static var horizontalGradient: LinearGradient { LinearGradient(colors: [light, dark], startPoint: .leading, endPoint: .trailing) }
    static var verticalGradient: LinearGradient { LinearGradient(colors: [light, dark], startPoint: .top, endPoint: .bottom) }
}

// MARK: - Joined ring (square left edge, rounded right corners) for Favorites
private struct FavoritesJoinedRingShape: InsettableShape {
    var leftInset: CGFloat
    var cornerRadius: CGFloat
    var insetAmount: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let xL = r.minX + leftInset
        let xR = r.maxX
        let yT = r.minY
        let yB = r.maxY
        let cr = max(0, cornerRadius - insetAmount)
        var p = Path()
        p.move(to: CGPoint(x: xL, y: yT))
        p.addLine(to: CGPoint(x: xR - cr, y: yT))
        p.addQuadCurve(to: CGPoint(x: xR, y: yT + cr), control: CGPoint(x: xR, y: yT))
        p.addLine(to: CGPoint(x: xR, y: yB - cr))
        p.addQuadCurve(to: CGPoint(x: xR - cr, y: yB), control: CGPoint(x: xR, y: yB))
        p.addLine(to: CGPoint(x: xL, y: yB))
        p.addLine(to: CGPoint(x: xL, y: yT))
        p.closeSubpath()
        return p
    }
    func inset(by amount: CGFloat) -> some InsettableShape { var copy = self; copy.insetAmount += amount; return copy }
}

// MARK: - Joined ring stroke (slight left overlap to fuse with bar)
private struct FavoritesJoinedRingStrokeShape: InsettableShape {
    var leftInset: CGFloat
    var cornerRadius: CGFloat
    var overlap: CGFloat = 1.3
    var insetAmount: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let xL = r.minX + leftInset - overlap
        let xR = r.maxX
        let yT = r.minY
        let yB = r.maxY
        let cr = max(0, cornerRadius - insetAmount)
        var p = Path()
        p.move(to: CGPoint(x: xL, y: yT))
        p.addLine(to: CGPoint(x: xR - cr, y: yT))
        p.addQuadCurve(to: CGPoint(x: xR, y: yT + cr), control: CGPoint(x: xR, y: yT))
        p.addLine(to: CGPoint(x: xR, y: yB - cr))
        p.addQuadCurve(to: CGPoint(x: xR - cr, y: yB), control: CGPoint(x: xR, y: yB))
        p.addLine(to: CGPoint(x: xL, y: yB))
        p.addLine(to: CGPoint(x: xL, y: yT))
        p.closeSubpath()
        return p
    }
    func inset(by amount: CGFloat) -> some InsettableShape { var copy = self; copy.insetAmount += amount; return copy }
}

// Pixel snapping helper for crisp 1px dividers
private let _pxScale: CGFloat = {
    #if os(iOS)
    return UIScreen.main.scale
    #elseif os(macOS)
    return NSScreen.main?.backingScaleFactor ?? 2.0
    #else
    return 2.0
    #endif
}()
@inline(__always) private var hairline: CGFloat { 1.0 / _pxScale }

// Button style for the top segment chips - adaptive for light/dark mode
private struct SegmentChipStyle: ButtonStyle {
    var isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        // Adaptive colors based on color scheme
        let bg: Color = {
            if colorScheme == .dark {
                return isSelected ? Color.white : Color.white.opacity(0.15)
            } else {
                return isSelected ? Color.black : Color.black.opacity(0.08)
            }
        }()
        let strokeColor: Color = {
            if colorScheme == .dark {
                return Color.white.opacity(isSelected ? 0.0 : 0.25)
            } else {
                return Color.black.opacity(isSelected ? 0.0 : 0.15)
            }
        }()
        let isDark = colorScheme == .dark
        
        return configuration.label
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(bg)
                    // Premium glass top-shine for selected state
                    if isSelected {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        (isDark ? Color.white : Color.white).opacity(isDark ? 0.12 : 0.30),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(strokeColor, lineWidth: 0.8)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.9), value: configuration.isPressed)
    }
}

// Adaptive label for segment chips
private struct SegmentChipLabel: View {
    let segmentName: String
    let count: Int
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    private var textColor: Color {
        if colorScheme == .dark {
            return isSelected ? .black : .white
        } else {
            return isSelected ? .white : .black
        }
    }
    
    private var badgeTextColor: Color {
        if colorScheme == .dark {
            return isSelected ? .black.opacity(0.6) : .white.opacity(0.6)
        } else {
            return isSelected ? .white.opacity(0.7) : .black.opacity(0.6)
        }
    }
    
    private var badgeBgColor: Color {
        if colorScheme == .dark {
            return isSelected ? Color.black.opacity(0.15) : Color.white.opacity(0.15)
        } else {
            return isSelected ? Color.white.opacity(0.25) : Color.black.opacity(0.10)
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Text(segmentName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(textColor)
                .lineLimit(1)
            
            // Show count badge when count > 0 (including All segment)
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(badgeTextColor)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        Capsule()
                            .fill(badgeBgColor)
                    )
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct MarketView: View {
    @ObservedObject private var vm = MarketViewModel.shared
    @ObservedObject private var firestoreSync = FirestoreMarketSync.shared
    // PERFORMANCE FIX v22: Removed @EnvironmentObject AppState.
    // AppState has 18+ @Published properties. MarketView only uses it for onChange handlers
    // (marketNavPath, dismissMarketSubviews) — not in body. Observation caused full re-renders
    // on every keyboard/tab/nav change. Using AppState.shared for write-only access.
    private var appState: AppState { AppState.shared }
    @Environment(\.scenePhase) private var scenePhase

    // Inline reordering state for Favorites segment
    @State private var favLocalOrder: [String] = []
    @State private var favDraggingID: String? = nil
    // DEAD CODE REMOVED: favShakeAttempts was never incremented, so shake effect never triggered
    @State private var favIsDragging: Bool = false
    @State private var favListResetKey: UUID = UUID()
    @State private var favDragWatchTimer: Timer? = nil
    @State private var favDragHeartbeat: Date = .distantPast
    @State private var favHoverTargetID: String? = nil
    @State private var favHoverInsertAfter: Bool = false
    @State private var favAnimatePulse: Bool = false
    @State private var favRingActive: Bool = false
    @State private var favRingRowID: String? = nil
    @State private var favDragSessionID: UUID? = nil
    @State private var favRingClearTask: Task<Void, Never>? = nil

    @State private var visibleCount: Int = 80  // Increased from 60 for better initial coverage
    @State private var lastLoadMoreAt: Date = .distantPast
    
    // Temporarily disable list animations during segment/sort switches for instant response
    @State private var isSegmentSwitching: Bool = false

    // Debounce heavy filtering/sorting to keep UI taps snappy
    @State private var filterDebounceTask: Task<Void, Never>? = nil

    @State private var isNetworkReachable: Bool = true
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "NetworkMonitorQueue")

    // Guards to avoid duplicate start/stop of monitors and polling
    @State private var networkMonitorStarted: Bool = false
    @State private var pollingActive: Bool = false

    @State private var showPairsSheet: Bool = false
    @State private var pairsSheetSymbol: String = "BTC"
    @State private var showFilterSheet: Bool = false
    @State private var isSearchFocused: Bool = false  // Tracks search field focus state
    
    // PERFORMANCE FIX: Programmatic navigation to avoid NavigationLink preloading in ForEach
    // NavigationLink inside ForEach causes SwiftUI to initialize ALL destination views upfront
    // Using a single hidden NavigationLink with state-based activation prevents this
    @State private var selectedCoinForDetail: MarketCoin? = nil
    
    // Binance sparkline fetching for market coins (mirrors WatchlistSection approach)
    // PERFORMANCE FIX: Defer disk I/O to onAppear instead of view init
    @State private var marketSparklineCache: [String: [Double]] = [:]
    @State private var lastMarketSparklineFetchAt: Date = .distantPast
    @State private var marketSparklineFetchInProgress: Bool = false
    @State private var didInitialLoad: Bool = false  // PERFORMANCE FIX: Track initial load to skip redundant work
    // Track when each sparkline was last refreshed to ensure freshness
    @State private var sparklineLastRefreshAt: [String: Date] = [:]
    // How often to force refresh even good quality data (5 minutes for 7D data)
    private let sparklineForceRefreshInterval: TimeInterval = 300
    
    // PERFORMANCE FIX: Cached coins for display to reduce re-renders
    // The displayed coins are updated via debounced onReceive instead of directly in body
    // This prevents the entire view from re-rendering on every MarketViewModel change
    @State private var cachedDisplayCoins: [MarketCoin] = []
    @State private var lastCoinsCacheAt: Date = .distantPast
    // DEAD CODE REMOVED: displayCoinsUpdateTask was never assigned
    
    /// SPARKLINE STABILITY: Determines if new sparkline data should replace existing cached data.
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
    
    /// Checks if a sparkline needs refresh based on staleness
    private func sparklineNeedsRefresh(_ coinID: String) -> Bool {
        // No cached data - needs fetch
        guard let existing = marketSparklineCache[coinID], existing.count >= 10 else { return true }
        // Check if stale (older than 5 minutes)
        if let lastRefresh = sparklineLastRefreshAt[coinID] {
            return Date().timeIntervalSince(lastRefresh) > sparklineForceRefreshInterval
        }
        // No timestamp - assume stale
        return true
    }

    private func startMonitoringIfNeeded() {
        guard !networkMonitorStarted else { return }
        networkMonitor.pathUpdateHandler = { path in
            let reachable = path.status == .satisfied
            DispatchQueue.main.async {
                isNetworkReachable = reachable
                if reachable {
                    ensurePollingRunning()
                }
            }
        }
        networkMonitor.start(queue: networkQueue)
        networkMonitorStarted = true
    }

    private func ensurePollingRunning() {
        guard !pollingActive else { return }
        LivePriceManager.shared.startPolling(interval: 60)
        pollingActive = true
    }

    private func stopPollingIfNeeded() {
        guard pollingActive else { return }
        LivePriceManager.shared.stopPolling()
        pollingActive = false
    }
    
    /// PERFORMANCE: Batch fetches Binance sparklines for visible market coins
    /// Called from MarketView level instead of per-row to reduce concurrent tasks
    /// Pre-fetches sparklines for coins beyond visible range for smoother scrolling
    private func fetchBinanceSparklinesForVisibleCoins() {
        let now = Date()
        // Throttle: minimum 5 seconds between fetch attempts (reduced from 30 for better scroll experience)
        // This allows sparklines to load as user scrolls down without excessive API calls
        guard now.timeIntervalSince(lastMarketSparklineFetchAt) > 5 else { return }
        guard !marketSparklineFetchInProgress else { return }
        
        let coins = coinsToDisplay()
        // SPARKLINE OPTIMIZATION: Reduce pre-fetch on slow/cellular networks
        // Fast network: 32 coins ahead, Slow network: 16 coins ahead
        let prefetchAhead = NetworkReachability.shared.recommendedPrefetchCount
        let prefetchCount = min(visibleCount + prefetchAhead, coins.count)
        let coinsToFetch = Array(coins.prefix(prefetchCount))
        guard !coinsToFetch.isEmpty else { return }
        
        // Filter to coins that need fresh data (missing, sparse, or stale)
        let coinsNeedingFetch = coinsToFetch.filter { sparklineNeedsRefresh($0.id) }
        guard !coinsNeedingFetch.isEmpty else { return }
        
        marketSparklineFetchInProgress = true
        lastMarketSparklineFetchAt = now
        
        Task {
            let coinData = coinsNeedingFetch.map { (id: $0.id, symbol: $0.symbol.uppercased()) }
            let fetchedIDs = await WatchlistSparklineService.shared.fetchSparklines(for: coinData)
            
            // PERFORMANCE: Batch fetch all sparklines at once, then update cache on main thread
            var newCache: [String: [Double]] = [:]
            for id in fetchedIDs {
                if let sparkline = await WatchlistSparklineService.shared.getSparkline(for: id),
                   sparkline.count >= 10 {
                    newCache[id] = sparkline
                }
            }
            
            await MainActor.run {
                let refreshTime = Date()
                // STABILITY: Only replace if new data is better quality
                for (id, sparkline) in newCache {
                    if self.shouldReplaceSparkline(existing: self.marketSparklineCache[id], new: sparkline) {
                        self.marketSparklineCache[id] = sparkline
                        self.sparklineLastRefreshAt[id] = refreshTime
                    }
                }
                self.marketSparklineFetchInProgress = false
            }
        }
    }
    
    /// Refreshes Binance sparklines (fetches fresh data for visible coins)
    /// Pre-fetches beyond visible range for smoother scrolling experience
    /// STABILITY: Uses quality checks to prevent replacing good data with degraded data
    private func refreshBinanceSparklines() async {
        let coins = coinsToDisplay()
        // SPARKLINE OPTIMIZATION: Reduce pre-fetch on slow/cellular networks
        let prefetchAhead = NetworkReachability.shared.recommendedPrefetchCount
        let prefetchCount = min(visibleCount + prefetchAhead, coins.count)
        let coinsToRefresh = Array(coins.prefix(prefetchCount))
        guard !coinsToRefresh.isEmpty else { return }
        
        await MainActor.run { marketSparklineFetchInProgress = true }
        
        let coinData = coinsToRefresh.map { (id: $0.id, symbol: $0.symbol.uppercased()) }
        let fetchedIDs = await WatchlistSparklineService.shared.refreshSparklines(for: coinData)
        
        // PERFORMANCE: Batch fetch all sparklines at once
        var newCache: [String: [Double]] = [:]
        for id in fetchedIDs {
            if let sparkline = await WatchlistSparklineService.shared.getSparkline(for: id),
               sparkline.count >= 10 {
                newCache[id] = sparkline
            }
        }
        
        await MainActor.run {
            let refreshTime = Date()
            // STABILITY: Only replace if new data is better quality
            for (id, sparkline) in newCache {
                if self.shouldReplaceSparkline(existing: self.marketSparklineCache[id], new: sparkline) {
                    self.marketSparklineCache[id] = sparkline
                    self.sparklineLastRefreshAt[id] = refreshTime
                }
            }
            
            // MEMORY FIX v14: Reduced from 600 to 200 to limit sparkline memory.
            // Each sparkline is ~1.3 KB (168 Doubles), so 200 entries ≈ 260 KB max.
            let maxCacheSize = 200
            if self.marketSparklineCache.count > maxCacheSize {
                // Keep entries that were recently refreshed
                let sortedByAge = self.sparklineLastRefreshAt.sorted { $0.value > $1.value }
                let idsToKeep = Set(sortedByAge.prefix(maxCacheSize).map { $0.key })
                let idsToRemove = self.marketSparklineCache.keys.filter { !idsToKeep.contains($0) }
                for id in idsToRemove {
                    self.marketSparklineCache.removeValue(forKey: id)
                    self.sparklineLastRefreshAt.removeValue(forKey: id)
                }
            }
            
            self.marketSparklineFetchInProgress = false
            self.lastMarketSparklineFetchAt = refreshTime
        }
    }

    private func applyFiltersImmediatelyNoAnimation() {
        withAnimation(nil) {
            vm.applyAllFiltersAndSort()
        }
    }

    // Debounced filter application to keep typing responsive
    private func applyFiltersDebounced() {
        filterDebounceTask?.cancel()
        filterDebounceTask = Task { @MainActor in
            // Short debounce (100ms) for responsive search
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            // Call filter synchronously on main thread
            vm.applyAllFiltersAndSort()
        }
    }

    // Small helpers to simplify segment row and reduce type-checking complexity
    @ViewBuilder
    private func segmentChip(for seg: MarketSegment, isSelected: Bool) -> some View {
        let count = vm.segmentCounts[seg] ?? 0
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            isSegmentSwitching = true
            vm.selectedSegment = seg
            visibleCount = 80  // Reset to initial count on segment switch
            applyFiltersImmediatelyNoAnimation()
            DispatchQueue.main.async {
                isSegmentSwitching = false
            }
        } label: {
            SegmentChipLabel(segmentName: seg.rawValue, count: count, isSelected: isSelected)
        }
        .buttonStyle(SegmentChipStyle(isSelected: isSelected))
        .id(seg.id)
        .accessibilityLabel(Text("\(seg.rawValue), \(count) coins"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(Text("Filter coins by \(seg.rawValue)"))
    }

    private func searchToggleButton() -> some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            withAnimation {
                vm.showSearchBar.toggle()
                // Clear search and restore normal list when hiding search bar
                if !vm.showSearchBar && !vm.searchText.isEmpty {
                    vm.searchText = ""
                }
            }
        } label: {
            // SEARCH FIX: Use consistent white/textSecondary color like other icons in the row
            // Filled icon when active for visual feedback, but same color for consistency
            Image(systemName: vm.showSearchBar ? "magnifyingglass.circle.fill" : "magnifyingglass.circle")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(DS.Adaptive.textSecondary)
                .frame(width: 32, height: 32)
        }
    }
    
    /// Whether any non-default filter is currently active
    private var hasActiveFilter: Bool {
        vm.selectedCategory != .all || vm.sortField != .marketCap || vm.sortDirection != .desc
    }

    private var liveDataStatusMessage: String? {
        // Keep market UI optimistic: hide the waiting/delayed feed banner.
        // Data pipeline already continues refreshing in the background.
        return nil
    }
    
    private func filterButton() -> some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            showFilterSheet = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 18))
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .frame(width: 32, height: 32)
                
                // Active filter indicator dot
                if hasActiveFilter {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .offset(x: 2, y: -2)
                }
            }
        }
    }

    // MARK: - Column Header
    @ViewBuilder
    private func headerGutterDivider() -> some View {
        Color.clear
            .frame(width: MarketColumns.gutter)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(DS.Adaptive.divider)
                    .frame(width: hairline, height: 12)
            }
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            headerButton("Coin", .coin)
                .frame(width: MarketColumns.coinColumnWidth, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
            headerGutterDivider()

            Text("7D")
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundColor(DS.Adaptive.textPrimary.opacity(0.95))
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .frame(width: MarketColumns.sparklineWidth, alignment: .center)
            headerGutterDivider()

            headerButton("Price", .price)
                .monospacedDigit()
                .frame(width: MarketColumns.priceWidth, alignment: .trailing)
            headerGutterDivider()

            headerButton("24h", .dailyChange)
                .monospacedDigit()
                .frame(width: MarketColumns.changeWidth, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
            headerGutterDivider()

            Text("Vol")
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundColor(DS.Adaptive.textPrimary.opacity(0.95))
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .monospacedDigit()
                .frame(width: MarketColumns.volumeWidth, alignment: .trailing)
            headerGutterDivider()

            Text("Fav")
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundColor(DS.Adaptive.textPrimary.opacity(0.95))
                .baselineOffset(1)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .frame(width: max(MarketColumns.starColumnWidth, 36), alignment: .center)
        }
        .padding(.horizontal, MarketColumns.horizontalPadding)
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) {
            GeometryReader { proxy in
                Rectangle()
                    .fill(DS.Adaptive.divider)
                    .frame(height: hairline)
                    .position(x: proxy.size.width / 2, y: hairline / 2)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Empty State Views
    private func emptyStateView(for segment: MarketSegment) -> some View {
        VStack(spacing: 16) {
            // Icon
            Image(systemName: emptyStateIcon(for: segment))
                .font(.system(size: 48, weight: .light))
                .foregroundColor(DS.Adaptive.textTertiary)
            
            // Title
            Text(emptyStateTitle(for: segment))
                .font(.headline)
                .foregroundColor(DS.Adaptive.textPrimary.opacity(0.8))
            
            // Subtitle
            Text(emptyStateSubtitle(for: segment))
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            // Action button for favorites
            if segment == .favorites {
                Button {
                    vm.selectedSegment = .all
                } label: {
                    Text("Browse Coins")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(DS.Adaptive.background)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(DS.Adaptive.textPrimary))
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    private func emptyStateIcon(for segment: MarketSegment) -> String {
        switch segment {
        case .favorites: return "star"
        case .new: return "sparkles"
        case .gainers: return "chart.line.uptrend.xyaxis"
        case .losers: return "chart.line.downtrend.xyaxis"
        case .trending: return "flame"
        default: return "magnifyingglass"
        }
    }
    
    private func emptyStateTitle(for segment: MarketSegment) -> String {
        switch segment {
        case .favorites: return "No Favorites Yet"
        case .new: return "No New Listings"
        case .gainers: return "No Gainers Right Now"
        case .losers: return "No Losers Right Now"
        case .trending: return "No Trending Coins"
        default: return "No Coins Found"
        }
    }
    
    private func emptyStateSubtitle(for segment: MarketSegment) -> String {
        switch segment {
        case .favorites: return "Tap the star on any coin to add it to your watchlist"
        case .new: return "No coins have been listed in the past 14 days"
        case .gainers: return "No coins are up more than 0.5% in the last 24 hours"
        case .losers: return "No coins are down more than 0.5% in the last 24 hours"
        case .trending: return "Market activity is low right now"
        default: return "Try adjusting your search or filters"
        }
    }
    
    // MARK: - Coin List (with pinned column header)
    private var coinList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                // PERFORMANCE FIX v21: Removed GeometryReader-based .trackScrolling().
                // Scroll tracking now handled by UIKit KVO bridge (zero SwiftUI layout overhead).
                Section {
                    if vm.selectedSegment == .favorites {
                        if vm.favoriteIDs.isEmpty {
                            emptyStateView(for: .favorites)
                        } else {
                            reorderableFavoritesList()
                        }
                    } else {
                        let allCoins: [MarketCoin] = coinsToDisplay()
                        if allCoins.isEmpty {
                            emptyStateView(for: vm.selectedSegment)
                        }
                        let limitedCoins: [MarketCoin] = Array(allCoins.prefix(visibleCount))
                        let totalCoins = allCoins.count
                        let limitedCount = limitedCoins.count
                        // PERFORMANCE FIX: Pre-compute the set of coin IDs in the pagination zone (last 16 items).
                        // This turns the per-row pagination check from O(n) firstIndex lookup into O(1) Set membership.
                        let paginationThreshold = max(0, limitedCount - 16)
                        let paginationZoneIDs: Set<String> = {
                            guard visibleCount < totalCoins else { return [] }
                            return Set(limitedCoins.suffix(from: paginationThreshold).map(\.id))
                        }()
                        let lastCoinID = limitedCoins.last?.id
                        // PERFORMANCE FIX: Use direct ForEach with coin.id for proper identity
                        // Index is computed only when needed (divider, pagination) to avoid enumerated() allocation
                        ForEach(limitedCoins, id: \.id) { coin in
                            // PERFORMANCE FIX: Use Button instead of NavigationLink to avoid preloading
                            // NavigationLink in ForEach causes SwiftUI to initialize ALL CoinDetailView destinations
                            // This was causing significant lag when opening the Market tab
                            Button {
                                #if os(iOS)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                #endif
                                selectedCoinForDetail = coin
                            } label: {
                                // PERFORMANCE: Pass pre-loaded sparkline data to avoid disk I/O in rows
                                CoinRowView(
                                    coin: coin,
                                    sparklineData: marketSparklineCache[coin.id] ?? [],
                                    livePrice: vm.bestPrice(for: coin.id)
                                )
                                    .environmentObject(vm)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, MarketColumns.horizontalPadding)
                                    .environment(\.font, .system(size: 17, weight: .regular))
                                    // PERFORMANCE FIX: Removed row-level .drawingGroup() to avoid double Metal rendering
                                    // CoinRowView already has drawingGroup on price text and SparklineView has its own
                            }
                            .buttonStyle(PlainButtonStyle())
                            // Subtle divider line - show on all except last item
                            .overlay(alignment: .bottom) {
                                if coin.id != lastCoinID {
                                    Rectangle()
                                        .fill(DS.Adaptive.divider)
                                        .frame(height: 0.5)
                                        .padding(.leading, MarketColumns.horizontalPadding + 36) // Align with text, past icon
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            // PERFORMANCE FIX v21: Rasterize rows during scroll for bitmap caching
                            .rasterizeDuringScroll()
                            // PERFORMANCE: Disable all animations on row for scroll smoothness
                            .transaction { $0.animation = nil }
                            .animation(.none, value: coin.id)
                            .onAppear {
                                // PERFORMANCE FIX: O(1) pagination check using pre-computed Set
                                // Previously used firstIndex(where:) which was O(n) per row appearance
                                DispatchQueue.main.async {
                                    if paginationZoneIDs.contains(coin.id) {
                                        let now = Date()
                                        if now.timeIntervalSince(lastLoadMoreAt) > 0.15 {
                                            lastLoadMoreAt = now
                                            withAnimation(nil) {
                                                visibleCount = min(visibleCount + 32, totalCoins)  // Load 32 coins at a time
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Footer loading indicator while more items remain
                        if visibleCount < totalCoins {
                            HStack {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: DS.Adaptive.textPrimary))
                                Text("Loading more…")
                                    .foregroundColor(DS.Adaptive.textSecondary)
                                    .font(.footnote)
                            }
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 12)
                            .onAppear {
                                // Defer to avoid "Modifying state during view update"
                                DispatchQueue.main.async {
                                    let now = Date()
                                    if now.timeIntervalSince(lastLoadMoreAt) > 0.15 {
                                        lastLoadMoreAt = now
                                        visibleCount = min(visibleCount + 24, totalCoins)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    columnHeader
                        .background(DS.Adaptive.background) // keep pinned header solid while scrolling
                }
            }
        }
        // PERFORMANCE FIX v21: UIKit scroll bridge replaces GeometryReader + coordinateSpace + trackDragging.
        // Bridges into the real UIScrollView underneath and applies:
        // - Deceleration rate 0.994 (snappier than default 0.998, Coinbase-like)
        // - KVO-based scroll tracking (zero SwiftUI overhead)
        .withUIKitScrollBridge()
        .scrollDismissesKeyboard(.interactively) // Match AI Chat behavior - dismiss on drag
        .refreshable {
            await vm.loadAllData()
            // Also refresh Binance sparklines on pull-to-refresh
            await refreshBinanceSparklines()
        }
        .onChange(of: vm.selectedSegment) { _, _ in
            // Defer state modification to avoid "Modifying state during view update"
            DispatchQueue.main.async { visibleCount = 80 }
        }
        .onChange(of: vm.searchText) { _, _ in
            // Defer state modification to avoid "Modifying state during view update"
            DispatchQueue.main.async { visibleCount = 80 }
        }
        .onChange(of: visibleCount) { _, _ in
            // PERFORMANCE FIX: Defer sparkline fetch during scroll to prevent jank
            // Only fetch when scroll settles to avoid competing with scroll rendering
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                guard !ScrollStateManager.shared.isScrolling else { return }
                fetchBinanceSparklinesForVisibleCoins()
            }
        }
        .transaction { txn in
            if isSegmentSwitching {
                txn.disablesAnimations = true
            }
        }
    }

    // MARK: - Favorites Reorderable List
    private func reorderableFavoritesList() -> some View {
        // Use shared watchlist order from view model instead of filtered/sorted list
        let base = vm.watchlistCoins
        let idOrder = favLocalOrder.isEmpty ? base.map { $0.id } : favLocalOrder
        let map = Dictionary(base.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered: [MarketCoin] = idOrder.compactMap { map[$0] }

        return ZStack {
            // PERFORMANCE: Disable animations during scroll for smooth 60fps
            LazyVStack(spacing: 0) {
                ForEach(Array(ordered.enumerated()), id: \.element.id) { idx, coin in
                    // PERFORMANCE FIX: Use Button instead of NavigationLink to avoid preloading
                    // Same fix as main coin list - prevents all CoinDetailView from being initialized upfront
                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        selectedCoinForDetail = coin
                    } label: {
                        // PERFORMANCE: Pass pre-loaded sparkline data to avoid disk I/O in rows
                        CoinRowView(
                            coin: coin,
                            sparklineData: marketSparklineCache[coin.id] ?? [],
                            livePrice: vm.bestPrice(for: coin.id)
                        )
                            .environmentObject(vm)
                            .padding(.vertical, 6)
                            .padding(.horizontal, MarketColumns.horizontalPadding)
                            .contentShape(Rectangle())
                            .environment(\.font, .system(size: 17, weight: .regular))
                            // PERFORMANCE FIX: Removed row-level .drawingGroup() to avoid double Metal rendering
                            .animation(.none, value: favRingActive)
                            .animation(.none, value: favRingRowID)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onDrag {
                                #if os(iOS)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                #endif
                                favRingClearTask?.cancel()
                                favRingClearTask = nil
                                self.favHoverTargetID = nil
                                self.favHoverInsertAfter = false
                                self.favDragHeartbeat = Date()
                                let sessionID = UUID()
                                favDragSessionID = sessionID
                                favRingRowID = coin.id
                                favRingActive = true
                                self.favDraggingID = coin.id
                                self.favIsDragging = true
                                // MEMORY FIX: Capture sessionID to check if this drag session is still active
                                // This prevents stale closures from clearing visuals after view dismissal
                                let capturedCoinID = coin.id
                                DispatchQueue.main.asyncAfter(deadline: .now() + 60.0) {
                                    // Only clear if this is still the same drag session
                                    guard favDragSessionID == sessionID, favDraggingID == capturedCoinID else { return }
                                    forceFavClearDragVisuals()
                                }
                                return NSItemProvider(object: coin.id as NSString)
                    }
                    // PERFORMANCE FIX: Removed duplicate buttonStyle and simultaneousGesture
                    // Button action already provides haptic feedback
                    .background(
                        Group {
                            if favRingActive && favRingRowID == coin.id {
                                LinearGradient(colors: [MarketGold.light.opacity(0.10), MarketGold.dark.opacity(0.06)], startPoint: .leading, endPoint: .trailing)
                                    .clipShape(FavoritesJoinedRingShape(leftInset: 12, cornerRadius: 8))
                            } else {
                                Color.clear
                            }
                        }
                    )
                    .overlay {
                        if favRingActive && favRingRowID == coin.id {
                            ZStack {
                                FavoritesJoinedRingStrokeShape(leftInset: 12, cornerRadius: 8, overlap: 1.3)
                                    .stroke(MarketGold.light.opacity(0.28), lineWidth: 4)
                                    .opacity(0.9)
                                FavoritesJoinedRingStrokeShape(leftInset: 12, cornerRadius: 8, overlap: 1.3)
                                    .stroke(LinearGradient(colors: [MarketGold.light, MarketGold.dark], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.4)
                                    .opacity(0.98)
                                FavoritesJoinedRingStrokeShape(leftInset: 12, cornerRadius: 8, overlap: 1.3)
                                    .inset(by: 1)
                                    .stroke(Color.black.opacity(0.45), lineWidth: 0.6)
                                Rectangle()
                                    .fill(LinearGradient(colors: [MarketGold.light.opacity(0.0), MarketGold.light.opacity(0.95), MarketGold.light.opacity(0.0)], startPoint: .leading, endPoint: .trailing))
                                    .opacity(0.35)
                                    .offset(x: favAnimatePulse ? 120 : -120)
                                    .animation(globalAnimationsKilled ? .none : .linear(duration: 0.9).repeatForever(autoreverses: false), value: favAnimatePulse)
                                    .mask(FavoritesJoinedRingStrokeShape(leftInset: 12, cornerRadius: 8, overlap: 1.3).stroke(lineWidth: 2))
                            }
                            .transaction { $0.animation = nil }
                            .allowsHitTesting(false)
                        }
                    }
                    .overlay(alignment: .leading) {
                        if favRingActive && favRingRowID == coin.id {
                            Rectangle()
                                .fill(LinearGradient(colors: [MarketGold.light.opacity(0.0), MarketGold.light.opacity(0.7), MarketGold.light.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                                .frame(width: 1.6)
                                .offset(x: 11.5)
                                .opacity(0.5)
                                .transaction { $0.animation = nil }
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay(alignment: .leading) {
                        if favIsDragging && favDraggingID == coin.id {
                            Capsule()
                                .fill(MarketGold.verticalGradient)
                                .frame(width: 3)
                                .padding(.vertical, 4)
                        }
                    }
                    .opacity((favIsDragging && favDraggingID == coin.id) ? 0.9 : 1.0)
                    .scaleEffect(1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.85), value: favDraggingID)
                    // Subtle divider line between rows
                    .overlay(alignment: .bottom) {
                        if idx < ordered.count - 1 && !favIsDragging {
                            Rectangle()
                                .fill(DS.Adaptive.divider)
                                .frame(height: 0.5)
                                .padding(.leading, MarketColumns.horizontalPadding + 36)
                        }
                    }
                    .onDrop(of: [UTType.plainText, UTType.text], delegate: FavoritesReorderDropDelegateV2(
                        targetID: coin.id,
                        localOrder: $favLocalOrder,
                        draggingID: $favDraggingID,
                        isDragging: $favIsDragging,
                        listResetKey: $favListResetKey,
                        dragHeartbeat: $favDragHeartbeat,
                        hoverTargetID: $favHoverTargetID,
                        hoverInsertAfter: $favHoverInsertAfter,
                        dragSessionID: $favDragSessionID,
                        onReorder: { ids in
                            FavoritesManager.shared.updateOrder(ids)
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            #endif
                        }
                    ))
                    // PERFORMANCE: Disable all animations on row for scroll smoothness
                    .transaction { $0.animation = nil }
                    .animation(.none, value: coin.id)
                }
            }
            .onDrop(of: [UTType.plainText, UTType.text], delegate: FavoritesEndDropDelegate(
                localOrder: $favLocalOrder,
                draggingID: $favDraggingID,
                isDragging: $favIsDragging,
                listResetKey: $favListResetKey,
                dragHeartbeat: $favDragHeartbeat,
                hoverTargetID: $favHoverTargetID,
                hoverInsertAfter: $favHoverInsertAfter,
                dragSessionID: $favDragSessionID,
                onReorder: { ids in
                    FavoritesManager.shared.updateOrder(ids)
                }
            ))
        }
        .id(favListResetKey)
        // DEAD CODE REMOVED: .shake(favShakeAttempts) - was never triggered
        .onAppear {
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                // Seed local order with current favorites
                let ids = base.map { $0.id }
                if favLocalOrder != ids { favLocalOrder = ids }
            }
        }
        .onChange(of: base.map { $0.id }) { _, ids in
            // Defer state modification to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                if favLocalOrder != ids { favLocalOrder = ids }
            }
        }
        .onChange(of: favIsDragging) { _, active in
            // Defer state modifications to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                if active {
                    favDragHeartbeat = Date()
                    startFavDragWatchdog()
                    guard !globalAnimationsKilled else { return }
                    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: true)) {
                        favAnimatePulse = true
                    }
                } else {
                    forceFavClearDragVisuals()
                }
            }
        }
        .onChange(of: favDraggingID) { _, newID in
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                if newID == nil {
                    forceFavClearDragVisuals()
                }
            }
        }
        .onDisappear {
            favRingClearTask?.cancel(); favRingClearTask = nil; forceFavClearDragVisuals()
        }
        .simultaneousGesture(TapGesture().onEnded {
            forceFavClearDragVisuals()
        })
    }

    // MARK: - Helpers
    private func headerButton(_ label: String, _ field: SortField) -> some View {
        let isDisabled = (vm.selectedSegment == .favorites)
        return Button {
            isSegmentSwitching = true
            // Manually toggle sort to avoid relying on a missing ViewModel API
            let currentField = vm.sortField
            if currentField == field {
                // Toggle direction when tapping the same field
                vm.sortDirection = (vm.sortDirection == .asc) ? .desc : .asc
            } else {
                // Switch field and default to descending for new field
                vm.sortField = field
                vm.sortDirection = .desc
            }
            applyFiltersImmediatelyNoAnimation()
            DispatchQueue.main.async {
                isSegmentSwitching = false
            }
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundColor(DS.Adaptive.textPrimary.opacity(0.95))
                if vm.sortField == field {
                    Image(systemName: vm.sortDirection == .asc ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary.opacity(0.8))
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .contentShape(Rectangle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1.0)
        .accessibilityHint(Text(isDisabled ? "Sorting is disabled in Favorites. Drag rows to reorder." : "Sort by \(label)"))
        .background(vm.sortField == field ? DS.Adaptive.overlay(0.05) : Color.clear)
    }

    private func coinsToDisplay() -> [MarketCoin] {
        // If user is searching, always return filteredCoins directly (bypass cache for responsive search)
        let isSearching = !vm.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isSearching {
            return vm.filteredCoins
        }
        
        // PERFORMANCE FIX: Use cached coins if available and recent (< 500ms)
        // This prevents expensive recomputation on every body evaluation
        if !cachedDisplayCoins.isEmpty && Date().timeIntervalSince(lastCoinsCacheAt) < 0.5 {
            return cachedDisplayCoins
        }
        
        // Not searching - return best available list
        let live = vm.filteredCoins
        if !live.isEmpty { return live }
        if case .success(let s) = vm.state, !s.isEmpty { return s }
        return vm.allCoins
    }
    
    /// PERFORMANCE FIX: Updates the cached display coins with debouncing
    /// Called from onReceive handler to coalesce rapid updates
    private func updateCachedDisplayCoins() {
        let isSearching = !vm.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isSearching {
            // Don't cache during search - need immediate updates
            return
        }
        
        let live = vm.filteredCoins
        let newCoins: [MarketCoin]
        if !live.isEmpty {
            newCoins = live
        } else if case .success(let s) = vm.state, !s.isEmpty {
            newCoins = s
        } else {
            newCoins = vm.allCoins
        }
        
        // Only update if meaningfully different (by count or first few IDs)
        let needsUpdate: Bool = {
            if cachedDisplayCoins.count != newCoins.count { return true }
            // Check first 5 coins for identity changes
            for i in 0..<min(5, cachedDisplayCoins.count) {
                if cachedDisplayCoins[i].id != newCoins[i].id { return true }
            }
            return false
        }()
        
        if needsUpdate {
            cachedDisplayCoins = newCoins
            lastCoinsCacheAt = Date()
        }
    }

    // MARK: - Favorites Drag Watchdog
    // MEMORY FIX: Use Timer.scheduledTimer which is properly managed by RunLoop.
    // The timer is invalidated in stopFavDragWatchdog() which is called by
    // forceFavClearDragVisuals() in onDisappear, ensuring cleanup.
    // PERFORMANCE FIX: Increased interval from 0.3s to 1.0s to reduce main thread work
    private func startFavDragWatchdog() {
        favDragWatchTimer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            // Check if still dragging and if heartbeat is stale
            guard favIsDragging else { return }
            let gap = Date().timeIntervalSince(favDragHeartbeat)
            if gap > 1.0 {
                forceFavClearDragVisuals()
            }
        }
        favDragWatchTimer = t
    }

    private func stopFavDragWatchdog() {
        favDragWatchTimer?.invalidate()
        favDragWatchTimer = nil
    }
    
    private func forceFavClearDragVisuals() {
        stopFavDragWatchdog()
        favIsDragging = false
        favDraggingID = nil
        favHoverTargetID = nil
        favHoverInsertAfter = false
        favAnimatePulse = false
        favDragSessionID = nil
        // Keep current favRingRowID and favRingActive so the highlight remains briefly.
        favRingClearTask?.cancel()
        let holdSeconds: Double = 0.8
        favRingClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(holdSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.15)) { favRingActive = false }
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            favRingRowID = nil
        }
    }

    var body: some View {
        ZStack {
            DS.Adaptive.background.ignoresSafeArea()
            VStack(spacing: 0) {
                segmentRow
                
                // Global market stats bar
                MarketStatsBar()
                
                // FIX: Status banners moved from .overlay(alignment: .top) into the VStack
                // so they push content down instead of overlapping the segment row and stats bar.
                if let liveDataStatusMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .foregroundColor(.orange)
                        Text(liveDataStatusMessage)
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textPrimary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.9)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(DS.Adaptive.cardBackgroundElevated)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(DS.Adaptive.strokeStrong, lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, MarketColumns.horizontalPadding)
                    .padding(.vertical, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if !isNetworkReachable {
                    HStack(spacing: 6) {
                        Image(systemName: "wifi.slash")
                            .foregroundColor(.orange)
                        Text("Offline — using cached data")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textPrimary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.9)
                        Button("Retry") {
                            Task { await vm.loadAllData() }
                        }
                        .font(.caption.bold())
                        .buttonStyle(.borderless)
                        .foregroundColor(DS.Adaptive.textPrimary.opacity(0.9))
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(DS.Adaptive.cardBackgroundElevated)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(DS.Adaptive.strokeStrong, lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, MarketColumns.horizontalPadding)
                    .padding(.vertical, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.22, dampingFraction: 0.9), value: isNetworkReachable)
                }
                
                if vm.showSearchBar {
                    HStack(spacing: 10) {
                        // Search icon
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(DS.Adaptive.textSecondary)
                        
                        // UIKit-backed text field for reliable keyboard focus
                        // SEARCH PERFORMANCE: Removed redundant onTextChange callback that was causing double updates
                        // The $vm.searchText binding already triggers didSet which handles search filtering
                        SearchTextField(
                            text: $vm.searchText,
                            placeholder: "Search coins...",
                            autoFocus: true, // Automatically focus when search bar appears
                            onTextChange: nil, // Binding handles updates - no callback needed
                            onSubmit: {
                                // Apply search immediately when search button is pressed
                                vm.performSearchFiltering()
                                // Dismiss keyboard
                                UIApplication.shared.dismissKeyboard()
                                isSearchFocused = false
                            },
                            onEditingChanged: { focused in
                                isSearchFocused = focused
                            }
                        )
                        .frame(height: 36)
                        
                        // Trailing buttons
                        let trimmed = vm.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                        let match = vm.allCoins.first(where: { $0.symbol.caseInsensitiveCompare(trimmed) == .orderedSame })?.symbol.uppercased()
                        
                        if let match {
                            Button {
                                #if os(iOS)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                #endif
                                pairsSheetSymbol = match
                                showPairsSheet = true
                            } label: {
                                Image(systemName: "chart.xyaxis.line")
                                    .font(.system(size: 14))
                                    .foregroundColor(.green)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("View pairs for \(match)"))
                        }
                        
                        if !vm.searchText.isEmpty {
                            Button {
                                vm.searchText = ""
                                applyFiltersImmediatelyNoAnimation()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(DS.Adaptive.textSecondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Clear search"))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(DS.Adaptive.chipBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(isSearchFocused ? DS.Adaptive.gold.opacity(0.5) : DS.Adaptive.stroke, lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, MarketColumns.horizontalPadding)
                    .padding(.bottom, 8)
                }
                // Active filter indicator chip (shows when category/sort filter is active)
                if hasActiveFilter {
                    activeFilterChip
                }
                coinList
            }
        }
        // PERFORMANCE FIX: Single hidden NavigationLink for programmatic navigation
        // This prevents SwiftUI from initializing ALL CoinDetailView destinations in ForEach
        // Navigation is triggered by setting selectedCoinForDetail state
        .navigationDestination(item: $selectedCoinForDetail) { coin in
            CoinDetailView(coin: coin)
        }
        .withBannerAd() // Show ads for free tier users
        .toolbar(.hidden, for: .navigationBar)
        // FIX: Status banners moved inline into VStack above (between MarketStatsBar and coinList)
        // to prevent overlapping the segment row. The old .overlay(alignment: .top) block was removed.
        .onAppear {
            // Essential work runs immediately (lightweight, guarded internally)
            startMonitoringIfNeeded()
            ensurePollingRunning()
            
            // Skip heavy initialization work on tab switches after first load
            guard !didInitialLoad else { return }
            didInitialLoad = true
            
            // ACCURACY FIX v23: Populate sparkline cache from CoinGecko data FIRST (fresh from Firestore).
            // The disk cache may contain stale Binance klines from a previous session showing
            // outdated trends. CoinGecko sparklineIn7d is updated in real-time via Firestore.
            Task.detached(priority: .utility) {
                // 1. Try CoinGecko data from MarketViewModel (fresh, authoritative)
                let geckoSparklines = await MainActor.run { () -> [String: [Double]] in
                    var result: [String: [Double]] = [:]
                    for coin in MarketViewModel.shared.allCoins {
                        let spark = coin.sparklineIn7d.filter { $0.isFinite && $0 > 0 }
                        if spark.count >= 10 {
                            result[coin.id] = spark
                        }
                    }
                    return result
                }
                
                // 2. Fall back to disk cache only for coins WITHOUT CoinGecko data
                let diskCache = WatchlistSparklineService.loadCachedSparklinesSync()
                
                await MainActor.run {
                    // Load CoinGecko data first (always fresh)
                    for (id, sparkline) in geckoSparklines {
                        self.marketSparklineCache[id] = sparkline
                    }
                    // Fill gaps with disk cache (stale Binance data, better than nothing)
                    for (id, sparkline) in diskCache where sparkline.count >= 10 {
                        if self.marketSparklineCache[id] == nil {
                            self.marketSparklineCache[id] = sparkline
                        }
                    }
                }
            }
            
            // Data loading - runs immediately without artificial delay
            Task {
                await vm.loadAllData()
                vm.applyAllFiltersAndSort()
                
                // Fetch Binance sparklines after a short delay to let UI settle
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                fetchBinanceSparklinesForVisibleCoins()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Defer state modifications to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                switch newPhase {
                case .active:
                    // APP LIFECYCLE FIX: Force refresh cached display coins to prevent blank areas
                    updateCachedDisplayCoins()
                    // PERFORMANCE v26: Don't call loadAllData() here - CryptoSageAIApp already
                    // handles foreground refresh with a 60s cooldown. Calling it from both
                    // CryptoSageAIApp AND MarketView causes duplicate API fetches.
                    ensurePollingRunning()
                case .inactive, .background:
                    // Pause live polling to reduce background work
                    stopPollingIfNeeded()
                @unknown default:
                    break
                }
            }
        }
        .onDisappear {
            if networkMonitorStarted {
                networkMonitor.cancel()
                networkMonitorStarted = false
            }
            stopPollingIfNeeded()
            filterDebounceTask?.cancel()
            filterDebounceTask = nil
        }
        // Derived usage publisher handler removed - banner was causing visual noise
        // .onReceive(LivePriceManager.shared.derivedUsagePublisher) { ... }
        .onReceive(NotificationCenter.default.publisher(for: .showPairsForSymbol)) { notif in
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                if let sym = notif.object as? String, !sym.isEmpty {
                    pairsSheetSymbol = sym.uppercased()
                    showPairsSheet = true
                }
            }
        }
        // PERFORMANCE FIX: Debounced update for cached display coins
        // This reduces re-renders by coalescing rapid filteredCoins updates
        .onReceive(vm.$filteredCoins.debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)) { _ in
            // Don't update during scroll to prevent jank
            guard !ScrollStateManager.shared.isScrolling else { return }
            updateCachedDisplayCoins()
        }
        .task {
            // PERFORMANCE FIX: Initialize cached display coins on first appear
            updateCachedDisplayCoins()
        }
        .sheet(isPresented: $showPairsSheet) {
            MarketPairsSheet(symbol: pairsSheetSymbol)
        }
        .sheet(isPresented: $showFilterSheet) {
            MarketFilterSheet(viewModel: vm)
        }
        // FIX v23: Replaced .onChange(of: appState.X) with targeted .onReceive handlers.
        // With AppState accessed via computed property (not @EnvironmentObject), the view
        // doesn't observe AppState's objectWillChange, so onChange never re-evaluates.
        // .onReceive directly subscribes to the specific @Published property publishers,
        // ensuring these handlers fire reliably without observing all 18+ AppState properties.
        .onReceive(AppState.shared.$marketNavPath) { newPath in
            if newPath.isEmpty && selectedCoinForDetail != nil {
                DispatchQueue.main.async {
                    selectedCoinForDetail = nil
                }
            }
        }
        .onReceive(AppState.shared.$dismissMarketSubviews) { shouldDismiss in
            if shouldDismiss && selectedCoinForDetail != nil {
                selectedCoinForDetail = nil
                DispatchQueue.main.async {
                    AppState.shared.dismissMarketSubviews = false
                }
            } else if shouldDismiss {
                DispatchQueue.main.async {
                    AppState.shared.dismissMarketSubviews = false
                }
            }
        }
    }
    
    // MARK: - Active Filter Chip
    private var activeFilterChip: some View {
        HStack(spacing: 8) {
            // Show active category if not "All"
            if vm.selectedCategory != .all {
                filterChipView(
                    icon: vm.selectedCategory.icon,
                    text: vm.selectedCategory.rawValue,
                    onRemove: { vm.selectedCategory = .all }
                )
            }
            
            // Show sort indicator if not default
            if vm.sortField != .marketCap || vm.sortDirection != .desc {
                let sortText = "\(vm.sortField.rawValue) \(vm.sortDirection == .asc ? "↑" : "↓")"
                filterChipView(
                    icon: "arrow.up.arrow.down",
                    text: sortText,
                    onRemove: {
                        vm.sortField = .marketCap
                        vm.sortDirection = .desc
                    }
                )
            }
            
            Spacer()
            
            // Clear all button
            Button {
                withAnimation {
                    vm.selectedCategory = .all
                    vm.sortField = .marketCap
                    vm.sortDirection = .desc
                }
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
            } label: {
                Text("Clear")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, MarketColumns.horizontalPadding)
        .padding(.vertical, 6)
        .background(DS.Adaptive.background)
    }
    
    private func filterChipView(icon: String, text: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption.weight(.medium))
            Button {
                withAnimation {
                    onRemove()
                }
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
            }
            // ACCESSIBILITY FIX: Add label for screen readers
            .accessibilityLabel("Remove \(text) filter")
        }
        .foregroundColor(DS.Adaptive.textPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(DS.Adaptive.chipBackground)
        )
    }

    // MARK: - Segment Row (chips + search, no overlap)
    private var segmentRow: some View {
        HStack(spacing: 8) {
            // Always scrollable chips so they never collide with the search icon
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(MarketSegment.allCases, id: \.id) { (seg: MarketSegment) in
                            let isSelected = (vm.selectedSegment == seg)
                            segmentChip(for: seg, isSelected: isSelected)
                        }
                    }
                    .padding(.leading, 2)
                    .padding(.trailing, 4)
                }
                .frame(height: 36)
                .onAppear {
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(vm.selectedSegment.id, anchor: .center)
                        }
                    }
                }
                .onChange(of: vm.selectedSegment) { _, newSeg in
                    // Defer state modification to avoid "Modifying state during view update"
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(newSeg.id, anchor: .center)
                        }
                    }
                }
            }

            // Filter and search buttons outside of the scroll view
            HStack(spacing: 4) {
                filterButton()
                searchToggleButton()
            }
        }
        .padding(.horizontal, MarketColumns.horizontalPadding)
        .padding(.top, 0)
        .padding(.bottom, 2)
        .background(DS.Adaptive.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DS.Adaptive.divider)
                .frame(height: hairline)
        }
        // Search text onChange moved to the TextField itself for reliable triggering
    }
}

private struct FavoritesReorderDropDelegateV2: DropDelegate {
    let targetID: String
    @Binding var localOrder: [String]
    @Binding var draggingID: String?
    @Binding var isDragging: Bool
    @Binding var listResetKey: UUID
    @Binding var dragHeartbeat: Date
    @Binding var hoverTargetID: String?
    @Binding var hoverInsertAfter: Bool
    @Binding var dragSessionID: UUID?
    let onReorder: ([String]) -> Void

    func dropEntered(info: DropInfo) {
        dragHeartbeat = Date()
        guard let from = draggingID else { return }
        guard targetID != from else {
            hoverTargetID = targetID
            hoverInsertAfter = false
            return
        }
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
        if isDragging && dragSessionID != nil {
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
            listResetKey = UUID()
            return false
        }
        onReorder(localOrder)
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        #endif
        // Reset all drag state
        draggingID = nil
        isDragging = false
        hoverTargetID = nil
        hoverInsertAfter = false
        listResetKey = UUID()

        return true
    }
    
    func dropEnded(info: DropInfo) {
        // Reset all drag state
        draggingID = nil
        isDragging = false
        hoverTargetID = nil
        hoverInsertAfter = false
        listResetKey = UUID()
    }
}

private struct FavoritesEndDropDelegate: DropDelegate {
    @Binding var localOrder: [String]
    @Binding var draggingID: String?
    @Binding var isDragging: Bool
    @Binding var listResetKey: UUID
    @Binding var dragHeartbeat: Date
    @Binding var hoverTargetID: String?
    @Binding var hoverInsertAfter: Bool
    @Binding var dragSessionID: UUID?
    let onReorder: ([String]) -> Void

    func dropExited(info: DropInfo) {
        hoverTargetID = nil
        hoverInsertAfter = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if isDragging && dragSessionID != nil {
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
            listResetKey = UUID()
            return false
        }
        onReorder(localOrder)
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        #endif
        // Reset all drag state
        draggingID = nil
        isDragging = false
        hoverTargetID = nil
        hoverInsertAfter = false
        listResetKey = UUID()

        return true
    }
    
    func dropEnded(info: DropInfo) {
        // Reset all drag state
        draggingID = nil
        isDragging = false
        hoverTargetID = nil
        hoverInsertAfter = false
        listResetKey = UUID()
    }
}

