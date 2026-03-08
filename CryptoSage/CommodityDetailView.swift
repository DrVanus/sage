//
//  CommodityDetailView.swift
//  CryptoSage
//
//  Created by CryptoSage on 1/30/26.
//  Premium detail view for commodities with TradingView charts, live Coinbase prices,
//  technical indicators, and Yahoo Finance historical data.
//

import SwiftUI
import WebKit
import Combine
import Charts

// MARK: - Commodity Chart Type
enum CommodityChartType: String, CaseIterable {
    case cryptoSageAI = "CryptoSage AI"
    case tradingView  = "TradingView"
}

// MARK: - Commodity Info Tab
enum CommodityInfoTab: String, CaseIterable, Hashable {
    case overview = "Overview"
    case news     = "News"
    case analysis = "Analysis"
}

// MARK: - Commodity Trading Signal
struct CommodityTradingSignal {
    enum SignalType: String {
        case strongBuy = "STRONG BUY"
        case buy = "BUY"
        case hold = "HOLD"
        case sell = "SELL"
        case strongSell = "STRONG SELL"
        
        var color: Color {
            switch self {
            case .strongBuy, .buy: return .green
            case .hold: return .gray
            case .sell, .strongSell: return .red
            }
        }
        
        var icon: String {
            switch self {
            case .strongBuy, .buy: return "arrow.up.circle.fill"
            case .hold: return "minus.circle.fill"
            case .sell, .strongSell: return "arrow.down.circle.fill"
            }
        }
    }
    
    let signal: SignalType
    let confidence: String // "High", "Medium", "Low"
    let reason: String
    let sentimentScore: Double // 0-100 (0 = bearish, 100 = bullish)
}

// MARK: - CommodityDetailView

struct CommodityDetailView: View {
    let commodityInfo: CommodityInfo
    let holding: Holding?
    
    // Chart state
    @State private var selectedChartType: CommodityChartType = .cryptoSageAI
    @State private var selectedInterval: ChartInterval = .oneMonth
    @State private var indicators: Set<IndicatorType> = [.volume]
    @AppStorage("TV.Indicators.Selected") private var tvIndicatorsRaw: String = ""
    @State private var showIndicatorMenu: Bool = false
    @State private var showTimeframePopover: Bool = false
    @State private var timeframeButtonFrame: CGRect = .zero
    
    // Price state
    @State private var currentPrice: Double = 0
    @State private var change24h: Double = 0
    @State private var priceHighlight: Bool = false
    @State private var lastPriceUpdate: Date? = nil
    @State private var isLoadingPrice: Bool = true
    
    // Chart data state
    @State private var chartData: [CommodityChartPoint] = []
    @State private var isLoadingChart: Bool = true
    
    // Info tab state
    @State private var selectedInfoTab: CommodityInfoTab = .overview
    
    // Technical analysis
    @StateObject private var techVM = TechnicalsViewModel()
    
    // AI Trading Signal (unified TradingSignal model + Firebase AI)
    @State private var tradingSignal: TradingSignal? = nil
    @State private var isGeneratingSignal: Bool = false
    @State private var signalTask: Task<Void, Never>? = nil
    @State private var signalDebounceTask: Task<Void, Never>? = nil
    @State private var lastSignalIndicatorsSignature: String = ""
    @State private var lastSignalInputPrice: Double?
    @State private var lastSignalInputChange24h: Double?
    @State private var lastSignalGeneratedAt: Date = .distantPast
    
    // AI Insight (Firebase-backed, shared across users like coin detail)
    @State private var aiInsight: CoinAIInsight? = nil
    @State private var isLoadingInsight: Bool = false
    @State private var aiInsightError: String? = nil
    
    // Deep Dive / Why-is-moving sheets
    @State private var showDeepDive: Bool = false
    @State private var showWhySheet: Bool = false
    @State private var whyExplanation: String = ""
    @State private var isGeneratingWhy: Bool = false
    
    // News state
    @StateObject private var newsVM = CommodityNewsViewModel()
    @State private var selectedNewsCategory: CommodityNewsCategory = .top
    
    // Crosshair state (native chart)
    @State private var crosshairPrice: Double? = nil
    @State private var crosshairDate: Date? = nil
    @State private var showCrosshair: Bool = false
    
    // Environment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var portfolioVM: PortfolioViewModel
    
    // Shared price manager for consistent data across the app
    @ObservedObject private var priceManager = CommodityLivePriceManager.shared
    
    // Yahoo quote data for market data section
    @State private var yahooQuote: StockQuote? = nil
    
    // Cancellables for price updates
    @State private var priceRefreshTask: Task<Void, Never>? = nil
    @State private var chartRefreshTask: Task<Void, Never>? = nil
    
    private var isDark: Bool { colorScheme == .dark }
    
    // MARK: - Computed Properties
    
    private var tvSymbol: String {
        commodityInfo.tradingViewSymbol
    }
    
    private var tvAltSymbols: [String] {
        [commodityInfo.tradingViewSymbol] + commodityInfo.tradingViewAltSymbols
    }
    
    private var tvTheme: String {
        isDark ? "dark" : "light"
    }
    
    private var tvStudies: [String] {
        TVStudiesMapper.buildCurrentStudies()
    }
    
    private var displayedPrice: Double {
        // Priority: local fetch > shared manager > holding
        if currentPrice > 0 {
            return currentPrice
        }
        if let sharedPrice = priceManager.prices[commodityInfo.id], sharedPrice.price > 0 {
            return sharedPrice.price
        }
        return holding?.currentPrice ?? 0
    }
    
    private var displayedChange24h: Double {
        // Priority: local fetch > shared manager > 0
        if change24h != 0 {
            return change24h
        }
        if let sharedPrice = priceManager.prices[commodityInfo.id], let change = sharedPrice.change24h {
            return change
        }
        return 0
    }
    
    private var priceColor: Color {
        displayedChange24h >= 0 ? .green : .red
    }

