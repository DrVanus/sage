//
//  PredictionAccuracyView.swift
//  CryptoSage
//
//  UI components for displaying prediction accuracy metrics.
//

import SwiftUI

// MARK: - Firebase Global Accuracy ViewModel

/// ViewModel for fetching and managing global accuracy metrics from Firebase
@MainActor
final class FirebaseGlobalAccuracyViewModel: ObservableObject {
    static let shared = FirebaseGlobalAccuracyViewModel()
    
    @Published private(set) var totalPredictions: Int = 0
    @Published private(set) var directionAccuracyPercent: Double = 50
    @Published private(set) var rangeAccuracyPercent: Double = 50
    @Published private(set) var averageError: Double = 3
    @Published private(set) var timeframeAccuracy: [String: Double] = [:]
    @Published private(set) var directionBreakdown: [String: Double] = [:]
    @Published private(set) var hasData: Bool = false
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var error: String?
    
    private var lastFetchTime: Date?
    private let fetchCooldown: TimeInterval = 300 // 5 minutes
    
    private init() {}
    
    /// Whether we have enough data to display meaningful metrics
    var hasEnoughData: Bool {
        hasData && totalPredictions >= 50
    }
    
    /// Fetch global accuracy metrics from Firebase
    func fetchMetrics(force: Bool = false) async {
        // Check cooldown unless forced
        if !force, let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < fetchCooldown {
            return
        }
        
        guard !isLoading else { return }
        
        isLoading = true
        error = nil
        
        do {
            let response = try await FirebaseService.shared.getGlobalAccuracyMetrics()
            
            totalPredictions = response.totalPredictions
            directionAccuracyPercent = response.directionAccuracyPercent
            rangeAccuracyPercent = response.rangeAccuracyPercent
            averageError = response.averageError
            timeframeAccuracy = response.timeframeAccuracy ?? [:]
            directionBreakdown = response.directionBreakdown ?? [:]
            hasData = response.hasData
            lastUpdated = ISO8601DateFormatter().date(from: response.lastUpdated)
            lastFetchTime = Date()
            
            #if DEBUG
            print("[FirebaseGlobalAccuracy] Fetched: \(totalPredictions) predictions, \(String(format: "%.1f", directionAccuracyPercent))% accuracy")
            #endif
        } catch {
            self.error = error.localizedDescription
            #if DEBUG
            print("[FirebaseGlobalAccuracy] Error: \(error.localizedDescription)")
            #endif
        }
        
        isLoading = false
    }
}

// MARK: - Accuracy Stats Card

/// Card showing overall prediction accuracy statistics with trend and streak indicators
struct PredictionAccuracyCard: View {
    @ObservedObject private var accuracyService = PredictionAccuracyService.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var showClearConfirmation = false
    
    private var isDark: Bool { colorScheme == .dark }
    
    /// Calculate current streak from recent predictions
    private var currentStreak: (count: Int, type: String)? {
        // Get evaluated predictions only
        let evaluatedPredictions = accuracyService.storedPredictions.filter { $0.isEvaluated && $0.directionCorrect != nil }
        guard evaluatedPredictions.count >= 2 else { return nil }
        
        // Get recent results sorted by date (newest first)
        let sortedResults = evaluatedPredictions.sorted { 
            ($0.evaluatedAt ?? Date.distantPast) > ($1.evaluatedAt ?? Date.distantPast)
        }
        
        var streakCount = 0
        var streakType: Bool? = nil
        
        for result in sortedResults.prefix(10) {
            guard let correct = result.directionCorrect else { continue }
            if streakType == nil {
                streakType = correct
                streakCount = 1
            } else if correct == streakType {
                streakCount += 1
            } else {
                break
            }
        }
        
        guard streakCount >= 2 else { return nil }
        return (streakCount, streakType == true ? "correct" : "miss")
    }
    
    /// Calculate if accuracy is trending up or down (compare recent vs older)
    private var accuracyTrend: (direction: String, change: Double)? {
        // Get evaluated predictions only
        let evaluatedPredictions = accuracyService.storedPredictions.filter { $0.isEvaluated && $0.directionCorrect != nil }
        guard evaluatedPredictions.count >= 6 else { return nil }
        
        // Sort by date
        let sortedResults = evaluatedPredictions.sorted { 
            ($0.evaluatedAt ?? Date.distantPast) > ($1.evaluatedAt ?? Date.distantPast)
        }
        
        // Split into recent (first half) and older (second half)
        let midpoint = sortedResults.count / 2
        let recentResults = Array(sortedResults.prefix(midpoint))
        let olderResults = Array(sortedResults.suffix(from: midpoint))
        
        guard recentResults.count >= 3, olderResults.count >= 3 else { return nil }
        
        let recentAccuracy = Double(recentResults.filter { $0.directionCorrect == true }.count) / Double(recentResults.count) * 100
        let olderAccuracy = Double(olderResults.filter { $0.directionCorrect == true }.count) / Double(olderResults.count) * 100
        
        let change = recentAccuracy - olderAccuracy
        if abs(change) < 5 { return nil } // Only show if significant change
        
        return (change > 0 ? "up" : "down", abs(change))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with premium styling
            HStack {
                HStack(spacing: 6) {
                    // Icon with subtle background
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(BrandColors.goldBase.opacity(isDark ? 0.12 : 0.08))
                            .frame(width: 24, height: 24)
                        
                        Image(systemName: "chart.bar.doc.horizontal")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(BrandColors.goldBase)
                    }
                    
                    Text("AI Prediction Accuracy")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.Adaptive.textPrimary)
                }
                
