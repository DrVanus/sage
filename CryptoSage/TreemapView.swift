import SwiftUI

public struct TreemapView: View {
    public let data: [TreemapValue]
    public let palette: Palette
    public let locale: Locale

    public init(data: [TreemapValue], palette: Palette, locale: Locale = .current) {
        self.data = data
        self.palette = palette
        self.locale = locale
    }

    public var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let nodes = squarify(data: data, bounds: bounds)
            ZStack {
                ForEach(nodes, id: \.value.id) { node in
                    TreemapTile(node: node, palette: palette, locale: locale)
                }
            }
        }
    }

    private struct TreemapTile: View {
        let node: TreemapNode
        let palette: Palette
        let locale: Locale

        var body: some View {
            let bound = bound(for: node)
            let color = color(for: node, bound: bound, palette: palette)
            let labelColor = labelColors[palette] ?? .white
            let badgeLabelColor = badgeLabelColors[palette] ?? .white
            let percent = condensedPercentString(value: node.value.value, total: node.total, locale: locale)
            let valueAbbreviation = valueAbbrev(value: node.value.value, locale: locale)

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(color)
                    .frame(width: bound.width, height: bound.height)
                    .overlay(
                        Rectangle()
                            .stroke(labelColor.opacity(labelOutlineOpacity), lineWidth: 1)
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(node.value.label)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(labelColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(valueAbbreviation)
                        .font(.caption2)
                        .foregroundColor(labelColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(percent)
                        .font(.caption2)
                        .foregroundColor(labelColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .padding(4)
                .frame(width: bound.width, height: bound.height, alignment: .topLeading)
                .background(Color.black.opacity(0.15))
                if let badge = node.value.badge {
                    Text(badge)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(badgeLabelColor)
                        .padding(badgeMetrics.padding)
                        .background(badgeMetrics.background)
                        .cornerRadius(badgeMetrics.cornerRadius)
                        .padding(4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            .frame(width: bound.width, height: bound.height)
            .onTapGesture {
                Haptics.selectionFeedback()
            }
            .position(x: bound.midX, y: bound.midY)
        }
    }
}
