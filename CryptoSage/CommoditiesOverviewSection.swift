//
//  CommoditiesOverviewSection.swift
//  CryptoSage
//
//  Created by CryptoSage on 1/30/26.
//  Home page section showing quick overview of commodities and precious metals.
//

import SwiftUI
import Combine

struct CommoditiesOverviewSection: View {
    @EnvironmentObject var portfolioVM: PortfolioViewModel
    // PERFORMANCE FIX v20: Removed @EnvironmentObject appState (18+ @Published)
    // PERFORMANCE FIX: Avoid full-section re-renders on every publisher tick.
    // We consume shared singletons and trigger controlled refreshes via debounced onReceive.
    private var marketCache: StockMarketCache { StockMarketCache.shared }
    private var commodityPriceManager: CommodityLivePriceManager { CommodityLivePriceManager.shared }
    private var sparklineService: StockSparklineService { StockSparklineService.shared }
    @State private var commodityDataTick: UInt = 0
    @Environment(\.colorScheme) private var colorScheme
    
    var onOpenCommodityHolding: (Holding) -> Void = { _ in }
    var onOpenMarketCommodity: (CachedStock) -> Void = { _ in }
    var onOpenLiveCommodity: (CommodityInfo) -> Void = { _ in }
    var onOpenMarketView: () -> Void = {}
    
    // MARK: - Third Slot Rotation
    // Rotates the third commodity slot between different commodities for variety
    // Includes energy commodities (natural gas, oil, brent) more frequently by design
    @State private var thirdSlotRotationIndex: Int = 0
    // Weighted rotation: energy items appear more often since users want to see gas/oil prices
    // Pattern: metal, energy, metal, energy, energy, metal, energy, energy
    private let thirdSlotCandidates = [
        "platinum",     // Precious metal
        "natural_gas",  // Energy - user requested more visibility
        "palladium",    // Precious metal
        "crude_oil",    // Energy
        "natural_gas",  // Energy - appears twice for higher frequency
        "copper",       // Industrial metal
        "brent_oil",    // Energy
        "gasoline"      // Energy - RBOB gas
    ]
    private let rotationInterval: TimeInterval = 20 // Rotate every 20 seconds for more variety
    
    /// Current third slot commodity based on rotation
    private var currentThirdSlotCommodity: String {
        thirdSlotCandidates[thirdSlotRotationIndex % thirdSlotCandidates.count]
    }
    
    private var isDark: Bool { colorScheme == .dark }
    
    // MARK: - Layout Constants (matching stocks section and watchlist for consistency)
    private let minSparkWidth: CGFloat = 120   // Minimum sparkline width - wider for better visibility
    private let iconSize: CGFloat = 38         // Commodity icon size
    private let priceColumnWidth: CGFloat = 85 // Price + change column width (wider for $2,035.50)
    private let nameColumnWidth: CGFloat = 80  // Symbol + commodity name column width
    
    // Check if user has real commodity holdings
    private var hasRealHoldings: Bool {
        !portfolioVM.commodityHoldings.isEmpty
    }
    
    // User's commodity holdings
    private var userHoldings: [Holding] {
        portfolioVM.commodityHoldings
    }
    
    // Fallback precious metals data for instant display while live prices load
    // Prices are approximate Feb 2026 values - changes set to 0 (unavailable until live data loads)
    private static let fallbackCommodities: [CachedStock] = [
        CachedStock(
            symbol: "gold",
            name: "Gold",
            currentPrice: 4967.00,  // Updated Feb 2026
            change: 0,             // Set to 0 - no fake data
            changePercent: 0,      // Will show "—" until live data available
            dayHigh: 4967.00,
            dayLow: 4967.00,
            previousClose: 4967.00,
            marketCap: nil,
            volume: nil,
            assetType: .commodity,
            exchange: nil,
            sector: nil,
            lastUpdated: Date()
        ),
        CachedStock(
            symbol: "silver",
            name: "Silver",
            currentPrice: 76.92,  // Updated Feb 2026
            change: 0,            // Set to 0 - no fake data
            changePercent: 0,     // Will show "—" until live data available
            dayHigh: 76.92,
            dayLow: 76.92,
            previousClose: 76.92,
            marketCap: nil,
            volume: nil,
            assetType: .commodity,
            exchange: nil,
            sector: nil,
            lastUpdated: Date()
        ),
        CachedStock(
            symbol: "platinum",
            name: "Platinum",
            currentPrice: 2100.00,  // Updated Feb 2026
            change: 0,             // Set to 0 - no fake data
            changePercent: 0,      // Will show "—" until live data available
            dayHigh: 2100.00,
            dayLow: 2100.00,
            previousClose: 2100.00,
            marketCap: nil,
            volume: nil,
            assetType: .commodity,
            exchange: nil,
            sector: nil,
            lastUpdated: Date()
        )
    ]
    
