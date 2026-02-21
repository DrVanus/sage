//
//  MyBotsWidget.swift
//  CryptoSage
//
//  A compact widget for displaying bot status summary on the Portfolio page.
//  Shows running/stopped counts, total P&L, and navigates to BotHubView.
//  Supports Demo Mode, Paper Trading, and Live Trading modes.
//

import SwiftUI

// MARK: - My Bots Widget

/// A compact widget that displays bot status summary and links to bot management
struct MyBotsWidget: View {
    // Bot managers
    @ObservedObject private var paperBotManager = PaperBotManager.shared
    @ObservedObject private var liveBotManager = LiveBotManager.shared
    @ObservedObject private var paperTradingManager = PaperTradingManager.shared
    @ObservedObject private var demoModeManager = DemoModeManager.shared
    @Environment(\.colorScheme) private var colorScheme
    
    // Animation state
    @State private var pulseAnimation: Bool = false
    
    private var isDark: Bool { colorScheme == .dark }
    
    // MARK: - Current Mode
    
    private enum TradingMode {
        case demo
        case paper
        case live
        
        var badgeText: String {
            switch self {
            case .demo: return "DEMO"
            case .paper: return "PAPER"
            case .live: return "LIVE"
            }
        }
        
        var badgeColor: Color {
            switch self {
            case .demo: return BrandColors.goldBase
            case .paper: return AppTradingMode.paper.color
            case .live: return .green
            }
        }
    }
    
    private var currentMode: TradingMode {
        if demoModeManager.isDemoMode {
            return .demo
        } else if paperTradingManager.isPaperTradingEnabled {
            return .paper
        } else {
            return .live
        }
    }
    
    // MARK: - Mode-Aware Computed Properties
    
    private var totalBots: Int {
        switch currentMode {
        case .demo:
            return paperBotManager.demoBotCount
        case .paper:
            return paperBotManager.totalBotCount
        case .live:
            return liveBotManager.totalBotCount
        }
    }
    
    private var runningBots: Int {
        switch currentMode {
        case .demo:
            return paperBotManager.runningDemoBotCount
        case .paper:
            return paperBotManager.runningBotCount
        case .live:
            return liveBotManager.enabledBotCount
        }
    }
    
    private var stoppedBots: Int {
        totalBots - runningBots
    }
    
    private var hasRunningBots: Bool {
        runningBots > 0
    }
    
    // Total profit/loss (mode-aware)
    private var totalProfitLoss: Double {
        switch currentMode {
        case .demo:
            return paperBotManager.totalDemoBotProfit
        case .paper:
            return paperBotManager.paperBots.reduce(0) { $0 + $1.totalProfit }
        case .live:
            // Sum P/L from all live 3Commas bots
            return liveBotManager.totalProfitUsd
        }
    }
    
    // Whether to show profit/loss
    private var showProfitLoss: Bool {
        // Show P/L when there are bots and we have data
        // For live mode, only show if 3Commas is configured and we have bots
        if currentMode == .live {
            return totalBots > 0 && liveBotManager.isConfigured
        }
        return totalBots > 0
    }
    
    var body: some View {
        NavigationLink(destination: BotHubView()) {
            HStack(spacing: 12) {
                // Icon with status indicator
                botIconView
                
                // Info section
                VStack(alignment: .leading, spacing: 3) {
                    // Title with mode badge and running count
                    HStack(spacing: 6) {
                        Text("My Bots")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        // Mode badge
                        HStack(spacing: 3) {
                            if currentMode == .demo {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 7, weight: .bold))
                            }
                            Text(currentMode.badgeText)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(currentMode.badgeColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(currentMode.badgeColor.opacity(0.15))
                        )
                        
                        // Running count badge
                        if runningBots > 0 {
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                                    .scaleEffect(pulseAnimation ? 1.3 : 1.0)
                                
                                Text("\(runningBots)")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundColor(.green)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.green.opacity(0.15)))
                        }
                    }
                    
                    // Status text
                    Text(statusText)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                
                Spacer()
                
                // Right side: P&L and chevron in horizontal layout
                HStack(spacing: 8) {
                    if showProfitLoss {
                        Text(formatProfitLoss(totalProfitLoss))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(totalProfitLoss >= 0 ? .green : .red)
                    }
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
            }
            .padding(14)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isDark ? Color.white.opacity(0.05) : DS.Adaptive.cardBackground)
                    
