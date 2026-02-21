//
//  WhaleActivityView.swift
//  CryptoSage
//
//  Main whale activity feed view.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct WhaleActivityView: View {
    @StateObject private var viewModel = WhaleTrackingViewModel()
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showFilters: Bool = false
    @State private var showWatchedWallets: Bool = false
    @State private var showSettings: Bool = false
    @State private var showAllSignals: Bool = false
    @State private var pulseAnimation: Bool = false
    @State private var showUpgradeSheet: Bool = false
    @State private var relativeNow: Date = Date()
    private let relativeTimeRefreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    // MARK: - Anchored Dropdown State
    @State private var activeDropdownFieldID: String? = nil
    
    /// Optional dismiss callback when presented as sheet/fullScreenCover
    var onDismiss: (() -> Void)?
    
    /// Whether to show the close button (true when presented modally)
    var showCloseButton: Bool = false
    
    /// Number of transactions to show for free users
    private let freePreviewCount: Int = 5
    
    /// Check if user has whale tracking access
    private var hasWhaleAccess: Bool {
        subscriptionManager.hasAccess(to: .whaleTracking)
    }
    
    /// Check if user has smart money access
    private var hasSmartMoneyAccess: Bool {
        subscriptionManager.hasAccess(to: .smartMoneyAlerts)
    }
    
    private var isShowingPrimaryEmptyState: Bool {
        !viewModel.isLoading && viewModel.filteredTransactions.isEmpty
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Unified header with SubpageHeaderBar
            SubpageHeaderBar(
                title: "Whale Tracker",
                showCloseButton: showCloseButton,
                onDismiss: { onDismiss?() ?? dismiss() }
            ) {
                // Right-side buttons: Watched wallets and settings
                HStack(spacing: 16) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showWatchedWallets = true
                    } label: {
                        Image(systemName: "eye")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.blue)
                    }
                    
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(DS.Adaptive.textSecondary)
                    }
                }
            }
            
            ScrollView {
                VStack(spacing: 10) {
                    // Hero Summary Header
                    heroSummaryHeader
                    
                    // Exchange Flow Visualization
                    if let stats = viewModel.statistics, stats.totalVolumeUSD > 0 {
                        exchangeFlowCard(stats)
                    }
                    
                    // Statistics Card
                    if let stats = viewModel.statistics, stats.totalTransactionsLast24h > 0 {
                        statisticsCard(stats)
                    }
                    
                    // Volume History Chart
                    if !viewModel.volumeHistory.isEmpty && viewModel.volumeHistory.contains(where: { $0.volumeUSD > 0 }) {
                        volumeHistoryChart
                    } else if let stats = viewModel.statistics, stats.totalTransactionsLast24h == 0, !isShowingPrimaryEmptyState {
                        noActivity24hCard
                    }
                    
                    // Smart Money Signals (gated for Pro users)
                    if !viewModel.smartMoneySignals.isEmpty {
                        if hasSmartMoneyAccess {
                            smartMoneySection
                        } else {
                            // Soft paywall for Smart Money section
                            SoftPaywallSection(feature: .smartMoneyAlerts, title: "Smart Money Signals") {
                                smartMoneySection
                            }
                        }
                    }
                    
                    // Filter bar
                    filterBar
                    
                    // Data source indicator
                    if !isShowingPrimaryEmptyState {
                        dataSourceIndicator
                    }
                    
                    // Transactions list (with soft paywall for free users)
                    if viewModel.isLoading && viewModel.filteredTransactions.isEmpty {
                        loadingView
                    } else if viewModel.filteredTransactions.isEmpty {
                        dataSourceIndicator
                        emptyStateView
                    } else {
                        if hasWhaleAccess {
                            // Full access - show all transactions
                            transactionsList
                        } else {
                            // Limited access - show soft paywall
                            paywallTransactionsList
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { _ in
                        if activeDropdownFieldID != nil {
                            activeDropdownFieldID = nil
                        }
                    }
            )
            .refreshable {
                await viewModel.refresh()
            }
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        // NAVIGATION: Enable native iOS pop gesture + custom edge swipe
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { onDismiss?() ?? dismiss() })
        .sheet(isPresented: $showFilters) {
            WhaleFiltersSheet(viewModel: viewModel)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showWatchedWallets) {
            WatchedWalletsView(viewModel: viewModel)
        }
        .sheet(isPresented: $showSettings) {
            WhaleAlertSettingsView()
        }
        .sheet(isPresented: $showAllSignals) {
            AllSmartMoneySignalsView(
                signals: viewModel.smartMoneySignals,
                index: viewModel.smartMoneyIndex
            )
        }
        .onAppear {
            viewModel.startMonitoring()
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
        }
        .onReceive(relativeTimeRefreshTimer) { tick in
            relativeNow = tick
        }
        .onDisappear {
            activeDropdownFieldID = nil
            viewModel.stopMonitoring()
        }
    }
    
    // MARK: - Hero Summary Header
    
    private var heroSummaryHeader: some View {
        VStack(spacing: 12) {
            // Main stats row
            HStack(alignment: .center, spacing: 16) {
                // Animated whale icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.3), Color.cyan.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                        .scaleEffect(pulseAnimation ? 1.05 : 1.0)
                    
                    Image(systemName: "water.waves")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    if let stats = viewModel.statistics {
                        if stats.totalTransactionsLast24h == 0 || stats.totalVolumeUSD <= 0 {
                            Text("Monitoring Whale Activity")
                                .font(.system(size: 23, weight: .bold))
                                .foregroundColor(DS.Adaptive.textPrimary)
                            
                            Text("Watching for whale-sized transfers across supported chains")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(DS.Adaptive.textTertiary)
                        } else {
                            // Volume
                            Text(formatHeroVolume(stats.totalVolumeUSD))
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(DS.Adaptive.textPrimary)
                            
                            // Subtitle
                            HStack(spacing: 8) {
                                Text("\(stats.totalTransactionsLast24h) transactions")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(DS.Adaptive.textSecondary)
                                
                                Text("•")
                                    .foregroundColor(DS.Adaptive.textTertiary)
                                
                                Text("24h")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(DS.Adaptive.textTertiary)
                                
                                // Sentiment indicator
                                if stats.exchangeInflowUSD + stats.exchangeOutflowUSD > 0 {
                                    HStack(spacing: 3) {
                                        Image(systemName: stats.netExchangeFlow < 0 ? "arrow.up.right" : "arrow.down.right")
                                            .font(.system(size: 10, weight: .bold))
                                        Text(stats.netExchangeFlow < 0 ? "Bullish" : "Bearish")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .foregroundColor(stats.netExchangeFlow < 0 ? .green : .red)
                                }
                            }
                        }
                    } else {
                        Text("Loading...")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        Text("Fetching whale activity")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                }
                
                Spacer()
            }
        }
        .padding(.vertical, 8)
    }
    
    private func formatHeroVolume(_ value: Double) -> String {
        if value >= 1_000_000_000 {
            return String(format: "$%.2fB", value / 1_000_000_000)
        } else if value >= 1_000_000 {
            return String(format: "$%.2fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "$%.1fK", value / 1_000)
        }
        return String(format: "$%.0f", value)
    }
    
    private var noActivity24hCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(DS.Adaptive.textTertiary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("No 24h volume to chart")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textSecondary)
                Text("Chart appears automatically when activity is detected")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Adaptive.chipBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
    }
    
    // MARK: - Exchange Flow Card
    
    private func exchangeFlowCard(_ stats: WhaleStatistics) -> some View {
        let totalFlow = stats.exchangeInflowUSD + stats.exchangeOutflowUSD
        let hasExchangeFlow = totalFlow > 0
        let inflowRatio = hasExchangeFlow ? stats.exchangeInflowUSD / totalFlow : 0.5
        let outflowRatio = hasExchangeFlow ? stats.exchangeOutflowUSD / totalFlow : 0.5
        let isBullish = stats.netExchangeFlow < 0
        
        return VStack(spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    // Animated icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.green.opacity(0.2), Color.red.opacity(0.2)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 32, height: 32)
                        
                        Image(systemName: hasExchangeFlow ? "arrow.left.arrow.right.circle.fill" : "chart.bar.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: hasExchangeFlow ? [.green, .red] : [.blue, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(hasExchangeFlow ? "Exchange Flow" : "Transfer Volume")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        if !hasExchangeFlow {
                            Text("No exchange flow detected")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(DS.Adaptive.textTertiary)
                        }
                    }
                }
                
                Spacer()
                
                // Sentiment badge
                if hasExchangeFlow {
                    HStack(spacing: 4) {
                        Image(systemName: isBullish ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                        Text(isBullish ? "Bullish" : "Bearish")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(isBullish ? .green : .red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill((isBullish ? Color.green : Color.red).opacity(0.15))
                    )
                } else {
                    // Volume indicator when no exchange flow
                    HStack(spacing: 4) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 10, weight: .bold))
                        Text("Active")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.blue.opacity(0.15))
                    )
                }
            }
            
            if hasExchangeFlow {
                // Flow visualization
                VStack(spacing: 12) {
                    // Main flow bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: 6)
                                .fill(DS.Adaptive.chipBackground)
                            
                            // Flow bars
                            HStack(spacing: 3) {
                                // Outflow (green - bullish)
                                if outflowRatio > 0.01 {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(
                                            LinearGradient(
                                                colors: [.green.opacity(0.8), .green],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: (geo.size.width - 3) * outflowRatio)
                                        .overlay(
                                            Text(formatLargeNumber(stats.exchangeOutflowUSD))
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundColor(.white)
                                                .opacity(outflowRatio > 0.2 ? 1 : 0)
                                        )
                                }
                                
                                // Inflow (red - bearish)
                                if inflowRatio > 0.01 {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(
                                            LinearGradient(
                                                colors: [.red, .red.opacity(0.8)],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: (geo.size.width - 3) * inflowRatio)
                                        .overlay(
                                            Text(formatLargeNumber(stats.exchangeInflowUSD))
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundColor(.white)
                                                .opacity(inflowRatio > 0.2 ? 1 : 0)
                                        )
                                }
                            }
                            .padding(3)
                        }
                    }
                    .frame(height: 28)
                    
                    // Labels
                    HStack {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Exchange Outflow")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(DS.Adaptive.textTertiary)
                                Text(MarketFormat.largeCurrency(stats.exchangeOutflowUSD, useCurrentCurrency: true))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.green)
                            }
                        }
                        
                        Spacer()
                        
                        // Net flow indicator
                        VStack(spacing: 2) {
                            Text("Net")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(DS.Adaptive.textTertiary)
                            Text(MarketFormat.largeCurrency(abs(stats.netExchangeFlow), useCurrentCurrency: true))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(isBullish ? .green : .red)
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 6) {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("Exchange Inflow")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(DS.Adaptive.textTertiary)
                                Text(MarketFormat.largeCurrency(stats.exchangeInflowUSD, useCurrentCurrency: true))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.red)
                            }
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                        }
                    }
                }
                
                // Explanation
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                    Text(isBullish 
                         ? "More crypto leaving exchanges → Less selling pressure"
                         : "More crypto entering exchanges → Potential selling pressure")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(DS.Adaptive.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // Volume-based visualization when no exchange flow
                VStack(spacing: 12) {
                    // Total volume bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(DS.Adaptive.chipBackground)
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: [.blue.opacity(0.7), .purple.opacity(0.7)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width - 6)
                                .padding(3)
                                .overlay(
                                    Text(formatLargeNumber(stats.totalVolumeUSD))
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                )
                        }
                    }
                    .frame(height: 28)
                    
                    // Volume stats
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Total Volume")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(DS.Adaptive.textTertiary)
                            Text(MarketFormat.largeCurrency(stats.totalVolumeUSD, useCurrentCurrency: true))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.blue)
                        }
                        
                        Spacer()
                        
                        VStack(spacing: 1) {
                            Text("Transfers")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(DS.Adaptive.textTertiary)
                            Text("\(stats.totalTransactionsLast24h)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.purple)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("Avg Size")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(DS.Adaptive.textTertiary)
                            Text(MarketFormat.largeCurrency(stats.avgTransactionSize, useCurrentCurrency: true))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.cyan)
                        }
                    }
                }
                
                // Explanation for volume mode
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                    Text("Wallet-to-wallet transfers detected. No direct exchange activity.")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(DS.Adaptive.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: hasExchangeFlow 
                            ? [(isBullish ? Color.green : Color.red).opacity(0.3), DS.Adaptive.stroke]
                            : [Color.blue.opacity(0.3), Color.purple.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
    
    private func formatLargeNumber(_ value: Double) -> String {
        if value >= 1_000_000_000 {
            return String(format: "$%.1fB", value / 1_000_000_000)
        } else if value >= 1_000_000 {
            return String(format: "$%.1fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "$%.0fK", value / 1_000)
        }
        return String(format: "$%.0f", value)
    }
    
    // MARK: - Statistics Card
    
    private func statisticsCard(_ stats: WhaleStatistics) -> some View {
        HStack(spacing: 0) {
            statItem(
                title: "Volume",
                value: MarketFormat.largeCurrency(stats.totalVolumeUSD, useCurrentCurrency: true),
                icon: "chart.bar.fill",
                color: .blue
            )
            
            Divider()
                .frame(height: 36)
            
            statItem(
                title: "Avg Size",
                value: MarketFormat.largeCurrency(stats.avgTransactionSize, useCurrentCurrency: true),
                icon: "arrow.left.arrow.right",
                color: .purple
            )
            
            Divider()
                .frame(height: 36)
            
            if let largest = stats.largestTransaction {
                statItem(
                    title: "Largest",
                    value: MarketFormat.largeCurrency(largest.amountUSD, useCurrentCurrency: true),
                    icon: "star.fill",
                    color: BrandColors.goldBase
                )
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
    }
    
    private func statItem(title: String, value: String, icon: String, color: Color = DS.Adaptive.textPrimary) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
            
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(DS.Adaptive.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(DS.Adaptive.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Volume History Chart
    
    /// Computed property to check if data is sparse (few active hours)
    private var activeHoursCount: Int {
        viewModel.volumeHistory.filter { $0.volumeUSD > 0 }.count
    }
    
    private var volumeHistoryChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("24h Volume History")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                
                Spacer()
                
                // Volume trend indicator
                if let trend = volumeTrend {
                    HStack(spacing: 3) {
                        Image(systemName: trend.isPositive ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                        Text(String(format: "%.1f%%", abs(trend.percentage)))
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(trend.isPositive ? .green : .red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill((trend.isPositive ? Color.green : Color.red).opacity(0.15))
                    )
                }
            }
            
            // Sparkline Chart - shows all 24 hours with minimal bars for inactive hours
            WhaleVolumeSparkline(dataPoints: viewModel.volumeHistory)
                .frame(height: 60)
            
            // Hour axis labels (every 6 hours)
            HStack {
                Text("24h ago")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
                Spacer()
                Text("12h")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
                Spacer()
                Text("Now")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .padding(.horizontal, 4)
            
            // Legend
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 8, height: 8)
                    Text("Volume")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.green.opacity(0.6))
                        .frame(width: 8, height: 4)
                    Text("Outflow")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.red.opacity(0.6))
                        .frame(width: 8, height: 4)
                    Text("Inflow")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                
                Spacer()
            }
            
            // Info note about whale transaction rarity
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                if activeHoursCount == 0 {
                    Text("No whale transactions ($100K+) detected in the last 24 hours.")
                        .font(.system(size: 10, weight: .regular))
                } else if activeHoursCount <= 3 {
                    Text("Whale transactions ($100K+) are rare events. Gray bars = no large transfers that hour.")
                        .font(.system(size: 10, weight: .regular))
                } else {
                    Text("Chart shows hourly whale volume. Tap bars for details.")
                        .font(.system(size: 10, weight: .regular))
                }
            }
            .foregroundColor(DS.Adaptive.textTertiary)
            .padding(.top, 4)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
    }
    
    private var volumeTrend: (percentage: Double, isPositive: Bool)? {
        let history = viewModel.volumeHistory
        guard history.count >= 6 else { return nil }
        
        // Compare recent 6 hours vs previous 6 hours
        let recentVolume = history.suffix(6).reduce(0) { $0 + $1.volumeUSD }
        let previousVolume = history.dropLast(6).suffix(6).reduce(0) { $0 + $1.volumeUSD }
        
        guard previousVolume > 0 else { return nil }
        
        let change = ((recentVolume - previousVolume) / previousVolume) * 100
        return (percentage: change, isPositive: change >= 0)
    }
    
    // MARK: - Smart Money Section
    
    private var smartMoneySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with Smart Money Index
            HStack {
                HStack(spacing: 8) {
                    // Smart Money icon (institutional/money flow) with animated gradient ring
                    ZStack {
                        // Outer glow
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [Color.purple.opacity(0.4), Color.blue.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                            .frame(width: 32, height: 32)
                        
                        // Inner fill
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.purple.opacity(0.25), Color.blue.opacity(0.15)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 28, height: 28)
                        
                        Image(systemName: "dollarsign.arrow.circlepath")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.purple, .blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    Text("Smart Money")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                
                Spacer()
                
                // Smart Money Index Badge
                if let index = viewModel.smartMoneyIndex {
                    SmartMoneyIndexBadge(index: index)
                }
            }
            
            // Smart Money Index Gauge (if available)
            if let index = viewModel.smartMoneyIndex {
                SmartMoneyGauge(index: index)
            }
            
            // Recent signals preview (max 3)
            VStack(spacing: 8) {
                ForEach(Array(viewModel.smartMoneySignals.prefix(3).enumerated()), id: \.element.id) { idx, signal in
                    SmartMoneySignalRow(signal: signal)
                    
                    if idx < min(2, viewModel.smartMoneySignals.count - 1) {
                        Divider()
                            .background(DS.Adaptive.divider.opacity(0.5))
                    }
                }
            }
            
            // Enhanced View all signals button
            if viewModel.smartMoneySignals.count > 3 {
                Button {
                    let impactLight = UIImpactFeedbackGenerator(style: .light)
                    impactLight.impactOccurred()
                    showAllSignals = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.stack")
                            .font(.system(size: 12, weight: .semibold))
                        Text("View all \(viewModel.smartMoneySignals.count) signals")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 16))
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.15), Color.cyan.opacity(0.1)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.3), Color.cyan.opacity(0.2)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.05), Color.blue.opacity(0.03)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.purple.opacity(0.3), Color.blue.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
    
    // MARK: - Data Source Indicator
    
    // MARK: - Data Sources Summary
    
    /// Active data sources being used
    private var activeDataSources: [WhaleDataSource] {
        let txs = viewModel.filteredTransactions
        return Array(Set(txs.map { $0.dataSource })).sorted { $0.rawValue < $1.rawValue }
    }
    
    private var freshnessLabel: String {
        let service = WhaleTrackingService.shared
        if service.isDataStale { return "Stale cache" }
        if service.isUsingCachedData { return "Cached" }
        return "Live"
    }
    
    private var freshnessColor: Color {
        let service = WhaleTrackingService.shared
        if service.isDataStale { return .orange }
        if service.isUsingCachedData { return .yellow }
        return .green
    }

    private var providerSummaryText: String {
        let providers = WhaleTrackingService.shared.activeDataProviders
        guard !providers.isEmpty else { return "No provider details" }
        let preview = providers.prefix(2)
        if providers.count > 2 {
            return "\(preview.joined(separator: ", ")) +\(providers.count - 2)"
        }
        return preview.joined(separator: ", ")
    }
    
    private var dataSourceIndicator: some View {
        VStack(spacing: 6) {
            // Primary status indicator
            Group {
                switch WhaleTrackingService.shared.dataSourceStatus {
                case .success(let source):
                    if isShowingPrimaryEmptyState {
                        VStack(spacing: 3) {
                            HStack(spacing: 6) {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 10))
                                Text(source)
                                    .font(.system(size: 10, weight: .semibold))
                                Text("•")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(DS.Adaptive.textTertiary)
                                Text(freshnessLabel)
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundColor(freshnessColor)
                            
                            Text(statusMetadataText)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(DS.Adaptive.textTertiary)
                        }
                    } else {
                        VStack(spacing: 5) {
                            HStack(spacing: 6) {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 10))
                                Text(source)
                                    .font(.system(size: 10, weight: .medium))
                                Text("•")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(DS.Adaptive.textTertiary)
                                Text(freshnessLabel)
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundColor(freshnessColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(freshnessColor.opacity(0.15))
                            )
                            
                            if let updatedAt = WhaleTrackingService.shared.lastDataUpdatedAt {
                                (
                                    Text("Updated \(updatedAt, style: .relative) ago")
                                    + Text(" • \(statusMetadataText)")
                                )
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(DS.Adaptive.textTertiary)
                            } else {
                                Text(statusMetadataText)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(DS.Adaptive.textTertiary)
                            }
                        }
                    }
                case .usingFallback:
                    // No data available
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10))
                        Text("Connecting to blockchain APIs...")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.orange.opacity(0.15))
                    )
                case .error(let message):
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 10))
                        Text(message)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.red.opacity(0.15))
                    )
                case .fetching:
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Scanning blockchain...")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.blue.opacity(0.15))
                )
            case .idle:
                EmptyView()
                }
            }
        }
    }

    private var statusMetadataText: String {
        let sourceCount = activeDataSources.count
        let sourceText = sourceCount == 1 ? "1 source" : "\(sourceCount) sources"
        return "\(sourceText) • \(providerSummaryText)"
    }
    
    // MARK: - Filter Bar
    
    private var filterBar: some View {
        VStack(spacing: 7) {
            // Primary filter row
            HStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        CSAnchoredSelectionField(
                            fieldID: "whale_chain_filter",
                            defaultTitle: "All Chains",
                            defaultIconSystemName: viewModel.selectedBlockchain?.icon ?? "link.circle.fill",
                            preferredMenuWidth: 220,
                            menuMaxHeight: 420,
                            options: chainFilterOptions,
                            accentColor: viewModel.selectedBlockchain?.color ?? .blue,
                            selectedID: chainSelectionIDBinding,
                            activeFieldID: $activeDropdownFieldID
                        )
                        
                        CSAnchoredSelectionField(
                            fieldID: "whale_token_filter",
                            defaultTitle: "All Tokens",
                            defaultIconSystemName: "dollarsign.circle.fill",
                            preferredMenuWidth: 200,
                            menuMaxHeight: 420,
                            options: tokenFilterOptions,
                            accentColor: .blue,
                            selectedID: tokenSelectionIDBinding,
                            activeFieldID: $activeDropdownFieldID
                        )
                        
                        CSAnchoredSelectionField(
                            fieldID: "whale_sort_filter",
                            defaultTitle: "Newest",
                            defaultIconSystemName: "arrow.up.arrow.down",
                            preferredMenuWidth: 200,
                            menuMaxHeight: 280,
                            options: sortFilterOptions,
                            accentColor: DS.Colors.gold,
                            selectedID: sortSelectionIDBinding,
                            activeFieldID: $activeDropdownFieldID
                        )
                    }
                    .padding(.trailing, 2)
                }
                
                // More filters button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    activeDropdownFieldID = nil
                    showFilters = true
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DS.Adaptive.textSecondary)
                            .frame(width: 34, height: 34)
                            .background(
                                Capsule()
                                    .fill(DS.Adaptive.chipBackground)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(DS.Adaptive.stroke.opacity(0.7), lineWidth: 0.8)
                            )
                        
                        // Active filter indicator
                        if viewModel.hasActiveFilters {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 8, height: 8)
                                .offset(x: 3, y: -3)
                        }
                    }
                }
            }
            
            // Active filters row (if any filters are active)
            if viewModel.hasActiveFilters {
                HStack(spacing: 6) {
                    Text("Filters:")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            // Active filter chips
                            if let blockchain = viewModel.selectedBlockchain {
                                filterChip(text: blockchain.symbol, color: blockchain.color) {
                                    viewModel.selectedBlockchain = nil
                                }
                            }
                            
                            if let token = viewModel.selectedToken {
                                filterChip(text: token, color: .blue) {
                                    viewModel.selectedToken = nil
                                }
                            }
                            
                            if abs(viewModel.minAmount - viewModel.baselineMinAmount) > 0.5 {
                                filterChip(text: ">\(formatShortAmount(viewModel.minAmount))", color: .purple) {
                                    viewModel.minAmount = viewModel.baselineMinAmount
                                }
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Clear all button
                    Button {
                        viewModel.clearFilters()
                    } label: {
                        Text("Clear")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.red)
                    }
                }
            }
        }
    }
    
    private let chainAllID = "__all_chains__"
    private let tokenAllID = "__all_tokens__"
    
    private var chainSelectionIDBinding: Binding<String?> {
        Binding(
            get: { viewModel.selectedBlockchain?.rawValue ?? chainAllID },
            set: { selected in
                guard let selected else {
                    viewModel.selectedBlockchain = nil
                    return
                }
                if selected == chainAllID {
                    viewModel.selectedBlockchain = nil
                } else {
                    viewModel.selectedBlockchain = WhaleBlockchain.allCases.first(where: { $0.rawValue == selected })
                }
            }
        )
    }
    
    private var tokenSelectionIDBinding: Binding<String?> {
        Binding(
            get: { viewModel.selectedToken ?? tokenAllID },
            set: { selected in
                guard let selected else {
                    viewModel.selectedToken = nil
                    return
                }
                viewModel.selectedToken = selected == tokenAllID ? nil : selected
            }
        )
    }
    
    private var sortSelectionIDBinding: Binding<String?> {
        Binding(
            get: { viewModel.sortOrder.rawValue },
            set: { selected in
                guard let selected else { return }
                if let order = WhaleTrackingViewModel.SortOrder.allCases.first(where: { $0.rawValue == selected }) {
                    viewModel.sortOrder = order
                }
            }
        )
    }
    
    private var chainFilterOptions: [CSAnchoredSelectionOption] {
        var options: [CSAnchoredSelectionOption] = [
            CSAnchoredSelectionOption(
                id: chainAllID,
                title: "All Chains",
                iconSystemName: "link.circle.fill"
            )
        ]
        
        options.append(contentsOf: WhaleBlockchain.allCases.map {
            CSAnchoredSelectionOption(id: $0.rawValue, title: $0.rawValue, iconSystemName: $0.icon)
        })
        return options
    }
    
    private var tokenFilterOptions: [CSAnchoredSelectionOption] {
        var options: [CSAnchoredSelectionOption] = [
            CSAnchoredSelectionOption(
                id: tokenAllID,
                title: "All Tokens",
                iconSystemName: "dollarsign.circle"
            )
        ]
        
        let available = Set(viewModel.availableTokens)
        let common = WhaleTrackingViewModel.commonTokens.filter { available.contains($0) }
        options.append(contentsOf: common.map { CSAnchoredSelectionOption(id: $0, title: $0) })
        
        let remaining = viewModel.availableTokens.filter { !WhaleTrackingViewModel.commonTokens.contains($0) }
        options.append(contentsOf: remaining.map { CSAnchoredSelectionOption(id: $0, title: $0) })
        
        return options
    }
    
    private var sortFilterOptions: [CSAnchoredSelectionOption] {
        WhaleTrackingViewModel.SortOrder.allCases.map { order in
            let icon: String = {
                switch order {
                case .newest: return "clock.arrow.circlepath"
                case .oldest: return "clock"
                case .largest: return "arrow.up.right"
                case .smallest: return "arrow.down.right"
                }
            }()
            return CSAnchoredSelectionOption(id: order.rawValue, title: order.rawValue, iconSystemName: icon)
        }
    }
    
    private func filterChip(text: String, color: Color, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.system(size: 10, weight: .semibold))
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
            }
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(color.opacity(0.15))
        )
    }
    
    private func formatShortAmount(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "$%.0fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "$%.0fK", value / 1_000)
        }
        return String(format: "$%.0f", value)
    }
    
    // MARK: - Transactions List
    
    private var transactionsList: some View {
        VStack(spacing: 12) {
            // Live Feed Header
            liveFeedHeader
            
            LazyVStack(spacing: 12) {
                ForEach(Array(viewModel.filteredTransactions.enumerated()), id: \.element.id) { index, transaction in
                    EnhancedWhaleTransactionRow(
                        transaction: transaction,
                        pulseAnimation: pulseAnimation,
                        currentTime: relativeNow,
                        onWatchWallet: { address, label, blockchain in
                            viewModel.addWatchedWallet(address: address, label: label, blockchain: blockchain)
                        }
                    )
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        ))
                        .animation(.easeOut(duration: 0.3).delay(Double(index) * 0.05), value: viewModel.filteredTransactions.count)
                }
            }
        }
    }
    
    // MARK: - Paywall Transactions List (for free users)
    
    private var paywallTransactionsList: some View {
        VStack(spacing: 12) {
            // Live Feed Header
            liveFeedHeader
            
            // Show preview transactions (first N items clear)
            LazyVStack(spacing: 12) {
                ForEach(Array(viewModel.filteredTransactions.prefix(freePreviewCount).enumerated()), id: \.element.id) { index, transaction in
                    EnhancedWhaleTransactionRow(
                        transaction: transaction,
                        pulseAnimation: pulseAnimation,
                        currentTime: relativeNow,
                        onWatchWallet: { address, label, blockchain in
                            viewModel.addWatchedWallet(address: address, label: label, blockchain: blockchain)
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .animation(.easeOut(duration: 0.3).delay(Double(index) * 0.05), value: viewModel.filteredTransactions.count)
                }
            }
            
            // Soft paywall for remaining transactions
            if viewModel.filteredTransactions.count > freePreviewCount {
                paywallOverlay
            }
        }
        .trackPaywallView(for: .whaleTracking)
    }
    
    // MARK: - Paywall Overlay
    
    private var paywallOverlay: some View {
        ZStack {
            // Blurred preview of next transactions
            VStack(spacing: 12) {
                ForEach(Array(viewModel.filteredTransactions.dropFirst(freePreviewCount).prefix(2).enumerated()), id: \.element.id) { index, transaction in
                    EnhancedWhaleTransactionRow(
                        transaction: transaction,
                        pulseAnimation: false,
                        currentTime: relativeNow,
                        onWatchWallet: { _, _, _ in }
                    )
                }
            }
            .allowsHitTesting(false)
            .mask(
                LinearGradient(
                    colors: [.white, .white.opacity(0.5), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            
            // Upgrade prompt
            VStack(spacing: 16) {
                // Lock icon with glow
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [BrandColors.goldBase.opacity(0.3), BrandColors.goldBase.opacity(0)],
                                center: .center,
                                startRadius: 10,
                                endRadius: 40
                            )
                        )
                        .frame(width: 80, height: 80)
                    
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [BrandColors.goldLight.opacity(0.3), BrandColors.goldDark.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                        .overlay(
                            Circle()
                                .stroke(BrandColors.goldBase.opacity(0.5), lineWidth: 1)
                        )
                    
                    ZStack(alignment: .bottomTrailing) {
                        Image(systemName: "water.waves")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [BrandColors.goldLight, BrandColors.goldBase],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                        Image(systemName: "lock.fill")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.9))
                            .padding(3)
                            .background(
                                Circle()
                                    .fill(BrandColors.goldBase)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                                    )
                            )
                            .offset(x: 2, y: 2)
                    }
                }
                
                VStack(spacing: 6) {
                    Text("\(viewModel.filteredTransactions.count - freePreviewCount) more transactions")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Text(StoreKitManager.shared.hasAnyTrialAvailable
                         ? "Start your free trial to track all whale movements"
                         : "Upgrade to Pro to track all whale movements")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                        .multilineTextAlignment(.center)
                }
                
                // Upgrade button
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    PaywallManager.shared.trackFeatureAttempt(.whaleTracking)
                    showUpgradeSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 14))
                        Text(StoreKitManager.shared.hasAnyTrialAvailable ? "Start Free Trial" : "Upgrade to Pro")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [BrandColors.goldLight, BrandColors.goldBase],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(20)
                }
            }
            .padding(.vertical, 24)
        }
        .unifiedPaywallSheet(feature: .whaleTracking, isPresented: $showUpgradeSheet)
    }
    
    // MARK: - Live Feed Header
    
    private var liveFeedHeader: some View {
        HStack(spacing: 8) {
            // Animated live dot
            ZStack {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulseAnimation ? 2.5 : 1.0)
                    .opacity(pulseAnimation ? 0 : 0.5)
            }
            
            Text("Live Whale Feed")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Text("•")
                .font(.system(size: 10))
                .foregroundColor(DS.Adaptive.textTertiary)
            
            Text("\(viewModel.filteredTransactions.count) transactions")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.Adaptive.textSecondary)
            
            Spacer()
            
            // Auto-refresh indicator
            if case .fetching = WhaleTrackingService.shared.dataSourceStatus {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            // Animated whale
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 80, height: 80)
                    .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                    .opacity(pulseAnimation ? 0.5 : 0.8)
                
                Image(systemName: "water.waves")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 8) {
                Text("Scanning the blockchain...")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.Adaptive.textPrimary)
                
                Text("Looking for whale movements")
                    .font(.system(size: 13))
                    .foregroundStyle(DS.Adaptive.textTertiary)
            }
            
            ProgressView()
                .scaleEffect(1.1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "water.waves")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue.opacity(0.5), .cyan.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(spacing: 8) {
                Text("No whale activity matching filters")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DS.Adaptive.textPrimary)
                
                if viewModel.hasActiveFilters {
                    Text("Your filters may be too restrictive")
                        .font(.system(size: 14))
                        .foregroundStyle(DS.Adaptive.textSecondary)
                } else {
                    Text("Large transactions ($100K+) are monitored in real-time")
                        .font(.system(size: 14))
                        .foregroundStyle(DS.Adaptive.textSecondary)
                }
            }
            
            // Helpful context
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.blue.opacity(0.8))
                Text("Whale transfers are less frequent. Keep filters broad to catch more activity.")
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.blue.opacity(0.08))
            )
            
            // Suggestions
            VStack(alignment: .leading, spacing: 12) {
                suggestionRow(icon: "slider.horizontal.3", text: "Lower the minimum amount threshold", action: { showFilters = true })
                suggestionRow(icon: "link.circle", text: "Select 'All Chains' for more results", action: { viewModel.selectedBlockchain = nil })
                suggestionRow(icon: "arrow.clockwise", text: "Pull down to refresh now", action: { Task { await viewModel.refresh() } })
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DS.Adaptive.chipBackground)
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
    
    private func suggestionRow(icon: String, text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.blue)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                    )
                
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DS.Adaptive.textSecondary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Whale Size Category

