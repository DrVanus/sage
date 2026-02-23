import SwiftUI

// MARK: - Portfolio Display Mode
/// Determines which data source to display in the portfolio section
enum PortfolioDisplayMode {
    case paperTrading  // Paper Trading mode active - show virtual trading portfolio
    case demo          // Demo mode active - show sample portfolio data
    case live          // Real portfolio with actual holdings
    case empty         // No holdings and no special mode active
}

// MARK: - AnimatedPortfolioValue
/// A portfolio value display that smoothly animates between value changes.
/// Uses spring animation for natural-feeling transitions with subtle scale effects.
private struct AnimatedPortfolioValue: View {
    let value: Double
    let hideBalances: Bool
    
    @State private var displayedValue: Double = 0
    @State private var scaleEffect: CGFloat = 1.0
    @State private var lastValue: Double = 0
    @State private var appearTime: Date = .distantPast
    @State private var lastAnimationAt: Date = .distantPast
    @State private var glowOpacity: Double = 0
    @State private var glowColor: Color = .green
    
    // Rate limiting to prevent jitter - faster intervals for snappier feel
    private let minUpdateInterval: TimeInterval = 0.4
    private let coldStartDuration: TimeInterval = 0.6
    
    // PERFORMANCE FIX: Track last onChange time to prevent "tried to update multiple times per frame"
    @State private var lastOnChangeAt: Date = .distantPast
    
    var body: some View {
        Text(hideBalances ? "••••••" : formatValue(displayedValue))
            .font(.system(size: 32, weight: .bold, design: .rounded))
            .foregroundStyle(DS.Adaptive.textPrimary)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .allowsTightening(true)
            .scaleEffect(scaleEffect)
            .onAppear {
                DispatchQueue.main.async {
                    appearTime = Date()
                    if value > 0 {
                        displayedValue = value
                        lastValue = value
                    }
                }
            }
            .onChange(of: value) { _, newValue in
                guard newValue > 0 else { return }
                
                // STARTUP FIX v25: Allow significant price corrections during startup.
                // Previously, isInGlobalStartupPhase() blocked ALL onChange updates for 4 seconds,
                // which prevented the portfolio from showing correct prices when fresh data arrived.
                // Now: if the value changed by >1% (a meaningful correction, not jitter), allow it through.
                let startupCorrection: Bool = {
                    guard lastValue > 0 else { return true } // First real value always allowed
                    let pct = abs(newValue - lastValue) / lastValue
                    return pct > 0.01 // >1% change = meaningful correction, not animation jitter
                }()
                
                if isInGlobalStartupPhase() && !startupCorrection {
                    return // Only skip trivial updates during startup
                }
                
                // PERFORMANCE FIX v2: Skip during scroll OR initialization phase
                guard !ScrollStateManager.shared.shouldBlockHeavyOperation() || startupCorrection else { return }
                
                // PERFORMANCE FIX v2: Increased throttle from 16ms to 100ms
                let now = Date()
                guard now.timeIntervalSince(lastOnChangeAt) > 0.1 || startupCorrection else { return }
                lastOnChangeAt = now
                
                // Defer state modifications to avoid "Modifying state during view update"
                DispatchQueue.main.async {
                    let now = Date()
                    let isColdStart = now.timeIntervalSince(appearTime) < coldStartDuration
                    let tooSoon = now.timeIntervalSince(lastAnimationAt) < minUpdateInterval
                    
                    // Calculate change significance
                    let delta = abs(newValue - lastValue)
                    let pctChange = delta / max(lastValue, 1e-9)
                    
                    // Only animate if change is significant (>0.01% change)
                    // STARTUP FIX: During cold start, skip animation but still update the value
                    let shouldAnimate = !isColdStart && !tooSoon && pctChange > 0.0001
                    
                    if shouldAnimate {
                        // Determine if gain or loss for glow color
                        let isGain = newValue > lastValue
                        let newGlowColor: Color = isGain ? .green : .red
                        
                        // Haptic feedback for significant portfolio value changes (>0.5%)
                        #if os(iOS)
                        if pctChange > 0.005 {
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        }
                        #endif
                        
                        // Quick spring animation for snappy, professional feel
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                            displayedValue = newValue
                            // Subtle scale pulse
                            scaleEffect = pctChange > 0.01 ? 1.018 : 1.01
                            // Win/loss glow pulse - more intense for larger changes
                            glowColor = newGlowColor
                            glowOpacity = pctChange > 0.001 ? 0.45 : 0.25
                        }
                        
                        lastAnimationAt = now
                        
                        // Quick reset for snappier feel
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                            withAnimation(.easeOut(duration: 0.25)) {
                                scaleEffect = 1.0
                                glowOpacity = 0
                            }
                        }
                    } else {
                        // Update silently without animation
                        displayedValue = newValue
                    }
                    
                    lastValue = newValue
                }
            }
    }
    
    private func formatValue(_ value: Double) -> String {
        guard value > 0 else { return "$0.00" }
        return MarketFormat.price(value)
    }
}

// MARK: - AnimatedPLDisplay
/// An animated P&L display with smooth direction transitions and color changes.
/// Shows label + value in a compact format consistent with Portfolio page styling.
private struct AnimatedPLDisplay: View {
    let amount: Double
    let percent: Double
    let label: String
    let hideBalances: Bool
    /// Optional tap handler — when provided, the label becomes an interactive timeframe selector
    var onLabelTap: (() -> Void)? = nil
    
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var displayedAmount: Double = 0
    @State private var displayedPercent: Double = 0
    @State private var isUp: Bool = true
    @State private var scaleEffect: CGFloat = 1.0
    @State private var appearTime: Date = .distantPast
    @State private var lastAnimationAt: Date = .distantPast
    
    private var isDark: Bool { colorScheme == .dark }
    
    private let minUpdateInterval: TimeInterval = 0.35
    private let coldStartDuration: TimeInterval = 0.5
    
    // PERFORMANCE FIX: Track last onChange time to prevent "tried to update multiple times per frame"
    @State private var lastOnChangeAt: Date = .distantPast
    
    var body: some View {
        HStack(spacing: 4) {
            // Tappable timeframe label with chevron
            if let tap = onLabelTap {
                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    tap()
                } label: {
                    HStack(spacing: 2) {
                        Text(label)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(isDark ? Color.white.opacity(0.6) : Color.secondary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 6, weight: .bold))
                            .foregroundStyle(isDark ? Color.white.opacity(0.35) : Color.secondary.opacity(0.6))
                    }
                    .lineLimit(1)
                }
                .buttonStyle(.plain)
            } else {
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(isDark ? Color.white.opacity(0.5) : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .allowsTightening(true)
            }
            
            if hideBalances {
                Text("••••• (•••%)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(isUp ? Color.green : Color.red)
            } else {
                Text(formatPL(displayedAmount, displayedPercent))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .allowsTightening(true)
                    .foregroundStyle(isUp ? Color.green : Color.red)
            }
        }
        .scaleEffect(scaleEffect)
        .lineLimit(1)
        .onAppear {
            DispatchQueue.main.async {
                appearTime = Date()
                displayedAmount = amount
                displayedPercent = percent
                isUp = amount >= 0
            }
        }
        .onChange(of: amount) { _, newAmount in
            // STARTUP FIX v25: Allow significant P&L corrections during startup.
            // Previously blocked ALL onChange for 4 seconds, showing stale P&L values.
            let significantCorrection = abs(newAmount - displayedAmount) > 1.0
            
            if isInGlobalStartupPhase() && !significantCorrection { return }
            
            // PERFORMANCE FIX v2: Skip during scroll OR initialization phase
            guard !ScrollStateManager.shared.shouldBlockHeavyOperation() || significantCorrection else { return }
            // PERFORMANCE FIX v2: Increased throttle from 16ms to 100ms
            let now = Date()
            guard now.timeIntervalSince(lastOnChangeAt) > 0.1 || significantCorrection else { return }
            lastOnChangeAt = now
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                updateDisplay(newAmount: newAmount, newPercent: percent)
            }
        }
        .onChange(of: percent) { _, newPercent in
            // STARTUP FIX v25: Allow significant P&L corrections during startup.
            let significantCorrection = abs(newPercent - displayedPercent) > 0.5
            
            if isInGlobalStartupPhase() && !significantCorrection { return }
            
            // PERFORMANCE FIX v2: Skip during scroll OR initialization phase
            guard !ScrollStateManager.shared.shouldBlockHeavyOperation() || significantCorrection else { return }
            // PERFORMANCE FIX v2: Increased throttle from 16ms to 100ms
            let now = Date()
            guard now.timeIntervalSince(lastOnChangeAt) > 0.1 || significantCorrection else { return }
            lastOnChangeAt = now
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                updateDisplay(newAmount: amount, newPercent: newPercent)
            }
        }
    }
    
    private func updateDisplay(newAmount: Double, newPercent: Double) {
        let now = Date()
        let isColdStart = now.timeIntervalSince(appearTime) < coldStartDuration
        let tooSoon = now.timeIntervalSince(lastAnimationAt) < minUpdateInterval
        
        let newIsUp = newAmount >= 0
        let directionChanged = newIsUp != isUp
        let amountDelta = abs(newAmount - displayedAmount)
        let significantChange = amountDelta > 1.0 || directionChanged
        
        let shouldAnimate = !isColdStart && !tooSoon && significantChange
        
        if shouldAnimate {
            lastAnimationAt = now
            
            // Quick spring for snappy color/direction transitions
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                displayedAmount = newAmount
                displayedPercent = newPercent
                isUp = newIsUp
                scaleEffect = 1.015
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(.easeOut(duration: 0.18)) {
                    scaleEffect = 1.0
                }
            }
        } else {
            displayedAmount = newAmount
            displayedPercent = newPercent
            if directionChanged {
                isUp = newIsUp
            }
        }
    }
    
    private func formatPL(_ amount: Double, _ percent: Double) -> String {
        let sign = amount >= 0 ? "+" : "-"
        return "\(sign)\(MarketFormat.price(abs(amount))) (\(String(format: "%.2f", abs(percent)))%)"
    }
}

struct PortfolioSectionView: View {
    @EnvironmentObject var vm: HomeViewModel
    @Binding var selectedRange: HomeView.PortfolioRange
    
    // Timeframe picker overlay state - passed from parent to render overlay at top level
    @Binding var showTimeframePicker: Bool
    @Binding var timeframePickerAnchor: CGRect
    
    // Callback for "Ask AI" - navigates to AI chat with a prompt
    var onOpenChat: ((String) -> Void)?
    
    // Init with default bindings for backwards compatibility
    init(
        selectedRange: Binding<HomeView.PortfolioRange>,
        showTimeframePicker: Binding<Bool> = .constant(false),
        timeframePickerAnchor: Binding<CGRect> = .constant(.zero),
        showAllInsights: Binding<Bool> = .constant(false),
        onOpenChat: ((String) -> Void)? = nil
    ) {
        self._selectedRange = selectedRange
        self._showTimeframePicker = showTimeframePicker
        self._timeframePickerAnchor = timeframePickerAnchor
        self._showAllInsights = showAllInsights
        self.onOpenChat = onOpenChat
    }

    // Privacy mode - hides sensitive financial data
    @AppStorage("hideBalances") private var hideBalances = false
    
    // Track if header mode toggle is expanded (show mode label when collapsed for context)
    @AppStorage("headerModeToggleExpanded") private var isHeaderToggleExpanded = true
    
    @State private var showSparkAmount = false
    @State private var showExchangeConnection = false
    @State private var showAddHolding = false
    /// FIX v5.0.3: Changed from @State to @Binding — the navigationDestination is now
    /// at HomeView level (outside LazyVStack) to fix the SwiftUI lazy container warning.
    @Binding var showAllInsights: Bool
    /// FIX v23: Tick counter to trigger periodic re-renders for paper trading data.
    /// Incremented by a debounced onReceive of PaperTradingManager.objectWillChange.
    /// This replaces @ObservedObject which caused re-renders on EVERY price update.
    @State private var paperTradingTick: UInt = 0
    /// FIX v23: Cached paper trading prices. Previously `paperTradingPrices` was a computed
    /// property that iterated all 250 MarketViewModel.allCoins on EVERY access — and it was
    /// accessed 6+ times per body evaluation (total value, P&L, P&L%, sparkline data,
    /// allocation chips, pie chart slices). That's 1500+ iterations per render.
    /// Now we cache it and only refresh on the debounced timer tick.
    @State private var cachedPaperPrices: [String: Double] = [:]
    
    /// STABILITY FIX v23: Cached paper trading sparkline to prevent chart re-adjusting on startup.
    /// Previously, `paperTradingSparklineData` was a computed property that regenerated 720 points
    /// from scratch on every access. Its shape depends on the BTC sparkline reference (which changes
    /// 2-3 times as data loads from Firestore), causing the chart to visibly jump between different
    /// shapes. Now we cache it and only regenerate when: (a) trade history changes, (b) selected
    /// range changes, or (c) initial data has finished loading.
    @State private var cachedPaperSparkline: [ChartPoint] = []
    @State private var lastSparklineTradeCount: Int = -1
    @State private var lastSparklineBTCRefCount: Int = 0
    @State private var sparklineInitialized: Bool = false
    
    /// Cached sparkline for Portfolio (live) mode.
    /// Uses CoinGecko per-coin sparkline data to show actual market value over 7 days.
    /// Extends to 30 days using proportional scaling from the 7-day data.
    /// Regenerated when holdings change or sparkline data first arrives.
    @State private var cachedPortfolioSparkline: [ChartPoint] = []
    @State private var lastPortfolioHoldingsCount: Int = -1
    @State private var lastPortfolioSparklineRefCount: Int = 0
    @State private var lastPortfolioSparklineFingerprint: Int = 0
    
    // AI Insights state
    @State private var smartPrompts: [String] = []
    @State private var promptIndex: Int = 0
    @State private var lastPromptRefresh: Date = .distantPast
    @State private var lastInteraction: Date = .distantPast
    // PERFORMANCE FIX v19: Changed from .common to .default so timer pauses during scroll
    @State private var cycleTimer = Timer.publish(every: 14, on: .main, in: .default).autoconnect()
    private let promptRefreshInterval: TimeInterval = 60
    
    @Environment(\.colorScheme) private var colorScheme
    
    // FIX v23: Replaced @ObservedObject with computed properties accessing singletons.
    // PaperTradingManager has 9 @Published properties — lastKnownPrices fires on EVERY price
    // update (every 2-6s). With @ObservedObject, EACH fire caused a full PortfolioSectionView
    // re-render including: iterating 250 coins 6x for paperTradingPrices, generating 720
    // sparkline points, rendering 3-layer blur glow, and recalculating allocation chips.
    // Now we access the singletons directly — no SwiftUI observation, no cascade.
    // The view still re-renders when HomeViewModel (@EnvironmentObject) changes, which is rare.
    private var demoModeManager: DemoModeManager { DemoModeManager.shared }
    private var paperTradingManager: PaperTradingManager { PaperTradingManager.shared }

    // Pie chart size — reduced to prevent clipping on right edge with 14pt horizontal padding
    private let pieChartSize: CGFloat = 64
    private let cardCornerRadius: CGFloat = 14  // Matches Portfolio tab for consistency
    
    private var isDark: Bool { colorScheme == .dark }
    
    /// Determines the current display mode based on active modes
    private var displayMode: PortfolioDisplayMode {
        if paperTradingManager.isPaperTradingEnabled {
            return .paperTrading
        } else if demoModeManager.isDemoMode {
            return .demo
        } else if vm.portfolioVM.holdings.isEmpty {
            return .empty
        } else {
            return .live
        }
    }
    
    /// Returns true when we should show the empty state
    private var shouldShowEmptyState: Bool {
        displayMode == .empty
    }
    
    // MARK: - AI Insights Helpers
    
    /// Active prompts to display - uses smart prompts if available, falls back to defaults
    private var prompts: [String] {
        if smartPrompts.isEmpty {
            return [
                "How can I improve my portfolio diversification?",
                "What trades performed best last week?",
                "Should I rebalance my assets now?"
            ]
        }
        return smartPrompts
    }
    
    private var currentPrompt: String {
        guard prompts.indices.contains(promptIndex) else { return "" }
        return prompts[promptIndex]
    }
    
    /// Refresh smart prompts from SmartPromptService
    /// Fetches 10 prompts to give users more variety when cycling through with chevron buttons
    private func refreshSmartPrompts() {
        let holdings = vm.portfolioVM.holdings
        let newPrompts = SmartPromptService.shared.buildContextualPrompts(count: 10, holdings: holdings)
        if !newPrompts.isEmpty {
            smartPrompts = newPrompts
            lastPromptRefresh = Date()
            if promptIndex >= newPrompts.count {
                promptIndex = 0
            }
        }
    }
    
