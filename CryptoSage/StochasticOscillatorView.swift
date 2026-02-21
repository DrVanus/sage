import Foundation
import SwiftUI
import Charts

/// A dedicated Stochastic oscillator pane for the CryptoSage AI chart
struct StochasticOscillatorView: View {
    let dataPoints: [ChartDataPoint]
    let xDomain: ClosedRange<Date>
    let kPeriod: Int
    let dPeriod: Int
    @Binding var showCrosshair: Bool
    @Binding var crosshairDataPoint: ChartDataPoint?
    // Normalized x position (0-1) from main chart for pixel-perfect crosshair alignment
    @Binding var crosshairXFraction: CGFloat
    let height: CGFloat  // Dynamic height for Stochastic pane
    var isCompact: Bool = false  // Compact mode for stacked oscillators
    var trailingInset: CGFloat = 40  // Trailing inset to match main chart's Y-axis width
    var leadingInset: CGFloat = 4  // Leading inset to match main chart's plot area origin
    var showXAxis: Bool = false  // Whether to show x-axis labels (true when bottom-most chart)
    var interval: ChartInterval = .oneDay  // Chart interval for x-axis label formatting
    var plotWidth: CGFloat = 300  // Actual plot width from main chart for consistent x-axis

    // MARK: - Find Closest Data Point for Crosshair
    private var visibleDataPoints: [ChartDataPoint] {
        dataPoints.filter { $0.date >= xDomain.lowerBound && $0.date <= xDomain.upperBound }
    }
    
    private func findClosestDataPoint(to date: Date) -> ChartDataPoint? {
        let visiblePoints = visibleDataPoints
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
    
    // Colors
    private let kLineColor = Color.teal
    private let dLineColor = Color.orange
    private let overboughtColor = Color.red.opacity(0.12)
    private let oversoldColor = Color.green.opacity(0.12)
    private let referenceLineColor = Color.white.opacity(0.3)
    
    // Levels
    private let overboughtLevel: Double = 80
    private let oversoldLevel: Double = 20
    
    // Computed Stochastic data
    private var stochData: [(date: Date, k: Double, d: Double)] {
        let sourcePoints = visibleDataPoints
        let closes = sourcePoints.map { $0.close }
        guard let series = TechnicalsEngine.stochSeries(closes, kPeriod: kPeriod, dPeriod: dPeriod) else {
            return []
        }
        
        // Align with dataPoints - stoch series starts later
        let offset = sourcePoints.count - series.k.count
        guard offset >= 0 else { return [] }
        let usableCount = min(series.k.count, series.d.count)
        guard usableCount > 0 else { return [] }
        var result: [(Date, Double, Double)] = []
        for i in 0..<usableCount {
            let dataIndex = offset + i
            if dataIndex < sourcePoints.count {
                result.append((sourcePoints[dataIndex].date, series.k[i], series.d[i]))
            }
        }
        
        // EDGE FILL: Extend the first value to xDomain start to eliminate left-side gap
        if let first = result.first, first.0 > xDomain.lowerBound {
            result.insert((xDomain.lowerBound, first.1, first.2), at: 0)
        }
        
        return result
    }
    
    // MARK: - Find Stochastic Value for Crosshair (nearest-neighbor lookup)
    
    private func stochValue(for date: Date) -> (k: Double, d: Double)? {
        guard !stochData.isEmpty else { return nil }
        
        var closest: (date: Date, k: Double, d: Double)? = nil
        var minDiff = Double.infinity
        
        for point in stochData {
            let diff = abs(point.date.timeIntervalSince(date))
            if diff < minDiff {
                minDiff = diff
                closest = point
            }
        }
        
        guard let c = closest else { return nil }
        return (c.k, c.d)
    }

    var body: some View {
        Chart {
            // Overbought zone (80-100)
            RectangleMark(
                xStart: .value("Start", xDomain.lowerBound),
                xEnd: .value("End", xDomain.upperBound),
                yStart: .value("Upper", overboughtLevel),
                yEnd: .value("Top", 100)
            )
            .foregroundStyle(overboughtColor)
            
            // Oversold zone (0-20)
            RectangleMark(
                xStart: .value("Start", xDomain.lowerBound),
                xEnd: .value("End", xDomain.upperBound),
                yStart: .value("Bottom", 0),
                yEnd: .value("Lower", oversoldLevel)
            )
            .foregroundStyle(oversoldColor)
            
            // Reference lines
            RuleMark(y: .value("Overbought", overboughtLevel))
                .foregroundStyle(referenceLineColor)
                .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
            
            RuleMark(y: .value("Oversold", oversoldLevel))
                .foregroundStyle(referenceLineColor)
                .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
            
            // %K line
            ForEach(stochData, id: \.date) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("K", point.k),
                    series: .value("Series", "K")
                )
                .foregroundStyle(kLineColor)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            
            // %D line
            ForEach(stochData, id: \.date) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("D", point.d),
                    series: .value("Series", "D")
                )
                .foregroundStyle(dLineColor)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            
            // CROSSHAIR: Use native Chart marks for guaranteed alignment
            if showCrosshair, let cp = crosshairDataPoint {
                // Vertical crosshair line
                RuleMark(x: .value("Time", cp.date))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [4, 3]))
                
