//
//  SmartTradingEngine.swift
//  CryptoSage
//
//  AI Trading Intelligence - Core Decision Engine
//  The "brain" that fuses all AI signals into intelligent trading decisions.
//

import Foundation
import Combine
import SwiftUI

// MARK: - Smart Trading Decision Model

/// A unified trading decision produced by the SmartTradingEngine,
/// combining sentiment, predictions, technicals, and risk analysis.
public struct SmartTradingDecision: Codable, Identifiable {
    public let id: UUID
    public let symbol: String
    public let coinName: String
    public let timestamp: Date

    // --- Core Decision ---
    public let action: SmartAction
    public let conviction: Double              // 0-100: how confident the engine is
    public let urgency: DecisionUrgency        // how time-sensitive this decision is

    // --- Position Sizing ---
    public let recommendedPositionPct: Double  // % of portfolio to allocate
    public let recommendedAmountUSD: Double    // dollar amount based on portfolio value
    public let maxPositionPct: Double          // risk-adjusted cap

    // --- Price Levels ---
    public let currentPrice: Double
    public let suggestedEntry: Double
    public let stopLoss: Double
    public let takeProfit: Double
    public let riskRewardRatio: Double

    // --- Signal Breakdown ---
    public let sentimentSignal: SignalContribution
    public let predictionSignal: SignalContribution
    public let technicalSignal: SignalContribution
    public let algorithmSignal: SignalContribution
    public let riskSignal: SignalContribution

    // --- Context ---
    public let marketRegime: String
    public let fearGreedValue: Int
    public let fearGreedClassification: String
    public let reasoning: [String]             // human-readable reasons
    public let riskWarnings: [String]          // what could go wrong

    // --- Metadata ---
    public let signalSourceCount: Int          // how many signals contributed
    public let dataFreshness: DataFreshness    // how recent the underlying data is

    // MARK: - Computed Properties

    public var riskPct: Double {
        guard currentPrice > 0 else { return 0 }
        return abs(currentPrice - stopLoss) / currentPrice * 100
    }

    public var rewardPct: Double {
        guard currentPrice > 0 else { return 0 }
        return abs(takeProfit - currentPrice) / currentPrice * 100
    }

    public var isActionable: Bool {
        conviction >= 60 && action != .hold && signalSourceCount >= 2
    }

    public var confidenceLabel: String {
        switch conviction {
        case 80...100: return "Very High"
        case 65..<80:  return "High"
        case 50..<65:  return "Moderate"
        case 35..<50:  return "Low"
        default:       return "Very Low"
        }
    }

    public var summaryText: String {
        "\(action.displayName) \(symbol.uppercased()) — \(confidenceLabel) conviction (\(Int(conviction))%)"
    }
}

// MARK: - Supporting Types

public enum SmartAction: String, Codable, CaseIterable {
    case strongBuy = "strong_buy"
    case buy = "buy"
    case accumulate = "accumulate"   // DCA in slowly
    case hold = "hold"
    case reducePosition = "reduce"   // trim position
    case sell = "sell"
    case strongSell = "strong_sell"

    public var displayName: String {
        switch self {
        case .strongBuy:      return "Strong Buy"
        case .buy:            return "Buy"
        case .accumulate:     return "Accumulate"
        case .hold:           return "Hold"
        case .reducePosition: return "Reduce Position"
        case .sell:           return "Sell"
        case .strongSell:     return "Strong Sell"
        }
    }

    public var icon: String {
        switch self {
        case .strongBuy:      return "arrow.up.circle.fill"
        case .buy:            return "arrow.up.circle"
        case .accumulate:     return "plus.circle"
        case .hold:           return "pause.circle"
        case .reducePosition: return "minus.circle"
        case .sell:           return "arrow.down.circle"
        case .strongSell:     return "arrow.down.circle.fill"
        }
    }

