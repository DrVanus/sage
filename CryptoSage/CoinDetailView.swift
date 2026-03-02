//
//  CoinDetailView.swift
//  CSAI1
//
//  Cleaned-up version with no duplicate CoinDetailTradingViewWebView
//

import SwiftUI
// import Charts
import WebKit
import Combine

// MARK: - ChartType
enum ChartType: String, CaseIterable {
    case cryptoSageAI = "CryptoSage AI"
    case tradingView  = "TradingView"
}

// MARK: - InfoTab for Overview/News/Ideas
enum InfoTab: String, CaseIterable, Hashable {
    case overview = "Overview"
    case news     = "News"
    case ideas    = "Ideas"
}

// MARK: - NewsCategory for in-app headlines
enum CoinNewsCategory: String, CaseIterable, Hashable {
    case top = "Top"
    case market = "Market"
    case onChain = "On‑chain"
    case ecosystem = "Ecosystem"
    case regulation = "Regulation"
    case social = "Social"

    var queryKeywords: String {
        switch self {
        case .top: return "crypto OR cryptocurrency"
        case .market: return "price OR rally OR selloff OR market"
        case .onChain: return "on-chain OR onchain OR wallets OR addresses OR tvl"
        case .ecosystem: return "ecosystem OR dapps OR defi OR nft"
        case .regulation: return "regulation OR sec OR etf OR lawsuit OR legal"
        case .social: return "reddit OR twitter OR x.com OR sentiment"
        }
    }
}

// MARK: - CoinDetailView
struct CoinDetailView: View {
    let coin: MarketCoin

    @State private var selectedChartType: ChartType = .cryptoSageAI
    @State private var selectedInterval: ChartInterval = .oneDay
    
    @StateObject private var priceVM: PriceViewModel
    @StateObject private var techVM: TechnicalsViewModel

    @State private var change24h: Double
    @State private var indicators: Set<IndicatorType> = [.volume]
    @AppStorage("TV.Indicators.Selected") private var tvIndicatorsRaw: String = ""
    @State private var priceHighlight = false
    @State private var lastLivePriceSample: Double? = nil
    @State private var showIndicatorMenu: Bool = false
    @State private var showTimeframePopover: Bool = false
    @State private var timeframeButtonFrame: CGRect = .zero
    @State private var timeframePopoverEdge: Edge = .bottom
    @State private var selectedInfoTab: InfoTab = .overview
    @State private var showDeepDive: Bool = false
    @State private var showDiagnostics: Bool = false
    
    // AI Insight state - initialized with cached value to prevent loading flash on revisit
    @State private var aiInsight: CoinAIInsight?
    @State private var isGeneratingInsight: Bool = false
    @State private var aiInsightError: String? = nil
    
    // AI Trading Signal state
    @State private var tradingSignal: TradingSignal? = nil
    @State private var isGeneratingSignal: Bool = false
    
    // Why is it moving state (used by WhyIsItMovingSheet)
    @State private var showWhySheet: Bool = false
    @State private var whyExplanation: String = ""
    @State private var isGeneratingWhy: Bool = false
    
    // Task tracking for cancellation on disappear (memory leak prevention)
    @State private var insightTask: Task<Void, Never>? = nil
    @State private var signalTask: Task<Void, Never>? = nil
    @State private var fallbackTask: Task<Void, Never>? = nil
    @State private var startupTask: Task<Void, Never>? = nil
    @State private var signalDebounceTask: Task<Void, Never>? = nil
    @State private var lastSignalIndicatorsSignature: String = ""
    @State private var showWhyMovingCard: Bool = false
    @State private var whyVisibilityTask: Task<Void, Never>? = nil
    
    // Quick actions state
    @State private var showSetAlert: Bool = false

    // Trading controls state
    @State private var tradeAmount: String = ""
    @State private var selectedOrderType: OrderType = .market
    @State private var limitPrice: String = ""
    @State private var isPlacingOrder: Bool = false
    @State private var orderError: String? = nil
    @State private var showOrderSuccess: Bool = false
    @State private var lastOrderId: String? = nil

    // Fast backfill to avoid endless shimmers
    @State private var fallbackCap: Double? = nil
    @State private var fallbackFDV: Double? = nil
    @State private var fallbackCirc: Double? = nil
    @State private var fallbackMax: Double? = nil
    @State private var fallbackRank: Int? = nil
    @State private var fallbackVolume24h: Double? = nil
    @State private var lastFallbackFetchAt: Date = .distantPast
    @State private var isFetchingFallback: Bool = false
    @State private var lastStatsUpdate: Date? = nil

    // Cached LivePriceManager values to avoid calling during body computation
    @State private var cachedChange24h: Double? = nil
    @State private var cachedVolume24h: Double? = nil
    @State private var cachedRank: Int? = nil
    @State private var cachedMaxSupply: Double? = nil
    @State private var cached1hChange: Double? = nil
    @State private var cached7dChange: Double? = nil
    
    // PERFORMANCE FIX: Cache freshCoin to avoid O(n) array search on every computed property access
    @State private var cachedFreshCoin: MarketCoin? = nil
    
    // PERFORMANCE FIX: Throttled publisher to reduce update frequency
    private let throttledPricePublisher = LivePriceManager.shared.publisher
        .throttle(for: .milliseconds(500), scheduler: DispatchQueue.main, latest: true)

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var marketVM: MarketViewModel
    
    private var isDark: Bool { colorScheme == .dark }

    // PERFORMANCE FIX: Use cached coin to avoid O(n) search during body computation
    // Updated via .onChange(of: marketVM.allCoins) and .onAppear
    private var freshCoin: MarketCoin {
        cachedFreshCoin ?? coin
    }
    
    // Helper to find and cache the fresh coin from marketVM
    private func updateCachedFreshCoin() {
        if let found = marketVM.allCoins.first(where: { $0.id == coin.id }) {
            cachedFreshCoin = found
        }
    }

    @MainActor
    private func applyCachedStatsOnAppear() {
        cachedChange24h = LivePriceManager.shared.bestChange24hPercent(for: freshCoin.symbol)
        cachedVolume24h = LivePriceManager.shared.bestVolumeUSD(for: freshCoin)
        cachedRank = LivePriceManager.shared.bestRank(for: freshCoin)
        cachedMaxSupply = LivePriceManager.shared.bestMaxSupply(for: freshCoin)
        cached1hChange = LivePriceManager.shared.bestChange1hPercent(for: freshCoin.symbol)
        cached7dChange = LivePriceManager.shared.bestChange7dPercent(for: freshCoin.symbol)

        if let best = cachedChange24h {
            change24h = best
        }
        priceVM.updateSymbol(coin.symbol.uppercased())
        lastStatsUpdate = Date()
        lastLivePriceSample = displayedPrice
        if let cached = loadCachedStats(for: coin.symbol.uppercased()) {
            if let v = cached.cap, v > 0 { fallbackCap = v }
            if let v = cached.fdv, v > 0 { fallbackFDV = v }
            if let v = cached.circ, v > 0 { fallbackCirc = v }
            if let v = cached.max, v > 0 { fallbackMax = v }
            if let v = cached.vol, v > 0 { fallbackVolume24h = v }
            if let r = cached.rank, r > 0 { fallbackRank = r }
            lastStatsUpdate = Date()
        }
        let sharedSet = parseIndicatorSet(from: tvIndicatorsRaw)
        if !sharedSet.isEmpty { indicators = sharedSet }
    }

    // MARK: - Trading Functions

