//
//  AgentHomeCard.swift
//  CryptoSage
//
//  Small conditional card for the Home tab — shows agent status,
//  daily P&L, and trade count. Only visible when the agent is connected.
//  Tapping switches to the Portfolio tab where the agent dashboard lives.
//

import SwiftUI

struct AgentHomeCard: View {
    @ObservedObject private var agentService = AgentConnectionService.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Only render when agent is connected
        if agentService.isConnected {
            Button {
                // Haptic feedback
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                // Navigate to Portfolio tab where the agent dashboard section lives
                AppState.shared.selectedTab = .portfolio
            } label: {
                cardContent
            }
            .buttonStyle(.plain)
        }
    }

    private var cardContent: some View {
        PremiumGlassCard(showGoldAccent: false, cornerRadius: 14) {
            HStack(spacing: 10) {
                // Agent status dot
                Circle()
                    .fill(agentService.agentStatus?.statusColor ?? .gray)
                    .frame(width: 8, height: 8)

                // Agent name
                Text(AgentConfig.defaultAgentName)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)

                Spacer()

                // Daily P&L
                if let pnl = agentService.agentStatus?.daily_pnl {
                    Text(formatPnL(pnl))
                        .font(.caption.weight(.medium).monospaced())
                        .foregroundColor(pnl >= 0 ? .green : .red)
                }

                // Divider dot
                Circle()
                    .fill(DS.Adaptive.textTertiary)
                    .frame(width: 3, height: 3)

                // Trade count today (cached in service)
                let tradeCount = agentService.todayTradeCount
                Text("\(tradeCount) trade\(tradeCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundColor(DS.Adaptive.textTertiary)

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Helpers

    private func formatPnL(_ value: Double) -> String {
        let prefix = value >= 0 ? "+" : ""
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return "\(prefix)\(formatter.string(from: NSNumber(value: value)) ?? "$0.00")"
    }
}

#Preview {
    VStack {
        AgentHomeCard()
    }
    .padding()
    .background(Color.black)
}