    private var signalAssetKey: String {
        AITradingSignalService.commoditySignalCoinId(identifier: commodityInfo.id)
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
                    items: supportedIntervals,
                    selectedItem: selectedInterval,
                    titleForItem: { $0.rawValue },
                    onSelect: { interval in
                        selectedInterval = interval
                        loadChartDataThenTechnicals()
                    },
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
        .sheet(isPresented: $showDeepDive) {
            CommodityDeepDiveSheet(
                commodityName: commodityInfo.name,
                symbol: commodityInfo.displaySymbol,
                price: displayedPrice,
                change24h: displayedChange24h,
                sparkline: chartData.map(\.price),
                aiInsight: aiInsight
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showWhySheet) {
            CommodityWhyMovingSheet(
                commodityName: commodityInfo.name,
                symbol: commodityInfo.displaySymbol,
                change24h: displayedChange24h,
                explanation: whyExplanation,
                isLoading: isGeneratingWhy
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            startPriceUpdates()
            loadChartDataThenTechnicals()
            loadAIInsight()
            // Sync indicator state from shared @AppStorage
            let sharedSet = parseIndicatorSet(from: tvIndicatorsRaw)
            if !sharedSet.isEmpty { indicators = sharedSet }
            // Load initial news
            newsVM.fetch(commodityName: commodityInfo.name, category: selectedNewsCategory)
        }
        .task(id: commodityInfo.id.lowercased()) {
            tradingSignal = nil
            signalTask?.cancel()
            signalTask = Task { await generateTradingSignal() }
        }
        .onDisappear {
            stopPriceUpdates()
            signalTask?.cancel()
            signalDebounceTask?.cancel()
            signalTask = nil
            signalDebounceTask = nil
        }
        .onChange(of: selectedInterval) { _, _ in
            loadChartDataThenTechnicals()
        }
        // INDICATOR SYNC: Keep local indicators state in sync with shared @AppStorage
        .onChange(of: indicators) { _, new in
            DispatchQueue.main.async {
                let raw = serializeIndicatorSet(new)
                if tvIndicatorsRaw != raw { tvIndicatorsRaw = raw }
            }
        }
        .onChange(of: tvIndicatorsRaw) { _, raw in
            DispatchQueue.main.async {
                let set = parseIndicatorSet(from: raw)
                if !set.isEmpty && set != indicators { indicators = set }
            }
        }
        .onChange(of: displayedPrice) { _, _ in
            scheduleDebouncedSignalGenerationForMarketInputs()
        }
        .onChange(of: displayedChange24h) { _, _ in
            scheduleDebouncedSignalGenerationForMarketInputs()
        }
        .safeAreaInset(edge: .top) { navBar }
        .tint(.yellow)
        // NAVIGATION: Enable native iOS pop gesture + custom edge swipe
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
    }
    
    // Supported intervals for commodities (Yahoo Finance supports these)
    private var supportedIntervals: [ChartInterval] {
        [.oneDay, .oneWeek, .oneMonth, .threeMonth, .sixMonth, .oneYear, .threeYear, .all]
    }
    
    // MARK: - Navigation Bar
    
    private var navBar: some View {
        HStack(spacing: 12) {
            // Back button
            CSNavButton(
                icon: "chevron.left",
                action: { dismiss() }
            )
            
            // Commodity icon and name
            HStack(spacing: 10) {
                // Distinctive commodity icon
                CommodityIconView(commodityId: commodityInfo.id, size: 36)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(commodityInfo.name)
                        .font(.system(size: 16, weight: .bold))
                        // LIGHT MODE FIX: Adaptive text color
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    HStack(spacing: 4) {
                        Text(commodityInfo.displaySymbol)
                            .font(.system(size: 12, weight: .medium))
                            // LIGHT MODE FIX: Adaptive secondary text
                            .foregroundColor(DS.Adaptive.textSecondary)
                        
                        // Type badge - white text on colored bg is fine
                        Text(commodityInfo.type.rawValue.uppercased())
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            // LIGHT MODE FIX: Use adaptive badge colors
                            .background(adaptiveBadgeColor.opacity(isDark ? 0.8 : 0.85))
                            .clipShape(Capsule())
                    }
                }
            }
            
            Spacer()
            
            // Price display with gold gradient styling
            VStack(alignment: .trailing, spacing: 4) {
                if isLoadingPrice && currentPrice == 0 {
                    CommodityShimmerView()
                        .frame(width: 100, height: 24)
                } else {
                    // Price with gold gradient - LIGHT MODE FIX: Deeper amber in light mode
                    Text(formatPrice(displayedPrice))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(
                            LinearGradient(
                                colors: isDark
                                    ? [Color(red: 1.0, green: 0.85, blue: 0.4), Color(red: 0.9, green: 0.7, blue: 0.2)]
                                    : [Color(red: 0.72, green: 0.52, blue: 0.08), Color(red: 0.60, green: 0.42, blue: 0.04)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        // LIGHT MODE FIX: No yellow glow in light mode
                        .scaleEffect(priceHighlight ? 1.05 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: priceHighlight)
                }
                
                // Change percentage badge
                HStack(spacing: 3) {
                    Image(systemName: displayedChange24h >= 0 ? "arrow.up" : "arrow.down")
                        .font(.system(size: 9, weight: .bold))
                    Text(String(format: "%+.2f%%", displayedChange24h))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundColor(priceColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(priceColor.opacity(isDark ? 0.15 : 0.12))
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Rectangle()
                .fill(DS.Adaptive.background)
                .ignoresSafeArea()
        )
    }
    
    private var commodityTypeColor: Color {
        switch commodityInfo.type {
        case .preciousMetal: return .yellow
        case .industrialMetal: return .orange
        case .energy: return .blue
        case .agriculture: return .green
        case .livestock: return .brown
        }
    }
    
    // LIGHT MODE FIX: Darker badge colors for better contrast on light backgrounds
    private var adaptiveBadgeColor: Color {
        if isDark { return commodityTypeColor }
        switch commodityInfo.type {
        case .preciousMetal: return Color(red: 0.75, green: 0.60, blue: 0.08) // deep amber
        case .industrialMetal: return Color(red: 0.82, green: 0.50, blue: 0.12) // burnt orange
        case .energy: return Color(red: 0.15, green: 0.40, blue: 0.75) // deeper blue
        case .agriculture: return Color(red: 0.15, green: 0.55, blue: 0.25) // deeper green
        case .livestock: return Color(red: 0.50, green: 0.32, blue: 0.15) // deeper brown
        }
    }
    
    // MARK: - Main Content
    
    private var contentScrollView: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Portfolio position banner (if user holds this commodity)
                if let holding = holding, holding.quantity > 0 {
                    portfolioPositionBanner(holding)
                }
                
                // Chart with controls
                chartSection
                
                // "Why is it moving?" card for significant price changes (>= 3%)
                if abs(displayedChange24h) >= 3.0 {
                    whyIsMovingCard
                }
                
                // Info tabs (Overview/News/Analysis)
                infoTabsSection
                
                // AI Trading Signal section
                aiTradingSignalSection
                
                // Technicals (before stats, matching coin detail)
                technicalsSection
                
                // Key stats
                statsCardView
                
                // About section
                aboutSection
            }
            .padding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 20)
        }
        // PERFORMANCE FIX v21: UIKit scroll bridge for snappier deceleration + animation freeze
        .withUIKitScrollBridge()
    }
    
    // MARK: - Portfolio Position Banner
    
    private func portfolioPositionBanner(_ holding: Holding) -> some View {
        let value = holding.quantity * displayedPrice
        let costBasis = holding.costBasis
        let pnl = value - costBasis
        let pnlPercent = costBasis > 0 ? (pnl / costBasis) * 100 : 0
        
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your Position")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.Adaptive.textSecondary)
                
                Text("\(formatQuantity(holding.quantity)) \(commodityInfo.unit)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(DS.Adaptive.textPrimary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(formatCurrency(value))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                HStack(spacing: 4) {
                    Text(formatCurrency(pnl))
                    Text("(\(String(format: "%+.2f%%", pnlPercent)))")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(pnl >= 0 ? .green : .red)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
    }
    
    // MARK: - Chart Section
    
    private var chartSection: some View {
        VStack(spacing: 0) {
            // Chart content FIRST (like coin detail)
            if selectedChartType == .cryptoSageAI {
                nativeChartView
            } else {
                tradingViewChart
            }
            
            // Controls row BELOW the chart (matching coin detail)
            chartControlsRow
                .padding(.top, 4)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
        }
        .background(
            ZStack {
                // Premium glass background (matching coin detail)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
                
                // Subtle gradient overlay for depth
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isDark ? 0.03 : 0.1),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Grid overlay for premium look
                GeometryReader { geo in
                    Path { path in
                        let spacing: CGFloat = 20
                        for x in stride(from: 0, to: geo.size.width, by: spacing) {
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: geo.size.height))
                        }
                        for y in stride(from: 0, to: geo.size.height, by: spacing) {
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: geo.size.width, y: y))
                        }
                    }
                    .stroke(DS.Adaptive.textTertiary.opacity(0.03), lineWidth: 0.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            DS.Adaptive.stroke.opacity(0.6),
                            DS.Adaptive.stroke.opacity(0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
    
    // MARK: - Chart Controls Row (Matching Coin Detail)
    
    private var chartControlsRow: some View {
        // No ScrollView - fixed width, matching coin page layout
        HStack(spacing: 6) {
            // Chart source segmented toggle - expands to fill remaining width
            ChartSourceSegmentedToggle(
                selected: $selectedChartType,
                options: [
                    (.cryptoSageAI, "CryptoSage AI"),
                    (.tradingView, "TradingView")
                ]
            )
            
            // Timeframe dropdown button using shared component
            TimeframeDropdownButton(
                interval: selectedInterval.rawValue,
                isActive: showTimeframePopover,
                action: { showTimeframePopover = true }
            )
            .fixedSize(horizontal: true, vertical: false)
            .background(
                GeometryReader { geo in
                    Color.clear.onAppear {
                        timeframeButtonFrame = geo.frame(in: .global)
                    }
                    .onChange(of: showTimeframePopover) { _, _ in
                        timeframeButtonFrame = geo.frame(in: .global)
                    }
                }
            )
            
            // Indicators button using shared component
            IndicatorsButton(
                count: indicators.count,
                action: { showIndicatorMenu = true }
            )
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }
    
    private var nativeChartView: some View {
        Group {
            if isLoadingChart {
                VStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: DS.Adaptive.gold))
                    Text("Loading chart data...")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                .frame(height: 280)
            } else if chartData.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.line.downtrend.xyaxis")
                        .font(.system(size: 40))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    Text("Chart data unavailable")
                        .font(.subheadline)
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                .frame(height: 280)
            } else {
                CommodityNativeChartView(
                    chartData: chartData,
                    indicators: indicators,
                    priceColor: priceColor,
                    crosshairPrice: $crosshairPrice,
                    crosshairDate: $crosshairDate,
                    showCrosshair: $showCrosshair
                )
                .frame(height: 280)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 12)
    }
    
    private var tradingViewChart: some View {
        TradingViewChartWebView(
            symbol: tvSymbol,
            interval: selectedInterval.tvValue,
            theme: tvTheme,
            studies: tvStudies,
            altSymbols: tvAltSymbols,
            interactive: true
        )
        .frame(height: 400)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 8)
        .padding(.bottom, 12)
    }
    
    // MARK: - Info Tabs Section
    
    private var infoTabsSection: some View {
        VStack(spacing: 0) {
            // Tab selector
            HStack(spacing: 0) {
                ForEach(CommodityInfoTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedInfoTab = tab
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Text(tab.rawValue)
                                .font(.system(size: 14, weight: selectedInfoTab == tab ? .semibold : .medium))
                                .foregroundColor(selectedInfoTab == tab ? DS.Adaptive.textPrimary : DS.Adaptive.textSecondary)
                            
                            Rectangle()
                                .fill(selectedInfoTab == tab ? DS.Adaptive.gold : Color.clear)
                                .frame(height: 2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            
            // Tab content
            Group {
                switch selectedInfoTab {
                case .overview:
                    overviewTabContent
                case .news:
                    newsTabContent
                case .analysis:
                    analysisTabContent
                }
            }
            .padding(16)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
    }
    
    private var overviewTabContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            // AI Insight Preview Card (matching coin detail)
            aiInsightPreviewCard
            
            // Key info grid (About section moved to bottom of page)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                infoGridItem(title: "Type", value: commodityInfo.type.rawValue)
                infoGridItem(title: "Unit", value: commodityInfo.unit)
                infoGridItem(title: "Exchange", value: "COMEX/NYMEX")
                infoGridItem(title: "Symbol", value: commodityInfo.yahooSymbol)
            }
        }
    }
    
    private var aiInsightPreviewCard: some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            showDeepDive = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                // Header with sparkle icon
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DS.Adaptive.gold)
                    
                    if isLoadingInsight && aiInsight == nil {
                        HStack(spacing: 4) {
                            Text("Analyzing")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(DS.Adaptive.textSecondary)
                            ProgressView()
                                .scaleEffect(0.6)
                        }
                    } else {
                        Text("AI Insight")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                    
                    Spacer()
                    
                    if let insight = aiInsight {
                        Text(insight.ageText)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                }
                
                // Insight text
                if let insight = aiInsight {
                    Text(insight.insightText)
                        .font(.system(size: 13))
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .lineSpacing(3)
                        .lineLimit(3)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(DS.Adaptive.textTertiary.opacity(0.2))
                            .frame(height: 12)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(DS.Adaptive.textTertiary.opacity(0.15))
                            .frame(width: 200, height: 12)
                    }
                    .shimmer()
                }
                
                // Tap for full analysis
                HStack {
                    Text("Tap for full analysis")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.Adaptive.gold)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(DS.Adaptive.gold)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DS.Adaptive.gold.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DS.Adaptive.gold.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func timeAgoString(from date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 {
            return "just now"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "\(minutes)m ago"
        } else {
            let hours = seconds / 3600
            return "\(hours)h ago"
        }
    }
    
    private func infoGridItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.Adaptive.textTertiary)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(DS.Adaptive.cardBackground.opacity(0.5))
        )
    }
    
    private var commodityDescription: String {
        switch commodityInfo.id {
        case "gold":
            return "Gold is a precious metal that has been used as a store of value and medium of exchange for thousands of years. It's often seen as a hedge against inflation and economic uncertainty."
        case "silver":
            return "Silver is both a precious metal and an industrial metal, with applications in electronics, solar panels, and jewelry. It often moves in correlation with gold but with higher volatility."
        case "platinum":
            return "Platinum is a rare precious metal primarily used in catalytic converters for vehicles, jewelry, and various industrial applications. It's rarer than gold."
        case "palladium":
            return "Palladium is a precious metal crucial for catalytic converters in gasoline-powered vehicles. It has seen significant price increases due to supply constraints."
        case "copper":
            return "Copper is an essential industrial metal used in construction, electronics, and renewable energy infrastructure. It's often called 'Dr. Copper' as its price can indicate economic health."
        case "aluminum":
            return "Aluminum is a lightweight, corrosion-resistant metal used in transportation, construction, and packaging. It's the most widely used non-ferrous metal."
        case "crude_oil":
            return "Crude Oil (WTI) is the benchmark for US oil prices. It's essential for transportation, heating, and manufacturing, making it one of the most traded commodities globally."
        case "brent_oil":
            return "Brent Crude is the international benchmark for oil prices, sourced from the North Sea. It's used to price approximately two-thirds of the world's oil."
        case "natural_gas":
            return "Natural Gas is a clean-burning fossil fuel used for heating, electricity generation, and industrial processes. Prices can be volatile due to weather and storage levels."
        case "heating_oil":
            return "Heating Oil is a refined petroleum product used primarily for heating homes and buildings. Prices are influenced by crude oil costs and seasonal demand."
        case "gasoline":
            return "RBOB Gasoline is the benchmark for US gasoline prices. Prices are affected by crude oil costs, refining capacity, and seasonal driving demand."
        case "corn":
            return "Corn is one of the world's most important crops, used for food, animal feed, and ethanol production. Prices are influenced by weather, exports, and energy policies."
        case "soybeans":
            return "Soybeans are a major agricultural commodity used for animal feed, cooking oil, and biodiesel. China is the largest importer of US soybeans."
        case "wheat":
            return "Wheat is a staple grain used for bread, pasta, and animal feed worldwide. Prices are affected by weather conditions and global supply dynamics."
        case "coffee":
            return "Coffee is the world's second-most traded commodity after crude oil. Prices are influenced by weather in Brazil and other producing countries."
        case "cocoa":
            return "Cocoa is the primary ingredient in chocolate production. Most cocoa is grown in West Africa, and prices are sensitive to weather and political conditions."
        case "cotton":
            return "Cotton is a natural fiber used in textiles and clothing. Prices are influenced by weather, global demand, and competition from synthetic fibers."
        case "sugar":
            return "Sugar is produced from sugarcane and sugar beets. Brazil is the world's largest producer and exporter, with prices tied to ethanol demand."
        case "live_cattle":
            return "Live Cattle futures represent beef cattle ready for slaughter. Prices are influenced by feed costs, consumer demand, and herd sizes."
        case "lean_hogs":
            return "Lean Hogs futures represent pork production. Prices are affected by feed costs, disease outbreaks, and export demand."
        default:
            return "A globally traded commodity used in various industries and investment portfolios."
        }
    }
    
