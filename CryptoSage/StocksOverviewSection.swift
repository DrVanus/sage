//
//  StocksOverviewSection.swift
//  CryptoSage
//
//  Created by CryptoSage on 1/19/26.
//  Home page section showing quick overview of stock/ETF holdings and market movers.
//

import SwiftUI
import Combine

struct StocksOverviewSection: View {
    @EnvironmentObject var portfolioVM: PortfolioViewModel
    // PERFORMANCE FIX v21: Removed @EnvironmentObject var appState: AppState
    // AppState has 18+ @Published properties. Every change to ANY of them forced this
    // entire section to re-render. Only dismissHomeSubviews is needed - use targeted onReceive.
    // FIX v23: Replaced @ObservedObject with computed singleton access + debounced refresh.
    // StockMarketCache has 8 @Published, StockSparklineService has 2.
    // With @ObservedObject, ANY change to either (loading state, market open status, error, etc.)
    // forced a full re-render of this section including stock row sparklines and gradient cards.
    // Now we debounce to 3 seconds — stock data refreshes every 15-60s anyway.
    private var marketCache: StockMarketCache { StockMarketCache.shared }
    private var sparklineService: StockSparklineService { StockSparklineService.shared }
    @State private var stockDataTick: UInt = 0
    @Environment(\.colorScheme) private var colorScheme
    
    var onOpenMarketStock: (CachedStock) -> Void = { _ in }
    var onOpenMarketView: () -> Void = {}
    
    // PERFORMANCE FIX v2: Track when task last ran to prevent repeated execution
    @MainActor private static var lastTaskRunAt: Date = .distantPast
    
    // MARK: - Third Slot Rotation
    // Rotates the third stock slot between different popular stocks for variety
    @State private var thirdSlotRotationIndex: Int = 0
    private let thirdSlotCandidates = ["AMZN", "AAPL", "GOOG", "MSFT", "META"]
    private let rotationInterval: TimeInterval = 30 // Rotate every 30 seconds
    
    /// Current third slot stock based on rotation
    private var currentThirdSlotStock: String {
        thirdSlotCandidates[thirdSlotRotationIndex % thirdSlotCandidates.count]
    }
    
    private var isDark: Bool { colorScheme == .dark }
    
    // MARK: - Layout Constants (matching watchlist for consistency)
    private let minSparkWidth: CGFloat = 120  // Minimum sparkline width - wider for better visibility
    private let iconSize: CGFloat = 38        // Stock logo size
    private let priceColumnWidth: CGFloat = 85 // Price + change column width (wider for larger prices)
    private let nameColumnWidth: CGFloat = 80  // Ticker + company name column width
    
    // Check if user has real stock holdings
    private var hasRealHoldings: Bool {
        !portfolioVM.securitiesHoldings.isEmpty
    }
    
    // User's stock holdings
    private var userHoldings: [Holding] {
        portfolioVM.securitiesHoldings
    }
    