                // Trend indicator
                if let trend = accuracyTrend {
                    HStack(spacing: 2) {
                        Image(systemName: trend.direction == "up" ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 9, weight: .bold))
                        Text(String(format: "%.0f%%", trend.change))
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundColor(trend.direction == "up" ? .green : .red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill((trend.direction == "up" ? Color.green : Color.red).opacity(0.12))
                    )
                }
                
                Spacer()
                
                // Show the evaluated count for the displayed metrics
                let displayCount = accuracyService.displayMetrics.evaluatedPredictions
                if displayCount > 0 {
                    Text("\(displayCount) prediction\(displayCount == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Adaptive.textTertiary)
                }
            }
            
            // Show real accuracy stats (even early data with partial count)
            if accuracyService.displayMetrics.evaluatedPredictions > 0 {
                // Use DeepSeek-only metrics when available, else all metrics
                let metricsToShow = accuracyService.displayMetrics
                let showingDeepSeek = accuracyService.isShowingDeepSeekMetrics
                
                // Early data indicator when < 5 evaluated
                if !metricsToShow.hasEnoughData {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 9))
                            .foregroundStyle(.blue)
                        Text("Early data — \(metricsToShow.evaluatedPredictions)/5 predictions tracked")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.blue)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.blue.opacity(isDark ? 0.12 : 0.08))
                    )
                }
                
                // Legacy prediction notice - clearer about what's happening
                if accuracyService.legacyPredictionCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                        
                        if showingDeepSeek {
                            // DeepSeek metrics shown, legacy excluded from stats
                            Text("\(accuracyService.legacyPredictionCount) older prediction\(accuracyService.legacyPredictionCount == 1 ? "" : "s") from previous AI model")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.orange)
                        } else {
                            // All metrics shown including legacy (no DeepSeek evaluated yet)
                            let legacyEval = accuracyService.legacyEvaluatedCount
                            if legacyEval > 0 {
                                Text("\(legacyEval) of \(metricsToShow.evaluatedPredictions) from previous AI model")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.orange)
                            } else {
                                Text("\(accuracyService.legacyPredictionCount) prediction\(accuracyService.legacyPredictionCount == 1 ? "" : "s") from previous AI model")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.orange)
                            }
                        }
                        
                        Spacer()
                        Button {
                            showClearConfirmation = true
                        } label: {
                            Text("Clear")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .stroke(.orange.opacity(0.4), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.orange.opacity(isDark ? 0.10 : 0.06))
                    )
                }
                
                // Main stats row
                HStack(spacing: 16) {
                    AccuracyStatBox(
                        title: "Trend Hit",
                        value: metricsToShow.formattedDirectionAccuracy,
                        subtitle: "\(metricsToShow.directionsCorrect)/\(metricsToShow.evaluatedPredictions) correct",
                        color: accuracyColor(for: metricsToShow.directionAccuracyPercent)
                    )
                    
                    AccuracyStatBox(
                        title: "In Range",
                        value: metricsToShow.formattedRangeAccuracy,
                        subtitle: "\(metricsToShow.withinRangeCount)/\(metricsToShow.evaluatedPredictions) hit",
                        color: accuracyColor(for: metricsToShow.rangeAccuracyPercent)
                    )
                    
                    AccuracyStatBox(
                        title: "Avg Miss",
                        value: metricsToShow.formattedAverageError,
                        subtitle: "price diff",
                        color: errorColor(for: metricsToShow.averagePriceError)
                    )
                }
                
                // Direction breakdown with streak indicator (only when enough data)
                if metricsToShow.hasEnoughData && (metricsToShow.bullishPredictions > 0 || metricsToShow.bearishPredictions > 0) {
                    Divider()
                        .background(DS.Adaptive.stroke.opacity(0.5))
                    
                    HStack(spacing: 6) {
                        DirectionAccuracyPill(
                            direction: .bullish,
                            correct: metricsToShow.bullishCorrect,
                            total: metricsToShow.bullishPredictions
                        )
                        
                        DirectionAccuracyPill(
                            direction: .bearish,
                            correct: metricsToShow.bearishCorrect,
                            total: metricsToShow.bearishPredictions
                        )
                        
                        if metricsToShow.neutralPredictions > 0 {
                            DirectionAccuracyPill(
                                direction: .neutral,
                                correct: metricsToShow.neutralCorrect,
                                total: metricsToShow.neutralPredictions
                            )
                        }
                        
                        Spacer(minLength: 4)
                        
                        // Streak indicator
                        if let streak = currentStreak {
                            HStack(spacing: 3) {
                                Image(systemName: streak.type == "correct" ? "flame.fill" : "snowflake")
                                    .font(.system(size: 9))
                                Text("\(streak.count)")
                                    .font(.system(size: 10, weight: .bold))
                                Text(streak.type == "correct" ? "hot" : "cold")
                                    .font(.system(size: 8))
                            }
                            .foregroundColor(streak.type == "correct" ? .orange : .blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill((streak.type == "correct" ? Color.orange : Color.blue).opacity(0.12))
                            )
                            .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }
            } else if accuracyService.metrics.evaluatedPredictions > 0 {
                // Edge case: all evaluated predictions are legacy only (displayMetrics is empty
                // because deepSeekMetrics is empty, but there ARE legacy evaluated predictions)
                // This shouldn't normally happen since displayMetrics falls back to metrics,
                // but handle it defensively
                let metricsToShow = accuracyService.metrics
                
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                    Text("Stats from previous AI model (\(metricsToShow.evaluatedPredictions) predictions)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.orange)
                    Spacer()
                    Button {
                        showClearConfirmation = true
                    } label: {
                        Text("Clear")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .stroke(.orange.opacity(0.4), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.orange.opacity(isDark ? 0.10 : 0.06))
                )
                
                HStack(spacing: 16) {
                    AccuracyStatBox(
                        title: "Trend Hit",
                        value: metricsToShow.formattedDirectionAccuracy,
                        subtitle: "\(metricsToShow.directionsCorrect)/\(metricsToShow.evaluatedPredictions) correct",
                        color: accuracyColor(for: metricsToShow.directionAccuracyPercent)
                    )
                    
                    AccuracyStatBox(
                        title: "In Range",
                        value: metricsToShow.formattedRangeAccuracy,
                        subtitle: "\(metricsToShow.withinRangeCount)/\(metricsToShow.evaluatedPredictions) hit",
                        color: accuracyColor(for: metricsToShow.rangeAccuracyPercent)
                    )
                    
                    AccuracyStatBox(
                        title: "Avg Miss",
                        value: metricsToShow.formattedAverageError,
                        subtitle: "price diff",
                        color: errorColor(for: metricsToShow.averagePriceError)
                    )
                }
            } else {
                // No evaluated predictions yet — show helpful status
                let totalStored = accuracyService.storedPredictions.count
                let pendingEval = accuracyService.storedPredictions.filter { $0.isReadyForEvaluation }.count
                let awaitingExpiry = totalStored - pendingEval - accuracyService.storedPredictions.filter { $0.isEvaluated }.count
                
                VStack(spacing: 10) {
                    if totalStored > 0 {
                        // Predictions exist but haven't expired yet
                        HStack(spacing: 8) {
                            // Animated progress indicator
                            ZStack {
                                Circle()
                                    .stroke(DS.Adaptive.stroke.opacity(0.3), lineWidth: 2)
                                    .frame(width: 32, height: 32)
                                
                                Circle()
                                    .trim(from: 0, to: min(CGFloat(totalStored) / 5.0, 1.0))
                                    .stroke(BrandColors.goldBase, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                    .frame(width: 32, height: 32)
                                    .rotationEffect(.degrees(-90))
                                
                                Text("\(totalStored)")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(BrandColors.goldBase)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(totalStored) prediction\(totalStored == 1 ? "" : "s") tracking")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(DS.Adaptive.textPrimary)
                                
                                if awaitingExpiry > 0 {
                                    // Show when the next prediction expires
                                    let nextExpiry = accuracyService.storedPredictions
                                        .filter { !$0.isEvaluated && !$0.isReadyForEvaluation }
                                        .min(by: { $0.targetDate < $1.targetDate })
                                    
                                    if let next = nextExpiry {
                                        let timeLeft = next.targetDate.timeIntervalSinceNow
                                        let timeString: String = {
                                            if timeLeft < 3600 { return "\(Int(timeLeft / 60))m" }
                                            if timeLeft < 86400 { return "\(Int(timeLeft / 3600))h \(Int((timeLeft.truncatingRemainder(dividingBy: 3600)) / 60))m" }
                                            return "\(Int(timeLeft / 86400))d"
                                        }()
                                        Text("Next result in ~\(timeString)")
                                            .font(.system(size: 11))
                                            .foregroundStyle(DS.Adaptive.textTertiary)
                                    }
                                }
                                
                                if pendingEval > 0 {
                                    Text("\(pendingEval) ready to evaluate")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // Show prediction breakdown
                        let timeframes = Dictionary(grouping: accuracyService.storedPredictions.filter { !$0.isEvaluated }) { $0.timeframe }
                        if !timeframes.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(Array(timeframes.keys.sorted(by: { $0.durationSeconds < $1.durationSeconds })), id: \.rawValue) { tf in
                                    let count = timeframes[tf]?.count ?? 0
                                    HStack(spacing: 3) {
                                        Text(tf.displayName)
                                            .font(.system(size: 9, weight: .semibold))
                                        Text("×\(count)")
                                            .font(.system(size: 9, weight: .bold, design: .rounded))
                                    }
                                    .foregroundStyle(DS.Adaptive.textSecondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule()
                                            .fill(DS.Adaptive.chipBackground)
                                    )
                                }
                                Spacer()
                            }
                        }
                    } else {
                        // No predictions at all
                        Image(systemName: "chart.bar.doc.horizontal")
                            .font(.system(size: 20))
                            .foregroundStyle(DS.Adaptive.textTertiary)
                        
                        Text("Generate predictions to start tracking")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DS.Adaptive.textSecondary)
                        
                        Text("We'll compare predicted vs actual prices once each prediction's timeframe expires")
                            .font(.system(size: 11))
                            .foregroundStyle(DS.Adaptive.textTertiary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        }
        .padding(14)
        .background(
            ZStack {
                // Base card background
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
                
                // Subtle top gradient for depth
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                BrandColors.goldBase.opacity(isDark ? 0.04 : 0.02),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            DS.Adaptive.stroke.opacity(0.5),
                            DS.Adaptive.stroke.opacity(0.3)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .alert("Clear Prediction History?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                accuracyService.clearLegacyPredictions()
            }
        } message: {
            let count = accuracyService.legacyPredictionCount
            Text("This will permanently remove \(count) prediction\(count == 1 ? "" : "s") from the previous AI model. This data is stored locally and cannot be recovered.")
        }
        .task {
            // Evaluate any pending predictions when this card appears
            let pendingCount = accuracyService.storedPredictions.filter { $0.isReadyForEvaluation }.count
            if pendingCount > 0 {
                await accuracyService.evaluatePendingPredictions()
            }
        }
    }
    
    private func accuracyColor(for percentage: Double) -> Color {
        if percentage >= 70 { return .green }
        if percentage >= 50 { return .yellow }
        return .red
    }
    
    private func errorColor(for error: Double) -> Color {
        if error <= 3 { return .green }
        if error <= 7 { return .yellow }
        return .red
    }
}

// MARK: - Accuracy Stat Box

private struct AccuracyStatBox: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
                .tracking(0.5)
                .lineLimit(1)
            
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Text(subtitle)
                .font(.system(size: 9))
                .foregroundStyle(DS.Adaptive.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(isDark ? 0.10 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(color.opacity(0.15), lineWidth: 0.5)
        )
    }
}

// MARK: - Direction Accuracy Pill

private struct DirectionAccuracyPill: View {
    let direction: PredictionDirection
    let correct: Int
    let total: Int
    
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    private var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(correct) / Double(total) * 100
    }
    
    /// Human-readable label for each direction type
    private var directionLabel: String {
        switch direction {
        case .bullish: return "Up"
        case .bearish: return "Dn"
        case .neutral: return "Flat"
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            // Direction arrow icon
            Image(systemName: direction.icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(direction.color)
            
            Text(directionLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(direction.color)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            
            // Percentage with rounded corners
            Text("\(Int(round(percentage)))%")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(isDark ? .white : .black)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            
            Text("(\(correct)/\(total))")
                .font(.system(size: 9))
                .foregroundStyle(DS.Adaptive.textTertiary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(direction.color.opacity(isDark ? 0.15 : 0.12))
        )
        .overlay(
            Capsule()
                .stroke(direction.color.opacity(0.25), lineWidth: 0.5)
        )
    }
}

// MARK: - Accuracy by Timeframe View

struct AccuracyByTimeframeView: View {
    @ObservedObject private var accuracyService = PredictionAccuracyService.shared
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Accuracy by Timeframe")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DS.Adaptive.textPrimary)
            
            ForEach(PredictionTimeframe.allCases, id: \.rawValue) { timeframe in
                if let metrics = accuracyService.metrics.metricsByTimeframe[timeframe] {
                    TimeframeAccuracyRow(metrics: metrics)
                }
            }
            
            if accuracyService.metrics.metricsByTimeframe.isEmpty {
                Text("No timeframe data available yet")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Adaptive.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(DS.Adaptive.stroke.opacity(0.5), lineWidth: 1)
        )
    }
}

private struct TimeframeAccuracyRow: View {
    let metrics: TimeframeMetrics
    
    var body: some View {
        HStack {
            Text(metrics.timeframe.displayName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.Adaptive.textPrimary)
                .frame(width: 40, alignment: .leading)
            
            // Accuracy bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DS.Adaptive.chipBackground)
                    
                    // Fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(accuracyGradient(for: metrics.directionAccuracyPercent))
                        .frame(width: geo.size.width * CGFloat(metrics.directionAccuracyPercent / 100))
                }
            }
            .frame(height: 20)
            
            Text(String(format: "%.0f%%", metrics.directionAccuracyPercent))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.Adaptive.textPrimary)
                .frame(width: 40, alignment: .trailing)
            
            Text("(\(metrics.evaluatedPredictions))")
                .font(.system(size: 10))
                .foregroundStyle(DS.Adaptive.textTertiary)
                .frame(width: 30)
        }
    }
    
    private func accuracyGradient(for percentage: Double) -> LinearGradient {
        let color: Color = {
            if percentage >= 70 { return .green }
            if percentage >= 50 { return .yellow }
            return .red
        }()
        
        return LinearGradient(
            colors: [color.opacity(0.7), color],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - Recent Predictions List

struct RecentPredictionsView: View {
    @ObservedObject private var accuracyService = PredictionAccuracyService.shared
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Predictions")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Adaptive.textPrimary)
                
                Spacer()
                
                if accuracyService.isEvaluating {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            
            let recentPredictions = accuracyService.recentPredictions(limit: 5)
            
            if recentPredictions.isEmpty {
                Text("No evaluated predictions yet")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Adaptive.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                ForEach(recentPredictions) { prediction in
                    PredictionResultRow(prediction: prediction)
                    
                    if prediction.id != recentPredictions.last?.id {
                        Divider()
                            .background(DS.Adaptive.stroke.opacity(0.3))
                    }
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
                .stroke(DS.Adaptive.stroke.opacity(0.5), lineWidth: 1)
        )
    }
}

private struct PredictionResultRow: View {
    let prediction: StoredPrediction
    
    var body: some View {
        HStack(spacing: 12) {
            // Result icon
            Image(systemName: prediction.directionCorrect == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(prediction.directionCorrect == true ? Color.green : Color.red)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(prediction.coinSymbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.Adaptive.textPrimary)
                    
                    Text(prediction.timeframe.displayName)
                        .font(.system(size: 10))
                        .foregroundStyle(DS.Adaptive.textTertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(DS.Adaptive.chipBackground)
                        )
                }
                
                HStack(spacing: 8) {
                    // Predicted
                    HStack(spacing: 2) {
                        Image(systemName: prediction.predictedDirection.icon)
                            .font(.system(size: 9))
                        Text(String(format: "%.1f%%", prediction.predictedPriceChange))
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(prediction.predictedDirection.color)
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8))
                        .foregroundStyle(DS.Adaptive.textTertiary)
                    
                    // Actual
                    if let actualChange = prediction.actualPriceChange {
                        HStack(spacing: 2) {
                            Image(systemName: prediction.actualDirection?.icon ?? "minus")
                                .font(.system(size: 9))
                            Text(String(format: "%.1f%%", actualChange))
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(prediction.actualDirection?.color ?? DS.Adaptive.textTertiary)
                    }
                }
            }
            
            Spacer()
            
            // Error
            if let error = prediction.priceError {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.1f%%", error))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(errorColor(for: error))
                    
                    Text("error")
                        .font(.system(size: 9))
                        .foregroundStyle(DS.Adaptive.textTertiary)
                }
            }
        }
    }
    
    private func errorColor(for error: Double) -> Color {
        if error <= 3 { return .green }
        if error <= 7 { return .yellow }
        return .red
    }
}

// MARK: - Full Accuracy Dashboard View

struct PredictionAccuracyDashboardView: View {
    @ObservedObject private var accuracyService = PredictionAccuracyService.shared
    @ObservedObject private var communityService = CommunityAccuracyService.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    // Your accuracy card
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(DS.Adaptive.textSecondary)
                            Text("Your Accuracy")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DS.Adaptive.textSecondary)
                        }
                        PredictionAccuracyCard()
                    }
                    
                    // Community accuracy card
                    CommunityAccuracyCard()
                    
                    // Comparison card (if both have data)
                    if accuracyService.displayMetrics.hasEnoughData && communityService.communityMetrics.hasData {
                        AccuracyComparisonCard()
                    }
                    
                    // Timeframe breakdown
                    AccuracyByTimeframeView()
                    
                    // Confidence level breakdown
                    if accuracyService.displayMetrics.hasEnoughData {
                        ConfidenceLevelAccuracyCard()
                    }
                    
                    // Recent predictions
                    RecentPredictionsView()
                    
                    // Disclaimer
                    disclaimerSection
                }
                .padding(16)
            }
            .background(DS.Adaptive.background.ignoresSafeArea())
            .navigationTitle("Prediction Accuracy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    CSNavButton(
                        icon: "chevron.left",
                        action: { dismiss() },
                        compact: true
                    )
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            await accuracyService.evaluatePendingPredictions()
                            await communityService.sync()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(DS.Adaptive.textSecondary)
                    }
                    .disabled(accuracyService.isEvaluating || communityService.isSyncing)
                }
            }
            .task {
                // Fetch community data on appear
                await communityService.fetchCommunityMetrics()
            }
        }
    }
    
    private var disclaimerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                
                Text("About These Metrics")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.Adaptive.textSecondary)
            }
            
            Text("Past performance does not guarantee future results. Accuracy metrics are calculated from historical predictions and may not reflect future prediction quality. Crypto markets are highly volatile and unpredictable.")
                .font(.system(size: 11))
                .foregroundStyle(DS.Adaptive.textTertiary)
                .lineSpacing(2)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.orange.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Confidence Level Accuracy Card

