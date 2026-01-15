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
    @State private var goTrade: Bool = false
    @State private var showIndicatorMenu: Bool = false
    @State private var showTimeframePopover: Bool = false
    @State private var timeframeButtonFrame: CGRect = .zero
    @State private var timeframePopoverEdge: Edge = .bottom
    @State private var selectedInfoTab: InfoTab = .overview
    @State private var showDeepDive: Bool = false
    @State private var showNotesEditor: Bool = false
    @State private var showDiagnostics: Bool = false

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

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject private var marketVM: MarketViewModel

    // Latest coin snapshot from the shared market VM (falls back to initial)
    private var freshCoin: MarketCoin {
        marketVM.allCoins.first(where: { $0.id == coin.id }) ?? coin
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
        _priceVM = StateObject(wrappedValue: PriceViewModel(symbol: coin.symbol.uppercased(), timeframe: .live))
        _techVM = StateObject(wrappedValue: TechnicalsViewModel())
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
        // Prefer the MarketViewModel snapshot (kept in sync with LivePriceManager) for spot price
        if let fresh = marketVM.allCoins.first(where: { $0.id == coin.id })?.priceUsd, fresh > 0 { return fresh }
        // Fallback to the local PriceViewModel stream if needed
        if priceVM.price > 0 { return priceVM.price }
        // Seed from initial coin payload as last resort
        return coin.priceUsd ?? 0
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

            NavigationLink("", isActive: $goTrade) {
                TradeView(symbol: coin.symbol.uppercased(), showBackButton: true)
                    .environmentObject(MarketViewModel.shared)
            }
            .hidden()
        }
        .sheet(isPresented: $showIndicatorMenu) {
            ChartIndicatorMenu(isPresented: $showIndicatorMenu, isUsingNativeChart: selectedChartType == .cryptoSageAI)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showDeepDive) {
            DeepDiveSheetView(symbol: coin.symbol.uppercased(), price: displayedPrice, change24h: displayedChange24hValue, sparkline: freshCoin.sparklineIn7d)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showDiagnostics) {
            CoinDiagnosticsSheet(items: diagnosticsItems, sparklineInfo: diagnosticsSparklineInfo, lastStatsUpdate: lastStatsUpdate)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        // Removed NotesEditorSheet per instructions

        .navigationBarBackButtonHidden(true)
        .onAppear {
            // Analytics: Track coin detail view
            AnalyticsService.shared.track(.coinDetailViewed, parameters: ["symbol": coin.symbol.uppercased()])
            
            // Ensure we are subscribed to the same unified live price stream used by Trading
            LivePriceManager.shared.primeVolumeIfNeeded(for: coin.symbol)
            
            // Defer state modifications to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                // Populate cached LivePriceManager values on appear
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
                techVM.refresh(symbol: coin.symbol.uppercased(), interval: selectedInterval, currentPrice: displayedPrice, sparkline: freshCoin.sparklineIn7d)
                let sharedSet = parseIndicatorSet(from: tvIndicatorsRaw)
                if !sharedSet.isEmpty { indicators = sharedSet }
                // Kick a quick backfill so stats don't shimmer forever
                fetchFallbackStatsIfNeeded()
                // If market snapshot is empty, refresh it in the background
                if marketVM.allCoins.isEmpty { Task { await marketVM.loadAllData() } }
            }
        }
        .onDisappear {
            priceVM.stopLiveUpdates()
        }
        .onChange(of: priceVM.price) { _ in
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
        .onChange(of: selectedInterval) { newInterval in
            techVM.refresh(symbol: coin.symbol.uppercased(), interval: newInterval, currentPrice: displayedPrice, sparkline: freshCoin.sparklineIn7d)
        }
        .onChange(of: indicators) { new in
            // Defer state modifications to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                let raw = serializeIndicatorSet(new)
                if tvIndicatorsRaw != raw { tvIndicatorsRaw = raw }
            }
        }
        .onChange(of: tvIndicatorsRaw) { raw in
            // Defer state modifications to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                let set = parseIndicatorSet(from: raw)
                if !set.isEmpty && set != indicators { indicators = set }
            }
        }
        .onReceive(marketVM.objectWillChange) { _ in
            // Defer state modifications to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                fetchFallbackStatsIfNeeded()
            }
        }
        .onReceive(LivePriceManager.shared.publisher) { coins in
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
        .safeAreaInset(edge: .top) { navBar }
        .safeAreaInset(edge: .bottom) { tradeButton }
        .tint(.yellow)
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
            VStack(spacing: 16) {
                chartSection
                overviewSection
                statsCardView
                technicalsSection
            }
            .padding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 10)
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
            edgeProvider: { frame in bestPopoverEdge(for: frame) }
        )
        .frame(maxWidth: .infinity)
    }

    // MARK: - Stats Card View
    private var statsCardView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("Live Coin Data")
                    .font(.headline)
                    .foregroundColor(.white)
                Circle()
                    .fill(isStatsFresh ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                    .accessibilityLabel(isStatsFresh ? "Live" : "Stale")
                
                Spacer()
                
                // Price transport mode indicator (shows WS or Polling)
                let isWS = priceVM.transportMode == .ws
                Text(priceVM.transportMode.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill((isWS ? Color.green : Color.teal).opacity(0.15))
                    )
                    .foregroundStyle(isWS ? Color.green : Color.teal)
                    .accessibilityLabel(isWS ? "WebSocket live" : "REST polling")
                    .opacity(0.9)
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
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 6)
        .padding(.vertical, 4)
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
            Divider().background(Color.white.opacity(0.12))

            statRow(title: "24h Change", value: changeText, valueColor: displayedChange24hValue >= 0 ? .green : .red)
            Divider().background(Color.white.opacity(0.12))

            statRow(title: "7d Change", value: change7dText, valueColor: (displayedChange7dValue ?? 0) >= 0 ? .green : .red)
            Divider().background(Color.white.opacity(0.12))

            statRow(title: "Realized Vol (24h)", value: realizedVol24hText, infoMessage: "Std. dev. of intraday returns over last 24h from sparkline; not annualized.")
            Divider().background(Color.white.opacity(0.12))

            statRow(title: "Market Cap", value: marketCapText, infoMessage: "Prefer provider Market Cap; may be derived from price × supply or global estimates when missing.")
            Divider().background(Color.white.opacity(0.12))

            statRow(title: "FDV", value: fdvText, infoMessage: "Fully Diluted Valuation = price × max supply (falls back to total/circulating when max is unavailable).")
            Divider().background(Color.white.opacity(0.12))

            statRow(title: "Volume (24h)", value: volumeText)
        }
        .transaction { $0.animation = nil }
    }

    // MARK: - Extended Stats View
    private var extendedStatsView: some View {
        VStack(spacing: 12) {
            Divider().background(Color.white.opacity(0.12))
            statRow(title: "Rank", value: rankText, valueColor: rankColor, shimmerWidth: 40)
            Divider().background(Color.white.opacity(0.12))
            statRow(title: "Circ. Supply", value: circText, infoMessage: "Prefer provider circulating supply; else derived as Market Cap ÷ Price; else falls back to total/max supply.")
            Divider().background(Color.white.opacity(0.12))
            statRow(title: "Max Supply", value: maxSupplyText, infoMessage: "Prefer provider max supply; else total supply; else circulating supply.")
        }
        .transaction { $0.animation = nil }
    }

    // MARK: - Technicals Section
    private var technicalsSection: some View {
        let summary = techVM.summary
        let w = UIScreen.main.bounds.width
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Technicals")
                    .font(.headline)
                    .foregroundColor(.white)
                if isTechFresh {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                        .accessibilityLabel("Live")
                }
                Text(selectedInterval.rawValue)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.vertical, 3)
                    .padding(.horizontal, 8)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.6))
                
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
                    .foregroundColor(.white)
                }
            }
            let gaugeHeight: CGFloat = (w < 390 ? 150 : (w < 480 ? 164 : 176))
            TechnicalsGaugeView(summary: summary, timeframeLabel: selectedInterval.rawValue, lineWidth: (w < 390 ? 6.5 : 7.5), preferredHeight: gaugeHeight)
                .scaleEffect(w < 390 ? 0.87 : (w < 430 ? 0.89 : (w < 480 ? 0.91 : 0.92)), anchor: .top)
                .padding(.horizontal, 6)
                .padding(.top, 2)
                .padding(.bottom, 10)

            // Consolidated summary + key facts in a tighter two-row layout
            LocalTechSummaryGrid(
                summary: summary,
                indicators: summary.indicators,
                sourceLabel: techVM.sourceLabel,
                preferred: techVM.preferredSource,
                onSelect: { pref in
                    techVM.preferredSource = pref
                    techVM.refresh(
                        symbol: coin.symbol.uppercased(),
                        interval: selectedInterval,
                        currentPrice: displayedPrice,
                        sparkline: freshCoin.sparklineIn7d,
                        forceBypassCache: true
                    )
                }
            )
            .padding(.bottom, 0)
            
            HStack {
                Spacer()
                TechnicalsSourceMenu(
                    sourceLabel: techVM.sourceLabel,
                    preferred: techVM.preferredSource,
                    onSelect: { pref in
                        techVM.preferredSource = pref
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
            .padding(.top, 4)
            .id("TechSourceMenuRow")
            .transaction { txn in txn.animation = nil }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 6)
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
    
    // Derive a 24h percent change from a 7D sparkline (expects ~hourly samples)
    private func derived24hChangePercentFromSparkline(_ series: [Double]) -> Double? {
        let s = series
        guard s.count >= 25 else { return nil }
        guard let last = s.last, last.isFinite, last > 0 else { return nil }
        let prev = s[s.count - 25]
        guard prev.isFinite, prev > 0 else { return nil }
        let frac = (last - prev) / prev
        return frac * 100.0
    }

    private func derived1hChangePercentFromSparkline(_ series: [Double]) -> Double? {
        let s = series
        guard s.count >= 2 else { return nil }
        guard let last = s.last, last.isFinite, last > 0 else { return nil }
        let prev = s[s.count - 2]
        guard prev.isFinite, prev > 0 else { return nil }
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
        // Estimate samples/hour assuming ~7 days of data
        let pointsPerHour = max(1, Int(round(Double(max(1, n - 1)) / (7.0 * 24.0))))
        let lookback = max(1, pointsPerHour * max(1, hours))
        let minWindow = min(n - 1, max(3, lookback))
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
        // Clamp tiny noise to zero
        if abs(change) < 0.0005 { return 0 }
        return change
    }

    private func realizedVolatilityPercent(prices: [Double], anchorPrice: Double?, hours: Int = 24) -> Double? {
        let dataRaw = prices.filter { $0.isFinite && $0 > 0 }
        let n = dataRaw.count
        guard n >= 6 else { return nil }
        // Estimate samples per hour assuming ~7 days of data
        let pointsPerHour = max(1, Int(round(Double(max(1, n - 1)) / (7.0 * 24.0))))
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

        Task {
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
                guard let url = URL(string: "https://api.coingecko.com/api/v3/coins/\(id)?localization=false&tickers=false&community_data=false&developer_data=false&sparkline=false") else { continue }
                do {
                    let (data, _) = try await session.data(from: url)
                    let decoded = try JSONDecoder().decode(CGResponse.self, from: data)
                    if let md = decoded.market_data {
                        let sym = symbol
                        await MainActor.run {
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
            await MainActor.run { self.isFetchingFallback = false }
        }
    }

    // MARK: - Overview Section
    @ViewBuilder
    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            InfoTabs(selected: $selectedInfoTab)
            switch selectedInfoTab {
            case .overview:
                OverviewCard(
                    text: overviewSummaryText(),
                    symbol: coin.symbol.uppercased(),
                    onTap: { showDeepDive = true },
                    onAddNotes: { },
                    showNotesButton: false
                )
            case .news:
                CoinNewsEmbed(symbol: coin.symbol.uppercased())
            case .ideas:
                IdeasCard(symbol: coin.symbol.uppercased())
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 6)
        .padding(.vertical, 2)
    }
    
    // Removed selectedInfoTabBinding property per instructions

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
        HStack(spacing: 8) {
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                presentationMode.wrappedValue.dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12), lineWidth: 0.8))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            NavBarCenterView(
                symbol: coin.symbol.uppercased(),
                imageURL: imageURLForSymbol(coin.symbol),
                change24h: displayedChange24hValue,
                formattedPrice: priceText,
                priceHighlight: priceHighlight,
                showPrice: true
            )

            Spacer(minLength: 0)

            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                showDeepDive = true
            } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12), lineWidth: 0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(Color.clear)
    }

    // MARK: - Trade Button
    private var tradeButton: some View {
        Button(action: {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            goTrade = true
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(goldButtonGradient)
                    .overlay(
                        LinearGradient(colors: [Color.white.opacity(0.16), Color.clear], startPoint: .top, endPoint: .center)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(ctaRimStrokeGradient, lineWidth: 1)
                    )
                    .overlay(
                        ctaBottomShade
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    )
                Text("Trade \(coin.symbol.uppercased())")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.black.opacity(0.96))
                    .padding(.vertical, 14)
                    .padding(.horizontal, 12)
            }
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
        .buttonStyle(GlowButtonStyle(isSell: false))
        .accessibilityLabel("Trade \(coin.symbol.uppercased())")
        .accessibilityHint("Opens trading for \(coin.symbol.uppercased())")
    }
    
    // MARK: - Price Formatter
    private func formatPrice(_ value: Double) -> String {
        guard value > 0 else { return "$0.00" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        if value < 1.0 {
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 8
        } else {
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
        }
        return "$" + (formatter.string(from: NSNumber(value: value)) ?? "0.00")
    }

    // MARK: - Large Number Formatter
    private func formatLargeNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal

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
                .fill(Color.white.opacity(0.08))
                .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.8))
                .shadow(color: Color.black.opacity(0.25), radius: 2, x: 0, y: 1)
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: 24, height: 24)
    }

    private func valueCapsule(text: String, color: Color = .white) -> some View {
        Text(text)
            .monospacedDigit()
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(color)
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(Color.white.opacity(0.09))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 0.8))
    }
    
    private struct SmallInfoButton: View {
        let message: String
        @State private var show = false
        var body: some View {
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                show = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $show) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(message)
                        .font(.footnote)
                        .foregroundColor(.primary)
                }
                .padding()
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