    public var color: Color {
        switch self {
        case .strongBuy:      return .green
        case .buy:            return .green.opacity(0.8)
        case .accumulate:     return .mint
        case .hold:           return .gray
        case .reducePosition: return .orange
        case .sell:           return .red.opacity(0.8)
        case .strongSell:     return .red
        }
    }

    /// Numeric score from -100 (strong sell) to +100 (strong buy)
    public var numericScore: Double {
        switch self {
        case .strongBuy:      return 100
        case .buy:            return 70
        case .accumulate:     return 40
        case .hold:           return 0
        case .reducePosition: return -40
        case .sell:           return -70
        case .strongSell:     return -100
        }
    }
}

public enum DecisionUrgency: String, Codable, CaseIterable {
    case immediate = "immediate"    // Act now — breakout/breakdown
    case soon = "soon"              // Within hours
    case standard = "standard"      // Within a day
    case patient = "patient"        // DCA opportunity, no rush

    public var displayName: String {
        switch self {
        case .immediate: return "Act Now"
        case .soon:      return "Within Hours"
        case .standard:  return "Today"
        case .patient:   return "No Rush"
        }
    }
}

public enum DataFreshness: String, Codable {
    case realtime = "realtime"    // < 1 min old
    case fresh = "fresh"          // < 5 min old
    case recent = "recent"        // < 30 min old
    case stale = "stale"          // > 30 min old
}

/// Contribution of a single signal source to the overall decision
public struct SignalContribution: Codable {
    public let source: String           // e.g., "Fear & Greed Index"
    public let score: Double            // -100 to +100
    public let weight: Double           // 0-1, how much this source influences the decision
    public let confidence: Double       // 0-1, how reliable this signal is right now
    public let direction: String        // "bullish", "bearish", "neutral"
    public let details: String          // human-readable explanation

    public var weightedScore: Double {
        score * weight * confidence
    }

    public static func neutral(source: String) -> SignalContribution {
        SignalContribution(
            source: source,
            score: 0,
            weight: 0,
            confidence: 0,
            direction: "neutral",
            details: "No data available"
        )
    }
}

// MARK: - Portfolio Risk Snapshot

/// A snapshot of current portfolio risk metrics for the engine to consider.
public struct PortfolioRiskSnapshot {
    public let totalValueUSD: Double
    public let cashAvailableUSD: Double
    public let holdings: [PortfolioHoldingSnapshot]
    public let concentrationRisk: Double       // 0-1, 1 = all in one asset
    public let overallDrawdown: Double          // current drawdown from peak
    public let dailyPnLPct: Double
    public let weeklyPnLPct: Double

    public struct PortfolioHoldingSnapshot {
        public let symbol: String
        public let allocationPct: Double       // % of portfolio
        public let unrealizedPnLPct: Double
        public let costBasis: Double
        public let currentValue: Double
    }
}

// MARK: - Engine Configuration

public struct SmartEngineConfig: Codable {
    // Signal weights (must sum to ~1.0)
    public var sentimentWeight: Double = 0.20
    public var predictionWeight: Double = 0.25
    public var technicalWeight: Double = 0.30
    public var algorithmWeight: Double = 0.20
    public var riskWeight: Double = 0.05

    // Risk parameters
    public var maxSinglePositionPct: Double = 15.0    // max % of portfolio per asset
    public var maxPortfolioDrawdownPct: Double = 20.0  // pause trading if drawdown exceeds
    public var minConvictionToTrade: Double = 55.0     // minimum conviction to generate non-hold
    public var requireMultipleSignals: Bool = true      // need 2+ confirming signals

    // Fear/Greed position sizing
    public var fearMultiplierMax: Double = 1.5         // buy more in extreme fear
    public var greedMultiplierMin: Double = 0.5        // buy less in extreme greed

    // Volatility adjustments
    public var highVolatilityStopMultiplier: Double = 1.5
    public var lowVolatilityStopMultiplier: Double = 0.8

    public static let `default` = SmartEngineConfig()