                // Crosshair dots on K and D lines
                if let stochValues = stochValue(for: cp.date) {
                    // K line dot
                    PointMark(x: .value("Time", cp.date), y: .value("K", stochValues.k))
                        .symbolSize(40)
                        .foregroundStyle(kLineColor)
                    
                    // D line dot
                    PointMark(x: .value("Time", cp.date), y: .value("D", stochValues.d))
                        .symbolSize(40)
                        .foregroundStyle(dLineColor)
                }
            }
        }
        .chartXScale(domain: xDomain)
        .chartXScale(range: .plotDimension(padding: 24))
        .chartYScale(domain: 0...100)
        .chartXAxis {
            let xAxis = ChartXAxisProvider(interval: interval, domain: xDomain, plotWidth: plotWidth, uses24hClock: ChartDateFormatters.uses24hClock)
            AxisMarks(values: xAxis.ticks()) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                    .foregroundStyle(DS.Colors.grid.opacity(0.20))
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
        // Y-axis with marks at key Stochastic levels
        .chartYAxis {
            AxisMarks(position: .trailing, values: [20.0, 50.0, 80.0]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                    .foregroundStyle(.clear)
                AxisTick(stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(DS.Colors.tick.opacity(0.5))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.55))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .chartPlotStyle { plot in
            plot
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
        // Gesture handler for Stochastic chart
        // NOTE: Crosshair line and dots are now rendered inside Chart using RuleMark/PointMark
        .chartOverlay { proxy in
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
        .overlay(alignment: .topLeading) {
            // Stochastic label badge with current values - hide when crosshair is active
            // Uses smaller font/padding in compact mode
            if !showCrosshair {
                HStack(spacing: isCompact ? 3 : 5) {
                    Circle()
                        .fill(kLineColor)
                        .frame(width: isCompact ? 5 : 7, height: isCompact ? 5 : 7)
                    Text("Stoch")
                        .font(.system(size: isCompact ? 9 : 11, weight: .bold))
                        .foregroundStyle(.white)
                    if let lastPoint = stochData.last {
                        Text(String(format: "%.1f", lastPoint.k))
                            .font(.system(size: isCompact ? 9 : 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(
                                lastPoint.k >= overboughtLevel ? Color.red :
                                lastPoint.k <= oversoldLevel ? Color.green :
                                Color.white
                            )
                    }
                }
                .padding(.horizontal, isCompact ? 6 : 9)
                .padding(.vertical, isCompact ? 3 : 5)
                .background(
                    Capsule()
                        .fill(Color(red: 0.08, green: 0.08, blue: 0.10))
                )
                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                .padding(.leading, isCompact ? 4 : 8)
                .padding(.top, isCompact ? 3 : 5)
            }
        }
        .overlay(alignment: .top) {
            // Subtle divider line at top
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)
        }
        .transaction { txn in txn.animation = nil }
        .frame(height: height)
        // Force chart redraw when geometry changes (e.g., after rotation)
        .id("Stoch-\(Int(plotWidth))-\(Int(height))")
    }
}
