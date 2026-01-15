import SwiftUI

// Shared brand gradient and color helpers used across Home headers and buttons
extension ShapeStyle where Self == LinearGradient {
    /// Gold gradient used for icons and accents in headers
    static var csGold: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 1.0, green: 0.92, blue: 0.30),
                Color.orange
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension Color {
    /// Solid gold that pairs with the csGold gradient
    static var csGoldSolid: Color { Color(red: 1.0, green: 0.92, blue: 0.30) }
}

extension ShapeStyle where Self == Color {
    /// Enables shorthand usage like `.foregroundStyle(.csGoldSolid)`
    static var csGoldSolid: Color { Color.csGoldSolid }
}

// Secondary CTA button style used by headers (e.g., "All News", "All Events")
struct CSSecondaryCTAButtonStyle: ButtonStyle {
    var height: CGFloat = 28
    var cornerRadius: CGFloat = 10
    var horizontalPadding: CGFloat = 10
    var font: Font = .caption.weight(.semibold)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundStyle(Color.csGoldSolid)
            .frame(height: height)
            .padding(.horizontal, horizontalPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.csGoldSolid.opacity(configuration.isPressed ? 0.9 : 0.6), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}
