//
//  StockDetailView.swift
//  CryptoSage
//
//  Created by CryptoSage on 1/19/26.
//  Full detail view for stocks and ETFs with charts, company info, and key stats.
//  Revamped with premium styling matching the crypto coin detail pages.
//

import SwiftUI
import Charts

// MARK: - Stock Chart Type

/// Chart type for stocks (Native SwiftUI Charts or TradingView WebView)
enum StockChartType: String, CaseIterable, Hashable {
    case native = "Native"
    case tradingView = "TradingView"
}

// MARK: - Stock Chart Interval

enum StockChartInterval: String, CaseIterable {
    // Intraday timeframes
    case oneMin = "1m"
    case fiveMin = "5m"
    case fifteenMin = "15m"
    case thirtyMin = "30m"
    case oneHour = "1H"
    case fourHour = "4H"
    // Daily and longer
    case oneDay = "1D"
    case oneWeek = "1W"
    case oneMonth = "1M"
    case threeMonths = "3M"
    case sixMonths = "6M"
    case oneYear = "1Y"
    case fiveYears = "5Y"
    case all = "ALL"
    
    var displayName: String { rawValue }
    
    /// Yahoo Finance API range parameter
    var yahooRange: String {
        switch self {
        case .oneMin:       return "1d"
        case .fiveMin:      return "5d"
        case .fifteenMin:   return "1mo"
        case .thirtyMin:    return "1mo"
        case .oneHour:      return "1mo"
        case .fourHour:     return "3mo"
        case .oneDay:       return "1d"
        case .oneWeek:      return "5d"
        case .oneMonth:     return "1mo"
        case .threeMonths:  return "3mo"
        case .sixMonths:    return "6mo"
        case .oneYear:      return "1y"
        case .fiveYears:    return "5y"
        case .all:          return "max"
        }
    }
    
    /// Yahoo Finance API interval parameter
    var yahooInterval: String {
        switch self {
        case .oneMin:       return "1m"
        case .fiveMin:      return "5m"
        case .fifteenMin:   return "15m"
        case .thirtyMin:    return "30m"
        case .oneHour:      return "60m"
        case .fourHour:     return "60m"  // Yahoo doesn't support 4h, use 1h
        case .oneDay:       return "5m"
        case .oneWeek:      return "15m"
        case .oneMonth:     return "1d"
        case .threeMonths:  return "1d"
        case .sixMonths:    return "1d"
        case .oneYear:      return "1wk"
        case .fiveYears:    return "1mo"
        case .all:          return "1mo"
        }
    }
    
    /// TradingView interval string
    var tvInterval: String {
        switch self {
        case .oneMin:       return "1"
        case .fiveMin:      return "5"
        case .fifteenMin:   return "15"
        case .thirtyMin:    return "30"
        case .oneHour:      return "60"
        case .fourHour:     return "240"
        case .oneDay:       return "D"
        case .oneWeek:      return "W"
        case .oneMonth:     return "M"
        case .threeMonths:  return "3M"
        case .sixMonths:    return "6M"
        case .oneYear:      return "12M"
        case .fiveYears:    return "60M"
        case .all:          return "M"
        }
    }
    
    /// Whether this is an intraday timeframe
    var isIntraday: Bool {
        switch self {
        case .oneMin, .fiveMin, .fifteenMin, .thirtyMin, .oneHour, .fourHour:
            return true
        default:
            return false
        }
    }
}

// MARK: - Stock Info Tab

enum StockInfoTab: String, CaseIterable, Hashable {
    case overview = "Overview"
    case news = "News"
    case analysis = "Analysis"
}

// MARK: - Stock News Category
enum StockNewsCategory: String, CaseIterable, Hashable {
    case top = "Top"
    case earnings = "Earnings"
    case analysis = "Analysis"
    case market = "Market"
    case sec = "SEC Filings"
    
    var queryKeywords: String {
        switch self {
        case .top: return "stock OR shares"
        case .earnings: return "earnings OR revenue OR quarterly OR annual"
        case .analysis: return "analyst OR rating OR upgrade OR downgrade OR target"
        case .market: return "market OR trading OR volume OR price"
        case .sec: return "SEC OR filing OR 10-K OR 10-Q OR insider"
        }
    }
}

// MARK: - Stock Trading Signal Type

enum StockSignalType: String {
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
        case .buy: return "arrow.up.circle.fill"
        case .sell: return "arrow.down.circle.fill"
        case .hold: return "pause.circle.fill"
        }
    }
    
    var description: String {
        switch self {
        case .buy: return "Technical indicators suggest potential upside"
        case .sell: return "Consider taking profits or reducing exposure"
        case .hold: return "Wait for a clearer trend before acting"
        }
    }
}

// MARK: - Stock Trading Signal

struct StockTradingSignal {
    let type: StockSignalType
    let confidence: Double // 0.0 - 1.0
    let reasons: [String]
    let timestamp: Date
    
    var confidenceText: String {
        if confidence >= 0.8 { return "High" }
        if confidence >= 0.6 { return "Medium" }
        return "Low"
    }
    
    var confidenceColor: Color {
        if confidence >= 0.8 { return .green }
        if confidence >= 0.6 { return .yellow }
        return .orange
    }
    
    var sentimentScore: Double {
        type == .buy ? confidence : (type == .sell ? -confidence : 0)
    }
}

// MARK: - Stock Detail View

struct StockDetailView: View {
    let ticker: String
    let companyName: String
    let assetType: AssetType
    
    /// Optional holding if user owns this stock
    var holding: Holding?
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    // State
    @State private var quote: StockQuote?
    @State private var isLoadingQuote = false
    @State private var selectedInterval: StockChartInterval = .oneMonth
    @State private var chartData: [StockChartPoint] = []
    @State private var isLoadingChart = false
    @State private var showTradeSheet = false
    @State private var showSetAlert = false
    @State private var selectedInfoTab: StockInfoTab = .overview
    @State private var selectedNewsCategory: StockNewsCategory = .top
    @StateObject private var newsVM = StockNewsViewModel()
    
    // Chart type state (Native vs TradingView)
    @State private var selectedChartType: StockChartType = .native
    @State private var indicators: Set<IndicatorType> = [.volume]
    @State private var showIndicatorMenu = false
    
    // Crosshair state
    @State private var crosshairPrice: Double?
    @State private var crosshairDate: Date?
    @State private var showCrosshair = false
    
    // Data freshness tracking
    @State private var lastQuoteUpdate: Date?
    @State private var showDiagnostics = false
    
    // AI Signal state (unified TradingSignal model + Firebase AI)
    @State private var tradingSignal: TradingSignal?
    @State private var isGeneratingSignal = false
    @State private var signalTask: Task<Void, Never>? = nil
    @State private var signalDebounceTask: Task<Void, Never>? = nil
    @State private var lastSignalIndicatorsSignature: String = ""
    @State private var lastSignalInputPrice: Double?
    @State private var lastSignalInputChange24h: Double?
    @State private var lastSignalGeneratedAt: Date = .distantPast
    
    // AI Insight (Firebase-backed, shared across users like coin detail)
    @State private var aiInsight: CoinAIInsight? = nil
    @State private var isLoadingInsight: Bool = false
    
    // Technicals
    @StateObject private var techVM = TechnicalsViewModel()
    
    // Deep Dive state
    @State private var showDeepDive = false
    
    // Why is it moving state
    @State private var showWhyMoving = false
    
    // Watchlist integration
    @ObservedObject private var watchlistManager = StockWatchlistManager.shared
    
    // Animation states
    @State private var priceHighlight = false
    @State private var lastPrice: Double = 0
    
    // Check if stock is in watchlist
    private var isFavorite: Bool {
        watchlistManager.isWatched(ticker)
    }
    
    private var isDark: Bool { colorScheme == .dark }
    
    // LIGHT MODE FIX: Adaptive badge colors for better contrast on light backgrounds
    private var adaptiveBadgeColor: Color {
        if isDark { return assetType.color }
        switch assetType {
        case .stock: return Color(red: 0.15, green: 0.38, blue: 0.72) // deeper blue
        case .etf: return Color(red: 0.15, green: 0.55, blue: 0.25) // deeper green
        case .commodity: return Color(red: 0.75, green: 0.60, blue: 0.08) // deep amber
        case .crypto: return Color(red: 0.82, green: 0.50, blue: 0.12) // deeper orange
        }
    }
    
    // Computed display values
    private var displayPrice: Double {
        quote?.regularMarketPrice ?? holding?.currentPrice ?? 0
    }
    
    private var displayChange: Double {
        // Use API value if available, fallback to calculation from previousClose
        if let change = quote?.regularMarketChangePercent {
            return change
        }
        if let q = quote, let prevClose = q.regularMarketPreviousClose, prevClose > 0 {
            return ((q.regularMarketPrice - prevClose) / prevClose) * 100
        }
        return holding?.dailyChange ?? 0
    }
    
    private var displayName: String {
        quote?.displayName ?? companyName
    }

