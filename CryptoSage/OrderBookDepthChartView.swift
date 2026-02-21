// MARK: - OrderBookDepthChartView.swift
// Visual depth chart showing cumulative bid/ask depth as step curves (professional trading style)
// OPTIMIZED: Uses Canvas rendering, state caching, and throttled updates for smooth performance

import SwiftUI
import Combine

/// Premium depth chart view showing cumulative order book depth
/// Features step-style curves like professional exchanges (Binance/Coinbase)
/// Bids (green) extend left from mid-price, Asks (red) extend right
struct OrderBookDepthChartView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    @ObservedObject var viewModel: OrderBookViewModel
    let height: CGFloat
    
    // MARK: - Cached Data State (prevents glitchy redraws)
    @State private var cachedBidData: [DepthPoint] = []
    @State private var cachedAskData: [DepthPoint] = []
    @State private var cachedMidPrice: Double = 0
    @State private var cachedSpread: Double = 0
    @State private var cachedMaxDepth: Double = 1
    @State private var cachedPriceRange: (min: Double, max: Double) = (0, 0)
    
    // Smooth animation state
    @State private var displayedBidData: [DepthPoint] = []
    @State private var displayedAskData: [DepthPoint] = []
    @State private var animationProgress: CGFloat = 1.0
    
    // Interactive state
    @State private var touchLocation: CGPoint? = nil
    @State private var selectedData: (price: Double, depth: Double, isBid: Bool, x: CGFloat)? = nil
    @State private var chartSize: CGSize = .zero
    @State private var lastHapticPrice: Double? = nil
    
    // Pulse animation for best price markers
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.6
    
    // Haptic generators
    private let impactGenerator = UIImpactFeedbackGenerator(style: .light)
    private let selectionGenerator = UISelectionFeedbackGenerator()
    
    private var isDark: Bool { colorScheme == .dark }
    
    // MARK: - Depth Point Model
    struct DepthPoint: Equatable {
        let price: Double
        let cumDepth: Double
        
        static func == (lhs: DepthPoint, rhs: DepthPoint) -> Bool {
            abs(lhs.price - rhs.price) < 0.0001 && abs(lhs.cumDepth - rhs.cumDepth) < 0.01
        }
    }
    
    // MARK: - Design Constants
    private enum Design {
        // Chart proportions
        static let depthHeightRatio: CGFloat = 0.90  // Use 90% of height for depth
        static let cornerRadius: CGFloat = 10
        static let chartCornerRadius: CGFloat = 8
        
        // Line widths
        static let depthLineWidth: CGFloat = 2.5
        static let gridLineWidth: CGFloat = 0.5
        static let midPriceLineWidth: CGFloat = 1.5
        
        // Marker sizes
        static let bestPriceMarkerSize: CGFloat = 10
        static let bestPriceOuterSize: CGFloat = 18
        static let crosshairDotSize: CGFloat = 10
        static let crosshairOuterSize: CGFloat = 20
        
        // Glow effects
        static let lineGlowRadius: CGFloat = 6
        static let markerGlowRadius: CGFloat = 8
        
        // Typography
        static let headerLabelSize: CGFloat = 9
        static let headerValueSize: CGFloat = 13
        static let axisLabelSize: CGFloat = 9
        static let midPriceLabelSize: CGFloat = 10
        
        // Padding
        static let horizontalPadding: CGFloat = 12
        static let verticalPadding: CGFloat = 10
        static let headerBottomPadding: CGFloat = 8
    }
    
    // MARK: - Enhanced Gradients
    private var bidAreaGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: DS.Colors.bid.opacity(isDark ? 0.45 : 0.32), location: 0),
                .init(color: DS.Colors.bid.opacity(isDark ? 0.25 : 0.18), location: 0.4),
                .init(color: DS.Colors.bid.opacity(isDark ? 0.12 : 0.08), location: 0.7),
                .init(color: DS.Colors.bid.opacity(isDark ? 0.04 : 0.02), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    private var askAreaGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: DS.Colors.ask.opacity(isDark ? 0.45 : 0.32), location: 0),
                .init(color: DS.Colors.ask.opacity(isDark ? 0.25 : 0.18), location: 0.4),
                .init(color: DS.Colors.ask.opacity(isDark ? 0.12 : 0.08), location: 0.7),
                .init(color: DS.Colors.ask.opacity(isDark ? 0.04 : 0.02), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    private var chartBackgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                isDark ? Color(white: 0.07) : Color(white: 0.98),
                isDark ? Color(white: 0.03) : Color(white: 0.95)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            // Chart header with spread info (or tooltip when touching)
            if let data = selectedData {
                interactiveHeader(data: data)
            } else {
                chartHeader
            }
            
            // Chart area with Canvas rendering
            GeometryReader { geo in
                let width = geo.size.width
                let chartHeight = geo.size.height - 20
                
                ZStack {
                    // Premium background
                    chartBackground(width: width, height: chartHeight)
                    
                    // Canvas-rendered chart content (GPU accelerated)
                    chartCanvas(width: width, height: chartHeight)
                        // MEMORY FIX: .drawingGroup() removed - GPU offscreen buffer savings
                    
                    // Mid-price indicator (hide when touching)
                    if touchLocation == nil {
                        midPriceIndicator(width: width, height: chartHeight)
                    }
                    
                    // Animated best bid/ask markers
                    bestPriceMarkers(width: width, height: chartHeight)
                    
                    // Interactive crosshair overlay
                    if let touch = touchLocation {
                        crosshairOverlay(touch: touch, width: width, height: chartHeight)
                    }
                }
                .frame(height: chartHeight)
                .clipShape(RoundedRectangle(cornerRadius: Design.chartCornerRadius))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            handleTouch(value.location, width: width)
                        }
                        .onEnded { _ in
                            withAnimation(.easeOut(duration: 0.15)) {
                                touchLocation = nil
                                selectedData = nil
                                lastHapticPrice = nil
                            }
                        }
                )
                .onAppear {
                    chartSize = geo.size
                    updateCachedData()
                    startPulseAnimation()
                }
                
                // Price axis
                priceAxis(width: width)
                    .offset(y: chartHeight + 2)
            }
            .frame(height: height - 32)
        }
        .padding(.horizontal, Design.horizontalPadding)
        .padding(.vertical, Design.verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: Design.cornerRadius)
                .fill(isDark ? Color.white.opacity(0.025) : Color.black.opacity(0.015))
                .overlay(
                    RoundedRectangle(cornerRadius: Design.cornerRadius)
                        .stroke(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.03), lineWidth: 1)
                )
        )
        // Throttled data updates to prevent glitchy redraws
        .onReceive(
            Publishers.CombineLatest(viewModel.$bids, viewModel.$asks)
                .throttle(for: .milliseconds(150), scheduler: RunLoop.main, latest: true)
        ) { _, _ in
            updateCachedDataAnimated()
        }
    }
    
    // MARK: - Data Caching
    
    private func updateCachedData() {
        // Compute bid data
        var cumulative: Double = 0
        cachedBidData = viewModel.bids.prefix(40).compactMap { entry -> DepthPoint? in
            guard let price = Double(entry.price), let qty = Double(entry.qty) else { return nil }
            cumulative += price * qty
            return DepthPoint(price: price, cumDepth: cumulative)
        }
        
        // Compute ask data
        cumulative = 0
        cachedAskData = viewModel.asks.prefix(40).compactMap { entry -> DepthPoint? in
            guard let price = Double(entry.price), let qty = Double(entry.qty) else { return nil }
            cumulative += price * qty
            return DepthPoint(price: price, cumDepth: cumulative)
        }
        
        // Update derived values
        let bestBid = viewModel.bids.first.flatMap { Double($0.price) } ?? 0
        let bestAsk = viewModel.asks.first.flatMap { Double($0.price) } ?? 0
        cachedMidPrice = (bestBid > 0 && bestAsk > 0) ? (bestBid + bestAsk) / 2 : max(bestBid, bestAsk)
        cachedSpread = max(0, bestAsk - bestBid)
        
        let maxBid = cachedBidData.last?.cumDepth ?? 0
        let maxAsk = cachedAskData.last?.cumDepth ?? 0
        cachedMaxDepth = max(maxBid, maxAsk, 1)
        
        let bidMin = cachedBidData.last?.price ?? cachedMidPrice
        let askMax = cachedAskData.last?.price ?? cachedMidPrice
        let spread = max(askMax - bidMin, 1)
        let padding = spread * 0.06
        cachedPriceRange = (bidMin - padding, askMax + padding)
        
        // Set displayed data immediately on first load
        displayedBidData = cachedBidData
        displayedAskData = cachedAskData
    }
    
    private func updateCachedDataAnimated() {
        // Store old values for interpolation
        let oldBidData = cachedBidData
        let oldAskData = cachedAskData
        
        // Update cached data
        updateCachedData()
        
        // Only animate if data actually changed significantly
        let bidChanged = oldBidData.count != cachedBidData.count || 
            (oldBidData.first?.cumDepth ?? 0) != (cachedBidData.first?.cumDepth ?? 0)
        let askChanged = oldAskData.count != cachedAskData.count ||
            (oldAskData.first?.cumDepth ?? 0) != (cachedAskData.first?.cumDepth ?? 0)
        
        if bidChanged || askChanged {
            withAnimation(.easeInOut(duration: 0.25)) {
                displayedBidData = cachedBidData
                displayedAskData = cachedAskData
            }
        }
    }
    
    // MARK: - Canvas Rendering (GPU Accelerated)
    
    private func chartCanvas(width: CGFloat, height: CGFloat) -> some View {
        Canvas { context, size in
            let priceSpan = cachedPriceRange.max - cachedPriceRange.min
            guard priceSpan > 0, cachedMaxDepth > 0 else { return }
            
            // Draw grid first (background layer)
            drawGrid(context: context, width: width, height: height)
            
            // Draw bid area
            let bidAreaPath = createStepAreaPath(
                data: displayedBidData,
                width: width,
                height: height,
                priceRange: cachedPriceRange,
                maxDepth: cachedMaxDepth,
                startFromMid: true
            )
            context.fill(bidAreaPath, with: .linearGradient(
                Gradient(stops: [
                    .init(color: DS.Colors.bid.opacity(isDark ? 0.40 : 0.28), location: 0),
                    .init(color: DS.Colors.bid.opacity(isDark ? 0.20 : 0.14), location: 0.5),
                    .init(color: DS.Colors.bid.opacity(isDark ? 0.05 : 0.03), location: 1.0)
                ]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: height)
            ))
            
            // Draw bid line with glow
            let bidLinePath = createStepLinePath(
                data: displayedBidData,
                width: width,
                height: height,
                priceRange: cachedPriceRange,
                maxDepth: cachedMaxDepth,
                startFromMid: true
            )
            // Glow layer
            context.stroke(bidLinePath, with: .color(DS.Colors.bid.opacity(0.4)), 
                          style: StrokeStyle(lineWidth: Design.depthLineWidth + 4, lineCap: .round, lineJoin: .round))
            // Main line
            context.stroke(bidLinePath, with: .color(DS.Colors.bid), 
                          style: StrokeStyle(lineWidth: Design.depthLineWidth, lineCap: .round, lineJoin: .round))
            
            // Draw ask area
            let askAreaPath = createStepAreaPath(
                data: displayedAskData,
                width: width,
                height: height,
                priceRange: cachedPriceRange,
                maxDepth: cachedMaxDepth,
                startFromMid: true
            )
            context.fill(askAreaPath, with: .linearGradient(
                Gradient(stops: [
                    .init(color: DS.Colors.ask.opacity(isDark ? 0.40 : 0.28), location: 0),
                    .init(color: DS.Colors.ask.opacity(isDark ? 0.20 : 0.14), location: 0.5),
                    .init(color: DS.Colors.ask.opacity(isDark ? 0.05 : 0.03), location: 1.0)
                ]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: height)
            ))
            
            // Draw ask line with glow
            let askLinePath = createStepLinePath(
                data: displayedAskData,
                width: width,
                height: height,
                priceRange: cachedPriceRange,
                maxDepth: cachedMaxDepth,
                startFromMid: true
            )
            // Glow layer
            context.stroke(askLinePath, with: .color(DS.Colors.ask.opacity(0.4)), 
                          style: StrokeStyle(lineWidth: Design.depthLineWidth + 4, lineCap: .round, lineJoin: .round))
            // Main line
            context.stroke(askLinePath, with: .color(DS.Colors.ask), 
                          style: StrokeStyle(lineWidth: Design.depthLineWidth, lineCap: .round, lineJoin: .round))
        }
    }
    
    private func drawGrid(context: GraphicsContext, width: CGFloat, height: CGFloat) {
        let gridColor = isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.04)
        
        // Horizontal lines (depth levels) - 3 levels for cleaner look
        for i in 1..<4 {
            let y = height * CGFloat(i) / 4
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: width, y: y))
            context.stroke(path, with: .color(gridColor), lineWidth: Design.gridLineWidth)
        }
        
        // Vertical center line (more prominent)
        let centerX = width / 2
        var centerPath = Path()
        centerPath.move(to: CGPoint(x: centerX, y: 0))
        centerPath.addLine(to: CGPoint(x: centerX, y: height))
        context.stroke(centerPath, with: .color(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)), 
                      lineWidth: Design.gridLineWidth)
    }
    
    private func createStepAreaPath(data: [DepthPoint], width: CGFloat, height: CGFloat, 
                                     priceRange: (min: Double, max: Double), maxDepth: Double, 
                                     startFromMid: Bool) -> Path {
        Path { path in
            guard !data.isEmpty else { return }
            let priceSpan = priceRange.max - priceRange.min
            guard priceSpan > 0 else { return }
            
            let midX = width / 2
            path.move(to: CGPoint(x: midX, y: height))
            
            var lastY = height
            for point in data {
                let x = CGFloat((point.price - priceRange.min) / priceSpan) * width
                let y = height - CGFloat(point.cumDepth / maxDepth) * height * Design.depthHeightRatio
                
                // Step pattern with slight rounding for smoother appearance
                path.addLine(to: CGPoint(x: x, y: lastY))
                path.addLine(to: CGPoint(x: x, y: y))
                lastY = y
            }
            
            if let last = data.last {
                let lastX = CGFloat((last.price - priceRange.min) / priceSpan) * width
                path.addLine(to: CGPoint(x: lastX, y: height))
            }
            path.closeSubpath()
        }
    }
    
    private func createStepLinePath(data: [DepthPoint], width: CGFloat, height: CGFloat,
                                     priceRange: (min: Double, max: Double), maxDepth: Double,
                                     startFromMid: Bool) -> Path {
        Path { path in
            guard !data.isEmpty else { return }
            let priceSpan = priceRange.max - priceRange.min
            guard priceSpan > 0 else { return }
            
            let midX = width / 2
            path.move(to: CGPoint(x: midX, y: height))
            
            var lastY = height
            for point in data {
                let x = CGFloat((point.price - priceRange.min) / priceSpan) * width
                let y = height - CGFloat(point.cumDepth / maxDepth) * height * Design.depthHeightRatio
                
                path.addLine(to: CGPoint(x: x, y: lastY))
                path.addLine(to: CGPoint(x: x, y: y))
                lastY = y
            }
        }
    }
    
    // MARK: - Chart Components
    
    private func chartBackground(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: Design.chartCornerRadius)
            .fill(chartBackgroundGradient)
            .overlay(
                RoundedRectangle(cornerRadius: Design.chartCornerRadius)
                    .stroke(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.03), lineWidth: 1)
            )
    }
    
    private func midPriceIndicator(width: CGFloat, height: CGFloat) -> some View {
        let midX = width / 2
        
        return ZStack {
            // Gradient vertical line
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            isDark ? Color.white.opacity(0.35) : Color.black.opacity(0.20),
                            isDark ? Color.white.opacity(0.15) : Color.black.opacity(0.08)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: Design.midPriceLineWidth, height: height)
            
            // Mid-price badge at top with premium styling
            Text(formatSmartPrice(cachedMidPrice))
                .font(.system(size: Design.midPriceLabelSize, weight: .bold, design: .monospaced))
                .foregroundColor(isDark ? .white : .black)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(isDark ? Color.black.opacity(0.9) : Color.white.opacity(0.98))
                )
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    isDark ? Color.white.opacity(0.25) : Color.black.opacity(0.08),
                                    isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.04)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
                .offset(y: -height / 2 + 16)
        }
        .position(x: midX, y: height / 2)
    }
    
    private func bestPriceMarkers(width: CGFloat, height: CGFloat) -> some View {
        let priceSpan = cachedPriceRange.max - cachedPriceRange.min
        
        return ZStack {
            // Best bid marker with pulse
            if let bestBid = displayedBidData.first, priceSpan > 0 {
                let x = CGFloat((bestBid.price - cachedPriceRange.min) / priceSpan) * width
                let y = height - CGFloat(bestBid.cumDepth / cachedMaxDepth) * height * Design.depthHeightRatio
                
                // Outer pulse ring
                Circle()
                    .fill(DS.Colors.bid.opacity(0.2 * pulseOpacity))
                    .frame(width: Design.bestPriceOuterSize * pulseScale, height: Design.bestPriceOuterSize * pulseScale)
                    .position(x: x, y: y)
                
                // Inner glow
                Circle()
                    .fill(DS.Colors.bid.opacity(0.4))
                    .frame(width: Design.bestPriceMarkerSize + 4, height: Design.bestPriceMarkerSize + 4)
                    .position(x: x, y: y)
                
                // Main marker
                Circle()
                    .fill(DS.Colors.bid)
                    .frame(width: Design.bestPriceMarkerSize, height: Design.bestPriceMarkerSize)
                    .position(x: x, y: y)
            }
            
            // Best ask marker with pulse
            if let bestAsk = displayedAskData.first, priceSpan > 0 {
                let x = CGFloat((bestAsk.price - cachedPriceRange.min) / priceSpan) * width
                let y = height - CGFloat(bestAsk.cumDepth / cachedMaxDepth) * height * Design.depthHeightRatio
                
                // Outer pulse ring
                Circle()
                    .fill(DS.Colors.ask.opacity(0.2 * pulseOpacity))
                    .frame(width: Design.bestPriceOuterSize * pulseScale, height: Design.bestPriceOuterSize * pulseScale)
                    .position(x: x, y: y)
                
                // Inner glow
                Circle()
                    .fill(DS.Colors.ask.opacity(0.4))
                    .frame(width: Design.bestPriceMarkerSize + 4, height: Design.bestPriceMarkerSize + 4)
                    .position(x: x, y: y)
                
                // Main marker
                Circle()
                    .fill(DS.Colors.ask)
                    .frame(width: Design.bestPriceMarkerSize, height: Design.bestPriceMarkerSize)
                    .position(x: x, y: y)
            }
        }
    }
    
    private func startPulseAnimation() {
        withAnimation(
            .easeInOut(duration: 1.5)
            .repeatForever(autoreverses: true)
        ) {
            pulseScale = 1.3
            pulseOpacity = 0.3
        }
    }
    
    // MARK: - Interactive Components
    
    private func handleTouch(_ location: CGPoint, width: CGFloat) {
        let dataBounds = getDataBoundsX(width: width)
        let clampedX = max(dataBounds.min, min(location.x, dataBounds.max))
        
        touchLocation = CGPoint(x: clampedX, y: location.y)
        let newData = findDataAtX(clampedX, width: width)
        
        // Haptic feedback when crossing to a new price level
        if let data = newData {
            if lastHapticPrice == nil {
                impactGenerator.prepare()
                impactGenerator.impactOccurred()
                lastHapticPrice = data.price
            } else if lastHapticPrice != data.price {
                selectionGenerator.selectionChanged()
                lastHapticPrice = data.price
            }
        }
        
        selectedData = newData
    }
    
    private var chartHeader: some View {
        HStack {
            // Bid depth total with imbalance indicator
            VStack(alignment: .leading, spacing: 3) {
                Text("Bids")
                    .font(.system(size: Design.headerLabelSize, weight: .semibold))
                    .foregroundColor(DS.Colors.bid.opacity(0.8))
                Text(formatSmartDepth(displayedBidData.last?.cumDepth ?? 0))
                    .font(.system(size: Design.headerValueSize, weight: .bold, design: .monospaced))
                    .foregroundColor(DS.Colors.bid)
            }
            
            Spacer()
            
            // Spread indicator with imbalance percentage
            VStack(spacing: 3) {
                Text("Spread")
                    .font(.system(size: Design.headerLabelSize, weight: .semibold))
                    .foregroundColor(.gray)
                Text(formatSmartSpread(cachedSpread))
                    .font(.system(size: Design.headerValueSize, weight: .bold, design: .monospaced))
                    .foregroundColor(isDark ? .white.opacity(0.9) : .black.opacity(0.8))
            }
            
            Spacer()
            
            // Ask depth total
            VStack(alignment: .trailing, spacing: 3) {
                Text("Asks")
                    .font(.system(size: Design.headerLabelSize, weight: .semibold))
                    .foregroundColor(DS.Colors.ask.opacity(0.8))
                Text(formatSmartDepth(displayedAskData.last?.cumDepth ?? 0))
                    .font(.system(size: Design.headerValueSize, weight: .bold, design: .monospaced))
                    .foregroundColor(DS.Colors.ask)
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, Design.headerBottomPadding)
    }
    
    private func interactiveHeader(data: (price: Double, depth: Double, isBid: Bool, x: CGFloat)) -> some View {
        let sideColor = data.isBid ? DS.Colors.bid : DS.Colors.ask
        
        return HStack {
            // Price
            VStack(alignment: .leading, spacing: 2) {
                Text("Price")
                    .font(.system(size: Design.headerLabelSize, weight: .medium))
                    .foregroundColor(.gray)
                Text(formatDetailPrice(data.price))
                    .font(.system(size: Design.headerValueSize, weight: .bold, design: .monospaced))
                    .foregroundColor(sideColor)
            }
            
            Spacer()
            
            // Cumulative depth
            VStack(spacing: 2) {
                Text("Total Depth")
                    .font(.system(size: Design.headerLabelSize, weight: .medium))
                    .foregroundColor(.gray)
                Text(formatSmartDepth(data.depth))
                    .font(.system(size: Design.headerValueSize, weight: .bold, design: .monospaced))
                    .foregroundColor(sideColor)
            }
            
            Spacer()
            
            // Side indicator with icon
            VStack(alignment: .trailing, spacing: 2) {
                Text("Side")
                    .font(.system(size: Design.headerLabelSize, weight: .medium))
                    .foregroundColor(.gray)
                HStack(spacing: 4) {
                    Image(systemName: data.isBid ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .font(.system(size: 11))
                    Text(data.isBid ? "BID" : "ASK")
                        .font(.system(size: Design.headerValueSize, weight: .bold))
                }
                .foregroundColor(sideColor)
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, Design.headerBottomPadding)
        .animation(.easeInOut(duration: 0.1), value: data.price)
    }
    
    private func crosshairOverlay(touch: CGPoint, width: CGFloat, height: CGFloat) -> some View {
        let data = selectedData
        let color = data?.isBid == true ? DS.Colors.bid : (data?.isBid == false ? DS.Colors.ask : Color.white)
        let snapX = data?.x ?? touch.x
        
        return ZStack {
            // Vertical crosshair line with gradient
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.8), color.opacity(0.4)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 2, height: height)
                .position(x: snapX, y: height / 2)
            
            // Highlight dot on the curve
            if let data = data {
                let y = height - CGFloat(data.depth / cachedMaxDepth) * height * Design.depthHeightRatio
                
                // Outer glow ring
                Circle()
                    .fill(color.opacity(0.25))
                    .frame(width: Design.crosshairOuterSize, height: Design.crosshairOuterSize)
                    .position(x: snapX, y: y)
                
                // Inner solid dot
                Circle()
                    .fill(color)
                    .frame(width: Design.crosshairDotSize, height: Design.crosshairDotSize)
                    .position(x: snapX, y: y)
                
                // Price label below the dot
                Text(formatSmartPrice(data.price))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(color)
                    )
                    .position(x: snapX, y: min(y + 20, height - 14))
            }
        }
    }
    
    private func priceAxis(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            // Lowest bid price
            if let lowestBid = displayedBidData.last {
                Text(formatSmartPrice(lowestBid.price))
                    .font(.system(size: Design.axisLabelSize, weight: .medium, design: .monospaced))
                    .foregroundColor(DS.Colors.bid.opacity(0.7))
            }
            
            Spacer()
            
            // Best bid price
            if let bestBid = displayedBidData.first {
                Text(formatSmartPrice(bestBid.price))
                    .font(.system(size: Design.axisLabelSize, weight: .semibold, design: .monospaced))
                    .foregroundColor(DS.Colors.bid)
            }
            
            Spacer()
            
            // MID label
            Text("MID")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.gray.opacity(0.8))
            
            Spacer()
            
            // Best ask price
            if let bestAsk = displayedAskData.first {
                Text(formatSmartPrice(bestAsk.price))
                    .font(.system(size: Design.axisLabelSize, weight: .semibold, design: .monospaced))
                    .foregroundColor(DS.Colors.ask)
            }
            
            Spacer()
            
            // Highest ask price
            if let highestAsk = displayedAskData.last {
                Text(formatSmartPrice(highestAsk.price))
                    .font(.system(size: Design.axisLabelSize, weight: .medium, design: .monospaced))
                    .foregroundColor(DS.Colors.ask.opacity(0.7))
            }
        }
        .frame(height: 14)
    }
    
    // MARK: - Data Lookup Helpers
    
    private func getDataBoundsX(width: CGFloat) -> (min: CGFloat, max: CGFloat) {
        let priceSpan = cachedPriceRange.max - cachedPriceRange.min
        guard priceSpan > 0 else { return (0, width) }
        
        let leftPrice = displayedBidData.last?.price ?? cachedMidPrice
        let leftX = CGFloat((leftPrice - cachedPriceRange.min) / priceSpan) * width
        
        let rightPrice = displayedAskData.last?.price ?? cachedMidPrice
        let rightX = CGFloat((rightPrice - cachedPriceRange.min) / priceSpan) * width
        
        return (max(0, leftX), min(width, rightX))
    }
    
    private func findDataAtX(_ x: CGFloat, width: CGFloat) -> (price: Double, depth: Double, isBid: Bool, x: CGFloat)? {
        let priceSpan = cachedPriceRange.max - cachedPriceRange.min
        guard priceSpan > 0 else { return nil }
        
        let touchPrice = cachedPriceRange.min + Double(x / width) * priceSpan
        let isBid = touchPrice < cachedMidPrice
        
        if isBid {
            var bestMatch: DepthPoint? = nil
            for bid in displayedBidData {
                if bid.price <= touchPrice {
                    bestMatch = bid
                    break
                }
                bestMatch = bid
            }
            if bestMatch == nil, let lowest = displayedBidData.last {
                bestMatch = lowest
            }
            if let match = bestMatch {
                let snapX = CGFloat((match.price - cachedPriceRange.min) / priceSpan) * width
                return (match.price, match.cumDepth, true, snapX)
            }
        } else {
            var bestMatch: DepthPoint? = nil
            for ask in displayedAskData {
                if ask.price >= touchPrice {
                    bestMatch = ask
                    break
                }
                bestMatch = ask
            }
            if bestMatch == nil, let highest = displayedAskData.last {
                bestMatch = highest
            }
            if let match = bestMatch {
                let snapX = CGFloat((match.price - cachedPriceRange.min) / priceSpan) * width
                return (match.price, match.cumDepth, false, snapX)
            }
        }
        
        return nil
    }
    
    // MARK: - Smart Formatting Helpers
    
    /// Smart price formatting - shows appropriate precision with K suffix for large values
    private func formatSmartPrice(_ price: Double) -> String {
        if price >= 100000 {
            return String(format: "$%.0fK", price / 1000)
        } else if price >= 10000 {
            return String(format: "$%.1fK", price / 1000)
        } else if price >= 1000 {
            return String(format: "$%.2fK", price / 1000)
        } else if price >= 100 {
            return String(format: "$%.0f", price)
        } else if price >= 1 {
            return String(format: "$%.2f", price)
        } else if price >= 0.01 {
            return String(format: "$%.4f", price)
        } else {
            return String(format: "$%.6f", price)
        }
    }
    
    /// Detailed price for interactive header
    private func formatDetailPrice(_ price: Double) -> String {
        if price >= 1000 {
            return String(format: "$%,.2f", price)
        } else if price >= 1 {
            return String(format: "$%.4f", price)
        } else {
            return String(format: "$%.6f", price)
        }
    }
    
    /// Smart depth formatting with M/K suffixes
    private func formatSmartDepth(_ depth: Double) -> String {
        if depth >= 1_000_000 {
            return String(format: "$%.2fM", depth / 1_000_000)
        } else if depth >= 100_000 {
            return String(format: "$%.0fK", depth / 1000)
        } else if depth >= 10_000 {
            return String(format: "$%.1fK", depth / 1000)
        } else if depth >= 1000 {
            return String(format: "$%.2fK", depth / 1000)
        } else {
            return String(format: "$%.0f", depth)
        }
    }
    
    /// Smart spread formatting with cents for small values
    private func formatSmartSpread(_ spread: Double) -> String {
        if spread < 0.01 {
            return "<1¢"
        } else if spread < 1 {
            return String(format: "%.1f¢", spread * 100)
        } else if spread < 10 {
            return String(format: "$%.2f", spread)
        } else if spread < 100 {
            return String(format: "$%.1f", spread)
        } else {
            return String(format: "$%.0f", spread)
        }
    }
}

// MARK: - Preview
#if DEBUG
struct OrderBookDepthChartView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            OrderBookDepthChartView(
                viewModel: OrderBookViewModel.shared,
                height: 200
            )
        }
        .padding()
        .background(Color.black)
        .previewLayout(.sizeThatFits)
    }
}
#endif
