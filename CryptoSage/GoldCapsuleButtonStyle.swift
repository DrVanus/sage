import SwiftUI

// Lightweight press feedback style used throughout the app
public struct PressableStyle: ButtonStyle {
    public var scale: CGFloat = 0.97
    public var opacity: Double = 0.9
    public init(scale: CGFloat = 0.97, opacity: Double = 0.9) {
        self.scale = scale
        self.opacity = opacity
    }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? opacity : 1)
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// Gold capsule CTA style with subtle gloss and rim strokes
public struct GoldCapsuleButtonStyle: ButtonStyle {
    public var height: CGFloat
    public var horizontalPadding: CGFloat
    public var pressedScale: CGFloat

    // Local gold token fallbacks so we don't depend on external BrandColors
    private var goldGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.98, green: 0.89, blue: 0.55), // light gold
                Color(red: 0.86, green: 0.72, blue: 0.28)  // deep gold
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    private var rimHighlight: Color { Color.white.opacity(0.30) }
    private var rimShadow: Color { Color.black.opacity(0.25) }

    public init(height: CGFloat = 36, horizontalPadding: CGFloat = 18, pressedScale: CGFloat = 0.97) {
        self.height = height
        self.horizontalPadding = horizontalPadding
        self.pressedScale = pressedScale
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(Color.black.opacity(0.92))
            .padding(.horizontal, horizontalPadding)
            .frame(height: height)
            .background(
                Capsule()
                    .fill(goldGradient)
                    .overlay(
                        LinearGradient(colors: [Color.white.opacity(0.16), .clear], startPoint: .top, endPoint: .center)
                            .clipShape(Capsule())
                    )
                    .overlay(
                        Capsule().stroke(rimHighlight, lineWidth: 0.8)
                    )
                    .overlay(
                        Capsule().stroke(rimShadow, lineWidth: 0.6)
                    )
            )
            .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 2)
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