    private var newsTabContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Category chips – matching CoinDetailView's NewsCategoryChips styling
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CommodityNewsCategory.allCases, id: \.self) { cat in
                        commodityNewsCategoryButton(for: cat)
                    }
                }
                .padding(.horizontal, 2)
            }
            
            if newsVM.isLoading {
                // Shimmer loading cards matching ArticleRow dimensions
                ForEach(0..<3, id: \.self) { _ in
                    HStack(alignment: .center, spacing: 14) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            // LIGHT MODE FIX: Adaptive shimmer placeholder colors
                            .fill(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                            .frame(width: 120, height: 85)
                        VStack(alignment: .leading, spacing: 8) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                                .frame(height: 14)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                                .frame(width: 180, height: 14)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                                .frame(width: 100, height: 10)
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.03)))
                    .shimmer()
                }
            } else if newsVM.articles.isEmpty {
                VStack(spacing: 10) {
                    Text("No headlines right now.")
                        .font(.footnote)
                        // LIGHT MODE FIX: Adaptive text
                        .foregroundColor(DS.Adaptive.textSecondary)
                    // Quick links to Google News
                    HStack(spacing: 12) {
                        Link(destination: URL(string: "https://news.google.com/search?q=\(commodityInfo.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "commodity")+commodity") ?? URL(string: "https://news.google.com")!) {
                            HStack(spacing: 4) {
                                Image(systemName: "safari")
                                Text("Google News")
                            }
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(DS.Adaptive.gold)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                // ArticleRow design matching CoinDetailView
                VStack(spacing: 8) {
                    ForEach(newsVM.articles.prefix(6)) { article in
                        Button {
                            if let url = URL(string: article.link) {
                                #if os(iOS)
                                UIApplication.shared.open(url)
                                #endif
                            }
                        } label: {
                            HStack(alignment: .center, spacing: 14) {
                                // Thumbnail
                                CachingAsyncImage(url: article.imageURL, referer: URL(string: article.link))
                                    .frame(width: 120, height: 85)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            // LIGHT MODE FIX: Adaptive stroke
                                            .stroke(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
                                    )
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(article.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(3)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .layoutPriority(1)
                                    
                                    HStack(spacing: 8) {
                                        if let src = article.source, !src.isEmpty {
                                            SourcePill(text: src)
                                        }
                                        Text(article.relativeTime)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(12)
                            // LIGHT MODE FIX: Adaptive card backgrounds
                            .background(RoundedRectangle(cornerRadius: 10).fill(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.03)))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 0.8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // "More on Google News" link – matching coin detail style
                HStack {
                    Spacer()
                    if let url = newsVM.moreURL(for: commodityInfo.name, category: selectedNewsCategory) {
                        Link(destination: url) {
                            HStack(spacing: 6) {
                                Image(systemName: "safari")
                                Text("More on Google News")
                            }
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(DS.Adaptive.gold)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }
    
    private func commodityNewsCategoryButton(for cat: CommodityNewsCategory) -> some View {
        let isSelected = selectedNewsCategory == cat
        let fillColor: Color = isDark
            ? (isSelected ? Color.white.opacity(0.16) : Color.white.opacity(0.06))
            : (isSelected ? Color.black.opacity(0.08) : Color.black.opacity(0.03))
        let strokeColor: Color = isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
        let textColor: Color = isDark ? .white : DS.Adaptive.textPrimary
        
        return Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            withAnimation(.easeInOut(duration: 0.18)) { selectedNewsCategory = cat }
            newsVM.fetch(commodityName: commodityInfo.name, category: cat)
        } label: {
            Text(cat.rawValue)
                .font(.caption.weight(.semibold))
                .foregroundColor(textColor)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(fillColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(strokeColor, lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
    }
    
    private var analysisTabContent: some View {
        let summary = techVM.summary
        
        return VStack(alignment: .leading, spacing: 14) {
            // Quick verdict header
            HStack(spacing: 8) {
                Circle()
                    .fill(summary.verdict.color)
                    .frame(width: 10, height: 10)
                
                Text(summary.verdict.rawValue)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(summary.verdict.color)
                
                Spacer()
                
                Text("\(Int(summary.score01 * 100))%")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            
            // Moving Averages vs Oscillators breakdown
            VStack(spacing: 10) {
                // Moving Averages
                analysisBreakdownRow(
                    title: "Moving Averages",
                    buy: summary.maBuy,
                    neutral: summary.maNeutral,
                    sell: summary.maSell
                )
                
                Divider()
                    .background(DS.Adaptive.divider)
                
                // Oscillators
                analysisBreakdownRow(
                    title: "Oscillators",
                    buy: summary.oscBuy,
                    neutral: summary.oscNeutral,
                    sell: summary.oscSell
                )
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DS.Adaptive.cardBackground.opacity(0.5))
            )
            
            // View more link
            NavigationLink {
                TechnicalsDetailNativeView(
                    symbol: commodityInfo.displaySymbol,
                    tvSymbol: commodityInfo.tradingViewSymbol,
                    tvTheme: tvTheme,
                    currentPrice: displayedPrice
                )
            } label: {
                HStack {
                    Text("View all indicators")
                        .font(.system(size: 13, weight: .medium))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(DS.Adaptive.gold)
            }
        }
    }
    
    private func analysisBreakdownRow(title: String, buy: Int, neutral: Int, sell: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.Adaptive.textSecondary)
            
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("\(buy) Buy")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.green)
                }
                
                HStack(spacing: 4) {
                    Circle().fill(Color.gray).frame(width: 6, height: 6)
                    Text("\(neutral) Neutral")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.gray)
                }
                
                HStack(spacing: 4) {
                    Circle().fill(Color.red).frame(width: 6, height: 6)
                    Text("\(sell) Sell")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.red)
                }
                
                Spacer()
            }
        }
    }
    
    // MARK: - Stats Card View
    
    /// Get the best available price data from either local fetch or shared manager
    private var livePriceData: CommodityPriceData? {
        priceManager.prices[commodityInfo.id]
    }
    
    /// Determine the data source for display
    private var dataSourceLabel: String {
        if let data = livePriceData {
            switch data.source {
            case .yahooFinance: return "Yahoo"
            case .cached: return "Cache"
            case .fallback: return "Fallback"
            }
        }
        return "Yahoo"
    }
    
    /// Get the best available price
    private var bestPrice: Double {
        if displayedPrice > 0 { return displayedPrice }
        return livePriceData?.price ?? 0
    }
    
    /// Get the best available change
    private var bestChange: Double {
        if displayedChange24h != 0 { return displayedChange24h }
        return livePriceData?.change24h ?? 0
    }
    
    /// Check if we have live data
    private var hasLiveData: Bool {
        bestPrice > 0
    }
    
    /// Check if technicals data is fresh (within last 60 seconds)
    private var isTechFresh: Bool {
        if let d = techVM.lastUpdated {
            return Date().timeIntervalSince(d) < 60
        }
        return false
    }
    
    private var statsCardView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                GoldHeaderGlyph(systemName: "chart.bar.doc.horizontal")
                
                Text("Market Data")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Spacer()
                
                // Source badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(dataSourceLabel == "Coinbase" ? Color.green : Color.blue)
                        .frame(width: 5, height: 5)
                    Text(dataSourceLabel)
                        .font(.system(size: 10, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill((dataSourceLabel == "Coinbase" ? Color.green : Color.blue).opacity(0.12))
                )
                .foregroundColor(dataSourceLabel == "Coinbase" ? Color.green : Color.blue)
            }
            
            // Stats grid (2 columns for better layout)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                // Price
                statGridItem(
                    title: "Price",
                    value: hasLiveData ? formatPrice(bestPrice) : nil,
                    isLoading: !hasLiveData && priceManager.isLoading
                )
                
                // 24h Change
                statGridItem(
                    title: "24h Change",
                    value: hasLiveData ? String(format: "%+.2f%%", bestChange) : nil,
                    valueColor: bestChange >= 0 ? .green : .red,
                    isLoading: !hasLiveData && priceManager.isLoading
                )
                
                // Previous Close (from Yahoo quote or shared manager)
                if let prevClose = yahooQuote?.regularMarketPreviousClose ?? livePriceData?.previousClose, prevClose > 0 {
                    statGridItem(title: "Prev Close", value: formatPrice(prevClose))
                } else {
                    statGridItem(title: "Prev Close", value: nil, isLoading: yahooQuote == nil)
                }
                
                // Day Open (from Yahoo quote)
                if let open = yahooQuote?.regularMarketOpen, open > 0 {
                    statGridItem(title: "Open", value: formatPrice(open))
                } else {
                    statGridItem(title: "Unit", value: "per \(commodityInfo.unit)")
                }
                
                // Day High (from Yahoo quote)
                if let high = yahooQuote?.regularMarketDayHigh, high > 0 {
                    statGridItem(title: "Day High", value: formatPrice(high))
                }
                
                // Day Low (from Yahoo quote)
                if let low = yahooQuote?.regularMarketDayLow, low > 0 {
                    statGridItem(title: "Day Low", value: formatPrice(low))
                }
                
                // 52-week range (from Yahoo quote)
                if let high52 = yahooQuote?.fiftyTwoWeekHigh, high52 > 0 {
                    statGridItem(title: "52W High", value: formatPrice(high52))
                }
                if let low52 = yahooQuote?.fiftyTwoWeekLow, low52 > 0 {
                    statGridItem(title: "52W Low", value: formatPrice(low52))
                }
                
                // Volume (from Yahoo quote)
                if let vol = yahooQuote?.regularMarketVolume, vol > 0 {
                    statGridItem(title: "Volume", value: formatVolume(Double(vol)))
                }
                
                // Last Update
                if let lastUpdate = livePriceData?.lastUpdated ?? lastPriceUpdate {
                    statGridItem(title: "Updated", value: timeAgoString(from: lastUpdate))
                } else {
                    statGridItem(title: "Exchange", value: "Futures")
                }
            }
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
    
    private func statGridItem(title: String, value: String?, valueColor: Color? = nil, isLoading: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.Adaptive.textTertiary)
            
            if isLoading {
                RoundedRectangle(cornerRadius: 3)
                    .fill(DS.Adaptive.textTertiary.opacity(0.2))
                    .frame(width: 60, height: 16)
                    .shimmer()
            } else if let value = value {
                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(valueColor ?? DS.Adaptive.textPrimary)
                    .monospacedDigit()
            } else {
                Text("--")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
        )
    }
    
    // MARK: - Technicals Section
    
    private var technicalsSection: some View {
        let summary = techVM.summary
        let w = UIScreen.main.bounds.width
        let onSelectSource: (TechnicalsViewModel.TechnicalsSourcePreference) -> Void = { pref in
            techVM.setPreferredSource(pref)
            techVM.refresh(
                symbol: commodityInfo.yahooSymbol,
                interval: selectedInterval,
                currentPrice: displayedPrice,
                sparkline: chartData.map { $0.price },
                forceBypassCache: true
            )
        }
        
        return VStack(alignment: .leading, spacing: 7) {
            // Header row (matching coin detail)
            HStack(spacing: 6) {
                GoldHeaderGlyph(systemName: "waveform.path.ecg")
                
                Text("Technicals")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                // Loading/fresh indicator
                if techVM.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(DS.Adaptive.gold)
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
                
                // More details link
                NavigationLink {
                    TechnicalsDetailNativeView(
                        symbol: commodityInfo.displaySymbol,
                        tvSymbol: commodityInfo.tradingViewSymbol,
                        tvTheme: tvTheme,
                        currentPrice: displayedPrice
                    )
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
            
            // Gauge with proper sizing (matching coin detail)
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
            .padding(.bottom, 2)
            
            // Summary + source menu as a cohesive block
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    commodityTechCountPill(title: "Sell", value: summary.sellCount, color: .red)
                    commodityTechCountPill(title: "Neutral", value: summary.neutralCount, color: .yellow)
                    commodityTechCountPill(title: "Buy", value: summary.buyCount, color: .green)
                    Spacer(minLength: 0)
                    TechnicalsSourceMenu(
                        sourceLabel: techVM.sourceLabel,
                        preferred: techVM.preferredSource,
                        requestedSource: techVM.requestedSource,
                        isSwitchingSource: techVM.isSourceSwitchInFlight,
                        onSelect: onSelectSource
                    )
                }
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        commodityTechCountPill(title: "Sell", value: summary.sellCount, color: .red)
                        commodityTechCountPill(title: "Neutral", value: summary.neutralCount, color: .yellow)
                        commodityTechCountPill(title: "Buy", value: summary.buyCount, color: .green)
                    }
                    HStack {
                        Spacer(minLength: 0)
                        TechnicalsSourceMenu(
                            sourceLabel: techVM.sourceLabel,
                            preferred: techVM.preferredSource,
                            requestedSource: techVM.requestedSource,
                            isSwitchingSource: techVM.isSourceSwitchInFlight,
                            onSelect: onSelectSource
                        )
                    }
                }
            }
            .padding(.top, 4)
            .animation(.easeInOut(duration: 0.18), value: techVM.isSourceSwitchInFlight)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            ZStack {
                // Base gradient background
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
                .stroke(DS.Adaptive.stroke.opacity(0.8), lineWidth: 1)
        )
    }
    
    private func commodityTechCountPill(title: String, value: Int, color: Color) -> some View {
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
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DS.Adaptive.overlay(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DS.Adaptive.stroke.opacity(0.8), lineWidth: 1)
        )
    }
    
    // MARK: - About Section
    
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                GoldHeaderGlyph(systemName: "info.circle")
                
                Text("About \(commodityInfo.name)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Spacer()
            }
            
            Text(commodityDescription)
                .font(.system(size: 14))
                .foregroundColor(DS.Adaptive.textSecondary)
                .lineSpacing(4)
            
            // External links
            HStack(spacing: 12) {
                linkButton(title: "TradingView", icon: "chart.xyaxis.line", url: "https://www.tradingview.com/symbols/\(commodityInfo.tradingViewSymbol.replacingOccurrences(of: ":", with: "-"))/")
                linkButton(title: "Yahoo Finance", icon: "globe", url: "https://finance.yahoo.com/quote/\(commodityInfo.yahooSymbol)")
            }
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
    
    private func linkButton(title: String, icon: String, url: String) -> some View {
        Button {
            if let url = URL(string: url) {
                #if os(iOS)
                UIApplication.shared.open(url)
                #endif
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(DS.Adaptive.gold)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(DS.Adaptive.gold.opacity(0.15))
            )
        }
    }
    
    // MARK: - Data Loading
    
    private func startPriceUpdates() {
        // Ensure this commodity is tracked by the shared price manager
        priceManager.startPolling(for: Set([commodityInfo.id]))
        
        // Immediate fetch for this specific commodity
        Task {
            await fetchPrice()
        }
        
        // Schedule periodic updates (every 30 seconds)
        priceRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                if Task.isCancelled { break }
                await fetchPrice()
            }
        }
    }
    
    private func stopPriceUpdates() {
        priceRefreshTask?.cancel()
        priceRefreshTask = nil
        chartRefreshTask?.cancel()
        chartRefreshTask = nil
    }
    
    private func fetchPrice() async {
        isLoadingPrice = currentPrice == 0
        
        var coinbasePriceUsed = false
        
        // Try Coinbase first for precious metals (faster live prices)
        if let coinbaseSymbol = commodityInfo.coinbaseSymbol {
            if let price = await CoinbaseService.shared.fetchSpotPrice(coin: coinbaseSymbol) {
                await MainActor.run {
                    let oldPrice = currentPrice
                    currentPrice = price
                    lastPriceUpdate = Date()
                    isLoadingPrice = false
                    
                    // Animate price change
                    if oldPrice > 0 && abs(price - oldPrice) / oldPrice > 0.001 {
                        withAnimation(.easeInOut(duration: 0.15)) { priceHighlight = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            withAnimation(.easeInOut(duration: 0.2)) { priceHighlight = false }
                        }
                    }
                }
                
                // Fetch 24h stats from Coinbase
                if let stats = await CoinbaseService.shared.fetch24hStats(coin: coinbaseSymbol) {
                    await MainActor.run {
                        if stats.openPrice > 0 {
                            change24h = ((price - stats.openPrice) / stats.openPrice) * 100
                        }
                    }
                }
                coinbasePriceUsed = true
            }
        }
        
        // Always fetch Yahoo Finance quote for market data (open, high, low, prevClose, volume)
        // Even when Coinbase provides the live price, Yahoo has richer data for the stats card
        let yahooSymbol = commodityInfo.yahooSymbol
        if let quote = await StockPriceService.shared.fetchQuote(ticker: yahooSymbol) {
            await MainActor.run {
                yahooQuote = quote
                
                // If Coinbase didn't provide price, use Yahoo
                if !coinbasePriceUsed {
                    let calculatedChange: Double = {
                        if let apiChange = quote.regularMarketChangePercent {
                            return apiChange
                        }
                        if let prevClose = quote.regularMarketPreviousClose, prevClose > 0 {
                            return ((quote.regularMarketPrice - prevClose) / prevClose) * 100
                        }
                        return 0
                    }()
                    
                    currentPrice = quote.regularMarketPrice
                    change24h = calculatedChange
                    lastPriceUpdate = Date()
                    isLoadingPrice = false
                }
            }
        }
    }
    
    // MARK: - Indicator Sync Helpers
    
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
    
    // MARK: - "Why Is It Moving" AI Generation
    
    private func generateWhyExplanation() {
        guard !isGeneratingWhy else { return }
        isGeneratingWhy = true
        showWhySheet = true
        
        Task {
            let cleanSymbol = commodityInfo.displaySymbol
                .replacingOccurrences(of: "=", with: "")
                .uppercased()
            
            do {
                let response = try await FirebaseService.shared.getCoinInsight(
                    coinId: "whymove-commodity-\(commodityInfo.id.lowercased())",
                    coinName: "\(commodityInfo.name) (Commodity)",
                    symbol: cleanSymbol,
                    price: displayedPrice,
                    change24h: displayedChange24h,
                    change7d: nil,
                    marketCap: nil,
                    volume24h: nil,
                    assetType: "commodity"
                )
                await MainActor.run {
                    whyExplanation = response.content
                    isGeneratingWhy = false
                }
            } catch {
                await MainActor.run {
                    whyExplanation = "\(commodityInfo.name) is \(displayedChange24h > 0 ? "up" : "down") \(String(format: "%.1f%%", abs(displayedChange24h))) today. This significant move may be driven by supply/demand shifts, geopolitical events, or broader market sentiment."
                    isGeneratingWhy = false
                }
            }
        }
    }
    
    /// Loads chart data first, then triggers technicals + signal generation with the loaded data
    private func loadChartDataThenTechnicals() {
        chartRefreshTask?.cancel()
        chartRefreshTask = Task {
            await fetchChartData()
            // Now that chartData is populated, refresh technicals with actual sparkline data
            await MainActor.run {
                refreshTechnicals()
            }
            await generateTradingSignal()
        }
    }
    
    private func fetchChartData() async {
        await MainActor.run { isLoadingChart = true }

        let yahooSymbol = commodityInfo.yahooSymbol
        let range = selectedInterval.toStockChartRange()

        var historicalData = await StockPriceService.shared.fetchHistoricalData(ticker: yahooSymbol, range: range)

        // Fallback: if chart data is empty (common for futures outside trading hours
        // or for intraday intervals), try daily data instead
        if historicalData.isEmpty {
            let isIntraday: Bool = {
                switch selectedInterval {
                case .oneMin, .fiveMin, .fifteenMin, .thirtyMin, .oneHour, .fourHour, .oneDay:
                    return true
                default:
                    return false
                }
            }()
            if isIntraday {
                #if DEBUG
                print("[CommodityDetail] Intraday chart empty for \(yahooSymbol), falling back to 1mo daily data")
                #endif
                historicalData = await StockPriceService.shared.fetchHistoricalData(
                    ticker: yahooSymbol, range: .oneMonth)
            }
        }

        await MainActor.run {
            chartData = historicalData.map { point in
                CommodityChartPoint(timestamp: point.date, price: point.close, volume: Double(point.volume))
            }
            isLoadingChart = false
        }
    }
    
    private func refreshTechnicals() {
        // CRITICAL FIX: Use actual chart data prices as sparkline for on-device technicals
        // The Firebase backend doesn't have commodity futures data (GC=F, SI=F, etc.)
        // and Coinbase/Binance don't trade these symbols, so we need the Yahoo Finance
        // historical data as the sparkline for the TechnicalsEngine to compute indicators.
        let closes = chartData.map { $0.price }
        guard !closes.isEmpty else {
            #if DEBUG
            print("[CommodityDetail] Skipping technicals refresh - no chart data yet")
            #endif
            return
        }
        #if DEBUG
        print("[CommodityDetail] Refreshing technicals with \(closes.count) price points, price: \(displayedPrice)")
        #endif
        techVM.refresh(
            symbol: commodityInfo.yahooSymbol,
            interval: selectedInterval,
            currentPrice: displayedPrice > 0 ? displayedPrice : (closes.last ?? 0),
            sparkline: closes
        )
    }
    
    // MARK: - AI Trading Signal Generation
    
    @MainActor
    private func generateTradingSignal() async {
        guard !isGeneratingSignal else { return }
        isGeneratingSignal = true
        lastSignalInputPrice = displayedPrice
        lastSignalInputChange24h = displayedChange24h
        lastSignalGeneratedAt = Date()
        
        // Use AITradingSignalService: Firebase/DeepSeek first, local fallback
        let cleanSymbol = commodityInfo.displaySymbol
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "F", with: "")
            .uppercased()
        
        let signal = await AITradingSignalService.shared.fetchSignal(
            coinId: signalAssetKey,
            symbol: cleanSymbol,
            price: displayedPrice,
            change24h: displayedChange24h,
            change7d: nil,
            sparkline: chartData.map(\.price),
            techVM: techVM,
            fearGreedValue: nil // Crypto-specific - not applicable to commodities
        )
        tradingSignal = signal
        
        isGeneratingSignal = false
    }
    
    /// Load AI insight via Firebase (shared across all users, cached server-side for 2 hours)
    /// Uses the same CoinAIInsightService as the coin detail page for consistency
    private func loadAIInsight() {
        // Check for any cached insight first (even stale) to prevent flash
        let cacheKey = "COMMODITY_\(commodityInfo.id.uppercased())"
        if let cached = CoinAIInsightService.shared.getAnyCachedInsight(for: cacheKey) {
            aiInsight = cached
            // If it's still fresh, don't re-fetch
            if cached.isFresh { return }
        }
        
        guard !isLoadingInsight else { return }
        // Only show loading if we don't have a cached insight to display
        if aiInsight == nil {
            isLoadingInsight = true
        }
        aiInsightError = nil
        
        Task { @MainActor in
            // Wait briefly for price data to arrive
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            let price = displayedPrice
            let change = displayedChange24h
            _ = chartData.map { $0.price }
            
            // Create a fallback insight for immediate display
            let fallbackText = generateLocalCommodityInsight()
            let fallbackInsight = CoinAIInsight(
                symbol: cacheKey,
                insightText: fallbackText,
                price: price,
                change24h: change
            )
            
            // Try Firebase-backed AI insight (shared across all users)
            // Uses getCoinInsight with commodity-specific ID so it caches as "coin_commodity_gold" etc.
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 8_000_000_000) // 8 second timeout
                return true
            }
            
            let insightTask = Task { () -> CoinAIInsight? in
                do {
                    // Call Firebase via the shared insight service
                    // The coinId "commodity-gold" creates a unique cache key in Firestore
                    let response = try await FirebaseService.shared.getCoinInsight(
                        coinId: "commodity-\(commodityInfo.id)",
                        coinName: "\(commodityInfo.name) (Commodity)",
                        symbol: commodityInfo.displaySymbol.replacingOccurrences(of: "=", with: ""),
                        price: price,
                        change24h: change,
                        change7d: nil,
                        marketCap: nil,
                        volume24h: nil,
                        assetType: "commodity"
                    )
                    
                    let insight = CoinAIInsight(
                        symbol: cacheKey,
                        insightText: response.content,
                        price: price,
                        change24h: change
                    )
                    
                    // Cache locally using the CoinAIInsightService pattern
                    CoinAIInsightService.shared.cacheInsight(insight, for: cacheKey)
                    
                    return insight
                } catch {
                    aiInsightError = error.localizedDescription
                    return nil
                }
            }
            
            // Race between timeout and actual generation
            let result = await withTaskGroup(of: CoinAIInsight?.self) { group -> CoinAIInsight? in
                group.addTask { await insightTask.value }
                group.addTask {
                    _ = await timeoutTask.value
                    return nil
                }
                for await result in group {
                    if result != nil {
                        group.cancelAll()
                        return result
                    }
                }
                return nil
            }
            
            // Use Firebase result or fallback
            if let insight = result {
                aiInsight = insight
            } else if aiInsight == nil {
                // Only use fallback if we don't already have a cached insight showing
                aiInsight = fallbackInsight
            }
            isLoadingInsight = false
        }
    }
    
    /// Generate a local fallback insight when Firebase is unavailable
    private func generateLocalCommodityInsight() -> String {
        let change = displayedChange24h
        let price = displayedPrice
        let magnitude = abs(change)
        
        var parts: [String] = []
        
        if magnitude < 0.5 {
            parts.append("\(commodityInfo.name) is trading flat at \(formatPrice(price)) with minimal movement today")
        } else if magnitude < 2 {
            parts.append("\(commodityInfo.name) is \(change >= 0 ? "up" : "down") \(String(format: "%.2f%%", change)) to \(formatPrice(price)), showing moderate activity")
        } else if magnitude < 5 {
            parts.append("\(commodityInfo.name) has moved \(String(format: "%+.2f%%", change)) to \(formatPrice(price)), reflecting significant market interest")
        } else {
            parts.append("\(commodityInfo.name) is seeing high volatility with a \(String(format: "%+.2f%%", change)) move to \(formatPrice(price))")
        }
        
        let desc = commodityDescription.components(separatedBy: ".").first ?? ""
        if !desc.isEmpty {
            parts.append(desc)
        }
        
        return parts.joined(separator: ". ") + "."
    }
    
    // MARK: - Why Is Moving Card
    
    private var whyIsMovingCard: some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            generateWhyExplanation()
        } label: {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    Circle()
                        .fill(priceColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: displayedChange24h >= 0 ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(priceColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Why is \(commodityInfo.displaySymbol) \(String(format: "%+.1f%%", displayedChange24h))?")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
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
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(priceColor.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - AI Trading Signal Section
    
    @ViewBuilder
    private var aiTradingSignalSection: some View {
        AITradingSignalCard(
            symbol: commodityInfo.displaySymbol
                .replacingOccurrences(of: "=", with: "")
                .replacingOccurrences(of: "F", with: "")
                .uppercased(),
            price: displayedPrice,
            sparkline: chartData.map(\.price),
            change24h: displayedChange24h,
            signal: tradingSignal,
            isLoading: isGeneratingSignal
        )
        .onChange(of: techVM.summary.indicators) { _, _ in
            scheduleDebouncedSignalGenerationForIndicators()
        }
    }

    private func indicatorsSignature(_ indicators: [IndicatorSignal]) -> String {
        indicators
            .map { "\($0.label)|\(String(describing: $0.signal))|\($0.valueText ?? "")" }
            .joined(separator: "||")
    }

    private func scheduleDebouncedSignalGenerationForIndicators() {
        let signature = indicatorsSignature(techVM.summary.indicators)
        guard signature != lastSignalIndicatorsSignature else { return }
        lastSignalIndicatorsSignature = signature
        scheduleSignalGenerationDebounced(delayNanoseconds: 350_000_000)
    }

    private func scheduleDebouncedSignalGenerationForMarketInputs() {
        guard shouldRegenerateSignalForMarketInputs() else { return }
        scheduleSignalGenerationDebounced(delayNanoseconds: 450_000_000)
    }

    private func shouldRegenerateSignalForMarketInputs() -> Bool {
        let now = Date()
        guard now.timeIntervalSince(lastSignalGeneratedAt) >= 90 else { return false }

        guard let lastPrice = lastSignalInputPrice,
              let lastChange24h = lastSignalInputChange24h else {
            return tradingSignal != nil
        }

        guard lastPrice > 0 else { return true }
        let priceDeltaRatio = abs(displayedPrice - lastPrice) / lastPrice
        let changeDelta = abs(displayedChange24h - lastChange24h)
        return priceDeltaRatio >= 0.0025 || changeDelta >= 0.35
    }

    private func scheduleSignalGenerationDebounced(delayNanoseconds: UInt64) {
        signalDebounceTask?.cancel()
        signalDebounceTask = Task {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            signalTask?.cancel()
            signalTask = Task { await generateTradingSignal() }
        }
    }
    
    // MARK: - Formatters
    // PERFORMANCE FIX: Cached currency formatters — avoids allocation per call
    private static let _currency2: NumberFormatter = {
        let nf = NumberFormatter(); nf.numberStyle = .currency
        nf.currencyCode = CurrencyManager.currencyCode; nf.maximumFractionDigits = 2; return nf
    }()
    private static let _currency4: NumberFormatter = {
        let nf = NumberFormatter(); nf.numberStyle = .currency
        nf.currencyCode = CurrencyManager.currencyCode; nf.maximumFractionDigits = 4; return nf
    }()

    private func formatPrice(_ value: Double) -> String {
        let formatter = value < 1 ? Self._currency4 : Self._currency2
        return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
    
    private func formatCurrency(_ value: Double) -> String {
        Self._currency2.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
    
    private func formatVolume(_ vol: Double) -> String {
        if vol >= 1_000_000_000 { return String(format: "%.1fB", vol / 1_000_000_000) }
        if vol >= 1_000_000 { return String(format: "%.1fM", vol / 1_000_000) }
        if vol >= 1_000 { return String(format: "%.1fK", vol / 1_000) }
        return String(format: "%.0f", vol)
    }
    
    private func formatQuantity(_ value: Double) -> String {
        if value == floor(value) {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.4f", value)
        }
    }
    
    // PERFORMANCE FIX: Cached date formatters
    private static let _timeShort: DateFormatter = {
        let df = DateFormatter(); df.timeStyle = .short; return df
    }()
    private static let _dateMediumTimeShort: DateFormatter = {
        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .short; return df
    }()

    private func formatTime(_ date: Date) -> String {
        Self._timeShort.string(from: date)
    }
}

// MARK: - Commodity Chart Point

/// Chart data point for commodity price charts (renamed to avoid conflict with PortfolioViewModel.ChartPoint)
struct CommodityChartPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let price: Double
    var volume: Double = 0
}

// MARK: - Native Chart View (Enhanced with Crosshair)

struct CommodityNativeChartView: View {
    let chartData: [CommodityChartPoint]
    let indicators: Set<IndicatorType>
    let priceColor: Color
    @Binding var crosshairPrice: Double?
    @Binding var crosshairDate: Date?
    @Binding var showCrosshair: Bool
    
    var body: some View {
        if #available(iOS 16.0, *) {
            VStack(spacing: 0) {
                CommoditySwiftChart(
                    chartData: chartData,
                    indicators: indicators,
                    priceColor: priceColor,
                    crosshairPrice: $crosshairPrice,
                    crosshairDate: $crosshairDate,
                    showCrosshair: $showCrosshair
                )
                
                // Indicator legend (matching crypto chart)
                if !indicators.isEmpty {
                    commodityIndicatorLegend
                        .padding(.top, 4)
                        .padding(.horizontal, 8)
                }
                
                // RSI sub-pane (volume is now integrated into the main chart)
                if indicators.contains(.rsi) {
                    CommodityRSIChart(prices: chartData.map(\.price))
                        .frame(height: 50)
                        .padding(.top, 4)
                }
            }
        } else {
            GeometryReader { geo in
                Path { path in
                    guard chartData.count > 1 else { return }
                    let minPrice = chartData.map(\.price).min() ?? 0
                    let maxPrice = chartData.map(\.price).max() ?? 1
                    let priceRange = max(maxPrice - minPrice, 0.01)
                    
                    for (index, point) in chartData.enumerated() {
                        let x = geo.size.width * CGFloat(index) / CGFloat(chartData.count - 1)
                        let y = geo.size.height * (1 - CGFloat((point.price - minPrice) / priceRange))
                        if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(priceColor, lineWidth: 2)
            }
        }
    }
    
    @ViewBuilder
    private var commodityIndicatorLegend: some View {
        HStack(spacing: 10) {
            if indicators.contains(.sma) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1).fill(Color.orange.opacity(0.8)).frame(width: 12, height: 3)
                    Text("SMA 20")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
            }
            if indicators.contains(.ema) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1).fill(Color.cyan.opacity(0.8)).frame(width: 12, height: 3)
                    Text("EMA 12")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
            }
            if indicators.contains(.bb) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1).fill(Color.purple.opacity(0.45)).frame(width: 12, height: 3)
                    Text("BB 20")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
            }
            if indicators.contains(.volume) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1).fill(Color.green.opacity(0.35)).frame(width: 12, height: 3)
                    Text("Vol")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
            }
            Spacer()
        }
    }
}

