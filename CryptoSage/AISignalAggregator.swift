//
//  AISignalAggregator.swift
//  CryptoSage
//
//  AI Signal Aggregator — Collects and normalizes signals from ALL AI sources
//  into a unified format the SmartTradingEngine can consume.
//

import Foundation
import Combine

// MARK: - Aggregated Signals Container

/// The unified output from all signal sources, ready for the decision engine.
public struct AggregatedSignals {
    public let sentiment: SignalContribution
    public let prediction: SignalContribution
    public let technical: SignalContribution
    public let algorithm: SignalContribution
    public let risk: SignalContribution
    public let latestTimestamp: Date

    /// How many signal sources actually provided data (confidence > 0)
    public var activeSourceCount: Int {
        [sentiment, prediction, technical, algorithm, risk]
            .filter { $0.confidence > 0 }
            .count
    }

    /// Overall directional bias: positive = bullish, negative = bearish
    public var overallBias: Double {
        let active = [sentiment, prediction, technical, algorithm, risk]
            .filter { $0.confidence > 0 }
        guard !active.isEmpty else { return 0 }
        return active.map(\.weightedScore).reduce(0, +) / Double(active.count)
    }

    public static let empty = AggregatedSignals(
        sentiment: .neutral(source: "Sentiment"),
        prediction: .neutral(source: "Prediction"),
        technical: .neutral(source: "Technical"),
        algorithm: .neutral(source: "Algorithm"),
        risk: .neutral(source: "Risk"),
        latestTimestamp: Date()
    )
}

// MARK: - AI Signal Aggregator

/// Collects signals from every AI subsystem in CryptoSage and normalizes them
/// into a consistent format for the SmartTradingEngine.
@MainActor
public final class AISignalAggregator: ObservableObject {

    // MARK: - Singleton
    public static let shared = AISignalAggregator()

    // MARK: - Published State
    @Published public var lastAggregation: AggregatedSignals = .empty
    @Published public var isAggregating: Bool = false

    private init() {}

    // MARK: - Main Aggregation

    /// Collect and normalize all available AI signals for a given asset.
    public func aggregateSignals(
        symbol: String,
        currentPrice: Double,
        priceHistory: [Double],
        volumes: [Double],
        sparkline7d: [Double],
        change24h: Double,
        change7d: Double?
    ) async -> AggregatedSignals {

        isAggregating = true
        defer { isAggregating = false }

        // Gather all signals concurrently
        async let sentimentSignal = aggregateSentiment(symbol: symbol)
        async let predictionSignal = aggregatePrediction(symbol: symbol, currentPrice: currentPrice)
        async let technicalSignal = aggregateTechnicals(
            symbol: symbol,
            currentPrice: currentPrice,
            priceHistory: priceHistory,
            volumes: volumes,
            sparkline7d: sparkline7d,
            change24h: change24h
        )
        async let algorithmSignal = aggregateAlgorithms(
            symbol: symbol,
            currentPrice: currentPrice,
            priceHistory: priceHistory,
            volumes: volumes,
            sparkline7d: sparkline7d
        )
        async let riskSignal = aggregateRiskSignals(symbol: symbol, currentPrice: currentPrice)

        let signals = AggregatedSignals(
            sentiment: await sentimentSignal,
            prediction: await predictionSignal,
            technical: await technicalSignal,
            algorithm: await algorithmSignal,
            risk: await riskSignal,
            latestTimestamp: Date()
        )

        lastAggregation = signals
        return signals
    }

    // MARK: - 1. Sentiment Signal (Fear & Greed Index)

    private func aggregateSentiment(symbol: String) async -> SignalContribution {
        let vm = ExtendedFearGreedViewModel.shared

        // Try Firebase-enhanced sentiment first
        if let firebaseScore = vm.firebaseSentimentScore,
           let firebaseVerdict = vm.firebaseSentimentVerdict {
            let score = convertFearGreedToTradingScore(fearGreedValue: firebaseScore)
            let confidence = Double(vm.firebaseSentimentConfidence ?? 70) / 100.0
            let factors = vm.firebaseSentimentKeyFactors?.joined(separator: ", ") ?? ""

            return SignalContribution(
                source: "Fear & Greed Index (Enhanced)",
                score: score,
                weight: 1.0,
                confidence: confidence,
                direction: score > 10 ? "bullish" : score < -10 ? "bearish" : "neutral",
                details: "\(firebaseVerdict) (\(firebaseScore)/100). \(factors)"
            )
        }

        // Fall back to standard Fear & Greed data
        if let first = vm.data.first, let value = Int(first.value) {
            let score = convertFearGreedToTradingScore(fearGreedValue: value)

            return SignalContribution(
                source: "Fear & Greed Index",
                score: score,
                weight: 1.0,
                confidence: 0.7, // standard source is reasonably reliable
                direction: score > 10 ? "bullish" : score < -10 ? "bearish" : "neutral",
                details: "\(first.value_classification) (\(value)/100)"
            )
        }

        // Check derived metrics from ExtendedFearGreedViewModel
        if let breadth = vm.marketBreadth, let btcChange = vm.btc24hChange {
            let derivedScore = (breadth - 50) * 1.5 + btcChange * 5.0
            let clampedScore = max(-100, min(100, derivedScore))

            return SignalContribution(
                source: "Market Breadth (Derived)",
                score: clampedScore,
                weight: 0.7,
                confidence: 0.5,
                direction: clampedScore > 10 ? "bullish" : clampedScore < -10 ? "bearish" : "neutral",
                details: "Breadth: \(String(format: "%.0f", breadth))%, BTC 24h: \(String(format: "%.1f", btcChange))%"
            )
        }

        return .neutral(source: "Sentiment")
    }