// MARK: - Compact chart source toggle (AI <-> TV)
private struct ChartSourceToggle: View {
    @Binding var selected: ChartType
    var body: some View {
        HStack(spacing: 2) {
            segment(.cryptoSageAI, label: "CryptoSage AI")
            segment(.tradingView,  label: "TradingView")
        }
        .padding(1)
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chart source")
        .accessibilityValue(selected == .cryptoSageAI ? "CryptoSage AI" : "TradingView")
    }
    private func segment(_ type: ChartType, label: String) -> some View {
        return Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            withAnimation(.easeInOut(duration: 0.18)) { selected = type }
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .fixedSize(horizontal: true, vertical: false)
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .foregroundColor(selected == type ? .black : .white.opacity(0.9))
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(chipGoldGradient)
                            .opacity(selected == type ? 1 : 0)
                        // top gloss
                        RoundedRectangle(cornerRadius: 10)
                            .fill(LinearGradient(colors: [Color.white.opacity(0.18), .clear], startPoint: .top, endPoint: .center))
                            .opacity(selected == type ? 1 : 0)
                        // rim stroke
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(ctaRimStrokeGradient, lineWidth: selected == type ? 0.8 : 0)
                        // bottom shade
                        RoundedRectangle(cornerRadius: 10)
                            .fill(ctaBottomShade)
                            .opacity(selected == type ? 1 : 0)
                    }
                )
        }
        .buttonStyle(.plain)
    }
}


