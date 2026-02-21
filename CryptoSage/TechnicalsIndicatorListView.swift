import SwiftUI

// MARK: - Indicator Category
enum IndicatorCategory: String, CaseIterable {
    case oscillators = "Oscillators"
    case movingAverages = "Moving Averages"
    case trend = "Trend"
    
    var icon: String {
        switch self {
        case .oscillators: return "waveform.path"
        case .movingAverages: return "chart.line.uptrend.xyaxis"
        case .trend: return "arrow.up.right.and.arrow.down.left"
        }
    }
    
    static func category(for label: String) -> IndicatorCategory {
        let lower = label.lowercased()
        
        // Moving Averages
        if lower.contains("sma") || lower.contains("ema") || lower.hasPrefix("ma") ||
           lower.contains("moving average") || lower.contains("ema12>ema26") ||
           lower.contains("hull") || lower.contains("vwma") {
            return .movingAverages
        }
        
        // Oscillators
        if lower.contains("rsi") || lower.contains("macd") || lower.contains("stoch") ||
           lower.contains("cci") || lower.contains("momentum") || lower.contains("williams") ||
           lower.contains("ultimate") || lower.contains("awesome") || lower.contains("bull") ||
           lower.contains("bear") || lower.contains("adx") || lower.contains("+di") ||
           lower.contains("-di") || lower.contains("ao") {
            return .oscillators
        }
        
        // Trend (default for others like Bollinger, Ichimoku, etc.)
        return .trend
    }
}

// MARK: - Grouped Indicator List View
struct TechnicalsIndicatorListView: View {
    let indicators: [IndicatorSignal]
    
    @State private var expandedCategories: Set<IndicatorCategory> = Set(IndicatorCategory.allCases)
    
    private func color(for s: IndicatorSignalStrength) -> Color {
        switch s {
        case .sell: return .red
        case .neutral: return .yellow
        case .buy: return .green
        }
    }
    
    private var groupedIndicators: [(category: IndicatorCategory, items: [IndicatorSignal])] {
        var groups: [IndicatorCategory: [IndicatorSignal]] = [:]
        
        for indicator in indicators {
            let category = IndicatorCategory.category(for: indicator.label)
            groups[category, default: []].append(indicator)
        }
        
        // Return in consistent order
        return IndicatorCategory.allCases.compactMap { category in
            guard let items = groups[category], !items.isEmpty else { return nil }
            return (category: category, items: items)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(groupedIndicators, id: \.category) { group in
                IndicatorCategorySection(
                    category: group.category,
                    indicators: group.items,
                    isExpanded: expandedCategories.contains(group.category),
                    onToggle: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            if expandedCategories.contains(group.category) {
                                expandedCategories.remove(group.category)
                            } else {
                                expandedCategories.insert(group.category)
                            }
                        }
                    }
                )
            }
        }
    }
}

// MARK: - Category Section
private struct IndicatorCategorySection: View {
    let category: IndicatorCategory
    let indicators: [IndicatorSignal]
    let isExpanded: Bool
    let onToggle: () -> Void
    
    private var sellCount: Int { indicators.filter { $0.signal == .sell }.count }
    private var neutralCount: Int { indicators.filter { $0.signal == .neutral }.count }
    private var buyCount: Int { indicators.filter { $0.signal == .buy }.count }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Category Header
            Button(action: {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                onToggle()
            }) {
                HStack(spacing: 10) {
                    // Category icon
                    Image(systemName: category.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textSecondary)
                        .frame(width: 20)
                    
                    Text(category.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Spacer()
                    
                    // Signal counts
                    HStack(spacing: 6) {
                        SignalCountBadge(count: sellCount, signal: .sell)
                        SignalCountBadge(count: neutralCount, signal: .neutral)
                        SignalCountBadge(count: buyCount, signal: .buy)
                    }
                    
                    // Chevron
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DS.Adaptive.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(DS.Adaptive.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(DS.Adaptive.stroke, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            
            // Expandable indicator rows
            if isExpanded {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(indicators.enumerated()), id: \.element.id) { index, indicator in
                        IndicatorRow(indicator: indicator, index: index)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity
                            ))
                    }
                }
                .padding(.top, 6)
                .padding(.horizontal, 2)
            }
        }
    }
}

// MARK: - Signal Count Badge
private struct SignalCountBadge: View {
    let count: Int
    let signal: IndicatorSignalStrength
    
    private var color: Color {
        switch signal {
        case .sell: return .red
        case .neutral: return .yellow
        case .buy: return .green
        }
    }
    
    var body: some View {
        if count > 0 {
            Text("\(count)")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundColor(color)
                .frame(minWidth: 18)
                .padding(.vertical, 3)
                .padding(.horizontal, 6)
                .background(
                    Capsule()
                        .fill(color.opacity(0.15))
                )
                .overlay(
                    Capsule()
                        .stroke(color.opacity(0.3), lineWidth: 0.5)
                )
        }
    }
}

