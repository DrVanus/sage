import SwiftUI

/// A reusable, brand-styled segmented pill for chips and segmented controls.
/// - selected: filled gold gradient with rim and soft top gloss (flat in light mode)
/// - unselected: subtle fill with gold stroke (adapts to light/dark mode)
/// - pressed: slightly darker gradient
public struct GoldPillStyle: ButtonStyle {
    public var selected: Bool
    public var cornerRadius: CGFloat = 10

    public init(selected: Bool, cornerRadius: CGFloat = 10) {
        self.selected = selected
        self.cornerRadius = cornerRadius
    }

    public func makeBody(configuration: Configuration) -> some View {
        if selected {
            PremiumCompactCTAStyle(
                height: 28,
                horizontalPadding: 10,
                cornerRadius: cornerRadius,
                pressedScale: 0.985,
                font: .system(size: 12, weight: .semibold)
            ).makeBody(configuration: configuration)
        } else {
            PremiumSecondaryCTAStyle(
                height: 28,
                horizontalPadding: 10,
                cornerRadius: cornerRadius,
                pressedScale: 0.985,
                font: .system(size: 12, weight: .semibold)
            ).makeBody(configuration: configuration)
        }
    }
}

public extension View {
    /// Apply a pill background/overlay without altering font/padding.
    /// Uses silver in light mode, gold in dark mode.
    /// Note: For full adaptive behavior, use GoldPillStyle ButtonStyle instead.
    func goldPillBackground(selected: Bool, cornerRadius: CGFloat = 10, isDark: Bool = true) -> some View {
        self.background(
            Group {
                if selected {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            isDark
                                ? LinearGradient(colors: [BrandColors.goldLight, BrandColors.goldBase, BrandColors.goldDark], startPoint: .top, endPoint: .bottom)
                                : LinearGradient(colors: [Color(white: 0.15), Color(white: 0.05)], startPoint: .top, endPoint: .bottom)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .stroke(
                                    isDark
                                        ? LinearGradient(colors: [BrandColors.goldStrokeHighlight, BrandColors.goldStrokeShadow], startPoint: .top, endPoint: .bottom)
                                        : LinearGradient(colors: [Color.white.opacity(0.15), Color.black.opacity(0.08)], startPoint: .top, endPoint: .bottom),
                                    lineWidth: 0.8
                                )
                        )
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .stroke(
                                    isDark
                                        ? LinearGradient(colors: [BrandColors.goldBorder.opacity(0.55), Color.white.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                        : LinearGradient(colors: [Color.black.opacity(0.12), Color.black.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                    lineWidth: 0.8
                                )
                        )
                }
            }
        )
    }
}
