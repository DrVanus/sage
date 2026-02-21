//
//  SubpageHeaderBar.swift
//  CryptoSage
//
//  A unified header bar for all subpages with consistent styling.
//  Based on the AI Insights style: gold chevron back, centered title, optional badge/timestamp.
//

import SwiftUI

/// A standardized header bar for subpages throughout the app.
/// Provides consistent navigation UX with gold-accented back button and centered title.
struct SubpageHeaderBar<RightContent: View>: View {
    // MARK: - Properties
    
    /// The main title text
    let title: String
    
    /// Optional badge to display next to the title (e.g., "DEMO", "BETA")
    var badge: String? = nil
    
    /// Badge color - defaults to green for status badges
    var badgeColor: Color = .green
    
    /// Optional subtitle/timestamp below the title
    var subtitle: String? = nil
    
    /// Whether to show X close button instead of chevron back
    var showCloseButton: Bool = false
    
    /// Whether to include bottom divider line
    var showDivider: Bool = true
    
    /// Action when back/close button is tapped
    var onDismiss: () -> Void
    
    /// Optional right-side content (action buttons, timestamp, etc.)
    var rightContent: (() -> RightContent)?
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                // Left: Back/Close button
                backButton
                
                Spacer()
                
                // Center: Title with optional badge
                titleSection
                
                Spacer()
                
                // Right: Custom content or spacer for balance
                rightSection
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(DS.Adaptive.background.opacity(0.98))
            
            // Bottom divider
            if showDivider {
                Rectangle()
                    .fill(DS.Adaptive.divider)
                    .frame(height: 0.5)
            }
        }
    }
    
    // MARK: - Subviews
    
    private var backButton: some View {
        CSNavButton(
            icon: showCloseButton ? "xmark" : "chevron.left",
            action: onDismiss,
            accessibilityText: showCloseButton ? "Close" : "Back"
        )
    }
    
    private var titleSection: some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DS.Adaptive.textPrimary)
                    .lineLimit(1)
                
                // Badge (e.g., "DEMO")
                if let badge = badge {
                    SubpageHeaderBadge(text: badge, color: badgeColor)
                }
            }
            
            // Subtitle (e.g., timestamp)
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.Adaptive.textTertiary)
            }
        }
    }
    
    @ViewBuilder
    private var rightSection: some View {
        if let rightContent = rightContent {
            rightContent()
                .frame(minWidth: 44, alignment: .trailing)
        } else {
            // Empty spacer for balance
            Color.clear
                .frame(width: 44, height: 36)
        }
    }
}

// MARK: - Convenience Initializer (No Right Content)

extension SubpageHeaderBar where RightContent == EmptyView {
    init(
        title: String,
        badge: String? = nil,
        badgeColor: Color = .green,
        subtitle: String? = nil,
        showCloseButton: Bool = false,
        showDivider: Bool = true,
        onDismiss: @escaping () -> Void
    ) {
        self.title = title
        self.badge = badge
        self.badgeColor = badgeColor
        self.subtitle = subtitle
        self.showCloseButton = showCloseButton
        self.showDivider = showDivider
        self.onDismiss = onDismiss
        self.rightContent = nil
    }
}

// MARK: - Badge Component

struct SubpageHeaderBadge: View {
    let text: String
    var color: Color = .green
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            
            Text(text)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(color)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(color.opacity(isDark ? 0.15 : 0.10))
        )
        .overlay(
            Capsule()
                .stroke(color.opacity(isDark ? 0.40 : 0.25), lineWidth: 0.5)
        )
    }
}

// MARK: - Button Style

private struct SubpageHeaderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Timestamp Helper

extension SubpageHeaderBar {
    /// Creates a timestamp string for the current time
    static func currentTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: Date())
    }
}

// MARK: - Preview

#Preview("Subpage Headers") {
    VStack(spacing: 20) {
        // Basic header
        SubpageHeaderBar(
            title: "AI Insights",
            onDismiss: {}
        )
        
        // With badge
        SubpageHeaderBar(
            title: "AI Insights",
            badge: "DEMO",
            onDismiss: {}
        )
        
        // With subtitle
        SubpageHeaderBar(
            title: "Crypto News",
            subtitle: "Updated 2:30 PM",
            onDismiss: {}
        )
        
        // Close button style
        SubpageHeaderBar(
            title: "All Events",
            showCloseButton: true,
            onDismiss: {}
        )
        
        // With right content
        SubpageHeaderBar(
            title: "Whale Tracker",
            showCloseButton: true,
            onDismiss: {}
        ) {
            HStack(spacing: 12) {
                Image(systemName: "eye")
                    .font(.system(size: 16))
                    .foregroundStyle(DS.Adaptive.textSecondary)
                
                Image(systemName: "gearshape")
                    .font(.system(size: 16))
                    .foregroundStyle(DS.Adaptive.textSecondary)
            }
        }
        
        Spacer()
    }
    .background(DS.Adaptive.background)
    .preferredColorScheme(.dark)
}
