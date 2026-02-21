//
//  EmptyStateViews.swift
//  CryptoSage
//
//  Empty state views shown when demo mode is OFF and no real data exists.
//  Also includes demo mode indicator badge.
//

import SwiftUI
import Combine

// MARK: - Shimmer Button Effect
/// A shimmer overlay effect for buttons that creates a sweeping light animation
struct ShimmerButtonOverlay: View {
    @State private var shimmerOffset: CGFloat = -200
    @State private var shouldRunAnimation: Bool = false
    let isAnimating: Bool
    
    init(isAnimating: Bool = true) {
        self.isAnimating = isAnimating
    }
    
    var body: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [.clear, .white.opacity(0.35), .white.opacity(0.5), .white.opacity(0.35), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 80)
            .offset(x: shimmerOffset)
            .onAppear {
                if isAnimating {
                    // Initial delay before starting the animation loop
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
                        shouldRunAnimation = true
                        withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                            shimmerOffset = geo.size.width + 100
                        }
                    }
                }
            }
            .onReceive(ScrollStateManager.shared.$isScrolling.removeDuplicates()) { scrolling in
                if scrolling {
                    // Pause animation by resetting offset (kills the repeatForever)
                    shimmerOffset = -200
                    shouldRunAnimation = false
                } else if isAnimating && !shouldRunAnimation {
                    // Restart animation after settling period
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
                        shimmerOffset = -200
                        shouldRunAnimation = true
                        withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                            shimmerOffset = geo.size.width + 100
                        }
                    }
                }
            }
        }
        .mask(Capsule())
        .allowsHitTesting(false)
    }
}

// MARK: - Pulsing Sparkle Effect
/// A subtle pulsing glow effect for secondary buttons
struct PulsingGlowEffect: View {
    @State private var isPulsing = false
    let color: Color
    
    var body: some View {
        Capsule()
            .stroke(color.opacity(isPulsing ? 0.6 : 0.25), lineWidth: 2)
            .scaleEffect(isPulsing ? 1.02 : 1.0)
            .scrollAwarePulse(active: $isPulsing, duration: 1.5)
    }
}

// MARK: - Sparkle Icon Animation
/// An animated sparkle icon that pulses
struct AnimatedSparkleIcon: View {
    @State private var isAnimating = false
    let size: CGFloat
    let color: Color
    
    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.2))
                .frame(width: size, height: size)
            
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundColor(color)
                .scaleEffect(isAnimating ? 1.15 : 0.95)
                .opacity(isAnimating ? 1.0 : 0.7)
        }
        .scrollAwarePulse(active: $isAnimating, duration: 1.2)
    }
}

// Note: ScaleButtonStyle is defined in PortfolioView.swift and shared across the app

// MARK: - Unified Trading Mode Badge

/// Represents the different trading modes for badge display
enum TradingModeDisplay: String, CaseIterable {
    case paper = "PAPER"
    case demo = "DEMO"
    case portfolio = "PORTFOLIO"  // Renamed from "live" for clarity
    
    // Legacy alias for backward compatibility
    static var live: TradingModeDisplay { .portfolio }
    
    var badgeText: String { rawValue }
    
    var dotColor: Color {
        switch self {
        case .paper: return AppTradingMode.paper.color  // Warm amber (consistent across app)
        case .demo: return AppTradingMode.demo.color     // Gold (single source of truth)
        case .portfolio: return AppTradingMode.portfolio.color
        }
    }
    
    var icon: String {
        switch self {
        case .paper: return AppTradingMode.paper.icon
        case .demo: return AppTradingMode.demo.icon   // play.circle.fill — distinct from AI sparkles
        case .portfolio: return AppTradingMode.portfolio.icon
        }
    }
    
    var displayName: String {
        switch self {
        case .paper: return "Paper Trading"
        case .demo: return "Demo Mode"
        case .portfolio: return "Portfolio"
        }
    }
    
    var iconName: String { icon }
}

