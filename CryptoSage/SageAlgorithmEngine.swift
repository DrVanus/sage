//
//  SageAlgorithmEngine.swift
//  CryptoSage
//
//  CryptoSage AI's proprietary algorithm engine.
//  Orchestrates all Sage algorithms, detects market regimes, and generates consensus signals.
//

import Foundation
import Combine

// MARK: - Sage Algorithm Engine

/// CryptoSage AI's proprietary algorithm engine
/// Manages regime detection, algorithm orchestration, and consensus signal generation
@MainActor
public final class SageAlgorithmEngine: ObservableObject {
    public static let shared = SageAlgorithmEngine()
    
    // MARK: - Published State
    
    @Published public var latestConsensus: [String: SageConsensus] = [:]  // symbol -> consensus
    @Published public var latestSignals: [SageSignal] = []
    @Published public var currentRegimes: [String: SageMarketRegime] = [:]  // symbol -> regime
    @Published public var isEvaluating: Bool = false
    
    // MARK: - Algorithms
    
    /// All CryptoSage AI algorithms
    public private(set) var algorithms: [any SageAlgorithm] = []
    
    // MARK: - Cache
    
    private var signalCache: [String: (signals: [SageSignal], timestamp: Date)] = [:]
    private let cacheValiditySeconds: TimeInterval = 60  // 1 minute cache
    
    // MARK: - Storage Keys
    
    private static let signalHistoryKey = "sage_signal_history"
    private static let consensusHistoryKey = "sage_consensus_history"
    
    // MARK: - Initialization
    
    private init() {
        // Initialize all algorithms
        algorithms = [
            SageTrendAlgorithm(),
            SageMomentumAlgorithm(),
            SageReversionAlgorithm(),
            SageConfluenceAlgorithm(),
            SageVolatilityAlgorithm(),
            SageNeuralAlgorithm()
        ]
        
        loadSignalHistory()
    }
    
    // MARK: - Regime Detection
    
    /// Detect market regime for a symbol using TechnicalsEngine
    public func detectRegime(closes: [Double], volumes: [Double]) -> SageMarketRegime {
        guard let result = TechnicalsEngine.detectMarketRegime(closes: closes, volumes: volumes) else {
            return .ranging  // Default to ranging if detection fails
        }
        
        // Map string regime to enum
        switch result.regime {
        case "strongTrend":
            return .strongTrend
        case "trending":
            return .trending
        case "weakTrend":
            return .weakTrend
        case "ranging":
            return .ranging
        case "volatile":
            return .volatile
        case "accumulation":
            return .accumulation
        case "distribution":
            return .distribution
        default:
            return .ranging
        }
    }
    
    /// Get detailed regime analysis
    public func getRegimeDetails(closes: [Double], volumes: [Double]) -> (regime: SageMarketRegime, confidence: Double, details: [String: Any])? {
        guard let result = TechnicalsEngine.detectMarketRegime(closes: closes, volumes: volumes) else {
            return nil
        }
        
        let regime: SageMarketRegime
        switch result.regime {
        case "strongTrend": regime = .strongTrend
        case "trending": regime = .trending
        case "weakTrend": regime = .weakTrend
        case "ranging": regime = .ranging
        case "volatile": regime = .volatile
        case "accumulation": regime = .accumulation
        case "distribution": regime = .distribution
        default: regime = .ranging
        }
        
        return (regime, result.confidence, result.details)
    }
    
    // MARK: - Algorithm Evaluation
    
    /// Evaluate all algorithms for a symbol and generate consensus
    public func evaluateAll(data: SageMarketData) async -> SageConsensus {
        isEvaluating = true
        defer { isEvaluating = false }
        
        // Detect current regime
        let regime = detectRegime(closes: data.closes, volumes: data.volumes)
        currentRegimes[data.symbol] = regime
        
        // Evaluate each algorithm
        var signals: [SageSignal] = []
        var scores: [String: Double] = [:]
        
        for algorithm in algorithms {
            // Skip internal algorithms if not in dev mode
            if algorithm.isInternal && !AppConfig.isDeveloperMode {
                continue
            }
            
            if let signal = algorithm.evaluate(data: data, regime: regime) {
                signals.append(signal)
                scores[algorithm.id] = signal.score
            } else {
                // Calculate score even if no signal generated
                scores[algorithm.id] = algorithm.calculateScore(data: data)
            }
        }
        
        // Store signals
        latestSignals = signals
        
        // Generate consensus
        let consensus = generateConsensus(
            symbol: data.symbol,
            regime: regime,
            signals: signals,
            scores: scores,
            data: data
        )
        
        latestConsensus[data.symbol] = consensus
        saveSignalHistory()
        
        return consensus
    }
    
