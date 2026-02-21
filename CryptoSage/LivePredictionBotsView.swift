//
//  LivePredictionBotsView.swift
//  CryptoSage
//
//  View for displaying and managing live prediction market bots.
//  Shows active positions, P/L, and market status.
//

import SwiftUI

// MARK: - Live Prediction Bots View

struct LivePredictionBotsView: View {
    @ObservedObject private var tradingService = PredictionTradingService.shared
    @ObservedObject private var marketService = PredictionMarketService.shared
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var selectedBot: LivePredictionBot?
    @State private var showBotDetail: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            if tradingService.liveBots.isEmpty {
                emptyState
            } else {
                botsList
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.cyan.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "chart.bar.xaxis.ascending")
                    .font(.system(size: 32))
                    .foregroundColor(.cyan)
            }
            
            Text("No Live Prediction Bots")
                .font(.headline)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Text("Create a prediction bot to start trading on Polymarket or Kalshi with real funds")
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            NavigationLink(destination: PredictionBotView()) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                    Text("Create Prediction Bot")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(BrandColors.goldBase)
                .cornerRadius(12)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Bots List
    
    private var botsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Summary card
                summaryCard
                
                // Bot list
                ForEach(tradingService.liveBots) { bot in
                    LivePredictionBotCard(bot: bot) {
                        selectedBot = bot
                        showBotDetail = true
                    }
                }
                
                // Create new bot button
                createBotButton
                
                Spacer(minLength: 100)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .refreshable {
            await marketService.fetchTrendingMarkets()
        }
        .sheet(isPresented: $showBotDetail) {
            if let bot = selectedBot {
                LivePredictionBotDetailSheet(bot: bot)
            }
        }
    }
    
    // MARK: - Summary Card
    
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LIVE PREDICTION BOTS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(BrandColors.goldBase)
                        .tracking(0.5)
                    
                    Text("\(tradingService.liveBots.count) Active")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                
                Spacer()
                
                // Wallet status indicator
                if tradingService.isWalletConnected {
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("Connected")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                        Text("$\(String(format: "%.2f", tradingService.usdcBalance)) USDC")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                } else {
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 8, height: 8)
                            Text("Not Connected")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            
            Divider()
            
            // Stats row
            HStack(spacing: 20) {
                statItem(title: "Total Invested", value: formatCurrency(totalInvested))
                statItem(title: "P/L", value: formatPL(tradingService.totalProfitLoss), color: tradingService.totalProfitLoss >= 0 ? .green : .red)
                statItem(title: "Active Trades", value: "\(tradingService.activeTrades.filter { $0.status == .active || $0.status == .pending }.count)")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
    }
    
    private var totalInvested: Double {
        tradingService.liveBots.reduce(0) { $0 + $1.totalInvested }
    }
    
    private func statItem(title: String, value: String, color: Color = DS.Adaptive.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundColor(DS.Adaptive.textTertiary)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(color)
        }
    }
    
    // MARK: - Create Bot Button
    
    private var createBotButton: some View {
        NavigationLink(destination: PredictionBotView()) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(BrandColors.goldBase)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Create Prediction Bot")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    Text("Trade prediction markets with AI assistance")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(DS.Adaptive.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
                            .foregroundColor(BrandColors.goldBase.opacity(0.5))
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Helpers
    
    private func formatCurrency(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "$%.1fK", value / 1000)
        }
        return String(format: "$%.2f", value)
    }
    
    private func formatPL(_ value: Double) -> String {
        let prefix = value >= 0 ? "+" : ""
        return prefix + formatCurrency(value)
    }
}

// MARK: - Live Prediction Bot Card

struct LivePredictionBotCard: View {
    let bot: LivePredictionBot
    let onTap: () -> Void
    
    @ObservedObject private var tradingService = PredictionTradingService.shared
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack(alignment: .top, spacing: 10) {
                    // Platform badge
                    HStack(spacing: 4) {
                        Image(systemName: bot.platform.lowercased().contains("polymarket") ? "chart.bar.xaxis" : "chart.line.uptrend.xyaxis")
                            .font(.system(size: 10))
                        Text(bot.platform)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(bot.platform.lowercased().contains("polymarket") ? .purple : .blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill((bot.platform.lowercased().contains("polymarket") ? Color.purple : Color.blue).opacity(0.15))
                    )
                    
                    // Status badge
                    statusBadge
                    
                    Spacer()
                    
                    // Enabled toggle
                    Toggle("", isOn: Binding(
                        get: { bot.isEnabled },
                        set: { newValue in
                            if newValue {
                                Task { await tradingService.enableBot(id: bot.id) }
                            } else {
                                tradingService.disableBot(id: bot.id)
                            }
                        }
                    ))
                    .labelsHidden()
                    .scaleEffect(0.8)
                }
                
                // Title
                Text(bot.marketTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .lineLimit(2)
                
                // Position info
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Position")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textTertiary)
                        Text(bot.outcome)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(bot.outcome == "YES" ? .green : .red)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Entry")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textTertiary)
                        Text(String(format: "%.0f%%", bot.targetPrice * 100))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Invested")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textTertiary)
                        Text(String(format: "$%.2f", bot.totalInvested))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("P/L")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textTertiary)
                        Text(formatPL(bot.totalProfit))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(bot.totalProfit >= 0 ? .green : .red)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(DS.Adaptive.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(bot.status.rawValue)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(statusColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(statusColor.opacity(0.15))
        )
    }
    
    private var statusColor: Color {
        switch bot.status {
        case .idle: return .gray
        case .monitoring: return .blue
        case .trading: return .orange
        case .completed: return .green
        case .error: return .red
        }
    }
    
    private func formatPL(_ value: Double) -> String {
        let prefix = value >= 0 ? "+" : ""
        if abs(value) >= 1000 {
            return prefix + String(format: "$%.1fK", value / 1000)
        }
        return prefix + String(format: "$%.2f", value)
    }
}

// MARK: - Live Prediction Bot Detail Sheet

struct LivePredictionBotDetailSheet: View {
    let bot: LivePredictionBot
    
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var tradingService = PredictionTradingService.shared
    