    // All available fallback stocks for rotation
    // NVDA and TSLA are always first two, third slot rotates among others
    // NOTE: Change values set to 0 - no fake percentage data. Will show "—" until live data loads
    private static let allFallbackStocks: [String: CachedStock] = [
        "NVDA": CachedStock(
            symbol: "NVDA",
            name: "NVIDIA Corporation",
            currentPrice: 875.40,  // Approximate price - updated periodically
            change: 0,             // No fake data
            changePercent: 0,      // Will show "—" until live
            dayHigh: 875.40,
            dayLow: 875.40,
            previousClose: 875.40,
            marketCap: 2_150_000_000_000,
            volume: nil,           // No fake volume
            assetType: .stock,
            exchange: "NASDAQ",
            sector: "Technology",
            lastUpdated: Date()
        ),
        "TSLA": CachedStock(
            symbol: "TSLA",
            name: "Tesla Inc.",
            currentPrice: 248.90,
            change: 0,
            changePercent: 0,
            dayHigh: 248.90,
            dayLow: 248.90,
            previousClose: 248.90,
            marketCap: 790_000_000_000,
            volume: nil,
            assetType: .stock,
            exchange: "NASDAQ",
            sector: "Consumer Cyclical",
            lastUpdated: Date()
        ),
        "AMZN": CachedStock(
            symbol: "AMZN",
            name: "Amazon.com Inc.",
            currentPrice: 198.75,
            change: 0,
            changePercent: 0,
            dayHigh: 198.75,
            dayLow: 198.75,
            previousClose: 198.75,
            marketCap: 2_050_000_000_000,
            volume: nil,
            assetType: .stock,
            exchange: "NASDAQ",
            sector: "Consumer Cyclical",
            lastUpdated: Date()
        ),
        "AAPL": CachedStock(
            symbol: "AAPL",
            name: "Apple Inc.",
            currentPrice: 182.50,
            change: 0,
            changePercent: 0,
            dayHigh: 182.50,
            dayLow: 182.50,
            previousClose: 182.50,
            marketCap: 2_850_000_000_000,
            volume: nil,
            assetType: .stock,
            exchange: "NASDAQ",
            sector: "Technology",
            lastUpdated: Date()
        ),
        "GOOG": CachedStock(
            symbol: "GOOG",
            name: "Alphabet Inc.",
            currentPrice: 142.80,
            change: 0,
            changePercent: 0,
            dayHigh: 142.80,
            dayLow: 142.80,
            previousClose: 142.80,
            marketCap: 1_780_000_000_000,
            volume: nil,
            assetType: .stock,
            exchange: "NASDAQ",
            sector: "Technology",
            lastUpdated: Date()
        ),
        "MSFT": CachedStock(
            symbol: "MSFT",
            name: "Microsoft Corporation",
            currentPrice: 415.60,
            change: 0,
            changePercent: 0,
            dayHigh: 415.60,
            dayLow: 415.60,
            previousClose: 415.60,
            marketCap: 3_100_000_000_000,
            volume: nil,
            assetType: .stock,
            exchange: "NASDAQ",
            sector: "Technology",
            lastUpdated: Date()
        ),
        "META": CachedStock(
            symbol: "META",
            name: "Meta Platforms Inc.",
            currentPrice: 525.30,
            change: 0,
            changePercent: 0,
            dayHigh: 525.30,
            dayLow: 525.30,
            previousClose: 525.30,
            marketCap: 1_340_000_000_000,
            volume: nil,
            assetType: .stock,
            exchange: "NASDAQ",
            sector: "Technology",
            lastUpdated: Date()
        )
    ]
    
    // Fallback stocks with rotating third slot
    private var fallbackStocks: [CachedStock] {
        var stocks: [CachedStock] = []
        
        // Always show NVDA and TSLA first
        if let nvda = Self.allFallbackStocks["NVDA"] { stocks.append(nvda) }
        if let tsla = Self.allFallbackStocks["TSLA"] { stocks.append(tsla) }
        
        // Third slot rotates among candidates
        if let thirdStock = Self.allFallbackStocks[currentThirdSlotStock] {
            stocks.append(thirdStock)
        } else if let amzn = Self.allFallbackStocks["AMZN"] {
            stocks.append(amzn) // Fallback to AMZN if rotation stock not found
        }
        
        return stocks
    }
    
    // Market movers for display when no holdings exist
    private var marketMovers: [CachedStock] {
        // Mix top gainers and losers for variety
        let gainers = marketCache.topGainers(limit: 3)
        let losers = marketCache.topLosers(limit: 2)
        
        // If cache has data, interleave gainers and losers
        if !gainers.isEmpty || !losers.isEmpty {
            var result: [CachedStock] = []
            let maxCount = max(gainers.count, losers.count)
            for i in 0..<maxCount {
                if i < gainers.count { result.append(gainers[i]) }
                if i < losers.count { result.append(losers[i]) }
            }
            return Array(result.prefix(5))
        }
        
        // FIX: When market is closed (all stocks have 0% change), topGainers/topLosers
        // return empty since they filter for >0 and <0 respectively. Instead of falling
        // back to stale hardcoded prices, show top stocks by market cap from the cache.
        // These have REAL prices and the actual 0% change (which is correct for closed market).
        let topByMarketCap = marketCache.stocksExcludingCommodities
            .sorted { ($0.marketCap ?? 0) > ($1.marketCap ?? 0) }
            .prefix(5)
        if !topByMarketCap.isEmpty {
            return Array(topByMarketCap)
        }
        
        // Last resort: fallback to sample stocks with rotating third slot
        return fallbackStocks
    }
    
