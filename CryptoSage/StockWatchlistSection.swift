//
//  StockWatchlistSection.swift
//  CryptoSage
//
//  Created by CryptoSage on 1/20/26.
//  Home page section showing user's stock watchlist (favorited stocks).
//

import SwiftUI
import Combine

// MARK: - Brand Gold Palette (matching WatchlistSection)
private enum StockBrandGold {
    static let light = BrandColors.goldLight
    static let base  = BrandColors.goldBase
    static let dark  = BrandColors.goldDark
    
    static var horizontalGradient: LinearGradient { BrandColors.goldHorizontal }
}

// MARK: - Stock Watchlist Section

struct StockWatchlistSection: View {
    // PERFORMANCE FIX v21: Removed @EnvironmentObject var appState: AppState
    // AppState has 18+ @Published properties. Every change to ANY of them forced this
    // entire section to re-render. Only dismissHomeSubviews is needed - use targeted onReceive.
    // FIX v23: Replaced @ObservedObject with computed singleton access + debounced refresh.
    // StockWatchlistManager has 5 @Published, LiveStockPriceManager has 4.
    // LiveStockPriceManager.quotes fires on every stock price update.
    // With @ObservedObject, each price update re-rendered the entire section with sparklines.
    private var watchlistManager: StockWatchlistManager { StockWatchlistManager.shared }
    private var liveStockManager: LiveStockPriceManager { LiveStockPriceManager.shared }
    @State private var stockWatchTick: UInt = 0
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var selectedStock: CachedStock?
    @State private var showMarketView: Bool = false
    @State private var showAddStock: Bool = false
    @State private var refreshTrigger: Int = 0
    
    private var isDark: Bool { colorScheme == .dark }
    
    // Market status
    private var isMarketOpen: Bool {
        StockMarketCache.shared.isMarketOpen
    }
    