// MARK: - Indicator Computation Helpers

private struct MAPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

private struct BBPoint: Identifiable {
    let id = UUID()
    let date: Date
    let upper: Double
    let middle: Double
    let lower: Double
}

/// Compute Simple Moving Average from chart data
private func computeSMA(_ data: [CommodityChartPoint], period: Int) -> [MAPoint] {
    guard data.count >= period else { return [] }
    var result: [MAPoint] = []
    for i in (period - 1)..<data.count {
        let slice = data[(i - period + 1)...i]
        let avg = slice.reduce(0.0) { $0 + $1.price } / Double(period)
        result.append(MAPoint(date: data[i].timestamp, value: avg))
    }
    return result
}

/// Compute Exponential Moving Average
private func computeEMA(_ data: [CommodityChartPoint], period: Int) -> [MAPoint] {
    guard data.count >= period else { return [] }
    let multiplier = 2.0 / Double(period + 1)
    var ema = data.prefix(period).reduce(0.0) { $0 + $1.price } / Double(period)
    var result: [MAPoint] = [MAPoint(date: data[period - 1].timestamp, value: ema)]
    for i in period..<data.count {
        ema = (data[i].price - ema) * multiplier + ema
        result.append(MAPoint(date: data[i].timestamp, value: ema))
    }
    return result
}

