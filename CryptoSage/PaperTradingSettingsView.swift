//
//  PaperTradingSettingsView.swift
//  CryptoSage
//
//  Enhanced settings view for paper trading with live prices, performance stats,
//  portfolio breakdown, and comprehensive trade history.
//

import SwiftUI
import Combine

// MARK: - Coin Image URL Helper

/// Resolves a coin image URL for a given asset symbol.
/// Uses well-known CDN URLs for reliable coin logos.
/// CoinImageView also has its own fallback chain for additional resilience.
func coinImageURL(for symbol: String) -> URL? {
    let lowerSymbol = symbol.lowercased()
    
    // Map common stablecoins/wrapped tokens to their base symbols for better logo matching
    let normalizedSymbol: String
    switch lowerSymbol {
    case "usdt", "usdc", "busd", "fdusd", "usd":
        // Stablecoins - use tether logo as common representation
        normalizedSymbol = "usdt"
    default:
        normalizedSymbol = lowerSymbol
    }
    
    // CoinCap assets (reliable for major coins)
    return URL(string: "https://assets.coincap.io/assets/icons/\(normalizedSymbol)@2x.png")
}

struct PaperTradingSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var paperTradingManager = PaperTradingManager.shared
    @StateObject private var portfolioVM = PortfolioViewModel(repository: PortfolioRepository.shared)
    @StateObject private var socialService = SocialService.shared
    
    /// Check if user is on the leaderboard (editing balance disabled for fair competition)
    private var isOnLeaderboard: Bool {
        guard let profile = socialService.currentProfile else { return false }
        return profile.showOnLeaderboard
    }
    
    // Sheet states
    @State private var showResetAlert = false
    @State private var showEditBalanceSheet = false
    @State private var showAddBalanceSheet = false
    @State private var showRemoveBalanceSheet = false
    @State private var showFullHistorySheet = false
    @State private var showExportSheet = false
    @State private var showResetInfoSheet = false
    
    // Balance editing
    @State private var newStartingBalance: String = ""
    @State private var selectedAsset: String = "BTC"
    @State private var addAmount: String = ""
    @State private var removeAsset: String = "BTC"
    @State private var removeAmount: String = ""
    
    // Trade filters
    @State private var selectedSideFilter: TradeSide? = nil
    @State private var selectedAssetFilter: String? = nil
    
    // Live prices from LivePriceManager
    @State private var currentPrices: [String: Double] = [:]
    @State private var pricesCancellable: AnyCancellable?
    
    // Animation states
    @State private var pnlAnimationTrigger = false
    
    // Pie chart state (unused — chart handles its own slice interaction)
    
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    
    // Pie chart sizing — larger on the detail page for better visual presence
    private let pieChartSize: CGFloat = 105
    
    private var paperPrimary: Color { AppTradingMode.paper.color }
    private var paperSecondary: Color { AppTradingMode.paper.secondaryColor }
    
    // Available assets for adding balance
    private let availableAssets = ["USDT", "BTC", "ETH", "BNB", "SOL", "XRP", "ADA", "DOGE", "MATIC", "DOT", "AVAX", "LINK"]
    
    // MARK: - Allocation Slices for Pie Chart
    
    /// Generate allocation slices for the pie chart from Paper Trading balances
    private var allocationSlices: [PortfolioViewModel.AllocationSlice] {
        let totalValue = paperTradingManager.calculatePortfolioValue(prices: currentPrices)
        guard totalValue > 0 else { return [] }
        
        var slices: [PortfolioViewModel.AllocationSlice] = []
        
        for item in paperTradingManager.nonZeroBalances {
            let price = currentPrices[item.asset] ?? 1.0
            let value = item.amount * price
            let percent = (value / totalValue) * 100
            
            if percent >= 0.5 { // Only show assets with >= 0.5% allocation
                slices.append(PortfolioViewModel.AllocationSlice(
                    symbol: item.asset,
                    percent: percent,
                    color: assetColor(item.asset)
                ))
            }
        }
        
        return slices.sorted { $0.percent > $1.percent }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header Card with pie chart
                headerCard
                
                // Performance Statistics
                performanceSection
                
                // Balances Section
                balanceSection
                
                // Quick Actions (expanded)
                quickActionsSection
                
                // Paper Trading Bots Section
                PaperBotsSection()
                
                // Trade History (with filters)
                tradeHistorySection
                
                // Danger Zone
                resetSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .withUIKitScrollBridge() // PERFORMANCE FIX v21: UIKit scroll bridge for snappier deceleration + animation freeze
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationTitle("Paper Trading")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                CSNavButton(icon: "chevron.left", action: { dismiss() }, compact: true)
            }
        }
        .toolbarBackground(DS.Adaptive.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
        // NAVIGATION: Re-enable native iOS swipe-back gesture (hidden back button disables it)
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
        .onAppear {
            setupLivePrices()
        }
        .onDisappear {
            pricesCancellable?.cancel()
        }
        .alert("Reset Paper Trading", isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) { }
            if paperTradingManager.canReset {
                Button("Reset", role: .destructive) {
                    impactMedium.impactOccurred()
                    paperTradingManager.resetPaperTrading()
                }
            }
        } message: {
            if !paperTradingManager.canReset {
                let windowDays = paperTradingManager.resetWindowDaysForCurrentTier
                Text("You've already used your reset for this \(windowDays <= 30 ? "month" : "quarter"). Please wait for the cooldown to expire before resetting again.")
            } else {
                Text("This will reset your balance to $\(Int(paperTradingManager.startingBalance).formatted()) and clear all trade history. This cannot be undone.\n\nLeaderboard impact:\n\u{2022} 14-day leaderboard cooldown\n\u{2022} 20% score penalty\n\u{2022} Time-weight bonus resets to minimum")
            }
        }
        .sheet(isPresented: $showEditBalanceSheet) {
            editBalanceSheet
        }
        .sheet(isPresented: $showAddBalanceSheet) {
            addBalanceSheet
        }
        .sheet(isPresented: $showRemoveBalanceSheet) {
            removeBalanceSheet
        }
        .sheet(isPresented: $showFullHistorySheet) {
            PaperTradeHistoryFullView(currentPrices: currentPrices)
        }
        .sheet(isPresented: $showExportSheet) {
            exportSheet
        }
        .sheet(isPresented: $showResetInfoSheet) {
            PaperTradingResetInfoSheet(isPresented: $showResetInfoSheet)
        }
    }
    
    // MARK: - Live Price Setup
    
    private func setupLivePrices() {
        // Initialize with cached/default prices
        loadDefaultPrices()
        
        // Subscribe to live price updates
        // PRICE CONSISTENCY FIX: Use bestPrice() for consistent pricing across all views
        // PERFORMANCE FIX v22: Use slowPublisher (2s throttle) instead of raw publisher.
        // Paper trading settings don't need real-time prices.
        pricesCancellable = LivePriceManager.shared.slowPublisher
            .receive(on: DispatchQueue.main)
            .sink { coins in
                var newPrices: [String: Double] = currentPrices
                for coin in coins {
                    let symbol = coin.symbol.uppercased()
                    // Priority: bestPrice() > coin.priceUsd (fallback)
                    if let price = MarketViewModel.shared.bestPrice(for: coin.id), price > 0 {
                        newPrices[symbol] = price
                    } else if let price = coin.priceUsd, price > 0 {
                        newPrices[symbol] = price
                    }
                }
                
                // FIX: For any held assets not found in the slowPublisher emission,
                // try bestPrice(forSymbol:) which checks all available sources
                for (asset, _) in paperTradingManager.paperBalances {
                    let symbol = asset.uppercased()
                    if newPrices[symbol] == nil || newPrices[symbol] == 0 {
                        if let symbolPrice = MarketViewModel.shared.bestPrice(forSymbol: symbol), symbolPrice > 0 {
                            newPrices[symbol] = symbolPrice
                        }
                    }
                }
                
                // Ensure stablecoins are always correct
                newPrices["USDT"] = 1.0
                newPrices["USD"] = 1.0
                newPrices["USDC"] = 1.0
                
                // Push fresh prices to PaperTradingManager cache (with timestamps)
                paperTradingManager.updateLastKnownPrices(newPrices)
                
                // Check if P&L changed significantly for animation
                let oldPnl = paperTradingManager.calculateProfitLoss(prices: currentPrices)
                let newPnl = paperTradingManager.calculateProfitLoss(prices: newPrices)
                if abs(newPnl - oldPnl) > 10 {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        pnlAnimationTrigger.toggle()
                    }
                }
                
                currentPrices = newPrices
            }
    }
    
    private func loadDefaultPrices() {
        // Use MarketViewModel.shared.allCoins for consistency with other views (Home, Portfolio)
        // This ensures Paper Trading values match across the entire app
        var prices: [String: Double] = [
            // Stablecoins are always 1:1 with USD
            "USDT": 1.0, "USD": 1.0, "USDC": 1.0, "BUSD": 1.0, "FDUSD": 1.0
        ]
        
        // Load prices from MarketViewModel (same source as PortfolioSectionView)
        // PRICE CONSISTENCY FIX: Use bestPrice() for consistent pricing across all views
        for coin in MarketViewModel.shared.allCoins {
            let symbol = coin.symbol.uppercased()
            // Priority: bestPrice() > coin.priceUsd (fallback)
            if let price = MarketViewModel.shared.bestPrice(for: coin.id), price > 0 {
                prices[symbol] = price
            } else if let price = coin.priceUsd, price > 0 {
                prices[symbol] = price
            }
        }
        
        // FIX: For any held assets not yet resolved, try bestPrice(forSymbol:)
        // This covers startup scenarios where allCoins hasn't loaded yet
        for (asset, _) in paperTradingManager.paperBalances {
            let symbol = asset.uppercased()
            if prices[symbol] == nil || prices[symbol] == 0 {
                if let symbolPrice = MarketViewModel.shared.bestPrice(forSymbol: symbol), symbolPrice > 0 {
                    prices[symbol] = symbolPrice
                }
            }
        }
        
        // Final fallback: Use lastKnownPrices for any remaining gaps (only if fresh)
        for (asset, _) in paperTradingManager.paperBalances {
            let symbol = asset.uppercased()
            if prices[symbol] == nil || prices[symbol] == 0 {
                if let cachedPrice = paperTradingManager.lastKnownPrices[symbol], cachedPrice > 0,
                   paperTradingManager.isCachedPriceFresh(for: symbol) {
                    prices[symbol] = cachedPrice
                }
            }
        }
        
        currentPrices = prices
    }
    
    // MARK: - Header Card
    
    private var headerCard: some View {
        let isDark = colorScheme == .dark
        let portfolioValue = paperTradingManager.calculatePortfolioValue(prices: currentPrices)
        let pnl = paperTradingManager.calculateProfitLoss(prices: currentPrices)
        let pnlPercent = paperTradingManager.calculateProfitLossPercent(prices: currentPrices)
        let plColor = pnl >= 0 ? Color.green : Color.red
        
        return VStack(spacing: 12) {
            // Main content: Portfolio metrics + Pie chart
            HStack(alignment: .top, spacing: 12) {
                // Left: Portfolio value and P&L
                VStack(alignment: .leading, spacing: 4) {
                    // Portfolio value - large and prominent
                    Text(formatCurrency(portfolioValue))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .contentTransition(.numericText())
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .allowsTightening(true)
                    
                    // "Total Value" label with status indicator — uses paper mode accent color
                    HStack(spacing: 6) {
                        Text("Total Value")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(AppTradingMode.paper.color)
                        
                        // Active status dot
                        if paperTradingManager.isPaperTradingEnabled {
                            Circle()
                                .fill(AppTradingMode.paper.color)
                                .frame(width: 6, height: 6)
                        }
                    }
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    
                    // P&L metrics
                    HStack(spacing: 14) {
                        // P&L Percentage
                        VStack(alignment: .leading, spacing: 2) {
                            Text("P&L")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundColor(isDark ? .white.opacity(0.5) : .secondary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                            Text(String(format: "%@%.2f%%", pnl >= 0 ? "+" : "", pnlPercent))
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(plColor)
                                .contentTransition(.numericText())
                                .animation(.easeOut(duration: 0.25), value: pnlPercent)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        
                        // Total P&L Value
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Total P&L")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundColor(isDark ? .white.opacity(0.5) : .secondary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                            Text(String(format: "%@%@", pnl >= 0 ? "+" : "-", formatCurrency(abs(pnl))))
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(plColor)
                                .contentTransition(.numericText())
                                .animation(.easeOut(duration: 0.25), value: pnl)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        Spacer()
                    }
                    .padding(.top, 4)
                    
                    // Starting balance and duration info - cleaner single row
                    HStack(spacing: 0) {
                        Text("Started ")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(DS.Adaptive.textTertiary)
                        
                        if let startDate = paperTradingManager.tradingSinceDate {
                            Text(formatShortDate(startDate))
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundColor(DS.Adaptive.textSecondary)
                        }
                        
                        Text(" with ")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(DS.Adaptive.textTertiary)
                        
                        Text(formatCurrency(paperTradingManager.startingBalance))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(DS.Adaptive.textSecondary)
                        
                        // Edit button - always available (only affects next reset)
                        Button(action: {
                            impactLight.impactOccurred()
                            newStartingBalance = String(Int(paperTradingManager.startingBalance))
                            showEditBalanceSheet = true
                        }) {
                            Text("Edit")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundColor(paperPrimary)
                                .padding(.leading, 6)
                        }
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Right: Pie chart — interactive mini version.
                // Tap a slice to pop it out, tap center to reset.
                ThemedPortfolioPieChartView(
                    portfolioVM: portfolioVM,
                    showLegend: .constant(false),
                    allowRotation: false,
                    allowSweepOscillation: false,
                    showSweepIndicator: false,
                    allowHoverScrub: false,
                    showSliceCallouts: false,
                    showRotatingSheen: false,
                    showIdleCenterRing: false,
                    showActiveStartTick: false,
                    showSliceSeparators: false,
                    overrideAllocationData: allocationSlices,
                    centerMode: .hidden
                )
                .frame(width: pieChartSize, height: pieChartSize)
                .clipShape(Circle())
            }
            
            // Allocation chips row — matches homepage portfolio chip styling
            if !allocationSlices.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(allocationSlices.prefix(5), id: \.symbol) { slice in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(slice.color)
                                    .frame(width: 7, height: 7)
                                    .overlay(
                                        Circle()
                                            .stroke(slice.color.opacity(0.3), lineWidth: 1)
                                    )
                                
                                Text(slice.symbol)
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(DS.Adaptive.textPrimary)
                                
                                Text("\(Int(round(slice.percent)))%")
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundStyle(DS.Adaptive.textSecondary)
                                    .monospacedDigit()
                            }
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(slice.color.opacity(isDark ? 0.10 : 0.08))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                DS.Adaptive.stroke.opacity(0.6),
                                                DS.Adaptive.stroke.opacity(0.3)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ),
                                        lineWidth: 0.5
                                    )
                            )
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(headerCardBackground(isDark: isDark, plColor: plColor))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            plColor.opacity(isDark ? 0.35 : 0.25),
                            isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .animation(.easeInOut(duration: 0.3), value: pnl)
    }
    
    @ViewBuilder
    private func headerCardBackground(isDark: Bool, plColor: Color) -> some View {
        ZStack {
            // Base fill - matching Portfolio page
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: isDark ? [
                            Color.gray.opacity(0.2),
                            Color.black.opacity(0.4)
                        ] : [
                            Color(red: 1.0, green: 0.995, blue: 0.98),
                            Color(red: 0.96, green: 0.97, blue: 0.98)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }
    
    // MARK: - Performance Section
    
    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header with premium icon
            HStack(spacing: 8) {
                GoldHeaderGlyphCompact(systemName: "chart.line.uptrend.xyaxis")
                Text("Performance")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
            }
            
            let totalTrades = paperTradingManager.totalTradeCount
            
            if totalTrades == 0 {
                // Empty state with improved styling
                VStack(spacing: 10) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 28))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    Text("No trades yet")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DS.Adaptive.textSecondary)
                    Text("Start trading to see your performance stats")
                        .font(.system(size: 12))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                // Stats grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 10) {
                    // Total Trades — uses paper trading's amber accent
                    StatCard(
                        title: "Trades",
                        value: "\(totalTrades)",
                        subtitle: "\(paperTradingManager.buyTradeCount)B · \(paperTradingManager.sellTradeCount)S",
                        icon: "arrow.triangle.swap",
                        color: AppTradingMode.paper.color
                    )
                    
                    // Win Rate
                    let winRate = paperTradingManager.calculateWinRate(prices: currentPrices)
                    StatCard(
                        title: "Win Rate",
                        value: String(format: "%.0f%%", winRate),
                        subtitle: paperTradingManager.sellTradeCount > 0 ? "based on sells" : "no sells yet",
                        icon: "percent",
                        color: winRate >= 50 ? .green : .orange
                    )
                    
                    // Avg Trade Size
                    StatCard(
                        title: "Avg Trade",
                        value: formatCompactCurrency(paperTradingManager.averageTradeSize),
                        subtitle: "per trade",
                        icon: "banknote.fill",
                        color: .purple
                    )
                }
                
                // Second row: Best & Volume - equal width grid layout
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    // Best Trade card
                    if let best = paperTradingManager.bestTrade {
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [paperPrimary.opacity(0.25), paperSecondary.opacity(0.12)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 36, height: 36)
                                Circle()
                                    .stroke(paperPrimary.opacity(0.3), lineWidth: 1)
                                    .frame(width: 36, height: 36)
                                Image(systemName: "star.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [paperSecondary, paperPrimary],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            }
                            
                            VStack(spacing: 2) {
                                Text("Best Trade")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(DS.Adaptive.textTertiary)
                                    .textCase(.uppercase)
                                Text("\(best.side == .buy ? "Buy" : "Sell") \(formatCompactQuantity(best.quantity)) \(parseBaseAsset(best.symbol))")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(DS.Adaptive.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                            
                            Text(formatCompactCurrency(best.totalValue))
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(.green)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(DS.Adaptive.background.opacity(0.7))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(DS.Adaptive.stroke.opacity(0.5), lineWidth: 0.5)
                                )
                        )
                    } else {
                        // Placeholder when no best trade
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(DS.Adaptive.background.opacity(0.5))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "star")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(DS.Adaptive.textTertiary)
                            }
                            Text("Best Trade")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(DS.Adaptive.textTertiary)
                                .textCase(.uppercase)
                            Text("--")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(DS.Adaptive.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(DS.Adaptive.background.opacity(0.7))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(DS.Adaptive.stroke.opacity(0.5), lineWidth: 0.5)
                                )
                        )
                    }
                    
                    // Volume card - matching structure
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.cyan.opacity(0.25), Color.cyan.opacity(0.10)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 36, height: 36)
                            Circle()
                                .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
                                .frame(width: 36, height: 36)
                            Image(systemName: "waveform.path.ecg")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color.cyan, Color.cyan.opacity(0.75)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        }
                        
                        Text("Volume")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                            .textCase(.uppercase)
                        
                        Text(formatCompactCurrency(paperTradingManager.totalVolumeTraded))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(DS.Adaptive.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(DS.Adaptive.background.opacity(0.7))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(DS.Adaptive.stroke.opacity(0.5), lineWidth: 0.5)
                            )
                    )
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
                )
        )
    }
    
    // MARK: - Balance Section
    
    private var balanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    GoldHeaderGlyphCompact(systemName: "wallet.pass")
                    Text("Balances")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                
                Spacer()
                
                // Add button
                Button(action: {
                    impactLight.impactOccurred()
                    showAddBalanceSheet = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 12))
                        Text("Add")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.green.opacity(0.12))
                            .overlay(Capsule().stroke(Color.green.opacity(0.25), lineWidth: 0.5))
                    )
                }
                
                // Remove button
                Button(action: {
                    impactLight.impactOccurred()
                    showRemoveBalanceSheet = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 12))
                        Text("Remove")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.red.opacity(0.12))
                            .overlay(Capsule().stroke(Color.red.opacity(0.25), lineWidth: 0.5))
                    )
                }
                .padding(.leading, 6)
            }
            
            let balances = paperTradingManager.nonZeroBalances
            
            if balances.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 28))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    Text("No balances yet")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DS.Adaptive.textSecondary)
                    Text("Add funds or start trading")
                        .font(.system(size: 12))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                VStack(spacing: 8) {
                    ForEach(balances, id: \.asset) { item in
                        EnhancedBalanceRow(
                            asset: item.asset,
                            amount: item.amount,
                            price: currentPrices[item.asset],
                            totalPortfolioValue: paperTradingManager.calculatePortfolioValue(prices: currentPrices),
                            color: assetColor(item.asset)
                        )
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
                )
        )
    }
    
    // MARK: - Quick Actions
    
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                GoldHeaderGlyphCompact(systemName: "bolt.circle.fill")
                Text("Quick Actions")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
            }
            
            // First row: Pause/Start and Reset
            HStack(spacing: 10) {
                // Toggle Paper Trading
                QuickActionButton(
                    icon: paperTradingManager.isPaperTradingEnabled ? "pause.circle.fill" : "play.circle.fill",
                    title: paperTradingManager.isPaperTradingEnabled ? "Pause" : "Start",
                    color: paperTradingManager.isPaperTradingEnabled ? AppTradingMode.paper.color : .green
                ) {
                    impactMedium.impactOccurred()
                    paperTradingManager.toggle()
                }
                
                // Reset
                QuickActionButton(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Reset",
                    color: .red
                ) {
                    impactLight.impactOccurred()
                    showResetAlert = true
                }
            }
            
            // Second row: Quick Trade and Export
            HStack(spacing: 10) {
                // Quick Trade (NavigationLink)
                NavigationLink(destination: TradeView()) {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            ZStack {
                                // Premium gradient background circle
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.blue.opacity(0.25), Color.blue.opacity(0.10)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 44, height: 44)
                                
                                // Subtle ring stroke
                                Circle()
                                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                                    .frame(width: 44, height: 44)
                                
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [Color.blue, Color.blue.opacity(0.8)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            }
                            Text("Quick Trade")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(DS.Adaptive.textPrimary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(DS.Adaptive.cardBackground)
                            LinearGradient(
                                colors: [Color.white.opacity(0.06), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [DS.Adaptive.stroke, DS.Adaptive.stroke.opacity(0.5)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.5
                            )
                    )
                    // Subtle color glow removed for memory
                }
                .buttonStyle(PlainButtonStyle())
                
                // Export History
                QuickActionButton(
                    icon: "doc.badge.arrow.up.fill",
                    title: "Export",
                    color: .purple
                ) {
                    impactLight.impactOccurred()
                    showExportSheet = true
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
                )
        )
    }
    
    // MARK: - Trade History Section
    
    private var tradeHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row with title and actions
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    GoldHeaderGlyphCompact(systemName: "clock.arrow.circlepath")
                    Text("Recent Trades")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                
                Spacer()
                
                Text("\(paperTradingManager.paperTradeHistory.count) total")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
                
                if paperTradingManager.paperTradeHistory.count > 5 {
                    Button(action: {
                        impactLight.impactOccurred()
                        showFullHistorySheet = true
                    }) {
                        HStack(spacing: 3) {
                            Text("View All")
                                .font(.system(size: 11, weight: .semibold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(
                            LinearGradient(
                                colors: [paperSecondary, paperPrimary],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    }
                    .padding(.leading, 6)
                }
            }
            
            // Filter chips with improved styling
            if paperTradingManager.paperTradeHistory.count > 0 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(title: "All", isSelected: selectedSideFilter == nil, color: paperPrimary) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                selectedSideFilter = nil
                            }
                            impactLight.impactOccurred()
                        }
                        FilterChip(title: "Buys", isSelected: selectedSideFilter == .buy, color: .green) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                selectedSideFilter = .buy
                            }
                            impactLight.impactOccurred()
                        }
                        FilterChip(title: "Sells", isSelected: selectedSideFilter == .sell, color: .red) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                selectedSideFilter = .sell
                            }
                            impactLight.impactOccurred()
                        }
                    }
                }
            }
            
            let filteredTrades = paperTradingManager.filteredTrades(side: selectedSideFilter, asset: selectedAssetFilter)
            let recentTrades = Array(filteredTrades.prefix(5))
            
            if recentTrades.isEmpty {
                // Empty state with improved styling
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 28))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    Text("No trades yet")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DS.Adaptive.textSecondary)
                    Text("Your paper trade history will appear here")
                        .font(.system(size: 12))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                // Trade list with improved card styling
                VStack(spacing: 8) {
                    ForEach(recentTrades, id: \.id) { trade in
                        EnhancedTradeRow(trade: trade, currentPrice: currentPrices[parseBaseAsset(trade.symbol)])
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
                )
        )
    }
    
    // MARK: - Reset Section
    
    // MARK: - Reset Section Subviews (split to help type-checker)
    
    @ViewBuilder
    private func resetSectionHeader(canReset: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.counterclockwise.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.red)
            Text("RESET ACCOUNT")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.red)
                .tracking(0.5)
            
            Spacer()
            
            Button {
                showResetInfoSheet = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 13))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    @ViewBuilder
    private func resetFrequencyInfo(canReset: Bool, isPremium: Bool, windowDays: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: canReset ? "checkmark.circle.fill" : "clock.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(canReset ? .green : .orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(canReset ? "Reset available" : "Reset on cooldown")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text(isPremium
                    ? "Premium \u{2022} Once every \(windowDays) days"
                    : "Pro \u{2022} Once every \(windowDays) days")
                    .font(.system(size: 10))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            
            Spacer()
            
            if isPremium {
                Text("Monthly")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(BrandColors.goldBase)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(BrandColors.goldBase.opacity(0.15)))
            } else {
                Text("Quarterly")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(DS.Adaptive.background.opacity(0.8)))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DS.Adaptive.background.opacity(0.5))
        )
    }
    
    @ViewBuilder
    private func resetButton(canReset: Bool) -> some View {
        Button(action: {
            impactMedium.impactOccurred()
            showResetAlert = true
        }) {
            HStack(spacing: 6) {
                Image(systemName: canReset ? "trash.fill" : "lock.fill")
                    .font(.system(size: 13))
                Text(canReset ? "Reset All Paper Trading Data" : "Reset Unavailable")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(canReset ? Color.red : Color.gray)
                    if canReset {
                        LinearGradient(
                            colors: [Color.white.opacity(0.15), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!canReset)
        .opacity(canReset ? 1.0 : 0.7)
    }
    
    private var scorePenaltyRow: some View {
        let penaltyPercent = Int((1.0 - paperTradingManager.leaderboardScorePenaltyMultiplier) * 100)
        return HStack(spacing: 6) {
            Image(systemName: "chart.line.downtrend.xyaxis")
                .font(.system(size: 11))
                .foregroundColor(.orange)
            Text("Leaderboard score reduced by \(penaltyPercent)% due to recent reset")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.orange)
        }
    }
    
    @ViewBuilder
    private func nextResetRow(nextSlot: Date) -> some View {
        let formatter = RelativeDateTimeFormatter()
        let relative: String = {
            formatter.unitsStyle = .full
            return formatter.localizedString(for: nextSlot, relativeTo: Date())
        }()
        HStack(spacing: 6) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 11))
                .foregroundColor(DS.Adaptive.textSecondary)
            Text("Next reset available \(relative)")
                .font(.system(size: 11))
                .foregroundColor(DS.Adaptive.textSecondary)
        }
    }
    
    @ViewBuilder
    private func resetWarnings(canReset: Bool, cooldownDays: Int, isPremium: Bool) -> some View {
        // Leaderboard cooldown warning
        if cooldownDays > 0 {
            HStack(spacing: 6) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                Text("Leaderboard cooldown: \(cooldownDays) day\(cooldownDays == 1 ? "" : "s") remaining")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.orange)
            }
        }
        
        // Score penalty warning
        if paperTradingManager.resetsUsedInCurrentWindow > 0 {
            scorePenaltyRow
        }
        
        // When next reset is available
        if !canReset, let nextSlot = paperTradingManager.nextResetSlotAvailableAt {
            nextResetRow(nextSlot: nextSlot)
        }
        
        // Premium upsell for Pro users
        if !isPremium {
            HStack(spacing: 6) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 10))
                    .foregroundColor(BrandColors.goldBase)
                Text("Upgrade to Premium for monthly resets instead of quarterly")
                    .font(.system(size: 10))
                    .foregroundColor(BrandColors.goldBase.opacity(0.9))
            }
        }
    }
    
    private var resetSection: some View {
        let canReset = paperTradingManager.canReset
        let cooldownDays = paperTradingManager.leaderboardCooldownDaysRemaining
        let tier = SubscriptionManager.shared.effectiveTier
        let windowDays = paperTradingManager.resetWindowDaysForCurrentTier
        let isPremium = tier == .premium
        
        return VStack(alignment: .leading, spacing: 12) {
            resetSectionHeader(canReset: canReset)
            
            Text("Resetting will clear all balances, trade history, and leaderboard progress. Your account will return to the starting balance.")
                .font(.system(size: 12))
                .foregroundColor(DS.Adaptive.textSecondary)
                .lineSpacing(2)
            
            resetFrequencyInfo(canReset: canReset, isPremium: isPremium, windowDays: windowDays)
            
            resetWarnings(canReset: canReset, cooldownDays: cooldownDays, isPremium: isPremium)
            
            resetButton(canReset: canReset)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.red.opacity(0.25), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Edit Balance Sheet
    
    private var editBalanceSheet: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Starting Balance")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DS.Adaptive.textSecondary)
                    
                    TextField("Enter amount", text: $newStartingBalance)
                        .keyboardType(.numberPad)
                        .font(.system(size: 18, weight: .semibold))
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(DS.Adaptive.cardBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(DS.Adaptive.stroke, lineWidth: 1)
                                )
                        )
                    
                    Text("This will be your starting USDT balance when you reset.")
                        .font(.system(size: 12))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    
                    // Info about leaderboard fairness
                    if isOnLeaderboard {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.blue)
                            Text("Leaderboard ROI is calculated from your starting balance. For fair comparison, the standard is $\(Int(PaperTradingManager.defaultStartingBalance).formatted()).")
                                .font(.system(size: 11))
                                .foregroundColor(DS.Adaptive.textTertiary)
                        }
                        .padding(.top, 4)
                    }
                }
                
                // Preset amounts
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick Select")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DS.Adaptive.textSecondary)
                    
                    HStack(spacing: 10) {
                        ForEach([10000, 50000, 100000, 500000, 1000000], id: \.self) { amount in
                            Button(action: {
                                impactLight.impactOccurred()
                                newStartingBalance = String(amount)
                            }) {
                                Text(formatCompactAmount(Double(amount)))
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(DS.Adaptive.textPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(DS.Adaptive.cardBackground)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(DS.Adaptive.stroke, lineWidth: 1)
                                            )
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                
                Spacer()
                
                Button(action: {
                    impactMedium.impactOccurred()
                    if let amount = Double(newStartingBalance), amount > 0 {
                        paperTradingManager.startingBalance = amount
                    }
                    showEditBalanceSheet = false
                }) {
                    Text("Save")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(20)
            .background(DS.Adaptive.background.ignoresSafeArea())
            .navigationTitle("Edit Starting Balance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DS.Adaptive.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showEditBalanceSheet = false } label: {
                        Text("Cancel")
                            .foregroundStyle(DS.Adaptive.textSecondary)
                    }
                }
            }
        }
    }
    
    // MARK: - Add Balance Sheet
    
    private var addBalanceSheet: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Asset picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Asset")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DS.Adaptive.textSecondary)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(availableAssets, id: \.self) { asset in
                                AssetChip(
                                    asset: asset,
                                    isSelected: selectedAsset == asset,
                                    color: assetColor(asset)
                                ) {
                                    impactLight.impactOccurred()
                                    selectedAsset = asset
                                }
                            }
                        }
                    }
                }
                
                // Amount input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Amount to Add")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DS.Adaptive.textSecondary)
                    
                    TextField("Enter amount", text: $addAmount)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 18, weight: .semibold))
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(DS.Adaptive.cardBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(DS.Adaptive.stroke, lineWidth: 1)
                                )
                        )
                    
                    // Current balance
                    let currentBalance = paperTradingManager.balance(for: selectedAsset)
                    Text("Current balance: \(formatQuantity(currentBalance)) \(selectedAsset)")
                        .font(.system(size: 12))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                
                // Quick amounts based on asset
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick Add")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DS.Adaptive.textSecondary)
                    
                    HStack(spacing: 10) {
                        ForEach(quickAmountsForAsset(selectedAsset), id: \.self) { amount in
                            Button(action: {
                                impactLight.impactOccurred()
                                addAmount = formatQuantityForInput(amount)
                            }) {
                                Text(formatQuickAmount(amount, asset: selectedAsset))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(DS.Adaptive.textPrimary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(DS.Adaptive.cardBackground)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(DS.Adaptive.stroke, lineWidth: 1)
                                            )
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                
                Spacer()
                
                Button(action: {
                    impactMedium.impactOccurred()
                    if let amount = Double(addAmount), amount > 0 {
                        paperTradingManager.addToBalance(asset: selectedAsset, amount: amount)
                    }
                    addAmount = ""
                    showAddBalanceSheet = false
                }) {
                    Text("Add Balance")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.green)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(20)
            .background(DS.Adaptive.background.ignoresSafeArea())
            .navigationTitle("Add Balance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DS.Adaptive.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAddBalanceSheet = false } label: {
                        Text("Cancel")
                            .foregroundStyle(DS.Adaptive.textSecondary)
                    }
                }
            }
        }
    }
    
    // MARK: - Remove Balance Sheet
    
    private var removeBalanceSheet: some View {
        NavigationView {
            VStack(spacing: 24) {
                let nonZeroAssets = paperTradingManager.nonZeroBalances.map { $0.asset }
                
                if nonZeroAssets.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "wallet.pass")
                            .font(.system(size: 48))
                            .foregroundColor(DS.Adaptive.textTertiary)
                        Text("No balances to remove")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Asset picker (only show assets with balance)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Asset")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(DS.Adaptive.textSecondary)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(nonZeroAssets, id: \.self) { asset in
                                    AssetChip(
                                        asset: asset,
                                        isSelected: removeAsset == asset,
                                        color: assetColor(asset)
                                    ) {
                                        impactLight.impactOccurred()
                                        removeAsset = asset
                                    }
                                }
                            }
                        }
                    }
                    
                    // Amount input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Amount to Remove")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(DS.Adaptive.textSecondary)
                        
                        TextField("Enter amount", text: $removeAmount)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 18, weight: .semibold))
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(DS.Adaptive.cardBackground)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(DS.Adaptive.stroke, lineWidth: 1)
                                    )
                            )
                        
                        let currentBalance = paperTradingManager.balance(for: removeAsset)
                        HStack {
                            Text("Available: \(formatQuantity(currentBalance)) \(removeAsset)")
                                .font(.system(size: 12))
                                .foregroundColor(DS.Adaptive.textTertiary)
                            Spacer()
                            Button("Max") {
                                impactLight.impactOccurred()
                                removeAmount = formatQuantityForInput(currentBalance)
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.blue)
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        impactMedium.impactOccurred()
                        if let amount = Double(removeAmount), amount > 0 {
                            _ = paperTradingManager.deductFromBalance(asset: removeAsset, amount: amount)
                        }
                        removeAmount = ""
                        showRemoveBalanceSheet = false
                    }) {
                        Text("Remove Balance")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.red)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(20)
            .background(DS.Adaptive.background.ignoresSafeArea())
            .navigationTitle("Remove Balance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DS.Adaptive.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showRemoveBalanceSheet = false } label: {
                        Text("Cancel")
                            .foregroundStyle(DS.Adaptive.textSecondary)
                    }
                }
            }
        }
    }
    
    // resetInfoSheet is extracted to PaperTradingResetInfoSheet (below)
    // to reduce type-checker complexity in this struct.
    
    // MARK: - Export Sheet
    
    private var exportSheet: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundColor(.purple)
                    
                    Text("Export Trade History")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Text("Export your paper trading history as a CSV file that you can open in Excel or Google Sheets.")
                        .font(.system(size: 14))
                        .foregroundColor(DS.Adaptive.textSecondary)
                        .multilineTextAlignment(.center)
                    
                    // Stats preview
                    VStack(spacing: 8) {
                        HStack {
                            Text("Total Trades")
                                .foregroundColor(DS.Adaptive.textSecondary)
                            Spacer()
                            Text("\(paperTradingManager.totalTradeCount)")
                                .fontWeight(.semibold)
                        }
                        Divider()
                        HStack {
                            Text("Date Range")
                                .foregroundColor(DS.Adaptive.textSecondary)
                            Spacer()
                            if let first = paperTradingManager.paperTradeHistory.last,
                               let last = paperTradingManager.paperTradeHistory.first {
                                Text("\(formatShortDate(first.timestamp)) - \(formatShortDate(last.timestamp))")
                                    .fontWeight(.medium)
                            } else {
                                Text("N/A")
                            }
                        }
                    }
                    .font(.system(size: 13))
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 10).fill(DS.Adaptive.cardBackground))
                }
                
                Spacer()
                
                if paperTradingManager.paperTradeHistory.isEmpty {
                    Text("No trades to export")
                        .font(.system(size: 14))
                        .foregroundColor(DS.Adaptive.textTertiary)
                } else {
                    ShareLink(
                        item: paperTradingManager.exportToCSV(),
                        subject: Text("Paper Trading History"),
                        message: Text("My CryptoSage paper trading history")
                    ) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export CSV")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.purple)
                        )
                    }
                }
            }
            .padding(20)
            .background(DS.Adaptive.background.ignoresSafeArea())
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DS.Adaptive.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showExportSheet = false } label: {
                        Text("Done")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(DS.Adaptive.gold)
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func formatCurrency(_ value: Double, showSign: Bool = false) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = CurrencyManager.currencyCode
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        if showSign && value > 0 {
            return "+\(formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value))"
        }
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }
    
    private func formatCompactCurrency(_ value: Double) -> String {
        if value >= 1_000_000 {
            let millions = value / 1_000_000
            // Use no decimal if it's a round number
            if millions.truncatingRemainder(dividingBy: 1) == 0 {
                return String(format: "$%.0fM", millions)
            }
            return String(format: "$%.1fM", millions)
        } else if value >= 10_000 {
            // For 10K+, drop decimal to save space (e.g., $25K instead of $25.0K)
            return String(format: "$%.0fK", value / 1_000)
        } else if value >= 1_000 {
            let thousands = value / 1_000
            // Use no decimal if it's a round number
            if thousands.truncatingRemainder(dividingBy: 1) == 0 {
                return String(format: "$%.0fK", thousands)
            }
            return String(format: "$%.1fK", thousands)
        } else if value >= 100 {
            return String(format: "$%.0f", value)
        } else {
            return String(format: "$%.2f", value)
        }
    }
    
    private func formatCompactAmount(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "$%.0fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "$%.0fK", value / 1_000)
        } else {
            return String(format: "$%.0f", value)
        }
    }
    
    private func formatQuantity(_ value: Double) -> String {
        if value < 0.001 {
            return String(format: "%.8f", value)
        } else if value < 1 {
            return String(format: "%.4f", value)
        } else if value < 1000 {
            return String(format: "%.2f", value)
        } else {
            return String(format: "%.0f", value)
        }
    }
    
    private func formatQuantityForInput(_ value: Double) -> String {
        if value < 0.001 {
            return String(format: "%.8f", value)
        } else if value < 1 {
            return String(format: "%.6f", value)
        } else if value < 1000 {
            return String(format: "%.4f", value)
        } else {
            return String(format: "%.2f", value)
        }
    }
    
    private func formatCompactQuantity(_ value: Double) -> String {
        if value < 0.01 {
            return String(format: "%.4f", value)
        } else if value < 1 {
            return String(format: "%.2f", value)
        } else {
            return String(format: "%.1f", value)
        }
    }
    
    private func formatShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
    
    private func parseBaseAsset(_ symbol: String) -> String {
        let upper = symbol.uppercased()
        let quotes = ["USDT", "USD", "BUSD", "USDC", "FDUSD"]
        for q in quotes where upper.hasSuffix(q) {
            return String(upper.dropLast(q.count))
        }
        return upper
    }
    
    /// Asset color — delegates to PortfolioViewModel's comprehensive curated palette
    /// so all screens share the exact same colors (BTC=blue, ETH=teal, SOL=orange, etc.)
    private func assetColor(_ asset: String) -> Color {
        portfolioVM.color(for: asset)
    }
    
    private func quickAmountsForAsset(_ asset: String) -> [Double] {
        switch asset.uppercased() {
        case "USDT", "USD", "USDC", "BUSD":
            return [1000, 5000, 10000, 50000]
        case "BTC":
            return [0.01, 0.1, 0.5, 1.0]
        case "ETH":
            return [0.1, 0.5, 1.0, 5.0]
        case "BNB":
            return [1, 5, 10, 50]
        case "SOL":
            return [1, 10, 50, 100]
        default:
            return [10, 100, 500, 1000]
        }
    }
    
    private func formatQuickAmount(_ amount: Double, asset: String) -> String {
        if amount >= 1000 {
            return "\(Int(amount / 1000))K \(asset)"
        } else if amount >= 1 {
            return "\(Int(amount)) \(asset)"
        } else {
            return "\(amount) \(asset)"
        }
    }
}