    /// Execute a trade (buy or sell) via Coinbase Advanced Trade API
    @MainActor
    private func executeTrade(side: TradeSide) {
        // Clear previous errors
        orderError = nil

        // Validate amount
        guard let amount = Double(tradeAmount), amount > 0 else {
            orderError = "Please enter a valid amount"
            return
        }

        // Validate limit price if limit order
        if selectedOrderType == .limit {
            guard let price = Double(limitPrice), price > 0 else {
                orderError = "Please enter a valid limit price"
                return
            }
        }

        // Haptic feedback
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif

        isPlacingOrder = true

        Task {
            do {
                let productId = "\(coin.symbol.uppercased())-USD"
                let orderResponse: CoinbaseOrderResponse

                if selectedOrderType == .market {
                    // Place market order
                    orderResponse = try await CoinbaseAdvancedTradeService.shared.placeMarketOrder(
                        productId: productId,
                        side: side.rawValue,
                        size: amount,
                        isSizeInQuote: false
                    )
                } else {
                    // Place limit order
                    guard let limitPriceValue = Double(limitPrice) else {
                        throw NSError(domain: "CoinDetailView", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid limit price"])
                    }

                    orderResponse = try await CoinbaseAdvancedTradeService.shared.placeLimitOrder(
                        productId: productId,
                        side: side.rawValue,
                        size: amount,
                        price: limitPriceValue,
                        postOnly: false
                    )
                }

                await MainActor.run {
                    isPlacingOrder = false

                    if orderResponse.success, let successResponse = orderResponse.successResponse {
                        // Success!
                        lastOrderId = successResponse.orderId
                        showOrderSuccess = true
                        tradeAmount = ""
                        limitPrice = ""

                        // Success haptic
                        #if os(iOS)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        #endif

                        // Track analytics
                        AnalyticsService.shared.track(.tradeExecuted, parameters: [
                            "symbol": coin.symbol.uppercased(),
                            "side": side.rawValue,
                            "orderType": selectedOrderType.rawValue,
                            "amount": String(amount)
                        ])
                    } else if let errorResponse = orderResponse.errorResponse {
                        // Show error from API
                        orderError = errorResponse.message
                        #if os(iOS)
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                        #endif
                    }
                }
            } catch {
                await MainActor.run {
                    isPlacingOrder = false
                    orderError = error.localizedDescription

                    // Error haptic
                    #if os(iOS)
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    #endif
                }
            }
        }
    }

    /// Format currency with appropriate decimal places
    private func currencyFormat(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = value < 1 ? 4 : 2
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    private func startDeferredStartupRefreshes() {
        startupTask?.cancel()
        startupTask = Task {
            guard !Task.isCancelled else { return }

            await MainActor.run {
                techVM.refresh(
                    symbol: coin.symbol.uppercased(),
                    interval: selectedInterval,
                    currentPrice: displayedPrice,
                    sparkline: freshCoin.sparklineIn7d
                )
                fetchFallbackStatsIfNeeded()
            }

            guard !Task.isCancelled else { return }
            if marketVM.allCoins.isEmpty {
                // Let initial page rendering settle before pulling a full market snapshot.
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard !Task.isCancelled else { return }
                await marketVM.loadAllData()
            }
        }
    }

    private func scheduleWhyMovingVisibility(for change: Double) {
        whyVisibilityTask?.cancel()
        let currentVisible = showWhyMovingCard
        whyVisibilityTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            let showThreshold: Double = currentVisible ? 4.6 : 5.0
            let shouldShow = abs(change) >= showThreshold
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showWhyMovingCard = shouldShow
                }
            }
        }
    }

    // Always prefer a sparkline-derived 24h change when available for consistency; otherwise use normalized provider values
    private var displayedChange24hValue: Double {
        // Use cached value to avoid calling LivePriceManager during body
        if let cached = cachedChange24h, cached.isFinite {
            return cached
        }
        // Fallback to provider values (normalize if some providers report fractions/basis points)
        let candidates: [Double?] = [
            marketVM.allCoins.first(where: { $0.id == coin.id })?.dailyChange,
            change24h
        ]
        for s in candidates {
            if let v = s, v.isFinite { return normalizePercent(v) }
        }
        // Last resort: derive from sparkline
        if let d = derivePercentFromSparkline(freshCoin.sparklineIn7d, anchorPrice: displayedPrice, hours: 24) { return d }
        return 0
    }

    private var displayedMarketCap: Double? {
        if let cap = freshCoin.marketCap, cap.isFinite, cap > 0 { return cap }
        let best = bestCap(for: freshCoin)
        if best > 0 { return best }
        if let f = fallbackCap, f.isFinite, f > 0 { return f }
        return nil
    }
    
    private var displayedCirculatingSupply: Double? {
        let c = freshCoin
        // 1) Prefer provider circulating supply
        if let cs = c.circulatingSupply, cs.isFinite, cs > 0 { return cs }
        // 2) Derive from Market Cap / Price when possible
        let price = displayedPrice
        if price.isFinite, price > 0 {
            if let cap = displayedMarketCap, cap.isFinite, cap > 0 {
                let derived = cap / price
                if derived.isFinite, derived > 0 { return derived }
            }
        }
        // 3) Fallbacks
        if let total = c.totalSupply, total.isFinite, total > 0 { return total }
        if let maxS = c.maxSupply, maxS.isFinite, maxS > 0 { return maxS }
        if let f = fallbackCirc, f.isFinite, f > 0 { return f }
        return nil
    }

    private var displayedFDV: Double? {
        let price = displayedPrice
        guard price.isFinite, price > 0 else { return nil }
        // Prefer max supply, then total, then circ (or derived circ)
        if let maxS = displayedMaxSupply, maxS.isFinite, maxS > 0 { return price * maxS }
        if let total = freshCoin.totalSupply, total.isFinite, total > 0 { return price * total }
        if let circ = displayedCirculatingSupply, circ.isFinite, circ > 0 { return price * circ }
        if let f = fallbackFDV, f.isFinite, f > 0 { return f }
        return nil
    }

    private var displayedVolume24h: Double? {
        // Use cached value to avoid calling LivePriceManager during body
        cachedVolume24h ?? freshCoin.volumeUsd24Hr ?? fallbackVolume24h
    }

    private func bestCap(for c: MarketCoin) -> Double {
        if let cap = c.marketCap, cap.isFinite, cap > 0 { return cap }
        // Prefer provider price; fall back to the live displayed price used elsewhere in this view
        let priceCandidate: Double = {
            if let p = c.priceUsd, p.isFinite, p > 0 { return p }
            return displayedPrice
        }()
        let p = priceCandidate
        if p.isFinite, p > 0 {
            if let circ = c.circulatingSupply, circ.isFinite, circ > 0 {
                let v = p * circ; if v.isFinite, v > 0 { return v }
            }
            if let total = c.totalSupply, total.isFinite, total > 0 {
                let v = p * total; if v.isFinite, v > 0 { return v }
            }
            if let maxSup = c.maxSupply, maxSup.isFinite, maxSup > 0 {
                let v = p * maxSup; if v.isFinite, v > 0 { return v }
            }
        }
        return 0
    }

    private var computedRank: Int? {
        let coins = marketVM.allCoins
        // If we don't have a reasonably complete snapshot, avoid returning a misleading rank
        guard coins.count >= 100 else { return nil }
        let sorted = coins.sorted { bestCap(for: $0) > bestCap(for: $1) }
        guard let idx = sorted.firstIndex(where: { $0.id == freshCoin.id }) else { return nil }
        return idx + 1
    }

    // Prefer cached CoinGecko rank, then live rank, then a local rank computed from market snapshot (only when snapshot is large enough)
    private var displayedRank: Int? {
        if let r = fallbackRank { return r }
        // Use cached value to avoid calling LivePriceManager during body
        if let r = cachedRank { return r }
        return computedRank
    }

    private var displayedMaxSupply: Double? {
        if let ms = freshCoin.maxSupply, ms.isFinite, ms > 0 { return ms }
        if let total = freshCoin.totalSupply, total.isFinite, total > 0 { return total }
        if let circ = freshCoin.circulatingSupply, circ.isFinite, circ > 0 { return circ }
        // Use cached value to avoid calling LivePriceManager during body
        return cachedMaxSupply ?? fallbackMax
    }

    init(coin: MarketCoin) {
        self.coin = coin
        _change24h     = State(initialValue: coin.dailyChange ?? 0)
        _priceVM = StateObject(wrappedValue: PriceViewModel.shared(for: coin.symbol.uppercased(), timeframe: .live))
        _techVM = StateObject(wrappedValue: TechnicalsViewModel())
        
        // Pre-load ANY cached AI insight synchronously (even if stale) to prevent loading flash
        // This shows the previous insight immediately - fresh or stale - instead of a spinner
        // If stale, we'll refresh in background without showing loading state
        let cachedInsight = MainActor.assumeIsolated {
            CoinAIInsightService.shared.getAnyCachedInsight(for: coin.symbol)
        }
        _aiInsight = State(initialValue: cachedInsight)
    }

    private var tvSymbol: String {
        let isUS = ComplianceManager.shared.isUSUser
        let prefix = isUS ? "BINANCEUS" : "BINANCE"
        let quote = isUS ? "USD" : "USDT"
        return "\(prefix):\(coin.symbol.uppercased())\(quote)"
    }

    private var tvTheme: String {
        colorScheme == .dark ? "Dark" : "Light"
    }
    
    private var displayedPrice: Double {
        // PRICE CONSISTENCY FIX: Use bestPrice for consistency with HomeView/MarketView
        // bestPrice checks live coins array first, then allCoins, then caches
        if let best = marketVM.bestPrice(for: coin.id), best > 0 { return best }
        // Fallback to the local PriceViewModel stream if needed
        if priceVM.price > 0 { return priceVM.price }
        // Seed from initial coin payload as last resort
        return coin.priceUsd ?? 0
    }
    
    // PRICE CONSISTENCY: Check if price data is stale
    // NOTE: Disabled the gray styling - it was too aggressive and confusing to users
    // The price updates from marketVM which refreshes every few seconds, so prices
    // are generally current. TradeView doesn't show staleness either.
    // Only show staleness indicator when we truly have no price data at all.
    private var isPriceDataStale: Bool {
        // Only show stale when we have zero price - otherwise trust the displayed price
        return displayedPrice <= 0
    }
    
    private func imageURLForSymbol(_ symbol: String) -> URL? {
        let lower = symbol.lowercased()
        if let coin = marketVM.allCoins.first(where: { $0.symbol.lowercased() == lower }) {
            return coin.imageUrl
        }
        return nil
    }
    
    private var tvStudies: [String] {
        // Reference tvIndicatorsRaw to ensure SwiftUI detects changes and triggers view update
        _ = tvIndicatorsRaw
        return TVStudiesMapper.buildCurrentStudies()
    }
    
    private var tvAltSymbols: [String] {
        let s = coin.symbol.uppercased()
        return [
            tvSymbol,
            // USD quotes
            "BINANCEUS:\(s)USD",
            "COINBASE:\(s)USD",
            "KRAKEN:\(s)USD",
            "BITFINEX:\(s)USD",
            "BITSTAMP:\(s)USD",
            "GEMINI:\(s)USD",
            "CRYPTO:\(s)USD",
            // USDT/FDUSD quotes
            "BINANCE:\(s)USDT",
            "BYBIT:\(s)USDT",
            "OKX:\(s)USDT",
            "KUCOIN:\(s)USDT",
            "BITGET:\(s)USDT",
            "BINANCE:\(s)FDUSD"
        ]
    }

    private func keyForIndicator(_ ind: IndicatorType) -> String {
        switch ind {
        case .volume: return "volume"
        case .sma: return "sma"
        case .ema: return "ema"
        case .bb: return "bb"
        case .rsi: return "rsi"
        case .macd: return "macd"
        case .stoch: return "stoch"
        case .vwap: return "vwap"
        case .ichimoku: return "ichimoku"
        case .atr: return "atr"
        case .obv: return "obv"
        case .mfi: return "mfi"
        }
    }

    private func parseIndicatorSet(from raw: String) -> Set<IndicatorType> {
        let keys = raw.split(separator: ",").map { String($0) }
        var out = Set<IndicatorType>()
        for k in keys {
            switch k {
            case "volume": out.insert(.volume)
            case "sma": out.insert(.sma)
            case "ema": out.insert(.ema)
            case "bb": out.insert(.bb)
            case "rsi": out.insert(.rsi)
            case "macd": out.insert(.macd)
            case "stoch": out.insert(.stoch)
            case "vwap": out.insert(.vwap)
            case "ichimoku": out.insert(.ichimoku)
            case "atr": out.insert(.atr)
            case "obv": out.insert(.obv)
            case "mfi": out.insert(.mfi)
            default: break
            }
        }
        return out
    }

    private func serializeIndicatorSet(_ set: Set<IndicatorType>) -> String {
        let order: [IndicatorType] = [.volume, .sma, .ema, .bb, .rsi, .macd, .stoch, .vwap, .ichimoku, .atr, .obv, .mfi]
        let keys: [String] = order.compactMap { set.contains($0) ? keyForIndicator($0) : nil }
        return keys.joined(separator: ",")
    }

    // MARK: - Body
    var body: some View {
        ZStack {
            FuturisticBackground()
                .ignoresSafeArea()

            contentScrollView
            
            // Timeframe anchored dropdown overlay
            if showTimeframePopover {
                CSAnchoredGridMenu(
                    isPresented: $showTimeframePopover,
                    anchorRect: timeframeButtonFrame,
                    items: ChartInterval.allCases,
                    selectedItem: selectedInterval,
                    titleForItem: { $0.rawValue },
                    onSelect: { selectedInterval = $0 },
                    columns: 3,
                    preferredWidth: 240,
                    edgePadding: 16,
                    title: "Timeframe"
                )
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showTimeframePopover)
        .sheet(isPresented: $showIndicatorMenu) {
            ChartIndicatorMenu(isPresented: $showIndicatorMenu, isUsingNativeChart: selectedChartType == .cryptoSageAI)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showDeepDive) {
            DeepDiveSheetView(
                symbol: coin.symbol.uppercased(),
                price: displayedPrice,
                change24h: displayedChange24hValue,
                sparkline: freshCoin.sparklineIn7d,
                existingInsight: aiInsight,
                coinImageURL: coin.imageUrl
            )
        }
        .sheet(isPresented: $showDiagnostics) {
            CoinDiagnosticsSheet(items: diagnosticsItems, sparklineInfo: diagnosticsSparklineInfo, lastStatsUpdate: lastStatsUpdate)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert("Order Placed Successfully", isPresented: $showOrderSuccess) {
            Button("OK", role: .cancel) {
                showOrderSuccess = false
            }
        } message: {
            if let orderId = lastOrderId {
                Text("Your order has been placed.\nOrder ID: \(orderId)")
            } else {
                Text("Your order has been placed successfully.")
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            // PERFORMANCE FIX: Initialize cached fresh coin immediately
            updateCachedFreshCoin()
            
            // Analytics: Track coin detail view
            AnalyticsService.shared.track(.coinDetailViewed, parameters: ["symbol": coin.symbol.uppercased()])
            
            // Record chart view for ad cooldown (user is analyzing, don't interrupt)
            AdManager.shared.recordChartViewShown()
            
            // Ensure we are subscribed to the same unified live price stream used by Trading
            LivePriceManager.shared.primeVolumeIfNeeded(for: coin.symbol)

            Task { @MainActor in
                applyCachedStatsOnAppear()
                startDeferredStartupRefreshes()
                scheduleWhyMovingVisibility(for: displayedChange24hValue)
                if tradingSignal == nil {
                    signalTask?.cancel()
                    signalTask = Task { await generateTradingSignal() }
                }
            }
        }
        .onDisappear {
            // Cancel any pending async tasks to prevent memory leaks
            startupTask?.cancel()
            signalDebounceTask?.cancel()
            whyVisibilityTask?.cancel()
            insightTask?.cancel()
            signalTask?.cancel()
            fallbackTask?.cancel()
            startupTask = nil
            signalDebounceTask = nil
            whyVisibilityTask = nil
            insightTask = nil
            signalTask = nil
            fallbackTask = nil
        }
        .onChange(of: priceVM.price) { _, _ in
            // PERFORMANCE FIX v13: Skip during global startup phase
            guard !isInGlobalStartupPhase() else { return }
            // PERFORMANCE FIX: Skip during scroll to prevent "multiple updates per frame"
            guard !ScrollStateManager.shared.isScrolling else { return }
            
            // Defer state modifications to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.15)) { priceHighlight = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeInOut(duration: 0.2)) { priceHighlight = false }
                }
                // Refresh cached LivePriceManager values
                cachedChange24h = LivePriceManager.shared.bestChange24hPercent(for: freshCoin.symbol)
                cachedVolume24h = LivePriceManager.shared.bestVolumeUSD(for: freshCoin)
                if let best = cachedChange24h {
                    change24h = best
                } else if let fresh = marketVM.allCoins.first(where: { $0.id == coin.id })?.dailyChange {
                    change24h = fresh
                }
                lastStatsUpdate = Date()
            }
        }
        .onChange(of: selectedInterval) { _, newInterval in
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                techVM.refresh(symbol: coin.symbol.uppercased(), interval: newInterval, currentPrice: displayedPrice, sparkline: freshCoin.sparklineIn7d)
            }
        }
        .onChange(of: indicators) { _, new in
            // Defer state modifications to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                let raw = serializeIndicatorSet(new)
                if tvIndicatorsRaw != raw { tvIndicatorsRaw = raw }
            }
        }
        .onChange(of: tvIndicatorsRaw) { _, raw in
            // Defer state modifications to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                let set = parseIndicatorSet(from: raw)
                if !set.isEmpty && set != indicators { indicators = set }
            }
        }
        .onReceive(marketVM.objectWillChange) { _ in
            // Defer state modifications to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                // PERFORMANCE FIX: Update cached fresh coin when market data changes
                updateCachedFreshCoin()
                fetchFallbackStatsIfNeeded()
            }
        }
        // PERFORMANCE FIX: Use throttled publisher (500ms) to reduce update frequency
        .onReceive(throttledPricePublisher) { coins in
            // PERFORMANCE FIX: Skip updates during scroll to prevent jank
            guard !ScrollStateManager.shared.isScrolling else { return }
            
            // Compute the latest price for this coin from the live emission
            let newPrice = (coins.first { $0.id == coin.id || $0.symbol.lowercased() == coin.symbol.lowercased() }?.priceUsd) ?? displayedPrice
            let old = lastLivePriceSample ?? newPrice
            // Relative threshold (~0.15%) to avoid flicker on tiny updates
            let rel = abs(newPrice - old) / max(1e-9, max(abs(newPrice), abs(old)))
            // Defer state modifications to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                if rel >= 0.0015 {
                    withAnimation(.easeInOut(duration: 0.15)) { priceHighlight = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.easeInOut(duration: 0.2)) { priceHighlight = false }
                    }
                }
                lastLivePriceSample = newPrice
                // Refresh cached LivePriceManager values
                cachedChange24h = LivePriceManager.shared.bestChange24hPercent(for: freshCoin.symbol)
                cachedVolume24h = LivePriceManager.shared.bestVolumeUSD(for: freshCoin)
                cached1hChange = LivePriceManager.shared.bestChange1hPercent(for: freshCoin.symbol)
                cached7dChange = LivePriceManager.shared.bestChange7dPercent(for: freshCoin.symbol)
                if let best = cachedChange24h {
                    change24h = best
                }
                lastStatsUpdate = Date()
            }
        }
        .onChange(of: displayedChange24hValue) { _, newValue in
            scheduleWhyMovingVisibility(for: newValue)
        }
        .safeAreaInset(edge: .top) { navBar }
        .tint(.yellow)
        // NAVIGATION: Enable both native iOS pop gesture AND custom edge swipe with visual feedback
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
    }

    // MARK: - Lightweight fallback stats cache
    private struct CachedCoinStats: Codable {
        let cap: Double?
        let fdv: Double?
        let circ: Double?
        let max: Double?
        let vol: Double?
        let rank: Int?
        let ts: TimeInterval
    }
    private func statsCacheKey(for symbol: String) -> String { "CachedStats.\(symbol.uppercased())" }
    private func loadCachedStats(for symbol: String) -> CachedCoinStats? {
        let key = statsCacheKey(for: symbol)
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(CachedCoinStats.self, from: data)
    }
    private func saveCachedStats(cap: Double?, fdv: Double?, circ: Double?, max: Double?, vol: Double?, rank: Int?, for symbol: String) {
        let stats = CachedCoinStats(cap: cap, fdv: fdv, circ: circ, max: max, vol: vol, rank: rank, ts: Date().timeIntervalSince1970)
        if let data = try? JSONEncoder().encode(stats) {
            UserDefaults.standard.set(data, forKey: statsCacheKey(for: symbol))
        }
    }

    // MARK: - Main Scroll Content
    private var contentScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Portfolio position banner (if user holds this coin)
                portfolioPositionBanner
                
                // Chart with streamlined controls
                chartSection

                // Trading Controls - Quick Buy/Sell interface
                tradingControlsSection

                // Prominent "Why is it moving?" card for significant moves
                if showWhyMovingCard {
                    WhyIsMovingCard(
                        coinId: coin.id,
                        symbol: coin.symbol.uppercased(),
                        coinName: coin.name,
                        change24h: displayedChange24hValue
                    )
                }
                
                // Overview/News/Ideas tabs - moved directly under chart for better UX
                overviewSection
                
                // AI Trading Signal - more compact card
                aiTradingSignalSection
                
                // Key Levels visualization
                keyLevelsSection
                
                // Stats and Technicals
                statsCardView
                technicalsSection
            }
            .padding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 10)
        }
        // PERFORMANCE FIX v21: UIKit scroll bridge for snappier deceleration + KVO tracking
        .withUIKitScrollBridge()
        .sheet(isPresented: $showWhySheet) {
            WhyIsItMovingSheet(
                symbol: coin.symbol.uppercased(),
                change24h: displayedChange24hValue,
                explanation: whyExplanation,
                isLoading: isGeneratingWhy
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSetAlert) {
            AddAlertView(prefilledSymbol: coin.symbol.uppercased(), prefilledPrice: displayedPrice)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Chart Section
    private var chartSection: some View {
        let isCompact = UIScreen.main.bounds.width < 360
        return ChartCard(
            selectedChartType: $selectedChartType,
            selectedInterval: $selectedInterval,
            showTimeframePopover: $showTimeframePopover,
            timeframeButtonFrame: $timeframeButtonFrame,
            timeframePopoverEdge: $timeframePopoverEdge,
            showIndicatorMenu: $showIndicatorMenu,
            indicatorsCount: indicators.count,
            symbol: coin.symbol.uppercased(),
            tvSymbol: tvSymbol,
            tvTheme: tvTheme,
            tvStudies: tvStudies,
            tvAltSymbols: tvAltSymbols,
            isCompact: isCompact,
            edgeProvider: { frame in bestPopoverEdge(for: frame) },
            livePrice: displayedPrice
        )
        .frame(maxWidth: .infinity)
    }

    // MARK: - Trading Controls Section
    private var tradingControlsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Premium header
            HStack(spacing: 8) {
                GoldHeaderGlyph(systemName: "arrow.left.arrow.right")

                Text("Quick Trade")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)

                Spacer()

                // Current price indicator
                Text(currencyFormat(displayedPrice))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }

            // Order type selector
            HStack(spacing: 8) {
                Text("Order Type")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DS.Adaptive.textSecondary)

                Spacer()

                HStack(spacing: 4) {
                    ForEach([OrderType.market, OrderType.limit], id: \.self) { type in
                        orderTypeButton(type)
                    }
                }
            }

            // Amount input
            VStack(alignment: .leading, spacing: 8) {
                Text("Amount (\(coin.symbol.uppercased()))")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DS.Adaptive.textSecondary)

                HStack(spacing: 8) {
                    TextField("0.00", text: $tradeAmount)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(DS.Adaptive.chipBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(DS.Adaptive.stroke, lineWidth: 1)
                        )

                    // Quick amount buttons
                    quickAmountButton("25%")
                    quickAmountButton("50%")
                    quickAmountButton("Max")
                }
            }

            // Limit price input (only for limit orders)
            if selectedOrderType == .limit {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Limit Price (USD)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DS.Adaptive.textSecondary)

                    TextField(currencyFormat(displayedPrice), text: $limitPrice)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(DS.Adaptive.chipBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(DS.Adaptive.stroke, lineWidth: 1)
                        )
                }
            }

            // Order impact preview
            if let amount = Double(tradeAmount), amount > 0 {
                VStack(spacing: 6) {
                    orderImpactRow(title: "Est. Total", value: currencyFormat(amount * displayedPrice))

                    if selectedOrderType == .limit, let price = Double(limitPrice), price > 0 {
                        orderImpactRow(title: "Limit Total", value: currencyFormat(amount * price))
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(DS.Adaptive.chipBackground.opacity(0.5))
                )
            }

            // Error message
            if let error = orderError {
                Text(error)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.red.opacity(0.1))
                    )
            }

            // Buy/Sell buttons
            HStack(spacing: 12) {
                // Buy button
                Button {
                    executeTrade(side: .buy)
                } label: {
                    HStack(spacing: 6) {
                        if isPlacingOrder {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Buy")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PremiumAccentCTAStyle(accent: .green, height: 44))
                .disabled(isPlacingOrder || tradeAmount.isEmpty)
                .opacity((isPlacingOrder || tradeAmount.isEmpty) ? 0.5 : 1.0)

                // Sell button
                Button {
                    executeTrade(side: .sell)
                } label: {
                    HStack(spacing: 6) {
                        if isPlacingOrder {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Sell")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PremiumAccentCTAStyle(accent: .red, height: 44))
                .disabled(isPlacingOrder || tradeAmount.isEmpty)
                .opacity((isPlacingOrder || tradeAmount.isEmpty) ? 0.5 : 1.0)
            }

            // Disclaimer
            Text("Live trading on Coinbase Advanced Trade. Ensure sufficient funds.")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(DS.Adaptive.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
    }

    // Helper view for order type buttons
    private func orderTypeButton(_ type: OrderType) -> some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedOrderType = type
            }
        } label: {
            Text(type.rawValue.capitalized)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(selectedOrderType == type ? (isDark ? .black : .white) : DS.Adaptive.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(selectedOrderType == type
                              ? (isDark ? DS.Colors.gold : Color.black)
                              : DS.Adaptive.chipBackground)
                )
                .overlay(
                    Capsule()
                        .stroke(selectedOrderType == type
                                ? (isDark ? DS.Colors.gold : Color.black)
                                : DS.Adaptive.stroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // Helper view for quick amount buttons
    private func quickAmountButton(_ label: String) -> some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            // TODO: Implement quick amount calculation based on portfolio balance
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(DS.Adaptive.chipBackground)
                )
                .overlay(
                    Capsule()
                        .stroke(DS.Adaptive.stroke, lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
    }

    // Helper view for order impact rows
    private func orderImpactRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.Adaptive.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
        }
    }

    // MARK: - Stats Card View
    private var statsCardView: some View {
        let isOffline = priceVM.transportMode == .offline
        
        return VStack(alignment: .leading, spacing: 14) {
            // Premium header
            HStack(spacing: 8) {
                GoldHeaderGlyph(systemName: "chart.bar.doc.horizontal")
                
                Text("Coin Data")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Spacer()
                
                // Connection status badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(isOffline ? Color.orange : Color.green)
                        .frame(width: 5, height: 5)
                    Text(priceVM.transportMode.displayString)
                        .font(.system(size: 10, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill((isOffline ? Color.orange : Color.green).opacity(0.12))
                )
                .foregroundColor(isOffline ? Color.orange : Color.green)
            }
            .contentShape(Rectangle())
            .onLongPressGesture {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                showDiagnostics = true
            }

            coreStatsView
            extendedStatsView
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
    }

    // Added computed properties for displayed 1h and 7d changes
    // Uses cached LivePriceManager values to avoid calling during body computation
    private var displayedChange1hValue: Double? {
        // Use cached value to avoid calling LivePriceManager during body
        return cached1hChange
    }
    
    /// Whether the 1h change value comes from a fresh source (rolling window or provider)
    /// Returns true if we have any 1h change value (LivePriceManager provides best-effort values)
    private var is1hChangeFresh: Bool {
        return cached1hChange != nil
    }

    private var displayedChange7dValue: Double? {
        // Use cached value to avoid calling LivePriceManager during body
        return cached7dChange
    }

    private var realizedVol24hText: String? {
        if let v = realizedVolatilityPercent(prices: freshCoin.sparklineIn7d, anchorPrice: displayedPrice, hours: 24) {
            return String(format: "%.2f%%", v)
        }
        return nil
    }

    // MARK: - Precomputed value strings to reduce ViewBuilder complexity
    private var priceText: String { formatPrice(displayedPrice) }
    private var changeText: String { String(format: "%.2f%%", displayedChange24hValue) }
    private var change1hText: String? { displayedChange1hValue.map { String(format: "%.2f%%", $0) } }
    private var change7dText: String? { displayedChange7dValue.map { String(format: "%.2f%%", $0) } }
    private var marketCapText: String? { (displayedMarketCap ?? 0) > 0 ? formatLargeNumber(displayedMarketCap!) : nil }
    private var fdvText: String? { (displayedFDV ?? 0) > 0 ? formatLargeNumber(displayedFDV!) : nil }
    private var volumeText: String? { (displayedVolume24h ?? 0) > 0 ? formatLargeNumber(displayedVolume24h!) : nil }
    private var rankText: String? { displayedRank.map { String($0) } }
    private var circText: String? { (displayedCirculatingSupply ?? 0) > 0 ? formatLargeNumber(displayedCirculatingSupply!) : nil }
    private var maxSupplyText: String? { (displayedMaxSupply ?? 0) > 0 ? formatLargeNumber(displayedMaxSupply!) : nil }

    // Emphasis color for rank tiers
    private var rankColor: Color {
        guard let r = displayedRank else { return .white }
        if r <= 10 { return Color.gold }
        if r <= 50 { return .green }
        return .white
    }

    // MARK: - Core Stats View
    private var coreStatsView: some View {
        VStack(spacing: 12) {
            statRowWithFreshness(
                title: "1h Change",
                value: change1hText,
                valueColor: (displayedChange1hValue ?? 0) >= 0 ? .green : .red,
                isFresh: is1hChangeFresh,
                infoMessage: is1hChangeFresh ? nil : "Data derived from sparkline; may differ from real-time price movement"
            )
            Divider().background(DS.Adaptive.divider)

            // 24h Change row with "Why?" button for significant moves
            HStack {
                HStack(spacing: 6) {
                    Text("24h Change")
                        .font(.footnote)
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                Spacer()
                HStack(spacing: 8) {
                    // "Why?" button appears for significant moves (>=5%)
                    WhyIsItMovingButton(
                        symbol: coin.symbol.uppercased(),
                        coinName: coin.name,
                        coinId: coin.id,
                        priceChange: displayedChange24hValue
                    )
                    
                    Text(changeText)
                        .monospacedDigit()
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(displayedChange24hValue >= 0 ? .green : .red)
                        .contentTransition(.numericText())
                        .frame(minWidth: 72, alignment: .trailing)
                }
            }
            .transaction { $0.animation = nil }
            Divider().background(DS.Adaptive.divider)

            statRow(title: "7d Change", value: change7dText, valueColor: (displayedChange7dValue ?? 0) >= 0 ? .green : .red)
            Divider().background(DS.Adaptive.divider)

            statRow(title: "Realized Vol (24h)", value: realizedVol24hText, infoMessage: "Std. dev. of intraday returns over last 24h from sparkline; not annualized.")
            Divider().background(DS.Adaptive.divider)

            statRow(title: "Market Cap", value: marketCapText, infoMessage: "Prefer provider Market Cap; may be derived from price × supply or global estimates when missing.")
            Divider().background(DS.Adaptive.divider)

            statRow(title: "FDV", value: fdvText, infoMessage: "Fully Diluted Valuation = price × max supply (falls back to total/circulating when max is unavailable).")
            Divider().background(DS.Adaptive.divider)

            statRow(title: "Volume (24h)", value: volumeText)
        }
        .transaction { $0.animation = nil }
    }

    // MARK: - Extended Stats View
    private var extendedStatsView: some View {
        VStack(spacing: 12) {
            Divider().background(DS.Adaptive.divider)
            statRow(title: "Rank", value: rankText, valueColor: rankColor, shimmerWidth: 40)
            Divider().background(DS.Adaptive.divider)
            statRow(title: "Circ. Supply", value: circText, infoMessage: "Prefer provider circulating supply; else derived as Market Cap ÷ Price; else falls back to total/max supply.")
            Divider().background(DS.Adaptive.divider)
            statRow(title: "Max Supply", value: maxSupplyText, infoMessage: "Prefer provider max supply; else total supply; else circulating supply.")
        }
        .transaction { $0.animation = nil }
    }

    // MARK: - Technicals Section
    private var technicalsSection: some View {
        let summary = techVM.summary
        let w = UIScreen.main.bounds.width
        return VStack(alignment: .leading, spacing: 7) {
            // Header row
            HStack(spacing: 6) {
                GoldHeaderGlyph(systemName: "waveform.path.ecg")
                
                Text("Technicals")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                if techVM.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(DS.Colors.gold)
                } else if isTechFresh {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                        .accessibilityLabel("Live")
                }
                Text(selectedInterval.rawValue)
                    .font(.caption2.weight(.semibold))
                    .fontWidth(.condensed)
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                    .background(DS.Adaptive.cardBackground)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(DS.Adaptive.stroke, lineWidth: 0.6))
                
                Spacer()
                NavigationLink {
                    TechnicalsDetailNativeView(symbol: coin.symbol.uppercased(), tvSymbol: tvSymbol, tvTheme: tvTheme, currentPrice: displayedPrice)
                } label: {
                    HStack(spacing: 4) {
                        Text("More")
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Image(systemName: "chevron.right")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                }
            }
            
            // Gauge with proper sizing and arc labels/end caps enabled
            let gaugeHeight: CGFloat = (w < 390 ? 140 : (w < 430 ? 155 : (w < 480 ? 165 : 175)))
            let gaugeLineWidth: CGFloat = (w < 390 ? 6.0 : (w < 430 ? 7.0 : 7.5))
            TechnicalsGaugeView(
                summary: summary,
                timeframeLabel: selectedInterval.rawValue,
                lineWidth: gaugeLineWidth,
                preferredHeight: gaugeHeight,
                showArcLabels: true,
                showEndCaps: true,
                showVerdictLine: true
            )
            .padding(.horizontal, 4)
            .padding(.top, 4)
            .padding(.bottom, 2) // Tighter spacing before summary grid

            // Summary grid below gauge
            LocalTechSummaryGrid(
                summary: summary,
                indicators: summary.indicators,
                sourceLabel: techVM.sourceLabel,
                preferred: techVM.preferredSource,
                requestedSource: techVM.requestedSource,
                isSwitchingSource: techVM.isSourceSwitchInFlight,
                onSelect: { pref in
                    techVM.setPreferredSource(pref)
                    techVM.refresh(
                        symbol: coin.symbol.uppercased(),
                        interval: selectedInterval,
                        currentPrice: displayedPrice,
                        sparkline: freshCoin.sparklineIn7d,
                        forceBypassCache: true
                    )
                }
            )
            
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            ZStack {
                // Base gradient background matching TechnicalsCardStyle
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
                
                // Subtle inner highlight at top
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                DS.Adaptive.overlay(0.04),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
        .padding(.vertical, 2)
        .transaction { txn in txn.animation = nil }
    }

    // MARK: - Helpers for technicals
    private func verdictFor(score: Double) -> TechnicalVerdict {
        switch score {
        case ..<0.15:
            return .strongSell
        case ..<0.35:
            return .sell
        case ..<0.65:
            return .neutral
        case ..<0.85:
            return .buy
        default:
            return .strongBuy
        }
    }

    private func scoreFromChange(_ pct: Double) -> Double {
        guard !pct.isNaN else { return 0.5 }
        let clamped = min(max(pct, -10), 10)
        return (clamped + 10) / 20 // map -10..+10 -> 0..1
    }
    
    private func normalizePercent(_ v: Double) -> Double {
        let absV = abs(v)
        // Treat small fractions (e.g., 0.051 == 5.1%) as percent
        if absV <= 1.5 { return v * 100.0 }
        // Treat obvious basis points (e.g., 1234 == 12.34%) only when very large
        if absV >= 1000 { return v / 100.0 }
        // Otherwise, assume it's already a percentage
        return v
    }
    
    // Derive a 24h percent change from a 7D sparkline using smart step detection
    private func derived24hChangePercentFromSparkline(_ series: [Double]) -> Double? {
        let s = series.filter { $0.isFinite && $0 > 0 }
        let n = s.count
        guard n >= 3 else { return nil }
        guard let last = s.last, last > 0 else { return nil }
        
        // SMART STEP CALCULATION: Detect actual data coverage based on point count
        let stepHours: Double = {
            if n >= 140 && n <= 200 { return 1.0 }        // Hourly data
            else if n >= 35 && n < 140 { return 4.0 }     // 4-hour interval
            else if n >= 5 && n < 35 { return 24.0 }      // Daily data
            else { return (24.0 * 7.0) / Double(max(1, n - 1)) }  // Fallback
        }()
        
        // Calculate lookback for 24 hours
        let lookbackSteps = max(1, min(n - 1, Int(round(24.0 / stepHours))))
        let prevIdx = n - 1 - lookbackSteps
        guard prevIdx >= 0 else { return nil }
        let prev = s[prevIdx]
        guard prev > 0 else { return nil }
        let frac = (last - prev) / prev
        return frac * 100.0
    }

    private func derived1hChangePercentFromSparkline(_ series: [Double]) -> Double? {
        let s = series.filter { $0.isFinite && $0 > 0 }
        let n = s.count
        guard n >= 2 else { return nil }
        guard let last = s.last, last > 0 else { return nil }
        
        // SMART STEP CALCULATION: Detect actual data coverage based on point count
        let stepHours: Double = {
            if n >= 140 && n <= 200 { return 1.0 }        // Hourly data
            else if n >= 35 && n < 140 { return 4.0 }     // 4-hour interval
            else if n >= 5 && n < 35 { return 24.0 }      // Daily data (can't get 1h from this)
            else { return (24.0 * 7.0) / Double(max(1, n - 1)) }  // Fallback
        }()
        
        // For daily data (24h steps), we can't accurately derive 1h change
        if stepHours >= 24.0 { return nil }
        
        // Calculate lookback for 1 hour
        let lookbackSteps = max(1, min(n - 1, Int(round(1.0 / stepHours))))
        let prevIdx = n - 1 - lookbackSteps
        guard prevIdx >= 0 else { return nil }
        let prev = s[prevIdx]
        guard prev > 0 else { return nil }
        return (last - prev) / prev * 100.0
    }

    private func derived7dChangePercentFromSparkline(_ series: [Double]) -> Double? {
        let s = series
        guard let first = s.first, let last = s.last, first.isFinite, last.isFinite, first > 0 else { return nil }
        return (last - first) / first * 100.0
    }

    private func derivePercentFromSparkline(_ prices: [Double], anchorPrice: Double?, hours: Int) -> Double? {
        let data = prices.filter { $0.isFinite && $0 > 0 }
        if data.isEmpty { return nil }
        let n = data.count
        guard n >= 3 else { return nil }
        
        // SMART STEP CALCULATION: Detect actual data coverage based on point count
        // Common sparkline formats:
        // - 168 points (140-200): Hourly data over 7 days
        // - 42 points (35-55): 4-hour intervals over 7 days
        // - 7 points (5-14): Daily data over 7 days
        let (estimatedTotalHours, stepHours): (Double, Double) = {
            if n >= 140 && n <= 200 {
                return (Double(n - 1), 1.0)  // Hourly data
            } else if n >= 35 && n < 140 {
                return (Double(n - 1) * 4.0, 4.0)  // 4-hour interval
            } else if n >= 5 && n < 35 {
                return (Double(n - 1) * 24.0, 24.0)  // Daily data
            } else {
                let totalH = 24.0 * 7.0
                let step = totalH / Double(max(1, n - 1))
                return (totalH, step)  // Fallback
            }
        }()
        
        // Validate minimum coverage for requested timeframe
        let minimumCoverageRequired = Double(hours) * 0.8
        if estimatedTotalHours < minimumCoverageRequired { return nil }
        
        let lookbackSteps = max(1, Int(round(Double(hours) / stepHours)))
        let minWindow = min(n - 1, max(3, lookbackSteps))
        let nominalIndex = max(0, (n - 1) - minWindow)

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

        let lastVal: Double = {
            if let p = anchorPrice, p.isFinite, p > 0 { return p }
            for idx in stride(from: n - 1, through: 0, by: -1) {
                if data[idx].isFinite && data[idx] > 0 { return data[idx] }
            }
            return 0
        }()
        guard lastVal > 0 else { return nil }
        guard let prevIdx = findUsableIndex(around: nominalIndex) else { return nil }
        let prev = data[prevIdx]
        guard prev > 0 else { return nil }
        let change = ((lastVal - prev) / prev) * 100.0
        // Remove micro-noise: return nil (not 0) to avoid displaying misleading "0.00%"
        if abs(change) < 0.0005 { return nil }
        return change
    }

    private func realizedVolatilityPercent(prices: [Double], anchorPrice: Double?, hours: Int = 24) -> Double? {
        let dataRaw = prices.filter { $0.isFinite && $0 > 0 }
        let n = dataRaw.count
        guard n >= 6 else { return nil }
        
        // SMART STEP CALCULATION: Detect actual data coverage based on point count
        let stepHours: Double = {
            if n >= 140 && n <= 200 { return 1.0 }  // Hourly data
            else if n >= 35 && n < 140 { return 4.0 }  // 4-hour interval
            else if n >= 5 && n < 35 { return 24.0 }  // Daily data
            else { return (24.0 * 7.0) / Double(max(1, n - 1)) }  // Fallback
        }()
        let pointsPerHour = max(1, Int(round(1.0 / stepHours)))
        let windowLen = max(6, min(n, pointsPerHour * max(1, hours)))
        var window = Array(dataRaw.suffix(windowLen))
        // If we have a good anchor price, replace the last sample to reduce drift
        if let p = anchorPrice, p.isFinite, p > 0, let last = window.last, last.isFinite, last > 0 {
            let ratio = p / last
            if ratio > 0.5 && ratio < 1.5 {
                window[window.count - 1] = p
            }
        }
        // Compute log returns
        var returns: [Double] = []
        returns.reserveCapacity(max(0, window.count - 1))
        for i in 1..<window.count {
            let a = window[i - 1]
            let b = window[i]
            guard a > 0, b > 0 else { continue }
            let r = log(b / a)
            if r.isFinite { returns.append(r) }
        }
        guard returns.count >= 4 else { return nil }
        // Realized volatility over the window: sqrt(sum r_i^2) expressed in percent
        let sumSquares = returns.reduce(0.0) { $0 + $1 * $1 }
        let rv = sqrt(sumSquares) * 100.0
        if rv.isFinite { return rv } else { return nil }
    }

    // Best-effort mapping to CoinGecko IDs for quick stat backfill
    private func coingeckoID(for symbol: String, idFallback: String?) -> String {
        switch symbol.uppercased() {
        case "BTC": return "bitcoin"
        case "ETH": return "ethereum"
        case "SOL": return "solana"
        case "XRP": return "ripple"
        case "DOGE": return "dogecoin"
        case "ADA": return "cardano"
        case "BNB": return "binancecoin"
        case "LTC": return "litecoin"
        case "AVAX": return "avalanche-2"
        case "DOT": return "polkadot"
        case "LINK": return "chainlink"
        case "MATIC": return "matic-network"
        case "USDT": return "tether"
        case "USDC": return "usd-coin"
        default:
            if let id = idFallback, id.contains("-") || id == id.lowercased() { return id }
            return symbol.lowercased()
        }
    }

    // One-shot, low-latency fetch for missing stats so UI doesn't shimmer forever
    private func fetchFallbackStatsIfNeeded() {
        // Only fetch if something important is missing
        let needCap = (displayedMarketCap ?? 0) <= 0
        let needMax = (displayedMaxSupply ?? 0) <= 0
        let needCirc = (displayedCirculatingSupply ?? 0) <= 0
        let needFDV = (displayedFDV ?? 0) <= 0
        // Use cached value instead of calling LivePriceManager
        let needRank = (cachedRank == nil) || ((computedRank ?? 10_000) > 10)
        let needVol = (displayedVolume24h ?? 0) <= 0
        guard needCap || needMax || needCirc || needFDV || needRank || needVol else { return }
        if isFetchingFallback { return }
        if Date().timeIntervalSince(lastFallbackFetchAt) < 25 { return }

        isFetchingFallback = true
        lastFallbackFetchAt = Date()

        let symbol = coin.symbol.uppercased()
        let idCandidates: [String] = {
            var arr: [String] = []
            arr.append(coingeckoID(for: symbol, idFallback: freshCoin.id))
            let low = freshCoin.id.lowercased()
            if !arr.contains(low) { arr.append(low) }
            return arr
        }()

        // Cancel previous fallback task and track new one for cleanup on disappear
        fallbackTask?.cancel()
        fallbackTask = Task {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 8
            config.timeoutIntervalForResource = 8
            let session = URLSession(configuration: config)

            struct CGResponse: Decodable {
                struct MarketData: Decodable {
                    let market_cap: [String: Double]?
                    let fully_diluted_valuation: [String: Double]?
                    let total_volume: [String: Double]?
                    let circulating_supply: Double?
                    let total_supply: Double?
                    let max_supply: Double?
                }
                let market_data: MarketData?
                let market_cap_rank: Int?
            }

            for id in idCandidates where !id.isEmpty {
                // Check for task cancellation before each network request
                guard !Task.isCancelled else { break }
                guard let url = URL(string: "https://api.coingecko.com/api/v3/coins/\(id)?localization=false&tickers=false&community_data=false&developer_data=false&sparkline=false") else { continue }
                do {
                    let req = APIConfig.coinGeckoRequest(url: url)
                    let (data, _) = try await session.data(for: req)
                    guard !Task.isCancelled else { break }
                    let decoded = try JSONDecoder().decode(CGResponse.self, from: data)
                    if let md = decoded.market_data {
                        let sym = symbol
                        await MainActor.run {
                            guard !Task.isCancelled else { return }
                            if let usdCap = md.market_cap?["usd"], usdCap.isFinite, usdCap > 0 { self.fallbackCap = usdCap }
                            if let usdFDV = md.fully_diluted_valuation?["usd"], usdFDV.isFinite, usdFDV > 0 { self.fallbackFDV = usdFDV }
                            if let vol = md.total_volume?["usd"], vol.isFinite, vol > 0 { self.fallbackVolume24h = vol }
                            if let circ = md.circulating_supply, circ.isFinite, circ > 0 { self.fallbackCirc = circ }
                            if let mx = md.max_supply, mx.isFinite, mx > 0 { self.fallbackMax = mx }
                            else if let tot = md.total_supply, tot.isFinite, tot > 0 { self.fallbackMax = tot }
                            if let r = decoded.market_cap_rank, r > 0 { self.fallbackRank = r }
                            self.saveCachedStats(cap: self.fallbackCap, fdv: self.fallbackFDV, circ: self.fallbackCirc, max: self.fallbackMax, vol: self.fallbackVolume24h, rank: self.fallbackRank, for: sym)
                            self.lastStatsUpdate = Date()
                        }
                        break
                    }
                } catch {
                    // try next candidate
                }
            }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.isFetchingFallback = false
            }
        }
    }

    // MARK: - Overview Section
    @ViewBuilder
    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            InfoTabs(selected: $selectedInfoTab)
            switch selectedInfoTab {
            case .overview:
                AIOverviewCard(
                    insight: aiInsight,
                    fallbackText: overviewSummaryText(),
                    symbol: coin.symbol.uppercased(),
                    isGenerating: isGeneratingInsight,
                    error: aiInsightError,
                    onTap: { showDeepDive = true }
                )
            case .news:
                CoinNewsEmbed(symbol: coin.symbol.uppercased())
            case .ideas:
                IdeasCard(symbol: coin.symbol.uppercased())
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
        .padding(.vertical, 2)
        .task(id: coin.id) {
            // Use task(id:) instead of onAppear to prevent duplicate generations
            // This only triggers when the coin changes, not on every view recreation
            
            // Check if we already have a fresh cached insight - show immediately without loading
            if let freshCached = CoinAIInsightService.shared.getCachedInsight(for: coin.symbol) {
                aiInsight = freshCached
                return // Fresh cache exists, no need to do anything
            }
            
            // Try to get ANY cached insight (even stale) to show immediately
            if let cached = CoinAIInsightService.shared.getAnyCachedInsight(for: coin.symbol) {
                aiInsight = cached
                // Only refresh in background if truly stale AND not within cooldown
                if !cached.isFresh && CoinAIInsightService.shared.canRefresh(for: coin.symbol) {
                    await generateAIInsight(forceRefresh: false, showLoading: false)
                }
            } else {
                // No cached insight at all - generate with loading spinner
                await generateAIInsight(forceRefresh: false, showLoading: true)
            }
        }
    }
    
    // MARK: - AI Insight Generation
    @MainActor
    private func generateAIInsight(forceRefresh: Bool, showLoading: Bool = true) async {
        // Check for fresh cached insight first (not just any cached insight)
        if !forceRefresh, let cached = CoinAIInsightService.shared.getCachedInsight(for: coin.symbol) {
            aiInsight = cached
            return
        }
        
        // Don't regenerate if already generating
        guard !isGeneratingInsight else { return }
        
        // Only show loading spinner if requested (not when refreshing stale cache in background)
        if showLoading {
            isGeneratingInsight = true
        }
        aiInsightError = nil
        
        // Create fallback insight immediately for better UX
        let fallbackText = CoinAIInsightService.shared.generateFallbackInsight(
            symbol: coin.symbol,
            price: displayedPrice,
            change24h: displayedChange24hValue,
            sparkline: freshCoin.sparklineIn7d
        )
        let fallbackInsight = CoinAIInsight(
            symbol: coin.symbol.uppercased(),
            insightText: fallbackText,
            price: displayedPrice,
            change24h: displayedChange24hValue
        )
        
        // Use timeout to prevent infinite loading (8 seconds max)
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            return true
        }
        
        let insightTask = Task { () -> CoinAIInsight? in
            do {
                return try await CoinAIInsightService.shared.generateInsight(
                    symbol: coin.symbol,
                    price: displayedPrice,
                    change24h: displayedChange24hValue,
                    change7d: displayedChange7dValue,
                    sparkline: freshCoin.sparklineIn7d,
                    forceRefresh: forceRefresh
                )
            } catch {
                aiInsightError = error.localizedDescription
                return nil
            }
        }
        
        // Race between timeout and actual insight generation
        let result = await withTaskGroup(of: CoinAIInsight?.self) { group -> CoinAIInsight? in
            group.addTask {
                await insightTask.value
            }
            group.addTask {
                _ = await timeoutTask.value
                return nil
            }
            
            // Return first non-nil result or nil if timeout wins
            for await result in group {
                if result != nil {
                    group.cancelAll()
                    return result
                }
            }
            return nil
        }
        
        // Use result or fallback
        if let insight = result {
            aiInsight = insight
        } else {
            aiInsight = fallbackInsight
            if aiInsightError == nil {
                aiInsightError = "Timed out - showing cached analysis"
            }
        }
        
        isGeneratingInsight = false
    }
    
    // MARK: - Portfolio Position Banner
    @ViewBuilder
    private var portfolioPositionBanner: some View {
        let holdings = AIFunctionTools.shared.portfolioHoldings
        if let holding = holdings.first(where: { $0.coinSymbol.uppercased() == coin.symbol.uppercased() }) {
            let pnl = holding.profitLoss
            let pnlPercent = holding.costBasis > 0 ? ((holding.currentPrice - holding.costBasis) / holding.costBasis) * 100 : 0
            let isPositive = pnl >= 0
            
            HStack(spacing: 12) {
                // Coin icon
                VStack(spacing: 2) {
                    Image(systemName: "briefcase.fill")
                        .font(.system(size: 16))
                        .foregroundColor(DS.Colors.gold)
                    Text("HOLDING")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                
                // Position details
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(formatQuantity(holding.quantity)) \(coin.symbol.uppercased())")
                        .font(.subheadline.bold())
                        .foregroundColor(DS.Adaptive.textPrimary)
                    Text("Worth \(formatCurrency(holding.currentValue))")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                
                Spacer()
                
                // P/L
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(isPositive ? "+" : "")\(formatCurrency(pnl))")
                        .font(.subheadline.bold())
                        .foregroundColor(isPositive ? .green : .red)
                    Text("\(isPositive ? "+" : "")\(String(format: "%.1f", pnlPercent))%")
                        .font(.caption)
                        .foregroundColor(isPositive ? .green : .red)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isPositive ? Color.green.opacity(0.08) : Color.red.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isPositive ? Color.green.opacity(0.3) : Color.red.opacity(0.3), lineWidth: 1)
            )
        }
    }
    
    // MARK: - AI Trading Signal Section
    @ViewBuilder
    private var aiTradingSignalSection: some View {
        AITradingSignalCard(
            symbol: coin.symbol.uppercased(),
            price: displayedPrice,
            sparkline: freshCoin.sparklineIn7d,
            change24h: displayedChange24hValue,
            signal: tradingSignal,
            isLoading: isGeneratingSignal
        )
        .onAppear {
            if tradingSignal == nil {
                signalTask?.cancel()
                signalTask = Task { await generateTradingSignal() }
            }
        }
        // Regenerate trading signal when TechnicalsViewModel updates with new RSI data
        // This ensures the AI Trading Signal RSI matches the chart's RSI
        // Cancel previous task to prevent race conditions from rapid updates
        .onChange(of: techVM.summary.indicators) { _, _ in
            scheduleDebouncedSignalGeneration()
        }
    }

    private func indicatorsSignature(_ indicators: [IndicatorSignal]) -> String {
        indicators
            .map { "\($0.label)|\(String(describing: $0.signal))|\($0.valueText ?? "")" }
            .joined(separator: "||")
    }

    private func scheduleDebouncedSignalGeneration() {
        let signature = indicatorsSignature(techVM.summary.indicators)
        guard signature != lastSignalIndicatorsSignature else { return }
        lastSignalIndicatorsSignature = signature

        signalDebounceTask?.cancel()
        signalDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            signalTask?.cancel()
            signalTask = Task { await generateTradingSignal() }
        }
    }
    
    @MainActor
    private func generateTradingSignal() async {
        guard !isGeneratingSignal else { return }
        let service = AITradingSignalService.shared
        let fearGreed = ExtendedFearGreedViewModel.shared.currentValue

        // Render something immediately so the card doesn't appear late.
        if tradingSignal == nil {
            if let cached = service.cachedSignal(for: coin.id) {
                tradingSignal = cached
            } else {
                let preview = await service.localPreviewSignal(
                    symbol: coin.symbol.uppercased(),
                    price: displayedPrice,
                    change24h: displayedChange24hValue,
                    sparkline: freshCoin.sparklineIn7d,
                    techVM: techVM,
                    fearGreedValue: fearGreed
                )
                tradingSignal = preview
            }
        }

        isGeneratingSignal = true

        // Use AITradingSignalService: Firebase/DeepSeek first, local fallback.
        let signal = await service.fetchSignal(
            coinId: coin.id,
            symbol: coin.symbol.uppercased(),
            price: displayedPrice,
            change24h: displayedChange24hValue,
            change7d: freshCoin.priceChangePercentage7dInCurrency,
            sparkline: freshCoin.sparklineIn7d,
            techVM: techVM,
            fearGreedValue: fearGreed
        )
        tradingSignal = signal
        
        isGeneratingSignal = false
    }
    
    // Quick actions now integrated into aiTradingSignalSection for cleaner layout
    
    private func shareCurrentCoin() {
        #if os(iOS)
        let text = "\(coin.name) (\(coin.symbol.uppercased())) is trading at \(priceText) (\(displayedChange24hValue >= 0 ? "+" : "")\(String(format: "%.2f", displayedChange24hValue))% 24h) - via CryptoSage"
        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
        #endif
    }
    
    private func toggleWatchlist() {
        let symbol = coin.symbol.uppercased()
        if MarketViewModel.shared.watchlistCoins.contains(where: { $0.symbol.uppercased() == symbol }) {
            FavoritesManager.shared.removeFromFavorites(coinID: symbol)
        } else {
            FavoritesManager.shared.addToFavorites(coinID: symbol)
        }
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
    
    @MainActor
    private func generateWhyExplanation() async {
        guard !isGeneratingWhy else { return }
        isGeneratingWhy = true
        
        // Build context for explanation
        let direction = displayedChange24hValue >= 0 ? "up" : "down"
        let changeText = String(format: "%.1f%%", abs(displayedChange24hValue))
        
        // Check for relevant news
        let newsVM = CryptoNewsFeedViewModel.shared
        let relevantNews = newsVM.articles.filter { article in
            article.title.localizedCaseInsensitiveContains(coin.symbol) ||
            article.title.localizedCaseInsensitiveContains(freshCoin.name)
        }.prefix(3)
        
        // Get market context
        let sentiment = ExtendedFearGreedViewModel.shared.currentValue
        let globalChange = MarketViewModel.shared.globalChange24hPercent
        
        // Try AI explanation (Firebase or local key)
        if APIConfig.hasAICapability {
            do {
                var prompt = "\(coin.symbol.uppercased()) is \(direction) \(changeText) in the last 24 hours. "
                prompt += "Current price: \(formatCurrency(displayedPrice)). "
                
                if let sentiment = sentiment {
                    prompt += "Market sentiment: \(sentiment)/100. "
                }
                if let global = globalChange {
                    prompt += "Overall market is \(global >= 0 ? "up" : "down") \(String(format: "%.1f%%", abs(global))). "
                }
                if !relevantNews.isEmpty {
                    prompt += "Recent headlines: "
                    for article in relevantNews {
                        prompt += "\(article.title). "
                    }
                }
                prompt += "Explain why this coin might be moving in 2-3 sentences. Be specific and reference the data."
                
                let response = try await AIService.shared.sendMessage(
                    prompt,
                    systemPrompt: "You explain crypto price movements concisely. No markdown. Be specific with data.",
                    usePremiumModel: false,
                    includeTools: false,
                    isAutomatedFeature: false, // Use Firebase backend (automated features skip Firebase)
                    maxTokens: 256 // Brief explanation (2-3 sentences)
                )
                whyExplanation = response
            } catch {
                whyExplanation = buildFallbackWhyExplanation(relevantNews: Array(relevantNews), sentiment: sentiment, globalChange: globalChange)
            }
        } else {
            whyExplanation = buildFallbackWhyExplanation(relevantNews: Array(relevantNews), sentiment: sentiment, globalChange: globalChange)
        }
        
        isGeneratingWhy = false
    }
    
    private func buildFallbackWhyExplanation(relevantNews: [CryptoNewsArticle], sentiment: Int?, globalChange: Double?) -> String {
        let direction = displayedChange24hValue >= 0 ? "up" : "down"
        let changeText = String(format: "%.1f%%", abs(displayedChange24hValue))
        
        var explanation = "\(coin.symbol.uppercased()) is \(direction) \(changeText) today. "
        
        // Market context
        if let global = globalChange {
            if (global >= 0) == (displayedChange24hValue >= 0) {
                explanation += "This aligns with the broader market which is \(global >= 0 ? "up" : "down") \(String(format: "%.1f%%", abs(global))). "
            } else {
                explanation += "This is diverging from the market which is \(global >= 0 ? "up" : "down") \(String(format: "%.1f%%", abs(global))). "
            }
        }
        
        // Sentiment
        if let sentiment = sentiment {
            if sentiment < 30 {
                explanation += "Market fear (sentiment at \(sentiment)) may be creating selling pressure. "
            } else if sentiment > 70 {
                explanation += "Market greed (sentiment at \(sentiment)) is driving buying activity. "
            }
        }
        
        // News
        if !relevantNews.isEmpty {
            explanation += "Recent news: \(relevantNews.first?.title ?? ""). "
        }
        
        return explanation
    }
    
    // MARK: - Key Levels Section
    @ViewBuilder
    private var keyLevelsSection: some View {
        let sparkline = freshCoin.sparklineIn7d
        let (support, resistance) = calculateSupportResistance(sparkline: sparkline)
        
        if support != nil || resistance != nil {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    GoldHeaderGlyph(systemName: "chart.line.flattrend.xyaxis")
                    Text("Key Levels")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    Spacer()
                }
                
                PriceLadderView(
                    currentPrice: displayedPrice,
                    support: support,
                    resistance: resistance
                )
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(DS.Adaptive.stroke, lineWidth: 1)
            )
        }
    }
    
    private func calculateSupportResistance(sparkline: [Double]) -> (Double?, Double?) {
        guard sparkline.count >= 10, displayedPrice > 0 else { return (nil, nil) }
        
        let window = Array(sparkline.suffix(96))
        var lows: [Double] = []
        var highs: [Double] = []
        
        if window.count >= 3 {
            for i in 1..<(window.count - 1) {
                let a = window[i - 1]
                let b = window[i]
                let c = window[i + 1]
                if b < a && b < c { lows.append(b) }
                if b > a && b > c { highs.append(b) }
            }
        }
        
        let support = lows.filter { $0 <= displayedPrice }.max() ?? window.filter { $0 <= displayedPrice }.max()
        let resistance = highs.filter { $0 >= displayedPrice }.min() ?? window.filter { $0 >= displayedPrice }.min()
        
        return (support, resistance)
    }

    // Build a concise, AI-style overview using price, 24h change and recent swing levels
    private func overviewSummaryText() -> String {
        let symbol = coin.symbol.uppercased()
        let price = displayedPrice
        let change = displayedChange24hValue
        let changeText = String(format: "%.1f%%", abs(change))
        let direction = change >= 0 ? "up" : "down"
        let seriesRaw = freshCoin.sparklineIn7d
        let series: [Double] = {
            guard let last = seriesRaw.last, last > 0, price > 0 else { return seriesRaw }
            let factor = price / last
            // If the sparkline appears normalized or off by a large factor, rescale to current price
            if factor > 1.5 || factor < 0.5 {
                return seriesRaw.map { $0 * factor }
            } else {
                return seriesRaw
            }
        }()
        let (support, resistance) = nearestSupportAndResistance(current: price, series: series)

        var parts: [String] = []
        parts.append("\(symbol) is \(direction) \(changeText) today, trading near \(formatPrice(price)).")

        if let r = resistance, let s = support {
            parts.append("Watch resistance near \(formatPrice(r)) and support around \(formatPrice(s)).")
        } else if let r = resistance {
            parts.append("Near-term resistance sits around \(formatPrice(r)).")
        } else if let s = support {
            parts.append("Near-term support sits around \(formatPrice(s)).")
        }

        // 7D range and current position within the range
        if let hi7 = series.max(), let lo7 = series.min(), hi7.isFinite, lo7.isFinite, hi7 > lo7 {
            let range = hi7 - lo7
            let pos = max(0, min(1, (price - lo7) / range))
            let posText = String(format: "%.0f%%", pos * 100)
            parts.append("7D: \(formatPrice(lo7))–\(formatPrice(hi7)) (pos ~\(posText)).")
        }

        // Quick facts row (compact)
        var facts: [String] = []
        if let r = displayedRank, r > 0 { facts.append("Rank #\(r)") }
        if let cap = displayedMarketCap, cap > 0 { facts.append("Cap \(formatLargeNumber(cap))") }
        if let vol = displayedVolume24h, vol > 0 { facts.append("Vol \(formatLargeNumber(vol))") }
        if !facts.isEmpty { parts.append(facts.joined(separator: " · ") + ".") }

        return parts.joined(separator: " ")
    }

    // Find simple near-term support/resistance from recent sparkline swings
    private func nearestSupportAndResistance(current: Double, series: [Double]) -> (Double?, Double?) {
        guard series.count >= 10, current.isFinite, current > 0 else { return (nil, nil) }
        // Look at roughly the last ~4 days of hourly-ish samples if available
        let window = Array(series.suffix(96))
        var lows: [Double] = []
        var highs: [Double] = []
        if window.count >= 3 {
            for i in 1..<(window.count - 1) {
                let a = window[i - 1]
                let b = window[i]
                let c = window[i + 1]
                if b < a && b < c { lows.append(b) }
                if b > a && b > c { highs.append(b) }
            }
        }
        // Prefer the nearest below/above the current price
        let support = (lows.filter { $0 <= current }.max()) ?? window.filter { $0 <= current }.max()
        let resistance = (highs.filter { $0 >= current }.min()) ?? window.filter { $0 >= current }.min()
        return (support, resistance)
    }

    // MARK: - Notes Helpers
    private func notesKey(for symbol: String) -> String { "Notes.\(symbol.uppercased())" }
    private func notes(for symbol: String) -> String { UserDefaults.standard.string(forKey: notesKey(for: symbol)) ?? "" }
    private func saveNotes(_ text: String, for symbol: String) { UserDefaults.standard.set(text, forKey: notesKey(for: symbol)) }

    // MARK: - Custom Nav Bar
    private var navBar: some View {
        // LAYOUT FIX: Use fixed-width containers for left/right to ensure true centering
        // The right side has 3 buttons vs 1 on left, so we balance with frame widths
        let buttonSize: CGFloat = 36  // Each button is ~36px (16px icon + 8px padding * 2)
        let buttonSpacing: CGFloat = 6
        let rightSideWidth: CGFloat = (buttonSize * 3) + (buttonSpacing * 2)  // 3 buttons + spacing
        
        return HStack(spacing: 0) {
            // Left side - back button with fixed width matching right side
            HStack {
                CSNavButton(
                    icon: "chevron.left",
                    action: { dismiss() }
                )
                
                Spacer(minLength: 0)
            }
            .frame(width: rightSideWidth)
            
            // Center - coin info (will expand to fill remaining space)
            NavBarCenterView(
                symbol: coin.symbol.uppercased(),
                imageURL: imageURLForSymbol(coin.symbol),
                change24h: displayedChange24hValue,
                formattedPrice: priceText,
                priceHighlight: priceHighlight,
                showPrice: true,
                isPriceStale: isPriceDataStale
            )
            .frame(maxWidth: .infinity)
            
            // Right side - action buttons with fixed width
            HStack(spacing: buttonSpacing) {
                Spacer(minLength: 0)

                // Watchlist toggle button
                let isOnWatchlist = MarketViewModel.shared.watchlistCoins.contains(where: { $0.symbol.uppercased() == coin.symbol.uppercased() })
                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    toggleWatchlist()
                } label: {
                    Image(systemName: isOnWatchlist ? "star.fill" : "star")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(
                            isOnWatchlist
                                ? AnyShapeStyle(LinearGradient(
                                    colors: colorScheme == .dark
                                        ? [BrandColors.goldLight, BrandColors.goldBase]
                                        : [BrandColors.goldBase, BrandColors.goldDark],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                  ))
                                : AnyShapeStyle(DS.Adaptive.textPrimary)
                        )
                        .padding(8)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(DS.Adaptive.cardBackground)
                                if isOnWatchlist {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.white.opacity(colorScheme == .dark ? 0.05 : 0.15), Color.clear],
                                                startPoint: .top,
                                                endPoint: .center
                                            )
                                        )
                                }
                            }
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8).stroke(
                                isOnWatchlist
                                    ? LinearGradient(
                                        colors: colorScheme == .dark
                                            ? [BrandColors.goldLight.opacity(0.5), BrandColors.goldBase.opacity(0.15)]
                                            : [BrandColors.goldDark.opacity(0.30), BrandColors.goldBase.opacity(0.10)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                      )
                                    : LinearGradient(colors: [DS.Adaptive.stroke], startPoint: .leading, endPoint: .trailing),
                                lineWidth: isOnWatchlist ? 1 : 0.8
                            )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isOnWatchlist ? "Remove from watchlist" : "Add to watchlist")
                .accessibilityHint("Toggle watchlist state for this coin")

                // Alert button (global coin action, intentionally separate from AI signal card)
                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    showSetAlert = true
                } label: {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [BrandColors.goldLight, BrandColors.goldBase]
                                    : [BrandColors.goldBase, BrandColors.goldDark],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .padding(8)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(DS.Adaptive.cardBackground)
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(
                                        RadialGradient(
                                            colors: [
                                                (colorScheme == .dark ? BrandColors.goldBase : BrandColors.goldDark).opacity(colorScheme == .dark ? 0.07 : 0.035),
                                                Color.clear
                                            ],
                                            center: .center,
                                            startRadius: 0,
                                            endRadius: 18
                                        )
                                    )
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.white.opacity(colorScheme == .dark ? 0.05 : 0.14), Color.clear],
                                            startPoint: .top,
                                            endPoint: .center
                                        )
                                    )
                            }
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    LinearGradient(
                                        colors: colorScheme == .dark
                                            ? [BrandColors.goldLight.opacity(0.34), BrandColors.goldBase.opacity(0.12)]
                                            : [BrandColors.goldDark.opacity(0.24), BrandColors.goldBase.opacity(0.08)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: colorScheme == .dark ? 1 : 1.15
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Create alert")
                .accessibilityHint("Open alert settings for this coin")
                
                // AI Deep Dive button — premium glass treatment
                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    showDeepDive = true
                } label: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [BrandColors.goldLight, BrandColors.goldBase]
                                    : [BrandColors.goldBase, BrandColors.goldDark],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .padding(8)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(DS.Adaptive.cardBackground)
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(
                                        RadialGradient(
                                            colors: [
                                                (colorScheme == .dark ? BrandColors.goldBase : BrandColors.goldDark).opacity(colorScheme == .dark ? 0.08 : 0.04),
                                                Color.clear
                                            ],
                                            center: .center,
                                            startRadius: 0,
                                            endRadius: 18
                                        )
                                    )
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.white.opacity(colorScheme == .dark ? 0.05 : 0.15), Color.clear],
                                            startPoint: .top,
                                            endPoint: .center
                                        )
                                    )
                            }
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8).stroke(
                                LinearGradient(
                                    colors: colorScheme == .dark
                                        ? [BrandColors.goldLight.opacity(0.35), BrandColors.goldBase.opacity(0.12)]
                                        : [BrandColors.goldDark.opacity(0.25), BrandColors.goldBase.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: colorScheme == .dark ? 1 : 1.2
                            )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open AI Deep Dive")
                .accessibilityHint("Show full AI analysis for this coin")
            }
            .frame(width: rightSideWidth)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(Color.clear)
    }

    // MARK: - Price Formatter
    // PERFORMANCE FIX v25: Cached formatters to avoid allocating NumberFormatter on every call.
    // These formatters are mutated per-call to set fraction digits, but the allocation is done once.
    private static let _decimalFormatter: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; return f
    }()
    private static let _currencyFormatter: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = CurrencyManager.currencyCode; return f
    }()
    
    private func formatPrice(_ value: Double) -> String {
        guard value > 0 else { return "\(CurrencyManager.symbol)0.00" }
        let formatter = Self._decimalFormatter
        if value < 1.0 {
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 8
        } else {
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
        }
        return CurrencyManager.symbol + (formatter.string(from: NSNumber(value: value)) ?? "0.00")
    }
    
    private func formatCurrency(_ value: Double) -> String {
        let formatter = Self._currencyFormatter
        formatter.currencyCode = CurrencyManager.currencyCode
        if value >= 1 {
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 2
        } else {
            formatter.maximumFractionDigits = 4
            formatter.minimumFractionDigits = 2
        }
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }
    
    private func formatQuantity(_ value: Double) -> String {
        let formatter = Self._decimalFormatter
        if value >= 1000 {
            formatter.maximumFractionDigits = 0
        } else if value >= 1 {
            formatter.maximumFractionDigits = 2
        } else {
            formatter.maximumFractionDigits = 6
        }
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }

    // MARK: - Large Number Formatter
    private func formatLargeNumber(_ value: Double) -> String {
        let formatter = Self._decimalFormatter

        func formatted(_ short: Double, suffix: String) -> String {
            if short < 10 {
                formatter.minimumFractionDigits = 1
                formatter.maximumFractionDigits = 1
            } else {
                formatter.minimumFractionDigits = 0
                formatter.maximumFractionDigits = 0
            }
            let s = formatter.string(from: NSNumber(value: short)) ?? String(format: "%.1f", short)
            return "\(s)\(suffix)"
        }
        
        if value >= 1_000_000_000_000 {
            return formatted(value / 1_000_000_000_000, suffix: "T")
        } else if value >= 1_000_000_000 {
            return formatted(value / 1_000_000_000, suffix: "B")
        } else if value >= 1_000_000 {
            return formatted(value / 1_000_000, suffix: "M")
        } else if value >= 1_000 {
            return formatted(value / 1_000, suffix: "K")
        } else {
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 2
            return formatter.string(from: NSNumber(value: value)) ?? String(value)
        }
    }
    
    // MARK: - Polished Stat Row Helpers
    private func leadingIcon(_ systemName: String) -> some View {
        ZStack {
            Circle()
                // LIGHT MODE FIX: Adaptive icon background
                .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                .overlay(Circle().stroke(isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.10), lineWidth: 0.8))
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isDark ? .white : DS.Adaptive.textPrimary)
        }
        .frame(width: 24, height: 24)
    }

    private func valueCapsule(text: String, color: Color = .white) -> some View {
        Text(text)
            .monospacedDigit()
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(isDark ? color : DS.Adaptive.textPrimary)
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            // LIGHT MODE FIX: Adaptive value capsule
            .background(isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.05))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isDark ? Color.white.opacity(0.16) : Color.black.opacity(0.10), lineWidth: 0.8))
    }
    
    private struct SmallInfoButton: View {
        let message: String
        @State private var show = false
        @State private var dismissTask: Task<Void, Never>? = nil
        var body: some View {
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                dismissTask?.cancel()
                withAnimation(.easeInOut(duration: 0.18)) {
                    show.toggle()
                }
                if show {
                    dismissTask = Task {
                        try? await Task.sleep(nanoseconds: 3_500_000_000)
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                show = false
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            .overlay(alignment: .topTrailing) {
                if show {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(message)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(DS.Adaptive.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: 220, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(DS.Adaptive.cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(DS.Adaptive.stroke, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 4)
                    .offset(x: -6, y: -8)
                    .zIndex(20)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
                    .onTapGesture {
                        dismissTask?.cancel()
                        withAnimation(.easeInOut(duration: 0.18)) {
                            show = false
                        }
                    }
                }
            }
            .onDisappear {
                dismissTask?.cancel()
                dismissTask = nil
            }
        }
    }

    // MARK: - Row builders (erase conditional complexity)
    private func statRow(icon: String, title: String, value: String?, valueColor: Color = .white, shimmerWidth: CGFloat = 72) -> some View {
        HStack {
            HStack(spacing: 8) {
                leadingIcon(icon)
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(value != nil ? .gray : .gray.opacity(0.5))
            }
            Spacer()
            if let v = value {
                valueCapsule(text: v, color: valueColor)
            } else {
                ShimmerBar(height: 10, cornerRadius: 6).frame(width: shimmerWidth)
            }
        }
    }

    private func statRow(title: String, value: String?, valueColor: Color = .white, shimmerWidth: CGFloat = 72, infoMessage: String? = nil) -> some View {
        HStack {
            HStack(spacing: 6) {
                Text(title)
                    .font(.footnote)
                    .foregroundColor(value != nil ? .gray : .gray.opacity(0.5))
                if let info = infoMessage {
                    SmallInfoButton(message: info)
                }
            }
            Spacer()
            if let v = value {
                Text(v)
                    .monospacedDigit()
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(valueColor)
                    .contentTransition(.numericText())
                    .frame(minWidth: shimmerWidth, alignment: .trailing)
            } else {
                ShimmerBar(height: 10, cornerRadius: 6).frame(width: shimmerWidth)
            }
        }
        .transaction { $0.animation = nil }
    }
    
    /// Stat row with freshness indicator (orange dot when stale, no dot when fresh)
    private func statRowWithFreshness(title: String, value: String?, valueColor: Color = .white, isFresh: Bool, shimmerWidth: CGFloat = 72, infoMessage: String? = nil) -> some View {
        HStack {
            HStack(spacing: 6) {
                Text(title)
                    .font(.footnote)
                    .foregroundColor(value != nil ? .gray : .gray.opacity(0.5))
                if !isFresh && value != nil {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 5, height: 5)
                        .help("Data may be stale (derived from sparkline)")
                }
                if let info = infoMessage {
                    SmallInfoButton(message: info)
                }
            }
            Spacer()
            if let v = value {
                Text(v)
                    .monospacedDigit()
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(isFresh ? valueColor : valueColor.opacity(0.7))
                    .contentTransition(.numericText())
                    .frame(minWidth: shimmerWidth, alignment: .trailing)
            } else {
                ShimmerBar(height: 10, cornerRadius: 6).frame(width: shimmerWidth)
            }
        }
        .transaction { $0.animation = nil }
    }

    private var isTechFresh: Bool {
        if let d = techVM.lastUpdated {
            return Date().timeIntervalSince(d) < 60
        }
        return false
    }
    
    private var isStatsFresh: Bool {
        if let d = lastStatsUpdate { return Date().timeIntervalSince(d) < 60 }
        return false
    }
    
    private var diagnosticsItems: [DiagItem] {
        var items: [DiagItem] = []
        // Price
        let priceSource: String = {
            if marketVM.allCoins.first(where: { $0.id == coin.id })?.priceUsd != nil { return "Market snapshot" }
            if priceVM.price > 0 { return "Live stream" }
            return "Initial payload"
        }()
        items.append(DiagItem(label: "Price", value: formatPrice(displayedPrice), source: priceSource))
        // 1h change
        let ch1h = displayedChange1hValue
        let ch1hSource: String = {
            // Use cached value to avoid calling LivePriceManager during body
            if cached1hChange != nil { return "Live" }
            if freshCoin.priceChangePercentage1hInCurrency != nil { return "Provider" }
            if derivePercentFromSparkline(freshCoin.sparklineIn7d, anchorPrice: displayedPrice, hours: 1) != nil { return "Sparkline" }
            return "N/A"
        }()
        items.append(DiagItem(label: "Change 1h", value: ch1h.map { String(format: "%.2f%%", $0) } ?? "—", source: ch1hSource))
        // 24h change
        let ch24Source: String = {
            // Use cached value to avoid calling LivePriceManager during body
            if cachedChange24h != nil { return "Live" }
            if marketVM.allCoins.first(where: { $0.id == coin.id })?.dailyChange != nil { return "Provider" }
            if derivePercentFromSparkline(freshCoin.sparklineIn7d, anchorPrice: displayedPrice, hours: 24) != nil { return "Sparkline" }
            return "N/A"
        }()
        items.append(DiagItem(label: "Change 24h", value: String(format: "%.2f%%", displayedChange24hValue), source: ch24Source))
        // 7d change
        let ch7d = displayedChange7dValue
        let ch7Source: String = {
            // Use cached value to avoid calling LivePriceManager during body
            if cached7dChange != nil { return "Live" }
            if freshCoin.priceChangePercentage7dInCurrency != nil { return "Provider" }
            if derivePercentFromSparkline(freshCoin.sparklineIn7d, anchorPrice: displayedPrice, hours: 168) != nil { return "Sparkline" }
            return "N/A"
        }()
        items.append(DiagItem(label: "Change 7d", value: ch7d.map { String(format: "%.2f%%", $0) } ?? "—", source: ch7Source))
        // Market Cap
        let capSource: String = {
            if let cap = freshCoin.marketCap, cap > 0 { return "Provider" }
            if bestCap(for: freshCoin) > 0 { return "Derived price×supply" }
            if let f = fallbackCap, f > 0 { return "Fallback (CG)" }
            return "N/A"
        }()
        items.append(DiagItem(label: "Market Cap", value: marketCapText ?? "—", source: capSource))
        // FDV
        let fdvSource: String = {
            if let m = freshCoin.maxSupply, m > 0 { return "Derived from max supply" }
            if let t = freshCoin.totalSupply, t > 0 { return "Derived from total supply" }
            if let c = displayedCirculatingSupply, c > 0 { return "Derived from circ. supply" }
            if let f = fallbackFDV, f > 0 { return "Fallback (CG)" }
            return "N/A"
        }()
        items.append(DiagItem(label: "FDV", value: fdvText ?? "—", source: fdvSource))
        // Volume 24h
        let volSource: String = {
            // Use cached value to avoid calling LivePriceManager during body
            if cachedVolume24h != nil { return "Live" }
            if freshCoin.volumeUsd24Hr != nil { return "Provider" }
            if let f = fallbackVolume24h, f > 0 { return "Fallback (CG)" }
            return "N/A"
        }()
        items.append(DiagItem(label: "Volume 24h", value: volumeText ?? "—", source: volSource))
        // Rank
        let rankSource: String = {
            if fallbackRank != nil { return "Cached CG" }
            // Use cached value to avoid calling LivePriceManager during body
            if cachedRank != nil { return "Live" }
            if computedRank != nil { return "Local snapshot" }
            return "N/A"
        }()
        items.append(DiagItem(label: "Rank", value: rankText ?? "—", source: rankSource))
        // Circulating supply
        let circSource: String = {
            if let cs = freshCoin.circulatingSupply, cs > 0 { return "Provider" }
            if let cap = displayedMarketCap, cap > 0, displayedPrice > 0 { return "Derived cap/price" }
            if let t = freshCoin.totalSupply, t > 0 { return "Total supply fallback" }
            if let m = freshCoin.maxSupply, m > 0 { return "Max supply fallback" }
            if let f = fallbackCirc, f > 0 { return "Fallback (CG)" }
            return "N/A"
        }()
        items.append(DiagItem(label: "Circ. Supply", value: circText ?? "—", source: circSource))
        // Max supply
        let maxSource: String = {
            if let m = freshCoin.maxSupply, m > 0 { return "Provider" }
            if let t = freshCoin.totalSupply, t > 0 { return "Total supply" }
            if let cs = freshCoin.circulatingSupply, cs > 0 { return "Circulating supply" }
            // Use cached value to avoid calling LivePriceManager during body
            if cachedMaxSupply != nil { return "Live alt" }
            if let f = fallbackMax, f > 0 { return "Fallback (CG)" }
            return "N/A"
        }()
        items.append(DiagItem(label: "Max Supply", value: maxSupplyText ?? "—", source: maxSource))
        // Realized vol 24h
        if let vol = realizedVolatilityPercent(prices: freshCoin.sparklineIn7d, anchorPrice: displayedPrice, hours: 24) {
            items.append(DiagItem(label: "Realized Vol 24h", value: String(format: "%.2f%%", vol), source: "Sparkline"))
        } else {
            items.append(DiagItem(label: "Realized Vol 24h", value: "—", source: "Insufficient data"))
        }
        // Freshness
        if let ts = lastStatsUpdate {
            let age = Int(Date().timeIntervalSince(ts))
            items.append(DiagItem(label: "Stats age", value: "\(age)s", source: isStatsFresh ? "Live" : "Stale"))
        }
        return items
    }

    private var diagnosticsSparklineInfo: String {
        let data = freshCoin.sparklineIn7d.filter { $0.isFinite && $0 > 0 }
        let n = data.count
        let pph = max(1, Int(round(Double(max(1, n - 1)) / (7.0 * 24.0))))
        var parts: [String] = []
        parts.append("Sparkline points: \(n) (~\(pph)/hr)")
        if let last = data.last, last > 0, displayedPrice > 0 {
            let ratio = displayedPrice / last
            let rtxt = String(format: "%.2fx", ratio)
            parts.append("Anchor/last ratio: \(rtxt)")
        }
        return parts.joined(separator: " · ")
    }

    private func bestPopoverEdge(for frame: CGRect, desiredHeight: CGFloat = 340) -> Edge {
        #if os(iOS)
        let screen = UIScreen.main.bounds
        let spaceBelow = max(0, screen.height - frame.maxY)
        let spaceAbove = max(0, frame.minY)
        if spaceBelow >= desiredHeight || spaceBelow >= spaceAbove { return .top } // show below the button
        return .bottom // show above the button
        #else
        return .top
        #endif
    }
}

// MARK: - Extracted Chart Card and Components
private struct ChartCard: View {
    @Binding var selectedChartType: ChartType
    @Binding var selectedInterval: ChartInterval
    @Binding var showTimeframePopover: Bool
    @Binding var timeframeButtonFrame: CGRect
    @Binding var timeframePopoverEdge: Edge
    @Binding var showIndicatorMenu: Bool

    let indicatorsCount: Int
    let symbol: String
    let tvSymbol: String
    let tvTheme: String
    let tvStudies: [String]
    let tvAltSymbols: [String]
    let isCompact: Bool
    let edgeProvider: (CGRect) -> Edge
    let livePrice: Double

    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    // Premium glass background colors
    private var cardFillColor: Color {
        isDark ? DS.Neutral.surface : DS.Adaptive.cardBackground
    }
    private var cardStrokeColor: Color {
        isDark ? DS.Neutral.stroke : Color.black.opacity(0.08)
    }
    private var topHighlightOpacity: Double {
        isDark ? 0.06 : 0.03
    }
    private var bottomShadeOpacity: Double {
        isDark ? 0.25 : 0.08
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Premium glass background with depth gradient (matching TradeView)
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [
                            colorScheme == .dark ? Color.black.opacity(0.20) : Color.black.opacity(0.04),
                            colorScheme == .dark ? Color.black.opacity(0.10) : Color.black.opacity(0.02)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .background(cardFillColor)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            // Subtle grid overlay for depth (4 rows, 6 columns)
            GeometryReader { geo in
                let rows = 4
                let cols = 6
                Path { path in
                    // Horizontal grid lines
                    for i in 1..<rows {
                        let y = geo.size.height * CGFloat(i) / CGFloat(rows)
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    // Vertical grid lines
                    for i in 1..<cols {
                        let x = geo.size.width * CGFloat(i) / CGFloat(cols)
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: geo.size.height))
                    }
                }
                // LIGHT MODE FIX: Adaptive grid
                .stroke(isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.04), lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(spacing: 0) {
                // Chart content kept alive for both sources
                // NOTE: No horizontal padding on chart to ensure RSI/indicator alignment
                // The chart measures its plot area internally and passes insets to oscillators
                // External padding would cause the crosshair and indicators to be misaligned
                ChartAreaView(
                    symbol: symbol,
                    selectedInterval: selectedInterval,
                    tvSymbol: tvSymbol,
                    tvTheme: tvTheme,
                    tvStudies: tvStudies,
                    tvAltSymbols: tvAltSymbols,
                    selectedChartType: selectedChartType,
                    livePrice: livePrice
                )
                .padding(.horizontal, 0)  // Match TradeView - no external padding on chart
                .padding(.top, 2)
                .padding(.bottom, 6)

                // Controls row - tighter layout, padding is handled inside the row
                ChartControlsRow(
                    selectedChartType: $selectedChartType,
                    selectedInterval: $selectedInterval,
                    showTimeframePopover: $showTimeframePopover,
                    timeframeButtonFrame: $timeframeButtonFrame,
                    timeframePopoverEdge: $timeframePopoverEdge,
                    showIndicatorMenu: $showIndicatorMenu,
                    indicatorsCount: indicatorsCount,
                    isCompact: isCompact,
                    edgeProvider: edgeProvider
                )
                .padding(.top, 4)
                .padding(.vertical, 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        // Border stroke
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(cardStrokeColor, lineWidth: 0.8)
                .allowsHitTesting(false)
        )
        // Top highlight gradient for premium glass effect
        .overlay(
            LinearGradient(
                colors: [Color.white.opacity(topHighlightOpacity), Color.clear],
                startPoint: .top,
                endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .allowsHitTesting(false)
        )
        // Subtle bottom shade for depth
        .overlay(
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(bottomShadeOpacity)],
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .allowsHitTesting(false)
        )
    }
}

private struct ChartAreaView: View {
    let symbol: String
    let selectedInterval: ChartInterval
    let tvSymbol: String
    let tvTheme: String
    let tvStudies: [String]
    let tvAltSymbols: [String]
    let selectedChartType: ChartType
    let livePrice: Double
    
    // LAZY CREATION + PERSISTENT LIFECYCLE:
    // - Don't create the TradingView WKWebView until the user first switches to it
    //   (avoids the 7+ second WebKit process launch delay on initial app load)
    // - Once created, keep it alive (hidden) so subsequent toggles are instant
    //   (avoids the 1-2 second reload that happened when destroying/recreating every switch)
    @State private var tradingViewCreated = false

    var body: some View {
        ZStack {
            // CryptoSage AI chart - has built-in crosshair and haptic feedback
            // showPercentageBadge: false - the header already shows the price change
            // livePrice: sync chart tooltip with header when at rightmost position
            if selectedChartType == .cryptoSageAI {
                CryptoChartView(symbol: symbol, interval: selectedInterval, height: 240, showPercentageBadge: false, livePrice: livePrice)
                    // SEAMLESS: Use symbol-only ID so timeframe switches update in-place
                    // instead of destroying and recreating the entire chart (which causes flicker).
                    // CryptoChartView handles interval changes internally via .onChange(of: interval)
                    .id("detail-\(symbol)")
                    .transaction { $0.animation = nil }
            }

            // LAZY PERSISTENT TRADINGVIEW:
            // Once the user switches to TradingView for the first time, the WebView stays alive
            // in the view hierarchy. When CryptoSage AI is selected, TradingView is hidden via
            // opacity(0) + disabled hit testing — this keeps the WKWebView process warm and avoids
            // the 1-2 second reload on every toggle. The WebView is never created until first use,
            // so it doesn't impact initial app launch performance.
            if tradingViewCreated {
                TradingViewChartWebView(
                    symbol: tvSymbol,
                    interval: selectedInterval.tvValue,
                    theme: tvTheme,
                    studies: tvStudies,
                    altSymbols: tvAltSymbols,
                    interactive: selectedChartType == .tradingView
                )
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 240, maxHeight: 240)
                .opacity(selectedChartType == .tradingView ? 1 : 0)
                .allowsHitTesting(selectedChartType == .tradingView)
            }
        }
        .onChange(of: selectedChartType) { _, newType in
            if newType == .tradingView && !tradingViewCreated {
                tradingViewCreated = true
            }
        }
    }
}

private struct ChartControlsRow: View {
    @Binding var selectedChartType: ChartType
    @Binding var selectedInterval: ChartInterval
    @Binding var showTimeframePopover: Bool
    @Binding var timeframeButtonFrame: CGRect
    @Binding var timeframePopoverEdge: Edge
    @Binding var showIndicatorMenu: Bool

    let indicatorsCount: Int
    let isCompact: Bool
    let edgeProvider: (CGRect) -> Edge
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var timeframeFrameDebounce: DispatchWorkItem? = nil

    var body: some View {
        // Integrated row: Segmented source toggle + Timeframe dropdown + Indicators
        // NO ScrollView - fixed width, perfectly fitted to each device
        HStack(spacing: 6) {
            // Chart source segmented toggle - expands to fill remaining width
            // NO fixedSize so it absorbs any extra space → zero dead pixels
            ChartSourceSegmentedToggle(selected: $selectedChartType)
            
            // Timeframe dropdown button - fixed intrinsic size
            TimeframeDropdownButton(
                interval: selectedInterval.rawValue,
                isActive: showTimeframePopover,
                action: { showTimeframePopover = true }
            )
            .fixedSize(horizontal: true, vertical: false)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: TimeframeButtonFrameKey.self, value: proxy.frame(in: .global))
                }
            )
            .onPreferenceChange(TimeframeButtonFrameKey.self) { frame in
                timeframeFrameDebounce?.cancel()
                let work = DispatchWorkItem { timeframeButtonFrame = frame }
                timeframeFrameDebounce = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.032, execute: work)
            }
            
            // Indicators button - fixed intrinsic size
            IndicatorsButton(
                count: indicatorsCount,
                action: { showIndicatorMenu = true }
            )
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }
}

