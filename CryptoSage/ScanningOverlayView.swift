import SwiftUI

// MARK: - Premium Gold Shield Scan Animation
struct HexShieldScanView: View {
    var size: CGFloat = 200
    @State private var ringPhase: CGFloat = 0
    @State private var scanRotation: Double = 0
    @State private var particlePhase: CGFloat = 0
    @State private var glowPulse: CGFloat = 0.6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    private let goldLight = BrandColors.goldLight
    private let goldBase = BrandColors.goldBase
    private let goldDark = BrandColors.goldDark
    
    var body: some View {
        ZStack {
            // Background glow behind entire shield
            Circle()
                .fill(
                    RadialGradient(
                        colors: [goldBase.opacity(0.25 * glowPulse), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.6
                    )
                )
                .frame(width: size * 1.2, height: size * 1.2)
            
            // Pulsing outer rings
            ForEach(0..<4, id: \.self) { i in
                let delay = CGFloat(i) * 0.25
                let phase = (ringPhase + delay).truncatingRemainder(dividingBy: 1.0)
                let scale = 0.4 + phase * 0.7
                let opacity = (1 - phase) * 0.4
                
                hexagonShape
                    .stroke(
                        LinearGradient(
                            colors: [goldLight.opacity(0.9), goldBase.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: size * scale, height: size * scale)
                    .opacity(opacity)
            }
            
            // Inner hexagonal frame with enhanced glow
            hexagonShape
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            goldLight.opacity(0.8),
                            goldBase.opacity(0.5),
                            goldDark.opacity(0.3),
                            goldBase.opacity(0.5),
                            goldLight.opacity(0.8)
                        ]),
                        center: .center
                    ),
                    lineWidth: 3
                )
                .frame(width: size * 0.55, height: size * 0.55)
            
            // Rotating scan line
            scanLine
                .frame(width: size * 0.5, height: size * 0.5)
                .rotationEffect(.degrees(scanRotation))
            
            // Central shield icon with enhanced glow
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [goldBase.opacity(0.4), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.22
                        )
                    )
                    .frame(width: size * 0.45, height: size * 0.45)
                
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: size * 0.15, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [goldLight, goldBase],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            
            // Floating data particles
            ForEach(0..<8, id: \.self) { i in
                dataParticle(index: i)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            DispatchQueue.main.async {
                withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                    ringPhase = 1.0
                }
                withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                    scanRotation = 360
                }
                withAnimation(.linear(duration: 4.0).repeatForever(autoreverses: false)) {
                    particlePhase = 1.0
                }
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    glowPulse = 1.0
                }
            }
        }
    }
    
    private var hexagonShape: some Shape {
        HexagonShape()
    }
    
    private var scanLine: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            Path { path in
                path.move(to: center)
                path.addLine(to: CGPoint(x: center.x, y: 0))
            }
            .stroke(
                LinearGradient(
                    colors: [goldLight.opacity(0.9), goldLight.opacity(0.0)],
                    startPoint: .bottom,
                    endPoint: .top
                ),
                lineWidth: 3
            )
        }
    }
    
    private func dataParticle(index: Int) -> some View {
        let angle = Double(index) * 45.0 + Double(particlePhase) * 360
        let radius = size * 0.35
        let particleRadius = size * 0.15 * (1 - particlePhase * 0.5)
        
        return Circle()
            .fill(goldLight.opacity(0.7 - particlePhase * 0.5))
            .frame(width: 4, height: 4)
            .offset(
                x: cos(angle * .pi / 180) * (radius - particleRadius * particlePhase),
                y: sin(angle * .pi / 180) * (radius - particleRadius * particlePhase)
            )
    }
}

// MARK: - Hexagon Shape
struct HexagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        
        for i in 0..<6 {
            let angle = (Double(i) * 60 - 90) * .pi / 180
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Animated Metric Counter
struct AnimatedMetricCounter: View {
    let label: String
    let targetValue: Double
    let format: String
    let isPercentage: Bool
    let delay: Double
    
    @State private var displayValue: Double = 0
    @State private var isAnimating = false
    
    private let goldLight = BrandColors.goldLight
    private let goldBase = BrandColors.goldBase
    
    init(label: String, targetValue: Double, format: String = "%.1f", isPercentage: Bool = true, delay: Double = 0) {
        self.label = label
        self.targetValue = targetValue
        self.format = format
        self.isPercentage = isPercentage
        self.delay = delay
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 2) {
                Text(String(format: format, displayValue * (isPercentage ? 100 : 1)))
                    .font(.system(size: 16, weight: .bold).monospacedDigit())
                    .foregroundStyle(goldLight)
                if isPercentage {
                    Text("%")
                        .font(.caption.bold())
                        .foregroundStyle(goldBase)
                }
            }
            
            // Mini progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.1))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [goldLight, goldBase],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(min(displayValue, 1.0)))
                }
            }
            .frame(height: 3)
        }
        .frame(minWidth: 70)
        .opacity(isAnimating ? 1 : 0)
        .offset(y: isAnimating ? 0 : 10)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeOut(duration: 0.4)) {
                    isAnimating = true
                }
                withAnimation(.easeOut(duration: 1.2).delay(0.2)) {
                    displayValue = targetValue
                }
            }
        }
    }
}

