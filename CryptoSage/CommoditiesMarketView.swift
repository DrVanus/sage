//
//  CommoditiesMarketView.swift
//  CryptoSage
//
//  Created by CryptoSage on 1/30/26.
//  Dedicated view for browsing all available commodities with live prices.
//  Enhanced to match StockMarketView quality and features.
//

import SwiftUI

// MARK: - Commodities Market Segment

enum CommoditiesMarketSegment: String, CaseIterable, Identifiable {
    case all = "All"
    case preciousMetals = "Precious Metals"
    case energy = "Energy"
    case industrial = "Industrial"
    case agriculture = "Agriculture"
    case livestock = "Livestock"
    case gainers = "Gainers"
    case losers = "Losers"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .preciousMetals: return "sparkles"
        case .energy: return "flame.fill"
        case .industrial: return "hammer.fill"
        case .agriculture: return "leaf.fill"
        case .livestock: return "hare.fill"
        case .gainers: return "arrow.up.right"
        case .losers: return "arrow.down.right"
        }
    }
    
    var commodityType: CommodityType? {
        switch self {
        case .all, .gainers, .losers: return nil
        case .preciousMetals: return .preciousMetal
        case .energy: return .energy
        case .industrial: return .industrialMetal
        case .agriculture: return .agriculture
        case .livestock: return .livestock
        }
    }
}

// MARK: - Commodities Sort Option

enum CommoditiesSortOption: String, CaseIterable {
    case name = "Name"
    case price = "Price"
    case change = "Change %"
    case type = "Type"
    
    var icon: String {
        switch self {
        case .name: return "textformat"
        case .price: return "dollarsign"
        case .change: return "percent"
        case .type: return "tag"
        }
    }
}

// MARK: - Commodities Market View

struct CommoditiesMarketView: View {
    @EnvironmentObject var portfolioVM: PortfolioViewModel
    @ObservedObject private var priceManager = CommodityLivePriceManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedSegment: CommoditiesMarketSegment = .all
    @State private var searchText: String = ""
    @State private var selectedCommodity: CommodityInfo?
    @State private var sortOption: CommoditiesSortOption = .name
    @State private var sortAscending: Bool = true
    @State private var isLoading: Bool = true
    @State private var hasLoaded: Bool = false
    @State private var lastUpdate: Date?
    @State private var visibleCount: Int = 30
    
    private var isDark: Bool { colorScheme == .dark }
    
    // Market status (commodities trade 23 hours a day on futures markets)
    // CME Globex: Sunday 5PM CT - Friday 4PM CT (6PM-5PM ET) with daily breaks
    private var isMarketOpen: Bool {
        // Use Eastern timezone for accurate commodity market hours
        guard let easternTZ = TimeZone(identifier: "America/New_York") else {
            // Fallback to simple weekend check
            let calendar = Calendar.current
            let weekday = calendar.component(.weekday, from: Date())
            return weekday != 1 && weekday != 7
        }
        
        var calendar = Calendar.current
        calendar.timeZone = easternTZ
        let weekday = calendar.component(.weekday, from: Date())
        let hour = calendar.component(.hour, from: Date())
        
        // Saturday: Closed all day
        if weekday == 7 { return false }
        
        // Sunday: Opens at 6PM ET
        if weekday == 1 && hour < 18 { return false }
        
        // Friday: Closes at 5PM ET
        if weekday == 6 && hour >= 17 { return false }
        
        return true
    }
    
    // Trading hours description
    private var tradingHoursText: String {
        isMarketOpen ? "24/5" : "Closed"
    }
    
    // Get live price for a commodity
    private func livePrice(for commodity: CommodityInfo) -> CommodityPriceData? {
        priceManager.prices[commodity.id]
    }
    
    // Price with fallback
    private func effectivePrice(for commodity: CommodityInfo) -> Double {
        livePrice(for: commodity)?.price ?? fallbackPrice(for: commodity)
    }
    
    // Change (optional - nil means no data available)
    private func effectiveChange(for commodity: CommodityInfo) -> Double? {
        livePrice(for: commodity)?.change24h
    }
    
    // Top gainers - only include commodities with actual positive change data
    private var topGainers: [CommodityInfo] {
        CommoditySymbolMapper.allCommodities
            .filter { (effectiveChange(for: $0) ?? 0) > 0.01 }  // > 0.01% to avoid noise
            .sorted { (effectiveChange(for: $0) ?? 0) > (effectiveChange(for: $1) ?? 0) }
    }
    
