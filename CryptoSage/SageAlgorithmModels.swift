//
//  SageAlgorithmModels.swift
//  CryptoSage
//
//  CryptoSage AI's proprietary algorithm data models.
//  These power the Sage algorithm suite - CryptoSage's unique trading intelligence.
//

import Foundation
import SwiftUI

// MARK: - Market Regime

/// CryptoSage AI's market regime classification
/// Research-backed: ADX + Bollinger Band width + ATR for regime detection
public enum SageMarketRegime: String, Codable, CaseIterable, Identifiable {
    case strongTrend    // ADX > 40 - very strong trend, high confidence
    case trending       // ADX 25-40 - tradeable trend
    case weakTrend      // ADX 20-25 - weak trend, use caution
    case ranging        // ADX < 20, low BB width - range-bound, mean reversion
    case volatile       // ADX < 25 but ATR expanding - choppy, reduce exposure
    case accumulation   // Low volatility + rising OBV - smart money entering
    case distribution   // High volume at highs + falling OBV - smart money exiting
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .strongTrend: return "Strong Trend"
        case .trending: return "Trending"
        case .weakTrend: return "Weak Trend"
        case .ranging: return "Range-Bound"
        case .volatile: return "Volatile"
        case .accumulation: return "Accumulation"
        case .distribution: return "Distribution"
        }
    }
    
    public var description: String {
        switch self {
        case .strongTrend: return "Very strong directional movement with high conviction"
        case .trending: return "Clear trend direction suitable for momentum strategies"
        case .weakTrend: return "Weak directional bias, trade with caution"
        case .ranging: return "Price oscillating in a range, ideal for mean reversion"
        case .volatile: return "High volatility without clear direction, reduce exposure"
        case .accumulation: return "Smart money appears to be accumulating"
        case .distribution: return "Smart money appears to be distributing"
        }
    }
    
    public var icon: String {
        switch self {
        case .strongTrend: return "arrow.up.right.circle.fill"
        case .trending: return "arrow.up.right"
        case .weakTrend: return "arrow.right"
        case .ranging: return "arrow.left.arrow.right"
        case .volatile: return "waveform.path.ecg"
        case .accumulation: return "arrow.down.to.line"
        case .distribution: return "arrow.up.to.line"
        }
    }
    
    public var color: Color {
        switch self {
        case .strongTrend: return .green
        case .trending: return .blue
        case .weakTrend: return .orange
        case .ranging: return .purple
        case .volatile: return .red
        case .accumulation: return .cyan
        case .distribution: return .pink
        }
    }
    
    /// Recommended position size multiplier based on regime
    public var positionSizeMultiplier: Double {
        switch self {
        case .strongTrend: return 1.0      // Full position
        case .trending: return 0.75        // 75%
        case .weakTrend: return 0.5        // 50%
        case .ranging: return 0.5          // 50% for mean reversion
        case .volatile: return 0.25        // 25% - minimal exposure
        case .accumulation: return 1.0     // Full position - early entry
        case .distribution: return 0.0     // Exit or avoid
        }
    }
    
    /// Recommended stop loss multiplier (ATR multiplier)
    public var stopLossATRMultiplier: Double {
        switch self {
        case .strongTrend: return 1.5
        case .trending: return 2.0
        case .weakTrend: return 2.5
        case .ranging: return 2.0
        case .volatile: return 3.0
        case .accumulation: return 2.0
        case .distribution: return 1.5  // Tight stops if somehow in position
        }
    }
    
    /// Detect market regime from price/volume data (nonisolated - safe to call from any context)
    /// This bypasses the @MainActor-isolated SageAlgorithmEngine for use in synchronous contexts
    public static func detect(closes: [Double], volumes: [Double]) -> SageMarketRegime {
        guard let result = TechnicalsEngine.detectMarketRegime(closes: closes, volumes: volumes) else {
            return .ranging
        }
        return SageMarketRegime(rawValue: result.regime) ?? .ranging
    }
}

// MARK: - Signal Type

/// CryptoSage AI signal types
public enum SageSignalType: String, Codable, CaseIterable {
    case strongBuy   // 4+ algorithms bullish, high confidence (80%+)
    case buy         // 3+ algorithms bullish, good confidence (60%+)
    case hold        // Mixed signals or low confidence
    case sell        // 3+ algorithms bearish, good confidence
    case strongSell  // 4+ algorithms bearish, high confidence
    
