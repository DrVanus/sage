// RSIOscillatorView.swift
// RSI oscillator chart pane for display below main price chart

import Foundation
import SwiftUI
import Charts

struct RSIOscillatorView: View {
    // Input data and configuration
    let dataPoints: [ChartDataPoint]
    let xDomain: ClosedRange<Date>
    let rsiPeriod: Int
    
    // Crosshair bindings (child updates parent)
    @Binding var showCrosshair: Bool
    @Binding var crosshairDataPoint: ChartDataPoint?
    // Normalized x position (0-1) from main chart for pixel-perfect crosshair alignment
    @Binding var crosshairXFraction: CGFloat
    
    // Desired height for the RSI view (defaults typically ~60)
    let height: CGFloat
    
    // Compact mode - show fewer Y-axis labels when space is tight
    var isCompact: Bool = false
    
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
    
    // MARK: - RSI Color Configuration (adaptive for light/dark)
    private let rsiLineColor = DS.Colors.rsiLine
    private var overboughtColor: Color { isDark ? Color.red.opacity(0.18) : Color.red.opacity(0.10) }
    private var oversoldColor: Color { isDark ? Color.green.opacity(0.18) : Color.green.opacity(0.10) }
    private var referenceLineColor: Color { isDark ? Color.white.opacity(0.40) : Color.black.opacity(0.22) }
    private var middleLineColor: Color { isDark ? Color.white.opacity(0.20) : Color.black.opacity(0.10) }
    
    // RSI thresholds
    private let overboughtLevel: Double = 70
    private let oversoldLevel: Double = 30
    private let middleLevel: Double = 50
    
    var body: some View {
        rsiChartContent
    }
    
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
    
    // MARK: - RSI Calculation
    
    private var rsiDataPoints: [(date: Date, rsi: Double)] {
        let sourcePoints = visibleDataPoints
        let closes = sourcePoints.map { $0.close }
        guard let rsiValues = TechnicalsEngine.rsiSeries(closes, period: rsiPeriod) else {
            return []
        }
        
        // RSI series starts at index = period, so align with data points
        var result: [(Date, Double)] = []
        let startIndex = rsiPeriod
        for (i, rsi) in rsiValues.enumerated() {
            let dataIndex = startIndex + i
            if dataIndex < sourcePoints.count {
                result.append((sourcePoints[dataIndex].date, rsi))
            }
        }
        
        // EDGE FILL: When the data source doesn't include enough warm-up candles
        // before the visible window, the RSI line starts partway through the chart,
        // leaving an ugly gap on the left. Extend the first RSI value back to the
        // xDomain start so the line reaches the left edge (standard on pro platforms).
        if let first = result.first, first.0 > xDomain.lowerBound {
            result.insert((xDomain.lowerBound, first.1), at: 0)
        }
        
        return result
    }
    
    // Find RSI value for a given date
    private func rsiValue(for date: Date) -> Double? {
        let points = rsiDataPoints
        guard !points.isEmpty else { return nil }
        
        // Find closest RSI point
        var closest: (Date, Double)? = nil
        var minDiff = Double.infinity
        
        for point in points {
            let diff = abs(point.0.timeIntervalSince(date))
            if diff < minDiff {
                minDiff = diff
                closest = point
            }
        }
        
        return closest?.1
    }
    