    // Top losers - only include commodities with actual negative change data
    private var topLosers: [CommodityInfo] {
        CommoditySymbolMapper.allCommodities
            .filter { (effectiveChange(for: $0) ?? 0) < -0.01 }  // < -0.01% to avoid noise
            .sorted { (effectiveChange(for: $0) ?? 0) < (effectiveChange(for: $1) ?? 0) }
    }
    
    // Filtered and sorted commodities
    private var displayedCommodities: [CommodityInfo] {
        var commodities = CommoditySymbolMapper.allCommodities
        
        // Filter by segment
        switch selectedSegment {
        case .gainers:
            commodities = topGainers
        case .losers:
            commodities = topLosers
        case .all:
            break
        default:
            if let type = selectedSegment.commodityType {
                commodities = commodities.filter { $0.type == type }
            }
        }
        
        // Filter by search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            commodities = commodities.filter {
                $0.name.lowercased().contains(query) ||
                $0.id.lowercased().contains(query) ||
                $0.yahooSymbol.lowercased().contains(query)
            }
        }
        
        // Sort
        switch sortOption {
        case .name:
            commodities.sort { sortAscending ? $0.name < $1.name : $0.name > $1.name }
        case .price:
            commodities.sort { sortAscending ? effectivePrice(for: $0) < effectivePrice(for: $1) : effectivePrice(for: $0) > effectivePrice(for: $1) }
        case .change:
            // Sort by change, treating nil as 0 for ordering purposes
            commodities.sort { sortAscending ? (effectiveChange(for: $0) ?? 0) < (effectiveChange(for: $1) ?? 0) : (effectiveChange(for: $0) ?? 0) > (effectiveChange(for: $1) ?? 0) }
        case .type:
            commodities.sort { sortAscending ? $0.type.rawValue < $1.type.rawValue : $0.type.rawValue > $1.type.rawValue }
        }
        
        return commodities
    }
    
    // Count for each segment
    private func countForSegment(_ segment: CommoditiesMarketSegment) -> Int {
        switch segment {
        case .all: return CommoditySymbolMapper.allCommodities.count
        case .gainers: return topGainers.count
        case .losers: return topLosers.count
        default:
            if let type = segment.commodityType {
                return CommoditySymbolMapper.commodities(ofType: type).count
            }
            return 0
        }
    }
    
    var body: some View {
        ZStack {
            // Background
            DS.Adaptive.background
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Error banner (if there's an error)
                if priceManager.consecutiveFailures > 0 {
                    errorBanner
                }
                
                // Content
                if !hasLoaded && isLoading {
                    loadingView
                } else if displayedCommodities.isEmpty && !searchText.isEmpty {
                    noSearchResultsView
                } else if displayedCommodities.isEmpty {
                    emptyStateView
                } else {
                    commoditiesListView
                }
            }
        }
        .navigationBarHidden(true)
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
        .navigationDestination(isPresented: Binding(
            get: { selectedCommodity != nil },
            set: { if !$0 { selectedCommodity = nil } }
        )) {
            if let commodity = selectedCommodity {
                CommodityDetailView(commodityInfo: commodity, holding: nil)
                    .environmentObject(portfolioVM)
            }
        }
        .task {
            await loadData()
        }
    }
    
    // MARK: - Load Data
    
    private func loadData() async {
        isLoading = true
        
        // Start polling for all commodities
        if !priceManager.isPolling {
            let allCommodityIds = Set(CommoditySymbolMapper.allCommodities.map { $0.id })
            priceManager.startPolling(for: allCommodityIds)
        }
        
        // Simulate loading delay for skeleton
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        await MainActor.run {
            hasLoaded = true
            isLoading = false
            lastUpdate = Date()
        }
    }
    
    private func refresh() async {
        let allCommodityIds = Set(CommoditySymbolMapper.allCommodities.map { $0.id })
        priceManager.startPolling(for: allCommodityIds)
        lastUpdate = Date()
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        VStack(spacing: 0) {
            // Top bar with back and title
            HStack(spacing: 10) {
                // Back button
                CSNavButton(
                    icon: "chevron.left",
                    action: { dismiss() }
                )
                
                Spacer()
                
                // Title - consistent with other sections
                HStack(spacing: 8) {
                    GoldHeaderGlyph(systemName: "cube.fill")
                    
                    Text("Commodities")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                
                Spacer()
                
                // Market status badge
                marketStatusBadge
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)
            
            // Segment picker
            segmentPicker
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            
            // Search and sort bar
            searchAndSortBar
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            
            Divider()
                .opacity(0.4)
        }
        .background(DS.Adaptive.backgroundSecondary)
    }
    
    // MARK: - Market Status Badge
    
    private var marketStatusBadge: some View {
        let status = priceManager.dataStatus
        let statusColor: Color = {
            switch status {
            case .loading: return .blue
            case .live: return isMarketOpen ? .green : .orange
            case .cached: return .yellow
            case .noData: return .red
            }
        }()
        
        let statusText: String = {
            switch status {
            case .loading: return "Loading"
            case .live: return tradingHoursText
            case .cached: return "Cached"
            case .noData: return "Offline"
            }
        }()
        
        return HStack(spacing: 5) {
            if status == .loading {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)
            } else {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
            }
            
            Text(statusText)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(statusColor.opacity(0.12))
        )
    }
    
    // MARK: - Error Banner
    
    private var errorBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundColor(.orange)
            
            Text("Some prices may be outdated")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.Adaptive.textSecondary)
            
            Spacer()
            
            Button {
                Task {
                    await refresh()
                }
            } label: {
                Text("Retry")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(isDark ? 0.1 : 0.08))
        .overlay(
            Rectangle()
                .fill(Color.orange.opacity(0.3))
                .frame(height: 1),
            alignment: .bottom
        )
    }
    
    // MARK: - Segment Picker
    
    private var segmentPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(CommoditiesMarketSegment.allCases) { segment in
                    segmentButton(segment)
                }
            }
        }
    }
    
    private func segmentButton(_ segment: CommoditiesMarketSegment) -> some View {
        let isSelected = selectedSegment == segment
        let count = countForSegment(segment)
        
        return Button {
            guard selectedSegment != segment else { return }
            
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedSegment = segment
                visibleCount = 30
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: segment.icon)
                    .font(.system(size: 10, weight: .semibold))
                
                Text(segment.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(isSelected ? (isDark ? Color.black : Color.white).opacity(0.7) : DS.Adaptive.textTertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(isSelected
                                    ? (isDark ? Color.black : Color.white).opacity(0.2)
                                    : DS.Adaptive.divider.opacity(0.5))
                        )
                }
            }
            .foregroundColor(isSelected ? (isDark ? Color.black : Color.white) : DS.Adaptive.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isSelected
                        ? (isDark ? Color.white : Color.black)
                        : (isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)))
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Search and Sort Bar
    
    private var searchAndSortBar: some View {
        HStack(spacing: 8) {
            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
                
                TextField("Search commodities...", text: $searchText)
                    .font(.system(size: 13))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
            )
            
            // Sort menu
            Menu {
                ForEach(CommoditiesSortOption.allCases, id: \.self) { option in
                    Button {
                        if sortOption == option {
                            sortAscending.toggle()
                        } else {
                            sortOption = option
                            sortAscending = true
                        }
                    } label: {
                        HStack {
                            Image(systemName: option.icon)
                            Text(option.rawValue)
                            Spacer()
                            if sortOption == option {
                                Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 12, weight: .medium))
                    Text(sortOption.rawValue)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(DS.Adaptive.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                )
            }
        }
    }
    
    // MARK: - Commodities List View
    
    private var commoditiesListView: some View {
        List {
            // Market Movers Section (only for All segment, and only if we have actual movers)
            if selectedSegment == .all && searchText.isEmpty && (!topGainers.isEmpty || !topLosers.isEmpty) {
                marketMoversSection
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            
            // Market Summary Section
            if selectedSegment == .all && searchText.isEmpty {
                marketSummarySection
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            
            // Commodities List
            ForEach(Array(displayedCommodities.prefix(visibleCount))) { commodity in
                commodityRow(commodity)
                    .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .onTapGesture {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        selectedCommodity = commodity
                    }
                    .onAppear {
                        if commodity == displayedCommodities.prefix(visibleCount).last {
                            loadMore()
                        }
                    }
            }
            
            // Load more indicator
            if visibleCount < displayedCommodities.count {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading more...")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                    Spacer()
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            
            // Footer section - shows category info when filtered, or data disclaimer at bottom
            commoditiesFooter
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 16, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            await refresh()
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 50)
        }
    }
    
    // MARK: - Market Movers Section
    
    /// Whether we have enough data to show market movers
    private var hasMarketData: Bool {
        !priceManager.prices.isEmpty && (topGainers.count + topLosers.count) > 0
    }
    
    /// Maximum items to show per mover section (ensures visual balance)
    private var moverDisplayCount: Int {
        // Show same count in both columns for visual balance
        let maxGainers = min(topGainers.count, 4)
        let maxLosers = min(topLosers.count, 4)
        return max(min(maxGainers, maxLosers), min(max(maxGainers, maxLosers), 3))
    }
    
    private var marketMoversSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.orange)
                    Text("Market Movers")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                
                Spacer()
                
                // Last updated time or loading indicator
                if priceManager.isLoading && !hasMarketData {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Loading...")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                } else if let lastUpdate = lastUpdate {
                    Text(timeAgoString(from: lastUpdate))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
            }
            
            HStack(alignment: .top, spacing: 12) {
                // Top Gainers
                moverCard(
                    title: "Top Gainers",
                    icon: "arrow.up.right",
                    color: .green,
                    items: Array(topGainers.prefix(moverDisplayCount)),
                    isGainer: true,
                    totalCount: topGainers.count
                )
                
                // Top Losers
                moverCard(
                    title: "Top Losers",
                    icon: "arrow.down.right",
                    color: .red,
                    items: Array(topLosers.prefix(moverDisplayCount)),
                    isGainer: false,
                    totalCount: topLosers.count
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(DS.Adaptive.divider.opacity(isDark ? 0.3 : 0.15), lineWidth: 1)
        )
    }
    
    /// Reusable mover card component
    private func moverCard(
        title: String,
        icon: String,
        color: Color,
        items: [CommodityInfo],
        isGainer: Bool,
        totalCount: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(color)
                
                Spacer()
                
                if totalCount > 0 {
                    Text("\(totalCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(color.opacity(0.8))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(color.opacity(0.15)))
                }
            }
            
            // Content
            if priceManager.isLoading && items.isEmpty && priceManager.prices.isEmpty {
                // Loading shimmer
                ForEach(0..<3, id: \.self) { _ in
                    moverShimmerRow(color: color)
                }
            } else if items.isEmpty {
                // No data - show friendly message with icon
                VStack(spacing: 6) {
                    Image(systemName: isGainer ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis")
                        .font(.system(size: 18, weight: .light))
                        .foregroundColor(color.opacity(0.4))
                    Text(isGainer ? "No gainers" : "No losers")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                ForEach(items) { commodity in
                    moverRow(commodity, isGainer: isGainer)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(isDark ? 0.08 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
    
    /// Shimmer row for loading state
    private func moverShimmerRow(color: Color) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(0.15))
                    .frame(width: 60, height: 11)
                RoundedRectangle(cornerRadius: 2)
                    .fill(color.opacity(0.1))
                    .frame(width: 40, height: 9)
            }
            Spacer()
            RoundedRectangle(cornerRadius: 3)
                .fill(color.opacity(0.2))
                .frame(width: 50, height: 14)
        }
        .shimmer()
    }
    
    private func moverRow(_ commodity: CommodityInfo, isGainer: Bool) -> some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            selectedCommodity = commodity
        } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(commodity.name)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .lineLimit(1)
                    
                    Text(formatCompactCurrency(effectivePrice(for: commodity)))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                
                Spacer()
                
                Text(formatPercent(effectiveChange(for: commodity)))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(isGainer ? .green : .red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill((isGainer ? Color.green : Color.red).opacity(isDark ? 0.2 : 0.12))
                    )
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Market Summary Section
    
    private var marketSummarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Market Overview")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            HStack(spacing: 10) {
                // Precious Metals summary
                categorySummaryCard(
                    title: "Precious Metals",
                    icon: "sparkles",
                    color: Color.yellow,
                    count: CommoditySymbolMapper.preciousMetals.count,
                    type: .preciousMetal
                )
                
                // Energy summary
                categorySummaryCard(
                    title: "Energy",
                    icon: "flame.fill",
                    color: Color.blue,
                    count: CommoditySymbolMapper.commodities(ofType: .energy).count,
                    type: .energy
                )
            }
            
            HStack(spacing: 10) {
                // Agriculture summary
                categorySummaryCard(
                    title: "Agriculture",
                    icon: "leaf.fill",
                    color: Color.green,
                    count: CommoditySymbolMapper.commodities(ofType: .agriculture).count,
                    type: .agriculture
                )
                
                // Industrial summary
                categorySummaryCard(
                    title: "Industrial",
                    icon: "hammer.fill",
                    color: Color.orange,
                    count: CommoditySymbolMapper.commodities(ofType: .industrialMetal).count,
                    type: .industrialMetal
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(DS.Adaptive.divider.opacity(isDark ? 0.3 : 0.15), lineWidth: 1)
        )
    }
    
    private func categorySummaryCard(title: String, icon: String, color: Color, count: Int, type: CommodityType) -> some View {
        let commodities = CommoditySymbolMapper.commodities(ofType: type)
        // Calculate average change only from commodities with valid data
        let validChanges = commodities.compactMap { effectiveChange(for: $0) }
        let avgChange: Double? = validChanges.isEmpty ? nil : validChanges.reduce(0.0, +) / Double(validChanges.count)
        
        return Button {
            // Navigate to segment
            switch type {
            case .preciousMetal: selectedSegment = .preciousMetals
            case .energy: selectedSegment = .energy
            case .agriculture: selectedSegment = .agriculture
            case .industrialMetal: selectedSegment = .industrial
            case .livestock: selectedSegment = .livestock
            }
        } label: {
            HStack(spacing: 8) {
                // Icon
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(color)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    HStack(spacing: 4) {
                        Text("\(count) items")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                        
                        Text(formatPercent(avgChange))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor((avgChange ?? 0) >= 0 ? .green : .red)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(isDark ? 0.06 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(color.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Commodity Row
    
    private func commodityRow(_ commodity: CommodityInfo) -> some View {
        let price = effectivePrice(for: commodity)
        let change = effectiveChange(for: commodity)
        
        return HStack(spacing: 10) {
            // Commodity Icon - use new CommodityIconView
            CommodityIconView(commodityId: commodity.id, size: 40)
            
            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(commodity.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    // Type badge
                    Text(badgeText(for: commodity.type))
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(badgeColor(for: commodity.type)))
                }
                
                Text("\(commodity.yahooSymbol) · \(commodity.unit)")
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Price and change
            VStack(alignment: .trailing, spacing: 2) {
                let hasLivePrice = livePrice(for: commodity) != nil
                
                HStack(spacing: 3) {
                    if !hasLivePrice {
                        // Subtle "Est" indicator for fallback/estimated prices
                        Text("est")
                            .font(.system(size: 8, weight: .medium, design: .rounded))
                            .foregroundColor(DS.Adaptive.textTertiary.opacity(0.6))
                            .offset(y: -1)
                    }
                    Text(formatPrice(price))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(hasLivePrice ? DS.Adaptive.textPrimary : DS.Adaptive.textSecondary)
                        .monospacedDigit()
                }
                
                if let change = change {
                    HStack(spacing: 2) {
                        Image(systemName: change >= 0 ? "arrow.up" : "arrow.down")
                            .font(.system(size: 8, weight: .bold))
                        Text(formatPercent(change))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    .foregroundColor(change >= 0 ? .green : .red)
                } else if !hasLivePrice {
                    // No live data at all - show muted "no data" indicator
                    Text("no data")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(DS.Adaptive.textTertiary.opacity(0.5))
                } else {
                    Text("—")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
            }
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(DS.Adaptive.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DS.Adaptive.divider.opacity(isDark ? 0.25 : 0.12), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                // Skeleton market movers
                skeletonMarketMoversSection
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                
                // Skeleton summary
                skeletonSummarySection
                    .padding(.horizontal, 16)
                
                // Skeleton commodity rows
                ForEach(0..<8, id: \.self) { _ in
                    skeletonCommodityRow
                        .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 20)
        }
        .withUIKitScrollBridge() // PERFORMANCE FIX v21: UIKit scroll bridge for snappier deceleration + animation freeze
    }
    
    // MARK: - Skeleton Views
    
    private var skeletonMarketMoversSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ShimmerRect(width: 120, height: 16)
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    ShimmerRect(width: 60, height: 12)
                    ForEach(0..<3, id: \.self) { _ in
                        HStack {
                            ShimmerRect(width: 50, height: 12)
                            Spacer()
                            ShimmerRect(width: 40, height: 12)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.green.opacity(isDark ? 0.05 : 0.03))
                )
                
                VStack(alignment: .leading, spacing: 8) {
                    ShimmerRect(width: 60, height: 12)
                    ForEach(0..<3, id: \.self) { _ in
                        HStack {
                            ShimmerRect(width: 50, height: 12)
                            Spacer()
                            ShimmerRect(width: 40, height: 12)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.red.opacity(isDark ? 0.05 : 0.03))
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(DS.Adaptive.cardBackground)
        )
    }
    
    private var skeletonSummarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ShimmerRect(width: 100, height: 14)
            
            HStack(spacing: 10) {
                skeletonSummaryCard
                skeletonSummaryCard
            }
            
            HStack(spacing: 10) {
                skeletonSummaryCard
                skeletonSummaryCard
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(DS.Adaptive.cardBackground)
        )
    }
    
    private var skeletonSummaryCard: some View {
        HStack(spacing: 8) {
            ShimmerCircle(size: 32)
            VStack(alignment: .leading, spacing: 4) {
                ShimmerRect(width: 60, height: 10)
                ShimmerRect(width: 40, height: 8)
            }
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.05))
        )
    }
    
    private var skeletonCommodityRow: some View {
        HStack(spacing: 10) {
            ShimmerCircle(size: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                ShimmerRect(width: 80, height: 14)
                ShimmerRect(width: 60, height: 11)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                ShimmerRect(width: 70, height: 14)
                ShimmerRect(width: 50, height: 11)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            CommodityIconView(commodityId: "gold", size: 64)
                .opacity(0.5)
            
            Text("No Commodities Available")
                .font(.headline)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Text("Pull to refresh or check back later")
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
            
            Button {
                Task { await refresh() }
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Capsule().fill(DS.Adaptive.gold))
            }
            
            Spacer()
        }
    }
    
    // MARK: - No Search Results
    
    private var noSearchResultsView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "magnifyingglass")
                .font(.system(size: 50))
                .foregroundColor(DS.Adaptive.textTertiary)
            
            Text("No Results")
                .font(.headline)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Text("Try a different search term")
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
            
            Spacer()
        }
    }
    
    // MARK: - Footer Section
    
    @ViewBuilder
    private var commoditiesFooter: some View {
        VStack(spacing: 12) {
            // When showing a filtered segment with few items, suggest exploring other categories
            if selectedSegment != .all && displayedCommodities.count < 8 {
                exploreCategoriesFooter
            }
            
            // Data info footer - always show at bottom
            dataInfoFooter
        }
    }
    
    /// Suggests other categories when current filter shows few items
    private var exploreCategoriesFooter: some View {
        let otherSegments = CommoditiesMarketSegment.allCases.filter {
            $0 != selectedSegment && $0 != .all && $0 != .gainers && $0 != .losers
        }
        
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DS.Adaptive.gold)
                Text("Explore Other Categories")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(DS.Adaptive.textPrimary)
            }
            
            ForEach(otherSegments) { segment in
                let count = countForSegment(segment)
                if count > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedSegment = segment
                            visibleCount = 30
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: segment.icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(categoryColor(for: segment))
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle()
                                        .fill(categoryColor(for: segment).opacity(0.12))
                                )
                            
                            Text(segment.rawValue)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(DS.Adaptive.textPrimary)
                            
                            Text("\(count)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(DS.Adaptive.textTertiary)
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(DS.Adaptive.textTertiary)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DS.Adaptive.divider.opacity(isDark ? 0.3 : 0.15), lineWidth: 1)
        )
    }
    
    /// Color for category segments
    private func categoryColor(for segment: CommoditiesMarketSegment) -> Color {
        switch segment {
        case .preciousMetals: return .yellow
        case .energy: return .blue
        case .agriculture: return .green
        case .industrial: return .orange
        case .livestock: return .brown
        default: return .gray
        }
    }
    
    /// Data disclaimer and source info at the bottom
    private var dataInfoFooter: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
                
                Text("Commodity data via Yahoo Finance")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
                
                Spacer()
                
                if let lastUpdate = lastUpdate {
                    Text("Updated \(timeAgoString(from: lastUpdate))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
            }
            
            // Show count of commodities with live data vs fallback
            let liveCount = displayedCommodities.filter { livePrice(for: $0) != nil }.count
            let totalCount = displayedCommodities.count
            
            if liveCount < totalCount && totalCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.orange.opacity(0.8))
                    
                    Text("\(liveCount)/\(totalCount) with live data. Others show estimated prices.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    
                    Spacer()
                }
            }
            
            Text("Futures prices update during market hours. CME Globex: Sun 6PM \u{2013} Fri 5PM ET.")
                .font(.system(size: 9, weight: .regular))
                .foregroundColor(DS.Adaptive.textTertiary.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
        )
    }
    
    // MARK: - Helpers
    
    private func loadMore() {
        guard visibleCount < displayedCommodities.count else { return }
        withAnimation {
            visibleCount = min(visibleCount + 20, displayedCommodities.count)
        }
    }
    
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
    
    // Fallback prices - approximate Feb 2026 values, replaced with live data when available
    private func fallbackPrice(for commodity: CommodityInfo) -> Double {
        switch commodity.id {
        // Precious Metals (updated Feb 2026)
        case "gold": return 4967.00
        case "silver": return 76.92
        case "platinum": return 2100.00
        case "palladium": return 1717.00
        // Industrial Metals
        case "copper": return 5.88
        case "aluminum": return 3039.00
        // Energy
        case "crude_oil": return 63.41
        case "brent_oil": return 79.80
        case "natural_gas": return 3.43
        case "heating_oil": return 2.85
        case "gasoline": return 2.25
        // Agriculture
        case "corn": return 4.55
        case "soybeans": return 10.25
        case "wheat": return 5.45
        case "coffee": return 3.25
        case "cocoa": return 8500.00
        case "cotton": return 0.75
        case "sugar": return 0.22
        case "oats": return 3.80
        case "rice": return 17.50
        case "orange_juice": return 4.75
        case "lumber": return 570.00
        // Livestock
        case "live_cattle": return 1.92
        case "lean_hogs": return 0.85
        case "feeder_cattle": return 2.65
        default: return 0
        }
    }
    
    private func badgeText(for type: CommodityType) -> String {
        switch type {
        case .preciousMetal: return "METAL"
        case .industrialMetal: return "IND"
        case .energy: return "ENERGY"
        case .agriculture: return "AGRI"
        case .livestock: return "LIVE"
        }
    }
    
    private func badgeColor(for type: CommodityType) -> Color {
        switch type {
        case .preciousMetal: return Color.yellow.opacity(0.9)
        case .industrialMetal: return Color.orange
        case .energy: return Color.blue
        case .agriculture: return Color.green
        case .livestock: return Color.brown
        }
    }
    
    private func formatPrice(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = CurrencyManager.currencyCode
        if value >= 1000 {
            formatter.maximumFractionDigits = 0
        } else if value >= 1 {
            formatter.maximumFractionDigits = 2
        } else {
            formatter.maximumFractionDigits = 4
        }
        return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
    
    private func formatCompactCurrency(_ value: Double) -> String {
        if value >= 1000 {
            return "$\(String(format: "%.0f", value))"
        } else if value >= 1 {
            return "$\(String(format: "%.2f", value))"
        } else {
            return "$\(String(format: "%.3f", value))"
        }
    }
    
    private func formatPercent(_ value: Double?) -> String {
        guard let value = value else { return "—" }  // Show dash for missing data
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", value))%"
    }
}

// MARK: - Shimmer Components

private struct ShimmerRect: View {
    let width: CGFloat
    let height: CGFloat
    
    @State private var isAnimating = false
    
    var body: some View {
        RoundedRectangle(cornerRadius: height / 3)
            .fill(
                LinearGradient(
                    colors: [
                        Color.gray.opacity(0.15),
                        Color.gray.opacity(0.25),
                        Color.gray.opacity(0.15)
                    ],
                    startPoint: isAnimating ? .trailing : .leading,
                    endPoint: isAnimating ? .leading : .trailing
                )
            )
            .frame(width: width, height: height)
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

private struct ShimmerCircle: View {
    let size: CGFloat
    
    @State private var isAnimating = false
    
    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.gray.opacity(0.15),
                        Color.gray.opacity(0.25),
                        Color.gray.opacity(0.15)
                    ],
                    startPoint: isAnimating ? .trailing : .leading,
                    endPoint: isAnimating ? .leading : .trailing
                )
            )
            .frame(width: size, height: size)
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CommoditiesMarketView()
            .environmentObject(PortfolioViewModel.sample)
    }
    .preferredColorScheme(.dark)
}
