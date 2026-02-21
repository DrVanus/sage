import SwiftUI

public enum PremiumGoldTokens {
    public static let base      = Color(red: 0.98, green: 0.82, blue: 0.20)
    public static let deep      = Color(red: 0.85, green: 0.68, blue: 0.12)
    public static let highlight = Color(red: 1.00, green: 0.90, blue: 0.55)
    public static let strokeHi  = Color.white.opacity(0.22)
    public static let strokeLo  = Color.black.opacity(0.18)
}

public struct PremiumGoldTagStyle: ButtonStyle {
    public var selected: Bool
    public var height: CGFloat = 26
    public var horizontalPadding: CGFloat = 12
    public var font: Font = .system(size: 12, weight: .semibold)

    public init(selected: Bool, height: CGFloat = 26, horizontalPadding: CGFloat = 12, font: Font = .system(size: 12, weight: .semibold)) {
        self.selected = selected
        self.height = height
        self.horizontalPadding = horizontalPadding
        self.font = font
    }

    public func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .font(font)
            .foregroundColor(selected ? Color.black.opacity(0.92) : PremiumGoldTokens.base)
            .padding(.horizontal, horizontalPadding)
            .frame(height: height)
            .background(
                Capsule(style: .continuous).fill(
                    selected
                    ? LinearGradient(colors: [PremiumGoldTokens.highlight, PremiumGoldTokens.base, PremiumGoldTokens.deep], startPoint: .topLeading, endPoint: .bottomTrailing)
                    : LinearGradient(colors: [Color.black.opacity(0.50), Color.black.opacity(0.50)], startPoint: .top, endPoint: .bottom)
                )
            )
            .overlay(
                Group {
                    if selected {
                        Capsule(style: .continuous)
                            .inset(by: 0.6)
                            .stroke(PremiumGoldTokens.strokeHi, lineWidth: 0.8)
                        Capsule(style: .continuous)
                            .stroke(PremiumGoldTokens.strokeLo, lineWidth: 0.6)
                    } else {
                        Capsule(style: .continuous)
                            .stroke(PremiumGoldTokens.base.opacity(0.9), lineWidth: 1.1)
                    }
                }
            )
            .opacity(pressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.12), value: pressed)
    }
}

public extension View {
    func premiumGoldTag(selected: Bool, height: CGFloat = 26, horizontalPadding: CGFloat = 12, font: Font = .system(size: 12, weight: .semibold)) -> some View {
        self.buttonStyle(PremiumGoldTagStyle(selected: selected, height: height, horizontalPadding: horizontalPadding, font: font))
    }
}
