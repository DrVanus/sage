import SwiftUI
import Charts
import UIKit

#if DEBUG
import Combine

/// A dummy PriceService for SwiftUI previews
private struct PreviewPriceService: PriceService {
    func pricePublisher(for symbols: [String], interval: TimeInterval) -> AnyPublisher<[String: Double], Never> {
        Just([:]).eraseToAnyPublisher()
    }
}
#endif

// File-scope helpers for premium chart transition
// Simplified to just opacity for smooth, lag-free transitions
private struct PremiumChartModifier: ViewModifier {
    let opacity: Double
    @ViewBuilder
    func body(content: Content) -> some View {
        content
            .opacity(opacity)
    }
}

private extension AnyTransition {
    static var premiumChart: AnyTransition {
        // Simple opacity fade - no blur/scale/offset which cause lag
        let active = PremiumChartModifier(opacity: 0.0)
        let identity = PremiumChartModifier(opacity: 1.0)
        return .modifier(active: active, identity: identity)
    }
}

/// A donut (pie) chart view that displays each coin's share of the portfolio
/// based on its current value (quantity * currentPrice).
struct ThemedPortfolioPieChartView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var portfolioVM: PortfolioViewModel
    @Binding var showLegend: Bool
    @State private var selectedSlice: PortfolioViewModel.AllocationSlice? = nil
    @State private var selectedSymbol: String? = nil

    @State private var hoverSymbol: String? = nil
    @State private var lastHoverSymbol: String? = nil
    @State private var selectionProgress: CGFloat = 0
    @State private var appearProgress: CGFloat = 0
    @State private var ripplePhase: CGFloat = 1
    @State private var lastHoverTick: CFTimeInterval = 0
    @State private var sweepStartTime: TimeInterval = 0
    // iOS 17+ uses chartAngleSelection for reliable hit detection
    @State private var selectedAngle: Double?
    
    @State private var chartRotation: Angle = .degrees(0)
    @State private var currentRotationBase: Double = 0 // radians, keeps rotation continuity
    @State private var dragLastAngle: Double? = nil
    @State private var dragVelocity: Double = 0 // radians per frame
    @State private var decelTimer: Timer? = nil
    @State private var sweepTimer: Timer? = nil

    var allowRotation: Bool = false
    var allowSweepOscillation: Bool = false
    var showSweepIndicator: Bool = false
    var allowHoverScrub: Bool = false

    var showSliceCallouts: Bool = false
    var showRotatingSheen: Bool = false
    var showIdleCenterRing: Bool = false
    var showActiveStartTick: Bool = false
    var showSliceSeparators: Bool = false  // Disabled by default - separators can cause visual artifacts
    var showSideInfoPanel: Bool = true  // When true, shows coin list panel beside chart if space permits
    
    // Optional override for allocation data (used for Paper Trading mode)
    // When provided, uses this data instead of portfolioVM.allocationData
    var overrideAllocationData: [PortfolioViewModel.AllocationSlice]? = nil
    
    // Optional override for total value (used for Paper Trading mode)
    // When provided, uses this value instead of portfolioVM.totalValue for center display
    var overrideTotalValue: Double? = nil

    // How the center of the donut should render
    enum CenterContentMode { case normal, hidden }
    var centerMode: CenterContentMode = .normal

    // Smooth inner accent ring animation state
    @State private var accentFrom: CGFloat = 0
    @State private var accentTo: CGFloat = 0
    @State private var accentRingColor: Color = Color.white.opacity(0.28) // Reset by updateAccentArc
    
    // Sweep indicator angle (radians) for animated transitions along the ring
    @State private var indicatorAngle: Double = 0
    // Indicator animation states
    @State private var indicatorPulse: CGFloat = 1.0      // Idle pulse scale (1.0 to 1.08)
    @State private var indicatorLandingScale: CGFloat = 1.0  // Landing bounce (1.0 -> 1.15 -> 1.0)
    @State private var isIndicatorSweeping: Bool = false  // True during sweep animation
    
    // Center label animation
    @State private var centerLabelScale: CGFloat = 1.0  // Pulse on selection change

    // Optional callbacks for host screens to react to selection/activation
    var onSelectSymbol: ((String?) -> Void)? = nil
    var onActivateSymbol: ((String) -> Void)? = nil

    // Optional callback to share symbol -> color mapping with parent/holdings UI
    var onUpdateColors: (([String: Color]) -> Void)? = nil

    private struct DisplaySlice: Identifiable {
        let id: String
        let symbol: String
        let percent: Double
        let color: Color
    }

    private struct RenderSliceData: Identifiable {
        let id: String
        let symbol: String
        let percent: Double
        let start: Double
        let color: Color
        let isActive: Bool
        let anyActive: Bool
        let activeProgress: CGFloat
        let outer: CGFloat
        let innerAdj: CGFloat
        let inner: CGFloat
        let percentInt: Int
        let sliceVal: Double
        let valueText: String
        let midAngle: Double
        var dx: CGFloat
        var dy: CGFloat
        let popX: CGFloat
        let popY: CGFloat
        let order: Int
        let gradient: LinearGradient
        // For graduated dimming based on distance from active slice
        let distanceFromActive: Int  // 0 = active, 1 = adjacent, 2+ = farther
        let sliceScale: CGFloat      // Scale factor for active slice pop effect
        let sliceOpacity: Double     // Precomputed opacity for graduated dimming
        let shadowOpacity: Double    // Precomputed shadow opacity
        let shadowRadius: CGFloat    // Precomputed shadow radius
    }

    private func rotatedPoint(_ p: CGPoint, in rect: CGRect, inverseRotation: Angle) -> CGPoint {
        // Changed to use local coordinates for center to fix rotation alignment
        let c = CGPoint(x: rect.size.width / 2.0, y: rect.size.height / 2.0)
        let dx = p.x - c.x
        let dy = p.y - c.y
        let a = inverseRotation.radians
        let rx = dx * CGFloat(cos(a)) + dy * CGFloat(sin(a))
        let ry = -dx * CGFloat(sin(a)) + dy * CGFloat(cos(a))
        return CGPoint(x: c.x + rx, y: c.y + ry)
    }

    private func angleAtPoint(_ p: CGPoint, in rect: CGRect) -> Double {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let dx = Double(p.x - c.x)
        let dy = Double(p.y - c.y)
        return atan2(dy, dx) // -pi..pi, 0 is right
    }

    private func midAngleFor(symbol: String, slices: [DisplaySlice]) -> Double? {
        var run: Double = 0
        for s in slices {
            let start = run
            let end = run + s.percent
            run = end
            if s.symbol == symbol {
                let midPercent = (start + end) / 2.0
                // Negate for CCW direction to match Swift Charts rendering
                return (midPercent / 100.0) * 2 * Double.pi - Double.pi / 2  // CW from 12 o'clock
            }
        }
        return nil
    }

    private func rotateChart(toMidAngle angle: Double, animated: Bool = true) {
        if !allowRotation { return }
        let desired = Double.pi / 2 // top (12 o'clock position)
        
        // Calculate the target absolute rotation (not accumulating)
        var targetRotation = desired - angle
        
        // Normalize to [-π, π] range
        while targetRotation > Double.pi { targetRotation -= 2 * Double.pi }
        while targetRotation < -Double.pi { targetRotation += 2 * Double.pi }
        
        // Calculate shortest path from current position
        let currentNormalized = currentRotationBase.truncatingRemainder(dividingBy: 2 * Double.pi)
        var delta = targetRotation - currentNormalized
        
        // Take shortest path
        if delta > Double.pi { delta -= 2 * Double.pi }
        if delta < -Double.pi { delta += 2 * Double.pi }
        
        // Update rotation (use absolute positioning to prevent unbounded growth)
        currentRotationBase = targetRotation
        let newAngle = Angle(radians: currentRotationBase)
        
        if animated {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                chartRotation = newAngle
            }
        } else {
            chartRotation = newAngle
        }
    }

    private func startDeceleration() {
        if !allowRotation { return }
        stopDeceleration()
        // PERFORMANCE FIX: Reduce from 60Hz to 30Hz - pie chart deceleration doesn't need 60fps
        // simple exponential decay on 30Hz
        let decay: Double = 0.85  // Adjusted decay for 30Hz (was 0.92 at 60Hz)
        // NOTE: SwiftUI View structs use [self] - timer invalidated in stopDeceleration
        decelTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [self] t in
            // Use DispatchQueue.main.async to safely update @State from timer callback
            DispatchQueue.main.async {
                let newVelocity = dragVelocity * decay
                if abs(newVelocity) < 0.001 {
                    t.invalidate()
                    decelTimer = nil
                    // Normalize rotation when stopping
                    var normalizedBase = currentRotationBase
                    while normalizedBase > Double.pi { normalizedBase -= 2 * Double.pi }
                    while normalizedBase < -Double.pi { normalizedBase += 2 * Double.pi }
                    currentRotationBase = normalizedBase
                    return
                }
                dragVelocity = newVelocity
                var newBase = currentRotationBase + newVelocity
                // Normalize to prevent unbounded growth during drag
                while newBase > Double.pi * 2 { newBase -= 2 * Double.pi }
                while newBase < -Double.pi * 2 { newBase += 2 * Double.pi }
                currentRotationBase = newBase
                chartRotation = Angle(radians: newBase)
            }
        }
    }
    
    private func stopDeceleration() {
        decelTimer?.invalidate()
        decelTimer = nil
    }

    private func startSweepOscillation() {
        // Simplified - no longer using sweep animations
    }

    private func stopSweepOscillation() {
        sweepTimer?.invalidate()
        sweepTimer = nil
    }

    @ViewBuilder
    private func sliceAnnotation(item: RenderSliceData, isMini: Bool, diameter: CGFloat) -> some View {
        calloutAnnotation(
            symbol: item.symbol,
            percentInt: item.percentInt,
            valueText: item.valueText,
            color: item.color,
            isMini: isMini,
            midAngle: item.midAngle,
            outer: item.outer,
            inner: item.inner,
            diameter: diameter,
            dx: item.dx,
            dy: item.dy
        )
        .opacity(Double(item.activeProgress))
        .scaleEffect(0.9 + 0.1 * item.activeProgress)
    }

    private func buildRenderSlices(
        slicesWithStart: [(slice: DisplaySlice, start: Double)],
        diameter: CGFloat,
        isMini: Bool,
        inner: CGFloat,
        outerSelected: CGFloat,
        outerNormal: CGFloat,
        activeSymbol: String?
    ) -> [RenderSliceData] {
        _ = (activeSymbol != nil)
        let sliceCount = slicesWithStart.count
        
        // Find the index of the active slice for distance calculation
        let activeIndex: Int? = activeSymbol != nil ? slicesWithStart.firstIndex(where: { $0.slice.symbol == activeSymbol }) : nil

        // First pass: compute preliminary geometry
        var prelim: [RenderSliceData] = slicesWithStart.enumerated().map { idx, item in
            let slice = item.slice
            let start = item.start
            let isActive = (activeSymbol == slice.symbol)
            let anyActive = (activeSymbol != nil)
            let activeProgress: CGFloat = isActive ? selectionProgress : 0 as CGFloat
            
            // Calculate distance from active slice (wrapping around for circular adjacency)
            let distanceFromActive: Int
            if let activeIdx = activeIndex {
                let directDist = abs(idx - activeIdx)
                let wrapDist = sliceCount - directDist
                distanceFromActive = min(directDist, wrapDist)
            } else {
                distanceFromActive = 0
            }
            
            // Scale for active slice (subtle 1.02x pop) - non-active slices stay at 1.0
            let sliceScale: CGFloat = isActive ? (1.0 + 0.02 * selectionProgress) : 1.0
            
            // Precompute opacity for graduated dimming (reduces type-checker burden in Chart)
            let sliceOpacity: Double
            if isActive {
                sliceOpacity = 1.0
            } else if anyActive {
                // Subtle dimming - keep non-selected slices more visible
                switch distanceFromActive {
                case 1: sliceOpacity = 0.88   // Adjacent slices - very subtle dim
                case 2: sliceOpacity = 0.85   // One step farther
                default: sliceOpacity = 0.82  // Distant slices - still visible
                }
            } else {
                sliceOpacity = 1.0
            }
            
            // Precompute shadow values
            let shadowOpacity: Double = isActive ? 0.5 : 0.02
            let shadowRadius: CGFloat = isActive ? max(6, diameter * 0.032) : 0
            
            // Active slice grows slightly, non-active slices shrink slightly for depth effect
            let scaleAdjust: CGFloat = isActive ? 0.0 : (anyActive ? -0.012 * selectionProgress : 0.0)
            let outer: CGFloat = outerNormal + min(0.045, (outerSelected - outerNormal)) * activeProgress + scaleAdjust
            let innerAdj: CGFloat = max(0.0, inner - 0.015 * activeProgress)

            let percentInt: Int = Int(slice.percent.rounded())
            let sliceVal: Double = portfolioVM.totalValue * (slice.percent / 100)
            let valueText: String = abbreviatedCurrency(sliceVal)

            // Prefer placing callouts outside the ring and guarantee a minimum distance from the hole
            let desiredCalloutR: Double = (Double(outer) + 0.06) * Double(diameter) / 2.0
            let minCalloutR: Double = (Double(inner) * Double(diameter) / 2.0) + Double(diameter) * 0.12
            let baseCalloutRadius: Double = max(desiredCalloutR, minCalloutR)

            // Angle from the chart's 0° (pointing right). Top is ~pi/2
            let midAngle: Double = (start + slice.percent / 2.0) * Double.pi / 50.0

            // Extra outward boost near the top to avoid center overlap
            let topDistance = abs(midAngle - (Double.pi / 2.0))
            let topBias = max(0.0, 1.0 - (topDistance / (Double.pi / 3.0))) // within ±60° of top -> 0..1
            let boostedRadius = baseCalloutRadius + Double(diameter) * 0.06 * Double(topBias)

            // Initial radial position
            var dx: CGFloat = CGFloat(cos(midAngle) * boostedRadius)
            var dy: CGFloat = CGFloat(sin(midAngle) * boostedRadius)

            // Tangential nudge so the callout sits to the side of the slice
            let tangentX = CGFloat(-sin(midAngle))
            let tangentY = CGFloat(cos(midAngle))
            let tangentialShift: CGFloat = diameter * 0.03
            let sideSign: CGFloat = (cos(midAngle) >= 0) ? 1 : -1
            dx += tangentX * tangentialShift * sideSign
            dy += tangentY * tangentialShift * sideSign

            // Pull slightly inward near left/right edges so callouts don't hit the card boundary
            let sideDistance0 = abs(midAngle - 0)
            let sideDistancePi = abs(midAngle - Double.pi)
            let minSideDist = min(sideDistance0, sideDistancePi)
            let sideBias = max(0.0, 1.0 - (minSideDist / (Double.pi / 6.0))) // within ±30° of left/right -> 0..1
            let edgePullIn = 1.0 - (0.06 * Double(sideBias))
            dx *= CGFloat(edgePullIn)
            dy *= CGFloat(edgePullIn)

            // Refined pop distance (2.5% vs 3.5%) for cleaner separation
            let popDistance: CGFloat = diameter * 0.025 * activeProgress
            let popX: CGFloat = CGFloat(cos(midAngle)) * popDistance
            let popY: CGFloat = CGFloat(sin(midAngle)) * popDistance
            
            let sliceGradient = gradient(for: slice.color)

            return RenderSliceData(
                id: slice.symbol,
                symbol: slice.symbol,
                percent: slice.percent,
                start: start,
                color: slice.color,
                isActive: isActive,
                anyActive: anyActive,
                activeProgress: activeProgress,
                outer: outer,
                innerAdj: innerAdj,
                inner: inner,
                percentInt: Int(percentInt),
                sliceVal: sliceVal,
                valueText: valueText,
                midAngle: midAngle,
                dx: dx,
                dy: dy,
                popX: popX,
                popY: popY,
                order: idx,
                gradient: sliceGradient,
                distanceFromActive: distanceFromActive,
                sliceScale: sliceScale,
                sliceOpacity: sliceOpacity,
                shadowOpacity: shadowOpacity,
                shadowRadius: shadowRadius
            )
        }

        // Second pass: collision avoidance between neighboring callouts on the same side.
        // Iterate a few times to reduce overlaps when 3+ slices are adjacent.
        let sep: CGFloat = diameter * 0.09 // desired vertical separation between callouts
        for _ in 0..<5 { // up to five relaxation passes
            var changed = false
            let sortedIdx = Array(prelim.indices).sorted { prelim[$0].midAngle < prelim[$1].midAngle }
            for i in 1..<sortedIdx.count {
                let prev = prelim[sortedIdx[i - 1]]
                var cur  = prelim[sortedIdx[i]]
                // Same side (both left or both right) and close in angle
                let sameSide = (cos(prev.midAngle) >= 0) == (cos(cur.midAngle) >= 0)
                let angleClose = abs(cur.midAngle - prev.midAngle) < (Double.pi / 4.0)
                if sameSide && angleClose {
                    let dyDelta = cur.dy - prev.dy
                    if abs(dyDelta) < sep {
                        // Push the current one away vertically and slightly outwards
                        let push = (dyDelta >= 0 ? 1 : -1) * (sep - abs(dyDelta))
                        cur.dy += push
                        let r = max(1, sqrt(cur.dx*cur.dx + cur.dy*cur.dy)) * 1.02
                        let angle = cur.midAngle
                        cur.dx = cos(angle) * r
                        cur.dy = sin(angle) * r + (push * 0.12)
                        prelim[sortedIdx[i]] = cur
                        changed = true
                    }
                }
            }
            if !changed { break }
        }
        return prelim
    }

    private static let wholeFormatter: NumberFormatter = {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.minimumFractionDigits = 0
        nf.maximumFractionDigits = 0
        return nf
    }()

    private static let oneDecimalFormatter: NumberFormatter = {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.minimumFractionDigits = 1
        nf.maximumFractionDigits = 1
        return nf
    }()

    // MARK: - Visual helpers
    private func blend(_ color: UIColor, with overlay: UIColor, amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        color.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        overlay.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = max(0, min(1, amount))
        return UIColor(red: r1 + (r2 - r1) * t,
                       green: g1 + (g2 - g1) * t,
                       blue: b1 + (b2 - b1) * t,
                       alpha: a1)
    }

    private func gradient(for color: Color) -> LinearGradient {
        let ui = UIColor(color)
        // Premium 5-stop metallic gradient with enhanced specular highlights
        let highlight = blend(ui, with: .white, amount: 0.45)  // Bright specular highlight
        let light = blend(ui, with: .white, amount: 0.22)      // Soft light transition
        let base = ui                                           // True color
        let dark = blend(ui, with: .black, amount: 0.18)       // Rich shadow
        let shadow = blend(ui, with: .black, amount: 0.28)     // Deep shadow edge
        
        return LinearGradient(
            colors: [
                Color(uiColor: highlight),
                Color(uiColor: light),
                Color(uiColor: base),
                Color(uiColor: dark),
                Color(uiColor: shadow)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private func donutLighting(diameter: CGFloat, inner: CGFloat, outer: CGFloat, tint: Color) -> some View {
        // Simplified lighting - subtle center highlight only
        let outerSize = diameter * outer
        let thickness = max(1, diameter * (outer - inner))
        RadialGradient(
            colors: [tint.opacity(0.08), Color.clear],
            center: .center,
            startRadius: 0,
            endRadius: outerSize / 1.5
        )
        .frame(width: outerSize, height: outerSize)
        .mask(
            Circle().stroke(lineWidth: thickness)
        )
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func donutDepth(diameter: CGFloat, inner: CGFloat, outer: CGFloat) -> some View {
        // Simplified depth effect - just a subtle inner shadow
        // Uses adaptive warm shadow for light mode
        let innerSize = diameter * inner
        Circle()
            .stroke(innerDepthShadow, lineWidth: 1.5)
            .frame(width: innerSize, height: innerSize)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func outerAuraGlow(diameter: CGFloat, outer: CGFloat, tint: Color) -> some View {
        // Minimal outer glow - very subtle for cleaner look
        // Adaptive: use different blend mode and opacity for light mode
        let size = diameter * outer
        let isDark = colorScheme == .dark
        
        RadialGradient(
            colors: [tint.opacity(isDark ? 0.06 : 0.04), Color.clear],
            center: .center,
            startRadius: size * 0.3,
            endRadius: size * 0.65
        )
        .frame(width: size * 1.05, height: size * 1.05)
        .allowsHitTesting(false)
        .opacity(isDark ? 0.4 : 0.25)
    }

    @ViewBuilder
    private func innerHoleGlow(diameter: CGFloat, inner: CGFloat) -> some View {
        // Simplified inner ring - single subtle shadow for depth, no extra rings
        let hole = diameter * inner
        let hasActive = (selectedSymbol ?? hoverSymbol) != nil
        
        // Adaptive inner shadow color - warm brown for light mode, black for dark mode
        let isDark = colorScheme == .dark
        let innerShadowColor = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor.black.withAlphaComponent(hasActive ? 0.18 : 0.12)
                : UIColor(red: 0.55, green: 0.45, blue: 0.33, alpha: hasActive ? 0.06 : 0.03)
        })
        
        ZStack {
            // Single subtle inner shadow for depth - clean and minimal
            Circle()
                .stroke(innerShadowColor, lineWidth: isDark ? 1.5 : 0.8)
                .frame(width: hole * 0.96, height: hole * 0.96)
            
            // Soft color glow only when actively selecting (very subtle)
            if hasActive {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.clear,
                                accentRingColor.opacity(0.06),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: hole * 0.3,
                            endRadius: hole * 0.48
                        )
                    )
                    .frame(width: hole * 0.94, height: hole * 0.94)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: hasActive)
        .allowsHitTesting(false)
    }
    
    @ViewBuilder
    private func colorReactiveAmbientGlow(diameter: CGFloat, outer: CGFloat, slices: [DisplaySlice]) -> some View {
        // Simplified ambient glow - subtle and clean
        // Adaptive: use different blend mode and opacity for light mode
        let size = diameter * outer
        let hasActive = (selectedSymbol ?? hoverSymbol) != nil
        let isDark = colorScheme == .dark
        
        // Determine glow color: active slice color when selected, dominant slice color otherwise
        let glowColor: Color = {
            if let sym = selectedSymbol ?? hoverSymbol,
               let match = slices.first(where: { $0.symbol == sym }) {
                return match.color
            }
            // Use dominant (largest) slice color when idle
            return slices.first?.color ?? Color.white
        }()
        
        // Single subtle ambient glow - cleaner than multiple layers
        RadialGradient(
            colors: [
                glowColor.opacity(hasActive ? (isDark ? 0.12 : 0.08) : (isDark ? 0.04 : 0.02)),
                glowColor.opacity(hasActive ? (isDark ? 0.04 : 0.02) : (isDark ? 0.01 : 0.005)),
                Color.clear
            ],
            center: .center,
            startRadius: size * 0.35,
            endRadius: size * 0.7
        )
        .frame(width: size * 1.1, height: size * 1.1)
        .animation(.easeInOut(duration: 0.4), value: hasActive)
        .animation(.easeInOut(duration: 0.5), value: selectedSymbol)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func activeStartHighlight(diameter: CGFloat, inner: CGFloat, outer: CGFloat) -> some View {
        ZStack {
            if (selectedSymbol ?? hoverSymbol) != nil {
                let start = Double(min(accentFrom, accentTo))
                let twoPi = Double.pi * 2
                let centerRatio = (inner + outer) / 2.0
                let tickLenRatio: CGFloat = max(0.008, (outer - inner) * 0.22)
                let lineWRatio: CGFloat = max(0.006, (outer - inner) * 0.22)
                // Convert to angles matching 12 o'clock clockwise direction
                // The tick marks the start of the slice
                let tickStartAngle = start * twoPi - Double.pi / 2   // At slice start position
                let tickEndAngle = (start + 0.01) * twoPi - Double.pi / 2  // Slightly past start
                ArcStroke(start: tickStartAngle, end: tickEndAngle, radiusRatio: centerRatio, lineWidthRatio: tickLenRatio)
                    .stroke(
                        LinearGradient(colors: [accentRingColor.opacity(0.85), accentRingColor.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: max(1, diameter * lineWRatio), lineCap: .round)
                    )
                    .opacity(0.75)
                    .allowsHitTesting(false)
            }
        }
    }

    private struct SpecularSheen: View {
        let diameter: CGFloat
        let inner: CGFloat
        let outer: CGFloat
        @State private var angle: Double = 0
        var body: some View {
            let ringWidth = max(1, diameter * (outer - inner) * 0.55)
            let frame = diameter * ((inner + outer) / 2.0)
            let band = AngularGradient(gradient: Gradient(stops: [
                .init(color: Color.clear, location: 0.46),
                .init(color: Color.white.opacity(0.35), location: 0.50),
                .init(color: Color.white.opacity(0.10), location: 0.53),
                .init(color: Color.clear, location: 0.56)
            ]), center: .center)
            Circle()
                .stroke(band, lineWidth: ringWidth)
                .frame(width: frame, height: frame)
                .rotationEffect(.degrees(angle))
                .onAppear {
                    // Defer to avoid "Modifying state during view update"
                    DispatchQueue.main.async {
                        // MEMORY FIX v19: Disable repeating rotation animation.
                        // Keep a static ring to avoid persistent allocation churn.
                        let _ = globalAnimationsKilled
                        angle = 0
                    }
                }
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func donutTrack(diameter: CGFloat, inner: CGFloat, outer: CGFloat, tint: Color) -> some View {
        // A very subtle track ring to increase contrast behind slices
        // Adaptive: use warm brown shadow in light mode for softer appearance
        let outerSize = diameter * outer
        let thickness = max(1, diameter * (outer - inner))
        let isDark = colorScheme == .dark
        
        Circle()
            .stroke(
                LinearGradient(colors: [
                    tint.opacity(isDark ? 0.06 : 0.03),
                    isDark 
                        ? Color.black.opacity(0.18)
                        : Color(red: 0.55, green: 0.45, blue: 0.33).opacity(0.05)
                ],
                               startPoint: .top,
                               endPoint: .bottom),
                lineWidth: thickness
            )
            .frame(width: outerSize, height: outerSize)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func ambientShadow(diameter: CGFloat, outer: CGFloat) -> some View {
        // Soft platform-like shadow to ground the chart
        // Light mode: nearly invisible to avoid dark halos on white backgrounds
        let w = diameter * outer
        let isDark = colorScheme == .dark
        
        if isDark {
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.35), Color.black.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: w * 0.9, height: diameter * 0.22)
                .offset(y: diameter * 0.26)
                .allowsHitTesting(false)
                .opacity(0.35)
        }
        // In light mode, skip the ambient shadow entirely — it creates visible dark blobs
    }

    @ViewBuilder
    private func sliceSeparators(
        slicesWithStart: [(slice: DisplaySlice, start: Double)],
        diameter: CGFloat,
        inner: CGFloat,
        outer: CGFloat
    ) -> some View {
        let innerR = inner * diameter / 2.0
        let outerR = outer * diameter / 2.0
        let separatorOffset: CGFloat = 0.003  // Small angular offset for 3D effect
        
        ZStack {
            ForEach(Array(slicesWithStart.enumerated()), id: \.offset) { _, item in
                if item.slice.percent >= 3 {
                    // Base angle for this separator (CW from 12 o'clock)
                    let angle = item.start * Double.pi / 50.0 - Double.pi / 2
                    let ux = CGFloat(cos(angle))
                    let uy = CGFloat(sin(angle))
                    
                    // Highlight line (leading edge - catches light)
                    let highlightAngle = angle - separatorOffset
                    let hux = CGFloat(cos(highlightAngle))
                    let huy = CGFloat(sin(highlightAngle))
                    Path { p in
                        p.move(to: CGPoint(x: hux * innerR, y: huy * innerR))
                        p.addLine(to: CGPoint(x: hux * outerR, y: huy * outerR))
                    }
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.18),
                                Color.white.opacity(0.12),
                                Color.white.opacity(0.06)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
                    
                    // Shadow line (trailing edge - in shadow)
                    let shadowAngle = angle + separatorOffset
                    let sux = CGFloat(cos(shadowAngle))
                    let suy = CGFloat(sin(shadowAngle))
                    Path { p in
                        p.move(to: CGPoint(x: sux * innerR, y: suy * innerR))
                        p.addLine(to: CGPoint(x: sux * outerR, y: suy * outerR))
                    }
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.28),
                                Color.black.opacity(0.22),
                                Color.black.opacity(0.15)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
                    
                    // Center groove (main separator line)
                    Path { p in
                        p.move(to: CGPoint(x: ux * innerR, y: uy * innerR))
                        p.addLine(to: CGPoint(x: ux * outerR, y: uy * outerR))
                    }
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.12),
                                Color.black.opacity(0.08)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func sideInfoPanel(width: CGFloat, slices: [DisplaySlice]) -> some View {
        let active = selectedSymbol ?? hoverSymbol
        let headerFont: Font = .headline
        let valueFont: Font = .title3.bold()
        let labelFont: Font = .caption
        let isCompact = width < 180
        let isTight = width < 220
        let topCount = (selectedSymbol ?? hoverSymbol) != nil ? 3 : 4
        let top = Array(slices.prefix(topCount))

        VStack(alignment: .leading, spacing: 6) {
            if let sym = active, let match = slices.first(where: { $0.symbol == sym }) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Circle().fill(match.color).frame(width: 10, height: 10)
                        Text(sym)
                            .font(headerFont.weight(.semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.85)
                            .layoutPriority(2)
                    }
                    if isTight {
                        Text(abbreviatedCurrency(portfolioVM.totalValue * (match.percent / 100)))
                            .font(valueFont)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .allowsTightening(true)
                            .layoutPriority(3)
                            .ifAvailableNumericTransition()
                        Text("\(Int(match.percent.rounded()))% of portfolio")
                            .font(labelFont)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .allowsTightening(true)
                            .layoutPriority(2)
                    } else {
                        HStack(spacing: 8) {
                            Text(abbreviatedCurrency(portfolioVM.totalValue * (match.percent / 100)))
                                .font(valueFont)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .allowsTightening(true)
                                .layoutPriority(3)
                                .ifAvailableNumericTransition()
                            Text("•")
                                .foregroundColor(.secondary)
                            Text("\(Int(match.percent.rounded()))%")
                                .font(valueFont)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .allowsTightening(true)
                        }
                        .contentTransition(.opacity)
                        Text("of portfolio")
                            .font(labelFont)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .allowsTightening(true)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                EmptyView()
            }

            ForEach(top, id: \.symbol) { s in
                if isCompact {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 10) {
                            Circle().fill(s.color).frame(width: 8, height: 8)
                            Text(s.symbol)
                                .font(.callout)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        ZStack(alignment: .leading) {
                            Capsule().fill(DS.Adaptive.overlay(0.06))
                                .frame(height: 4)
                            Capsule().fill(s.color.opacity(0.9))
                                .frame(width: max(8, (max(0, width - 28)) * CGFloat(s.percent / 100.0)), height: 4)
                                .animation(.easeOut(duration: 0.5), value: appearProgress)
                                .animation(.easeOut(duration: 0.35), value: selectedSymbol)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            if selectedSymbol == s.symbol { selectedSymbol = nil } else { selectedSymbol = s.symbol }
                        }
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                    }
                    .onLongPressGesture(minimumDuration: 0.35) {
                        if s.symbol != "OTHER" {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            #endif
                            onActivateSymbol?(s.symbol)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 10) {
                            Circle().fill(s.color).frame(width: 8, height: 8)
                            Text(s.symbol)
                                .font(.footnote)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .layoutPriority(2)
                            Spacer()
                            Text("\(Int(s.percent.rounded()))%")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                                .layoutPriority(1)
                        }
                        ZStack(alignment: .leading) {
                            Capsule().fill(DS.Adaptive.overlay(0.06))
                                .frame(height: 4)
                            Capsule().fill(s.color.opacity(0.9))
                                .frame(width: max(8, (max(0, width - 56)) * CGFloat(s.percent / 100.0)), height: 4)
                                .animation(.easeOut(duration: 0.5), value: appearProgress)
                                .animation(.easeOut(duration: 0.35), value: selectedSymbol)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            if selectedSymbol == s.symbol { selectedSymbol = nil } else { selectedSymbol = s.symbol }
                        }
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                    }
                    .onLongPressGesture(minimumDuration: 0.35) {
                        if s.symbol != "OTHER" {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            #endif
                            onActivateSymbol?(s.symbol)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: width, alignment: .topLeading)
        .transaction { $0.disablesAnimations = true }
    }

    private func abbreviatedCurrency(_ value: Double) -> String {
        let isNegative = value < 0
        let absVal: Double = value.magnitude
        let sign = isNegative ? "-" : ""

        let thousand: Double = 1_000.0
        let million: Double  = 1_000_000.0
        let billion: Double  = 1_000_000_000.0
        let trillion: Double = 1_000_000_000_000.0

        var scaled: Double
        var suffix: String

        if absVal >= trillion {
            scaled = absVal / trillion
            suffix = "T"
        } else if absVal >= billion {
            scaled = absVal / billion
            suffix = "B"
        } else if absVal >= million {
            scaled = absVal / million
            suffix = "M"
        } else if absVal >= thousand {
            scaled = absVal / thousand
            suffix = "K"
        } else {
            let base = ThemedPortfolioPieChartView.wholeFormatter.string(from: NSNumber(value: absVal)) ?? String(Int(absVal))
            return sign + "$" + base
        }

        // Use whole numbers only for very large values (100+), otherwise show one decimal for precision
        // This ensures $10.5M displays correctly instead of rounding to $11M
        let formatter = (scaled >= 100.0) ? ThemedPortfolioPieChartView.wholeFormatter : ThemedPortfolioPieChartView.oneDecimalFormatter
        let numberString = formatter.string(from: NSNumber(value: scaled)) ?? String(scaled)
        return sign + "$" + numberString + suffix
    }

    private func abbreviatedCurrencyParts(_ value: Double) -> (String, String) {
        let s = abbreviatedCurrency(value)
        if let last = s.last, "KMBT".contains(last) {
            return (String(s.dropLast()), String(last))
        } else {
            return (s, "")
        }
    }

    private func colorMap(from slices: [DisplaySlice]) -> [String: Color] {
        var dict: [String: Color] = [:]
        for s in slices { dict[s.symbol] = s.color }
        return dict
    }

    @ViewBuilder
    private func calloutAnnotation(symbol: String, percentInt: Int, valueText: String, color: Color, isMini: Bool, midAngle: Double, outer: CGFloat, inner: CGFloat, diameter: CGFloat, dx: CGFloat, dy: CGFloat) -> some View {
        let edgeRadius = CGFloat(Double(outer) * Double(diameter) / 2.0)
        let ux = CGFloat(cos(midAngle))
        let uy = CGFloat(sin(midAngle))
        let startPt = CGPoint(x: ux * edgeRadius, y: uy * edgeRadius)
        let endPt = CGPoint(x: dx, y: dy)

        let showPercent = diameter >= 200
        let isRightSide = cos(midAngle) >= 0

        ZStack {
            Path { p in
                p.move(to: startPt)
                let shorten: CGFloat = max(8, diameter * 0.045)
                let vx = endPt.x - startPt.x
                let vy = endPt.y - startPt.y
                let vlen = max(1, sqrt(vx*vx + vy*vy))
                let sx = endPt.x - (vx / vlen) * shorten
                let sy = endPt.y - (vy / vlen) * shorten
                p.addLine(to: CGPoint(x: sx, y: sy))
            }
            .stroke(calloutLineStroke, lineWidth: 1)

            if isRightSide {
                HStack(spacing: 8) {
                    // Symbol pill with dot
                    HStack(spacing: 6) {
                        Circle().fill(color).frame(width: isMini ? 6 : 7, height: isMini ? 6 : 7)
                        Text(symbol)
                            .font(isMini ? .caption2 : .caption)
                            .foregroundColor(calloutPillText)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(
                        Capsule()
                            .fill(calloutPillFill)
                            .overlay(Capsule().stroke(calloutPillStroke, lineWidth: 0.8))
                    )

                    // Value pill
                    Text(valueText)
                        .font(isMini ? .caption2 : .caption)
                        .foregroundColor(calloutPillText)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(
                            Capsule()
                                .fill(calloutPillFill)
                                .overlay(Capsule().stroke(calloutPillStroke, lineWidth: 0.8))
                        )

                    // Percent pill (conditionally shown)
                    if showPercent {
                        Text("\(percentInt)%")
                            .font(isMini ? .caption2 : .caption)
                            .foregroundColor(calloutPillText)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(
                                Capsule()
                                    .fill(calloutPillFill)
                                    .overlay(Capsule().stroke(calloutPillStroke, lineWidth: 0.8))
                            )
                    }
                }
                .frame(maxWidth: diameter * 0.7, alignment: .leading)
            } else {
                HStack(spacing: 8) {
                    // Percent pill (conditionally shown)
                    if showPercent {
                        Text("\(percentInt)%")
                            .font(isMini ? .caption2 : .caption)
                            .foregroundColor(calloutPillText)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(
                                Capsule()
                                    .fill(calloutPillFill)
                                    .overlay(Capsule().stroke(calloutPillStroke, lineWidth: 0.8))
                            )
                    }
                    // Value pill
                    Text(valueText)
                        .font(isMini ? .caption2 : .caption)
                        .foregroundColor(calloutPillText)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(
                            Capsule()
                                .fill(calloutPillFill)
                                .overlay(Capsule().stroke(calloutPillStroke, lineWidth: 0.8))
                        )

                    // Symbol pill with dot
                    HStack(spacing: 6) {
                        Circle().fill(color).frame(width: isMini ? 6 : 7, height: isMini ? 6 : 7)
                        Text(symbol)
                            .font(isMini ? .caption2 : .caption)
                            .foregroundColor(calloutPillText)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(
                        Capsule()
                            .fill(calloutPillFill)
                            .overlay(Capsule().stroke(calloutPillStroke, lineWidth: 0.8))
                    )
                }
                .frame(maxWidth: diameter * 0.7, alignment: .trailing)
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: CalloutSizeKey.self, value: geo.size)
            }
        )
        .onPreferenceChange(CalloutSizeKey.self) { _ in }
        .modifier(CalloutClampModifier(dx: dx, dy: dy, inner: inner, diameter: diameter))
    }

    // PERFORMANCE FIX: Add throttling and thread safety to prevent excessive updates
    private struct CalloutSizeKey: PreferenceKey {
        static var defaultValue: CGSize = .zero
        private static let lock = NSLock()
        private static var _lastUpdateAt: CFTimeInterval = 0
        private static var _lastValue: CGSize = .zero
        
        static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
            let next = nextValue()
            guard next != .zero else { return }
            
            let now = CACurrentMediaTime()
            
            lock.lock()
            defer { lock.unlock() }
            
            // Throttle to 5Hz (200ms) - callout size rarely changes
            guard now - _lastUpdateAt >= 0.2 else { return }
            
            // Only update if size changed significantly (> 2px)
            let dw = abs(next.width - _lastValue.width)
            let dh = abs(next.height - _lastValue.height)
            guard dw > 2 || dh > 2 else { return }
            
            value = next
            _lastValue = next
            _lastUpdateAt = now
        }
    }

    private struct CalloutClampModifier: ViewModifier {
        let dx: CGFloat
        let dy: CGFloat
        let inner: CGFloat
        let diameter: CGFloat
        @ViewBuilder
        func body(content: Content) -> some View {
            let r = diameter / 2.0
            let pad: CGFloat = 8
            // Desired point
            let x = dx
            let y = dy
            let radius = max(0.0001, sqrt(x*x + y*y))
            // Enforce a minimum distance from the inner hole + padding
            let minR = (diameter * inner / 2.0) + 16
            let maxR = r - pad
            let clampedR = min(max(radius, minR), maxR)
            let scale = clampedR / radius
            let rx = x * scale
            let ry = y * scale
            // Also cap to frame edges as a final safety
            let clampedX = max(-r + pad, min(r - pad, rx))
            let clampedY = max(-r + pad, min(r - pad, ry))
            content.offset(x: clampedX, y: clampedY)
        }
    }
    
    private struct ArcStroke: Shape {
        var start: Double   // radians
        var end: Double     // radians
        var radiusRatio: CGFloat // 0..1 relative to diameter
        var lineWidthRatio: CGFloat // 0..1 of diameter used as stroke width

        var animatableData: AnimatablePair<Double, Double> {
            get { AnimatablePair(start, end) }
            set { start = newValue.first; end = newValue.second }
        }

        func path(in rect: CGRect) -> Path {
            var p = Path()
            let d = min(rect.size.width, rect.size.height)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = d * radiusRatio / 2.0
            p.addArc(center: center,
                     radius: radius,
                     startAngle: Angle(radians: start),
                     endAngle: Angle(radians: end),
                     clockwise: true)
            return p
        }
    }

    private func makeDisplaySlices(from raw: [PortfolioViewModel.AllocationSlice], minPercent: Double = 2.0, maxSlices: Int = 8) -> [DisplaySlice] {
        // Filter invalid/zero entries and normalize to 100%
        let filtered = raw.filter { $0.percent.isFinite && $0.percent > 0 }
        let total = filtered.reduce(0.0) { $0 + $1.percent }
        guard total > 0 else { return [] }

        // Build normalized DisplaySlice values directly (avoid mutating AllocationSlice)
        let normalized: [DisplaySlice] = filtered.map { s in
            let scaled = (s.percent / total) * 100.0
            let clamped = max(0.0001, scaled)
            return DisplaySlice(id: s.symbol, symbol: s.symbol, percent: clamped, color: s.color)
        }

        // Sort by percent descending, with symbol as secondary key for stability
        // This prevents slices with nearly equal percentages from swapping positions on price updates
        let sorted = normalized.sorted { 
            if abs($0.percent - $1.percent) < 0.1 {
                return $0.symbol < $1.symbol  // Stable secondary sort by symbol
            }
            return $0.percent > $1.percent 
        }
        var kept: [DisplaySlice] = []
        var otherPercent: Double = 0
        for (idx, s) in sorted.enumerated() {
            if kept.count < maxSlices - 1 && s.percent >= minPercent {
                kept.append(s)
            } else if kept.count < maxSlices - 1 && idx < maxSlices - 1 {
                kept.append(s)
            } else {
                otherPercent += s.percent
            }
        }
        if otherPercent > 0.0001 {
            kept.append(DisplaySlice(id: "OTHER", symbol: "OTHER", percent: otherPercent, color: .gray))
        }
        // Ensure final sum ~100 (avoid accumulated rounding drift)
        let sum = kept.reduce(0.0) { $0 + $1.percent }
        if sum > 0, abs(sum - 100.0) > 0.01 {
            // proportionally rescale
            return kept.map { ds in
                DisplaySlice(id: ds.symbol, symbol: ds.symbol, percent: ds.percent * (100.0 / sum), color: ds.color)
            }
        }
        return kept
    }

    // MARK: - Hit-testing helpers
    private func percentAngleAndRadius(for local: CGPoint, in rect: CGRect) -> (percentAngle: Double, radius: CGFloat) {
        let center = CGPoint(x: rect.size.width / 2.0, y: rect.size.height / 2.0)
        let dx = local.x - center.x
        let dy = local.y - center.y
        let r = sqrt(dx*dx + dy*dy)
        let angle = atan2(dy, dx)
        // atan2 gives angle from positive x-axis (3 o'clock), range -π to π
        // Swift Charts starts from 12 o'clock (negative y-axis) and goes clockwise
        // Convert: 12 o'clock = -90° = -π/2 radians
        let angleFrom12 = angle + Double.pi / 2  // Shift origin to 12 o'clock
        let normalizedAngle = angleFrom12 >= 0 ? angleFrom12 : (angleFrom12 + 2 * Double.pi)
        // Convert to percentage (0-100), clockwise direction
        let percentAngle = (normalizedAngle / (2 * Double.pi)) * 100
        return (percentAngle, r)
    }

    private func symbol(at percentAngle: Double, in slicesWithStart: [(slice: DisplaySlice, start: Double)]) -> String? {
        let p = ((percentAngle.truncatingRemainder(dividingBy: 100)) + 100).truncatingRemainder(dividingBy: 100)
        for item in slicesWithStart {
            let start = item.start
            let end = start + item.slice.percent
            if p >= start && p < end {
                return item.slice.symbol
            }
        }
        return nil
    }

    // MARK: - Gesture handling helpers
    private func updateHover(local: CGPoint, rect: CGRect, inner: CGFloat, outerNormal: CGFloat, slicesWithStart: [(slice: DisplaySlice, start: Double)]) {
        let minDim = min(rect.size.width, rect.size.height)
        let innerRadiusPixels = inner * minDim / 2.0
        let outerRadiusPixels = outerNormal * minDim / 2.0
        let info = percentAngleAndRadius(for: local, in: rect)
        guard info.radius >= innerRadiusPixels && info.radius <= outerRadiusPixels else {
            hoverSymbol = nil
            return
        }
        hoverSymbol = symbol(at: info.percentAngle, in: slicesWithStart)
    }
    
    /// Enhanced hover update with haptic feedback for smooth scrubbing
    private func updateHoverWithFeedback(local: CGPoint, rect: CGRect, inner: CGFloat, outerNormal: CGFloat, slicesWithStart: [(slice: DisplaySlice, start: Double)]) {
        let minDim = min(rect.size.width, rect.size.height)
        // Slightly expand the detection zone for easier interaction
        let innerRadiusPixels = (inner - 0.05) * minDim / 2.0
        let outerRadiusPixels = (outerNormal + 0.08) * minDim / 2.0
        let info = percentAngleAndRadius(for: local, in: rect)
        
        // Check if touch is within the expanded ring area
        guard info.radius >= max(0, innerRadiusPixels) && info.radius <= outerRadiusPixels else {
            // Only clear if we had a hover and moved far outside
            if hoverSymbol != nil && info.radius > outerRadiusPixels * 1.2 {
                hoverSymbol = nil
            }
            return
        }
        
        let newSymbol = symbol(at: info.percentAngle, in: slicesWithStart)
        
        // Provide haptic feedback when switching to a different slice
        if let new = newSymbol, new != hoverSymbol {
            #if os(iOS)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
            
            // Update the indicator position immediately for responsive feel
            if showSweepIndicator, let sliceData = slicesWithStart.first(where: { $0.slice.symbol == new }) {
                let start = sliceData.start
                let percent = sliceData.slice.percent
                let midPercent = (start + percent / 2.0) / 100.0
                let targetAngle = midPercent * 2 * Double.pi - Double.pi / 2
                updateIndicatorAngle(to: targetAngle, animated: true)
            }
        }
        
        hoverSymbol = newSymbol
    }

    private func endGesture(local: CGPoint, rect: CGRect, inner: CGFloat, outerNormal: CGFloat, slicesWithStart: [(slice: DisplaySlice, start: Double)]) {
        let minDim = min(rect.size.width, rect.size.height)
        let innerR = inner * minDim / 2.0
        let outerR = outerNormal * minDim / 2.0
        let info = percentAngleAndRadius(for: local, in: rect)

        // Tap inside the center hole clears selection
        if info.radius <= innerR {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.86)) {
                selectedSymbol = nil
                selectionProgress = 0
            }
            hoverSymbol = nil
            onSelectSymbol?(nil)
            return
        }

        // Ignore taps outside the ring
        guard info.radius >= innerR && info.radius <= outerR else {
            hoverSymbol = nil
            return
        }

        let tapped = symbol(at: info.percentAngle, in: slicesWithStart)
        if let sym = tapped {
            if selectedSymbol == sym {
                // Second tap toggles off selection instead of trying to activate
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    selectedSymbol = nil
                    selectionProgress = 0
                }
                onSelectSymbol?(nil)
            } else {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.85)) {
                    selectedSymbol = sym
                    selectionProgress = 1
                    ripplePhase = 0
                }
                withAnimation(.easeOut(duration: 0.6)) { ripplePhase = 1 }
                onSelectSymbol?(sym)
            }
        }
        hoverSymbol = nil
    }

    // MARK: - Animation helpers
    private func handleSelectionChange(_ newValue: String?) {
        // Use consistent spring animation for all selection changes
        let selectionSpring = Animation.spring(response: 0.4, dampingFraction: 0.85)
        
        if newValue != nil {
            withAnimation(selectionSpring) {
                selectionProgress = 1
                ripplePhase = 0
            }
            withAnimation(.easeOut(duration: 0.6)) {
                ripplePhase = 1
            }
        } else {
            withAnimation(selectionSpring) {
                selectionProgress = 0
                ripplePhase = 1
            }
        }
    }

    private func runAppearAnimations() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            appearProgress = 1
        }
        sweepStartTime = CACurrentMediaTime()
    }

    // MARK: - Accessibility helpers
    private func primaryAccessibilityAction(slices: [DisplaySlice]) {
        let syms = slices.map { $0.symbol }
        if selectedSymbol != nil {
            selectedSymbol = nil
        } else if let first = syms.first {
            selectedSymbol = first
        }
    }

    private func nextSliceAccessibility(slices: [DisplaySlice]) {
        let syms = slices.map { $0.symbol }
        guard !syms.isEmpty else { return }
        if let sel = selectedSymbol, let idx = syms.firstIndex(of: sel) {
            selectedSymbol = syms[(idx + 1) % syms.count]
        } else {
            selectedSymbol = syms.first
        }
    }

    private func clearSelectionAccessibility() {
        selectedSymbol = nil
    }

    private func adjustableAccessibility(direction: AccessibilityAdjustmentDirection, slices: [DisplaySlice]) {
        let syms = slices.map { $0.symbol }
        guard !syms.isEmpty else { return }
        switch direction {
        case .increment:
            if let sel = selectedSymbol, let idx = syms.firstIndex(of: sel) {
                selectedSymbol = syms[(idx + 1) % syms.count]
            } else {
                selectedSymbol = syms.first
            }
        case .decrement:
            if let sel = selectedSymbol, let idx = syms.firstIndex(of: sel) {
                let newIndex = (idx - 1 + syms.count) % syms.count
                selectedSymbol = syms[newIndex]
            } else {
                selectedSymbol = syms.last
            }
        @unknown default:
            break
        }
    }

    // MARK: - Accessibility value helper
    private func accessibilityValueText() -> Text {
        Text(selectedSymbol ?? "Total")
    }

    @ViewBuilder
    private func pieChart(
        slicesWithStart: [(slice: DisplaySlice, start: Double)],
        diameter: CGFloat,
        isMini: Bool,
        inner: CGFloat,
        outerSelected: CGFloat,
        outerNormal: CGFloat
    ) -> some View {
        let renderSlices: [RenderSliceData] = buildRenderSlices(
            slicesWithStart: slicesWithStart,
            diameter: diameter,
            isMini: isMini,
            inner: inner,
            outerSelected: outerSelected,
            outerNormal: outerNormal,
            activeSymbol: selectedSymbol ?? hoverSymbol
        )

        Chart(renderSlices, id: \.symbol) { item in
            SectorMark(
                angle: .value("Percent", item.percent),
                innerRadius: .ratio(item.innerAdj),
                outerRadius: .ratio(item.outer)
            )
            .foregroundStyle(item.gradient)
            .opacity(item.sliceOpacity)
        }
        .background(Color.clear)
        .overlay(
            Group {
                if showSliceCallouts, selectedSymbol != nil {
                    ZStack {
                        ForEach(renderSlices.filter { $0.isActive }) { item in
                            sliceAnnotation(item: item, isMini: isMini, diameter: diameter)
                        }
                    }
                }
            }
        )
        .chartPlotStyle { plotArea in
            plotArea
                .background(Color.clear)
                .border(Color.clear)
        }
        .chartBackground { _ in Color.clear }
        .background(Color.clear)
        // iOS 17+ uses Swift Charts' built-in angle selection for reliable hit detection
        .modifier(ChartAngleSelectionModifier(
            selectedAngle: $selectedAngle,
            sliceBounds: slicesWithStart.map { (symbol: $0.slice.symbol, start: $0.start, end: $0.start + $0.slice.percent) },
            onSelect: { symbol in
                if let sym = symbol {
                    if selectedSymbol == sym {
                        // Tapping same slice deselects
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            selectedSymbol = nil
                            selectionProgress = 0
                        }
                        onSelectSymbol?(nil)
                    } else {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.85)) {
                            selectedSymbol = sym
                            selectionProgress = 1
                            ripplePhase = 0
                        }
                        withAnimation(.easeOut(duration: 0.6)) { ripplePhase = 1 }
                        onSelectSymbol?(sym)
                    }
                }
            }
        ))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        // Prevent implicit animations when allocation data updates (price changes)
        .transaction { t in
            // Only allow animations for selection-related changes, not data updates
            if selectedSymbol == nil && hoverSymbol == nil {
                t.animation = nil
            }
        }
    }

    @ViewBuilder
    private func activeGlowRing(diameter: CGFloat, inner: CGFloat, outer: CGFloat) -> some View {
        // Simplified - only show a subtle glow on the active slice
        ZStack {
            if (selectedSymbol ?? hoverSymbol) != nil {
                let a0 = Double(min(accentFrom, accentTo))
                let a1 = Double(max(accentFrom, accentTo))
                let centerRatio = (inner + outer) / 2.0
                let widthRatio: CGFloat = (outer - inner) * 0.25
                let twoPi = Double.pi * 2
                let startAngle = a0 * twoPi - Double.pi / 2
                let endAngle = a1 * twoPi - Double.pi / 2
                
                // Very subtle glow arc
                ArcStroke(start: startAngle, end: endAngle, radiusRatio: centerRatio, lineWidthRatio: widthRatio)
                    .stroke(
                        accentRingColor.opacity(0.25),
                        style: StrokeStyle(lineWidth: max(2, diameter * widthRatio * 0.4), lineCap: .round)
                    )
                    .opacity(Double(0.4 + 0.2 * selectionProgress))
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func allocationBackground(
        diameter: CGFloat,
        inner: CGFloat,
        outerNormal: CGFloat,
        slices: [DisplaySlice]
    ) -> some View {
        // Color-reactive ambient glow (premium effect)
        colorReactiveAmbientGlow(diameter: diameter, outer: outerNormal, slices: slices)
            .zIndex(-2)
        ambientShadow(diameter: diameter, outer: outerNormal).zIndex(-1)
        donutTrack(diameter: diameter, inner: inner, outer: outerNormal, tint: Color.white)
            .opacity(0.12)
            .zIndex(-1)
    }

    @ViewBuilder
    private func allocationChrome(
        diameter: CGFloat,
        isMini: Bool,
        inner: CGFloat,
        outerSelected: CGFloat,
        outerNormal: CGFloat,
        slicesWithStart: [(slice: DisplaySlice, start: Double)],
        hasActive: Bool
    ) -> some View {
        // Chrome & highlights - simplified to avoid visual competition
        
        // Rotating sheen only when idle and enabled
        if showRotatingSheen && !isMini && !hasActive && !showSweepIndicator {
            SpecularSheen(diameter: diameter, inner: inner, outer: outerNormal)
                .opacity(0.5)
        }
        
        // Active glow ring - only show when sweep indicator is OFF (they compete visually)
        if !showSweepIndicator {
            activeGlowRing(diameter: diameter, inner: inner, outer: hasActive ? outerSelected : outerNormal)
        }
        
        // Start tick mark (only when enabled and sweep indicator is off)
        if showActiveStartTick && !showSweepIndicator {
            activeStartHighlight(diameter: diameter, inner: inner, outer: hasActive ? outerSelected : outerNormal)
        }

        // Slice separators - more visible when idle, subtle when active
        if showSliceSeparators && !isMini {
            sliceSeparators(slicesWithStart: slicesWithStart, diameter: diameter, inner: inner, outer: outerNormal)
                .opacity(hasActive ? 0.5 : 0.9)
        }

        // Tinted track overlay when active (very subtle) - skip when sweep indicator shown
        if hasActive && !showSweepIndicator {
            donutTrack(diameter: diameter, inner: inner, outer: outerNormal, tint: accentRingColor)
                .opacity(0.15)
        }

        // Donut lighting only when idle
        if !hasActive && !isMini {
            donutLighting(diameter: diameter, inner: inner, outer: outerNormal, tint: Color.white)
                .opacity(0.7)
        }

        // Depth effects - reduced when active for cleaner look
        if !isMini {
            donutDepth(diameter: diameter, inner: inner, outer: outerNormal)
                .opacity(hasActive ? 0.15 : 0.7)
        }
    }

    private func onSlicesSymbolsChange(_ slices: [DisplaySlice]) {
        let syms = Set(slices.map { $0.symbol })
        if let sel = selectedSymbol, !syms.contains(sel) { selectedSymbol = nil }
        onUpdateColors?(colorMap(from: slices))
    }

    private func onSelectedChanged(_ newSelection: String?, slices: [DisplaySlice]) {
        handleSelectionChange(newSelection)
        UISelectionFeedbackGenerator().selectionChanged()
        stopSweepOscillation()
        
        // Simply update accent to match selected slice
        updateAccent(for: selectedSymbol ?? hoverSymbol, slices: slices)
        
        if allowRotation, let sel = newSelection, let mid = midAngleFor(symbol: sel, slices: slices) {
            rotateChart(toMidAngle: mid, animated: true)
        }
    }

    private func onHoverChanged(_ newHover: String?, slices: [DisplaySlice]) {
        lastHoverSymbol = newHover
        stopSweepOscillation()
        
        // Only update accent if there's no selected symbol (hover takes precedence only when nothing selected)
        if selectedSymbol == nil {
            updateAccent(for: newHover, slices: slices)
            
            // Update sweep indicator position when hovering (if not already updated by gesture)
            if showSweepIndicator, let sym = newHover, let mid = midAngleFor(symbol: sym, slices: slices) {
                updateIndicatorAngle(to: mid, animated: true)
            }
        }
        
        if allowRotation, selectedSymbol == nil, let sym = newHover, let mid = midAngleFor(symbol: sym, slices: slices) {
            rotateChart(toMidAngle: mid, animated: true)
        }
    }

    // MARK: - Extracted helper to build chart core ZStack (reduces type-checker burden)
    @ViewBuilder
    private func allocationChartCore(
        diameter: CGFloat,
        isMini: Bool,
        inner: CGFloat,
        outerSelected: CGFloat,
        outerNormal: CGFloat,
        slicesWithStart: [(slice: DisplaySlice, start: Double)],
        hasActive: Bool,
        slices: [DisplaySlice]
    ) -> some View {
        ZStack {
            allocationBackground(diameter: diameter, inner: inner, outerNormal: outerNormal, slices: slices)

            pieChart(
                slicesWithStart: slicesWithStart,
                diameter: diameter,
                isMini: isMini,
                inner: inner,
                outerSelected: outerSelected,
                outerNormal: outerNormal
            )

            allocationChrome(
                diameter: diameter,
                isMini: isMini,
                inner: inner,
                outerSelected: outerSelected,
                outerNormal: outerNormal,
                slicesWithStart: slicesWithStart,
                hasActive: hasActive
            )

            innerHoleGlow(diameter: diameter, inner: inner)
            selectionRipple(diameter: diameter, inner: inner, slices: slices)
            if showSweepIndicator {
                sweepIndicator(diameter: diameter, inner: inner, outerSelected: outerSelected, outerNormal: outerNormal)
            }
            // Only show center accent ring when sweep indicator is OFF (they compete visually)
            if (hasActive || showIdleCenterRing) && !showSweepIndicator {
                centerAccentRing(diameter: diameter, inner: inner, outerNormal: outerNormal, outerSelected: outerSelected, slices: slices)
            }
            centerReadout(diameter: diameter, inner: inner, isMini: isMini, slices: slices)
                .scaleEffect(1.0)
                .opacity(1.0)
                .rotationEffect(allowRotation ? -chartRotation : .degrees(0))
                .zIndex(3)
        }
        .rotationEffect(allowRotation ? chartRotation : .degrees(0))
    }

    // MARK: - Gesture overlay extracted for type-checker
    @ViewBuilder
    private func gestureOverlay(
        inner: CGFloat,
        outerNormal: CGFloat,
        slicesWithStart: [(slice: DisplaySlice, start: Double)]
    ) -> some View {
        GeometryReader { g in
            Color.clear
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            // Keep iOS edge-back gesture responsive when chart is near screen edge.
                            guard value.startLocation.x > 24 else { return }
                            handleDragChanged(value: value, size: g.size, inner: inner, outerNormal: outerNormal, slicesWithStart: slicesWithStart)
                        }
                        .onEnded { value in
                            guard value.startLocation.x > 24 else { return }
                            handleDragEnded(value: value, size: g.size, inner: inner, outerNormal: outerNormal, slicesWithStart: slicesWithStart)
                        }
                )
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.45)
                        .onEnded { _ in
                            if let sym = selectedSymbol, sym != "OTHER" {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                onActivateSymbol?(sym)
                            }
                        }
                )
        }
    }

    private func handleDragChanged(value: DragGesture.Value, size: CGSize, inner: CGFloat, outerNormal: CGFloat, slicesWithStart: [(slice: DisplaySlice, start: Double)]) {
        let now = CACurrentMediaTime()
        // Reduced throttle for smoother 120Hz ProMotion display support
        if now - lastHoverTick < 0.008 { return }
        lastHoverTick = now
        let rect = CGRect(origin: .zero, size: size)
        let local = value.location

        if allowRotation {
            let a = angleAtPoint(local, in: rect)
            if let last = dragLastAngle {
                var delta = a - last
                if delta > Double.pi { delta -= 2 * Double.pi }
                if delta < -Double.pi { delta += 2 * Double.pi }
                dragVelocity = delta
                currentRotationBase += delta
                while currentRotationBase > Double.pi * 2 { currentRotationBase -= 2 * Double.pi }
                while currentRotationBase < -Double.pi * 2 { currentRotationBase += 2 * Double.pi }
                chartRotation = Angle(radians: currentRotationBase)
            }
            dragLastAngle = a
        }

        if allowHoverScrub {
            let adjusted = allowRotation ? rotatedPoint(local, in: rect, inverseRotation: chartRotation) : local
            updateHoverWithFeedback(local: adjusted, rect: rect, inner: inner, outerNormal: outerNormal, slicesWithStart: slicesWithStart)
        }
    }

    private func handleDragEnded(value: DragGesture.Value, size: CGSize, inner: CGFloat, outerNormal: CGFloat, slicesWithStart: [(slice: DisplaySlice, start: Double)]) {
        let rect = CGRect(origin: .zero, size: size)
        let local = value.location
        let adjusted = allowRotation ? rotatedPoint(local, in: rect, inverseRotation: chartRotation) : local
        endGesture(local: adjusted, rect: rect, inner: inner, outerNormal: outerNormal, slicesWithStart: slicesWithStart)

        if allowRotation {
            startDeceleration()
            dragLastAngle = nil
        }
    }

    private func handleChartAppear(slices: [DisplaySlice]) {
        runAppearAnimations()
        onUpdateColors?(colorMap(from: slices))
        
        if let activeKey = (selectedSymbol ?? hoverSymbol) {
            var run: Double = 0
            let starts: [(symbol: String, start: Double, percent: Double)] = slices.map { s in
                defer { run += s.percent }
                return (s.symbol, run, s.percent)
            }
            if let item = starts.first(where: { $0.symbol == activeKey }) {
                let innerFrom = item.start / 100.0
                let innerTo = (item.start + item.percent) / 100.0
                let midPercent = (innerFrom + innerTo) / 2.0
                let targetAngle = midPercent * 2 * Double.pi - Double.pi / 2
                updateIndicatorAngle(to: targetAngle, animated: false)
            }
        }
        
        updateAccent(for: (selectedSymbol ?? hoverSymbol), slices: slices)
        sweepStartTime = CACurrentMediaTime()
        
        if let sel = selectedSymbol, let mid = midAngleFor(symbol: sel, slices: slices) {
            rotateChart(toMidAngle: mid, animated: false)
        }
        if showSweepIndicator && allowSweepOscillation && (selectedSymbol ?? hoverSymbol) != nil {
            startSweepOscillation()
        } else {
            stopSweepOscillation()
        }
    }

    // MARK: - Chart with gestures (intermediate layer)
    @ViewBuilder
    private func allocationChartWithGestures(
        diameter: CGFloat,
        isMini: Bool,
        inner: CGFloat,
        outerSelected: CGFloat,
        outerNormal: CGFloat,
        slicesWithStart: [(slice: DisplaySlice, start: Double)],
        hasActive: Bool,
        slices: [DisplaySlice]
    ) -> some View {
        allocationChartCore(
            diameter: diameter,
            isMini: isMini,
            inner: inner,
            outerSelected: outerSelected,
            outerNormal: outerNormal,
            slicesWithStart: slicesWithStart,
            hasActive: hasActive,
            slices: slices
        )
        .overlay(gestureOverlay(inner: inner, outerNormal: outerNormal, slicesWithStart: slicesWithStart))
        .animation(.interactiveSpring(response: 0.32, dampingFraction: 0.82, blendDuration: 0.08), value: selectedSymbol)
        .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.80, blendDuration: 0.05), value: hoverSymbol)
        .contentShape(Rectangle())
        // Hit-testing is always enabled so users can tap slices to pop them out
        // and tap the center to reset. The glow-bleed issue (which originally
        // prompted disabling hit-testing for .hidden) is fixed by using an opaque
        // center disc fill instead of .ultraThinMaterial.
    }

    @ViewBuilder
    private func allocationChartView(
        diameter: CGFloat,
        isMini: Bool,
        inner: CGFloat,
        outerSelected: CGFloat,
        outerNormal: CGFloat,
        slices: [DisplaySlice]
    ) -> some View {
        var running: Double = 0
        let slicesWithStart: [(slice: DisplaySlice, start: Double)] = slices.map { s in
            defer { running += s.percent }
            return (slice: s, start: running)
        }
        let hasActive: Bool = (selectedSymbol != nil || hoverSymbol != nil)
        let symbols: [String] = slices.map { $0.symbol }

        allocationChartWithGestures(
            diameter: diameter,
            isMini: isMini,
            inner: inner,
            outerSelected: outerSelected,
            outerNormal: outerNormal,
            slicesWithStart: slicesWithStart,
            hasActive: hasActive,
            slices: slices
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { primaryAccessibilityAction(slices: slices) }
        .accessibilityAction(named: Text("Next Slice")) { nextSliceAccessibility(slices: slices) }
        .accessibilityAction(named: Text("Clear Selection")) { clearSelectionAccessibility() }
        .accessibilityAdjustableAction { direction in adjustableAccessibility(direction: direction, slices: slices) }
        .accessibilityHint("Double-tap to select or clear. Swipe up or down to move between slices.")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Portfolio allocation")
        .accessibilityValue(accessibilityValueText())
        .frame(width: diameter, height: diameter, alignment: .center)
        .onChange(of: symbols) { _, _ in
            DispatchQueue.main.async { onSlicesSymbolsChange(slices) }
        }
        .onChange(of: selectedSymbol) { _, newSelection in
            DispatchQueue.main.async { onSelectedChanged(newSelection, slices: slices) }
        }
        .onChange(of: hoverSymbol) { _, newHover in
            DispatchQueue.main.async { onHoverChanged(newHover, slices: slices) }
        }
        .onAppear {
            DispatchQueue.main.async { handleChartAppear(slices: slices) }
        }
        .onDisappear {
            stopSweepOscillation()
            decelTimer?.invalidate(); decelTimer = nil
        }
    }

    @ViewBuilder
    private func chartView(diameter: CGFloat, isMini: Bool, inner: CGFloat, outerSelected: CGFloat, outerNormal: CGFloat, slices: [DisplaySlice]) -> some View {
        allocationChartView(
            diameter: diameter,
            isMini: isMini,
            inner: inner,
            outerSelected: outerSelected,
            outerNormal: outerNormal,
            slices: slices
        )
        // Note: allocationChartView already applies .frame(width: diameter, height: diameter)
        .transition(.premiumChart)
    }
    
    var body: some View {
        if #available(iOS 16.0, *) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let minDim = min(w, h)
                // Reserve margin for sweep indicator orb and glow effects (about 20-28pt overhang)
                let indicatorMargin: CGFloat = minDim > 200 ? 24 : 16
                let diameter = max(1, minDim - indicatorMargin)
                let isMini = diameter < 120
                let inner: CGFloat = isMini ? 0.60 : 0.58
                let outerSelected: CGFloat = isMini ? 0.85 : 0.86
                let outerNormal: CGFloat = isMini ? 0.82 : 0.84
                
                let slices: [DisplaySlice] = makeDisplaySlices(from: overrideAllocationData ?? portfolioVM.allocationData)
                
                if slices.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.pie")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary)
                        Text("No allocation to display")
                            .foregroundColor(.secondary)
                            .font(.footnote)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.clear)
                    .onAppear { DispatchQueue.main.async { selectedSymbol = nil } }
                } else {
                    // Responsive layout: if there's ample horizontal room and side panel is enabled, show side panel
                    let sideRoom = w - diameter
                    if showSideInfoPanel && sideRoom > diameter * 0.32 && !isMini {
                        let chartDiameter = diameter * 0.92
                        HStack(alignment: .center, spacing: 16) {
                            Spacer(minLength: 0)
                            chartView(diameter: chartDiameter, isMini: isMini, inner: inner, outerSelected: outerSelected, outerNormal: outerNormal, slices: slices)
                            sideInfoPanel(width: sideRoom * 0.72, slices: slices)
                                .frame(height: diameter)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // Center the chart (no side panel) - use full available space
                        chartView(diameter: diameter, isMini: isMini, inner: inner, outerSelected: outerSelected, outerNormal: outerNormal, slices: slices)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .modifier(LegendPositionModifier(show: showLegend))
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showLegend)
            .frame(minWidth: 60, minHeight: 60) // safety minimums
            .background(Color.clear)
        } else {
            Text("Pie chart requires iOS 16+.")
                .foregroundColor(.gray)
        }
    }

    @ViewBuilder
    private func centerAccentRing(diameter: CGFloat, inner: CGFloat, outerNormal: CGFloat, outerSelected: CGFloat, slices: [DisplaySlice]) -> some View {
        EmptyView()
    }

    @ViewBuilder
    private func selectionRipple(diameter: CGFloat, inner: CGFloat, slices: [DisplaySlice]) -> some View {
        ZStack {
            if let sel = selectedSymbol, let color = slices.first(where: { $0.symbol == sel })?.color {
                let baseSize = diameter * inner
                Circle()
                    .stroke(gradient(for: color).opacity(0.45), lineWidth: max(1, diameter * 0.01))
                    .frame(width: baseSize * 0.84, height: baseSize * 0.84)
                    .scaleEffect(1 + 0.35 * ripplePhase)
                    .opacity(Double(1 - ripplePhase))
                    .allowsHitTesting(false)
                    .animation(.easeOut(duration: 0.7), value: ripplePhase)
            }
        }
    }

    @ViewBuilder
    /// Premium orb indicator with visible track ring - orb slides smoothly around the ring
    private func sweepIndicator(diameter: CGFloat, inner: CGFloat, outerSelected: CGFloat, outerNormal: CGFloat) -> some View {
        // Position centered on the donut ring (midpoint between inner and outer)
        let sliceCenterRadius = (inner + outerNormal) / 2.0
        let indicatorRadius = diameter * sliceCenterRadius / 2.0
        // Larger orb for better visibility - increased size
        let orbSize: CGFloat = max(26, diameter * 0.092)
        let hasActive = (selectedSymbol ?? hoverSymbol) != nil
        // Track ring width - more prominent
        let trackWidth: CGFloat = max(5.0, diameter * 0.018)
        
        ZStack {
            // === TRACK RING ===
            if hasActive {
                // Outer glow for depth
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: trackWidth + 6)
                    .frame(width: indicatorRadius * 2, height: indicatorRadius * 2)
                
                // Dark base track for contrast
                Circle()
                    .stroke(Color.black.opacity(0.5), lineWidth: trackWidth + 2)
                    .frame(width: indicatorRadius * 2, height: indicatorRadius * 2)
                
                // Main track ring - white/silver for visibility against any color
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.85),
                                Color.white.opacity(0.5),
                                Color.white.opacity(0.3),
                                Color.white.opacity(0.5),
                                Color.white.opacity(0.85)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: trackWidth
                    )
                    .frame(width: indicatorRadius * 2, height: indicatorRadius * 2)
            }
            
            // === ORB INDICATOR ===
            if hasActive {
                // Large outer glow - slice color
                Circle()
                    .fill(accentRingColor.opacity(0.7))
                    .frame(width: orbSize * 2.5, height: orbSize * 2.5)
                    .offset(y: -indicatorRadius)
                    .rotationEffect(Angle(radians: indicatorAngle + Double.pi / 2))
                
                // White outer glow for pop
                Circle()
                    .fill(Color.white.opacity(0.4))
                    .frame(width: orbSize * 1.8, height: orbSize * 1.8)
                    .offset(y: -indicatorRadius)
                    .rotationEffect(Angle(radians: indicatorAngle + Double.pi / 2))
                
                // Thick white outline ring for contrast
                Circle()
                    .stroke(Color.white, lineWidth: 3.5)
                    .frame(width: orbSize + 6, height: orbSize + 6)
                    .scaleEffect(indicatorLandingScale * indicatorPulse)
                    .offset(y: -indicatorRadius)
                    .rotationEffect(Angle(radians: indicatorAngle + Double.pi / 2))
                
                // Main orb - vibrant slice color with glossy effect
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.9),  // Bright highlight
                                accentRingColor.opacity(0.95),
                                accentRingColor,
                                accentRingColor.opacity(0.85)
                            ],
                            center: UnitPoint(x: 0.35, y: 0.3),
                            startRadius: 0,
                            endRadius: orbSize * 0.55
                        )
                    )
                    .frame(width: orbSize, height: orbSize)
                    .overlay(
                        // Bright specular highlight
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [Color.white, Color.white.opacity(0.0)],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: orbSize * 0.22
                                )
                            )
                            .frame(width: orbSize * 0.45, height: orbSize * 0.35)
                            .offset(x: -orbSize * 0.12, y: -orbSize * 0.15)
                    )
                    .overlay(
                        // Inner white rim for glass effect
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.8), Color.white.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .scaleEffect(indicatorLandingScale * indicatorPulse)
                    .offset(y: -indicatorRadius)
                    .rotationEffect(Angle(radians: indicatorAngle + Double.pi / 2))
            }
        }
        .frame(width: diameter, height: diameter)
        .opacity(hasActive ? 1.0 : 0.0)
        // Smoother spring animation for fluid sliding around the ring
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: indicatorAngle)
        .animation(.easeInOut(duration: 0.3), value: hasActive)
        // MEMORY FIX: .drawingGroup() removed - GPU offscreen buffer savings
        .allowsHitTesting(false)
        .zIndex(10)
        .onAppear {
            startIdlePulse()
        }
    }
    
    /// Breathing animation for the orb when idle - more noticeable pulse
    private func startIdlePulse() {
        // MEMORY FIX v19: Disable idle pulse loop.
        indicatorPulse = 1.0
    }

    // Animate the sweep indicator angle along the shortest circular path
    private func updateIndicatorAngle(to targetAngle: Double, animated: Bool = true) {
        // Normalize current angle to [0, 2π)
        var current = indicatorAngle.truncatingRemainder(dividingBy: 2 * Double.pi)
        if current < 0 { current += 2 * Double.pi }
        
        // Normalize target angle to [0, 2π)
        var target = targetAngle.truncatingRemainder(dividingBy: 2 * Double.pi)
        if target < 0 { target += 2 * Double.pi }
        
        // Calculate shortest delta for smooth sweep around the ring
        var delta = target - current
        if delta > Double.pi { delta -= 2 * Double.pi }
        if delta < -Double.pi { delta += 2 * Double.pi }
        
        // Update angle - view's .animation modifier handles the sweep
        indicatorAngle = indicatorAngle + delta
    }
    
    // Smoothly update the inner accent ring to the active slice
    private func updateAccent(for activeKey: String?, slices: [DisplaySlice]) {
        var run: Double = 0
        let starts: [(symbol: String, start: Double, percent: Double, color: Color)] = slices.map { s in
            defer { run += s.percent }
            return (s.symbol, run, s.percent, s.color)
        }
        if let key = activeKey, let item = starts.first(where: { $0.symbol == key }) {
            // Inner ring exactly follows the slice
            let innerFrom = item.start / 100.0
            let innerTo = (item.start + item.percent) / 100.0
            let color = item.color
            
            // Use consistent spring animation (unified: 0.35, 0.85)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                accentFrom = CGFloat(innerFrom)
                accentTo = CGFloat(innerTo)
                accentRingColor = color
            }
            
            // Animate the sweep indicator to the slice midpoint (shortest path)
            let midPercent = (innerFrom + innerTo) / 2.0
            let targetAngle = midPercent * 2 * Double.pi - Double.pi / 2  // 12 o'clock start, clockwise
            updateIndicatorAngle(to: targetAngle, animated: true)
            
            // Trigger landing bounce animation and haptic after indicator arrives
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                // Landing haptic feedback
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                
                withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) {
                    indicatorLandingScale = 1.12  // Larger, more satisfying bounce
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.7)) {
                        indicatorLandingScale = 1.0
                    }
                }
            }
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                accentFrom = 0
                accentTo = 1
                accentRingColor = Color.white.opacity(0.28)
            }
        }
    }
}

