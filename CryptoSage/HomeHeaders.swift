//
//  HomeHeaders.swift
//  CSAI1
//
//  Extracted header views used on the Home page.
//

import SwiftUI

// MARK: - Reusable heading with optional icon
struct SectionHeading: View {
    let text: String
    let iconName: String?
    var iconColor: Color = .yellow
    var iconSize: CGFloat = 16
    var showsDivider: Bool = true

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if let icon = iconName {
                Image(systemName: icon)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.csGold)
                    .font(.system(size: iconSize, weight: .semibold, design: .rounded))
                    .frame(width: iconSize + 4, height: iconSize + 4, alignment: .center)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 2)
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
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
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: systemImage)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.csGold)
                .font(.system(size: iconSize, weight: .semibold, design: .rounded))
                .frame(width: iconSize + 4, height: iconSize + 4, alignment: .center)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.csGoldSolid)
                    .accessibilityLabel("\(title) – \(actionTitle)")
            }
        }
        .padding(.leading, 2)
        .padding(.vertical, 4)
        .overlay(
            Group {
                if showsDivider {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
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
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "newspaper")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.csGold)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            Button(action: onAllNews) {
                HStack(spacing: 6) {
                    Text("All News")
                    Image(systemName: "chevron.right")
                }
            }
            .buttonStyle(CSSecondaryCTAButtonStyle(height: 28, cornerRadius: 10, horizontalPadding: 10, font: .caption.weight(.semibold)))
            .accessibilityLabel("See all news")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .overlay(
            Group {
                if showsDivider {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 0.5)
                }
            }, alignment: .bottom
        )
    }
}

// MARK: - AI Insights header row
struct AIInsightsHeaderRow: View {
    var isAskHidden: Bool
    var onToggleAsk: () -> Void
    var onOpenAll: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb")
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.csGold)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                Text("AI Insights")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            Spacer(minLength: 8)
            if isAskHidden {
                Button(action: onToggleAsk) {
                    Image(systemName: "eye")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.06))
                                .overlay(
                                    Capsule()
                                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show Ask AI prompts")
            }
            Button(action: onOpenAll) {
                HStack(spacing: 6) {
                    Text("All Insights")
                    Image(systemName: "chevron.right")
                }
            }
            .buttonStyle(CSSecondaryCTAButtonStyle(height: 28, cornerRadius: 10, horizontalPadding: 10, font: .caption.weight(.semibold)))
            .accessibilityLabel("Open all insights")
        }
        .padding(.leading, 2)
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
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
            // Row 1: shared section header
            SectionHeader(systemImage: "eye", title: "Watchlist", actionTitle: nil, action: nil, showsDivider: false)

            // Row 2: column labels aligned to watchlist columns
            HStack(spacing: 0) {
                // Reserve space for the leading column (icon+name+price)
                Color.clear
                    .frame(width: max(0, leadingWidth))

                Text("7D")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .tracking(0.15)
                    .foregroundStyle(Color.white.opacity(0.68))
                    .frame(width: max(0, sparkWidth), alignment: .center)

                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: max(0, outerDividerW), height: 14)

                HStack(spacing: max(0, percentSpacing)) {
                    Text("1H")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .tracking(0.15)
                        .foregroundStyle(Color.white.opacity(0.68))
                        .frame(width: max(0, percentWidth), alignment: .trailing)
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: max(0, innerDividerW), height: 12)
                        .accessibilityHidden(true)
                    Text("24H")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .tracking(0.15)
                        .foregroundStyle(Color.white.opacity(0.68))
                        .frame(width: max(0, percentWidth), alignment: .trailing)
                }
                .frame(width: max(0, percentWidth * 2 + percentSpacing + innerDividerW), alignment: .trailing)
            }
            .padding(.top, 0)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
            }
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

    var body: some View {
        HStack(spacing: 10) {
            Text(title).foregroundStyle(.secondary)
            Divider().frame(height: 14)
            Text(totalText).foregroundStyle(.white).monospacedDigit()
            HStack(spacing: 4) {
                Image(systemName: isUp ? "arrow.up" : "arrow.down").foregroundStyle(isUp ? .green : .red)
                Text(changeText).foregroundStyle(.white).monospacedDigit()
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Capsule().fill((isUp ? Color.green : Color.red).opacity(0.18)))
            Spacer()
            Button(action: onRunRiskScan) { Image(systemName: "shield.lefthalf.filled") }
                .buttonStyle(.plain).foregroundStyle(.white)
            Button(action: onNotifications) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell")
                    if hasPendingNotifications { Circle().fill(.red).frame(width: 6, height: 6).offset(x: 3, y: -3) }
                }
            }
            .buttonStyle(.plain).foregroundStyle(.white)
            Menu {
                Button("Settings", action: onSettings)
                Button("Refresh Data", action: onRefreshData)
            } label: {
                Image(systemName: "gearshape").foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.65))
        .opacity(Double(fade))
    }
}

// MARK: - Simple top nav bar used by Home (debug/demo)
struct TopNavBar: View {
    let title: String
    let hasPendingNotifications: Bool
    let onNotifications: () -> Void
    let onSettings: () -> Void
    @Binding var demoModeEnabled: Bool
    let reseedDemo: () -> Void
    let clearDemo: () -> Void
    let onRefreshData: () -> Void
    let onRunRiskScan: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            Button(action: onRunRiskScan) { Image(systemName: "shield.lefthalf.filled") }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
            Button(action: onNotifications) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell")
                    if hasPendingNotifications { Circle().fill(Color.red).frame(width: 6, height: 6).offset(x: 4, y: -4) }
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            Menu {
                Toggle("Use Demo Portfolio", isOn: $demoModeEnabled)
                Button("Reseed Demo Portfolio", action: reseedDemo)
                Button("Clear Demo Portfolio", role: .destructive, action: clearDemo)
                Divider()
                Button("Settings", action: onSettings)
                Button("Refresh Data", action: onRefreshData)
            } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.65))
    }
}