    private var signalAssetKey: String {
        AITradingSignalService.stockSignalCoinId(symbol: ticker)
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            FuturisticBackground()
                .ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    // Portfolio position banner (if user holds this stock)
                    if let holding = holding {
                        portfolioPositionBanner(holding)
                    }
                    
                    // Chart with streamlined controls
                    chartSection
                    
                    // "Why is it moving?" inline card for significant moves (5%+)
                    StockWhyIsMovingCard(
                        ticker: ticker,
                        companyName: displayName,
                        changePercent: displayChange,
                        showSheet: $showWhyMoving
                    )
                    
                    // Overview/News/Analysis tabs
                    infoTabsSection
                    
                    // AI Trading Signal
                    aiTradingSignalSection
                    
                    // Key Levels visualization
                    keyLevelsSection
                    
                    // Technicals Gauge Section
                    technicalsSection
                    
                    // Key Stats
                    keyStatsSection
                    
                    // About Section
                    aboutSection
                    
                    // Disclaimer
                    disclaimerSection
                        .padding(.bottom, 100)
                }
                .padding(.horizontal)
                .padding(.top, 4)
            }
            // PERFORMANCE FIX v21: UIKit scroll bridge for snappier deceleration + animation freeze
            .withUIKitScrollBridge()
        }
        .navigationBarBackButtonHidden(true)
        .safeAreaInset(edge: .top) { stockNavBar }
        .tint(.yellow)
        // Enable both native iOS pop gesture AND custom edge swipe with visual feedback
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
        .task(id: ticker.lowercased()) {
            tradingSignal = nil
            await loadStockData()
            await generateTradingSignal()
            loadAIInsight()
            newsVM.fetch(query: "\(displayName) \(ticker)", category: selectedNewsCategory)
        }
        .refreshable {
            AITradingSignalService.shared.clearCache(for: signalAssetKey)
            await loadStockData()
            await generateTradingSignal()
            loadAIInsight()
            newsVM.fetch(query: "\(displayName) \(ticker)", category: selectedNewsCategory)
        }
        .onChange(of: displayPrice) { _, newValue in
            // PERFORMANCE FIX v13: Skip during global startup phase
            guard !isInGlobalStartupPhase() else { return }
            // PERFORMANCE FIX: Skip during scroll to prevent "multiple updates per frame"
            guard !ScrollStateManager.shared.isScrolling else { return }
            
            DispatchQueue.main.async {
                if newValue != lastPrice && lastPrice > 0 {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        priceHighlight = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            priceHighlight = false
                        }
                    }
                }
                lastPrice = newValue
            }
        }
        .sheet(isPresented: $showSetAlert) {
            stockAlertSheet
        }
        .sheet(isPresented: $showDeepDive) {
            stockDeepDiveSheetView
        }
        .sheet(isPresented: $showWhyMoving) {
            stockWhyMovingSheetView
        }
        .sheet(isPresented: $showDiagnostics) {
            stockDiagnosticsSheetView
        }
        .onDisappear {
            signalTask?.cancel()
            signalDebounceTask?.cancel()
            signalTask = nil
            signalDebounceTask = nil
        }
    }
    
    private var stockDiagnosticsSheetView: some View {
        StockDiagnosticsSheet(
            ticker: ticker,
            companyName: displayName,
            quote: quote,
            lastUpdate: lastQuoteUpdate,
            chartDataCount: chartData.count,
            selectedInterval: selectedInterval,
            assetType: assetType
        )
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
    
    private var stockDeepDiveSheetView: some View {
        StockDeepDiveSheet(
            ticker: ticker,
            companyName: displayName,
            price: displayPrice,
            change24h: displayChange,
            chartData: chartData
        )
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    private var stockWhyMovingSheetView: some View {
        StockWhyMovingSheet(
            ticker: ticker,
            companyName: displayName,
            priceChange: displayChange
        )
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
    
    // MARK: - Premium Navigation Bar (matching CommodityDetailView layout)
    
    private var stockNavBar: some View {
        HStack(spacing: 12) {
            // Back button
            CSNavButton(
                icon: "chevron.left",
                action: { dismiss() }
            )
            
            // Stock icon and name (left-aligned, matching commodity layout)
            HStack(spacing: 10) {
                StockImageView(ticker: ticker, assetType: assetType, size: 36)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        Text(ticker)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DS.Adaptive.textSecondary)
                        
                        // Type badge
                        Text(assetType == .etf ? "ETF" : assetType == .commodity ? "COMMODITY" : "STOCK")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(adaptiveBadgeColor.opacity(isDark ? 0.8 : 0.85))
                            .clipShape(Capsule())
                    }
                }
            }
            
            Spacer()
            
            // Price display with gold gradient (right-aligned, matching commodity layout)
            VStack(alignment: .trailing, spacing: 4) {
                if isLoadingQuote && quote == nil {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DS.Adaptive.textTertiary.opacity(0.2))
                        .frame(width: 100, height: 24)
                        .shimmer()
                } else {
                    Text(formatCurrency(displayPrice))
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
                        .scaleEffect(priceHighlight ? 1.05 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: priceHighlight)
                }
                
                // Change percentage badge (matching commodity layout)
                HStack(spacing: 3) {
                    Image(systemName: displayChange >= 0 ? "arrow.up" : "arrow.down")
                        .font(.system(size: 9, weight: .bold))
                    Text(String(format: "%+.2f%%", displayChange))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundColor(displayChange >= 0 ? .green : .red)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill((displayChange >= 0 ? Color.green : Color.red).opacity(isDark ? 0.15 : 0.12))
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
        )
    }
    
    // MARK: - Portfolio Position Banner
    
    private func portfolioPositionBanner(_ holding: Holding) -> some View {
        let totalValue = holding.currentValue
        let totalCost = holding.costBasis * holding.quantity
        let profitLoss = totalValue - totalCost
        let profitLossPercent = totalCost > 0 ? (profitLoss / totalCost) * 100 : 0
        let isPositive = profitLoss >= 0
        
        return HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(isPositive ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: isPositive ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isPositive ? .green : .red)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Your Position")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textTertiary)
                
                HStack(spacing: 8) {
                    Text(formatCurrency(totalValue))
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Text(String(format: "%@%.2f%%", isPositive ? "+" : "", profitLossPercent))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(isPositive ? .green : .red)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(String(format: "%.4f", holding.quantity)) shares")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textSecondary)
                Text("Avg \(formatCurrency(holding.costBasis))")
                    .font(.caption2)
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isPositive ? Color.green.opacity(0.08) : Color.red.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isPositive ? Color.green.opacity(0.3) : Color.red.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Chart Section
    
    /// TradingView symbol format for stocks (e.g., "NASDAQ:AAPL")
    private var tvStockSymbol: String {
        // Map common exchanges to TradingView format
        let exchange: String
        switch assetType {
        case .etf:
            exchange = "AMEX"
        case .commodity:
            // Commodities use different symbols in TradingView
            return ticker.replacingOccurrences(of: "=F", with: "1!")
        default:
            // Default to NASDAQ for tech stocks, NYSE for others
            let techTickers = ["AAPL", "MSFT", "GOOGL", "GOOG", "AMZN", "META", "TSLA", "NVDA", "AMD", "INTC", "CSCO", "ADBE", "NFLX", "QCOM", "TXN", "AVGO"]
            exchange = techTickers.contains(ticker.uppercased()) ? "NASDAQ" : "NYSE"
        }
        return "\(exchange):\(ticker.uppercased())"
    }
    
    /// TradingView studies based on selected indicators
    private var tvStudies: [String] {
        TVStudiesMapper.buildCurrentStudies()
    }
    
    private var chartSection: some View {
        ZStack(alignment: .bottom) {
            // Premium glass background with depth gradient
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [
                            isDark ? Color.black.opacity(0.20) : Color.black.opacity(0.04),
                            isDark ? Color.black.opacity(0.10) : Color.black.opacity(0.02)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .background(DS.Adaptive.cardBackground)
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
                // Chart area - switches between Native and TradingView
                stockChartArea
                    .padding(.horizontal, 8)
                    .padding(.top, 2)
                    .padding(.bottom, 6)
                
                // Controls row
                chartControlsRow
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        // Border stroke
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 0.8)
                .allowsHitTesting(false)
        )
        // Top highlight gradient for premium glass effect
        .overlay(
            LinearGradient(
                colors: [Color.white.opacity(isDark ? 0.06 : 0.03), Color.clear],
                startPoint: .top,
                endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .allowsHitTesting(false)
        )
        // Subtle bottom shade for depth
        .overlay(
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(isDark ? 0.25 : 0.08)],
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .allowsHitTesting(false)
        )
        .sheet(isPresented: $showIndicatorMenu) {
            ChartIndicatorMenu(isPresented: $showIndicatorMenu)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }
    
    // MARK: - Chart Area (Native or TradingView)
    
    private var stockChartArea: some View {
        ZStack {
            // Native chart
            if selectedChartType == .native {
                if isLoadingChart && chartData.isEmpty {
                    ProgressView()
                        .frame(height: 240)
                } else if chartData.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.largeTitle)
                            .foregroundColor(DS.Adaptive.textTertiary)
                        Text("Chart data unavailable")
                            .font(.subheadline)
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                    .frame(height: 240)
                } else {
                    VStack(spacing: 0) {
                        stockChartWithCrosshair
                        
                        // Indicator legend (matching crypto chart)
                        if !indicators.isEmpty {
                            stockIndicatorLegend
                                .padding(.top, 4)
                                .padding(.horizontal, 8)
                        }
                        
                        // RSI sub-pane (volume is now integrated into the main chart)
                        if indicators.contains(.rsi) {
                            stockRSIChart
                                .frame(height: 50)
                                .padding(.top, 4)
                        }
                    }
                }
            }
            
            // TradingView chart
            if selectedChartType == .tradingView {
                TradingViewChartWebView(
                    symbol: tvStockSymbol,
                    interval: selectedInterval.tvInterval,
                    theme: isDark ? "dark" : "light",
                    studies: tvStudies,
                    altSymbols: [],
                    interactive: true
                )
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 240, maxHeight: 240)
            }
        }
    }
    
    // MARK: - Native Stock Chart with Crosshair & Indicators
    
    // Indicator computation helpers (matching commodity chart)
    private func stockSMA(_ period: Int) -> [(date: Date, value: Double)] {
        guard chartData.count >= period else { return [] }
        var result: [(date: Date, value: Double)] = []
        for i in (period - 1)..<chartData.count {
            let slice = chartData[(i - period + 1)...i]
            let avg = slice.reduce(0.0) { $0 + $1.price } / Double(period)
            result.append((date: chartData[i].date, value: avg))
        }
        return result
    }
    
    private func stockEMA(_ period: Int) -> [(date: Date, value: Double)] {
        guard chartData.count >= period else { return [] }
        let multiplier = 2.0 / Double(period + 1)
        var ema = chartData.prefix(period).reduce(0.0) { $0 + $1.price } / Double(period)
        var result: [(date: Date, value: Double)] = [(date: chartData[period - 1].date, value: ema)]
        for i in period..<chartData.count {
            ema = (chartData[i].price - ema) * multiplier + ema
            result.append((date: chartData[i].date, value: ema))
        }
        return result
    }
    
    private func stockBB(_ period: Int = 20, mult: Double = 2.0) -> [(date: Date, upper: Double, middle: Double, lower: Double)] {
        guard chartData.count >= period else { return [] }
        var result: [(date: Date, upper: Double, middle: Double, lower: Double)] = []
        for i in (period - 1)..<chartData.count {
            let slice = Array(chartData[(i - period + 1)...i])
            let mean = slice.reduce(0.0) { $0 + $1.price } / Double(period)
            let variance = slice.reduce(0.0) { $0 + pow($1.price - mean, 2) } / Double(period)
            let stdDev = sqrt(variance)
            result.append((date: chartData[i].date, upper: mean + mult * stdDev, middle: mean, lower: mean - mult * stdDev))
        }
        return result
    }
    
    private func stockRSIValues(_ period: Int = 14) -> [Double] {
        let prices = chartData.map(\.price)
        guard prices.count > period else { return Array(repeating: 50, count: prices.count) }
        var rsiValues: [Double] = Array(repeating: 50, count: period)
        var avgGain: Double = 0
        var avgLoss: Double = 0
        for i in 1...period {
            let change = prices[i] - prices[i - 1]
            if change > 0 { avgGain += change } else { avgLoss += abs(change) }
        }
        avgGain /= Double(period)
        avgLoss /= Double(period)
        let firstRS = avgLoss == 0 ? 100.0 : avgGain / avgLoss
        rsiValues.append(100 - (100 / (1 + firstRS)))
        for i in (period + 1)..<prices.count {
            let change = prices[i] - prices[i - 1]
            let gain = change > 0 ? change : 0
            let loss = change < 0 ? abs(change) : 0
            avgGain = (avgGain * Double(period - 1) + gain) / Double(period)
            avgLoss = (avgLoss * Double(period - 1) + loss) / Double(period)
            let rs = avgLoss == 0 ? 100.0 : avgGain / avgLoss
            rsiValues.append(100 - (100 / (1 + rs)))
        }
        return rsiValues
    }
    
    private var stockChartWithCrosshair: some View {
        let minVal = chartData.map(\.price).min() ?? 0
        let maxVal = chartData.map(\.price).max() ?? 100
        let chartColor: Color = (chartData.last?.price ?? 0) >= (chartData.first?.price ?? 0) ? .green : .red
        
        // Compute BB bounds for y-axis scaling
        let bbData = indicators.contains(.bb) ? stockBB() : []
        let bbMin = bbData.map(\.lower).min() ?? minVal
        let bbMax = bbData.map(\.upper).max() ?? maxVal
        let effectiveMin = min(minVal, bbMin)
        let effectiveMax = max(maxVal, bbMax)
        let range = effectiveMax - effectiveMin
        let padding = range * 0.08
        
        // Integrated volume: scale to bottom 22% of chart (matching crypto chart)
        let showVol = indicators.contains(.volume) && chartData.contains(where: { $0.volume > 0 })
        // Use 98th percentile to prevent outlier spikes from crushing normal bars
        let sortedVols = showVol ? chartData.map(\.volume).sorted() : []
        let p98Idx = max(0, Int(Double(sortedVols.count) * 0.98) - 1)
        let volCap = showVol ? max(sortedVols.isEmpty ? 1 : sortedVols[min(p98Idx, sortedVols.count - 1)], 1) : 1.0
        let chartBottom = effectiveMin - padding
        let chartRange = (effectiveMax + padding) - chartBottom
        let volScale = chartRange * 0.22 / max(volCap, 1)
        
        return Chart {
            // ── Integrated Volume Bars (rendered first so they sit behind everything) ──
            if showVol {
                ForEach(Array(chartData.enumerated()), id: \.element.id) { index, point in
                    let isUp = index == 0 || point.price >= chartData[index - 1].price
                    let volH = min(point.volume, volCap * 1.2) * volScale
                    let baseColor = isUp ? Color.green : Color.red
                    BarMark(
                        x: .value("Date", point.date),
                        yStart: .value("VolBase", chartBottom),
                        yEnd: .value("Vol", chartBottom + volH)
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
            
            // ── Bollinger Bands (background, matching crypto chart) ──
            if indicators.contains(.bb) {
                ForEach(Array(bbData.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("Date", point.date), y: .value("BB Upper", point.upper))
                        .foregroundStyle(Color.purple.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1.0, dash: [4, 3]))
                    LineMark(x: .value("Date", point.date), y: .value("BB Lower", point.lower))
                        .foregroundStyle(Color.purple.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1.0, dash: [4, 3]))
                }
                ForEach(Array(bbData.enumerated()), id: \.offset) { _, point in
                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("BB Lower", point.lower),
                        yEnd: .value("BB Upper", point.upper)
                    )
                    .foregroundStyle(Color.purple.opacity(0.08))
                }
            }
            
            // ── SMA (20-period, matching crypto chart line weight) ──
            if indicators.contains(.sma) {
                let smaData = stockSMA(20)
                ForEach(Array(smaData.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("Date", point.date), y: .value("SMA", point.value))
                        .foregroundStyle(Color.orange.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 1.8))
                        .interpolationMethod(.monotone)
                }
            }
            
            // ── EMA (12-period, matching crypto chart line weight) ──
            if indicators.contains(.ema) {
                let emaData = stockEMA(12)
                ForEach(Array(emaData.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("Date", point.date), y: .value("EMA", point.value))
                        .foregroundStyle(Color.cyan.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 1.6))
                        .interpolationMethod(.monotone)
                }
            }
            
            // ── Price Line (bolder, matching crypto chart) ──
            ForEach(chartData) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Price", point.price)
                )
                .foregroundStyle(chartColor.gradient)
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2.2))
                
                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Min", effectiveMin - padding),
                    yEnd: .value("Price", point.price)
                )
                .foregroundStyle(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: chartColor.opacity(0.38), location: 0.0),
                            .init(color: chartColor.opacity(0.22), location: 0.3),
                            .init(color: chartColor.opacity(0.08), location: 0.6),
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
        .chartYScale(domain: (effectiveMin - padding)...(effectiveMax + padding))
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
                        Text(formatCompactCurrency(price))
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
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard let plotAnchor = proxy.plotFrame else { return }
                                let x = value.location.x - geo[plotAnchor].origin.x
                                if let date: Date = proxy.value(atX: x) {
                                    if let closest = chartData.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }) {
                                        if crosshairDate != closest.date {
                                            crosshairDate = closest.date
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
                                crosshairDate = nil
                                crosshairPrice = nil
                            }
                    )
                
                // Premium crosshair tooltip with indicator values
                if showCrosshair, let price = crosshairPrice, let date = crosshairDate, let plotAnchor = proxy.plotFrame {
                    if let xPos = proxy.position(forX: date) {
                        let tooltipBgColors: [Color] = isDark
                            ? [Color(red: 0.12, green: 0.12, blue: 0.14).opacity(0.95),
                               Color(red: 0.06, green: 0.06, blue: 0.08).opacity(0.95)]
                            : [Color.white.opacity(0.98),
                               Color(red: 0.96, green: 0.96, blue: 0.97).opacity(0.98)]
                        let tooltipTextColor: Color = isDark ? .white.opacity(0.8) : .primary.opacity(0.7)
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text(formatCurrency(price))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(DS.Colors.gold)
                            Text(formatChartDate(date))
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(tooltipTextColor)
                            
                            // Indicator values at crosshair position (with colored dots)
                            if indicators.contains(.sma) || indicators.contains(.ema) || (indicators.contains(.volume) && chartData.first(where: { $0.date == date })?.volume ?? 0 > 0) {
                                Divider().background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                                if indicators.contains(.sma) {
                                    let smaVal = stockSMA(20).last(where: { $0.date <= date })?.value
                                    if let v = smaVal {
                                        HStack(spacing: 4) {
                                            Circle().fill(Color.orange).frame(width: 5, height: 5)
                                            Text("SMA₂₀ \(formatCompactCurrency(v))")
                                                .font(.system(size: 9, weight: .medium))
                                                .foregroundColor(.orange)
                                        }
                                    }
                                }
                                if indicators.contains(.ema) {
                                    let emaVal = stockEMA(12).last(where: { $0.date <= date })?.value
                                    if let v = emaVal {
                                        HStack(spacing: 4) {
                                            Circle().fill(Color.cyan).frame(width: 5, height: 5)
                                            Text("EMA₁₂ \(formatCompactCurrency(v))")
                                                .font(.system(size: 9, weight: .medium))
                                                .foregroundColor(.cyan)
                                        }
                                    }
                                }
                                // Volume at crosshair
                                if indicators.contains(.volume),
                                   let volPoint = chartData.first(where: { $0.date == date }),
                                   volPoint.volume > 0 {
                                    HStack(spacing: 4) {
                                        Image(systemName: "chart.bar.fill")
                                            .font(.system(size: 7))
                                            .foregroundColor(DS.Colors.gold.opacity(0.8))
                                        Text(formatStockVolume(volPoint.volume))
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundColor(DS.Colors.gold.opacity(0.8))
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: tooltipBgColors,
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(
                                            LinearGradient(
                                                colors: [DS.Colors.gold.opacity(0.5), DS.Colors.gold.opacity(0.2)],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            ),
                                            lineWidth: 1
                                        )
                                )
                        )
                        .position(x: min(max(xPos + geo[plotAnchor].origin.x, 70), geo.size.width - 70), y: 30)
                    }
                }
            }
        }
        .frame(height: 240)
    }
    
    // MARK: - Indicator Legend (matching crypto chart)
    
    @ViewBuilder
    private var stockIndicatorLegend: some View {
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
    
    // MARK: - RSI Sub-Pane
    
    @ViewBuilder
    private var stockRSIChart: some View {
        let rsiVals = stockRSIValues()
        Chart {
            RuleMark(y: .value("Overbought", 70))
                .foregroundStyle(Color.red.opacity(0.3))
                .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
            RuleMark(y: .value("Oversold", 30))
                .foregroundStyle(Color.green.opacity(0.3))
                .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
            RuleMark(y: .value("Mid", 50))
                .foregroundStyle(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                .lineStyle(StrokeStyle(lineWidth: 0.3))
            
            ForEach(Array(rsiVals.enumerated()), id: \.offset) { index, rsi in
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
    
    private func formatStockVolume(_ v: Double) -> String {
        if v >= 1_000_000_000 { return String(format: "%.1fB", v / 1_000_000_000) }
        if v >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000) }
        if v >= 1_000 { return String(format: "%.0fK", v / 1_000) }
        return String(format: "%.0f", v)
    }
    
    // PERFORMANCE FIX: Cached date formatters
    private static let _intradayDateFmt: DateFormatter = {
        let df = DateFormatter(); df.dateFormat = "MMM d, h:mm a"; return df
    }()
    private static let _dailyDateFmt: DateFormatter = {
        let df = DateFormatter(); df.dateFormat = "MMM d, yyyy"; return df
    }()
    private static let _timestampFmt: DateFormatter = {
        let df = DateFormatter(); df.dateStyle = .short; df.timeStyle = .medium; return df
    }()

    private func formatChartDate(_ date: Date) -> String {
        let formatter = selectedInterval.isIntraday ? Self._intradayDateFmt : Self._dailyDateFmt
        return formatter.string(from: date)
    }
    
    // MARK: - Chart Controls Row
    
    @State private var showTimeframePicker = false
    
    private var chartControlsRow: some View {
        // No ScrollView - fixed width, perfectly fitted (matching coin page layout)
        HStack(spacing: 6) {
            // Chart source segmented toggle - expands to fill remaining width
            ChartSourceSegmentedToggle(selected: $selectedChartType)
            
            // Timeframe dropdown button - styled to match the coin page
            Menu {
                Section("Intraday") {
                    ForEach([StockChartInterval.oneMin, .fiveMin, .fifteenMin, .thirtyMin, .oneHour, .fourHour], id: \.self) { interval in
                        Button {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            selectedInterval = interval
                            Task { await loadChartData() }
                        } label: {
                            HStack {
                                Text(interval.displayName)
                                if selectedInterval == interval {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                Section("Daily & Longer") {
                    ForEach([StockChartInterval.oneDay, .oneWeek, .oneMonth, .threeMonths, .sixMonths, .oneYear, .fiveYears, .all], id: \.self) { interval in
                        Button {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            selectedInterval = interval
                            Task { await loadChartData() }
                        } label: {
                            HStack {
                                Text(interval.displayName)
                                if selectedInterval == interval {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(selectedInterval.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundColor(DS.Adaptive.textPrimary)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(
                    Capsule()
                        .fill(isDark ? DS.Neutral.bg(0.06) : Color(uiColor: .systemGray5))
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isDark ? ctaRimStrokeGradient : LinearGradient(colors: [Color.black.opacity(0.12), Color.black.opacity(0.06)], startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
                )
            }
            .fixedSize(horizontal: true, vertical: false)
            
            // Indicators button - shared component for consistency
            IndicatorsButton(count: indicators.count) {
                showIndicatorMenu = true
            }
            .fixedSize(horizontal: true, vertical: false)
            
            // Alert button - compact icon-only to save space (matching coin page density)
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                showSetAlert = true
            } label: {
                Image(systemName: "bell.badge")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(isDark ? DS.Neutral.bg(0.06) : Color(uiColor: .systemGray5))
                    )
                    .overlay(
                        Circle()
                            .stroke(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }
    
    // MARK: - Info Tabs Section
    
    private var infoTabsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Use shared underline tab picker component
            UnderlineTabPicker(selected: $selectedInfoTab)
            
            // Tab content
            switch selectedInfoTab {
            case .overview:
                stockOverviewCard
            case .news:
                stockNewsCard
            case .analysis:
                stockAnalysisCard
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
    }
    
    private var stockOverviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // AI Insight header
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
            
            HStack(spacing: 8) {
                Text(generateStockOverview())
                    .font(.system(size: 14))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // Quick stats row
            HStack(spacing: 16) {
                if let pe = quote?.trailingPE {
                    quickStatBadge(label: "P/E", value: String(format: "%.1f", pe))
                }
                if let divYield = quote?.dividendYield, divYield > 0 {
                    quickStatBadge(label: "Div Yield", value: String(format: "%.2f%%", divYield * 100))
                }
                if let beta = quote?.beta {
                    quickStatBadge(label: "Beta", value: String(format: "%.2f", beta))
                }
            }
            
            // AI Deep Dive button - prominent CTA
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                showDeepDive = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                    Text("AI Deep Dive")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(DS.Colors.gold)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(DS.Colors.gold.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(DS.Colors.gold.opacity(0.25), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            
            // Market status row
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                    let isOpen = isMarketCurrentlyOpen()
                    Text(isOpen ? "Market Open" : "Market Closed")
                        .font(.caption)
                    Circle()
                        .fill(isOpen ? Color.green : Color.gray)
                        .frame(width: 6, height: 6)
                }
                .foregroundColor(DS.Adaptive.textTertiary)
                
                Spacer()
                
                // Last updated indicator
                if let _ = quote {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 5, height: 5)
                        Text("Live")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                }
            }
        }
        .padding(.top, 8)
    }
    
    private func quickStatBadge(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(DS.Adaptive.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                // LIGHT MODE FIX: Adaptive fill
                .fill(isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
        )
    }
    
    private var stockNewsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Category chips
            stockNewsCategoryChips
            
            if newsVM.isLoading {
                // Shimmer loading cards matching ArticleRow dimensions
                // LIGHT MODE FIX: Adaptive shimmer placeholder colors
                ForEach(0..<3, id: \.self) { _ in
                    HStack(alignment: .center, spacing: 14) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
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
                // Empty state with links
                VStack(spacing: 10) {
                    Text("No headlines right now.")
                        .font(.footnote)
                        // LIGHT MODE FIX: Adaptive text
                        .foregroundColor(DS.Adaptive.textSecondary)
                    stockNewsLinks
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                // Real ArticleRow design matching CoinDetailView
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
                
                // "More on Google News" link
                HStack {
                    Spacer()
                    if let url = newsVM.moreURL(for: "\(displayName) \(ticker)", category: selectedNewsCategory) {
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
        .padding(.top, 8)
    }
    
    private var stockNewsCategoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(StockNewsCategory.allCases, id: \.self) { cat in
                    stockNewsCategoryButton(for: cat)
                }
            }
            .padding(.horizontal, 2)
        }
    }
    
    private func stockNewsCategoryButton(for cat: StockNewsCategory) -> some View {
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
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedNewsCategory = cat
            }
            newsVM.fetch(query: "\(displayName) \(ticker)", category: cat)
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
    
    private func stockNewsRow(index: Int) -> some View {
        let headline = sampleNewsHeadline(for: index, category: selectedNewsCategory)
        let source = newsSource(for: index)
        let timeAgo = newsTimeAgo(for: index)
        
        return Button {
            if let url = URL(string: newsURL(for: index)) {
                #if os(iOS)
                UIApplication.shared.open(url)
                #endif
            }
        } label: {
            HStack(alignment: .center, spacing: 14) {
                // Thumbnail placeholder
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [assetType.color.opacity(0.3), assetType.color.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 56)
                    .overlay(
                        Image(systemName: "newspaper.fill")
                            .font(.system(size: 20))
                            .foregroundColor(assetType.color.opacity(0.6))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            // LIGHT MODE FIX: Adaptive stroke
                            .stroke(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
                    )
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(headline)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    HStack(spacing: 8) {
                        // Source pill - LIGHT MODE FIX: Adaptive badge color
                        Text(source)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(adaptiveBadgeColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(adaptiveBadgeColor.opacity(0.12))
                            )
                        
                        Text(timeAgo)
                            .font(.caption2)
                            .foregroundColor(DS.Adaptive.textTertiary)
                            .monospacedDigit()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    // LIGHT MODE FIX: Adaptive fill
                    .fill(isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var stockNewsLinks: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .opacity(0.5)
            
            Text("External Sources")
                .font(.caption.weight(.semibold))
                .foregroundColor(DS.Adaptive.textTertiary)
            
            HStack(spacing: 12) {
                newsLinkButton(title: "Yahoo Finance", url: "https://finance.yahoo.com/quote/\(ticker)/news", icon: "link")
                newsLinkButton(title: "Google News", url: "https://news.google.com/search?q=\(ticker)%20stock", icon: "magnifyingglass")
                newsLinkButton(title: "SEC Filings", url: "https://www.sec.gov/cgi-bin/browse-edgar?action=getcompany&company=\(ticker)&type=&dateb=&owner=include&count=40", icon: "doc.text")
            }
        }
        .padding(.top, 4)
    }
    
    private func newsLinkButton(title: String, url: String, icon: String) -> some View {
        Link(destination: URL(string: url) ?? URL(fileURLWithPath: "/")) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .foregroundColor(DS.Colors.gold)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(DS.Colors.gold.opacity(0.1))
            )
        }
    }
    
    private func sampleNewsHeadline(for index: Int, category: StockNewsCategory) -> String {
        switch category {
        case .top:
            let headlines = [
                "\(displayName) shares move on strong trading volume",
                "\(ticker) stock receives attention from institutional investors",
                "Market watch: \(displayName) trading update"
            ]
            return headlines[index % headlines.count]
        case .earnings:
            let headlines = [
                "\(displayName) Q4 earnings beat estimates, revenue up YoY",
                "Analysts react to \(ticker) quarterly results",
                "\(displayName) provides updated guidance for fiscal year"
            ]
            return headlines[index % headlines.count]
        case .analysis:
            let headlines = [
                "Wall Street analyst raises \(ticker) price target",
                "\(displayName) receives updated rating from major firm",
                "Technical analysis: \(ticker) approaching key resistance level"
            ]
            return headlines[index % headlines.count]
        case .market:
            let headlines = [
                "\(ticker) sees increased options activity ahead of catalyst",
                "\(displayName) trading volume spikes amid sector rotation",
                "Market momentum: \(ticker) outperforms broader market"
            ]
            return headlines[index % headlines.count]
        case .sec:
            let headlines = [
                "\(displayName) files quarterly report with SEC",
                "Insider transactions reported for \(ticker)",
                "\(displayName) announces proxy filing ahead of shareholder meeting"
            ]
            return headlines[index % headlines.count]
        }
    }
    
    private func newsSource(for index: Int) -> String {
        let sources = ["Yahoo Finance", "Reuters", "Bloomberg", "MarketWatch", "Seeking Alpha"]
        return sources[index % sources.count]
    }
    
    private func newsTimeAgo(for index: Int) -> String {
        let times = ["2h ago", "4h ago", "6h ago", "1d ago", "2d ago"]
        return times[index % times.count]
    }
    
    private func newsURL(for index: Int) -> String {
        return "https://finance.yahoo.com/quote/\(ticker)/news"
    }
    
    private var stockAnalysisCard: some View {
        let summary = techVM.summary
        let totalSignals = summary.buyCount + summary.neutralCount + summary.sellCount
        let hasTechnicals = totalSignals > 0
        
        return VStack(alignment: .leading, spacing: 12) {
            // Technical indicator signals summary (real data from TechnicalsEngine)
            HStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text("Buy")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text("\(summary.buyCount)")
                        .font(.headline.weight(.bold))
                        .foregroundColor(.green)
                }
                
                VStack(spacing: 4) {
                    Text("Neutral")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text("\(summary.neutralCount)")
                        .font(.headline.weight(.bold))
                        .foregroundColor(.orange)
                }
                
                VStack(spacing: 4) {
                    Text("Sell")
                        .font(.caption)
                        .foregroundColor(.red)
                    Text("\(summary.sellCount)")
                        .font(.headline.weight(.bold))
                        .foregroundColor(.red)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Verdict")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                    Text(summary.verdict.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(
                            summary.buyCount > summary.sellCount ? .green :
                            summary.sellCount > summary.buyCount ? .red : .orange
                        )
                }
            }
            
            // Signal distribution bar
            if hasTechnicals {
                GeometryReader { geo in
                    let buyFraction = CGFloat(summary.buyCount) / CGFloat(totalSignals)
                    let neutralFraction = CGFloat(summary.neutralCount) / CGFloat(totalSignals)
                    let sellFraction = CGFloat(summary.sellCount) / CGFloat(totalSignals)
                    HStack(spacing: 2) {
                        if buyFraction > 0 {
                            Rectangle()
                                .fill(Color.green)
                                .frame(width: max(geo.size.width * buyFraction, 2))
                        }
                        if neutralFraction > 0 {
                            Rectangle()
                                .fill(Color.orange)
                                .frame(width: max(geo.size.width * neutralFraction, 2))
                        }
                        if sellFraction > 0 {
                            Rectangle()
                                .fill(Color.red)
                                .frame(width: max(geo.size.width * sellFraction, 2))
                        }
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 8)
                
                Text("Based on \(totalSignals) technical indicators")
                    .font(.caption2)
                    .foregroundColor(DS.Adaptive.textTertiary)
            } else {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.6)
                    Text("Analyzing indicators...")
                        .font(.caption2)
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
            }
            
            // Key levels from technicals
            if let support = calculateSupport(), let resistance = calculateResistance() {
                Divider().background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Support")
                            .font(.caption2)
                            .foregroundColor(DS.Adaptive.textTertiary)
                        Text(formatCurrency(support))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.green)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Resistance")
                            .font(.caption2)
                            .foregroundColor(DS.Adaptive.textTertiary)
                        Text(formatCurrency(resistance))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.red)
                    }
                    Spacer()
                }
            }
        }
        .padding(.top, 8)
    }
    
    // MARK: - AI Trading Signal Section
    
    @ViewBuilder
    private var aiTradingSignalSection: some View {
        AITradingSignalCard(
            symbol: ticker.uppercased(),
            price: displayPrice,
            sparkline: chartData.map(\.price),
            change24h: displayChange,
            signal: tradingSignal,
            isLoading: isGeneratingSignal
        )
        .onChange(of: techVM.summary.indicators) { _, _ in
            scheduleDebouncedSignalGenerationForIndicators()
        }
        .onChange(of: displayPrice) { _, _ in
            scheduleDebouncedSignalGenerationForMarketInputs()
        }
        .onChange(of: displayChange) { _, _ in
            scheduleDebouncedSignalGenerationForMarketInputs()
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
        let priceDeltaRatio = abs(displayPrice - lastPrice) / lastPrice
        let changeDelta = abs(displayChange - lastChange24h)
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
    
    // MARK: - Key Levels Section
    
    private var keyLevelsSection: some View {
        let support = calculateSupport()
        let resistance = calculateResistance()
        
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                GoldHeaderGlyph(systemName: "ruler")
                
                Text("Key Levels")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Spacer()
            }
            
            // Price ladder visualization
            VStack(spacing: 0) {
                // Resistance
                if let resistance = resistance {
                    keyLevelRow(
                        label: "Resistance",
                        price: resistance,
                        color: .red,
                        icon: "arrow.up",
                        distancePercent: ((resistance - displayPrice) / displayPrice) * 100
                    )
                }
                
                // Current price
                HStack {
                    Text("Current")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    
                    Spacer()
                    
                    Text(formatCurrency(displayPrice))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(DS.Colors.gold)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(DS.Colors.gold.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(DS.Colors.gold.opacity(0.3), lineWidth: 1)
                )
                .padding(.vertical, 4)
                
                // Support
                if let support = support {
                    keyLevelRow(
                        label: "Support",
                        price: support,
                        color: .green,
                        icon: "arrow.down",
                        distancePercent: ((support - displayPrice) / displayPrice) * 100
                    )
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
    
    private func keyLevelRow(label: String, price: Double, color: Color, icon: String, distancePercent: Double) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
                Text(formatCurrency(price))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
            }
            
            Spacer()
            
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                Text(String(format: "%.1f%%", abs(distancePercent)))
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(color)
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Technicals Section
    
    private var technicalsSection: some View {
        let summary = techVM.summary
        let w = UIScreen.main.bounds.width
        let onSelectSource: (TechnicalsViewModel.TechnicalsSourcePreference) -> Void = { pref in
            techVM.setPreferredSource(pref)
            let closes = chartData.map { $0.price }
            techVM.refresh(
                symbol: ticker,
                interval: stockIntervalToChartInterval(selectedInterval),
                currentPrice: displayPrice,
                sparkline: closes,
                forceBypassCache: true
            )
        }
        
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
                } else {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                        .accessibilityLabel("Live")
                }
                
                Text(selectedInterval.displayName)
                    .font(.caption2.weight(.semibold))
                    .fontWidth(.condensed)
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                    .background(DS.Adaptive.cardBackground)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(DS.Adaptive.stroke, lineWidth: 0.6))
                
                Spacer()
                
                // More details link (matching coin detail)
                NavigationLink {
                    TechnicalsDetailNativeView(
                        symbol: ticker,
                        tvSymbol: tvStockSymbol,
                        tvTheme: isDark ? "Dark" : "Light",
                        currentPrice: displayPrice
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
            
            // Gauge with proper sizing
            let gaugeHeight: CGFloat = (w < 390 ? 130 : (w < 430 ? 145 : 155))
            let gaugeLineWidth: CGFloat = (w < 390 ? 6.0 : 7.0)
            
            if chartData.count >= 8 {
                TechnicalsGaugeView(
                    summary: summary,
                    timeframeLabel: selectedInterval.displayName,
                    lineWidth: gaugeLineWidth,
                    preferredHeight: gaugeHeight,
                    showArcLabels: true,
                    showEndCaps: true,
                    showVerdictLine: true
                )
                .padding(.horizontal, 4)
                .padding(.top, 4)
                .padding(.bottom, 2)
                
                // Summary + source menu without dead spacer zones
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        techCountPill(title: "Sell", value: summary.sellCount, color: .red)
                        techCountPill(title: "Neutral", value: summary.neutralCount, color: .yellow)
                        techCountPill(title: "Buy", value: summary.buyCount, color: .green)
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
                            techCountPill(title: "Sell", value: summary.sellCount, color: .red)
                            techCountPill(title: "Neutral", value: summary.neutralCount, color: .yellow)
                            techCountPill(title: "Buy", value: summary.buyCount, color: .green)
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
            } else {
                // Loading/empty state
                VStack(spacing: 8) {
                    if techVM.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text("Insufficient data for technicals")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                }
                .frame(height: 100)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
                
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
    }
    
    private func techCountPill(title: String, value: Int, color: Color) -> some View {
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
    
    // MARK: - Key Stats Section
    
    /// Check if quote data is fresh (within 2 minutes)
    private var isStatsFresh: Bool {
        guard let lastUpdate = lastQuoteUpdate else { return false }
        return Date().timeIntervalSince(lastUpdate) < 120 // 2 minutes
    }
    
    /// Connection mode for display
    private var connectionMode: String {
        if isLoadingQuote { return "Updating..." }
        if quote != nil && isStatsFresh { return "Live" }
        if quote != nil { return "Cached" }
        return "Offline"
    }
    
    private var connectionColor: Color {
        if isLoadingQuote { return .orange }
        if quote != nil && isStatsFresh { return .green }
        if quote != nil { return .orange }
        return .red
    }
    
    private var keyStatsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                GoldHeaderGlyph(systemName: "chart.bar.doc.horizontal")
                
                Text("Stock Data")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Spacer()
                
                // Connection status badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(connectionColor)
                        .frame(width: 5, height: 5)
                    Text(connectionMode)
                        .font(.system(size: 10, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(connectionColor.opacity(0.12))
                )
                .foregroundColor(connectionColor)
                
                // Market status badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(isMarketCurrentlyOpen() ? Color.green : Color.orange)
                        .frame(width: 5, height: 5)
                    Text(isMarketCurrentlyOpen() ? "Open" : "Closed")
                        .font(.system(size: 10, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill((isMarketCurrentlyOpen() ? Color.green : Color.orange).opacity(0.12))
                )
                .foregroundColor(isMarketCurrentlyOpen() ? Color.green : Color.orange)
            }
            .contentShape(Rectangle())
            .onLongPressGesture {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                showDiagnostics = true
            }
            
            // Stats grid with shimmer loading
            if isLoadingQuote && quote == nil {
                // Shimmer loading state
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(0..<8, id: \.self) { _ in
                        statRowShimmer
                    }
                }
            } else {
                // Actual stats
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    statRow(label: "Market Cap", value: quote.flatMap(\.marketCap).map(formatLargeNumber) ?? "--")
                    statRow(label: "Volume", value: quote.flatMap(\.regularMarketVolume).map { formatLargeNumber(Double($0)) } ?? "--")
                    statRow(label: "Open", value: quote.flatMap(\.regularMarketOpen).map(formatCurrency) ?? "--")
                    statRow(label: "Prev Close", value: quote.flatMap(\.regularMarketPreviousClose).map(formatCurrency) ?? "--")
                    statRow(label: "Day High", value: quote.flatMap(\.regularMarketDayHigh).map(formatCurrency) ?? "--")
                    statRow(label: "Day Low", value: quote.flatMap(\.regularMarketDayLow).map(formatCurrency) ?? "--")
                    statRow(label: "52W High", value: quote.flatMap(\.fiftyTwoWeekHigh).map(formatCurrency) ?? "--")
                    statRow(label: "52W Low", value: quote.flatMap(\.fiftyTwoWeekLow).map(formatCurrency) ?? "--")
                }
                
                // Additional metrics
                if quote?.trailingPE != nil || quote?.dividendYield != nil {
                    Rectangle()
                        .fill(DS.Adaptive.divider)
                        .frame(height: 1)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        if let pe = quote?.trailingPE {
                            statRow(label: "P/E Ratio", value: String(format: "%.2f", pe))
                        }
                        if let eps = quote?.epsTrailingTwelveMonths {
                            statRow(label: "EPS (TTM)", value: formatCurrency(eps))
                        }
                        if let divYield = quote?.dividendYield, divYield > 0 {
                            statRow(label: "Div Yield", value: String(format: "%.2f%%", divYield * 100))
                        }
                        if let beta = quote?.beta {
                            statRow(label: "Beta", value: String(format: "%.2f", beta))
                        }
                    }
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
    
    private var statRowShimmer: some View {
        HStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 60, height: 12)
                .shimmer()
            Spacer()
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 50, height: 13)
                .shimmer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                // LIGHT MODE FIX: Adaptive fill
                .fill(isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
        )
    }
    
    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(DS.Adaptive.textTertiary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DS.Adaptive.textPrimary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                // LIGHT MODE FIX: Adaptive fill
                .fill(isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
        )
    }
    
    // MARK: - About Section
    
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                GoldHeaderGlyph(systemName: "info.circle")
                
                Text("About \(displayName)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
            }
            
            Text(assetType == .etf
                 ? "This is an Exchange-Traded Fund (ETF) that trades on stock exchanges. ETFs hold diversified assets and trade throughout the day like stocks."
                 : assetType == .commodity
                 ? "This is a commodity futures contract. Commodities are raw materials or primary agricultural products that can be bought and sold. Futures prices reflect the expected future value of the commodity."
                 : "Track the performance of \(displayName) (\(ticker)) in your portfolio. CryptoSage provides real-time price updates for stocks alongside your cryptocurrency holdings.")
                .font(.system(size: 13))
                .foregroundColor(DS.Adaptive.textSecondary)
                .lineSpacing(4)
            
            // External links
            HStack(spacing: 16) {
                Link(destination: URL(string: "https://finance.yahoo.com/quote/\(ticker)") ?? URL(fileURLWithPath: "/")) {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                        Text("Yahoo Finance")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundColor(DS.Colors.gold)
                }
                
                Link(destination: URL(string: "https://www.google.com/finance/quote/\(ticker):NASDAQ") ?? URL(fileURLWithPath: "/")) {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                        Text("Google Finance")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundColor(DS.Colors.gold)
                }
            }
            .padding(.top, 4)
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
    
    // MARK: - Disclaimer
    
    private var disclaimerSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.caption)
            Text("Stock data provided by Yahoo Finance. Prices may be delayed. This is not financial advice.")
                .font(.caption2)
        }
        .foregroundColor(DS.Adaptive.textTertiary)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(DS.Adaptive.chipBackground)
        )
    }
    
    // MARK: - Alert Sheet
    
    private var stockAlertSheet: some View {
        NavigationView {
            VStack(spacing: 20) {
                StockImageView(ticker: ticker, assetType: assetType, size: 60)
                
                Text("Set Price Alert for \(ticker)")
                    .font(.headline)
                
                Text("Price alerts for stocks coming soon!")
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .multilineTextAlignment(.center)
                
                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSetAlert = false
                    } label: {
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
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
    
    // MARK: - Data Loading
    
    private func loadStockData() async {
        await MainActor.run { isLoadingQuote = true }
        
        // Check if this is a precious metal from Coinbase - use Coinbase API instead of Yahoo Finance
        if assetType == .commodity && PreciousMetalsHelper.isPreciousMetal(ticker) {
            // Fetch precious metal price from Coinbase
            if let price = await CoinbaseService.shared.fetchSpotPrice(coin: ticker) {
                // Also try to get 24h stats for change percentage
                let stats = await CoinbaseService.shared.fetch24hStats(coin: ticker)
                
                await MainActor.run {
                    // Create a mock StockQuote from Coinbase data
                    let coinbaseQuote = StockQuote(
                        symbol: ticker,
                        shortName: PreciousMetalsHelper.displayName(for: ticker),
                        longName: PreciousMetalsHelper.displayName(for: ticker),
                        regularMarketPrice: price,
                        regularMarketChange: stats?.change24h ?? 0,
                        regularMarketChangePercent: stats?.change24h ?? 0,
                        regularMarketPreviousClose: stats?.openPrice,
                        regularMarketOpen: stats?.openPrice,
                        regularMarketDayHigh: stats?.highPrice,
                        regularMarketDayLow: stats?.lowPrice,
                        regularMarketVolume: Int(stats?.volume ?? 0),
                        marketCap: nil,
                        fiftyTwoWeekHigh: nil,
                        fiftyTwoWeekLow: nil,
                        currency: "USD",
                        exchange: "Coinbase",
                        quoteType: "COMMODITY",
                        timestamp: Date(),
                        trailingPE: nil,
                        forwardPE: nil,
                        epsTrailingTwelveMonths: nil,
                        dividendYield: nil,
                        beta: nil,
                        priceToBook: nil,
                        fiftyDayAverage: nil,
                        twoHundredDayAverage: nil
                    )
                    self.quote = coinbaseQuote
                    self.isLoadingQuote = false
                    self.lastQuoteUpdate = Date()
                    
                    #if DEBUG
                    print("💰 [StockDetailView] Loaded precious metal quote from Coinbase: \(ticker) = $\(price)")
                    #endif
                }
            } else {
                await MainActor.run { isLoadingQuote = false }
            }
        } else {
            // Regular stocks/ETFs - use Yahoo Finance
            if let fetchedQuote = await StockPriceService.shared.fetchQuote(ticker: ticker) {
                await MainActor.run {
                    quote = fetchedQuote
                    isLoadingQuote = false
                    lastQuoteUpdate = Date()
                }
            } else {
                await MainActor.run { isLoadingQuote = false }
            }
        }
        
        await loadChartData()
    }
    
    private func loadChartData() async {
        await MainActor.run { isLoadingChart = true }
        
        // For precious metals: try Yahoo Finance with the futures symbol for real historical data
        // Falls back to mock data only if Yahoo Finance fails
        if assetType == .commodity && PreciousMetalsHelper.isPreciousMetal(ticker) {
            // Map Coinbase precious metal symbols to Yahoo Finance futures symbols
            let yahooSymbol: String
            switch ticker.uppercased() {
            case "XAU", "GOLD", "GLD": yahooSymbol = "GC=F"
            case "XAG", "SILVER", "SLV": yahooSymbol = "SI=F"
            case "XPT", "PLATINUM", "PLT", "PLAT": yahooSymbol = "PL=F"
            case "XPD", "PALLADIUM", "PAL": yahooSymbol = "PA=F"
            case "XCU", "COPPER", "CU", "COPR": yahooSymbol = "HG=F"
            default: yahooSymbol = "\(ticker)=F"
            }
            
            let historicalData = await StockPriceService.shared.fetchHistoricalData(
                ticker: yahooSymbol,
                rangeString: selectedInterval.yahooRange,
                intervalString: selectedInterval.yahooInterval
            )
            
            let points: [StockChartPoint]
            if historicalData.count >= 5 {
                points = historicalData.map { StockChartPoint(date: $0.date, price: $0.close, volume: Double($0.volume)) }
            } else {
                // Only fall back to mock data if Yahoo Finance fails
                points = generateMockChartData(for: selectedInterval)
            }
            
            await MainActor.run {
                chartData = points
                isLoadingChart = false
                
                // Refresh technicals with real chart data
                let closes = points.map { $0.price }
                if closes.count >= 8 {
                    techVM.refresh(
                        symbol: ticker,
                        interval: stockIntervalToChartInterval(selectedInterval),
                        currentPrice: displayPrice,
                        sparkline: closes
                    )
                }
            }
            return
        }
        
        // Use the new flexible API with range and interval from StockChartInterval
        let historicalData = await StockPriceService.shared.fetchHistoricalData(
            ticker: ticker,
            rangeString: selectedInterval.yahooRange,
            intervalString: selectedInterval.yahooInterval
        )
        
        let points: [StockChartPoint]
        if historicalData.isEmpty {
            points = generateMockChartData(for: selectedInterval)
        } else {
            points = historicalData.map { StockChartPoint(date: $0.date, price: $0.close, volume: Double($0.volume)) }
        }
        
        await MainActor.run {
            chartData = points
            isLoadingChart = false
            
            // Refresh technicals with chart data
            let closes = points.map { $0.price }
            if closes.count >= 8 {
                techVM.refresh(
                    symbol: ticker,
                    interval: stockIntervalToChartInterval(selectedInterval),
                    currentPrice: displayPrice,
                    sparkline: closes
                )
            }
        }
    }
    
    // Convert StockChartInterval to ChartInterval for technicals
    private func stockIntervalToChartInterval(_ interval: StockChartInterval) -> ChartInterval {
        switch interval {
        case .oneMin: return .oneMin
        case .fiveMin: return .fiveMin
        case .fifteenMin: return .fifteenMin
        case .thirtyMin: return .thirtyMin
        case .oneHour: return .oneHour
        case .fourHour: return .fourHour
        case .oneDay: return .oneDay
        case .oneWeek: return .oneWeek
        case .oneMonth: return .oneMonth
        case .threeMonths: return .threeMonth
        case .sixMonths: return .sixMonth
        case .oneYear: return .oneYear
        case .fiveYears: return .threeYear
        case .all: return .all
        }
    }

    @MainActor
    private func generateTradingSignal() async {
        guard !isGeneratingSignal else { return }
        isGeneratingSignal = true
        lastSignalInputPrice = displayPrice
        lastSignalInputChange24h = displayChange
        lastSignalGeneratedAt = Date()
        
        // Use AITradingSignalService: Firebase/DeepSeek first, local fallback
        let cleanTicker = ticker.uppercased()
        let signal = await AITradingSignalService.shared.fetchSignal(
            coinId: signalAssetKey,
            symbol: cleanTicker,
            price: displayPrice,
            change24h: displayChange,
            change7d: nil,
            sparkline: chartData.map(\.price),
            techVM: techVM,
            fearGreedValue: nil // Crypto-specific - not applicable to stocks
        )
        tradingSignal = signal
        
        isGeneratingSignal = false
    }
    
    private func calculateSupport() -> Double? {
        guard !chartData.isEmpty else { return nil }
        let prices = chartData.map(\.price)
        let minPrice = prices.min() ?? displayPrice
        // Support is typically around recent lows
        return minPrice * 0.98
    }
    
    private func calculateResistance() -> Double? {
        guard !chartData.isEmpty else { return nil }
        let prices = chartData.map(\.price)
        let maxPrice = prices.max() ?? displayPrice
        // Resistance is typically around recent highs
        return maxPrice * 1.02
    }
    
    private func generateStockOverview() -> String {
        // Use Firebase AI insight if available
        if let insight = aiInsight {
            return insight.insightText
        }
        
        // Fallback: generate locally while Firebase loads
        var parts: [String] = []
        
        if displayChange >= 0 {
            parts.append("\(displayName) is up \(String(format: "%.2f", displayChange))% today.")
        } else {
            parts.append("\(displayName) is down \(String(format: "%.2f", abs(displayChange)))% today.")
        }
        
        if let pe = quote?.trailingPE {
            if pe < 20 {
                parts.append("With a P/E of \(String(format: "%.1f", pe)), it trades at a reasonable valuation.")
            } else if pe > 35 {
                parts.append("Its P/E of \(String(format: "%.1f", pe)) reflects high growth expectations.")
            }
        }
        
        if let divYield = quote?.dividendYield, divYield > 0.02 {
            parts.append("Offers a \(String(format: "%.1f", divYield * 100))% dividend yield.")
        }
        
        return parts.joined(separator: " ")
    }
    
    /// Load AI insight via Firebase (shared across all users, cached server-side for 2 hours)
    private func loadAIInsight() {
        let prefix = assetType == .commodity ? "COMMODITY" : "STOCK"
        let cacheKey = "\(prefix)_\(ticker.uppercased())"
        
        // Check for any cached insight first
        if let cached = CoinAIInsightService.shared.getAnyCachedInsight(for: cacheKey) {
            aiInsight = cached
            if cached.isFresh { return }
        }
        
        guard !isLoadingInsight else { return }
        isLoadingInsight = true
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            let price = displayPrice
            let change = displayChange
            let coinIdPrefix = assetType == .commodity ? "commodity" : "stock"
            let cleanTicker = ticker.replacingOccurrences(of: "=", with: "")
            
            do {
                let response = try await FirebaseService.shared.getCoinInsight(
                    coinId: "\(coinIdPrefix)-\(cleanTicker.lowercased())",
                    coinName: displayName,
                    symbol: cleanTicker,
                    price: price,
                    change24h: change,
                    change7d: nil,
                    marketCap: quote?.marketCap,
                    volume24h: quote?.regularMarketVolume.map { Double($0) }
                )
                
                let insight = CoinAIInsight(
                    symbol: cacheKey,
                    insightText: response.content,
                    price: price,
                    change24h: change
                )
                
                CoinAIInsightService.shared.cacheInsight(insight, for: cacheKey)
                aiInsight = insight
            } catch {
                #if DEBUG
                print("[StockDetail] Firebase AI insight error: \(error.localizedDescription)")
                #endif
                // Keep using local fallback
            }
            isLoadingInsight = false
        }
    }
    
    private func generateMockChartData(for interval: StockChartInterval) -> [StockChartPoint] {
        let currentPrice = displayPrice > 0 ? displayPrice : 100
        let calendar = Calendar.current
        let now = Date()
        
        let pointCount: Int
        let dateIncrement: (Int) -> Date
        
        switch interval {
        case .oneMin:
            pointCount = 60
            dateIncrement = { calendar.date(byAdding: .minute, value: -$0, to: now)! }
        case .fiveMin:
            pointCount = 60
            dateIncrement = { calendar.date(byAdding: .minute, value: -($0 * 5), to: now)! }
        case .fifteenMin:
            pointCount = 48
            dateIncrement = { calendar.date(byAdding: .minute, value: -($0 * 15), to: now)! }
        case .thirtyMin:
            pointCount = 48
            dateIncrement = { calendar.date(byAdding: .minute, value: -($0 * 30), to: now)! }
        case .oneHour:
            pointCount = 24
            dateIncrement = { calendar.date(byAdding: .hour, value: -$0, to: now)! }
        case .fourHour:
            pointCount = 42
            dateIncrement = { calendar.date(byAdding: .hour, value: -($0 * 4), to: now)! }
        case .oneDay:
            pointCount = 78
            dateIncrement = { calendar.date(byAdding: .minute, value: -($0 * 5), to: now)! }
        case .oneWeek:
            pointCount = 35
            dateIncrement = { calendar.date(byAdding: .hour, value: -$0, to: now)! }
        case .oneMonth:
            pointCount = 22
            dateIncrement = { calendar.date(byAdding: .day, value: -$0, to: now)! }
        case .threeMonths:
            pointCount = 65
            dateIncrement = { calendar.date(byAdding: .day, value: -$0, to: now)! }
        case .sixMonths:
            pointCount = 130
            dateIncrement = { calendar.date(byAdding: .day, value: -$0, to: now)! }
        case .oneYear:
            pointCount = 252
            dateIncrement = { calendar.date(byAdding: .day, value: -$0, to: now)! }
        case .fiveYears:
            pointCount = 60
            dateIncrement = { calendar.date(byAdding: .month, value: -$0, to: now)! }
        case .all:
            pointCount = 120
            dateIncrement = { calendar.date(byAdding: .month, value: -$0, to: now)! }
        }
        
        var points: [StockChartPoint] = []
        var price = currentPrice
        let volatility = currentPrice * 0.015
        
        for i in (0..<pointCount).reversed() {
            let date = dateIncrement(i)
            let change = Double.random(in: -volatility...volatility)
            price = max(price * 0.7, min(price * 1.3, price + change))
            points.append(StockChartPoint(date: date, price: price))
        }
        
        if !points.isEmpty {
            points[points.count - 1] = StockChartPoint(date: now, price: currentPrice)
        }
        
        return points.sorted { $0.date < $1.date }
    }
    
    // MARK: - Helpers
    
    // PERFORMANCE FIX: Cached currency formatters
    private static let _currency2: NumberFormatter = {
        let nf = NumberFormatter(); nf.numberStyle = .currency
        nf.currencyCode = CurrencyManager.currencyCode; nf.maximumFractionDigits = 2; return nf
    }()
    private static let _currency4: NumberFormatter = {
        let nf = NumberFormatter(); nf.numberStyle = .currency
        nf.currencyCode = CurrencyManager.currencyCode; nf.maximumFractionDigits = 4; return nf
    }()
    private func formatCurrency(_ value: Double) -> String {
        let formatter = value >= 1 ? Self._currency2 : Self._currency4
        return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
    
    private func formatCompactCurrency(_ value: Double) -> String {
        if value >= 1000 {
            return "$\(Int(value / 1000))K"
        }
        return formatCurrency(value)
    }
    
    private func formatChangePercent(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", value))%"
    }
    
    private func formatLargeNumber(_ value: Double) -> String {
        if value >= 1_000_000_000_000 {
            return String(format: "$%.2fT", value / 1_000_000_000_000)
        } else if value >= 1_000_000_000 {
            return String(format: "$%.2fB", value / 1_000_000_000)
        } else if value >= 1_000_000 {
            return String(format: "$%.2fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "$%.2fK", value / 1_000)
        }
        return formatCurrency(value)
    }
    
    private func isMarketCurrentlyOpen() -> Bool {
        let calendar = Calendar.current
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)
        
        if weekday == 1 || weekday == 7 { return false }
        
        guard let eastern = TimeZone(identifier: "America/New_York") else { return false }
        let components = calendar.dateComponents(in: eastern, from: now)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        
        let marketOpen = hour > 9 || (hour == 9 && minute >= 30)
        let marketClose = hour < 16
        
        return marketOpen && marketClose
    }
    
    private func shareStock() {
        let shareText = """
        Check out \(displayName) (\(ticker)) on CryptoSage!
        Current Price: \(formatCurrency(displayPrice))
        Change: \(formatChangePercent(displayChange))
        """
        
        #if os(iOS)
        let activityVC = UIActivityViewController(
            activityItems: [shareText],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
        #endif
    }
}

// MARK: - Stock Chart Point

struct StockChartPoint: Identifiable {
    let id = UUID()
    let date: Date
    let price: Double
    var volume: Double = 0
}

// MARK: - Stock Deep Dive Sheet

struct StockDeepDiveSheet: View {
    let ticker: String
    let companyName: String
    let price: Double
    let change24h: Double
    let chartData: [StockChartPoint]
    
    @State private var aiAnalysis: String = ""
    @State private var isLoading: Bool = false
    @State private var error: String? = nil
    @State private var cardsAppeared: Bool = false
    @State private var showCopiedToast: Bool = false
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    
    private var sparkline: [Double] { chartData.map { $0.price } }
    private var changeColor: Color { change24h >= 0 ? .green : .red }
    
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
    
    private var hasAIContent: Bool { !aiAnalysis.isEmpty }
    
    private var shareableText: String {
        "\(ticker) (\(companyName)) AI Deep Dive\n\n\(aiAnalysis)"
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 0) {
                        // Hero header
                        stockHero
                            .modifier(StockDeepDiveCardAppear(appeared: cardsAppeared, delay: 0))
                        
                        VStack(alignment: .leading, spacing: 14) {
                            stockTechnicals
                                .modifier(StockDeepDiveCardAppear(appeared: cardsAppeared, delay: 0.05))
                            stockContext
                                .modifier(StockDeepDiveCardAppear(appeared: cardsAppeared, delay: 0.1))
                            stockAISection
                                .modifier(StockDeepDiveCardAppear(appeared: cardsAppeared, delay: 0.15))
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
                            UIPasteboard.general.string = aiAnalysis
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
    private var stockHero: some View {
        let hi = sparkline.max() ?? price
        let lo = sparkline.min() ?? price
        let range = hi - lo
        let pos = max(0, min(1, range > 0 ? (price - lo) / range : 0.5))
        
        return VStack(spacing: 0) {
            VStack(spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ticker)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        Text(companyName)
                            .font(.system(size: 12))
                            .foregroundColor(DS.Adaptive.textSecondary)
                            .lineLimit(1)
                        Text(currency(price))
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
                
                // Mini sparkline
                if sparkline.count > 5 {
                    SparklineView(
                        data: sparkline,
                        isPositive: change24h >= 0,
                        overrideColor: changeColor,
                        height: 50,
                        lineWidth: SparklineConsistency.listLineWidth,
                        verticalPaddingRatio: SparklineConsistency.listVerticalPaddingRatio,
                        fillOpacity: SparklineConsistency.listFillOpacity * 0.32,
                        gradientStroke: true,
                        showEndDot: true,
                        leadingFade: 0.0,
                        trailingFade: 0.0,
                        showTrailHighlight: false,
                        trailLengthRatio: 0.0,
                        endDotPulse: false,
                        backgroundStyle: .none,
                        glowOpacity: SparklineConsistency.listGlowOpacity,
                        glowLineWidth: SparklineConsistency.listGlowLineWidth,
                        smoothSamplesPerSegment: SparklineConsistency.listSmoothSamplesPerSegment,
                        maxPlottedPoints: SparklineConsistency.listMaxPlottedPoints,
                        showBackground: false,
                        showExtremaDots: false,
                        neonTrail: false,
                        crispEnds: true,
                        horizontalInset: SparklineConsistency.listHorizontalInset,
                        compact: false,
                        seriesOrder: .oldestToNewest
                    )
                    .frame(height: 50)
                }
                
                // Range bar
                VStack(spacing: 5) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(LinearGradient(colors: [Color.red.opacity(0.25), Color.orange.opacity(0.15), Color.green.opacity(0.25)],
                                                     startPoint: .leading, endPoint: .trailing))
                                .frame(height: 5)
                            Circle().fill(.white).frame(width: 9, height: 9)
                                .offset(x: max(0, min(geo.size.width - 9, CGFloat(pos) * (geo.size.width - 9))))
                        }
                    }
                    .frame(height: 9)
                    HStack {
                        Text(currency(lo)).font(.system(size: 9).monospacedDigit()).foregroundColor(DS.Adaptive.textTertiary)
                        Spacer()
                        Text("Range · \(Int(pos * 100))%").font(.system(size: 9, weight: .medium)).foregroundColor(DS.Adaptive.textSecondary)
                        Spacer()
                        Text(currency(hi)).font(.system(size: 9).monospacedDigit()).foregroundColor(DS.Adaptive.textTertiary)
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
    
    // MARK: - Technicals
    private var stockTechnicals: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                GoldHeaderGlyph(systemName: "chart.line.uptrend.xyaxis")
                Text("Technical Indicators").font(.system(size: 14, weight: .semibold)).foregroundColor(DS.Adaptive.textPrimary)
            }
            
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                if sparkline.count >= 14, let rsi = TechnicalsEngine.rsi(sparkline, period: 14) {
                    DeepDiveIndicatorCell(name: "RSI (14)", value: String(format: "%.0f", rsi),
                                          signal: rsi < 30 ? "Oversold" : (rsi > 70 ? "Overbought" : "Neutral"),
                                          signalColor: rsi < 30 ? .green : (rsi > 70 ? .red : .yellow))
                }
                if sparkline.count >= 26, let macdResult = TechnicalsEngine.macdLineSignal(sparkline) {
                    let m = macdResult.macd, s = macdResult.signal
                    DeepDiveIndicatorCell(name: "MACD", value: String(format: "%.4f", m - s),
                                          signal: m > s ? "Bullish" : "Bearish", signalColor: m > s ? .green : .red)
                }
                let vol = volatility(of: sparkline)
                DeepDiveIndicatorCell(name: "Volatility", value: String(format: "%.2f%%", vol),
                                      signal: vol > 5 ? "High" : (vol > 2 ? "Medium" : "Low"),
                                      signalColor: vol > 5 ? .orange : (vol > 2 ? .yellow : .green))
                let mom = percentChange(from: sparkline.first, to: sparkline.last)
                DeepDiveIndicatorCell(name: "Momentum", value: String(format: "%+.1f%%", mom),
                                      signal: mom > 5 ? "Strong" : (mom > 0 ? "Positive" : (mom > -5 ? "Negative" : "Weak")),
                                      signalColor: mom > 0 ? .green : .red)
            }
            
            // Support / Resistance
            let (support, resistance) = swingLevels(series: sparkline)
            if support != nil || resistance != nil {
                HStack(spacing: 8) {
                    if let s = support {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2).fill(Color.green).frame(width: 3, height: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Support").font(.system(size: 9, weight: .medium)).foregroundColor(DS.Adaptive.textTertiary)
                                Text(currency(s)).font(.system(size: 13, weight: .bold).monospacedDigit()).foregroundColor(.green)
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
                                Text(currency(r)).font(.system(size: 13, weight: .bold).monospacedDigit()).foregroundColor(.red)
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
    private var stockContext: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                GoldHeaderGlyph(systemName: "globe")
                Text("Market Context").font(.system(size: 14, weight: .semibold)).foregroundColor(DS.Adaptive.textPrimary)
            }
            VStack(spacing: 0) {
                if let sentiment = ExtendedFearGreedViewModel.shared.currentValue,
                   let classification = ExtendedFearGreedViewModel.shared.currentClassificationKey {
                    VStack(spacing: 6) {
                        HStack {
                            Text("Fear & Greed Index").font(.system(size: 12)).foregroundColor(DS.Adaptive.textSecondary)
                            Spacer()
                            HStack(spacing: 4) {
                                Text("\(sentiment)").font(.system(size: 13, weight: .bold).monospacedDigit()).foregroundColor(DS.Adaptive.textPrimary)
                                Text("(\(classification.capitalized))").font(.system(size: 10)).foregroundColor(DS.Adaptive.textTertiary)
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
                    Rectangle().fill(DS.Adaptive.divider.opacity(0.5)).frame(height: 0.5).padding(.horizontal, 10)
                }
                
                // Market status
                HStack {
                    Text("US Market").font(.system(size: 12)).foregroundColor(DS.Adaptive.textSecondary)
                    Spacer()
                    HStack(spacing: 4) {
                        Circle().fill(isMarketOpen() ? Color.green : Color.orange).frame(width: 6, height: 6)
                        Text(isMarketOpen() ? "Open" : "Closed").font(.system(size: 13, weight: .semibold)).foregroundColor(DS.Adaptive.textPrimary)
                    }
                }
                .padding(.vertical, 8).padding(.horizontal, 10)
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isDark ? Color.white.opacity(0.02) : Color.black.opacity(0.015)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(DS.Adaptive.stroke.opacity(0.6), lineWidth: 0.5))
        }
        .modifier(DeepDiveCardStyle())
    }
    
    // MARK: - AI Analysis
    private var stockAISection: some View {
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
                if error != nil && !hasAIContent && !isLoading {
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
            
            if isLoading && !hasAIContent {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(0..<6, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3).fill(DS.Adaptive.chipBackground)
                            .frame(maxWidth: i == 5 ? 140 : (i == 3 ? 200 : .infinity)).frame(height: 14).shimmer()
                    }
                }
            } else {
                Text(aiAnalysis.isEmpty ? buildFallbackAnalysis() : aiAnalysis)
                    .font(.system(size: 14)).foregroundColor(DS.Adaptive.textPrimary)
                    .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            }
            
            Text("AI-generated analysis for educational purposes only. Always do your own research.")
                .font(.system(size: 9)).foregroundColor(DS.Adaptive.textTertiary).padding(.top, 4)
        }
        .modifier(DeepDiveCardStyle())
    }
    
    // MARK: - AI Loading (cache-first)
    @MainActor
    private func loadDeepDive() async {
        // Check cache first
        let cacheKey = "stock-\(ticker)"
        if let cached = CoinAIInsightService.shared.cachedDeepDive(for: cacheKey) {
            aiAnalysis = cached
            return
        }
        
        isLoading = true
        error = nil
        
        let cleanTicker = ticker.replacingOccurrences(of: "=", with: "")
        do {
            let response = try await FirebaseService.shared.getCoinInsight(
                coinId: "deepdive-\(cleanTicker.lowercased())",
                coinName: companyName,
                symbol: cleanTicker,
                price: price,
                change24h: change24h,
                change7d: nil,
                marketCap: nil,
                volume24h: nil,
                assetType: "stock"
            )
            withAnimation(.easeInOut(duration: 0.2)) { aiAnalysis = response.content }
        } catch {
            self.error = error.localizedDescription
            if aiAnalysis.isEmpty { aiAnalysis = buildFallbackAnalysis() }
        }
        isLoading = false
    }
    
    // MARK: - Natural Fallback
    private func buildFallbackAnalysis() -> String {
        let verb = change24h >= 0 ? "gained" : "declined"
        let c = String(format: "%.2f%%", abs(change24h))
        let (s1, r1) = swingLevels(series: sparkline)
        let hi = sparkline.max() ?? price
        let lo = sparkline.min() ?? price
        let range = hi - lo
        let pos = range > 0 ? (price - lo) / range : 0.5
        let mom = percentChange(from: sparkline.first, to: sparkline.last)
        let vol = volatility(of: sparkline)
        
        var paragraphs: [String] = []
        paragraphs.append("\(ticker) (\(companyName)) has \(verb) \(c) and is currently trading near \(currency(price)).")
        
        let posDesc: String
        if pos < 0.25 { posDesc = "near the bottom" }
        else if pos < 0.50 { posDesc = "in the lower half" }
        else if pos < 0.75 { posDesc = "in the upper half" }
        else { posDesc = "near the top" }
        paragraphs.append("The price sits \(posDesc) of its recent range (\(currency(lo)) – \(currency(hi))), with momentum at \(String(format: "%.1f%%", mom)).")
        
        var levelParts: [String] = []
        if let s = s1 { levelParts.append("support around \(currency(s))") }
        if let r = r1 { levelParts.append("resistance near \(currency(r))") }
        if !levelParts.isEmpty { paragraphs.append("Key levels to watch include \(levelParts.joined(separator: " and ")).") }
        
        let volDesc = vol < 1.0 ? "relatively low" : (vol < 3.0 ? "moderate" : "elevated")
        paragraphs.append("Realized volatility is \(volDesc) at \(String(format: "%.2f%%", vol)).")
        
        return paragraphs.joined(separator: "\n\n")
    }

    // MARK: - Helpers
    private func percentChange(from: Double?, to: Double?) -> Double {
        guard let f = from, let t = to, f > 0 else { return 0 }
        return (t - f) / f * 100
    }
    private func volatility(of series: [Double]) -> Double {
        guard series.count > 2 else { return 0 }
        var returns: [Double] = []
        for i in 1..<series.count { let a = series[i-1]; let b = series[i]; if a > 0 && b > 0 { returns.append((b-a)/a) } }
        let mean = returns.reduce(0, +) / Double(max(1, returns.count))
        let varSum = returns.reduce(0) { $0 + pow($1 - mean, 2) }
        return sqrt(varSum / Double(max(1, returns.count - 1))) * 100
    }
    private func swingLevels(series: [Double]) -> (Double?, Double?) {
        guard series.count >= 10 else { return (nil, nil) }
        let window = Array(series.suffix(96))
        var lows: [Double] = []; var highs: [Double] = []
        if window.count >= 3 {
            for i in 1..<(window.count - 1) {
                let (a, b, c) = (window[i-1], window[i], window[i+1])
                if b < a && b < c { lows.append(b) }
                if b > a && b > c { highs.append(b) }
            }
        }
        return (lows.max(), highs.min())
    }
    private func currency(_ v: Double) -> String { String(format: "$%.2f", v) }
    private func isMarketOpen() -> Bool {
        let cal = Calendar.current; let now = Date(); let wd = cal.component(.weekday, from: now)
        if wd == 1 || wd == 7 { return false }
        guard let tz = TimeZone(identifier: "America/New_York") else { return false }
        let c = cal.dateComponents(in: tz, from: now)
        let (h, m) = (c.hour ?? 0, c.minute ?? 0)
        return (h > 9 || (h == 9 && m >= 30)) && h < 16
    }
}

private struct StockDeepDiveCardAppear: ViewModifier {
    let appeared: Bool; let delay: Double
    func body(content: Content) -> some View {
        content.opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 10)
            .animation(.spring(response: 0.45, dampingFraction: 0.8).delay(delay), value: appeared)
    }
}

// MARK: - Stock Why Moving Sheet

struct StockWhyMovingSheet: View {
    let ticker: String
    let companyName: String
    let priceChange: Double
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var aiAnalysis: String = ""
    @State private var isLoading: Bool = true
    @State private var error: String? = nil
    
    private var isDark: Bool { colorScheme == .dark }
    private var isPositive: Bool { priceChange >= 0 }
    private var accentColor: Color { isPositive ? .green : .red }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Hero header
                    headerSection
                    
                    // AI Analysis section
                    aiAnalysisSection
                    
                    // Research links (compact)
                    researchLinksSection
                    
                    // Disclaimer
                    disclaimerSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(DS.Adaptive.background)
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadAIAnalysis() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(DS.Adaptive.textTertiary)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Why is \(ticker) moving?")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !aiAnalysis.isEmpty {
                        ShareLink(item: "\(companyName) (\(ticker)) \(String(format: "%+.2f%%", priceChange))\n\n\(aiAnalysis)") {
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
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(accentColor.opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(accentColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(companyName) is \(isPositive ? "up" : "down")")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        Text(String(format: "%+.2f%% today", priceChange))
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
    }
    
    private var aiAnalysisSection: some View {
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
                
                if error != nil && aiAnalysis.isEmpty && !isLoading {
                    Button { Task { await loadAIAnalysis() } } label: {
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
            
            if isLoading {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(0..<5, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(DS.Adaptive.chipBackground)
                            .frame(maxWidth: i == 4 ? 140 : (i == 2 ? 200 : .infinity))
                            .frame(height: 14)
                            .shimmer()
                    }
                }
            } else if !aiAnalysis.isEmpty {
                Text(aiAnalysis)
                    .font(.system(size: 14))
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            } else if error != nil {
                Text("Unable to generate analysis at this time.")
                    .font(.system(size: 14))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            
            Text("AI analysis of market data. Not financial advice.")
                .font(.system(size: 9))
                .foregroundColor(DS.Adaptive.textTertiary)
                .padding(.top, 4)
        }
        .modifier(DeepDiveCardStyle())
    }
    
    private var researchLinksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                GoldHeaderGlyph(systemName: "magnifyingglass")
                Text("Research")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
            }
            
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                stockResearchLink(title: "Yahoo Finance", url: "https://finance.yahoo.com/quote/\(ticker)/news", icon: "chart.line.uptrend.xyaxis")
                stockResearchLink(title: "Google News", url: "https://news.google.com/search?q=\(ticker)%20stock", icon: "newspaper")
                stockResearchLink(title: "SEC Filings", url: "https://www.sec.gov/cgi-bin/browse-edgar?action=getcompany&company=\(ticker)", icon: "doc.text")
                stockResearchLink(title: "Twitter/X", url: "https://x.com/search?q=%24\(ticker)", icon: "bubble.left")
            }
        }
        .modifier(DeepDiveCardStyle())
    }
    
    private func stockResearchLink(title: String, url: String, icon: String) -> some View {
        Link(destination: URL(string: url) ?? URL(fileURLWithPath: "/")) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(DS.Adaptive.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.05), lineWidth: 0.5)
            )
        }
    }
    
    private var disclaimerSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 10))
            Text("Stock prices are influenced by many factors. This is for informational purposes only and not investment advice.")
                .font(.system(size: 9))
        }
        .foregroundColor(DS.Adaptive.textTertiary)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isDark ? Color.white.opacity(0.02) : Color.black.opacity(0.015))
        )
    }
    
    // MARK: - AI Analysis Loading
    private func loadAIAnalysis() async {
        let cleanTicker = ticker.replacingOccurrences(of: "=", with: "").uppercased()
        
        await MainActor.run { isLoading = true; error = nil }
        
        do {
            let response = try await FirebaseService.shared.getCoinInsight(
                coinId: "whymoving-\(cleanTicker.lowercased())",
                coinName: companyName,
                symbol: cleanTicker,
                price: 0,
                change24h: priceChange,
                change7d: nil,
                marketCap: nil,
                volume24h: nil
            )
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) { aiAnalysis = response.content }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }
}

// MARK: - Stock Diagnostics Sheet

/// Diagnostics sheet for debugging stock data issues
/// Accessible via long-press on the stats section header
private struct StockDiagnosticsSheet: View {
    let ticker: String
    let companyName: String
    let quote: StockQuote?
    let lastUpdate: Date?
    let chartDataCount: Int
    let selectedInterval: StockChartInterval
    let assetType: AssetType
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Data Diagnostics")
                            .font(.title2.weight(.bold))
                        Text("Debug information for \(ticker)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    
                    // Quote Info
                    diagnosticsSection(title: "Quote Data") {
                        diagnosticsRow("Symbol", value: ticker)
                        diagnosticsRow("Name", value: companyName)
                        diagnosticsRow("Asset Type", value: assetType.rawValue.capitalized)
                        diagnosticsRow("Exchange", value: quote?.exchange ?? "Unknown")
                        diagnosticsRow("Current Price", value: quote.map { String(format: "$%.2f", $0.regularMarketPrice) } ?? "N/A")
                        diagnosticsRow("Quote Available", value: quote != nil ? "Yes" : "No")
                    }
                    
                    // Timing Info
                    diagnosticsSection(title: "Data Freshness") {
                        diagnosticsRow("Last Update", value: lastUpdate.map(formatTimestamp) ?? "Never")
                        diagnosticsRow("Age", value: lastUpdate.map(formatAge) ?? "N/A")
                        diagnosticsRow("Is Fresh", value: isDataFresh ? "Yes (< 2 min)" : "No (stale)")
                    }
                    
                    // Chart Info
                    diagnosticsSection(title: "Chart Data") {
                        diagnosticsRow("Data Points", value: "\(chartDataCount)")
                        diagnosticsRow("Interval", value: selectedInterval.displayName)
                        diagnosticsRow("Yahoo Range", value: selectedInterval.yahooRange)
                        diagnosticsRow("Yahoo Interval", value: selectedInterval.yahooInterval)
                    }
                    
                    // API Source
                    diagnosticsSection(title: "Data Source") {
                        if assetType == .commodity {
                            diagnosticsRow("Primary Source", value: "Coinbase")
                        } else {
                            diagnosticsRow("Primary Source", value: "Yahoo Finance")
                        }
                        diagnosticsRow("Quote Type", value: quote?.quoteType ?? "Unknown")
                    }
                }
                .padding(.vertical)
            }
            .background(DS.Adaptive.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
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
    
    private var isDataFresh: Bool {
        guard let lastUpdate = lastUpdate else { return false }
        return Date().timeIntervalSince(lastUpdate) < 120
    }
    
    private func diagnosticsSection(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(DS.Adaptive.textPrimary)
                .padding(.horizontal)
            
            VStack(spacing: 1) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(DS.Adaptive.cardBackground)
            )
            .padding(.horizontal)
        }
    }
    
    private func diagnosticsRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundColor(DS.Adaptive.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
    
    private static let _timestampFmt: DateFormatter = {
        let df = DateFormatter(); df.dateStyle = .short; df.timeStyle = .medium; return df
    }()
    private func formatTimestamp(_ date: Date) -> String {
        return Self._timestampFmt.string(from: date)
    }
    
    private func formatAge(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 {
            return "\(seconds)s ago"
        } else if seconds < 3600 {
            return "\(seconds / 60)m \(seconds % 60)s ago"
        } else {
            return "\(seconds / 3600)h \((seconds % 3600) / 60)m ago"
        }
    }
}

// MARK: - Stock Why Is Moving Card

/// Inline card shown for significant stock price movements (5%+ change)
/// Similar to WhyIsMovingCard for coins
private struct StockWhyIsMovingCard: View {
    let ticker: String
    let companyName: String
    let changePercent: Double
    @Binding var showSheet: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var isPositive: Bool { changePercent >= 0 }
    private var changeColor: Color { isPositive ? .green : .red }
    
    // Only show for significant moves (5% or more)
    var shouldShow: Bool { abs(changePercent) >= 5.0 }
    
    var body: some View {
        if shouldShow {
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                showSheet = true
            } label: {
                HStack(spacing: 14) {
                    // Icon with colored background
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
                            Text("Why is \(ticker)")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(DS.Adaptive.textPrimary)
                            
                            Text("\(isPositive ? "+" : "")\(String(format: "%.1f", changePercent))%")
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
        }
    }
}

// MARK: - Stock News ViewModel

@MainActor
final class StockNewsViewModel: ObservableObject {
    @Published var articles: [NewsArticle] = []
    @Published var isLoading: Bool = false
    
    private static var cache: [String: (Date, [NewsArticle])] = [:]
    private let cacheTTL: TimeInterval = 10 * 60 // 10 minutes
    
    func fetch(query: String, category: StockNewsCategory) {
        let key = query + "|" + category.rawValue
        if let (ts, items) = Self.cache[key], Date().timeIntervalSince(ts) < cacheTTL {
            self.articles = items
            self.isLoading = false
            return
        }
        
        isLoading = true
        let url = feedURL(for: query, category: category)
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
    
    func moreURL(for query: String, category: StockNewsCategory) -> URL? {
        let q = buildQuery(for: query, category: category)
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return URL(string: "https://news.google.com/search?q=\(q)")
    }
    
    private func feedURL(for query: String, category: StockNewsCategory) -> URL {
        let q = buildQuery(for: query, category: category)
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return URL(string: "https://news.google.com/rss/search?q=\(q)&hl=en-US&gl=US&ceid=US:en") ?? URL(fileURLWithPath: "/")
    }
    
    private func buildQuery(for query: String, category: StockNewsCategory) -> String {
        return "\(query) \(category.queryKeywords)"
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        StockDetailView(
            ticker: "AAPL",
            companyName: "Apple Inc.",
            assetType: .stock,
            holding: Holding(
                ticker: "AAPL",
                companyName: "Apple Inc.",
                shares: 10,
                currentPrice: 248.50,
                costBasis: 175.00,
                assetType: .stock,
                stockExchange: "NASDAQ",
                isin: nil,
                imageUrl: nil,
                isFavorite: true,
                dailyChange: 1.25,
                purchaseDate: Date(),
                source: "manual"
            )
        )
    }
    .preferredColorScheme(.dark)
}
