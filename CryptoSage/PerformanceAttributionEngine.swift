//
//  PerformanceAttributionEngine.swift
//  CryptoSage
//
//  Performance Attribution Engine — Tracks AI prediction accuracy,
//  strategy performance vs benchmarks, and signal source attribution.
//

import Foundation
import Combine

// MARK: - Prediction Tracking

/// Tracks a prediction from creation to resolution.
public struct TrackedPrediction: Codable, Identifiable {
    public let id: UUID
    public let symbol: String
    public let source: PredictionSource
    public let createdAt: Date
    public let predictedDirection: String        // "bullish", "bearish", "neutral"
    public let predictedScore: Double            // -100 to +100
    public let confidenceAtCreation: Double      // 0-1
    public let priceAtCreation: Double
    public let timeframeHours: Double            // prediction horizon

    // Resolution (filled in when prediction expires)
    public var resolvedAt: Date?
    public var priceAtResolution: Double?
    public var actualChangePct: Double?
    public var wasCorrect: Bool?
    public var profitIfFollowed: Double?          // estimated % gain/loss

    public var isResolved: Bool { resolvedAt != nil }
    public var isExpired: Bool { Date() > createdAt.addingTimeInterval(timeframeHours * 3600) }

    public var targetDate: Date {
        createdAt.addingTimeInterval(timeframeHours * 3600)
    }
}

public enum PredictionSource: String, Codable, CaseIterable {
    case sentiment = "Sentiment"
    case aiPrediction = "AI Prediction"
    case technicalAnalysis = "Technical Analysis"
    case sageAlgorithm = "Sage Algorithm"
    case smartEngine = "Smart Engine"

    public var displayName: String { rawValue }
}

// MARK: - Strategy Performance Record

public struct StrategyPerformanceRecord: Codable, Identifiable {
    public let id: UUID
    public let strategyName: String
    public let period: PerformancePeriod
    public let startDate: Date
    public let endDate: Date

    // Returns
    public let totalReturnPct: Double
    public let benchmarkReturnPct: Double        // BTC or S&P500
    public let alphaReturnPct: Double             // excess return vs benchmark

    // Risk metrics
    public let sharpeRatio: Double
    public let sortinoRatio: Double
    public let maxDrawdownPct: Double
    public let volatilityPct: Double

    // Trade statistics
    public let totalTrades: Int
    public let winningTrades: Int
    public let losingTrades: Int
    public let averageWinPct: Double
    public let averageLossPct: Double
    public let profitFactor: Double

    // Attribution
    public let sentimentContribution: Double     // how much sentiment helped/hurt
    public let predictionContribution: Double
    public let technicalContribution: Double
    public let algorithmContribution: Double

    public var winRate: Double {
        totalTrades > 0 ? Double(winningTrades) / Double(totalTrades) * 100 : 0
    }

    public var expectancy: Double {
        let winProb = winRate / 100.0
        let lossProb = 1.0 - winProb
        return (winProb * averageWinPct) - (lossProb * abs(averageLossPct))
    }
}

public enum PerformancePeriod: String, Codable, CaseIterable {
    case day = "1D"
    case week = "1W"
    case month = "1M"
    case quarter = "3M"
    case year = "1Y"
    case allTime = "All"

    public var displayName: String { rawValue }

    public var timeInterval: TimeInterval {
        switch self {
        case .day:     return 86400
        case .week:    return 604800
        case .month:   return 2592000
        case .quarter: return 7776000
        case .year:    return 31536000
        case .allTime: return .infinity
        }
    }
}

// MARK: - Signal Source Accuracy

public struct SignalSourceAccuracy: Identifiable {
    public let id = UUID()
    public let source: PredictionSource
    public let totalPredictions: Int
    public let correctPredictions: Int
    public let averageConfidence: Double
    public let averageReturnWhenFollowed: Double
    public let bestPrediction: Double?           // best return from this source
    public let worstPrediction: Double?          // worst return from this source

    public var accuracy: Double {
        totalPredictions > 0 ? Double(correctPredictions) / Double(totalPredictions) * 100 : 0
    }

    public var reliabilityScore: Double {
        // Combines accuracy with consistency
        let accuracyFactor = accuracy / 100.0
        let confidenceCalibration = 1.0 - abs(averageConfidence - accuracyFactor / 100.0)
        return (accuracyFactor * 0.6 + confidenceCalibration * 0.4) * 100
    }
}