private struct TimeframeButtonFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    private static var lastUpdateAt: CFTimeInterval = 0
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        guard next != .zero else { return }
        let now = CACurrentMediaTime()
        // Coalesce to at most ~15Hz to reduce multiple updates per frame warnings
        if now - lastUpdateAt < (1.0 / 15.0) { return }
        // Ignore jitter up to 3px to reduce churn
        let dx = abs(next.origin.x - value.origin.x)
        let dy = abs(next.origin.y - value.origin.y)
        let dw = abs(next.size.width - value.size.width)
        let dh = abs(next.size.height - value.size.height)
        if dx < 3.0 && dy < 3.0 && dw < 3.0 && dh < 3.0 { return }
        value = next
        lastUpdateAt = now
    }
}

// UPDATED: TechnicalsSourceRow as a Menu with selection options and chevron
// (TechnicalsSourceRow struct removed)

// Pretty-print and sanitize the technicals source label for UI
// (prettySourceName function removed)


private struct NavBarCenterView: View {
    let symbol: String
    let imageURL: URL?
    let change24h: Double
    let formattedPrice: String
    let priceHighlight: Bool
    let showPrice: Bool
    var isPriceStale: Bool = false  // PRICE CONSISTENCY: Show indicator when data is old
    
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                CoinImageView(symbol: symbol, url: imageURL, size: 24)
                Text(symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(DS.Adaptive.textPrimary)  // STYLING FIX: Use adaptive color
                HStack(spacing: 4) {
                    Image(systemName: change24h >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .foregroundColor(change24h >= 0 ? .green : .red)
                    Text(String(format: "%.2f%%", abs(change24h)))
                        .monospacedDigit()
                        .foregroundColor(change24h >= 0 ? .green : .red)
                }
                .font(.caption2)
                .fontWeight(.bold)
                .padding(.vertical, 2)
                .padding(.horizontal, 6)
                .adaptiveNeutralCapsulePill(isDark: isDark, backgroundOpacity: 0.28, strokeOpacity: 0.18)  // STYLING FIX: Use adaptive pill
                .accessibilityLabel("24 hour change")
                .accessibilityValue("\(String(format: "%.2f", abs(change24h)))% \(change24h >= 0 ? "up" : "down")")
            }
            if showPrice {
                HStack(spacing: 4) {
                    Text(formattedPrice)
                        .monospacedDigit()
                        .font(.system(size: 22, weight: .heavy))
                        // Dark mode: gold gradient; Light mode: clean dark text
                        .foregroundStyle(isPriceStale
                            ? AnyShapeStyle(Color.gray)
                            : AnyShapeStyle(isDark
                                ? AdaptiveGradients.chipGold(isDark: true)
                                : LinearGradient(colors: [Color(white: 0.08), Color(white: 0.08)], startPoint: .top, endPoint: .bottom)))
                        .scaleEffect(priceHighlight ? 1.015 : 1.0)
                    
                    // NOTE: Staleness icon removed - was too alarming for users
                    // The grayed-out price color already provides a subtle visual cue when data is old
                }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(DS.Adaptive.cardBackground.opacity(isDark ? 0.45 : 0.85))  // STYLING FIX: Use adaptive background
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(isPriceStale ? Color.orange.opacity(0.3) : DS.Adaptive.stroke, lineWidth: 1)  // STYLING FIX: Use adaptive stroke
                        )
                )
                .padding(.vertical, 2)
                .padding(.horizontal, 6)
                .animation(.spring(response: 0.28, dampingFraction: 0.78), value: priceHighlight)
                .onLongPressGesture(minimumDuration: 0.4) {
                    #if os(iOS)
                    if !formattedPrice.isEmpty && formattedPrice != "$0.00" {
                        UIPasteboard.general.string = formattedPrice
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    #endif
                }
            }
        }
    }
}