    /// AI Insight with text and a prompt to open chat with
    private var aiInsight: (text: String, prompt: String)? {
        let allocationData: [(symbol: String, percent: Double)]
        if displayMode == .paperTrading {
            allocationData = paperTradingAllocationChips().map { (symbol: $0.symbol, percent: $0.percent) }
        } else {
            allocationData = vm.portfolioVM.allocationData.map { (symbol: $0.symbol, percent: $0.percent) }
        }
        
        guard let top = allocationData.max(by: { $0.percent < $1.percent }) else { return nil }
        let topPct = Int(round(top.percent))
        
        // Get P&L info for richer insights
        let pnlPercent: Double
        if displayMode == .paperTrading {
            pnlPercent = paperTradingManager.calculateProfitLossPercent(prices: paperTradingPrices)
        } else {
            pnlPercent = vm.portfolioVM.dailyChangePercent
        }
        
        // Generate contextual insights based on portfolio state
        if topPct >= 50 {
            return (
                text: "\(top.symbol) dominates at \(topPct)%. High concentration increases risk.",
                prompt: "Analyze my \(top.symbol) position at \(topPct)% concentration. Should I diversify and what are the risks?"
            )
        } else if topPct >= 35 {
            if pnlPercent < -5 {
                return (
                    text: "Portfolio down \(String(format: "%.1f", abs(pnlPercent)))%. \(top.symbol) leads at \(topPct)%.",
                    prompt: "My portfolio is down \(String(format: "%.1f", abs(pnlPercent)))% with \(top.symbol) at \(topPct)%. What's my best strategy?"
                )
            } else if pnlPercent > 10 {
                return (
                    text: "Nice gains! Up \(String(format: "%.1f", pnlPercent))%. Consider taking some profits.",
                    prompt: "I'm up \(String(format: "%.1f", pnlPercent))% on my portfolio. Should I take profits or hold?"
                )
            } else {
                return (
                    text: "\(top.symbol) leads at \(topPct)%. Tap for rebalancing advice.",
                    prompt: "My top holding is \(top.symbol) at \(topPct)%. Should I rebalance my portfolio?"
                )
            }
        } else if topPct >= 20 {
            return (
                text: "Well diversified with \(top.symbol) at \(topPct)%. Tap for optimization tips.",
                prompt: "My portfolio is well balanced with \(top.symbol) at \(topPct)%. How can I optimize further?"
            )
        } else {
            // Even distribution
            return (
                text: "Portfolio is evenly distributed. Tap for market insights.",
                prompt: "Analyze my evenly distributed portfolio and suggest improvements."
            )
        }
    }
    
    /// Top allocation data for insights
    private var topAllocation: (symbol: String, percent: Double)? {
        let allocationData: [(symbol: String, percent: Double)]
        if displayMode == .paperTrading {
            allocationData = paperTradingAllocationChips().map { (symbol: $0.symbol, percent: $0.percent) }
        } else {
            allocationData = vm.portfolioVM.allocationData.map { (symbol: $0.symbol, percent: $0.percent) }
        }
        return allocationData.max(by: { $0.percent < $1.percent })
    }
    
    // MARK: - Paper Trading Helpers
    
    /// Get current market prices for Paper Trading calculations
    /// BUG FIX: Now includes fallback to lastKnownPrices when live prices are unavailable (API rate limiting)
    /// FIX v23: Now uses cachedPaperPrices @State instead of iterating 250 coins on every access.
    /// The cache is refreshed in the debounced onReceive handler and on initial appear.
    private var paperTradingPrices: [String: Double] { cachedPaperPrices }
    
    /// Recomputes paper trading prices from live market data. Called from onReceive (debounced).
    private func refreshPaperTradingPrices() -> [String: Double] {
        var prices: [String: Double] = [:]
        
        // First, get all available live prices from market data
        // PRICE CONSISTENCY FIX: Use bestPrice() which checks LivePriceManager first
        for coin in MarketViewModel.shared.allCoins {
            let symbol = coin.symbol.uppercased()
            // Priority: bestPrice() > coin.priceUsd (fallback)
            if let price = MarketViewModel.shared.bestPrice(for: coin.id), price > 0 {
                prices[symbol] = price
            } else if let price = coin.priceUsd, price > 0 {
                prices[symbol] = price
            }
        }
        
        // FIX: For any assets in paperBalances not yet resolved, try bestPrice(forSymbol:)
        // This catches cases where allCoins hasn't loaded yet but LivePriceManager has data
        for (asset, _) in paperTradingManager.paperBalances {
            let symbol = asset.uppercased()
            if prices[symbol] == nil || prices[symbol] == 0 {
                if let symbolPrice = MarketViewModel.shared.bestPrice(forSymbol: symbol), symbolPrice > 0 {
                    prices[symbol] = symbolPrice
                }
            }
        }
        
        // Fallback: For any assets still without live prices,
        // use lastKnownPrices from PaperTradingManager — but only if they are fresh (< 30 min old)
        for (asset, _) in paperTradingManager.paperBalances {
            let symbol = asset.uppercased()
            if prices[symbol] == nil || prices[symbol] == 0 {
                if let cachedPrice = paperTradingManager.lastKnownPrices[symbol], cachedPrice > 0,
                   paperTradingManager.isCachedPriceFresh(for: symbol) {
                    prices[symbol] = cachedPrice
                }
            }
        }
        
        // USDT is always 1:1 with USD
        prices["USDT"] = 1.0
        prices["USD"] = 1.0
        prices["USDC"] = 1.0
        
        // Push fresh prices back to PaperTradingManager cache (with timestamps)
        // so future fallback lookups have up-to-date data
        paperTradingManager.updateLastKnownPrices(prices)
        
        return prices
    }
    
    /// Calculate Paper Trading portfolio total value
    private var paperTradingTotalValue: Double {
        paperTradingManager.calculatePortfolioValue(prices: paperTradingPrices)
    }
    
    /// Calculate Paper Trading P&L
    private var paperTradingProfitLoss: Double {
        paperTradingManager.calculateProfitLoss(prices: paperTradingPrices)
    }
    
    /// Calculate Paper Trading P&L percentage
    private var paperTradingProfitLossPercent: Double {
        paperTradingManager.calculateProfitLossPercent(prices: paperTradingPrices)
    }
    
    /// STABILITY FIX v23: Generates and caches the paper trading sparkline.
    /// Only regenerates when: (a) first call, (b) trade count changed, or (c) BTC reference
    /// data became available for the first time (initial data load after cold start).
    /// This prevents the chart from visibly re-adjusting 2-3 times as data loads.
    private func ensurePaperSparklineCached(forceRegenerate: Bool = false) {
        let tradeCount = paperTradingManager.paperTradeHistory.count
        let btcRefCount: Int = {
            if let btcCoin = MarketViewModel.shared.allCoins.first(where: { $0.symbol.uppercased() == "BTC" }) {
                return btcCoin.sparklineIn7d.count
            }
            return 0
        }()
        
        // Decide whether to regenerate
        let needsRegenerate: Bool = {
            if forceRegenerate { return true }
            if cachedPaperSparkline.isEmpty { return true }
            if tradeCount != lastSparklineTradeCount { return true }
            // Only regenerate for BTC ref data if this is the FIRST time we get it
            // (transition from 0 points to having data). After that, don't regenerate
            // just because BTC sparkline data refreshed — that causes the visible jumps.
            if lastSparklineBTCRefCount < 24 && btcRefCount >= 24 { return true }
            // FIX v26: Regenerate when the live portfolio value diverges significantly (>3%)
            // from the sparkline's last point. This catches cases where the sparkline was
            // generated with stale/incomplete prices and the chart shape is wrong.
            // Without this, the extension period (1M view) stays anchored to a wrong value
            // and never gets corrected.
            if let lastPoint = cachedPaperSparkline.last {
                let liveTotal = paperTradingManager.calculatePortfolioValue(prices: cachedPaperPrices)
                if liveTotal > 0 && lastPoint.value > 0 {
                    let divergence = abs(liveTotal - lastPoint.value) / lastPoint.value
                    if divergence > 0.03 { return true }
                }
            }
            return false
        }()
        
        guard needsRegenerate else { return }
        
        cachedPaperSparkline = paperTradingSparklineData
        lastSparklineTradeCount = tradeCount
        lastSparklineBTCRefCount = btcRefCount
        sparklineInitialized = true
    }
    
    /// FIX v26: Lightweight patch — keeps the sparkline's last point in sync with the
    /// current live total without regenerating the entire 720-point sparkline. This prevents
    /// the P&L and chart from diverging from the displayed total value between full regenerations.
    private func patchSparklineEndpoint() {
        guard !cachedPaperSparkline.isEmpty else { return }
        let liveTotal = paperTradingManager.calculatePortfolioValue(prices: cachedPaperPrices)
        guard liveTotal > 0 else { return }
        cachedPaperSparkline[cachedPaperSparkline.count - 1] = ChartPoint(date: Date(), value: liveTotal)
    }
    
    /// Generate sparkline data for Paper Trading mode.
    /// ACCURACY FIX v23: Uses ACTUAL per-coin sparkline data to calculate real historical
    /// portfolio values instead of synthetic BTC-correlated curves. Previous approach had two
    /// bugs: (1) trade replay valued portfolio at historical points using CURRENT prices,
    /// (2) BTC correlation created unrealistic valleys (showed $73K when actual was $90K).
    /// Now we compute the real portfolio value at each sparkline point using each coin's
    /// CoinGecko sparkline data, giving an accurate picture of portfolio performance.
    private var paperTradingSparklineData: [ChartPoint] {
        let currentValue = paperTradingTotalValue
        let initialValue = paperTradingManager.initialPortfolioValue
        let now = Date()
        let stableSymbols: Set<String> = ["USDT", "USD", "USDC", "BUSD", "FDUSD", "DAI", "TUSD"]
        
        // Fresh/cash-only paper accounts should not show synthetic volatility.
        // If there are no trades and no non-stable balances, return a flat 30-day line.
        let hasNonStableBalance = paperTradingManager.paperBalances.contains { asset, amount in
            amount > 0.000001 && !stableSymbols.contains(asset.uppercased())
        }
        if paperTradingManager.paperTradeHistory.isEmpty && !hasNonStableBalance {
            let anchor = max(1, currentValue > 0 ? currentValue : initialValue)
            let targetHours = 720
            var points: [ChartPoint] = []
            points.reserveCapacity(targetHours)
            for i in 0..<targetHours {
                let date = now.addingTimeInterval(-Double(targetHours - 1 - i) * 3600)
                points.append(ChartPoint(date: date, value: anchor))
            }
            return points
        }
        
        // ── 1. Build balance timeline from trade history ──────────────────
        // Replay trades chronologically to know what was held at any point in time.
        // This is critical: the old code applied CURRENT balances to ALL historical hours,
        // which is wrong if trades happened within the sparkline window.
        let sortedTrades = paperTradingManager.paperTradeHistory.sorted { $0.timestamp < $1.timestamp }
        
        struct BalanceSnapshot {
            let date: Date
            let balances: [String: Double]
        }
        
        var snapshots: [BalanceSnapshot] = []
        var runningBal: [String: Double] = ["USDT": initialValue]
        snapshots.append(BalanceSnapshot(date: .distantPast, balances: runningBal))
        
        // Collect ALL symbols that were ever held (needed for sparkline lookup)
        var allHeldSymbols: Set<String> = []
        
        for trade in sortedTrades {
            let (baseAsset, quoteAsset) = paperTradingManager.parseSymbol(trade.symbol)
            let totalCost = trade.quantity * trade.price
            switch trade.side {
            case .buy:
                runningBal[quoteAsset, default: 0] -= totalCost
                runningBal[baseAsset, default: 0] += trade.quantity
            case .sell:
                runningBal[baseAsset, default: 0] -= trade.quantity
                runningBal[quoteAsset, default: 0] += totalCost
            }
            snapshots.append(BalanceSnapshot(date: trade.timestamp, balances: runningBal))
            allHeldSymbols.insert(baseAsset.uppercased())
        }
        
        // Also include current balance symbols
        for (asset, amount) in paperTradingManager.paperBalances where amount > 0.000001 {
            allHeldSymbols.insert(asset.uppercased())
        }
        
        // Helper: get the active balances at a given date
        func balancesAt(_ date: Date) -> [String: Double] {
            var result = snapshots[0].balances
            for snap in snapshots {
                if snap.date <= date { result = snap.balances } else { break }
            }
            return result
        }
        
        // ── 2. Gather per-coin sparkline data (CoinGecko 168-point 7D hourly) ──
        var coinSparklines: [String: [Double]] = [:]
        var coinCurrentPrices: [String: Double] = [:]
        let allCoins = MarketViewModel.shared.allCoins
        
        for symbol in allHeldSymbols where !stableSymbols.contains(symbol) {
            if let coin = allCoins.first(where: { $0.symbol.uppercased() == symbol }) {
                let spark = coin.sparklineIn7d.filter { $0.isFinite && $0 > 0 }
                if spark.count >= 10 { coinSparklines[symbol] = spark }
                if let price = MarketViewModel.shared.bestPrice(for: coin.id), price > 0 {
                    coinCurrentPrices[symbol] = price
                } else if let price = coin.priceUsd, price > 0 {
                    coinCurrentPrices[symbol] = price
                }
            }
        }
        
        // ── 3. Generate the 7-day sparkline using CORRECT balances at each hour ──
        let sparklineLength = coinSparklines.values.map { $0.count }.max() ?? 168
        var recentHistory: [ChartPoint] = []
        recentHistory.reserveCapacity(sparklineLength)
        
        for i in 0..<sparklineLength {
            let date = now.addingTimeInterval(-Double(sparklineLength - 1 - i) * 3600)
            let activeBal = balancesAt(date)
            var portfolioValue: Double = 0
            
            for (asset, amount) in activeBal where amount > 0.000001 {
                let symbol = asset.uppercased()
                if stableSymbols.contains(symbol) {
                    portfolioValue += amount
                } else if let sparkline = coinSparklines[symbol] {
                    let sparkIdx = Int(Double(i) / Double(max(sparklineLength - 1, 1)) * Double(sparkline.count - 1))
                    let clampedIdx = min(max(sparkIdx, 0), sparkline.count - 1)
                    portfolioValue += amount * sparkline[clampedIdx]
                } else if let currentPrice = coinCurrentPrices[symbol] {
                    portfolioValue += amount * currentPrice
                }
            }
            
            if portfolioValue > 0 {
                recentHistory.append(ChartPoint(date: date, value: portfolioValue))
            }
        }
        
        // Ensure last point matches current live value exactly
        if !recentHistory.isEmpty && currentValue > 0 {
            recentHistory[recentHistory.count - 1] = ChartPoint(date: now, value: currentValue)
        }
        
        // ── 4. Extend backward for 1M / 1Y / All views ──────────────────
        // CRITICAL FIX v27: The extension anchor must reflect the ACTUAL portfolio value
        // at the extension start date, NOT always initialValue ($100k).
        //
        // Previous bug: always used initialValue as anchor → "1 Month" P&L showed all-time
        // loss instead of last month's loss (e.g., -$20k instead of -$10k).
        //
        // Correct approach:
        //   1. Replay trades that occurred BEFORE the extension window to get accurate
        //      balances at the extension start date
        //   2. Value those balances using trade-time prices (best available approximation)
        //   3. Use THAT value as the anchor (not initialValue)
        //   4. Insert trade-time waypoints within the extension window
        //   5. Interpolate smoothly between waypoints and the oldest sparkline value
        let targetHours = 720  // 30 days
        if recentHistory.count < targetHours && !recentHistory.isEmpty {
            let oldestValue = recentHistory.first?.value ?? currentValue
            let oldestDate = recentHistory.first?.date ?? now
            let extendHours = targetHours - recentHistory.count
            let extensionStartDate = oldestDate.addingTimeInterval(-Double(extendHours) * 3600)
            
            // STEP A: Replay all trades BEFORE the extension window to build accurate
            // starting balances and collect trade-time prices for valuation.
            var replayBal: [String: Double] = ["USDT": initialValue]
            var assetPrices: [String: Double] = [:]  // Track each asset's price from its own trade
            
            for trade in sortedTrades where trade.timestamp <= extensionStartDate {
                let (baseAsset, quoteAsset) = paperTradingManager.parseSymbol(trade.symbol)
                let totalCost = trade.quantity * trade.price
                switch trade.side {
                case .buy:
                    replayBal[quoteAsset, default: 0] -= totalCost
                    replayBal[baseAsset, default: 0] += trade.quantity
                    assetPrices[baseAsset.uppercased()] = trade.price
                case .sell:
                    replayBal[baseAsset, default: 0] -= trade.quantity
                    replayBal[quoteAsset, default: 0] += totalCost
                    assetPrices[baseAsset.uppercased()] = trade.price
                }
            }
            
            // STEP B: Calculate the actual portfolio value at extensionStartDate
            // using the balances from pre-window trades and trade-time prices.
            var extensionStartValue: Double = 0
            for (asset, amount) in replayBal where amount > 0.000001 {
                let sym = asset.uppercased()
                if stableSymbols.contains(sym) {
                    extensionStartValue += amount
                } else if let price = assetPrices[sym], price > 0 {
                    extensionStartValue += amount * price
                } else if let price = coinCurrentPrices[sym], price > 0 {
                    extensionStartValue += amount * price
                }
            }
            // Safety: if no trades before window, start value IS initialValue
            if extensionStartValue <= 0 { extensionStartValue = initialValue }
            
            // Also check stored snapshots for a more accurate start value
            if let snapshotValue = paperTradingManager.snapshotValue(nearDate: extensionStartDate),
               snapshotValue > 0 {
                extensionStartValue = snapshotValue
            }
            
            // STEP C: Build waypoints for the extension period
            var waypoints: [(date: Date, value: Double)] = []
            waypoints.append((date: extensionStartDate, value: extensionStartValue))
            
            // STEP D: Process trades within the extension window (add as waypoints)
            for trade in sortedTrades {
                guard trade.timestamp > extensionStartDate && trade.timestamp < oldestDate else {
                    continue  // Already processed pre-window trades; skip post-window too
                }
                
                let (baseAsset, quoteAsset) = paperTradingManager.parseSymbol(trade.symbol)
                let totalCost = trade.quantity * trade.price
                switch trade.side {
                case .buy:
                    replayBal[quoteAsset, default: 0] -= totalCost
                    replayBal[baseAsset, default: 0] += trade.quantity
                    assetPrices[baseAsset.uppercased()] = trade.price
                case .sell:
                    replayBal[baseAsset, default: 0] -= trade.quantity
                    replayBal[quoteAsset, default: 0] += totalCost
                    assetPrices[baseAsset.uppercased()] = trade.price
                }
                
                // Calculate portfolio value at this trade using EACH asset's own price
                var tradeVal: Double = 0
                for (asset, amount) in replayBal where amount > 0.000001 {
                    let sym = asset.uppercased()
                    if stableSymbols.contains(sym) {
                        tradeVal += amount
                    } else if let price = assetPrices[sym] {
                        // Use this asset's own trade price (from the trade where it was bought/sold)
                        tradeVal += amount * price
                    } else if let price = coinCurrentPrices[sym] {
                        tradeVal += amount * price
                    }
                }
                if tradeVal > 0 {
                    waypoints.append((date: trade.timestamp, value: tradeVal))
                }
            }
            
            // End waypoint: connect to the start of sparkline data
            waypoints.append((date: oldestDate, value: oldestValue))
            
            // Sort waypoints by date
            waypoints.sort { $0.date < $1.date }
            
            // Generate extension points by interpolating between waypoints
            var extensionPoints: [ChartPoint] = []
            extensionPoints.reserveCapacity(extendHours)
            
            for i in 0..<extendHours {
                let date = oldestDate.addingTimeInterval(-Double(extendHours - i) * 3600)
                
                // Find the two waypoints this date falls between
                var wpBefore = waypoints[0]
                var wpAfter = waypoints[waypoints.count - 1]
                for j in 0..<waypoints.count - 1 {
                    if waypoints[j].date <= date && waypoints[j + 1].date >= date {
                        wpBefore = waypoints[j]
                        wpAfter = waypoints[j + 1]
                        break
                    }
                }
                
                // Linear interpolation between waypoints
                let totalInterval = wpAfter.date.timeIntervalSince(wpBefore.date)
                let progress: Double
                if totalInterval > 0 {
                    progress = date.timeIntervalSince(wpBefore.date) / totalInterval
                } else {
                    progress = 0
                }
                let value = wpBefore.value + (wpAfter.value - wpBefore.value) * progress
                extensionPoints.append(ChartPoint(date: date, value: max(value, 0.01)))
            }
            
            return extensionPoints + recentHistory
        }
        
        // For no-trade case with no sparkline data, return flat line at current value
        if recentHistory.isEmpty {
            var points: [ChartPoint] = []
            for i in 0..<targetHours {
                let date = now.addingTimeInterval(-Double(targetHours - 1 - i) * 3600)
                points.append(ChartPoint(date: date, value: currentValue > 0 ? currentValue : initialValue))
            }
            return points
        }
        
        return recentHistory
    }
    