    // Gold gradient for accents
    private var goldGradient: LinearGradient {
        isDark
            ? LinearGradient(
                colors: [StockBrandGold.light, StockBrandGold.base],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            : LinearGradient(
                colors: [StockBrandGold.base, StockBrandGold.dark],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
    }
    
    var body: some View {
        // FIX v23: Reference tick to trigger re-renders on debounced stock data updates
        let _ = stockWatchTick
        
        VStack(alignment: .leading, spacing: 0) {
            // Section Header
            sectionHeader
            
            // Content
            if watchlistManager.isEmpty {
                emptyStateView
            } else {
                watchlistContent
            }
        }
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
        // Navigation to full market view
        .navigationDestination(isPresented: $showMarketView) {
            StockMarketView()
        }
        // Navigation to add stock
        .navigationDestination(isPresented: $showAddStock) {
            AddStockHoldingView { holding in
                // When adding from watchlist, add to watchlist instead of portfolio
                if let ticker = holding.ticker {
                    watchlistManager.add(ticker)
                }
            }
        }
        // Pop-to-root: Dismiss all navigation when home tab is tapped
        // FIX v23: Debounced stock watchlist observation (replaces @ObservedObject)
        .onReceive(StockWatchlistManager.shared.objectWillChange.debounce(for: .seconds(3), scheduler: DispatchQueue.main)) { _ in
            guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
            stockWatchTick &+= 1
        }
        .onReceive(LiveStockPriceManager.shared.objectWillChange.debounce(for: .seconds(5), scheduler: DispatchQueue.main)) { _ in
            guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
            stockWatchTick &+= 1
        }
        // PERFORMANCE FIX v21: Use targeted onReceive instead of @EnvironmentObject var appState
        .onReceive(AppState.shared.$dismissHomeSubviews) { shouldDismiss in
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                if shouldDismiss {
                    // Clear all navigation states
                    if selectedStock != nil { selectedStock = nil }
                    if showMarketView { showMarketView = false }
                    if showAddStock { showAddStock = false }
                    // Reset the trigger after handling
                    AppState.shared.dismissHomeSubviews = false
                }
            }
        }
    }
    
    // MARK: - Section Header
    
    private var sectionHeader: some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            showMarketView = true
        } label: {
            HStack(spacing: 8) {
                // Gold accent icon - consistent with other sections
                GoldHeaderGlyph(systemName: "star.fill")
                
                Text("Stock Watchlist")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                // Market status badge
                marketStatusBadge
                
                Spacer()
                
                // Stock count
                if !watchlistManager.isEmpty {
                    Text("\(watchlistManager.count) stocks")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
        }
        .buttonStyle(.plain)
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
    
    // MARK: - Watchlist Content
    
    private var watchlistContent: some View {
        VStack(spacing: 0) {
            // Stock rows card
            VStack(spacing: 0) {
                // Show up to 5 stocks
                let displayStocks = Array(watchlistManager.watchlistStocks.prefix(5))
                
                ForEach(displayStocks) { stock in
                    stockRow(stock)
                        .onTapGesture {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            selectedStock = stock
                        }
                    
                    if stock.id != displayStocks.last?.id {
                        Divider()
                            .padding(.horizontal, 14)
                            .opacity(0.5)
                    }
                }
                
                // See all / Browse market row
                Divider()
                    .padding(.horizontal, 14)
                    .opacity(0.5)
                
                browseMarketRow
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
        .padding(.horizontal, 16)
    }
    
    // MARK: - Stock Row
    
    private func stockRow(_ stock: CachedStock) -> some View {
        StockWatchlistRowView(
            stock: stock,
            onRemove: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    watchlistManager.remove(stock.symbol)
                }
            }
        )
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
    
    // MARK: - Browse Market Row
    
    private var browseMarketRow: some View {
        SectionCTAButton(
            title: "Browse Stock Market",
            icon: "chart.line.uptrend.xyaxis",
            badge: watchlistManager.count > 5 ? "\(watchlistManager.count - 5) more" : nil,
            showGoldBar: true,
            compact: true
        ) {
            showMarketView = true
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(DS.Adaptive.gold.opacity(0.12))
                    .frame(width: 40, height: 40)
                
                Image(systemName: "star")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(DS.Adaptive.gold.opacity(0.7))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("No Stocks Watched")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textSecondary)
                
                Text("Add stocks to track their prices")
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            Spacer()
            
            Button {
                showMarketView = true
            } label: {
                Text("Browse")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(DS.Adaptive.gold))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DS.Adaptive.divider.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }
    
    // MARK: - Formatters
    
    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
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
    
    private func formatPercent(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", value))%"
    }
}

// MARK: - Stock Watchlist Row View (with animations)

private struct StockWatchlistRowView: View {
    let stock: CachedStock
    let onRemove: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var priceColor: Color = .primary
    @State private var priceScale: CGFloat = 1.0
    @State private var lastPrice: Double = 0
    @State private var starScale: CGFloat = 1.0
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        HStack(spacing: 10) {
            // Stock Logo
            StockImageView(
                ticker: stock.symbol,
                assetType: stock.assetType,
                size: 36
            )
            
            // Ticker and name
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(stock.symbol)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    // ETF badge
                    if stock.assetType == .etf {
                        Text("ETF")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(AssetType.etf.color.opacity(0.9))
                            .clipShape(Capsule())
                    }
                }
                
                Text(stock.name)
                    .font(.system(size: 10))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Price and change
            VStack(alignment: .trailing, spacing: 1) {
                Text(formatCurrency(stock.currentPrice))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(priceColor)
                    .monospacedDigit()
                    .scaleEffect(priceScale)
                    .contentTransition(.numericText())
                
                HStack(spacing: 2) {
                    Image(systemName: stock.changePercent >= 0 ? "arrow.up" : "arrow.down")
                        .font(.system(size: 7, weight: .bold))
                    
                    Text(formatPercent(stock.changePercent))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundColor(stock.changePercent >= 0 ? .green : .red)
            }
            
            // Remove button with animation
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                    starScale = 0.7
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    onRemove()
                }
            } label: {
                Image(systemName: "star.fill")
                    .font(.system(size: 14))
                    .foregroundColor(DS.Adaptive.gold)
                    .scaleEffect(starScale)
            }
            .buttonStyle(.plain)
        }
        .onAppear {
            lastPrice = stock.currentPrice
            priceColor = DS.Adaptive.textPrimary
        }
        .onChange(of: stock.currentPrice) { _, newPrice in
            // PERFORMANCE FIX v13: Skip during global startup phase to prevent warnings
            guard !isInGlobalStartupPhase() else { return }
            // PERFORMANCE FIX: Skip during scroll to prevent "multiple updates per frame"
            guard !ScrollStateManager.shared.isScrolling && !ScrollStateManager.shared.isFastScrolling else { return }
            
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                guard newPrice != lastPrice, lastPrice > 0 else {
                    lastPrice = newPrice
                    return
                }
                
                let wentUp = newPrice > lastPrice
                
                // Animate price change
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    priceColor = wentUp ? .green : .red
                    priceScale = wentUp ? 1.02 : 0.98
                }
                
                // Reset after animation
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
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
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
    
    private func formatPercent(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", value))%"
    }
}

// MARK: - Preview

#Preview("With Stocks") {
    StockWatchlistSection()
        .preferredColorScheme(.dark)
        .onAppear {
            // Add some demo stocks for preview
            StockWatchlistManager.shared.add("AAPL")
            StockWatchlistManager.shared.add("TSLA")
            StockWatchlistManager.shared.add("NVDA")
        }
}

#Preview("Empty") {
    StockWatchlistSection()
        .preferredColorScheme(.dark)
}
