//
//  AllStocksView.swift
//  CryptoSage
//
//  Created by CryptoSage on 1/19/26.
//  Full page view for managing all stock and ETF holdings.
//

import SwiftUI

// MARK: - Sort Options

enum StocksSortOption: String, CaseIterable {
    case value = "Value"
    case dailyChange = "Daily Change"
    case ticker = "Ticker A-Z"
    case shares = "Shares"
    case profitLoss = "P/L"
    
    var icon: String {
        switch self {
        case .value: return "dollarsign.circle"
        case .dailyChange: return "chart.line.uptrend.xyaxis"
        case .ticker: return "textformat.abc"
        case .shares: return "number"
        case .profitLoss: return "arrow.up.arrow.down"
        }
    }
}

// MARK: - View Mode

enum AllStocksViewMode: String, CaseIterable {
    case holdings = "My Holdings"
    case market = "Market"
}

// MARK: - All Stocks View

struct AllStocksView: View {
    @EnvironmentObject var portfolioVM: PortfolioViewModel
    @ObservedObject private var marketCache = StockMarketCache.shared
    @ObservedObject private var watchlistManager = StockWatchlistManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    // View mode
    @State private var viewMode: AllStocksViewMode = .holdings
    
    // Search and filtering
    @State private var searchText = ""
    @State private var sortOption: StocksSortOption = .value
    @State private var sortAscending = false
    @State private var showSortMenu = false
    @State private var filterType: AssetType? = nil  // nil = all
    @FocusState private var isSearchFocused: Bool
    
    // Navigation
    @State private var selectedHolding: Holding?
    @State private var selectedMarketStock: CachedStock?
    @State private var showAddStock = false
    @State private var showMarketView = false
    @State private var holdingToEdit: Holding?
    @State private var holdingToDelete: Holding?
    @State private var showDeleteConfirmation = false
    
    // Refresh
    @State private var isRefreshing = false
    
    private var isDark: Bool { colorScheme == .dark }
    
    // User's actual holdings
    private var displayHoldings: [Holding] {
        portfolioVM.securitiesHoldings
    }
    
    // Market stocks for browsing
    private var marketStocks: [CachedStock] {
        marketCache.allStocks(sortedBy: .changePercent, ascending: false)
    }
    
    // Filtered and sorted holdings
    private var filteredHoldings: [Holding] {
        var holdings = displayHoldings
        
        // Apply type filter
        if let filterType = filterType {
            holdings = holdings.filter { $0.assetType == filterType }
        }
        
        // Apply search filter
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            holdings = holdings.filter {
                $0.displaySymbol.lowercased().contains(query) ||
                $0.displayName.lowercased().contains(query)
            }
        }
        
        // Apply sorting
        holdings = holdings.sorted { a, b in
            let comparison: Bool
            switch sortOption {
            case .value:
                comparison = a.currentValue > b.currentValue
            case .dailyChange:
                comparison = a.dailyChange > b.dailyChange
            case .ticker:
                comparison = a.displaySymbol < b.displaySymbol
            case .shares:
                comparison = a.quantity > b.quantity
            case .profitLoss:
                comparison = a.profitLoss > b.profitLoss
            }
            return sortAscending ? !comparison : comparison
        }
        