// MARK: - Performance Attribution Engine

@MainActor
public final class PerformanceAttributionEngine: ObservableObject {

    // MARK: - Singleton
    public static let shared = PerformanceAttributionEngine()

    // MARK: - Published State
    @Published public var trackedPredictions: [TrackedPrediction] = []
    @Published public var performanceHistory: [StrategyPerformanceRecord] = []
    @Published public var sourceAccuracies: [SignalSourceAccuracy] = []
    @Published public var overallAccuracy: Double = 0
    @Published public var isCalculating: Bool = false

    // MARK: - Persistence Keys
    private let predictionsKey = "TrackedPredictions"
    private let performanceKey = "PerformanceHistory"
    private let maxPredictions = 1000

    private init() {
        loadPredictions()
        loadPerformance()
        recalculateAccuracies()
    }

    // MARK: - Prediction Tracking

    /// Record a new prediction from any signal source.
    public func trackPrediction(
        symbol: String,
        source: PredictionSource,
        direction: String,
        score: Double,
        confidence: Double,
        currentPrice: Double,
        timeframeHours: Double
    ) {
        let prediction = TrackedPrediction(
            id: UUID(),
            symbol: symbol,
            source: source,
            createdAt: Date(),
            predictedDirection: direction,
            predictedScore: score,
            confidenceAtCreation: confidence,
            priceAtCreation: currentPrice,
            timeframeHours: timeframeHours,
            resolvedAt: nil,
            priceAtResolution: nil,
            actualChangePct: nil,
            wasCorrect: nil,
            profitIfFollowed: nil
        )

        trackedPredictions.append(prediction)

        // Cap stored predictions
        if trackedPredictions.count > maxPredictions {
            trackedPredictions = Array(trackedPredictions.suffix(maxPredictions))
        }

        savePredictions()
    }

    /// Track a prediction from a SmartTradingDecision.
    public func trackDecision(_ decision: SmartTradingDecision) {
        let direction: String
        switch decision.action {
        case .strongBuy, .buy, .accumulate: direction = "bullish"
        case .sell, .strongSell, .reducePosition: direction = "bearish"
        case .hold: direction = "neutral"
        }

        trackPrediction(
            symbol: decision.symbol,
            source: .smartEngine,
            direction: direction,
            score: decision.conviction * (direction == "bearish" ? -1 : 1),
            confidence: decision.conviction / 100.0,
            currentPrice: decision.currentPrice,
            timeframeHours: 24 // default 24h horizon for engine decisions
        )
    }

    /// Resolve expired predictions with current prices.
    public func resolveExpiredPredictions(currentPrices: [String: Double]) {
        let now = Date()
        var updated = false

        for i in trackedPredictions.indices {
            let prediction = trackedPredictions[i]
            guard !prediction.isResolved, prediction.isExpired else { continue }
            guard let currentPrice = currentPrices[prediction.symbol.lowercased()],
                  prediction.priceAtCreation > 0 else { continue }

            let changePct = (currentPrice - prediction.priceAtCreation) / prediction.priceAtCreation * 100

            let wasCorrect: Bool
            switch prediction.predictedDirection {
            case "bullish":  wasCorrect = changePct > 0
            case "bearish":  wasCorrect = changePct < 0
            default:         wasCorrect = abs(changePct) < 2 // neutral = price stayed flat
            }

            // Calculate profit if the prediction was followed
            let profitIfFollowed: Double
            switch prediction.predictedDirection {
            case "bullish":  profitIfFollowed = changePct   // bought → gain from price increase
            case "bearish":  profitIfFollowed = -changePct  // sold/shorted → gain from price decrease
            default:         profitIfFollowed = 0
            }

            trackedPredictions[i].resolvedAt = now
            trackedPredictions[i].priceAtResolution = currentPrice
            trackedPredictions[i].actualChangePct = changePct
            trackedPredictions[i].wasCorrect = wasCorrect
            trackedPredictions[i].profitIfFollowed = profitIfFollowed
            updated = true
        }

        if updated {
            savePredictions()
            recalculateAccuracies()
        }
    }

    // MARK: - Accuracy Calculation

