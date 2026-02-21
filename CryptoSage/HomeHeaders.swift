//
//  HomeHeaders.swift
//  CryptoSage
//
//  Premium header views used on the Home page.
//

import SwiftUI

// MARK: - Premium Section Header (matches Portfolio card style)
struct PremiumSectionHeader: View {
    let systemImage: String
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            GoldHeaderGlyph(systemName: systemImage)
            
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.Adaptive.textPrimary)
            
            Spacer(minLength: 8)
            
            if let actionTitle, let action {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    action()
                }) {
                    Text(actionTitle)
                }
                .buttonStyle(CSTextLinkButtonStyle())
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Reusable heading with optional icon
struct SectionHeading: View {
    let text: String
    let iconName: String?
    var iconColor: Color = .yellow
    var iconSize: CGFloat = 16
    var showsDivider: Bool = true

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let icon = iconName {
                GoldHeaderGlyphSmall(systemName: icon)
            }
            Text(text)
                .font(.headline.weight(.semibold))
                .foregroundStyle(DS.Adaptive.textPrimary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(DS.Adaptive.divider)
                    .frame(height: 0.5)
            }
        }
    }
}

// MARK: - Section header with icon and optional action
struct SectionHeader: View {
    let systemImage: String
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var showsDivider: Bool = true
    var iconColor: Color = .yellow
    var iconSize: CGFloat = 16

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            GoldHeaderGlyphSmall(systemName: systemImage)
            
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(DS.Adaptive.textPrimary)
            
            Spacer(minLength: 0)
            
            if let actionTitle, let action {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    action()
                }) {
                    Text(actionTitle)
                }
                .buttonStyle(CSTextLinkButtonStyle())
                .accessibilityLabel("\(title) – \(actionTitle)")
            }
        }
        .padding(.vertical, 6)
        .overlay(
            Group {
                if showsDivider {
                    Rectangle()
                        .fill(DS.Adaptive.divider)
                        .frame(height: 0.5)
                }
            }, alignment: .bottom
        )
    }
}

struct NewsSectionHeader: View {
    let title: String
    var showsDivider: Bool = true
    let onAllNews: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            GoldHeaderGlyphSmall(systemName: "newspaper.fill")
            
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(DS.Adaptive.textPrimary)
            
            Spacer(minLength: 0)
            
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onAllNews()
            }) {
                Text("All News")
            }
            .buttonStyle(CSTextLinkButtonStyle())
            .accessibilityLabel("See all news")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

// MARK: - AI Insights header row
struct AIInsightsHeaderRow: View {
    // PERFORMANCE FIX v20: Removed @EnvironmentObject appState (18+ @Published)
    // Only used for dismissHomeSubviews - now via AppState.shared
    /// FIX v5.0.3: Changed from @State to @Binding so the navigationDestination can be
    /// placed at the parent level (outside any lazy container).
    @Binding var openAllInsights: Bool
    
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            GoldHeaderGlyphSmall(systemName: "lightbulb.fill")
            
            Text("AI Insights")
                .font(.headline.weight(.semibold))
                .foregroundStyle(DS.Adaptive.textPrimary)
            
            Spacer(minLength: 8)
            
            // All Insights button
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                openAllInsights = true
            } label: {
                Text("All Insights")
            }
            .buttonStyle(CSTextLinkButtonStyle())
            .accessibilityLabel("Open all insights")
        }
        .padding(.vertical, 6)
        // FIX v5.0.3: navigationDestination for AllAIInsightsView removed — should be
        // placed at the parent level (outside any lazy container) to fix SwiftUI warning.
        .onReceive(AppState.shared.$dismissHomeSubviews) { shouldDismiss in
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                if shouldDismiss && openAllInsights {
                    openAllInsights = false
                    AppState.shared.dismissHomeSubviews = false
                }
            }
        }
    }
}

// MARK: - Watchlist aligned header (used by Home watchlist section)
struct WatchlistHeaderUnified: View {
    let leadingWidth: CGFloat
    let sparkWidth: CGFloat
    let percentWidth: CGFloat
    let percentSpacing: CGFloat
    let innerDividerW: CGFloat
    let outerDividerW: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            // Row 1: Section title with gold icon - consistent with other sections
            HStack(alignment: .center, spacing: 8) {
                GoldHeaderGlyph(systemName: "eye.fill")
                
                Text("Watchlist")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.Adaptive.textPrimary)
                