    // Display stocks - prioritize holdings, fallback to market movers
    private var displayStocks: [CachedStock] {
        if hasRealHoldings {
            // Convert holdings to CachedStock for unified display
            return userHoldings.prefix(5).compactMap { holding in
                let symbol = holding.ticker ?? holding.coinSymbol
                if let cached = marketCache.stock(for: symbol) {
                    return cached
                }
                // Create from holding data
                return CachedStock(
                    symbol: symbol,
                    name: holding.displayName,
                    currentPrice: holding.currentPrice,
                    change: 0,
                    changePercent: holding.dailyChange,
                    dayHigh: holding.currentPrice,
                    dayLow: holding.currentPrice,
                    previousClose: holding.currentPrice,
                    marketCap: nil,
                    volume: nil,
                    assetType: holding.assetType,
                    exchange: holding.stockExchange,
                    sector: nil,
                    lastUpdated: Date()
                )
            }
        } else {
            return marketMovers
        }
    }
    
    // Total stock/ETF value (only for holdings mode)
    private var stocksTotal: Double {
        hasRealHoldings ? userHoldings.reduce(0) { $0 + $1.currentValue } : 0
    }
    
    // Stock count (excludes commodity futures to avoid double-counting with Commodities section)
    private var stockCount: Int {
        hasRealHoldings ? userHoldings.count : marketCache.stockOnlyCount
    }
    
    // Market status
    private var isMarketOpen: Bool {
        marketCache.isMarketOpen
    }
    