// MARK: - Quick Indicators Gear
private struct QuickIndicatorsButton: View {
    @Binding var selected: Set<IndicatorType>
    var body: some View {
        Menu {
            ForEach(IndicatorType.allCases, id: \.self) { ind in
                let isOn = selected.contains(ind)
                Button(action: {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    if isOn { selected.remove(ind) } else { selected.insert(ind) }
                }) {
                    HStack {
                        Image(systemName: "checkmark")
                            .opacity(isOn ? 1 : 0)
                        Text(ind.label)
                    }
                }
            }
            if !selected.isEmpty {
                Button("Clear", role: .destructive) {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    selected.removeAll()
                }
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                HStack(spacing: 6) {
                    Text("Indicators")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 16)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
                .foregroundColor(.white)
                .accessibilityLabel("Indicators")
                .accessibilityValue(selected.isEmpty ? "None" : "\(selected.count) selected")

                if !selected.isEmpty {
                    Text("\(selected.count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.black)
                        .padding(4)
                        .background(
                            Circle()
                                .fill(Color.gold)
                                .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1))
                        )
                        .offset(x: 8, y: -8)
                }
            }
            .frame(height: 32)
        }
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

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background card with subtle stroke
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 6)

            VStack(spacing: 0) {
                // Chart content kept alive for both sources
                ChartAreaView(
                    symbol: symbol,
                    selectedInterval: selectedInterval,
                    tvSymbol: tvSymbol,
                    tvTheme: tvTheme,
                    tvStudies: tvStudies,
                    tvAltSymbols: tvAltSymbols,
                    selectedChartType: selectedChartType
                )
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 10)

                // Controls row
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
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
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

    var body: some View {
        ZStack {
            // CryptoSage AI chart - has built-in crosshair and haptic feedback
            CryptoChartView(symbol: symbol, interval: selectedInterval, height: 240)
                .opacity(selectedChartType == .cryptoSageAI ? 1 : 0)
                .allowsHitTesting(selectedChartType == .cryptoSageAI)

            // TradingView chart
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
    
    // Debounce work item to avoid "Modifying state during view update" warning
    @State private var timeframeFrameDebounce: DispatchWorkItem? = nil

    var body: some View {
        HStack(spacing: isCompact ? 6 : 10) {
            // Left: Chart source toggle
            ChartSourceToggle(selected: $selectedChartType)
                .frame(height: 32)

            // Middle: Timeframe dropdown (Popover)
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                timeframePopoverEdge = edgeProvider(timeframeButtonFrame)
                showTimeframePopover = true
            } label: {
                HStack(spacing: 6) {
                    Text(selectedInterval.rawValue)
                        .font(.caption)
                        .fontWeight(.semibold)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12), lineWidth: 0.8))
                .foregroundColor(.white)
            }
            .frame(height: 32)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: TimeframeButtonFrameKey.self, value: proxy.frame(in: .global))
                }
            )
            .onPreferenceChange(TimeframeButtonFrameKey.self) { frame in
                // Defer state update to next runloop to avoid "Modifying state during view update"
                timeframeFrameDebounce?.cancel()
                let work = DispatchWorkItem { timeframeButtonFrame = frame }
                timeframeFrameDebounce = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.032, execute: work)
            }
            .popover(isPresented: $showTimeframePopover, attachmentAnchor: .rect(.bounds), arrowEdge: timeframePopoverEdge) {
                ChartTimeframePicker(isPresented: $showTimeframePopover, selection: $selectedInterval)
                    .presentationCompactAdaptation(.none)
            }
            .accessibilityLabel("Timeframe")
            .accessibilityValue(selectedInterval.rawValue)

            // Right: Indicators button (opens shared ChartIndicatorMenu)
            let activeCount = indicatorsCount
            let isActive = activeCount > 0
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                showIndicatorMenu = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    HStack(spacing: 6) {
                        Text("Indicators")
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 16)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
                    .foregroundColor(.white)

                    if isActive {
                        Text("\(activeCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.black)
                            .padding(4)
                            .background(
                                Circle()
                                    .fill(Color.gold)
                                    .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1))
                            )
                            .offset(x: 8, y: -8)
                    }
                }
            }
            .frame(height: 32)
        }
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

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                CoinImageView(symbol: symbol, url: imageURL, size: 24)
                Text(symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
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
                .neutralCapsulePill(backgroundOpacity: 0.28, strokeOpacity: 0.18)
                .accessibilityLabel("24 hour change")
                .accessibilityValue("\(String(format: "%.2f", abs(change24h)))% \(change24h >= 0 ? "up" : "down")")
            }
            if showPrice {
                Text(formattedPrice)
                    .monospacedDigit()
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(chipGoldGradient)
                    .shadow(color: Color.black.opacity(0.8), radius: 1, x: 0, y: 1)
                    .shadow(color: Color.gold.opacity(priceHighlight ? 0.35 : 0.18), radius: priceHighlight ? 5 : 3, x: 0, y: 0)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.black.opacity(0.45))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.35), radius: 4, x: 0, y: 2)
                    )
                    .padding(.vertical, 2)
                    .padding(.horizontal, 6)
                    .animation(.easeInOut(duration: 0.2), value: priceHighlight)
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
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.caption2.weight(.bold))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.vertical, 2)
                .padding(.horizontal, 7)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.6))
        }
    }
}

