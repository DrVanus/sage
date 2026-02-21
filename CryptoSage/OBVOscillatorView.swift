// OBVOscillatorView.swift
// On Balance Volume oscillator chart pane for display below main price chart

import Foundation
import SwiftUI
import Charts

/// A dedicated OBV oscillator pane for the CryptoSage AI chart
struct OBVOscillatorView: View {
    let dataPoints: [ChartDataPoint]
    let xDomain: ClosedRange<Date>
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
    private let obvLineColor = Color.cyan
    private let zeroLineColor = Color.white.opacity(0.3)
    private let positiveColor = DS.Colors.bid.opacity(0.3)
    private let negativeColor = DS.Colors.ask.opacity(0.3)
    
    // Computed OBV data
    private var obvData: [(date: Date, obv: Double)] {
        let sourcePoints = visibleDataPoints
        guard sourcePoints.count >= 2 else { return [] }
        
        var result: [(Date, Double)] = []
        var obvValue: Double = 0
        
        // First point starts at 0
        result.append((sourcePoints[0].date, 0))
        
        for i in 1..<sourcePoints.count {
            if sourcePoints[i].close > sourcePoints[i-1].close {
                obvValue += sourcePoints[i].volume
            } else if sourcePoints[i].close < sourcePoints[i-1].close {
                obvValue -= sourcePoints[i].volume
            }
            // If close == prevClose, OBV stays the same
            result.append((sourcePoints[i].date, obvValue))
        }
        
        return result
    }
    
    // Y-axis range for OBV (auto-scale based on data)
    private var yDomain: ClosedRange<Double> {
        guard !obvData.isEmpty else { return -1...1 }
        let allValues = obvData.map { $0.obv }
        guard let minVal = allValues.min(), let maxVal = allValues.max() else { return -1...1 }
        let range = maxVal - minVal
        let padding = range * 0.1
        // Ensure zero is included in the range
        let actualMin = min(0, minVal - padding)
        let actualMax = max(0, maxVal + padding)
        return actualMin...actualMax
    }
    
    // MARK: - Find OBV Value for Crosshair (nearest-neighbor lookup)
    
    private func obvValue(for date: Date) -> Double? {
        guard !obvData.isEmpty else { return nil }
        
        var closest: (date: Date, obv: Double)? = nil
        var minDiff = Double.infinity
        
        for point in obvData {
            let diff = abs(point.date.timeIntervalSince(date))
            if diff < minDiff {
                minDiff = diff
                closest = point
            }
        }
        
        return closest?.obv
    }

    var body: some View {
        Chart {
            // Zero line
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(zeroLineColor)
                .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
            
            // OBV area fill (positive/negative)
            ForEach(obvData, id: \.date) { point in
                AreaMark(
                    x: .value("Time", point.date),
                    yStart: .value("Zero", 0),
                    yEnd: .value("OBV", point.obv)
                )
                .foregroundStyle(point.obv >= 0 ? positiveColor : negativeColor)
            }
            
            // OBV line
            ForEach(obvData, id: \.date) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("OBV", point.obv),
                    series: .value("Series", "OBV")
                )
                .foregroundStyle(obvLineColor)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.monotone)
            }
            
            // CROSSHAIR: Use native Chart marks for guaranteed alignment
            if showCrosshair, let cp = crosshairDataPoint {
                // Vertical crosshair line
                RuleMark(x: .value("Time", cp.date))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [4, 3]))
                
                // Crosshair dot on OBV line
                if let obv = obvValue(for: cp.date) {
                    PointMark(x: .value("Time", cp.date), y: .value("OBV", obv))
                        .symbolSize(40)
                        .foregroundStyle(obvLineColor)
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
        // Y-axis with dynamic values for OBV oscillator
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
        // Gesture handler and crosshair overlay for OBV chart
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
        .overlay(alignment: .topLeading) {
            // OBV label badge with current value - hide when crosshair is active
            if !showCrosshair {
                HStack(spacing: isCompact ? 3 : 5) {
                    Circle()
                        .fill(obvLineColor)
                        .frame(width: isCompact ? 5 : 7, height: isCompact ? 5 : 7)
                    Text("OBV")
                        .font(.system(size: isCompact ? 9 : 11, weight: .bold))
                        .foregroundStyle(.white)
                    if let lastOBV = obvData.last {
                        Text(formatOBV(lastOBV.obv))
                            .font(.system(size: isCompact ? 9 : 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(lastOBV.obv >= 0 ? DS.Colors.bid : DS.Colors.ask)
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
        .id("OBV-\(Int(plotWidth))-\(Int(height))")
    }
    
    // Format OBV value for display
    private func formatOBV(_ value: Double) -> String {
        let absValue = abs(value)
        if absValue >= 1_000_000_000 {
            return String(format: "%.1fB", value / 1_000_000_000)
        } else if absValue >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        } else if absValue >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        } else {
            return String(format: "%.0f", value)
        }
    }
}
