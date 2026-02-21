//
//  PaperTradeHistoryFullView.swift
//  CryptoSage
//
//  Full trade history view with comprehensive filtering, search, and grouping.
//

import SwiftUI

struct PaperTradeHistoryFullView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var paperTradingManager = PaperTradingManager.shared
    
    var currentPrices: [String: Double]
    
    // Filter states
    @State private var selectedSideFilter: TradeSide? = nil
    @State private var selectedAssetFilter: String? = nil
    @State private var searchText: String = ""
    @State private var sortOrder: SortOrder = .newest
    @State private var showSortPicker: Bool = false
    
    enum SortOrder: String, CaseIterable {
        case newest = "Newest First"
        case oldest = "Oldest First"
        case largestValue = "Largest Value"
        case smallestValue = "Smallest Value"
    }
    
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Stats header
                statsHeader
                
                // Filters
                filtersSection
                
                // Trade list
                if filteredTrades.isEmpty {
                    emptyState
                } else {
                    tradeList
                }
            }
            .background(DS.Adaptive.background.ignoresSafeArea())
            .navigationTitle("Trade History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Text("Done")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTradingMode.paper.color)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search by symbol")
            .enableInteractivePopGesture()
            .edgeSwipeToDismiss(onDismiss: { dismiss() })
        }
    }
    
    // MARK: - Stats Header
    
    private var statsHeader: some View {
        HStack(spacing: 16) {
            StatPill(
                title: "Total",
                value: "\(paperTradingManager.totalTradeCount)",
                color: .blue
            )
            StatPill(
                title: "Buys",
                value: "\(paperTradingManager.buyTradeCount)",
                color: .green
            )
            StatPill(
                title: "Sells",
                value: "\(paperTradingManager.sellTradeCount)",
                color: .red
            )
            StatPill(
                title: "Volume",
                value: formatCompactCurrency(paperTradingManager.totalVolumeTraded),
                color: .purple
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(DS.Adaptive.cardBackground)
    }
    
    // MARK: - Filters Section
    
    private var filtersSection: some View {
        VStack(spacing: 12) {
            // Side filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChipView(title: "All", isSelected: selectedSideFilter == nil) {
                        impactLight.impactOccurred()
                        selectedSideFilter = nil
                    }
                    FilterChipView(title: "Buys", isSelected: selectedSideFilter == .buy, color: .green) {
                        impactLight.impactOccurred()
                        selectedSideFilter = .buy
                    }
                    FilterChipView(title: "Sells", isSelected: selectedSideFilter == .sell, color: .red) {
                        impactLight.impactOccurred()
                        selectedSideFilter = .sell
                    }
                    
                    Divider()
                        .frame(height: 20)
                    
                    // Asset filters
                    ForEach(uniqueAssets, id: \.self) { asset in
                        FilterChipView(
                            title: asset,
                            isSelected: selectedAssetFilter == asset,
                            color: assetColor(asset)
                        ) {
                            impactLight.impactOccurred()
                            if selectedAssetFilter == asset {
                                selectedAssetFilter = nil
                            } else {
                                selectedAssetFilter = asset
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            
            // Sort picker
            HStack {
                Text("Sort by:")
                    .font(.system(size: 12))
                    .foregroundColor(DS.Adaptive.textSecondary)
                
                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    showSortPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Text(sortOrder.rawValue)
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showSortPicker, arrowEdge: .bottom) {
                    TradeSortPickerPopover(isPresented: $showSortPicker, selection: $sortOrder)
                        .presentationCompactAdaptation(.popover)
                }
                
                Spacer()
                
                Text("\(filteredTrades.count) trades")
                    .font(.system(size: 12))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
        .background(DS.Adaptive.cardBackground)
    }
    
    // MARK: - Trade List
    
    private var tradeList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(groupedTrades.keys.sorted().reversed(), id: \.self) { dateKey in
                    Section {
                        ForEach(groupedTrades[dateKey] ?? [], id: \.id) { trade in
                            PaperTradeHistoryDetailRow(trade: trade, currentPrice: currentPrices[parseBaseAsset(trade.symbol)])
                            
                            if trade.id != groupedTrades[dateKey]?.last?.id {
                                Divider()
                                    .background(DS.Adaptive.stroke)
                                    .padding(.leading, 56)
                            }
                        }
                    } header: {
                        HStack {
                            Text(dateKey)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(DS.Adaptive.textSecondary)
                            Spacer()
                            let dayTrades = groupedTrades[dateKey] ?? []
                            let dayVolume = dayTrades.map { $0.totalValue }.reduce(0, +)
                            Text("\(dayTrades.count) trades · \(formatCompactCurrency(dayVolume))")
                                .font(.system(size: 11))
                                .foregroundColor(DS.Adaptive.textTertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(DS.Adaptive.background)
                    }
                }
            }
            .padding(.bottom, 32)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(DS.Adaptive.textTertiary)
            Text("No trades found")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(DS.Adaptive.textSecondary)
            Text("Try adjusting your filters or search")
                .font(.system(size: 13))
                .foregroundColor(DS.Adaptive.textTertiary)
            
            if selectedSideFilter != nil || selectedAssetFilter != nil || !searchText.isEmpty {
                Button(action: {
                    selectedSideFilter = nil
                    selectedAssetFilter = nil
                    searchText = ""
                }) {
                    Text("Clear Filters")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.blue)
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Computed Properties
    
    private var filteredTrades: [PaperTrade] {
        var result = paperTradingManager.paperTradeHistory
        
        // Apply side filter
        if let side = selectedSideFilter {
            result = result.filter { $0.side == side }
        }
        
        // Apply asset filter
        if let asset = selectedAssetFilter {
            result = result.filter { parseBaseAsset($0.symbol) == asset }
        }
        
        // Apply search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { $0.symbol.lowercased().contains(query) }
        }
        
        // Apply sorting
        switch sortOrder {
        case .newest:
            result.sort { $0.timestamp > $1.timestamp }
        case .oldest:
            result.sort { $0.timestamp < $1.timestamp }
        case .largestValue:
            result.sort { $0.totalValue > $1.totalValue }
        case .smallestValue:
            result.sort { $0.totalValue < $1.totalValue }
        }
        
        return result
    }
    
    // PERFORMANCE FIX: Cached date formatters — avoid allocation per computed property access
    private static let _groupDateFormatter: DateFormatter = {
        let df = DateFormatter(); df.dateFormat = "EEEE, MMM d, yyyy"; return df
    }()
    private static let _timeDateFormatter: DateFormatter = {
        let df = DateFormatter(); df.dateFormat = "h:mm a"; return df
    }()

    private var groupedTrades: [String: [PaperTrade]] {
        return Dictionary(grouping: filteredTrades) { trade in
            Self._groupDateFormatter.string(from: trade.timestamp)
        }
    }
    
    private var uniqueAssets: [String] {
        let assets = paperTradingManager.paperTradeHistory.map { parseBaseAsset($0.symbol) }
        return Array(Set(assets)).sorted()
    }
    
    // MARK: - Helpers
    
    private func parseBaseAsset(_ symbol: String) -> String {
        let upper = symbol.uppercased()
        let quotes = ["USDT", "USD", "BUSD", "USDC", "FDUSD"]
        for q in quotes where upper.hasSuffix(q) {
            return String(upper.dropLast(q.count))
        }
        return upper
    }
    
    private func formatCompactCurrency(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "$%.1fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "$%.1fK", value / 1_000)
        } else {
            return String(format: "$%.0f", value)
        }
    }
    
    private func assetColor(_ asset: String) -> Color {
        switch asset.uppercased() {
        case "BTC": return .orange
        case "ETH": return .purple
        case "SOL": return Color(red: 0.6, green: 0.2, blue: 0.9)
        case "BNB": return .yellow
        case "XRP": return .gray
        case "ADA": return .blue
        case "DOGE": return Color(red: 0.8, green: 0.6, blue: 0.2)
        default: return .blue
        }
    }
}

// MARK: - Supporting Views

private struct StatPill: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(DS.Adaptive.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FilterChipView: View {
    let title: String
    let isSelected: Bool
    var color: Color = .blue
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isSelected ? .white : DS.Adaptive.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? color : DS.Adaptive.background)
                )
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.clear : DS.Adaptive.stroke, lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

private struct PaperTradeHistoryDetailRow: View {
    let trade: PaperTrade
    let currentPrice: Double?
    
    private var sideColor: Color {
        trade.side == .buy ? .green : .red
    }
    
    /// Extract base asset from symbol (e.g., "BTCUSDT" -> "BTC")
    private var baseAsset: String {
        let upper = trade.symbol.uppercased()
        let quotes = ["USDT", "USD", "BUSD", "USDC", "FDUSD"]
        for q in quotes where upper.hasSuffix(q) {
            return String(upper.dropLast(q.count))
        }
        return upper
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Coin logo with side indicator overlay
            ZStack(alignment: .bottomTrailing) {
                CoinImageView(
                    symbol: baseAsset,
                    url: coinImageURL(for: baseAsset),
                    size: 40
                )
                
                // Small side indicator badge
                Circle()
                    .fill(sideColor)
                    .frame(width: 16, height: 16)
                    .overlay(
                        Image(systemName: trade.side == .buy ? "arrow.down" : "arrow.up")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                    )
                    .offset(x: 2, y: 2)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(baseAsset)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Text(trade.side == .buy ? "BUY" : "SELL")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 3).fill(sideColor))
                }
                
                Text(formatDate(trade.timestamp))
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(formatCurrency(trade.totalValue))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                HStack(spacing: 4) {
                    Text(formatQuantity(trade.quantity))
                        .font(.system(size: 11))
                        .foregroundColor(DS.Adaptive.textSecondary)
                    Text("@")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    Text(formatPrice(trade.price))
                        .font(.system(size: 11))
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    private static let _timeDateFormatter: DateFormatter = {
        let df = DateFormatter(); df.dateFormat = "h:mm a"; return df
    }()
    private func formatDate(_ date: Date) -> String {
        Self._timeDateFormatter.string(from: date)
    }
    
    private func formatQuantity(_ value: Double) -> String {
        if value < 0.01 { return String(format: "%.4f", value) }
        else if value < 1 { return String(format: "%.3f", value) }
        else { return String(format: "%.2f", value) }
    }
    
    // PERFORMANCE FIX: Cached currency formatters
    private static let _priceFmt2: NumberFormatter = {
        let nf = NumberFormatter(); nf.numberStyle = .currency
        nf.currencyCode = CurrencyManager.currencyCode
        nf.maximumFractionDigits = 2; nf.minimumFractionDigits = 2; return nf
    }()
    private static let _priceFmt4: NumberFormatter = {
        let nf = NumberFormatter(); nf.numberStyle = .currency
        nf.currencyCode = CurrencyManager.currencyCode
        nf.maximumFractionDigits = 4; nf.minimumFractionDigits = 4; return nf
    }()

    private func formatPrice(_ value: Double) -> String {
        if value < 1 {
            return Self._priceFmt4.string(from: NSNumber(value: value)) ?? String(format: "$%.4f", value)
        } else {
            return Self._priceFmt2.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
        }
    }
    
    private func formatCurrency(_ value: Double) -> String {
        Self._priceFmt2.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }
}

// MARK: - Trade Sort Picker Popover
private struct TradeSortPickerPopover: View {
    @Binding var isPresented: Bool
    @Binding var selection: PaperTradeHistoryFullView.SortOrder
    
    var body: some View {
        VStack(spacing: 4) {
            // Header
            HStack {
                Text("Sort by")
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
            
            // Sort options
            VStack(spacing: 2) {
                ForEach(PaperTradeHistoryFullView.SortOrder.allCases, id: \.self) { order in
                    sortOptionRow(order)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .padding(4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        .frame(minWidth: 160, maxWidth: 200)
    }
    
    @ViewBuilder
    private func sortOptionRow(_ order: PaperTradeHistoryFullView.SortOrder) -> some View {
        let isSelected = selection == order
        
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
                selection = order
            }
            isPresented = false
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTradingMode.paper.color)
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 16)
                Text(order.rawValue)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.85))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(order.rawValue))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Preview

#if DEBUG
struct PaperTradeHistoryFullView_Previews: PreviewProvider {
    static var previews: some View {
        PaperTradeHistoryFullView(currentPrices: ["BTC": 45000, "ETH": 2500])
            .preferredColorScheme(.dark)
    }
}
#endif