enum WhaleSize: String {
    case shrimp = "Shrimp"
    case fish = "Fish"
    case dolphin = "Dolphin"
    case whale = "Whale"
    case megaWhale = "Mega Whale"
    
    var icon: String {
        switch self {
        case .shrimp: return "hare.fill"
        case .fish: return "fish.fill"
        case .dolphin: return "seal.fill"
        case .whale: return "water.waves"
        case .megaWhale: return "crown.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .shrimp: return .gray
        case .fish: return .blue
        case .dolphin: return .cyan
        case .whale: return .purple
        case .megaWhale: return BrandColors.goldBase
        }
    }
    
    var backgroundOpacity: Double {
        switch self {
        case .shrimp: return 0.05
        case .fish: return 0.08
        case .dolphin: return 0.1
        case .whale: return 0.12
        case .megaWhale: return 0.15
        }
    }
    
    static func from(amountUSD: Double) -> WhaleSize {
        switch amountUSD {
        case 0..<500_000: return .shrimp
        case 500_000..<1_000_000: return .fish
        case 1_000_000..<5_000_000: return .dolphin
        case 5_000_000..<25_000_000: return .whale
        default: return .megaWhale
        }
    }
}

// MARK: - Enhanced Transaction Row

struct EnhancedWhaleTransactionRow: View {
    let transaction: WhaleTransaction
    let pulseAnimation: Bool
    let currentTime: Date
    var onWatchWallet: ((String, String, WhaleBlockchain) -> Void)? = nil
    
