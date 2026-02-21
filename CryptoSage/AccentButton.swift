import SwiftUI

public struct AccentButtonStyle: ButtonStyle {
    public var height: CGFloat = 34
    public var cornerRadius: CGFloat = 12
    public var horizontalPadding: CGFloat = 14
    public var font: Font = .system(size: 14, weight: .semibold)
    public var tint: Color = .yellow
    public var backgroundOpacity: Double = 0.12
    public var ringOpacity: Double = 0.85
    public var pressedScale: CGFloat = 0.97
    public var pressedOpacity: Double = 0.9
    
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
            .animation(.spring(response: 0.25, dampingFraction: 0.9), value: configuration.isPressed)
    }
}

// Note:
// To create a dimmed variant of this button style, callers can pass a lower ringOpacity value
// or use a tint color with reduced opacity. A convenience extension for a dimmed variant is not provided here.

#Preview("AccentButtonStyle") {
    VStack(spacing: 12) {
        Button("Primary Action") {}
            .buttonStyle(AccentButtonStyle())
        Button("Dimmed Action") {}
            .buttonStyle(AccentButtonStyle(tint: .yellow.opacity(0.9), backgroundOpacity: 0.08, ringOpacity: 0.4))
    }
    .padding()
    .background(Color.black)
    .preferredColorScheme(.dark)
}
