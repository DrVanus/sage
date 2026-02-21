import SwiftUI
import UIKit


// Compact, professional Market Movers (Trending / Gainers / Losers)
struct TrendingSectionView: View {
    let coins: [MarketCoin]
    let maxItemsPerList: Int
    @Binding var selectedCoin: MarketCoin?

    @AppStorage("TrendingSection.SelectedTab") private var selectedTab: Int = 0
    // PERFORMANCE FIX v20: Removed @EnvironmentObject appState (18+ @Published)
    // Only used for dismissHomeSubviews - now accessed via AppState.shared
    
    // PERFORMANCE: Cached lists to avoid expensive recomputation during body evaluation
    @State private var cachedTrending: [MarketCoin] = []
    @State private var cachedGainers: [MarketCoin] = []
    @State private var cachedLosers: [MarketCoin] = []
    @State private var cachedDayChanges: [String: Double] = [:]
    @State private var cachedPrices: [String: Double] = [:]  // PERFORMANCE FIX: Cache prices to avoid singleton access in body
    @State private var lastCoinsHash: Int = 0
    
    // PERFORMANCE FIX: Debounce rapid coins.count updates to reduce MarketMovers spam
    @State private var lastCoinsCountUpdate: Date = .distantPast
    
    // PERFORMANCE FIX v2: Task handle to cancel previous updates when new one is triggered
    // This prevents the "[MarketMovers] Updated" spam - multiple sources (onAppear, onChange, Timer)
    // were triggering overlapping updates during startup
    @State private var updateTask: Task<Void, Never>? = nil
    @State private var startupSuppressionUntil: Date = Date().addingTimeInterval(20)

    init(coins: [MarketCoin], maxItemsPerList: Int = 5, selectedCoin: Binding<MarketCoin?> = .constant(nil)) {
        self.coins = coins
        self.maxItemsPerList = maxItemsPerList
        self._selectedCoin = selectedCoin
    }

    // MARK: - Helpers
    // Use canonical stablecoin detection from MarketCoin for consistency across app
    private func isStable(_ coin: MarketCoin) -> Bool {
        coin.isStable || MarketCoin.stableSymbols.contains(coin.symbol.uppercased())
    }