// MARK: - Supporting Components

private struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 6) {
            // Premium gradient icon treatment
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.18), color.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                
                Circle()
                    .stroke(color.opacity(0.25), lineWidth: 1)
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [color, color.opacity(0.75)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(DS.Adaptive.textPrimary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(DS.Adaptive.textSecondary)
                .textCase(.uppercase)
                .tracking(0.3)
            
            Text(subtitle)
                .font(.system(size: 8))
                .foregroundColor(DS.Adaptive.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DS.Adaptive.background.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(DS.Adaptive.stroke.opacity(0.5), lineWidth: 0.5)
                )
        )
    }
}

private struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    // Premium gradient background circle
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.25), color.opacity(0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    
                    // Subtle ring stroke
                    Circle()
                        .stroke(color.opacity(0.3), lineWidth: 1)
                        .frame(width: 44, height: 44)
                    
                    // Icon with gradient
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [color, color.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(DS.Adaptive.cardBackground)
                    
                    // Top glass highlight
                    LinearGradient(
                        colors: [Color.white.opacity(0.06), Color.clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [DS.Adaptive.stroke, DS.Adaptive.stroke.opacity(0.5)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            )
            // Subtle color glow removed for memory
            .scaleEffect(isPressed ? 0.97 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    var color: Color = .blue
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.weight(.bold))
                .lineLimit(1)
                .foregroundStyle(isSelected ? Color.white : DS.Adaptive.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .frame(minHeight: 32)
                .background(
                    Capsule()
                        .fill(isSelected ? color.opacity(isDark ? 0.88 : 0.83) : DS.Adaptive.chipBackground)
                )
                .overlay(
                    Capsule().inset(by: 0.5)
                        .stroke(isSelected ? color.opacity(isDark ? 0.55 : 0.45) : DS.Adaptive.stroke, lineWidth: 1)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
    }
}

private struct AssetChip: View {
    let asset: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(asset)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : DS.Adaptive.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? color.opacity(0.8) : DS.Adaptive.cardBackground)
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : DS.Adaptive.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

private struct EnhancedBalanceRow: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let asset: String
    let amount: Double
    let price: Double?
    let totalPortfolioValue: Double
    var color: Color = .gray  // Unified color from PortfolioViewModel palette
    
    private var isDark: Bool { colorScheme == .dark }
    
    private var usdValue: Double {
        amount * (price ?? 1.0)
    }
    
    private var percentage: Double {
        totalPortfolioValue > 0 ? (usdValue / totalPortfolioValue) * 100 : 0
    }
    
    /// Unified asset color — passed from the parent using PortfolioViewModel's palette
    private var assetColor: Color { color }
    
    var body: some View {
        HStack(spacing: 12) {
            // Asset icon with premium gradient ring styling
            CoinImageView(
                symbol: asset,
                url: coinImageURL(for: asset),
                size: 42
            )
            .overlay(
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [assetColor.opacity(0.5), assetColor.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(asset)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                HStack(spacing: 4) {
                    Text(formatQuantity(amount))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.Adaptive.textSecondary)
                        .monospacedDigit()
                    
                    // Allocation pill with asset color
                    Text(String(format: "%.1f%%", percentage))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(assetColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(assetColor.opacity(isDark ? 0.15 : 0.12))
                        )
                        .overlay(
                            Capsule()
                                .stroke(assetColor.opacity(0.25), lineWidth: 0.5)
                        )
                }
            }
            
            Spacer()
            
            // Value display
            Text(formatCurrency(usdValue))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(DS.Adaptive.textPrimary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            assetColor.opacity(isDark ? 0.08 : 0.06),
                            DS.Adaptive.cardBackground.opacity(0.5)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        )
    }
    
    private func formatQuantity(_ value: Double) -> String {
        if value < 0.001 { return String(format: "%.6f", value) }
        else if value < 1 { return String(format: "%.4f", value) }
        else if value < 1000 { return String(format: "%.2f", value) }
        else { return String(format: "%.0f", value) }
    }
    
    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = CurrencyManager.currencyCode
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }
}

private struct EnhancedTradeRow: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let trade: PaperTrade
    let currentPrice: Double?
    
    private var isDark: Bool { colorScheme == .dark }
    
    private var sideColor: Color {
        trade.side == .buy ? Color(red: 0.2, green: 0.78, blue: 0.4) : Color(red: 0.95, green: 0.35, blue: 0.35)
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
    
    /// Calculate unrealized P&L if current price is available
    private var unrealizedPnL: (amount: Double, percent: Double)? {
        guard let current = currentPrice, trade.side == .buy else { return nil }
        let currentValue = trade.quantity * current
        let pnl = currentValue - trade.totalValue
        let pnlPercent = (pnl / trade.totalValue) * 100
        return (pnl, pnlPercent)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Coin logo with side indicator overlay
            ZStack(alignment: .bottomTrailing) {
                CoinImageView(
                    symbol: baseAsset,
                    url: coinImageURL(for: baseAsset),
                    size: 42
                )
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [sideColor.opacity(0.5), sideColor.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
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
                    .offset(x: 4, y: 4)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(baseAsset)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    // Side badge
                    Text(trade.side == .buy ? "BUY" : "SELL")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(sideColor)
                        )
                }
                
                Text(formatDate(trade.timestamp))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(formatCurrency(trade.totalValue))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .monospacedDigit()
                
                Text("\(formatQuantity(trade.quantity)) @ \(formatPrice(trade.price))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                
                // Show unrealized P&L for buy trades if current price available
                if let pnl = unrealizedPnL {
                    Text(String(format: "%@%.2f%%", pnl.percent >= 0 ? "+" : "", pnl.percent))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(pnl.amount >= 0 ? .green : .red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill((pnl.amount >= 0 ? Color.green : Color.red).opacity(isDark ? 0.15 : 0.10))
                        )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            sideColor.opacity(isDark ? 0.06 : 0.04),
                            DS.Adaptive.cardBackground.opacity(0.5)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        )
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }
    
    private func formatQuantity(_ value: Double) -> String {
        if value < 0.01 { return String(format: "%.4f", value) }
        else if value < 1 { return String(format: "%.3f", value) }
        else { return String(format: "%.2f", value) }
    }
    
    private func formatPrice(_ value: Double) -> String {
        // Always show 2 decimal places for proper financial display
        // Also use NumberFormatter for proper comma grouping (e.g., "$69,248.00" not "$69248")
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = CurrencyManager.currencyCode
        if value < 1 {
            formatter.maximumFractionDigits = 4
            formatter.minimumFractionDigits = 4
        } else {
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 2
        }
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }
    
    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = CurrencyManager.currencyCode
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }
}

// MARK: - Preview

// MARK: - Reset Info Sheet (Extracted to reduce type-checker load)

struct PaperTradingResetInfoSheet: View {
    @Binding var isPresented: Bool
    
    private var isPremium: Bool {
        SubscriptionManager.shared.effectiveTier == .premium
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    howResetsWorkSection
                    Divider().opacity(0.3)
                    leaderboardImpactSection
                    Divider().opacity(0.3)
                    whatGetsResetSection
                    if !isPremium { premiumUpsellSection }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(DS.Adaptive.background)
            .navigationTitle("Reset & Leaderboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { isPresented = false }
                        .font(.system(size: 14, weight: .semibold))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    // MARK: - Sections
    
    private var howResetsWorkSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("How Resets Work", systemImage: "arrow.counterclockwise.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Text("Paper trading is a learning tool — you shouldn't be stuck forever if things go wrong. Both Pro and Premium subscribers can reset their account to start fresh.")
                .font(.system(size: 12))
                .foregroundColor(DS.Adaptive.textSecondary)
                .lineSpacing(2)
            
            bulletRow(icon: "person.fill", color: .blue,
                title: "Pro", detail: "1 reset every 90 days (quarterly)")
            bulletRow(icon: "crown.fill", color: BrandColors.goldBase,
                title: "Premium", detail: "1 reset every 30 days (monthly)")
        }
    }
    
    private var leaderboardImpactSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Leaderboard Impact", systemImage: "trophy")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Text("To keep the leaderboard fair, every reset carries competitive consequences. This prevents users from resetting repeatedly to chase a lucky streak.")
                .font(.system(size: 12))
                .foregroundColor(DS.Adaptive.textSecondary)
                .lineSpacing(2)
            
            bulletRow(icon: "clock.fill", color: .orange,
                title: "14-Day Cooldown",
                detail: "Your leaderboard scores carry a penalty for 14 days after a reset")
            bulletRow(icon: "chart.line.downtrend.xyaxis", color: .red,
                title: "20% Score Penalty",
                detail: "Your leaderboard score is reduced by 20% for each reset in your rolling window")
            bulletRow(icon: "timer", color: .purple,
                title: "Time-Weight Resets",
                detail: "Longer track records earn a bonus (up to 1.5x). Resetting drops this back to 0.7x — it takes months to rebuild")
        }
    }
    
    private var whatGetsResetSection: some View {
        let balanceK = Int(PaperTradingManager.defaultStartingBalance / 1000)
        return VStack(alignment: .leading, spacing: 10) {
            Label("What Gets Reset", systemImage: "trash")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            bulletRow(icon: "dollarsign.circle", color: .green,
                title: "Balances",
                detail: "All holdings cleared, balance returns to $\(balanceK)K starting amount")
            bulletRow(icon: "list.bullet.rectangle", color: .blue,
                title: "Trade History",
                detail: "All paper trades and pending orders are permanently deleted")
            bulletRow(icon: "chart.bar.fill", color: .orange,
                title: "Leaderboard Progress",
                detail: "PnL, win rate, and all performance stats start over")
        }
    }
    
    private var premiumUpsellSection: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.3)
            HStack(spacing: 8) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 12))
                    .foregroundColor(BrandColors.goldBase)
                Text("Premium members can reset monthly instead of quarterly — upgrade anytime in Settings.")
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(BrandColors.goldBase.opacity(0.06))
            )
            .padding(.top, 8)
        }
    }
    
    // MARK: - Bullet Row
    
    private func bulletRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(color)
                .frame(width: 20, height: 20)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .lineSpacing(1)
            }
        }
    }
}

#if DEBUG
struct PaperTradingSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            PaperTradingSettingsView()
        }
        .preferredColorScheme(.dark)
    }
}
#endif
