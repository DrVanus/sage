//
//  AllAIInsightsView.swift
//  CryptoSage
//
//  Created by DM on 5/31/25.
//

import SwiftUI

// Premium styling helpers - adaptive for light/dark mode
private extension View {
    func glassCard(cornerRadius: CGFloat = 14) -> some View {
        self.modifier(AdaptiveGlassCard(cornerRadius: cornerRadius))
    }
}

private struct AdaptiveGlassCard: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    
    func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isDark ? Color.white.opacity(0.06) : DS.Adaptive.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: isDark
                                        ? [Color.white.opacity(0.22), Color.white.opacity(0.06)]
                                        : [DS.Adaptive.stroke.opacity(0.4), DS.Adaptive.stroke.opacity(0.15)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: isDark ? 1 : 0.8
                            )
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct SummaryMetricCard: View {
    let metric: SummaryMetric
    var cardWidth: CGFloat? = nil // nil means flexible
    @State private var shimmerX: CGFloat = -160
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        let isDark = colorScheme == .dark
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(isDark ? Color.white.opacity(0.10) : DS.Adaptive.chipBackground)
                    .overlay(Circle().stroke(isDark ? Color.white.opacity(0.14) : BrandColors.goldBase.opacity(0.3), lineWidth: 0.8))
                Image(systemName: metric.iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isDark ? AnyShapeStyle(BrandColors.goldHorizontal) : AnyShapeStyle(BrandColors.goldBase))
            }
            .frame(width: 36, height: 36)

            Text(metric.valueText)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(DS.Adaptive.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(metric.title)
                .font(.caption)
                .foregroundColor(DS.Adaptive.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: cardWidth, height: 116)
        .frame(maxWidth: cardWidth == nil ? .infinity : nil)
        .glassCard()
        .overlay(
            // Top gloss
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: isDark ? [Color.white.opacity(0.16), .clear] : [Color.white.opacity(0.5), .clear], startPoint: .top, endPoint: .center))
                .allowsHitTesting(false)
        )
    }
}

private struct SummaryMetricSkeleton: View {
    var cardWidth: CGFloat? = nil // nil means flexible
    @State private var shimmerX: CGFloat = -160
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        let isDark = colorScheme == .dark
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(isDark ? Color.white.opacity(0.06) : DS.Adaptive.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: isDark
                                ? [Color.white.opacity(0.22), Color.white.opacity(0.06)]
                                : [DS.Adaptive.stroke.opacity(0.4), DS.Adaptive.stroke.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .frame(width: cardWidth, height: 116)
            .frame(maxWidth: cardWidth == nil ? .infinity : nil)
            .overlay(
                Rectangle()
                    .fill(LinearGradient(colors: [Color.clear, (isDark ? Color.white : Color.black).opacity(isDark ? 0.35 : 0.08), Color.clear], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 70, height: 140)
                    .offset(x: shimmerX)
                    .mask(RoundedRectangle(cornerRadius: 14, style: .continuous))
            )
            .onAppear {
                // Defer to avoid "Modifying state during view update"
                DispatchQueue.main.async {
                    withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                        shimmerX = 200
                    }
                }
            }
    }
}

private struct GlassPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.06 : 0))
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct PillTag: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        let isDark = colorScheme == .dark
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundColor(TintedChipStyle.selectedText(isDark: isDark))
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .tintedCapsuleChip(isSelected: true, isDark: isDark)
    }
}

private struct ContributionRow: View {
    let name: String
    let pct: Double   // 0..1
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        let isDark = colorScheme == .dark
        ZStack(alignment: .leading) {
            GeometryReader { geo in
                let w = max(0, min(geo.size.width, geo.size.width * pct))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill((isDark ? BrandColors.goldHorizontal : BrandColors.goldHorizontalLight).opacity(isDark ? 0.22 : 0.35))
                    .frame(width: w)
            }
            .allowsHitTesting(false)
            HStack {
                Text(name)
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textPrimary)
                Spacer()
                Text(String(format: "%.0f%%", pct * 100))
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 36)
        .glassCard(cornerRadius: 8)
    }
}

private struct FeeRow: View {
    let label: String
    let pct: Double
    let maxPct: Double
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        let isDark = colorScheme == .dark
        ZStack(alignment: .leading) {
            GeometryReader { geo in
                let ratio = maxPct > 0 ? (pct / maxPct) : 0
                let w = max(0, min(geo.size.width, geo.size.width * ratio))
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill((isDark ? BrandColors.goldHorizontal : BrandColors.goldHorizontalLight).opacity(isDark ? 0.18 : 0.3))
                    .frame(width: w)
            }
            .allowsHitTesting(false)
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textPrimary.opacity(0.85))
                Spacer()
                Text(String(format: "%.2f%%", pct * 100))
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 36)
        .glassCard(cornerRadius: 10)
    }
}