    private func currencyString(_ value: Double) -> String {
        Self.currencyFormatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    // Magnitude-aware price string for tiny assets
    // PERFORMANCE FIX: Cached formatters for sub-$1 prices to avoid creating a new
    // NumberFormatter on every call (was called once per card during body evaluation)
    private static let smallPriceFormatter4: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.usesGroupingSeparator = true
        f.minimumFractionDigits = 4; f.maximumFractionDigits = 4; return f
    }()
    private static let smallPriceFormatter5: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.usesGroupingSeparator = true
        f.minimumFractionDigits = 5; f.maximumFractionDigits = 5; return f
    }()
    private static let smallPriceFormatter6: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.usesGroupingSeparator = true
        f.minimumFractionDigits = 6; f.maximumFractionDigits = 6; return f
    }()
    private static let smallPriceFormatter8: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.usesGroupingSeparator = true
        f.minimumFractionDigits = 6; f.maximumFractionDigits = 8; return f
    }()
    
    private static func priceString(_ value: Double) -> String {
        let absV = abs(value)
        if absV >= 1.0 {
            return Self.currencyFormatter.string(from: NSNumber(value: value)) ?? "$0.00"
        }
        let f: NumberFormatter
        if absV >= 0.1 { f = smallPriceFormatter4 }
        else if absV >= 0.01 { f = smallPriceFormatter5 }
        else if absV >= 0.001 { f = smallPriceFormatter6 }
        else { f = smallPriceFormatter8 }
        let raw = f.string(from: NSNumber(value: value)) ?? "0"
        return "$" + raw
    }

    private func clampPercent(_ v: Double, limit: Double = 100) -> Double {
        guard v.isFinite else { return 0 }
        return max(-limit, min(limit, v))
    }

    // Derive a 24h percent change from 7d sparkline when provider value is missing
    private func derived24hChange(fromSparkline prices: [Double], anchorPrice: Double?) -> Double? {
        // Require an anchor to avoid mixing normalized (0..1) sparklines with USD prices
        guard let anchor = anchorPrice, anchor.isFinite, anchor > 0 else { return nil }
        let data = prices.filter { $0.isFinite && $0 > 0 }
        let n = data.count
        guard n >= 3 else { return nil }

        // Sanity check: recent window median should be in the same unit/magnitude as the anchor
        let windowCount = min(8, n)
        let recent = Array(data.suffix(windowCount))
        let sorted = recent.sorted()
        let median = sorted[windowCount/2]
        let unitRatio = max(median, anchor) / max(1e-9, min(median, anchor))
        // If the recent sparkline values are far from the anchor (e.g., normalized 0..1 vs USD 100+), bail out
        // Use 1.8 threshold for 24h (moderate - allows daily volatility)
        if unitRatio > 1.8 { return nil }

        // SMART STEP CALCULATION: Detect actual data coverage based on point count
        // Common sparkline formats:
        // - 168 points (140-200): Hourly data over 7 days
        // - 42 points (35-55): 4-hour intervals over 7 days
        // - 7 points (5-14): Daily data over 7 days
        let (estimatedTotalHours, stepHours): (Double, Double) = {
            if n >= 140 && n <= 200 {
                // Hourly data: ~168 points = 7 days, each step = 1 hour
                return (Double(n - 1), 1.0)
            } else if n >= 35 && n < 140 {
                // 4-hour interval data: ~42 points, each step = 4 hours
                return (Double(n - 1) * 4.0, 4.0)
            } else if n >= 5 && n < 35 {
                // Daily or sparse data: ~7 points, each step = 24 hours
                return (Double(n - 1) * 24.0, 24.0)
            } else {
                // Fallback: assume 7-day coverage (legacy behavior)
                let totalH = 24.0 * 7.0
                let step = totalH / Double(max(1, n - 1))
                return (totalH, step)
            }
        }()
        
        // Validate minimum coverage for 24h lookback (need at least 80% = 19.2 hours)
        if estimatedTotalHours < 19.2 { return nil }
        
        let lookbackSteps = max(1, Int(round(24.0 / stepHours)))
        let clamped = min(lookbackSteps, max(1, n - 1))
        let nominalIndex = max(0, (n - 1) - clamped)

        func findUsableIndex(around idx: Int, maxSteps: Int = 12) -> Int? {
            var step = 0
            while step <= maxSteps {
                let back = idx - step
                if back >= 0, data[back] > 0, data[back].isFinite { return back }
                step += 1
            }
            step = 1
            while step <= maxSteps {
                let fwd = idx + step
                if fwd < n, data[fwd] > 0, data[fwd].isFinite { return fwd }
                step += 1
            }
            return data.firstIndex(where: { $0 > 0 && $0.isFinite })
        }

        // Previous price ~24h ago from series; current price is the provided anchor
        guard let prevIdx = findUsableIndex(around: nominalIndex) else { return nil }
        let prev = data[prevIdx]
        guard prev > 0 else { return nil }
        let pct = ((anchor - prev) / prev) * 100.0
        if !pct.isFinite { return nil }
        // Clamp extreme outliers but don't reject entirely - sparklines can be noisy
        // FIX: Consistent ±300% limit across app for 24h changes
        return max(-300, min(300, pct))
    }

    private func dayChange(_ coin: MarketCoin) -> Double? {
        // CONSISTENCY FIX: Use LivePriceManager.bestChange24hPercent() as the single source of truth
        // This ensures all views (TrendingSectionView, WatchlistSection, CoinRowView, HomeView)
        // display the same 24h percentage for the same coin at the same time.
        //
        // LivePriceManager.bestChange24hPercent() internally handles the full fallback chain:
        // 1. Provider value (CoinGecko API)
        // 2. Sidecar cache (persisted to disk)
        // 3. Sparkline derivation (when no other source available)
        // 4. Binance 24h ticker fetch (async, for cache population)
        //
        // Using coin.best24hPercent accesses the same LivePriceManager method via the extension.
        if let best = coin.best24hPercent, best.isFinite {
            // Apply consistent ±300% clamp across all views
            return max(-300, min(300, best))
        }
        
        // Fallback: access LivePriceManager directly for coins that may not have
        // the extension property populated yet (e.g., newly fetched coins)
        if let lpm = LivePriceManager.shared.bestChange24hPercent(for: coin), lpm.isFinite {
            return max(-300, min(300, lpm))
        }

        // No change data available - return nil (don't fake 0% which would pollute gainers/losers)
        return nil
    }

    private func bestVolumeUSD(for coin: MarketCoin) -> Double? {
        if let v = coin.totalVolume, v.isFinite, v > 0 { return v }
        return LivePriceManager.shared.bestVolumeUSD(for: coin)
    }

    private static let currencyFormatter: NumberFormatter = {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = CurrencyManager.currencyCode
        nf.maximumFractionDigits = 2
        nf.minimumFractionDigits = 2
        return nf
    }()

    // Filter low-signal entries and stables
    // PRICE CONSISTENCY FIX: Use bestPrice() for consistent price checking
    private var filteredCoins: [MarketCoin] {
        coins.filter { coin in
            guard !isStable(coin) else { return false }
            // Use bestPrice() for consistency, fallback to coin.priceUsd
            let price = MarketViewModel.shared.bestPrice(for: coin.id) ?? coin.priceUsd ?? 0
            guard price > 0 else { return false }
            // Accept coins even without volume data (Coinbase may not provide it)
            if let vol = bestVolumeUSD(for: coin) { return vol >= 100_000 }
            return true // Allow coins without volume data
        }
    }

    // Relaxation steps to ensure we show enough items even on quieter markets
    // Start with no volume requirement since Coinbase data may lack volume
    private let volumeRelaxationSteps: [Double] = [0, 50_000, 250_000, 1_000_000]

    // Same filter as above, parameterized by a minimum USD volume
    // PRICE CONSISTENCY FIX: Use bestPrice() for consistent price checking
    private func filteredCoins(minVolume: Double) -> [MarketCoin] {
        coins.filter { coin in
            guard !isStable(coin) else { return false }
            // Use bestPrice() for consistency, fallback to coin.priceUsd
            let price = MarketViewModel.shared.bestPrice(for: coin.id) ?? coin.priceUsd ?? 0
            guard price > 0 else { return false }
            // If no volume requirement, accept all non-stable coins with valid price
            if minVolume <= 0 { return true }
            // Accept coins without volume data when requirements are low
            if let vol = bestVolumeUSD(for: coin) { return vol >= minVolume }
            return minVolume <= 50_000 // Accept coins without volume if threshold is low
        }
    }

    private func trending(from source: [MarketCoin]) -> [MarketCoin] {
        source
            .compactMap { c -> (MarketCoin, Double)? in
                // CRITICAL: Only include coins that ACTUALLY have percentage data.
                // Coins with nil dayChange should be excluded — not treated as 0%.
                // Showing coins at 0% makes the section look broken.
                guard let ch = dayChange(c), abs(ch) > 0.001 else { return nil }
                let vol = bestVolumeUSD(for: c) ?? 10_000
                let score = abs(ch) * log10(max(vol, 10_000))
                return (c, score)
            }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }

    private func buildTrending() -> [MarketCoin] {
        for step in volumeRelaxationSteps {
            let list = Array(trending(from: filteredCoins(minVolume: step)).prefix(maxItemsPerList))
            if list.count >= min(3, maxItemsPerList) { return list }
        }
        return Array(trending(from: filteredCoins(minVolume: 0)).prefix(maxItemsPerList))
    }

    private func buildGainers() -> [MarketCoin] {
        for step in volumeRelaxationSteps {
            let pool = filteredCoins(minVolume: step)
            let positives = pool
                .map { ($0, dayChange($0) ?? 0) }
                .filter { $0.1 > 0 }
                .sorted { $0.1 > $1.1 }
                .map { $0.0 }
            if !positives.isEmpty { return Array(positives.prefix(maxItemsPerList)) }
        }
        return []
    }

    private func buildLosers() -> [MarketCoin] {
        for step in volumeRelaxationSteps {
            let pool = filteredCoins(minVolume: step)
            let negatives = pool
                .map { ($0, dayChange($0) ?? 0) }
                .filter { $0.1 < 0 }
                .sorted { $0.1 < $1.1 }
                .map { $0.0 }
            if !negatives.isEmpty { return Array(negatives.prefix(maxItemsPerList)) }
        }
        return []
    }
    
    // MARK: - Minimum Guarantee Builders
    // Ensure at least minCoins appear even when data is incomplete
    
    /// Build gainers list - ONLY coins with STRICTLY POSITIVE change (> 0)
    /// Better to show fewer correct coins than wrong data
    private func buildGainersWithMinimum() -> [MarketCoin] {
        // Start with strictest volume filter, then relax progressively
        for step in volumeRelaxationSteps {
            let pool = filteredCoins(minVolume: step)
            let positives = pool
                .compactMap { coin -> (MarketCoin, Double)? in
                    guard let change = dayChange(coin), change > 0.01 else { return nil } // > 0.01% to avoid near-zero
                    return (coin, change)
                }
                .sorted { $0.1 > $1.1 }  // Highest gains first
                .prefix(maxItemsPerList)
                .map { $0.0 }
            
            // Return as soon as we have at least 1 gainer
            if !positives.isEmpty {
                return Array(positives)
            }
        }
        
        // No gainers found at all - return empty (better than showing wrong data)
        #if DEBUG
        print("[MarketMovers] WARNING: No gainers found in pool of \(coins.count) coins")
        #endif
        return []
    }
    
    /// Build losers list - ONLY coins with STRICTLY NEGATIVE change (< 0)
    /// Better to show fewer correct coins than wrong data
    private func buildLosersWithMinimum() -> [MarketCoin] {
        // Start with strictest volume filter, then relax progressively
        for step in volumeRelaxationSteps {
            let pool = filteredCoins(minVolume: step)
            let negatives = pool
                .compactMap { coin -> (MarketCoin, Double)? in
                    guard let change = dayChange(coin), change < -0.01 else { return nil } // < -0.01% to avoid near-zero
                    return (coin, change)
                }
                .sorted { $0.1 < $1.1 }  // Most negative first (biggest losers)
                .prefix(maxItemsPerList)
                .map { $0.0 }
            
            // Return as soon as we have at least 1 loser
            if !negatives.isEmpty {
                return Array(negatives)
            }
        }
        
        // No losers found at all - return empty (better than showing wrong data)
        #if DEBUG
        print("[MarketMovers] WARNING: No losers found in pool of \(coins.count) coins")
        #endif
        return []
    }

    /// Lightweight hash that changes when percentage data first becomes available on coins.
    /// Used to detect when CoinGecko 24h% data arrives (coin count stays the same but
    /// priceChangePercentage24hInCurrency goes from nil to a real value).
    private var percentageDataHash: Int {
        var h = Hasher()
        // Only check the first 10 coins to keep this cheap
        for coin in coins.prefix(10) {
            h.combine(coin.priceChangePercentage24hInCurrency != nil)
        }
        return h.finalize()
    }
    
    // PERFORMANCE: Use cached lists instead of recomputing on every body evaluation
    private var currentList: [MarketCoin] {
        switch selectedTab {
        case 0: return cachedTrending
        case 1: return cachedGainers
        case 2: return cachedLosers
        default: return []
        }
    }
    
    // Get cached day change for a coin (avoids recomputation)
    private func cachedDayChange(for coin: MarketCoin) -> Double {
        cachedDayChanges[coin.id] ?? 0
    }
    
    // PERFORMANCE FIX: Get cached price for a coin (avoids singleton access in body)
    private func cachedPrice(for coin: MarketCoin) -> Double? {
        cachedPrices[coin.id] ?? coin.priceUsd
    }
    
    // Recompute all cached lists when coins change
    // PERFORMANCE FIX v8: Initial load is truly synchronous (no Task), updates are async
    private func updateCachedLists(force: Bool = false) {
        // STARTUP RACE FIX: Avoid computing movers against an empty pool.
        // During startup, this produced noisy logs like:
        // "No gainers found in pool of 0 coins" before the first real 250-coin payload arrived.
        guard !coins.isEmpty else {
            updateTask?.cancel()
            return
        }
        // JANK FIX: During startup, skip heavy movers recompute until we have enough coin coverage.
        if !force, Date() < startupSuppressionUntil, coins.count < 80 {
            return
        }

        // PERFORMANCE FIX v8: Check for initial load FIRST, before any other processing
        // This ensures we populate the UI immediately on first call
        let needsInitialLoad = cachedTrending.isEmpty && cachedGainers.isEmpty && cachedLosers.isEmpty
        
        if needsInitialLoad && !coins.isEmpty {
            // PERFORMANCE FIX v18: Changed from SYNCHRONOUS to ASYNC initial load
            // The previous sync load blocked the first frame render while processing 250 coins
            // (buildTrending/Gainers/Losers iterate ALL coins with sorting).
            // Now we only do a minimal sync setup and defer the heavy work.
            
            // FIX: Check if coins ACTUALLY have percentage data before showing them.
            // Previously we showed the first 6 coins as placeholders, but they had nil
            // percentage data, so users saw "0.00%" for 2 minutes until the timer refreshed.
            var dayChanges: [String: Double] = [:]
            var prices: [String: Double] = [:]
            var quickTrending: [MarketCoin] = []
            
            for coin in coins.prefix(50) {
                if let change = dayChange(coin), abs(change) > 0.001 {
                    dayChanges[coin.id] = change
                    if let p = MarketViewModel.shared.bestPrice(for: coin.id) ?? coin.priceUsd {
                        prices[coin.id] = p
                    }
                    quickTrending.append(coin)
                    if quickTrending.count >= maxItemsPerList { break }
                }
            }
            
            cachedDayChanges = dayChanges
            cachedPrices = prices
            
            // Only show coins that actually have percentage data — otherwise keep showing
            // the placeholder/redacted view (shimmer), which is much better than "0.00%"
            if !quickTrending.isEmpty {
                cachedTrending = quickTrending
            }
            // else: leave cachedTrending empty → placeholder shimmer stays visible until data arrives
            
            #if DEBUG
            print("[MarketMovers] Initial load (quick) - \(quickTrending.count) coins with real % data (of \(coins.count) total)")
            #endif
            
            // Immediately schedule the full computation async (runs after first frame renders)
            let coinsSnapshot = coins
            updateTask = Task { @MainActor in
                // Tiny yield to let the first frame render
                await Task.yield()
                
                var fullDayChanges: [String: Double] = [:]
                var fullPrices: [String: Double] = [:]
                for coin in coinsSnapshot {
                    if let change = self.dayChange(coin) {
                        fullDayChanges[coin.id] = change
                    }
                    if let p = MarketViewModel.shared.bestPrice(for: coin.id) ?? coin.priceUsd {
                        fullPrices[coin.id] = p
                    }
                }
                
                self.cachedDayChanges = fullDayChanges
                self.cachedPrices = fullPrices
                self.cachedTrending = self.buildTrending()
                self.cachedGainers = self.buildGainersWithMinimum()
                self.cachedLosers = self.buildLosersWithMinimum()
                
                // If the initial quick load had no data (% not ready), schedule a fast retry
                if quickTrending.isEmpty && self.cachedTrending.isEmpty {
                    self.schedulePercentageRetry()
                }
                
                #if DEBUG
                print("[MarketMovers] Initial load (async) - Input: \(coinsSnapshot.count), Trending: \(self.cachedTrending.count), Gainers: \(self.cachedGainers.count), Losers: \(self.cachedLosers.count)")
                #endif
            }
            return
        }
        
        // For subsequent updates, use hash check and async Task
        var hasher = Hasher()
        hasher.combine(coins.count)
        for coin in coins.prefix(30) {
            hasher.combine(coin.id)
            hasher.combine(Int((coin.priceUsd ?? 0) * 100))
            hasher.combine(Int((coin.priceChangePercentage24hInCurrency ?? 0) * 100))
        }
        let newHash = hasher.finalize()
        
        guard force || newHash != lastCoinsHash else { return }
        lastCoinsHash = newHash
        
        // Cancel any in-flight update
        updateTask?.cancel()
        
        // Capture coins for async processing
        let coinsSnapshot = coins
        
        // PERFORMANCE FIX v17: Skip updates during scroll to prevent main thread blocking
        // MarketMovers processing 423 coins causes significant main thread work
        if ScrollStateManager.shared.shouldBlockHeavyOperation() {
            return
        }
        
        updateTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
            
            // PERFORMANCE FIX v17: Yield to the run loop periodically during heavy processing
            // This prevents the main thread from being blocked for too long
            var dayChanges: [String: Double] = [:]
            var prices: [String: Double] = [:]
            for (index, coin) in coinsSnapshot.enumerated() {
                if Task.isCancelled { return }
                // FIX: Only store actual percentage values, not nil → 0 conversions.
                // Coins with nil dayChange should NOT appear in trending/gainers/losers.
                if let change = self.dayChange(coin) {
                    dayChanges[coin.id] = change
                }
                if let p = MarketViewModel.shared.bestPrice(for: coin.id) ?? coin.priceUsd {
                    prices[coin.id] = p
                }
                // Yield every 50 coins to let the run loop process events (scroll, gestures)
                if index > 0 && index % 50 == 0 {
                    await Task.yield()
                    // If scroll started during processing, abort
                    if ScrollStateManager.shared.shouldBlockHeavyOperation() { return }
                }
            }
            
            guard !Task.isCancelled else { return }
            
            self.cachedDayChanges = dayChanges
            self.cachedPrices = prices
            self.cachedTrending = self.buildTrending()
            self.cachedGainers = self.buildGainersWithMinimum()
            self.cachedLosers = self.buildLosersWithMinimum()
            
            #if DEBUG
            print("[MarketMovers] Updated (async) - Input: \(coinsSnapshot.count), Trending: \(self.cachedTrending.count), Gainers: \(self.cachedGainers.count), Losers: \(self.cachedLosers.count)")
            #endif
        }
    }

    // MARK: - Fast Retry for Missing Percentage Data
    // When the initial load finds no coins with percentage data (CoinGecko hasn't
    // delivered 24h changes yet), retry quickly instead of waiting for the 60s timer.
    // Retries at 3s, 6s, 12s until data appears or 3 attempts pass.
    private func schedulePercentageRetry() {
        Task { @MainActor in
            for delay in [3, 6, 12] as [UInt64] {
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                guard !Task.isCancelled else { return }
                // Check if data has arrived
                let hasData = !cachedTrending.isEmpty && cachedDayChanges.values.contains(where: { abs($0) > 0.001 })
                if hasData { return } // Already populated, no retry needed
                
                #if DEBUG
                print("[MarketMovers] Percentage retry after \(delay)s — re-computing lists")
                #endif
                updateCachedLists(force: true)
            }
        }
    }
    
    @Environment(\.colorScheme) private var colorScheme
    
    // MARK: - Tab Data
    private struct TabItem: Identifiable {
        let id: Int
        let title: String
    }
    
    private var tabItems: [TabItem] {
        [TabItem(id: 0, title: "Trending"),
         TabItem(id: 1, title: "Gainers"),
         TabItem(id: 2, title: "Losers")]
    }
    
    // MARK: - Segment Button
    @ViewBuilder
    private func segmentButton(for tab: TabItem) -> some View {
        let isSelected = selectedTab == tab.id
        let isDark = colorScheme == .dark
        let textColor: Color = isSelected ? TintedChipStyle.selectedText(isDark: isDark) : DS.Adaptive.textSecondary
        
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                selectedTab = tab.id
            }
        } label: {
            Text(tab.title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundColor(textColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(segmentBackground(isSelected: isSelected, isDark: isDark))
                .clipShape(Capsule())
                .overlay(
                    isSelected ?
                    Capsule().stroke(
                        LinearGradient(
                            colors: isDark
                                ? [BrandColors.goldLight.opacity(0.35), BrandColors.goldBase.opacity(0.1)]
                                : [BrandColors.silverBase.opacity(0.3), BrandColors.silverDark.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    ) : nil
                )
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func segmentBackground(isSelected: Bool, isDark: Bool) -> some View {
        if isSelected {
            ZStack {
                TintedChipStyle.selectedBackground(isDark: isDark)
                LinearGradient(
                    colors: [Color.white.opacity(isDark ? 0.15 : 0.6), Color.white.opacity(0)],
                    startPoint: .top,
                    endPoint: .center
                )
            }
        } else {
            Color.clear
        }
    }
    
    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                GoldHeaderGlyph(systemName: "chart.line.uptrend.xyaxis")
                
                Text("Market Movers")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.Adaptive.textPrimary)
                
                Spacer(minLength: 8)
                
                // Custom segmented control with adaptive colors
                HStack(spacing: 2) {
                    ForEach(tabItems) { tab in
                        segmentButton(for: tab)
                    }
                }
                .padding(2)
                .background(
                    ZStack {
                        Capsule().fill(DS.Adaptive.chipBackground)
                        Capsule().fill(
                            LinearGradient(
                                colors: [Color.white.opacity(colorScheme == .dark ? 0.06 : 0.35), Color.white.opacity(0)],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                    }
                )
                .overlay(
                    Capsule().stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(0.15), Color.white.opacity(0.05)]
                                : [Color.black.opacity(0.08), Color.black.opacity(0.03)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
                )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .overlay(
                Rectangle()
                    .fill(DS.Adaptive.divider)
                    .frame(height: 0.5),
                alignment: .bottom
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    if currentList.isEmpty {
                        ForEach(0..<max(3, maxItemsPerList), id: \.self) { _ in
                            CoinCardPlaceholderView()
                        }
                        .redacted(reason: .placeholder)
                    } else {
                        ForEach(currentList, id: \.id) { coin in
                            CoinCardView(coin: coin, change24h: cachedDayChange(for: coin), cachedPrice: cachedPrice(for: coin), onTap: {
                                selectedCoin = coin
                            })
                        }
                    }
                }
                .padding(.leading, 8)
                .padding(.trailing, 16)
                // PERFORMANCE FIX: Stabilized .id() to only change on tab switch, not data count.
                // Including currentList.count was forcing entire view recreation on every data update,
                // causing scroll jank and unnecessary re-renders.
                .id(selectedTab)
                .animation(.spring(response: 0.35, dampingFraction: 0.9), value: selectedTab)
            }
            .frame(height: 60)
            .overlay(EdgeFadeOverlay().allowsHitTesting(false))
        }
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(DS.Adaptive.stroke, lineWidth: 1)
                )
        )
        // No card-level gold bar - individual coin cards have gold bars instead
        // Navigation destination is hosted in HomeView (outside lazy containers).
        // Dismiss CoinDetailView when home button is tapped (pop-to-root)
        .onReceive(AppState.shared.$dismissHomeSubviews) { shouldDismiss in
            if shouldDismiss && selectedCoin != nil {
                selectedCoin = nil
                // Reset the trigger after handling
                DispatchQueue.main.async {
                    AppState.shared.dismissHomeSubviews = false
                }
            }
        }
        .onAppear {
            startupSuppressionUntil = Date().addingTimeInterval(20)
            // PERFORMANCE FIX: Load Market Movers immediately on appear
            // The data is already cached from MarketViewModel, so no delay needed
            // Previous debounce caused perceived lag - better to show data right away
            updateCachedLists()
        }
        .onChange(of: coins.count) { _, newCount in
            // PERFORMANCE FIX v9: Skip ALL updates if we already have data and are scrolling
            let hasData = !cachedTrending.isEmpty || !cachedGainers.isEmpty || !cachedLosers.isEmpty
            if hasData && ScrollStateManager.shared.shouldBlockHeavyOperation() { return }
            
            // PERFORMANCE FIX v9: Increased debounce to 5s to reduce update spam
            // MarketMovers doesn't need real-time updates - periodic is fine
            let now = Date()
            if hasData && now.timeIntervalSince(lastCoinsCountUpdate) <= 5.0 { return }
            lastCoinsCountUpdate = now
            
            // Refresh cached lists when coins change
            DispatchQueue.main.async {
                self.updateCachedLists()
            }
        }
        // FIX: Also listen for percentage data arriving.
        // coins.count doesn't change when CoinGecko % data populates — but the hash of
        // first few coins' priceChangePercentage24h does. This triggers a quick refresh
        // so users don't see 0% for minutes while waiting on the 60s timer.
        .onChange(of: percentageDataHash) { _, _ in
            // Only trigger if we currently have no real percentage data
            let hasRealData = cachedDayChanges.values.contains(where: { abs($0) > 0.001 })
            if hasRealData { return }
            DispatchQueue.main.async {
                self.updateCachedLists(force: true)
            }
        }
        // Periodic refresh to ensure lists update with live price/change data
        // PERFORMANCE FIX v19: Changed .common to .default - timer pauses during scroll
        // FIX: Reduced from 120s to 60s — 2 minutes was too long to show stale/0% data
        .onReceive(Timer.publish(every: 60, on: .main, in: .default).autoconnect()) { _ in
            let hasData = !cachedTrending.isEmpty || !cachedGainers.isEmpty || !cachedLosers.isEmpty
            if hasData && ScrollStateManager.shared.shouldBlockHeavyOperation() { return }
            updateCachedLists(force: true)
        }
        // Haptic feedback and conditional refresh when tab changes
        .onChange(of: selectedTab) { _, _ in
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                // Force refresh if any list appears stale
                if cachedTrending.isEmpty || cachedGainers.isEmpty || cachedLosers.isEmpty {
                    updateCachedLists(force: true)
                }
            }
        }
    }

    // MARK: - Card
    // PERFORMANCE FIX: Accept price as parameter to avoid MarketViewModel.shared access in body
    private struct CoinCardView: View {
        let coin: MarketCoin
        let change24h: Double
        let cachedPrice: Double?  // PERFORMANCE: Passed from parent to avoid singleton access in body
        let onTap: () -> Void
        
        @Environment(\.colorScheme) private var colorScheme

        private var symbol: String { coin.symbol.uppercased() }
        private var isDark: Bool { colorScheme == .dark }

        private var dayChangeColor: Color {
            if abs(change24h) < 0.005 { return DS.Adaptive.textSecondary }
            return change24h >= 0 ? .green : .red
        }

        private func percentString(_ v: Double) -> String {
            if !v.isFinite { return "—" }
            // FIX: Defensive clamp to ±300% for consistent display
            let clamped = max(-300, min(300, v))
            let epsilon = 0.005
            if abs(clamped) < epsilon { return "0.00%" }
            let sign = clamped >= 0 ? "+" : "-"
            return String(format: "%@%.2f%%", sign, abs(clamped))
        }

        private var accessibilityLabelText: String {
            let priceText: String
            // PERFORMANCE FIX: Use cached price passed from parent instead of singleton access
            if let price = cachedPrice ?? coin.priceUsd {
                priceText = TrendingSectionView.currencyFormatter.string(from: NSNumber(value: price)) ?? "$0.00"
            } else {
                priceText = "price unavailable"
            }
            let changeText: String = {
                return percentString(change24h)
            }()
            return "\(symbol), \(priceText), \(changeText)"
        }

        var body: some View {
            Button(action: {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                onTap()
            }) {
                HStack(spacing: 6) {
                    CoinImageView(symbol: coin.symbol, url: coin.imageUrl, size: 28)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(symbol)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .allowsTightening(true)
                        // PERFORMANCE FIX: Use cached price passed from parent instead of singleton access
                        if let price = cachedPrice ?? coin.priceUsd {
                            Text(TrendingSectionView.priceString(price))
                                .font(.footnote.monospacedDigit())
                                .foregroundColor(DS.Adaptive.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .allowsTightening(true)
                        } else {
                            Text("—")
                                .font(.footnote.monospacedDigit())
                                .foregroundColor(DS.Adaptive.textTertiary)
                        }
                    }

                    Spacer(minLength: 4)

                    // Percentage change badge - clean and compact
                    Text(percentString(change24h))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .lineLimit(1)
                        .foregroundColor(dayChangeColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(abs(change24h) < 0.005 ? DS.Adaptive.chipBackground : dayChangeColor.opacity(0.15))
                        )
                        .fixedSize()
                }
                .padding(.leading, 10)  // Extra left padding for gold bar
                .padding(.trailing, 8)
                .padding(.vertical, 8)
                .frame(height: 60)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(DS.Adaptive.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(DS.Adaptive.stroke, lineWidth: 1)
                        )
                )
                // Gold bar accent on left edge
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    BrandColors.goldLight.opacity(isDark ? 0.75 : 0.65),
                                    BrandColors.goldBase.opacity(isDark ? 0.55 : 0.45)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 3)
                        .padding(.vertical, 10)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabelText)
        }
    }

    // MARK: - Placeholder Card
    private struct CoinCardPlaceholderView: View {
        var body: some View {
            HStack(spacing: 8) {
                Circle()
                    .fill(DS.Adaptive.strokeStrong)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(DS.Adaptive.strokeStrong)
                        .frame(width: 40, height: 10)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(DS.Adaptive.stroke)
                        .frame(width: 60, height: 9)
                }
                Spacer(minLength: 8)
                RoundedRectangle(cornerRadius: 10)
                    .fill(DS.Adaptive.stroke)
                    .frame(width: 56, height: 22)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(height: 60)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.Adaptive.chipBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(DS.Adaptive.stroke, lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Edge Fade Overlay
    // Adaptive edge fade for scroll indicators
    private struct EdgeFadeOverlay: View {
        @Environment(\.colorScheme) private var colorScheme
        var body: some View {
            GeometryReader { geo in
                let fadeColor = colorScheme == .dark ? Color.black : Color.white
                HStack {
                    LinearGradient(
                        colors: [fadeColor.opacity(0.6), fadeColor.opacity(0.0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: min(24, geo.size.width * 0.06))
                    Spacer()
                    LinearGradient(
                        colors: [fadeColor.opacity(0.0), fadeColor.opacity(0.6)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: min(24, geo.size.width * 0.06))
                }
                .ignoresSafeArea()
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

#if DEBUG
struct TrendingSectionView_Previews: PreviewProvider {
    static func makeCoin(id: String, symbol: String, name: String, price: Double, change24h: Double?, volume: Double?) -> MarketCoin {
        return MarketCoin(
            id: id,
            symbol: symbol,
            name: name,
            imageUrl: nil,
            priceUsd: price,
            marketCap: nil,
            totalVolume: volume,
            priceChangePercentage1hInCurrency: nil,
            priceChangePercentage24hInCurrency: change24h,
            priceChangePercentage7dInCurrency: nil,
            sparklineIn7d: [],
            marketCapRank: nil,
            maxSupply: nil,
            circulatingSupply: nil,
            totalSupply: nil
        )
    }

    static var previews: some View {
        let coins: [MarketCoin] = [
            makeCoin(id: "bitcoin", symbol: "BTC", name: "Bitcoin", price: 30500, change24h: 3.5, volume: 2_000_000_000),
            makeCoin(id: "ethereum", symbol: "ETH", name: "Ethereum", price: 1900, change24h: 5.2, volume: 1_500_000_000),
            makeCoin(id: "dogecoin", symbol: "DOGE", name: "Dogecoin", price: 0.06, change24h: -2.0, volume: 500_000_000),
            makeCoin(id: "solana", symbol: "SOL", name: "Solana", price: 20.5, change24h: -1.1, volume: 1_200_000_000),
            makeCoin(id: "cardano", symbol: "ADA", name: "Cardano", price: 0.35, change24h: 0.6, volume: 900_000_000)
        ]

        ZStack {
            Color.black.ignoresSafeArea()
            TrendingSectionView(coins: coins)
                .padding()
                .preferredColorScheme(.dark)
        }
        .frame(height: 140)
    }
}
#endif























