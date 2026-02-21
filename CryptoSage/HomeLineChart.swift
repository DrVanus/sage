import SwiftUI

struct HomeLineChartView: View {
    let data: [Double]
    var lineColor: Color = .green
    
    /// Trailing inset to prevent end dot from being clipped at right edge
    /// (Leading edge starts at 0 for clean left alignment)
    var trailingInset: CGFloat = 6

    @Environment(\.colorScheme) private var colorScheme
    
    @State private var drawProgress: CGFloat = 0
    @State private var hasAnimated: Bool = false
    // PERFORMANCE: Track last data hash to detect actual content changes
    @State private var lastDataHash: Int = 0
    
    /// Dynamic line width based on data density - thinner for more detail
    private var effectiveLineWidth: CGFloat {
        let count = data.count
        if count > 200 { return 1.4 }  // Very dense data
        if count > 150 { return 1.6 }  // Dense data
        if count > 100 { return 1.8 }  // Moderate data
        return 2.0  // Default
    }
    
    /// Professional multi-stop gradient for area fill
    private var areaGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: lineColor.opacity(0.42), location: 0.0),   // Top - visible
                .init(color: lineColor.opacity(0.28), location: 0.25), // Upper mid
                .init(color: lineColor.opacity(0.12), location: 0.55), // Lower mid
                .init(color: lineColor.opacity(0.04), location: 0.80), // Near bottom
                .init(color: .clear, location: 1.0)                    // Bottom - clear
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    // PERFORMANCE: Build line path once, reuse for main line and glow
    private func buildLinePath(from points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for p in points.dropFirst() { path.addLine(to: p) }
        }
    }
    
    // PERFORMANCE: Simple hash of data for change detection
    private var dataHash: Int {
        var hasher = Hasher()
        hasher.combine(data.count)
        if let first = data.first { hasher.combine(first) }
        if let last = data.last { hasher.combine(last) }
        return hasher.finalize()
    }

    var body: some View {
        GeometryReader { geo in
            // SAFETY: Validate data has at least 2 points and valid range
            let validData = data.filter { $0.isFinite }
            let minVal = validData.min() ?? 0
            let maxVal = validData.max() ?? 1
            let hasValidData = validData.count > 1 && maxVal > minVal
            
            if hasValidData {
                let range = maxVal - minVal
                // Use effective width with trailing inset only (chart starts from left edge)
                let effectiveWidth = max(1, geo.size.width - trailingInset)
                // SAFETY: Use max(1, count - 1) to prevent division by zero
                let divisor = CGFloat(max(1, validData.count - 1))
                let points: [CGPoint] = validData.enumerated().map { (index, value) in
                    let xPos = effectiveWidth * CGFloat(index) / divisor
                    let yPos = geo.size.height * (1 - CGFloat((value - minVal) / range))
                    return CGPoint(x: xPos, y: yPos)
                }
                
                // PERFORMANCE: Build path once, reuse for stroke and glow
                let linePath = buildLinePath(from: points)

                ZStack {
                    let isDark = colorScheme == .dark
                    
                    // Grid lines span full width (decorative, not data-dependent)
                    let gridColor = isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.06)
                    ForEach(0..<3, id: \.self) { i in
                        let y = geo.size.height * CGFloat(i + 1) / 4.0
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: geo.size.width, y: y))
                        }
                        .stroke(gridColor, style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    }

                    // Baseline at first data point - spans chart area only
                    if let firstPoint = points.first, let lastPoint = points.last {
                        Path { path in
                            let y = firstPoint.y
                            path.move(to: CGPoint(x: firstPoint.x, y: y))
                            path.addLine(to: CGPoint(x: lastPoint.x, y: y))
                        }
                        .stroke((isDark ? Color.white : Color.black).opacity(0.06), style: StrokeStyle(lineWidth: 0.8, dash: [4, 4]))
                    }

                    // Area fill with professional multi-stop gradient
                    Path { path in
                        guard let first = points.first, let last = points.last else { return }
                        path.move(to: CGPoint(x: first.x, y: geo.size.height))
                        path.addLine(to: first)
                        for p in points.dropFirst() { path.addLine(to: p) }
                        path.addLine(to: CGPoint(x: last.x, y: geo.size.height))
                        path.closeSubpath()
                    }
                    .fill(areaGradient)

                    // PERFORMANCE: Reuse linePath for both main line and glow
                    // Soft outer glow (behind main line) - reduced in light mode
                    linePath
                        .trim(from: 0, to: max(0, min(1, drawProgress)))
                        .stroke(lineColor.opacity(isDark ? 0.35 : 0.2), style: StrokeStyle(lineWidth: effectiveLineWidth * (isDark ? 3 : 2), lineCap: .round, lineJoin: .round))
                        .opacity(isDark ? 0.25 : 0.15)

                    // Main price line with dynamic width
                    linePath
                        .trim(from: 0, to: max(0, min(1, drawProgress)))
                        .stroke(lineColor, style: StrokeStyle(lineWidth: effectiveLineWidth, lineCap: .round, lineJoin: .round))

                    // Premium end dot — matches SparklineView's live price indicator
                    if let last = points.last {
                        // Outer diffuse glow - reduced in light mode
                        Circle()
                            .fill(lineColor.opacity(isDark ? 0.25 : 0.15))
                            .frame(width: isDark ? 10 : 8, height: isDark ? 10 : 8)
                            .position(last)
                        // Inner glow ring - reduced in light mode
                        Circle()
                            .fill(lineColor.opacity(isDark ? 0.4 : 0.25))
                            .frame(width: isDark ? 6 : 5, height: isDark ? 6 : 5)
                            .position(last)
                        // Solid main dot
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [lineColor.opacity(1.0), lineColor.opacity(0.85)],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 2.5
                                )
                            )
                            .frame(width: 4.5, height: 4.5)
                            .position(last)
                    }
                }
                .onAppear {
                    // Defer to avoid "Modifying state during view update"
                    DispatchQueue.main.async {
                        let reduceMotion = UIAccessibility.isReduceMotionEnabled
                        if reduceMotion || hasAnimated {
                            drawProgress = 1
                        } else {
                            withAnimation(.easeInOut(duration: 0.4)) { drawProgress = 1 }
                            hasAnimated = true
                        }
                        lastDataHash = dataHash
                    }
                }
                // IMPROVEMENT: Watch actual data content changes, not just count
                .onChange(of: dataHash) { _, newHash in
                    // Only reset animation on significant data changes
                    if newHash != lastDataHash {
                        DispatchQueue.main.async {
                            drawProgress = 1
                            lastDataHash = newHash
                        }
                    }
                }
                // MEMORY FIX: .drawingGroup() removed - GPU offscreen buffer savings
            } else {
                // Show placeholder for insufficient data
                Text("No Chart Data")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