    // MARK: - Portfolio (Live) Mode Sparkline
    
    /// Generates and caches the portfolio sparkline from CoinGecko per-coin data.
    /// Called when holdings change or sparkline reference data first arrives.
    private func ensurePortfolioSparklineCached() {
        let holdingsCount = vm.portfolioVM.holdings.count
        let allCoins = MarketViewModel.shared.allCoins
        let sparkRefCount: Int = {
            // Check if we have sparkline data from any held coin
            for h in vm.portfolioVM.holdings {
                if let coin = allCoins.first(where: { $0.symbol.caseInsensitiveCompare(h.coinSymbol) == .orderedSame }) {
                    if coin.sparklineIn7d.count >= 10 { return coin.sparklineIn7d.count }
                }
            }
            return 0
        }()
        let sparklineFingerprint: Int = {
            var hasher = Hasher()
            for h in vm.portfolioVM.holdings.sorted(by: { $0.coinSymbol.uppercased() < $1.coinSymbol.uppercased() }) {
                hasher.combine(h.coinSymbol.uppercased())
                hasher.combine(Int((h.quantity * 1_000_000).rounded()))
                if let coin = allCoins.first(where: { $0.symbol.caseInsensitiveCompare(h.coinSymbol) == .orderedSame }) {
                    let spark = coin.sparklineIn7d.filter { $0.isFinite && $0 > 0 }
                    hasher.combine(coin.id.lowercased())
                    hasher.combine(spark.count)
                    if let first = spark.first { hasher.combine(Int((first * 10_000).rounded())) }
                    if let last = spark.last { hasher.combine(Int((last * 10_000).rounded())) }
                }
            }
            return hasher.finalize()
        }()
        
        let needsRegenerate: Bool = {
            if cachedPortfolioSparkline.isEmpty { return true }
            if holdingsCount != lastPortfolioHoldingsCount { return true }
            // Regenerate once when sparkline data first arrives
            if lastPortfolioSparklineRefCount < 10 && sparkRefCount >= 10 { return true }
            if sparklineFingerprint != lastPortfolioSparklineFingerprint { return true }
            return false
        }()
        
        guard needsRegenerate else { return }
        cachedPortfolioSparkline = generatePortfolioSparkline()
        lastPortfolioHoldingsCount = holdingsCount
        lastPortfolioSparklineRefCount = sparkRefCount
        lastPortfolioSparklineFingerprint = sparklineFingerprint
    }
    
    /// Generates a sparkline for Portfolio (live) mode using CoinGecko per-coin sparkline data.
    /// Uses the same accurate approach as Paper Trading: each coin's actual hourly prices.
    private func generatePortfolioSparkline() -> [ChartPoint] {
        let holdings = vm.portfolioVM.holdings
        let totalValue = vm.portfolioVM.totalValue
        guard !holdings.isEmpty, totalValue > 0 else { return [] }
        
        let now = Date()
        let allCoins = MarketViewModel.shared.allCoins
        let stableSymbols: Set<String> = ["USDT", "USD", "USDC", "BUSD", "FDUSD", "DAI", "TUSD"]
        
        // Gather per-coin sparkline data (CoinGecko 168-point 7D hourly)
        var coinSparklines: [String: [Double]] = [:]
        var coinCurrentPrices: [String: Double] = [:]
        var holdingQuantities: [String: Double] = [:]
        var symbolToKey: [String: String] = [:]
        let diskSparklineCache = WatchlistSparklineService.loadCachedSparklinesSync()
        
        for h in holdings where h.quantity > 0.000001 {
            let symbol = h.coinSymbol.uppercased()
            var key = symbol
            holdingQuantities[symbol, default: 0] += h.quantity
            
            if stableSymbols.contains(symbol) { continue }
            
            if let coin = allCoins.first(where: { $0.symbol.uppercased() == symbol }) {
                key = coin.id.lowercased()
                symbolToKey[symbol] = key
                let spark = coin.sparklineIn7d.filter { $0.isFinite && $0 > 0 }
                if spark.count >= 10 {
                    coinSparklines[key] = spark
                } else if let cached = diskSparklineCache[key] {
                    let cleanCached = cached.filter { $0.isFinite && $0 > 0 }
                    if cleanCached.count >= 10 { coinSparklines[key] = cleanCached }
                }
                if let price = MarketViewModel.shared.bestPrice(for: coin.id), price > 0 {
                    coinCurrentPrices[key] = price
                } else if let price = coin.priceUsd, price > 0 {
                    coinCurrentPrices[key] = price
                } else if h.currentPrice > 0 {
                    coinCurrentPrices[key] = h.currentPrice
                }
            } else if h.currentPrice > 0 {
                // Symbol fallback if coin metadata is not available yet
                symbolToKey[symbol] = key
                if let cached = diskSparklineCache[symbol.lowercased()] {
                    let cleanCached = cached.filter { $0.isFinite && $0 > 0 }
                    if cleanCached.count >= 10 { coinSparklines[key] = cleanCached }
                }
                coinCurrentPrices[key] = h.currentPrice
            }
        }
        
        // If no sparkline data at all, fall back to transaction-based history
        if coinSparklines.isEmpty { return [] }
        
        // Generate 7-day sparkline using per-coin actual prices
        let sparklineLength = coinSparklines.values.map { $0.count }.max() ?? 168
        var recentHistory: [ChartPoint] = []
        recentHistory.reserveCapacity(sparklineLength)
        
        for i in 0..<sparklineLength {
            let date = now.addingTimeInterval(-Double(sparklineLength - 1 - i) * 3600)
            var portfolioValue: Double = 0
            
            for (symbol, quantity) in holdingQuantities where quantity > 0.000001 {
                if stableSymbols.contains(symbol) {
                    portfolioValue += quantity
                } else if let sparkline = coinSparklines[symbolToKey[symbol] ?? symbol] {
                    let sparkIdx = Int(Double(i) / Double(max(sparklineLength - 1, 1)) * Double(sparkline.count - 1))
                    let clampedIdx = min(max(sparkIdx, 0), sparkline.count - 1)
                    portfolioValue += quantity * sparkline[clampedIdx]
                } else if let currentPrice = coinCurrentPrices[symbolToKey[symbol] ?? symbol] {
                    portfolioValue += quantity * currentPrice
                }
            }
            
            if portfolioValue > 0 {
                recentHistory.append(ChartPoint(date: date, value: portfolioValue))
            }
        }
        
        // Ensure last point matches current live value
        if !recentHistory.isEmpty && totalValue > 0 {
            recentHistory[recentHistory.count - 1] = ChartPoint(date: now, value: totalValue)
        }
        
        // Extend backward for 1M view (30 days total)
        let targetHours = 720
        if recentHistory.count < targetHours && recentHistory.count >= 2 {
            let oldestValue = recentHistory.first?.value ?? totalValue
            let oldestDate = recentHistory.first?.date ?? now
            let extendHours = targetHours - recentHistory.count
            
            // For extension: scale from oldest sparkline value toward totalValue proportionally
            // (simple linear interpolation assuming stable allocation over 30 days)
            var extensionPoints: [ChartPoint] = []
            extensionPoints.reserveCapacity(extendHours)
            
            for i in 0..<extendHours {
                let date = oldestDate.addingTimeInterval(-Double(extendHours - i) * 3600)
                // Gradually approach oldestValue — slight variance to look organic
                let progress = Double(i) / Double(max(extendHours - 1, 1))
                let value = oldestValue * (0.97 + 0.03 * progress) // Smooth 3% range
                extensionPoints.append(ChartPoint(date: date, value: max(value, 0.01)))
            }
            
            return extensionPoints + recentHistory
        }
        
        if recentHistory.isEmpty {
            // Flat line at current value
            var points: [ChartPoint] = []
            for i in 0..<168 {
                let date = now.addingTimeInterval(-Double(168 - 1 - i) * 3600)
                points.append(ChartPoint(date: date, value: totalValue))
            }
            return points
        }
        
        return recentHistory
    }
    
    /// Generates a dense sparkline with realistic market-correlated movement
    /// - Parameters:
    ///   - startValue: Starting portfolio value
    ///   - endValue: Ending portfolio value (current)
    ///   - hours: Number of hourly data points to generate
    ///   - referenceSparkline: Market data to correlate movement with (e.g., BTC)
    ///   - volatilityScale: How much the portfolio should move relative to market (0.0 = flat, 1.0 = same as market)
    /// - Returns: Array of ChartPoints with hourly granularity
    private func generateDenseSparkline(
        startValue: Double,
        endValue: Double,
        hours: Int,
        referenceSparkline: [Double],
        volatilityScale: Double
    ) -> [ChartPoint] {
        let now = Date()
        var points: [ChartPoint] = []
        points.reserveCapacity(hours)
        
        // Base linear interpolation from start to end
        let totalChange = endValue - startValue
        
        // Compute normalized reference movement (if available)
        var referenceNormalized: [Double] = []
        if referenceSparkline.count >= 2,
           let refMin = referenceSparkline.min(),
           let refMax = referenceSparkline.max(),
           refMax > refMin {
            let refRange = refMax - refMin
            referenceNormalized = referenceSparkline.map { ($0 - refMin) / refRange - 0.5 }
        }
        
        for i in 0..<hours {
            let date = now.addingTimeInterval(-Double(hours - 1 - i) * 3600)
            let progress = Double(i) / Double(max(hours - 1, 1))
            
            // Base value from linear interpolation
            var value = startValue + totalChange * progress
            
            // Add market-correlated micro-movement for visual interest
            if !referenceNormalized.isEmpty {
                let refIndex = min(i, referenceNormalized.count - 1)
                let marketMovement = referenceNormalized[refIndex]
                // Scale the movement by volatility and portfolio size
                let volatilityAmount = startValue * volatilityScale * marketMovement
                value += volatilityAmount
            } else {
                // No reference data - add deterministic pseudo-random movement
                // Use sine waves with different frequencies for organic look
                // VISUAL ENHANCEMENT: Increased amplitudes for visible chart movement
                let seed = Double(i)
                let wave1 = sin(seed * 0.12) * 0.012      // Primary wave - slow, visible
                let wave2 = sin(seed * 0.35 + 1.5) * 0.006 // Secondary wave - medium frequency
                let wave3 = sin(seed * 0.08 + 2.3) * 0.008 // Tertiary wave - longer cycle
                value += startValue * (wave1 + wave2 + wave3) * volatilityScale
            }
            
            // Ensure value stays positive
            value = max(value, startValue * 0.9)
            
            points.append(ChartPoint(date: date, value: value))
        }
        
        // Ensure the last point exactly matches the current value
        if !points.isEmpty {
            points[points.count - 1] = ChartPoint(date: now, value: endValue)
        }
        
        return points
    }
    
    /// Interpolates sparse trade-based points into dense hourly data
    /// - Parameters:
    ///   - sparsePoints: Original points at trade timestamps
    ///   - targetHours: Number of hourly points to generate
    ///   - referenceSparkline: Market data for realistic inter-trade movement
    /// - Returns: Dense array of hourly ChartPoints
    private func interpolateToDenseSparkline(
        sparsePoints: [ChartPoint],
        targetHours: Int,
        referenceSparkline: [Double]
    ) -> [ChartPoint] {
        guard sparsePoints.count >= 2 else {
            // Fallback if not enough sparse points
            let startVal = sparsePoints.first?.value ?? paperTradingManager.initialPortfolioValue
            let endVal = sparsePoints.last?.value ?? paperTradingTotalValue
            // VISUAL ENHANCEMENT: Increased volatilityScale for engaging chart
            return generateDenseSparkline(
                startValue: startVal,
                endValue: endVal,
                hours: targetHours,
                referenceSparkline: referenceSparkline,
                volatilityScale: 0.04 // Visible market correlation for engaging chart
            )
        }
        
        let now = Date()
        let startDate = now.addingTimeInterval(-Double(targetHours) * 3600)
        var densePoints: [ChartPoint] = []
        densePoints.reserveCapacity(targetHours)
        
        // Sort sparse points by date
        let sortedSparse = sparsePoints.sorted { $0.date < $1.date }
        
        // Normalize reference sparkline
        var refNorm: [Double] = []
        if referenceSparkline.count >= 2,
           let refMin = referenceSparkline.min(),
           let refMax = referenceSparkline.max(),
           refMax > refMin {
            let refRange = refMax - refMin
            refNorm = referenceSparkline.map { ($0 - refMin) / refRange - 0.5 }
        }
        
        // Generate hourly points
        for hour in 0..<targetHours {
            let pointDate = startDate.addingTimeInterval(Double(hour) * 3600)
            
            // Find the two sparse points that bracket this date
            var beforePoint = sortedSparse.first!
            var afterPoint = sortedSparse.last!
            
            for i in 0..<sortedSparse.count {
                if sortedSparse[i].date <= pointDate {
                    beforePoint = sortedSparse[i]
                }
                if sortedSparse[i].date > pointDate {
                    afterPoint = sortedSparse[i]
                    break
                }
            }
            
            // Linear interpolation between bracket points
            let timeDiff = afterPoint.date.timeIntervalSince(beforePoint.date)
            let progress: Double
            if timeDiff > 0 {
                progress = min(1.0, max(0.0, pointDate.timeIntervalSince(beforePoint.date) / timeDiff))
            } else {
                progress = 1.0
            }
            
            var value = beforePoint.value + (afterPoint.value - beforePoint.value) * progress
            
            // Add market-correlated movement between trades for visual interest
            // VISUAL ENHANCEMENT: Increased amplitude for engaging chart appearance
            if !refNorm.isEmpty {
                let refIndex = min(hour, refNorm.count - 1)
                let marketMovement = refNorm[refIndex]
                // Scale movement by average value - visible but not overwhelming
                let avgValue = (beforePoint.value + afterPoint.value) / 2
                value += avgValue * 0.015 * marketMovement
            }
            
            densePoints.append(ChartPoint(date: pointDate, value: max(value, 0.01)))
        }
        
        // Ensure last point matches current value exactly
        if !densePoints.isEmpty {
            densePoints[densePoints.count - 1] = ChartPoint(date: now, value: paperTradingTotalValue)
        }
        
        return densePoints
    }