    // Get commodities from live price manager (primary source for homepage)
    private var liveCommodities: [CachedStock] {
        // Convert CommodityPriceData to CachedStock for unified display
        // Gold and Silver are always first two, third slot rotates between options
        let priorityOrder = ["gold", "silver", currentThirdSlotCommodity]
        
        let sortedPrices = commodityPriceManager.prices.values.sorted { a, b in
            let aIndex = priorityOrder.firstIndex(of: a.id) ?? 999
            let bIndex = priorityOrder.firstIndex(of: b.id) ?? 999
            return aIndex < bIndex
        }
        
        // If we have live prices, filter to only show the priority items
        if !sortedPrices.isEmpty {
            let prioritySet = Set(priorityOrder)
            let filteredPrices = sortedPrices.filter { prioritySet.contains($0.id) }
            
            // If we have the priority items, use them; otherwise fall back to sorted
            let pricesToUse = filteredPrices.isEmpty ? Array(sortedPrices.prefix(3)) : Array(filteredPrices.prefix(3))
            
            return pricesToUse.map { priceData in
                let info = CommoditySymbolMapper.getCommodityById(priceData.id)
                // Use change24h if available, otherwise 0 (will show "—" in UI)
                let changePercent = priceData.change24h ?? 0
                return CachedStock(
                    symbol: info?.yahooSymbol ?? priceData.symbol,
                    name: priceData.name,
                    currentPrice: priceData.price,
                    change: 0,
                    changePercent: changePercent,
                    dayHigh: priceData.price,
                    dayLow: priceData.price,
                    previousClose: priceData.previousClose ?? priceData.price,
                    marketCap: nil,
                    volume: nil,
                    assetType: .commodity,
                    exchange: nil,
                    sector: nil,
                    lastUpdated: priceData.lastUpdated
                )
            }
        }
        
        // Fallback to sample data for instant display
        return Self.fallbackCommodities
    }
    
    // Get commodities from market cache (fallback)
    private var marketCommodities: [CachedStock] {
        let cached = marketCache.allStocks().filter { $0.assetType == .commodity }
        // If cache has commodities, return them; otherwise use fallback
        return cached.isEmpty ? Self.fallbackCommodities : cached
    }
    