private struct LocalVerdictPill: View {
    let title: String
    let value: String
    let color: Color
    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .fontWidth(.condensed)
                .foregroundColor(DS.Adaptive.textSecondary)
            Text(value)
                .font(.caption2.weight(.bold))
                .fontWidth(.condensed)
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.vertical, 4)
                .padding(.horizontal, 10)
                .background(DS.Adaptive.cardBackground)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(DS.Adaptive.stroke, lineWidth: 0.6))
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DS.Adaptive.overlay(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(DS.Adaptive.stroke.opacity(0.8), lineWidth: 1))
    }
}

private struct LocalQuickSignalsRow: View {
    let summary: TechnicalsSummary
    
    // Check if we have real data loaded
    private var hasRealData: Bool {
        let totalCounts = summary.sellCount + summary.neutralCount + summary.buyCount
        return totalCounts > 0
    }
    
    private func textColor(for verdict: TechnicalVerdict) -> (String, Color) {
        switch verdict {
        case .strongSell: return ("Strong Sell", .red)
        case .sell:       return ("Sell", .red)
        case .neutral:    return ("Neutral", .yellow)
        case .buy:        return ("Buy", .green)
        case .strongBuy:  return ("Strong Buy", .green)
        }
    }
    var body: some View {
        let (overallText, overallColor) = textColor(for: summary.verdict)
        // Build subgroup verdicts from counts
        let maScore = (Double(summary.maBuy) + 0.5 * Double(summary.maNeutral)) / Double(max(1, summary.maSell + summary.maNeutral + summary.maBuy))
        let maVerdict: TechnicalVerdict = {
            switch maScore { case ..<0.15: return .strongSell; case ..<0.35: return .sell; case ..<0.65: return .neutral; case ..<0.85: return .buy; default: return .strongBuy }
        }()
        let (maText, maColor) = textColor(for: maVerdict)
        let oscScore = (Double(summary.oscBuy) + 0.5 * Double(summary.oscNeutral)) / Double(max(1, summary.oscSell + summary.oscNeutral + summary.oscBuy))
        let oscVerdict: TechnicalVerdict = {
            switch oscScore { case ..<0.15: return .strongSell; case ..<0.35: return .sell; case ..<0.65: return .neutral; case ..<0.85: return .buy; default: return .strongBuy }
        }()
        let (oscText, oscColor) = textColor(for: oscVerdict)
        
        // Always show computed values - avoid horizontal scrolling for a cleaner card.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                LocalVerdictPill(title: "Overall", value: overallText, color: overallColor)
                LocalVerdictPill(title: "MAs", value: maText, color: maColor)
                LocalVerdictPill(title: "Osc", value: oscText, color: oscColor)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    LocalVerdictPill(title: "Overall", value: overallText, color: overallColor)
                    LocalVerdictPill(title: "MAs", value: maText, color: maColor)
                }
                HStack(spacing: 8) {
                    LocalVerdictPill(title: "Osc", value: oscText, color: oscColor)
                    Spacer(minLength: 0)
                }
            }
        }
        // Use opacity fade-in instead of changing content/id
        .opacity(hasRealData ? 1 : 0.3)
        .animation(.easeOut(duration: 0.2), value: hasRealData)
        // Suppress any animations during initial load
        .transaction { txn in
            if !hasRealData { txn.animation = nil }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick technical signals")
    }
}

