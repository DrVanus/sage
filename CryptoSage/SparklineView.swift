//
//  SparklineView.swift
//  CryptoSage
//
//  Created by DM on 5/25/25.
//
//  STABILITY NOTES:
//  - This view uses orientation-invariant identity hashing to prevent SwiftUI animation glitches
//  - Data is never reversed at render time - orientation is determined upstream by MarketMetricsEngine
//  - The Equatable conformance uses a fast hash comparison for data to avoid O(n) comparisons
//

import SwiftUI

enum SparklineBackgroundStyle: Equatable { case none, glass, tinted, dark }

enum SeriesOrder: Equatable {
    case oldestToNewest
    case newestToOldest
}

/// Shared sparkline style and trend rules used by watchlist/market/prediction surfaces.
enum SparklineConsistency {
    // Provider values should drive trend color so line color matches displayed % metrics.
    static let relativeTrendThreshold: Double = 0.004

    static let listLineWidth: CGFloat = 1.8
    static let listStableLineWidth: CGFloat = 1.4
    static let listFillOpacity: Double = 0.46
    static let listStableFillOpacity: Double = 0.10
    static let listGlowOpacity: Double = 0.28
    static let listGlowLineWidth: CGFloat = 3.4
    static let listSmoothSamplesPerSegment: Int = 6
    static let listMaxPlottedPoints: Int = 140
    static let listVerticalPaddingRatio: CGFloat = 0.10
    static let listHorizontalInset: CGFloat = 8

    // Small-card sparkline profile (leaderboards, bot cards, compact panels).
    static let miniCardLineWidth: CGFloat = 1.8
    static let miniCardFillOpacity: Double = 0.30
    static let miniCardGlowOpacity: Double = 0.24
    static let miniCardGlowLineWidth: CGFloat = 3.2
    static let miniCardSmoothSamplesPerSegment: Int = 5
    static let miniCardMaxPlottedPoints: Int = 140
    static let miniCardHorizontalInset: CGFloat = 8

    static func trendPositive(
        spark: [Double],
        provider7d: Double?,
        provider24h: Double?,
        fallback: Bool
    ) -> Bool {
        // Keep color semantics aligned with metrics shown in rows.
        if let p7 = provider7d, p7.isFinite { return p7 >= 0 }
        if let p24 = provider24h, p24.isFinite { return p24 >= 0 }

        let valid = spark.filter { $0.isFinite && $0 > 0 }
        if valid.count > 10, let first = valid.first, let last = valid.last {
            let relDiff = (last - first) / first
            if abs(relDiff) > relativeTrendThreshold { return relDiff >= 0 }
        }
        return fallback
    }
}

// PERFORMANCE FIX v25: Separate scroll detection for DATA (downsampling/smoothing)
// from GLOW rendering.
//
// GLOW FIX v24 history: This was set to always return false because:
// 1. Sparklines scrolled into view first render DURING scroll with lightweight glow
// 2. After scroll ends, nothing triggers a re-render → stuck with flat look permanently
// The 3-layer blur glow is just 3 Path strokes with .blur(radius: 0) — modern iOS GPUs handle this fine.
//
// PERFORMANCE FIX v25: We now ONLY use this for data reduction (fewer points + skip smoothing),
// NOT for glow quality. The glow path always renders full quality (see sparklineGlowPath below).
// Downsampling from 150→48 points and skipping catmull-rom smoothing during scroll
// saves significant CPU without any visible quality loss since the sparkline is moving anyway.
private func sparklineShouldReduceDataDuringScroll() -> Bool {
    return ScrollStateAtomicStorage.shared.shouldBlock()
}

/// A reusable sparkline chart view for rendering an array of price points.
/// STABILITY: Uses stable identity hashing and disables animations to prevent visual glitches.
struct SparklineView: View, Equatable {
    
    // MARK: - Fast Equatable Implementation
    // Uses hash comparison for data arrays to avoid O(n) element-by-element comparison
    static func == (lhs: SparklineView, rhs: SparklineView) -> Bool {
        // Fast path: compare critical rendering properties first
        guard lhs.isPositive == rhs.isPositive,
              lhs.overrideColor == rhs.overrideColor,
              lhs.height == rhs.height,
              lhs.compact == rhs.compact,
              lhs.backgroundStyle == rhs.backgroundStyle else {
            return false
        }
        
        // Use stable hash for data comparison (orientation-invariant)
        guard lhs.stableDataHash == rhs.stableDataHash else {
            return false
        }
        
        // Compare remaining visual properties
        return lhs.lineWidth == rhs.lineWidth &&
               lhs.fillOpacity == rhs.fillOpacity &&
               lhs.gradientStroke == rhs.gradientStroke &&
               lhs.showEndDot == rhs.showEndDot &&
               lhs.seriesOrder == rhs.seriesOrder
    }
    
    /// SPARKLINE FIX: Stable hash for data comparison - orientation-invariant
    /// Uses aggressive quantization to prevent minor data variations from causing hash changes
    /// This prevents flickering/glitching when data updates slightly between renders
    private var stableDataHash: Int {
        guard !data.isEmpty else { return 0 }
        var hasher = Hasher()
        
        // Quantize count to ranges of 20 (more aggressive than before)
        // This prevents hash changes when count varies by small amounts (e.g., 165 vs 168)
        let quantizedCount = (data.count / 20) * 20
        hasher.combine(quantizedCount)
        
        let validValues = data.filter { $0.isFinite && $0 > 0 }
        if !validValues.isEmpty, let minV = validValues.min(), let maxV = validValues.max() {
            // Quantize min/max to significant figures based on magnitude
            // This prevents hash changes from tiny price fluctuations (e.g., 3000.01 vs 3000.02)
            let range = maxV - minV
            let magnitude = range > 0 ? pow(10, floor(log10(range))) : 1.0
            let quantizationStep = Swift.max(magnitude / 10, 1.0) // At least 1.0 step
            
            let quantizedMin = floor(minV / quantizationStep) * quantizationStep
            let quantizedMax = ceil(maxV / quantizationStep) * quantizationStep
            
            // Use integers of the quantized values for stable hashing
            hasher.combine(Int(quantizedMin))
            hasher.combine(Int(quantizedMax))
            
            // Add first and last values as stability anchors (also quantized)
            // This helps when the shape stays similar but endpoints shift
            if let first = validValues.first, let last = validValues.last {
                hasher.combine(Int(floor(first / quantizationStep)))
                hasher.combine(Int(floor(last / quantizationStep)))
            }
        }
        
        return hasher.finalize()
    }
    