    /// Convert Fear/Greed (0-100) to a contrarian trading score (-100 to +100).
    /// Extreme Fear = bullish opportunity (+score), Extreme Greed = bearish caution (-score).
    private func convertFearGreedToTradingScore(fearGreedValue: Int) -> Double {
        // Contrarian mapping:
        // F&G 0 (Extreme Fear)   → +80 (strong bullish)
        // F&G 25 (Fear)          → +40
        // F&G 50 (Neutral)       → 0
        // F&G 75 (Greed)         → -40
        // F&G 100 (Extreme Greed)→ -80 (strong bearish)

        let normalized = Double(fearGreedValue) // 0 to 100
        let score = -(normalized - 50) * 1.6    // maps 0→+80, 50→0, 100→-80
        return max(-100, min(100, score))
    }

    // MARK: - 2. AI Price Prediction Signal

    private func aggregatePrediction(symbol: String, currentPrice: Double) async -> SignalContribution {
        // Check AITradingSignalService cache first
        let signalService = AITradingSignalService.shared
        if let cachedSignal = signalService.cachedSignal(for: symbol) {
            return convertTradingSignalToContribution(cachedSignal, source: "AI Trading Signal")
        }

        // Check for stock signals (prefixed)
        let stockKey = AITradingSignalService.stockSignalCoinId(symbol: symbol)
        if let stockSignal = signalService.cachedSignal(for: stockKey) {
            return convertTradingSignalToContribution(stockSignal, source: "AI Trading Signal (Stock)")
        }

        // No cached signal available — return neutral
        // The engine can trigger a fresh fetch if needed
        return .neutral(source: "AI Prediction")
    }

    private func convertTradingSignalToContribution(
        _ signal: TradingSignal,
        source: String
    ) -> SignalContribution {
        let score: Double = {
            switch signal.type {
            case .buy:  return signal.confidence * 100
            case .sell: return -(signal.confidence * 100)
            case .hold: return signal.sentimentScore * 20 // mild directional bias from sentiment
            }
        }()

        return SignalContribution(
            source: source,
            score: score.clamped(to: -100...100),
            weight: 1.0,
            confidence: signal.confidence,
            direction: signal.type == .buy ? "bullish" : signal.type == .sell ? "bearish" : "neutral",
            details: "\(signal.type.rawValue.capitalized) signal — \(signal.confidenceLabel) confidence. \(signal.reasons.first ?? "")"
        )
    }

    // MARK: - 3. Technical Analysis Signal