// MARK: - Diversification Empty State
private struct DiversificationEmptyState: View {
    var isPaperTrading: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        let isDark = colorScheme == .dark
        VStack(spacing: 16) {
            pieChartIllustration(isDark: isDark)
            emptyStateText(isDark: isDark)
            if !isPaperTrading {
                sampleAllocationPreview(isDark: isDark)
            }
        }
        .padding(.vertical, 8)
    }
    
    private func pieChartIllustration(isDark: Bool) -> some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(DS.Adaptive.divider.opacity(isDark ? 0.08 : 0.2), lineWidth: 12)
                .frame(width: 100, height: 100)
            
            // Decorative segments
            pieSegment(index: 0, isDark: isDark)
            pieSegment(index: 1, isDark: isDark)
            pieSegment(index: 2, isDark: isDark)
            pieSegment(index: 3, isDark: isDark)
            
            // Center icon
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 28))
                .foregroundStyle(isDark ? AnyShapeStyle(BrandColors.goldHorizontal) : AnyShapeStyle(BrandColors.goldBase))
        }
        .padding(.vertical, 8)
    }
    
    private func pieSegment(index: Int, isDark: Bool) -> some View {
        let startFraction = CGFloat(index) * 0.25
        let endFraction = startFraction + 0.2
        let opacity = 0.3 + Double(index) * 0.15
        let goldColor = BrandColors.goldBase.opacity(opacity)
        
        return Circle()
            .trim(from: startFraction, to: endFraction)
            .stroke(
                LinearGradient(
                    colors: [goldColor, DS.Adaptive.divider.opacity(0.1)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: 12, lineCap: .round)
            )
            .frame(width: 100, height: 100)
            .rotationEffect(.degrees(Double(index) * 90))
    }
    
    private func emptyStateText(isDark: Bool) -> some View {
        VStack(spacing: 6) {
            Text(isPaperTrading ? "No Holdings Yet" : "No Portfolio Connected")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Text(isPaperTrading 
                 ? "Start paper trading to build your portfolio and see diversification analysis"
                 : "Connect your portfolio to see diversification analysis and risk metrics")
                .font(.caption)
                .foregroundColor(DS.Adaptive.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
    }
    
    private func sampleAllocationPreview(isDark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sample Allocation")
                .font(.caption2.weight(.medium))
                .foregroundColor(DS.Adaptive.textTertiary)
            
            HStack(spacing: 8) {
                allocationDot(asset: "BTC", opacity: 1.0, isDark: isDark)
                allocationDot(asset: "ETH", opacity: 0.7, isDark: isDark)
                allocationDot(asset: "SOL", opacity: 0.5, isDark: isDark)
                allocationDot(asset: "Other", opacity: 0.3, isDark: isDark)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(sampleAllocationBackground(isDark: isDark))
    }
    
    private func allocationDot(asset: String, opacity: Double, isDark: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(BrandColors.goldBase.opacity(opacity))
                .frame(width: 6, height: 6)
            Text(asset)
                .font(.caption2)
                .foregroundColor(DS.Adaptive.textSecondary)
        }
    }
    
    private func sampleAllocationBackground(isDark: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(DS.Adaptive.chipBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
            )
    }
}

// MARK: - Fee Empty State
private struct FeeEmptyState: View {
    var isPaperTrading: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        let isDark = colorScheme == .dark
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(DS.Adaptive.chipBackground)
                    .frame(width: 60, height: 60)
                
                Image(systemName: "percent")
                    .font(.system(size: 24))
                    .foregroundStyle(isDark ? AnyShapeStyle(BrandColors.goldHorizontal) : AnyShapeStyle(BrandColors.goldBase))
            }
            
            VStack(spacing: 4) {
                Text(isPaperTrading ? "No Trades Yet" : "No Fee Data")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text(isPaperTrading 
                     ? "Fees will be estimated at 0.1% trading fee + ~$0.50 network fee per trade"
                     : "Complete some trades to see fee breakdown")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
        }
        .padding(.vertical, 20)
    }
}

// MARK: - Trade Quality Empty State
private struct TradeQualityEmptyState: View {
    var isPaperTrading: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        let isDark = colorScheme == .dark
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(DS.Adaptive.chipBackground)
                    .frame(width: 60, height: 60)
                
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(isDark ? AnyShapeStyle(BrandColors.goldHorizontal) : AnyShapeStyle(BrandColors.goldBase))
            }
            
            VStack(spacing: 4) {
                Text(isPaperTrading ? "No Positions Yet" : "No Trade History")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text(isPaperTrading 
                     ? "Start paper trading to see position performance and P&L metrics"
                     : "Complete buy and sell trades to see quality metrics")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 20)
    }
}

// MARK: - Momentum Empty State
private struct MomentumEmptyState: View {
    var isPaperTrading: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        let isDark = colorScheme == .dark
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(DS.Adaptive.chipBackground)
                    .frame(width: 60, height: 60)
                
                Image(systemName: "arrow.up.right.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(isDark ? AnyShapeStyle(BrandColors.goldHorizontal) : AnyShapeStyle(BrandColors.goldBase))
            }
            
            VStack(spacing: 4) {
                Text(isPaperTrading ? "No Trading Activity" : "No Momentum Data")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text(isPaperTrading 
                     ? "Execute paper trades to see momentum analysis and trading patterns"
                     : "Start trading to see momentum analysis")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 20)
    }
}

// MARK: - AI Insights Empty State (No Portfolio Data)
private struct AIInsightsEmptyState: View {
    var onEnableDemo: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        let isDark = colorScheme == .dark
        VStack(spacing: 24) {
            Spacer()
            
            // Illustration
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [BrandColors.goldBase.opacity(0.2), Color.clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)
                
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 56))
                    .foregroundStyle(isDark ? AnyShapeStyle(BrandColors.goldHorizontal) : AnyShapeStyle(BrandColors.goldBase))
            }
            
            VStack(spacing: 12) {
                Text("No Portfolio Data")
                    .font(.title2.weight(.bold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text("Connect an exchange or enable demo mode to unlock AI-powered insights and analysis.")
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            // Try Demo Mode Button
            Button(action: onEnableDemo) {
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 16))
                    Text("Try Demo Mode")
                        .font(.headline)
                }
                .foregroundColor(BrandColors.ctaTextColor(isDark: isDark))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(BrandColors.ctaHorizontal(isDark: isDark))
                )
            }
            .padding(.horizontal, 40)
            
            Spacer()
        }
        .padding(.vertical, 40)
    }
}

// MARK: - AI Insights Locked State (Free Users)
private struct AIInsightsLockedState: View {
    var onUpgrade: () -> Void
    var onEnableDemo: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Lock illustration
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.15))
                    .frame(width: 120, height: 120)
                
                Circle()
                    .fill(Color.purple.opacity(0.1))
                    .frame(width: 90, height: 90)
                
                Image(systemName: "lock.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .purple.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            
            VStack(spacing: 12) {
                Text("Pro Feature")
                    .font(.title2.weight(.bold))
                    .foregroundColor(DS.Adaptive.textPrimary)

                Text("AI Insights provides deep portfolio analysis, performance tracking, and personalized recommendations.")
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            // Feature preview
            VStack(alignment: .leading, spacing: 10) {
                featureRow(icon: "chart.line.uptrend.xyaxis", text: "Performance vs BTC/ETH")
                featureRow(icon: "shield.fill", text: "Risk Score Analysis")
                featureRow(icon: "arrow.triangle.2.circlepath", text: "Rebalancing Suggestions")
                featureRow(icon: "bell.badge.fill", text: "Smart Alerts")
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(DS.Adaptive.chipBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(DS.Adaptive.stroke, lineWidth: 1)
                    )
            )
            .padding(.horizontal, 32)
            
            VStack(spacing: 12) {
                // Upgrade Button
                Button(action: onUpgrade) {
                    HStack(spacing: 8) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 16))
                        Text("Upgrade to Pro")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(
                    PremiumPrimaryCTAStyle(
                        height: 48,
                        horizontalPadding: 16,
                        cornerRadius: 12,
                        font: .headline
                    )
                )
                .padding(.horizontal, 40)
                
                // Try Demo Mode Button
                Button(action: onEnableDemo) {
                    HStack(spacing: 8) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 14))
                        Text("Preview with Demo Data")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundColor(DS.Adaptive.textSecondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 40)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.purple)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
            Spacer()
            Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundColor(.green)
        }
    }
}