/// Compute Bollinger Bands (20-period SMA ± 2 std devs)
private func computeBB(_ data: [CommodityChartPoint], period: Int = 20, multiplier: Double = 2.0) -> [BBPoint] {
    guard data.count >= period else { return [] }
    var result: [BBPoint] = []
    for i in (period - 1)..<data.count {
        let slice = Array(data[(i - period + 1)...i])
        let mean = slice.reduce(0.0) { $0 + $1.price } / Double(period)
        let variance = slice.reduce(0.0) { $0 + pow($1.price - mean, 2) } / Double(period)
        let stdDev = sqrt(variance)
        result.append(BBPoint(
            date: data[i].timestamp,
            upper: mean + multiplier * stdDev,
            middle: mean,
            lower: mean - multiplier * stdDev
        ))
    }
    return result
}

/// Compute RSI
private func computeRSI(_ prices: [Double], period: Int = 14) -> [Double] {
    guard prices.count > period else { return Array(repeating: 50, count: prices.count) }
    var rsiValues: [Double] = Array(repeating: 50, count: period)
    
    var avgGain: Double = 0
    var avgLoss: Double = 0
    for i in 1...period {
        let change = prices[i] - prices[i - 1]
        if change > 0 { avgGain += change }
        else { avgLoss += abs(change) }
    }
    avgGain /= Double(period)
    avgLoss /= Double(period)
    
    let firstRS = avgLoss == 0 ? 100 : avgGain / avgLoss
    rsiValues.append(100 - (100 / (1 + firstRS)))
    
    for i in (period + 1)..<prices.count {
        let change = prices[i] - prices[i - 1]
        let gain = change > 0 ? change : 0
        let loss = change < 0 ? abs(change) : 0
        avgGain = (avgGain * Double(period - 1) + gain) / Double(period)
        avgLoss = (avgLoss * Double(period - 1) + loss) / Double(period)
        let rs = avgLoss == 0 ? 100 : avgGain / avgLoss
        rsiValues.append(100 - (100 / (1 + rs)))
    }
    return rsiValues
}

@available(iOS 16.0, *)
struct CommoditySwiftChart: View {
    let chartData: [CommodityChartPoint]
    let indicators: Set<IndicatorType>
    let priceColor: Color
    @Binding var crosshairPrice: Double?
    @Binding var crosshairDate: Date?
    @Binding var showCrosshair: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    private var prices: [Double] { chartData.map(\.price) }
    private var minVal: Double { chartData.map(\.price).min() ?? 0 }
    private var maxVal: Double { chartData.map(\.price).max() ?? 100 }
    private var range: Double { maxVal - minVal }
    private var padding: Double { range * 0.08 }
    
    // Compute BB bounds for y-axis scaling
    private var bbData: [BBPoint] {
        indicators.contains(.bb) ? computeBB(chartData) : []
    }
    private var effectiveMin: Double {
        let bbMin = bbData.map(\.lower).min() ?? minVal
        return min(minVal, bbMin) - padding
    }
    private var effectiveMax: Double {
        let bbMax = bbData.map(\.upper).max() ?? maxVal
        return max(maxVal, bbMax) + padding
    }
    
