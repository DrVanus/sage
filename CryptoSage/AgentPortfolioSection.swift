//
//  AgentPortfolioSection.swift
//  CryptoSage
//
//  Created by DM on 3/7/26.
//
//  Compact agent dashboard section embedded in the Portfolio tab.
//  Shows agent status, portfolio value, daily P&L, positions, latest signal,
//  and links to Agent Settings + full Agent Portfolio view.
//  Only visible when the agent is connected.
//

import SwiftUI

struct AgentPortfolioSection: View {
    @ObservedObject private var agentService = AgentConnectionService.shared
    @Environment(\.colorScheme) private var colorScheme

    /// Navigate to AgentSettingsView
    @State private var showAgentSettings: Bool = false
    /// Navigate to full signal feed
    @State private var showSignalFeed: Bool = false
    /// Navigate to full portfolio view
    @State private var showFullPortfolio: Bool = false

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        if agentService.isConnected {
            VStack(spacing: 8) {
                agentHeaderCard
                agentPortfolioCard
                agentPositionsCard
                agentLatestSignalCard
                agentQuickLinks
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
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
                // Start Firestore listeners when section appears
                if let userId = AuthenticationManager.shared.currentUser?.id {
                    agentService.startListening(userId: userId)
                }
            }
        }
    }

    // MARK: - Agent Header (Status + Mode Badge)

    private var agentHeaderCard: some View {
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

                // Paper / Live mode indicator
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

    // MARK: - Portfolio Value + Daily P&L

    private var agentPortfolioCard: some View {
        PremiumGlassCard(showGoldAccent: false, cornerRadius: 14) {
            VStack(spacing: 8) {
                HStack {
                    Text("Agent Portfolio")
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
                        // Daily P&L
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Daily P&L")
                                .font(.caption2)
                                .foregroundColor(DS.Adaptive.textTertiary)
                            let pnl = agentService.agentStatus?.daily_pnl ?? 0
                            Text(formatPnL(pnl))
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(pnl >= 0 ? .green : .red)
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
                        ProgressView()
                            .tint(DS.Colors.gold)
                            .scaleEffect(0.7)
                        Text("Loading portfolio...")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textTertiary)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Open Positions (compact)

    private var agentPositionsCard: some View {
        Group {
            if let portfolio = agentService.portfolio, !portfolio.positions.isEmpty {
                PremiumGlassCard(showGoldAccent: false, cornerRadius: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Open Positions")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(DS.Adaptive.textSecondary)

                        // Show max 4 positions inline, truncate if more
                        ForEach(Array(portfolio.positions.sorted(by: { $0.key < $1.key }).prefix(4)), id: \.key) { symbol, qty in
                            HStack {
                                Text(symbol)
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(DS.Adaptive.textPrimary)
                                Spacer()
                                Text(formatQuantity(qty))
                                    .font(.caption.monospaced())
                                    .foregroundColor(DS.Adaptive.textSecondary)
                            }
                            .padding(.vertical, 1)
                        }

                        if portfolio.positions.count > 4 {
                            Button {
                                showFullPortfolio = true
                            } label: {
                                Text("+\(portfolio.positions.count - 4) more")
                                    .font(.caption2)
                                    .foregroundColor(DS.Adaptive.textTertiary)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    // MARK: - Latest Signal (single compact row)

    private var agentLatestSignalCard: some View {
        Group {
            if let signal = agentService.latestSignals.first {
                PremiumGlassCard(showGoldAccent: false, cornerRadius: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Latest Signal")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(DS.Adaptive.textSecondary)
                            Spacer()
                            Button {
                                showSignalFeed = true
                            } label: {
                                HStack(spacing: 3) {
                                    Text("All Signals")
                                        .font(.caption2)
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                }
                                .foregroundColor(DS.Adaptive.textTertiary)
                            }
                        }

                        HStack(spacing: 8) {
                            // Signal score circle
                            ZStack {
                                Circle()
                                    .stroke(signal.signalColor.opacity(0.3), lineWidth: 2)
                                    .frame(width: 28, height: 28)
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
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    // MARK: - Quick Links (Settings + Performance)

    private var agentQuickLinks: some View {
        HStack(spacing: 8) {
            // Performance stats
            PremiumGlassCard(showGoldAccent: false, cornerRadius: 12) {
                HStack(spacing: 12) {
                    statCell(
                        label: "Win Rate",
                        value: computeWinRate(),
                        color: DS.Adaptive.textPrimary
                    )
                    Divider()
                        .frame(height: 24)
                    statCell(
                        label: "Trades",
                        value: "\(agentService.recentTrades.count)",
                        color: DS.Adaptive.textPrimary
                    )
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            // Settings button
            Button {
                showAgentSettings = true
            } label: {
                PremiumGlassCard(showGoldAccent: false, cornerRadius: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape")
                            .font(.caption)
                        Text("Settings")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func statCell(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(DS.Adaptive.textTertiary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundColor(color)
        }
    }

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

    /// Computes win rate from recent agent trades
    private func computeWinRate() -> String {
        let trades = agentService.recentTrades
        guard trades.count > 1 else { return "—" }
        let sorted = trades.sorted { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }
        var lastBuyPrice: [String: Double] = [:]
        var wins = 0
        var completedRoundTrips = 0
        for trade in sorted {
            if trade.isBuy {
                lastBuyPrice[trade.symbol] = trade.price
            } else if let buyPrice = lastBuyPrice[trade.symbol], buyPrice > 0 {
                completedRoundTrips += 1
                if trade.price > buyPrice { wins += 1 }
                lastBuyPrice.removeValue(forKey: trade.symbol)
            }
        }
        guard completedRoundTrips > 0 else { return "—" }
        let pct = Double(wins) / Double(completedRoundTrips) * 100
        return String(format: "%.0f%%", pct)
    }
}

#Preview {
    VStack {
        AgentPortfolioSection()
    }
    .padding()
    .background(Color.black)
}
