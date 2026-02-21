//
//  StockMarketView.swift
//  CryptoSage
//
//  Created by CryptoSage on 1/20/26.
//  Full market browsing view for stocks and ETFs.
//

import SwiftUI

// MARK: - Stock Market View

struct StockMarketView: View {
    @StateObject private var vm: StockMarketViewModel
    @EnvironmentObject var portfolioVM: PortfolioViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    // Navigation
    @State private var selectedStock: CachedStock?
    @State private var showAddStock = false
    
    // UI State
    @State private var showSortMenu = false
    @State private var visibleCount: Int = 50
    
    private var isDark: Bool { colorScheme == .dark }
    
    // MARK: - Initialization
    
    /// Initialize with an optional initial segment
    /// - Parameter initialSegment: The segment to show when the view opens. Defaults to `.all`
    init(initialSegment: StockMarketSegment = .all) {
        _vm = StateObject(wrappedValue: StockMarketViewModel(initialSegment: initialSegment))
    }
    
    var body: some View {
        ZStack {
            // Background
            DS.Adaptive.background
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Content
                if !vm.hasLoaded && vm.isLoading {
                    loadingView
                } else if vm.displayedStocks.isEmpty && !vm.searchText.isEmpty {
                    noSearchResultsView
                } else if vm.displayedStocks.isEmpty && vm.errorMessage != nil {
                    errorStateView
                } else if vm.displayedStocks.isEmpty {
                    emptyStateView
                } else {
                    stockListView
                }
            }
        }
        .navigationBarHidden(true)
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
        // Navigation to stock detail
        .navigationDestination(isPresented: Binding(
            get: { selectedStock != nil },
            set: { if !$0 { selectedStock = nil } }
        )) {
            if let stock = selectedStock {
                StockDetailView(
                    ticker: stock.symbol,
                    companyName: stock.name,
                    assetType: stock.assetType,
                    holding: nil
                )
            }
        }
        // Navigation to add stock
        .navigationDestination(isPresented: $showAddStock) {
            AddStockHoldingView { holding in
                BrokeragePortfolioDataService.shared.addManualHolding(holding)
                if let ticker = holding.ticker {
                    Task { @MainActor in
                        LiveStockPriceManager.shared.addTickers([ticker], source: "portfolio")
                    }
                }
            }
        }
        .task {
            await vm.loadData()
        }
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
                    GoldHeaderGlyph(systemName: "chart.line.uptrend.xyaxis")
                    
                    Text("Stock Market")
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
        HStack(spacing: 8) {
            // Market status
            HStack(spacing: 5) {
                Circle()
                    .fill(vm.isMarketOpen ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                
                Text(vm.isMarketOpen ? "Open" : "Closed")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(vm.isMarketOpen ? .green : .orange)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill((vm.isMarketOpen ? Color.green : Color.orange).opacity(0.12))
            )
        }
    }
    
    // MARK: - Last Updated Indicator
    
