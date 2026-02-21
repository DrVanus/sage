import SwiftUI

public struct SimplePercentChip: View {
    public let text: String
    public let fontSize: CGFloat
    public let textColor: Color
    public let backdrop: Color
    public let minWidth: CGFloat
    public let maxWidth: CGFloat
    public let hPad: CGFloat
    public let vPad: CGFloat

    public init(
        text: String,
        fontSize: CGFloat,
        textColor: Color,
        backdrop: Color,
        minWidth: CGFloat,
        maxWidth: CGFloat,
        hPad: CGFloat,
        vPad: CGFloat
    ) {
        self.text = text
        self.fontSize = fontSize
        self.textColor = textColor
        self.backdrop = backdrop
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.hPad = hPad
        self.vPad = vPad
    }

    public var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundColor(textColor)
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .allowsTightening(true)
            .padding(.horizontal, max(4, hPad))
            .padding(.vertical, max(2, vPad))
            .frame(maxWidth: maxWidth)
            .fixedSize(horizontal: true, vertical: false)
            .background(backdrop, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
    }
}