// MARK: - Premium Performance Chart
private struct PremiumPerformanceChart: View {
    let data: [Double]
    let isPositive: Bool
    
    @State private var drawProgress: CGFloat = 0
    @State private var pulseScale: CGFloat = 1.0
    
    private var lineColor: Color {
        isPositive ? .green : .red
    }
    
    private var currentValue: Double {
        data.last ?? 0
    }
    
    private var changePercent: Double {
        guard let first = data.first, let last = data.last, first != 0 else { return 0 }
        return ((last - first) / first) * 100
    }
    
    // Catmull-Rom spline interpolation for smooth curves
    private func catmullRomSmooth(_ pts: [CGPoint], samplesPerSegment: Int = 4) -> [CGPoint] {
        let n = pts.count
        guard n >= 2, samplesPerSegment > 0 else { return pts }
        var out: [CGPoint] = []
        out.reserveCapacity((n - 1) * samplesPerSegment + 1)
        
        func point(_ i: Int) -> CGPoint { pts[max(0, min(n - 1, i))] }
        
        for i in 0..<(n - 1) {
            let p0 = point(i - 1), p1 = point(i), p2 = point(i + 1), p3 = point(i + 2)
            for s in 0..<samplesPerSegment {
                let t = CGFloat(s) / CGFloat(samplesPerSegment)
                let t2 = t * t
                let t3 = t2 * t
                // Linear X to maintain monotonic time axis
                let x = p1.x + (p2.x - p1.x) * t
                // Catmull-Rom Y for smooth price curve
                let y = 0.5 * ((2*p1.y) + (-p0.y + p2.y)*t + (2*p0.y - 5*p1.y + 4*p2.y - p3.y)*t2 + (-p0.y + 3*p1.y - 3*p2.y + p3.y)*t3)
                out.append(CGPoint(x: x, y: y))
            }
        }
        if let last = pts.last { out.append(last) }
        return out
    }
    
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            
            ZStack {
                // Background glass
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [lineColor.opacity(0.25), lineColor.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                
                // Subtle grid lines
                ForEach(0..<3, id: \.self) { i in
                    let yPos = h * CGFloat(i + 1) / 4.0
                    Path { path in
                        path.move(to: CGPoint(x: 12, y: yPos))
                        path.addLine(to: CGPoint(x: w - 12, y: yPos))
                    }
                    .stroke(Color.white.opacity(0.06), style: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                }
                
                if data.count > 1,
                   let minVal = data.min(),
                   let maxVal = data.max() {
                    let range = max(maxVal - minVal, 0.0001)
                    let padding = range * 0.12
                    let adjustedMin = minVal - padding
                    let adjustedRange = range + (padding * 2)
                    
                    let chartInset: CGFloat = 16
                    let chartWidth = w - (chartInset * 2)
                    let chartHeight = h - 44 // Leave room for value badge
                    
                    let basePoints: [CGPoint] = data.enumerated().map { (index, value) in
                        let xPos = chartInset + chartWidth * CGFloat(index) / CGFloat(data.count - 1)
                        let yPos = 22 + chartHeight * (1 - CGFloat((value - adjustedMin) / adjustedRange))
                        return CGPoint(x: xPos, y: yPos)
                    }
                    
                    // Apply Catmull-Rom smoothing
                    let smoothPoints = catmullRomSmooth(basePoints, samplesPerSegment: 5)
                    
                    // Gradient area fill with smooth curve
                    if let first = smoothPoints.first, let last = smoothPoints.last {
                        Path { path in
                            path.move(to: CGPoint(x: first.x, y: h - 16))
                            path.addLine(to: first)
                            for p in smoothPoints.dropFirst() { path.addLine(to: p) }
                            path.addLine(to: CGPoint(x: last.x, y: h - 16))
                            path.closeSubpath()
                        }
                        .fill(
                            LinearGradient(
                                colors: [lineColor.opacity(0.25), lineColor.opacity(0.10), lineColor.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                    
                    // Outer glow layer
                    if let first = smoothPoints.first {
                        Path { path in
                            path.move(to: first)
                            for p in smoothPoints.dropFirst() { path.addLine(to: p) }
                        }
                        .trim(from: 0, to: drawProgress)
                        .stroke(lineColor.opacity(0.35), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    }
                    
                    // Inner glow layer
                    if let first = smoothPoints.first {
                        Path { path in
                            path.move(to: first)
                            for p in smoothPoints.dropFirst() { path.addLine(to: p) }
                        }
                        .trim(from: 0, to: drawProgress)
                        .stroke(lineColor.opacity(0.5), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    }
                    
                    // Main line
                    if let first = smoothPoints.first {
                        Path { path in
                            path.move(to: first)
                            for p in smoothPoints.dropFirst() { path.addLine(to: p) }
                        }
                        .trim(from: 0, to: drawProgress)
                        .stroke(
                            LinearGradient(
                                colors: [lineColor.opacity(0.8), lineColor, lineColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                        )
                    }
                    
                    // End dot with pulse (use original last point for accurate position)
                    if let last = basePoints.last {
                        // Outer pulse ring
                        Circle()
                            .stroke(lineColor.opacity(0.3), lineWidth: 2)
                            .frame(width: 18, height: 18)
                            .scaleEffect(pulseScale)
                            .opacity(2.2 - pulseScale)
                            .position(last)
                        
                        // Inner glow
                        Circle()
                            .fill(lineColor.opacity(0.4))
                            .frame(width: 14, height: 14)
                            .position(last)
                        
                        // Main dot
                        Circle()
                            .fill(lineColor)
                            .frame(width: 8, height: 8)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                            )
                            .position(last)
                        
                        // Value badge - position above or below based on y position
                        let badgeY = last.y < h / 2 ? last.y + 24 : last.y - 24
                        HStack(spacing: 4) {
                            Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 10, weight: .bold))
                            Text(String(format: "%+.1f%%", changePercent))
                                .font(.system(size: 11, weight: .semibold))
                                .monospacedDigit()
                        }
                        .foregroundColor(isPositive ? .green : .red)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.7))
                                .overlay(
                                    Capsule()
                                        .stroke(lineColor.opacity(0.5), lineWidth: 1)
                                )
                        )
                        .position(x: min(max(last.x, 45), w - 45), y: max(min(badgeY, h - 20), 20))
                    }
                } else {
                    // Placeholder
                    VStack(spacing: 8) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.3))
                        Text("No performance data")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 1.0)) {
                    drawProgress = 1.0
                }
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    pulseScale = 1.8
                }
            }
        }
    }
}

