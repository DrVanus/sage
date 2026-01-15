import SwiftUI

public struct WeightedHeatMapView: View {
    public let symbols: [String]
    public let timeFrame: String
    public let palette: [Color]
    public let showValue: Bool

    public init(symbols: [String], timeFrame: String, palette: [Color], showValue: Bool) {
        self.symbols = symbols
        self.timeFrame = timeFrame
        self.palette = palette
        self.showValue = showValue
    }

    public var body: some View {
        VStack(spacing: 4) {
            ForEach(symbols, id: \.self) { symbol in
                BarTile(
                    symbol: symbol,
                    tf: timeFrame,
                    palette: palette,
                    showValue: showValue
                )
            }
        }
    }

    private struct BarTile: View {
        let symbol: String
        let tf: String
        let palette: [Color]
        let showValue: Bool

        var body: some View {
            let changeValue = change(for: symbol, tf: tf)
            let boundValue = bound(for: changeValue)
            let barColor = color(for: boundValue, palette: palette)
            let labelColor = labelColors[boundValue]
            let badgeLabelColor = badgeLabelColors[boundValue]

            HStack(alignment: .center, spacing: 8) {
                Text(symbol)
                    .font(.caption)
                    .foregroundColor(labelColor)
                    .frame(width: 50, alignment: .leading)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 12)

                        Capsule()
                            .fill(barColor)
                            .frame(width: CGFloat(abs(changeValue)) * geometry.size.width, height: 12)
                            .animation(.easeInOut, value: changeValue)
                    }
                }
                .frame(height: 12)

                if showValue {
                    Text(changeValue.condensedPercentString)
                        .font(.caption2)
                        .foregroundColor(labelColor)
                        .padding(.horizontal, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(labelColor.opacity(labelOutlineOpacity), lineWidth: 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(badgeLabelColor)
                                )
                        )
                        .accessibilityLabel("\(symbol) change")
                        .accessibilityValue(valueAbbrev(changeValue))
                }
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            .onTapGesture {
                Haptics.impact(.medium)
            }
        }
    }
}