/// A unified trading mode badge that provides consistent styling across Paper, Demo, and Live modes.
/// Use this instead of individual DemoModeBadge or PaperTradingModeBadge for consistency.
struct TradingModeBadge: View {
    let mode: TradingModeDisplay
    var onTap: (() -> Void)? = nil
    
    @Environment(\.colorScheme) private var colorScheme
    
    // MARK: - Paper Trading Colors
    private let paperOrange = AppTradingMode.paper.color  // Warm amber (distinct from gold brand)
    private let paperPurple = Color.purple
    
    // MARK: - Demo Mode Colors (Gold theme)
    private var demoTextColor: Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.98, green: 0.82, blue: 0.20, alpha: 1.0) // Gold #FABE33
                : UIColor(red: 0.55, green: 0.42, blue: 0.05, alpha: 1.0) // Dark amber #8C6B0D
        })
    }
    
    private var demoBackgroundColor: Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.98, green: 0.82, blue: 0.20, alpha: 0.15)
                : UIColor(red: 0.55, green: 0.42, blue: 0.05, alpha: 0.12)
        })
    }
    
    private var demoStrokeColors: [Color] {
        colorScheme == .dark
            ? [Color(red: 0.98, green: 0.82, blue: 0.20).opacity(0.6), Color(red: 0.98, green: 0.82, blue: 0.20).opacity(0.3)]
            : [Color(red: 0.55, green: 0.42, blue: 0.05).opacity(0.4), Color(red: 0.55, green: 0.42, blue: 0.05).opacity(0.2)]
    }
    
    // MARK: - Portfolio Mode Colors (Green theme)
    private let portfolioGreen = Color.green
    
    // MARK: - Computed Properties
    
    private var textColor: Color {
        switch mode {
        case .paper: return paperOrange
        case .demo: return demoTextColor
        case .portfolio: return portfolioGreen
        }
    }
    
    private var backgroundFill: some ShapeStyle {
        switch mode {
        case .paper:
            return AnyShapeStyle(LinearGradient(
                colors: [paperOrange.opacity(0.15), paperPurple.opacity(0.15)],
                startPoint: .leading,
                endPoint: .trailing
            ))
        case .demo:
            return AnyShapeStyle(demoBackgroundColor)
        case .portfolio:
            return AnyShapeStyle(portfolioGreen.opacity(0.15))
        }
    }
    
    private var strokeGradient: LinearGradient {
        switch mode {
        case .paper:
            return LinearGradient(
                colors: [paperOrange.opacity(0.6), paperPurple.opacity(0.4)],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .demo:
            return LinearGradient(
                colors: demoStrokeColors,
                startPoint: .leading,
                endPoint: .trailing
            )
        case .portfolio:
            return LinearGradient(
                colors: [portfolioGreen.opacity(0.6), portfolioGreen.opacity(0.3)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
    
    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 6) {
                // Colored indicator dot with subtle glow
                ZStack {
                    Circle()
                        .fill(mode.dotColor.opacity(0.4))
                        .frame(width: 10, height: 10)
                    Circle()
                        .fill(mode.dotColor)
                        .frame(width: 6, height: 6)
                }
                
                Text(mode.badgeText)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(textColor)
            }
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                ZStack {
                    Capsule()
                        .fill(backgroundFill)
                    // Glass top shine — consistent with ModeBadge
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(colorScheme == .dark ? 0.04 : 0.12), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
                .overlay(
                    Capsule()
                        .stroke(strokeGradient, lineWidth: colorScheme == .dark ? 1 : 1.2)
                )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Unified ModeBadge (shared across Home + Portfolio)

/// Rendering variant for ModeBadge
enum ModeBadgeVariant {
    /// Small capsule pill: colored dot + uppercase short label (e.g. "PAPER")
    /// Ideal for inline use next to "Total Value" or section headers
    case compact
    /// Larger capsule pill: icon + full display name (e.g. "Paper Trading")
    /// Ideal for card header labels above the balance
    case label
}

/// A single, shared mode badge used across both the Home portfolio card and the
/// Portfolio tab to ensure a fully consistent look. All mode colors are sourced
/// from `AppTradingMode.color` (single source of truth).
///
/// Usage:
/// ```
/// ModeBadge(mode: .paper, variant: .label)          // "Paper Trading" with icon
/// ModeBadge(mode: .demo, variant: .compact)          // "DEMO" with dot
/// ModeBadge(mode: .paper, variant: .compact) { ... } // tappable
/// ```
struct ModeBadge: View {
    let mode: AppTradingMode
    var variant: ModeBadgeVariant = .compact
    var onTap: (() -> Void)? = nil
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    private var modeColor: Color { mode.color }
    
    var body: some View {
        if let action = onTap {
            Button(action: action) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }
    
    @ViewBuilder
    private var content: some View {
        HStack(spacing: variant == .compact ? 4 : 5) {
            switch variant {
            case .compact:
                // Glowing colored dot
                Circle()
                    .fill(modeColor)
                    .frame(width: 5, height: 5)
                
                Text(mode.badgeLabel)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                
            case .label:
                // Mode icon with glow
                Image(systemName: mode.icon)
                    .font(.system(size: 10, weight: .semibold))
                
                Text(mode.displayName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
        }
        .foregroundColor(modeColor)
        .padding(.horizontal, variant == .compact ? 7 : 9)
        .padding(.vertical, variant == .compact ? 3 : 4)
        .background(
            ZStack {
                // Base tinted fill
                Capsule()
                    .fill(modeColor.opacity(isDark ? 0.12 : 0.07))
                // Glass top shine
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(isDark ? 0.04 : 0.12), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            }
        )
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [
                            modeColor.opacity(isDark ? 0.35 : 0.22),
                            modeColor.opacity(isDark ? 0.12 : 0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isDark ? 0.5 : 0.8
                )
        )
    }
}

// MARK: - Demo Mode Badge (Legacy wrapper - uses TradingModeBadge internally)
/// A small pill indicator that shows when demo mode is active.
/// Tappable to show options for exiting demo mode.
/// Note: Consider using TradingModeBadge(mode: .demo) directly for new code.
struct DemoModeBadge: View {
    var onTap: (() -> Void)? = nil
    
    var body: some View {
        TradingModeBadge(mode: .demo, onTap: onTap)
    }
}

// MARK: - Paper Trading Mode Badge (Legacy wrapper - uses TradingModeBadge internally)
/// A small pill indicator that shows when paper trading mode is active.
/// Tappable to show options for exiting paper trading mode.
/// Note: Consider using TradingModeBadge(mode: .paper) directly for new code.
struct PaperTradingModeBadge: View {
    var onTap: (() -> Void)? = nil
    
    var body: some View {
        TradingModeBadge(mode: .paper, onTap: onTap)
    }
}

// MARK: - Paper Trading Mode Badge (Legacy implementation - kept for reference)
/// Original implementation preserved for backwards compatibility during transition
private struct _LegacyPaperTradingModeBadge: View {
    var onTap: (() -> Void)? = nil
    
    private let paperColor = AppTradingMode.paper.color  // Warm amber
    private let paperPurple = Color.purple
    
    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 5) {
                // Static orange indicator dot (no animation to avoid visual distraction)
                Circle()
                    .fill(paperColor)
                    .frame(width: 6, height: 6)
                
                Text("PAPER")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(paperColor)
            }
            .fixedSize() // Prevent layout recalculations
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [paperColor.opacity(0.15), paperPurple.opacity(0.15)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        paperColor.opacity(0.6),
                                        paperPurple.opacity(0.4)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

/// A larger demo mode indicator with more details
struct DemoModeIndicatorCard: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let onExitDemo: () -> Void
    let onGoToSettings: () -> Void
    
    private let goldBase = Color(red: 0.98, green: 0.82, blue: 0.20)
    // Darker gold for light mode text contrast
    private let goldDark = Color(red: 0.70, green: 0.55, blue: 0.10)
    
    var body: some View {
        let isDark = colorScheme == .dark
        
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(isDark ? goldBase.opacity(0.2) : goldBase.opacity(0.25))
                    .frame(width: 36, height: 36)
                
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isDark ? goldBase : goldDark)
            }
            
            // Text - adaptive colors with better contrast
            VStack(alignment: .leading, spacing: 2) {
                Text("Demo Mode Active")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isDark ? DS.Adaptive.textPrimary : goldDark)
                
                Text("Using sample portfolio data")
                    .font(.system(size: 11))
                    .foregroundColor(isDark ? DS.Adaptive.textSecondary : goldDark.opacity(0.8))
            }
            
            Spacer()
            
            // Exit button - adaptive colors
            Button(action: onExitDemo) {
                Text("Exit")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isDark ? .white.opacity(0.8) : goldDark)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(isDark ? Color.white.opacity(0.1) : goldBase.opacity(0.25))
                            .overlay(
                                Capsule()
                                    .stroke(isDark ? Color.white.opacity(0.2) : goldDark.opacity(0.35), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isDark ? goldBase.opacity(0.08) : goldBase.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isDark ? goldBase.opacity(0.25) : goldDark.opacity(0.30), lineWidth: 1)
                )
        )
    }
}

// MARK: - Compact Demo Mode Strip

/// A compact, single-line demo mode indicator optimized for the trading screen.
/// Shows demo status with minimal vertical footprint (~36px vs ~80px for the full card).
struct CompactDemoModeStrip: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var onExit: (() -> Void)?
    
    private let goldBase = Color(red: 0.98, green: 0.82, blue: 0.20)
    private let goldDark = Color(red: 0.70, green: 0.55, blue: 0.10)
    
    var body: some View {
        let isDark = colorScheme == .dark
        let textColor = isDark ? goldBase : goldDark
        
        HStack(spacing: 12) {
            // Left: Demo icon + status
            HStack(spacing: 8) {
                // Demo mode icon
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(textColor)
                
                // Status text
                Text("Demo Mode")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.Adaptive.textSecondary)
                
                Text("Sample data")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(textColor.opacity(0.8))
            }
            
            Spacer()
            
            // Right: Exit button
            Button(action: { onExit?() }) {
                Text("Exit")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isDark ? .white.opacity(0.8) : goldDark)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        ZStack {
                            Capsule()
                                .fill(isDark ? Color.white.opacity(0.08) : goldBase.opacity(0.2))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(isDark ? 0.08 : 0.3), Color.white.opacity(0)],
                                        startPoint: .top,
                                        endPoint: .center
                                    )
                                )
                        }
                    )
                    .overlay(
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: isDark
                                        ? [Color.white.opacity(0.2), Color.white.opacity(0.06)]
                                        : [goldDark.opacity(0.35), goldDark.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.5
                            )
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isDark ? goldBase.opacity(0.06) : goldBase.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isDark ? goldBase.opacity(0.2) : goldDark.opacity(0.25), lineWidth: 1)
                )
        )
    }
}