    @State private var showDetails: Bool = false
    @State private var isPressed: Bool = false
    @State private var showCopiedToast: Bool = false
    @State private var copiedText: String = ""
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    
    private var whaleSize: WhaleSize {
        WhaleSize.from(amountUSD: transaction.amountUSD)
    }
    
    private var isDark: Bool { colorScheme == .dark }
    
    private var freshPulseColor: Color {
        let baseOpacity: Double = transaction.blockchain == .bitcoin ? 0.22 : 0.28
        return transaction.blockchain.color.opacity(baseOpacity)
    }
    
    // Share text for the transaction
    private var shareText: String {
        let sentiment = transaction.sentiment.rawValue
        let type = transaction.transactionType.description
        return "🐋 Whale Alert!\n\n\(transaction.formattedUSD) (\(transaction.formattedAmount) \(transaction.symbol))\n\(type) • \(sentiment)\n\nFrom: \(transaction.shortFromAddress)\nTo: \(transaction.shortToAddress)\n\nTracked by CryptoSage"
    }
    
    var body: some View {
        Button {
            // Light haptic feedback
            let impactLight = UIImpactFeedbackGenerator(style: .light)
            impactLight.impactOccurred()
            showDetails = true
        } label: {
            HStack(spacing: 0) {
                // Sentiment color bar with gradient
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                transaction.sentiment.color,
                                transaction.sentiment.color.opacity(0.5)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 4)
                
                VStack(spacing: 10) {
                    // Main row content
                    HStack(spacing: 12) {
                        // Blockchain icon with whale size indicator
                        ZStack(alignment: .bottomTrailing) {
                            // Pulse for fresh transactions
                            if transaction.isFresh {
                                Circle()
                                    .fill(freshPulseColor)
                                    .frame(width: 48, height: 48)
                                    .scaleEffect(pulseAnimation ? 1.15 : 1.0)
                                    .opacity(pulseAnimation ? 0.42 : 0.62)
                            }
                            
                            // Main icon with blockchain coin logo
                            CoinImageView(symbol: transaction.blockchain.symbol, url: nil, size: 44)
                            
                            // Whale size badge
                            ZStack {
                                Circle()
                                    .fill(isDark ? Color.black : Color.white)
                                    .frame(width: 18, height: 18)
                                
                                Circle()
                                    .fill(whaleSize.color.opacity(0.2))
                                    .frame(width: 16, height: 16)
                                
                                Image(systemName: whaleSize.icon)
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(whaleSize.color)
                            }
                            .offset(x: 2, y: 2)
                        }
                        .frame(width: 46, height: 46)
                        .clipped()
                        
                        // Details section
                        VStack(alignment: .leading, spacing: 4) {
                            // Amount row with badges
                            HStack(spacing: 6) {
                                Text(transaction.formattedUSD)
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundStyle(DS.Adaptive.textPrimary)
                                
                                // LIVE badge for fresh transactions
                                if transaction.isFresh {
                                    HStack(spacing: 3) {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 5, height: 5)
                                        Text("NEW")
                                            .font(.system(size: 9, weight: .bold))
                                    }
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(Color.green.opacity(0.15))
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(Color.green.opacity(0.3), lineWidth: 0.5)
                                    )
                                }
                                
                                Text("(\(transaction.formattedAmount) \(transaction.symbol))")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(DS.Adaptive.textSecondary)
                            }
                            
                            // Transaction type with sentiment
                            HStack(spacing: 6) {
                                HStack(spacing: 3) {
                                    Image(systemName: transaction.transactionType.icon)
                                        .font(.system(size: 9))
                                    Text(transaction.transactionType.description)
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundStyle(transaction.sentiment.color)
                                
                                // Whale size label
                                Text("•")
                                    .font(.system(size: 8))
                                    .foregroundColor(DS.Adaptive.textTertiary)
                                
                                HStack(spacing: 2) {
                                    Image(systemName: whaleSize.icon)
                                        .font(.system(size: 8))
                                    Text(whaleSize.rawValue)
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundColor(whaleSize.color)
                            }
                        }
                        
                        Spacer()
                        
                        // Right side: time, sentiment, chevron
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(WhaleRelativeTimeFormatter.format(transaction.timestamp, now: currentTime))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(DS.Adaptive.textTertiary)
                            
                            // Sentiment indicator
                            HStack(spacing: 4) {
                                Image(systemName: transaction.sentiment.icon)
                                    .font(.system(size: 9, weight: .semibold))
                                Text(transaction.sentiment.rawValue)
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundColor(transaction.sentiment.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(transaction.sentiment.color.opacity(0.12))
                            )
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(DS.Adaptive.textTertiary)
                        }
                    }
                    
                    // Address flow section
                    HStack(spacing: 8) {
                        addressLabel(transaction.shortFromAddress, label: transaction.fromLabel, isFrom: true)
                        
                        // Animated arrow
                        ZStack {
                            Circle()
                                .fill(transaction.sentiment.color.opacity(0.15))
                                .frame(width: 20, height: 20)
                            
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(transaction.sentiment.color)
                        }
                        
                        addressLabel(transaction.shortToAddress, label: transaction.toLabel, isFrom: false)
                    }
                }
                .padding(14)
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        // Subtle size-based background tint
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(whaleSize.color.opacity(whaleSize.backgroundOpacity))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                transaction.sentiment.color.opacity(0.4),
                                whaleSize.color.opacity(0.2),
                                DS.Adaptive.stroke
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(WhaleCardButtonStyle())
        .contextMenu {
            // Copy From Address
            Button {
                // SECURITY: Auto-clear clipboard after 60s to prevent address leakage
                SecurityManager.shared.secureCopy(transaction.fromAddress)
                showCopiedFeedback("From address copied")
            } label: {
                Label("Copy From Address", systemImage: "doc.on.doc")
            }
            
            // Copy To Address
            Button {
                // SECURITY: Auto-clear clipboard after 60s to prevent address leakage
                SecurityManager.shared.secureCopy(transaction.toAddress)
                showCopiedFeedback("To address copied")
            } label: {
                Label("Copy To Address", systemImage: "doc.on.doc")
            }
            
            Divider()
            
            // Watch From Wallet
            Button {
                let label = transaction.fromLabel ?? "Watched Wallet"
                onWatchWallet?(transaction.fromAddress, label, transaction.blockchain)
                showCopiedFeedback("Wallet added to watch list")
            } label: {
                Label("Watch From Wallet", systemImage: "eye.fill")
            }
            
            // Watch To Wallet
            Button {
                let label = transaction.toLabel ?? "Watched Wallet"
                onWatchWallet?(transaction.toAddress, label, transaction.blockchain)
                showCopiedFeedback("Wallet added to watch list")
            } label: {
                Label("Watch To Wallet", systemImage: "eye.fill")
            }
            
            Divider()
            
            // Share Transaction
            Button {
                shareTransaction()
            } label: {
                Label("Share Transaction", systemImage: "square.and.arrow.up")
            }
            
            // View on Explorer
            if let url = transaction.explorerURL {
                Button {
                    openURL(url)
                } label: {
                    Label("View on Explorer", systemImage: "safari")
                }
            }
            
            // Copy Transaction Hash
            Button {
                // SECURITY: Auto-clear clipboard after 60s
                SecurityManager.shared.secureCopy(transaction.hash)
                showCopiedFeedback("Transaction hash copied")
            } label: {
                Label("Copy Transaction Hash", systemImage: "number")
            }
        }
        .overlay(alignment: .top) {
            // Copied toast notification
            if showCopiedToast {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                    Text(copiedText)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.green)
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(100)
                .offset(y: -8)
            }
        }
        .sheet(isPresented: $showDetails) {
            WhaleTransactionDetailView(transaction: transaction)
                .presentationDetents([.medium, .large])
        }
    }
    