private struct ConfidenceLevelAccuracyCard: View {
    @ObservedObject private var accuracyService = PredictionAccuracyService.shared
    
    var body: some View {
        // Use displayMetrics: shows DeepSeek-only when available, else all models
        let metricsToShow = accuracyService.displayMetrics
        
        VStack(alignment: .leading, spacing: 12) {
            Text("Accuracy by Confidence Level")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DS.Adaptive.textPrimary)
            
            HStack(spacing: 12) {
                if let high = metricsToShow.highConfidenceAccuracy {
                    ConfidenceLevelBox(
                        level: "High",
                        accuracy: high,
                        color: .green
                    )
                }
                
                if let medium = metricsToShow.mediumConfidenceAccuracy {
                    ConfidenceLevelBox(
                        level: "Medium",
                        accuracy: medium,
                        color: .yellow
                    )
                }
                
                if let low = metricsToShow.lowConfidenceAccuracy {
                    ConfidenceLevelBox(
                        level: "Low",
                        accuracy: low,
                        color: .red
                    )
                }
            }
            
            Text("Higher confidence predictions should ideally have better accuracy")
                .font(.system(size: 10))
                .foregroundStyle(DS.Adaptive.textTertiary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(DS.Adaptive.stroke.opacity(0.5), lineWidth: 1)
        )
    }
}

