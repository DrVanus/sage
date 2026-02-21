//
//  TradingModeSegmentedControl.swift
//  CryptoSage
//
//  Global trading mode switcher for the home screen.
//  Compact, premium design with gold-accented selected state.
//

import SwiftUI

// MARK: - App Mode Enum

/// The main modes of the app
enum AppTradingMode: String, CaseIterable, Identifiable {
    case portfolio = "Portfolio"  // Track holdings (no trading)
    case paper = "Paper"          // Virtual trading with $100K
    case liveTrading = "Live"     // Real trading (Developer mode only)
    case demo = "Demo"            // Sample data for exploring
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .portfolio: return "chart.pie.fill"
        case .paper: return "doc.text.fill"
        case .liveTrading: return "bolt.fill"
        case .demo: return "play.circle.fill"  // Distinct from AI "sparkles" icons
        }
    }
    
    var description: String {
        switch self {
        case .portfolio: return "Track real holdings"
        case .paper: return "Practice with $100K virtual"
        case .liveTrading: return "Execute real trades"
        case .demo: return "Explore with sample data"
        }
    }
    
    /// Mode colors — designed for clear visual separation across all modes:
    /// Green (portfolio) / Orange (paper) / Blue (demo) / Red (live)
    var color: Color {
        switch self {
        case .portfolio: return .green
        case .paper: return Color(red: 1.0, green: 0.55, blue: 0.0)   // Warm amber/orange
        case .liveTrading: return .red
        case .demo: return Color(red: 0.35, green: 0.62, blue: 1.0)   // Cornflower blue — distinct from brand gold
        }
    }
    
    var secondaryColor: Color {
        switch self {
        case .portfolio: return .cyan
        case .paper: return Color(red: 1.0, green: 0.65, blue: 0.15)  // Lighter amber
        case .liveTrading: return Color(red: 1.0, green: 0.4, blue: 0.4)  // Lighter red
        case .demo: return Color(red: 0.55, green: 0.75, blue: 1.0)   // Lighter blue
        }
    }
    
    /// Full display name for card headers and labels
    var displayName: String {
        switch self {
        case .portfolio: return "Portfolio"
        case .paper: return "Paper Trading"
        case .liveTrading: return "Live Trading"
        case .demo: return "Demo Portfolio"
        }
    }
    
    /// Short label for compact header toggle (4+ modes, e.g. developer mode)
    var compactLabel: String {
        switch self {
        case .portfolio: return "Portfolio"
        case .paper: return "Paper"
        case .liveTrading: return "Live"
        case .demo: return "Demo"
        }
    }
    
    /// Short uppercase label for compact badges
    var badgeLabel: String {
        switch self {
        case .portfolio: return "PORTFOLIO"
        case .paper: return "PAPER"
        case .liveTrading: return "LIVE"
        case .demo: return "DEMO"
        }
    }
}

// MARK: - Compact Trading Mode Control

/// A collapsible mode switcher with premium styling
/// - Expanded: Shows all mode buttons with swipe-to-hide
/// - Collapsed: Shows nothing (compact mode icon is in header bar)
struct TradingModeSegmentedControl: View {
    @ObservedObject private var paperTradingManager = PaperTradingManager.shared
    @ObservedObject private var demoModeManager = DemoModeManager.shared
    @Environment(\.colorScheme) private var colorScheme
    
    /// Persisted expanded/collapsed state
    @AppStorage("tradingModeSwitcherExpanded") private var isExpanded: Bool = true
    
    /// Current active mode based on manager states
    var currentMode: AppTradingMode {
        if paperTradingManager.isPaperTradingEnabled { return .paper }
        if demoModeManager.isDemoMode { return .demo }
        if isDeveloperMode && SubscriptionManager.shared.developerLiveTradingEnabled {
            return .liveTrading
        }
        return .portfolio
    }
    
    /// Check if user has connected exchange accounts
    private var hasConnectedAccounts: Bool {
        !ConnectedAccountsManager.shared.accounts.isEmpty
    }
    
    /// Check if developer mode is active
    private var isDeveloperMode: Bool {
        SubscriptionManager.shared.isDeveloperMode
    }
    
    private var isDark: Bool { colorScheme == .dark }
    
    /// Available modes based on user state
    var availableModes: [AppTradingMode] {
        var modes: [AppTradingMode] = [.portfolio, .paper]
        
        // Demo available for developers + regular users without connected accounts
        if isDeveloperMode || !hasConnectedAccounts {
            modes.append(.demo)
        }
        
        // Live Trading only for developers (real money execution)
        if isDeveloperMode {
            modes.append(.liveTrading)
        }
        
        return modes
    }
    