    private func showCopiedFeedback(_ message: String) {
        let impactMedium = UIImpactFeedbackGenerator(style: .medium)
        impactMedium.impactOccurred()
        copiedText = message
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showCopiedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.2)) {
                showCopiedToast = false
            }
        }
    }
    
    private func shareTransaction() {
        let activityVC = UIActivityViewController(
            activityItems: [shareText],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            // Find the topmost presented controller
            var topController = rootVC
            while let presented = topController.presentedViewController {
                topController = presented
            }
            
            // For iPad: configure popover
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = topController.view
                popover.sourceRect = CGRect(x: topController.view.bounds.midX, y: topController.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            
            topController.present(activityVC, animated: true)
        }
    }
    
    private func addressLabel(_ address: String, label: String?, isFrom: Bool) -> some View {
        VStack(alignment: isFrom ? .leading : .trailing, spacing: 2) {
            if let label = label {
                HStack(spacing: 3) {
                    if !isFrom { Spacer() }
                    Image(systemName: "building.columns.fill")
                        .font(.system(size: 8))
                    Text(label)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                    if isFrom { Spacer() }
                }
                .foregroundStyle(BrandColors.goldBase)
            }
            Text(address)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(DS.Adaptive.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: isFrom ? .leading : .trailing)
    }
}

// MARK: - Card Button Style

struct WhaleCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Transaction Detail View

struct WhaleTransactionDetailView: View {
    let transaction: WhaleTransaction
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var didCopyHash = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Amount header with sentiment
                    VStack(spacing: 12) {
                        // Sentiment badge
                        HStack(spacing: 6) {
                            Image(systemName: transaction.sentiment.icon)
                                .font(.system(size: 12, weight: .bold))
                            Text(transaction.sentiment.rawValue)
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(transaction.sentiment.color)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(transaction.sentiment.color.opacity(0.15))
                        )
                        
                        Text(transaction.formattedUSD)
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(DS.Adaptive.textPrimary)
                        
                        Text("\(transaction.formattedAmount) \(transaction.symbol)")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(DS.Adaptive.textSecondary)
                        
                        HStack(spacing: 8) {
                            CoinImageView(symbol: transaction.blockchain.symbol, url: nil, size: 18)
                            Text(transaction.blockchain.rawValue)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(DS.Adaptive.textSecondary)
                        }
                        
                        HStack(spacing: 8) {
                            detailPill(
                                icon: WhaleSize.from(amountUSD: transaction.amountUSD).icon,
                                text: WhaleSize.from(amountUSD: transaction.amountUSD).rawValue,
                                color: WhaleSize.from(amountUSD: transaction.amountUSD).color
                            )
                            detailPill(
                                icon: "clock",
                                text: WhaleRelativeTimeFormatter.format(transaction.timestamp),
                                color: DS.Adaptive.textSecondary
                            )
                        }
                    }
                    .padding(.vertical)
                    
                    // Transaction type explanation
                    HStack(spacing: 12) {
                        Image(systemName: transaction.transactionType.icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(transaction.sentiment.color)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(transaction.sentiment.color.opacity(0.15))
                            )
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(transaction.transactionType.description)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(DS.Adaptive.textPrimary)
                            Text(transactionExplanation)
                                .font(.system(size: 12))
                                .foregroundStyle(DS.Adaptive.textTertiary)
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(transaction.sentiment.color.opacity(0.1))
                    )
                    
                    // Details
                    VStack(spacing: 0) {
                        hashRow
                        Divider().background(DS.Adaptive.divider)
                        detailRow("From", value: transaction.shortFromAddress, isMonospace: true)
                        if let fromLabel = transaction.fromLabel {
                            detailRow("", value: fromLabel, isHighlighted: true)
                        }
                        Divider().background(DS.Adaptive.divider)
                        detailRow("To", value: transaction.shortToAddress, isMonospace: true)
                        if let toLabel = transaction.toLabel {
                            detailRow("", value: toLabel, isHighlighted: true)
                        }
                        Divider().background(DS.Adaptive.divider)
                        detailRow("Time", value: WhaleRelativeTimeFormatter.format(transaction.timestamp))
                        Divider().background(DS.Adaptive.divider)
                        detailRow("Date", value: transaction.timestamp.formatted(date: .abbreviated, time: .shortened))
                        Divider().background(DS.Adaptive.divider)
                        detailRow("Source", value: sourceDisplayText)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    
                    if transaction.blockchain.explorerURL(forAddress: transaction.fromAddress) != nil || transaction.blockchain.explorerURL(forAddress: transaction.toAddress) != nil {
                        VStack(spacing: 8) {
                            if let fromURL = transaction.blockchain.explorerURL(forAddress: transaction.fromAddress) {
                                explorerAddressButton(title: "View Sender Wallet", url: fromURL)
                            }
                            if let toURL = transaction.blockchain.explorerURL(forAddress: transaction.toAddress) {
                                explorerAddressButton(title: "View Receiver Wallet", url: toURL)
                            }
                        }
                    }
                    
                    // View on Explorer button
                    if let url = transaction.explorerURL {
                        Button {
                            openURL(url)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.up.right.square")
                                Text("View on \(transaction.blockchain.rawValue)")
                            }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(transaction.blockchain.color)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(transaction.blockchain.color.opacity(0.15))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(transaction.blockchain.color.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }
                }
                .padding()
            }
            .background(DS.Adaptive.background)
            .navigationTitle("Transaction Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DS.Adaptive.textSecondary)
                            .padding(8)
                            .background(
                                Circle()
                                    .fill(DS.Adaptive.textSecondary.opacity(0.12))
                            )
                    }
                }
            }
            .enableInteractivePopGesture()
            .edgeSwipeToDismiss(onDismiss: { dismiss() })
        }
    }
    
    private var transactionExplanation: String {
        switch transaction.transactionType {
        case .exchangeWithdrawal:
            return "Crypto moving off exchange often indicates accumulation - bullish signal"
        case .exchangeDeposit:
            return "Crypto moving to exchange may indicate intent to sell - bearish signal"
        case .transfer:
            return "Wallet to wallet transfer - could be rebalancing or OTC trade"
        case .unknown:
            return "Transaction type could not be determined"
        }
    }
    
    private var sourceDisplayText: String {
        let reliability = transaction.dataSource.isReliable ? "Verified" : "Unverified"
        return "\(transaction.dataSource.rawValue) • \(reliability)"
    }
    
    private var shortenedHash: String {
        guard transaction.hash.count > 20 else { return transaction.hash }
        let prefix = transaction.hash.prefix(8)
        let suffix = transaction.hash.suffix(6)
        return "\(prefix)...\(suffix)"
    }
    
    @ViewBuilder
    private func detailPill(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
        )
    }
    
    private var hashRow: some View {
        HStack {
            Text("Hash")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DS.Adaptive.textSecondary)
            Spacer()
            Text(shortenedHash)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(DS.Adaptive.textPrimary)
            Button {
                #if canImport(UIKit)
                UIPasteboard.general.string = transaction.hash
                #endif
                withAnimation(.easeInOut(duration: 0.2)) {
                    didCopyHash = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        didCopyHash = false
                    }
                }
            } label: {
                Image(systemName: didCopyHash ? "checkmark.circle.fill" : "doc.on.doc")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(didCopyHash ? .green : DS.Adaptive.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
    }
    
    private func explorerAddressButton(title: String, url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "wallet.pass")
                Text(title)
                Spacer()
                Image(systemName: "arrow.up.right")
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(DS.Adaptive.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DS.Adaptive.chipBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(DS.Adaptive.stroke, lineWidth: 0.6)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func detailRow(_ title: String, value: String, isMonospace: Bool = false, isHighlighted: Bool = false) -> some View {
        HStack {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DS.Adaptive.textSecondary)
            }
            Spacer()
            Text(value)
                .font(isMonospace ? .system(size: 13, weight: .medium, design: .monospaced) : .system(size: 14, weight: .medium))
                .foregroundStyle(isHighlighted ? BrandColors.goldBase : DS.Adaptive.textPrimary)
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Filters Sheet

struct WhaleFiltersSheet: View {
    @ObservedObject var viewModel: WhaleTrackingViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var minAmountText: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Minimum Amount") {
                    TextField("Min USD Amount", text: $minAmountText)
                        .keyboardType(.numberPad)
                        .onAppear {
                            minAmountText = String(Int(viewModel.minAmount))
                        }
                    
                    // Quick presets
                    HStack(spacing: 8) {
                        ForEach(["100K", "500K", "1M", "5M"], id: \.self) { preset in
                            let isSelected = minAmountText == String(Int(presetValue(preset)))
                            Button {
                                let impactLight = UIImpactFeedbackGenerator(style: .light)
                                impactLight.impactOccurred()
                                let value: Double
                                switch preset {
                                case "100K": value = 100_000
                                case "500K": value = 500_000
                                case "1M": value = 1_000_000
                                case "5M": value = 5_000_000
                                default: value = 500_000
                                }
                                minAmountText = String(Int(value))
                                viewModel.minAmount = value
                            } label: {
                                Text(preset)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(isSelected ? .white : DS.Adaptive.textSecondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(isSelected ? Color.blue : DS.Adaptive.chipBackground)
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(isSelected ? Color.clear : DS.Adaptive.stroke, lineWidth: 0.5)
                                    )
                            }
                            .buttonStyle(.plain)
                            .animation(.easeInOut(duration: 0.15), value: isSelected)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Section("Search") {
                    TextField("Address, hash, or symbol", text: $viewModel.searchText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        viewModel.selectedBlockchain = nil
                        viewModel.selectedToken = nil
                        viewModel.minAmount = viewModel.baselineMinAmount
                        viewModel.searchText = ""
                        viewModel.sortOrder = .newest
                        minAmountText = String(Int(viewModel.baselineMinAmount))
                    } label: {
                        Text("Reset")
                            .foregroundStyle(.red.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if let amount = Double(minAmountText) {
                            viewModel.minAmount = amount
                        }
                        dismiss()
                    } label: {
                        Text("Done")
                    .fontWeight(.semibold)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
            .enableInteractivePopGesture()
            .edgeSwipeToDismiss(onDismiss: { dismiss() })
        }
    }
    
    private func presetValue(_ preset: String) -> Double {
        switch preset {
        case "100K": return 100_000
        case "500K": return 500_000
        case "1M": return 1_000_000
        case "5M": return 5_000_000
        default: return 500_000
        }
    }
}

// MARK: - Volume Sparkline Chart

struct WhaleVolumeSparkline: View {
    let dataPoints: [WhaleTrackingService.VolumeDataPoint]
    
    @State private var selectedPoint: WhaleTrackingService.VolumeDataPoint?
    @State private var touchLocation: CGPoint = .zero
    
    private var maxVolume: Double {
        dataPoints.map(\.volumeUSD).max() ?? 1
    }
    
    private var normalizedPoints: [CGFloat] {
        guard maxVolume > 0 else { return [] }
        return dataPoints.map { CGFloat($0.volumeUSD / maxVolume) }
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Background grid lines
                VStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { _ in
                        Divider()
                            .background(DS.Adaptive.divider.opacity(0.3))
                        Spacer()
                    }
                }
                
                // Flow bars (stacked inflow/outflow) - Always show all 24 bars
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array(dataPoints.enumerated()), id: \.element.id) { index, point in
                        let isSelected = selectedPoint?.id == point.id
                        let hasVolume = point.volumeUSD > 0
                        let barHeight = maxVolume > 0 ? (point.volumeUSD / maxVolume) * Double(geo.size.height * 0.85) : 0
                        
                        // Minimum bar height to show all 24 hours visually
                        let minBarHeight: CGFloat = 4
                        
                        VStack(spacing: 0) {
                            if hasVolume {
                                // Outflow portion (green)
                                let outflowHeight = point.exchangeOutflow > 0 ? (point.exchangeOutflow / point.volumeUSD) * barHeight : 0
                                if outflowHeight > 0 {
                                    Rectangle()
                                        .fill(Color.green.opacity(isSelected ? 0.9 : 0.6))
                                        .frame(height: max(outflowHeight, 0))
                                }
                                
                                // Inflow portion (red)
                                let inflowHeight = point.exchangeInflow > 0 ? (point.exchangeInflow / point.volumeUSD) * barHeight : 0
                                if inflowHeight > 0 {
                                    Rectangle()
                                        .fill(Color.red.opacity(isSelected ? 0.9 : 0.6))
                                        .frame(height: max(inflowHeight, 0))
                                }
                                
                                // Neutral volume portion (blue/purple)
                                let neutralHeight = max(barHeight - outflowHeight - inflowHeight, minBarHeight)
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.blue.opacity(isSelected ? 0.9 : 0.7), Color.purple.opacity(isSelected ? 0.9 : 0.5)],
                                            startPoint: .bottom,
                                            endPoint: .top
                                        )
                                    )
                                    .frame(height: neutralHeight)
                            } else {
                                // No volume - show minimal placeholder bar
                                Rectangle()
                                    .fill(DS.Adaptive.divider.opacity(isSelected ? 0.6 : 0.3))
                                    .frame(height: minBarHeight)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                        .scaleEffect(y: isSelected ? 1.05 : 1.0, anchor: .bottom)
                        .animation(.easeOut(duration: 0.15), value: isSelected)
                        .onTapGesture {
                            let impactLight = UIImpactFeedbackGenerator(style: .light)
                            impactLight.impactOccurred()
                            withAnimation(.easeOut(duration: 0.15)) {
                                selectedPoint = selectedPoint?.id == point.id ? nil : point
                            }
                        }
                    }
                }
                
                // Selected point tooltip
                if let selected = selectedPoint {
                    VStack(spacing: 4) {
                        Text(formatTime(selected.date))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                        
                        Text(formatVolume(selected.volumeUSD))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        HStack(spacing: 8) {
                            HStack(spacing: 2) {
                                Circle().fill(Color.green).frame(width: 4, height: 4)
                                Text(formatVolume(selected.exchangeOutflow))
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundColor(.green)
                            }
                            HStack(spacing: 2) {
                                Circle().fill(Color.red).frame(width: 4, height: 4)
                                Text(formatVolume(selected.exchangeInflow))
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundColor(.red)
                            }
                        }
                        
                        Text("\(selected.transactionCount) txns")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(DS.Adaptive.stroke, lineWidth: 1)
                    )
                    .offset(y: -geo.size.height - 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha" // e.g., "3PM"
        return formatter.string(from: date)
    }
    
    private func formatVolume(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "$%.1fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "$%.0fK", value / 1_000)
        }
        return String(format: "$%.0f", value)
    }
}

// MARK: - Smart Money Components

struct SmartMoneyIndexBadge: View {
    let index: SmartMoneyIndex
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: index.trend.icon)
                .font(.system(size: 10, weight: .bold))
            Text("\(index.score)")
                .font(.system(size: 12, weight: .bold))
        }
        .foregroundColor(index.trend.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(index.trend.color.opacity(0.15))
        )
    }
}

