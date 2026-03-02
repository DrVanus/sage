//
//  MarketSentimentDetailView.swift
//  CryptoSage
//
//  Full breakdown view for Market Sentiment AI analysis.
//  Shows detailed AI observations, key factors, confidence metrics, and historical data.
//

import SwiftUI

// MARK: - MarketSentimentDetailView

struct MarketSentimentDetailView: View {
    @ObservedObject var vm: ExtendedFearGreedViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    private let gold = BrandColors.goldBase
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // Large Gauge Section
                    gaugeSection
                        .padding(.top, 8)
                    
                    // AI Confidence & Score Section (CryptoSage AI only)
                    if vm.selectedSource == .derived,
                       vm.firebaseSentimentScore != nil || vm.firebaseSentimentConfidence != nil {
                        aiScoreSection
                    }
                    
                    // Full AI Analysis Section
                    analysisSection
                    
                    // Key Factors Section (CryptoSage AI only)
                    if vm.selectedSource == .derived,
                       let factors = vm.firebaseSentimentKeyFactors, !factors.isEmpty {
                        keyFactorsSection(factors: factors)
                    }
                    
                    // Historical Comparison Section
                    historicalSection
                    
                    // Source Information
                    sourceSection
                        .padding(.top, 8)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .background(DS.Adaptive.background)
            .navigationTitle("Market Sentiment")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            // LIGHT MODE FIX: Explicitly set toolbar background to match page background.
            // Without this, the navigation bar uses system material which can look dark/mismatched
            // in light mode, especially when presented as a sheet.
            .toolbarBackground(DS.Adaptive.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(isDark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    CSNavButton(
                        icon: "chevron.left",
                        action: { dismiss() },
                        compact: true
                    )
                }
            }
            // NAVIGATION: Enable native iOS pop gesture + custom edge swipe
            .enableInteractivePopGesture()
            .edgeSwipeToDismiss(onDismiss: { dismiss() })
        }
        // LIGHT MODE FIX: Set presentation background so the sheet itself doesn't
        // show a dark/gray tint behind the navigation bar in light mode
        .presentationBackground(DS.Adaptive.background)
    }
    
    // MARK: - Gauge Section
    
    /// Whether the sentiment data is recent enough to show a LIVE badge
    /// CryptoSage AI refreshes every 5 min; alternative.me every ~1h. Use 15 min threshold.
    private var isDataFresh: Bool {
        guard let tsStr = vm.data.first?.timestamp,
              let ts = Double(tsStr) else { return false }
        let age = Date().timeIntervalSince(Date(timeIntervalSince1970: ts))
        return age < 900 // 15 minutes
    }
    
    private var gaugeSection: some View {
        let sentimentColor = color(for: vm.data.first?.valueClassification)
        
        return VStack(spacing: 12) {
            // Large gauge — always show score badge so users see the numeric value
            ImprovedHalfCircleGauge(
                value: Double(vm.currentValue ?? 50),
                classification: vm.data.first?.valueClassification,
                lineWidth: 14,
                disableBadgeAnimation: false,
                showLiveBadge: isDataFresh,
                tickLabelOpacityFactor: 1.0,
                gentleMode: false
            )
            .frame(height: 180)
            
            // Labels
            HStack {
                Text("Extreme Fear")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.red.opacity(0.9))
                Spacer()
                Text("Extreme Greed")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.green.opacity(0.9))
            }
            .padding(.horizontal, 20)
            
            // Current classification label with glow
            if let classification = vm.data.first?.valueClassification {
                Text(classification.capitalized)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(sentimentColor)
            }
        }
        .padding(.vertical, 16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(DS.Adaptive.cardBackground)
                
                // Subtle sentiment-colored glow at top
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [sentimentColor.opacity(0.08), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [sentimentColor.opacity(0.3), DS.Adaptive.stroke],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
    }
    
    // MARK: - AI Score Section
    
    private var aiScoreSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with gold accent
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(gold)
                    .font(.system(size: 18, weight: .medium))
                Text("AI Sentiment Analysis")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(DS.Adaptive.textPrimary)
                Spacer()
            }
            
            // Score and Confidence in a nicer layout
            HStack(spacing: 20) {
                // AI Score - more prominent
                if let score = vm.firebaseSentimentScore {
                    VStack(alignment: .center, spacing: 6) {
                        Text("AI Score")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textSecondary)
                        ZStack {
                            Circle()
                                .stroke(gold.opacity(0.2), lineWidth: 3)
                                .frame(width: 70, height: 70)
                            Circle()
                                .trim(from: 0, to: CGFloat(score) / 100)
                                .stroke(scoreColor(score), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .frame(width: 70, height: 70)
                                .rotationEffect(.degrees(-90))
                            VStack(spacing: 0) {
                                Text("\(score)")
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundColor(scoreColor(score))
                                Text("/100")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(DS.Adaptive.textTertiary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                
                // Confidence with improved bar
                if let confidence = vm.firebaseSentimentConfidence {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Confidence")
                                .font(.caption)
                                .foregroundColor(DS.Adaptive.textSecondary)
                            Spacer()
                            Text("\(confidence)%")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(confidenceColor(confidence))
                        }
                        
                        // Improved confidence bar with gold border
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(DS.Adaptive.chipBackground)
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(
                                        LinearGradient(
                                            colors: [confidenceColor(confidence).opacity(0.8), confidenceColor(confidence)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geo.size.width * CGFloat(confidence) / 100)
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(gold.opacity(0.3), lineWidth: 0.5)
                            )
                        }
                        .frame(height: 10)
                        
                        // Verdict inline with confidence
                        if let verdict = vm.firebaseSentimentVerdict {
                            HStack(spacing: 4) {
                                Text("Verdict:")
                                    .font(.caption)
                                    .foregroundColor(DS.Adaptive.textSecondary)
                                Text(verdict)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(color(for: verdict.lowercased()))
                            }
                            .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [gold.opacity(0.4), gold.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
    
    // MARK: - Analysis Section
    
    /// Whether the current observation is from Firebase AI (CryptoSage AI source with live data)
    private var isLiveAIAnalysis: Bool {
        vm.selectedSource == .derived && vm.liveAIObservation != nil && !vm.liveAIObservation!.isEmpty
    }
    
    /// Header status for the analysis card; avoids vague labels like "Auto".
    private var analysisStatusText: String? {
        if vm.isLoadingAIObservation {
            return "Refreshing..."
        }
        if isLiveAIAnalysis, let lastFetch = vm.lastAIObservationFetch {
            return "Updated \(formatTimestamp(lastFetch))"
        }
        if let lastUpdate = vm.lastUpdatedDateUTC {
            return "Market data \(formatTimestamp(lastUpdate))"
        }
        return nil
    }
    
    private var analysisTitle: String { "Sentiment Analysis" }
    
    /// Lightweight cleanup for occasional punctuation artifacts in generated text.
    private var cleanedAnalysisText: String {
        cleanAnalysisText(vm.aiObservationFull)
    }
    
    private var analysisSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: isLiveAIAnalysis ? "sparkles" : "chart.line.uptrend.xyaxis")
                    .foregroundColor(gold)
                    .font(.system(size: 14, weight: .semibold))
                Text(analysisTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .allowsTightening(true)
                
                Spacer()
                
                if let statusText = analysisStatusText {
                    HStack(spacing: 4) {
                        if vm.isLoadingAIObservation {
                            ProgressView()
                                .scaleEffect(0.55)
                                .frame(width: 8, height: 8)
                        } else {
                            Circle()
                                .fill(isLiveAIAnalysis ? Color.green : DS.Adaptive.textTertiary.opacity(0.8))
                                .frame(width: 6, height: 6)
                        }
                        Text(statusText)
                            .font(.caption2)
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                }
            }
            
            // Pull-quote style analysis with gold accent bar
            HStack(alignment: .top, spacing: 12) {
                // Gold accent bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [gold, gold.opacity(0.5)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3)
                
                Text(cleanedAnalysisText)
                    .font(.body)
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(5)
            }
            .padding(.vertical, 4)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [gold.opacity(0.3), DS.Adaptive.stroke],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
    
    // MARK: - Key Factors Section
    
    private func keyFactorsSection(factors: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "tag.fill")
                    .foregroundColor(gold)
                    .font(.system(size: 14, weight: .semibold))
                Text("Key Factors")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Spacer()
                
                Text("\(factors.count) factors")
                    .font(.caption2)
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            // Wrap factors in a flow layout with numbered items
            FlowLayout(spacing: 8) {
                ForEach(Array(factors.enumerated()), id: \.element) { index, factor in
                    EnhancedKeyFactorChip(text: factor, index: index + 1)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(DS.Adaptive.stroke, lineWidth: 0.8)
        )
    }
    
    // MARK: - Historical Section
    
    /// Calculate overall trend direction based on 7d and 30d deltas
    private var overallTrend: (icon: String, color: Color, text: String) {
        let d7 = vm.delta7d ?? 0
        let d30 = vm.delta30d ?? 0
        
        if d7 > 3 && d30 > 5 {
            return ("arrow.up.right.circle.fill", .green, "Improving")
        } else if d7 < -3 && d30 < -5 {
            return ("arrow.down.right.circle.fill", .red, "Declining")
        } else if abs(d7) <= 3 && abs(d30) <= 5 {
            return ("minus.circle.fill", .yellow, "Stable")
        } else if d7 > 0 {
            return ("arrow.up.right.circle.fill", .green, "Recovering")
        } else {
            return ("arrow.down.right.circle.fill", .orange, "Weakening")
        }
    }
    
    private var historicalSection: some View {
        let trend = overallTrend
        
        return VStack(alignment: .leading, spacing: 16) {
            // Header with trend indicator
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(gold)
                    .font(.system(size: 14, weight: .semibold))
                Text("Sentiment Timeline")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Spacer()
                
                // Trend indicator pill
                HStack(spacing: 4) {
                    Image(systemName: trend.icon)
                        .font(.system(size: 10, weight: .semibold))
                    Text(trend.text)
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(trend.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(trend.color.opacity(0.15))
                )
            }
            
            // Mini trend visualization
            trendSparkline
            
            // Current value - featured highlight
            currentSentimentCard
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(DS.Adaptive.stroke, lineWidth: 0.8)
        )
    }
    
    /// Check if historical data is actually available (not just falling back to current value)
    private var hasValidHistoricalData: Bool {
        let nowVal = vm.currentValue ?? 50
        let yVal = Int(vm.yesterdayData?.value ?? "") ?? nowVal
        let wVal = Int(vm.lastWeekData?.value ?? "") ?? nowVal
        let mVal = Int(vm.lastMonthData?.value ?? "") ?? nowVal
        
        // If all values are identical, historical data is likely not available
        let values = [nowVal, yVal, wVal, mVal]
        let uniqueValues = Set(values)
        return uniqueValues.count > 1 || vm.data.count > 1
    }
    
    /// Visual trend chart showing sentiment values over time
    private var trendSparkline: some View {
        // Use current value as fallback for missing historical data
        let nowVal = vm.currentValue ?? 50
        let dataPoints: [(label: String, value: Int, color: Color, hasData: Bool)] = [
            ("30d", Int(vm.lastMonthData?.value ?? "") ?? nowVal, color(for: vm.lastMonthData?.valueClassification), vm.lastMonthData != nil),
            ("7d", Int(vm.lastWeekData?.value ?? "") ?? nowVal, color(for: vm.lastWeekData?.valueClassification), vm.lastWeekData != nil),
            ("1d", Int(vm.yesterdayData?.value ?? "") ?? nowVal, color(for: vm.yesterdayData?.valueClassification), vm.yesterdayData != nil),
            ("Now", nowVal, color(for: vm.data.first?.valueClassification), true)
        ]
        
        return VStack(spacing: 10) {
            // Sentiment scale legend
            HStack(spacing: 0) {
                ForEach([
                    ("Fear", Color.red),
                    ("Neutral", Color.yellow),
                    ("Greed", Color.green)
                ], id: \.0) { zone, zoneColor in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(zoneColor)
                            .frame(width: 6, height: 6)
                        Text(zone)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)
            
            // Mini bar chart with scale
            HStack(alignment: .center, spacing: 8) {
                // Scale indicator
                VStack(alignment: .trailing, spacing: 0) {
                    Text("100")
                        .font(.system(size: 7, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    Spacer()
                    Text("50")
                        .font(.system(size: 7, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    Spacer()
                    Text("0")
                        .font(.system(size: 7, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                .frame(width: 20, height: 60)
                
                // Bars
                HStack(alignment: .bottom, spacing: 16) {
                    ForEach(Array(dataPoints.enumerated()), id: \.offset) { index, point in
                        let isNow = index == 3
                        let hasHistoricalData = point.hasData
                        
                        VStack(spacing: 5) {
                            // Value label on top (show "—" if no historical data)
                            if hasHistoricalData || isNow {
                                Text("\(point.value)")
                                    .font(.system(size: isNow ? 13 : 11, weight: isNow ? .bold : .semibold, design: .rounded))
                                    .foregroundColor(isNow ? gold : point.color)
                            } else {
                                ShimmerBar(height: 10, cornerRadius: 3)
                                    .frame(width: 28)
                            }
                            
                            // Bar with zones
                            ZStack(alignment: .bottom) {
                                // Zone background
                                VStack(spacing: 0) {
                                    Rectangle().fill(Color.green.opacity(0.15))
                                    Rectangle().fill(Color.yellow.opacity(0.1))
                                    Rectangle().fill(Color.red.opacity(0.15))
                                }
                                .frame(width: isNow ? 32 : 24, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                
                                // Filled portion (dimmed if no historical data)
                                if hasHistoricalData || isNow {
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(
                                            LinearGradient(
                                                colors: isNow 
                                                    ? [gold, gold.opacity(0.6)]
                                                    : [point.color, point.color.opacity(0.5)],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .frame(width: isNow ? 32 : 24, height: CGFloat(point.value) / 100.0 * 60)
                                } else {
                                    // Show dashed outline for missing data
                                    RoundedRectangle(cornerRadius: 5)
                                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3]))
                                        .foregroundColor(DS.Adaptive.textTertiary.opacity(0.3))
                                        .frame(width: 24, height: CGFloat(point.value) / 100.0 * 60)
                                }
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(isNow ? gold : Color.clear, lineWidth: isNow ? 1.5 : 0)
                            )
                            
                            // Time label
                            Text(point.label)
                                .font(.system(size: isNow ? 10 : 9, weight: isNow ? .bold : .medium))
                                .foregroundColor(isNow ? gold : (hasHistoricalData ? DS.Adaptive.textTertiary : DS.Adaptive.textTertiary.opacity(0.5)))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            
            // Trend flow with delta values - connecting arrows between time periods
            HStack(spacing: 0) {
                Spacer().frame(width: 28) // Offset for scale
                
                // Flow indicators showing change between periods
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { i in
                        let fromVal = dataPoints[i].value
                        let toVal = dataPoints[i + 1].value
                        let delta = toVal - fromVal
                        let isUp = delta >= 0
                        let fromLabel = dataPoints[i].label
                        let toLabel = dataPoints[i + 1].label
                        let hasValidDelta = dataPoints[i].hasData && dataPoints[i + 1].hasData
                        
                        VStack(spacing: 2) {
                            // Period transition label
                            Text("\(fromLabel) → \(toLabel)")
                                .font(.system(size: 7, weight: .medium))
                                .foregroundColor(DS.Adaptive.textTertiary)
                            
                            // Delta pill (show "—" if data unavailable)
                            if hasValidDelta {
                                HStack(spacing: 2) {
                                    Image(systemName: isUp ? "arrow.up" : "arrow.down")
                                        .font(.system(size: 7, weight: .bold))
                                    Text("\(abs(delta))")
                                        .font(.system(size: 9, weight: .bold, design: .rounded))
                                }
                                .foregroundColor(isUp ? .green : .red)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill((isUp ? Color.green : Color.red).opacity(0.15))
                                )
                            } else {
                                ShimmerBar(height: 10, cornerRadius: 8)
                                    .frame(width: 36)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(DS.Adaptive.chipBackground.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DS.Adaptive.stroke.opacity(0.5), lineWidth: 0.5)
        )
    }
    
    /// Current sentiment summary card
    private var currentSentimentCard: some View {
        let currentVal = vm.currentValue ?? 50
        let classification = vm.data.first?.valueClassification ?? "Neutral"
        let sentimentColor = color(for: classification)
        
        // Calculate overall change
        let monthVal = Int(vm.lastMonthData?.value ?? "") ?? currentVal
        let overallChange = currentVal - monthVal
        
        return HStack(spacing: 16) {
            // Left: Current value and classification
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Current")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    if isDataFresh {
                        Text("LIVE")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(gold))
                    }
                }
                
                Text(classification.capitalized)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(sentimentColor)
            }
            
            Spacer()
            
            // Right: Value badge and 30d change
            HStack(spacing: 12) {
                // 30-day change indicator
                VStack(alignment: .trailing, spacing: 2) {
                    Text("30d change")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    
                    HStack(spacing: 3) {
                        Image(systemName: overallChange >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                        Text("\(overallChange >= 0 ? "+" : "")\(overallChange)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(overallChange >= 0 ? .green : .red)
                }
                
                // Large value badge
                Text("\(currentVal)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .frame(width: 50, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                LinearGradient(
                                    colors: [sentimentColor, sentimentColor.opacity(0.8)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(gold.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(gold.opacity(0.3), lineWidth: 1)
        )
    }
    
    private func historicalRowEnhanced(label: String, sublabel: String, value: Int?, classification: String?, delta: Int? = nil, isCurrent: Bool = false) -> some View {
        let sentimentColor = color(for: classification)
        let progress = Double(value ?? 50) / 100.0
        
        return HStack(spacing: 12) {
            // Left: Label and mini progress bar
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(label)
                        .font(.system(size: isCurrent ? 15 : 13, weight: isCurrent ? .semibold : .medium))
                        .foregroundColor(isCurrent ? DS.Adaptive.textPrimary : DS.Adaptive.textSecondary)
                    
                    if isCurrent && isDataFresh {
                        Text("LIVE")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(gold)
                            )
                    }
                }
                
                // Mini progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Track
                        RoundedRectangle(cornerRadius: 2)
                            .fill(DS.Adaptive.chipBackground)
                            .frame(height: 4)
                        
                        // Fill with gradient
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(
                                    colors: [sentimentColor.opacity(0.6), sentimentColor],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * progress, height: 4)
                    }
                }
                .frame(height: 4)
                .frame(maxWidth: isCurrent ? .infinity : 100)
            }
            
            Spacer()
            
            // Right: Delta, classification, value
            HStack(spacing: 8) {
                // Delta indicator (only for past values)
                if let delta = delta {
                    let isUp = delta >= 0
                    HStack(spacing: 2) {
                        Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 9, weight: .bold))
                        Text("\(abs(delta))")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(isUp ? .green : .red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill((isUp ? Color.green : Color.red).opacity(0.15))
                    )
                }
                
                // Classification label
                if let cls = classification {
                    Text(cls.capitalized)
                        .font(.system(size: isCurrent ? 12 : 11, weight: .medium))
                        .foregroundColor(sentimentColor)
                        .lineLimit(1)
                }
                
                // Value badge
                if let val = value {
                    Text("\(val)")
                        .font(.system(size: isCurrent ? 16 : 14, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                        .frame(width: isCurrent ? 38 : 32, height: isCurrent ? 28 : 24)
                        .background(
                            RoundedRectangle(cornerRadius: isCurrent ? 8 : 6)
                                .fill(
                                    LinearGradient(
                                        colors: [sentimentColor, sentimentColor.opacity(0.8)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, isCurrent ? 14 : 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isCurrent ? gold.opacity(0.08) : DS.Adaptive.chipBackground.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isCurrent ? gold.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
    
    // MARK: - Source Section (minimal footer)
    
    private var sourceSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 10))
                .foregroundColor(DS.Adaptive.textTertiary)
            
            if let lastUpdate = vm.lastUpdatedDateUTC {
                Text("Updated \(formatTimestamp(lastUpdate))")
                    .font(.caption2)
                    .foregroundColor(DS.Adaptive.textTertiary)
                
                Text("•")
                    .font(.caption2)
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            Text(vm.sourceDisplayNameWithFallback)
                .font(.caption2)
                .foregroundColor(DS.Adaptive.textTertiary)
            
            if let nextUpdate = vm.nextUpdateInterval, nextUpdate > 0 {
                Text("•")
                    .font(.caption2)
                    .foregroundColor(DS.Adaptive.textTertiary)
                
                Text("Refresh ~\(formatRefreshInterval(nextUpdate))")
                    .font(.caption2)
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
    
    // MARK: - Helper Functions
    
    private func color(for cls: String?) -> Color {
        let key = (cls ?? "").lowercased()
        switch key {
        case "extreme fear":  return .red
        case "fear":          return .orange
        case "neutral":       return DS.Adaptive.neutralYellow
        case "greed":         return .green
        case "extreme greed": return .mint
        default:              return .gray
        }
    }
    
    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 0..<20:  return .red
        case 20..<40: return .orange
        case 40..<60: return DS.Adaptive.neutralYellow
        case 60..<80: return .green
        default:      return .mint
        }
    }
    
    private func confidenceColor(_ confidence: Int) -> Color {
        switch confidence {
        case 0..<40:  return .red
        case 40..<60: return .orange
        case 60..<80: return .yellow
        default:      return .green
        }
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, h:mm a"
            return formatter.string(from: date)
        }
    }
    
    private func formatRefreshInterval(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        if seconds < 60 { return "\(seconds)s" }
        let mins = seconds / 60
        if mins < 60 { return "\(mins)m" }
        let hours = mins / 60
        let remMins = mins % 60
        return remMins == 0 ? "\(hours)h" : "\(hours)h \(remMins)m"
    }
    
    private func cleanAnalysisText(_ text: String) -> String {
        var cleaned = text.replacingOccurrences(of: " . ", with: " • ")
        while cleaned.contains("  ") {
            cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
        }
        while cleaned.contains("• •") {
            cleaned = cleaned.replacingOccurrences(of: "• •", with: "•")
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Detail Key Factor Chip

/// Larger chip for detail view with more prominent styling
struct DetailKeyFactorChip: View {
    let text: String
    private let gold = BrandColors.goldBase
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(gold.opacity(0.8))
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(gold)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(gold.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(gold.opacity(0.3), lineWidth: 1)
        )
    }
}

/// Enhanced key factor chip with index number
struct EnhancedKeyFactorChip: View {
    let text: String
    let index: Int
    private let gold = BrandColors.goldBase
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 8) {
            // Index badge
            Text("\(index)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(colorScheme == .dark ? .black : .white)
                .frame(width: 18, height: 18)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [gold, gold.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
            
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.Adaptive.textPrimary)
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(gold.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(gold.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - Preview

#if DEBUG
struct MarketSentimentDetailView_Previews: PreviewProvider {
    static var previews: some View {
        MarketSentimentDetailView(vm: ExtendedFearGreedViewModel.shared)
            .preferredColorScheme(.dark)
    }
}
#endif