    var body: some View {
        // FIX v23: Reference paperTradingTick to trigger re-renders on debounced price updates.
        // Without @ObservedObject, the view needs this dependency to refresh periodically.
        let _ = paperTradingTick
        
        if shouldShowEmptyState {
            // Show empty state when demo mode is off and no real holdings
            HomeBalanceEmptyStateCard(
                onConnectExchange: {
                    showExchangeConnection = true
                },
                onEnableDemo: {
                    demoModeManager.enableDemoMode()
                    vm.portfolioVM.enableDemoMode()
                },
                onEnablePaperTrading: {
                    PaperTradingManager.shared.enablePaperTrading()
                }
            )
            .sheet(isPresented: $showExchangeConnection) {
                NavigationStack {
                    PortfolioPaymentMethodsView()
                }
            }
        } else {
            portfolioCard
        }
    }
    
    private var portfolioCard: some View {
        // Get P/L color for dynamic effects - use selected range to match chart color
        let rangeChange = rangeChangePercent()
        let plColor = rangeChange >= 0 ? Color.green : Color.red
        
        return VStack(spacing: 0) {
            topRow

            // Refined divider with fade — clean separation between chips and sparkline
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.clear, DS.Adaptive.divider, DS.Adaptive.divider, Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 0.5)
                .padding(.top, 4)
                .padding(.bottom, 4)

            // Sparkline
            sparklineView

            // AI Insights Section - streamlined and connected
            if onOpenChat != nil {
                // Subtle divider between sparkline and AI section
                Rectangle()
                    .fill(DS.Adaptive.divider.opacity(0.25))
                    .frame(height: 0.5)
                    .padding(.top, 8)
                    .padding(.horizontal, -2)

                // Compact Ask AI row (no redundant chips - allocation shown above)
                compactAskAIRow
                    .padding(.top, 6)

                // More AI Insights link
                moreInsightsLink
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 14)
        .onAppear {
            refreshSmartPrompts()
        }
        .onReceive(cycleTimer) { _ in
            guard !CryptoSageAIApp.isEmergencyStopActive() else { return }
            // PERFORMANCE FIX: Skip timer actions during scroll
            guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
            
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                guard !CryptoSageAIApp.isEmergencyStopActive() else { return }
                // Double-check scroll state after async dispatch
                guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
                
                // Auto-cycle prompts when not recently interacted
                if prompts.count > 1 && Date().timeIntervalSince(lastInteraction) > 18 {
                    withAnimation { promptIndex = (promptIndex + 1) % max(1, prompts.count) }
                }
                // Refresh smart prompts periodically
                if Date().timeIntervalSince(lastPromptRefresh) > promptRefreshInterval {
                    refreshSmartPrompts()
                }
            }
        }
        .onChange(of: vm.portfolioVM.holdings.count) { _, _ in
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                refreshSmartPrompts()
            }
        }
        // FIX v23: Throttled paper trading updates. PaperTradingManager has 9 @Published properties
        // that fire on every price update. Instead of @ObservedObject (which re-renders on EVERY change),
        // we debounce to 2 seconds — fast enough to catch fresh prices on launch, slow enough to avoid spam.
        // FIX v24: Reduced from 5s → 2s to fix stale portfolio value on app launch.
        // The 5-second debounce meant fresh prices from Firestore/API (arriving ~3-5s after launch)
        // wouldn't update the displayed portfolio total for another 5 seconds on top of that.
        .onReceive(PaperTradingManager.shared.objectWillChange.debounce(for: .seconds(2), scheduler: DispatchQueue.main)) { _ in
            // FIX v28: Bypass scroll guard when sparkline hasn't been initialized yet,
            // so the first data arrival always populates the chart.
            guard !ScrollStateManager.shared.shouldBlockHeavyOperation() || !sparklineInitialized else { return }
            cachedPaperPrices = refreshPaperTradingPrices()
            // STABILITY FIX v23: Only regenerate sparkline if trade count changed (not just prices)
            ensurePaperSparklineCached()
            patchSparklineEndpoint()  // FIX v26: Keep sparkline endpoint in sync
            paperTradingTick &+= 1
        }
        // FIX v25: Subscribe to MarketViewModel.allCoins AND LivePriceManager for Paper Trading.
        // Previously had .dropFirst() which skipped the first (cached) emission, and a 1500ms
        // debounce that delayed fresh prices further. Now:
        // - No .dropFirst() — handles initial cached data immediately
        // - 500ms debounce — fast enough for startup, still prevents spam
        // This ensures paper trading portfolio value updates as soon as fresh data arrives
        // from Firestore, not 3-5 seconds later.
        .onReceive(
            MarketViewModel.shared.$allCoins
                .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
        ) { coins in
            guard !coins.isEmpty else { return }
            // FIX v28: Bypass scroll guard for initial sparkline population
            guard !ScrollStateManager.shared.shouldBlockHeavyOperation() || !sparklineInitialized else { return }
            
            if PaperTradingManager.shared.isPaperTradingEnabled {
                cachedPaperPrices = refreshPaperTradingPrices()
                // STABILITY FIX v23: Update sparkline cache — but ensurePaperSparklineCached
                // only regenerates if BTC ref data arrived for the first time (not on every refresh)
                ensurePaperSparklineCached()
                patchSparklineEndpoint()  // FIX v26: Keep sparkline endpoint in sync
                paperTradingTick &+= 1
                
                // Record periodic portfolio value snapshot for accurate historical P&L
                let liveValue = paperTradingManager.calculatePortfolioValue(prices: cachedPaperPrices)
                paperTradingManager.recordSnapshotIfNeeded(currentValue: liveValue)
            } else if !DemoModeManager.shared.isDemoMode {
                // Portfolio (live) mode: regenerate sparkline when CoinGecko data arrives
                ensurePortfolioSparklineCached()
            }
        }
        // STARTUP FIX: Subscribe to LivePriceManager's raw publisher for immediate Firestore data.
        // This fires as soon as Firestore delivers fresh prices (typically 1-2s after launch),
        // ensuring paper trading shows correct portfolio value without waiting for allCoins update.
        .onReceive(
            LivePriceManager.shared.publisher
                .filter { !$0.isEmpty }
                .first()
                .receive(on: DispatchQueue.main)
        ) { _ in
            guard PaperTradingManager.shared.isPaperTradingEnabled else { return }
            // FIX v28: Bypass scroll guard for initial sparkline population
            guard !ScrollStateManager.shared.shouldBlockHeavyOperation() || !sparklineInitialized else { return }
            cachedPaperPrices = refreshPaperTradingPrices()
            ensurePaperSparklineCached()
            patchSparklineEndpoint()  // FIX v26: Keep sparkline endpoint in sync
            paperTradingTick &+= 1
        }
        // Same for DemoModeManager (rare changes, but prevents observation cascade)
        .onReceive(DemoModeManager.shared.objectWillChange.debounce(for: .seconds(1), scheduler: DispatchQueue.main)) { _ in
            paperTradingTick &+= 1
        }
        .onAppear {
            // MEMORY FIX v7: Defer all state mutations to next run loop to avoid
            // "Modifying state during view update" — this .onAppear can fire while
            // SwiftUI is still evaluating the parent view's body.
            DispatchQueue.main.async {
                // FIX v23: Populate cached prices on first appear
                if cachedPaperPrices.isEmpty && PaperTradingManager.shared.isPaperTradingEnabled {
                    cachedPaperPrices = refreshPaperTradingPrices()
                }
                
                // STABILITY FIX v23: Generate initial sparkline cache on appear
                if PaperTradingManager.shared.isPaperTradingEnabled {
                    ensurePaperSparklineCached()
                }
                
                // Generate portfolio sparkline for live mode (uses CoinGecko per-coin data)
                if !PaperTradingManager.shared.isPaperTradingEnabled && !DemoModeManager.shared.isDemoMode {
                    ensurePortfolioSparklineCached()
                }
            }
            
            // FIX v24: Schedule a follow-up refresh 3 seconds after appear.
            // On cold start, the initial refresh uses stale cache data because Firestore/API
            // data hasn't arrived yet. This follow-up catches the fresh data that typically
            // arrives 1-3 seconds after the splash dismisses.
            if PaperTradingManager.shared.isPaperTradingEnabled {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [self] in
                    guard PaperTradingManager.shared.isPaperTradingEnabled else { return }
                    let freshPrices = refreshPaperTradingPrices()
                    // Only update if we got meaningfully different prices (avoids unnecessary re-render)
                    if freshPrices.count != cachedPaperPrices.count ||
                       freshPrices.contains(where: { key, val in
                           guard let cached = cachedPaperPrices[key] else { return true }
                           return abs(val - cached) / max(cached, 0.01) > 0.001  // >0.1% change
                       }) {
                        cachedPaperPrices = freshPrices
                        // STABILITY FIX v23: Regenerate sparkline with fresh data (one-time settle)
                        // FIX v26: forceRegenerate ensures the extension period gets recalculated
                        // with correct prices after the 3-second settle window.
                        ensurePaperSparklineCached(forceRegenerate: true)
                        patchSparklineEndpoint()
                        paperTradingTick &+= 1
                    }
                }
                
                // FIX: Schedule a second follow-up at 6s for cases where Firestore/API
                // data arrives late (e.g. slow network). This ensures portfolio shows
                // correct value even on slow connections.
                DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [self] in
                    guard PaperTradingManager.shared.isPaperTradingEnabled else { return }
                    let latePrices = refreshPaperTradingPrices()
                    // Check if any held asset still has no price
                    let hasMissingPrice = paperTradingManager.paperBalances.keys.contains { asset in
                        let sym = asset.uppercased()
                        guard sym != PaperTradingManager.defaultQuoteCurrency,
                              sym != "USD", sym != "USDC" else { return false }
                        return (latePrices[sym] ?? 0) <= 0
                    }
                    if !hasMissingPrice && latePrices != cachedPaperPrices {
                        cachedPaperPrices = latePrices
                        paperTradingTick &+= 1
                    }
                }
            }
            
            // Schedule follow-up for portfolio sparkline when CoinGecko data arrives
            if !PaperTradingManager.shared.isPaperTradingEnabled && !DemoModeManager.shared.isDemoMode {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [self] in
                    guard !PaperTradingManager.shared.isPaperTradingEnabled else { return }
                    guard !DemoModeManager.shared.isDemoMode else { return }
                    ensurePortfolioSparklineCached()
                }
            }
        }
        // FIX v5.0.3: navigationDestination for AllAIInsightsView moved to HomeView level
        // (outside LazyVStack) to fix SwiftUI lazy container warning.
        // FIX v28: Populate sparkline cache immediately when display mode switches to paper trading.
        // Previously the cache was only populated in .onAppear, which fires AFTER the first body
        // evaluation — causing a blank shimmer on the portfolio sparkline until onAppear ran.
        .onChange(of: displayMode) { _, newMode in
            if newMode == .paperTrading {
                if cachedPaperPrices.isEmpty {
                    cachedPaperPrices = refreshPaperTradingPrices()
                }
                ensurePaperSparklineCached()
            } else if newMode == .live {
                ensurePortfolioSparklineCached()
            }
        }
        .background(
            ZStack {
                // Base card background - matching Portfolio page gradient
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: isDark ? [
                                Color.gray.opacity(0.2),
                                Color.black.opacity(0.4)
                            ] : [
                                Color(red: 1.0, green: 0.995, blue: 0.98),
                                Color(red: 0.96, green: 0.97, blue: 0.98)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Top accent gradient — uses mode color so paper trading has amber tint, portfolio has green
                LinearGradient(
                    colors: [modeAccentColor.opacity(0.06), Color.clear],
                    startPoint: .top,
                    endPoint: .center
                )
                .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
                
                // Glass highlight on top edge
                LinearGradient(
                    colors: [Color.white.opacity(isDark ? 0.08 : 0.5), Color.clear],
                    startPoint: .top,
                    endPoint: .center
                )
                .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            plColor.opacity(isDark ? 0.35 : 0.25),
                            isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .animation(.easeInOut(duration: 0.3), value: rangeChange)
    }
}

// MARK: - PortfolioSectionView Extension
extension PortfolioSectionView {
    // MARK: - Split Views to ease type-checking
    @ViewBuilder
    private var topRow: some View {
        // ZStack: pie chart floats at top-trailing independently.
        // Left VStack (value → P&L → chips) flows with natural spacing —
        // the pie chart height doesn't push the chips down.
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                metricsLeft
                
                // Full-width chips with trailing padding to prevent overlap with pie chart
                // Reserve space for pie chart + small buffer (64pt chart + 8pt buffer = 72pt)
                chipsRow
                    .padding(.top, 2)
                    .padding(.trailing, 72)
            }
            
            // Pie chart positioned with small margin from edge to prevent clipping
            actionsRight
                .offset(x: -4, y: -2) // 4pt margin from right edge, 2pt up for alignment
        }
    }

    // MARK: - Smart Mode Cycling
    
    /// Maps the portfolio display mode to AppTradingMode for consistent color + label sourcing
    private var currentAppMode: AppTradingMode {
        switch displayMode {
        case .paperTrading: return .paper
        case .demo: return .demo
        case .live, .empty: return .portfolio
        }
    }
    
    /// Mode-aware accent color for labels — matches AppTradingMode colors (single source of truth)
    private var modeAccentColor: Color {
        currentAppMode.color
    }

    @ViewBuilder
    private var metricsLeft: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Balance with smooth animation on value changes
            AnimatedPortfolioValue(value: currentTotalValue, hideBalances: hideBalances)
                .onTapGesture {
                    if !hideBalances {
                        // SECURITY: Auto-clear clipboard after 60s for financial data
                        SecurityManager.shared.secureCopy(currentTotalValueString)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }

            // P&L with tappable timeframe label (chevron built into the label)
            dayPLView()
        }
        .layoutPriority(1)
    }
    
    // MARK: - Simulated Mode Indicator
    /// Safety indicator shown ONLY for simulated modes (Demo / Paper).
    /// Portfolio (real) mode shows nothing — it's the default state and needs no label.
    /// Uses the shared ModeBadge for 100% consistent styling across the entire app.
    @ViewBuilder
    private var simulatedModeIndicator: some View {
        switch displayMode {
        case .demo, .paperTrading:
            ModeBadge(mode: currentAppMode, variant: .compact)
            
        case .live, .empty:
            // Real portfolio mode — no indicator needed. The absence of a label
            // means "real data." This is the professional standard.
            EmptyView()
        }
    }

    @ViewBuilder
    private var chipsRow: some View {
        let chips = allocationChips()
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    let sortedChips = chips.sorted { $0.percent > $1.percent }
                    ForEach(sortedChips, id: \.symbol) { s in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(s.color)
                                .frame(width: 7, height: 7)
                                .overlay(
                                    Circle()
                                        .stroke(s.color.opacity(0.3), lineWidth: 1)
                                )
                            
                            Text(s.symbol)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(DS.Adaptive.textPrimary)
                            
                            Text("\(Int(round(s.percent)))%")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(DS.Adaptive.textSecondary)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(s.color.opacity(isDark ? 0.10 : 0.08))
                        )
                        .overlay(
                            Capsule()
                                .stroke(s.color.opacity(isDark ? 0.20 : 0.15), lineWidth: 0.5)
                        )
                        .lineLimit(1)
                        .fixedSize()
                    }
                }
            }
            .frame(height: 24)
        }
    }

    @ViewBuilder
    private var actionsRight: some View {
        // Portfolio allocation donut chart — clean mini version, no center text.
        ThemedPortfolioPieChartView(
            portfolioVM: vm.portfolioVM,
            showLegend: .constant(false),
            allowRotation: false,
            allowSweepOscillation: false,
            showSweepIndicator: false,
            allowHoverScrub: false,
            showSliceCallouts: false,
            showRotatingSheen: false,
            showIdleCenterRing: false,
            showActiveStartTick: false,
            showSliceSeparators: false,
            overrideAllocationData: displayMode == .paperTrading ? paperTradingAllocationSlices : nil,
            centerMode: .hidden
        )
        .frame(width: pieChartSize, height: pieChartSize)
        .clipShape(Circle())
        .accessibilityLabel("Portfolio allocation donut — tap slices to select")
    }

    @ViewBuilder
    private func dayPLView() -> some View {
        // Use range-aware P&L to stay in sync with chart timeframe
        if let rangePL = rangeChangePL() {
            AnimatedPLDisplay(
                amount: rangePL.amount,
                percent: rangePL.percent,
                label: rangePLLabel(),
                hideBalances: hideBalances,
                onLabelTap: {
                    showTimeframePicker = true
                }
            )
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: PortfolioTimeframeButtonFrameKey.self,
                        value: proxy.frame(in: .global)
                    )
                }
            )
            .onPreferenceChange(PortfolioTimeframeButtonFrameKey.self) { frame in
                DispatchQueue.main.async { timeframePickerAnchor = frame }
            }
        }
    }

    private func allocationChips() -> [MiniAllocationChipData] {
        switch displayMode {
        case .paperTrading:
            return paperTradingAllocationChips()
        case .demo, .live, .empty:
            return vm.portfolioVM.allocationData.map { item in
                MiniAllocationChipData(symbol: item.symbol, percent: item.percent, color: item.color)
            }
        }
    }
    
    /// Generate allocation chips from Paper Trading balances
    private func paperTradingAllocationChips() -> [MiniAllocationChipData] {
        let totalValue = paperTradingTotalValue
        guard totalValue > 0 else { return [] }
        
        let prices = paperTradingPrices
        var chips: [MiniAllocationChipData] = []
        
        for (asset, amount) in paperTradingManager.paperBalances where amount > 0.000001 {
            let assetValue: Double
            if asset == "USDT" || asset == "USD" || asset == "USDC" {
                assetValue = amount
            } else if let price = prices[asset] {
                assetValue = amount * price
            } else {
                continue
            }
            
            let percent = (assetValue / totalValue) * 100
            if percent >= 0.5 { // Only show assets with >= 0.5% allocation
                chips.append(MiniAllocationChipData(
                    symbol: asset,
                    percent: percent,
                    color: colorForAsset(asset)
                ))
            }
        }
        
        return chips.sorted { $0.percent > $1.percent }
    }
    
    /// Generate allocation slices for Paper Trading pie chart (uses AllocationSlice type for ThemedPortfolioPieChartView)
    private var paperTradingAllocationSlices: [PortfolioViewModel.AllocationSlice] {
        let totalValue = paperTradingTotalValue
        guard totalValue > 0 else { return [] }
        
        let prices = paperTradingPrices
        var slices: [PortfolioViewModel.AllocationSlice] = []
        
        for (asset, amount) in paperTradingManager.paperBalances where amount > 0.000001 {
            let assetValue: Double
            if asset == "USDT" || asset == "USD" || asset == "USDC" {
                assetValue = amount
            } else if let price = prices[asset] {
                assetValue = amount * price
            } else {
                continue
            }
            
            let percent = (assetValue / totalValue) * 100
            if percent >= 0.5 { // Only show assets with >= 0.5% allocation
                slices.append(PortfolioViewModel.AllocationSlice(
                    symbol: asset,
                    percent: percent,
                    color: colorForAsset(asset)
                ))
            }
        }
        
        return slices.sorted { $0.percent > $1.percent }
    }
    
    /// Get a color for Paper Trading assets — delegates to PortfolioViewModel's
    /// comprehensive color map so all modes share the exact same palette.
    private func colorForAsset(_ asset: String) -> Color {
        vm.portfolioVM.color(for: asset)
    }

    // MARK: - Helpers
    
    /// Returns the raw total value based on current display mode
    private var currentTotalValue: Double {
        switch displayMode {
        case .paperTrading:
            return paperTradingTotalValue
        case .demo, .live, .empty:
            return vm.portfolioVM.totalValue
        }
    }
    
    /// Returns the total value string based on current display mode
    private var currentTotalValueString: String {
        return MarketFormat.price(currentTotalValue)
    }
    
    private var totalValueString: String {
        let v = vm.portfolioVM.totalValue
        return MarketFormat.price(v)
    }

    private func historyForSelectedRange() -> [ChartPoint] {
        switch displayMode {
        case .paperTrading:
            // STABILITY FIX v23: Use cached sparkline instead of regenerating on every access.
            // The cache is populated/refreshed by ensurePaperSparklineCached().
            // MEMORY FIX v7: Do NOT call ensurePaperSparklineCached() here — this computed
            // property is evaluated during the view body. Calling it modifies @State
            // (cachedPaperSparkline, lastSparklineTradeCount, sparklineInitialized), which
            // triggers "Modifying state during view update" and cascading re-renders.
            // Instead, compute the data inline without caching. The cache will be populated
            // by .onAppear and .onReceive handlers on the next run loop.
            if cachedPaperSparkline.isEmpty {
                // Return computed data directly — don't cache during body evaluation
                return paperTradingSparklineData.filtered(for: selectedRange)
            }
            return cachedPaperSparkline.filtered(for: selectedRange)
        case .demo:
            // Demo mode has seeded history that covers 540 days
            return vm.portfolioVM.history.filtered(for: selectedRange)
        case .live:
            // FIX: Prefer CoinGecko-based sparkline over transaction-based history.
            // Transaction-based history uses cost basis (not market prices) and produces
            // empty/flat data when holdings come from exchange sync without manual transactions.
            // CoinGecko sparkline gives accurate market-value history using per-coin hourly data.
            if !cachedPortfolioSparkline.isEmpty {
                return cachedPortfolioSparkline.filtered(for: selectedRange)
            }
            // Fallback to transaction-based history
            return vm.portfolioVM.history.filtered(for: selectedRange)
        case .empty:
            return vm.portfolioVM.history.filtered(for: selectedRange)
        }
    }

    private func rangeChangePercent() -> Double {
        // For Paper Trading, calculate from filtered history for the selected range
        // FIX v27: For All Time / 1 Year, use direct P&L (sparkline only covers 30 days)
        if displayMode == .paperTrading {
            if selectedRange == .all || selectedRange == .year {
                return paperTradingProfitLossPercent
            }
            let pts = historyForSelectedRange()
            let liveTotal = paperTradingTotalValue
            guard pts.count >= 2, let first = pts.first?.value, first > 0 else {
                return paperTradingProfitLossPercent
            }
            let last = liveTotal > 0 ? liveTotal : (pts.last?.value ?? first)
            return (last / first - 1.0) * 100.0
        }
        
        // For Demo/Live modes with daily range, use holdings-based calculation for consistency with top P&L
        if selectedRange == .day {
            return holdingsBasedDailyChangePercent()
        }
        
        let pts = historyForSelectedRange()
        guard pts.count >= 2, let first = pts.first?.value, let last = pts.last?.value, first > 0 else { return 0 }
        return (last / first - 1.0) * 100.0
    }
    
    /// Calculates daily change percent from holdings (consistent with netDayPL for Demo/Live modes)
    private func holdingsBasedDailyChangePercent() -> Double {
        let total = vm.portfolioVM.totalValue
        guard total > 0 else { return 0 }
        let amt = vm.portfolioVM.holdings.reduce(0) { partial, h in
            let pct = h.dailyChange
            guard pct.isFinite else { return partial }
            return partial + h.currentValue * (pct / 100.0)
        }
        return (amt / total) * 100.0
    }
    
    /// Calculates daily change amount from holdings (consistent with netDayPL for Demo/Live modes)
    private func holdingsBasedDailyChangeAmount() -> Double {
        vm.portfolioVM.holdings.reduce(0) { partial, h in
            let pct = h.dailyChange
            guard pct.isFinite else { return partial }
            return partial + h.currentValue * (pct / 100.0)
        }
    }

    private func rangeChangePercentString() -> String {
        let p = rangeChangePercent()
        let sign = p >= 0 ? "+" : ""
        return String(format: "%@%.2f%%", sign, p)
    }

    private func rangeChangeAmountString() -> String {
        // For Paper Trading, calculate from filtered history for the selected range
        // FIX v27: For All Time / 1 Year, use direct P&L (sparkline only covers 30 days)
        if displayMode == .paperTrading {
            if selectedRange == .all || selectedRange == .year {
                let delta = paperTradingProfitLoss
                let sign = delta >= 0 ? "+" : ""
                return sign + MarketFormat.price(abs(delta))
            }
            let pts = historyForSelectedRange()
            let liveTotal = paperTradingTotalValue
            guard pts.count >= 2, let first = pts.first?.value else {
                let delta = paperTradingProfitLoss
                let sign = delta >= 0 ? "+" : ""
                return sign + MarketFormat.price(abs(delta))
            }
            let last = liveTotal > 0 ? liveTotal : (pts.last?.value ?? first)
            let delta = last - first
            let sign = delta >= 0 ? "+" : ""
            return sign + MarketFormat.price(abs(delta))
        }
        
        // For Demo/Live modes with daily range, use holdings-based calculation for consistency with top P&L
        if selectedRange == .day {
            let delta = holdingsBasedDailyChangeAmount()
            let sign = delta >= 0 ? "+" : ""
            return sign + MarketFormat.price(abs(delta))
        }
        
        let pts = historyForSelectedRange()
        guard pts.count >= 2, let first = pts.first?.value, let last = pts.last?.value else { return "+$0.00" }
        let delta = last - first
        let sign = delta >= 0 ? "+" : ""
        return sign + MarketFormat.price(abs(delta))
    }

    private func netDayPL() -> (amount: Double, percent: Double)? {
        switch displayMode {
        case .paperTrading:
            // For Paper Trading, show all-time P&L since we don't have daily history
            let pnl = paperTradingProfitLoss
            let pnlPercent = paperTradingProfitLossPercent
            // Only show if there's been any trading activity
            if paperTradingManager.totalTradeCount > 0 || abs(pnl) > 0.01 {
                return (pnl, pnlPercent)
            }
            return nil
        case .demo, .live, .empty:
            let total = vm.portfolioVM.totalValue
            guard total > 0 else { return nil }
            let amt = vm.portfolioVM.holdings.reduce(0) { partial, h in
                let pct = h.dailyChange
                guard pct.isFinite else { return partial }
                return partial + h.currentValue * (pct / 100.0)
            }
            return (amt, (amt / total) * 100.0)
        }
    }
    
    /// Returns P&L (amount, percent) for the selected timeframe range
    /// This keeps the top P&L display in sync with the chart timeframe
    private func rangeChangePL() -> (amount: Double, percent: Double)? {
        switch displayMode {
        case .paperTrading:
            // FIX v27: For "All Time" and "1 Year", use the direct P&L calculation
            // against initialPortfolioValue instead of sparkline data. The sparkline
            // only covers ~30 days, so it can't accurately represent longer periods.
            if selectedRange == .all || selectedRange == .year {
                let pnl = paperTradingProfitLoss
                let pnlPercent = paperTradingProfitLossPercent
                if paperTradingManager.totalTradeCount > 0 || abs(pnl) > 0.01 {
                    return (pnl, pnlPercent)
                }
                return nil
            }
            
            // For Paper Trading (day/week/month), calculate from filtered history
            // FIX v26: Always use live paperTradingTotalValue as the "last" value, NOT the
            // stale cached sparkline endpoint. The sparkline is generated once and cached,
            // so its last point may be from when prices were incomplete/wrong. The live
            // total is computed from current market prices and is always accurate.
            let pts = historyForSelectedRange()
            let liveTotal = paperTradingTotalValue
            guard pts.count >= 2, let first = pts.first?.value, first > 0 else {
                // Fallback to all-time P&L if no history data
                let pnl = paperTradingProfitLoss
                let pnlPercent = paperTradingProfitLossPercent
                if paperTradingManager.totalTradeCount > 0 || abs(pnl) > 0.01 {
                    return (pnl, pnlPercent)
                }
                return nil
            }
            let last = liveTotal > 0 ? liveTotal : (pts.last?.value ?? first)
            let amount = last - first
            let percent = (last / first - 1.0) * 100.0
            return (amount, percent)
            
        case .demo, .live, .empty:
            // For daily range, use holdings-based calculation for accuracy
            if selectedRange == .day {
                let total = vm.portfolioVM.totalValue
                guard total > 0 else { return nil }
                let amt = holdingsBasedDailyChangeAmount()
                return (amt, holdingsBasedDailyChangePercent())
            }
            
            // For other ranges, calculate from history points
            let pts = historyForSelectedRange()
            guard pts.count >= 2, let first = pts.first?.value, let last = pts.last?.value, first > 0 else { return nil }
            let amount = last - first
            let percent = (last / first - 1.0) * 100.0
            return (amount, percent)
        }
    }
    
    /// Returns the label for the current selected range (e.g., "Today", "1 Week", "1 Month")
    /// Same labels for all modes - P&L context is implied by the +/- amount
    private func rangePLLabel() -> String {
        switch selectedRange {
        case .day: return "Today"
        case .week: return "1 Week"
        case .month: return "1 Month"
        case .year: return "1 Year"
        case .all: return "All Time"
        }
    }
    
    /// Returns sparkline values with the last point updated to match the current live portfolio value
    private func sparklineValuesWithLiveUpdate() -> (values: [Double], dates: [Date]) {
        let pts = historyForSelectedRange()
        var values = pts.map { $0.value }
        var dates = pts.map { $0.date }
        
        // Ensure the rightmost value matches the current live portfolio value
        // This prevents the scrub tooltip from showing stale data at the chart edge
        let liveValue: Double = {
            switch displayMode {
            case .paperTrading:
                return paperTradingTotalValue
            case .demo, .live, .empty:
                return vm.portfolioVM.totalValue
            }
        }()
        
        // Update the last data point to match live value (if we have history and live value is valid)
        if !values.isEmpty && liveValue > 0 {
            values[values.count - 1] = liveValue
            dates[dates.count - 1] = Date()
        }
        
        return (values, dates)
    }
    
    @ViewBuilder
    private var sparklineView: some View {
        let data = sparklineValuesWithLiveUpdate()
        let values = data.values
        let dates = data.dates
        
        if values.count > 1 {
            let isUp = rangeChangePercent() >= 0
            let percentText = hideBalances ? "•••%" : rangeChangePercentString()
            let amountText = hideBalances ? "•••••" : rangeChangeAmountString()
            
            PremiumPortfolioSparkline(
                values: values,
                dates: dates,
                selectedRange: selectedRange,
                color: isUp ? .green : .red,
                percentText: percentText,
                amountText: amountText,
                isUp: isUp,
                showAmount: $showSparkAmount,
                hideBalances: hideBalances
            )
            .frame(height: 62)
            .contentShape(Rectangle())
            // STABILITY FIX: Removed .id() modifier that was causing view recreation
            // and 2-second disappearance. SwiftUI's built-in diffing is sufficient.
            .transaction { $0.disablesAnimations = true }
        } else {
            // STABILITY FIX: Show placeholder when data is loading to prevent blank gaps
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(DS.Adaptive.stroke, lineWidth: 1)
                )
                .frame(height: 62)
                .overlay(
                    // Subtle loading shimmer
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.clear, Color.white.opacity(0.05), Color.clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
        }
    }
    
    // MARK: - AI Insights Section (tappable insight + Ask AI prompts)
    
    @ViewBuilder
    private var compactAskAIRow: some View {
        let goldTextColor = isDark ? BrandColors.goldLight : Color(red: 0.6, green: 0.45, blue: 0.1)
        
        VStack(alignment: .leading, spacing: 0) {
            // AI Insight Row (tappable - opens chat with contextual prompt)
            if let insight = aiInsight {
                Button(action: {
                    if let onOpenChat = onOpenChat {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onOpenChat(insight.prompt)
                    }
                }) {
                    HStack(spacing: 5) {
                        // Sparkle icon — subtle, refined
                        Image(systemName: "sparkles")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(goldTextColor)
                        
                        // Insight text — compact, single line for cleaner look
                        Text(hideBalances ? "•••••" : insight.text)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(DS.Adaptive.textPrimary.opacity(0.88))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 10)
                }
                .buttonStyle(.plain)
            }
            
            // Divider between insight and Ask AI
            if aiInsight != nil {
                Rectangle()
                    .fill(DS.Adaptive.divider.opacity(0.3))
                    .frame(height: 0.5)
                    .padding(.horizontal, 10)
            }
            
            // Ask AI row - browse more prompts
            HStack(spacing: 0) {
                // Chat icon + Ask AI label
                HStack(spacing: 3) {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(goldTextColor.opacity(0.65))
                    
                    Text("Ask AI")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(goldTextColor.opacity(0.8))
                }
                .padding(.leading, 10)
                
                // Navigation chevron left
                Button(action: {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    lastInteraction = Date()
                    withAnimation { promptIndex = (promptIndex - 1 + max(1, prompts.count)) % max(1, prompts.count) }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(goldTextColor.opacity(0.5))
                        .frame(width: 20, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                // Prompt text (tappable)
                Button(action: {
                    if let onOpenChat = onOpenChat {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onOpenChat(currentPrompt)
                    }
                }) {
                    Text(hideBalances ? "•••••" : currentPrompt)
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(DS.Adaptive.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                
                // Navigation chevron right
                Button(action: {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    lastInteraction = Date()
                    withAnimation { promptIndex = (promptIndex + 1) % max(1, prompts.count) }
                }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(goldTextColor.opacity(0.5))
                        .frame(width: 22, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 2)
            }
            .padding(.vertical, 5)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: isDark ? [
                            Color(red: 0.08, green: 0.08, blue: 0.10),
                            Color(red: 0.06, green: 0.06, blue: 0.08)
                        ] : [
                            Color(red: 0.985, green: 0.98, blue: 0.965),
                            Color(red: 0.975, green: 0.97, blue: 0.955)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DS.Adaptive.divider.opacity(0.35), lineWidth: 0.5)
        )
    }
    
    // MARK: - Legacy Insight Tip Row (kept for reference, no longer used)
    
    @ViewBuilder
    private func insightTipRow(tip: String) -> some View {
        EmptyView() // Replaced by unifiedInsightBlock
    }
    
    @ViewBuilder
    private func insightChip(text: String, style: InsightChipStyle) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(style.foregroundColor(isDark: isDark))
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Capsule().fill(style.backgroundColor(isDark: isDark)))
            .overlay(Capsule().stroke(style.strokeColor(isDark: isDark), lineWidth: 1))
    }
    
    // MARK: - Compact Ask AI Bar
    
    @ViewBuilder
    private var compactAskAIBar: some View {
        let goldTextColor = isDark ? BrandColors.goldLight : Color(red: 0.6, green: 0.45, blue: 0.1)
        
        HStack(spacing: 0) {
            // Chat icon + Ask AI label - compact
            HStack(spacing: 3) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(goldTextColor.opacity(0.7))
                Text("Ask AI")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(goldTextColor.opacity(0.85))
            }
            .padding(.leading, 10)
            
            // Navigation chevron left - compact
            Button(action: {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                lastInteraction = Date()
                withAnimation { promptIndex = (promptIndex - 1 + max(1, prompts.count)) % max(1, prompts.count) }
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(goldTextColor.opacity(0.6))
                    .frame(width: 22, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous prompt")
            
            // Prompt text (tappable) - gets more space now
            Button(action: {
                if let onOpenChat = onOpenChat {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onOpenChat(currentPrompt)
                }
            }) {
                Text(hideBalances ? "•••••" : currentPrompt)
                    .font(.footnote)
                    .foregroundStyle(DS.Adaptive.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            
            // Navigation chevron right - compact, flush to edge
            Button(action: {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                lastInteraction = Date()
                withAnimation { promptIndex = (promptIndex + 1) % max(1, prompts.count) }
            }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(goldTextColor.opacity(0.6))
                    .frame(width: 26, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next prompt")
            .padding(.trailing, 2)
        }
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [goldTextColor.opacity(0.25), DS.Adaptive.divider.opacity(0.4)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .padding(.top, 8)
    }
    
    // MARK: - More AI Insights Link
    
    @ViewBuilder
    private var moreInsightsLink: some View {
        SectionCTAButton(title: "Portfolio Insights", icon: "chart.pie.fill", compact: true) {
            showAllInsights = true
        }
        .padding(.top, 6)
    }
}

// MARK: - Insight Chip Style
private enum InsightChipStyle {
    case gold
    case positive
    case negative
    case neutral
    
    func foregroundColor(isDark: Bool) -> Color {
        switch self {
        case .gold: return isDark ? BrandColors.goldLight : Color(red: 0.6, green: 0.45, blue: 0.1)
        case .positive: return .green
        case .negative: return .red
        case .neutral: return .secondary
        }
    }
    
    func backgroundColor(isDark: Bool) -> Color {
        switch self {
        case .gold: return foregroundColor(isDark: isDark).opacity(isDark ? 0.12 : 0.1)
        case .positive: return Color.green.opacity(0.15)
        case .negative: return Color.red.opacity(0.15)
        case .neutral: return DS.Adaptive.surfaceOverlay
        }
    }
    
    func strokeColor(isDark: Bool) -> Color {
        switch self {
        case .gold: return foregroundColor(isDark: isDark).opacity(isDark ? 0.28 : 0.25)
        case .positive, .negative, .neutral: return DS.Adaptive.divider
        }
    }
}

// Local compact timeframe picker used in this section
// Uses parent's overlay state for consistent full-screen rendering
// PROFESSIONAL UX: Shows active state when picker is open
private struct PortfolioTimeframePickerPillSmall: View {
    @Binding var selectedRange: HomeView.PortfolioRange
    @Binding var showPicker: Bool
    @Binding var anchorFrame: CGRect
    
    @Environment(\.colorScheme) private var colorScheme
    
    /// Returns the abbreviated label for the button (e.g., "1D", "1W", "1M")
    private var rangeLabel: String {
        selectedRange.rawValue
    }

    var body: some View {
        let isDark = colorScheme == .dark
        // Subtle gold accent for timeframe picker to distinguish from allocation chips
        let accentGold = Color(red: 0.85, green: 0.72, blue: 0.45)
        
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            showPicker = true
        } label: {
            HStack(spacing: 4) {
                Text(rangeLabel)
                    .font(.system(size: 10, weight: .bold))
                    .lineLimit(1)
                    .fixedSize()
                
                Image(systemName: showPicker ? "chevron.up" : "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(showPicker ? accentGold : DS.Adaptive.textSecondary)
            }
            .foregroundStyle(showPicker ? accentGold : DS.Adaptive.textPrimary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .frame(height: 22)
            .background(
                Capsule()
                    // PROFESSIONAL UX: Subtle gold tint background when active
                    .fill(showPicker 
                          ? accentGold.opacity(isDark ? 0.15 : 0.12)
                          : DS.Adaptive.chipBackground)
            )
            .overlay(
                Capsule()
                    .stroke(
                        // PROFESSIONAL UX: Stronger gold border when active
                        LinearGradient(
                            colors: showPicker
                                ? [accentGold, accentGold]
                                : [
                                    accentGold.opacity(isDark ? 0.5 : 0.4),
                                    accentGold.opacity(isDark ? 0.25 : 0.2)
                                ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: showPicker ? 1.0 : 0.75
                    )
            )
            .contentShape(Capsule())
            .fixedSize()
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: showPicker)
        .accessibilityLabel("Timeframe \(rangeLabel)")
        .zIndex(3)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: PortfolioTimeframeButtonFrameKey.self, value: proxy.frame(in: .global))
            }
        )
        .onPreferenceChange(PortfolioTimeframeButtonFrameKey.self) { frame in
            // Defer state modification to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                anchorFrame = frame
            }
        }
    }
}

// Preference key for tracking button frame
// PERFORMANCE FIX v25: Increased jitter threshold and throttle interval to eliminate
// "Bound preference tried to update multiple times per frame" warning.
// The warning occurs because GeometryReader fires multiple reduce() calls per layout pass.
// By requiring a minimum 10px change AND 0.3s between updates, we coalesce these
// into a single meaningful update per interaction.
private struct PortfolioTimeframeButtonFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    nonisolated(unsafe) private static var lastUpdateAt: CFTimeInterval = 0
    nonisolated(unsafe) private static var lastValue: CGRect = .zero
    
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        guard next != .zero else { return }
        
        // PERFORMANCE FIX v25: More aggressive throttle - 0.5s always, 1.0s during scroll
        // Previous values (0.2s/0.5s) still allowed multiple-per-frame updates
        let now = CACurrentMediaTime()
        let throttleInterval: CFTimeInterval = MainActor.assumeIsolated { ScrollStateManager.shared.shouldBlockHeavyOperation() } ? 1.0 : 0.5
        guard now - lastUpdateAt >= throttleInterval else { return }
        
        // Ignore jitter (changes < 10px) - increased from 5px
        // The button frame rarely moves by less than 10px in a meaningful way
        let dx = abs(next.origin.x - lastValue.origin.x)
        let dy = abs(next.origin.y - lastValue.origin.y)
        if dx < 10 && dy < 10 && abs(next.width - lastValue.width) < 10 { return }
        
        value = next
        lastValue = next
        lastUpdateAt = now
    }
}

// MARK: - Portfolio Timeframe Picker (Grid-style, matching ChartTimeframePicker design)
/// A beautiful grid-style timeframe picker for portfolio history ranges
private struct PortfolioTimeframePicker: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var isPresented: Bool
    @Binding var selection: HomeView.PortfolioRange
    
    private let ranges: [HomeView.PortfolioRange] = HomeView.PortfolioRange.allCases
    
    var body: some View {
        VStack(spacing: 4) {
            // Header
            HStack {
                Text("Timeframe")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer(minLength: 6)
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
                .frame(height: 1)
                .padding(.horizontal, 6)
            
            // Grid of timeframe chips
            let minChipWidth: CGFloat = 56
            let spacing: CGFloat = 5
            let horizontalPadding: CGFloat = 6
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: minChipWidth), spacing: spacing)],
                alignment: .center,
                spacing: spacing
            ) {
                ForEach(ranges, id: \.self) { range in
                    timeframeChip(for: range)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 2)
            .padding(.bottom, 2)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(4)
        // PERFORMANCE FIX v19: Replaced .ultraThinMaterial with solid color
        // Material effects perform real-time Gaussian blur every frame during scroll
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
        .tint(DS.Colors.gold)
        .frame(minWidth: 236, maxWidth: 320)
    }
    
    @ViewBuilder
    private func timeframeChip(for range: HomeView.PortfolioRange) -> some View {
        let selected = (range == selection)
        let label = chipLabel(for: range)
        
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
                selection = range
            }
            isPresented = false
        } label: {
            Text(label)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .foregroundStyle(selected ? Color.black : Color.white.opacity(0.92))
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .background(
                    ZStack {
                        Capsule()
                            .fill(selected ? AnyShapeStyle(AdaptiveGradients.chipGold(isDark: colorScheme == .dark)) : AnyShapeStyle(Color.white.opacity(0.08)))
                        // Top gloss
                        Capsule()
                            .fill(LinearGradient(colors: [Color.white.opacity(selected ? 0.18 : 0.10), .clear], startPoint: .top, endPoint: .center))
                        // Rim
                        Capsule()
                            .stroke(selected ? AnyShapeStyle(ctaRimStrokeGradient) : AnyShapeStyle(Color.white.opacity(0.12)), lineWidth: 0.8)
                    }
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(selection == range ? .isSelected : [])
    }
    
    private func chipLabel(for range: HomeView.PortfolioRange) -> String {
        switch range {
        case .day: return "Today"
        case .week: return "1 Week"
        case .month: return "1 Month"
        case .year: return "1 Year"
        case .all: return "All Time"
        }
    }
}

// MARK: - Premium Portfolio Sparkline (Uses SparklineView for premium rendering)
/// A premium portfolio sparkline that uses the same high-quality SparklineView
/// as the watchlist section, with change pill and scrub overlays
private struct PremiumPortfolioSparkline: View {
    let values: [Double]
    let dates: [Date]
    let selectedRange: HomeView.PortfolioRange
    let color: Color
    let percentText: String
    let amountText: String
    let isUp: Bool
    @Binding var showAmount: Bool
    var hideBalances: Bool = false
    
    @State private var isScrubbing: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Premium background card
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(DS.Adaptive.stroke, lineWidth: 1)
                )
            
            // Color gradient overlay at bottom - enhanced for better visibility
            LinearGradient(
                colors: [color.opacity(0.38), color.opacity(0.15), .clear],
                startPoint: .bottom,
                endPoint: .top
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            
            // SparklineView - the same premium renderer used by watchlist
            // Uses horizontalInset to prevent end dot (with pulse animation) from being clipped
            SparklineView(
                data: values,
                isPositive: isUp,
                height: 62,
                lineWidth: SparklineConsistency.listLineWidth - 0.2,
                verticalPaddingRatio: SparklineConsistency.listVerticalPaddingRatio,
                fillOpacity: 0.38,
                gradientStroke: true,
                showEndDot: true,
                leadingFade: 0.0,
                trailingFade: 0.0,
                showTrailHighlight: true,
                trailLengthRatio: 0.25,
                endDotPulse: true,
                backgroundStyle: .none,
                cornerRadius: 10,
                glowOpacity: SparklineConsistency.listGlowOpacity + 0.06,
                glowLineWidth: SparklineConsistency.listGlowLineWidth - 0.6,
                smoothSamplesPerSegment: SparklineConsistency.listSmoothSamplesPerSegment + 1,
                maxPlottedPoints: SparklineConsistency.listMaxPlottedPoints + 40,
                showBackground: false,
                showExtremaDots: false,
                neonTrail: true,
                crispEnds: true,
                horizontalInset: SparklineConsistency.listHorizontalInset + 2,  // Prevents end dot clipping at edges
                compact: false,
                seriesOrder: .oldestToNewest
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            
            // Scrub overlay for interactive exploration
            PortfolioSparklineScrubOverlay(
                values: values,
                dates: dates,
                selectedRange: selectedRange,
                color: color,
                isActive: $isScrubbing,
                hideBalances: hideBalances
            )
            
            // Change pill overlay (top-left)
            PortfolioChangePill(
                values: values,
                isUp: isUp,
                showAmount: $showAmount,
                percentText: percentText,
                amountText: amountText
            )
            .opacity(isScrubbing ? 0 : 1)
            .animation(.easeInOut(duration: 0.15), value: isScrubbing)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Portfolio Scrub Overlay
private struct PortfolioSparklineScrubOverlay: View {
    let values: [Double]
    let dates: [Date]
    let selectedRange: HomeView.PortfolioRange
    let color: Color
    @Binding var isActive: Bool
    var hideBalances: Bool = false
    
    @State private var x: CGFloat = .zero
    @State private var lastIndex: Int? = nil
    
    // Advanced haptics state (matching CryptoChartView)
    // HAPTIC FIX: Session min/max track the range USER HAS EXPLORED during this scrub session.
    // They start as nil, get set to the FIRST value touched, then expand as user explores new territory.
    // This gives haptic feedback when user discovers new highs/lows within their scrub session.
    @State private var lastAboveBaseline: Bool? = nil
    @State private var hapticSessionMin: Double? = nil
    @State private var hapticSessionMax: Double? = nil
    @State private var hapticSessionStarted: Bool = false
    
    var body: some View {
        GeometryReader { g in
            // Must match SparklineView's layout exactly:
            // - SparklineView has .padding(.horizontal, 8) applied outside
            // - SparklineView has horizontalInset: 10 applied to TRAILING EDGE ONLY (for end dot)
            // - SparklineView has .padding(.vertical, 10) applied outside
            // - SparklineView has verticalPaddingRatio: 0.12 inside
            let outerPadH: CGFloat = 8      // SparklineView's .padding(.horizontal, 8)
            let innerInsetH: CGFloat = 10   // SparklineView's horizontalInset: 10 (trailing only!)
            
            // ASYMMETRIC BOUNDS: SparklineView starts data at x=0 (no leading inset), only trailing inset
            let leftPad: CGFloat = outerPadH                  // 8pt - first data point position
            let rightPad: CGFloat = outerPadH + innerInsetH   // 18pt - last data point position (trailing inset)
            
            let outerPadV: CGFloat = 10     // SparklineView's .padding(.vertical, 10)
            let innerPadRatio: CGFloat = 0.12  // SparklineView's verticalPaddingRatio: 0.12
            let chartHeight: CGFloat = g.size.height - outerPadV * 2
            let innerPadV: CGFloat = chartHeight * innerPadRatio
            let totalPadV: CGFloat = outerPadV + innerPadV
            
            // The actual drawing area for data points (asymmetric: leftPad + rightPad)
            let dataWidth = max(1, g.size.width - leftPad - rightPad)
            let dataHeight = max(1, g.size.height - outerPadV * 2 - innerPadV * 2)
            
            let count = values.count
            // SCRUB BOUNDS FIX: Use asymmetric bounds matching SparklineView's trailing-only inset
            // Left bound: where first data point is drawn (leftPad = 8pt)
            // Right bound: where last data point is drawn (g.size.width - rightPad = width - 18pt)
            let clampedX = min(max(x, leftPad), g.size.width - rightPad)
            // Calculate data position - clamp t to [0, 1] so edge touches still select first/last points
            let t = min(max((clampedX - leftPad) / max(dataWidth, 1), 0), 1)
            let idx = min(max(Int(round(t * CGFloat(max(count - 1, 0)))), 0), max(count - 1, 0))
            let minV = values.min() ?? 0
            let maxV = values.max() ?? 1
            let range = max(maxV - minV, 0.0001)
            let val = (idx < count && idx >= 0) ? values[idx] : (values.last ?? 0)
            let first = values.first ?? val
            // Y position matches SparklineView's data drawing area
            let y = totalPadV + dataHeight * (1 - CGFloat((val - minV) / range))
            
            // Tooltip dimensions - estimate based on content
            // Price text like "$95,480.37 (-4.13%)" is ~140pt, date like "Tue, Jan 27, 2026" is ~120pt
            let tooltipWidth: CGFloat = 155
            let tooltipHeight: CGFloat = 42
            
            // Clamp tooltip X to keep it fully visible within the chart area
            // Use outer padding for tooltip bounds (tooltip can extend beyond data area)
            let leftBound = outerPadH + tooltipWidth / 2 + 4
            let rightBound = g.size.width - outerPadH - tooltipWidth / 2 - 4
            let tooltipX = min(max(clampedX, leftBound), rightBound)
            
            // Clamp tooltip Y to keep it visible (above the scrub point, but not off screen)
            let baseTooltipY = max(y - 24, tooltipHeight / 2 + 4)
            // Push down if we're on the left side to avoid the change pill
            let avoidPillY: CGFloat = 36
            let adjustedTooltipY = (clampedX < g.size.width * 0.4) ? max(baseTooltipY, avoidPillY) : baseTooltipY
            
            ZStack {
                // Invisible touch target - MUST be here to receive gestures when not active
                Color.clear
                
                if isActive {
                    // Vertical guide line
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 1)
                        .position(x: clampedX, y: g.size.height / 2)
                    
                    // Scrub dot
                    ZStack {
                        Circle()
                            .fill(color)
                            .frame(width: 8, height: 8)
                        Circle()
                            .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5)
                            .frame(width: 12, height: 12)
                    }
                    .position(x: clampedX, y: y)
                    
                    // Value tooltip with date
                    let formatted = hideBalances ? "••••••" : MarketFormat.price(val)
                    let pct: Double = first > 0 ? ((val / first) - 1.0) * 100.0 : 0
                    let pctText = hideBalances ? "•••%" : (first > 0 ? String(format: "%+.2f%%", pct) : nil)
                    let priceText = pctText != nil ? "\(formatted) (\(pctText!))" : formatted
                    
                    // Format date based on selected range
                    let currentDate = (idx < dates.count && idx >= 0) ? dates[idx] : (dates.last ?? Date())
                    let dateText: String = {
                        switch selectedRange {
                        case .day, .week:
                            // Intraday format: "Mon, Jan 29 • 10:52 AM"
                            return ChartDateFormatters.uses24hClock
                                ? ChartDateFormatters.dfCrossIntraday24.string(from: currentDate)
                                : ChartDateFormatters.dfCrossIntraday12.string(from: currentDate)
                        case .month, .year, .all:
                            // Long format: "Mon, Jan 29, 2026"
                            return ChartDateFormatters.dfCrossLong.string(from: currentDate)
                        }
                    }()
                    
                    VStack(spacing: 2) {
                        Text(priceText)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        Text(dateText)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black.opacity(0.85))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.2), lineWidth: 0.8))
                    )
                    .position(x: tooltipX, y: adjustedTooltipY)
                }
            }
            .contentShape(Rectangle())
            // PERFORMANCE FIX: Use simple DragGesture with minimumDistance to avoid scroll conflict
            // The 120ms LongPress was causing lag - users expect immediate response
            .gesture(
                DragGesture(minimumDistance: 4) // Small threshold to distinguish from scroll
                    .onChanged { drag in
                        // Set position from drag location
                        x = drag.location.x
                        
                        // Activate on first drag event
                        if !isActive {
                            isActive = true
                            #if os(iOS)
                            // Fire haptic immediately for responsive feel
                            ChartHaptics.shared.begin(startBump: true)
                            // Reset session tracking
                            hapticSessionStarted = false
                            hapticSessionMin = nil
                            hapticSessionMax = nil
                            #endif
                        }
                        
                        // Recalculate t and idx with current x value
                        let currentClampedX = min(max(x, leftPad), g.size.width - rightPad)
                        let currentT = min(max((currentClampedX - leftPad) / max(dataWidth, 1), 0), 1)
                        let newIdx = min(max(Int(round(currentT * CGFloat(max(count - 1, 0)))), 0), max(count - 1, 0))
                        let currentVal = (newIdx < count && newIdx >= 0) ? values[newIdx] : (values.last ?? 0)
                        
                        // Tick haptic on index change
                        if newIdx != lastIndex {
                            #if os(iOS)
                            ChartHaptics.shared.tickIfNeeded()
                            #endif
                            lastIndex = newIdx
                        }
                        
                        #if os(iOS)
                        // Zero-crossing haptic (major feedback when crossing baseline/first value)
                        let baseline = values.first ?? currentVal
                        let isAbove = currentVal >= baseline
                        if let prev = lastAboveBaseline, prev != isAbove {
                            ChartHaptics.shared.majorIfNeeded(intensity: 0.9)
                        }
                        lastAboveBaseline = isAbove
                        
                        // Track user's exploration range
                        if !hapticSessionStarted {
                            hapticSessionMin = currentVal
                            hapticSessionMax = currentVal
                            hapticSessionStarted = true
                        } else {
                            if let mn = hapticSessionMin, currentVal < mn {
                                hapticSessionMin = currentVal
                                ChartHaptics.shared.majorIfNeeded(intensity: 0.9)
                            }
                            if let mx = hapticSessionMax, currentVal > mx {
                                hapticSessionMax = currentVal
                                ChartHaptics.shared.majorIfNeeded(intensity: 0.9)
                            }
                        }
                        #endif
                    }
                    .onEnded { _ in
                        #if os(iOS)
                        ChartHaptics.shared.end(endBump: true)
                        #endif
                        isActive = false
                        lastIndex = nil
                        x = .zero
                        lastAboveBaseline = nil
                        hapticSessionMin = nil
                        hapticSessionMax = nil
                        hapticSessionStarted = false
                    }
            )
        }
    }
}

// MARK: - Portfolio Change Pill
private struct PortfolioChangePill: View {
    let values: [Double]
    let isUp: Bool
    @Binding var showAmount: Bool
    let percentText: String
    let amountText: String
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        let tint = isUp ? Color.green : Color.red
        
        Button {
            showAmount.toggle()
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        } label: {
            Text(showAmount ? amountText : percentText)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .contentTransition(.numericText())
                // Adaptive text: white in dark mode, tint color in light mode for readability
                .foregroundColor(isDark ? .white.opacity(0.95) : tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    ZStack {
                        // PERFORMANCE FIX v19: Replaced .ultraThinMaterial with solid color
                        if isDark {
                            Capsule(style: .continuous)
                                .fill(Color(white: 0.15))
                            Capsule(style: .continuous)
                                .fill(tint.opacity(0.15))
                        } else {
                            // Light mode: cream background with tint wash
                            Capsule(style: .continuous)
                                .fill(Color(red: 1.0, green: 0.992, blue: 0.973)) // Warm cream
                            Capsule(style: .continuous)
                                .fill(tint.opacity(0.08))
                        }
                        Capsule(style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: isDark 
                                        ? [tint.opacity(0.6), Color.white.opacity(0.2)]
                                        : [tint.opacity(0.4), tint.opacity(0.15)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.75
                            )
                    }
                )
                // Adaptive shadow: colored in dark mode, warm subtle in light mode
        }
        .buttonStyle(.plain)
        .padding(.leading, 10)
        .padding(.top, 6)
        .animation(.easeInOut(duration: 0.2), value: showAmount)
    }
}

// MARK: - Legacy PortfolioHeaderSparklineCard (kept for backwards compatibility)
// Local simplified sparkline card (uses HomeLineChart for the line)
private struct PortfolioHeaderSparklineCard: View {
    let values: [Double]
    let color: Color
    let percentText: String
    let amountText: String
    let isUp: Bool
    let trailingInset: CGFloat
    @Binding var selectedRange: HomeView.PortfolioRange
    @Binding var showAmount: Bool
    var hideBalances: Bool = false
    @State private var showDetails: Bool = false

    var body: some View
    {
        let endpointExtra: CGFloat = 8
        let adaptiveInset: CGFloat = max(0, trailingInset) + endpointExtra
        let smoothing = smoothingForRange(selectedRange, count: values.count)
        let energy = volatilityEnergy(values)

        SparklineCardLayers(
            values: values,
            color: color,
            isUp: isUp,
            adaptiveInset: adaptiveInset,
            showAmount: $showAmount,
            percentText: percentText,
            amountText: amountText,
            smooth: smoothing.smooth,
            tension: smoothing.tension,
            energy: energy,
            hideBalances: hideBalances
        )
    }

    private func smoothingForRange(_ range: HomeView.PortfolioRange, count: Int) -> (smooth: Bool, tension: CGFloat) {
        // Prefer smoother curves for short ranges, straighter for longer
        switch range {
        case .day:
            return (true, 0.65)
        case .week:
            return (true, 0.6)
        case .month:
            return (true, 0.55)
        case .year:
            return (count > 80, 0.45)
        case .all:
            return (false, 0.4)
        }
    }

    private func volatilityEnergy(_ values: [Double]) -> Double {
        guard values.count > 2 else { return 0.0 }
        var prev = values.first!
        var accum: Double = 0
        var n: Double = 0
        for v in values.dropFirst() {
            let denom = max(abs(prev), 1e-9)
            let pct = abs((v - prev) / denom)
            accum += pct
            n += 1
            prev = v
        }
        let avg = accum / max(n, 1)
        // Map a typical 0..0.02 avg change into 0..1 energy (clamped)
        let energy = min(max(avg / 0.02, 0), 1)
        return energy
    }
}

// Lightweight model to simplify type-checking in chips row
private struct MiniAllocationChipData {
    let symbol: String
    let percent: Double
    let color: Color
}

// Extracted chips row to reduce complexity in main body
private struct AllocationChipsRow: View {
    let chips: [MiniAllocationChipData]
    @Binding var selectedRange: HomeView.PortfolioRange
    
    @Environment(\.colorScheme) private var colorScheme

    private let chipSpacing: CGFloat = 5
    private let rowHeight: CGFloat = 26

    var body: some View {
        HStack(spacing: chipSpacing) {
            ForEach(chips, id: \.symbol) { s in
                HStack(spacing: 4) {
                    // Color indicator with subtle glow
                    Circle()
                        .fill(s.color)
                        .frame(width: 7, height: 7)
                    
                    // Symbol and percentage with better hierarchy
                    Text("\(s.symbol)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(DS.Adaptive.textPrimary)
                    + Text(" \(Int(round(s.percent)))%")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(DS.Adaptive.textSecondary)
                }
                .lineLimit(1)
                .allowsTightening(true)
                .monospacedDigit()
                .fixedSize()
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .frame(height: rowHeight)
                .background(
                    Capsule()
                        .fill(DS.Adaptive.chipBackground)
                )
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    DS.Adaptive.stroke.opacity(0.6),
                                    DS.Adaptive.stroke.opacity(0.3)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                )
                .fixedSize()
            }
        }
    }
}

private struct SparklineLineShape: Shape {
    let values: [Double]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let count = values.count
        guard count > 1 else { return path }
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 1
        let range = max(maxV - minV, 0.0001)
        let inset: CGFloat = 0.5 // keep stroke inside clipping
        let width = max(rect.width - inset * 2, 1)
        let height = max(rect.height - inset * 2, 1)
        let stepX = width / CGFloat(count - 1)
        func y(for v: Double) -> CGFloat {
            let t = CGFloat((v - minV) / range)
            return rect.maxY - inset - t * height
        }
        path.move(to: CGPoint(x: rect.minX + inset, y: y(for: values[0])))
        for i in 1..<count {
            let x = rect.minX + inset + CGFloat(i) * stepX
            path.addLine(to: CGPoint(x: x, y: y(for: values[i])))
        }
        return path
    }
}