struct SmartMoneyGauge: View {
    let index: SmartMoneyIndex
    @State private var animatedScore: Double = 0
    @State private var dotScale: CGFloat = 1.0
    
    var body: some View {
        VStack(spacing: 10) {
            // Score display
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(round(GaugeMotionProfile.clampPercent(animatedScore))))")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(index.trend.color)
                
                Text("/100")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
                
                Spacer()
                
                // Trend badge
                HStack(spacing: 4) {
                    Image(systemName: index.trend == .bullish ? "arrow.up.right" :
                                     index.trend == .bearish ? "arrow.down.right" : "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                    Text(index.trend.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(index.trend.color)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(index.trend.color.opacity(0.12))
                )
                .overlay(
                    Capsule()
                        .stroke(index.trend.color.opacity(0.2), lineWidth: 0.5)
                )
            }
            
            // Gauge bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 6)
                        .fill(DS.Adaptive.chipBackground)
                        .frame(height: 10)
                    
                    // Gradient fill
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [.red.opacity(0.7), .orange, .yellow, .green.opacity(0.8), .green],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 10)
                        .mask(
                            RoundedRectangle(cornerRadius: 6)
                                .frame(width: geo.size.width * CGFloat(GaugeMotionProfile.clampUnit(animatedScore / 100.0)))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        )
                    