// MARK: - Individual Indicator Row with Signal Bar
private struct IndicatorRow: View {
    let indicator: IndicatorSignal
    let index: Int
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var appeared = false
    
    private var isDark: Bool { colorScheme == .dark }
    
    private var signalColor: Color {
        switch indicator.signal {
        case .sell: return .red
        case .neutral: return .yellow
        case .buy: return .green
        }
    }
    
    // Compute signal bar fill percentage (0 to 1)
    private var signalFillPercent: CGFloat {
        switch indicator.signal {
        case .sell: return 0.35
        case .neutral: return 0.5
        case .buy: return 0.65
        }
    }
    
    var body: some View {
        HStack(spacing: 6) {
            // Indicator label - fixed width portion
            Text(indicator.label)
                .font(.subheadline)
                .fontWidth(.condensed)
                .foregroundColor(DS.Adaptive.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .layoutPriority(1)
            
            Spacer(minLength: 4)
            
            // Value (if present) - flexible, allow shrinking for long values like Bollinger Bands
            if let v = indicator.valueText, !v.isEmpty {
                Text(v)
                    .font(.caption.monospacedDigit())
                    .fontWidth(.condensed)
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .allowsTightening(true)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            
            // Signal badge - fixed width
            Text(indicator.signal.rawValue.capitalized)
                .font(.caption2.weight(.bold))
                .foregroundColor(signalColor)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(
                    Capsule()
                        .fill(signalColor.opacity(isDark ? 0.12 : 0.15))
                )
                .overlay(
                    Capsule()
                        .stroke(signalColor.opacity(isDark ? 0.25 : 0.35), lineWidth: 0.5)
                )
                .fixedSize()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            GeometryReader { geo in
                // Signal strength bar background
                ZStack(alignment: indicator.signal == .sell ? .leading : (indicator.signal == .buy ? .trailing : .center)) {
                    // Base background
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DS.Adaptive.overlay(0.03))
                    
                    // Signal fill bar
                    signalBar(width: geo.size.width)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DS.Adaptive.stroke.opacity(0.5), lineWidth: 0.5)
        )
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3).delay(Double(index) * 0.03)) {
                appeared = true
            }
        }
    }
    
    @ViewBuilder
    private func signalBar(width: CGFloat) -> some View {
        // Increase opacity for light mode to make colors more visible
        let barOpacity = isDark ? 0.25 : 0.35
        let fadeOpacity = isDark ? 0.05 : 0.08
        let glowOpacity = isDark ? 0.15 : 0.22
        
        switch indicator.signal {
        case .sell:
            // Red bar from left
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [signalColor.opacity(barOpacity), signalColor.opacity(fadeOpacity)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: width * 0.4)
                Spacer()
            }
        case .buy:
            // Green bar from right
            HStack(spacing: 0) {
                Spacer()
                LinearGradient(
                    colors: [signalColor.opacity(fadeOpacity), signalColor.opacity(barOpacity)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: width * 0.4)
            }
        case .neutral:
            // Yellow glow in center
            RadialGradient(
                colors: [signalColor.opacity(glowOpacity), signalColor.opacity(0.0)],
                center: .center,
                startRadius: 0,
                endRadius: width * 0.4
            )
        }
    }
}

// MARK: - Preview
#if DEBUG
struct TechnicalsIndicatorListView_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            TechnicalsIndicatorListView(indicators: [
                IndicatorSignal(label: "RSI(14)", signal: .buy, valueText: "58.2"),
                IndicatorSignal(label: "MACD Level", signal: .buy, valueText: "492.35"),
                IndicatorSignal(label: "MACD Crossover", signal: .buy, valueText: "M 492 / S 343"),
                IndicatorSignal(label: "CCI(20)", signal: .neutral, valueText: "49"),
                IndicatorSignal(label: "ADX(14)", signal: .neutral, valueText: "8.5"),
                IndicatorSignal(label: "Ultimate Oscillator", signal: .sell, valueText: "37.0"),
                IndicatorSignal(label: "SMA(10)", signal: .sell, valueText: "91553.49"),
                IndicatorSignal(label: "SMA(20)", signal: .buy, valueText: "89899.42"),
                IndicatorSignal(label: "SMA(50)", signal: .buy, valueText: "89651.45"),
                IndicatorSignal(label: "EMA(10)", signal: .neutral, valueText: "91269.25"),
                IndicatorSignal(label: "EMA(12)", signal: .buy, valueText: "91045.90"),
                IndicatorSignal(label: "Bollinger Bands", signal: .neutral, valueText: "mid 89899"),
            ])
            .padding()
        }
        .background(DS.Adaptive.background)
    }
}
#endif