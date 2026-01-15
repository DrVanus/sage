import SwiftUI

public struct AccentButtonStyle: ButtonStyle {
    public var height: CGFloat
    public var cornerRadius: CGFloat
    public var horizontalPadding: CGFloat
    public var font: Font
    public var tint: Color
    public var backgroundOpacity: Double
    public var ringOpacity: Double
    public var pressedScale: CGFloat
    public var pressedOpacity: Double

    public init(
        height: CGFloat = 34,
        cornerRadius: CGFloat = 12,
        horizontalPadding: CGFloat = 14,
        font: Font = .system(size: 14, weight: .semibold),
        tint: Color = .yellow,
        backgroundOpacity: Double = 0.12,
        ringOpacity: Double = 0.85,
        pressedScale: CGFloat = 0.97,
        pressedOpacity: Double = 0.9
    ) {
        self.height = height
        self.cornerRadius = cornerRadius
        self.horizontalPadding = horizontalPadding
        self.font = font
        self.tint = tint
        self.backgroundOpacity = backgroundOpacity
        self.ringOpacity = ringOpacity
        self.pressedScale = pressedScale
        self.pressedOpacity = pressedOpacity
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundColor(tint)
            .frame(height: height)
            .padding(.horizontal, horizontalPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(backgroundOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(tint.opacity(ringOpacity), lineWidth: 1.2)
            )
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
    }
}

// Usage: Button("Action") { ... }.buttonStyle(AccentButtonStyle())
// To de-emphasize, pass a slightly lower ringOpacity or a tint with reduced opacity.