                    // Indicator dot
                    let position = CGFloat(GaugeMotionProfile.clampUnit(animatedScore / 100.0)) * geo.size.width
                    Circle()
                        .fill(.white)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle()
                                .fill(index.trend.color)
                                .frame(width: 8, height: 8)
                        )
                        .scaleEffect(dotScale)
                        .offset(x: max(0, min(position - 7, geo.size.width - 14)))
                }
            }
            .frame(height: 14)
            
            // Labels
            HStack {
                Text("Bearish")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.red.opacity(0.7))
                Spacer()
                Text("Bullish")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.green)
            }
            
            // Signal counts
            HStack(spacing: 16) {
                signalCount(count: index.bullishSignals, label: "Bullish", color: .green)
                signalCount(count: index.neutralSignals, label: "Neutral", color: .gray)
                signalCount(count: index.bearishSignals, label: "Bearish", color: .red)
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 4)
        .onAppear {
            animatedScore = 0
            dotScale = 0.94
            withAnimation(GaugeMotionProfile.fill) {
                animatedScore = Double(index.score)
                dotScale = 1.08
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(GaugeMotionProfile.spring) {
                    dotScale = 1.0
                }
            }
        }
        .onChange(of: index.score) { _, newScore in
            withAnimation(GaugeMotionProfile.fill) {
                animatedScore = Double(newScore)
                dotScale = 1.05
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(GaugeMotionProfile.spring) {
                    dotScale = 1.0
                }
            }
        }
    }
    
    private func signalCount(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 20, height: 20)
                
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(color)
            }
            
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DS.Adaptive.textSecondary)
        }
    }
}