private struct LocalCountPill: View {
    let title: String
    let value: Int
    let color: Color
    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .fontWidth(.condensed)
                .foregroundColor(DS.Adaptive.textSecondary)
            Text("\(value)")
                .font(.caption2.weight(.bold))
                .fontWidth(.condensed)
                .foregroundColor(color)
                .monospacedDigit()
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(DS.Adaptive.cardBackground)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(DS.Adaptive.stroke, lineWidth: 0.6))
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DS.Adaptive.overlay(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(DS.Adaptive.stroke.opacity(0.8), lineWidth: 1))
    }
}

private struct LocalCountsRow: View {
    let summary: TechnicalsSummary
    var body: some View {
        HStack(spacing: 6) {
            LocalCountPill(title: "Sell", value: summary.sellCount, color: .red)
            LocalCountPill(title: "Neutral", value: summary.neutralCount, color: .yellow)
            LocalCountPill(title: "Buy", value: summary.buyCount, color: .green)
            Spacer(minLength: 0)
        }
        .padding(.top, 0)
    }
}

private struct LocalSignalChip: View {
    let label: String
    let value: String?
    let color: Color
    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .fontWidth(.condensed)
                .foregroundColor(DS.Adaptive.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let v = value, !v.isEmpty {
                Text(v)
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .fontWidth(.condensed)
                    .foregroundColor(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 9)
        .frame(maxWidth: 118)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DS.Adaptive.overlay(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DS.Adaptive.stroke.opacity(0.8), lineWidth: 0.8)
        )
    }
}