        return holdings
    }
    
    // Total value
    private var totalValue: Double {
        displayHoldings.reduce(0) { $0 + $1.currentValue }
    }
    
    // Stock count
    private var stockCount: Int {
        displayHoldings.filter { $0.assetType == .stock }.count
    }
    
    // ETF count
    private var etfCount: Int {
        displayHoldings.filter { $0.assetType == .etf }.count
    }
    
    // Commodity count
    private var commodityCount: Int {
        displayHoldings.filter { $0.assetType == .commodity }.count
    }
    
    // Market status
    private var isMarketOpen: Bool {
        LiveStockPriceManager.shared.isMarketOpen
    }
    
    var body: some View {
        ZStack {
            // Background
            DS.Adaptive.background
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Custom Header
                headerView
                
                // Content
                if displayHoldings.isEmpty {
                    emptyStateView
                } else {
                    stocksListView
                }
            }
            
            // Floating Add Button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    addButton
                }
            }
            .padding(20)
        }
        .navigationBarHidden(true)
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
        .navigationDestination(isPresented: Binding(
            get: { selectedHolding != nil },
            set: { if !$0 { selectedHolding = nil } }
        )) {
            if let holding = selectedHolding {
                StockDetailView(
                    ticker: holding.displaySymbol,
                    companyName: holding.displayName,
                    assetType: holding.assetType,
                    holding: holding
                )
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { selectedMarketStock != nil },
            set: { if !$0 { selectedMarketStock = nil } }
        )) {
            if let stock = selectedMarketStock {
                StockDetailView(
                    ticker: stock.symbol,
                    companyName: stock.name,
                    assetType: stock.assetType,
                    holding: nil
                )
            }
        }
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
        .navigationDestination(isPresented: $showMarketView) {
            StockMarketView()
                .environmentObject(portfolioVM)
        }
        .alert("Delete Holding?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                holdingToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let holding = holdingToDelete {
                    deleteHolding(holding)
                }
            }
        } message: {
            if let holding = holdingToDelete {
                Text("Are you sure you want to delete \(holding.displaySymbol)? This action cannot be undone.")
            }
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        VStack(spacing: 0) {
            // Top bar with back button and title
            HStack(spacing: 10) {
                // Back button
                CSNavButton(
                    icon: "chevron.left",
                    action: { dismiss() }
                )
                
                Spacer()
                
                // Title with gold accent icon - consistent with other sections
                HStack(spacing: 8) {
                    GoldHeaderGlyph(systemName: "chart.line.uptrend.xyaxis")
                    
                    Text("Stocks & ETFs")
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
            
            // Summary Stats
            summaryStats
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            
            // Search and Filter Bar
            searchAndFilterBar
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            
            Divider()
                .opacity(0.4)
        }
        .background(DS.Adaptive.backgroundSecondary)
    }
    
    // MARK: - Market Status Badge
    
    private var marketStatusBadge: some View {
        HStack(spacing: 5) {
            // Animated pulse dot when market is open
            Circle()
                .fill(isMarketOpen ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
                .overlay(
                    Circle()
                        .stroke(isMarketOpen ? Color.green.opacity(0.5) : Color.clear, lineWidth: 2)
                        .scaleEffect(isMarketOpen ? 1.5 : 1)
                        .opacity(isMarketOpen ? 0 : 1)
                        .animation(
                            isMarketOpen 
                                ? Animation.easeOut(duration: 1.2).repeatForever(autoreverses: false)
                                : .default,
                            value: isMarketOpen
                        )
                )
            
            Text(isMarketOpen ? "Open" : "Closed")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isMarketOpen ? .green : .orange)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill((isMarketOpen ? Color.green : Color.orange).opacity(0.12))
        )
        .overlay(
            Capsule()
                .stroke((isMarketOpen ? Color.green : Color.orange).opacity(0.25), lineWidth: 1)
        )
    }
    
    // Daily P/L calculation
    private var totalDailyPL: Double {
        displayHoldings.reduce(0) { $0 + ($1.currentValue * $1.dailyChange / 100) }
    }
    
    // MARK: - Summary Stats
    
    private var summaryStats: some View {
        HStack(spacing: 0) {
            // Total Value
            VStack(alignment: .leading, spacing: 2) {
                Text("TOTAL VALUE")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .tracking(0.5)
                
                Text(formatCurrency(totalValue))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .monospacedDigit()
            }
            
            Spacer()
            
            // Daily P/L
            HStack(spacing: 3) {
                Image(systemName: totalDailyPL >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
                Text(formatProfitLoss(totalDailyPL))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundColor(totalDailyPL >= 0 ? .green : .red)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill((totalDailyPL >= 0 ? Color.green : Color.red).opacity(0.12))
            )
            
            // Divider
            Rectangle()
                .fill(DS.Adaptive.divider.opacity(0.3))
                .frame(width: 1, height: 32)
                .padding(.horizontal, 12)
            
            // Holdings breakdown (compact)
            HStack(spacing: 12) {
                // Stocks
                HStack(spacing: 4) {
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AssetType.stock.color)
                    Text("\(stockCount)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                
                // ETFs
                HStack(spacing: 4) {
                    Image(systemName: "chart.pie.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AssetType.etf.color)
                    Text("\(etfCount)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                
                // Commodities (only show if any exist)
                if commodityCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "scalemass.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AssetType.commodity.color)
                        Text("\(commodityCount)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(DS.Adaptive.textPrimary)
                    }
                }
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
                .stroke(DS.Adaptive.divider.opacity(isDark ? 0.3 : 0.15), lineWidth: 1)
        )
    }
    
    // MARK: - Search and Filter Bar
    
    private var searchAndFilterBar: some View {
        HStack(spacing: 8) {
            // Search Field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
                
                TextField("Search...", text: $searchText)
                    .font(.system(size: 13))
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                
                if !searchText.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            searchText = ""
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .onTapGesture {
                isSearchFocused = true
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
            )
            
            // Filter Chips
            filterChips
            
            // Sort Button
            Menu {
                ForEach(StocksSortOption.allCases, id: \.self) { option in
                    Button {
                        if sortOption == option {
                            sortAscending.toggle()
                        } else {
                            sortOption = option
                            sortAscending = false
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
                Image(systemName: "arrow.up.arrow.down.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
        }
    }
    
    // MARK: - Filter Chips
    
    private var filterChips: some View {
        HStack(spacing: 4) {
            filterChip(title: "All", type: nil, isAllChip: true)
            filterChip(title: "Stocks", type: .stock, isAllChip: false)
            filterChip(title: "ETFs", type: .etf, isAllChip: false)
        }
    }
    
    private func filterChip(title: String, type: AssetType?, isAllChip: Bool) -> some View {
        let isSelected = filterType == type
        
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                filterType = type
            }
        } label: {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? .white : DS.Adaptive.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(
                            isSelected 
                                ? (isAllChip ? DS.Adaptive.gold : (type?.color ?? DS.Adaptive.gold))
                                : (isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                        )
                )
        }
    }
    
    // MARK: - Stocks List View
    
    private var stocksListView: some View {
        List {
            ForEach(filteredHoldings) { holding in
                stockRow(holding)
                    .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            holdingToDelete = holding
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .onTapGesture {
                        selectedHolding = holding
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            await refreshPrices()
        }
    }
    
    // MARK: - Stock Row
    
    private func stockRow(_ holding: Holding) -> some View {
        HStack(spacing: 10) {
            // Logo
            StockImageView(
                ticker: holding.displaySymbol,
                assetType: holding.assetType,
                size: 42
            )
            
            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(holding.displaySymbol)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    // ETF badge
                    if holding.assetType == .etf {
                        Text("ETF")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(holding.assetType.color))
                    }
                }
                
                Text(holding.displayName)
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .lineLimit(1)
                
                // Shares info
                Text("\(formatQuantity(holding.quantity)) shares @ \(formatPrice(holding.currentPrice))")
                    .font(.system(size: 10))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            Spacer()
            
            // Value and change
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatCurrency(holding.currentValue))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .monospacedDigit()
                
                // Daily change
                HStack(spacing: 2) {
                    Image(systemName: holding.dailyChange >= 0 ? "arrow.up" : "arrow.down")
                        .font(.system(size: 8, weight: .bold))
                    Text(formatPercent(holding.dailyChange))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundColor(holding.dailyChange >= 0 ? .green : .red)
                
                // Total P/L
                Text(formatProfitLoss(holding.profitLoss))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(holding.profitLoss >= 0 ? .green.opacity(0.7) : .red.opacity(0.7))
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
    
    private func formatPrice(_ value: Double) -> String {
        return "$\(String(format: "%.2f", value))"
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            // Icon
            ZStack {
                Circle()
                    .fill(DS.Adaptive.gold.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(DS.Adaptive.gold.opacity(0.8))
            }
            
            VStack(spacing: 6) {
                Text("No Stock Holdings")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text("Add stocks and ETFs to track alongside your crypto, or browse the stock market")
                    .font(.system(size: 13))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)
            
            // Action buttons
            VStack(spacing: 10) {
                Button {
                    showMarketView = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "building.columns.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Browse Stock Market")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(DS.Adaptive.gold))
                }
                .padding(.horizontal, 40)
                
                Button {
                    showAddStock = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Add Stock Manually")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(DS.Adaptive.gold)
                }
            }
            
            Spacer()
        }
    }
    
    // MARK: - Add Button (FAB)
    
    private var addButton: some View {
        Button {
            showAddStock = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(
                    Circle()
                        .fill(DS.Adaptive.gold)
                )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Actions
    
    private func refreshPrices() async {
        isRefreshing = true
        await portfolioVM.refreshStockPrices()
        isRefreshing = false
    }
    
    private func deleteHolding(_ holding: Holding) {
        BrokeragePortfolioDataService.shared.removeHolding(holding)
        holdingToDelete = nil
    }
    
    // MARK: - Formatters
    
    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = CurrencyManager.currencyCode
        
        if value >= 1_000_000 {
            return "$\(String(format: "%.2fM", value / 1_000_000))"
        } else if value >= 1_000 {
            formatter.maximumFractionDigits = 0
        } else {
            formatter.maximumFractionDigits = 2
        }
        
        return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
    
    private func formatPercent(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", value))%"
    }
    
    private func formatQuantity(_ value: Double) -> String {
        if value == floor(value) {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.2f", value)
        }
    }
    
    private func formatProfitLoss(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        if abs(value) >= 1_000_000 {
            return "\(sign)$\(String(format: "%.2fM", value / 1_000_000))"
        } else if abs(value) >= 1_000 {
            return "\(sign)$\(String(format: "%.0f", value))"
        } else {
            return "\(sign)$\(String(format: "%.2f", value))"
        }
    }
}

// MARK: - Holding Extension for Convenience Init

extension Holding {
    /// Convenience initializer for stock holdings
    init(
        ticker: String,
        companyName: String,
        shares: Double,
        currentPrice: Double,
        costBasis: Double,
        assetType: AssetType,
        stockExchange: String?,
        isin: String?,
        imageUrl: String?,
        isFavorite: Bool,
        dailyChange: Double,
        purchaseDate: Date,
        source: String?
    ) {
        self.init(
            coinName: companyName,
            coinSymbol: ticker,
            quantity: shares,
            currentPrice: currentPrice,
            costBasis: costBasis,
            imageUrl: imageUrl,
            isFavorite: isFavorite,
            dailyChange: dailyChange,
            purchaseDate: purchaseDate
        )
        self.assetType = assetType
        self.ticker = ticker
        self.companyName = companyName
        self.stockExchange = stockExchange
        self.isin = isin
        self.source = source
    }
}

// MARK: - Preview

#Preview("With Holdings") {
    NavigationStack {
        AllStocksView()
            .environmentObject(PortfolioViewModel.sample)
    }
    .preferredColorScheme(.dark)
}

#Preview("Empty State") {
    NavigationStack {
        AllStocksView()
            .environmentObject(PortfolioViewModel.sample)
    }
    .preferredColorScheme(.dark)
}
