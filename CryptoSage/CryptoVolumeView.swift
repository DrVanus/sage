import Foundation
import SwiftUI
import Charts

struct CryptoVolumeView: View {
    // Input data and configuration
    let dataPoints: [ChartDataPoint]
    let xDomain: ClosedRange<Date>
    let halfCandleSpan: TimeInterval
    let volumeYMax: Double

    // Crosshair bindings (child updates parent)
    @Binding var showCrosshair: Bool
    @Binding var crosshairDataPoint: ChartDataPoint?
    // Normalized x position (0-1) from main chart for pixel-perfect crosshair alignment
    @Binding var crosshairXFraction: CGFloat

    // Desired height for the volume view (defaults typically ~52)
    let height: CGFloat
    
    // Optional volume moving average period (0 = disabled)
    var volumeMAPeriod: Int = 0
    
    // Trailing inset to match main chart's Y-axis width for perfect crosshair alignment
    var trailingInset: CGFloat = 40
    
    // Leading inset to match main chart's plot area origin
    var leadingInset: CGFloat = 4
    
    // Whether to show x-axis labels (true when this is the bottom-most chart)
    var showXAxis: Bool = false
    
    // Chart interval for x-axis label formatting
    var interval: ChartInterval = .oneDay
    
    // Actual plot width from main chart for consistent x-axis tick calculation
    var plotWidth: CGFloat = 300

    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    // MARK: - Clean, professional color configuration (adaptive for light/dark)
    // Muted colors for a cleaner, less distracting appearance
    private let upColorBase = Color(red: 0.18, green: 0.65, blue: 0.42)     // Softer green
    private let downColorBase = Color(red: 0.78, green: 0.28, blue: 0.28)   // Softer red
    private var neutralColor: Color { isDark ? Color(white: 0.45) : Color(white: 0.60) }
    private var zeroVolumeColor: Color { isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04) }
    
    // Opacity range for intensity-based coloring
    // Light mode uses slightly higher opacity for visibility against bright backgrounds
    private var minOpacity: Double { isDark ? 0.70 : 0.55 }
    private var maxOpacity: Double { isDark ? 0.88 : 0.75 }
    
    // Minimum bar height as percentage of Y-max (ensures all bars are visible)
    // 12% minimum height for cleaner, less cluttered appearance
    private let minBarHeightPercent: Double = 0.12
    
    // Percentile to use for Y-axis scaling (88th = ignore top 12% outliers)
    // Tighter scaling for fuller chart fill
    private let yAxisPercentile: Double = 0.88
    
    /// Format volume value for compact Y-axis display (e.g., "1.2M", "500K")
    static func formatVolAxis(_ v: Double) -> String {
        let abs = Swift.abs(v)
        if abs >= 1_000_000_000 { return String(format: "%.0fB", v / 1_000_000_000) }
        if abs >= 1_000_000 { return String(format: "%.0fM", v / 1_000_000) }
        if abs >= 1_000 { return String(format: "%.0fK", v / 1_000) }
        return String(format: "%.0f", v)
    }
    
    var body: some View {
        // Show volume chart directly without placeholder
        volumeChartContent
    }
    
    @ViewBuilder
    private var volumeChartContent: some View {
        // Use data points directly - parent handles freezing
        let points = dataPoints
        
        // Use passed xDomain directly to ensure perfect alignment with main price chart
        let domain = xDomain
        
        // Compute volume stats for Y-axis scaling
        let volumeStats = computeVolumeStats()
        let effectiveVolumeMax = volumeStats.percentileMax
        let minDisplayVolume = effectiveVolumeMax * minBarHeightPercent
        
        // Compute volume moving average if enabled
        let volumeMAPoints: [(Date, Double)] = volumeMAPeriod > 1 ? computeVolumeMA(period: volumeMAPeriod) : []
        
        Chart {
            // Volume bars with TradingView-style gradient and intensity coloring
            ForEach(Array(points.enumerated()), id: \.element.id) { idx, pt in
                let prevClose = (idx > 0 ? points[idx-1].close : points[idx].close)
                let isUp = pt.close >= prevClose
                
                // Determine if this is a zero-volume candle
                let hasVolume = pt.volume > 0
                
                // Apply minimum bar height - ensures all bars are visible
                // Bars above percentile max are capped at 100%
                let displayVolume: Double = {
                    if !hasVolume {
                        return minDisplayVolume * 0.3  // Zero volume gets minimal placeholder
                    }
                    // Ensure minimum visibility, cap at effectiveMax for outliers
                    return max(minDisplayVolume, min(pt.volume, effectiveVolumeMax * 1.1))
                }()
                
                // Compute relative intensity (0-1) based on volume relative to percentile max
                let intensity: Double = {
                    if !hasVolume { return 0.15 }  // Low intensity for zero volume
                    let raw = pt.volume / effectiveVolumeMax
                    // Clamp between 0.5 and 1.0 for more uniform, cleaner appearance
                    return max(0.5, min(1.0, raw))
                }()
                
                let opacity = minOpacity + (maxOpacity - minOpacity) * intensity
                
                let baseColor: Color = {
                    if !hasVolume { return zeroVolumeColor }
                    if idx == 0 { return neutralColor }
                    return isUp ? upColorBase : downColorBase
                }()
                
                // Calculate bar width - use narrower bars (70% width) to create visible gaps
                // This improves crosshair alignment and gives a cleaner professional look
                let barHalfWidth: TimeInterval = {
                    if points.count >= 2 {
                        let interval = points.count > 1 
                            ? points[min(idx + 1, points.count - 1)].date.timeIntervalSince(points[max(idx - 1, 0)].date) / 2
                            : halfCandleSpan * 2
                        return interval * 0.35  // 35% of interval on each side = 70% width total
                    }
                    return halfCandleSpan
                }()
                
                let startDate: Date = {
                    let barStart = pt.date.addingTimeInterval(-barHalfWidth)
                    return max(domain.lowerBound, barStart)
                }()

                let endDate: Date = {
                    let barEnd = pt.date.addingTimeInterval(barHalfWidth)
                    return min(domain.upperBound, barEnd)
                }()

                // Main volume bar with clean 2-stop gradient (flat, professional look)
                RectangleMark(
                    xStart: .value("Start", startDate),
                    xEnd:   .value("End",   endDate),
                    yStart: .value("Zero", 0),
                    yEnd:   .value("Volume", displayVolume)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            baseColor.opacity(hasVolume ? opacity : 0.08),      // Solid top
                            baseColor.opacity(hasVolume ? opacity * 0.5 : 0.03) // Fade at bottom
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            
            // Volume Moving Average line (if enabled)
            if volumeMAPeriod > 1 && !volumeMAPoints.isEmpty {
                ForEach(Array(volumeMAPoints.enumerated()), id: \.offset) { _, point in
                    LineMark(
                        x: .value("Time", point.0),
                        y: .value("MA", min(point.1, effectiveVolumeMax * 1.1))  // Cap MA line too
                    )
                    .foregroundStyle(Color.orange.opacity(0.85))
                    .lineStyle(StrokeStyle(lineWidth: 1.2))
                    .interpolationMethod(.monotone)
                }
            }

            // CROSSHAIR: Use native Chart marks for guaranteed alignment
            if showCrosshair, let cp = crosshairDataPoint {
                // Vertical crosshair line
                RuleMark(x: .value("Time", cp.date))
                    .foregroundStyle(isDark ? Color.white.opacity(0.6) : Color.black.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [4, 3]))
                
                // Crosshair dot on volume bar
                if let nearest = findClosestDataPoint(to: cp.date),
                   let idx = points.firstIndex(where: { $0.date == nearest.date }) {
                    let prevClose = idx > 0 ? points[idx - 1].close : nearest.close
                    let isUp = nearest.close >= prevClose
                    let dotColor = isUp ? upColorBase : downColorBase
                    let displayVol = max(effectiveVolumeMax * minBarHeightPercent, min(nearest.volume, effectiveVolumeMax * 1.1))
                    
                    PointMark(x: .value("Time", cp.date), y: .value("Vol", displayVol))
                        .symbolSize(40)
                        .foregroundStyle(dotColor)
                }
            }
        }
        .chartXScale(domain: domain)
        .chartXScale(range: .plotDimension(padding: 24))
        .chartYScale(domain: 0...(effectiveVolumeMax * 1.12))
        .chartXAxis {
            let xAxis = ChartXAxisProvider(interval: interval, domain: xDomain, plotWidth: plotWidth, uses24hClock: ChartDateFormatters.uses24hClock)
            AxisMarks(values: xAxis.ticks()) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.75, dash: [5, 3]))
                    .foregroundStyle(DS.Colors.grid.opacity(0.5))
                if showXAxis {
                    AxisTick(stroke: StrokeStyle(lineWidth: 1))
                        .foregroundStyle(DS.Colors.tick.opacity(0.4))
                    AxisValueLabel {
                        if let dt = value.as(Date.self) {
                            Text(xAxis.label(for: dt))
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(DS.Colors.axisLabel)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }
            }
        }
        // Y-axis for volume data
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                    .foregroundStyle(.clear)
                AxisTick(stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(DS.Colors.tick.opacity(0.5))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(v.formatted(.number.notation(.compactName)))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(DS.Colors.axisLabel)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
        }
        .chartPlotStyle { plotArea in
            plotArea
                .background(
                    LinearGradient(
                        colors: [
                            DS.Colors.chartBgTop.opacity(0.85),
                            DS.Colors.chartBgBottom.opacity(0.75)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(DS.Colors.grid.opacity(0.12))
                        .frame(height: 0.5)
                        .allowsHitTesting(false)
                }
        }
        // ALIGNMENT FIX: Remove explicit width constraint - let padding handle alignment
        // The chart takes full width, and padding on leading/trailing sides will
        // make the plot area match the main chart's plot area exactly
        // Gesture handler and crosshair overlay for volume chart
        .chartOverlay { proxy in
            // NOTE: Crosshair line and dot are now rendered inside Chart using RuleMark/PointMark
            GeometryReader { geo in
                if let plotAnchor = proxy.plotFrame {
                    let plotFrame = geo[plotAnchor]
                    let origin = plotFrame.origin
                    
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    #if os(iOS)
                                    if !showCrosshair {
                                        ChartHaptics.shared.begin()
                                    }
                                    #endif
                                    
                                    let rawX = value.location.x - origin.x
                                    let x = min(max(rawX, 0), plotFrame.width)
                                    if let date: Date = proxy.value(atX: x) {
                                        if let nearest = findClosestDataPoint(to: date) {
                                            #if os(iOS)
                                            if crosshairDataPoint?.id != nearest.id {
                                                ChartHaptics.shared.tickIfNeeded()
                                            }
                                            #endif
                                            crosshairDataPoint = nearest
                                            crosshairXFraction = plotFrame.width > 0 ? x / plotFrame.width : 0
                                            showCrosshair = true
                                        }
                                    }
                                }
                                .onEnded { _ in
                                    #if os(iOS)
                                    ChartHaptics.shared.end()
                                    #endif
                                    showCrosshair = false
                                    crosshairXFraction = 0
                                }
                        )
                }
            }
        }
        // Y-axis labels are now rendered natively by Swift Charts (see .chartYAxis above)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) {
            // Premium divider line at top with gradient fade for visual separation
            // Adaptive for light/dark mode
            LinearGradient(
                colors: [
                    DS.Colors.grid.opacity(0.1),
                    DS.Colors.grid.opacity(0.5),
                    DS.Colors.grid.opacity(0.5),
                    DS.Colors.grid.opacity(0.1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)
        }
        .transaction { txn in txn.animation = nil }
        .frame(height: height)
        // Force chart redraw when geometry changes (e.g., after rotation)
        .id("Vol-\(Int(plotWidth))-\(Int(height))")
    }
    
    // MARK: - Find Closest Data Point for Crosshair
    
    private func findClosestDataPoint(to date: Date) -> ChartDataPoint? {
        // Filter to only visible points within xDomain to prevent snapping outside chart area
        let visiblePoints = dataPoints.filter { $0.date >= xDomain.lowerBound && $0.date <= xDomain.upperBound }
        guard !visiblePoints.isEmpty else { return nil }
        
        var closest: ChartDataPoint? = nil
        var minDiff = Double.infinity
        
        for point in visiblePoints {
            let diff = abs(point.date.timeIntervalSince(date))
            if diff < minDiff {
                minDiff = diff
                closest = point
            }
        }
        
        return closest
    }
    
    // MARK: - Volume Statistics with Consistent 98th Percentile Scaling
    
    private struct VolumeStats {
        let percentileMax: Double   // Effective max for Y-axis scaling (98th percentile)
        let absoluteMax: Double     // True maximum (for reference)
        let mean: Double            // Average volume
    }
    
    private func computeVolumeStats() -> VolumeStats {
        let lower = xDomain.lowerBound
        let upper = xDomain.upperBound
        
        // Collect volumes within visible range
        var visibleVolumes: [Double] = []
        for pt in dataPoints {
            if pt.date >= lower && pt.date <= upper && pt.volume > 0 {
                visibleVolumes.append(pt.volume)
            }
        }
        
        // FALLBACK: If no volumes found within xDomain (timing mismatch), use ALL data points
        // This prevents empty/flat volume charts when domain doesn't match data timestamps
        if visibleVolumes.isEmpty {
            visibleVolumes = dataPoints.compactMap { $0.volume > 0 ? $0.volume : nil }
        }
        
        // If still no volume data (all zeros), use volumeYMax as fallback
        guard !visibleVolumes.isEmpty else {
            let fallback = max(volumeYMax, 1)
            return VolumeStats(percentileMax: fallback, absoluteMax: fallback, mean: fallback)
        }
        
        // Sort volumes for percentile calculation
        let sortedVolumes = visibleVolumes.sorted()
        let count = sortedVolumes.count
        let absoluteMax = sortedVolumes.last ?? 1
        let mean = sortedVolumes.reduce(0, +) / Double(count)
        
        // CONSISTENCY FIX: Use 98th percentile (same as volumeCeiling in CryptoChartView)
        // This ensures volume scaling is consistent between integrated overlay and separate pane
        // Previous approach (mean + 1.2 stdDev) caused different scales between views
        let percentileIndex = Int(Double(count - 1) * 0.98)
        let safeIndex = max(0, min(count - 1, percentileIndex))
        var effectiveMax = sortedVolumes[safeIndex]
        
        // Ensure effective max is reasonable:
        // - At least 1.0 to prevent division by zero
        // - Apply 12% headroom for visual breathing room (matches chart overlay)
        effectiveMax = max(effectiveMax, 1)
        
        return VolumeStats(percentileMax: effectiveMax, absoluteMax: absoluteMax, mean: mean)
    }
    
    // MARK: - Volume Moving Average Computation
    
    private func computeVolumeMA(period: Int) -> [(Date, Double)] {
        guard period > 1, dataPoints.count >= period else { return [] }
        
        var result: [(Date, Double)] = []
        let volumes = dataPoints.map { $0.volume }
        
        // Simple moving average
        var sum: Double = volumes[0..<period].reduce(0, +)
        result.append((dataPoints[period - 1].date, sum / Double(period)))
        
        for i in period..<volumes.count {
            sum += volumes[i]
            sum -= volumes[i - period]
            result.append((dataPoints[i].date, sum / Double(period)))
        }
        
        return result
    }

}
