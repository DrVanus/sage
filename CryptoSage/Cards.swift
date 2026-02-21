import SwiftUI

struct CardCTAButtonStyle: ButtonStyle {
    var height: CGFloat = 34
    var cornerRadius: CGFloat = 10
    var horizontalPadding: CGFloat = 12
    var font: Font = .subheadline.weight(.semibold)

    func makeBody(configuration: Configuration) -> some View {
        let tint: Color = .yellow
        configuration.label
            .font(font)
            .foregroundStyle(tint)
            .frame(height: height)
            .padding(.horizontal, horizontalPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(DS.Adaptive.chipBackgroundActive)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(tint.opacity(0.85), lineWidth: 1.2)
            )
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

struct CardContainer<Content: View>: View {
    let content: () -> Content
    var body: some View {
        ZStack {
            // Base background
            RoundedRectangle(cornerRadius: 12)
                .fill(DS.Adaptive.cardBackground)
            
            // Subtle top gradient highlight for depth
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.04),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
            
            content()
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    LinearGradient(
                        colors: [
                            DS.Adaptive.stroke.opacity(1.2),
                            DS.Adaptive.stroke.opacity(0.6)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // PERFORMANCE FIX v21: Reduced shadow radius from 8 to 4 and compositing group.
        // Shadows with large radius require GPU to compute a Gaussian blur around the entire
        // card outline every frame during scroll. Reducing radius cuts GPU work significantly.
        // compositingGroup() flattens all layers (gradient + overlay + stroke) into a single
        // offscreen buffer before applying the shadow, so the shadow only blurs one surface
        // instead of each layer separately.
        .compositingGroup()
    }
}

// MARK: - Premium Glass Card
// High-tech glassmorphism card with depth, gold accents, and subtle animations

struct PremiumGlassCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let showGoldAccent: Bool
    let cornerRadius: CGFloat
    let enableShimmer: Bool
    let content: () -> Content
    
    @State private var hasAppeared = false
    @State private var shimmerOffset: CGFloat = -1.5
    
    init(showGoldAccent: Bool = true, cornerRadius: CGFloat = 16, enableShimmer: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.showGoldAccent = showGoldAccent
        self.cornerRadius = cornerRadius
        self.enableShimmer = enableShimmer
        self.content = content
    }
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        ZStack {
            // PERFORMANCE FIX v19: Replaced .ultraThinMaterial with solid color.
            // .ultraThinMaterial performs real-time Gaussian blur every frame, which is
            // extremely expensive during scroll (GPU must re-blur as background content moves).
            // This single change eliminates the #1 GPU bottleneck during home page scroll.
            // The gradient mimics the glass look without the real-time blur cost.
            // LIGHT MODE FIX: Slightly warmer card background with more depth gradient.
            // Previous 0.96→0.93 was too flat; now uses a warm cream top to a slightly cooler bottom
            // for visible card depth without being heavy.
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: isDark ? Color(white: 0.12) : Color(red: 1.0, green: 0.99, blue: 0.97), location: 0.0),
                            .init(color: isDark ? Color(white: 0.08) : Color(red: 0.97, green: 0.96, blue: 0.94), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            // Layer 2: Depth overlay (combines old layers 2, 3, 4 into one for fewer draw calls)
            // LIGHT MODE FIX: Boosted gold accent visibility from 0.03 to 0.06
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(isDark ? 0.08 : 0.22), location: 0.0),
                            .init(color: showGoldAccent ? BrandColors.goldBase.opacity(isDark ? 0.04 : 0.06) : Color.clear, location: 0.15),
                            .init(color: Color.clear, location: 0.4),
                            .init(color: Color.black.opacity(isDark ? 0.06 : 0.03), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            // Layer 5: Animated shimmer sweep (optional)
            if enableShimmer && isDark {
                GeometryReader { geo in
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: BrandColors.goldBase.opacity(0.15), location: 0.45),
                            .init(color: Color.white.opacity(0.25), location: 0.5),
                            .init(color: BrandColors.goldBase.opacity(0.15), location: 0.55),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.5)
                    .offset(x: shimmerOffset * geo.size.width)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .allowsHitTesting(false)
            }
            
            // Content
            content()
        }
        .overlay(
            // Premium border with gold accent at top
            // LIGHT MODE FIX: Increased gold border opacity from 0.35/0.15 to 0.45/0.25
            // so the premium gold accent at the top of cards is actually visible.
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        stops: showGoldAccent ? [
                            .init(color: BrandColors.goldBase.opacity(isDark ? 0.5 : 0.45), location: 0.0),
                            .init(color: BrandColors.goldBase.opacity(isDark ? 0.2 : 0.25), location: 0.15),
                            .init(color: DS.Adaptive.stroke.opacity(isDark ? 0.5 : 0.35), location: 0.4),
                            .init(color: DS.Adaptive.stroke.opacity(isDark ? 0.25 : 0.18), location: 1.0)
                        ] : [
                            .init(color: DS.Adaptive.stroke.opacity(0.7), location: 0.0),
                            .init(color: DS.Adaptive.stroke.opacity(0.3), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: isDark ? 1.0 : 0.8
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        // PERFORMANCE FIX v21: compositingGroup() + reduced shadow radius for scroll performance.
        // Flattens all gradient/overlay layers into a single offscreen buffer before shadow.
        // Shadow radius reduced from 8 to 4 to cut GPU Gaussian blur cost during scroll.
        .compositingGroup()
        // Subtle appear animation
        .scaleEffect(hasAppeared ? 1.0 : 0.98)
        .opacity(hasAppeared ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                hasAppeared = true
            }
            // Start shimmer animation if enabled
            if enableShimmer {
                startShimmerAnimation()
            }
        }
    }
    
    private func startShimmerAnimation() {
        // Delay start and run periodically
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            // PERFORMANCE FIX: Skip shimmer animation during scroll
            guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else {
                // Retry later when scroll ends
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.startShimmerAnimation()
                }
                return
            }
            withAnimation(.easeInOut(duration: 1.5)) {
                shimmerOffset = 1.5
            }
            // Reset and repeat
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                shimmerOffset = -1.5
                startShimmerAnimation()
            }
        }
    }
}