                Spacer(minLength: 0)
            }

            // Row 2: column labels aligned to watchlist columns
            HStack(spacing: 0) {
                // Reserve space for the leading column (icon+name+price)
                Color.clear
                    .frame(width: max(0, leadingWidth))

                Text("7D")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.Adaptive.textSecondary.opacity(0.8))
                    .frame(width: max(0, sparkWidth), alignment: .center)
                    .padding(.trailing, 4)

                Rectangle()
                    .fill(DS.Adaptive.divider.opacity(0.4))
                    .frame(width: max(0, outerDividerW), height: 12)

                HStack(spacing: max(0, percentSpacing)) {
                    Text("1H")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.Adaptive.textSecondary.opacity(0.8))
                        .frame(width: max(0, percentWidth), alignment: .trailing)
                    Rectangle()
                        .fill(DS.Adaptive.divider.opacity(0.3))
                        .frame(width: max(0, innerDividerW), height: 8)
                        .accessibilityHidden(true)
                    Text("24H")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.Adaptive.textSecondary.opacity(0.8))
                        .frame(width: max(0, percentWidth), alignment: .trailing)
                }
                .padding(.leading, 4)
                .frame(width: max(0, percentWidth * 2 + percentSpacing + innerDividerW + 4), alignment: .trailing)
            }
            .padding(.bottom, 4)
        }
    }
}

// MARK: - Minimal top ribbon bar used by HomeView overlay
struct MinimalRibbonBar: View {
    let title: String
    let totalText: String
    let changeText: String
    let isUp: Bool
    let hasPendingNotifications: Bool
    let onNotifications: () -> Void
    let onSettings: () -> Void
    let onRefreshData: () -> Void
    let onRunRiskScan: () -> Void
    var fade: CGFloat = 1.0
    
    @State private var showSettingsMenu: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Text(title).foregroundStyle(.secondary)
            Divider().frame(height: 14)
            Text(totalText).foregroundStyle(DS.Adaptive.textPrimary).monospacedDigit()
            HStack(spacing: 4) {
                Image(systemName: isUp ? "arrow.up" : "arrow.down").foregroundStyle(isUp ? .green : .red)
                Text(changeText).foregroundStyle(DS.Adaptive.textPrimary).monospacedDigit()
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Capsule().fill((isUp ? Color.green : Color.red).opacity(0.18)))
            Spacer()
            Button(action: onRunRiskScan) { Image(systemName: "shield.lefthalf.filled") }
                .buttonStyle(.plain).foregroundStyle(DS.Adaptive.textPrimary)
            Button(action: onNotifications) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell")
                    if hasPendingNotifications { Circle().fill(.red).frame(width: 6, height: 6).offset(x: 3, y: -3) }
                }
            }
            .buttonStyle(.plain).foregroundStyle(DS.Adaptive.textPrimary)
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                showSettingsMenu = true
            } label: {
                Image(systemName: "gearshape").foregroundStyle(DS.Adaptive.textPrimary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showSettingsMenu, arrowEdge: .bottom) {
                HeaderActionMenu(isPresented: $showSettingsMenu, actions: [
                    .init(title: "Settings", icon: "gearshape", action: onSettings),
                    .init(title: "Refresh Data", icon: "arrow.clockwise", action: onRefreshData)
                ])
                .presentationCompactAdaptation(.popover)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(DS.Adaptive.background.opacity(0.65))
        .opacity(Double(fade))
    }
}

// MARK: - Simple top nav bar used by Home (debug/demo)
struct TopNavBar: View {
    let title: String
    let hasPendingNotifications: Bool
    let onNotifications: () -> Void
    let onSettings: () -> Void
    let reseedDemo: () -> Void
    let clearDemo: () -> Void
    let onRefreshData: () -> Void
    let onRunRiskScan: () -> Void
    
    /// Uses unified DemoModeManager for demo mode toggle
    @ObservedObject private var demoModeManager = DemoModeManager.shared
    @State private var showSettingsMenu: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(DS.Adaptive.textPrimary)
            Spacer()
            Button(action: onRunRiskScan) { Image(systemName: "shield.lefthalf.filled") }
                .buttonStyle(.plain)
                .foregroundStyle(DS.Adaptive.textPrimary)
            Button(action: onNotifications) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell")
                    if hasPendingNotifications { Circle().fill(Color.red).frame(width: 6, height: 6).offset(x: 4, y: -4) }
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(DS.Adaptive.textPrimary)
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                showSettingsMenu = true
            } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(DS.Adaptive.textPrimary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showSettingsMenu, arrowEdge: .bottom) {
                TopNavSettingsMenu(
                    isPresented: $showSettingsMenu,
                    isDemoMode: $demoModeManager.isDemoMode,
                    onReseedDemo: reseedDemo,
                    onClearDemo: clearDemo,
                    onSettings: onSettings,
                    onRefreshData: onRefreshData
                )
                .presentationCompactAdaptation(.popover)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(DS.Adaptive.background.opacity(0.65))
    }
}

