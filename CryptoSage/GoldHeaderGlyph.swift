import SwiftUI

public struct GoldHeaderGlyph: View {
    public let systemName: String
    public var size: CGFloat = 20
    public var body: some View {
        ZStack {
            Circle()
                .fill(BrandColors.goldDiagonalGradient)
                .overlay(
                    Circle().inset(by: 0.6)
                        .stroke(BrandColors.goldStrokeHighlight, lineWidth: 0.8)
                )
                .overlay(
                    Circle()
                        .stroke(BrandColors.goldStrokeShadow, lineWidth: 0.6)
                )
            Image(systemName: systemName)
                .font(.system(size: size * 0.65, weight: .semibold))
                .foregroundColor(.black.opacity(0.92))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

public struct GoldHeaderGlyphSmall: View {
    public let systemName: String
    public var body: some View {
        GoldHeaderGlyph(systemName: systemName, size: 18)
    }
}
