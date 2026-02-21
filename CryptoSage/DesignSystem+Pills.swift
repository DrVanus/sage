import SwiftUI

// MARK: - Tinted Chip Style Colors
// These colors provide a subtle, modern chip appearance matching the app-wide design language.
// Used for filter chips, category selectors, and segmented controls throughout the app.
enum TintedChipStyle {
    /// Tinted background color for selected chips
    /// Dark mode: subtle gold tint; Light mode: warm amber tint for cohesive light-mode feel
    /// LIGHT MODE FIX: Changed from dark charcoal (silverBase @ 85%) to a warm golden amber.
    /// The charcoal looked like a dark-mode element pasted onto a light background.
    static func selectedBackground(isDark: Bool) -> Color {
        isDark
            ? BrandColors.goldBase.opacity(0.15)
            : Color(red: 0.96, green: 0.90, blue: 0.72) // Warm honey amber - matches gold brand on light bg
    }
    
    /// Text color for selected chips
    /// Dark mode: gold text; Light mode: dark amber for contrast on warm background
    static func selectedText(isDark: Bool) -> Color {
        isDark
            ? DS.Adaptive.goldText
            : Color(red: 0.40, green: 0.30, blue: 0.05) // Dark amber-brown for readability
    }
    
    /// Stroke color for selected chips
    static func selectedStroke(isDark: Bool) -> Color {
        isDark
            ? BrandColors.goldBase.opacity(0.35)
            : BrandColors.goldBase.opacity(0.50) // Gold-tinted stroke instead of charcoal
    }
    
    /// Unselected background (same as DS.Adaptive.chipBackground but for explicit use)
    static var unselectedBackground: Color { DS.Adaptive.chipBackground }
    
    /// Unselected text color
    static var unselectedText: Color { DS.Adaptive.textPrimary }
    
    /// Unselected stroke color
    static var unselectedStroke: Color { DS.Adaptive.stroke }
}

// MARK: - Reusable Pill Helpers

extension View {
    // MARK: - Tinted Chip Styles (Modern, Subtle)
    
    /// Tinted capsule chip for filter/category selectors - premium glass style
    /// Use this for category chips, filter pills, segment controls throughout the app
    func tintedCapsuleChip(isSelected: Bool, isDark: Bool) -> some View {
        self
            .background(
                ZStack {
                    Capsule()
                        .fill(isSelected ? TintedChipStyle.selectedBackground(isDark: isDark) : TintedChipStyle.unselectedBackground)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isSelected ? (isDark ? 0.12 : 0.45) : (isDark ? 0.05 : 0.3)),
                                    Color.white.opacity(0)
                                ],
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
                            colors: isSelected
                                ? (isDark
                                    ? [BrandColors.goldLight.opacity(0.35), TintedChipStyle.selectedStroke(isDark: true).opacity(0.6)]
                                    : [BrandColors.goldBase.opacity(0.45), TintedChipStyle.selectedStroke(isDark: false).opacity(0.3)])
                                : (isDark
                                    ? [Color.white.opacity(0.12), TintedChipStyle.unselectedStroke.opacity(0.6)]
                                    : [Color.black.opacity(0.06), TintedChipStyle.unselectedStroke.opacity(0.5)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isSelected ? 1 : 0.8
                    )
            )
    }
    
    /// Tinted rounded rectangle chip for filter/category selectors - premium glass style
    func tintedRoundedChip(isSelected: Bool, isDark: Bool, cornerRadius: CGFloat = 7) -> some View {
        self
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(isSelected ? TintedChipStyle.selectedBackground(isDark: isDark) : TintedChipStyle.unselectedBackground)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isSelected ? (isDark ? 0.12 : 0.45) : (isDark ? 0.05 : 0.3)),
                                    Color.white.opacity(0)
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: isSelected
                                ? (isDark
                                    ? [BrandColors.goldLight.opacity(0.35), TintedChipStyle.selectedStroke(isDark: true).opacity(0.6)]
                                    : [BrandColors.goldBase.opacity(0.45), TintedChipStyle.selectedStroke(isDark: false).opacity(0.3)])
                                : (isDark
                                    ? [Color.white.opacity(0.12), TintedChipStyle.unselectedStroke.opacity(0.6)]
                                    : [Color.black.opacity(0.06), TintedChipStyle.unselectedStroke.opacity(0.5)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isSelected ? 1 : 0.8
                    )
            )
    }
    
    // MARK: - Legacy Gold Styles (kept for CTA buttons)
    
    // Gold/charcoal rounded rectangle pill (used for menu-style controls)
    func goldRoundedPill(cornerRadius: CGFloat = 12, isDark: Bool = true) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AdaptiveGradients.chipGold(isDark: isDark))
            )
            .overlay(
                LinearGradient(colors: [Color.white.opacity(isDark ? 0.16 : 0.25), Color.clear], startPoint: .top, endPoint: .center)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(BrandColors.ctaRimStroke(isDark: isDark), lineWidth: 0.8)
            )
            .overlay(
                ctaBottomShade(height: 28, isDark: isDark)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
    }

    // Gold/charcoal capsule pill (used for compact chips)
    func goldCapsulePill(isDark: Bool = true) -> some View {
        self
            .background(Capsule().fill(AdaptiveGradients.chipGold(isDark: isDark)))
            .overlay(
                LinearGradient(colors: [Color.white.opacity(isDark ? 0.16 : 0.25), Color.clear], startPoint: .top, endPoint: .center)
                    .clipShape(Capsule())
            )
            .overlay(
                Capsule()
                    .stroke(BrandColors.ctaRimStroke(isDark: isDark), lineWidth: 0.8)
            )
            .overlay(
                ctaBottomShade(height: 28, isDark: isDark)
                    .clipShape(Capsule())
            )
    }

    // Neutral capsule pill for semantic chips (e.g., change +/-)
    func neutralCapsulePill(backgroundOpacity: Double = 0.28, strokeOpacity: Double = 0.18) -> some View {
        self
            .background(Capsule().fill(Color.black.opacity(backgroundOpacity)))
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(strokeOpacity), lineWidth: 0.8)
            )
    }
    
    // STYLING FIX: Adaptive neutral capsule pill that works in both light and dark mode
    func adaptiveNeutralCapsulePill(isDark: Bool, backgroundOpacity: Double = 0.28, strokeOpacity: Double = 0.18) -> some View {
        self
            .background(Capsule().fill(DS.Adaptive.cardBackground.opacity(isDark ? backgroundOpacity : backgroundOpacity * 2)))
            .overlay(
                Capsule()
                    .stroke(DS.Adaptive.stroke.opacity(strokeOpacity), lineWidth: 0.8)
            )
    }
}