    // Display commodities - prioritize holdings, then live prices, fallback to sample data
    // Always returns data for instant display
    private var displayCommodities: [CachedStock] {
        if hasRealHoldings {
            // Convert holdings to CachedStock for unified display
            return userHoldings.prefix(5).compactMap { holding in
                let symbol = holding.ticker ?? holding.coinSymbol
                // Try to get live price data first
                if let priceData = commodityPriceManager.getPriceBySymbol(symbol) {
                    // Use change24h if available, otherwise 0
                    let changePercent = priceData.change24h ?? 0
                    return CachedStock(
                        symbol: symbol,
                        name: priceData.name,
                        currentPrice: priceData.price,
                        change: 0,
                        changePercent: changePercent,
                        dayHigh: priceData.price,
                        dayLow: priceData.price,
                        previousClose: priceData.previousClose ?? priceData.price,
                        marketCap: nil,
                        volume: nil,
                        assetType: .commodity,
                        exchange: nil,
                        sector: nil,
                        lastUpdated: priceData.lastUpdated
                    )
                }
                // Fall back to cached data
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
                    assetType: .commodity,
                    exchange: nil,
                    sector: nil,
                    lastUpdated: Date()
                )
            }
        } else {
            // liveCommodities now always returns data (live or fallback)
            return liveCommodities
        }
    }
    
    // Total commodity value (only for holdings mode)
    private var commoditiesTotal: Double {
        hasRealHoldings ? userHoldings.reduce(0) { $0 + $1.currentValue } : 0
    }
    
    // Commodity count - show total available commodities
    private var commodityCount: Int {
        if hasRealHoldings {
            return userHoldings.count
        }
        // Show total supported commodities count
        return CommoditySymbolMapper.allCommodities.count
    }
    
    // Check if we have live price data
    private var hasLiveData: Bool {
        commodityPriceManager.hasLiveData
    }
    
    // Data source text using the new dataStatus from price manager
    private var dataSourceText: String {
        commodityPriceManager.dataStatus.displayText
    }
    
    // Whether data is loading (for UI feedback)
    private var isLoadingData: Bool {
        commodityPriceManager.isLoading
    }
    
    var body: some View {
        // Trigger view recompute only on debounced refresh ticks.
        let _ = commodityDataTick
        
        VStack(alignment: .leading, spacing: 0) {
            // Section Header
            sectionHeader
            
            // Content - always shows data (fallback ensures displayCommodities is never empty)
            commoditiesContent
        }
        .task {
            // Tab-gating: only run Home commodity work while Home tab is active.
            guard AppState.shared.selectedTab == .home else { return }
            // If section appears during startup, wait briefly instead of exiting.
            // Exiting here can delay live commodity data until user navigates away/back.
            if isInGlobalStartupPhase() {
                #if DEBUG
                print("📊 [CommoditiesOverviewSection] Startup phase active — brief defer")
                #endif
                // FIX: Reduced from 250ms to 100ms — CommodityLivePriceManager no longer
                // has its own startup sleep, so this is the only remaining gate
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard AppState.shared.selectedTab == .home else { return }
            }
            
            // Start live commodity price updates (precious metals from Firebase, others from Yahoo)
            // This fetches Gold, Silver, Platinum, Palladium, Copper, Oil, Gas, etc.
            if !commodityPriceManager.isPolling {
                // Track all commodities that appear in the third-slot rotation + defaults
                let commoditiesToTrack = Set([
                    "gold", "silver", "platinum", "palladium",
                    "copper", "crude_oil", "natural_gas", "brent_oil", "gasoline"
                ])
                commodityPriceManager.startPolling(for: commoditiesToTrack)
            }
            
            // Fetch row sparklines immediately from current display commodities.
            // This avoids a long placeholder state while waiting for background delays.
            let initialCommodities = Array(displayCommodities.prefix(3))
            let initialYahooSymbols = initialCommodities.compactMap { commodity -> String? in
                if let info = CommoditySymbolMapper.getCommodity(for: commodity.symbol) {
                    return info.yahooSymbol
                }
                if commodity.symbol.contains("=F") {
                    return commodity.symbol
                }
                return nil
            }
            if !initialYahooSymbols.isEmpty {
                await sparklineService.fetchSparklines(for: initialYahooSymbols)
            }
            
            // PERFORMANCE FIX: Defer sparkline fetching until after startup
            // Sparklines are nice-to-have but not critical for initial display
            Task.detached(priority: .utility) { @MainActor in
                // Keep only a short settle delay for follow-up symbols from live updates.
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                guard AppState.shared.selectedTab == .home else { return }
                
                // Fetch sparklines for displayed commodities (use Yahoo symbols for historical data)
                let commoditiesToDisplay = Array(await MainActor.run { self.displayCommodities.prefix(3) })
                let yahooSymbols = commoditiesToDisplay.compactMap { commodity -> String? in
                    // Convert to Yahoo symbol for sparkline fetch
                    if let info = CommoditySymbolMapper.getCommodity(for: commodity.symbol) {
                        return info.yahooSymbol
                    }
                    // Already a Yahoo symbol if contains =F
                    if commodity.symbol.contains("=F") {
                        return commodity.symbol
                    }
                    return nil
                }
                
                if !yahooSymbols.isEmpty {
                    await self.sparklineService.fetchSparklines(for: yahooSymbols)
                }
            }
            
            // PERFORMANCE FIX: REMOVED - Don't refresh market cache here!
            // The CommodityLivePriceManager already provides live prices via Firebase.
            // The marketCache.refresh() was triggering 19 unnecessary Yahoo Finance API calls.
            // If market cache data is needed, let StocksOverviewSection handle it when visible.
        }
        .onDisappear {
            if AppState.shared.selectedTab != .home {
                commodityPriceManager.stopPolling()
            }
        }
        // MARK: - Third Slot Rotation Timer
        // Rotates the third commodity every 30 seconds for variety
        // PERFORMANCE FIX v19: Changed .common to .default - timer pauses during scroll
        .onReceive(Timer.publish(every: rotationInterval, on: .main, in: .default).autoconnect()) { _ in
            // PERFORMANCE FIX: Skip rotation animation during scroll
            guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                thirdSlotRotationIndex = (thirdSlotRotationIndex + 1) % thirdSlotCandidates.count
            }
        }
        // Debounced updates prevent high-frequency redraws while preserving freshness.
        .onReceive(CommodityLivePriceManager.shared.objectWillChange.debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)) { _ in
            guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
            commodityDataTick &+= 1
        }
        .onReceive(StockSparklineService.shared.objectWillChange.debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)) { _ in
            guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
            commodityDataTick &+= 1
        }
        .onReceive(StockMarketCache.shared.objectWillChange.debounce(for: .seconds(1), scheduler: DispatchQueue.main)) { _ in
            guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
            commodityDataTick &+= 1
        }
        .onReceive(AppState.shared.$dismissHomeSubviews) { _ in }
    }
    
    // MARK: - Section Header
    
    private var sectionHeader: some View {
        HStack(spacing: 8) {
            // Gold accent icon - commodity cube icon
            GoldHeaderGlyph(systemName: "cube.fill")
            
            Text("Commodities & Metals")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            // Only show badge when NOT live (loading, cached, or no data)
            // Live is the expected state - no need to announce it
            if commodityPriceManager.dataStatus != .live {
                dataSourceBadge
            }
            
            Spacer()
            
            // Total value with subtle styling
            if commoditiesTotal > 0 {
                Text(formatCurrency(commoditiesTotal))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .monospacedDigit()
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    // MARK: - Data Source Badge (only shown for non-live states)
    
    @ViewBuilder
    private var dataSourceBadge: some View {
        let status = commodityPriceManager.dataStatus
        let color: Color = {
            switch status {
            case .loading: return .blue
            case .live: return .green
            case .cached: return .yellow
            case .noData: return .orange
            }
        }()
        let isAnimating = status == .loading
        
        HStack(spacing: 4) {
            if isAnimating {
                // Pulsing dot for loading state
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
                    .opacity(0.8)
                    .modifier(PulsingAnimation())
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
            }
            
            Text(dataSourceText)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(color)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
        )
    }
    
    // MARK: - Pulsing Animation Modifier
    
    private struct PulsingAnimation: ViewModifier {
        @State private var isPulsing = false
        
        func body(content: Content) -> some View {
            content
                .scaleEffect(isPulsing ? 1.3 : 1.0)
                .opacity(isPulsing ? 0.6 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
                .onAppear { guard !globalAnimationsKilled else { return }; isPulsing = true }
        }
    }
    
    // MARK: - Commodities Content
    
    private var commoditiesContent: some View {
        VStack(spacing: 0) {
            // Minimal subheader - only show timestamp when not live for transparency
            if !hasRealHoldings && !displayCommodities.isEmpty {
                if let lastUpdate = commodityPriceManager.lastUpdateTime,
                   commodityPriceManager.dataStatus != .live {
                    HStack {
                        Spacer()
                        Text(timeAgoString(from: lastUpdate))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 2)
                }
            }
            
            // Commodity rows card with premium styling
            VStack(spacing: 0) {
                // Show loading shimmer when we don't have real live data yet
                // (fallback data has changePercent == 0 for all items)
                let realLiveData = !commodityPriceManager.prices.isEmpty
                let topDisplayCommodities = Array(displayCommodities.prefix(3))
                
                if !realLiveData && isLoadingData {
                    // Show data with shimmer for change percentages
                    ForEach(topDisplayCommodities) { commodity in
                        commodityRowWithLoadingChange(commodity)
                            .onTapGesture {
                                #if os(iOS)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                #endif
                                if let info = CommoditySymbolMapper.getCommodity(for: commodity.symbol) {
                                    onOpenLiveCommodity(info)
                                } else {
                                    onOpenMarketCommodity(commodity)
                                }
                            }
                        
                        if commodity.id != topDisplayCommodities.last?.id {
                            Divider()
                                .padding(.horizontal, 14)
                                .opacity(0.5)
                        }
                    }
                } else {
                    // Show top 3 commodities on homepage with full data
                    ForEach(topDisplayCommodities) { commodity in
                        commodityRow(commodity)
                            .onTapGesture {
                                #if os(iOS)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                #endif
                                // Try to find commodity info for proper navigation
                                if let info = CommoditySymbolMapper.getCommodity(for: commodity.symbol) {
                                    onOpenLiveCommodity(info)
                                } else {
                                    // Fallback to CachedStock navigation
                                    onOpenMarketCommodity(commodity)
                                }
                            }
                        
                        if commodity.id != topDisplayCommodities.last?.id {
                            Divider()
                                .padding(.horizontal, 14)
                                .opacity(0.5)
                        }
                    }
                }
                
                // Integrated "See All" / "Browse Market" row at bottom
                Divider()
                    .padding(.horizontal, 14)
                    .opacity(0.5)
                
                seeAllCommoditiesRow
            }
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        DS.Adaptive.divider.opacity(isDark ? 0.4 : 0.2),
                        lineWidth: 1
                    )
            )
        }
    }

    // MARK: - Loading Shimmer Row
    
    private var commodityShimmerRow: some View {
        HStack(spacing: 8) {
            // Shimmer icon
            Circle()
                .fill(shimmerGradient)
                .frame(width: iconSize, height: iconSize)
            
            // Shimmer name and badge
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(shimmerGradient)
                    .frame(width: 50, height: 14)
                
                RoundedRectangle(cornerRadius: 3)
                    .fill(shimmerGradient)
                    .frame(width: 35, height: 10)
            }
            .frame(width: nameColumnWidth, alignment: .leading)
            
            Spacer()
            
            // Shimmer sparkline
            RoundedRectangle(cornerRadius: 4)
                .fill(shimmerGradient)
                .frame(width: minSparkWidth, height: 34)
            
            // Shimmer price
            VStack(alignment: .trailing, spacing: 4) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(shimmerGradient)
                    .frame(width: 65, height: 14)
                
                RoundedRectangle(cornerRadius: 3)
                    .fill(shimmerGradient)
                    .frame(width: 45, height: 10)
            }
            .frame(width: priceColumnWidth, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
    }
    
    @State private var shimmerPhase: CGFloat = 0
    
    private var shimmerGradient: LinearGradient {
        LinearGradient(
            colors: [
                DS.Adaptive.textTertiary.opacity(0.1),
                DS.Adaptive.textTertiary.opacity(0.2),
                DS.Adaptive.textTertiary.opacity(0.1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    // MARK: - Commodity Row with Loading Change
    
    /// Shows commodity with price but shimmer for change percentage while loading
    private func commodityRowWithLoadingChange(_ commodity: CachedStock) -> some View {
        GeometryReader { geometry in
            let rowPadding: CGFloat = 28
            let spacing: CGFloat = 24
            let fixedWidth = iconSize + nameColumnWidth + priceColumnWidth + rowPadding + spacing
            let availableSparkWidth = max(minSparkWidth, geometry.size.width - fixedWidth)
            
            HStack(spacing: 8) {
                // Distinctive commodity icon
                CommodityIconView(
                    commodityId: CommoditySymbolMapper.getCommodity(for: commodity.symbol)?.id ?? commodity.symbol.lowercased(),
                    size: iconSize
                )
                
                // Symbol and Name
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(CommoditySymbolMapper.getCommodity(for: commodity.symbol)?.displaySymbol ?? commodity.symbol.uppercased())
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        // Type badge
                        Text(commodityTypeBadge(commodity.symbol))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(commodityBadgeColor(commodity.symbol).opacity(0.9))
                            .clipShape(Capsule())
                    }
                    
                    Text(commodity.name)
                        .font(.system(size: 11))
                        .foregroundColor(DS.Adaptive.textSecondary)
                        .lineLimit(1)
                }
                .frame(width: nameColumnWidth, alignment: .leading)
                
                // Sparkline shimmer while loading
                RoundedRectangle(cornerRadius: 4)
                    .fill(shimmerGradient)
                    .frame(width: availableSparkWidth, height: 34)
                    .shimmer()
                
                // Price (show actual) and change (shimmer)
                VStack(alignment: .trailing, spacing: 4) {
                    // Show fallback price
                    Text(formatCommodityPrice(commodity.currentPrice, symbol: commodity.symbol))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .monospacedDigit()
                    
                    // Shimmer for change percentage
                    RoundedRectangle(cornerRadius: 3)
                        .fill(DS.Adaptive.textTertiary.opacity(0.2))
                        .frame(width: 50, height: 14)
                        .shimmer()
                }
                .frame(width: priceColumnWidth, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 56)
        .contentShape(Rectangle())
    }
    
    // MARK: - Time Ago Helper
    
    private func timeAgoString(from date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 {
            return "Just now"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "\(minutes)m ago"
        } else {
            let hours = seconds / 3600
            return "\(hours)h ago"
        }
    }
    
    // MARK: - Commodity Row (for CachedStock)
    
    private func commodityRow(_ commodity: CachedStock) -> some View {
        GeometryReader { geometry in
            // Calculate dynamic sparkline width based on available space
            let rowPadding: CGFloat = 28  // 14 * 2 horizontal padding
            let spacing: CGFloat = 24     // spacing between elements (8 * 3)
            let fixedWidth = iconSize + nameColumnWidth + priceColumnWidth + rowPadding + spacing
            let availableSparkWidth = max(minSparkWidth, geometry.size.width - fixedWidth)
            
            HStack(spacing: 8) {
                // Distinctive commodity icon
                CommodityIconView(
                    commodityId: CommoditySymbolMapper.getCommodity(for: commodity.symbol)?.id ?? commodity.symbol.lowercased(),
                    size: iconSize
                )
                
                // Symbol and name - fixed width to ensure consistent layout
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(commodityDisplaySymbol(commodity.symbol))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        // Commodity type badge
                        Text(commodityTypeBadge(commodity.symbol))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(commodityBadgeColor(commodity.symbol).opacity(0.9))
                            .clipShape(Capsule())
                    }
                    
                    Text(commodity.name)
                        .font(.system(size: 11))
                        .foregroundColor(DS.Adaptive.textSecondary)
                        .lineLimit(1)
                    
                    // Show quantity if user owns this commodity
                    if let holding = userHoldings.first(where: { ($0.ticker ?? $0.coinSymbol) == commodity.symbol }) {
                        Text("\(formatQuantity(holding.quantity)) oz")
                            .font(.system(size: 10))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                }
                .frame(width: nameColumnWidth, alignment: .leading)
                
                // Sparkline stretches to fill available space
                commoditySparklineView(for: commodity, width: availableSparkWidth)
                
                // Price and change - fixed width for consistent alignment
                VStack(alignment: .trailing, spacing: 1) {
                    Text(formatCommodityPrice(commodity.currentPrice, symbol: commodity.symbol))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .monospacedDigit()
                    
                    // Show loading shimmer, "—" for no data, or actual change
                    if isLoadingData && commodity.changePercent == 0 {
                        // Loading shimmer for change
                        RoundedRectangle(cornerRadius: 3)
                            .fill(DS.Adaptive.textTertiary.opacity(0.2))
                            .frame(width: 45, height: 14)
                    } else if commodity.changePercent == 0 && !hasLiveData {
                        // No data available - shimmer placeholder
                        ShimmerBar(height: 12, cornerRadius: 3)
                            .frame(width: 42)
                    } else {
                        // Show actual change percentage
                        HStack(spacing: 2) {
                            Image(systemName: commodity.changePercent >= 0 ? "arrow.up" : "arrow.down")
                                .font(.system(size: 8, weight: .bold))
                            
                            Text(formatPercent(commodity.changePercent))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                        }
                        .foregroundColor(commodity.changePercent >= 0 ? .green : .red)
                    }
                }
                .frame(width: priceColumnWidth, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 56)  // Fixed row height for consistent layout
        .contentShape(Rectangle())
    }
    
    // MARK: - Commodity Sparkline View
    
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
    private func commoditySparklineView(for commodity: CachedStock, width: CGFloat) -> some View {
        // Get Yahoo symbol for sparkline lookup
        let yahooSymbol: String = {
            if let info = CommoditySymbolMapper.getCommodity(for: commodity.symbol) {
                return info.yahooSymbol
            }
            return commodity.symbol
        }()
        
        let sparklineData = sparklineService.sparklineCache[yahooSymbol] ?? []
        let isPositive = commodity.changePercent >= 0
        
        if sparklineData.count >= 10 {
            // Premium sparkline matching watchlist styling - wider and more visible
            SparklineView(
                data: sparklineData,
                isPositive: isPositive,
                // Keep commodity identity colors (gold/silver/oil/gas/etc.) instead of gain/loss colors.
                overrideColor: commodityBadgeColor(commodity.symbol),
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
                            commodityBadgeColor(commodity.symbol).opacity(0.1),
                            commodityBadgeColor(commodity.symbol).opacity(0.15),
                            commodityBadgeColor(commodity.symbol).opacity(0.1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: width, height: 34)
                .accessibilityHidden(true)
        }
    }
    
    // MARK: - Commodity Helpers
    
    /// Convert futures symbol to display symbol (handles both Yahoo and Coinbase symbols)
    private func commodityDisplaySymbol(_ symbol: String) -> String {
        // First try to get from CommoditySymbolMapper
        if let info = CommoditySymbolMapper.getCommodity(for: symbol) {
            return info.displaySymbol
        }
        
        // Fallback for Yahoo symbols
        switch symbol {
        case "GC=F": return "GOLD"
        case "SI=F": return "SILVER"
        case "PL=F": return "PLAT"
        case "PA=F": return "PALL"
        case "HG=F": return "COPPER"
        case "CL=F": return "OIL"
        case "BZ=F": return "BRENT"
        case "NG=F": return "NATGAS"
        case "HO=F": return "HTOIL"
        case "RB=F": return "GAS"
        case "ALI=F": return "ALUM"
        case "ZC=F": return "CORN"
        case "ZS=F": return "SOY"
        case "ZW=F": return "WHEAT"
        case "KC=F": return "COFFEE"
        case "CC=F": return "COCOA"
        case "CT=F": return "COTTON"
        case "SB=F": return "SUGAR"
        case "ZO=F": return "OATS"
        case "ZR=F": return "RICE"
        case "OJ=F": return "OJ"
        case "LBS=F": return "LUMBER"
        case "LE=F": return "CATTLE"
        case "HE=F": return "HOGS"
        case "GF=F": return "FEEDER"
        default: return symbol
        }
    }
    
    /// Get badge text for commodity type
    private func commodityTypeBadge(_ symbol: String) -> String {
        // Try to get type from CommoditySymbolMapper first
        if let type = CommoditySymbolMapper.commodityType(for: symbol) {
            switch type {
            case .preciousMetal: return "METAL"
            case .industrialMetal: return "IND"
            case .energy: return "ENERGY"
            case .agriculture: return "AGRI"
            case .livestock: return "LIVE"
            }
        }
        
        // Fallback for Yahoo symbols
        switch symbol {
        case "GC=F", "SI=F", "PL=F", "PA=F":
            return "METAL"
        case "HG=F", "ALI=F":
            return "IND"
        case "CL=F", "BZ=F", "NG=F", "HO=F", "RB=F":
            return "ENERGY"
        case "ZC=F", "ZS=F", "ZW=F", "KC=F", "CC=F", "CT=F", "SB=F", "ZO=F", "ZR=F", "OJ=F", "LBS=F":
            return "AGRI"
        case "LE=F", "HE=F", "GF=F":
            return "LIVE"
        default:
            return "COMM"
        }
    }
    
    /// Get badge/sparkline color for commodity
    /// Individual precious metals get distinct colors for better visual distinction
    private func commodityBadgeColor(_ symbol: String) -> Color {
        if let commodity = CommoditySymbolMapper.getCommodity(for: symbol) {
            switch commodity.id {
            case "gold":
                return Color(red: 1.0, green: 0.84, blue: 0.0)
            case "silver":
                return Color(red: 0.75, green: 0.77, blue: 0.82)
            case "platinum":
                return Color(red: 0.90, green: 0.89, blue: 0.87)
            case "palladium":
                return Color(red: 0.70, green: 0.72, blue: 0.75)
            case "copper":
                return Color(red: 0.72, green: 0.45, blue: 0.20)
            case "aluminum":
                return Color(red: 0.77, green: 0.77, blue: 0.77)
            case "crude_oil", "brent_oil":
                return Color(red: 0.24, green: 0.24, blue: 0.27)
            case "natural_gas":
                return Color(red: 0.20, green: 0.50, blue: 0.90)
            case "heating_oil":
                return Color(red: 0.95, green: 0.55, blue: 0.20)
            case "gasoline":
                return Color(red: 0.98, green: 0.66, blue: 0.18)
            case "corn":
                return Color(red: 0.95, green: 0.85, blue: 0.30)
            case "wheat":
                return Color(red: 0.85, green: 0.65, blue: 0.30)
            case "soybeans":
                return Color(red: 0.65, green: 0.75, blue: 0.35)
            case "coffee":
                return Color(red: 0.45, green: 0.30, blue: 0.15)
            case "cocoa":
                return Color(red: 0.35, green: 0.20, blue: 0.10)
            case "cotton":
                return Color(red: 0.95, green: 0.95, blue: 0.95)
            case "sugar":
                return Color(red: 0.95, green: 0.95, blue: 0.90)
            case "oats":
                return Color(red: 0.85, green: 0.78, blue: 0.55)
            case "rice":
                return Color(red: 0.95, green: 0.93, blue: 0.85)
            case "orange_juice":
                return Color(red: 1.0, green: 0.65, blue: 0.0)
            case "lumber":
                return Color(red: 0.55, green: 0.35, blue: 0.15)
            case "live_cattle":
                return Color(red: 0.60, green: 0.40, blue: 0.25)
            case "lean_hogs":
                return Color(red: 0.85, green: 0.60, blue: 0.60)
            case "feeder_cattle":
                return Color(red: 0.55, green: 0.35, blue: 0.20)
            default:
                break
            }
        }

        let symbolLower = symbol.lowercased()
        
        // Individual precious metal colors - distinct for each metal
        // Gold: Rich warm gold
        if symbolLower.contains("gold") || symbol == "GC=F" || symbolLower == "gc" {
            return Color(red: 1.0, green: 0.84, blue: 0.0) // Rich gold
        }
        // Silver: Cool silver-gray
        if symbolLower.contains("silver") || symbol == "SI=F" || symbolLower == "si" {
            return Color(red: 0.75, green: 0.77, blue: 0.82) // Silver metallic
        }
        // Platinum: Bright platinum white-silver
        if symbolLower.contains("platinum") || symbol == "PL=F" || symbolLower == "pl" {
            return Color(red: 0.90, green: 0.89, blue: 0.87) // Platinum
        }
        // Palladium: Slightly darker silver
        if symbolLower.contains("palladium") || symbol == "PA=F" || symbolLower == "pa" {
            return Color(red: 0.70, green: 0.72, blue: 0.75) // Palladium
        }
        
        // Try to get type from CommoditySymbolMapper for other commodities
        if let type = CommoditySymbolMapper.commodityType(for: symbol) {
            switch type {
            case .preciousMetal: return Color(red: 1.0, green: 0.84, blue: 0.0) // Fallback gold
            case .industrialMetal: return Color.orange
            case .energy: return Color.blue
            case .agriculture: return Color.green
            case .livestock: return Color.brown
            }
        }
        
        // Fallback for Yahoo symbols
        switch symbol {
        case "HG=F", "ALI=F":
            return Color.orange // Industrial metals
        case "CL=F", "BZ=F", "NG=F", "HO=F", "RB=F":
            return Color.blue // Oil, Natural Gas, etc.
        case "ZC=F", "ZS=F", "ZW=F", "KC=F", "CC=F", "CT=F", "SB=F", "ZO=F", "ZR=F", "LBS=F":
            return Color.green // Agriculture
        case "OJ=F":
            return Color.orange // Orange Juice
        case "LE=F", "HE=F", "GF=F":
            return Color.brown // Livestock
        default:
            return Color.gray
        }
    }
    
    /// Format commodity price (per oz for metals, per barrel for oil, etc.)
    private func formatCommodityPrice(_ value: Double, symbol: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = CurrencyManager.currencyCode
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
    
    // Format quantity
    private func formatQuantity(_ value: Double) -> String {
        if value == floor(value) {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.2f", value)
        }
    }
    
    // MARK: - See All Commodities Row (using standard SectionCTAButton for consistency)
    
    private var seeAllCommoditiesRow: some View {
        SectionCTAButton(
            title: "Browse Commodities",
            icon: "cube.fill",
            badge: "\(commodityCount) items",
            showGoldBar: true,
            accentColor: BrandColors.goldBase,
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
        // Show dash for 0% when it indicates no data (handled in display logic)
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", value))%"
    }
    
    private func formatPercent(_ value: Double?) -> String {
        guard let value = value else { return "—" }
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", value))%"
    }
}

// MARK: - Preview

#Preview("With Commodities") {
    CommoditiesOverviewSection()
        .environmentObject(PortfolioViewModel.sample)
        .preferredColorScheme(.dark)
}

#Preview("Empty State") {
    CommoditiesOverviewSection()
        .environmentObject(PortfolioViewModel.sample)
        .preferredColorScheme(.dark)
}