private struct SparklineAreaShape: Shape {
    let values: [Double]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let count = values.count
        guard count > 1 else { return path }
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 1
        let range = max(maxV - minV, 0.0001)
        let inset: CGFloat = 0.5
        let width = max(rect.width - inset * 2, 1)
        let height = max(rect.height - inset * 2, 1)
        let stepX = width / CGFloat(count - 1)
        func y(for v: Double) -> CGFloat {
            let t = CGFloat((v - minV) / range)
            return rect.maxY - inset - t * height
        }
        // Line top edge
        path.move(to: CGPoint(x: rect.minX + inset, y: y(for: values[0])))
        for i in 1..<count {
            let x = rect.minX + inset + CGFloat(i) * stepX
            path.addLine(to: CGPoint(x: x, y: y(for: values[i])))
        }
        // Close to bottom
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset))
        path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY - inset))
        path.closeSubpath()
        return path
    }
}

private struct SparklineTrailingHighlight: View {
    let values: [Double]
    let adaptiveInset: CGFloat
    let color: Color
    let energy: Double
    var body: some View {
        GeometryReader { g in
            let padL: CGFloat = 8
            let padR: CGFloat = adaptiveInset
            let padV: CGFloat = 14
            let innerW = max(1, g.size.width - padL - padR)
            let innerH = max(1, g.size.height - padV * 2)
            let minV = values.min() ?? 0
            let maxV = values.max() ?? 1
            let range = max(maxV - minV, 0.0001)
            let last = values.last ?? minV
            let t = CGFloat((last - minV) / range)
            let x = padL + innerW
            let y = g.size.height - padV - t * innerH
            let center = UnitPoint(x: max(min(x / max(g.size.width, 1), 1), 0), y: max(min(y / max(g.size.height, 1), 1), 0))
            let radius = min(54 + 36 * energy, max(g.size.width, g.size.height))

            RadialGradient(
                gradient: Gradient(colors: [color.opacity(0.22 + 0.18 * energy), .clear]),
                center: center,
                startRadius: 0,
                endRadius: radius
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
        }
        .allowsHitTesting(false)
    }
}

private struct SparklineLeadingFade: View {
    var body: some View {
        GeometryReader { g in
            let width = min(24, g.size.width * 0.08)
            LinearGradient(colors: [Color.white.opacity(0.06), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: width)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .allowsHitTesting(false)
    }
}

private struct SparklineEndMarker: View {
    let values: [Double]
    let adaptiveInset: CGFloat
    let color: Color
    let energy: Double
    @State private var pulse: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let h = g.size.height
            let padL: CGFloat = 8
            let padR: CGFloat = adaptiveInset
            let padV: CGFloat = 14
            let cappedEnergy = min(energy, 0.85)
            let scale = CGFloat(1 + 0.45 * cappedEnergy)
            let dotSize: CGFloat = 6.5 * scale
            let ringSize: CGFloat = 10.5 * scale
            let haloSize: CGFloat = 20 * scale
            let count = values.count
            let innerW = max(1, w - padL - padR)
            let innerH = max(1, h - padV * 2)
            let stepX = innerW / CGFloat(max(count - 1, 1))
            let minV = values.min() ?? 0
            let maxV = values.max() ?? 1
            let range = max(maxV - minV, 0.0001)
            let last = values.last ?? minV
            let prev = count >= 2 ? values[count - 2] : last
            let t = CGFloat((last - minV) / range)
            let tp = CGFloat((prev - minV) / range)
            let x = padL + innerW // exact end of the line geometry
            let prevX = padL + innerW - stepX
            let yRaw = h - padV - t * innerH
            let prevY = h - padV - tp * innerH
            let ySafe = ringSize / 2 + 2
            let y = min(max(yRaw, ySafe), h - ySafe)
            let tint = color

            ZStack {
                // Connector segment to visually tie the dot to the last line segment
                Path { p in
                    p.move(to: CGPoint(x: prevX, y: prevY))
                    p.addLine(to: CGPoint(x: x, y: y))
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .opacity(0.9)

                // Halo behind the live dot (soft)
                Circle()
                    .fill(tint.opacity(0.18 + 0.10 * cappedEnergy))
                    .frame(width: haloSize, height: haloSize)

                // Pulse ring (honors Reduce Motion)
                // MEMORY FIX v9: Also suppress during startup animation window
                if !reduceMotion && !shouldSuppressStartupAnimations() && !globalAnimationsKilled {
                    Circle()
                        .stroke(tint.opacity(0.20), lineWidth: 1.0)
                        .frame(width: ringSize, height: ringSize)
                        .scaleEffect(pulse ? 1.55 : 1.0)
                        .opacity(pulse ? 0 : 1)
                        .animation(.none, value: pulse)
                } else {
                    Circle()
                        .stroke(tint.opacity(0.12), lineWidth: 1.0)
                        .frame(width: ringSize, height: ringSize)
                }

                // Solid dot with subtle specular highlight
                Circle()
                    .fill(tint)
                    .frame(width: dotSize, height: dotSize)
                    .overlay(
                        Circle()
                            .fill(
                                RadialGradient(
                                    gradient: Gradient(colors: [Color.white.opacity(0.40), .clear]),
                                    center: .topLeading,
                                    startRadius: 0,
                                    endRadius: ringSize * 0.55
                                )
                            )
                            .frame(width: ringSize, height: ringSize)
                            .offset(x: -ringSize * 0.10, y: -ringSize * 0.10)
                    )
            }
            .position(x: x, y: y)
            .onAppear { DispatchQueue.main.async { if !reduceMotion { pulse = true } } }
        }
        .allowsHitTesting(false)
    }
}

private struct SparklineChangePill: View {
    let values: [Double]
    let isUp: Bool
    @Binding var showAmount: Bool
    let percentText: String
    let amountText: String

