import SwiftUI

// Capsule CTA style - black in light mode, gold in dark mode (matches market page)
public struct GoldCapsuleButtonStyle: ButtonStyle {
    public var height: CGFloat
    public var horizontalPadding: CGFloat
    public var pressedScale: CGFloat

    public init(height: CGFloat = 36, horizontalPadding: CGFloat = 18, pressedScale: CGFloat = 0.97) {
        self.height = height
        self.horizontalPadding = horizontalPadding
        self.pressedScale = pressedScale
    }

    public func makeBody(configuration: Configuration) -> some View {
        PremiumPrimaryCTAStyle(
            height: height,
            horizontalPadding: horizontalPadding,
            cornerRadius: height / 2,
            pressedScale: pressedScale,
            font: .system(size: 14, weight: .semibold)
        ).makeBody(configuration: configuration)
    }
}
