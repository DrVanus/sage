//
//  WalletDetailView.swift
//  CryptoSage
//
//  Detailed view for a watched wallet showing activity and stats.
//

import SwiftUI

struct WalletDetailView: View {
    let wallet: WatchedWallet
    @StateObject private var service = WhaleTrackingService.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showEditSheet: Bool = false
    
    // Computed properties for wallet data
    private var walletTransactions: [WhaleTransaction] {
        service.recentTransactions.filter {
            $0.fromAddress.lowercased() == wallet.address.lowercased() ||
            $0.toAddress.lowercased() == wallet.address.lowercased()
        }
    }
    
    private var totalVolume: Double {
        walletTransactions.reduce(0) { $0 + $1.amountUSD }
    }
    
    private var inflowVolume: Double {
        walletTransactions.filter {
            $0.toAddress.lowercased() == wallet.address.lowercased()
        }.reduce(0) { $0 + $1.amountUSD }
    }
    
    private var outflowVolume: Double {
        walletTransactions.filter {
            $0.fromAddress.lowercased() == wallet.address.lowercased()
        }.reduce(0) { $0 + $1.amountUSD }
    }
    
    private var netFlow: Double {
        inflowVolume - outflowVolume
    }
    
    private var isSmartMoney: Bool {
        KnownSmartMoneyWallets.isSmartMoney(wallet.address)
    }
    