    /// The series of prices to plot
    let data: [Double]
    /// Whether the line should be colored green (positive) or red (negative)
    let isPositive: Bool
    /// Optional explicit color override (e.g., neutral gray for stablecoins)
    var overrideColor: Color? = nil
    
    var height: CGFloat = 30
    var lineWidth: CGFloat = 1.8
    var verticalPaddingRatio: CGFloat = 0.08
    
    /// Dynamic line width based on data density
    /// Slight thinning for very dense data to preserve micro price movements
    /// Less aggressive than before to maintain consistent visual weight
    private var effectiveLineWidth: CGFloat {
        let pointCount = data.count
        if pointCount > 250 { return max(1.4, lineWidth * 0.80) }  // Very dense
        if pointCount > 180 { return max(1.5, lineWidth * 0.88) }  // Dense
        if pointCount > 130 { return max(1.6, lineWidth * 0.92) }  // Moderate
        return lineWidth  // Default
    }
    var fillOpacity: Double = 0.38
    
    var gradientStroke: Bool = true
    var showEndDot: Bool = true
    
    // Visual options
    var leadingFade: CGFloat = 0.12      // 0 -> no fade, 0.0...1.0 fraction of width
    var trailingFade: CGFloat = 0.04     // fraction of width to fade on the trailing edge
    var showTrailHighlight: Bool = true // emphasize the most recent segment (off by default for crisper end)
    var trailLengthRatio: CGFloat = 0.28 // fraction of smoothed points highlighted at the end
    var minWidth: CGFloat = 70           // ensures we get non-zero width in tight layouts
    var endDotPulse: Bool = true        // subtle animated pulse on the last point
    var showMinMaxTicks: Bool = false    // draw tiny ticks at min/max points (changed default to false)

    var preferredWidth: CGFloat? = nil   // if set, forces a fixed width (useful in tight HStacks)
    var showBaseline: Bool = false       // optional dashed baseline through the mean (changed default to false)

    // New background style enum property
    var backgroundStyle: SparklineBackgroundStyle = .glass

    // Advanced styling (restored)
    var cornerRadius: CGFloat = 8
    // These tuning properties apply only to .tinted mode now
    var glowOpacity: Double = SparklineConsistency.listGlowOpacity
    var glowLineWidth: CGFloat = SparklineConsistency.listGlowLineWidth
    // CHART SMOOTHNESS FIX: Increased from 4 to 6 for smoother curves (was causing squiggly appearance)
    var smoothSamplesPerSegment: Int = 6
    // Reduced from 280 to 200 for cleaner chart appearance while still showing price detail
    var maxPlottedPoints: Int = 200
    var rawMode: Bool = false

    // New background styling properties - apply only to .tinted
    var showBackground: Bool = true
    var backgroundOpacity: Double = 0.18
    var glassOverlayOpacity: Double = 0.35
    var borderOpacity: Double = 0.25
    
    // Subtle grid overlay inside the glass card
    var gridEnabled: Bool = true
    // Small extrema dots (min/max) for micro detail
    var showExtremaDots: Bool = true

    // Enhanced neon trail at the end of the line
    var neonTrail: Bool = true

    // Glass sheen animation
    var sheenEnabled: Bool = false
    var sheenPeriod: Double = 3.0

    // Edge treatment
    var crispEnds: Bool = true           // disable edge fade mask when true
    
    /// Trailing inset for chart content to prevent end dot clipping at right edge
    /// Set to ~8pt to ensure the pulsing end dot (10pt + blur) doesn't get clipped
    /// Note: Chart starts from x=0 (left edge) for clean alignment - inset only applies to trailing edge
    var horizontalInset: CGFloat = 0

    // Contrast tweaks
    var redFillBoost: Double = 0.10      // extra opacity for red area on dark bg (boosted for richer fills)

    // Rendering mode optimized for tight list cells
    var compact: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    // Data handling
    var seriesOrder: SeriesOrder = .oldestToNewest

    // 24H Reference level - shows a horizontal line at a specific data point (e.g., 24h ago price)
    var showReferenceLevel: Bool = false
    var referenceLevelIndex: Int? = nil  // Index in data array for reference point (nil = auto-calculate for 24h)
    var referenceLevelOpacity: Double = 0.2

    private var orderedData: [Double] {
        switch seriesOrder {
        case .oldestToNewest:
            return data
        case .newestToOldest:
            return data.reversed()
        }
    }
    
    // MARK: - Stable Color Logic
    // CRITICAL FIX: Removed the series-flipping logic that was causing color oscillation.
    // The sparkline data order should be determined by the data provider (Binance/CoinGecko),
    // not flipped at render time based on an external `isPositive` hint that may conflict
    // with the sparkline's actual trend direction.
    //
    // The color is now determined solely by the `isPositive` parameter passed by the caller,
    // who is responsible for computing and stabilizing this value. This prevents race conditions
    // between the sparkline data trend and the external 7D percent change.
    
    private var effectiveOrderedData: [Double] {
        // Simply return the ordered data without any flipping.
        // The caller (WatchlistSection, CoinRowView) is responsible for:
        // 1. Ensuring data is in the correct order (oldest to newest)
        // 2. Computing and stabilizing the `isPositive` flag
        return orderedData
    }

    // Actual trend derived from the sparkline data (used only for fallback/debugging)
    private var trendIsUp: Bool {
        guard let first = effectiveOrderedData.first, let last = effectiveOrderedData.last else { return isPositive }
        guard first.isFinite, last.isFinite, first > 0, last > 0 else { return isPositive }
        return (last - first) >= 0
    }