    public var displayName: String {
        switch self {
        case .strongBuy: return "Strong Buy"
        case .buy: return "Buy"
        case .hold: return "Hold"
        case .sell: return "Sell"
        case .strongSell: return "Strong Sell"
        }
    }
    
    public var color: Color {
        switch self {
        case .strongBuy: return .green
        case .buy: return Color.green.opacity(0.7)
        case .hold: return .gray
        case .sell: return Color.red.opacity(0.7)
        case .strongSell: return .red
        }
    }
    
    public var icon: String {
        switch self {
        case .strongBuy: return "arrow.up.circle.fill"
        case .buy: return "arrow.up.circle"
        case .hold: return "minus.circle"
        case .sell: return "arrow.down.circle"
        case .strongSell: return "arrow.down.circle.fill"
        }
    }
    
    /// Numeric value for calculations (-2 to +2)
    public var numericValue: Double {
        switch self {
        case .strongBuy: return 2.0
        case .buy: return 1.0
        case .hold: return 0.0
        case .sell: return -1.0
        case .strongSell: return -2.0
        }
    }
}

// MARK: - Algorithm Category

/// Categories for CryptoSage AI algorithms
public enum SageAlgorithmCategory: String, Codable, CaseIterable {
    case trend          // Trend following
    case momentum       // Momentum-based
    case meanReversion  // Mean reversion
    case multiTimeframe // Multi-timeframe analysis
    case volatility     // Volatility-based
    case ai             // AI/ML enhanced
    
    public var displayName: String {
        switch self {
        case .trend: return "Trend"
        case .momentum: return "Momentum"
        case .meanReversion: return "Mean Reversion"
        case .multiTimeframe: return "Multi-Timeframe"
        case .volatility: return "Volatility"
        case .ai: return "AI Enhanced"
        }
    }
    
    public var icon: String {
        switch self {
        case .trend: return "chart.line.uptrend.xyaxis"
        case .momentum: return "bolt.fill"
        case .meanReversion: return "arrow.left.arrow.right"
        case .multiTimeframe: return "clock.badge.checkmark"
        case .volatility: return "waveform.path.ecg"
        case .ai: return "brain"
        }
    }
    
    public var color: Color {
        switch self {
        case .trend: return .blue
        case .momentum: return .orange
        case .meanReversion: return .purple
        case .multiTimeframe: return .cyan
        case .volatility: return .red
        case .ai: return .green
        }
    }
}

// MARK: - Individual Signal

/// Signal generated by a single CryptoSage AI algorithm
public struct SageSignal: Codable, Identifiable {
    public let id: UUID
    public let algorithmId: String
    public let algorithmName: String
    public let category: SageAlgorithmCategory
    public let timestamp: Date
    public let symbol: String
    public let type: SageSignalType
    public let score: Double              // -100 to +100 (negative = bearish, positive = bullish)
    public let confidence: Double         // 0-1 (how confident the algorithm is)
    public let regime: SageMarketRegime
    public let factors: [String]          // What triggered the signal
    public let suggestedEntry: Double?
    public let suggestedStopLoss: Double?
    public let suggestedTakeProfit: Double?
    
    public init(
        id: UUID = UUID(),
        algorithmId: String,
        algorithmName: String,
        category: SageAlgorithmCategory,
        timestamp: Date = Date(),
        symbol: String,
        type: SageSignalType,
        score: Double,
        confidence: Double,
        regime: SageMarketRegime,
        factors: [String],
        suggestedEntry: Double? = nil,
        suggestedStopLoss: Double? = nil,
        suggestedTakeProfit: Double? = nil
    ) {
        self.id = id
        self.algorithmId = algorithmId
        self.algorithmName = algorithmName
        self.category = category
        self.timestamp = timestamp
        self.symbol = symbol
        self.type = type
        self.score = score
        self.confidence = confidence
        self.regime = regime
        self.factors = factors
        self.suggestedEntry = suggestedEntry
        self.suggestedStopLoss = suggestedStopLoss
        self.suggestedTakeProfit = suggestedTakeProfit
    }
    
    /// Risk/reward ratio if entry, stop, and target are set
    public var riskRewardRatio: Double? {
        guard let entry = suggestedEntry,
              let stop = suggestedStopLoss,
              let target = suggestedTakeProfit else { return nil }
        
        let risk = abs(entry - stop)
        let reward = abs(target - entry)
        guard risk > 0 else { return nil }
        return reward / risk
    }
}

