import SwiftUI

// MARK: - Shared Color Tokens
extension Color {
    static let gold = Color(red: 212/255, green: 175/255, blue: 55/255)
}

// MARK: - Shared Gradient Tokens
var goldButtonGradient: LinearGradient {
    LinearGradient(
        gradient: Gradient(stops: [
            .init(color: Color(red: 1.00, green: 0.90, blue: 0.45), location: 0.0),
            .init(color: Color(red: 1.00, green: 0.82, blue: 0.25), location: 0.52),
            .init(color: Color(red: 0.88, green: 0.68, blue: 0.20), location: 1.0)
        ]),
        startPoint: .top,
        endPoint: .bottom
    )
}

var redButtonGradient: LinearGradient {
    LinearGradient(
        gradient: Gradient(stops: [
            .init(color: Color(red: 0.95, green: 0.25, blue: 0.25), location: 0.0),
            .init(color: Color(red: 0.88, green: 0.12, blue: 0.12), location: 0.52),
            .init(color: Color(red: 0.70, green: 0.05, blue: 0.05), location: 1.0)
        ]),
        startPoint: .top,
        endPoint: .bottom
    )
}

var chipGoldGradient: LinearGradient {
    LinearGradient(
        gradient: Gradient(stops: [
            .init(color: Color(red: 0.98, green: 0.82, blue: 0.24), location: 0.0),
            .init(color: Color.gold, location: 0.55),
            .init(color: Color(red: 0.73, green: 0.52, blue: 0.12), location: 1.0)
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

var ctaRimStrokeGradient: LinearGradient {
    LinearGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0.12)], startPoint: .top, endPoint: .bottom)
}

var ctaRimStrokeGradientRed: LinearGradient {
    LinearGradient(
        colors: [
            Color(red: 1.0, green: 0.35, blue: 0.35).opacity(0.55),
            Color(red: 1.0, green: 0.35, blue: 0.35).opacity(0.18)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

var ctaBottomShade: LinearGradient {
    LinearGradient(colors: [Color.clear, Color.black.opacity(0.12)], startPoint: .center, endPoint: .bottom)
}