struct AllAIInsightsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = AIInsightViewModel()
    @EnvironmentObject var portfolioVM: PortfolioViewModel
    
    // Paper Trading support - observe the manager to get Paper Trading data
    @ObservedObject private var paperTradingManager = PaperTradingManager.shared
    
    // Helper for adaptive colors
    private var isDark: Bool { colorScheme == .dark }
    
    // Navigation state
    @State private var showUpgradeView = false
    
    // Check if paper trading mode is active
    private var isPaperTradingMode: Bool {
        paperTradingManager.isPaperTradingEnabled
    }
    
    // Check if we have real portfolio data (not demo mode or paper trading)
    private var hasRealPortfolioData: Bool {
        !portfolioVM.holdings.isEmpty && !DemoModeManager.shared.isDemoMode && !isPaperTradingMode
    }
    
    // Check if demo mode is active
    private var isDemoMode: Bool {
        DemoModeManager.shared.isDemoMode
    }
    
    // Check if user can access (Pro+ OR demo mode OR paper trading mode)
    private var canAccess: Bool {
        isDemoMode || isPaperTradingMode || SubscriptionManager.shared.hasTier(.pro) || !portfolioVM.holdings.isEmpty
    }
    
    // Check if should show locked state (free user, no demo, no paper trading, no portfolio)
    private var shouldShowLockedState: Bool {
        !isDemoMode && !isPaperTradingMode && !SubscriptionManager.shared.hasTier(.pro) && portfolioVM.holdings.isEmpty
    }
    
    // Check if should show empty state (has subscription but no data, not in demo or paper trading)
    private var shouldShowEmptyState: Bool {
        !isDemoMode && !isPaperTradingMode && portfolioVM.holdings.isEmpty && SubscriptionManager.shared.hasTier(.pro)
    }
    
    // Build portfolio object from current holdings
    private var currentPortfolio: Portfolio {
        Portfolio(holdings: portfolioVM.holdings, transactions: portfolioVM.transactions)
    }
    
    // MARK: - Paper Trading Data Helpers
    
    /// Get current market prices for Paper Trading calculations
    /// Uses live prices from MarketViewModel for accurate portfolio valuation
    /// BUG FIX: Now includes fallback to lastKnownPrices when live prices are unavailable (API rate limiting)
    /// NOTE: Does NOT update cache here to avoid "Publishing changes from within view updates" warnings
    /// PRICE CONSISTENCY FIX: Use bestPrice() for consistent pricing across all views
    private var paperTradingPrices: [String: Double] {
        var prices: [String: Double] = [:]
        
        // Get prices from MarketViewModel's live coin data
        // PRICE CONSISTENCY FIX: Use bestPrice() which checks LivePriceManager first
        for coin in MarketViewModel.shared.allCoins {
            let symbol = coin.symbol.uppercased()
            // Priority: bestPrice() > coin.priceUsd (fallback)
            if let price = MarketViewModel.shared.bestPrice(for: coin.id), price > 0 {
                prices[symbol] = price
            } else if let price = coin.priceUsd, price > 0 {
                prices[symbol] = price
            }
        }
        
        // Also check portfolioVM holdings for any prices not in market data
        for holding in portfolioVM.holdings {
            let symbol = holding.coinSymbol.uppercased()
            if (prices[symbol] == nil || prices[symbol] == 0) && holding.currentPrice > 0 {
                prices[symbol] = holding.currentPrice
            }
        }
        
        // FIX: Try bestPrice(forSymbol:) for assets not yet resolved
        for (asset, _) in paperTradingManager.paperBalances {
            let symbol = asset.uppercased()
            if prices[symbol] == nil || prices[symbol] == 0 {
                if let symbolPrice = MarketViewModel.shared.bestPrice(forSymbol: symbol), symbolPrice > 0 {
                    prices[symbol] = symbolPrice
                }
            }
        }
        
        // Fallback: For any assets still without live prices,
        // use lastKnownPrices — but only if fresh (< 30 min old)
        for (asset, _) in paperTradingManager.paperBalances {
            let symbol = asset.uppercased()
            if prices[symbol] == nil || prices[symbol] == 0 {
                if let cachedPrice = paperTradingManager.lastKnownPrices[symbol], cachedPrice > 0,
                   paperTradingManager.isCachedPriceFresh(for: symbol) {
                    prices[symbol] = cachedPrice
                }
            }
        }
        
        // Stablecoins are always 1:1 with USD
        prices["USDT"] = 1.0
        prices["USD"] = 1.0
        prices["USDC"] = 1.0
        
        return prices
    }
    
    /// Paper Trading total portfolio value for the pie chart center display
    /// Calculates total value using current market prices
    private var paperTradingTotalValue: Double {
        paperTradingManager.calculatePortfolioValue(prices: paperTradingPrices)
    }
    
    /// Paper Trading allocation data for the pie chart
    /// Converts Paper Trading balances to AllocationSlice format for ThemedPortfolioPieChartView
    /// Note: AllocationSlice.percent expects 0-100 scale (percentage), not 0-1 (ratio)
    private var paperTradingAllocationData: [PortfolioViewModel.AllocationSlice] {
        let prices = paperTradingPrices
        let totalValue = paperTradingManager.calculatePortfolioValue(prices: prices)
        guard totalValue > 0 else { return [] }
        
        return paperTradingManager.paperBalances
            .filter { $0.value > 0.000001 }
            .map { asset, amount in
                let value: Double
                if asset.uppercased() == "USDT" || asset.uppercased() == "USD" {
                    value = amount
                } else {
                    value = amount * (prices[asset.uppercased()] ?? 0)
                }
                // Convert to percentage (0-100 scale) for AllocationSlice
                let percentValue = (value / totalValue) * 100
                return PortfolioViewModel.AllocationSlice(
                    symbol: asset.uppercased(),
                    percent: percentValue,
                    color: portfolioVM.color(for: asset)
                )
            }
            .filter { $0.percent > 0.1 } // Filter out tiny allocations (< 0.1%)
            .sorted { $0.percent > $1.percent }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 1) Unified header with SubpageHeaderBar
            SubpageHeaderBar(
                title: "AI Insights",
                badge: modeBadgeText,
                badgeColor: modeBadgeColor,
                onDismiss: { dismiss() }
            ) {
                // Right side: Timestamp
                Text(SubpageHeaderBar<EmptyView>.currentTimestamp())
                    .font(.footnote)
                    .foregroundColor(DS.Adaptive.textTertiary)
            }

            // 2) Content based on state
            if shouldShowLockedState {
                // Free user with no portfolio - show upgrade prompt
                AIInsightsLockedState(
                    onUpgrade: { showUpgradeView = true },
                    onEnableDemo: { enableDemoMode() }
                )
            } else if shouldShowEmptyState {
                // Pro user but no portfolio data
                AIInsightsEmptyState(
                    onEnableDemo: { enableDemoMode() }
                )
            } else {
                // Has access - show full insights
                insightsContent
            }
        }
        .background(DS.Adaptive.background)
        .ignoresSafeArea(edges: .bottom)
        .foregroundColor(DS.Adaptive.textPrimary)
        .onAppear {
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                // Check if paper trading mode is active
                let isPaperTrading = PaperTradingManager.shared.isPaperTradingEnabled
                
                // Update viewModel with current portfolio state
                viewModel.updatePortfolioState(
                    hasData: !portfolioVM.holdings.isEmpty || isPaperTrading,
                    isDemoMode: DemoModeManager.shared.isDemoMode
                )
                
                // Load data based on current mode
                if DemoModeManager.shared.isDemoMode {
                    // Demo mode: load mock data
                    viewModel.loadMockIfNeeded()
                } else if isPaperTrading {
                    // Paper Trading mode: load REAL paper trading data
                    let prices = paperTradingPrices
                    viewModel.loadPaperTradingData(
                        paperManager: paperTradingManager,
                        prices: prices
                    )
                } else if !portfolioVM.holdings.isEmpty {
                    // Live Trading mode: load REAL portfolio data
                    let prices = paperTradingPrices // Reuse same price source
                    viewModel.loadLivePortfolioData(
                        holdings: portfolioVM.holdings,
                        transactions: portfolioVM.transactions,
                        prices: prices
                    )
                }
                // If no demo mode, no paper trading, and no portfolio data, viewModel will show empty state
            }
        }
        .onChange(of: paperTradingManager.paperBalances) { _, _ in
            // Update all paper trading data when balances change
            if isPaperTradingMode {
                let prices = paperTradingPrices
                viewModel.loadPaperTradingData(
                    paperManager: paperTradingManager,
                    prices: prices
                )
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        // NAVIGATION: Enable native iOS pop gesture + custom edge swipe
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
        .sheet(isPresented: $showUpgradeView) {
            NavigationStack {
                SubscriptionPricingView()
            }
        }
    }
    
    // Mode badge helpers — colors sourced from AppTradingMode (single source of truth)
    private var modeBadgeText: String? {
        if isPaperTradingMode { return AppTradingMode.paper.badgeLabel }
        if isDemoMode { return AppTradingMode.demo.badgeLabel }
        return nil
    }
    
    private var modeBadgeColor: Color {
        if isPaperTradingMode { return AppTradingMode.paper.color }
        if isDemoMode { return AppTradingMode.demo.color }
        return AppTradingMode.portfolio.color
    }
    
    // MARK: - Helper Methods
    
    private func enableDemoMode() {
        DemoModeManager.shared.enableDemoMode()
        portfolioVM.enableDemoMode()
        viewModel.updatePortfolioState(hasData: true, isDemoMode: true)
        viewModel.loadMockIfNeeded()
    }
    
    // MARK: - Main Insights Content
    
    private var insightsContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // AI summary hero card
                heroInsightCard

                // Summary cards with placeholder when loading
                summaryCardScroll

                // Performance & Attribution (custom expand/collapse)
                    expandableSection(
                        title: "Performance & Attribution",
                        isExpanded: $viewModel.isPerformanceExpanded
                    ) {
                        performanceContent
                    }

                    // Trade Quality & Timing (custom expand/collapse)
                    expandableSection(
                        title: "Trade Quality & Timing",
                        isExpanded: $viewModel.isQualityExpanded
                    ) {
                        qualityContent
                    }

                    // Diversification & Risk (custom expand/collapse)
                    expandableSection(
                        title: "Diversification & Risk",
                        isExpanded: $viewModel.isDiversificationExpanded
                    ) {
                        diversificationContent
                    }

                    // Momentum Analysis (custom expand/collapse)
                    expandableSection(
                        title: "Momentum Analysis",
                        isExpanded: $viewModel.isMomentumExpanded
                    ) {
                        momentumContent
                    }

                    // Fee Breakdown (custom expand/collapse)
                    expandableSection(
                        title: "Fee Breakdown",
                        isExpanded: $viewModel.isFeeExpanded
                    ) {
                        feeContent
                    }

                    Spacer(minLength: 100)
                }
                .padding(.top, 10)
                .padding(.bottom, 20)
            }
            // PERFORMANCE FIX v21: UIKit scroll bridge for snappier deceleration + animation freeze
            .withUIKitScrollBridge()
    }
}