// MARK: - Scan Step Card
struct ScanStepCard: View {
    let step: String
    let icon: String
    let isActive: Bool
    let isComplete: Bool
    let delay: Double
    
    @State private var shimmerPhase: CGFloat = -1
    @State private var showSparkle = false
    @State private var appeared = false
    
    private let goldLight = BrandColors.goldLight
    private let goldBase = BrandColors.goldBase
    
    // FIXED HEIGHT to prevent layout jumping when steps change state
    private let cardHeight: CGFloat = 52
    
    var body: some View {
        HStack(spacing: 12) {
            // Status indicator - fixed size container to prevent jumping
            ZStack {
                // Always reserve space with invisible circle
                Circle()
                    .fill(Color.clear)
                    .frame(width: 28, height: 28)
                
                if isComplete {
                    Circle()
                        .fill(goldBase.opacity(0.2))
                        .frame(width: 28, height: 28)
                    
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(goldLight)
                    
                    // Sparkle burst on completion
                    if showSparkle {
                        SparkleBurstView(color: goldLight)
                            .frame(width: 40, height: 40)
                    }
                } else if isActive {
                    // Pulsing active indicator
                    Circle()
                        .stroke(goldLight.opacity(0.5), lineWidth: 2)
                        .frame(width: 28, height: 28)
                    
                    Circle()
                        .fill(goldBase)
                        .frame(width: 10, height: 10)
                        .scaleEffect(appeared ? 1.2 : 0.8)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: appeared)
                } else {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 28, height: 28)
                }
            }
            .frame(width: 28, height: 28) // Fixed frame for indicator
            
            // Step content - fixed layout, shimmer uses opacity instead of conditional
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(isActive || isComplete ? goldLight : .secondary)
                
                Text(step)
                    .font(.subheadline.weight(isActive ? .semibold : .regular))
                    .foregroundStyle(isActive || isComplete ? .white : .secondary)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: cardHeight) // FIXED HEIGHT prevents jumping
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(isActive ? 0.95 : 0.85)
        )
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isActive ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isActive ? goldLight.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 1)
        )
        // Active glow effect (doesn't change size)
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : -20)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    appeared = true
                }
            }
        }
        .onChange(of: isComplete) { _, completed in
            if completed {
                showSparkle = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    showSparkle = false
                }
            }
        }
    }
}

// MARK: - Completion Celebration View
struct ScanCompletionView: View {
    let riskLevel: String
    let riskScore: Int
    let riskColor: Color
    
    @State private var showScore = false
    @State private var pulseScale: CGFloat = 0.8
    @State private var showSparkles = false
    
    private let goldLight = BrandColors.goldLight
    
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                // Pulsing background
                Circle()
                    .fill(riskColor.opacity(0.15))
                    .frame(width: 120, height: 120)
                    .scaleEffect(pulseScale)
                
                // Score ring
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 8)
                    .frame(width: 100, height: 100)
                
                Circle()
                    .trim(from: 0, to: showScore ? CGFloat(riskScore) / 100 : 0)
                    .stroke(
                        LinearGradient(
                            colors: [riskColor.opacity(0.8), riskColor],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                
                // Score text
                VStack(spacing: 2) {
                    Text("\(riskScore)")
                        .font(.system(size: 32, weight: .bold).monospacedDigit())
                        .foregroundStyle(riskColor)
                    Text(riskLevel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .scaleEffect(showScore ? 1 : 0.5)
                .opacity(showScore ? 1 : 0)
                
                // Celebration sparkles
                if showSparkles {
                    ForEach(0..<6, id: \.self) { i in
                        SparkleBurstView(color: goldLight)
                            .frame(width: 30, height: 30)
                            .offset(
                                x: cos(Double(i) * 60 * .pi / 180) * 70,
                                y: sin(Double(i) * 60 * .pi / 180) * 70
                            )
                    }
                }
            }
            
            Text("Analysis Complete")
                .font(.headline)
                .foregroundStyle(.white)
                .opacity(showScore ? 1 : 0)
        }
        .onAppear {
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    pulseScale = 1.1
                }
                withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
                    showScore = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showSparkles = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            }
        }
    }
}

// MARK: - Main Scanning Overlay View
struct ScanningOverlayView: View {
    // Optional scan result for dynamic completion display
    var scanResult: RiskScanResult?
    
    @State private var stepIndex: Int = 0
    @State private var showCompletion = false
    @State private var metricsRevealed = false
    @State private var currentStepProgress: CGFloat = 0
    