    // Professional trading colors - vibrant but refined (matches Robinhood/Coinbase style)
    private static let professionalGreen = Color(red: 0.20, green: 0.82, blue: 0.48)  // Vibrant trading green
    private static let professionalRed = Color(red: 0.95, green: 0.30, blue: 0.35)    // Vibrant trading red
    
    // Choose the stroke/fill color.
    // CRITICAL FIX: Always use the external `isPositive` parameter to determine color.
    // The caller is responsible for computing and stabilizing this value to prevent flicker.
    // This ensures the color matches the displayed 7D percent change, not a potentially
    // conflicting sparkline first-vs-last comparison.
    private var effectiveColor: Color {
        if let override = overrideColor { return override }
        // Always use the caller-provided isPositive - they have stabilized it
        // Use professional trading colors for a polished look
        return isPositive ? Self.professionalGreen : Self.professionalRed
    }
    
    // MARK: - Statistical Helpers
    
    /// Compute a lightweight volatility metric in [0, 1]
    /// Uses an optimized single-pass algorithm for better performance
    @inline(__always)
    private func volatility(of series: [Double]) -> Double {
        let n = series.count
        guard n > 2 else { return 0 }
        
        // Single-pass algorithm for mean and variance (Welford's method)
        var mean: Double = 0
        var m2: Double = 0
        var minVal = Double.infinity
        var maxVal = -Double.infinity
        var count = 0
        
        for value in series where value.isFinite {
            count += 1
            let delta = value - mean
            mean += delta / Double(count)
            let delta2 = value - mean
            m2 += delta * delta2
            
            minVal = min(minVal, value)
            maxVal = max(maxVal, value)
        }
        
        guard count > 1 else { return 0 }
        
        let variance = m2 / Double(count - 1)
        let std = sqrt(max(variance, 0))
        let range = maxVal - minVal
        
        guard range > 0 else { return 0 }
        
        // Normalize by range and clamp to [0, 1]
        return min(1.0, max(0.0, std / range * 2.0))
    }

    @inline(__always)
    private func mean(_ arr: [Double]) -> Double {
        guard !arr.isEmpty else { return 0 }
        var sum: Double = 0
        var count = 0
        for v in arr where v.isFinite {
            sum += v
            count += 1
        }
        return count > 0 ? sum / Double(count) : 0
    }

    // A luminance mask that fades on both edges
    private func edgeFadeMask(leading: CGFloat, trailing: CGFloat) -> some View {
        let l = crispEnds ? 0 : max(0, min(1, leading))
        let r = crispEnds ? 0 : max(0, min(1, trailing))
        return LinearGradient(stops: [
            .init(color: .white.opacity(0), location: 0),
            .init(color: .white, location: l),
            .init(color: .white, location: max(l, 1 - r)),
            .init(color: .white.opacity(0), location: 1)
        ], startPoint: .leading, endPoint: .trailing)
    }

    // MARK: - Data Preparation
    
    /// Prepares sparkline data for rendering: filters invalid values, pads short series,
    /// and handles flat data. Uses lazy evaluation where possible.
    private var preparedData: [Double] {
        let ordered = effectiveOrderedData
        
        // Fast path for raw mode
        if rawMode {
            return ordered.filter { $0.isFinite }
        }
        
        // Filter invalid values efficiently
        var d = ordered.filter { $0.isFinite && $0 >= 0 }
        
        // Handle empty data
        guard !d.isEmpty else { return [] }
        
        // Pad short series (minimum 4 points for smooth rendering)
        if d.count < 4 {
            let lastValue = d.last ?? 1.0
            d.append(contentsOf: repeatElement(lastValue, count: 4 - d.count))
        }
        
        // Check for flat data (all values essentially equal)
        // Use first/last/middle comparison for speed instead of full min/max scan
        let first = d[0]
        let last = d[d.count - 1]
        let mid = d[d.count / 2]
        
        // Quick flatness check
        let quickRange = max(abs(last - first), abs(mid - first), abs(mid - last))
        
        if quickRange < 1e-10 {
            // Data appears flat - confirm with full range check
            guard let minV = d.min(), let maxV = d.max() else { return d }
            let rng = maxV - minV
            
            // Only treat as truly flat if range is below floating point noise threshold
            if rng < 1e-12 {
                let avg = d.reduce(0, +) / Double(d.count)
                return Array(repeating: avg, count: d.count)
            }
        }
        
        return d
    }

    // MARK: - LTTB Downsampling (Largest Triangle Three Buckets)
    // Preserves visual features (peaks, valleys) better than simple stride-based decimation.
    // This is the industry-standard algorithm for sparkline downsampling.
    private func resample(_ series: [Double], maxPoints: Int) -> [Double] {
        let n = series.count
        guard n > maxPoints, maxPoints > 2 else { return series }
        
        var out: [Double] = []
        out.reserveCapacity(maxPoints)
        
        // Always include the first point
        out.append(series[0])
        
        // Bucket size (excluding first and last points)
        let bucketSize = Double(n - 2) / Double(maxPoints - 2)
        
        var previousSelectedIndex = 0
        
        for bucketIndex in 0..<(maxPoints - 2) {
            // Calculate bucket boundaries
            let bucketStart = Int(Double(bucketIndex) * bucketSize) + 1
            let bucketEnd = min(Int(Double(bucketIndex + 1) * bucketSize) + 1, n - 1)
            
            // Calculate the average point of the next bucket (for triangle area calculation)
            let nextBucketStart = bucketEnd
            let nextBucketEnd = min(Int(Double(bucketIndex + 2) * bucketSize) + 1, n)
            
            var avgX: Double = 0
            var avgY: Double = 0
            let nextBucketCount = nextBucketEnd - nextBucketStart
            
            if nextBucketCount > 0 {
                for i in nextBucketStart..<nextBucketEnd {
                    avgX += Double(i)
                    avgY += series[i]
                }
                avgX /= Double(nextBucketCount)
                avgY /= Double(nextBucketCount)
            } else {
                avgX = Double(n - 1)
                avgY = series[n - 1]
            }
            
            // Find the point in this bucket that creates the largest triangle
            // with the previously selected point and the average of the next bucket
            var maxArea: Double = -1
            var selectedIndex = bucketStart
            
            let pointAX = Double(previousSelectedIndex)
            let pointAY = series[previousSelectedIndex]
            
            for i in bucketStart..<bucketEnd {
                // Calculate triangle area using the cross product formula
                let area = abs(
                    (pointAX - avgX) * (series[i] - pointAY) -
                    (pointAX - Double(i)) * (avgY - pointAY)
                ) * 0.5
                
                if area > maxArea {
                    maxArea = area
                    selectedIndex = i
                }
            }
            
            out.append(series[selectedIndex])
            previousSelectedIndex = selectedIndex
        }
        
        // Always include the last point
        out.append(series[n - 1])
        
        return out
    }