    public static let conservative = SmartEngineConfig(
        maxSinglePositionPct: 8.0,
        maxPortfolioDrawdownPct: 12.0,
        minConvictionToTrade: 70.0,
        fearMultiplierMax: 1.2,
        greedMultiplierMin: 0.6
    )

    public static let aggressive = SmartEngineConfig(
        maxSinglePositionPct: 25.0,
        maxPortfolioDrawdownPct: 30.0,
        minConvictionToTrade: 45.0,
        fearMultiplierMax: 2.0,
        greedMultiplierMin: 0.4
    )
}

// MARK: - Smart Trading Engine

/// The central "brain" of CryptoSage's trading intelligence.
/// Fuses all AI signals into unified, actionable trading decisions.
@MainActor
public final class SmartTradingEngine: ObservableObject {

    // MARK: - Singleton
    public static let shared = SmartTradingEngine()

    // MARK: - Published State
    @Published public var latestDecisions: [String: SmartTradingDecision] = [:]
    @Published public var isAnalyzing: Bool = false
    @Published public var lastAnalysisTime: Date?
    @Published public var engineStatus: EngineStatus = .idle
    @Published public var activeAlerts: [SmartAlert] = []
    @Published public var config: SmartEngineConfig = .default

    // MARK: - Dependencies
    private let signalAggregator = AISignalAggregator.shared
    private let positionSizer = DynamicPositionSizer.shared

    // MARK: - Internal State
    private var decisionHistory: [SmartTradingDecision] = []
    private var cancellables = Set<AnyCancellable>()
    private let maxHistoryCount = 500
    private let decisionCacheDuration: TimeInterval = 120 // 2 minutes

    // MARK: - Init

    private init() {
        loadPersistedConfig()
    }

    // MARK: - Core Analysis

