import SwiftUI

public struct BrandColors {
    public static let goldLight = Color(red: 1.0, green: 0.894, blue: 0.454) // #FFE58C
    public static let goldBase = Color(red: 0.894, green: 0.745, blue: 0.204)  // #E4BF34
    public static let goldDark = Color(red: 0.682, green: 0.561, blue: 0.0)    // #AD8F00
    
    public static let goldStrokeHighlight = Color(red: 1.0, green: 0.953, blue: 0.678) // #FFF3AC
    public static let goldStrokeShadow = Color(red: 0.647, green: 0.541, blue: 0.0)    // #A58500
    
    public static let goldBorder = Color(red: 0.831, green: 0.718, blue: 0.243) // #D4B83E
    public static let goldShadow = Color(red: 0.682, green: 0.561, blue: 0.0)    // #AD8F00
}

/// A reusable, brand-styled segmented pill for chips and segmented controls.
/// - selected: filled gold gradient with rim and soft top gloss
/// - unselected: subtle dark fill with gold stroke
/// - pressed: slightly darker gradient
public struct GoldPillStyle: ButtonStyle {
    public var selected: Bool
    public var cornerRadius: CGFloat = 10

    public init(selected: Bool, cornerRadius: CGFloat = 10) {
        self.selected = selected
        self.cornerRadius = cornerRadius
    }

    public func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed
        return configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(selected ? .black : .white.opacity(0.92))
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(background(isPressed: isPressed))
            .overlay(rim)
            .overlay(topGloss)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .animation(.easeInOut(duration: 0.12), value: isPressed)
    }

    // MARK: - Layers
    private var rim: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(selected ? BrandColors.goldStrokeHighlight.opacity(0.7) : BrandColors.goldBorder.opacity(0.35), lineWidth: selected ? 0.9 : 0.8)
    }

    private var topGloss: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(LinearGradient(colors: [Color.white.opacity(selected ? 0.16 : 0.10), .clear], startPoint: .top, endPoint: .center))
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func background(isPressed: Bool) -> some View {
        if selected {
            let grad = LinearGradient(colors: [BrandColors.goldLight, BrandColors.goldBase, BrandColors.goldDark], startPoint: .top, endPoint: .bottom)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(grad)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(LinearGradient(colors: [BrandColors.goldStrokeHighlight, BrandColors.goldStrokeShadow], startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
                )
                .shadow(color: BrandColors.goldShadow.opacity(0.35), radius: selected ? 4 : 2, x: 0, y: 1)
                .opacity(isPressed ? 0.94 : 1)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(LinearGradient(colors: [BrandColors.goldBorder.opacity(0.55), Color.white.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(0.25), radius: 2, x: 0, y: 1)
                .opacity(isPressed ? 0.85 : 1)
        }
    }
}

public extension View {
    /// Apply a gold pill background/overlay without altering font/padding.
    func goldPillBackground(selected: Bool, cornerRadius: CGFloat = 10) -> some View {
        self.background(
            Group {
                if selected {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(LinearGradient(colors: [BrandColors.goldLight, BrandColors.goldBase, BrandColors.goldDark], startPoint: .top, endPoint: .bottom))
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .stroke(LinearGradient(colors: [BrandColors.goldStrokeHighlight, BrandColors.goldStrokeShadow], startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
                        )
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .stroke(LinearGradient(colors: [BrandColors.goldBorder.opacity(0.55), Color.white.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
                        )
                }
            }
        )
    }
}