// MARK: - Consensus (Combined Output)

/// Combined output from all CryptoSage AI algorithms
/// This is what Sage Neural produces - the master recommendation
public struct SageConsensus: Codable, Identifiable {
    public let id: UUID
    public let symbol: String
    public let timestamp: Date
    public let regime: SageMarketRegime
    
    // Individual algorithm scores (-100 to +100)
    public let trendScore: Double
    public let momentumScore: Double
    public let reversionScore: Double
    public let confluenceScore: Double
    public let volatilityScore: Double
    
    // Sentiment score (Fear/Greed as contrarian: -100 = extreme greed/bearish, +100 = extreme fear/bullish)
    public let sentimentScore: Double
    
    // Master recommendation
    public let masterSignal: SageSignalType
    public let confidence: Double               // 0-100
    public let explanation: String              // AI-generated explanation for users
    
    // Individual signals from each algorithm
    public let signals: [SageSignal]
    
    // Risk metrics
    public let suggestedPositionSize: Double    // % of portfolio (0-100)
    public let suggestedStopLoss: Double        // % from entry
    public let suggestedTakeProfit: Double      // % from entry
    
    public init(
        id: UUID = UUID(),
        symbol: String,
        timestamp: Date = Date(),
        regime: SageMarketRegime,
        trendScore: Double,
        momentumScore: Double,
        reversionScore: Double,
        confluenceScore: Double,
        volatilityScore: Double,
        sentimentScore: Double,
        masterSignal: SageSignalType,
        confidence: Double,
        explanation: String,
        signals: [SageSignal],
        suggestedPositionSize: Double,
        suggestedStopLoss: Double,
        suggestedTakeProfit: Double
    ) {
        self.id = id
        self.symbol = symbol
        self.timestamp = timestamp
        self.regime = regime
        self.trendScore = trendScore
        self.momentumScore = momentumScore
        self.reversionScore = reversionScore
        self.confluenceScore = confluenceScore
        self.volatilityScore = volatilityScore
        self.sentimentScore = sentimentScore
        self.masterSignal = masterSignal
        self.confidence = confidence
        self.explanation = explanation
        self.signals = signals
        self.suggestedPositionSize = suggestedPositionSize
        self.suggestedStopLoss = suggestedStopLoss
        self.suggestedTakeProfit = suggestedTakeProfit
    }
    
    /// Average score across all algorithms
    public var averageScore: Double {
        let scores = [trendScore, momentumScore, reversionScore, confluenceScore, volatilityScore]
        return scores.reduce(0, +) / Double(scores.count)
    }
    
    /// Number of bullish algorithms
    public var bullishCount: Int {
        signals.filter { $0.score > 20 }.count
    }
    
    /// Number of bearish algorithms
    public var bearishCount: Int {
        signals.filter { $0.score < -20 }.count
    }
    
    /// Agreement level (0-1) - how much algorithms agree
    public var agreementLevel: Double {
        let scores = [trendScore, momentumScore, reversionScore, confluenceScore, volatilityScore]
        let mean = scores.reduce(0, +) / Double(scores.count)
        let variance = scores.reduce(0) { $0 + pow($1 - mean, 2) } / Double(scores.count)
        let stdDev = sqrt(variance)
        // Lower stdDev = higher agreement. Normalize to 0-1 where 1 = perfect agreement
        return max(0, 1 - (stdDev / 50))
    }
}

// MARK: - Market Data Input

/// Market data structure for algorithm evaluation
public struct SageMarketData: Codable {
    public let symbol: String
    public let timestamp: Date
    public let currentPrice: Double
    public let closes: [Double]           // Historical closes (newest last)
    public let highs: [Double]            // Historical highs
    public let lows: [Double]             // Historical lows
    public let volumes: [Double]          // Historical volumes
    public let timeframe: SageTimeframe
    
    // Optional multi-timeframe data
    public var higherTimeframeCloses: [Double]?  // e.g., 4H or 1D
    public var lowerTimeframeCloses: [Double]?   // e.g., 15m or 1H
    
    // Optional sentiment data
    public var fearGreedIndex: Int?       // 0-100 (0 = extreme fear, 100 = extreme greed)
    
