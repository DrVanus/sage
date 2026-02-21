//
//  PaperTradeBadge.swift
//  CryptoSage
//
//  Visual indicator badge shown when paper trading mode is active.
//  NOTE: For new code, prefer using TradingModeBadge(mode: .paper) from EmptyStateViews.swift
//  for consistency across the app.
//

import SwiftUI

// MARK: - Paper Trading Badge

/// A larger, more prominent pill indicator for paper trading mode.
/// Note: For inline badges in headers, use `TradingModeBadge(mode: .paper)` instead.
/// This component is kept for backwards compatibility where a more prominent badge is needed.
struct PaperTradeBadge: View {
    var onTap: (() -> Void)?
    
    @ObservedObject private var paperTradingManager = PaperTradingManager.shared
    private var paperPrimary: Color { AppTradingMode.paper.color }
    private var paperSecondary: Color { AppTradingMode.paper.secondaryColor }
    
    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text("Paper Trading")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [paperPrimary, paperSecondary],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Compact Paper Trading Badge (uses unified TradingModeBadge)

/// A compact paper trading badge that uses the unified TradingModeBadge for consistency.
/// Use this for inline header badges where a smaller, consistent style is preferred.
struct CompactPaperTradingBadge: View {
    var onTap: (() -> Void)?
    
    var body: some View {
        TradingModeBadge(mode: .paper, onTap: onTap)
    }
}

// MARK: - Paper Trading Indicator Card

/// A larger paper trading indicator with balance and P&L info
struct PaperTradingIndicatorCard: View {
    var onExit: (() -> Void)?
    var currentPrices: [String: Double] = [:]
    
    @ObservedObject private var paperTradingManager = PaperTradingManager.shared
    
    private var portfolioValue: Double {
        paperTradingManager.calculatePortfolioValue(prices: currentPrices)
    }
    private var paperPrimary: Color { AppTradingMode.paper.color }
    private var paperSecondary: Color { AppTradingMode.paper.secondaryColor }
    
    private var profitLoss: Double {
        paperTradingManager.calculateProfitLoss(prices: currentPrices)
    }
    