// MARK: - COMPONENTS
private extension AllAIInsightsView {
    
    // Derive lightweight tags from the current insight text
    func insightTags() -> [String] {
        let t = (viewModel.insight?.text ?? "").lowercased()
        var tags: [String] = []
        if t.contains("diversif") { tags.append("Diversification") }
        if t.contains("momentum") { tags.append("Momentum") }
        if t.contains("risk") { tags.append("Risk") }
        if t.contains("rebalance") || t.contains("trim") { tags.append("Rebalance") }
        return Array(tags.prefix(3))
    }
    
    // MARK: - Expandable Section Helper
    
    /// Reusable expandable section with consistent styling
    @ViewBuilder
    func expandableSection<Content: View>(
        title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.wrappedValue.toggle()
                }
            }) {
                sectionHeader(title: title)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .buttonStyle(GlassPressStyle())

            if isExpanded.wrappedValue {
                content()
                    .padding(.top, 8)
                    .padding(.horizontal, 16)
            }
        }
    }
    
    // Responsive summary metric cards (3-up layout that fits all devices)
    var summaryCardScroll: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 12
            let horizontalPadding: CGFloat = 16
            let cardCount: CGFloat = 3
            let availableWidth = geometry.size.width - (horizontalPadding * 2)
            let cardWidth = (availableWidth - (spacing * (cardCount - 1))) / cardCount
            
            HStack(spacing: spacing) {
                if viewModel.summaryMetrics.isEmpty {
                    ForEach(0..<3, id: \.self) { _ in
                        SummaryMetricSkeleton(cardWidth: cardWidth)
                    }
                } else {
                    ForEach(viewModel.summaryMetrics, id: \.id) { metric in
                        SummaryMetricCard(metric: metric, cardWidth: cardWidth)
                            .buttonStyle(.plain)
                            .transition(.opacity.combined(with: .scale))
                    }
                }
            }
            .padding(.horizontal, horizontalPadding)
        }
        .frame(height: 128)
        .padding(.bottom, 8)
    }
    
    // Premium AI summary hero card
    var heroInsightCard: some View {
        HStack(alignment: .top, spacing: 10) {
            // Simplified 3px gold accent bar
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            BrandColors.goldLight.opacity(isDark ? 0.8 : 0.7),
                            BrandColors.goldBase.opacity(isDark ? 0.6 : 0.5)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 3)
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 10) {
                // Header row with title, badge, and refresh button
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14))
                            .foregroundStyle(isDark ? AnyShapeStyle(BrandColors.goldHorizontal) : AnyShapeStyle(BrandColors.goldBase))
                        Text("AI Summary")
                            .font(.subheadline.bold())
                            .foregroundColor(DS.Adaptive.textPrimary)
                    }
                    
                    if viewModel.remainingRefreshes >= 0 {
                        Text("\(max(viewModel.remainingRefreshes, 0)) left")
                            .font(.caption2.bold())
                            .foregroundColor(DS.Adaptive.textSecondary)
                            .padding(.vertical, 2)
                            .padding(.horizontal, 6)
                            .background(Capsule().fill(DS.Adaptive.chipBackground))
                            .overlay(Capsule().stroke(DS.Adaptive.stroke, lineWidth: 0.5))
                    }
                    
                    Spacer(minLength: 0)
                    
                    // Compact refresh button inline with header
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: DS.Adaptive.gold))
                            .scaleEffect(0.8)
                            .frame(width: 24, height: 24)
                    } else {
                        Button {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            Task {
                                // Route to appropriate refresh method based on mode
                                if isDemoMode {
                                    // Demo mode: cycle through demo insights (no API calls)
                                    await viewModel.refreshDemoMode()
                                } else if isPaperTradingMode {
                                    // Paper Trading mode: use real AI with paper trading data
                                    let prices = paperTradingPrices
                                    await viewModel.refreshPaperTradingMode(
                                        paperManager: paperTradingManager,
                                        prices: prices
                                    )
                                } else if hasRealPortfolioData {
                                    // Real portfolio: use real AI with live portfolio data
                                    await viewModel.refresh(using: currentPortfolio)
                                } else {
                                    // No data - show appropriate message
                                    viewModel.showNoPortfolioError()
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 10, weight: .bold))
                                Text("Refresh")
                                    .font(.caption2.bold())
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 10)
                            .foregroundColor(TintedChipStyle.selectedText(isDark: isDark))
                            .tintedCapsuleChip(isSelected: true, isDark: isDark)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Main insight text
                Text(viewModel.insight?.text ?? "Tap Refresh for a fresh read on your portfolio.")
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textPrimary.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .lineSpacing(2)

                // Timestamp and tags row
                HStack(spacing: 10) {
                    if let ts = viewModel.insight?.timestamp {
                        Text("Updated \(ts.shortRelativeString)")
                            .font(.caption2)
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                    
                    let tags = insightTags()
                    if !tags.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(tags, id: \.self) { PillTag(text: $0) }
                        }
                    }
                    
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 14)
        .contextMenu {
            if let text = viewModel.insight?.text {
                Button {
                    #if os(iOS)
                    UIPasteboard.general.string = text
                    #endif
                } label: {
                    Label("Copy Insight", systemImage: "doc.on.doc")
                }
            }
        }
    }
    
    // Single summary card (icon + value + label)
    func summaryCard(metric: SummaryMetric) -> some View {
        SummaryMetricCard(metric: metric)
    }
    
    // Standard header for each DisclosureGroup
    func sectionHeader(title: String) -> some View {
        let expanded = isSectionExpanded(title)
        return HStack(spacing: 12) {
            // Simplified 3px gold accent bar when expanded
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            BrandColors.goldLight.opacity(isDark ? 0.8 : 0.7),
                            BrandColors.goldBase.opacity(isDark ? 0.6 : 0.5)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 3, height: 20)
                .opacity(expanded ? 1 : 0)
                .animation(.easeInOut(duration: 0.18), value: expanded)

            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
                .lineLimit(1)

            Spacer()

            Image(systemName: "chevron.right")
                .rotationEffect(.degrees(expanded ? 90 : 270))
                .animation(.easeInOut(duration: 0.2), value: expanded)
                .font(.caption.weight(.semibold))
                .foregroundColor(DS.Adaptive.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassCard()
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            BrandColors.goldLight.opacity(isDark ? 0.5 : 0.4),
                            BrandColors.goldBase.opacity(isDark ? 0.3 : 0.25)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: expanded ? 1 : 0
                )
                .opacity(expanded ? 0.6 : 0)
                .animation(.easeInOut(duration: 0.18), value: expanded)
        )
        .overlay(
            // A faint top gloss for depth
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [isDark ? Color.white.opacity(0.12) : Color.white.opacity(0.5), .clear], startPoint: .top, endPoint: .center))
                .allowsHitTesting(false)
        )
    }
    
    // Helper to toggle the chevron direction
    func isSectionExpanded(_ title: String) -> Bool {
        switch title {
        case "Performance & Attribution": return viewModel.isPerformanceExpanded
        case "Trade Quality & Timing":   return viewModel.isQualityExpanded
        case "Diversification & Risk":    return viewModel.isDiversificationExpanded
        case "Momentum Analysis":         return viewModel.isMomentumExpanded
        case "Fee Breakdown":             return viewModel.isFeeExpanded
        default:                          return false
        }
    }
    
    // Performance & Attribution content
    var performanceContent: some View {
        VStack(spacing: 16) {
            // Premium performance sparkline chart
            PremiumPerformanceChart(
                data: viewModel.performanceData,
                isPositive: viewModel.performancePositive
            )
            .frame(height: 160)

            VStack(alignment: .leading, spacing: 6) {
                Text("Top Contributors")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textSecondary)

                ForEach(viewModel.contributors) { contributor in
                    ContributionRow(name: contributor.name, pct: contributor.contribution)
                }

                Text(performanceAttributionFooter)
                    .font(.caption2)
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassCard()
    }
    
    // Performance attribution footer text based on mode
    private var performanceAttributionFooter: String {
        if isDemoMode {
            return "Demo mode - showing sample performance data"
        } else if isPaperTradingMode {
            return "Attribution window: paper trading performance since start"
        } else {
            return "Attribution window: last 30 days of realized P/L"
        }
    }
    
    // Trade Quality & Timing content
    var qualityContent: some View {
        VStack(spacing: 12) {
            if viewModel.tradeQualityData != nil {
                tradeQualityDataContent
            } else {
                TradeQualityEmptyState(isPaperTrading: isPaperTradingMode)
            }
        }
        .padding(.horizontal, 16)
        .glassCard()
    }
    
    @ViewBuilder
    private var tradeQualityDataContent: some View {
        // Determine if showing unrealized P&L (open positions) vs realized (completed trades)
        let isUnrealized = viewModel.tradeQualityData?.isUnrealized ?? false
        let bestLabel = isUnrealized ? "Best Position" : "Best Trade"
        let worstLabel = isUnrealized ? "Worst Position" : "Worst Trade"
        
        HStack(spacing: 12) {
            // Best/Worst Trade Card
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(bestLabel).font(.caption).foregroundColor(DS.Adaptive.textSecondary)
                    Image(systemName: "arrow.up.right.circle.fill").foregroundColor(.green)
                        .font(.caption)
                }
                let bestSym = viewModel.tradeQualityData?.bestTrade.symbol ?? "---"
                let bestPct = viewModel.tradeQualityData?.bestTrade.profitPct ?? 0
                HStack(spacing: 6) {
                    Text("\(bestSym):")
                        .font(.subheadline)
                        .foregroundColor(DS.Adaptive.textPrimary)
                    Text(String(format: "%.1f%%", bestPct))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(bestPct >= 0 ? .green : .red)
                }

                Spacer(minLength: 6)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(worstLabel).font(.caption).foregroundColor(DS.Adaptive.textSecondary)
                    Image(systemName: "arrow.down.right.circle.fill").foregroundColor(.red)
                        .font(.caption)
                }
                let worstSym = viewModel.tradeQualityData?.worstTrade.symbol ?? "---"
                let worstPct = viewModel.tradeQualityData?.worstTrade.profitPct ?? 0
                HStack(spacing: 6) {
                    Text("\(worstSym):")
                        .font(.subheadline)
                        .foregroundColor(DS.Adaptive.textPrimary)
                    Text(String(format: "%.1f%%", worstPct))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(worstPct >= 0 ? .green : .red)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 120)
            .glassCard()

            // Premium P/L Distribution Histogram
            VStack(alignment: .center, spacing: 8) {
                Text(isUnrealized ? "Unrealized P/L" : "P/L Distribution")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    
                    let bins = viewModel.tradeQualityData?.histogramBins ?? []
                    let maxBin = bins.max() ?? 1
                    
                    GeometryReader { geo in
                        let barWidth: CGFloat = max(12, (geo.size.width - CGFloat(bins.count - 1) * 6) / CGFloat(max(1, bins.count)))
                        let maxHeight = geo.size.height - 20 // Leave room for labels
                        
                        HStack(alignment: .bottom, spacing: 6) {
                            ForEach(bins.indices, id: \.self) { idx in
                                let count = bins[idx]
                                let heightRatio = maxBin > 0 ? CGFloat(count) / CGFloat(maxBin) : 0
                                let barHeight = max(4, heightRatio * maxHeight)
                                
                                VStack(spacing: 2) {
                                    // Value label above bar
                                    Text("\(count)")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(DS.Adaptive.textSecondary)
                                        .opacity(count > 0 ? 1 : 0)
                                    
                                    // Premium bar with gradient and glow
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color(red: 1.0, green: 0.85, blue: 0.4),
                                                    Color(red: 0.95, green: 0.75, blue: 0.3),
                                                    Color(red: 0.85, green: 0.65, blue: 0.2)
                                                ],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .frame(width: barWidth, height: barHeight)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                                .fill(
                                                    LinearGradient(
                                                        colors: [Color.white.opacity(0.3), Color.clear],
                                                        startPoint: .top,
                                                        endPoint: .center
                                                    )
                                                )
                                        )
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    }
                    .frame(height: 85)
                    
                    // X-axis labels
                    HStack {
                        Text("Loss")
                            .font(.system(size: 8))
                            .foregroundColor(.red.opacity(0.7))
                        Spacer()
                        Text("Gain")
                            .font(.system(size: 8))
                            .foregroundColor(.green.opacity(0.7))
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 140)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [DS.Adaptive.gold.opacity(0.2), DS.Adaptive.gold.opacity(0.05)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                )
                .glassCard()
        }
    }
    
    // Diversification & Risk content
    var diversificationContent: some View {
        VStack(spacing: 12) {
            if let weights = viewModel.diversificationData?.percentages, !weights.isEmpty {
                diversificationChartSection(weights: weights)
            } else {
                DiversificationEmptyState(isPaperTrading: isPaperTradingMode)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassCard()
    }
    
    @ViewBuilder
    private func diversificationChartSection(weights: [AssetWeight]) -> some View {
        // Pass Paper Trading allocation data and total value when in Paper Trading mode
        // This ensures the pie chart displays actual Paper Trading balances and correct center value
        ThemedPortfolioPieChartView(
            portfolioVM: portfolioVM,
            showLegend: .constant(false),
            overrideAllocationData: isPaperTradingMode ? paperTradingAllocationData : nil,
            overrideTotalValue: isPaperTradingMode ? paperTradingTotalValue : nil
        )
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 10))

        if let topAsset = weights.max(by: { $0.weight < $1.weight }), topAsset.weight > 0.6 {
            concentrationWarningBadge(asset: topAsset.asset, weight: topAsset.weight)
        } else {
            healthyDiversificationBadge
        }
    }
    
    private func concentrationWarningBadge(asset: String, weight: Double) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(DS.Adaptive.gold)
            Text("Concentration: \(Int(weight * 100))% in \(asset)")
                .font(.caption)
                .foregroundColor(DS.Adaptive.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassCard(cornerRadius: 8)
    }
    
    private var healthyDiversificationBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(isDark ? AnyShapeStyle(BrandColors.goldHorizontal) : AnyShapeStyle(BrandColors.goldBase))
            Text("Diversification levels are healthy.")
                .font(.caption)
                .foregroundColor(DS.Adaptive.textPrimary.opacity(0.8))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassCard(cornerRadius: 8)
    }
    
    // Momentum Analysis content (refined)
    var momentumContent: some View {
        VStack(spacing: 16) {
            if viewModel.momentumData != nil {
                momentumDataContent
            } else {
                MomentumEmptyState(isPaperTrading: isPaperTradingMode)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassCard()
    }
    
    @ViewBuilder
    private var momentumDataContent: some View {
        HStack {
            Text("Momentum Scores")
                .font(.subheadline.bold())
                .foregroundColor(DS.Adaptive.textPrimary)
            Spacer()
            // Legend
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text("Score")
                    .font(.caption2)
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
        }

        GeometryReader { geo in
            let strategies = viewModel.momentumData?.strategies ?? []
            let maxScore = strategies.map { $0.score }.max() ?? 1
            let chartHeight = geo.size.height - 40 // Leave room for labels
            
            ZStack {
                // Grid lines with labels
                ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { fraction in
                    let yPos = chartHeight * (1 - CGFloat(fraction)) + 10
                    HStack(spacing: 4) {
                        Text("\(Int(fraction * 100))")
                            .font(.system(size: 8))
                            .foregroundColor(DS.Adaptive.textTertiary)
                            .frame(width: 20, alignment: .trailing)
                        
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: 0))
                            path.addLine(to: CGPoint(x: geo.size.width - 28, y: 0))
                        }
                        .stroke(
                            DS.Adaptive.divider.opacity(fraction == 0.5 ? 0.3 : 0.15),
                            style: StrokeStyle(lineWidth: fraction == 0.5 ? 0.8 : 0.5, dash: [4, 4])
                        )
                    }
                    .position(x: geo.size.width / 2, y: yPos)
                }
                
                // Bars
                HStack(alignment: .bottom, spacing: 0) {
                    Spacer(minLength: 28)
                    ForEach(strategies) { strategy in
                        let heightRatio = maxScore > 0 ? CGFloat(strategy.score) / CGFloat(maxScore) : 0
                        let barHeight = max(8, heightRatio * chartHeight)
                        
                        VStack(spacing: 6) {
                            // Score label above bar
                            Text(String(format: "%.0f", strategy.score * 100))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(DS.Adaptive.textPrimary)
                            
                            // Premium gradient bar
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.green.opacity(0.95),
                                            Color.green,
                                            Color(red: 0.1, green: 0.6, blue: 0.3)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: 48, height: barHeight)
                                .overlay(
                                    // Top highlight
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.white.opacity(0.35), Color.clear],
                                                startPoint: .top,
                                                endPoint: .center
                                            )
                                        )
                                )
                                .overlay(
                                    // Border
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(Color.green.opacity(0.4), lineWidth: 0.5)
                                )
                            
                            // Strategy label (multiline to prevent truncation)
                            Text(strategy.name)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(DS.Adaptive.textSecondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                    .minimumScaleFactor(0.8)
                                    .frame(width: 65)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        Spacer(minLength: 4)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 8)
                }
        }
        .frame(height: 200)
    }
    
    // Fee Breakdown content
    var feeContent: some View {
        VStack(spacing: 10) {
            if let fees = viewModel.feeData?.fees, !fees.isEmpty {
                let maxFee = fees.map { $0.pct }.max() ?? 0
                ForEach(fees) { feeItem in
                    FeeRow(label: feeItem.label, pct: feeItem.pct, maxPct: maxFee)
                }
                
                // Mode-specific footer text
                Text(feeFooterText)
                    .font(.caption2)
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            } else {
                // Empty state for fee section
                FeeEmptyState(isPaperTrading: isPaperTradingMode)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassCard()
    }
    
    // Fee footer text based on mode
    private var feeFooterText: String {
        if isDemoMode {
            return "Demo mode - showing sample fee structure"
        } else if isPaperTradingMode {
            return "Estimated fees based on typical exchange rates (paper trading)"
        } else {
            return "Fees calculated from your transaction history"
        }
    }
}





// MARK: - DATEFORMATTER EXTENSION
fileprivate extension DateFormatter {
    static let shortTime: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "h:mm a"
        return df
    }()
}

fileprivate extension Date {
    var shortRelativeString: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: self, relativeTo: Date())
    }
}


// MARK: - PREVIEW
struct AllAIInsightsView_Previews: PreviewProvider {
    static var previews: some View {
        let portfolioVM = PortfolioViewModel(repository: PortfolioRepository())
        
        Group {
            AllAIInsightsView()
                .environmentObject(portfolioVM)
                .preferredColorScheme(.dark)
            
            AllAIInsightsView()
                .environmentObject(portfolioVM)
                .preferredColorScheme(.light)
        }
    }
}