    public init(
        symbol: String,
        timestamp: Date = Date(),
        currentPrice: Double,
        closes: [Double],
        highs: [Double],
        lows: [Double],
        volumes: [Double],
        timeframe: SageTimeframe,
        higherTimeframeCloses: [Double]? = nil,
        lowerTimeframeCloses: [Double]? = nil,
        fearGreedIndex: Int? = nil
    ) {
        self.symbol = symbol
        self.timestamp = timestamp
        self.currentPrice = currentPrice
        self.closes = closes
        self.highs = highs
        self.lows = lows
        self.volumes = volumes
        self.timeframe = timeframe
        self.higherTimeframeCloses = higherTimeframeCloses
        self.lowerTimeframeCloses = lowerTimeframeCloses
        self.fearGreedIndex = fearGreedIndex
    }
}

// MARK: - Timeframe

/// Supported timeframes for Sage algorithms
public enum SageTimeframe: String, Codable, CaseIterable {
    case m15 = "15m"
    case h1 = "1h"
    case h4 = "4h"
    case d1 = "1d"
    
    public var displayName: String {
        switch self {
        case .m15: return "15 Minutes"
        case .h1: return "1 Hour"
        case .h4: return "4 Hours"
        case .d1: return "1 Day"
        }
    }
    
    public var shortName: String { rawValue.uppercased() }
    
    /// Minimum data points needed for reliable signals
    public var minDataPoints: Int {
        switch self {
        case .m15: return 200   // ~50 hours
        case .h1: return 200    // ~8 days
        case .h4: return 200    // ~33 days
        case .d1: return 200    // ~200 days
        }
    }
}

// MARK: - Algorithm Protocol

/// Protocol that all CryptoSage AI algorithms conform to
public protocol SageAlgorithm {
    var id: String { get }
    var name: String { get }
    var description: String { get }
    var category: SageAlgorithmCategory { get }
    var primaryTimeframe: SageTimeframe { get }
    var minDataPoints: Int { get }
    var isInternal: Bool { get }  // Dev-only (true) or user-facing (false)
    
    /// Evaluate the algorithm and generate a signal
    func evaluate(data: SageMarketData, regime: SageMarketRegime) -> SageSignal?
    
    /// Calculate a score without full signal generation (for quick consensus)
    func calculateScore(data: SageMarketData) -> Double
}

// MARK: - Algorithm Info (for UI)

/// Displayable information about a Sage algorithm
public struct SageAlgorithmInfo: Identifiable {
    public let id: String
    public let name: String
    public let description: String
    public let category: SageAlgorithmCategory
    public let timeframe: SageTimeframe
    public let isInternal: Bool
    
    public init(from algorithm: SageAlgorithm) {
        self.id = algorithm.id
        self.name = algorithm.name
        self.description = algorithm.description
        self.category = algorithm.category
        self.timeframe = algorithm.primaryTimeframe
        self.isInternal = algorithm.isInternal
    }
}

// MARK: - Performance Tracking

/// Track algorithm performance for validation
public struct SageAlgorithmPerformance: Codable, Identifiable {
    public let id: UUID
    public let algorithmId: String
    public let symbol: String
    public let startDate: Date
    public let endDate: Date
    
    public var totalSignals: Int
    public var winningSignals: Int
    public var losingSignals: Int
    public var totalReturnPercent: Double
    public var maxDrawdownPercent: Double
    public var sharpeRatio: Double
    public var sortinoRatio: Double
    public var profitFactor: Double
    
    public init(
        id: UUID = UUID(),
        algorithmId: String,
        symbol: String,
        startDate: Date,
        endDate: Date
    ) {
        self.id = id
        self.algorithmId = algorithmId
        self.symbol = symbol
        self.startDate = startDate
        self.endDate = endDate
        self.totalSignals = 0
        self.winningSignals = 0
        self.losingSignals = 0
        self.totalReturnPercent = 0
        self.maxDrawdownPercent = 0
        self.sharpeRatio = 0
        self.sortinoRatio = 0
        self.profitFactor = 0
    }
    
    public var winRate: Double {
        guard totalSignals > 0 else { return 0 }
        return Double(winningSignals) / Double(totalSignals) * 100
    }
    
    /// Check if algorithm passes validation criteria
    public var passesValidation: Bool {
        return sharpeRatio >= 1.0 &&
               maxDrawdownPercent <= 25 &&
               winRate >= 45 &&
               profitFactor >= 1.5
    }
}