private struct LocalQuickSignalsRow: View {
    let summary: TechnicalsSummary
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                LocalVerdictPill(title: "Overall", value: overallText, color: overallColor)
                LocalVerdictPill(title: "MAs", value: maText, color: maColor)
                LocalVerdictPill(title: "Osc", value: oscText, color: oscColor)
            }
            .padding(.horizontal, 2)
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
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text("\(value)")
                .font(.caption2.weight(.bold))
                .foregroundColor(color)
                .monospacedDigit()
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.6))
        }
        .frame(minWidth: 60, alignment: .leading)
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
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.white.opacity(0.9))
            if let v = value, !v.isEmpty {
                Text(v)
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundColor(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.6))
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

// This is the modified LocalTechSummaryGrid body per instructions
private struct LocalTechSummaryGrid: View {
    let summary: TechnicalsSummary
    let indicators: [IndicatorSignal]
    let sourceLabel: String
    let preferred: TechnicalsViewModel.TechnicalsSourcePreference
    let onSelect: (TechnicalsViewModel.TechnicalsSourcePreference) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Row 1: Quick verdicts
            LocalQuickSignalsRow(summary: summary)
            // Row 2: Counts + top indicator chips (incl. Williams %R) + source pill
            CombinedCountsSignalsSourceRow(
                summary: summary,
                indicators: indicators,
                sourceLabel: sourceLabel,
                preferred: preferred,
                onSelect: onSelect
            )
        }
    }
}

