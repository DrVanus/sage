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
            .font(.system(size: fontSize, weight: .semibold))
            .monospacedDigit()
            .foregroundColor(textColor)
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.7)
            .allowsTightening(true)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, hPad)
            .padding(.vertical, vPad)
            .background(backdrop, in: Capsule())
            .overlay(Capsule().stroke(Color.black.opacity(0.18), lineWidth: 0.6))
            .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
            .frame(minWidth: minWidth, maxWidth: maxWidth, alignment: .center)
    }
}
