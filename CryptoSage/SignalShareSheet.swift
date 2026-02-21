//
//  SignalShareSheet.swift
//  CryptoSage
//
//  Reusable component for displaying and sharing strategy signals.
//  Allows users to copy signal details for use as trading advisory
//  on external platforms.
//

import SwiftUI

// MARK: - Signal Share Sheet

/// A sheet view for displaying signal details with share/copy options
struct SignalShareSheet: View {
    let signal: StrategySignal
    let strategyName: String
    let tradingPair: String
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var showCopiedFeedback = false
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Signal Header
                    signalHeader
                    
                    // Signal Details Card
                    signalDetailsCard
                    
                    // Triggered Conditions
                    if !signal.triggeredConditions.isEmpty {
                        triggeredConditionsCard
                    }
                    
                    // Advisory Disclaimer
                    advisoryDisclaimer
                    
                    // Action Buttons
                    actionButtons
                    
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(DS.Adaptive.background)
            .navigationTitle("Signal Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(BrandColors.goldBase)
                }
            }
            .overlay {
                if showCopiedFeedback {
                    copiedFeedbackOverlay
                }
            }
        }
    }
    
    // MARK: - Signal Header
    
    private var signalHeader: some View {
        VStack(spacing: 12) {
            // Signal type indicator
            ZStack {
                Circle()
                    .fill(signal.type == .buy ? Color.green.opacity(0.2) : 
                          (signal.type == .sell ? Color.red.opacity(0.2) : Color.gray.opacity(0.2)))
                    .frame(width: 80, height: 80)
                
                Image(systemName: signal.type.icon)
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(signal.type.color)
            }
            
            Text(signal.type.rawValue)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(signal.type.color)
            
            Text(strategyName)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(DS.Adaptive.textSecondary)
        }
        .padding(.vertical, 16)
    }
    
    // MARK: - Signal Details Card
    
    private var signalDetailsCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "chart.bar.doc.horizontal")
                    .foregroundColor(BrandColors.goldBase)
                Text("Signal Details")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Spacer()
            }
            
            Divider()
            
            detailRow(label: "Trading Pair", value: tradingPair)
            detailRow(label: "Signal Price", value: "$\(String(format: "%.2f", signal.price))")
            detailRow(label: "Confidence", value: "\(signal.confidenceLevel) (\(Int(signal.confidence * 100))%)")
            detailRow(label: "Generated", value: formatDate(signal.timestamp))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
        )
    }
    
    // MARK: - Triggered Conditions Card
    
    private var triggeredConditionsCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Triggered Conditions")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Spacer()
            }
            
            Divider()
            
            ForEach(signal.triggeredConditions, id: \.self) { condition in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.green)
                        .frame(width: 20)
                    
                    Text(condition)
                        .font(.system(size: 14))
                        .foregroundColor(DS.Adaptive.textSecondary)
                    
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
        )
    }
    
    // MARK: - Advisory Disclaimer
    
    private var advisoryDisclaimer: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 20))
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Advisory Only")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.orange)
                
                Text("This signal is for educational purposes. Use it as reference for your own analysis. Always do your own research before making trading decisions.")
                    .font(.system(size: 12))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Copy Signal Button
            Button {
                copySignalToClipboard()
            } label: {
                HStack {
                    Image(systemName: "doc.on.doc")
                    Text("Copy Signal Details")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(BrandColors.goldBase)
                )
            }
            
            // Share Button
            ShareLink(
                item: signal.generateShareableText(strategyName: strategyName, pair: tradingPair)
            ) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share Signal")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(BrandColors.goldBase)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(BrandColors.goldBase, lineWidth: 1.5)
                )
            }
        }
    }
    
    // MARK: - Copied Feedback Overlay
    
    private var copiedFeedbackOverlay: some View {
        VStack {
            Spacer()
            
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Signal copied to clipboard!")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.85))
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            
            Spacer().frame(height: 100)
        }
        .animation(.spring(response: 0.3), value: showCopiedFeedback)
    }
    
    // MARK: - Helpers
    
    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(DS.Adaptive.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(DS.Adaptive.textPrimary)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }
    
    private func copySignalToClipboard() {
        let text = signal.generateShareableText(strategyName: strategyName, pair: tradingPair)
        UIPasteboard.general.string = text
        
        // Show feedback
        withAnimation {
            showCopiedFeedback = true
        }
        
        // Hide after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopiedFeedback = false
            }
        }
        
        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}

// MARK: - Strategy Share Sheet

/// A sheet view for sharing complete strategy details
struct StrategyShareSheet: View {
    let strategy: TradingStrategy
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var showCopiedFeedback = false
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Strategy Header
                    strategyHeader
                    
                    // Configuration Summary
                    configurationCard
                    
                    // Entry Conditions
                    if !strategy.entryConditions.isEmpty {
                        conditionsCard(
                            title: "Entry Conditions",
                            icon: "arrow.down.circle.fill",
                            iconColor: .green,
                            conditions: strategy.entryConditions
                        )
                    }
                    
                    // Exit Conditions
                    if !strategy.exitConditions.isEmpty {
                        conditionsCard(
                            title: "Exit Conditions",
                            icon: "arrow.up.circle.fill",
                            iconColor: .red,
                            conditions: strategy.exitConditions
                        )
                    }
                    
                    // Risk Management
                    riskManagementCard
                    