    /// Generate a complete trading decision for a single asset.
    /// This is the main entry point — it gathers all signals and fuses them.
    public func analyzeAsset(
        symbol: String,
        coinName: String,
        currentPrice: Double,
        priceHistory: [Double],
        volumes: [Double],
        sparkline7d: [Double],
        change24h: Double,
        change7d: Double?,
        portfolioSnapshot: PortfolioRiskSnapshot
    ) async -> SmartTradingDecision {

        // Check cache first
        if let cached = latestDecisions[symbol.lowercased()],
           Date().timeIntervalSince(cached.timestamp) < decisionCacheDuration {
            return cached
        }

        isAnalyzing = true
        engineStatus = .analyzing(symbol: symbol.uppercased())
        defer {
            isAnalyzing = false
            engineStatus = .idle
        }

        // STEP 1: Aggregate all AI signals
        let aggregatedSignals = await signalAggregator.aggregateSignals(
            symbol: symbol,
            currentPrice: currentPrice,
            priceHistory: priceHistory,
            volumes: volumes,
            sparkline7d: sparkline7d,
            change24h: change24h,
            change7d: change7d
        )

        // STEP 2: Get Fear/Greed context
        let fearGreedValue = getFearGreedValue()
        let fearGreedClassification = getFearGreedClassification()

        // STEP 3: Determine market regime
        let regime = detectMarketRegime(closes: priceHistory, volumes: volumes)

        // STEP 4: Calculate composite score using weighted signal fusion
        let compositeResult = calculateCompositeScore(signals: aggregatedSignals)

        // STEP 5: Determine action from composite score
        let action = determineAction(
            compositeScore: compositeResult.score,
            conviction: compositeResult.conviction,
            signalAgreement: compositeResult.signalAgreement
        )

        // STEP 6: Dynamic position sizing (Fear/Greed adjusted)
        let sizing = positionSizer.calculatePositionSize(
            action: action,
            conviction: compositeResult.conviction,
            fearGreedValue: fearGreedValue,
            regime: regime,
            currentPrice: currentPrice,
            volatility: calculateVolatility(prices: priceHistory),
            portfolioSnapshot: portfolioSnapshot,
            config: config
        )

        // STEP 7: Calculate risk levels (stop-loss, take-profit)
        let riskLevels = calculateRiskLevels(
            action: action,
            currentPrice: currentPrice,
            priceHistory: priceHistory,
            regime: regime,
            volatility: calculateVolatility(prices: priceHistory)
        )

        // STEP 8: Generate reasoning
        let reasoning = generateReasoning(
            action: action,
            signals: aggregatedSignals,
            fearGreed: fearGreedValue,
            regime: regime,
            compositeScore: compositeResult.score
        )

        let riskWarnings = generateRiskWarnings(
            action: action,
            portfolioSnapshot: portfolioSnapshot,
            sizing: sizing,
            regime: regime,
            fearGreedValue: fearGreedValue
        )

        // STEP 9: Determine urgency
        let urgency = determineUrgency(
            action: action,
            conviction: compositeResult.conviction,
            regime: regime,
            change24h: change24h
        )

        // STEP 10: Assess data freshness
        let freshness = assessDataFreshness(signals: aggregatedSignals)

        // Build the decision
        let decision = SmartTradingDecision(
            id: UUID(),
            symbol: symbol.lowercased(),
            coinName: coinName,
            timestamp: Date(),
            action: action,
            conviction: compositeResult.conviction,
            urgency: urgency,
            recommendedPositionPct: sizing.positionPct,
            recommendedAmountUSD: sizing.amountUSD,
            maxPositionPct: sizing.maxPct,
            currentPrice: currentPrice,
            suggestedEntry: riskLevels.entry,
            stopLoss: riskLevels.stopLoss,
            takeProfit: riskLevels.takeProfit,
            riskRewardRatio: riskLevels.rrRatio,
            sentimentSignal: aggregatedSignals.sentiment,
            predictionSignal: aggregatedSignals.prediction,
            technicalSignal: aggregatedSignals.technical,
            algorithmSignal: aggregatedSignals.algorithm,
            riskSignal: aggregatedSignals.risk,
            marketRegime: regime,
            fearGreedValue: fearGreedValue,
            fearGreedClassification: fearGreedClassification,
            reasoning: reasoning,
            riskWarnings: riskWarnings,
            signalSourceCount: aggregatedSignals.activeSourceCount,
            dataFreshness: freshness
        )

        // Cache and record
        latestDecisions[symbol.lowercased()] = decision
        recordDecision(decision)
        lastAnalysisTime = Date()

        // Check for alerts
        checkAlerts(decision: decision)

        return decision
    }

    /// Analyze multiple assets in parallel (e.g., entire portfolio or watchlist).
    public func analyzeMultipleAssets(
        assets: [(symbol: String, coinName: String, price: Double, history: [Double], volumes: [Double], sparkline: [Double], change24h: Double, change7d: Double?)],
        portfolioSnapshot: PortfolioRiskSnapshot
    ) async -> [SmartTradingDecision] {

        engineStatus = .batchAnalysis(count: assets.count)
        isAnalyzing = true
        defer {
            isAnalyzing = false
            engineStatus = .idle
        }

        var decisions: [SmartTradingDecision] = []

        // Process in parallel using task groups
        await withTaskGroup(of: SmartTradingDecision.self) { group in
            for asset in assets {
                group.addTask { [self] in
                    await self.analyzeAsset(
                        symbol: asset.symbol,
                        coinName: asset.coinName,
                        currentPrice: asset.price,
                        priceHistory: asset.history,
                        volumes: asset.volumes,
                        sparkline7d: asset.sparkline,
                        change24h: asset.change24h,
                        change7d: asset.change7d,
                        portfolioSnapshot: portfolioSnapshot
                    )
                }
            }

            for await decision in group {
                decisions.append(decision)
            }
        }

        // Sort by conviction (highest first)
        decisions.sort { $0.conviction > $1.conviction }

        return decisions
    }

    // MARK: - Composite Score Calculation