    /// Recalculate accuracy metrics for all signal sources.
    public func recalculateAccuracies() {
        let resolved = trackedPredictions.filter { $0.isResolved }
        guard !resolved.isEmpty else {
            sourceAccuracies = []
            overallAccuracy = 0
            return
        }

        var accuracies: [SignalSourceAccuracy] = []

        for source in PredictionSource.allCases {
            let sourcePredictions = resolved.filter { $0.source == source }
            guard !sourcePredictions.isEmpty else { continue }

            let correct = sourcePredictions.filter { $0.wasCorrect == true }.count
            let avgConfidence = sourcePredictions.map(\.confidenceAtCreation).reduce(0, +) / Double(sourcePredictions.count)
            let returns = sourcePredictions.compactMap(\.profitIfFollowed)
            let avgReturn = returns.isEmpty ? 0 : returns.reduce(0, +) / Double(returns.count)

            let accuracy = SignalSourceAccuracy(
                source: source,
                totalPredictions: sourcePredictions.count,
                correctPredictions: correct,
                averageConfidence: avgConfidence,
                averageReturnWhenFollowed: avgReturn,
                bestPrediction: returns.max(),
                worstPrediction: returns.min()
            )
            accuracies.append(accuracy)
        }

        sourceAccuracies = accuracies.sorted { $0.accuracy > $1.accuracy }

        // Overall accuracy
        let totalCorrect = resolved.filter { $0.wasCorrect == true }.count
        overallAccuracy = Double(totalCorrect) / Double(resolved.count) * 100
    }

    // MARK: - Performance Benchmarking

    /// Generate a performance record for a given period.
    public func generatePerformanceRecord(
        strategyName: String,
        period: PerformancePeriod,
        decisions: [SmartTradingDecision],
        portfolioReturns: [Double],
        benchmarkReturns: [Double]
    ) -> StrategyPerformanceRecord {
        isCalculating = true
        defer { isCalculating = false }

        let totalReturn = portfolioReturns.reduce(0, +)
        let benchmarkReturn = benchmarkReturns.reduce(0, +)
        let alpha = totalReturn - benchmarkReturn

        // Risk metrics
        let sharpe = calculateSharpeRatio(returns: portfolioReturns)
        let sortino = calculateSortinoRatio(returns: portfolioReturns)
        let maxDD = calculateMaxDrawdown(returns: portfolioReturns)
        let vol = calculateVolatility(returns: portfolioReturns)

        // Trade stats from decisions
        let trades = decisions.filter { $0.action != .hold }
        let winners = trades.filter { $0.conviction >= 60 } // proxy: high conviction trades
        let losers = trades.filter { $0.conviction < 40 }

        // Attribution
        let sentimentAttr = calculateSourceAttribution(decisions: decisions, keyPath: \.sentimentSignal)
        let predictionAttr = calculateSourceAttribution(decisions: decisions, keyPath: \.predictionSignal)
        let technicalAttr = calculateSourceAttribution(decisions: decisions, keyPath: \.technicalSignal)
        let algorithmAttr = calculateSourceAttribution(decisions: decisions, keyPath: \.algorithmSignal)

        let record = StrategyPerformanceRecord(
            id: UUID(),
            strategyName: strategyName,
            period: period,
            startDate: Date().addingTimeInterval(-period.timeInterval),
            endDate: Date(),
            totalReturnPct: totalReturn,
            benchmarkReturnPct: benchmarkReturn,
            alphaReturnPct: alpha,
            sharpeRatio: sharpe,
            sortinoRatio: sortino,
            maxDrawdownPct: maxDD,
            volatilityPct: vol,
            totalTrades: trades.count,
            winningTrades: winners.count,
            losingTrades: losers.count,
            averageWinPct: 0, // would need actual trade results
            averageLossPct: 0,
            profitFactor: losers.isEmpty ? 0 : Double(winners.count) / Double(max(losers.count, 1)),
            sentimentContribution: sentimentAttr,
            predictionContribution: predictionAttr,
            technicalContribution: technicalAttr,
            algorithmContribution: algorithmAttr
        )

        performanceHistory.append(record)
        savePerformance()

        return record
    }

    // MARK: - Risk Metrics

    private func calculateSharpeRatio(returns: [Double], riskFreeRate: Double = 0.04) -> Double {
        guard returns.count >= 2 else { return 0 }
        let avgReturn = returns.reduce(0, +) / Double(returns.count)
        let vol = calculateVolatility(returns: returns)
        guard vol > 0 else { return 0 }
        let annualizedReturn = avgReturn * 365
        return (annualizedReturn - riskFreeRate) / vol
    }