    // Integrated volume: scale to bottom 22% of chart (matching crypto chart)
    private var showVol: Bool {
        indicators.contains(.volume) && chartData.contains(where: { $0.volume > 0 })
    }
    // Use 98th percentile to prevent outlier spikes from crushing normal bars
    private var volCap: Double {
        guard showVol else { return 1 }
        let sorted = chartData.map(\.volume).sorted()
        let p98 = max(0, Int(Double(sorted.count) * 0.98) - 1)
        return max(sorted.isEmpty ? 1 : sorted[min(p98, sorted.count - 1)], 1)
    }
    private var volScale: Double { (effectiveMax - effectiveMin) * 0.22 / max(volCap, 1) }
    
    var body: some View {
        Chart {
            // ── Integrated Volume Bars (rendered first, behind everything) ──
            if showVol {
                ForEach(Array(chartData.enumerated()), id: \.element.id) { index, point in
                    let isUp = index == 0 || point.price >= chartData[index - 1].price
                    let volH = min(point.volume, volCap * 1.2) * volScale
                    let baseColor = isUp ? Color.green : Color.red
                    BarMark(
                        x: .value("Time", point.timestamp),
                        yStart: .value("VolBase", effectiveMin),
                        yEnd: .value("Vol", effectiveMin + volH)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [baseColor.opacity(0.35), baseColor.opacity(0.12)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
            
            // ── Bollinger Bands (matching crypto chart) ──
            if indicators.contains(.bb) {
                ForEach(bbData) { point in
                    LineMark(x: .value("Time", point.date), y: .value("BB Upper", point.upper))
                        .foregroundStyle(Color.purple.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1.0, dash: [4, 3]))
                    LineMark(x: .value("Time", point.date), y: .value("BB Lower", point.lower))
                        .foregroundStyle(Color.purple.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1.0, dash: [4, 3]))
                }
                ForEach(bbData) { point in
                    AreaMark(
                        x: .value("Time", point.date),
                        yStart: .value("BB Lower", point.lower),
                        yEnd: .value("BB Upper", point.upper)
                    )
                    .foregroundStyle(Color.purple.opacity(0.08))
                }
            }
            
            // ── SMA (20-period, matching crypto chart line weight) ──
            if indicators.contains(.sma) {
                let smaData = computeSMA(chartData, period: 20)
                ForEach(smaData) { point in
                    LineMark(x: .value("Time", point.date), y: .value("SMA", point.value))
                        .foregroundStyle(Color.orange.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 1.8))
                        .interpolationMethod(.monotone)
                }
            }
            
            // ── EMA (12-period, matching crypto chart line weight) ──
            if indicators.contains(.ema) {
                let emaData = computeEMA(chartData, period: 12)
                ForEach(emaData) { point in
                    LineMark(x: .value("Time", point.date), y: .value("EMA", point.value))
                        .foregroundStyle(Color.cyan.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 1.6))
                        .interpolationMethod(.monotone)
                }
            }
            
            // ── Price Line (bolder, matching crypto chart) ──
            ForEach(chartData) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Price", point.price)
                )
                .foregroundStyle(priceColor.gradient)
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2.2))
                
                AreaMark(
                    x: .value("Time", point.timestamp),
                    yStart: .value("Min", effectiveMin),
                    yEnd: .value("Price", point.price)
                )
                .foregroundStyle(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: priceColor.opacity(0.38), location: 0.0),
                            .init(color: priceColor.opacity(0.22), location: 0.3),
                            .init(color: priceColor.opacity(0.08), location: 0.6),
                            .init(color: .clear, location: 1.0)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)
            }
            
            // ── Crosshair ── LIGHT MODE FIX: Adaptive colors
            if showCrosshair, let date = crosshairDate {
                RuleMark(x: .value("Selected", date))
                    .foregroundStyle(isDark ? Color.white.opacity(0.5) : Color.black.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 2]))
                if let price = crosshairPrice {
                    RuleMark(y: .value("Price", price))
                        .foregroundStyle(isDark ? Color.white.opacity(0.3) : Color.black.opacity(0.20))
                        .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                }
            }
        }
        .chartYScale(domain: effectiveMin...effectiveMax)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                    .foregroundStyle(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                AxisValueLabel()
                    .foregroundStyle(DS.Adaptive.textTertiary)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 5)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3, dash: [4, 4]))
                    .foregroundStyle(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                AxisValueLabel {
                    if let price = value.as(Double.self) {
                        Text(formatAxisPrice(price))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(DS.Adaptive.textTertiary)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                // Preserve native/custom back swipe from the left edge.
                                guard value.startLocation.x > 28 else { return }
                                guard let plotAnchor = proxy.plotFrame else { return }
                                let x = value.location.x - geo[plotAnchor].origin.x
                                if let date: Date = proxy.value(atX: x) {
                                    if let closest = chartData.min(by: {
                                        abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date))
                                    }) {
                                        if crosshairDate != closest.timestamp {
                                            crosshairDate = closest.timestamp
                                            crosshairPrice = closest.price
                                            #if os(iOS)
                                            ChartHaptics.shared.tickIfNeeded()
                                            #endif
                                        }
                                        showCrosshair = true
                                    }
                                }
                            }
                            .onEnded { _ in
                                showCrosshair = false
                                crosshairPrice = nil
                                crosshairDate = nil
                            }
                    )
            }
        }
        // Premium crosshair tooltip (matching stock/coin page design)
        .overlay(alignment: .topLeading) {
            if showCrosshair, let price = crosshairPrice, let date = crosshairDate {
                let closestPoint = chartData.min(by: {
                    abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date))
                })
                
                let tooltipBg: [Color] = isDark
                    ? [Color(red: 0.12, green: 0.12, blue: 0.14).opacity(0.95),
                       Color(red: 0.06, green: 0.06, blue: 0.08).opacity(0.95)]
                    : [Color.white.opacity(0.98),
                       Color(red: 0.96, green: 0.96, blue: 0.97).opacity(0.98)]
                let goldStroke = LinearGradient(
                    colors: isDark
                        ? [Color(red: 1.0, green: 0.85, blue: 0.4).opacity(0.5), Color(red: 0.85, green: 0.65, blue: 0.1).opacity(0.3)]
                        : [Color(red: 0.72, green: 0.52, blue: 0.08).opacity(0.4), Color(red: 0.60, green: 0.42, blue: 0.04).opacity(0.25)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(formatAxisPrice(price))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(
                                isDark
                                    ? LinearGradient(colors: [Color(red: 1.0, green: 0.85, blue: 0.4), Color(red: 0.9, green: 0.7, blue: 0.2)], startPoint: .leading, endPoint: .trailing)
                                    : LinearGradient(colors: [Color(red: 0.72, green: 0.52, blue: 0.08), Color(red: 0.60, green: 0.42, blue: 0.04)], startPoint: .leading, endPoint: .trailing)
                            )
                        Text(formatCrosshairDate(date))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                        
                        if let point = closestPoint, point.volume > 0, indicators.contains(.volume) {
                            HStack(spacing: 3) {
                                Image(systemName: "chart.bar.fill")
                                    .font(.system(size: 7))
                                Text(formatVolume(point.volume))
                                    .font(.system(size: 9, weight: .medium))
                            }
                            .foregroundColor(DS.Colors.gold.opacity(0.8))
                        }
                    }
                    
                    if indicators.contains(.sma) || indicators.contains(.ema) {
                        VStack(alignment: .leading, spacing: 3) {
                            if indicators.contains(.sma) {
                                let smaVal = computeSMA(chartData, period: 20).last(where: { $0.date <= date })?.value
                                if let v = smaVal {
                                    HStack(spacing: 3) {
                                        Circle().fill(Color.orange).frame(width: 5, height: 5)
                                        Text("SMA \(formatAxisPrice(v))")
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundColor(.orange)
                                    }
                                }
                            }
                            if indicators.contains(.ema) {
                                let emaVal = computeEMA(chartData, period: 12).last(where: { $0.date <= date })?.value
                                if let v = emaVal {
                                    HStack(spacing: 3) {
                                        Circle().fill(Color.cyan).frame(width: 5, height: 5)
                                        Text("EMA \(formatAxisPrice(v))")
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundColor(.cyan)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: tooltipBg, startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(goldStroke, lineWidth: 1)
                )
                .padding(.leading, 8)
                .padding(.top, 8)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.15), value: showCrosshair)
            }
        }
    }
    
    private func formatAxisPrice(_ value: Double) -> String {
        if value >= 10000 {
            return "$\(String(format: "%.0f", value))"
        } else if value >= 1000 {
            return "$\(String(format: "%.1f", value))"
        } else if value >= 1 {
            return String(format: "$%.2f", value)
        } else {
            return String(format: "$%.4f", value)
        }
    }
    
    private func formatVolume(_ vol: Double) -> String {
        if vol >= 1_000_000_000 { return String(format: "%.1fB", vol / 1_000_000_000) }
        if vol >= 1_000_000 { return String(format: "%.1fM", vol / 1_000_000) }
        if vol >= 1_000 { return String(format: "%.1fK", vol / 1_000) }
        return String(format: "%.0f", vol)
    }
    
    private static let _dateMediumTimeShort: DateFormatter = {
        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .short; return df
    }()
    private func formatCrosshairDate(_ date: Date) -> String {
        return Self._dateMediumTimeShort.string(from: date)
    }
}

// MARK: - Volume Sub-Chart
@available(iOS 16.0, *)
struct CommodityVolumeChart: View {
    let chartData: [CommodityChartPoint]
    let priceColor: Color
    
    var body: some View {
        Chart {
            ForEach(Array(chartData.enumerated()), id: \.element.id) { index, point in
                let isUp = index == 0 || point.price >= chartData[index - 1].price
                BarMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Vol", point.volume)
                )
                .foregroundStyle(isUp ? Color.green.opacity(0.4) : Color.red.opacity(0.4))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 2)) { value in
                AxisValueLabel {
                    if let vol = value.as(Double.self) {
                        Text(formatVolume(vol))
                            .font(.system(size: 8))
                            .foregroundStyle(DS.Adaptive.textTertiary.opacity(0.6))
                    }
                }
            }
        }
    }
    
    private func formatVolume(_ v: Double) -> String {
        if v >= 1_000_000_000 { return String(format: "%.1fB", v / 1_000_000_000) }
        if v >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000) }
        if v >= 1_000 { return String(format: "%.0fK", v / 1_000) }
        return String(format: "%.0f", v)
    }
}

// MARK: - RSI Sub-Pane
@available(iOS 16.0, *)
struct CommodityRSIChart: View {
    let prices: [Double]
    
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    private var rsiValues: [Double] { computeRSI(prices) }
    
    var body: some View {
        Chart {
            // Overbought/oversold zones
            RuleMark(y: .value("Overbought", 70))
                .foregroundStyle(Color.red.opacity(0.3))
                .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
            RuleMark(y: .value("Oversold", 30))
                .foregroundStyle(Color.green.opacity(0.3))
                .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
            RuleMark(y: .value("Mid", 50))
                .foregroundStyle(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                .lineStyle(StrokeStyle(lineWidth: 0.3))
            
            ForEach(Array(rsiValues.enumerated()), id: \.offset) { index, rsi in
                LineMark(
                    x: .value("Idx", index),
                    y: .value("RSI", rsi)
                )
                .foregroundStyle(Color.yellow.opacity(0.85))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.monotone)
            }
        }
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [30, 50, 70]) { value in
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text("\(v)")
                            .font(.system(size: 8))
                            .foregroundStyle(DS.Adaptive.textTertiary.opacity(0.6))
                    }
                }
            }
        }
        .overlay(alignment: .topLeading) {
            Text("RSI (14)")
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.yellow.opacity(0.6))
                .padding(.leading, 4)
                .padding(.top, 2)
        }
    }
}

// MARK: - ChartInterval Extension for Commodities

extension ChartInterval {
    /// Convert to StockPriceService.ChartRange for Yahoo Finance historical data
    func toStockChartRange() -> StockPriceService.ChartRange {
        switch self {
        case .oneDay: return .oneDay
        case .oneWeek: return .fiveDay
        case .oneMonth: return .oneMonth
        case .threeMonth: return .threeMonth
        case .sixMonth: return .sixMonth
        case .oneYear: return .oneYear
        case .threeYear: return .fiveYear
        case .all: return .max
        default: return .oneMonth
        }
    }
}

// MARK: - Commodity News Category
enum CommodityNewsCategory: String, CaseIterable, Hashable {
    case top = "Top"
    case market = "Market"
    case supply = "Supply"
    case economic = "Economic"
    case trading = "Trading"
    