    private struct CompositeResult {
        let score: Double           // -100 to +100
        let conviction: Double      // 0-100
        let signalAgreement: Double // 0-1
    }

    private func calculateCompositeScore(signals: AggregatedSignals) -> CompositeResult {
        let weights = [
            (signals.sentiment, config.sentimentWeight),
            (signals.prediction, config.predictionWeight),
            (signals.technical, config.technicalWeight),
            (signals.algorithm, config.algorithmWeight),
            (signals.risk, config.riskWeight)
        ]

        // Weighted average of available signals
        var totalWeight: Double = 0
        var weightedSum: Double = 0
        var activeSignals: [Double] = []

        for (signal, weight) in weights {
            guard signal.confidence > 0 else { continue }
            let effectiveWeight = weight * signal.confidence
            weightedSum += signal.score * effectiveWeight
            totalWeight += effectiveWeight
            activeSignals.append(signal.score)
        }

        let compositeScore = totalWeight > 0 ? weightedSum / totalWeight : 0

        // Calculate signal agreement (how much signals agree with each other)
        let signalAgreement = calculateSignalAgreement(scores: activeSignals)

        // Conviction = function of score magnitude, signal agreement, and source count
        let scoreMagnitude = min(abs(compositeScore) / 100.0, 1.0)
        let sourceBonus = min(Double(activeSignals.count) / 5.0, 1.0)
        let conviction = (scoreMagnitude * 0.4 + signalAgreement * 0.4 + sourceBonus * 0.2) * 100

        return CompositeResult(
            score: compositeScore.clamped(to: -100...100),
            conviction: conviction.clamped(to: 0...100),
            signalAgreement: signalAgreement
        )
    }

    private func calculateSignalAgreement(scores: [Double]) -> Double {
        guard scores.count >= 2 else { return scores.isEmpty ? 0 : 0.5 }

        // Check if signals agree on direction
        let bullishCount = scores.filter { $0 > 10 }.count
        let bearishCount = scores.filter { $0 < -10 }.count
        let neutralCount = scores.count - bullishCount - bearishCount

        let maxDirectional = max(bullishCount, bearishCount)
        let directionalAgreement = Double(maxDirectional) / Double(scores.count)

        // Check magnitude similarity
        let avgMagnitude = scores.map { abs($0) }.reduce(0, +) / Double(scores.count)
        let magnitudeVariance = scores.map { pow(abs($0) - avgMagnitude, 2) }.reduce(0, +) / Double(scores.count)
        let magnitudeAgreement = 1.0 - min(sqrt(magnitudeVariance) / 50.0, 1.0)

        return (directionalAgreement * 0.7 + magnitudeAgreement * 0.3).clamped(to: 0...1)
    }

    // MARK: - Action Determination

    private func determineAction(
        compositeScore: Double,
        conviction: Double,
        signalAgreement: Double
    ) -> SmartAction {

        // If conviction is below threshold, always hold
        guard conviction >= config.minConvictionToTrade else {
            return .hold
        }

        // Require multiple confirming signals if configured
        if config.requireMultipleSignals && signalAgreement < 0.4 {
            return .hold
        }

        switch compositeScore {
        case 70...100:
            return conviction >= 75 ? .strongBuy : .buy
        case 40..<70:
            return .buy
        case 15..<40:
            return .accumulate
        case -15..<15:
            return .hold
        case -40..<(-15):
            return .reducePosition
        case -70..<(-40):
            return .sell
        case -100..<(-70):
            return conviction >= 75 ? .strongSell : .sell
        default:
            return .hold
        }
    }

    // MARK: - Risk Level Calculation

    private struct RiskLevels {
        let entry: Double
        let stopLoss: Double
        let takeProfit: Double
        let rrRatio: Double
    }