struct SmartMoneySignalRow: View {
    let signal: SmartMoneySignal
    
    var body: some View {
        HStack(spacing: 12) {
            // Enhanced category icon with gradient ring
            ZStack {
                // Outer glow ring
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [signal.wallet.category.color.opacity(0.5), signal.wallet.category.color.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
                    .frame(width: 42, height: 42)
                
                // Inner fill
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [signal.wallet.category.color.opacity(0.2), signal.wallet.category.color.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 38, height: 38)
                
                Image(systemName: signal.wallet.category.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [signal.wallet.category.color, signal.wallet.category.color.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            
            // Signal info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(signal.wallet.label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .lineLimit(1)
                    
                    // Enhanced ROI badge
                    if let roi = signal.wallet.historicalROI {
                        HStack(spacing: 2) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 8, weight: .bold))
                            Text("+\(Int(roi))%")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.green.opacity(0.12))
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.green.opacity(0.25), lineWidth: 0.5)
                        )
                    }
                }
                
                // Category and blockchain row
                HStack(spacing: 6) {
                    // Category label
                    Text(signal.wallet.category.shortLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    
                    Text("•")
                        .font(.system(size: 8))
                        .foregroundColor(DS.Adaptive.textTertiary.opacity(0.5))
                    
                    // Blockchain indicator
                    HStack(spacing: 3) {
                        Circle()
                            .fill(signal.wallet.blockchain.color)
                            .frame(width: 6, height: 6)
                        Text(signal.wallet.blockchain.rawValue)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(signal.wallet.blockchain.color)
                    }
                }
                
                // Signal type badge with better styling
                HStack(spacing: 5) {
                    Image(systemName: signal.signalType.icon)
                        .font(.system(size: 10, weight: .semibold))
                    Text(signal.signalType.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(signal.signalType.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(signal.signalType.color.opacity(0.12))
                )
                .overlay(
                    Capsule()
                        .stroke(signal.signalType.color.opacity(0.2), lineWidth: 0.5)
                )
            }
            
            Spacer()
            
            // Amount and time
            VStack(alignment: .trailing, spacing: 4) {
                Text(formatLargeAmount(signal.transaction.amountUSD))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                // Timestamp (cleaner format)
                Text(WhaleRelativeTimeFormatter.format(signal.timestamp))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
                
                // Confidence with percentage
                HStack(spacing: 4) {
                    Text("Confidence")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    
                    // Confidence bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(DS.Adaptive.stroke.opacity(0.3))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(confidenceGradient)
                                .frame(width: geo.size.width * CGFloat(signal.confidence / 100))
                        }
                    }
                    .frame(width: 40, height: 4)
                    
                    Text("\(Int(signal.confidence))%")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(confidenceColor)
                }
            }
        }
        .padding(.vertical, 6)
    }
    
    private var confidenceGradient: LinearGradient {
        switch signal.confidence {
        case 0..<40:
            return LinearGradient(colors: [.orange, .orange.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
        case 40..<70:
            return LinearGradient(colors: [.yellow, .yellow.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
        default:
            return LinearGradient(colors: [.green, .green.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
        }
    }
    
    private var confidenceColor: Color {
        switch signal.confidence {
        case 0..<40: return .orange
        case 40..<70: return .yellow
        default: return .green
        }
    }
    
    private func formatLargeAmount(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "$%.1fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "$%.0fK", value / 1_000)
        }
        return String(format: "$%.0f", value)
    }
    
}

#Preview {
    WhaleActivityView()
        .preferredColorScheme(.dark)
}