    // MARK: - Point Generation
    
    /// Convert values to points in view space with pixel-perfect alignment
    /// Uses pre-computed multipliers for better performance
    @inline(__always)
    private func makePoints(_ values: [Double], w: CGFloat, h: CGFloat, low: Double, denom: Double, scale: CGFloat) -> [CGPoint] {
        let n = values.count
        guard n > 0 else { return [] }
        
        // Pre-compute constants
        let countMinus1 = CGFloat(max(n - 1, 1))
        let xMultiplier = w / countMinus1
        let safeScale = max(scale, 1.0)
        let invScale = 1.0 / safeScale
        
        // Pre-allocate output array
        var points = [CGPoint]()
        points.reserveCapacity(n)
        
        for (idx, v) in values.enumerated() {
            // X: linear interpolation across width
            let rawX = xMultiplier * CGFloat(idx)
            
            // Y: normalized value mapped to height (inverted for screen coordinates)
            let norm = (v - low) / denom
            let rawY = h * (1.0 - CGFloat(norm))
            
            // Snap to pixel grid for crisp rendering
            let x = (rawX * safeScale).rounded() * invScale
            let y = (rawY * safeScale).rounded() * invScale
            
            points.append(CGPoint(x: x, y: y))
        }
        
        return points
    }

    // MARK: - Catmull-Rom Interpolation
    // Optimized implementation for smoother curves (Y only; X stays linear to preserve monotonicity)
    // Uses pre-computed coefficients for better performance
    private func catmullRom(_ pts: [CGPoint], samplesPerSegment: Int) -> [CGPoint] {
        let n = pts.count
        guard n >= 2, samplesPerSegment > 0 else { return pts }
        
        // Pre-allocate output array for better performance
        let outputCount = (n - 1) * samplesPerSegment + 1
        var out = [CGPoint]()
        out.reserveCapacity(outputCount)
        
        // Pre-compute reciprocal for division optimization
        let invSamples = 1.0 / CGFloat(samplesPerSegment)
        
        // Helper to safely access points with boundary clamping
        @inline(__always) func safePoint(_ i: Int) -> CGPoint {
            pts[max(0, min(n - 1, i))]
        }
        
        for i in 0..<(n - 1) {
            let p0 = safePoint(i - 1)
            let p1 = safePoint(i)
            let p2 = safePoint(i + 1)
            let p3 = safePoint(i + 2)
            
            // Pre-compute Catmull-Rom coefficients for this segment (Y axis)
            let c0 = p1.y
            let c1 = 0.5 * (-p0.y + p2.y)
            let c2 = 0.5 * (2*p0.y - 5*p1.y + 4*p2.y - p3.y)
            let c3 = 0.5 * (-p0.y + 3*p1.y - 3*p2.y + p3.y)
            
            // X interpolation values
            let xDelta = p2.x - p1.x
            
            for s in 0..<samplesPerSegment {
                let t = CGFloat(s) * invSamples
                let t2 = t * t
                let t3 = t2 * t
                
                // Linear interpolation for X (time axis must be monotonic)
                let x = p1.x + xDelta * t
                
                // Catmull-Rom interpolation for Y using pre-computed coefficients
                let y = c0 + c1*t + c2*t2 + c3*t3
                
                out.append(CGPoint(x: x, y: y))
            }
        }
        
        // Always include the last point
        if let last = pts.last {
            out.append(last)
        }
        
        return out
    }

    /// SPARKLINE FIX: Generates a stable hash of the sparkline data for identity purposes.
    /// Uses orientation-invariant characteristics to prevent identity changes from flips.
    /// Uses heavy quantization to avoid floating point noise causing unnecessary identity changes.
    /// CRITICAL: Does NOT include color (isPositive) to prevent re-renders on color changes alone.
    private var dataIdentityHash: Int {
        guard !data.isEmpty else { return 0 }
        var hasher = Hasher()
        let validValues = data.filter { $0.isFinite && $0 > 0 }
        guard !validValues.isEmpty else { return 0 }
        
        // Quantize count to ranges of 20 (matches stableDataHash for consistency)
        // This prevents hash changes when count varies by small amounts (e.g., 165 vs 168)
        let quantizedCount = (validValues.count / 20) * 20
        hasher.combine(quantizedCount)
        
        // Quantize min/max to significant figures based on magnitude (matches stableDataHash)
        let minV = validValues.min()!
        let maxV = validValues.max()!
        let range = maxV - minV
        let magnitude = range > 0 ? pow(10, floor(log10(range))) : 1.0
        let quantizationStep = Swift.max(magnitude / 10, 1.0)
        
        let quantizedMin = floor(minV / quantizationStep) * quantizationStep
        let quantizedMax = ceil(maxV / quantizationStep) * quantizationStep
        
        hasher.combine(Int(quantizedMin))
        hasher.combine(Int(quantizedMax))
        
        // DO NOT include isPositive or overrideColor here
        // Color changes should update the stroke/fill color but NOT cause a full re-render
        // of the path geometry. The color is applied via the effectiveColor computed property.
        
        return hasher.finalize()
    }
    
    var body: some View {
        // Render immediately — EngineBookkeeping class wrapper prevents cascade.
        makeBody()
    }