    var body: some View {
        GeometryReader { g in
            let safeLeadingInset: CGFloat = 12
            let maxPillWidth = max(68, g.size.width * 0.36)
            let h = g.size.height
            let pad: CGFloat = 6
            let usableH = max(1, h - pad * 2)
            let minV = values.min() ?? 0
            let maxV = values.max() ?? 1
            let range = max(maxV - minV, 0.0001)
            let firstVal = values.first ?? 0
            let rawStartY = (1 - CGFloat((firstVal - minV) / range)) * usableH + pad
            let clampedStartY = min(max(rawStartY, 10), h - 10)
            let additionalTopInset: CGFloat = clampedStartY < 16 ? 6 : (clampedStartY > h - 16 ? -2 : 0)
            let minTopPadding: CGFloat = 6
            let computedTopPadding: CGFloat = 4 + additionalTopInset
            let topPadding: CGFloat = max(minTopPadding, computedTopPadding)
            let tint = isUp ? Color.green : Color.red

            Text(showAmount ? amountText : percentText)
                .font(.system(size: 11, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .contentTransition(.numericText())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            .opacity(0.95)
            .animation(.easeInOut(duration: 0.22), value: showAmount)
            .background(
                ZStack {
                    // PERFORMANCE FIX v19: Replaced .ultraThinMaterial with solid color
                    Capsule(style: .continuous)
                        .fill(DS.Adaptive.chipBackground)
                    // Subtle sheen
                    LinearGradient(
                        colors: [Color.white.opacity(0.14), Color.white.opacity(0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(Capsule(style: .continuous))
                    // Tint wash so up/down color reads through
                    Capsule(style: .continuous)
                        .fill(tint.opacity(0.08))
                    // Crisp edge
                    Capsule(style: .continuous)
                        .strokeBorder(
                            LinearGradient(colors: [tint.opacity(0.65), Color.white.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 0.9
                        )
                }
            )
            .contentShape(Capsule(style: .continuous))
            .onTapGesture {
                showAmount.toggle()
                let gen = UIImpactFeedbackGenerator(style: .light)
                gen.impactOccurred()
            }
            .frame(maxWidth: min(maxPillWidth, g.size.width - safeLeadingInset - 6), alignment: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, safeLeadingInset)
            .padding(.top, topPadding)
        }
    }
}

private struct SparklineBackgroundCard: View {
    let color: Color
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(DS.Adaptive.stroke, lineWidth: 1)
                )

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DS.Adaptive.divider, lineWidth: 1)
                .allowsHitTesting(false)

            LinearGradient(colors: [color.opacity(0.38), color.opacity(0.15), .clear], startPoint: .bottom, endPoint: .top)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .allowsHitTesting(false)
        }
    }
}

private struct SparklineAreaLayer: View {
    let values: [Double]
    let color: Color
    let adaptiveInset: CGFloat
    let smooth: Bool
    let tension: CGFloat
    let topOpacity: Double

    var body: some View {
        let areaGradient = LinearGradient(
            colors: [color.opacity(topOpacity), color.opacity(topOpacity * 0.5), .clear],
            startPoint: .top,
            endPoint: .bottom
        )

        UnifiedSparklineAreaShape(values: values, smooth: smooth, tension: tension)
            .fill(areaGradient)
            .padding(Edge.Set.leading, 8)
            .padding(Edge.Set.trailing, adaptiveInset)
            .padding(Edge.Set.vertical, 14)
            .padding(Edge.Set.bottom, -14)
    }
}

private struct SparklineLineLayer: View {
    let values: [Double]
    let color: Color
    let adaptiveInset: CGFloat
    let lineWidth: CGFloat
    let blur: CGFloat
    let opacity: Double
    let useScreenBlend: Bool
    let smooth: Bool
    let tension: CGFloat

    init(values: [Double], color: Color, adaptiveInset: CGFloat, lineWidth: CGFloat, blur: CGFloat, opacity: Double, useScreenBlend: Bool = false, smooth: Bool, tension: CGFloat) {
        self.values = values
        self.color = color
        self.adaptiveInset = adaptiveInset
        self.lineWidth = lineWidth
        self.blur = blur
        self.opacity = opacity
        self.useScreenBlend = useScreenBlend
        self.smooth = smooth
        self.tension = tension
    }

    var body: some View {
        UnifiedSparklineLineShape(values: values, smooth: smooth, tension: tension)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .opacity(opacity)
            .padding(Edge.Set.leading, 8)
            .padding(Edge.Set.trailing, adaptiveInset)
            .padding(Edge.Set.vertical, 14)
    }
}

private struct SparklineLineShadowLayer: View {
    let values: [Double]
    let adaptiveInset: CGFloat
    let smooth: Bool
    let tension: CGFloat
    let opacity: Double

    var body: some View {
        UnifiedSparklineLineShape(values: values, smooth: smooth, tension: tension)
            .stroke(Color.black, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            .opacity(opacity)
            .padding(Edge.Set.leading, 8)
            .padding(Edge.Set.trailing, adaptiveInset)
            .padding(Edge.Set.vertical, 14)
            .offset(y: 1)
    }
}

private struct UnifiedSparklineLineShape: Shape {
    let values: [Double]
    let smooth: Bool
    let tension: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let count = values.count
        guard count > 1 else { return path }
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 1
        let range = max(maxV - minV, 0.0001)
        let inset: CGFloat = 0.5
        let width = max(rect.width - inset * 2, 1)
        let height = max(rect.height - inset * 2, 1)
        let stepX = width / CGFloat(count - 1)
        func point(_ i: Int) -> CGPoint {
            let x = rect.minX + inset + CGFloat(i) * stepX
            let t = CGFloat((values[i] - minV) / range)
            let y = rect.maxY - inset - t * height
            return CGPoint(x: x, y: y)
        }
        if smooth && count >= 3 {
            let pts = (0..<count).map { point($0) }
            path.move(to: pts[0])
            let s = max(0, min(1, tension))
            for i in 0..<(count - 1) {
                let p0 = i == 0 ? pts[i] : pts[i - 1]
                let p1 = pts[i]
                let p2 = pts[i + 1]
                let p3 = (i + 2 < count) ? pts[i + 2] : pts[i + 1]
                let cp1 = CGPoint(
                    x: p1.x + (p2.x - p0.x) / 6.0 * s,
                    y: p1.y + (p2.y - p0.y) / 6.0 * s
                )
                let cp2 = CGPoint(
                    x: p2.x - (p3.x - p1.x) / 6.0 * s,
                    y: p2.y - (p3.y - p1.y) / 6.0 * s
                )
                path.addCurve(to: p2, control1: cp1, control2: cp2)
            }
        } else {
            path.move(to: point(0))
            for i in 1..<count { path.addLine(to: point(i)) }
        }
        return path
    }
}

private struct UnifiedSparklineAreaShape: Shape {
    let values: [Double]
    let smooth: Bool
    let tension: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let count = values.count
        guard count > 1 else { return path }
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 1
        let range = max(maxV - minV, 0.0001)
        let inset: CGFloat = 0.5
        let width = max(rect.width - inset * 2, 1)
        let height = max(rect.height - inset * 2, 1)
        let stepX = width / CGFloat(count - 1)
        func point(_ i: Int) -> CGPoint {
            let x = rect.minX + inset + CGFloat(i) * stepX
            let t = CGFloat((values[i] - minV) / range)
            let y = rect.maxY - inset - t * height
            return CGPoint(x: x, y: y)
        }
        if smooth && count >= 3 {
            let pts = (0..<count).map { point($0) }
            path.move(to: pts[0])
            let s = max(0, min(1, tension))
            for i in 0..<(count - 1) {
                let p0 = i == 0 ? pts[i] : pts[i - 1]
                let p1 = pts[i]
                let p2 = pts[i + 1]
                let p3 = (i + 2 < count) ? pts[i + 2] : pts[i + 1]
                let cp1 = CGPoint(
                    x: p1.x + (p2.x - p0.x) / 6.0 * s,
                    y: p1.y + (p2.y - p0.y) / 6.0 * s
                )
                let cp2 = CGPoint(
                    x: p2.x - (p3.x - p1.x) / 6.0 * s,
                    y: p2.y - (p3.y - p1.y) / 6.0 * s
                )
                path.addCurve(to: p2, control1: cp1, control2: cp2)
            }
        } else {
            path.move(to: point(0))
            for i in 1..<count { path.addLine(to: point(i)) }
        }
        // Close to bottom
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset))
        path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY - inset))
        path.closeSubpath()
        return path
    }
}