    private let goldLight = BrandColors.goldLight
    private let goldBase = BrandColors.goldBase
    
    // Haptic generators
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    private let mediumHaptic = UIImpactFeedbackGenerator(style: .medium)
    
    private let steps: [(String, String)] = [
        ("Analyzing concentration", "chart.pie.fill"),
        ("Measuring volatility", "waveform.path.ecg"),
        ("Checking liquidity", "drop.fill"),
        ("Assessing drawdown", "arrow.down.to.line"),
        ("Generating AI insights", "sparkles")
    ]
    
    // Computed metrics based on result or defaults
    private var targetMetrics: [(String, Double)] {
        if let result = scanResult {
            return [
                ("Top Weight", result.metrics.topWeight),
                ("Volatility", result.metrics.volatility),
                ("HHI", result.metrics.hhi),
                ("Stablecoin", result.metrics.stablecoinWeight)
            ]
        }
        return [
            ("Top Weight", 0.40),
            ("Volatility", 0.013),
            ("HHI", 0.30),
            ("Stablecoin", 0.10)
        ]
    }
    
    // Computed completion data
    private var completionRiskLevel: String {
        scanResult?.level.rawValue ?? "Low"
    }
    
    private var completionRiskScore: Int {
        scanResult?.score ?? 24
    }
    
    private var completionRiskColor: Color {
        guard let result = scanResult else { return .green }
        switch result.level {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .red
        }
    }
    
    var body: some View {
        ZStack {
            // Blurred background with better contrast
            Color.black.opacity(0.92)
                .ignoresSafeArea()
                .background(.ultraThinMaterial.opacity(0.5))
            
            VStack(spacing: 24) {
                Spacer()
                
                if showCompletion {
                    ScanCompletionView(
                        riskLevel: completionRiskLevel,
                        riskScore: completionRiskScore,
                        riskColor: completionRiskColor
                    )
                    .transition(.scale.combined(with: .opacity))
                } else {
                    // Shield animation
                    HexShieldScanView(size: 180)
                        .frame(width: 180, height: 180)
                    
                    // Title with progress
                    VStack(spacing: 6) {
                        Text("Scanning Portfolio")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                        
                        Text("AI-powered risk analysis in progress")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        // Overall progress bar with glow
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white.opacity(0.12))
                                
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(
                                        LinearGradient(
                                            colors: [goldLight, goldBase],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geo.size.width * currentStepProgress)
                            }
                        }
                        .frame(width: 220, height: 6)
                        .padding(.top, 10)
                    }
                    
                    // Live metrics preview
                    if metricsRevealed {
                        HStack(spacing: 16) {
                            ForEach(Array(targetMetrics.enumerated()), id: \.offset) { index, metric in
                                AnimatedMetricCounter(
                                    label: metric.0,
                                    targetValue: metric.1,
                                    format: metric.0 == "HHI" ? "%.1f" : "%.1f",
                                    isPercentage: metric.0 != "HHI",
                                    delay: Double(index) * 0.2
                                )
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(goldBase.opacity(0.2), lineWidth: 1)
                                )
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                
                Spacer()
                
                // Step cards
                if !showCompletion {
                    VStack(spacing: 8) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            ScanStepCard(
                                step: step.0,
                                icon: step.1,
                                isActive: index == stepIndex,
                                isComplete: index < stepIndex,
                                delay: Double(index) * 0.12
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .onAppear {
            // Prepare haptic engines
            lightHaptic.prepare()
            mediumHaptic.prepare()
        }
        .task {
            // Initial delay for cards to appear
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            // Reveal metrics with animation
            try? await Task.sleep(nanoseconds: 400_000_000)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                metricsRevealed = true
            }
            
            // Progress through steps with deliberate pacing
            for i in 0..<steps.count {
                // "Processing" time for each step - slower pace
                let stepDuration: UInt64 = 900_000_000 // 900ms per step
                
                // Animate progress bar during this step
                let targetProgress = CGFloat(i + 1) / CGFloat(steps.count)
                withAnimation(.easeInOut(duration: 0.8)) {
                    currentStepProgress = targetProgress
                }
                
                try? await Task.sleep(nanoseconds: stepDuration)
                
                // Complete the step with haptic
                await MainActor.run {
                    lightHaptic.impactOccurred()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        stepIndex = i + 1
                    }
                }
                
                // Brief "thinking" pause between steps
                if i < steps.count - 1 {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
            
            // Pause to let user see all steps completed
            try? await Task.sleep(nanoseconds: 600_000_000)
            
            // Show completion celebration with haptic
            await MainActor.run {
                mediumHaptic.impactOccurred()
                withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
                    showCompletion = true
                }
            }
        }
    }
}

// MARK: - Preview
#Preview {
    ScanningOverlayView()
        .preferredColorScheme(.dark)
}
