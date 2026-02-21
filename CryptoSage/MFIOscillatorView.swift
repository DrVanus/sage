// MFIOscillatorView.swift
// Money Flow Index oscillator chart pane for display below main price chart

import Foundation
import SwiftUI
import Charts

/// A dedicated MFI oscillator pane for the CryptoSage AI chart
/// MFI is a volume-weighted RSI that oscillates between 0-100
/// >80 is overbought, <20 is oversold
struct MFIOscillatorView: View {
    let dataPoints: [ChartDataPoint]
    let xDomain: ClosedRange<Date>
    let mfiPeriod: Int
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
    private let mfiLineColor = Color.green
    private let overboughtColor = Color.red.opacity(0.15)
    private let oversoldColor = Color.green.opacity(0.15)
    private let referenceLineColor = Color.white.opacity(0.3)
    private let middleLineColor = Color.white.opacity(0.15)
    
    // MFI thresholds
    private let overboughtLevel: Double = 80
    private let oversoldLevel: Double = 20
    private let middleLevel: Double = 50
    
    // Computed MFI data
    // MFI = 100 - 100/(1 + Money Flow Ratio)
    // Money Flow Ratio = Positive Money Flow / Negative Money Flow
    // Uses close as typical price approximation since we don't have OHLC
    private var mfiData: [(date: Date, mfi: Double)] {
        let sourcePoints = visibleDataPoints
        guard sourcePoints.count > mfiPeriod else { return [] }
        
        // Calculate raw money flow for each period
        // Typical price approximated as close
        // Raw Money Flow = Typical Price × Volume
        var result: [(Date, Double)] = []
        
        for endIdx in mfiPeriod..<sourcePoints.count {
            var positiveFlow: Double = 0
            var negativeFlow: Double = 0
            
            for i in (endIdx - mfiPeriod + 1)...endIdx {
                guard i > 0 else { continue }
                let tp = sourcePoints[i].close  // Using close as typical price
                let prevTp = sourcePoints[i-1].close
                let rawMF = tp * sourcePoints[i].volume
                
                if tp > prevTp {
                    positiveFlow += rawMF
                } else if tp < prevTp {
                    negativeFlow += rawMF
                }
                // If tp == prevTp, money flow doesn't count
            }
            
            let mfi: Double
            if negativeFlow <= 0 {
                mfi = 100  // All positive flow
            } else if positiveFlow <= 0 {
                mfi = 0   // All negative flow
            } else {
                let moneyFlowRatio = positiveFlow / negativeFlow
                mfi = 100 - (100 / (1 + moneyFlowRatio))
            }
            
            result.append((sourcePoints[endIdx].date, mfi.isFinite ? mfi : 50))
        }
        
        // EDGE FILL: Extend the first value to xDomain start to eliminate left-side gap
        if let first = result.first, first.0 > xDomain.lowerBound {
            result.insert((xDomain.lowerBound, first.1), at: 0)
        }
        
        return result
    }
    
    // Find MFI value for a given date
    private func mfiValue(for date: Date) -> Double? {
        guard !mfiData.isEmpty else { return nil }
        
        var closest: (Date, Double)? = nil
        var minDiff = Double.infinity
        
        for point in mfiData {
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
            // Overbought zone (above 80)
            RectangleMark(
                xStart: .value("Start", xDomain.lowerBound),
                xEnd: .value("End", xDomain.upperBound),
                yStart: .value("OB Start", overboughtLevel),
                yEnd: .value("OB End", 100)
            )
            .foregroundStyle(overboughtColor)
            
            // Oversold zone (below 20)
            RectangleMark(
                xStart: .value("Start", xDomain.lowerBound),
                xEnd: .value("End", xDomain.upperBound),
                yStart: .value("OS Start", 0),
                yEnd: .value("OS End", oversoldLevel)
            )
            .foregroundStyle(oversoldColor)
            
            // Reference line at 80 (overbought)
            RuleMark(y: .value("Overbought", overboughtLevel))
                .foregroundStyle(referenceLineColor)
                .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [4, 4]))
            
            // Reference line at 50 (middle)
            RuleMark(y: .value("Middle", middleLevel))
                .foregroundStyle(middleLineColor)
                .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
            
            // Reference line at 20 (oversold)
            RuleMark(y: .value("Oversold", oversoldLevel))
                .foregroundStyle(referenceLineColor)
                .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [4, 4]))
            
            // MFI line
            ForEach(mfiData, id: \.date) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("MFI", point.mfi),
                    series: .value("Series", "MFI")
                )
                .foregroundStyle(mfiLineColor)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.monotone)
            }
            
            // CROSSHAIR: Use native Chart marks for guaranteed alignment
            if showCrosshair, let cp = crosshairDataPoint {
                // Vertical crosshair line
                RuleMark(x: .value("Time", cp.date))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [4, 3]))
                
                // Crosshair dot on MFI line
                if let mfi = mfiValue(for: cp.date) {
                    PointMark(x: .value("Time", cp.date), y: .value("MFI", mfi))
                        .symbolSize(40)
                        .foregroundStyle(mfiLineColor)
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
        // Y-axis with fixed values for MFI oscillator (0-100 range)
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
        // Gesture handler and crosshair overlay for MFI chart
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
            // MFI label badge with current value
            if !showCrosshair {
                HStack(spacing: isCompact ? 3 : 5) {
                    Circle()
                        .fill(mfiLineColor)
                        .frame(width: isCompact ? 5 : 7, height: isCompact ? 5 : 7)
                    Text("MFI \(mfiPeriod)")
                        .font(.system(size: isCompact ? 9 : 11, weight: .bold))
                        .foregroundStyle(.white)
                    if let lastMFI = mfiData.last {
                        Text(String(format: "%.1f", lastMFI.mfi))
                            .font(.system(size: isCompact ? 9 : 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(
                                lastMFI.mfi >= overboughtLevel ? Color.red :
                                lastMFI.mfi <= oversoldLevel ? Color.green :
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
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)
        }
        .transaction { txn in txn.animation = nil }
        .frame(height: height)
        // Force chart redraw when geometry changes (e.g., after rotation)
        .id("MFI-\(Int(plotWidth))-\(Int(height))")
    }
}