private struct ConfidenceLevelBox: View {
    let level: String
    let accuracy: Double
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(level)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.Adaptive.textTertiary)
                .textCase(.uppercase)
            
            Text(String(format: "%.0f%%", accuracy))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(color)
            
            Text("accurate")
                .font(.system(size: 9))
                .foregroundStyle(DS.Adaptive.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.1))
        )
    }
}

// MARK: - Inline Accuracy Badge (for embedding in other views)

struct PredictionAccuracyBadge: View {
    @ObservedObject private var accuracyService = PredictionAccuracyService.shared
    
    var body: some View {
        // Use displayMetrics: shows DeepSeek-only when available, else all models
        let metricsToShow = accuracyService.displayMetrics
        if metricsToShow.hasEnoughData {
            HStack(spacing: 4) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 10))
                
                Text("\(Int(metricsToShow.directionAccuracyPercent))% accurate")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(accuracyColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(accuracyColor.opacity(0.15))
            )
        }
    }
    
    private var accuracyColor: Color {
        let percentage = accuracyService.displayMetrics.directionAccuracyPercent
        if percentage >= 70 { return .green }
        if percentage >= 50 { return .yellow }
        return .red
    }
}

// MARK: - Community Accuracy Card

/// Card showing community-wide accuracy statistics
/// Uses Firebase global accuracy when available, falls back to CloudKit/baseline
struct CommunityAccuracyCard: View {
    @ObservedObject private var communityService = CommunityAccuracyService.shared
    @ObservedObject private var firebaseGlobalAccuracy = FirebaseGlobalAccuracyViewModel.shared
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    
    /// Use Firebase data if available, otherwise use CloudKit/baseline
    private var useFirebaseData: Bool {
        firebaseGlobalAccuracy.hasEnoughData
    }
    
