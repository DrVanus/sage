// ATROscillatorView.swift
// Average True Range oscillator chart pane for display below main price chart

import Foundation
import SwiftUI
import Charts

/// A dedicated ATR oscillator pane for the CryptoSage AI chart
/// ATR measures volatility - higher values indicate more volatile price action
struct ATROscillatorView: View {
    let dataPoints: [ChartDataPoint]
    let xDomain: ClosedRange<Date>
    let atrPeriod: Int
    @Binding var showCrosshair: Bool
    @Binding var crosshairDataPoint: ChartDataPoint?
    // Normalized x position (0-1) from main chart for pixel-perfect crosshair alignment
    @Binding var crosshairXFraction: CGFloat
    let height: CGFloat
    var isCompact: Bool = false
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
    private let atrLineColor = Color.yellow
    private let atrFillColor = Color.yellow.opacity(0.15)
    
    // Computed ATR data using close approximation (since we don't have OHLC)
    // True ATR needs High/Low data, but we approximate using close-to-close range
    private var atrData: [(date: Date, atr: Double)] {
        let sourcePoints = visibleDataPoints
        guard sourcePoints.count > atrPeriod else { return [] }
        
        // Calculate True Range approximation using close prices
        // TR ≈ |close[i] - close[i-1]|
        var trSeries: [Double] = []
        for i in 1..<sourcePoints.count {
            let tr = abs(sourcePoints[i].close - sourcePoints[i-1].close)
            trSeries.append(tr)
        }
        
        guard trSeries.count >= atrPeriod else { return [] }
        
        // Calculate ATR as smoothed average of TR (Wilder smoothing)
        var result: [(Date, Double)] = []
        
        // First ATR is simple average of first N TR values
        let firstATR = trSeries.prefix(atrPeriod).reduce(0, +) / Double(atrPeriod)
        var atr = firstATR
        
        // ATR starts at index atrPeriod (first full calculation)
        result.append((sourcePoints[atrPeriod].date, atr))
        
        // Continue with Wilder smoothing: ATR = (prev ATR * (n-1) + TR) / n
        for i in atrPeriod..<trSeries.count {
            atr = (atr * Double(atrPeriod - 1) + trSeries[i]) / Double(atrPeriod)
            // Map back to sourcePoints index (trSeries is 1-indexed relative to sourcePoints)
            let dataIndex = i + 1
            if dataIndex < sourcePoints.count {
                result.append((sourcePoints[dataIndex].date, atr))
            }
        }
        
        // EDGE FILL: Extend the first value to xDomain start to eliminate left-side gap
        if let first = result.first, first.0 > xDomain.lowerBound {
            result.insert((xDomain.lowerBound, first.1), at: 0)
        }
        
        return result
    }
    
    // Y-axis range for ATR (auto-scale based on data)
    private var yDomain: ClosedRange<Double> {
        guard !atrData.isEmpty else { return 0...1 }
        let allValues = atrData.map { $0.atr }
        guard let minVal = allValues.min(), let maxVal = allValues.max() else { return 0...1 }
        let range = maxVal - minVal
        let padding = range * 0.15
        // ATR is always positive, start from 0
        return 0...(maxVal + padding)
    }
    
    // Find ATR value for a given date
    private func atrValue(for date: Date) -> Double? {
        guard !atrData.isEmpty else { return nil }
        
        var closest: (Date, Double)? = nil
        var minDiff = Double.infinity
        
        for point in atrData {
            let diff = abs(point.0.timeIntervalSince(date))
            if diff < minDiff {
                minDiff = diff
                closest = point
            }
        }
        
        return closest?.1
    }

    var body: some View {
        Chart {
            // ATR area fill
            ForEach(atrData, id: \.date) { point in
                AreaMark(
                    x: .value("Time", point.date),
                    yStart: .value("Zero", 0),
                    yEnd: .value("ATR", point.atr)
                )
                .foregroundStyle(atrFillColor)
            }
            
            // ATR line
            ForEach(atrData, id: \.date) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("ATR", point.atr),
                    series: .value("Series", "ATR")
                )
                .foregroundStyle(atrLineColor)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.monotone)
            }
            
            // CROSSHAIR: Use native Chart marks for guaranteed alignment
            if showCrosshair, let cp = crosshairDataPoint {
                // Vertical crosshair line
                RuleMark(x: .value("Time", cp.date))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [4, 3]))
                
                // Crosshair dot on ATR line
                if let atr = atrValue(for: cp.date) {
                    PointMark(x: .value("Time", cp.date), y: .value("ATR", atr))
                        .symbolSize(40)
                        .foregroundStyle(atrLineColor)
                }
            }
        }
        .chartXScale(domain: xDomain)
        .chartXScale(range: .plotDimension(padding: 24))
        .chartYScale(domain: yDomain)
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
        // Y-axis with dynamic values for ATR oscillator
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
        // Gesture handler and crosshair overlay for ATR chart
        .chartOverlay { proxy in
            // NOTE: Crosshair line and dot are now rendered inside Chart using RuleMark/PointMark
            GeometryReader { geo in
                // FIX: proxy.plotFrame is Optional<Anchor<CGRect>> — unwrap safely
                if let plotAnchor = proxy.plotFrame {
                    let plotFrame = geo[plotAnchor]
                    let origin = plotFrame.origin

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
        }
        // Y-axis labels are now rendered natively by Swift Charts (see .chartYAxis above)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topLeading) {
            // ATR label badge with current value
            if !showCrosshair {
                HStack(spacing: isCompact ? 3 : 5) {
                    Circle()
                        .fill(atrLineColor)
                        .frame(width: isCompact ? 5 : 7, height: isCompact ? 5 : 7)
                    Text("ATR \(atrPeriod)")
                        .font(.system(size: isCompact ? 9 : 11, weight: .bold))
                        .foregroundStyle(.white)
                    if let lastATR = atrData.last {
                        Text(formatATR(lastATR.atr))
                            .font(.system(size: isCompact ? 9 : 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(atrLineColor)
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
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)
        }
        .transaction { txn in txn.animation = nil }
        .frame(height: height)
        // Force chart redraw when geometry changes (e.g., after rotation)
        .id("ATR-\(Int(plotWidth))-\(Int(height))")
    }
    
    // Format ATR value for display (price-like formatting)
    private func formatATR(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.0f", value)
        } else if value >= 1 {
            return String(format: "%.2f", value)
        } else if value >= 0.01 {
            return String(format: "%.4f", value)
        } else {
            return String(format: "%.6f", value)
        }
    }
}