    private func calculateRiskLevels(
        action: SmartAction,
        currentPrice: Double,
        priceHistory: [Double],
        regime: String,
        volatility: Double
    ) -> RiskLevels {
        guard currentPrice > 0 else {
            return RiskLevels(entry: 0, stopLoss: 0, takeProfit: 0, rrRatio: 0)
        }

        // ATR-based stop loss
        let atr = calculateATR(prices: priceHistory)
        let atrPct = atr / currentPrice

        // Regime-based multiplier for stops
        let regimeMultiplier: Double = {
            switch regime {
            case "volatile":      return config.highVolatilityStopMultiplier
            case "ranging":       return 0.9
            case "strongTrend":   return 1.2
            case "trending":      return 1.0
            default:              return 1.0
            }
        }()

        let stopPct = max(atrPct * 2.0 * regimeMultiplier, 0.02) // minimum 2% stop
        let targetRR = 2.0 // target 2:1 risk-reward
        let profitPct = stopPct * targetRR

        let isBuyAction = [SmartAction.strongBuy, .buy, .accumulate].contains(action)

        let entry = currentPrice
        let stopLoss: Double
        let takeProfit: Double

        if isBuyAction {
            stopLoss = currentPrice * (1.0 - stopPct)
            takeProfit = currentPrice * (1.0 + profitPct)
        } else if action == .hold {
            stopLoss = currentPrice * (1.0 - stopPct)
            takeProfit = currentPrice * (1.0 + profitPct)
        } else {
            // Sell actions — stop is above, target is below
            stopLoss = currentPrice * (1.0 + stopPct)
            takeProfit = currentPrice * (1.0 - profitPct)
        }

        let riskDist = abs(entry - stopLoss)
        let rewardDist = abs(takeProfit - entry)
        let rrRatio = riskDist > 0 ? rewardDist / riskDist : 0

        return RiskLevels(
            entry: entry,
            stopLoss: stopLoss,
            takeProfit: takeProfit,
            rrRatio: rrRatio
        )
    }

    // MARK: - Reasoning & Warnings

    private func generateReasoning(
        action: SmartAction,
        signals: AggregatedSignals,
        fearGreed: Int,
        regime: String,
        compositeScore: Double
    ) -> [String] {
        var reasons: [String] = []

        // Sentiment reasoning
        if signals.sentiment.confidence > 0 {
            if fearGreed < 25 {
                reasons.append("Extreme Fear (F&G: \(fearGreed)) — historically a buying opportunity")
            } else if fearGreed < 40 {
                reasons.append("Fear sentiment (F&G: \(fearGreed)) suggests undervalued conditions")
            } else if fearGreed > 75 {
                reasons.append("Extreme Greed (F&G: \(fearGreed)) — caution advised, potential overvaluation")
            } else if fearGreed > 60 {
                reasons.append("Greed sentiment (F&G: \(fearGreed)) — reduced position sizing recommended")
            }
        }

        // Prediction reasoning
        if signals.prediction.confidence > 0 {
            let dir = signals.prediction.direction
            let conf = Int(signals.prediction.confidence * 100)
            reasons.append("AI prediction: \(dir) with \(conf)% confidence — \(signals.prediction.details)")
        }

        // Technical reasoning
        if signals.technical.confidence > 0 {
            reasons.append("Technical analysis: \(signals.technical.details)")
        }

        // Algorithm consensus reasoning
        if signals.algorithm.confidence > 0 {
            reasons.append("Sage Algorithm consensus: \(signals.algorithm.details)")
        }

        // Regime reasoning
        reasons.append("Market regime: \(regime) — adjusting risk parameters accordingly")

        // Overall composite
        let absScore = abs(compositeScore)
        if absScore > 60 {
            reasons.append("Strong signal convergence (\(Int(compositeScore)) composite) across \(signals.activeSourceCount) sources")
        } else if absScore > 30 {
            reasons.append("Moderate signal alignment (\(Int(compositeScore)) composite) — proceed with standard sizing")
        }

        return reasons
    }