private struct CombinedCountsSignalsSourceRow: View {
    let summary: TechnicalsSummary
    let indicators: [IndicatorSignal]
    let sourceLabel: String
    let preferred: TechnicalsViewModel.TechnicalsSourcePreference
    let onSelect: (TechnicalsViewModel.TechnicalsSourcePreference) -> Void

    private func color(for s: IndicatorSignalStrength) -> Color {
        switch s {
        case .sell: return .red
        case .neutral: return .yellow
        case .buy: return .green
        }
    }

    var body: some View {
        let top = Array(indicators.prefix(3))
        let isWide = UIScreen.main.bounds.width >= 500
        if isWide {
            HStack(spacing: 6) {
                LocalCountPill(title: "Sell", value: summary.sellCount, color: .red)
                LocalCountPill(title: "Neutral", value: summary.neutralCount, color: .yellow)
                LocalCountPill(title: "Buy", value: summary.buyCount, color: .green)
                if !top.isEmpty {
                    ForEach(top) { sig in
                        LocalSignalChip(label: sig.label, value: sig.valueText, color: color(for: sig.signal))
                    }
                }
                Spacer(minLength: 0)
            }
        } else {
            // On compact widths, keep everything on one horizontally scrollable row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    LocalCountPill(title: "Sell", value: summary.sellCount, color: .red)
                    LocalCountPill(title: "Neutral", value: summary.neutralCount, color: .yellow)
                    LocalCountPill(title: "Buy", value: summary.buyCount, color: .green)
                    if !top.isEmpty {
                        ForEach(top) { sig in
                            LocalSignalChip(label: sig.label, value: sig.valueText, color: color(for: sig.signal))
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }
}

// Removed LocalSourceMenu entirely as per instructions

private struct InfoTabs: View {
    @Binding var selected: InfoTab
    var body: some View {
        HStack(spacing: 12) {
            ForEach(InfoTab.allCases, id: \.self) { tab in
                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    withAnimation(.easeInOut(duration: 0.18)) { selected = tab }
                } label: {
                    VStack(spacing: 4) {
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: selected == tab ? .semibold : .regular))
                            .foregroundColor(selected == tab ? .white : .white.opacity(0.65))
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                        Capsule()
                            .fill(selected == tab ? chipGoldGradient : LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom))
                            .frame(width: 20, height: 2)
                            .opacity(selected == tab ? 1 : 0)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct CoinNewsCategoryChips: View {
    @Binding var selected: CoinNewsCategory
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CoinNewsCategory.allCases, id: \.self) { cat in
                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        withAnimation(.easeInOut(duration: 0.18)) { selected = cat }
                    } label: {
                        Text(cat.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(selected == cat ? .black : .white.opacity(0.9))
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(
                                Group {
                                    if selected == cat { RoundedRectangle(cornerRadius: 10).fill(chipGoldGradient) }
                                    else { RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)) }
                                }
                            )
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 0.8))
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

    var body: some View {
        VStack(spacing: 8) {
            Button(action: onTap) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(chipGoldGradient)
                        .padding(6)
                    Text(text)
                        .font(.footnote)
                        .foregroundColor(.white)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.white.opacity(0.5))
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
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.vertical, 12)
                    .padding(.horizontal, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06), lineWidth: 0.6))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ComingSoonCard: View {
    let title: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundColor(.white.opacity(0.85))
            Text("\(title) is coming soon.")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.9))
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 0.8))
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
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Copy") { copyAll() }
                        .bold()
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