    var queryKeywords: String {
        switch self {
        case .top: return "price OR market OR forecast"
        case .market: return "price OR rally OR selloff OR futures"
        case .supply: return "supply OR production OR mining OR output"
        case .economic: return "inflation OR interest rates OR fed OR economy"
        case .trading: return "trading OR futures OR options OR COMEX"
        }
    }
}

// MARK: - Commodity News ViewModel
@MainActor
final class CommodityNewsViewModel: ObservableObject {
    @Published var articles: [NewsArticle] = []
    @Published var isLoading: Bool = false
    
    private static var cache: [String: (Date, [NewsArticle])] = [:]
    private let cacheTTL: TimeInterval = 10 * 60 // 10 minutes
    
    func fetch(commodityName: String, category: CommodityNewsCategory) {
        let key = commodityName + "|" + category.rawValue
        if let (ts, items) = Self.cache[key], Date().timeIntervalSince(ts) < cacheTTL {
            self.articles = items
            self.isLoading = false
            return
        }
        isLoading = true
        let url = feedURL(for: commodityName, category: category)
        Task { @MainActor in
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let items = GoogleNewsRSSParser.parse(data: data)
                self.articles = items
                self.isLoading = false
                Self.cache[key] = (Date(), items)
            } catch {
                self.articles = []
                self.isLoading = false
            }
        }
    }
    
    func moreURL(for commodityName: String, category: CommodityNewsCategory) -> URL? {
        let q = query(for: commodityName, category: category)
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? commodityName
        return URL(string: "https://news.google.com/search?q=\(q)")
    }
    
    private func feedURL(for commodityName: String, category: CommodityNewsCategory) -> URL {
        let q = query(for: commodityName, category: category)
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? commodityName
        return URL(string: "https://news.google.com/rss/search?q=\(q)&hl=en-US&gl=US&ceid=US:en") ?? URL(string: "https://news.google.com")!
    }
    
    private func query(for commodityName: String, category: CommodityNewsCategory) -> String {
        return "\(commodityName) commodity \(category.queryKeywords)"
    }
}

// MARK: - Commodity Shimmer View

private struct CommodityShimmerView: View {
    @State private var isAnimating = false
    
    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.gray.opacity(0.3))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.3), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .offset(x: isAnimating ? 200 : -200)
            )
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - Factory Method

extension CommodityDetailView {
    /// Create a CommodityDetailView from a symbol string
    /// Looks up the commodity info from the mapper, or creates a fallback info
    static func fromSymbol(_ symbol: String, holding: Holding? = nil) -> CommodityDetailView {
        let info = CommoditySymbolMapper.getCommodity(for: symbol) ?? CommodityInfo(
            id: symbol.lowercased(),
            name: CommoditySymbolMapper.displayName(for: symbol),
            type: .preciousMetal,
            coinbaseSymbol: symbol,
            yahooSymbol: "\(symbol)=F",
            tradingViewSymbol: "TVC:\(symbol.uppercased())",
            tradingViewAltSymbols: [],
            unit: "unit",
            currencyCode: nil
        )
        return CommodityDetailView(commodityInfo: info, holding: holding)
    }
}

// MARK: - Commodity Deep Dive Sheet

struct CommodityDeepDiveSheet: View {
    let commodityName: String
    let symbol: String
    let price: Double
    let change24h: Double
    let sparkline: [Double]
    let aiInsight: CoinAIInsight?
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var deepDiveText: String = ""
    @State private var isLoading: Bool = false
    @State private var isEnhancing: Bool = false   // loading behind existing insight
    @State private var justUpdated: Bool = false    // flash after deep dive replaces existing
    @State private var error: String? = nil
    @State private var cardsAppeared: Bool = false
    @State private var showCopiedToast: Bool = false
    
    private var isDark: Bool { colorScheme == .dark }
    private var changeColor: Color { change24h >= 0 ? .green : .red }
    private var hasContent: Bool { !deepDiveText.isEmpty || aiInsight != nil }
    
    private var displayText: String {
        if !deepDiveText.isEmpty { return deepDiveText }
        if let insight = aiInsight { return insight.insightText }
        return ""
    }
    
    private var shareableText: String {
        "\(commodityName) AI Deep Dive\n\n\(displayText)"
    }
    
    private var sentimentLabel: String {
        if change24h > 3 { return "Bullish" }
        if change24h > 0.5 { return "Slightly Bullish" }
        if change24h > -0.5 { return "Neutral" }
        if change24h > -3 { return "Slightly Bearish" }
        return "Bearish"
    }
    private var sentimentColor: Color {
        if change24h > 0.5 { return .green }
        if change24h > -0.5 { return .orange }
        return .red
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 0) {
                        // Hero header
                        commodityHero
                            .modifier(CommodityDeepDiveAppear(appeared: cardsAppeared, delay: 0))
                        
                        VStack(alignment: .leading, spacing: 14) {
                            // Technical Indicators (matching crypto deep dive)
                            if sparkline.count >= 14 {
                                commodityTechnicals
                                    .modifier(CommodityDeepDiveAppear(appeared: cardsAppeared, delay: 0.05))
                            }
                            
                            // Market Context
                            commodityMarketContext
                                .modifier(CommodityDeepDiveAppear(appeared: cardsAppeared, delay: 0.10))
                            
                            // AI Analysis
                            commodityAISection
                                .modifier(CommodityDeepDiveAppear(appeared: cardsAppeared, delay: 0.15))
                            
                            Spacer(minLength: 20)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                    }
                }
                