    @State private var showDeleteConfirmation: Bool = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Market info
                    marketInfoSection
                    
                    // Position details
                    positionSection
                    
                    // Trades history
                    if !bot.trades.isEmpty {
                        tradesSection
                    }
                    
                    // Actions
                    actionsSection
                    
                    Spacer(minLength: 50)
                }
                .padding(20)
            }
            .background(DS.Adaptive.background.ignoresSafeArea())
            .navigationTitle("Bot Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(BrandColors.goldBase)
                }
            }
        }
        .alert("Delete Bot?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                tradingService.deleteBot(id: bot.id)
                dismiss()
            }
        } message: {
            Text("This will permanently delete this prediction bot. Active trades will not be cancelled automatically.")
        }
    }
    
    private var marketInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MARKET")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(BrandColors.goldBase)
                .tracking(0.5)
            
            Text(bot.marketTitle)
                .font(.headline)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            HStack(spacing: 12) {
                Label(bot.platform, systemImage: "chart.bar.xaxis")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textSecondary)
                
                Text("•")
                    .foregroundColor(DS.Adaptive.textTertiary)
                
                Text("Created \(bot.createdAt, style: .relative) ago")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(DS.Adaptive.cardBackground)
        )
    }
    
    private var positionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("POSITION")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(BrandColors.goldBase)
                .tracking(0.5)
            
            HStack(spacing: 20) {
                statBox(title: "Side", value: bot.outcome, color: bot.outcome == "YES" ? .green : .red)
                statBox(title: "Entry", value: String(format: "%.0f%%", bot.targetPrice * 100))
                statBox(title: "Amount", value: String(format: "$%.2f", bot.betAmount))
            }
            
            Divider()
            
            HStack(spacing: 20) {
                statBox(title: "Invested", value: String(format: "$%.2f", bot.totalInvested))
                statBox(title: "Trades", value: "\(bot.trades.count)")
                statBox(title: "P/L", value: formatPL(bot.totalProfit), color: bot.totalProfit >= 0 ? .green : .red)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(DS.Adaptive.cardBackground)
        )
    }
    
    private func statBox(title: String, value: String, color: Color = DS.Adaptive.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(DS.Adaptive.textTertiary)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var tradesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TRADE HISTORY")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(BrandColors.goldBase)
                .tracking(0.5)
            
            ForEach(bot.trades) { trade in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(trade.outcome)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(trade.outcome == "YES" ? .green : .red)
                        Text(trade.createdAt, style: .date)
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "$%.2f", trade.amount))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        Text(trade.status.rawValue)
                            .font(.caption)
                            .foregroundColor(statusColor(for: trade.status))
                    }
                }
                .padding(.vertical, 8)
                
                if trade.id != bot.trades.last?.id {
                    Divider()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(DS.Adaptive.cardBackground)
        )
    }
    
    private func statusColor(for status: LivePredictionTrade.TradeStatus) -> Color {
        switch status {
        case .pending: return .orange
        case .active: return .blue
        case .won: return .green
        case .lost: return .red
        case .cancelled: return .gray
        }
    }
    
    private var actionsSection: some View {
        VStack(spacing: 12) {
            // Toggle bot
            Button {
                if bot.isEnabled {
                    tradingService.disableBot(id: bot.id)
                } else {
                    Task { await tradingService.enableBot(id: bot.id) }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: bot.isEnabled ? "pause.circle.fill" : "play.circle.fill")
                    Text(bot.isEnabled ? "Pause Bot" : "Start Bot")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(bot.isEnabled ? Color.orange : Color.green)
                .cornerRadius(12)
            }
            
            // Delete bot
            Button {
                showDeleteConfirmation = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trash")
                    Text("Delete Bot")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.red, lineWidth: 1)
                )
            }
        }
    }
    
    private func formatPL(_ value: Double) -> String {
        let prefix = value >= 0 ? "+" : ""
        return prefix + String(format: "$%.2f", value)
    }
}

// MARK: - Preview

#if DEBUG
struct LivePredictionBotsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            LivePredictionBotsView()
        }
        .preferredColorScheme(.dark)
    }
}
#endif