private struct LocalTopSignalsRow: View {
    let indicators: [IndicatorSignal]
    private func color(for s: IndicatorSignalStrength) -> Color { switch s { case .sell: return .red; case .neutral: return .yellow; case .buy: return .green } }
    var body: some View {
        let top = Array(indicators.prefix(3))
        if !top.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(top) { sig in
                        LocalSignalChip(label: sig.label, value: sig.valueText, color: color(for: sig.signal))
                    }
                }
                .padding(.horizontal, 2)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Top indicator signals")
        }
    }
}

// Refined LocalTechSummaryGrid with cleaner layout
private struct LocalTechSummaryGrid: View {
    let summary: TechnicalsSummary
    let indicators: [IndicatorSignal]
    let sourceLabel: String
    let preferred: TechnicalsViewModel.TechnicalsSourcePreference
    let requestedSource: TechnicalsViewModel.TechnicalsSourcePreference
    let isSwitchingSource: Bool
    let onSelect: (TechnicalsViewModel.TechnicalsSourcePreference) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Row 1: Quick verdict pills (Overall, MAs, Osc)
            LocalQuickSignalsRow(summary: summary)
            
            // Row 2+: Counts + signals + source, optimized for compact widths
            CombinedCountsSignalsSourceRow(
                summary: summary,
                indicators: indicators,
                sourceLabel: sourceLabel,
                preferred: preferred,
                requestedSource: requestedSource,
                isSwitchingSource: isSwitchingSource,
                onSelect: onSelect
            )
        }
        .transaction { txn in txn.animation = nil }
    }
}