    private var lastUpdatedText: String {
        guard let lastUpdate = vm.lastUpdate else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastUpdate, relativeTo: Date())
    }
    
    // MARK: - Segment Picker
    
    private var segmentPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(StockMarketSegment.allCases) { segment in
                    segmentButton(segment)
                }
            }
        }
    }
    
    private func segmentButton(_ segment: StockMarketSegment) -> some View {
        let isSelected = vm.selectedSegment == segment
        let count: Int = {
            switch segment {
            case .all: return vm.totalStockCount
            case .sp500: return vm.indexCounts[.sp500] ?? 0
            case .nasdaq100: return vm.indexCounts[.nasdaq100] ?? 0
            case .dowJones: return vm.indexCounts[.dowJones] ?? 0
            case .etfs: return StockMarketCache.shared.allStocks().filter { $0.assetType == .etf }.count
            case .commodities: return StockMarketCache.shared.allStocks().filter { $0.assetType == .commodity }.count
            case .gainers: return vm.topGainers.count
            case .losers: return vm.topLosers.count
            }
        }()
        
        return Button {
            guard vm.selectedSegment != segment else { return }
            
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            
            withAnimation(.easeInOut(duration: 0.2)) {
                vm.selectedSegment = segment
                // Reset visible count when switching segments for better performance
                visibleCount = 50
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
                
                TextField("Search stocks...", text: $vm.searchText)
                    .font(.system(size: 13))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                if !vm.searchText.isEmpty {
                    Button {
                        vm.searchText = ""
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
                ForEach(StockSortOption.allCases, id: \.self) { option in
                    Button {
                        vm.setSortOption(option)
                    } label: {
                        HStack {
                            Image(systemName: option.icon)
                            Text(option.rawValue)
                            Spacer()
                            if vm.sortOption == option {
                                Image(systemName: vm.sortAscending ? "chevron.up" : "chevron.down")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 12, weight: .medium))
                    Text(vm.sortOption.rawValue)
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
    
    // MARK: - Stock List View
    
    private var stockListView: some View {
        List {
            // Market Movers Section (only for All segment)
            if vm.selectedSegment == .all && vm.searchText.isEmpty {
                marketMoversSection
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            
            // Stock List
            ForEach(Array(vm.displayedStocks.prefix(visibleCount))) { stock in
                stockRow(stock)
                    .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .onTapGesture {
                        selectedStock = stock
                    }
                    .onAppear {
                        // Load more when reaching end
                        if stock == vm.displayedStocks.prefix(visibleCount).last {
                            loadMore()
                        }
                    }
            }
            
            // Load more indicator
            if visibleCount < vm.displayedStocks.count {
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
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            await vm.refresh()
        }
        // FIX: Add bottom padding to prevent tab bar from cutting off last items
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 90)
        }
    }
    
    // MARK: - Market Movers Section
    
    private var marketMoversSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with title and count
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
                
                // Last updated time
                if let lastUpdate = vm.lastUpdate {
                    Text(timeAgoString(from: lastUpdate))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
            }
            
            HStack(spacing: 12) {
                // Top Gainers
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                        Text("Top Gainers")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.green)
                        
                        Spacer()
                        
                        Text("\(vm.topGainers.count)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.green.opacity(0.8))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.green.opacity(0.15))
                            )
                    }
                    
                    if vm.topGainers.isEmpty {
                        Text(vm.isMarketOpen ? "No gainers today" : "Market closed")
                            .font(.system(size: 10))
                            .foregroundColor(DS.Adaptive.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    } else {
                        ForEach(vm.topGainers.prefix(3)) { stock in
                            moverRow(stock, isGainer: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.green.opacity(isDark ? 0.08 : 0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.green.opacity(0.2), lineWidth: 1)
                )
                
                // Top Losers
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.red)
                        Text("Top Losers")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.red)
                        
                        Spacer()
                        
                        Text("\(vm.topLosers.count)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.red.opacity(0.8))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.red.opacity(0.15))
                            )
                    }
                    
                    if vm.topLosers.isEmpty {
                        Text(vm.isMarketOpen ? "No losers today" : "Market closed")
                            .font(.system(size: 10))
                            .foregroundColor(DS.Adaptive.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    } else {
                        ForEach(vm.topLosers.prefix(3)) { stock in
                            moverRow(stock, isGainer: false)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.red.opacity(isDark ? 0.08 : 0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.red.opacity(0.2), lineWidth: 1)
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
    
    private func moverRow(_ stock: CachedStock, isGainer: Bool) -> some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            selectedStock = stock
        } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(stock.symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Text(formatCompactCurrency(stock.currentPrice))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                
                Spacer()
                
                Text(formatPercent(stock.changePercent))
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
    
    private func formatCompactCurrency(_ value: Double) -> String {
        if value >= 1000 {
            return "$\(String(format: "%.0f", value))"
        } else if value >= 1 {
            return "$\(String(format: "%.2f", value))"
        } else {
            return "$\(String(format: "%.3f", value))"
        }
    }
    
    // MARK: - Stock Row
    
    private func stockRow(_ stock: CachedStock) -> some View {
        StockMarketRowView(
            stock: stock,
            isWatched: StockWatchlistManager.shared.isWatched(stock.symbol),
            onToggleWatchlist: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    StockWatchlistManager.shared.toggle(stock.symbol)
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                }
            }
        )
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
                // Skeleton market movers section
                skeletonMarketMoversSection
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                
                // Skeleton stock rows
                ForEach(0..<8, id: \.self) { _ in
                    skeletonStockRow
                        .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 20)
        }
    }
    
    // MARK: - Skeleton Views
    
    private var skeletonMarketMoversSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ShimmerRect(width: 120, height: 16)
            
            HStack(spacing: 12) {
                // Gainers skeleton
                VStack(alignment: .leading, spacing: 8) {
                    ShimmerRect(width: 60, height: 12)
                    ForEach(0..<3, id: \.self) { _ in
                        HStack {
                            ShimmerRect(width: 40, height: 12)
                            Spacer()
                            ShimmerRect(width: 50, height: 12)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.green.opacity(isDark ? 0.05 : 0.03))
                )
                
                // Losers skeleton
                VStack(alignment: .leading, spacing: 8) {
                    ShimmerRect(width: 60, height: 12)
                    ForEach(0..<3, id: \.self) { _ in
                        HStack {
                            ShimmerRect(width: 40, height: 12)
                            Spacer()
                            ShimmerRect(width: 50, height: 12)
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
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(DS.Adaptive.divider.opacity(isDark ? 0.3 : 0.15), lineWidth: 1)
        )
    }
    
    private var skeletonStockRow: some View {
        HStack(spacing: 10) {
            // Logo placeholder
            ShimmerCircle(size: 40)
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                ShimmerRect(width: 50, height: 14)
                ShimmerRect(width: 100, height: 11)
            }
            
            Spacer()
            
            // Price
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
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DS.Adaptive.divider.opacity(isDark ? 0.25 : 0.12), lineWidth: 1)
        )
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 50))
                .foregroundColor(DS.Adaptive.textTertiary)
            
            Text("No Stocks Available")
                .font(.headline)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Text("Pull to refresh or check back later")
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
            
            Button {
                Task { await vm.refresh() }
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
    
    // MARK: - Error State
    
    private var errorStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            // Error icon with animation
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 90, height: 90)
                
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundColor(.orange)
            }
            
            VStack(spacing: 8) {
                Text("Unable to Load Data")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text(vm.errorMessage ?? "Please check your internet connection and try again.")
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            // Retry button
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                Task { await vm.refresh() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Try Again")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(DS.Adaptive.gold)
                )
            }
            
            // Helpful tips
            VStack(alignment: .leading, spacing: 8) {
                Text("Troubleshooting tips:")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DS.Adaptive.textSecondary)
                
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text("Check your internet connection")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text("Try switching between WiFi and cellular")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text("Wait a moment and try again")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(DS.Adaptive.chipBackground)
            )
            .padding(.horizontal, 40)
            .padding(.top, 8)
            
            Spacer()
        }
    }
    
    // MARK: - Helpers
    
    private func loadMore() {
        guard visibleCount < vm.displayedStocks.count else { return }
        withAnimation {
            visibleCount = min(visibleCount + 30, vm.displayedStocks.count)
        }
    }
    
    private func formatCurrency(_ value: Double) -> String {
        if value >= 10000 {
            return "$\(String(format: "%.0f", value))"
        } else if value >= 1 {
            return "$\(String(format: "%.2f", value))"
        } else {
            return "$\(String(format: "%.4f", value))"
        }
    }
    
    private func formatPercent(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", value))%"
    }
}

// MARK: - Stock Market Row View

private struct StockMarketRowView: View {
    let stock: CachedStock
    let isWatched: Bool
    let onToggleWatchlist: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var priceColor: Color = .primary
    @State private var priceScale: CGFloat = 1.0
    @State private var lastPrice: Double = 0
    @State private var starScale: CGFloat = 1.0
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        HStack(spacing: 10) {
            // Logo
            StockImageView(
                ticker: stock.symbol,
                assetType: stock.assetType,
                size: 40
            )
            
            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(stock.symbol)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    // ETF badge
                    if stock.assetType == .etf {
                        Text("ETF")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(AssetType.etf.color))
                    }
                }
                
                Text(Self.abbreviateCompanyName(stock.name))
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Price and change
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatCurrency(stock.currentPrice))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(priceColor)
                    .monospacedDigit()
                    .scaleEffect(priceScale)
                    .contentTransition(.numericText())
                
                HStack(spacing: 2) {
                    Image(systemName: stock.changePercent >= 0 ? "arrow.up" : "arrow.down")
                        .font(.system(size: 8, weight: .bold))
                    Text(formatPercent(stock.changePercent))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundColor(stock.changePercent >= 0 ? .green : .red)
            }
            
            // Watchlist star button
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                    starScale = 0.8
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                        starScale = 1.0
                    }
                    onToggleWatchlist()
                }
            } label: {
                Image(systemName: isWatched ? "star.fill" : "star")
                    .font(.system(size: 16))
                    .foregroundColor(isWatched ? .yellow : DS.Adaptive.textTertiary)
                    .scaleEffect(starScale)
            }
            .buttonStyle(.plain)
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(DS.Adaptive.textTertiary)
        }
        .onAppear {
            lastPrice = stock.currentPrice
            priceColor = DS.Adaptive.textPrimary
        }
        .onChange(of: stock.currentPrice) { _, newPrice in
            // PERFORMANCE FIX: Skip during global startup phase to prevent
            // "onChange tried to update multiple times per frame" warning
            guard !isInGlobalStartupPhase() else { return }
            
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                guard newPrice != lastPrice, lastPrice > 0 else {
                    lastPrice = newPrice
                    return
                }
                
                let wentUp = newPrice > lastPrice
                
                // PERFORMANCE FIX: Skip animations during scroll to maintain 60fps
                guard !ScrollStateManager.shared.isScrolling else {
                    lastPrice = newPrice
                    return
                }
                
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    priceColor = wentUp ? .green : .red
                    priceScale = wentUp ? 1.02 : 0.98
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        priceColor = DS.Adaptive.textPrimary
                        priceScale = 1.0
                    }
                }
                
                lastPrice = newPrice
            }
        }
    }
    
    private func formatCurrency(_ value: Double) -> String {
        if value >= 10000 {
            return "$\(String(format: "%.0f", value))"
        } else if value >= 1 {
            return "$\(String(format: "%.2f", value))"
        } else {
            return "$\(String(format: "%.4f", value))"
        }
    }
    
    private func formatPercent(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", value))%"
    }
    
    /// Strip common suffixes from company names for cleaner display.
    /// "Amazon.com Inc." → "Amazon.com", "NVIDIA Corporation" → "NVIDIA"
    static func abbreviateCompanyName(_ name: String) -> String {
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
                break
            }
        }
        return abbreviated
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
        StockMarketView()
            .environmentObject(PortfolioViewModel.sample)
    }
    .preferredColorScheme(.dark)
}