    /// Evaluate a single algorithm
    public func evaluate(algorithmId: String, data: SageMarketData) -> SageSignal? {
        guard let algorithm = algorithms.first(where: { $0.id == algorithmId }) else {
            return nil
        }
        
        let regime = detectRegime(closes: data.closes, volumes: data.volumes)
        return algorithm.evaluate(data: data, regime: regime)
    }
    
    /// Get quick scores from all algorithms (for consensus without full signal generation)
    public func getQuickScores(data: SageMarketData) -> [String: Double] {
        var scores: [String: Double] = [:]
        
        for algorithm in algorithms {
            if algorithm.isInternal && !AppConfig.isDeveloperMode {
                continue
            }
            scores[algorithm.id] = algorithm.calculateScore(data: data)
        }
        
        return scores
    }
    
    // MARK: - Consensus Generation
    
    /// Generate consensus signal from all algorithm outputs
    private func generateConsensus(
        symbol: String,
        regime: SageMarketRegime,
        signals: [SageSignal],
        scores: [String: Double],
        data: SageMarketData
    ) -> SageConsensus {
        
        // Extract individual scores
        let trendScore = scores["sage_trend"] ?? 0
        let momentumScore = scores["sage_momentum"] ?? 0
        let reversionScore = scores["sage_reversion"] ?? 0
        let confluenceScore = scores["sage_confluence"] ?? 0
        let volatilityScore = scores["sage_volatility"] ?? 0
        
        // Calculate sentiment score (Fear/Greed as contrarian)
        // 0 = extreme fear = bullish (+100), 100 = extreme greed = bearish (-100)
        let sentimentScore: Double
        if let fearGreed = data.fearGreedIndex {
            sentimentScore = Double(50 - fearGreed) * 2  // Convert to -100 to +100
        } else {
            sentimentScore = 0  // Neutral if not available
        }
        
        // Calculate master signal
        let allScores = [trendScore, momentumScore, reversionScore, confluenceScore, volatilityScore]
        let averageScore = allScores.reduce(0, +) / Double(allScores.count)
        
        // Count bullish/bearish
        let bullishCount = allScores.filter { $0 > 20 }.count
        let bearishCount = allScores.filter { $0 < -20 }.count
        
        // Determine master signal type
        let masterSignal: SageSignalType
        let confidence: Double
        
        if bullishCount >= 4 && averageScore > 40 {
            masterSignal = .strongBuy
            confidence = min(90, 60 + averageScore * 0.3)
        } else if bullishCount >= 3 && averageScore > 20 {
            masterSignal = .buy
            confidence = min(80, 50 + averageScore * 0.3)
        } else if bearishCount >= 4 && averageScore < -40 {
            masterSignal = .strongSell
            confidence = min(90, 60 + abs(averageScore) * 0.3)
        } else if bearishCount >= 3 && averageScore < -20 {
            masterSignal = .sell
            confidence = min(80, 50 + abs(averageScore) * 0.3)
        } else {
            masterSignal = .hold
            confidence = 50 - abs(averageScore) * 0.2
        }
        
        // Generate explanation
        let explanation = generateExplanation(
            symbol: symbol,
            masterSignal: masterSignal,
            regime: regime,
            scores: scores,
            bullishCount: bullishCount,
            bearishCount: bearishCount,
            sentimentScore: sentimentScore
        )
        
        // Calculate risk-adjusted position size and levels
        let positionSize = calculatePositionSize(regime: regime, confidence: confidence)
        let (stopLoss, takeProfit) = calculateRiskLevels(
            data: data,
            regime: regime,
            signal: masterSignal
        )
        
        return SageConsensus(
            symbol: symbol,
            regime: regime,
            trendScore: trendScore,
            momentumScore: momentumScore,
            reversionScore: reversionScore,
            confluenceScore: confluenceScore,
            volatilityScore: volatilityScore,
            sentimentScore: sentimentScore,
            masterSignal: masterSignal,
            confidence: confidence,
            explanation: explanation,
            signals: signals,
            suggestedPositionSize: positionSize,
            suggestedStopLoss: stopLoss,
            suggestedTakeProfit: takeProfit
        )
    }
    
    // MARK: - Explanation Generation
    