private struct CombinedCountsSignalsSourceRow: View {
    let summary: TechnicalsSummary
    let indicators: [IndicatorSignal]
    let sourceLabel: String
    let preferred: TechnicalsViewModel.TechnicalsSourcePreference
    let requestedSource: TechnicalsViewModel.TechnicalsSourcePreference
    let isSwitchingSource: Bool
    let onSelect: (TechnicalsViewModel.TechnicalsSourcePreference) -> Void

    private func color(for s: IndicatorSignalStrength) -> Color {
        switch s {
        case .sell: return .red
        case .neutral: return .yellow
        case .buy: return .green
        }
    }

    var body: some View {
        let top = Array(indicators.prefix(2))
        let isWide = UIScreen.main.bounds.width >= 430
        
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                LocalCountPill(title: "Sell", value: summary.sellCount, color: .red)
                LocalCountPill(title: "Neutral", value: summary.neutralCount, color: .yellow)
                LocalCountPill(title: "Buy", value: summary.buyCount, color: .green)
                if isWide { Spacer(minLength: 0) }
            }
            
            HStack(alignment: .center, spacing: 6) {
                if !top.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(top) { sig in
                            LocalSignalChip(label: sig.label, value: sig.valueText, color: color(for: sig.signal))
                        }
                    }
                } else {
                    Text("Signals updating...")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(DS.Adaptive.textTertiary)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                }
                
                Spacer(minLength: 0)
                
                TechnicalsSourceMenu(
                    sourceLabel: sourceLabel,
                    preferred: preferred,
                    requestedSource: requestedSource,
                    isSwitchingSource: isSwitchingSource,
                    onSelect: onSelect
                )
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isSwitchingSource)
    }
}

private struct InfoTabs: View {
    @Binding var selected: InfoTab
    
    var body: some View {
        // Use shared underline tab picker component
        UnderlineTabPicker(selected: $selected)
    }
}

