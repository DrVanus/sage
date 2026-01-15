import SwiftUI

/// A compact capsule badge suitable for showing transport state (WS/REST) and cooldown.
public struct TransportBadge: View {
    public let text: String
    public let tint: Color
    public var accessibilityLabel: String?

    public init(text: String, tint: Color, accessibilityLabel: String? = nil) {
        self.text = text
        self.tint = tint
        self.accessibilityLabel = accessibilityLabel
    }

    public var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(tint.opacity(0.15))
            )
            .foregroundStyle(tint)
            .accessibilityLabel(Text(accessibilityLabel ?? text))
    }
}

#Preview("TransportBadge – samples") {
    VStack(spacing: 12) {
        TransportBadge(text: "WS · Coinbase", tint: .green, accessibilityLabel: "WebSocket · Coinbase")
        TransportBadge(text: "WS · Binance", tint: .green, accessibilityLabel: "WebSocket · Binance")
        TransportBadge(text: "REST", tint: .teal, accessibilityLabel: "REST polling")
        TransportBadge(text: "REST · Cooldown", tint: .orange, accessibilityLabel: "REST polling · cooldown 14s")
    }
    .padding()
}
