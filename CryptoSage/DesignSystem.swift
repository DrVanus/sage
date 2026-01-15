import SwiftUI

// MARK: - Design System Tokens
enum DS {
    enum Fonts {
        // Primary price display (top ticker)
        static let priceXL: Font = .system(size: 26, weight: .bold, design: .rounded)
        // Badge/crosshair price labels
        static let priceBadge: Font = .system(size: 12, weight: .semibold, design: .rounded)
        static let crosshairPrice: Font = .system(size: 14, weight: .semibold, design: .rounded)
        static let crosshairDate: Font = .system(size: 11, weight: .regular, design: .rounded)
        // Axis labels and chips
        static let axis: Font = .caption2
        static let chip: Font = .caption2
        // Order book
        static let orderBookHeader: Font = .caption
        static let orderBookNumber: Font = .system(size: 12, weight: .semibold, design: .rounded)
    }

    enum Spacing {
        static let orderBookRowHeight: CGFloat = 22
        static let orderBookRowSpacing: CGFloat = 4
        static let chipHorizontal: CGFloat = 14
        static let chipVertical: CGFloat = 6
    }

    enum Colors {
        static let textPrimary = Color.white
        static let textSecondary = Color.gray.opacity(0.95)
        static let grid = Color.white.opacity(0.10)
        static let tick = Color.white.opacity(0.30)
        static let axisLabel = Color.gray.opacity(0.95)
        static let badgeBackground = Color.black.opacity(0.85)
        static let badgeStroke = Color.yellow.opacity(0.6)
        static let chartFillTop = Color.yellow.opacity(0.30)
        static let chartFillMid = Color.yellow.opacity(0.15)
        static let chartFillLow = Color.yellow.opacity(0.05)
        static let chartFillZero = Color.clear
        static let bid = Color.green
        static let ask = Color.red
        static let gold = Color.yellow
    }
}

// MARK: - Numeric text helpers
struct NumericText: ViewModifier {
    let font: Font
    let color: Color
    func body(content: Content) -> some View {
        content
            .font(font)
            .monospacedDigit()
            .foregroundColor(color)
    }
}

extension View {
    func numeric(_ font: Font = DS.Fonts.orderBookNumber, color: Color = DS.Colors.textPrimary) -> some View {
        modifier(NumericText(font: font, color: color))
    }
}