// File-scope helper: numeric text transition on iOS 17+
private struct NumericTransitionModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.contentTransition(.numericText(value: 1))
        } else {
            content
        }
    }
}

private extension View {
    func ifAvailableNumericTransition() -> some View {
        self.modifier(NumericTransitionModifier())
    }
}

private extension View {
    @ViewBuilder
    func applyIf<T: View>(_ condition: Bool, _ transform: (Self) -> T) -> some View {
        if condition { transform(self) } else { self }
    }
}

private struct LegendPositionModifier: ViewModifier {
    let show: Bool
    @ViewBuilder
    func body(content: Content) -> some View {
        if show {
            content.chartLegend(.visible)
        } else {
            content.chartLegend(.hidden)
        }
    }
}

struct ThemedPortfolioPieChartView_Previews: PreviewProvider {
    static var previews: some View {
        // Create a preview repository and VM
        let manualService = ManualPortfolioDataService(initialHoldings: [], initialTransactions: [])
        let liveService   = LivePortfolioDataService()
#if DEBUG
        let priceService  = PreviewPriceService()
#else
        let priceService  = CoinPaprikaData()
#endif
        let repo = PortfolioRepository(
            manualService: manualService,
            liveService:   liveService,
            priceService:  priceService
        )
        let vm = PortfolioViewModel(repository: repo)
        return ThemedPortfolioPieChartView(
            portfolioVM: vm,
            showLegend: .constant(false),
            allowRotation: false,
            allowSweepOscillation: false,
            showSweepIndicator: false,
            allowHoverScrub: false,
            showSliceCallouts: false,
            showRotatingSheen: false,
            showIdleCenterRing: false,
            showActiveStartTick: false,
            showSliceSeparators: false,
            centerMode: .normal,
            onSelectSymbol: nil,
            onActivateSymbol: nil,
            onUpdateColors: nil
        )
        .frame(width: 200, height: 200)
    }
}