#if false // Disabled duplicate helper types; using shared versions from CoinDetailSupportViews.swift

private struct CDVDeepDiveSheetView: View {
    let symbol: String
    let price: Double
    let change24h: Double
    let sparkline: [Double]
    @State private var longForm: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(longForm)
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding()
            }
            .navigationTitle("AI Deep Dive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Copy") {
                        #if os(iOS)
                        UIPasteboard.general.string = longForm
                        #endif
                    }
                }
            }
        }
        .onAppear {
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async { regenerate() }
        }
    }

    private func regenerate() {
        longForm = buildDeepDive()
    }

    private func buildDeepDive() -> String {
        let p = price
        let dir = change24h >= 0 ? "up" : "down"
        let c = String(format: "%.2f%%", abs(change24h))
        let (s1, r1) = swingLevels(series: sparkline)
        let hi7 = sparkline.max() ?? p
        let lo7 = sparkline.min() ?? p
        let range7 = hi7 - lo7
        let pos = range7 > 0 ? (p - lo7) / range7 : 0.5
        let posText = String(format: "%.0f%%", pos * 100)
        let mom7 = percentChange(from: sparkline.first, to: sparkline.last)
        let momText = String(format: "%.1f%%", mom7)
        let vol = volatility(of: sparkline)
        let volText = String(format: "%.2f%%", vol)

        var lines: [String] = []
        lines.append("\(symbol) is \(dir) \(c) over the last 24h, trading near \(currency(p)).")
        lines.append("7D range: \(currency(lo7)) – \(currency(hi7)) (position ~\(posText)). 7D momentum: \(momText).")
        if let s1 = s1 { lines.append("Nearest support: \(currency(s1)).") }
        if let r1 = r1 { lines.append("Nearest resistance: \(currency(r1)).") }
        lines.append("Realized intraday volatility (approx.): \(volText).")
        lines.append("Note: Levels are heuristic from recent swing points; confirm with your own analysis.")
        return lines.joined(separator: "\n\n")
    }

    private func percentChange(from: Double?, to: Double?) -> Double {
        guard let f = from, let t = to, f > 0 else { return 0 }
        return (t - f) / f * 100
    }

    private func volatility(of series: [Double]) -> Double {
        guard series.count > 2 else { return 0 }
        var returns: [Double] = []
        for i in 1..<series.count {
            let a = series[i - 1]
            let b = series[i]
            if a > 0 && b > 0 { returns.append((b - a) / a) }
        }
        let mean = returns.reduce(0, +) / Double(max(1, returns.count))
        let varSum = returns.reduce(0) { $0 + pow($1 - mean, 2) }
        let std = sqrt(varSum / Double(max(1, returns.count - 1)))
        return std * 100
    }

    private func swingLevels(series: [Double]) -> (Double?, Double?) {
        guard series.count >= 10 else { return (nil, nil) }
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
        let s = lows.max()
        let r = highs.min()
        return (s, r)
    }

    private func currency(_ v: Double) -> String { "$" + (NumberFormatter.currencyFormatter.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)) }
}

private extension NumberFormatter {
    static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()
}

private struct CDVNotesEditorSheet: View {
    let symbol: String
    @State var text: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    init(symbol: String, initialText: String, onSave: @escaping (String) -> Void) {
        self.symbol = symbol
        self._text = State(initialValue: initialText)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .padding()
                .navigationTitle("Notes · \(symbol)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") { onSave(text); dismiss() }
                            .bold()
                    }
                }
        }
    }
}

private struct CDVIdeasCard: View {
    let symbol: String // coin symbol, e.g., BTC
    @Environment(\.openURL) private var openURL
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TradingView Ideas")
                .font(.headline)
                .foregroundColor(.white)
            CDVTradingViewIdeasWebView(symbol: symbol)
                .frame(height: 420)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1))
            HStack {
                Spacer()
                Button {
                    let url = URL(string: "https://www.tradingview.com/symbols/\(symbol)USD/ideas/")!
                    openURL(url)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                        Text("Open in TradingView")
                    }
                    .font(.footnote.weight(.semibold))
                }
            }
        }
    }
}