private struct CoinNewsCategoryChips: View {
    @Binding var selected: CoinNewsCategory
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        let isDark = colorScheme == .dark
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CoinNewsCategory.allCases, id: \.self) { cat in
                    let isSelected = selected == cat
                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        withAnimation(.easeInOut(duration: 0.18)) { selected = cat }
                    } label: {
                        Text(cat.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(isSelected ? TintedChipStyle.selectedText(isDark: isDark) : DS.Adaptive.textPrimary.opacity(0.9))
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .tintedRoundedChip(isSelected: isSelected, isDark: isDark, cornerRadius: 10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

private struct OverviewCard: View {
    let text: String
    let symbol: String
    let onTap: () -> Void
    let onAddNotes: () -> Void
    let showNotesButton: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        VStack(spacing: 8) {
            Button(action: onTap) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AdaptiveGradients.chipGold(isDark: isDark))
                        .padding(6)
                    Text(text)
                        .font(.footnote)
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
            }
            .buttonStyle(.plain)
            .padding(8)

            if showNotesButton {
                Button(action: onAddNotes) {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.pencil")
                        Text("Add notes to \(symbol)")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(DS.Adaptive.overlay(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.Adaptive.stroke.opacity(0.6), lineWidth: 0.6))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - AI-Enhanced Overview Card
private struct AIOverviewCard: View {
    let insight: CoinAIInsight?
    let fallbackText: String
    let symbol: String
    let isGenerating: Bool
    let error: String?
    let onTap: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    
    /// Full insight text for reference
    private var fullText: String {
        insight?.insightText ?? fallbackText
    }
    
    /// Extract a proper preview that doesn't truncate mid-word/mid-sentence
    private var previewText: String {
        let text = fullText
        
        // If text is short enough, show it all
        if text.count <= 200 {
            return text
        }
        
        // Try to extract just the first 2-3 sentences for a clean preview
        // Use regex to split on sentence endings while preserving decimals in numbers
        // Pattern: period/exclamation/question followed by space and capital letter, or end of string
        let sentencePattern = #"(?<=[.!?])\s+(?=[A-Z])|(?<=[.!?])$"#
        let sentences: [String]
        if let regex = try? NSRegularExpression(pattern: sentencePattern, options: []) {
            let range = NSRange(text.startIndex..., in: text)
            var parts: [String] = []
            var lastEnd = text.startIndex
            regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                if let matchRange = match?.range, let swiftRange = Range(matchRange, in: text) {
                    let sentence = String(text[lastEnd..<swiftRange.lowerBound])
                    if !sentence.trimmingCharacters(in: .whitespaces).isEmpty {
                        parts.append(sentence)
                    }
                    lastEnd = swiftRange.upperBound
                }
            }
            // Add remaining text after last match
            let remaining = String(text[lastEnd...])
            if !remaining.trimmingCharacters(in: .whitespaces).isEmpty {
                parts.append(remaining)
            }
            sentences = parts
        } else {
            // Fallback: simple split but only on ". " followed by uppercase (safer than splitting all periods)
            sentences = text.components(separatedBy: ". ")
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        
        // Build preview from complete sentences, targeting ~180 chars
        var preview = ""
        var count = 0
        for sentence in sentences {
            let trimmed = sentence.trimmingCharacters(in: .whitespaces)
            // Skip section headers like "SUMMARY", "TECHNICAL ANALYSIS", etc.
            if trimmed.uppercased() == trimmed && trimmed.count < 25 {
                continue
            }
            // Preserve original sentence ending if present, otherwise add period
            let endsWithPunctuation = trimmed.last == "." || trimmed.last == "!" || trimmed.last == "?"
            let nextPart = endsWithPunctuation ? trimmed + " " : trimmed + ". "
            if preview.count + nextPart.count > 200 && !preview.isEmpty {
                break
            }
            preview += nextPart
            count += 1
            if count >= 3 { break }
        }
        
        // If we got a good preview, use it
        if !preview.isEmpty {
            return preview.trimmingCharacters(in: .whitespaces)
        }
        
        // Fallback: truncate at word boundary
        let maxLength = 180
        if text.count <= maxLength { return text }
        
        let truncated = String(text.prefix(maxLength))
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "..."
        }
        return truncated + "..."
    }
    
    /// Whether there's more content to see in Deep Dive
    private var hasMoreContent: Bool {
        fullText.count > previewText.count
    }
    
    private var ageText: String? {
        insight?.ageText
    }
    
    var body: some View {
        let isDark = colorScheme == .dark
        
        // Main insight card - tappable to see full Deep Dive
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                // AI sparkle icon with subtle animation when generating
                ZStack {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AdaptiveGradients.chipGold(isDark: isDark))
                    
                    if isGenerating {
                        Circle()
                            .stroke(AdaptiveGradients.chipGold(isDark: isDark), lineWidth: 2)
                            .frame(width: 24, height: 24)
                            .opacity(0.3)
                    }
                }
                .padding(6)
                
                VStack(alignment: .leading, spacing: 6) {
                    if isGenerating {
                        // Shimmer loading state
                        CoinDetailShimmerView()
                            .frame(height: 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        CoinDetailShimmerView()
                            .frame(height: 14)
                            .frame(width: 200, alignment: .leading)
                        CoinDetailShimmerView()
                            .frame(height: 14)
                            .frame(width: 150, alignment: .leading)
                    } else {
                        Text(previewText)
                            .font(.footnote)
                            .foregroundColor(DS.Adaptive.textPrimary)
                            .multilineTextAlignment(.leading)
                            .lineSpacing(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // "Tap for full analysis" with inline timestamp to save space
                        HStack(spacing: 0) {
                            if hasMoreContent {
                                Text("Tap for full analysis")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(DS.Adaptive.textTertiary)
                            }
                            
                            // Inline timestamp - shows right after "Tap for full analysis" or alone
                            if let age = ageText {
                                if hasMoreContent {
                                    Text("  •  ")
                                        .font(.system(size: 10))
                                        .foregroundColor(DS.Adaptive.textTertiary.opacity(0.6))
                                }
                                HStack(spacing: 3) {
                                    Image(systemName: "clock")
                                        .font(.system(size: 8))
                                    Text(age)
                                        .font(.system(size: 10))
                                }
                                .foregroundColor(DS.Adaptive.textTertiary)
                            }
                            
                            Spacer()
                        }
                        .padding(.top, 4)
                        
                        // Error indicator if any (show user-friendly message)
                        // Don't show errors when insight is successfully displaying
                        if let error = error, insight == nil {
                            // Don't show technical/temporary errors to users
                            let isHiddenError = error.lowercased().contains("api key") || 
                                               error.lowercased().contains("not configured") ||
                                               error.lowercased().contains("temporarily unavailable") ||
                                               error.lowercased().contains("timed out")
                            if !isHiddenError {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.system(size: 9))
                                    Text(error)
                                        .font(.system(size: 10))
                                        .lineLimit(1)
                                }
                                .foregroundColor(.orange)
                            }
                        }
                    }
                }
                
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
        }
        .buttonStyle(.plain)
        .padding(10)
    }
}

// MARK: - Shimmer Loading View
private struct CoinDetailShimmerView: View {
    @State private var isAnimating = false
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(
                LinearGradient(
                    colors: isDark
                        ? [Color.white.opacity(0.05), Color.white.opacity(0.1), Color.white.opacity(0.05)]
                        : [Color.black.opacity(0.04), Color.black.opacity(0.07), Color.black.opacity(0.04)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: isDark
                                ? [Color.clear, Color.white.opacity(0.1), Color.clear]
                                : [Color.clear, Color.black.opacity(0.06), Color.clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .offset(x: isAnimating ? 200 : -200)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

private struct ComingSoonCard: View {
    let title: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundColor(DS.Adaptive.textSecondary)
            Text("\(title) is coming soon.")
                .font(.footnote)
                .foregroundColor(DS.Adaptive.textSecondary)
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(DS.Adaptive.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.Adaptive.stroke, lineWidth: 0.8))
    }
}

private struct DiagItem: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let source: String
}

private struct CoinDiagnosticsSheet: View {
    let items: [DiagItem]
    let sparklineInfo: String?
    let lastStatsUpdate: Date?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let info = sparklineInfo, !info.isEmpty {
                    Section("Sparkline") {
                        Text(info)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                Section("Fields") {
                    ForEach(items) { item in
                        HStack {
                            Text(item.label)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(item.value)
                                    .monospacedDigit()
                                    .font(.subheadline.weight(.semibold))
                                Text(item.source)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                if let ts = lastStatsUpdate {
                    Section("Timestamps") {
                        Text("Last stats update: \(relative(ts))")
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Coin Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Text("Close")
                            .foregroundStyle(DS.Adaptive.textSecondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { copyAll() } label: {
                        Text("Copy")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(BrandColors.goldBase)
                    }
                }
            }
        }
    }

    private func relative(_ date: Date) -> String {
        let sec = Int(Date().timeIntervalSince(date))
        if sec < 60 { return "\(sec)s ago" }
        let m = sec / 60
        if m < 60 { return "\(m)m ago" }
        let h = m / 60
        return "\(h)h ago"
    }

    private func copyAll() {
        #if os(iOS)
        let lines = items.map { "\($0.label): \($0.value) [\($0.source)]" }
        let header = sparklineInfo.map { "Sparkline: \($0)" } ?? ""
        UIPasteboard.general.string = ([header] + lines).joined(separator: "\n")
        #endif
    }
}

// MARK: - Trading Signal Models

enum TradingSignalType: String {
    case buy = "BUY"
    case sell = "SELL"
    case hold = "HOLD"
    
    var color: Color {
        switch self {
        case .buy: return .green
        case .sell: return .red
        case .hold: return .orange
        }
    }
    
    var icon: String {
        switch self {
        case .buy: return "arrow.up"
        case .sell: return "arrow.down"
        case .hold: return "minus"
        }
    }
    
    var description: String {
        switch self {
        case .buy: return "AI analysis suggests bullish momentum"
        case .sell: return "AI analysis suggests bearish pressure"
        case .hold: return "Mixed signals — wait for a clearer trend"
        }
    }
    
    // Default sentiment score (overridden by AI when available)
    var defaultSentimentScore: Double {
        switch self {
        case .buy: return 0.7
        case .sell: return -0.7
        case .hold: return 0
        }
    }
}

struct TradingSignal {
    let type: TradingSignalType
    let confidence: Double          // 0-1 normalized score
    let confidenceLabel: String     // "High", "Medium", "Low"
    let reasons: [String]           // Key factors driving the signal
    let reasoning: String           // AI natural language analysis paragraph
    let sentimentScore: Double      // -1.0 to 1.0 from AI (or computed)
    let riskLevel: String           // "Low", "Medium", "High"
    let timestamp: Date
    let isAIPowered: Bool           // true = from DeepSeek, false = local fallback
    
    var confidenceText: String {
        confidenceLabel
    }
    
    var confidenceColor: Color {
        switch confidenceLabel {
        case "High": return .green
        case "Medium": return .yellow
        default: return .orange
        }
    }
    
    /// Relative time string for when the signal was last updated
    var timeAgoText: String {
        let seconds = Int(Date().timeIntervalSince(timestamp))
        if seconds < 60 { return "Just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        return "\(hours)h ago"
    }
}

// MARK: - AI Trading Signal Card

struct AITradingSignalCard: View {
    let symbol: String
    let price: Double
    let sparkline: [Double]
    let change24h: Double
    let signal: TradingSignal?
    let isLoading: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    @State private var showFullReasoning = false
    @State private var displayedSentimentScore: Double = 0
    @State private var hasMountedGauge = false
    @State private var gaugeDotScale: CGFloat = 1
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // ── Header row ──
            HStack(spacing: 0) {
                HStack(spacing: 7) {
                    GoldHeaderGlyph(systemName: "waveform.path.ecg.rectangle")
                    Text("AI Trading Signal")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                Spacer()
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.65)
                        .tint(DS.Colors.gold)
                } else if let signal = signal {
                    HStack(spacing: 5) {
                        if signal.isAIPowered {
                            HStack(spacing: 2) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 8, weight: .bold))
                                Text("AI")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .foregroundColor(DS.Colors.gold)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(DS.Colors.gold.opacity(0.15)))
                        }
                        Text(signal.timeAgoText)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                }
            }
            
            if let signal = signal {
                VStack(spacing: 10) {
                    // ── Signal badge row ──
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(signal.type.color.opacity(0.15))
                                .frame(width: 42, height: 42)
                            Image(systemName: signal.type.icon)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(signal.type.color)
                        }
                        
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(signal.type.rawValue)
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(signal.type.color)
                                
                                Text("Conf \(signal.confidenceText)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(signal.confidenceColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(signal.confidenceColor.opacity(0.15)))
                                
                                riskBadge(signal.riskLevel)
                            }
                            
                            Text(signalSummaryText(signal))
                                .font(.system(size: 11))
                                .foregroundColor(DS.Adaptive.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    
                    // ── Sentiment gauge ──
                    VStack(spacing: 4) {
                        GeometryReader { geo in
                            let gaugeWidth = geo.size.width
                            let normalizedPosition = max(0, min(1, (displayedSentimentScore + 1) / 2))
                            let indicatorX = CGFloat(normalizedPosition) * gaugeWidth
                            
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.red.opacity(0.65),
                                                Color.orange.opacity(0.5),
                                                Color.yellow.opacity(0.45),
                                                Color.green.opacity(0.5),
                                                Color.green.opacity(0.65)
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(height: 8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 0.5)
                                    )
                                
                                ZStack {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 16, height: 16)
                                    Circle()
                                        .fill(signal.type.color)
                                        .frame(width: 10, height: 10)
                                }
                                .scaleEffect(gaugeDotScale)
                                .offset(x: max(0, min(gaugeWidth - 16, indicatorX - 8)))
                            }
                        }
                        .frame(height: 16)
                        .onAppear {
                            runInitialGaugeAnimation(to: signal.sentimentScore)
                        }
                        .onChange(of: signal.sentimentScore) { _, _ in
                            withAnimation(GaugeMotionProfile.settle) {
                                displayedSentimentScore = signal.sentimentScore
                            }
                        }
                        
                        HStack {
                            Text("Bearish")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.red.opacity(0.7))
                            Spacer()
                            Text("Neutral")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(DS.Adaptive.textTertiary)
                            Spacer()
                            Text("Bullish")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.green.opacity(0.7))
                        }
                    }
                    
                    // ── Key factors (compact horizontal flow) ──
                    if !signal.reasons.isEmpty {
                        keyFactorsPills(signal.reasons)
                    }
                    
                    // ── Detailed reasoning (AI only) ──
                    if signal.isAIPowered && !signal.reasoning.isEmpty {
                        aiReasoningSection(signal)
                    }
                    
                }
            } else if isLoading {
                let shimmerFill = isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.04)
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(shimmerFill)
                            .frame(width: 42, height: 42)
                            .shimmer()
                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(shimmerFill)
                                .frame(width: 90, height: 18)
                                .shimmer()
                            RoundedRectangle(cornerRadius: 4)
                                .fill(shimmerFill)
                                .frame(width: 160, height: 12)
                                .shimmer()
                        }
                    }
                    RoundedRectangle(cornerRadius: 4)
                        .fill(shimmerFill)
                        .frame(height: 8)
                        .shimmer()
                }
            }
            
            // Disclaimer
            Text(signal?.isAIPowered == true
                 ? "AI + technical indicator analysis. Not financial advice."
                 : "Technical-indicator preview while AI updates. Not financial advice.")
                .font(.system(size: 9))
                .foregroundColor(DS.Adaptive.textTertiary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
    }
    
    // MARK: - Sub-components
    
    @ViewBuilder
    private func riskBadge(_ level: String) -> some View {
        let color: Color = {
            switch level {
            case "High": return .red
            case "Medium": return .orange
            default: return .green
            }
        }()
        
        HStack(spacing: 2) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text("Risk \(level)")
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundColor(color.opacity(0.9))
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Capsule().fill(color.opacity(0.1)))
    }
    
    /// Key factors displayed as compact wrapped horizontal flow
    @ViewBuilder
    private func keyFactorsPills(_ factors: [String]) -> some View {
        let pills = buildFactorPills(from: factors)
        let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(pills) { pill in
                HStack(spacing: 5) {
                    Image(systemName: pill.icon)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(pill.color)
                    Text(pill.text)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(pill.color.opacity(isDark ? 0.08 : 0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(pill.color.opacity(isDark ? 0.18 : 0.14), lineWidth: 0.5)
                )
            }
        }
    }

    private struct FactorPill: Identifiable {
        let id: String
        let text: String
        let icon: String
        let color: Color
    }

    private func buildFactorPills(from factors: [String]) -> [FactorPill] {
        factors.prefix(4).map { factor in
            FactorPill(
                id: factor,
                text: factor,
                icon: keyFactorIcon(for: factor),
                color: keyFactorColor(for: factor)
            )
        }
    }

    private func runInitialGaugeAnimation(to sentimentScore: Double) {
        let clamped = max(-1.0, min(1.0, sentimentScore))
        if !hasMountedGauge {
            hasMountedGauge = true
            // Always show a visible first animation, including neutral.
            let overshoot = clamped == 0 ? 0.22 : max(-1.0, min(1.0, clamped * 1.04))

            displayedSentimentScore = 0
            gaugeDotScale = 0.96
            withAnimation(GaugeMotionProfile.fill) {
                displayedSentimentScore = overshoot
                gaugeDotScale = 1.08
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                withAnimation(GaugeMotionProfile.springEmphasis) {
                    displayedSentimentScore = clamped
                    gaugeDotScale = 1
                }
            }
            return
        }
        withAnimation(GaugeMotionProfile.settle) {
            displayedSentimentScore = clamped
            gaugeDotScale = 1
        }
    }

    private func signalSummaryText(_ signal: TradingSignal) -> String {
        if signal.isAIPowered {
            return signal.type.description
        }
        switch signal.type {
        case .buy: return "Technical indicators suggest bullish momentum"
        case .sell: return "Technical indicators suggest bearish pressure"
        case .hold: return "Technical indicators are mixed; wait for clearer trend"
        }
    }
    
    /// Context-aware icon for key factor pills
    private func keyFactorIcon(for factor: String) -> String {
        let lower = factor.lowercased()
        if lower.contains("rsi") { return "waveform.path" }
        if lower.contains("macd") { return "chart.line.uptrend.xyaxis" }
        if lower.contains("sma") || lower.contains("ema") || lower.contains("moving") { return "line.diagonal" }
        if lower.contains("volume") { return "chart.bar.fill" }
        if lower.contains("momentum") { return "arrow.up.right" }
        if lower.contains("support") { return "arrow.down.to.line" }
        if lower.contains("resistance") { return "arrow.up.to.line" }
        if lower.contains("oversold") { return "arrow.down.circle" }
        if lower.contains("overbought") { return "arrow.up.circle" }
        if lower.contains("bullish") || lower.contains("buy") { return "arrow.up.right.circle" }
        if lower.contains("bearish") || lower.contains("sell") { return "arrow.down.right.circle" }
        if lower.contains("weak") || lower.contains("decline") { return "exclamationmark.triangle" }
        if lower.contains("strong") || lower.contains("rally") { return "bolt.fill" }
        if lower.contains("below") { return "chevron.down" }
        if lower.contains("above") { return "chevron.up" }
        return "lightbulb.fill"
    }
    
    /// Context-aware color for key factor pills
    private func keyFactorColor(for factor: String) -> Color {
        let lower = factor.lowercased()
        if lower.contains("bearish") || lower.contains("sell") || lower.contains("oversold") || lower.contains("weak") || lower.contains("decline") || lower.contains("below") {
            return .red
        }
        if lower.contains("bullish") || lower.contains("buy") || lower.contains("overbought") || lower.contains("strong") || lower.contains("rally") || lower.contains("above") {
            return .green
        }
        if lower.contains("rsi") || lower.contains("macd") {
            return Color.orange
        }
        if lower.contains("momentum") {
            let hasNeg = lower.contains("-") || lower.contains("weak")
            return hasNeg ? .red : .green
        }
        return DS.Colors.gold
    }
    
    /// AI reasoning section (expandable)
    @ViewBuilder
    private func aiReasoningSection(_ signal: TradingSignal) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showFullReasoning.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: signal.isAIPowered ? "brain.head.profile" : "function")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Colors.gold)
                    Text(signal.isAIPowered ? "AI Analysis" : "Analysis")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textSecondary)
                    Spacer()
                    Image(systemName: showFullReasoning ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
            }
            .buttonStyle(.plain)
            
            if showFullReasoning {
                Text(signal.reasoning)
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.04), lineWidth: 0.5)
        )
    }

}

// MARK: - Why Is Moving Card (Standalone)
/// A prominent card that appears when a coin has moved significantly,
/// explaining the reasons behind the price movement.
private struct WhyIsMovingCard: View {
    let coinId: String
    let symbol: String
    let coinName: String
    let change24h: Double
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingExplanation: Bool = false
    
    private var isPositive: Bool { change24h >= 0 }
    private var changeColor: Color { isPositive ? .green : .red }
    
    var body: some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            showingExplanation = true
        } label: {
            HStack(spacing: 14) {
                // Icon with animated pulse for attention
                ZStack {
                    Circle()
                        .fill(changeColor.opacity(0.15))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(changeColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Why is \(symbol)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        Text("\(isPositive ? "+" : "")\(String(format: "%.1f", change24h))%")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(changeColor)
                        
                        Text("?")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                    }
                    
                    Text("Tap to see what's driving this move")
                        .font(.system(size: 12))
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(changeColor.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(changeColor.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingExplanation) {
            PriceMovementExplanationSheet(
                symbol: symbol,
                coinName: coinName,
                coinId: coinId
            )
        }
    }
}

// MARK: - Quick Action Button

private struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            action()
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(color.opacity(0.3), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// Compact inline action button for quick actions row
private struct CompactActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        let isDark = colorScheme == .dark
        
        Button(action: {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            action()
        }) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(color)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(color.opacity(isDark ? 0.15 : 0.12))
            )
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [color.opacity(0.4), color.opacity(0.2)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Price Ladder View (Vertical Key Levels)

private struct PriceLadderView: View {
    let currentPrice: Double
    let support: Double?
    let resistance: Double?
    
    @Environment(\.colorScheme) private var colorScheme
    
    // PERFORMANCE FIX v25: Cached formatter to avoid allocation per formatPrice call
    private static let _currencyFmt: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = CurrencyManager.currencyCode; return f
    }()
    
    private func distancePercent(from: Double, to: Double) -> Double {
        guard from > 0 else { return 0 }
        return ((to - from) / from) * 100
    }
    
    private func formatPrice(_ value: Double) -> String {
        let formatter = Self._currencyFmt
        formatter.currencyCode = CurrencyManager.currencyCode
        if value >= 1 {
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 2
        } else if value >= 0.01 {
            formatter.maximumFractionDigits = 4
            formatter.minimumFractionDigits = 2
        } else {
            formatter.maximumFractionDigits = 6
            formatter.minimumFractionDigits = 4
        }
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%@%.2f", CurrencyManager.symbol, value)
    }
    
    var body: some View {
        let isDark = colorScheme == .dark
        
        VStack(spacing: 0) {
            // Resistance (top)
            if let resistance = resistance {
                let distPct = distancePercent(from: currentPrice, to: resistance)
                
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(formatPrice(resistance))
                            .font(.system(size: 14, weight: .bold).monospacedDigit())
                            .foregroundColor(.red)
                        Text("Resistance")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 9, weight: .bold))
                            Text("+\(String(format: "%.1f", distPct))%")
                                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        }
                        .foregroundColor(.red)
                        Text("Target if rising")
                            .font(.system(size: 9))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red.opacity(isDark ? 0.08 : 0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.red.opacity(0.15), lineWidth: 0.5)
                )
            }
            
            // Connector + Current price
            if resistance != nil || support != nil {
                HStack {
                    Spacer()
                    VStack(spacing: 2) {
                        if resistance != nil {
                            Rectangle()
                                .fill(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                                .frame(width: 1.5, height: 12)
                        }
                        
                        HStack(spacing: 6) {
                            Circle()
                                .fill(DS.Colors.gold)
                                .frame(width: 8, height: 8)
                            Text(formatPrice(currentPrice))
                                .font(.system(size: 12, weight: .bold).monospacedDigit())
                                .foregroundStyle(AdaptiveGradients.chipGold(isDark: isDark))
                            Text("Current")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(DS.Adaptive.textTertiary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(DS.Colors.gold.opacity(0.08)))
                        .overlay(Capsule().stroke(DS.Colors.gold.opacity(0.2), lineWidth: 0.5))
                        
                        if support != nil {
                            Rectangle()
                                .fill(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                                .frame(width: 1.5, height: 12)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            
            // Support (bottom)
            if let support = support {
                let distPct = distancePercent(from: currentPrice, to: support)
                
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(formatPrice(support))
                            .font(.system(size: 14, weight: .bold).monospacedDigit())
                            .foregroundColor(.green)
                        Text("Support")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 9, weight: .bold))
                            Text("\(String(format: "%.1f", distPct))%")
                                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        }
                        .foregroundColor(.green)
                        Text("Watch if falling")
                            .font(.system(size: 9))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.green.opacity(isDark ? 0.08 : 0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.green.opacity(0.15), lineWidth: 0.5)
                )
            }
        }
    }
}

// MARK: - Why Is It Moving Sheet

private struct WhyIsItMovingSheet: View {
    let symbol: String
    let change24h: Double
    let explanation: String
    let isLoading: Bool
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    private var isPositive: Bool { change24h >= 0 }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    HStack(spacing: 12) {
                        Image(systemName: isPositive ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(isPositive ? .green : .red)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(symbol)
                                .font(.title2.bold())
                            Text("\(isPositive ? "+" : "")\(String(format: "%.1f", change24h))% today")
                                .font(.headline)
                                .foregroundColor(isPositive ? .green : .red)
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill((isPositive ? Color.green : Color.red).opacity(0.1))
                    )
                    
                    // Explanation
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundColor(DS.Adaptive.gold)
                            Text("CryptoSage AI Analysis")
                                .font(.headline)
                                .foregroundColor(DS.Adaptive.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .allowsTightening(true)
                        }
                        
                        if isLoading {
                            VStack(spacing: 8) {
                                ForEach(0..<4, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(DS.Adaptive.chipBackground)
                                        .frame(height: 16)
                                }
                            }
                        } else {
                            Text(explanation)
                                .font(.body)
                                .foregroundColor(DS.Adaptive.textPrimary)
                                .lineSpacing(4)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(DS.Adaptive.cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
                    )
                    
                    // Disclaimer
                    Text("AI analysis is generated based on available market data and news. This is not financial advice.")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                        .padding(.horizontal)
                }
                .padding()
            }
            .navigationTitle("Why is \(symbol) moving?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Text("Done")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(DS.Adaptive.gold)
                    }
                }
            }
            .toolbarBackground(DS.Adaptive.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
        }
    }
}