extension ThemedPortfolioPieChartView {
    // Adaptive center disc color for light/dark mode
    // Light mode uses warm cream/white to look clean and professional
    private var centerDiscFill: Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark 
                ? UIColor.black.withAlphaComponent(0.55) 
                : UIColor(red: 0.997, green: 0.993, blue: 0.985, alpha: 1.0) // Warm off-white #FEF9F0
        })
    }
    private var centerDiscStroke: Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark 
                ? UIColor.white.withAlphaComponent(0.03) 
                : UIColor(red: 0.85, green: 0.80, blue: 0.72, alpha: 0.25) // Light warm beige stroke
        })
    }
    private var centerDiscShadow: Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark 
                ? UIColor.black.withAlphaComponent(0.25) 
                : UIColor(red: 0.70, green: 0.62, blue: 0.50, alpha: 0.06) // Very subtle warm shadow
        })
    }
    
    // Adaptive material background for center disc - opaque in light mode for clean look
    private var centerDiscMaterial: some View {
        Group {
            if colorScheme == .dark {
                Circle().fill(.ultraThinMaterial)
            } else {
                Circle().fill(Color(UIColor.systemBackground))
            }
        }
    }
    
    // Adaptive inner shadow for depth effects - warm brown in light mode
    private var innerDepthShadow: Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark 
                ? UIColor.black.withAlphaComponent(0.15) 
                : UIColor(red: 0.55, green: 0.45, blue: 0.33, alpha: 0.10) // Warm brown
        })
    }
    
    // Stronger inner shadow variant
    private var innerDepthShadowStrong: Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark 
                ? UIColor.black.withAlphaComponent(0.20) 
                : UIColor(red: 0.55, green: 0.45, blue: 0.33, alpha: 0.06) // Very subtle warm brown
        })
    }
    
    // Adaptive callout pill colors for light/dark mode
    private var calloutPillFill: Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark 
                ? UIColor.black.withAlphaComponent(0.55) 
                : UIColor.white.withAlphaComponent(0.95)
        })
    }
    private var calloutPillText: Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark 
                ? UIColor.white.withAlphaComponent(0.95) 
                : UIColor.black.withAlphaComponent(0.85)
        })
    }
    private var calloutPillStroke: Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark 
                ? UIColor.white.withAlphaComponent(0.06) 
                : UIColor.black.withAlphaComponent(0.10)
        })
    }
    private var calloutPillShadow: Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark 
                ? UIColor.black.withAlphaComponent(0.25) 
                : UIColor.black.withAlphaComponent(0.08)
        })
    }
    private var calloutLineStroke: Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark 
                ? UIColor.white.withAlphaComponent(0.14) 
                : UIColor.black.withAlphaComponent(0.12)
        })
    }

    @ViewBuilder
    private func centerReadout(diameter: CGFloat, inner: CGFloat, isMini: Bool, slices: [DisplaySlice]) -> some View {
        let isDark = colorScheme == .dark
        if centerMode == .hidden {
            // Render a clean opaque center disc without any text.
            // Uses opaque fill in both modes so the ambient glow never bleeds
            // through — this allows hit-testing to stay enabled for slice interaction.
            let innerDiameter = diameter * inner
            Circle()
                .fill(isDark ? centerDiscFill : Color(UIColor.systemBackground))
                .overlay(
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: isDark
                                    ? [centerDiscFill.opacity(0.7), centerDiscFill.opacity(0.5), centerDiscFill.opacity(0.3)]
                                    : [centerDiscFill, centerDiscFill.opacity(0.95), centerDiscFill.opacity(0.9)],
                                center: .center,
                                startRadius: 0,
                                endRadius: innerDiameter * 0.45
                            )
                        )
                )
                .overlay(
                    Circle()
                        .stroke(innerDepthShadowStrong, lineWidth: isDark ? 3 : 1.5)
                        .mask(Circle().padding(1))
                )
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: isDark
                                    ? [Color.white.opacity(0.25),
                                       Color.white.opacity(0.12),
                                       Color.white.opacity(0.03),
                                       Color.clear]
                                    : [Color(red: 0.85, green: 0.80, blue: 0.72).opacity(0.18),
                                       Color(red: 0.85, green: 0.80, blue: 0.72).opacity(0.08),
                                       Color.clear,
                                       Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isDark ? 1.5 : 0.8
                        )
                        .padding(2)
                )
                .overlay(Circle().stroke(centerDiscStroke, lineWidth: isDark ? 1 : 0.5))
                .frame(width: innerDiameter * 0.84, height: innerDiameter * 0.84)
        } else {
            let innerDiameter = diameter * inner
            ZStack {
                // Premium glassmorphic center disc - use solid background in light mode
                Group {
                    if isDark {
                        Circle().fill(.ultraThinMaterial)
                    } else {
                        Circle().fill(Color(UIColor.systemBackground))
                    }
                }
                    .overlay(
                        // Layered depth gradient
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: isDark
                                        ? [centerDiscFill.opacity(0.7), centerDiscFill.opacity(0.5), centerDiscFill.opacity(0.3)]
                                        : [centerDiscFill, centerDiscFill.opacity(0.95), centerDiscFill.opacity(0.9)],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: innerDiameter * 0.45
                                )
                            )
                    )
                    .overlay(
                        // Inner shadow for depth
                        Circle()
                            .stroke(innerDepthShadowStrong, lineWidth: isDark ? 3 : 1.5)
                            .mask(Circle().padding(1))
                    )
                    .overlay(
                        // Specular highlight ring (top-left) - adaptive
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: isDark
                                        ? [Color.white.opacity(0.25),
                                           Color.white.opacity(0.12),
                                           Color.white.opacity(0.03),
                                           Color.clear]
                                        : [Color(red: 0.85, green: 0.80, blue: 0.72).opacity(0.18),
                                           Color(red: 0.85, green: 0.80, blue: 0.72).opacity(0.08),
                                           Color.clear,
                                           Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: isDark ? 1.5 : 0.8
                            )
                            .padding(2)
                    )
                    .overlay(
                        // Outer rim stroke
                        Circle().stroke(centerDiscStroke, lineWidth: isDark ? 1 : 0.5)
                    )
                // Adaptive font sizes based on inner diameter for better scaling
                // Use more aggressive scaling for very small charts (under 80pt inner diameter)
                let isVerySmall = innerDiameter < 80
                let valueFontSize: CGFloat = isVerySmall ? max(12, innerDiameter * 0.28) : (isMini ? min(18, innerDiameter * 0.22) : min(22, innerDiameter * 0.16))
                let suffixFontSize: CGFloat = isVerySmall ? max(9, innerDiameter * 0.18) : (isMini ? min(13, innerDiameter * 0.16) : min(13, innerDiameter * 0.10))
                let labelFontSize: CGFloat = isVerySmall ? max(8, innerDiameter * 0.16) : (isMini ? min(11, innerDiameter * 0.14) : min(13, innerDiameter * 0.10))
                // Wider max width for small charts to allow text to breathe
                let textMaxWidth: CGFloat = isVerySmall ? innerDiameter * 0.82 : innerDiameter * 0.72
                
                // Use override total value if provided (for Paper Trading mode)
                let displayTotal = overrideTotalValue ?? portfolioVM.totalValue
                
                VStack(spacing: isVerySmall ? 1 : (isMini ? 2 : 6)) {
                    if let sym = (selectedSymbol ?? hoverSymbol), let match = slices.first(where: { $0.symbol == sym }) {
                        if isMini {
                            let parts = abbreviatedCurrencyParts(displayTotal * (match.percent / 100))
                            HStack(alignment: .firstTextBaseline, spacing: 0) {
                                Text(parts.0)
                                    .font(.system(size: valueFontSize, weight: .black, design: .rounded))
                                    .foregroundColor(.primary)
                                    .monospacedDigit()
                                    .kerning(-0.3)
                                    .ifAvailableNumericTransition()
                                if !parts.1.isEmpty {
                                    Text(parts.1)
                                        .font(.system(size: suffixFontSize, weight: .black, design: .rounded))
                                        .foregroundColor(.primary.opacity(0.9))
                                        .kerning(-0.3)
                                        .baselineOffset(1)
                                }
                            }
                            .lineLimit(1)
                            .minimumScaleFactor(isVerySmall ? 0.4 : 0.5)
                            .allowsTightening(true)
                            .frame(maxWidth: textMaxWidth)
                            Text("\(sym == "OTHER" ? "Other" : sym) • \(Int(match.percent.rounded()))%")
                                .font(.system(size: labelFontSize, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(isVerySmall ? 0.5 : 0.6)
                                .frame(maxWidth: textMaxWidth)
                        } else {
                            Text(abbreviatedCurrency(displayTotal * (match.percent / 100)))
                                .font(.system(size: valueFontSize, weight: .black, design: .rounded))
                                .foregroundColor(.primary)
                                .ifAvailableNumericTransition()
                                .lineLimit(1)
                                .minimumScaleFactor(isVerySmall ? 0.5 : 0.6)
                                .frame(maxWidth: textMaxWidth)
                            Text("\(sym == "OTHER" ? "Other" : sym) • \(Int(match.percent.rounded()))%")
                                .font(.system(size: labelFontSize, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(isVerySmall ? 0.6 : 0.7)
                                .frame(maxWidth: textMaxWidth)
                        }
                    } else {
                        if isMini {
                            let parts = abbreviatedCurrencyParts(displayTotal)
                            HStack(alignment: .firstTextBaseline, spacing: 0) {
                                Text(parts.0)
                                    .font(.system(size: valueFontSize, weight: .black, design: .rounded))
                                    .foregroundColor(.primary)
                                    .monospacedDigit()
                                    .kerning(-0.3)
                                    .ifAvailableNumericTransition()
                                if !parts.1.isEmpty {
                                    Text(parts.1)
                                        .font(.system(size: suffixFontSize, weight: .black, design: .rounded))
                                        .foregroundColor(.primary.opacity(0.9))
                                        .kerning(-0.3)
                                        .baselineOffset(1)
                                }
                            }
                            .lineLimit(1)
                            .minimumScaleFactor(isVerySmall ? 0.4 : 0.5)
                            .allowsTightening(true)
                            .frame(maxWidth: textMaxWidth)
                        } else {
                            Text(abbreviatedCurrency(displayTotal))
                                .font(.system(size: valueFontSize, weight: .black, design: .rounded))
                                .foregroundColor(.primary)
                                .ifAvailableNumericTransition()
                                .lineLimit(1)
                                .minimumScaleFactor(isVerySmall ? 0.5 : 0.6)
                                .frame(maxWidth: textMaxWidth)
                        }
                    }
                }
                .scaleEffect(centerLabelScale)  // Scale pulse animation
                .onChange(of: selectedSymbol) { _, _ in
                    // Trigger subtle scale pulse when selection changes (unified spring)
                    withAnimation(.spring(response: 0.18, dampingFraction: 0.6)) {
                        centerLabelScale = 1.05
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                            centerLabelScale = 1.0
                        }
                    }
                }
            }
            .frame(width: innerDiameter * 0.84, height: innerDiameter * 0.84)
            .multilineTextAlignment(.center)
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.25) {
                let total = overrideTotalValue ?? portfolioVM.totalValue
                let copyValue: String
                if let sym = (selectedSymbol ?? hoverSymbol), let match = slices.first(where: { $0.symbol == sym }) {
                    copyValue = abbreviatedCurrency(total * (match.percent / 100))
                } else {
                    copyValue = abbreviatedCurrency(total)
                }
                UIPasteboard.general.string = copyValue
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }
}


// MARK: - iOS 17+ Chart Angle Selection Modifier
/// Wraps Swift Charts' built-in chartAngleSelection for reliable slice hit detection
private struct ChartAngleSelectionModifier: ViewModifier {
    @Binding var selectedAngle: Double?
    // Simple tuple with just what's needed - avoids referencing private DisplaySlice type
    let sliceBounds: [(symbol: String, start: Double, end: Double)]
    let onSelect: (String?) -> Void
    
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content
                .chartAngleSelection(value: $selectedAngle)
                .onChange(of: selectedAngle) { _, newAngle in
                    // Defer to avoid "Modifying state during view update"
                    DispatchQueue.main.async {
                        if let angle = newAngle {
                            let symbol = symbolForAngle(angle)
                            onSelect(symbol)
                        }
                    }
                }
        } else {
            content
        }
    }
    
    private func symbolForAngle(_ angle: Double) -> String? {
        for item in sliceBounds {
            if angle >= item.start && angle < item.end {
                return item.symbol
            }
        }
        if let last = sliceBounds.last, angle >= 100 - 0.001 {
            return last.symbol
        }
        return nil
    }
}