// Enhanced to hide banners and force dark mode
private struct CDVTradingViewIdeasWebView: UIViewRepresentable {
    let symbol: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        
        // Inject script at document START to block Smart App Banner before it renders
        let bannerBlockScript = WKUserScript(
            source: """
            (function(){
                // Remove Smart App Banner meta tag immediately and continuously
                function removeAppBanner() {
                    document.querySelectorAll('meta[name="apple-itunes-app"]').forEach(m => m.remove());
                    document.querySelectorAll('meta[name="smartbanner"]').forEach(m => m.remove());
                }
                removeAppBanner();
                var observer = new MutationObserver(function(mutations) {
                    removeAppBanner();
                });
                if(document.documentElement) {
                    observer.observe(document.documentElement, {childList: true, subtree: true});
                }
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(bannerBlockScript)
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.bounces = true
        webView.navigationDelegate = context.coordinator
        #if os(iOS)
        webView.overrideUserInterfaceStyle = .dark
        webView.scrollView.indicatorStyle = .white
        #endif
        webView.load(URLRequest(url: ideasURL()))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // reload only if symbol changed path
        uiView.evaluateJavaScript("document.readyState") { _, _ in
            uiView.load(URLRequest(url: ideasURL()))
        }
    }

    private func ideasURL() -> URL {
        let base = "https://www.tradingview.com/symbols/\(symbol)USD/ideas/"
        // Append a best-effort theme hint; the site may ignore it, but it is harmless
        let path = base + "?theme=dark"
        return URL(string: path) ?? URL(string: "https://www.tradingview.com/ideas/crypto/")!
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Hide app-store banner and sticky headers for a cleaner embed and enforce dark theme
            let js = """
            (function(){
              function applyDark(){
                try{ localStorage.setItem('theme','dark'); }catch(e){}
                try{ document.documentElement.setAttribute('data-theme','dark'); }catch(e){}
                try{ document.body && document.body.classList.add('theme-dark'); }catch(e){}
                try{
                  var meta = document.querySelector('meta[name=\\"color-scheme\\"]');
                  if(!meta){ meta = document.createElement('meta'); meta.name='color-scheme'; document.head.appendChild(meta); }
                  meta.content='dark';
                }catch(e){}
                var css = `
                  :root, html, body { background:#000 !important; color:#ddd !important; }
                  header, .header, .tv-header, .tv-header__link, [data-widget-type=\\"promo\\"], .js-header { display:none !important; }
                  .layout__area--header, .apply-dark-bg { background:#000 !important; }
                `;
                var style = document.getElementById('cs-dark-style');
                if(!style){ style = document.createElement('style'); style.id='cs-dark-style'; style.type='text/css'; style.appendChild(document.createTextNode(css)); document.head.appendChild(style); }
              }
              function hideBanners(){
                try{
                  // Remove obvious App Store install banners and sticky promos
                  document.querySelectorAll('a[href*="apps.apple.com"]').forEach(a=>{
                    let n=a; let steps=0;
                    while(n && n.parentElement && steps++<4){
                      n=n.parentElement;
                      if(n.offsetHeight>60){ n.style.display='none'; break; }
                    }
                  });
                  const sels = [
                    '[data-name=\\"banner\\"]','[data-widget-name=\\"banner\\"]','[class*=\\"banner\\"]',
                    '.tv-floating-toolbar','.js-idea-page__app-promo','.sticky','.stickyHeader'
                  ];
                  sels.forEach(s=>document.querySelectorAll(s).forEach(e=>e.style.display='none'));
                }catch(e){}
              }
              applyDark(); hideBanners();
              const mo = new MutationObserver(()=>{ applyDark(); hideBanners(); });
              mo.observe(document.documentElement,{childList:true,subtree:true});
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}

private struct CDVNewsLinksList: View {
    let symbol: String
    @Environment(\.openURL) private var openURL
    var body: some View {
        VStack(spacing: 8) {
            linkRow(title: "Google News", url: "https://news.google.com/search?q=\(symbol)%20crypto")
            linkRow(title: "Bing News", url: "https://www.bing.com/news/search?q=\(symbol)%20crypto")
            linkRow(title: "CoinDesk", url: "https://www.coindesk.com/search/?q=\(symbol)")
            linkRow(title: "CoinTelegraph", url: "https://cointelegraph.com/tags/\(symbol.lowercased())")
            linkRow(title: "X (Twitter) Search", url: "https://x.com/search?q=\(symbol)%20crypto&src=typed_query")
        }
    }
    private func linkRow(title: String, url: String) -> some View {
        Button {
            if let u = URL(string: url) { openURL(u) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.right.square")
                Text(title)
                Spacer()
            }
            .font(.footnote.weight(.semibold))
            .foregroundColor(.white.opacity(0.9))
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - In-app News Tab (lightweight headlines via Google News RSS)
private struct CDVNewsTab: View {
    let symbol: String
    @State private var selected: CoinNewsCategory = .top
    @StateObject private var vm = CDVCoinNewsViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CoinNewsCategoryChips(selected: $selected)
            if vm.isLoading {
                ProgressView().tint(.white)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            }
            if vm.articles.isEmpty && !vm.isLoading {
                VStack(spacing: 10) {
                    Text("No headlines right now.")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.8))
                    CDVNewsLinksList(symbol: symbol)
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(vm.articles.prefix(6)) { a in
                        CDVArticleRow(article: a)
                    }
                }
            }
            HStack {
                Spacer()
                Link(destination: vm.moreURL(for: symbol, category: selected)) {
                    HStack(spacing: 6) {
                        Image(systemName: "safari")
                        Text("More on Google News")
                    }
                    .font(.footnote.weight(.semibold))
                }
            }
        }
        .onAppear {
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async { vm.fetch(symbol: symbol, category: selected) }
        }
        .onChange(of: selected) { cat in vm.fetch(symbol: symbol, category: cat) }
    }
}

private struct CDVArticleRow: View {
    let article: CDVNewsArticle
    @Environment(\.openURL) private var openURL
    var body: some View {
        Button {
            if let url = URL(string: article.link) { openURL(url) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                if let url = article.imageURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08))
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08))
                        @unknown default:
                            RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08))
                        }
                    }
                    .frame(width: 54, height: 54)
                    .clipped()
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.10), lineWidth: 0.6))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(article.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                    HStack(spacing: 8) {
                        if let src = article.source, !src.isEmpty {
                            Text(src)
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                        Image(systemName: "clock")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                        Text(article.relativeTime)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }
}

private struct CDVNewsArticle: Identifiable {
    let id = UUID()
    let title: String
    let link: String
    let pubDate: Date
    let source: String?
    let imageURL: URL?
    var relativeTime: String {
        let interval = Date().timeIntervalSince(pubDate)
        let minutes = Int(interval / 60)
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        return "\(hours/24)d"
    }
}

private final class CDVCoinNewsViewModel: ObservableObject {
    @Published var articles: [CDVNewsArticle] = []
    @Published var isLoading: Bool = false
    
    private static var cache: [String: (Date, [CDVNewsArticle])] = [:]
    private let cacheTTL: TimeInterval = 10 * 60

    func fetch(symbol: String, category: CoinNewsCategory) {
        let key = symbol.uppercased() + "|" + category.rawValue
        if let (ts, items) = Self.cache[key], Date().timeIntervalSince(ts) < cacheTTL {
            self.articles = items
            self.isLoading = false
            return
        }
        
        isLoading = true
        let url = feedURL(for: symbol, category: category)
        Task { @MainActor in
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let items = CDVGoogleNewsRSSParser.parse(data: data)
                self.articles = items
                self.isLoading = false
                Self.cache[key] = (Date(), items)
            } catch {
                self.articles = []
                self.isLoading = false
            }
        }
    }

    func moreURL(for symbol: String, category: CoinNewsCategory) -> URL {
        let q = query(for: symbol, category: category).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? symbol
        return URL(string: "https://news.google.com/search?q=\(q)")!
    }

    private func feedURL(for symbol: String, category: CoinNewsCategory) -> URL {
        let q = query(for: symbol, category: category).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? symbol
        // Google News RSS endpoint
        let path = "https://news.google.com/rss/search?q=\(q)&hl=en-US&gl=US&ceid=US:en"
        return URL(string: path)!
    }

    private func query(for symbol: String, category: CoinNewsCategory) -> String {
        return "\(symbol) \(category.queryKeywords)"
    }
}