                    // Top highlight for glass effect
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    isDark ? Color.white.opacity(0.06) : Color.white.opacity(0.5),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        hasRunningBots ? Color.green.opacity(0.3) : (isDark ? Color.white.opacity(0.08) : DS.Adaptive.stroke),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .onAppear {
            // Seed demo bots if in demo mode
            if demoModeManager.isDemoMode {
                paperBotManager.seedDemoBots()
            }
            
            if hasRunningBots {
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                    pulseAnimation = true
                }
            }
        }
    }
    
    // MARK: - Bot Icon View
    
    private var botIconView: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    hasRunningBots
                        ? LinearGradient(colors: [Color.green.opacity(0.15), Color.green.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: isDark ? [Color.white.opacity(0.05), Color.white.opacity(0.03)] : [DS.Adaptive.chipBackground, DS.Adaptive.chipBackground.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 44, height: 44)
            
            // Bot icon
            Image(systemName: "cpu")
                .font(.system(size: 18))
                .foregroundStyle(
                    hasRunningBots
                        ? LinearGradient(colors: [Color.green, Color.green.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                        : LinearGradient(colors: [Color.gray, Color.gray.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                )
            
            // Running indicator dot
            if hasRunningBots {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(Color.black, lineWidth: 2)
                    )
                    .offset(x: 14, y: -14)
            }
        }
    }
    
    // MARK: - Status Text
    
    private var statusText: String {
        if totalBots == 0 {
            if currentMode == .demo {
                return "View sample bots"
            }
            return "No bots created yet"
        } else if runningBots == 0 {
            let prefix = currentMode == .demo ? "Sample: " : ""
            return "\(prefix)\(totalBots) bot\(totalBots == 1 ? "" : "s") • All stopped"
        } else if stoppedBots == 0 {
            let prefix = currentMode == .demo ? "Sample: " : ""
            return "\(prefix)\(runningBots) running"
        } else {
            let prefix = currentMode == .demo ? "Sample: " : ""
            return "\(prefix)\(runningBots) running, \(stoppedBots) stopped"
        }
    }
    
    // MARK: - Helpers
    
    private func formatProfitLoss(_ value: Double) -> String {
        let prefix = value >= 0 ? "+" : ""
        if abs(value) >= 1000 {
            return "\(prefix)$\(String(format: "%.1fK", value / 1000))"
        } else {
            return "\(prefix)$\(String(format: "%.2f", value))"
        }
    }
}

// MARK: - Compact Bots Preview Widget

/// A smaller variant for tight spaces
struct CompactBotsWidget: View {
    @ObservedObject private var paperBotManager = PaperBotManager.shared
    @ObservedObject private var liveBotManager = LiveBotManager.shared
    @ObservedObject private var paperTradingManager = PaperTradingManager.shared
    @ObservedObject private var demoModeManager = DemoModeManager.shared
    
    private var isDemoMode: Bool {
        demoModeManager.isDemoMode
    }
    
    private var isPaperMode: Bool {
        paperTradingManager.isPaperTradingEnabled
    }
    
    private var runningBots: Int {
        if isDemoMode {
            return paperBotManager.runningDemoBotCount
        }
        return isPaperMode ? paperBotManager.runningBotCount : liveBotManager.enabledBotCount
    }
    
    private var totalBots: Int {
        if isDemoMode {
            return paperBotManager.demoBotCount
        }
        return isPaperMode ? paperBotManager.totalBotCount : liveBotManager.totalBotCount
    }
    
    var body: some View {
        NavigationLink(destination: BotHubView()) {
            HStack(spacing: 8) {
                Image(systemName: isDemoMode ? "sparkles" : "cpu")
                    .font(.system(size: 14))
                    .foregroundColor(isDemoMode ? BrandColors.goldBase : (runningBots > 0 ? .green : .gray))
                
                if totalBots > 0 {
                    Text("\(runningBots)/\(totalBots)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                    
                    if runningBots > 0 {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                    }
                } else {
                    Text(isDemoMode ? "Demo bots" : "No bots")
                        .font(.system(size: 12))
                        .foregroundColor(isDemoMode ? BrandColors.goldBase : .gray)
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
        .onAppear {
            if isDemoMode {
                paperBotManager.seedDemoBots()
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct MyBotsWidget_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            MyBotsWidget()
            
            CompactBotsWidget()
        }
        .padding()
        .background(Color.black)
        .previewLayout(.sizeThatFits)
    }
}
#endif