    var body: some View {
        // FIX v23: Reference tick to trigger re-renders on debounced stock data updates
        let _ = stockDataTick
        
        VStack(alignment: .leading, spacing: 0) {
            // Section Header
            sectionHeader
            
            // Content - always shows data (fallback ensures displayStocks is never empty)
            stocksContent
        }
        .task(id: "stocksOverviewInit") {
            // Avoid hard-skipping on startup; brief deferral is faster than waiting for a full re-appear.
            if isInGlobalStartupPhase() {
                #if DEBUG
                print("📊 [StocksOverviewSection] Startup phase active — deferring task")
                #endif
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            
            // PERFORMANCE FIX v2: Use task(id:) with stable identifier to prevent repeated execution
            // This ensures the task only runs once per view lifecycle, not on every parent re-render
            
            // PERFORMANCE FIX v2: Skip if we've recently loaded (within 30 seconds)
            let now = Date()
            if now.timeIntervalSince(Self.lastTaskRunAt) < 30 {
                return
            }
            Self.lastTaskRunAt = now
            
            #if DEBUG
            print("📊 [StocksOverviewSection] Task started, cache count: \(marketCache.stocks.count), needs refresh: \(marketCache.needsRefresh)")
            #endif
            
            // Fetch row sparklines immediately from current display symbols.
            // This avoids the visible "blank sparkline" delay on first paint.
            let initialTickers = Array(displayStocks.prefix(3).map { $0.symbol })
            if !initialTickers.isEmpty {
                Task(priority: .userInitiated) { @MainActor in
                    await sparklineService.fetchSparklines(for: initialTickers)
                }
                Task(priority: .utility) {
                    await StockLogoService.shared.prefetchLogos(for: initialTickers)
                }
            }
            
            // Prefetch a wider, stable logo set used in this section to reduce
            // visible badge fallbacks while users scroll/revisit Home.
            let logoPrefetchUniverse = Array(
                Set(displayStocks.prefix(8).map(\.symbol) + marketMovers.prefix(8).map(\.symbol))
            )
            if !logoPrefetchUniverse.isEmpty {
                Task(priority: .utility) {
                    await StockLogoService.shared.prefetchLogos(for: logoPrefetchUniverse)
                }
            }
            
            // PERFORMANCE FIX v3: Defer heavy data loading
            // Don't block view rendering - let cached data display first, then refresh in background
            Task.detached(priority: .utility) { @MainActor in
                // Short defer keeps startup smooth but avoids long sparkline blank states.
                try? await Task.sleep(nanoseconds: 120_000_000)
                
                // Trigger background refresh if needed
                if marketCache.stocks.isEmpty || marketCache.needsRefresh {
                    await marketCache.refresh()
                    #if DEBUG
                    print("📊 [StocksOverviewSection] Cache refresh complete, count: \(marketCache.stocks.count)")
                    #endif
                }
                
                // Fetch sparklines for displayed stocks in background
                let tickersToFetch = displayStocks.prefix(3).map { $0.symbol }
                if !tickersToFetch.isEmpty {
                    await sparklineService.fetchSparklines(for: Array(tickersToFetch))
                    await StockLogoService.shared.prefetchLogos(for: Array(tickersToFetch))
                    #if DEBUG
                    print("📈 [StocksOverviewSection] Sparklines fetched for: \(tickersToFetch)")
                    #endif
                }
            }
        }
        .onAppear {
            // Warm logos quickly even if the section task is throttled.
            let logoUniverse = Array(
                Set(displayStocks.prefix(8).map(\.symbol) + marketMovers.prefix(8).map(\.symbol))
            )
            if !logoUniverse.isEmpty {
                Task.detached(priority: .utility) {
                    await StockLogoService.shared.prefetchLogos(for: logoUniverse)
                }
            }

            // Also ensure market movers get updated sparklines when real data loads
            if !marketCache.stocks.isEmpty {
                let realTickers = Array(marketMovers.prefix(3).map { $0.symbol })
                if !realTickers.isEmpty && realTickers != displayStocks.prefix(3).map({ $0.symbol }) {
                    Task.detached(priority: .utility) { @MainActor in
                        await sparklineService.fetchSparklines(for: realTickers)
                    }
                }
            }
        }
        // MARK: - Third Slot Rotation Timer
        // Rotates the third stock every 30 seconds for variety (when using fallback data)
        // PERFORMANCE FIX v19: Changed .common to .default - timer pauses during scroll
        .onReceive(Timer.publish(every: rotationInterval, on: .main, in: .default).autoconnect()) { _ in
            // PERFORMANCE FIX: Skip rotation animation during scroll
            guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                thirdSlotRotationIndex = (thirdSlotRotationIndex + 1) % thirdSlotCandidates.count
            }
        }
        // Pop-to-root: Dismiss all navigation when home tab is tapped
        // FIX v23: Debounced stock data observation (replaces @ObservedObject)
        .onReceive(StockMarketCache.shared.objectWillChange.debounce(for: .seconds(1), scheduler: DispatchQueue.main)) { _ in
            guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
            stockDataTick &+= 1
        }
        .onReceive(StockSparklineService.shared.objectWillChange.debounce(for: .milliseconds(350), scheduler: DispatchQueue.main)) { _ in
            guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
            stockDataTick &+= 1
        }
    }
    
    // MARK: - Section Header
    
