import SwiftUI

struct RiskReportView: View {
    let result: RiskScanResult?
    var lastScanned: Date?
    
    @Environment(\.dismiss) private var dismiss
    
    // Animation states
    @State private var scoreAnimated = false
    @State private var ringProgress: CGFloat = 0
    @State private var headerAppeared = false
    @State private var highlightsAppeared: [Bool] = []
    @State private var metricsAppeared = false
    @State private var recommendationsAppeared = false
    
    private let goldLight = BrandColors.goldLight
    private let goldBase = BrandColors.goldBase
    
    var body: some View {
        NavigationView {
            ZStack {
                // Premium background gradient
                backgroundGradient
                
                VStack(spacing: 0) {
                    if let result = result {
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 20) {
                                // Animated Score Section
                                scoreSection(result: result)
                                    .padding(.top, 8)
                                
                                // Highlights Section
                                highlightsSection(highlights: result.highlights)
                                
                                // Metrics Section
                                metricsSection(result: result)
                                
                                // Recommendations
                                recommendationsSection(result: result)
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 32)
                        }
                        .scrollViewBackSwipeFix()
                    } else {
                        placeholderView
                            .padding()
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .navigationTitle("Risk Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .fontWeight(.semibold)
                            .foregroundStyle(goldLight)
                    }
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            // Initialize highlight animation states
            if let result = result {
                highlightsAppeared = Array(repeating: false, count: result.highlights.count)
            }
            
            // Trigger entrance animations
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    headerAppeared = true
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeOut(duration: 1.2)) {
                    ringProgress = CGFloat(result?.score ?? 0) / 100
                    scoreAnimated = true
                }
            }
            
            // Stagger highlights
            for i in 0..<(result?.highlights.count ?? 0) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + Double(i) * 0.1) {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        if i < highlightsAppeared.count {
                            highlightsAppeared[i] = true
                        }
                    }
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    metricsAppeared = true
                }
            }
            
            // Recommendations appear last
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    recommendationsAppeared = true
                }
            }
        }
    }
    
    // MARK: - Background
    private var backgroundGradient: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Subtle radial gradient from top
            RadialGradient(
                colors: [
                    goldBase.opacity(0.08),
                    Color.clear
                ],
                center: .top,
                startRadius: 0,
                endRadius: 400
            )
            .ignoresSafeArea()
            
            // Risk-colored accent at bottom
            if let result = result {
                RadialGradient(
                    colors: [
                        riskColor(for: result.level).opacity(0.1),
                        Color.clear
                    ],
                    center: .bottom,
                    startRadius: 0,
                    endRadius: 300
                )
                .ignoresSafeArea()
            }
        }
    }
    
    // MARK: - Score Section
    private func scoreSection(result: RiskScanResult) -> some View {
        VStack(spacing: 16) {
            // Large animated ring
            ZStack {
                // Background ring
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 12)
                    .frame(width: 140, height: 140)
                
                // Animated progress ring
                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                riskColor(for: result.level).opacity(0.6),
                                riskColor(for: result.level),
                                riskColor(for: result.level).opacity(0.8)
                            ]),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(-90))
                
                // Score display
                VStack(spacing: 4) {
                    Text("\(result.score)")
                        .font(.system(size: 48, weight: .bold).monospacedDigit())
                        .foregroundStyle(riskColor(for: result.level))
                    
                    Text(result.level.rawValue.uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .scaleEffect(scoreAnimated ? 1 : 0.8)
                .opacity(scoreAnimated ? 1 : 0)
            }
            .opacity(headerAppeared ? 1 : 0)
            .scaleEffect(headerAppeared ? 1 : 0.9)
            
            // Risk level description
            VStack(spacing: 6) {
                Text(riskDescription(for: result.level))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                // Last scanned timestamp
                if let scanned = lastScanned {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.caption2)
                        Text("Scanned \(relativeTimeString(from: scanned))")
                            .font(.caption2)
                    }
                    .foregroundStyle(goldBase.opacity(0.7))
                }
            }
            .opacity(headerAppeared ? 1 : 0)
        }
        .padding(.vertical, 20)
    }
    
    private func relativeTimeString(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        return "\(days)d ago"
    }
    
    // MARK: - Highlights Section
    private func highlightsSection(highlights: [RiskHighlight]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Risk Highlights", icon: "exclamationmark.triangle.fill")
            
            if highlights.isEmpty {
                emptyHighlightsCard
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(highlights.enumerated()), id: \.offset) { index, highlight in
                        highlightCard(highlight: highlight, index: index)
                    }
                }
            }
        }
    }
    
    private var emptyHighlightsCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.title2)
                .foregroundStyle(.green)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("No Major Risks Detected")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Your portfolio appears well-balanced")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(16)
        .background(cardBackground)
    }
    
    private func highlightCard(highlight: RiskHighlight, index: Int) -> some View {
        let appeared = index < highlightsAppeared.count ? highlightsAppeared[index] : false
        
        return HStack(spacing: 12) {
            // Severity indicator
            Circle()
                .fill(riskColor(for: highlight.severity))
                .frame(width: 10, height: 10)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(highlight.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                
                Text(highlight.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            SeverityPill(severity: highlight.severity)
        }
        .padding(16)
        .background(cardBackground)
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : -30)
    }
    
    // MARK: - Metrics Section
    private func metricsSection(result: RiskScanResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Portfolio Metrics", icon: "chart.bar.fill")
            
            VStack(spacing: 12) {
                // Row 1
                HStack(spacing: 12) {
                    metricCard(
                        label: "Top Holding",
                        value: formatPercent(result.metrics.topWeight),
                        icon: "chart.pie.fill",
                        status: result.metrics.topWeight > 0.4 ? .warning : .good
                    )
                    metricCard(
                        label: "HHI Index",
                        value: formatNumber(result.metrics.hhi),
                        icon: "square.grid.3x3.fill",
                        status: result.metrics.hhi > 0.25 ? .warning : .good
                    )
                }
                
                // Row 2
                HStack(spacing: 12) {
                    metricCard(
                        label: "Stablecoin",
                        value: formatPercent(result.metrics.stablecoinWeight),
                        icon: "dollarsign.circle.fill",
                        status: .neutral
                    )
                    metricCard(
                        label: "Volatility",
                        value: formatPercent(result.metrics.volatility),
                        icon: "waveform.path.ecg",
                        status: result.metrics.volatility > 0.05 ? .warning : .good
                    )
                }
                
                // Row 3
                HStack(spacing: 12) {
                    metricCard(
                        label: "Max Drawdown",
                        value: formatPercent(result.metrics.maxDrawdown),
                        icon: "arrow.down.to.line",
                        status: result.metrics.maxDrawdown > 0.2 ? .warning : .good
                    )
                    metricCard(
                        label: "Illiquid Assets",
                        value: "\(result.metrics.illiquidCount)",
                        icon: "drop.fill",
                        status: result.metrics.illiquidCount > 0 ? .warning : .good
                    )
                }
            }
            .opacity(metricsAppeared ? 1 : 0)
            .offset(y: metricsAppeared ? 0 : 20)
        }
    }
    
    private enum MetricStatus {
        case good, warning, neutral
        
        var color: Color {
            switch self {
            case .good: return .green
            case .warning: return .yellow
            case .neutral: return .gray
            }
        }
    }
    
    private func metricCard(label: String, value: String, icon: String, status: MetricStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(goldLight.opacity(0.8))
                
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            HStack {
                Text(value)
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                
                Spacer()
                
                Circle()
                    .fill(status.color)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }
    
    // MARK: - Recommendations Section
    private func recommendationsSection(result: RiskScanResult) -> some View {
        let hasAIRecommendations = result.aiRecommendations != nil && !(result.aiRecommendations?.isEmpty ?? true)
        let recs = hasAIRecommendations ? (result.aiRecommendations ?? []) : algorithmicRecommendations(for: result)
        
        return VStack(alignment: .leading, spacing: 12) {
            // Header with AI badge if applicable
            HStack(spacing: 8) {
                sectionHeader(title: "Recommendations", icon: "lightbulb.fill")
                
                if hasAIRecommendations {
                    aiBadge
                }
            }
            .opacity(recommendationsAppeared ? 1 : 0)
            
            // AI Summary if available
            if let aiSummary = result.aiAnalysis, !aiSummary.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(goldLight)
                    
                    Text(aiSummary)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .italic()
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(goldBase.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(goldBase.opacity(0.15), lineWidth: 1)
                        )
                )
                .opacity(recommendationsAppeared ? 1 : 0)
            }
            
            VStack(spacing: 8) {
                ForEach(Array(recs.enumerated()), id: \.offset) { index, rec in
                    HStack(spacing: 12) {
                        Image(systemName: hasAIRecommendations ? "sparkles" : "arrow.right.circle.fill")
                            .font(.caption)
                            .foregroundStyle(goldLight)
                        
                        Text(rec)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.9))
                        
                        Spacer()
                    }
                    .padding(14)
                    .background(cardBackground)
                    .opacity(recommendationsAppeared ? 1 : 0)
                    .offset(y: recommendationsAppeared ? 0 : 15)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.08), value: recommendationsAppeared)
                }
            }
        }
    }
    
    /// AI badge indicator
    private var aiBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .bold))
            Text("AI")
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(goldLight)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(goldBase.opacity(0.15))
                .overlay(
                    Capsule()
                        .stroke(goldBase.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    /// Fallback algorithmic recommendations when AI is not available
    private func algorithmicRecommendations(for result: RiskScanResult) -> [String] {
        var recs: [String] = []
        
        if result.metrics.topWeight > 0.35 {
            recs.append("Consider diversifying your largest holding")
        }
        if result.metrics.stablecoinWeight < 0.1 {
            recs.append("Add stablecoins to reduce portfolio volatility")
        }
        if result.metrics.volatility > 0.03 {
            recs.append("Your portfolio has high volatility exposure")
        }
        if result.metrics.illiquidCount > 0 {
            recs.append("Review your illiquid assets for exit strategy")
        }
        
        if recs.isEmpty {
            recs.append("Portfolio is well-diversified. Keep monitoring!")
        }
        
        return recs
    }
    
    // MARK: - Helper Views
    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(goldLight)
            
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
        }
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
    
    private var placeholderView: some View {
        VStack(spacing: 16) {
            Image(systemName: "shield.slash")
                .font(.system(size: 60, weight: .medium))
                .foregroundStyle(goldLight.opacity(0.5))
            
            Text("No Scan Results")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            
            Text("Run a risk scan to see detailed analysis and personalized recommendations.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Helpers
    private func riskColor(for level: RiskLevel) -> Color {
        switch level {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .red
        }
    }
    
    private func riskDescription(for level: RiskLevel) -> String {
        switch level {
        case .low: return "Your portfolio has low overall risk exposure"
        case .medium: return "Some risk factors require your attention"
        case .high: return "Your portfolio has significant risk exposure"
        }
    }
    
    private func formatPercent(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }
    
    private func formatNumber(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.2f", value)
        }
    }
}

// MARK: - Severity Pill
fileprivate struct SeverityPill: View {
    let severity: RiskLevel
    
    private var color: Color {
        switch severity {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .red
        }
    }
    
    private var label: String {
        switch severity {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
    
    var body: some View {
        Text(label)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(color.opacity(0.2))
                    .overlay(
                        Capsule()
                            .stroke(color.opacity(0.4), lineWidth: 1)
                    )
            )
            .foregroundColor(color)
    }
}

#Preview {
    let sample = RiskScanResult(
        score: 73,
        level: .medium,
        highlights: [
            RiskHighlight(title: "Elevated Concentration", detail: "Top holding is 40% of portfolio", severity: .medium),
            RiskHighlight(title: "High Volatility Exposure", detail: "Recent price swings above average", severity: .high),
            RiskHighlight(title: "Low Diversification", detail: "HHI index suggests concentration", severity: .medium)
        ],
        metrics: RiskMetrics(topWeight: 0.42, hhi: 0.28, stablecoinWeight: 0.15, volatility: 0.027, maxDrawdown: 0.35, illiquidCount: 2)
    )
    return RiskReportView(result: sample, lastScanned: Date())
}