    @ViewBuilder
    private var rsiChartContent: some View {
        // Use passed xDomain directly to ensure perfect alignment with main price chart
        let domain = xDomain
        let rsiPoints = rsiDataPoints
        
        Chart {
            // Overbought zone (above 70)
            RectangleMark(
                xStart: .value("Start", domain.lowerBound),
                xEnd: .value("End", domain.upperBound),
                yStart: .value("OB Start", overboughtLevel),
                yEnd: .value("OB End", 100)
            )
            .foregroundStyle(overboughtColor)
            
            // Oversold zone (below 30)
            RectangleMark(
                xStart: .value("Start", domain.lowerBound),
                xEnd: .value("End", domain.upperBound),
                yStart: .value("OS Start", 0),
                yEnd: .value("OS End", oversoldLevel)
            )
            .foregroundStyle(oversoldColor)
            
            // Reference line at 70 (overbought)
            RuleMark(y: .value("Overbought", overboughtLevel))
                .foregroundStyle(referenceLineColor)
                .lineStyle(StrokeStyle(lineWidth: 1.0, dash: [4, 3]))
            
            // Reference line at 50 (middle)
            RuleMark(y: .value("Middle", middleLevel))
                .foregroundStyle(middleLineColor)
                .lineStyle(StrokeStyle(lineWidth: 0.7, dash: [3, 4]))
            
            // Reference line at 30 (oversold)
            RuleMark(y: .value("Oversold", oversoldLevel))
                .foregroundStyle(referenceLineColor)
                .lineStyle(StrokeStyle(lineWidth: 1.0, dash: [4, 3]))
            
            // RSI Line
            ForEach(Array(rsiPoints.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("Time", point.0),
                    y: .value("RSI", point.1)
                )
                .foregroundStyle(rsiLineColor)
                .lineStyle(StrokeStyle(lineWidth: 2.0))
                .interpolationMethod(.monotone)
            }
            
            // CROSSHAIR: Use native Chart marks for guaranteed alignment
            // RuleMark and PointMark use Swift Charts' coordinate system directly
            if showCrosshair, let cp = crosshairDataPoint {
                // Vertical crosshair line
                RuleMark(x: .value("Time", cp.date))
                    .foregroundStyle(isDark ? Color.white.opacity(0.6) : Color.black.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [4, 3]))
                
                // Crosshair dot on RSI line
                if let rsi = rsiValue(for: cp.date) {
                    // Outer glow
                    PointMark(x: .value("Time", cp.date), y: .value("RSI", rsi))
                        .symbolSize(50)
                        .foregroundStyle(rsiLineColor.opacity(0.35))
                    
                    // Inner dot
                    PointMark(x: .value("Time", cp.date), y: .value("RSI", rsi))
                        .symbolSize(25)
                        .foregroundStyle(rsiLineColor)
                }
            }
        }
        .chartXScale(domain: domain)
        .chartXScale(range: .plotDimension(padding: 24))
        .chartYScale(domain: 0...100)
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
        // ALIGNMENT: Use a real Y-axis with visible labels instead of hidden + padding.
        // Padding inside chartPlotStyle doesn't reliably resize the plot area to match
        // the price chart, causing x-axis grid lines to misalign. A real Y-axis lets
        // Swift Charts handle the layout natively - each chart renders its own axis correctly.
        .chartYAxis {
            // ALIGNMENT: Identical AxisMarks structure as price chart (AxisGridLine + AxisTick + AxisValueLabel)
            // with the SAME fixed label width (40). This makes Swift Charts allocate the exact same
            // Y-axis area width → identical plot area → pixel-perfect x-axis alignment.
            AxisMarks(position: .trailing, values: [30.0, 50.0, 70.0]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                    .foregroundStyle(.clear)
                AxisTick(stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(DS.Colors.tick.opacity(0.5))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))")
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
        .chartLegend(.hidden)
        // Gesture handler for crosshair interaction on RSI chart
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                // Begin haptic session when drag starts
                                #if os(iOS)
                                if !showCrosshair {
                                    ChartHaptics.shared.begin()
                                }
                                #endif
                                
                                guard let plotAnchor = proxy.plotFrame else { return }
                                let plotFrame = geo[plotAnchor]
                                let origin = plotFrame.origin
                                let rawX = value.location.x - origin.x
                                // Clamp x to plot bounds so edge touches select first/last data points
                                let x = min(max(rawX, 0), plotFrame.width)
                                if let date: Date = proxy.value(atX: x) {
                                    // Find nearest data point and update crosshair
                                    if let nearest = findClosestDataPoint(to: date) {
                                        // Tick haptic when data point changes
                                        #if os(iOS)
                                        if crosshairDataPoint?.id != nearest.id {
                                            ChartHaptics.shared.tickIfNeeded()
                                        }
                                        #endif
                                        crosshairDataPoint = nearest
                                        // Update x fraction for cross-chart alignment
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
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let plotAnchor = proxy.plotFrame {
                    let plotFrame = geo[plotAnchor]
                    let origin = plotFrame.origin
                    let localPlotWidth = plotFrame.size.width
                    let plotHeight = plotFrame.size.height
                    
                    // NOTE: Crosshair line and dot are now rendered inside Chart using RuleMark/PointMark
                    // This guarantees perfect alignment as Swift Charts handles coordinate mapping
                    
                    // Floating RSI value annotation with edge clamping
                    if showCrosshair, let cp = crosshairDataPoint,
                       let rsi = rsiValue(for: cp.date) {
                    
                    let badgeWidth: CGFloat = 40
                    let badgeHeight: CGFloat = 20
                    let padding: CGFloat = 8
                    
                    // Use proxy.position to get X position from crosshair data point
                    let xPos = proxy.position(forX: cp.date) ?? 0
                    let baseX = origin.x + xPos
                    
                    // For Y, try proxy.position with fallback based on RSI value (0-100 scale)
                    let yPos = proxy.position(forY: rsi) ?? (plotHeight * (1.0 - rsi / 100.0))
                    let baseY = origin.y + yPos - badgeHeight / 2 - 8 // Above the point
                    
                    // Clamp X to stay within plot bounds
                    let minX = origin.x + badgeWidth / 2 + padding
                    let maxX = origin.x + localPlotWidth - badgeWidth / 2 - padding
                    let clampedX = min(max(baseX, minX), maxX)
                    
                    // Clamp Y to stay within plot bounds (ensure badge stays inside)
                    let minY = origin.y + badgeHeight / 2 + 4
                    let maxY = origin.y + plotHeight - badgeHeight / 2 - 4
                    let clampedY = min(max(baseY, minY), maxY)
                    
                    Text(String(format: "%.1f", rsi))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(rsi >= overboughtLevel ? Color.red.opacity(0.8) :
                                      rsi <= oversoldLevel ? Color.green.opacity(0.8) :
                                      Color.black.opacity(0.7))
                        )
                        .position(x: clampedX, y: clampedY)
                        .allowsHitTesting(false)
                    }
                }
            }
        }
        // Y-axis labels are now rendered natively by Swift Charts (see .chartYAxis above)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topLeading) {
            // RSI label badge with current value - hide when crosshair is active
            // Uses a solid dark background for clear readability against the chart
            if !showCrosshair {
                HStack(spacing: isCompact ? 3 : 5) {
                    Circle()
                        .fill(rsiLineColor)
                        .frame(width: isCompact ? 6 : 8, height: isCompact ? 6 : 8)
                    Text("RSI \(rsiPeriod)")
                        .font(.system(size: isCompact ? 10 : 12, weight: .bold))
                        .foregroundStyle(isDark ? .white : Color(white: 0.15))
                    if let currentRSI = rsiDataPoints.last?.rsi {
                        Text(String(format: "%.1f", currentRSI))
                            .font(.system(size: isCompact ? 10 : 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(
                                currentRSI >= overboughtLevel ? Color.red :
                                currentRSI <= oversoldLevel ? Color.green :
                                (isDark ? Color.white : Color(white: 0.15))
                            )
                    }
                }
                .padding(.horizontal, isCompact ? 7 : 10)
                .padding(.vertical, isCompact ? 4 : 5)
                .background(
                    Capsule()
                        .fill(isDark
                              ? Color(red: 0.08, green: 0.08, blue: 0.10)      // Dark mode: near-black
                              : Color(red: 0.95, green: 0.95, blue: 0.96))     // Light mode: soft gray matching chart bg
                )
                .overlay(
                    Capsule()
                        .stroke(isDark ? Color.white.opacity(0.15) : Color.black.opacity(0.08), lineWidth: 0.5)
                )
                .padding(.leading, isCompact ? 4 : 8)
                .padding(.top, isCompact ? 3 : 5)
            }
        }
        .overlay(alignment: .top) {
            // Subtle divider line at top (adaptive for light/dark)
            Rectangle()
                .fill(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                .frame(height: 0.5)
        }
        .transaction { txn in txn.animation = nil }
        .frame(height: height)
        // Force chart redraw when geometry changes (e.g., after rotation)
        // Without this, Swift Charts can render incorrectly after orientation changes
        .id("RSI-\(Int(plotWidth))-\(Int(height))")
    }
}