    private func calculateSortinoRatio(returns: [Double], riskFreeRate: Double = 0.04) -> Double {
        guard returns.count >= 2 else { return 0 }
        let avgReturn = returns.reduce(0, +) / Double(returns.count)
        let downside = returns.filter { $0 < 0 }
        guard !downside.isEmpty else { return avgReturn > 0 ? 3.0 : 0 }

        let downsideVariance = downside.map { pow($0, 2) }.reduce(0, +) / Double(downside.count)
        let downsideDeviation = sqrt(downsideVariance) * sqrt(365)
        guard downsideDeviation > 0 else { return 0 }

        let annualizedReturn = avgReturn * 365
        return (annualizedReturn - riskFreeRate) / downsideDeviation
    }

    private func calculateMaxDrawdown(returns: [Double]) -> Double {
        guard !returns.isEmpty else { return 0 }

        var peak: Double = 0
        var cumReturn: Double = 0
        var maxDD: Double = 0

        for ret in returns {
            cumReturn += ret
            peak = max(peak, cumReturn)
            let drawdown = peak - cumReturn
            maxDD = max(maxDD, drawdown)
        }

        return maxDD
    }

    private func calculateVolatility(returns: [Double]) -> Double {
        guard returns.count >= 2 else { return 0 }
        let mean = returns.reduce(0, +) / Double(returns.count)
        let variance = returns.map { pow($0 - mean, 2) }.reduce(0, +) / Double(returns.count - 1)
        return sqrt(variance) * sqrt(365)
    }

    // MARK: - Source Attribution

    private func calculateSourceAttribution(
        decisions: [SmartTradingDecision],
        keyPath: KeyPath<SmartTradingDecision, SignalContribution>
    ) -> Double {
        guard !decisions.isEmpty else { return 0 }

        let contributions = decisions.map { decision -> Double in
            let signal = decision[keyPath: keyPath]
            return signal.weightedScore
        }

        return contributions.reduce(0, +) / Double(contributions.count)
    }

    // MARK: - Dashboard Data

    /// Get a summary of the engine's performance for display.
    public var performanceSummary: PerformanceSummary {
        let resolved = trackedPredictions.filter { $0.isResolved }
        let recent = resolved.filter { $0.resolvedAt ?? Date() > Date().addingTimeInterval(-604800) } // last 7 days

        return PerformanceSummary(
            totalPredictions: trackedPredictions.count,
            resolvedPredictions: resolved.count,
            pendingPredictions: trackedPredictions.filter { !$0.isResolved && !$0.isExpired }.count,
            overallAccuracy: overallAccuracy,
            recentAccuracy: recent.isEmpty ? 0 : Double(recent.filter { $0.wasCorrect == true }.count) / Double(recent.count) * 100,
            bestSource: sourceAccuracies.first,
            worstSource: sourceAccuracies.last,
            avgReturn: resolved.compactMap(\.profitIfFollowed).reduce(0, +) / max(Double(resolved.count), 1)
        )
    }

    // MARK: - Persistence

    private func savePredictions() {
        if let data = try? JSONEncoder().encode(trackedPredictions) {
            UserDefaults.standard.set(data, forKey: predictionsKey)
        }
    }

    private func loadPredictions() {
        if let data = UserDefaults.standard.data(forKey: predictionsKey),
           let predictions = try? JSONDecoder().decode([TrackedPrediction].self, from: data) {
            trackedPredictions = predictions
        }
    }

    private func savePerformance() {
        if let data = try? JSONEncoder().encode(performanceHistory) {
            UserDefaults.standard.set(data, forKey: performanceKey)
        }
    }

    private func loadPerformance() {
        if let data = UserDefaults.standard.data(forKey: performanceKey),
           let history = try? JSONDecoder().decode([StrategyPerformanceRecord].self, from: data) {
            performanceHistory = history
        }
    }

    /// Clear all tracked data.
    public func reset() {
        trackedPredictions.removeAll()
        performanceHistory.removeAll()
        sourceAccuracies.removeAll()
        overallAccuracy = 0
        savePredictions()
        savePerformance()
    }
}

// MARK: - Performance Summary

public struct PerformanceSummary {
    public let totalPredictions: Int
    public let resolvedPredictions: Int
    public let pendingPredictions: Int
    public let overallAccuracy: Double
    public let recentAccuracy: Double          // last 7 days
    public let bestSource: SignalSourceAccuracy?
    public let worstSource: SignalSourceAccuracy?
    public let avgReturn: Double
}