    private var totalPredictions: Int {
        useFirebaseData ? firebaseGlobalAccuracy.totalPredictions : communityService.communityMetrics.totalPredictions
    }
    
    private var directionAccuracy: Double {
        useFirebaseData ? firebaseGlobalAccuracy.directionAccuracyPercent : communityService.communityMetrics.directionAccuracy
    }
    
    private var rangeAccuracy: Double {
        useFirebaseData ? firebaseGlobalAccuracy.rangeAccuracyPercent : communityService.communityMetrics.rangeAccuracy
    }
    
    private var averageError: Double {
        useFirebaseData ? firebaseGlobalAccuracy.averageError : communityService.communityMetrics.averageError
    }
    
    private var hasData: Bool {
        useFirebaseData ? firebaseGlobalAccuracy.hasData : communityService.communityMetrics.hasData
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "globe.americas.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.blue)
                
                Text("Global Accuracy")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Adaptive.textPrimary)
                
                Spacer()
                
                // Data source indicator
                if useFirebaseData {
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8))
                        Text("LIVE")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.green.opacity(0.15))
                    )
                }
            }
            
            // Explanation
            Text(useFirebaseData ?
                "Accuracy data from \(totalPredictions.formatted()) CryptoSage predictions. This data helps the AI calibrate future predictions." :
                "Benchmark accuracy data helps the AI calibrate predictions. Combined with your personal history, this improves confidence estimates.")
                .font(.system(size: 10))
                .foregroundStyle(DS.Adaptive.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            
            if hasData {
                // Main stats row
                HStack(spacing: 16) {
                    CommunityStatBox(
                        title: "Trend Hit",
                        value: String(format: "%.0f%%", directionAccuracy),
                        subtitle: "\(totalPredictions.formatted()) total",
                        color: accuracyColor(for: directionAccuracy)
                    )
                    
                    CommunityStatBox(
                        title: "In Range",
                        value: String(format: "%.0f%%", rangeAccuracy),
                        subtitle: "price hit",
                        color: accuracyColor(for: rangeAccuracy)
                    )
                    
                    CommunityStatBox(
                        title: "Avg Miss",
                        value: String(format: "%.1f%%", averageError),
                        subtitle: "price diff",
                        color: errorColor(for: averageError)
                    )
                }
                
                // Direction breakdown - show Firebase data if available
                if useFirebaseData && !firebaseGlobalAccuracy.directionBreakdown.isEmpty {
                    Divider()
                        .background(DS.Adaptive.stroke.opacity(0.5))
                    
                    HStack(spacing: 12) {
                        if let bullishAccuracy = firebaseGlobalAccuracy.directionBreakdown["bullish"] {
                            FirebaseDirectionPill(
                                direction: .bullish,
                                accuracy: bullishAccuracy
                            )
                        }
                        
                        if let bearishAccuracy = firebaseGlobalAccuracy.directionBreakdown["bearish"] {
                            FirebaseDirectionPill(
                                direction: .bearish,
                                accuracy: bearishAccuracy
                            )
                        }
                        
                        if let neutralAccuracy = firebaseGlobalAccuracy.directionBreakdown["neutral"] {
                            FirebaseDirectionPill(
                                direction: .neutral,
                                accuracy: neutralAccuracy
                            )
                        }
                        
                        Spacer()
                    }
                } else if communityService.communityMetrics.directionBreakdown.bullish.total > 0 ||
                          communityService.communityMetrics.directionBreakdown.bearish.total > 0 {
                    Divider()
                        .background(DS.Adaptive.stroke.opacity(0.5))
                    
                    HStack(spacing: 12) {
                        CommunityDirectionPill(
                            direction: .bullish,
                            stats: communityService.communityMetrics.directionBreakdown.bullish
                        )
                        
                        CommunityDirectionPill(
                            direction: .bearish,
                            stats: communityService.communityMetrics.directionBreakdown.bearish
                        )
                        
                        if communityService.communityMetrics.directionBreakdown.neutral.total > 0 {
                            CommunityDirectionPill(
                                direction: .neutral,
                                stats: communityService.communityMetrics.directionBreakdown.neutral
                            )
                        }
                        
                        Spacer()
                    }
                }
                
                // Reliability/building data indicator
                if !useFirebaseData && !communityService.communityMetrics.isReliable {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10))
                        Text("Building data... \(totalPredictions)/1000 predictions")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.orange)
                    .padding(.top, 4)
                } else if useFirebaseData && totalPredictions < 1000 {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 10))
                        Text("Accuracy improves with more data (\(totalPredictions)/1000)")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.blue)
                    .padding(.top, 4)
                }
            } else {
                // No data yet - loading or error
                VStack(spacing: 8) {
                    if firebaseGlobalAccuracy.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                        
                        Text("Loading global accuracy data...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DS.Adaptive.textSecondary)
                    } else if firebaseGlobalAccuracy.error != nil || communityService.syncError != nil {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 24))
                            .foregroundStyle(DS.Adaptive.textTertiary)
                        
                        Text("Unable to load global data")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DS.Adaptive.textSecondary)
                        
                        Button {
                            Task {
                                await firebaseGlobalAccuracy.fetchMetrics(force: true)
                                await communityService.fetchCommunityMetrics(force: true)
                            }
                        } label: {
                            Text("Retry")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.blue)
                        }
                    } else {
                        Image(systemName: "globe.americas")
                            .font(.system(size: 24))
                            .foregroundStyle(DS.Adaptive.textTertiary)
                        
                        Text("Global data loading...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DS.Adaptive.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
        .task {
            // Fetch Firebase global accuracy on appear
            await firebaseGlobalAccuracy.fetchMetrics()
        }
    }
    
    private func accuracyColor(for percentage: Double) -> Color {
        if percentage >= 70 { return .green }
        if percentage >= 50 { return .yellow }
        return .red
    }
    
    private func errorColor(for error: Double) -> Color {
        if error <= 3 { return .green }
        if error <= 7 { return .yellow }
        return .red
    }
}