                    // Advisory Disclaimer
                    advisoryDisclaimer
                    
                    // Action Buttons
                    actionButtons
                    
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(DS.Adaptive.background)
            .navigationTitle("Share Strategy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(BrandColors.goldBase)
                }
            }
            .overlay {
                if showCopiedFeedback {
                    copiedFeedbackOverlay
                }
            }
        }
    }
    
    // MARK: - Strategy Header
    
    private var strategyHeader: some View {
        VStack(spacing: 8) {
            Image(systemName: "function")
                .font(.system(size: 36))
                .foregroundColor(BrandColors.goldBase)
            
            Text(strategy.name)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(DS.Adaptive.textPrimary)
                .multilineTextAlignment(.center)
            
            if !strategy.description.isEmpty {
                Text(strategy.description)
                    .font(.system(size: 14))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 16)
    }
    
    // MARK: - Configuration Card
    
    private var configurationCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "gearshape.fill")
                    .foregroundColor(BrandColors.goldBase)
                Text("Configuration")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
            }
            
            Divider()
            
            configRow(label: "Trading Pair", value: strategy.tradingPair)
            configRow(label: "Timeframe", value: strategy.timeframe.displayName)
            configRow(label: "Logic", value: strategy.conditionLogic.displayName)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
        )
    }
    
    // MARK: - Conditions Card
    
    private func conditionsCard(
        title: String,
        icon: String,
        iconColor: Color,
        conditions: [StrategyCondition]
    ) -> some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("\(conditions.filter { $0.isEnabled }.count) active")
                    .font(.system(size: 12))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            Divider()
            
            ForEach(conditions) { condition in
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: condition.isEnabled ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(condition.isEnabled ? iconColor : DS.Adaptive.textTertiary)
                        .font(.system(size: 14))
                    
                    Text(condition.description)
                        .font(.system(size: 14))
                        .foregroundColor(condition.isEnabled ? DS.Adaptive.textSecondary : DS.Adaptive.textTertiary)
                    
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
        )
    }
    
    // MARK: - Risk Management Card
    
    private var riskManagementCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "shield.fill")
                    .foregroundColor(.blue)
                Text("Risk Management")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
            }
            
            Divider()
            
            if let sl = strategy.riskManagement.stopLossPercent {
                configRow(label: "Stop Loss", value: "\(String(format: "%.1f", sl))%")
            }
            if let tp = strategy.riskManagement.takeProfitPercent {
                configRow(label: "Take Profit", value: "\(String(format: "%.1f", tp))%")
            }
            if let ts = strategy.riskManagement.trailingStopPercent {
                configRow(label: "Trailing Stop", value: "\(String(format: "%.1f", ts))%")
            }
            if let rr = strategy.riskManagement.riskRewardRatio {
                configRow(label: "Risk/Reward", value: "1:\(String(format: "%.1f", rr))")
            }
            
            configRow(label: "Max Drawdown", value: "\(String(format: "%.0f", strategy.riskManagement.maxDrawdownPercent))%")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
        )
    }
    
    // MARK: - Advisory Disclaimer
    
    private var advisoryDisclaimer: some View {
        HStack(spacing: 12) {
            Image(systemName: "graduationcap.fill")
                .foregroundColor(.purple)
                .font(.system(size: 20))
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Educational Strategy")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.purple)
                
                Text("This strategy is shared for educational and advisory purposes. Test with paper trading before using real funds. Not financial advice.")
                    .font(.system(size: 12))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.purple.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Copy Strategy Button
            Button {
                copyStrategyToClipboard()
            } label: {
                HStack {
                    Image(systemName: "doc.on.doc")
                    Text("Copy Strategy Details")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(BrandColors.goldBase)
                )
            }
            
            // Share Button
            ShareLink(item: strategy.generateShareableText()) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share Strategy")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(BrandColors.goldBase)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(BrandColors.goldBase, lineWidth: 1.5)
                )
            }
            
            // Export JSON Button
            if let jsonExport = strategy.exportAsJSON() {
                ShareLink(
                    item: jsonExport,
                    subject: Text("CryptoSage Strategy: \(strategy.name)"),
                    message: Text("Strategy configuration exported from CryptoSage")
                ) {
                    HStack {
                        Image(systemName: "arrow.down.doc")
                        Text("Export as JSON")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func configRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(DS.Adaptive.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(DS.Adaptive.textPrimary)
        }
    }
    
    private var copiedFeedbackOverlay: some View {
        VStack {
            Spacer()
            
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Copied to clipboard!")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.85))
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            
            Spacer().frame(height: 100)
        }
        .animation(.spring(response: 0.3), value: showCopiedFeedback)
    }
    
    private func copyStrategyToClipboard() {
        let text = strategy.generateShareableText()
        UIPasteboard.general.string = text
        
        withAnimation {
            showCopiedFeedback = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopiedFeedback = false
            }
        }
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}

// MARK: - Preview

#Preview("Signal Share Sheet") {
    SignalShareSheet(
        signal: StrategySignal(
            strategyId: UUID(),
            type: .buy,
            price: 96250.50,
            confidence: 0.85,
            triggeredConditions: [
                "Price > SMA (200)",
                "RSI (14) > 50",
                "MACD Histogram > 0"
            ]
        ),
        strategyName: "Sage Trend Algorithm",
        tradingPair: "BTC_USDT"
    )
}
