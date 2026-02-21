import Foundation
import SwiftUI
import Charts

/// A dedicated MACD oscillator pane for the CryptoSage AI chart
struct MACDOscillatorView: View {
    let dataPoints: [ChartDataPoint]
    let xDomain: ClosedRange<Date>
    let fastPeriod: Int
    let slowPeriod: Int
    let signalPeriod: Int
    @Binding var showCrosshair: Bool
    @Binding var crosshairDataPoint: ChartDataPoint?
    // Normalized x position (0-1) from main chart for pixel-perfect crosshair alignment
    @Binding var crosshairXFraction: CGFloat
    let height: CGFloat  // Dynamic height for MACD pane
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
    
    // Colors - using design system colors for consistency
    private let macdLineColor = DS.Colors.macdLine
    private let signalLineColor = DS.Colors.macdSignal
    private let histogramUpColor = DS.Colors.bid.opacity(0.7)
    private let histogramDownColor = DS.Colors.ask.opacity(0.7)
    private let zeroLineColor = Color.white.opacity(0.3)
    
    // Computed MACD data
    private var macdData: [(date: Date, macd: Double, signal: Double, histogram: Double)] {
        let sourcePoints = visibleDataPoints
        let closes = sourcePoints.map { $0.close }
        guard let series = TechnicalsEngine.macdSeries(closes, fast: fastPeriod, slow: slowPeriod, signal: signalPeriod) else {
            return []
        }
        
        // Guard against array shape mismatches to prevent out-of-bounds on timeframe transitions.
        let usableCount = min(sourcePoints.count, series.macdLine.count, series.signalLine.count, series.histogram.count)
        guard usableCount > 0 else { return [] }
        
        // Align with visible domain points
        var result: [(Date, Double, Double, Double)] = []
        result.reserveCapacity(usableCount)
        for i in 0..<usableCount {
            result.append((sourcePoints[i].date, series.macdLine[i], series.signalLine[i], series.histogram[i]))
        }
        return result
    }
    
    // Y-axis range for MACD (auto-scale based on data)
    private var yDomain: ClosedRange<Double> {
        guard !macdData.isEmpty else { return -1...1 }
        let allValues = macdData.flatMap { [$0.macd, $0.signal, $0.histogram] }
        guard let minVal = allValues.min(), let maxVal = allValues.max() else { return -1...1 }
        let padding = (maxVal - minVal) * 0.1
        return (minVal - padding)...(maxVal + padding)
    }
    
    // MARK: - Find MACD Value for Crosshair (nearest-neighbor lookup)
    
    private func macdValue(for date: Date) -> (macd: Double, signal: Double, histogram: Double)? {
        guard !macdData.isEmpty else { return nil }
        
        var closest: (date: Date, macd: Double, signal: Double, histogram: Double)? = nil
        var minDiff = Double.infinity
        
        for point in macdData {
            let diff = abs(point.date.timeIntervalSince(date))
            if diff < minDiff {
                minDiff = diff
                closest = point
            }
        }
        
        guard let c = closest else { return nil }
        return (c.macd, c.signal, c.histogram)
    }

    var body: some View {
        Chart {
            // Zero line
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(zeroLineColor)
                .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
            
            // Histogram bars
            ForEach(macdData, id: \.date) { point in
                RectangleMark(
                    x: .value("Time", point.date),
                    yStart: .value("Zero", 0),
                    yEnd: .value("Histogram", point.histogram),
                    width: 3
                )
                .foregroundStyle(point.histogram >= 0 ? histogramUpColor : histogramDownColor)
            }
            
            // MACD line
            ForEach(macdData, id: \.date) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("MACD", point.macd),
                    series: .value("Series", "MACD")
                )
                .foregroundStyle(macdLineColor)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            
            // Signal line
            ForEach(macdData, id: \.date) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Signal", point.signal),
                    series: .value("Series", "Signal")
                )
                .foregroundStyle(signalLineColor)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            
            // CROSSHAIR: Use native Chart marks for guaranteed alignment
            if showCrosshair, let cp = crosshairDataPoint {
                // Vertical crosshair line
                RuleMark(x: .value("Time", cp.date))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [4, 3]))
                
                // Crosshair dots on MACD and Signal lines
                if let macdValues = macdValue(for: cp.date) {
                    // MACD dot
                    PointMark(x: .value("Time", cp.date), y: .value("MACD", macdValues.macd))
                        .symbolSize(40)
                        .foregroundStyle(macdLineColor)
                    
                    // Signal dot
                    PointMark(x: .value("Time", cp.date), y: .value("Signal", macdValues.signal))
                        .symbolSize(40)
                        .foregroundStyle(signalLineColor)
                }
            }
        }
        .chartXScale(domain: xDomain)
        .chartXScale(range: .plotDimension(padding: 24))
        .chartYScale(domain: yDomain)
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
        // Y-axis with dynamic values for MACD
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                    .foregroundStyle(.clear)
                AxisTick(stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(DS.Colors.tick.opacity(0.5))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(v.formatted(.number.precision(.fractionLength(0...1))))
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
        // Gesture handler for MACD chart
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
            // MACD label badge with current values - hide when crosshair is active
            // Uses smaller font/padding in compact mode
            if !showCrosshair {
                HStack(spacing: isCompact ? 3 : 5) {
                    Circle()
                        .fill(macdLineColor)
                        .frame(width: isCompact ? 5 : 7, height: isCompact ? 5 : 7)
                    Text("MACD")
                        .font(.system(size: isCompact ? 9 : 11, weight: .bold))
                        .foregroundStyle(.white)
                    if let lastMACD = macdData.last {
                        Text(formatMACD(lastMACD.histogram))
                            .font(.system(size: isCompact ? 9 : 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(lastMACD.histogram >= 0 ? DS.Colors.bid : DS.Colors.ask)
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
        .id("MACD-\(Int(plotWidth))-\(Int(height))")
    }
    
    // Format MACD value for display
    private func formatMACD(_ value: Double) -> String {
        if abs(value) >= 1000 {
            return String(format: "%.0f", value)
        } else if abs(value) >= 100 {
            return String(format: "%.1f", value)
        } else if abs(value) >= 1 {
            return String(format: "%.2f", value)
        } else {
            return String(format: "%.4f", value)
        }
    }
}