// MARK: - Premium Stat Badge
// Glowing badge for stat icons with animated gold ring

struct PremiumStatBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    let iconName: String
    let size: CGFloat
    
    @State private var hasAppeared = false
    @State private var glowPulse = false
    
    init(iconName: String, size: CGFloat = 24) {
        self.iconName = iconName
        self.size = size
    }
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        ZStack {
            // Outer glow ring (animated)
            Circle()
                .fill(BrandColors.goldBase.opacity(isDark ? 0.15 : 0.08))
                .frame(width: size + 8, height: size + 8)
                .scaleEffect(glowPulse ? 1.1 : 1.0)
            
            // Background circle with gradient
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            BrandColors.goldBase.opacity(isDark ? 0.18 : 0.12),
                            BrandColors.goldBase.opacity(isDark ? 0.08 : 0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
            
            // Gold ring stroke
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            BrandColors.goldLight.opacity(isDark ? 0.7 : 0.5),
                            BrandColors.goldBase.opacity(isDark ? 0.4 : 0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
                .frame(width: size, height: size)
            
            // Icon
            Image(systemName: iconName)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [BrandColors.goldLight, BrandColors.goldBase],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .scaleEffect(hasAppeared ? 1.0 : 0.8)
        .opacity(hasAppeared ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                hasAppeared = true
            }
        }
        // PERFORMANCE FIX v21: Scroll-aware glow pulse (pauses during scroll)
        .scrollAwarePulse(active: $glowPulse, duration: 2.0, delay: 0.5)
    }
}

struct ShareAppCard: View {
    private let shareURL = URL(string: "https://apps.apple.com/app/cryptosage-ai")!
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // Icon with subtle gold glow accent
                ZStack {
                    Circle()
                        .fill(BrandColors.goldBase.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: "person.2.fill")
                        .foregroundStyle(BrandColors.goldBase)
                        .font(.headline)
                }
                Text("Share CryptoSage")
                    .font(.headline)
                    .foregroundStyle(DS.Adaptive.textPrimary)
            }
            Text("Help others discover smart crypto insights")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            Spacer(minLength: 4)
            HStack(spacing: 8) {
                ShareLink(item: shareURL, message: Text("Check out CryptoSage — track markets, analyze portfolios, and get AI-powered crypto insights.\n")) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
                .buttonStyle(CSGoldPillButtonStyle(height: 26, horizontalPadding: 9, font: .caption2.weight(.semibold)))
                
                Button {
                    UIPasteboard.general.string = shareURL.absoluteString
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } label: {
                    Text("Copy Link")
                }
                .buttonStyle(CSGoldPillButtonStyle(height: 26, horizontalPadding: 9, font: .caption2.weight(.semibold)))
                .accessibilityLabel("Copy Link")
                
                Spacer(minLength: 0)
            }
        }
    }
}

// Keep backward compatibility alias
typealias InviteCard = ShareAppCard

struct RiskScanCard: View {
    let result: RiskScanResult?
    let isScanning: Bool
    let lastScan: Date?
    let onScan: () -> Void
    let onViewReport: () -> Void
    let overlayActive: Bool
    
    // Animation state
    @State private var hasAppeared = false

    private var riskColor: Color {
        guard let res = result else { return .gray }
        switch res.level {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .red
        }
    }