    // MEMORY FIX v16: Replaced AnyView return with @ViewBuilder.
    // AnyView allocates a heap box on every body evaluation that prevents SwiftUI from
    // efficiently diffing the view tree. With 8 sparklines evaluated 60x/sec from shimmer
    // animations, this alone caused ~4 MB/s of unreleased allocations.
    @ViewBuilder
    private func makeBody() -> some View {
        let color: Color = effectiveColor
        let base = color
        let top = base.opacity(0.95)
        let grad = LinearGradient(colors: [top, base.opacity(0.85), base.opacity(0.65)], startPoint: .leading, endPoint: .trailing)

        backgroundCard(base: base)
            .overlay(
                GeometryReader { geo in
                    let w = max(1.0, geo.size.width)
                    let h = max(1.0, geo.size.height)
                    chartLayer(w: w, h: h, grad: grad, color: color, base: base)
                }
            )
            .frame(width: preferredWidth)
            .frame(minWidth: preferredWidth == nil ? minWidth : nil)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transaction { $0.disablesAnimations = true }
    }

    @ViewBuilder
    private func gridOverlay(base: Color) -> some View {
        if gridEnabled && height >= 28 {
            GeometryReader { g in
                let w = g.size.width
                let h = g.size.height
                let gridColor = base.opacity(0.10)
                Path { p in
                    p.move(to: CGPoint(x: w * 0.33, y: 0)); p.addLine(to: CGPoint(x: w * 0.33, y: h))
                    p.move(to: CGPoint(x: w * 0.66, y: 0)); p.addLine(to: CGPoint(x: w * 0.66, y: h))
                    p.move(to: CGPoint(x: 0, y: h * 0.5)); p.addLine(to: CGPoint(x: w, y: h * 0.5))
                }
                .stroke(gridColor, lineWidth: 0.6)
            }
            .allowsHitTesting(false)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    private func sheenOverlay(base: Color) -> some View {
        // MEMORY FIX v19: Disable sheen overlay animation entirely.
        // TimelineView-based periodic updates were still contributing to Phase 1
        // growth before the emergency stop had a chance to engage.
        let _ = (base, sheenEnabled, reduceMotion, globalAnimationsKilled)
        EmptyView()
    }

    // Adaptive colors for sparkline background
    private var adaptiveSparklineStroke: Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.08) : UIColor.black.withAlphaComponent(0.08)
        })
    }
    private var adaptiveSparklineShadow: Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark ? UIColor.black.withAlphaComponent(0.25) : UIColor.black.withAlphaComponent(0.08)
        })
    }
    private var adaptiveSparklineOverlay: Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark ? UIColor.black.withAlphaComponent(0.18) : UIColor.clear
        })
    }
    private var adaptiveSparklineGradient: Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.10) : UIColor.black.withAlphaComponent(0.03)
        })
    }

    // MEMORY FIX v16: Replaced AnyView return with @ViewBuilder to eliminate heap allocation
    // per body evaluation. AnyView creates a type-erased box on the heap every time body is called,
    // and these accumulate when body is evaluated frequently (e.g., during animations).
    @ViewBuilder
    private func backgroundCard(base: Color) -> some View {
        switch backgroundStyle {
        case .glass:
            if !showBackground {
                Color.clear
            } else {
            // PERFORMANCE FIX v19: Replaced .ultraThinMaterial with solid color
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(DS.Adaptive.chipBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(adaptiveSparklineStroke, lineWidth: 0.8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(adaptiveSparklineShadow, lineWidth: 1)
                        .opacity(0.6)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(adaptiveSparklineOverlay)
                )
                .overlay(
                    LinearGradient(
                        colors: [adaptiveSparklineGradient, .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                )
                // Accent rim that picks up the line color for a high-tech edge
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            LinearGradient(colors: [base.opacity(0.25), .clear], startPoint: .leading, endPoint: .trailing),
                            lineWidth: 1
                        )
                )
                // Subtle horizontal vignette for depth
                .overlay(
                    LinearGradient(
                        stops: [
                            .init(color: Color.black.opacity(0.18), location: 0),
                            .init(color: .clear, location: 0.15),
                            .init(color: .clear, location: 0.85),
                            .init(color: Color.black.opacity(0.18), location: 1)
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .allowsHitTesting(false)
                )
                // Subtle vertical vignette
                .overlay(
                    LinearGradient(
                        stops: [
                            .init(color: Color.black.opacity(0.12), location: 0),
                            .init(color: .clear, location: 0.35),
                            .init(color: .clear, location: 0.9),
                            .init(color: Color.black.opacity(0.16), location: 1)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .allowsHitTesting(false)
                )
                // Subtle grid overlay inside the glass card
                .overlay(gridOverlay(base: base))
                // Animated sheen pass (disabled for Reduce Motion)
                .overlay(sheenOverlay(base: base))
            }
        case .tinted:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(base.opacity(backgroundOpacity * 0.75))
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.black.opacity(0.25))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(borderOpacity), lineWidth: 0.8)
                )
                .overlay(
                    LinearGradient(
                        colors: [Color.white.opacity(glassOverlayOpacity), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                )
                .overlay(gridOverlay(base: base))
        case .dark:
            if !showBackground {
                Color.clear
            } else {
            let isDarkMode = colorScheme == .dark
            // Adaptive background: premium dark terminal in dark mode, clean light in light mode
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: isDarkMode
                            ? [
                                Color(red: 0.08, green: 0.08, blue: 0.12).opacity(0.85),
                                Color(red: 0.04, green: 0.04, blue: 0.08).opacity(0.90)
                              ]
                            : [
                                Color(white: 0.96),
                                Color(white: 0.93)
                              ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    // Subtle inner highlight for depth
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: isDarkMode
                                    ? [Color.white.opacity(0.03), Color.clear]
                                    : [Color.white.opacity(0.6), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                )
                .overlay(
                    // Refined border with subtle trend color accent
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: isDarkMode
                                    ? [
                                        base.opacity(0.30),
                                        Color.white.opacity(0.08),
                                        base.opacity(0.20)
                                      ]
                                    : [
                                        base.opacity(0.20),
                                        Color.black.opacity(0.06),
                                        base.opacity(0.15)
                                      ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isDarkMode ? 0.6 : 0.8
                        )
                )
            }
        case .none:
            // Return a clear rect instead of EmptyView for proper GeometryReader sizing
            Color.clear
        }
    }
    
    // MARK: - Path Construction Helpers
    
    /// Builds a Path from an array of points. Optimized for repeated use.
    @inline(__always)
    private func buildLinePath(from points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for p in points.dropFirst() {
                path.addLine(to: p)
            }
        }
    }
    
    @ViewBuilder
    private func glowUnderlay(smoothPoints: [CGPoint], grad: LinearGradient, color: Color, vol: Double) -> some View {
        // Keep glow subtle and single-layer so the line reads as one clean stroke.
        // Multi-layer glows can look like double/triple lines in compact list rows.
        if !smoothPoints.isEmpty, glowOpacity > 0 {
            let path = buildLinePath(from: smoothPoints)
            let glowColor = color.opacity(glowOpacity * 0.34)
            path.stroke(
                glowColor,
                style: StrokeStyle(
                    lineWidth: glowLineWidth * 1.35,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
    }

    @ViewBuilder
    private func mainStroke(smoothPoints: [CGPoint], grad: LinearGradient, color: Color) -> some View {
        if !smoothPoints.isEmpty {
            let path = buildLinePath(from: smoothPoints)
            // Use .butt lineCap for crisper ends at small sizes; .round for larger sparklines
            let capStyle: CGLineCap = compact ? .butt : .round
            let joinStyle: CGLineJoin = compact ? .miter : .round
            let strokeStyle = StrokeStyle(lineWidth: effectiveLineWidth, lineCap: capStyle, lineJoin: joinStyle)
            
            // MEMORY FIX: Removed .shadow(color: .clear, radius: 0) from sparkline strokes.
            // Each shadow creates a GPU offscreen render buffer per sparkline instance.
            // With 15+ sparklines visible, this alone consumed ~2+ MB of GPU memory.
            if gradientStroke {
                path.stroke(grad, style: strokeStyle)
            } else {
                path.stroke(color, style: strokeStyle)
            }
        }
    }

    @ViewBuilder
    private func specularHighlight(smoothPoints: [CGPoint]) -> some View {
        // MEMORY FIX: Specular highlight disabled - .blendMode(.normal) forces a GPU offscreen
        // render buffer per sparkline. The visual effect is subtle but the memory cost is not.
        EmptyView()
    }

    @ViewBuilder
    private func areaFill(smoothPoints: [CGPoint], h: CGFloat, color: Color) -> some View {
        if let first = smoothPoints.first, let last = smoothPoints.last, smoothPoints.count >= 2 {
            // Create fill path without diagonal closeSubpath artifact
            Path { path in
                // Start at bottom-left corner
                path.move(to: CGPoint(x: first.x, y: h))
                // Go up to first sparkline point
                path.addLine(to: first)
                // Draw along the sparkline
                for p in smoothPoints.dropFirst() { path.addLine(to: p) }
                // Go down to bottom-right corner
                path.addLine(to: CGPoint(x: last.x, y: h))
                // Close path (horizontal line along bottom - no visible artifact)
                path.closeSubpath()
            }
            .fill(LinearGradient(
                stops: compact ? [
                    // COMPACT MODE: Simpler gradient for cleaner appearance
                    .init(color: color.opacity(fillOpacity), location: 0.0),
                    .init(color: color.opacity(fillOpacity * 0.3), location: 0.5),
                    .init(color: color.opacity(0.02), location: 1.0)
                ] : [
                    // FULL MODE: Rich gradient with sustained opacity for visible depth/shadow
                    // Both red and green fills get a boost for better visibility on dark backgrounds
                    .init(color: color.opacity(fillOpacity + (color == Self.professionalRed ? redFillBoost : 0.05)), location: 0.0),
                    .init(color: color.opacity(fillOpacity * 0.85), location: 0.20),
                    .init(color: color.opacity(fillOpacity * 0.60), location: 0.45),
                    .init(color: color.opacity(fillOpacity * 0.30), location: 0.70),
                    .init(color: color.opacity(fillOpacity * 0.10), location: 0.88),
                    .init(color: color.opacity(0.02), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            ))
        }
    }

    @ViewBuilder
    private func trailHighlight(smoothPoints: [CGPoint], color: Color, base: Color) -> some View {
        // MEMORY FIX: Trail highlight disabled - .blendMode(.normal) and .shadow(color: .clear, radius: 0) each create
        // GPU offscreen render buffers. Two buffers per sparkline × 15+ visible sparklines
        // = 30+ additional GPU buffers (~4+ MB). The area fill gradient already provides
        // visual emphasis on the trailing portion.
        EmptyView()
    }

    @ViewBuilder
    private func baselineLine(by: CGFloat?, color: Color, w: CGFloat) -> some View {
        if let by = by, by.isFinite {
            Path { p in
                p.move(to: CGPoint(x: 0, y: by))
                p.addLine(to: CGPoint(x: w, y: by))
            }
            .stroke(color.opacity(0.28), style: StrokeStyle(lineWidth: 1.0, lineCap: .round, dash: [3, 3]))
        }
    }

    /// Draws a small tick mark on the left edge at the Y-position of a specific data point (e.g., 24h ago price)
    @ViewBuilder
    private func referenceLevelLine(series: [Double], w: CGFloat, h: CGFloat, low: Double, denom: Double) -> some View {
        if showReferenceLevel {
            // Calculate the reference index - default to ~24h ago (assuming hourly data in 7D = 168 points)
            let refIndex: Int = {
                if let idx = referenceLevelIndex {
                    return max(0, min(series.count - 1, idx))
                }
                let autoIdx = max(0, series.count - max(1, series.count / 7))
                return min(series.count - 1, autoIdx)
            }()
            
            if refIndex < series.count, series[refIndex].isFinite {
                let refValue = series[refIndex]
                let norm = (refValue - low) / denom
                let refY = h * (1.0 - CGFloat(norm))
                let tickWidth: CGFloat = 6
                
                Path { p in
                    p.move(to: CGPoint(x: 0, y: refY))
                    p.addLine(to: CGPoint(x: tickWidth, y: refY))
                }
                .stroke(
                    Color.white.opacity(referenceLevelOpacity),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                )
            }
        }
    }

    @ViewBuilder
    private func minMaxTicks(plotted: [Double], basePoints: [CGPoint], h: CGFloat, color: Color) -> some View {
        if showMinMaxTicks {
            if let minValue = plotted.min(), let maxValue = plotted.max(),
               let minIndex = plotted.firstIndex(of: minValue),
               let maxIndex = plotted.firstIndex(of: maxValue) {
                // Min tick
                Path { p in
                    let minPt = basePoints[minIndex]
                    let tickHeight: CGFloat = 6
                    p.move(to: CGPoint(x: minPt.x, y: max(0.0, minPt.y - tickHeight)))
                    p.addLine(to: CGPoint(x: minPt.x, y: min(h, minPt.y + tickHeight)))
                }
                .stroke(color.opacity(0.6), lineWidth: 1)
                // Max tick
                Path { p in
                    let maxPt = basePoints[maxIndex]
                    let tickHeight: CGFloat = 6
                    p.move(to: CGPoint(x: maxPt.x, y: max(0.0, maxPt.y - tickHeight)))
                    p.addLine(to: CGPoint(x: maxPt.x, y: min(h, maxPt.y + tickHeight)))
                }
                .stroke(color.opacity(0.6), lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private func extremaDots(plotted: [Double], basePoints: [CGPoint], color: Color) -> some View {
        if showExtremaDots {
            if let minValue = plotted.min(), let maxValue = plotted.max(),
               let minIndex = plotted.firstIndex(of: minValue),
               let maxIndex = plotted.firstIndex(of: maxValue) {
                // MEMORY FIX: Removed .shadow(color: .clear, radius: 0) from extrema dots - each creates a GPU buffer
                Circle()
                    .fill(color.opacity(0.95))
                    .frame(width: 2.6, height: 2.6)
                    .position(basePoints[minIndex])
                Circle()
                    .fill(color.opacity(0.95))
                    .frame(width: 2.6, height: 2.6)
                    .position(basePoints[maxIndex])
            }
        }
    }

    @ViewBuilder
    private func endDotAndPulse(last: CGPoint?, color: Color) -> some View {
        if showEndDot, let last = last {
            // GLOW RESTORE v26: Enhanced end dot with soft glow ring for premium look.
            // Uses opacity-based rings instead of .blur() — zero GPU offscreen buffers.
            let skipExpensiveEffects = sparklineShouldReduceDataDuringScroll()
            
            // Soft outer glow ring (only in non-compact full rendering mode)
            if !compact && glowOpacity > 0 {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 10, height: 10)
                    .position(x: last.x, y: last.y)
            }
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: 6, height: 6)
                .position(x: last.x, y: last.y)
            Circle()
                .fill(color)
                .frame(width: 3.5, height: 3.5)
                .position(x: last.x, y: last.y)

            // MEMORY FIX v19: Disable end-dot pulse animation entirely.
            let _ = (endDotPulse, compact, skipExpensiveEffects, globalAnimationsKilled, reduceMotion)
        }
    }
    
    @ViewBuilder
    private func chartLayer(w: CGFloat, h: CGFloat, grad: LinearGradient, color: Color, base: Color) -> some View {
        // Use prepared data for stats, then adaptively resample for rendering
        let series = preparedData
        
        // Apply trailing inset only to prevent end dot clipping at right edge
        // The end dot with pulse animation extends ~8pt from center
        // Chart starts from x=0 (left edge) for clean alignment
        let trailingInset = horizontalInset
        let effectiveW = max(1, w - trailingInset)

        // Placeholder handling without early return (ViewBuilder-friendly)
        let placeholderEnabled = true
        let isEffectivelyEmpty = series.isEmpty || !series.contains(where: { $0.isFinite })

        if placeholderEnabled && isEffectivelyEmpty {
            // MEMORY FIX v16: Static placeholder — NO TimelineView.
            // The previous TimelineView fired every 0.5s creating Rectangle + LinearGradient
            // allocations. With 8 empty sparklines, that's 16 allocations/sec that never free.
            // Combined with AnyView wrapping, this caused ~8 MB/s memory growth.
            ZStack {
                let rr = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                rr.fill(Color.white.opacity(0.06))
                    .overlay(rr.stroke(Color.white.opacity(0.12), lineWidth: 0.6))
            }
            .mask(edgeFadeMask(leading: leadingFade, trailing: trailingFade))
        } else {
            let minV = series.min() ?? 0
            let maxV = series.max() ?? 1
            let range = max(maxV - minV, 1e-9)
            // Use range-relative padding only so small moves on large-price assets remain visible
            let pad = max(range * verticalPaddingRatio, range * 0.06) // at least 6% of range
            let low = minV - pad
            let high = maxV + pad
            let denom = max(high - low, 1e-9)
            let vol = volatility(of: series)

            let baselineY: CGFloat? = {
                guard showBaseline else { return nil }
                let m = mean(series)
                let norm = (m - low) / denom
                return h * (1 - CGFloat(norm))
            }()

            // Adaptive downsampling - increased from 96 to 150 for more price detail
            // PERFORMANCE FIX v25: Use fewer points during scroll (48 vs 150) for faster Path rendering
            // This only affects data resolution, NOT glow quality (glow always renders full)
            let scrolling = sparklineShouldReduceDataDuringScroll()
            let maxPoints = scrolling ? 48 : max(72, min(150, maxPlottedPoints))
            let plotted = resample(series, maxPoints: maxPoints)

            Group {
                if let first = plotted.first, plotted.allSatisfy({ $0 == first }) {
                    // Flat series: render a single crisp line centered vertically
                    // Chart starts at x=0, ends at effectiveW (with trailing inset for end dot)
                    ZStack {
                        Path { p in
                            let y = h / 2.0
                            p.move(to: CGPoint(x: 0, y: y))
                            p.addLine(to: CGPoint(x: effectiveW, y: y))
                        }
                        .stroke(grad, style: StrokeStyle(lineWidth: effectiveLineWidth, lineCap: .round))
                        .opacity(gradientStroke ? 1 : 0)
                        .overlay(
                            Path { p in
                                let y = h / 2.0
                                p.move(to: CGPoint(x: 0, y: y))
                                p.addLine(to: CGPoint(x: effectiveW, y: y))
                            }
                            .stroke(color, style: StrokeStyle(lineWidth: effectiveLineWidth, lineCap: .round))
                            .opacity(gradientStroke ? 0 : 1)
                        )
                    }
                    .mask(edgeFadeMask(leading: leadingFade, trailing: trailingFade))
                } else {
                    // Convert to points using effective width (starts at x=0, ends at effectiveW)
                    // No offset needed - chart starts from left edge, trailing inset reserves space for end dot
                    let renderScale = displayScale > 0 ? displayScale : UIScreen.main.scale
                    let basePoints = makePoints(plotted, w: effectiveW, h: h, low: low, denom: denom, scale: renderScale)
                    
                    // Use moderate smoothing for compact mode (4 samples for smoother curves), full smoothing otherwise
                    // PERFORMANCE FIX v25: Skip catmull-rom smoothing during scroll (use raw basePoints)
                    // Smoothing is CPU-intensive and invisible during fast scroll anyway
                    let samples = rawMode || scrolling ? 0 : (compact ? 4 : smoothSamplesPerSegment)
                    let maxX = basePoints.last?.x ?? .infinity
                    let points: [CGPoint] = (samples > 0) ? catmullRom(basePoints, samplesPerSegment: samples).map { CGPoint(x: min($0.x, maxX), y: min(h, max(0, $0.y))) } : basePoints

                    if w < 12 {
                        // Tiny placeholder shape when layout is extremely constrained
                        Capsule()
                            .fill(color.opacity(0.18))
                            .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 1))
                            .frame(width: max(8.0, w * 0.9), height: max(6.0, h * 0.5))
                            .position(x: w / 2.0, y: h / 2.0)
                            .mask(edgeFadeMask(leading: leadingFade, trailing: trailingFade))
                    } else {
                        ZStack {
                            // PERFORMANCE FIX v19: Skip decorative overlays during scroll
                            // These effects (baseline, reference, glow, specular, trail, ticks, dots)
                            // each add Path computations and compositing work. During scroll,
                            // only the main stroke and fill are needed for visual continuity.
                            if !compact && !scrolling {
                                baselineLine(by: baselineY, color: color, w: w)
                                referenceLevelLine(series: series, w: w, h: h, low: low, denom: denom)
                            }
                            
                            // Area fill FIRST (underneath everything for proper layering)
                            areaFill(smoothPoints: points, h: h, color: color)
                            
                            // CONSISTENCY FIX v23: Always render glow so all sparklines look
                            // identical (BTC and ETH were inconsistent due to timing of scroll flag).
                            // During scroll, glowUnderlay renders a lightweight single-stroke version.
                            if glowOpacity > 0 {
                                glowUnderlay(smoothPoints: points, grad: grad, color: color, vol: vol)
                            }

                            // Main stroke on top of fill and glow
                            mainStroke(smoothPoints: points, grad: grad, color: color)

                            if !compact && !scrolling {
                                specularHighlight(smoothPoints: points)
                                trailHighlight(smoothPoints: points, color: color, base: base)
                                minMaxTicks(plotted: plotted, basePoints: basePoints, h: h, color: color)
                                extremaDots(plotted: plotted, basePoints: basePoints, color: color)
                            }
                            
                            // End dot for both compact and non-compact modes
                            // FIX v23: Always show end dot — it's the "live price" indicator
                            // users expect. During scroll/startup, endDotAndPulse already
                            // renders a minimal 3.5pt dot (cheap) instead of the full glow version.
                            endDotAndPulse(last: points.last, color: color)
                        }
                        .mask(edgeFadeMask(leading: leadingFade, trailing: trailingFade))
                        // PERFORMANCE FIX: Removed .drawingGroup() which rasterizes to a Metal texture.
                        // With dozens of sparklines in the market list, each .drawingGroup() call causes
                        // GPU texture upload overhead during scroll, leading to frame drops when new
                        // rows appear. SwiftUI's default rendering handles sparklines efficiently at
                        // this display size without the extra rasterization step.
                    }
                }
            }
        }
    }
}

#if DEBUG
struct SparklineView_CS_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SparklineView(data: [1, 3, 2, 5, 4, 6, 5], isPositive: true)
                .frame(width: 140)
                .padding()
                .background(Color.black)
                .previewLayout(.sizeThatFits)

            SparklineView(
                data: stride(from: 0.0, through: 3.0, by: 0.2).map { sin($0) + 0.2 * Double.random(in: -0.2...0.2) + 4 },
                isPositive: true,
                overrideColor: .green,
                height: 40,
                lineWidth: 1.2,
                verticalPaddingRatio: 0.08,
                fillOpacity: 0.18,
                gradientStroke: true,
                showEndDot: true,
                leadingFade: 0.28,
                trailingFade: 0.08,
                showTrailHighlight: true,
                trailLengthRatio: 0.25,
                minWidth: 120,
                endDotPulse: true,
                showMinMaxTicks: true,
                preferredWidth: 140,
                showBaseline: true
            )
            .padding()
            .background(Color.black)
            .previewLayout(.sizeThatFits)

            SparklineView(
                data: stride(from: 0.0, through: 3.0, by: 0.2).map { cos($0) + 0.15 * Double.random(in: -0.2...0.2) + 4 },
                isPositive: true,
                height: 36,
                preferredWidth: 160, backgroundStyle: .glass
            )
            .padding()
            .background(Color.black)
            .previewLayout(.sizeThatFits)
        }
    }
}
#endif