    private var sectionHeader: some View {
        HStack(spacing: 8) {
            // Gold accent icon - consistent with other sections
            GoldHeaderGlyph(systemName: "chart.line.uptrend.xyaxis")
            
            Text("Stocks & ETFs")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            // Market status badge
            marketStatusBadge
            
            Spacer()
            
            // Total value with subtle styling
            if stocksTotal > 0 {
                Text(formatCurrency(stocksTotal))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }
    
    // MARK: - Market Status Badge
    
    private var marketStatusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isMarketOpen ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            
            Text(isMarketOpen ? "Open" : "Closed")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isMarketOpen ? .green : .orange)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill((isMarketOpen ? Color.green : Color.orange).opacity(0.15))
        )
    }
    
    // MARK: - Stocks Content
    
    private var stocksContent: some View {
        VStack(spacing: 0) {
            // Header for market movers mode
            if !hasRealHoldings && !displayStocks.isEmpty {
                HStack {
                    Text("Market Movers")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }
            
            // Stock rows card with premium styling
            VStack(spacing: 0) {
                // Show top 3 stocks on homepage
                let topDisplayStocks = Array(displayStocks.prefix(3))
                
                ForEach(topDisplayStocks) { stock in
                    marketStockRow(stock)
                        .onTapGesture {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            onOpenMarketStock(stock)
                        }
                    
                    if stock.id != topDisplayStocks.last?.id {
                        Divider()
                            .padding(.horizontal, 14)
                            .opacity(0.5)
                    }
                }
                
                // Integrated "See All" / "Browse Market" row at bottom
                Divider()
                    .padding(.horizontal, 14)
                    .opacity(0.5)
                
                seeAllStocksRow
            }
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        DS.Adaptive.divider.opacity(isDark ? 0.4 : 0.2),
                        lineWidth: 1
                    )
            )
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Market Stock Row (for CachedStock)
    
    private func marketStockRow(_ stock: CachedStock) -> some View {
        GeometryReader { geometry in
            // Calculate dynamic sparkline width based on available space
            let rowPadding: CGFloat = 28  // 14 * 2 horizontal padding
            let spacing: CGFloat = 24     // spacing between elements (8 * 3)
            let fixedWidth = iconSize + nameColumnWidth + priceColumnWidth + rowPadding + spacing
            let availableSparkWidth = max(minSparkWidth, geometry.size.width - fixedWidth)
            
            HStack(spacing: 8) {
                // Stock Logo
                StockImageView(
                    ticker: stock.symbol,
                    assetType: stock.assetType,
                    size: iconSize
                )
                
                // Ticker and name - fixed width to ensure consistent layout
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(stock.symbol)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        // ETF badge if applicable
                        if stock.assetType == .etf {
                            Text("ETF")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(stock.assetType.color.opacity(0.9))
                                .clipShape(Capsule())
                        }
                    }
                    
                    Text(Self.abbreviateCompanyName(stock.name))
                        .font(.system(size: 11))
                        .foregroundColor(DS.Adaptive.textSecondary)
                        .lineLimit(1)
                    
                    // Show shares if user owns this stock
                    if let holding = userHoldings.first(where: { ($0.ticker ?? $0.coinSymbol) == stock.symbol }) {
                        Text("\(formatShares(holding.quantity)) shares")
                            .font(.system(size: 10))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                }
                .frame(width: nameColumnWidth, alignment: .leading)
                
                // Sparkline stretches to fill available space
                stockSparklineView(for: stock, width: availableSparkWidth)
                
                // Price and change - fixed width for consistent alignment
                VStack(alignment: .trailing, spacing: 1) {
                    Text(formatCurrency(stock.currentPrice))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .monospacedDigit()
                    
                    HStack(spacing: 2) {
                        Image(systemName: stock.changePercent >= 0 ? "arrow.up" : "arrow.down")
                            .font(.system(size: 8, weight: .bold))
                        
                        Text(formatPercent(stock.changePercent))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    .foregroundColor(stock.changePercent >= 0 ? .green : .red)
                }
                .frame(width: priceColumnWidth, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 56)  // Fixed row height for consistent layout
        .contentShape(Rectangle())
    }
    
    // MARK: - Stock Sparkline View
    
    /// Keep sparkline identity stable when only color/percent changes.
    private func sparklineIdentity(for spark: [Double]) -> Int {
        guard !spark.isEmpty else { return 0 }
        var hasher = Hasher()
        let quantizedCount = (spark.count / 10) * 10
        hasher.combine(quantizedCount)
        let validValues = spark.filter { $0.isFinite && $0 > 0 }
        if let minV = validValues.min() { hasher.combine(Int(minV)) }
        if let maxV = validValues.max() { hasher.combine(Int(maxV)) }
        return hasher.finalize()
    }
    
    @ViewBuilder
    private func stockSparklineView(for stock: CachedStock, width: CGFloat) -> some View {
        let sparklineData = sparklineService.sparklineCache[stock.symbol] ?? []
        let isPositive = stock.changePercent >= 0
        
        if sparklineData.count >= 10 {
            // Premium sparkline matching watchlist styling - wider and more visible
            SparklineView(
                data: sparklineData,
                isPositive: isPositive,
                overrideColor: nil,
                height: 34,                      // Taller for better visibility (was 30)
                lineWidth: SparklineConsistency.listLineWidth,
                verticalPaddingRatio: SparklineConsistency.listVerticalPaddingRatio,
                fillOpacity: SparklineConsistency.listFillOpacity,
                gradientStroke: true,
                showEndDot: true,                // Show current price point (was false)
                leadingFade: 0.0,
                trailingFade: 0.0,
                showTrailHighlight: false,
                trailLengthRatio: 0.0,
                endDotPulse: false,
                backgroundStyle: .none,
                cornerRadius: 0,
                glowOpacity: SparklineConsistency.listGlowOpacity,
                glowLineWidth: SparklineConsistency.listGlowLineWidth,
                smoothSamplesPerSegment: SparklineConsistency.listSmoothSamplesPerSegment,
                maxPlottedPoints: SparklineConsistency.listMaxPlottedPoints,
                showBackground: false,
                showExtremaDots: false,
                neonTrail: false,
                crispEnds: true,
                horizontalInset: SparklineConsistency.listHorizontalInset,
                compact: false,                  // Full rendering mode (was true)
                seriesOrder: .oldestToNewest
            )
            .frame(width: width, height: 34)
            .padding(.trailing, SparklineConsistency.listHorizontalInset)
            .clipped()
            .padding(.trailing, -SparklineConsistency.listHorizontalInset)
            .id(sparklineIdentity(for: sparklineData))
            .transaction { $0.disablesAnimations = true }
            // GLOW FIX v23: Removed .drawingGroup() — it flattens the 3-layer blur glow
            // into a flat bitmap, making it look like a "highlighter" instead of a luminous glow.
            // Same fix as WatchlistSection and CoinRowView.
            .accessibilityHidden(true)
        } else {
            // Placeholder when sparkline data is loading - subtle shimmer effect
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.gray.opacity(0.1),
                            Color.gray.opacity(0.15),
                            Color.gray.opacity(0.1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: width, height: 34)
                .accessibilityHidden(true)
        }
    }
    
    // Format shares count
    private func formatShares(_ value: Double) -> String {
        if value == floor(value) {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.2f", value)
        }
    }
    
    // MARK: - See All Stocks Row (using standard SectionCTAButton for consistency)
    
    private var seeAllStocksRow: some View {
        // Show actual count if available, otherwise show approximate count
        // Uses stockOnlyCount to exclude commodity futures (shown in Commodities section)
        let stockCount = marketCache.stockOnlyCount > 0 ? marketCache.stockOnlyCount : 19
        return SectionCTAButton(
            title: "Browse Stock Market",
            icon: "chart.line.uptrend.xyaxis",
            badge: "\(stockCount) stocks",
            showGoldBar: true,
            accentColor: BrandColors.silverBase,
            compact: true
        ) {
            onOpenMarketView()
        }
    }
    
    // MARK: - Formatters
    
    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = CurrencyManager.currencyCode
        
        if value >= 1_000_000 {
            formatter.maximumFractionDigits = 1
            return "$\(String(format: "%.1fM", value / 1_000_000))"
        } else if value >= 1_000 {
            formatter.maximumFractionDigits = 0
            return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
        } else {
            formatter.maximumFractionDigits = 2
            return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
        }
    }
    
    private func formatPercent(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", value))%"
    }
    
    // MARK: - Company Name Abbreviation
    
    /// Strip common suffixes from company names for cleaner display in compact rows.
    /// "Amazon.com Inc." → "Amazon.com", "NVIDIA Corporation" → "NVIDIA",
    /// "Meta Platforms Inc." → "Meta Platforms", "Apple Inc." → "Apple"
    private static func abbreviateCompanyName(_ name: String) -> String {
        var abbreviated = name
        let suffixes = [
            ", Inc.", " Inc.", ", Corp.", " Corp.",
            " Corporation", " Incorporated",
            " Holdings", " Holding",
            ", Ltd.", " Ltd.", " Limited",
            " Company", " Co.",
            " Class A", " Class B", " Class C",
            " Cl A", " Cl B", " Cl C",
        ]
        for suffix in suffixes {
            if abbreviated.hasSuffix(suffix) {
                abbreviated = String(abbreviated.dropLast(suffix.count))
                break  // Only strip one suffix
            }
        }
        return abbreviated
    }
}

// MARK: - Preview

#Preview("With Holdings") {
    StocksOverviewSection()
        .environmentObject(PortfolioViewModel.sample)
        .preferredColorScheme(.dark)
}

#Preview("Empty State") {
    StocksOverviewSection()
        .environmentObject({
            let vm = PortfolioViewModel.sample
            // Clear stocks for empty preview
            return vm
        }())
        .preferredColorScheme(.dark)
}