    var body: some View {
        Group {
            if isScanning || overlayActive {
                // Scanning state - show when overlay is active too
                scanningStateView
            } else if let res = result {
                // Results state - prominent gauge with actions
                resultsStateView(result: res)
            } else {
                // Pre-scan state - minimal badge style
                preScanStateView
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isScanning)
        .animation(.easeInOut(duration: 0.25), value: overlayActive)
        .animation(.easeInOut(duration: 0.3), value: result?.score)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                hasAppeared = true
            }
        }
    }
    
    // MARK: - Pre-scan State (Badge Style)
    @Environment(\.colorScheme) private var colorScheme
    
    private var preScanStateView: some View {
        return HStack(spacing: 12) {
            // Icon matching other section headers (GoldHeaderGlyph style)
            GoldHeaderGlyph(systemName: "shield.lefthalf.filled", size: 36, iconSize: 18)
            
            // Title and subtitle
            VStack(alignment: .leading, spacing: 3) {
                Text("Risk Scan")
                    .font(.headline)
                    .foregroundStyle(DS.Adaptive.textPrimary)
                
                Text("AI-powered portfolio analysis")
                    .font(.caption)
                    .foregroundStyle(DS.Adaptive.textSecondary)
            }
            
            Spacer(minLength: 8)
            
            // Run Scan button - use shared premium compact style
            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onScan()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Run Scan")
                        .font(.system(size: 12, weight: .bold))
                }
            }
            .buttonStyle(
                PremiumCompactCTAStyle(
                    height: 30,
                    horizontalPadding: 12,
                    cornerRadius: 15,
                    font: .system(size: 12, weight: .bold)
                )
            )
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 8)
    }
    
    // MARK: - Scanning State
    private var scanningStateView: some View {
        HStack(spacing: 12) {
            // Compact progress indicator matching section icon size
            ZStack {
                // Background circle
                Circle()
                    .fill(TintedChipStyle.selectedBackground(isDark: colorScheme == .dark).opacity(0.5))
                    .frame(width: 36, height: 36)
                
                // Spinning progress indicator
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.75)
                    .tint(BrandColors.goldBase)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text("Risk Scan")
                    .font(.headline)
                    .foregroundStyle(DS.Adaptive.textPrimary)
                
                HStack(spacing: 6) {
                    Text("Analyzing portfolio")
                        .font(.caption)
                        .foregroundStyle(DS.Adaptive.textSecondary)
                    
                    // Animated dots
                    ScanningDotsView()
                }
            }
            
            Spacer()
        }
    }
    
    // MARK: - Results State (Premium Gauge Card)
    private func resultsStateView(result: RiskScanResult) -> some View {
        let isDark = colorScheme == .dark
        
        return HStack(spacing: 14) {
            // Enhanced risk gauge with tap interaction
            ZStack {
                // Subtle colored background glow
                Circle()
                    .fill(riskColor.opacity(isDark ? 0.12 : 0.08))
                    .frame(width: 78, height: 78)
                
                RiskMiniGauge(score: result.score, level: result.level, size: .large)
            }
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onViewReport()
            }
            
            // Risk info and metadata
            VStack(alignment: .leading, spacing: 6) {
                // Risk level with colored pill badge
                HStack(spacing: 8) {
                    // Colored risk level pill
                    Text(result.level.rawValue)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(isDark ? .white : riskColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(riskColor.opacity(isDark ? 0.25 : 0.15))
                        )
                        .overlay(
                            Capsule()
                                .stroke(riskColor.opacity(0.4), lineWidth: 1)
                        )
                    
                    Text("Risk")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DS.Adaptive.textSecondary)
                }
                
                // Metadata row with icon
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(riskColor.opacity(0.8))
                    
                    Text("6 metrics")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(DS.Adaptive.textTertiary)
                    
                    if let last = lastScan {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(DS.Adaptive.textTertiary.opacity(0.5))
                        
                        Text(stubRelativeString(last))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(DS.Adaptive.textTertiary)
                    }
                }
            }
            
            Spacer(minLength: 8)
            
            // Action buttons - stacked vertically with better spacing
            VStack(alignment: .trailing, spacing: 10) {
                // Primary action - View Report - premium glass style
                Button(action: onViewReport) {
                    HStack(spacing: 4) {
                        Text("View Report")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TintedChipStyle.selectedText(isDark: isDark))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        ZStack {
                            Capsule()
                                .fill(TintedChipStyle.selectedBackground(isDark: isDark))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(isDark ? 0.12 : 0.5), Color.white.opacity(0)],
                                        startPoint: .top,
                                        endPoint: .center
                                    )
                                )
                        }
                    )
                    .overlay(
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: isDark
                                        ? [BrandColors.goldLight.opacity(0.4), BrandColors.goldBase.opacity(0.15)]
                                        : [BrandColors.silverBase.opacity(0.4), BrandColors.silverDark.opacity(0.15)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                // Secondary action - Rescan
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onScan()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Rescan")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .foregroundStyle(BrandColors.goldBase)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Scanning Dots Animation
private struct ScanningDotsView: View {
    @State private var dotIndex = 0
    @State private var animationTimer: Timer? = nil
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(DS.Adaptive.textSecondary)
                    .frame(width: 3, height: 3)
                    .opacity(dotIndex == index ? 1 : 0.3)
            }
        }
        .onAppear {
            animationTimer?.invalidate()
            // NOTE: SwiftUI View structs use [self] - timer invalidated in onDisappear
            animationTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [self] _ in
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        dotIndex = (dotIndex + 1) % 3
                    }
                }
            }
        }
        .onDisappear {
            animationTimer?.invalidate()
            animationTimer = nil
        }
    }
}