    private var profitLossPercent: Double {
        paperTradingManager.calculateProfitLossPercent(prices: currentPrices)
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(paperPrimary)
                    Text("Paper Trading Active")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                
                Spacer()
                
                Button(action: { onExit?() }) {
                    Text("Exit")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.red.opacity(0.15))
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            Divider()
                .background(DS.Adaptive.stroke)
            
            // Stats
            HStack(spacing: 16) {
                // Portfolio Value
                VStack(alignment: .leading, spacing: 4) {
                    Text("Portfolio")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.Adaptive.textSecondary)
                    Text(formatCurrency(portfolioValue))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                
                Spacer()
                
                // P&L
                VStack(alignment: .trailing, spacing: 4) {
                    Text("P&L")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.Adaptive.textSecondary)
                    HStack(spacing: 4) {
                        Text(formatCurrency(profitLoss, showSign: true))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(profitLoss >= 0 ? .green : .red)
                        Text("(\(String(format: "%.2f", profitLossPercent))%)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(profitLoss >= 0 ? .green : .red)
                    }
                }
            }
            
            // Info text
            Text("Trades are simulated with virtual money. No real funds are used.")
                .font(.system(size: 11))
                .foregroundColor(DS.Adaptive.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(DS.Adaptive.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            LinearGradient(
                                colors: [paperPrimary.opacity(0.5), paperSecondary.opacity(0.5)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }
    
    private func formatCurrency(_ value: Double, showSign: Bool = false) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = CurrencyManager.currencyCode
        formatter.maximumFractionDigits = 2
        if showSign && value > 0 {
            return "+\(formatter.string(from: NSNumber(value: value)) ?? "$\(value)")"
        }
        return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
}

// MARK: - Compact Paper Trading Strip

/// A compact, single-line paper trading indicator optimized for the trading screen.
/// Shows P&L at a glance with minimal vertical footprint (~36px vs ~140px for the full card).
/// Users can tap the nav bar "Paper" badge to access full details in PaperTradingSettingsView.
struct CompactPaperTradingStrip: View {
    var onExit: (() -> Void)?
    var currentPrices: [String: Double] = [:]
    
    @ObservedObject private var paperTradingManager = PaperTradingManager.shared
    
    private var profitLoss: Double {
        paperTradingManager.calculateProfitLoss(prices: currentPrices)
    }
    
    private var profitLossPercent: Double {
        paperTradingManager.calculateProfitLossPercent(prices: currentPrices)
    }
    private var paperPrimary: Color { AppTradingMode.paper.color }
    private var paperSecondary: Color { AppTradingMode.paper.secondaryColor }
    
    private var plColor: Color {
        profitLoss >= 0 ? .green : .red
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Left: Paper icon + P&L info
            HStack(spacing: 8) {
                // Paper trading icon
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(paperPrimary)
                
                // P&L label and value
                HStack(spacing: 6) {
                    Text("P&L:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.Adaptive.textSecondary)
                    
                    Text(formatCurrency(profitLoss, showSign: true))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(plColor)
                    
                    Text("(\(formatPercent(profitLossPercent)))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(plColor)
                }
            }
            
            Spacer()
            
            // Right: Exit button
            Button(action: { onExit?() }) {
                Text("Exit")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.red.opacity(0.12))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.red.opacity(0.3), lineWidth: 0.5)
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(DS.Adaptive.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            LinearGradient(
                                colors: [paperPrimary.opacity(0.4), paperSecondary.opacity(0.4)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }
    
    private func formatCurrency(_ value: Double, showSign: Bool = false) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = CurrencyManager.currencyCode
        formatter.maximumFractionDigits = 2
        if showSign && value > 0 {
            return "+\(formatter.string(from: NSNumber(value: value)) ?? "$\(value)")"
        }
        return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
    
    private func formatPercent(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", value))%"
    }
}

// MARK: - Paper Trading Balance Row

/// Displays a single asset balance in paper trading
struct PaperBalanceRow: View {
    let asset: String
    let amount: Double
    var price: Double? = nil
    
    private var usdValue: Double? {
        guard let price = price else { return nil }
        return amount * price
    }
    
    var body: some View {
        HStack {
            // Asset icon with real coin logo
            CoinImageView(
                symbol: asset,
                url: coinImageURL(for: asset),
                size: 32
            )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(asset)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Text(formatQuantity(amount))
                    .font(.system(size: 12))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            
            Spacer()
            
            if let usdValue = usdValue {
                Text(formatCurrency(usdValue))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DS.Adaptive.textPrimary)
            }
        }
        .padding(.vertical, 8)
    }
    
    private func formatQuantity(_ value: Double) -> String {
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
    
    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = CurrencyManager.currencyCode
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
}

// MARK: - Paper Trade History Row

/// Displays a single paper trade in history
struct PaperTradeHistoryRow: View {
    let trade: PaperTrade
    
    private var sideColor: Color {
        trade.side == .buy ? .green : .red
    }
    
    private var sideText: String {
        trade.side == .buy ? "BUY" : "SELL"
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Side indicator
            Text(sideText)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(sideColor)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(trade.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Text(formatDate(trade.timestamp))
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatQuantity(trade.quantity))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Text("@ \(formatPrice(trade.price))")
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
        }
        .padding(.vertical, 8)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatQuantity(_ value: Double) -> String {
        if value < 0.001 {
            return String(format: "%.8f", value)
        } else if value < 1 {
            return String(format: "%.4f", value)
        } else {
            return String(format: "%.2f", value)
        }
    }
    
    private func formatPrice(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = CurrencyManager.currencyCode
        if value < 1 {
            formatter.maximumFractionDigits = 6
            formatter.minimumFractionDigits = 4
        } else if value < 100 {
            formatter.maximumFractionDigits = 4
            formatter.minimumFractionDigits = 2
        } else {
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 2
        }
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }
}

// MARK: - Paper Trading Promo Banner (for Free users)

/// Promotional banner shown to Free users on the trading page
/// Encourages upgrade to Pro for paper trading access
/// Can be dismissed - will reappear after 24 hours
struct PaperTradingPromoBanner: View {
    @Binding var showUpgrade: Bool
    var onDismiss: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    private var paperPrimary: Color { AppTradingMode.paper.color }
    private var paperSecondary: Color { AppTradingMode.paper.secondaryColor }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                showUpgrade = true
            } label: {
                HStack(spacing: 12) {
                    // Left: Icon + text
                    HStack(spacing: 8) {
                        // Paper trading icon with gradient background
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [paperPrimary.opacity(0.2), paperSecondary.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 32, height: 32)
                            
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [paperPrimary, paperSecondary],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text("Paper Trading")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(DS.Adaptive.textPrimary)
                                
                                Text("PRO")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(
                                                LinearGradient(
                                                    colors: [DS.Colors.gold, DS.Colors.gold.opacity(0.8)],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                    )
                                    .foregroundColor(.black)
                            }
                            
                            Text("Practice with $100k virtual funds")
                                .font(.system(size: 11))
                                .foregroundColor(DS.Adaptive.textSecondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Right: Unlock button
                    HStack(spacing: 4) {
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Unlock")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [paperPrimary, paperSecondary],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .padding(.trailing, 16) // Extra padding for dismiss button
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(DS.Adaptive.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    LinearGradient(
                                        colors: [paperPrimary.opacity(0.3), paperSecondary.opacity(0.3)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            // Dismiss button (X) in top-right corner
            if onDismiss != nil {
                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    onDismiss?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textTertiary)
                        .padding(6)
                        .background(
                            Circle()
                                .fill(DS.Adaptive.cardBackground)
                        )
                        .overlay(
                            Circle()
                                .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .offset(x: 4, y: -4)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct PaperTradeBadge_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            PaperTradeBadge()
            
            // Compact strip (new - optimized for trading screen)
            CompactPaperTradingStrip(
                currentPrices: ["BTC": 45000, "ETH": 2500]
            )
            .padding(.horizontal)
            
            // Full card (legacy - still available for other screens)
            PaperTradingIndicatorCard(
                currentPrices: ["BTC": 45000, "ETH": 2500]
            )
            .padding()
            
            PaperBalanceRow(asset: "BTC", amount: 0.5, price: 45000)
                .padding(.horizontal)
            
            PaperTradeHistoryRow(trade: PaperTrade(
                symbol: "BTCUSDT",
                side: .buy,
                quantity: 0.1,
                price: 45000
            ))
            .padding(.horizontal)
        }
        .background(Color.black)
    }
}
#endif
