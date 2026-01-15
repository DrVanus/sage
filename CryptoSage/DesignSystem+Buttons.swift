import SwiftUI

// MARK: - Shared Button Styles
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1.0)
    }
}

struct GlowButtonStyle: ButtonStyle {
    var isSell: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            // Softer, tighter glow to avoid bleeding into the next row
            .shadow(
                color: (isSell ? Color.red : Color.gold)
                    .opacity(configuration.isPressed ? 0.14 : 0.26),
                radius: configuration.isPressed ? 4 : 8,
                x: 0,
                y: configuration.isPressed ? 1 : 2
            )
            // Gentle grounding shadow (very small) to keep depth without spill
            .shadow(
                color: Color.black.opacity(configuration.isPressed ? 0.12 : 0.18),
                radius: configuration.isPressed ? 1.5 : 3,
                x: 0,
                y: configuration.isPressed ? 0.5 : 1
            )
            .brightness(configuration.isPressed ? -0.04 : 0)
    }
}