// MARK: - Mini Risk Gauge
private struct RiskMiniGauge: View {
    enum GaugeSize {
        case small
        case large
        
        var dimension: CGFloat {
            switch self {
            case .small: return 50
            case .large: return 68
            }
        }
        
        var strokeWidth: CGFloat {
            switch self {
            case .small: return 4.5
            case .large: return 5.5
            }
        }
        
        var fontSize: CGFloat {
            switch self {
            case .small: return 16
            case .large: return 24
            }
        }
        
        var subFontSize: CGFloat {
            switch self {
            case .small: return 7
            case .large: return 10
            }
        }
    }
    
    let score: Int
    let level: RiskLevel
    var size: GaugeSize = .small
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var animatedProgress: Double = 0
    @State private var showScore: Bool = false
    
    private var isDark: Bool { colorScheme == .dark }
    
    private var gaugeColor: Color {
        switch level {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .red
        }
    }
    
    private var progress: Double {
        Double(min(100, max(0, score))) / 100.0
    }
    
    private var gaugeSize: CGFloat { size.dimension }
    private var strokeWidth: CGFloat { size.strokeWidth }
    
    // Adaptive track colors
    private var trackColorStart: Color {
        isDark ? Color.white.opacity(0.08) : gaugeColor.opacity(0.12)
    }
    private var trackColorEnd: Color {
        isDark ? Color.white.opacity(0.04) : gaugeColor.opacity(0.06)
    }
    
    var body: some View {
        ZStack {
            // Background track circle - adaptive for light/dark
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [trackColorStart, trackColorEnd],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: strokeWidth
                )
                .frame(width: gaugeSize, height: gaugeSize)
            
            // Progress arc with gradient
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    AngularGradient(
                        colors: [gaugeColor.opacity(0.5), gaugeColor, gaugeColor.opacity(0.8)],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .frame(width: gaugeSize, height: gaugeSize)
                .rotationEffect(.degrees(-90))
            
            // Inner filled circle with subtle gradient
            Circle()
                .fill(
                    RadialGradient(
                        colors: [gaugeColor.opacity(isDark ? 0.12 : 0.08), gaugeColor.opacity(isDark ? 0.04 : 0.02)],
                        center: .center,
                        startRadius: 0,
                        endRadius: gaugeSize * 0.4
                    )
                )
                .frame(width: gaugeSize - strokeWidth * 2 - 4, height: gaugeSize - strokeWidth * 2 - 4)
            
            // Score text with animation - adaptive color
            VStack(spacing: -2) {
                Text("\(score)")
                    .font(.system(size: size.fontSize, weight: .bold).monospacedDigit())
                    .foregroundStyle(isDark ? .white : gaugeColor)
                
                if size == .large {
                    Text("/ 100")
                        .font(.system(size: size.subFontSize, weight: .medium))
                        .foregroundStyle(DS.Adaptive.textTertiary)
                }
            }
            .scaleEffect(showScore ? 1 : 0.7)
            .opacity(showScore ? 1 : 0)
        }
        .onAppear {
            // Animate the gauge filling
            withAnimation(GaugeMotionProfile.fill.delay(0.1)) {
                animatedProgress = progress
            }
            withAnimation(GaugeMotionProfile.springEmphasis.delay(0.2)) {
                showScore = true
            }
        }
        .onChange(of: score) { oldScore, newScore in
            // PERFORMANCE FIX v11: Skip during global startup phase
            guard !isInGlobalStartupPhase() else { return }
            
            // PERFORMANCE FIX v8: Skip during scroll and throttle updates
            guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
            // Skip if score hasn't changed significantly
            guard abs(newScore - oldScore) >= 1 else { return }
            
            let newProgress = Double(min(100, max(0, newScore))) / 100.0
            withAnimation(GaugeMotionProfile.fill) {
                animatedProgress = newProgress
            }
        }
    }
}

fileprivate func stubRelativeString(_ date: Date) -> String {
    let seconds = Int(Date().timeIntervalSince(date))
    if seconds < 60 { return "Just now" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)m ago" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h ago" }
    let days = hours / 24
    return "\(days)d ago"
}
