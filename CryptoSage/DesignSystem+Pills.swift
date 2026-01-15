import SwiftUI

// MARK: - Reusable Pill Helpers
// Gold rounded rectangle pill (used for menu-style controls)
extension View {
    func goldRoundedPill(cornerRadius: CGFloat = 12) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(chipGoldGradient)
            )
            .overlay(
                LinearGradient(colors: [Color.white.opacity(0.16), Color.clear], startPoint: .top, endPoint: .center)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(ctaRimStrokeGradient, lineWidth: 0.8)
            )
            .overlay(
                ctaBottomShade
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
    }

    // Gold capsule pill (used for compact chips)
    func goldCapsulePill() -> some View {
        self
            .background(Capsule().fill(chipGoldGradient))
            .overlay(
                LinearGradient(colors: [Color.white.opacity(0.16), Color.clear], startPoint: .top, endPoint: .center)
                    .clipShape(Capsule())
            )
            .overlay(
                Capsule()
                    .stroke(ctaRimStrokeGradient, lineWidth: 0.8)
            )
            .overlay(
                ctaBottomShade
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
}