// MARK: - Firebase Direction Pill

/// Pill showing accuracy for a specific direction from Firebase data
private struct FirebaseDirectionPill: View {
    let direction: PredictionDirection
    let accuracy: Double
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: direction == .bullish ? "arrow.up" :
                            direction == .bearish ? "arrow.down" : "arrow.right")
                .font(.system(size: 8, weight: .bold))
            
            Text(direction.rawValue.capitalized)
                .font(.system(size: 9, weight: .medium))
            
            Text(String(format: "%.0f%%", accuracy))
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(direction == .bullish ? .green :
                        direction == .bearish ? .red : .yellow)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill((direction == .bullish ? Color.green :
                      direction == .bearish ? Color.red : Color.yellow).opacity(0.12))
        )
    }
}

// MARK: - Community Stat Box

private struct CommunityStatBox: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(DS.Adaptive.textTertiary)
                .tracking(0.5)
                .lineLimit(1)
            
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Text(subtitle)
                .font(.system(size: 8))
                .foregroundStyle(DS.Adaptive.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Community Direction Pill

private struct CommunityDirectionPill: View {
    let direction: PredictionDirection
    let stats: DirectionStats
    
    private var directionLabel: String {
        switch direction {
        case .bullish: return "Up"
        case .bearish: return "Dn"
        case .neutral: return "Flat"
        }
    }
    
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: direction.icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(direction.color)
            
            Text(directionLabel)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(DS.Adaptive.textSecondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            
            Text("\(Int(stats.accuracy))%")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(DS.Adaptive.textPrimary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(direction.color.opacity(0.12))
                .overlay(
                    Capsule()
                        .stroke(direction.color.opacity(0.2), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Accuracy Comparison Card

/// Card comparing user's accuracy to community average
struct AccuracyComparisonCard: View {
    @ObservedObject private var communityService = CommunityAccuracyService.shared
    
    var body: some View {
        let comparisons = communityService.comparisonInsights()
        
        if !comparisons.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.purple)
                    
                    Text("You vs Community")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.Adaptive.textPrimary)
                }
                
                ForEach(comparisons, id: \.metric) { comparison in
                    ComparisonRow(comparison: comparison)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.purple.opacity(0.3), lineWidth: 1)
            )
        }
    }
}

private struct ComparisonRow: View {
    let comparison: AccuracyComparison
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(comparison.metric)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.Adaptive.textSecondary)
                
                Spacer()
                
                // Difference badge
                HStack(spacing: 2) {
                    Image(systemName: comparison.isAboveCommunity ? "arrow.up" : "arrow.down")
                        .font(.system(size: 9, weight: .bold))
                    Text(String(format: "%+.0f%%", comparison.difference))
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(comparison.isAboveCommunity ? .green : .orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill((comparison.isAboveCommunity ? Color.green : Color.orange).opacity(0.15))
                )
            }
            
            // Bar comparison
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("You")
                        .font(.system(size: 9))
                        .foregroundStyle(DS.Adaptive.textTertiary)
                    
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(DS.Adaptive.chipBackground)
                            
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.green)
                                .frame(width: geo.size.width * CGFloat(min(comparison.yourValue, 100) / 100))
                        }
                    }
                    .frame(height: 8)
                    
                    Text(String(format: "%.0f%%", comparison.yourValue))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.Adaptive.textPrimary)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Community")
                        .font(.system(size: 9))
                        .foregroundStyle(DS.Adaptive.textTertiary)
                    
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(DS.Adaptive.chipBackground)
                            
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.blue)
                                .frame(width: geo.size.width * CGFloat(min(comparison.communityValue, 100) / 100))
                        }
                    }
                    .frame(height: 8)
                    
                    Text(String(format: "%.0f%%", comparison.communityValue))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.Adaptive.textPrimary)
                }
            }
            
            // Insight
            Text(comparison.insight)
                .font(.system(size: 10))
                .foregroundStyle(DS.Adaptive.textTertiary)
                .italic()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(DS.Adaptive.chipBackground.opacity(0.5))
        )
    }
}