    /// Generate natural language explanation for the consensus
    private func generateExplanation(
        symbol: String,
        masterSignal: SageSignalType,
        regime: SageMarketRegime,
        scores: [String: Double],
        bullishCount: Int,
        bearishCount: Int,
        sentimentScore: Double
    ) -> String {
        
        var parts: [String] = []
        
        // Signal strength
        switch masterSignal {
        case .strongBuy:
            parts.append("CryptoSage AI detects a strong buying opportunity for \(symbol).")
        case .buy:
            parts.append("CryptoSage AI suggests a buying opportunity for \(symbol).")
        case .hold:
            parts.append("CryptoSage AI recommends holding \(symbol) at current levels.")
        case .sell:
            parts.append("CryptoSage AI suggests reducing \(symbol) exposure.")
        case .strongSell:
            parts.append("CryptoSage AI detects elevated risk for \(symbol).")
        }
        
        // Regime context
        parts.append("Market regime: \(regime.displayName).")
        
        // Algorithm agreement
        if bullishCount >= 4 {
            parts.append("\(bullishCount) of 5 algorithms are bullish.")
        } else if bearishCount >= 4 {
            parts.append("\(bearishCount) of 5 algorithms are bearish.")
        } else if bullishCount > bearishCount {
            parts.append("Slightly bullish bias with \(bullishCount) bullish algorithms.")
        } else if bearishCount > bullishCount {
            parts.append("Slightly bearish bias with \(bearishCount) bearish algorithms.")
        } else {
            parts.append("Mixed signals across algorithms.")
        }
        
        // Top contributing factors
        let sortedScores = scores.sorted { abs($0.value) > abs($1.value) }
        if let topFactor = sortedScores.first {
            let factorName = algorithmDisplayName(topFactor.key)
            if topFactor.value > 30 {
                parts.append("\(factorName) shows strong bullish signal.")
            } else if topFactor.value < -30 {
                parts.append("\(factorName) shows strong bearish signal.")
            }
        }
        
        // Sentiment
        if abs(sentimentScore) > 50 {
            if sentimentScore > 50 {
                parts.append("Extreme fear in market (contrarian bullish).")
            } else {
                parts.append("Extreme greed in market (contrarian bearish).")
            }
        }
        
        return parts.joined(separator: " ")
    }
    
    private func algorithmDisplayName(_ id: String) -> String {
        switch id {
        case "sage_trend": return "Sage Trend"
        case "sage_momentum": return "Sage Momentum"
        case "sage_reversion": return "Sage Reversion"
        case "sage_confluence": return "Sage Confluence"
        case "sage_volatility": return "Sage Volatility"
        case "sage_neural": return "Sage Neural"
        default: return id
        }
    }
    
    // MARK: - Risk Management
    
    /// Calculate position size based on regime and confidence
    private func calculatePositionSize(regime: SageMarketRegime, confidence: Double) -> Double {
        let baseSize = regime.positionSizeMultiplier * 100  // As percentage
        let confidenceAdjustment = (confidence / 100) * 0.5 + 0.5  // 0.5 to 1.0
        return min(baseSize * confidenceAdjustment, 100)
    }
    
    /// Calculate stop loss and take profit levels
    private func calculateRiskLevels(
        data: SageMarketData,
        regime: SageMarketRegime,
        signal: SageSignalType
    ) -> (stopLoss: Double, takeProfit: Double) {
        
        // Get ATR for volatility-based stops
        let atrData = TechnicalsEngine.atrApproxFromCloses(data.closes, period: 14)
        let atrPercent = atrData?.atrPercent ?? 2.0
        
        let atrMultiplier = regime.stopLossATRMultiplier
        let stopLossPercent = atrPercent * atrMultiplier
        
        // Take profit at minimum 1.5:1 R:R
        let takeProfitPercent = stopLossPercent * 2.0
        
        return (stopLossPercent, takeProfitPercent)
    }
    
    // MARK: - Cache & History
    
    /// Get cached consensus for a symbol
    public func getCachedConsensus(for symbol: String) -> SageConsensus? {
        return latestConsensus[symbol]
    }
    
    /// Clear all caches
    public func clearCache() {
        signalCache.removeAll()
        latestConsensus.removeAll()
        latestSignals.removeAll()
        currentRegimes.removeAll()
    }
    
    // MARK: - Persistence
    
    private func saveSignalHistory() {
        // Only save last 100 signals per symbol
        let limitedSignals = Array(latestSignals.prefix(100))
        
        do {
            let data = try JSONEncoder().encode(limitedSignals)
            UserDefaults.standard.set(data, forKey: Self.signalHistoryKey)
        } catch {
            print("[SageAlgorithmEngine] Failed to save signal history: \(error)")
        }
    }
    
    private func loadSignalHistory() {
        guard let data = UserDefaults.standard.data(forKey: Self.signalHistoryKey) else { return }
        
        do {
            latestSignals = try JSONDecoder().decode([SageSignal].self, from: data)
        } catch {
            print("[SageAlgorithmEngine] Failed to load signal history: \(error)")
        }
    }
    
    // MARK: - Algorithm Info
    
    /// Get information about all available algorithms
    public func getAlgorithmInfos() -> [SageAlgorithmInfo] {
        return algorithms.map { SageAlgorithmInfo(from: $0) }
    }
    
    /// Get info for a specific algorithm
    public func getAlgorithmInfo(id: String) -> SageAlgorithmInfo? {
        guard let algorithm = algorithms.first(where: { $0.id == id }) else {
            return nil
        }
        return SageAlgorithmInfo(from: algorithm)
    }
}

// MARK: - AppConfig Extension (if not defined elsewhere)

// isDeveloperMode is defined in AppConfig.swift — removed duplicate declaration