private enum CDVGoogleNewsRSSParser {
    static func parse(data: Data) -> [CDVNewsArticle] {
        let parser = _Parser()
        return parser.parse(data: data)
    }

    private final class _Parser: NSObject, XMLParserDelegate {
        private var items: [CDVNewsArticle] = []
        private var currentTitle: String = ""
        private var currentLink: String = ""
        private var currentPubDate: Date = Date()
        private var currentElement: String = ""
        private var currentSource: String = ""
        private var currentImageLink: String = ""

        func parse(data: Data) -> [CDVNewsArticle] {
            let xml = XMLParser(data: data)
            xml.delegate = self
            xml.parse()
            return items
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
            currentElement = elementName
            if elementName == "item" {
                currentTitle = ""; currentLink = ""; currentPubDate = Date()
                currentSource = ""; currentImageLink = ""
            }
            let name = elementName.lowercased()
            if name == "media:content" || name == "enclosure" || (qName?.lowercased() == "media:content") {
                if let url = attributeDict["url"], !url.isEmpty { currentImageLink = url }
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            switch currentElement {
            case "title": currentTitle += string
            case "link": currentLink += string
            case "pubDate":
                // accumulate then parse in endElement
                currentPubDate = parseDate(string) ?? currentPubDate
            case "source":
                currentSource += string
            default: break
            }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            if elementName == "item" {
                let title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                let link = currentLink.trimmingCharacters(in: .whitespacesAndNewlines)
                let src = currentSource.trimmingCharacters(in: .whitespacesAndNewlines)
                let img = URL(string: currentImageLink.trimmingCharacters(in: .whitespacesAndNewlines))
                let article = CDVNewsArticle(title: title, link: link, pubDate: currentPubDate, source: src.isEmpty ? nil : src, imageURL: (img?.scheme?.lowercased() == "https") ? img : nil)
                items.append(article)
            }
            currentElement = ""
        }

        private func parseDate(_ str: String) -> Date? {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
            return f.date(from: str.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

// New view: CoinNewsEmbed that wraps the Home news section UI with scoped view model
private struct CoinNewsEmbed: View {
    let symbol: String
    @ObservedObject private var vm = CryptoNewsFeedViewModel.shared
    @State private var lastSeenArticleID: String? = nil
    @State private var previousQuery: String? = nil

    var body: some View {
        PremiumNewsSection(viewModel: vm, lastSeenArticleID: $lastSeenArticleID)
            .onAppear {
                // Defer to avoid "Modifying state during view update"
                DispatchQueue.main.async {
                    // Save previous query and focus on this coin
                    previousQuery = vm.queryOverride
                    vm.queryOverride = "\(symbol) crypto"
                    vm.selectedSources = []
                    vm.loadAllNews(force: true)
                }
            }
            .onDisappear {
                // Restore previous query
                vm.queryOverride = previousQuery
            }
    }
}

#endif