// MARK: - Community Contribution Card

/// Card with toggle for user to opt in/out of community contributions
struct CommunityContributionCard: View {
    @ObservedObject private var communityService = CommunityAccuracyService.shared
    @ObservedObject private var accuracyService = PredictionAccuracyService.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.green)
                        
                        Text("Help Improve Predictions")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DS.Adaptive.textPrimary)
                    }
                    
                    Text("Share your anonymized accuracy data to help everyone get better predictions")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Adaptive.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
                
                Toggle("", isOn: $communityService.isContributionEnabled)
                    .labelsHidden()
                    .tint(.green)
            }
            
            // What's shared explanation
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.blue)
                    Text("What's Shared (Privacy-First)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.Adaptive.textSecondary)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    sharedDataRow(icon: "checkmark", text: "Direction accuracy % (bullish/bearish/neutral)", included: true)
                    sharedDataRow(icon: "checkmark", text: "Price range hit rate %", included: true)
                    sharedDataRow(icon: "checkmark", text: "Accuracy by timeframe (1H, 24H, 7D, etc)", included: true)
                    sharedDataRow(icon: "xmark", text: "Your actual predictions or prices", included: false)
                    sharedDataRow(icon: "xmark", text: "Portfolio, coins, or personal data", included: false)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.08))
            )
            
            // Contribution status
            if communityService.isContributionEnabled {
                HStack(spacing: 8) {
                    if let lastContrib = communityService.lastContributionDate {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.green)
                        
                        Text("Last contributed: \(lastContrib.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 10))
                            .foregroundStyle(DS.Adaptive.textTertiary)
                    } else if accuracyService.metrics.evaluatedPredictions >= 5 {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.blue)
                        
                        Text("Ready to contribute \(accuracyService.metrics.evaluatedPredictions) predictions")
                            .font(.system(size: 10))
                            .foregroundStyle(DS.Adaptive.textTertiary)
                        
                        Spacer()
                        
                        Button {
                            Task { await communityService.contributeLocalData() }
                        } label: {
                            Text("Contribute Now")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.blue)
                        }
                    } else {
                        Image(systemName: "hourglass")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                        
                        Text("Need \(5 - accuracyService.metrics.evaluatedPredictions) more predictions to contribute")
                            .font(.system(size: 10))
                            .foregroundStyle(DS.Adaptive.textTertiary)
                    }
                    
                    Spacer()
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
                .stroke(communityService.isContributionEnabled ? Color.green.opacity(0.3) : DS.Adaptive.stroke.opacity(0.5), lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private func sharedDataRow(icon: String, text: String, included: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: included ? "checkmark.circle.fill" : "xmark.circle")
                .font(.system(size: 9))
                .foregroundStyle(included ? .green : .red.opacity(0.6))
            Text(text)
                .font(.system(size: 9))
                .foregroundStyle(included ? DS.Adaptive.textSecondary : DS.Adaptive.textTertiary)
        }
    }
}
