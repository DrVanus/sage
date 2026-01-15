import SwiftUI

public struct GridHeatMapView: View {
    public let metrics: [BadgeScoreMetric]
    public let palette: BadgePalette
    public let badge: Badge
    public let currentTimeframe: Timeframe
    public let showBars: Bool
    public let maxColumns: Int
    
    public init(
        metrics: [BadgeScoreMetric],
        palette: BadgePalette,
        badge: Badge,
        currentTimeframe: Timeframe,
        showBars: Bool,
        maxColumns: Int = 3
    ) {
        self.metrics = metrics
        self.palette = palette
        self.badge = badge
        self.currentTimeframe = currentTimeframe
        self.showBars = showBars
        self.maxColumns = maxColumns
    }
    
    public var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: maxColumns)
        
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(metrics) { metric in
                GridTile(
                    metric: metric,
                    palette: palette,
                    badge: badge,
                    currentTimeframe: currentTimeframe,
                    showBars: showBars
                )
            }
        }
        .padding(.horizontal, 8)
    }
    
    private struct GridTile: View {
        let metric: BadgeScoreMetric
        let palette: BadgePalette
        let badge: Badge
        let currentTimeframe: Timeframe
        let showBars: Bool
        
        var body: some View {
            VStack(spacing: 2) {
                Text(metric.short)
                    .font(.caption2)
                    .foregroundColor(labelColors[metric] ?? .secondary)
                    .padding(.bottom, 2)
                
                if showBars {
                    let changeValue = change(for: metric, tf: currentTimeframe)
                    let boundValue = bound(for: changeValue)
                    let tileColor = color(for: changeValue, bound: boundValue, palette: palette)
                    
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(tileColor)
                            .frame(height: geo.size.height * CGFloat(abs(changeValue)))
                            .frame(maxHeight: geo.size.height)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.black.opacity(labelOutlineOpacity), lineWidth: 0.5)
                            )
                    }
                } else {
                    let value = valueAbbrev(metric.value(for: badge))
                    Text(value)
                        .font(.caption2)
                        .foregroundColor(labelColors[metric] ?? .secondary)
                }
                
                Text(condensedPercentString(change(for: metric, tf: currentTimeframe)))
                    .font(.caption2)
                    .foregroundColor(badgeLabelColors[metric] ?? .secondary)
            }
            .padding(4)
            .background(Color.clear)
            .cornerRadius(6)
        }
    }
}