                if showCopiedToast {
                    Text("Analysis copied")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Capsule().fill(Color.black.opacity(0.8)))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 16)
                }
            }
            .background(DS.Adaptive.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadDeepDive() }
            .onAppear {
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.4)) { cardsAppeared = true }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(DS.Adaptive.textTertiary)
                    }
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DS.Adaptive.gold)
                        Text("AI Deep Dive")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            #if os(iOS)
                            UIPasteboard.general.string = displayText
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            withAnimation(.easeInOut(duration: 0.2)) { showCopiedToast = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation(.easeInOut(duration: 0.2)) { showCopiedToast = false }
                            }
                        } label: {
                            Label("Copy Analysis", systemImage: "doc.on.doc")
                        }
                        ShareLink(item: shareableText) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                }
            }
            .toolbarBackground(DS.Adaptive.background.opacity(0.95), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
    
    // MARK: - Hero Header
    private var commodityHero: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(commodityName)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        Text(ddCurrency(price))
                            .font(.system(size: 26, weight: .heavy).monospacedDigit())
                            .foregroundColor(DS.Adaptive.textPrimary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        HStack(spacing: 4) {
                            Image(systemName: change24h >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 11, weight: .bold))
                            Text(String(format: "%.2f%%", abs(change24h)))
                                .font(.system(size: 14, weight: .bold).monospacedDigit())
                        }
                        .foregroundColor(changeColor)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(changeColor.opacity(isDark ? 0.15 : 0.1)))
                        
                        Text(sentimentLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(sentimentColor.opacity(0.9))
                    }
                }
                
                // Sparkline mini chart (matching crypto deep dive)
                if sparkline.count >= 2 {
                    let minP = sparkline.min() ?? 0
                    let maxP = sparkline.max() ?? 1
                    let sparkColor: Color = (sparkline.last ?? 0) >= (sparkline.first ?? 0) ? .green : .red
                    GeometryReader { geo in
                        Path { path in
                            let range = max(maxP - minP, 0.01)
                            for (i, val) in sparkline.enumerated() {
                                let x = geo.size.width * CGFloat(i) / CGFloat(max(sparkline.count - 1, 1))
                                let y = geo.size.height * (1 - CGFloat((val - minP) / range))
                                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                else { path.addLine(to: CGPoint(x: x, y: y)) }
                            }
                        }
                        .stroke(sparkColor, lineWidth: 1.5)
                    }
                    .frame(height: 40)
                    .padding(.top, 4)
                    
                    // 7D range bar
                    let rangePct = maxP > minP ? (price - minP) / (maxP - minP) : 0.5
                    VStack(spacing: 4) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)).frame(height: 4)
                                Circle().fill(DS.Adaptive.textPrimary).frame(width: 8, height: 8)
                                    .offset(x: max(0, min(geo.size.width - 8, CGFloat(rangePct) * geo.size.width - 4)))
                            }
                        }
                        .frame(height: 8)
                        
                        HStack {
                            Text(ddCurrency(minP))
                                .font(.system(size: 9, weight: .medium).monospacedDigit())
                                .foregroundColor(DS.Adaptive.textTertiary)
                            Spacer()
                            Text("7D Range · \(Int(rangePct * 100))%")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(DS.Adaptive.textTertiary)
                            Spacer()
                            Text(ddCurrency(maxP))
                                .font(.system(size: 9, weight: .medium).monospacedDigit())
                                .foregroundColor(DS.Adaptive.textTertiary)
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 16)
            .background(
                ZStack {
                    DS.Adaptive.cardBackground
                    LinearGradient(colors: [DS.Adaptive.gold.opacity(isDark ? 0.06 : 0.04), Color.clear],
                                   startPoint: .top, endPoint: .bottom)
                }
            )
            Rectangle().fill(DS.Adaptive.divider).frame(height: 0.5)
        }
    }
    
    // MARK: - Technical Indicators (matching crypto deep dive)
    private var commodityTechnicals: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                GoldHeaderGlyph(systemName: "chart.line.uptrend.xyaxis")
                Text("Technical Indicators")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
            }
            
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                // RSI
                if sparkline.count >= 14, let rsi = TechnicalsEngine.rsi(sparkline, period: 14) {
                    DeepDiveIndicatorCell(
                        name: "RSI (14)",
                        value: String(format: "%.0f", rsi),
                        signal: rsi < 30 ? "Oversold" : (rsi > 70 ? "Overbought" : "Neutral"),
                        signalColor: rsi < 30 ? .green : (rsi > 70 ? .red : .yellow)
                    )
                }
                
                // MACD
                if sparkline.count >= 26, let macdResult = TechnicalsEngine.macdLineSignal(sparkline) {
                    let m = macdResult.macd, s = macdResult.signal
                    DeepDiveIndicatorCell(
                        name: "MACD",
                        value: String(format: "%.4f", m - s),
                        signal: m > s ? "Bullish" : "Bearish",
                        signalColor: m > s ? .green : .red
                    )
                }
                
                // Volatility
                let vol = ddVolatility(of: sparkline)
                DeepDiveIndicatorCell(
                    name: "Volatility",
                    value: String(format: "%.2f%%", vol),
                    signal: vol > 5 ? "High" : (vol > 2 ? "Medium" : "Low"),
                    signalColor: vol > 5 ? .orange : (vol > 2 ? .yellow : .green)
                )
                
                // 7D Momentum
                let mom7 = ddPercentChange(from: sparkline.first, to: sparkline.last)
                DeepDiveIndicatorCell(
                    name: "7D Momentum",
                    value: String(format: "%+.1f%%", mom7),
                    signal: mom7 > 5 ? "Strong" : (mom7 > 0 ? "Positive" : (mom7 > -5 ? "Negative" : "Weak")),
                    signalColor: mom7 > 0 ? .green : .red
                )
            }
            
            // Support / Resistance levels
            let (support, resistance) = ddSwingLevels(series: sparkline, currentPrice: price)
            if support != nil || resistance != nil {
                HStack(spacing: 8) {
                    if let s = support {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2).fill(Color.green).frame(width: 3, height: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Support").font(.system(size: 9, weight: .medium)).foregroundColor(DS.Adaptive.textTertiary)
                                Text(ddCurrency(s)).font(.system(size: 13, weight: .bold).monospacedDigit()).foregroundColor(.green)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8).padding(.horizontal, 10)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.green.opacity(isDark ? 0.06 : 0.04)))
                    }
                    if let r = resistance {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2).fill(Color.red).frame(width: 3, height: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Resistance").font(.system(size: 9, weight: .medium)).foregroundColor(DS.Adaptive.textTertiary)
                                Text(ddCurrency(r)).font(.system(size: 13, weight: .bold).monospacedDigit()).foregroundColor(.red)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8).padding(.horizontal, 10)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.red.opacity(isDark ? 0.06 : 0.04)))
                    }
                }
                .padding(.top, 2)
            }
        }
        .modifier(DeepDiveCardStyle())
    }
    
    // MARK: - Market Context
    private var commodityMarketContext: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                GoldHeaderGlyph(systemName: "globe")
                Text("Market Context")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
            }
            
            VStack(spacing: 0) {
                // Fear & Greed
                if let sentiment = ExtendedFearGreedViewModel.shared.currentValue,
                   let classification = ExtendedFearGreedViewModel.shared.currentClassificationKey {
                    VStack(spacing: 6) {
                        HStack {
                            Text("Fear & Greed Index")
                                .font(.system(size: 12))
                                .foregroundColor(DS.Adaptive.textSecondary)
                            Spacer()
                            HStack(spacing: 4) {
                                Text("\(sentiment)")
                                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                                    .foregroundColor(DS.Adaptive.textPrimary)
                                Text("(\(classification.capitalized))")
                                    .font(.system(size: 10))
                                    .foregroundColor(DS.Adaptive.textTertiary)
                            }
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                LinearGradient(colors: [.red, .orange, .yellow, .green], startPoint: .leading, endPoint: .trailing)
                                    .frame(height: 5).clipShape(Capsule())
                                Circle().fill(.white).frame(width: 9, height: 9)
                                    .offset(x: CGFloat(sentiment) / 100 * (geo.size.width - 9))
                            }
                        }
                        .frame(height: 9)
                    }
                    .padding(.vertical, 8).padding(.horizontal, 10)
                    
                    Rectangle().fill(DS.Adaptive.divider).frame(height: 0.5).padding(.horizontal, 10)
                }
                
                // Global Market 24h
                if let globalChange = MarketViewModel.shared.globalChange24hPercent {
                    ddContextRow(
                        label: "Market 24h",
                        value: String(format: "%+.2f%%", globalChange),
                        valueColor: globalChange >= 0 ? .green : .red
                    )
                    Rectangle().fill(DS.Adaptive.divider).frame(height: 0.5).padding(.horizontal, 10)
                }
                
                // DXY / Dollar context (relevant for commodities)
                ddContextRow(
                    label: "Asset Type",
                    value: "Commodity",
                    valueColor: DS.Adaptive.textPrimary
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isDark ? Color.white.opacity(0.02) : Color.black.opacity(0.015))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(DS.Adaptive.stroke.opacity(0.6), lineWidth: 0.5)
            )
        }
        .modifier(DeepDiveCardStyle())
    }
    
    private func ddContextRow(label: String, value: String, valueColor: Color) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundColor(DS.Adaptive.textSecondary)
            Spacer()
            Text(value).font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundColor(valueColor)
        }
        .padding(.vertical, 8).padding(.horizontal, 10)
    }
    
    // MARK: - AI Analysis
    private var commodityAISection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                GoldHeaderGlyph(systemName: "sparkles")
                Text("CryptoSage AI Analysis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .allowsTightening(true)
                
                // "Enhancing..." indicator while deep dive loads behind existing insight
                if isEnhancing {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.55)
                            .frame(width: 10, height: 10)
                        Text("Enhancing…")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .transition(.opacity)
                }
                
                // Brief "Updated" badge after deep dive replaces stale insight
                if justUpdated {
                    Text("Updated")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.green)
                        .transition(.opacity)
                }
                
                Spacer()
                
                if error != nil && !hasContent && !isLoading {
                    Button { Task { await loadDeepDive() } } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise").font(.system(size: 10))
                            Text("Retry").font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(DS.Adaptive.gold)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(DS.Adaptive.gold.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }
            
            if let insight = aiInsight, deepDiveText.isEmpty {
                Text(insight.insightText)
                    .font(.system(size: 14))
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            if isLoading && !hasContent {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(0..<6, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(DS.Adaptive.chipBackground)
                            .frame(maxWidth: i == 5 ? 140 : (i == 3 ? 200 : .infinity))
                            .frame(height: 14)
                            .shimmer()
                    }
                }
            } else if !deepDiveText.isEmpty {
                Text(deepDiveText)
                    .font(.system(size: 14))
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            } else if error != nil && !hasContent {
                Text("Unable to generate analysis at this time.")
                    .font(.system(size: 14))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            
            Text("AI-generated analysis for educational purposes only. Always do your own research.")
                .font(.system(size: 9))
                .foregroundColor(DS.Adaptive.textTertiary)
                .padding(.top, 4)
        }
        .modifier(DeepDiveCardStyle())
    }
    
    // MARK: - Helpers
    
    private func ddCurrency(_ v: Double) -> String {
        if v >= 1 { return String(format: "$%.2f", v) }
        else if v >= 0.01 { return String(format: "$%.4f", v) }
        else { return String(format: "$%.6f", v) }
    }
    
    private func ddPercentChange(from: Double?, to: Double?) -> Double {
        guard let f = from, let t = to, f > 0 else { return 0 }
        return (t - f) / f * 100
    }
    
    private func ddVolatility(of series: [Double]) -> Double {
        guard series.count > 2 else { return 0 }
        var returns: [Double] = []
        for i in 1..<series.count {
            if series[i - 1] > 0 { returns.append((series[i] - series[i - 1]) / series[i - 1] * 100) }
        }
        let mean = returns.reduce(0, +) / Double(returns.count)
        let variance = returns.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(returns.count)
        return sqrt(variance)
    }
    
    private func ddSwingLevels(series: [Double], currentPrice: Double) -> (Double?, Double?) {
        guard series.count >= 10 else { return (nil, nil) }
        let window = Array(series.suffix(96))
        var localMins: [Double] = []; var localMaxs: [Double] = []
        for i in 1..<(window.count - 1) {
            if window[i] < window[i - 1] && window[i] < window[i + 1] { localMins.append(window[i]) }
            if window[i] > window[i - 1] && window[i] > window[i + 1] { localMaxs.append(window[i]) }
        }
        let support = localMins.filter { $0 < currentPrice }.max()
        let resistance = localMaxs.filter { $0 > currentPrice }.min()
        return (support, resistance)
    }
    
    // MARK: - Loading (cache-first)
    private func loadDeepDive() async {
        let cleanSymbol = symbol.replacingOccurrences(of: "=", with: "").uppercased()
        let cacheKey = "commodity-\(cleanSymbol)"
        
        if let cached = CoinAIInsightService.shared.cachedDeepDive(for: cacheKey) {
            await MainActor.run { deepDiveText = cached }
            return
        }
        
        let hasExisting = aiInsight != nil
        if !hasExisting {
            await MainActor.run { isLoading = true }
        } else {
            // Show "Enhancing..." so the user knows something is loading
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.15)) { isEnhancing = true }
            }
        }
        
        do {
            let response = try await FirebaseService.shared.getCoinInsight(
                coinId: "deepdive-commodity-\(cleanSymbol.lowercased())",
                coinName: "\(commodityName) (Commodity)",
                symbol: cleanSymbol,
                price: price,
                change24h: change24h,
                change7d: sparkline.count >= 2 ? ddPercentChange(from: sparkline.first, to: sparkline.last) : nil,
                marketCap: nil,
                volume24h: nil,
                assetType: "commodity"
            )
            await MainActor.run {
                let wasShowingExisting = hasExisting && deepDiveText.isEmpty
                withAnimation(.easeInOut(duration: 0.2)) {
                    deepDiveText = response.content
                    isEnhancing = false
                }
                isLoading = false
                
                // Flash "Updated" briefly when deep dive replaces the old insight
                if wasShowingExisting {
                    withAnimation(.easeInOut(duration: 0.15)) { justUpdated = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        withAnimation(.easeInOut(duration: 0.3)) { justUpdated = false }
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                withAnimation { isEnhancing = false }
                isLoading = false
            }
        }
    }
}

private struct CommodityDeepDiveAppear: ViewModifier {
    let appeared: Bool; let delay: Double
    func body(content: Content) -> some View {
        content.opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 10)
            .animation(.spring(response: 0.45, dampingFraction: 0.8).delay(delay), value: appeared)
    }
}

// MARK: - Commodity Why Moving Sheet

struct CommodityWhyMovingSheet: View {
    let commodityName: String
    let symbol: String
    let change24h: Double
    let explanation: String
    let isLoading: Bool
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var deepAnalysis: String = ""
    @State private var isLoadingDeep: Bool = false
    @State private var deepError: String? = nil
    
    private var isDark: Bool { colorScheme == .dark }
    private var accentColor: Color { change24h >= 0 ? .green : .red }
    private var displayAnalysis: String {
        if !deepAnalysis.isEmpty { return deepAnalysis }
        return explanation
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Hero header (matching stock Why Moving design)
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(accentColor.opacity(0.12))
                                        .frame(width: 40, height: 40)
                                    Image(systemName: change24h >= 0 ? "arrow.up.right" : "arrow.down.right")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(accentColor)
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(commodityName) is \(change24h >= 0 ? "up" : "down")")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(DS.Adaptive.textPrimary)
                                    Text(String(format: "%+.2f%% today", change24h))
                                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                                        .foregroundColor(accentColor)
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(DS.Adaptive.cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(DS.Adaptive.stroke, lineWidth: 1)
                    )
                    
                    // AI Analysis
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 7) {
                            GoldHeaderGlyph(systemName: "sparkles")
                            Text("CryptoSage AI Analysis")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(DS.Adaptive.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .allowsTightening(true)
                            Spacer()
                            
                            if deepError != nil && displayAnalysis.isEmpty {
                                Button { Task { await loadDeepAnalysis() } } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.clockwise").font(.system(size: 10))
                                        Text("Retry").font(.system(size: 10, weight: .medium))
                                    }
                                    .foregroundColor(DS.Adaptive.gold)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Capsule().fill(DS.Adaptive.gold.opacity(0.12)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        if isLoading || isLoadingDeep {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(0..<5, id: \.self) { i in
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(DS.Adaptive.chipBackground)
                                        .frame(maxWidth: i == 4 ? 140 : (i == 2 ? 200 : .infinity))
                                        .frame(height: 14)
                                        .shimmer()
                                }
                            }
                        } else if !displayAnalysis.isEmpty {
                            Text(displayAnalysis)
                                .font(.system(size: 14))
                                .foregroundColor(DS.Adaptive.textPrimary)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Text("AI analysis of market data. Not financial advice.")
                            .font(.system(size: 9))
                            .foregroundColor(DS.Adaptive.textTertiary)
                            .padding(.top, 4)
                    }
                    .modifier(DeepDiveCardStyle())
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(DS.Adaptive.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadDeepAnalysis() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(DS.Adaptive.textTertiary)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Why is \(symbol) moving?")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !displayAnalysis.isEmpty {
                        ShareLink(item: "\(commodityName) \(String(format: "%+.2f%%", change24h))\n\n\(displayAnalysis)") {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(DS.Adaptive.textSecondary)
                        }
                    }
                }
            }
            .toolbarBackground(DS.Adaptive.background.opacity(0.95), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
    
    private func loadDeepAnalysis() async {
        // If we already have the passed-in explanation, show it; but try to get a deeper one
        guard deepAnalysis.isEmpty else { return }
        
        let cleanSymbol = symbol.replacingOccurrences(of: "=", with: "").uppercased()
        
        if explanation.isEmpty {
            await MainActor.run { isLoadingDeep = true }
        }
        
        do {
            let response = try await FirebaseService.shared.getCoinInsight(
                coinId: "whymoving-commodity-\(cleanSymbol.lowercased())",
                coinName: "\(commodityName) (Commodity)",
                symbol: cleanSymbol,
                price: 0,
                change24h: change24h,
                change7d: nil,
                marketCap: nil,
                volume24h: nil,
                assetType: "commodity"
            )
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) { deepAnalysis = response.content }
                isLoadingDeep = false
            }
        } catch {
            await MainActor.run {
                deepError = error.localizedDescription
                isLoadingDeep = false
            }
        }
    }
}

// MARK: - Preview

#Preview("Gold") {
    NavigationStack {
        CommodityDetailView(
            commodityInfo: CommoditySymbolMapper.getCommodityById("gold")!,
            holding: nil
        )
        .environmentObject(PortfolioViewModel.sample)
    }
    .preferredColorScheme(.dark)
}

#Preview("Silver") {
    NavigationStack {
        CommodityDetailView.fromSymbol("XAG")
            .environmentObject(PortfolioViewModel.sample)
    }
    .preferredColorScheme(.dark)
}
