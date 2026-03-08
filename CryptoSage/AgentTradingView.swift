//
//  AgentTradingView.swift
//  CryptoSage
//
//  Full AI agent trading dashboard — status, portfolio,
//  open positions, signals, recent trades, and performance summary.
//  Available as a standalone view for detailed agent information.
//

import SwiftUI

struct AgentTradingView: View {
    @ObservedObject private var agentService = AgentConnectionService.shared
    @Environment(\.colorScheme) private var colorScheme

    /// Navigate to AgentSettingsView when user wants to connect
    @State private var showAgentSettings: Bool = false
    /// Navigate to full signal feed
    @State private var showSignalFeed: Bool = false
    /// Navigate to full portfolio view
    @State private var showFullPortfolio: Bool = false

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        Group {
            if agentService.isConnected {
                connectedContent
            } else {
                notConnectedContent
            }
        }
        .navigationDestination(isPresented: $showAgentSettings) {
            AgentSettingsView()
        }
        .navigationDestination(isPresented: $showSignalFeed) {
            AgentSignalFeedView()
        }
        .navigationDestination(isPresented: $showFullPortfolio) {
            AgentPortfolioView()
        }
        .task {
            // Start Firestore listeners when Agent tab appears (not just AgentSettingsView)
            guard agentService.isConnected else { return }
            if let userId = AuthenticationManager.shared.currentUser?.id {
                agentService.startListening(userId: userId)
            }
        }
    }

    // MARK: - Connected Content

    private var connectedContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                agentStatusCard
                portfolioSummaryCard
                openPositionsCard
                latestSignalsCard
                recentTradesCard
                performanceSummaryCard
                settingsLink
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
        }
        .background(isDark ? Color.black : DS.Adaptive.background)
    }

    // MARK: - Not Connected CTA

    private var notConnectedContent: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "cpu.fill")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(
                        colors: [BrandColors.goldLight, BrandColors.goldBase],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 8) {
                Text(AgentConfig.defaultAgentName)
                    .font(.title2.weight(.bold))
                    .foregroundColor(DS.Adaptive.textPrimary)

                Text("Connect your AI trading agent to view live portfolio, signals, and automated trades.")
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                showAgentSettings = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "link.badge.plus")
                    Text("Connect Agent")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundColor(isDark ? .black : .white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [BrandColors.goldLight, BrandColors.goldBase],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isDark ? Color.black : DS.Adaptive.background)
    }

    // MARK: - Agent Status Card

    private var agentStatusCard: some View {
        PremiumGlassCard(showGoldAccent: true, cornerRadius: 14) {
            HStack(spacing: 10) {
                // Status dot
                Circle()
                    .fill(agentService.agentStatus?.statusColor ?? .gray)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(AgentConfig.defaultAgentName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)

                    Text(agentService.agentStatus?.statusDisplayName ?? "Unknown")
                        .font(.caption)
                        .foregroundColor(agentService.agentStatus?.statusColor ?? .gray)
                }

                Spacer()

                // Paper / Live mode indicator (dimmed when offline to avoid confusion)
                if let status = agentService.agentStatus {
                    let isPaper = status.status.lowercased().contains("paper")
                    let isOnline = status.isOnline
                    let badgeColor: Color = isPaper ? .orange : (isOnline ? .green : .gray)
                    Text(isPaper ? "Paper" : "Live")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(badgeColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(badgeColor.opacity(0.12))
                        .clipShape(Capsule())
                }

                // Circuit breaker warning
                if agentService.agentStatus?.circuit_breaker_active == true {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Portfolio Summary

    private var portfolioSummaryCard: some View {
        PremiumGlassCard(showGoldAccent: false, cornerRadius: 14) {
            VStack(spacing: 10) {
                HStack {
                    Text("Portfolio")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DS.Adaptive.textSecondary)
                    Spacer()
                    Button {
                        showFullPortfolio = true
                    } label: {
                        HStack(spacing: 3) {
                            Text("Details")
                                .font(.caption2)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                        }
                        .foregroundColor(DS.Adaptive.textTertiary)
                    }
                }

                if let portfolio = agentService.portfolio {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Total Value")
                                .font(.caption2)
                                .foregroundColor(DS.Adaptive.textTertiary)
                            Text(formatUSD(portfolio.total_value_usd))
                                .font(.title3.weight(.bold))
                                .foregroundColor(DS.Adaptive.textPrimary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Cash")
                                .font(.caption2)
                                .foregroundColor(DS.Adaptive.textTertiary)
                            Text(formatUSD(portfolio.balance_usd))
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(DS.Adaptive.textPrimary)
                        }
                    }

                    HStack {
                        Text("Strategy: \(portfolio.strategy)")
                            .font(.caption2)
                            .foregroundColor(DS.Adaptive.textTertiary)
                        Spacer()
                        Text("\(portfolio.positionCount) positions")
                            .font(.caption2)
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                } else {
                    HStack {
                        Spacer()
                        Text("Loading portfolio...")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textTertiary)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Open Positions

    private var openPositionsCard: some View {
        Group {
            if let portfolio = agentService.portfolio, !portfolio.positions.isEmpty {
                PremiumGlassCard(showGoldAccent: false, cornerRadius: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Open Positions")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(DS.Adaptive.textSecondary)

                        ForEach(Array(portfolio.positions.sorted(by: { $0.key < $1.key })), id: \.key) { symbol, qty in
                            HStack {
                                Text(symbol)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(DS.Adaptive.textPrimary)
                                Spacer()
                                Text(formatQuantity(qty))
                                    .font(.subheadline.monospaced())
                                    .foregroundColor(DS.Adaptive.textSecondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    // MARK: - Latest Signals

    private var latestSignalsCard: some View {
        Group {
            if !agentService.latestSignals.isEmpty {
                PremiumGlassCard(showGoldAccent: false, cornerRadius: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Latest Signals")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(DS.Adaptive.textSecondary)
                            Spacer()
                            Button {
                                showSignalFeed = true
                            } label: {
                                HStack(spacing: 3) {
                                    Text("View All")
                                        .font(.caption2)
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                }
                                .foregroundColor(DS.Adaptive.textTertiary)
                            }
                        }

                        ForEach(agentService.latestSignals.prefix(3)) { signal in
                            HStack(spacing: 8) {
                                // Signal score circle
                                ZStack {
                                    Circle()
                                        .stroke(signal.signalColor.opacity(0.3), lineWidth: 2)
                                        .frame(width: 32, height: 32)
                                    Text(String(format: "%.0f", signal.composite_score))
                                        .font(.caption2.weight(.bold))
                                        .foregroundColor(signal.signalColor)
                                }

                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 4) {
                                        Text(signal.symbol)
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(DS.Adaptive.textPrimary)
                                        Text(signal.signalDisplayName)
                                            .font(.caption2.weight(.medium))
                                            .foregroundColor(signal.signalColor)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(signal.signalColor.opacity(0.12))
                                            .clipShape(Capsule())
                                    }
                                    if let reasoning = signal.reasoning {
                                        Text(reasoning)
                                            .font(.caption2)
                                            .foregroundColor(DS.Adaptive.textTertiary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                if let ts = signal.timestamp {
                                    Text(ts, style: .relative)
                                        .font(.caption2)
                                        .foregroundColor(DS.Adaptive.textTertiary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    // MARK: - Recent Trades

    private var recentTradesCard: some View {
        Group {
            if !agentService.recentTrades.isEmpty {
                PremiumGlassCard(showGoldAccent: false, cornerRadius: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent Trades")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(DS.Adaptive.textSecondary)

                        ForEach(agentService.recentTrades.prefix(5)) { trade in
                            HStack(spacing: 8) {
                                // Action pill
                                Text(trade.action)
                                    .font(.caption2.weight(.bold))
                                    .foregroundColor(trade.isBuy ? .green : .red)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background((trade.isBuy ? Color.green : Color.red).opacity(0.12))
                                    .clipShape(Capsule())

                                Text(trade.symbol)
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(DS.Adaptive.textPrimary)

                                Spacer()

                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(formatUSD(trade.usd_amount))
                                        .font(.caption.weight(.medium))
                                        .foregroundColor(DS.Adaptive.textPrimary)
                                    if let ts = trade.timestamp {
                                        Text(ts, style: .relative)
                                            .font(.caption2)
                                            .foregroundColor(DS.Adaptive.textTertiary)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    // MARK: - Performance Summary

    private var performanceSummaryCard: some View {
        PremiumGlassCard(showGoldAccent: false, cornerRadius: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Performance")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DS.Adaptive.textSecondary)

                HStack(spacing: 0) {
                    // Win Rate
                    statCell(
                        label: "Win Rate",
                        value: computeWinRate(),
                        color: DS.Adaptive.textPrimary
                    )
                    Spacer()
                    // Total P&L
                    let pnl = agentService.agentStatus?.daily_pnl ?? 0
                    statCell(
                        label: "Daily P&L",
                        value: formatPnL(pnl),
                        color: pnl >= 0 ? .green : .red
                    )
                    Spacer()
                    // Trade Count
                    statCell(
                        label: "Trades",
                        value: "\(agentService.recentTrades.count)",
                        color: DS.Adaptive.textPrimary
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private func statCell(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundColor(DS.Adaptive.textTertiary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(color)
        }
    }

    // MARK: - Settings Link

    private var settingsLink: some View {
        Button {
            showAgentSettings = true
        } label: {
            HStack {
                Image(systemName: "gearshape")
                    .font(.caption)
                Text("Agent Settings")
                    .font(.caption)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
            }
            .foregroundColor(DS.Adaptive.textTertiary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Helpers

    private func formatUSD(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    private func formatPnL(_ value: Double) -> String {
        let prefix = value >= 0 ? "+" : ""
        return "\(prefix)\(formatUSD(value))"
    }

    private func formatQuantity(_ qty: Double) -> String {
        if qty >= 1 {
            return String(format: "%.4f", qty)
        } else if qty >= 0.001 {
            return String(format: "%.6f", qty)
        } else {
            return String(format: "%.8f", qty)
        }
    }

    /// Computes win rate by pairing BUY→SELL trades per symbol and comparing prices.
    /// A "win" is a sell at a higher price than the most recent buy for that symbol.
    private func computeWinRate() -> String {
        let trades = agentService.recentTrades
        guard trades.count > 1 else { return "—" }

        // Sort oldest-first to pair buys with subsequent sells
        let sorted = trades.sorted { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }

        // Track the latest buy price per symbol
        var lastBuyPrice: [String: Double] = [:]
        var wins = 0
        var completedRoundTrips = 0

        for trade in sorted {
            if trade.isBuy {
                lastBuyPrice[trade.symbol] = trade.price
            } else if let buyPrice = lastBuyPrice[trade.symbol], buyPrice > 0 {
                // This sell completes a round-trip
                completedRoundTrips += 1
                if trade.price > buyPrice {
                    wins += 1
                }
                lastBuyPrice.removeValue(forKey: trade.symbol)
            }
        }

        guard completedRoundTrips > 0 else {
            // No completed round-trips yet — show buy/sell counts instead
            let buyCount = trades.filter(\.isBuy).count
            let sellCount = trades.count - buyCount
            return "\(buyCount)B/\(sellCount)S"
        }

        let rate = Double(wins) / Double(completedRoundTrips) * 100
        return String(format: "%.0f%%", rate)
    }
}

#Preview {
    NavigationStack {
        AgentTradingView()
    }
}