    private var smartMoneyInfo: SmartMoneyWallet? {
        KnownSmartMoneyWallets.wallet(for: wallet.address)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Wallet Header
                    walletHeader
                    
                    // Quick Stats
                    statsCard
                    
                    // Activity Heatmap
                    activityHeatmap
                    
                    // Flow Summary
                    flowSummary
                    
                    // Recent Transactions
                    recentTransactionsSection
                    
                    // Actions
                    actionsSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(DS.Adaptive.background)
            .navigationTitle("Wallet Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    CSNavButton(icon: "xmark", action: { dismiss() }, accessibilityText: "Close", compact: true)
                }
            }
            .enableInteractivePopGesture()
            .edgeSwipeToDismiss(onDismiss: { dismiss() })
        }
    }
    
    // MARK: - Wallet Header
    
    private var walletHeader: some View {
        VStack(spacing: 16) {
            // Icon and blockchain
            ZStack {
                // Blockchain coin logo
                CoinImageView(symbol: wallet.blockchain.symbol, url: nil, size: 72)
                
                // Smart money badge
                if isSmartMoney {
                    Image(systemName: "dollarsign.arrow.circlepath")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(6)
                        .background(
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.purple, .blue],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .offset(x: 28, y: 28)
                }
            }
            
            // Wallet name and address
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Text(wallet.label)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    // Verified badge for known wallets
                    if KnownWhaleLabels.label(for: wallet.address) != nil {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(BrandColors.goldBase)
                    }
                }
                
                // Address with copy button
                Button {
                    UIPasteboard.general.string = wallet.address
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()
                } label: {
                    HStack(spacing: 6) {
                        Text(wallet.shortAddress)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(DS.Adaptive.textSecondary)
                        
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundStyle(DS.Adaptive.textTertiary)
                    }
                }
                
                // Smart money info
                if let smartInfo = smartMoneyInfo {
                    HStack(spacing: 8) {
                        Image(systemName: smartInfo.category.icon)
                            .font(.system(size: 11))
                        Text(smartInfo.category.rawValue)
                            .font(.system(size: 11, weight: .semibold))
                        
                        if let roi = smartInfo.historicalROI {
                            Text("•")
                                .foregroundColor(DS.Adaptive.textTertiary)
                            Text("+\(Int(roi))% ROI")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.green)
                        }
                    }
                    .foregroundColor(smartInfo.category.color)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(smartInfo.category.color.opacity(0.15))
                    )
                }
                
                // Last activity
                if let lastActivity = wallet.lastActivity {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("Active \(WhaleRelativeTimeFormatter.format(lastActivity))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 16)
    }
    
    // MARK: - Stats Card
    
    private var statsCard: some View {
        HStack(spacing: 0) {
            statItem(
                title: "Transactions",
                value: "\(walletTransactions.count)",
                icon: "arrow.left.arrow.right",
                color: .blue
            )
            
            Divider()
                .frame(height: 36)
            
            statItem(
                title: "Total Volume",
                value: formatLargeAmount(totalVolume),
                icon: "chart.bar.fill",
                color: .purple
            )
            
            Divider()
                .frame(height: 36)
            
            statItem(
                title: "Net Flow",
                value: formatLargeAmount(abs(netFlow)),
                icon: netFlow >= 0 ? "arrow.down" : "arrow.up",
                color: netFlow >= 0 ? .green : .red
            )
        }
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
    }
    
    private func statItem(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
            
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(DS.Adaptive.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.Adaptive.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Activity Heatmap
    
    private var activityHeatmap: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Activity Pattern")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Spacer()
                
                Text("Last 24h")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            // Hourly activity grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 12), spacing: 4) {
                ForEach(0..<24, id: \.self) { hour in
                    let activity = activityForHour(hour)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(activityColor(for: activity))
                        .frame(height: 20)
                        .overlay(
                            Text(hour % 6 == 0 ? "\(hour)" : "")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(DS.Adaptive.textTertiary)
                        )
                }
            }
            
            // Legend
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 12, height: 12)
                    Text("None")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.green.opacity(0.4))
                        .frame(width: 12, height: 12)
                    Text("Low")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.green.opacity(0.7))
                        .frame(width: 12, height: 12)
                    Text("Medium")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.green)
                        .frame(width: 12, height: 12)
                    Text("High")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
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
    
    private func activityForHour(_ hour: Int) -> Int {
        let calendar = Calendar.current
        let now = Date()
        _ = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now)!
        
        let count = walletTransactions.filter { tx in
            let txHour = calendar.component(.hour, from: tx.timestamp)
            return txHour == hour && calendar.isDateInToday(tx.timestamp)
        }.count
        
        return count
    }
    
    private func activityColor(for count: Int) -> Color {
        switch count {
        case 0: return Color.gray.opacity(0.2)
        case 1: return Color.green.opacity(0.4)
        case 2: return Color.green.opacity(0.7)
        default: return Color.green
        }
    }
    
    // MARK: - Flow Summary
    
    private var flowSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Flow Summary")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            // Flow bar
            GeometryReader { geo in
                let totalFlow = inflowVolume + outflowVolume
                let inflowRatio = totalFlow > 0 ? inflowVolume / totalFlow : 0.5
                let outflowRatio = totalFlow > 0 ? outflowVolume / totalFlow : 0.5
                
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(DS.Adaptive.chipBackground)
                    
                    HStack(spacing: 2) {
                        // Inflow (receiving)
                        if inflowRatio > 0.01 {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.green)
                                .frame(width: max((geo.size.width - 4) * inflowRatio, 0))
                        }
                        
                        // Outflow (sending)
                        if outflowRatio > 0.01 {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.red)
                                .frame(width: max((geo.size.width - 4) * outflowRatio, 0))
                        }
                    }
                    .padding(2)
                }
            }
            .frame(height: 24)
            
            // Labels
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                        Text("Received")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                    Text(formatLargeAmount(inflowVolume))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.green)
                }
                
                Spacer()
                
                VStack(spacing: 2) {
                    Text("Net")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    Text((netFlow >= 0 ? "+" : "") + formatLargeAmount(netFlow))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(netFlow >= 0 ? .green : .red)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("Sent")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                        Circle().fill(Color.red).frame(width: 8, height: 8)
                    }
                    Text(formatLargeAmount(outflowVolume))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.red)
                }
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
    
    // MARK: - Recent Transactions
    
    private var recentTransactionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Transactions")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Spacer()
                
                Text("\(walletTransactions.count) total")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            if walletTransactions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    
                    Text("No recent transactions")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(walletTransactions.prefix(5).enumerated()), id: \.element.id) { index, tx in
                        WalletTransactionRow(transaction: tx, walletAddress: wallet.address)
                        
                        if index < min(4, walletTransactions.count - 1) {
                            Divider()
                                .background(DS.Adaptive.divider.opacity(0.5))
                        }
                    }
                }
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
    
    // MARK: - Actions Section
    
    private var actionsSection: some View {
        VStack(spacing: 12) {
            // View on Explorer
            Button {
                if let url = wallet.blockchain.explorerURL(forAddress: wallet.address) {
                    openURL(url)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.right.square")
                    Text("View on \(wallet.blockchain.rawValue)")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(wallet.blockchain.color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(wallet.blockchain.color.opacity(0.15))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(wallet.blockchain.color.opacity(0.3), lineWidth: 1)
                )
            }
            
            // Remove from watch list
            Button(role: .destructive) {
                service.removeWatchedWallet(id: wallet.id)
                dismiss()
            } label: {
                HStack {
                    Image(systemName: "eye.slash")
                    Text("Remove from Watch List")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.red.opacity(0.15))
                )
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatLargeAmount(_ value: Double) -> String {
        let absValue = abs(value)
        if absValue >= 1_000_000_000 {
            return String(format: "$%.2fB", value / 1_000_000_000)
        } else if absValue >= 1_000_000 {
            return String(format: "$%.2fM", value / 1_000_000)
        } else if absValue >= 1_000 {
            return String(format: "$%.1fK", value / 1_000)
        }
        return String(format: "$%.0f", value)
    }
}

// MARK: - Wallet Transaction Row

struct WalletTransactionRow: View {
    let transaction: WhaleTransaction
    let walletAddress: String
    
    private var isReceiving: Bool {
        transaction.toAddress.lowercased() == walletAddress.lowercased()
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Direction indicator
            ZStack {
                Circle()
                    .fill((isReceiving ? Color.green : Color.red).opacity(0.15))
                    .frame(width: 36, height: 36)
                
                Image(systemName: isReceiving ? "arrow.down.left" : "arrow.up.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isReceiving ? .green : .red)
            }
            
            // Details
            VStack(alignment: .leading, spacing: 3) {
                Text(isReceiving ? "Received" : "Sent")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text(isReceiving ? "From: \(transaction.shortFromAddress)" : "To: \(transaction.shortToAddress)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            Spacer()
            
            // Amount and time
            VStack(alignment: .trailing, spacing: 3) {
                Text((isReceiving ? "+" : "-") + formatAmount(transaction.amountUSD))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(isReceiving ? .green : .red)
                
                Text(transaction.timestamp, style: .relative)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
        }
        .padding(.vertical, 8)
    }
    
    private func formatAmount(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "$%.2fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "$%.1fK", value / 1_000)
        }
        return String(format: "$%.0f", value)
    }
}

#Preview {
    WalletDetailView(wallet: WatchedWallet(
        address: "0xBE0eB53F46cd790Cd13851d5EFf43D12404d33E8",
        label: "Binance Hot Wallet",
        blockchain: .ethereum,
        notifyOnActivity: true,
        minTransactionAmount: 1_000_000
    ))
    .preferredColorScheme(.dark)
}
