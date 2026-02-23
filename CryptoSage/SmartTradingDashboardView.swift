//
//  SmartTradingDashboardView.swift
//  CryptoSage
//
//  AI Trading Intelligence Dashboard — The main UI for the
//  SmartTradingEngine, showing decisions, signals, DCA, and performance.
//

import SwiftUI

// MARK: - Main Dashboard

struct SmartTradingDashboardView: View {
    @StateObject private var coordinator = SmartTradingCoordinator.shared
    @State private var showSettings = false
    @State private var selectedDecision: SmartTradingDecision?
    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Market Context Header
                    marketContextHeader

                    // Tab Selector
                    intelligenceTabSelector

                    // Tab Content
                    switch coordinator.selectedTab {
                    case .overview:
                        overviewSection
                    case .signals:
                        signalsSection
                    case .dca:
                        dcaSection
                    case .performance:
                        performanceSection
                    case .settings:
                        settingsSection
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 100)
            }
            .background(Color(.systemBackground))
            .navigationTitle("AI Intelligence")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            isRefreshing = true
                            await coordinator.fullRefresh()
                            isRefreshing = false
                        }
                    } label: {
                        if isRefreshing || coordinator.isAnalyzing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(coordinator.isAnalyzing)
                }
            }
            .task {
                await coordinator.analyzePortfolio()
            }
            .sheet(item: $selectedDecision) { decision in
                DecisionDetailSheet(decision: decision)
            }
        }
    }

    // MARK: - Market Context Header

    private var marketContextHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // Fear & Greed
                VStack(spacing: 4) {
                    Text("Fear & Greed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(coordinator.currentFearGreed)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(fearGreedColor(coordinator.currentFearGreed))
                    Text(coordinator.fearGreedClassification)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Divider()
                    .frame(height: 50)

                // AI Accuracy
                VStack(spacing: 4) {
                    Text("AI Accuracy")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(String(format: "%.0f", coordinator.aiAccuracy))%")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(coordinator.aiAccuracy >= 60 ? .green : .orange)
                    Text("\(coordinator.totalPredictions) predictions")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Divider()
                    .frame(height: 50)

                // Market Regime
                VStack(spacing: 4) {
                    Text("Regime")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: regimeIcon(coordinator.marketRegimeSummary))
                        .font(.system(size: 24))
                        .foregroundStyle(.blue)
                    Text(coordinator.marketRegimeSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )

            // Engine status
            if coordinator.isAnalyzing {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(SmartTradingEngine.shared.engineStatus.displayText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Tab Selector

    private var intelligenceTabSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SmartTradingCoordinator.IntelligenceTab.allCases, id: \.rawValue) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            coordinator.selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.caption)
                            Text(tab.rawValue)
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(coordinator.selectedTab == tab
                                      ? Color.accentColor
                                      : Color(.secondarySystemBackground))
                        )
                        .foregroundStyle(coordinator.selectedTab == tab ? .white : .primary)
                    }
                }
            }
        }
    }

    // MARK: - Overview Section

    private var overviewSection: some View {
        VStack(spacing: 16) {
            // Top Actionable Decisions
            if !coordinator.portfolioDecisions.isEmpty {
                sectionHeader("Portfolio Intelligence", icon: "briefcase")

                ForEach(coordinator.portfolioDecisions.prefix(5)) { decision in
                    DecisionCardView(decision: decision)
                        .onTapGesture {
                            selectedDecision = decision
                        }
                }
            }

            // Watchlist Decisions
            if !coordinator.watchlistDecisions.isEmpty {
                sectionHeader("Watchlist Intelligence", icon: "star")

                ForEach(coordinator.watchlistDecisions.prefix(5)) { decision in
                    DecisionCardView(decision: decision)
                        .onTapGesture {
                            selectedDecision = decision
                        }
                }
            }

            // Active DCA Plans
            if coordinator.activeDCAPlans > 0 {
                sectionHeader("Smart DCA", icon: "arrow.triangle.2.circlepath")

                HStack {
                    Label("\(coordinator.activeDCAPlans) active plans", systemImage: "checkmark.circle")
                        .font(.subheadline)
                    Spacer()
                    Button("Manage") {
                        coordinator.selectedTab = .dca
                    }
                    .font(.subheadline.weight(.medium))
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
            }

            // Quick Performance Glance
            sectionHeader("AI Performance", icon: "chart.bar.xaxis")
            performanceGlanceCard
        }
    }

    // MARK: - Signals Section

    private var signalsSection: some View {
        VStack(spacing: 16) {
            sectionHeader("All AI Signals", icon: "waveform.path.ecg")

            let allDecisions = (coordinator.portfolioDecisions + coordinator.watchlistDecisions + coordinator.topDecisions)
                .sorted { $0.conviction > $1.conviction }

            if allDecisions.isEmpty {
                emptyStateView(
                    icon: "brain",
                    title: "No Signals Yet",
                    message: "Pull to refresh to analyze your portfolio and watchlist"
                )
            } else {
                ForEach(allDecisions) { decision in
                    DecisionCardView(decision: decision)
                        .onTapGesture {
                            selectedDecision = decision
                        }
                }
            }
        }
    }

    // MARK: - DCA Section

    private var dcaSection: some View {
        VStack(spacing: 16) {
            sectionHeader("Smart DCA", icon: "arrow.triangle.2.circlepath")

            // Fear/Greed DCA Explanation
            VStack(alignment: .leading, spacing: 8) {
                Text("Sentiment-Adjusted DCA")
                    .font(.headline)
                Text("Automatically invest more during Fear and less during Greed. The market's emotion becomes your edge.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    dcaMultiplierBadge(label: "Extreme Fear", multiplier: "2.0×", color: .green)
                    dcaMultiplierBadge(label: "Neutral", multiplier: "1.0×", color: .gray)
                    dcaMultiplierBadge(label: "Extreme Greed", multiplier: "0.25×", color: .red)
                }
                .padding(.top, 4)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))

            // Active Plans
            let plans = SmartDCAEngine.shared.activePlans
            if plans.isEmpty {
                emptyStateView(
                    icon: "plus.circle",
                    title: "No DCA Plans",
                    message: "Create a smart DCA plan to automate your investing"
                )
            } else {
                ForEach(plans) { plan in
                    dcaPlanCard(plan: plan)
                }
            }
        }
    }

    // MARK: - Performance Section

    private var performanceSection: some View {
        VStack(spacing: 16) {
            sectionHeader("AI Performance Tracking", icon: "chart.bar.xaxis")

            performanceGlanceCard

            // Source Accuracy Breakdown
            let accuracies = PerformanceAttributionEngine.shared.sourceAccuracies
            if !accuracies.isEmpty {
                sectionHeader("Signal Source Accuracy", icon: "target")

                ForEach(accuracies) { accuracy in
                    sourceAccuracyRow(accuracy: accuracy)
                }
            }

            // Recent Predictions
            let recentPredictions = PerformanceAttributionEngine.shared.trackedPredictions
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(10)

            if !recentPredictions.isEmpty {
                sectionHeader("Recent Predictions", icon: "clock.arrow.circlepath")

                ForEach(Array(recentPredictions)) { prediction in
                    predictionRow(prediction: prediction)
                }
            }
        }
    }

    // MARK: - Settings Section

    private var settingsSection: some View {
        VStack(spacing: 16) {
            sectionHeader("Engine Configuration", icon: "gearshape")

            // Presets
            VStack(alignment: .leading, spacing: 12) {
                Text("Risk Profile")
                    .font(.headline)

                ForEach(SmartTradingCoordinator.ConfigPreset.allCases, id: \.rawValue) { preset in
                    Button {
                        coordinator.applyPreset(preset)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.rawValue)
                                    .font(.subheadline.weight(.semibold))
                                Text(preset.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isCurrentPreset(preset) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isCurrentPreset(preset) ? Color.green.opacity(0.1) : Color(.tertiarySystemBackground))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))

            // Signal Weights
            VStack(alignment: .leading, spacing: 12) {
                Text("Signal Weights")
                    .font(.headline)

                weightSlider(label: "Sentiment", value: coordinator.currentConfig.sentimentWeight, icon: "face.smiling")
                weightSlider(label: "AI Prediction", value: coordinator.currentConfig.predictionWeight, icon: "brain")
                weightSlider(label: "Technical", value: coordinator.currentConfig.technicalWeight, icon: "chart.xyaxis.line")
                weightSlider(label: "Algorithm", value: coordinator.currentConfig.algorithmWeight, icon: "function")
                weightSlider(label: "Risk", value: coordinator.currentConfig.riskWeight, icon: "shield")
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
        }
    }

    // MARK: - Component Views

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.headline)
            Spacer()
        }
        .padding(.top, 8)
    }

    private var performanceGlanceCard: some View {
        let summary = PerformanceAttributionEngine.shared.performanceSummary

        return HStack(spacing: 16) {
            performanceStat(
                label: "Accuracy",
                value: "\(String(format: "%.0f", summary.overallAccuracy))%",
                color: summary.overallAccuracy >= 60 ? .green : .orange
            )
            performanceStat(
                label: "Predictions",
                value: "\(summary.totalPredictions)",
                color: .blue
            )
            performanceStat(
                label: "Avg Return",
                value: "\(String(format: "%.1f", summary.avgReturn))%",
                color: summary.avgReturn >= 0 ? .green : .red
            )
            performanceStat(
                label: "Best Source",
                value: summary.bestSource?.source.displayName ?? "—",
                color: .purple
            )
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
    }

    private func performanceStat(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func dcaMultiplierBadge(label: String, multiplier: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(multiplier)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func dcaPlanCard(plan: SmartDCAPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(plan.name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(plan.isActive ? "Active" : "Paused")
                    .font(.caption)
                    .foregroundStyle(plan.isActive ? .green : .secondary)
            }
            HStack {
                Text("$\(String(format: "%.0f", plan.baseAmountUSD)) \(plan.frequency.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(plan.assets.count) assets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }

    private func sourceAccuracyRow(accuracy: SignalSourceAccuracy) -> some View {
        HStack {
            Text(accuracy.source.displayName)
                .font(.subheadline)
            Spacer()
            Text("\(String(format: "%.0f", accuracy.accuracy))%")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(accuracy.accuracy >= 60 ? .green : .orange)
            Text("(\(accuracy.totalPredictions))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func predictionRow(prediction: TrackedPrediction) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(prediction.symbol.uppercased())
                    .font(.subheadline.weight(.semibold))
                Text(prediction.source.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            if let wasCorrect = prediction.wasCorrect {
                Image(systemName: wasCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(wasCorrect ? .green : .red)
            } else {
                Text("Pending")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let changePct = prediction.actualChangePct {
                Text("\(String(format: "%+.1f", changePct))%")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(changePct >= 0 ? .green : .red)
            }
        }
        .padding(.vertical, 4)
    }

    private func weightSlider(label: String, value: Double, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.secondary)
            Text(label)
                .font(.subheadline)
            Spacer()
            Text("\(Int(value * 100))%")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }

    private func emptyStateView(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Helpers

    private func fearGreedColor(_ value: Int) -> Color {
        switch value {
        case 0..<25:  return .red
        case 25..<40: return .orange
        case 40..<60: return .gray
        case 60..<75: return .green
        default:      return .green
        }
    }

    private func regimeIcon(_ regime: String) -> String {
        switch regime.lowercased() {
        case "strongtrend", "trending": return "arrow.up.right"
        case "volatile":               return "waveform.path.ecg"
        case "ranging":                return "arrow.left.arrow.right"
        case "accumulation":           return "arrow.down.to.line"
        case "distribution":           return "arrow.up.to.line"
        default:                       return "questionmark.circle"
        }
    }

    private func isCurrentPreset(_ preset: SmartTradingCoordinator.ConfigPreset) -> Bool {
        let config = coordinator.currentConfig
        switch preset {
        case .conservative: return config.maxSinglePositionPct == 8.0
        case .balanced:     return config.maxSinglePositionPct == 15.0
        case .aggressive:   return config.maxSinglePositionPct == 25.0
        }
    }
}

// MARK: - Decision Card View

struct DecisionCardView: View {
    let decision: SmartTradingDecision

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Asset + Action
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(decision.coinName)
                        .font(.subheadline.weight(.semibold))
                    Text(decision.symbol.uppercased())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Action Badge
                HStack(spacing: 4) {
                    Image(systemName: decision.action.icon)
                    Text(decision.action.displayName)
                }
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(decision.action.color.opacity(0.2)))
                .foregroundStyle(decision.action.color)
            }

            // Conviction + Price Levels
            HStack(spacing: 16) {
                // Conviction
                VStack(alignment: .leading, spacing: 2) {
                    Text("Conviction")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Text("\(Int(decision.conviction))%")
                            .font(.subheadline.weight(.bold))
                        Text(decision.confidenceLabel)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }

                // Risk:Reward
                VStack(alignment: .leading, spacing: 2) {
                    Text("R:R Ratio")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f:1", decision.riskRewardRatio))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(decision.riskRewardRatio >= 2 ? .green : .orange)
                }

                // Position Size
                VStack(alignment: .leading, spacing: 2) {
                    Text("Position")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("\(String(format: "%.1f", decision.recommendedPositionPct))%")
                        .font(.subheadline.weight(.bold))
                }

                Spacer()

                // Urgency
                Text(decision.urgency.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(
                            decision.urgency == .immediate ? Color.red.opacity(0.2) :
                            decision.urgency == .soon ? Color.orange.opacity(0.2) :
                            Color(.tertiarySystemBackground)
                        )
                    )
                    .foregroundStyle(
                        decision.urgency == .immediate ? .red :
                        decision.urgency == .soon ? .orange : .secondary
                    )
            }

            // Signal Sources Mini Bar
            HStack(spacing: 8) {
                signalDot(signal: decision.sentimentSignal, label: "S")
                signalDot(signal: decision.predictionSignal, label: "P")
                signalDot(signal: decision.technicalSignal, label: "T")
                signalDot(signal: decision.algorithmSignal, label: "A")
                Spacer()
                Text("\(decision.signalSourceCount) signals")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func signalDot(signal: SignalContribution, label: String) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(signal.confidence > 0
                      ? (signal.score > 15 ? Color.green : signal.score < -15 ? Color.red : Color.gray)
                      : Color.gray.opacity(0.3))
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Decision Detail Sheet

struct DecisionDetailSheet: View {
    let decision: SmartTradingDecision
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Text(decision.coinName)
                            .font(.title2.weight(.bold))
                        Text(decision.symbol.uppercased())
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 4) {
                            Image(systemName: decision.action.icon)
                            Text(decision.action.displayName)
                        }
                        .font(.title3.weight(.bold))
                        .foregroundStyle(decision.action.color)
                        .padding(.top, 4)

                        Text("\(Int(decision.conviction))% Conviction")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)

                    Divider()

                    // Price Levels
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Price Levels")
                            .font(.headline)

                        priceLevelRow("Current Price", value: decision.currentPrice, color: .primary)
                        priceLevelRow("Entry", value: decision.suggestedEntry, color: .blue)
                        priceLevelRow("Stop Loss", value: decision.stopLoss, color: .red)
                        priceLevelRow("Take Profit", value: decision.takeProfit, color: .green)
                        priceLevelRow("Risk/Reward", value: decision.riskRewardRatio, color: .orange, isCurrency: false, suffix: ":1")
                    }

                    Divider()

                    // Position Sizing
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Position Sizing")
                            .font(.headline)

                        HStack {
                            Text("Recommended")
                            Spacer()
                            Text("\(String(format: "%.1f", decision.recommendedPositionPct))% ($\(String(format: "%.0f", decision.recommendedAmountUSD)))")
                                .font(.subheadline.weight(.semibold))
                        }

                        HStack {
                            Text("Max Allowed")
                            Spacer()
                            Text("\(String(format: "%.0f", decision.maxPositionPct))%")
                                .font(.subheadline.weight(.semibold))
                        }

                        HStack {
                            Text("Fear/Greed")
                            Spacer()
                            Text("\(decision.fearGreedValue) — \(decision.fearGreedClassification)")
                                .font(.subheadline.weight(.semibold))
                        }
                    }

                    Divider()

                    // Signal Breakdown
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Signal Breakdown")
                            .font(.headline)

                        signalRow(decision.sentimentSignal)
                        signalRow(decision.predictionSignal)
                        signalRow(decision.technicalSignal)
                        signalRow(decision.algorithmSignal)
                        signalRow(decision.riskSignal)
                    }

                    Divider()

                    // Reasoning
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reasoning")
                            .font(.headline)

                        ForEach(decision.reasoning, id: \.self) { reason in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                                    .padding(.top, 2)
                                Text(reason)
                                    .font(.caption)
                            }
                        }
                    }

                    // Risk Warnings
                    if !decision.riskWarnings.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Risk Warnings")
                                .font(.headline)
                                .foregroundStyle(.orange)

                            ForEach(decision.riskWarnings, id: \.self) { warning in
                                Text(warning)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Decision Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func priceLevelRow(_ label: String, value: Double, color: Color, isCurrency: Bool = true, suffix: String = "") -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(isCurrency ? "$\(String(format: "%.2f", value))" : "\(String(format: "%.2f", value))\(suffix)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
        }
    }

    private func signalRow(_ signal: SignalContribution) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(signal.source)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(signal.direction.capitalized)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(
                        signal.direction == "bullish" ? .green :
                        signal.direction == "bearish" ? .red : .gray
                    )
                Text("(\(String(format: "%.0f", signal.score)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !signal.details.isEmpty && signal.details != "No data available" {
                Text(signal.details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

#Preview {
    SmartTradingDashboardView()
}
