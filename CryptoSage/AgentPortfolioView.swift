//
//  AgentPortfolioView.swift
//  CryptoSage
//
//  Displays the connected AI agent's portfolio — positions, balance,
//  total value, and recent trade history.
//

import SwiftUI

struct AgentPortfolioView: View {
    @ObservedObject private var agentService = AgentConnectionService.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                portfolioSummary
                positionsSection
                recentTradesSection
            }
            .padding(.vertical, 16)
        }
        .background(DS.Adaptive.background)
        .navigationTitle("Agent Portfolio")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Portfolio Summary

    private var portfolioSummary: some View {
        SettingsSection(title: "PORTFOLIO VALUE") {
            if let portfolio = agentService.portfolio {
                VStack(spacing: 12) {
                    HStack {
                        Text("Total Value")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textSecondary)
                        Spacer()
                        Text(String(format: "$%.2f", portfolio.total_value_usd))
                            .font(.title2.weight(.bold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                    }

                    SettingsDivider()

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cash")
                                .font(.caption2)
                                .foregroundColor(DS.Adaptive.textTertiary)
                            Text(String(format: "$%.2f", portfolio.balance_usd))
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(DS.Adaptive.textPrimary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Crypto")
                                .font(.caption2)
                                .foregroundColor(DS.Adaptive.textTertiary)
                            Text(String(format: "$%.2f", portfolio.cryptoValue))
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(DS.Adaptive.textPrimary)
                        }
                    }

                    HStack {
                        Text("Strategy: \(portfolio.strategy)")
                            .font(.caption2)
                            .foregroundColor(DS.Adaptive.textTertiary)
                        Spacer()
                        if let updated = portfolio.updated_at {
                            Text(updated, style: .relative)
                                .font(.caption2)
                                .foregroundColor(DS.Adaptive.textTertiary)
                        }
                    }
                }
                .padding(.vertical, 4)
            } else {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "chart.pie")
                            .font(.title)
                            .foregroundColor(.gray)
                        Text("No portfolio data yet")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                    Spacer()
                }
                .padding(.vertical, 16)
            }
        }
    }

    // MARK: - Positions

    private var positionsSection: some View {
        Group {
            if let portfolio = agentService.portfolio, !portfolio.positions.isEmpty {
                SettingsSection(title: "POSITIONS") {
                    ForEach(Array(portfolio.positions.sorted(by: { $0.key < $1.key })), id: \.key) { symbol, quantity in
                        HStack {
                            Text(symbol)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(DS.Adaptive.textPrimary)
                            Spacer()
                            Text(formatQuantity(quantity))
                                .font(.subheadline.monospaced())
                                .foregroundColor(DS.Adaptive.textSecondary)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
    }

    // MARK: - Recent Trades

    private var recentTradesSection: some View {
        Group {
            if !agentService.recentTrades.isEmpty {
                SettingsSection(title: "RECENT TRADES") {
                    ForEach(agentService.recentTrades.prefix(10)) { trade in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(trade.action)
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(trade.isBuy ? .green : .red)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background((trade.isBuy ? Color.green : Color.red).opacity(0.12))
                                    .clipShape(Capsule())

                                Text(trade.symbol)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(DS.Adaptive.textPrimary)

                                Spacer()

                                Text(String(format: "$%.2f", trade.usd_amount))
                                    .font(.subheadline)
                                    .foregroundColor(DS.Adaptive.textPrimary)
                            }

                            HStack {
                                Text(String(format: "%.6f @ $%,.0f", trade.quantity, trade.price))
                                    .font(.caption2)
                                    .foregroundColor(DS.Adaptive.textTertiary)

                                Spacer()

                                if let ts = trade.timestamp {
                                    Text(ts, style: .relative)
                                        .font(.caption2)
                                        .foregroundColor(DS.Adaptive.textTertiary)
                                }
                            }

                            if !trade.reason.isEmpty {
                                Text(trade.reason)
                                    .font(.caption2)
                                    .foregroundColor(DS.Adaptive.textSecondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 4)

                        if trade.id != agentService.recentTrades.prefix(10).last?.id {
                            SettingsDivider()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatQuantity(_ qty: Double) -> String {
        if qty >= 1 {
            return String(format: "%.4f", qty)
        } else if qty >= 0.001 {
            return String(format: "%.6f", qty)
        } else {
            return String(format: "%.8f", qty)
        }
    }
}

#Preview {
    NavigationView {
        AgentPortfolioView()
    }
}