    private func generateRiskWarnings(
        action: SmartAction,
        portfolioSnapshot: PortfolioRiskSnapshot,
        sizing: PositionSizingResult,
        regime: String,
        fearGreedValue: Int
    ) -> [String] {
        var warnings: [String] = []

        // Portfolio-level warnings
        if portfolioSnapshot.overallDrawdown > config.maxPortfolioDrawdownPct * 0.7 {
            warnings.append("⚠️ Portfolio drawdown (\(String(format: "%.1f", portfolioSnapshot.overallDrawdown))%) approaching maximum threshold")
        }

        if portfolioSnapshot.concentrationRisk > 0.5 {
            warnings.append("⚠️ High concentration risk — portfolio heavily weighted in few assets")
        }

        // Regime warnings
        if regime == "volatile" {
            warnings.append("⚠️ High volatility regime — wider stops and smaller position sizes applied")
        }

        // Sentiment extremes
        if fearGreedValue > 80 {
            warnings.append("⚠️ Extreme Greed — market may be overextended, high reversal risk")
        } else if fearGreedValue < 15 {
            warnings.append("⚠️ Extreme Fear — while historically bullish, capitulation possible")
        }

        // Position sizing warnings
        if let existingHolding = portfolioSnapshot.holdings.first(where: { $0.symbol.lowercased() == sizing.symbol?.lowercased() }) {
            let totalAllocation = existingHolding.allocationPct + sizing.positionPct
            if totalAllocation > config.maxSinglePositionPct {
                warnings.append("⚠️ Adding this position would bring total allocation to \(String(format: "%.1f", totalAllocation))% — exceeds maximum \(String(format: "%.0f", config.maxSinglePositionPct))%")
            }
        }

        return warnings
    }

    // MARK: - Urgency

    private func determineUrgency(
        action: SmartAction,
        conviction: Double,
        regime: String,
        change24h: Double
    ) -> DecisionUrgency {
        // Strong conviction + volatile market = act fast
        if conviction >= 80 && (regime == "volatile" || abs(change24h) > 8) {
            return .immediate
        }

        if [SmartAction.strongBuy, .strongSell].contains(action) && conviction >= 70 {
            return .soon
        }

        if action == .accumulate {
            return .patient
        }

        if conviction >= 65 {
            return .standard
        }

        return .patient
    }

    // MARK: - Data Freshness

    private func assessDataFreshness(signals: AggregatedSignals) -> DataFreshness {
        let now = Date()
        let allTimestamps = [
            signals.sentiment.confidence > 0 ? signals.latestTimestamp : nil,
            signals.prediction.confidence > 0 ? signals.latestTimestamp : nil,
            signals.technical.confidence > 0 ? signals.latestTimestamp : nil,
        ].compactMap { $0 }

        guard let oldest = allTimestamps.min() else {
            return .stale
        }

        let age = now.timeIntervalSince(oldest)
        switch age {
        case 0..<60:    return .realtime
        case 60..<300:  return .fresh
        case 300..<1800: return .recent
        default:        return .stale
        }
    }

    // MARK: - Helper: Fear/Greed Access

    private func getFearGreedValue() -> Int {
        let vm = ExtendedFearGreedViewModel.shared

        // Prefer Firebase-enhanced score
        if let firebaseScore = vm.firebaseSentimentScore {
            return firebaseScore
        }

        // Fall back to standard data
        if let first = vm.data.first, let val = Int(first.value) {
            return val
        }

        return 50 // neutral default
    }

    private func getFearGreedClassification() -> String {
        let vm = ExtendedFearGreedViewModel.shared

        if let verdict = vm.firebaseSentimentVerdict {
            return verdict
        }

        if let first = vm.data.first {
            return first.value_classification
        }

        return "Neutral"
    }

    // MARK: - Helper: Market Regime

    private func detectMarketRegime(closes: [Double], volumes: [Double]) -> String {
        if let regime = SageAlgorithmEngine.shared.currentRegimes.values.first {
            return regime.rawValue
        }

        let detected = SageAlgorithmEngine.shared.detectRegime(closes: closes, volumes: volumes)
        return detected.rawValue
    }