// MARK: - Compact Exchange Connection Strip

/// A compact, single-line prompt to connect an exchange for the trading screen.
/// Minimal vertical footprint while still providing clear call-to-action.
struct CompactExchangeConnectionStrip: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        let isDark = colorScheme == .dark
        let goldBase = BrandColors.goldBase
        let goldDark = BrandColors.goldDark
        let goldAccent = isDark
            ? LinearGradient(colors: [BrandColors.goldLight, goldBase], startPoint: .leading, endPoint: .trailing)
            : LinearGradient(colors: [goldBase, goldDark], startPoint: .leading, endPoint: .trailing)
        
        HStack(spacing: 10) {
            // Left: Icon + text
            HStack(spacing: 8) {
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(goldAccent)
                
                Text("Connect exchange to view portfolio")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            
            Spacer()
            
            // Right: Connect button
            NavigationLink {
                PortfolioPaymentMethodsView()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                    Text("Connect")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(isDark ? .white : goldDark)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    ZStack {
                        Capsule()
                            .fill(isDark ? Color.white.opacity(0.08) : goldBase.opacity(0.2))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(isDark ? 0.08 : 0.3), Color.white.opacity(0)],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    }
                )
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: isDark
                                    ? [BrandColors.goldLight.opacity(0.3), goldBase.opacity(0.1)]
                                    : [goldBase.opacity(0.4), goldBase.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(goldBase.opacity(isDark ? 0.2 : 0.25), lineWidth: 1)
                )
        )
    }
}