    var body: some View {
        // Only show when expanded - when collapsed, the mode icon is in the header bar
        if isExpanded {
            VStack(spacing: 0) {
                // Mode buttons row
                HStack(spacing: 4) {
                    ForEach(availableModes) { mode in
                        modeButton(for: mode)
                    }
                }
                .padding(2)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(isDark ? 0.06 : 0.35), Color.white.opacity(0)],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            LinearGradient(
                                colors: isDark
                                    ? [Color.white.opacity(0.12), Color.white.opacity(0.04)]
                                    : [Color.black.opacity(0.08), Color.black.opacity(0.02)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                )
                
                // Minimal drag handle - just a subtle pill
                dragHandle
            }
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onEnded { value in
                        let verticalDominant = abs(value.translation.height) > abs(value.translation.width)
                        // Swipe up to hide - generous threshold
                        if verticalDominant && value.translation.height < -15 {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isExpanded = false
                            }
                        }
                    }
            )
            .sheet(isPresented: $showUpgradeSheet) {
                UnifiedPaywallSheet(feature: .paperTrading)
            }
        }
    }
    
    // MARK: - Drag Handle (minimal chevron only)
    
    private var dragHandle: some View {
        Image(systemName: "chevron.compact.up")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(isDark ? Color.white.opacity(0.3) : Color.black.opacity(0.2))
            .frame(maxWidth: .infinity)
            .frame(height: 20)
            .contentShape(Rectangle())
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded = false
                }
            }
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onEnded { value in
                        if value.translation.height < -10 {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isExpanded = false
                            }
                        }
                    }
            )
    }
    
    // MARK: - Mode Button
    
    @State private var showUpgradeSheet = false
    
    @ViewBuilder
    private func modeButton(for mode: AppTradingMode) -> some View {
        let isSelected = currentMode == mode
        let isLocked = mode == .paper && !paperTradingManager.hasAccess
        
        Button {
            if isLocked {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showUpgradeSheet = true
            } else {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    selectMode(mode)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: mode.icon)
                    .font(.system(size: 11, weight: .semibold))
                
                Text(mode.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: isDark ? [BrandColors.goldLight, BrandColors.goldBase] : [BrandColors.silverBase, BrandColors.silverDark],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
            .foregroundColor(isSelected ? (isDark ? .white : .black) : (isLocked ? .secondary.opacity(0.35) : .secondary.opacity(0.7)))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                ZStack {
                    if isSelected {
                        // Premium selected state - high-tech look
                        // Base gradient fill
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                LinearGradient(
                                    colors: isDark ? [
                                        mode.color.opacity(0.28),
                                        mode.color.opacity(0.18),
                                        mode.color.opacity(0.12)
                                    ] : [
                                        mode.color.opacity(0.22),
                                        mode.color.opacity(0.15),
                                        mode.color.opacity(0.10)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        
                        // Outer glow ring
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        mode.color.opacity(isDark ? 0.9 : 0.7),
                                        mode.color.opacity(isDark ? 0.6 : 0.45),
                                        mode.color.opacity(isDark ? 0.4 : 0.3)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1.5
                            )
                        
                        // Inner glass highlight
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isDark ? 0.25 : 0.5),
                                        Color.white.opacity(isDark ? 0.08 : 0.15),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .center
                                ),
                                lineWidth: 0.75
                            )
                            .padding(1.5)
                        
                        // Top shine accent
                        RoundedRectangle(cornerRadius: 9)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isDark ? 0.12 : 0.25),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: UnitPoint(x: 0.5, y: 0.4)
                                )
                            )
                            .padding(2)
                    } else {
                        // Unselected: subtle glass for depth
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(isDark ? 0.03 : 0.2), Color.white.opacity(0)],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    }
                }
            )
            // Glow shadow for selected
        }
        .buttonStyle(ModeButtonStyle())
    }
    
    // MARK: - Mode Selection Logic
    
    private func selectMode(_ mode: AppTradingMode) {
        DispatchQueue.main.async {
            switch mode {
            case .portfolio:
                self.paperTradingManager.disablePaperTrading()
                self.demoModeManager.disableDemoMode()
                if self.isDeveloperMode {
                    SubscriptionManager.shared.developerLiveTradingEnabled = false
                }
            case .paper:
                self.demoModeManager.disableDemoMode()
                _ = self.paperTradingManager.enablePaperTrading()
                if self.isDeveloperMode {
                    SubscriptionManager.shared.developerLiveTradingEnabled = false
                }
            case .liveTrading:
                self.paperTradingManager.disablePaperTrading()
                self.demoModeManager.disableDemoMode()
                SubscriptionManager.shared.developerLiveTradingEnabled = true
            case .demo:
                self.paperTradingManager.disablePaperTrading()
                self.demoModeManager.enableDemoMode()
                if self.isDeveloperMode {
                    SubscriptionManager.shared.developerLiveTradingEnabled = false
                }
            }
        }
    }
}

// MARK: - Mode Button Style (subtle press feedback)

private struct ModeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Inline Mode Pill (DEPRECATED - kept for compatibility, returns EmptyView)

/// No longer needed since mode switcher is always visible and compact
struct InlineTradingModePill: View {
    var body: some View {
        // Return empty - mode is shown in the always-visible switcher above
        EmptyView()
    }
}

// MARK: - Compact Mode Indicator (non-interactive, for other sections)

/// A small, non-interactive indicator showing the current mode.
/// Uses the shared ModeBadge for consistent styling across the app.
/// Use this in section headers where you want to show mode but not allow switching.
struct TradingModeIndicator: View {
    @ObservedObject private var paperTradingManager = PaperTradingManager.shared
    @ObservedObject private var demoModeManager = DemoModeManager.shared
    
    private var isDeveloperMode: Bool {
        SubscriptionManager.shared.isDeveloperMode
    }
    
    var currentMode: AppTradingMode {
        if paperTradingManager.isPaperTradingEnabled { return .paper }
        if demoModeManager.isDemoMode { return .demo }
        if isDeveloperMode && SubscriptionManager.shared.developerLiveTradingEnabled {
            return .liveTrading
        }
        return .portfolio
    }
    
    /// Only show indicator when NOT in portfolio mode (real data)
    var shouldShow: Bool {
        currentMode != .portfolio
    }
    
    var body: some View {
        if shouldShow {
            ModeBadge(mode: currentMode, variant: .compact)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        Text("Compact Mode Switcher")
            .font(.caption)
            .foregroundColor(.secondary)
        
        TradingModeSegmentedControl()
        
        Divider()
        
        HStack {
            Text("Mode indicator (for other sections):")
                .font(.caption)
                .foregroundColor(.secondary)
            TradingModeIndicator()
            Spacer()
        }
        .padding(.horizontal)
        
        Spacer()
    }
    .padding(.vertical)
    .background(DS.Adaptive.background)
    .preferredColorScheme(.dark)
}