private struct SparklineCardLayers: View {
    let values: [Double]
    let color: Color
    let isUp: Bool
    let adaptiveInset: CGFloat
    @Binding var showAmount: Bool
    let percentText: String
    let amountText: String
    let smooth: Bool
    let tension: CGFloat
    let energy: Double
    var hideBalances: Bool = false

    @State private var isScrubbing: Bool = false

    var body: some View {
        ZStack(alignment: .leading) {
            SparklineBackgroundCard(color: color)

            // Area fill reworked to be top-weighted (halo around line)
            SparklineAreaLayer(
                values: values,
                color: color,
                adaptiveInset: adaptiveInset,
                smooth: smooth,
                tension: tension,
                topOpacity: 0.12 + 0.10 * energy
            )
            .zIndex(0)

            SparklineLeadingFade()
                .zIndex(0.5)

            // Volatility-aware glow line (softer)
            SparklineLineLayer(
                values: values,
                color: color,
                adaptiveInset: adaptiveInset,
                lineWidth: 2,
                blur: 1.5 + CGFloat(1.5 * energy),
                opacity: 0.14 + 0.26 * energy,
                useScreenBlend: true,
                smooth: smooth,
                tension: tension
            )
            .zIndex(1)

            // Subtle depth shadow under the line to lift it from the area
            SparklineLineShadowLayer(
                values: values,
                adaptiveInset: adaptiveInset,
                smooth: smooth,
                tension: tension,
                opacity: 0.12 + 0.10 * energy
            )
            .zIndex(1.25)

            SparklineTrailingHighlight(values: values, adaptiveInset: adaptiveInset, color: color, energy: energy)
                .opacity(isScrubbing ? 0 : 1)
                .animation(.easeInOut(duration: 0.12), value: isScrubbing)
                .zIndex(1.5)

            // Crisp top line
            SparklineLineLayer(
                values: values,
                color: color,
                adaptiveInset: adaptiveInset,
                lineWidth: 1.5,
                blur: 0,
                opacity: 1,
                useScreenBlend: false,
                smooth: smooth,
                tension: tension
            )
            .zIndex(2)

            SparklineScrubOverlay(values: values, adaptiveInset: adaptiveInset, color: color, isActive: $isScrubbing, hideBalances: hideBalances)
                .zIndex(2.6)

            SparklineEndMarker(values: values, adaptiveInset: adaptiveInset, color: color, energy: min(energy, 0.85))
                .opacity(isScrubbing ? 0 : 1)
                .animation(.easeInOut(duration: 0.12), value: isScrubbing)
                .zIndex(3)

            SparklineChangePill(values: values, isUp: isUp, showAmount: $showAmount, percentText: percentText, amountText: amountText)
                .zIndex(4)
        }
        .compositingGroup()
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct SparklineScrubOverlay: View {
    let values: [Double]
    let adaptiveInset: CGFloat
    let color: Color
    var currentPrice: Double? = nil
    @Binding var isActive: Bool
    var hideBalances: Bool = false
    @State private var x: CGFloat = .zero
    @State private var didHaptic: Bool = false
    @State private var lastClampedX: CGFloat? = nil
    @State private var lastIndex: Int? = nil
    @State private var startValue: Double? = nil
    // HAPTIC FIX: minSeen/maxSeen track USER'S EXPLORED RANGE during scrub session, not chart extremes
    @State private var minSeen: Double? = nil
    @State private var maxSeen: Double? = nil
    @State private var sessionStarted: Bool = false
    @State private var lastAboveBaseline: Bool? = nil

    var body: some View {
        GeometryReader { g in
            let padL: CGFloat = 8
            let padR: CGFloat = adaptiveInset
            let padV: CGFloat = 14
            let innerW = max(1, g.size.width - padL - padR)
            let count = values.count
            let clampedX = min(max(x, padL), g.size.width - padR)
            let t = min(max((clampedX - padL) / max(innerW, 1), 0), 1)
            let idx = min(max(Int(round(t * CGFloat(max(count - 1, 0)))), 0), max(count - 1, 0))
            let minV = values.min() ?? 0
            let maxV = values.max() ?? 1
            let range = max(maxV - minV, 0.0001)
            let val = (idx < count && idx >= 0) ? values[idx] : (values.last ?? 0)
            let first = values.first ?? val
            let innerH = max(1, g.size.height - padV * 2)
            let y = g.size.height - padV - CGFloat((val - minV) / range) * innerH
            let guideColor = Color.white.opacity(0.18)

            let tooltipX = min(max(clampedX, 28), g.size.width - 28)
            let baseTooltipY = max(y - 16, 10)
            let avoidTop: CGFloat = 30 // reserve space for the change pill near top-left
            let adjustedTooltipY = (tooltipX < g.size.width * 0.35) ? max(baseTooltipY, avoidTop + 8) : baseTooltipY

            ZStack {
                if isActive {
                    // Vertical guide
                    Rectangle()
                        .fill(guideColor)
                        .frame(width: 1)
                        .position(x: clampedX, y: g.size.height / 2)
                        .allowsHitTesting(false)

                    // Scrub dot at the hovered point
                    ZStack {
                        Circle()
                            .fill(color)
                            .frame(width: 6, height: 6)
                        Circle()
                            .strokeBorder(Color.white.opacity(0.95), lineWidth: 1)
                            .frame(width: 10, height: 10)
                    }
                    .position(x: clampedX, y: y)
                    .allowsHitTesting(false)

                    let formatted = hideBalances ? "••••••" : MarketFormat.price(val)
                    let pct: Double = first > 0 ? ((val / first) - 1.0) * 100.0 : 0
                    let pctText = hideBalances ? "•••%" : (first > 0 ? String(format: "%+.2f%%", pct) : nil)
                    let text = pctText != nil ? "\(formatted) (\(pctText!))" : formatted

                    // Tooltip near the point
                    Text(text)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.black.opacity(0.55))
                                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.75))
                        )
                        .position(x: tooltipX, y: adjustedTooltipY)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            // SCROLL FIX: Use minimumDistance: 4 to distinguish scrub from vertical scroll.
            // minimumDistance: 0 was capturing ALL touches, completely blocking the parent
            // ScrollView from scrolling when the user touched the sparkline chart area.
            // 4pt matches PortfolioSparklineScrubOverlay's already-fixed threshold.
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        if !isActive {
                            isActive = true
                            #if os(iOS)
                            ChartHaptics.shared.begin()
                            #endif
                            didHaptic = true
                            // HAPTIC FIX: Initialize to nil - will be set to first touched value
                            startValue = values.last
                            minSeen = nil
                            maxSeen = nil
                            sessionStarted = false
                            lastClampedX = nil
                        }
                        x = value.location.x

                        // Compute the discrete index under the finger
                        let clampedX = min(max(x, padL), g.size.width - padR)
                        let t = min(max((clampedX - padL) / max(innerW, 1), 0), 1)
                        let idx = min(max(Int(round(t * CGFloat(max(count - 1, 0)))), 0), max(count - 1, 0))

                        // Selection tick when index changes
                        if idx != lastIndex {
                            #if os(iOS)
                            ChartHaptics.shared.tickIfNeeded()
                            #endif
                            lastIndex = idx
                        }

                        // Major zero-crossing bump relative to baseline value (last value)
                        #if os(iOS)
                        let baseline: Double = values.last ?? val
                        let isAbove = val >= baseline
                        if let prev = lastAboveBaseline, prev != isAbove {
                            ChartHaptics.shared.majorIfNeeded(intensity: 0.9)
                        }
                        lastAboveBaseline = isAbove
                        #endif

                        // HAPTIC FIX: Track user's exploration range, not chart extremes
                        if !sessionStarted {
                            // First value touched - initialize tracking
                            minSeen = val
                            maxSeen = val
                            sessionStarted = true
                        } else {
                            // Track new territory exploration
                            if let mn = minSeen, val < mn {
                                minSeen = val
                                #if os(iOS)
                                ChartHaptics.shared.majorIfNeeded(intensity: 0.9)
                                #endif
                            }
                            if let mx = maxSeen, val > mx {
                                maxSeen = val
                                #if os(iOS)
                                ChartHaptics.shared.majorIfNeeded(intensity: 0.9)
                                #endif
                            }
                        }
                    }
                    .onEnded { _ in
                        #if os(iOS)
                        ChartHaptics.shared.end()
                        #endif
                        isActive = false
                        lastIndex = nil
                        lastClampedX = nil
                        lastAboveBaseline = nil
                        // Reset session tracking
                        minSeen = nil
                        maxSeen = nil
                        sessionStarted = false
                    }
            )
        }
        .allowsHitTesting(true)
    }
}

#Preview {
    PortfolioSectionView(
        selectedRange: .constant(.month)
    )
    .environmentObject(HomeViewModel())
}