// MARK: - Header Action Menu (Styled popover for simple action lists)
struct HeaderActionMenuItem {
    let title: String
    let icon: String?
    let isDestructive: Bool
    let action: () -> Void
    
    init(title: String, icon: String? = nil, isDestructive: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isDestructive = isDestructive
        self.action = action
    }
}

struct HeaderActionMenu: View {
    @Binding var isPresented: Bool
    let actions: [HeaderActionMenuItem]
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(actions.enumerated()), id: \.offset) { index, item in
                actionRow(item)
                if index < actions.count - 1 {
                    Rectangle()
                        .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                        .frame(height: 0.5)
                        .padding(.horizontal, 8)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        // PERFORMANCE FIX v19: Replaced .ultraThinMaterial with solid color
        .background(DS.Adaptive.chipBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            LinearGradient(
                colors: isDark
                    ? [Color.white.opacity(0.10), .clear]
                    : [Color.white.opacity(0.6), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.08), lineWidth: 0.75)
                .allowsHitTesting(false)
        )
        .frame(minWidth: 160, maxWidth: 220)
    }
    
    @ViewBuilder
    private func actionRow(_ item: HeaderActionMenuItem) -> some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            item.action()
            isPresented = false
        } label: {
            HStack(spacing: 8) {
                if let icon = item.icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(item.isDestructive ? Color.red : (isDark ? Color.white.opacity(0.9) : DS.Adaptive.textPrimary))
                        .frame(width: 20)
                }
                Text(item.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(item.isDestructive ? Color.red : (isDark ? Color.white.opacity(0.92) : DS.Adaptive.textPrimary))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Top Nav Settings Menu (Extended menu with toggle support)
struct TopNavSettingsMenu: View {
    @Binding var isPresented: Bool
    @Binding var isDemoMode: Bool
    let onReseedDemo: () -> Void
    let onClearDemo: () -> Void
    let onSettings: () -> Void
    let onRefreshData: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    private var isDarkMode: Bool { colorScheme == .dark }
    
    var body: some View {
        VStack(spacing: 2) {
            // Demo mode toggle
            demoModeToggle
            
            divider
            
            // Demo actions
            actionRow(title: "Reseed Demo Portfolio", icon: "arrow.triangle.2.circlepath", action: onReseedDemo)
            actionRow(title: "Clear Demo Portfolio", icon: "trash", isDestructive: true, action: onClearDemo)
            
            divider
            
            // Main actions
            actionRow(title: "Settings", icon: "gearshape", action: onSettings)
            actionRow(title: "Refresh Data", icon: "arrow.clockwise", action: onRefreshData)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        // PERFORMANCE FIX v19: Replaced .ultraThinMaterial with solid color
        .background(DS.Adaptive.chipBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            LinearGradient(
                colors: isDarkMode
                    ? [Color.white.opacity(0.10), .clear]
                    : [Color.white.opacity(0.6), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.08), lineWidth: 0.75)
                .allowsHitTesting(false)
        )
        .frame(minWidth: 200, maxWidth: 260)
    }
    
    private var demoModeToggle: some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
                isDemoMode.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isDemoMode ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isDemoMode ? DS.Colors.gold : (isDarkMode ? Color.white.opacity(0.5) : DS.Adaptive.textTertiary))
                    .frame(width: 20)
                Text("Use Demo Portfolio")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isDarkMode ? Color.white.opacity(0.92) : DS.Adaptive.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private var divider: some View {
        Rectangle()
            .fill(isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
            .frame(height: 0.5)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
    }
    
    @ViewBuilder
    private func actionRow(title: String, icon: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            action()
            isPresented = false
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isDestructive ? Color.red : (isDarkMode ? Color.white.opacity(0.9) : DS.Adaptive.textPrimary))
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isDestructive ? Color.red : (isDarkMode ? Color.white.opacity(0.92) : DS.Adaptive.textPrimary))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