    private func aggregateTechnicals(
        symbol: String,
        currentPrice: Double,
        priceHistory: [Double],
        volumes: [Double],
        sparkline7d: [Double],
        change24h: Double
    ) async -> SignalContribution {
        guard !priceHistory.isEmpty || !sparkline7d.isEmpty else {
            return .neutral(source: "Technical Analysis")
        }

        let closes = priceHistory.isEmpty ? sparkline7d : priceHistory
        guard closes.count >= 14 else {
            return .neutral(source: "Technical Analysis")
        }

        // Calculate technical indicators using TechnicalsEngine
        var signals: [(name: String, score: Double, weight: Double)] = []

        // RSI
        if let rsi = TechnicalsEngine.rsi(closes) {
            let rsiScore: Double
            if rsi < 30 {
                rsiScore = (30 - rsi) * 3.0  // Oversold → bullish (0 to +90)
            } else if rsi > 70 {
                rsiScore = (70 - rsi) * 3.0  // Overbought → bearish (0 to -90)
            } else {
                rsiScore = (rsi - 50) * -1.0  // Mild contrarian within range
            }
            signals.append(("RSI(\(String(format: "%.0f", rsi)))", rsiScore.clamped(to: -100...100), 0.25))
        }

        // MACD
        if let macdHist = TechnicalsEngine.macdHistogram(closes) {
            let macdScore = (macdHist / currentPrice * 10000).clamped(to: -100...100) // normalize
            signals.append(("MACD", macdScore, 0.2))
        }

        // SMA Trend (price relative to 50-period SMA)
        if closes.count >= 50, let sma50 = TechnicalsEngine.sma(closes, period: 50) {
            let deviation = (currentPrice - sma50) / sma50 * 100  // % above/below SMA
            let trendScore = (deviation * 5).clamped(to: -100...100)
            signals.append(("SMA50 Trend", trendScore, 0.15))
        }

        // Bollinger Bands
        if let bb = TechnicalsEngine.bollingerBands(closes) {
            let bbWidth = bb.upper - bb.lower
            if bbWidth > 0 {
                let position = (currentPrice - bb.lower) / bbWidth // 0 = at lower, 1 = at upper
                let bbScore = ((0.5 - position) * 200).clamped(to: -100...100)  // Below middle = bullish
                signals.append(("Bollinger", bbScore, 0.15))
            }
        }

        // Momentum (24h change)
        let momentumScore = (change24h * 8).clamped(to: -100...100)
        signals.append(("Momentum", momentumScore, 0.1))

        // Aggregate score
        if let aggregateScore = TechnicalsEngine.aggregateScore(price: currentPrice, closes: closes) as Double? {
            let normalizedAggregate = (aggregateScore - 0.5) * 200 // 0-1 → -100 to +100
            signals.append(("Aggregate", normalizedAggregate.clamped(to: -100...100), 0.15))
        }

        // Calculate weighted average
        let totalWeight = signals.map(\.weight).reduce(0, +)
        let weightedScore = totalWeight > 0
            ? signals.map { $0.score * $0.weight }.reduce(0, +) / totalWeight
            : 0

        let details = signals.map { "\($0.name): \($0.score > 0 ? "+" : "")\(String(format: "%.0f", $0.score))" }.joined(separator: ", ")

        return SignalContribution(
            source: "Technical Analysis",
            score: weightedScore.clamped(to: -100...100),
            weight: 1.0,
            confidence: min(Double(signals.count) / 5.0, 1.0), // more indicators = more confident
            direction: weightedScore > 15 ? "bullish" : weightedScore < -15 ? "bearish" : "neutral",
            details: details
        )
    }

    // MARK: - 4. Sage Algorithm Consensus

    private func aggregateAlgorithms(
        symbol: String,
        currentPrice: Double,
        priceHistory: [Double],
        volumes: [Double],
        sparkline7d: [Double]
    ) async -> SignalContribution {
        let engine = SageAlgorithmEngine.shared

        // Check cached consensus first
        if let consensus = engine.getCachedConsensus(for: symbol) {
            return convertConsensusToContribution(consensus)
        }

        // If we have enough data, evaluate all algorithms
        let closes = priceHistory.isEmpty ? sparkline7d : priceHistory
        guard closes.count >= 50 else {
            return .neutral(source: "Sage Algorithms")
        }

        let fearGreedValue = Int(ExtendedFearGreedViewModel.shared.data.first?.value ?? "50") ?? 50

        let marketData = SageMarketData(
            symbol: symbol,
            timestamp: Date(),
            currentPrice: currentPrice,
            closes: closes,
            highs: closes, // approximate if real highs unavailable
            lows: closes,
            volumes: volumes.isEmpty ? Array(repeating: 1000000, count: closes.count) : volumes,
            timeframe: .d1,
            higherTimeframeCloses: nil,
            lowerTimeframeCloses: nil,
            fearGreedIndex: fearGreedValue
        )

        let consensus = await engine.evaluateAll(data: marketData)
        return convertConsensusToContribution(consensus)
    }

    private func convertConsensusToContribution(_ consensus: SageConsensus) -> SignalContribution {
        // Convert master signal to a score
        let score = consensus.masterSignal.numericValue * 50 // -2..+2 → -100..+100

        let details = """
        \(consensus.masterSignal.displayName) | \
        Agreement: \(String(format: "%.0f", consensus.agreementLevel * 100))% | \
        Trend: \(String(format: "%.0f", consensus.trendScore)), \
        Mom: \(String(format: "%.0f", consensus.momentumScore)), \
        Rev: \(String(format: "%.0f", consensus.reversionScore))
        """

        return SignalContribution(
            source: "Sage Algorithm Consensus",
            score: score.clamped(to: -100...100),
            weight: 1.0,
            confidence: consensus.confidence / 100.0,
            direction: score > 15 ? "bullish" : score < -15 ? "bearish" : "neutral",
            details: details
        )
    }

    // MARK: - 5. Risk Signals

    private func aggregateRiskSignals(symbol: String, currentPrice: Double) async -> SignalContribution {
        // Incorporate portfolio-level risk from AIRiskInsightService
        let riskService = AIRiskInsightService.shared

        if riskService.hasCachedAnalysis {
            // Risk service has recent analysis — use it as a risk overlay
            return SignalContribution(
                source: "Risk Analysis",
                score: 0, // risk is a modifier, not directional
                weight: 1.0,
                confidence: 0.6,
                direction: "neutral",
                details: "Portfolio risk analysis available — applied as position sizing modifier"
            )
        }

        return .neutral(source: "Risk Analysis")
    }
}

// MARK: - Private Double Extension

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