    // MARK: - Helper: Volatility

    private func calculateVolatility(prices: [Double]) -> Double {
        guard prices.count >= 2 else { return 0.02 }

        let returns = zip(prices.dropFirst(), prices).map { (log($0) - log($1)) }
        let mean = returns.reduce(0, +) / Double(returns.count)
        let variance = returns.map { pow($0 - mean, 2) }.reduce(0, +) / Double(returns.count)
        return sqrt(variance) * sqrt(365) // annualized
    }

    // MARK: - Helper: ATR

    private func calculateATR(prices: [Double], period: Int = 14) -> Double {
        guard prices.count >= period + 1 else {
            // Fallback: use simple range
            if let maxP = prices.max(), let minP = prices.min(), maxP > 0 {
                return (maxP - minP) / Double(max(prices.count, 1))
            }
            return 0
        }

        var trueRanges: [Double] = []
        for i in 1..<prices.count {
            let high = prices[i]
            let low = prices[i]
            let prevClose = prices[i - 1]
            let tr = max(high - low, abs(high - prevClose), abs(low - prevClose))
            trueRanges.append(tr)
        }

        // Simple average of last `period` true ranges
        let recentTRs = Array(trueRanges.suffix(period))
        return recentTRs.reduce(0, +) / Double(recentTRs.count)
    }

    // MARK: - Alerts

    public struct SmartAlert: Identifiable {
        public let id = UUID()
        public let symbol: String
        public let message: String
        public let action: SmartAction
        public let conviction: Double
        public let timestamp: Date
    }

    private func checkAlerts(decision: SmartTradingDecision) {
        guard decision.isActionable,
              decision.conviction >= 70,
              decision.action != .hold else { return }

        let alert = SmartAlert(
            symbol: decision.symbol,
            message: decision.summaryText,
            action: decision.action,
            conviction: decision.conviction,
            timestamp: Date()
        )

        activeAlerts.append(alert)

        // Keep only last 20 alerts
        if activeAlerts.count > 20 {
            activeAlerts = Array(activeAlerts.suffix(20))
        }
    }

    // MARK: - History & Persistence

    private func recordDecision(_ decision: SmartTradingDecision) {
        decisionHistory.append(decision)
        if decisionHistory.count > maxHistoryCount {
            decisionHistory = Array(decisionHistory.suffix(maxHistoryCount))
        }
    }

    public var recentDecisions: [SmartTradingDecision] {
        Array(decisionHistory.suffix(50))
    }

    public func decisionsForSymbol(_ symbol: String) -> [SmartTradingDecision] {
        decisionHistory.filter { $0.symbol.lowercased() == symbol.lowercased() }
    }

    // MARK: - Config Persistence

    private func loadPersistedConfig() {
        if let data = UserDefaults.standard.data(forKey: "SmartEngineConfig"),
           let saved = try? JSONDecoder().decode(SmartEngineConfig.self, from: data) {
            config = saved
        }
    }

    public func saveConfig() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: "SmartEngineConfig")
        }
    }

    public func resetConfig() {
        config = .default
        saveConfig()
    }

    // MARK: - Cache Management

    public func clearCache() {
        latestDecisions.removeAll()
        activeAlerts.removeAll()
    }

    public func clearCache(for symbol: String) {
        latestDecisions.removeValue(forKey: symbol.lowercased())
    }

    // MARK: - Engine Status

    public enum EngineStatus: Equatable {
        case idle
        case analyzing(symbol: String)
        case batchAnalysis(count: Int)
        case error(message: String)

        public var displayText: String {
            switch self {
            case .idle:
                return "Ready"
            case .analyzing(let symbol):
                return "Analyzing \(symbol.uppercased())..."
            case .batchAnalysis(let count):
                return "Analyzing \(count) assets..."
            case .error(let message):
                return "Error: \(message)"
            }
        }
    }
}

// MARK: - Double Clamping Extension

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