// MARK: - Reusable Empty State Container
struct EmptyStateView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let icon: String
    let title: String
    let subtitle: String
    let actionTitle: String?
    let action: (() -> Void)?
    
    init(
        icon: String,
        title: String,
        subtitle: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.action = action
    }
    
    private var isDark: Bool { colorScheme == .dark }
    private var goldLight: Color { BrandColors.goldLight }
    private var goldBase: Color { BrandColors.goldBase }
    
    private var goldAccent: LinearGradient {
        isDark
            ? LinearGradient(colors: [goldLight, goldBase], startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [goldBase, BrandColors.goldDark], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Icon with gradient background - adaptive colors
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: isDark
                                ? [Color.gray.opacity(0.15), Color.gray.opacity(0.05)]
                                : [Color.gray.opacity(0.12), Color.gray.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: icon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: isDark
                                ? [Color.white.opacity(0.9), Color.white.opacity(0.6)]
                                : [Color.black.opacity(0.7), Color.black.opacity(0.5)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            
            // Title - adaptive text color
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
                .multilineTextAlignment(.center)
            
            // Subtitle - adaptive secondary text color
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundColor(DS.Adaptive.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 24)
            
            // Action button (if provided) - premium glass style
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    HStack(spacing: 8) {
                        Text(actionTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(goldAccent.opacity(0.7))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
                    .background(
                        ZStack {
                            Capsule()
                                .fill(
                                    RadialGradient(
                                        colors: isDark
                                            ? [goldBase.opacity(0.1), Color.white.opacity(0.05)]
                                            : [goldBase.opacity(0.06), Color.black.opacity(0.02)],
                                        center: .top,
                                        startRadius: 0,
                                        endRadius: 50
                                    )
                                )
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(isDark ? 0.1 : 0.45), Color.white.opacity(0)],
                                        startPoint: .top,
                                        endPoint: .center
                                    )
                                )
                        }
                    )
                    .overlay(
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: isDark
                                        ? [goldLight.opacity(0.4), goldBase.opacity(0.15)]
                                        : [goldBase.opacity(0.3), goldBase.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .padding(.vertical, 40)
    }
}

// MARK: - Portfolio Empty State
struct PortfolioEmptyStateView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showUpgradeSheet = false
    
    let onConnectExchange: () -> Void
    let onEnableDemo: () -> Void
    var onEnablePaperTrading: (() -> Void)? = nil
    var onImportCSV: (() -> Void)? = nil
    
    private var isDark: Bool { colorScheme == .dark }
    private var goldLight: Color { BrandColors.goldLight }
    private var goldBase: Color { BrandColors.goldBase }
    
    private var goldAccent: LinearGradient {
        isDark
            ? LinearGradient(colors: [goldLight, goldBase], startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [goldBase, BrandColors.goldDark], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    private var hasPaperTradingAccess: Bool {
        subscriptionManager.hasAccess(to: .paperTrading)
    }
    
    /// Demo mode is only available for users without connected accounts
    private var canShowDemoOption: Bool {
        ConnectedAccountsManager.shared.accounts.isEmpty
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Premium icon with animated ring
            ZStack {
                // Outer subtle ring
                Circle()
                    .stroke(goldBase.opacity(0.15), lineWidth: 1)
                    .frame(width: 88, height: 88)
                
                // Background circle
                Circle()
                    .fill(
                        RadialGradient(
                            colors: isDark
                                ? [goldBase.opacity(0.12), goldBase.opacity(0.04)]
                                : [goldBase.opacity(0.10), goldBase.opacity(0.03)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 44
                        )
                    )
                    .frame(width: 76, height: 76)
                
                // Icon
                Image(systemName: "chart.pie")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(goldAccent)
            }
            
            // Title and subtitle - tighter spacing
            VStack(spacing: 8) {
                Text("No Portfolio Data")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text("Connect an exchange to sync your holdings, or try one of the practice modes below.")
                    .font(.system(size: 14))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            
            // Action buttons - compact and polished
            VStack(spacing: 10) {
                // Primary: Connect Exchange - premium glass style
                Button(action: onConnectExchange) {
                    HStack(spacing: 10) {
                        Image(systemName: "link.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(goldAccent)
                        
                        Text("Connect Exchange")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(goldAccent.opacity(0.7))
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 14)
                    .padding(.vertical, 12)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    RadialGradient(
                                        colors: isDark
                                            ? [goldBase.opacity(0.08), Color.white.opacity(0.04)]
                                            : [goldBase.opacity(0.05), Color.black.opacity(0.02)],
                                        center: .topLeading,
                                        startRadius: 0,
                                        endRadius: 120
                                    )
                                )
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(isDark ? 0.1 : 0.45), Color.white.opacity(0)],
                                        startPoint: .top,
                                        endPoint: .center
                                    )
                                )
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: isDark
                                        ? [goldLight.opacity(0.4), goldBase.opacity(0.15), DS.Adaptive.stroke.opacity(0.3)]
                                        : [goldBase.opacity(0.3), goldBase.opacity(0.1), DS.Adaptive.stroke.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(LinearGradient(colors: [goldLight.opacity(isDark ? 0.8 : 0.7), goldBase.opacity(isDark ? 0.6 : 0.5)], startPoint: .top, endPoint: .bottom))
                            .frame(width: 3)
                            .padding(.vertical, 8)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(ScaleButtonStyle())
                
                // Secondary options row
                HStack(spacing: 10) {
                    // Demo Mode button - only shown if no connected accounts
                    if canShowDemoOption {
                        Button(action: onEnableDemo) {
                            HStack(spacing: 5) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(goldAccent)
                                Text("Demo Mode")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(goldBase)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(goldBase.opacity(isDark ? 0.08 : 0.06))
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.white.opacity(isDark ? 0.08 : 0.35), Color.white.opacity(0)],
                                                startPoint: .top,
                                                endPoint: .center
                                            )
                                        )
                                }
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(
                                        LinearGradient(
                                            colors: isDark
                                                ? [goldLight.opacity(0.3), goldBase.opacity(0.1)]
                                                : [goldBase.opacity(0.25), goldBase.opacity(0.08)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                    
                    // Paper Trading button - with Pro badge if locked - premium glass
                    Button {
                        if hasPaperTradingAccess {
                            onEnablePaperTrading?()
                        } else {
                            PaywallManager.shared.trackFeatureAttempt(.paperTrading)
                            showUpgradeSheet = true
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(hasPaperTradingAccess ? AnyShapeStyle(goldAccent) : AnyShapeStyle(Color.gray.opacity(0.6)))
                            Text("Paper Trade")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(hasPaperTradingAccess ? goldBase : .gray)
                            
                            if !hasPaperTradingAccess {
                                Text("PRO")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(LinearGradient(colors: [goldLight, goldBase], startPoint: .leading, endPoint: .trailing))
                                    )
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(hasPaperTradingAccess 
                                        ? goldBase.opacity(isDark ? 0.08 : 0.06)
                                        : Color.gray.opacity(isDark ? 0.08 : 0.04))
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.white.opacity(isDark ? 0.08 : 0.35), Color.white.opacity(0)],
                                            startPoint: .top,
                                            endPoint: .center
                                        )
                                    )
                            }
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: isDark
                                            ? [hasPaperTradingAccess ? goldLight.opacity(0.3) : Color.white.opacity(0.12), hasPaperTradingAccess ? goldBase.opacity(0.1) : Color.white.opacity(0.04)]
                                            : [hasPaperTradingAccess ? goldBase.opacity(0.25) : Color.black.opacity(0.06), hasPaperTradingAccess ? goldBase.opacity(0.08) : Color.black.opacity(0.02)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
                
                // Import CSV option
                if let onImportCSV = onImportCSV {
                    Button(action: onImportCSV) {
                        HStack(spacing: 5) {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(goldAccent)
                            Text("Import CSV")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(goldBase)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(goldBase.opacity(isDark ? 0.08 : 0.06))
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.white.opacity(isDark ? 0.08 : 0.35), Color.white.opacity(0)],
                                            startPoint: .top,
                                            endPoint: .center
                                        )
                                    )
                            }
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: isDark
                                            ? [goldLight.opacity(0.3), goldBase.opacity(0.1)]
                                            : [goldBase.opacity(0.25), goldBase.opacity(0.08)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 32)
        .unifiedPaywallSheet(feature: .paperTrading, isPresented: $showUpgradeSheet)
    }
}

// MARK: - Home Balance Empty State Card
struct HomeBalanceEmptyStateCard: View {
    let onConnectExchange: () -> Void
    let onEnableDemo: () -> Void
    var onEnablePaperTrading: (() -> Void)? = nil
    
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showUpgradeSheet = false
    
    private var isDark: Bool { colorScheme == .dark }
    
    // Gold accent colors matching app design
    private var goldLight: Color { BrandColors.goldLight }
    private var goldBase: Color { BrandColors.goldBase }
    
    private var goldAccent: LinearGradient {
        isDark
            ? LinearGradient(colors: [goldLight, goldBase], startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [goldBase, BrandColors.goldDark], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    /// Demo mode is only available for users without connected accounts
    private var canShowDemoOption: Bool {
        ConnectedAccountsManager.shared.accounts.isEmpty
    }
    
    private var hasPaperTradingAccess: Bool {
        subscriptionManager.hasAccess(to: .paperTrading)
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Value display — no card-level mode badge; the header toggle handles mode indication
            VStack(alignment: .leading, spacing: 3) {
                Text("$0.00")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(DS.Adaptive.textTertiary)
                
                Text("No holdings yet")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Call to action
            Text("Connect your exchange to track your real portfolio")
                .font(.system(size: 13))
                .foregroundColor(DS.Adaptive.textSecondary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Single primary button - Connect Exchange - premium glass style
            Button(action: onConnectExchange) {
                HStack(spacing: 10) {
                    // Gold icon with glow
                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(goldAccent)
                    
                    Text("Connect Exchange")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Spacer()
                    
                    // Gold chevron
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(goldAccent.opacity(0.7))
                }
                .padding(.leading, 16)
                .padding(.trailing, 14)
                .padding(.vertical, 12)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                RadialGradient(
                                    colors: isDark
                                        ? [goldBase.opacity(0.08), Color.white.opacity(0.04)]
                                        : [goldBase.opacity(0.05), Color.black.opacity(0.02)],
                                    center: .topLeading,
                                    startRadius: 0,
                                    endRadius: 120
                                )
                            )
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(isDark ? 0.1 : 0.45), Color.white.opacity(0)],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: isDark
                                    ? [goldLight.opacity(0.4), goldBase.opacity(0.15), DS.Adaptive.stroke.opacity(0.3)]
                                    : [goldBase.opacity(0.3), goldBase.opacity(0.1), DS.Adaptive.stroke.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                // Gold bar accent on left
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [goldLight.opacity(isDark ? 0.8 : 0.7), goldBase.opacity(isDark ? 0.6 : 0.5)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 3)
                        .padding(.vertical, 8)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(ScaleButtonStyle())
            
            // Hint about other modes (subtle, since switcher is above)
            Text("Or try Demo or Paper mode above to explore")
                .font(.system(size: 11))
                .foregroundColor(DS.Adaptive.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(
            ZStack {
                // Base card background
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
                
                // Subtle top gradient
                LinearGradient(
                    colors: [DS.Adaptive.gradientHighlight, Color.clear],
                    startPoint: .top,
                    endPoint: .center
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
    }
}

// MARK: - Trading Empty State
struct TradingEmptyStateView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    
    let onConnectExchange: () -> Void
    let onEnableDemo: () -> Void
    
    private var isDark: Bool { colorScheme == .dark }
    private var goldLight: Color { BrandColors.goldLight }
    private var goldBase: Color { BrandColors.goldBase }
    
    private var goldAccent: LinearGradient {
        isDark
            ? LinearGradient(colors: [goldLight, goldBase], startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [goldBase, BrandColors.goldDark], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    private var hasPaperTradingAccess: Bool {
        subscriptionManager.hasAccess(to: .paperTrading)
    }
    
    /// Demo mode is only available for users without connected accounts
    private var canShowDemoOption: Bool {
        ConnectedAccountsManager.shared.accounts.isEmpty
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Show appropriate message based on subscription access
            if hasPaperTradingAccess {
                EmptyStateView(
                    icon: "doc.text.fill",
                    title: "Start Paper Trading",
                    subtitle: "Practice trading with $100,000 in virtual funds. Risk-free strategy testing."
                )
            } else if canShowDemoOption {
                EmptyStateView(
                    icon: "sparkles",
                    title: "Explore Trading",
                    subtitle: "Try Demo Mode to explore trading features, or upgrade to Pro for Paper Trading."
                )
            } else {
                EmptyStateView(
                    icon: "chart.pie.fill",
                    title: "Ready to Trade",
                    subtitle: "Enable Paper Trading to practice, or use AI Chat for trading advice."
                )
            }
            
            HStack(spacing: 12) {
                // Demo Mode button - only shown if no connected accounts
                if canShowDemoOption {
                    Button(action: onEnableDemo) {
                        HStack(spacing: 5) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(goldAccent)
                            Text("Try Demo")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(goldBase)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            Capsule()
                                .fill(goldBase.opacity(isDark ? 0.08 : 0.06))
                        )
                        .overlay(
                            Capsule()
                                .stroke(goldBase.opacity(isDark ? 0.2 : 0.18), lineWidth: 1)
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
                
                // Secondary: Connect for portfolio tracking (or Paper Trading if already connected)
                Button(action: onConnectExchange) {
                    HStack(spacing: 8) {
                        Image(systemName: canShowDemoOption ? "chart.pie.fill" : "doc.text.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(goldAccent)
                        Text(canShowDemoOption ? "Track Portfolio" : "Paper Trading")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        ZStack {
                            Capsule()
                                .fill(
                                    RadialGradient(
                                        colors: isDark
                                            ? [goldBase.opacity(0.1), Color.white.opacity(0.05)]
                                            : [goldBase.opacity(0.06), Color.black.opacity(0.02)],
                                        center: .top,
                                        startRadius: 0,
                                        endRadius: 50
                                    )
                                )
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(isDark ? 0.1 : 0.45), Color.white.opacity(0)],
                                        startPoint: .top,
                                        endPoint: .center
                                    )
                                )
                        }
                    )
                    .overlay(
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: isDark
                                        ? [goldLight.opacity(0.4), goldBase.opacity(0.15)]
                                        : [goldBase.opacity(0.3), goldBase.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
    }
}

// MARK: - Previews
struct EmptyStateViews_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Dark mode preview
            ZStack {
                DS.Adaptive.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 40) {
                        HomeBalanceEmptyStateCard(
                            onConnectExchange: {},
                            onEnableDemo: {}
                        )
                        
                        PortfolioEmptyStateView(
                            onConnectExchange: {},
                            onEnableDemo: {}
                        )
                        
                        TradingEmptyStateView(
                            onConnectExchange: {},
                            onEnableDemo: {}
                        )
                    }
                    .padding()
                }
            }
            .preferredColorScheme(.dark)
            .previewDisplayName("Dark Mode")
            
            // Light mode preview
            ZStack {
                DS.Adaptive.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 40) {
                        HomeBalanceEmptyStateCard(
                            onConnectExchange: {},
                            onEnableDemo: {}
                        )
                        
                        PortfolioEmptyStateView(
                            onConnectExchange: {},
                            onEnableDemo: {}
                        )
                        
                        TradingEmptyStateView(
                            onConnectExchange: {},
                            onEnableDemo: {}
                        )
                    }
                    .padding()
                }
            }
            .preferredColorScheme(.light)
            .previewDisplayName("Light Mode")
        }
    }
}
