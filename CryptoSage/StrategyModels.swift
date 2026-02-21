//
//  StrategyModels.swift
//  CryptoSage
//
//  Comprehensive data models for algorithmic trading strategies.
//  Supports rule-based strategies using technical indicators with
//  entry/exit conditions and position sizing rules.
//

import Foundation
import SwiftUI

// MARK: - Strategy

/// A complete trading strategy with entry/exit rules and risk management
public struct TradingStrategy: Codable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var description: String
    public var tradingPair: String
    public var timeframe: StrategyTimeframe
    
    // Strategy rules
    public var entryConditions: [StrategyCondition]
    public var exitConditions: [StrategyCondition]
    public var conditionLogic: ConditionLogic
    
    // Risk management
    public var riskManagement: RiskManagement
    public var positionSizing: PositionSizing
    
    // Metadata
    public var isEnabled: Bool
    public var createdAt: Date
    public var lastModifiedAt: Date
    public var tags: [String]
    
    // Backtest results (if available)
    public var backtestResults: BacktestSummary?
    
    public init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        tradingPair: String = "BTC_USDT",
        timeframe: StrategyTimeframe = .oneDay,
        entryConditions: [StrategyCondition] = [],
        exitConditions: [StrategyCondition] = [],
        conditionLogic: ConditionLogic = .all,
        riskManagement: RiskManagement = RiskManagement(),
        positionSizing: PositionSizing = PositionSizing(),
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        lastModifiedAt: Date = Date(),
        tags: [String] = [],
        backtestResults: BacktestSummary? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.tradingPair = tradingPair
        self.timeframe = timeframe
        self.entryConditions = entryConditions
        self.exitConditions = exitConditions
        self.conditionLogic = conditionLogic
        self.riskManagement = riskManagement
        self.positionSizing = positionSizing
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.lastModifiedAt = lastModifiedAt
        self.tags = tags
        self.backtestResults = backtestResults
    }
    
    /// Parse base and quote assets from trading pair
    public var baseAsset: String {
        let parts = tradingPair.split(separator: "_")
        return parts.first.map(String.init) ?? tradingPair
    }
    
    public var quoteAsset: String {
        let parts = tradingPair.split(separator: "_")
        return parts.count > 1 ? String(parts[1]) : "USDT"
    }
    
    public static func == (lhs: TradingStrategy, rhs: TradingStrategy) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Strategy Timeframe

public enum StrategyTimeframe: String, Codable, CaseIterable {
    case oneMinute = "1m"
    case fiveMinutes = "5m"
    case fifteenMinutes = "15m"
    case thirtyMinutes = "30m"
    case oneHour = "1h"
    case fourHours = "4h"
    case oneDay = "1d"
    case oneWeek = "1w"
    
    public var displayName: String {
        switch self {
        case .oneMinute: return "1 Minute"
        case .fiveMinutes: return "5 Minutes"
        case .fifteenMinutes: return "15 Minutes"
        case .thirtyMinutes: return "30 Minutes"
        case .oneHour: return "1 Hour"
        case .fourHours: return "4 Hours"
        case .oneDay: return "1 Day"
        case .oneWeek: return "1 Week"
        }
    }
    
    public var shortName: String {
        rawValue.uppercased()
    }
    
    /// Interval in seconds
    public var intervalSeconds: Int {
        switch self {
        case .oneMinute: return 60
        case .fiveMinutes: return 300
        case .fifteenMinutes: return 900
        case .thirtyMinutes: return 1800
        case .oneHour: return 3600
        case .fourHours: return 14400
        case .oneDay: return 86400
        case .oneWeek: return 604800
        }
    }
    
    /// Minimum candles needed for indicator calculations
    public var minimumCandles: Int {
        switch self {
        case .oneMinute, .fiveMinutes: return 200
        case .fifteenMinutes, .thirtyMinutes: return 150
        case .oneHour, .fourHours: return 100
        case .oneDay, .oneWeek: return 50
        }
    }
}

// MARK: - Condition Logic

/// How multiple conditions are combined
public enum ConditionLogic: String, Codable, CaseIterable {
    case all = "AND"      // All conditions must be true
    case any = "OR"       // Any condition must be true
    case custom = "CUSTOM" // Custom logic (advanced)
    
    public var displayName: String {
        switch self {
        case .all: return "All conditions (AND)"
        case .any: return "Any condition (OR)"
        case .custom: return "Custom logic"
        }
    }
    
    /// Short name for compact UI elements like segmented pickers
    public var shortName: String {
        switch self {
        case .all: return "AND"
        case .any: return "OR"
        case .custom: return "Custom"
        }
    }
}

// MARK: - Strategy Condition

/// A single condition that can trigger entry/exit
public struct StrategyCondition: Codable, Identifiable, Equatable {
    public let id: UUID
    public var indicator: StrategyIndicatorType
    public var comparison: ComparisonOperator
    public var value: ConditionValue
    public var isEnabled: Bool
    
    public init(
        id: UUID = UUID(),
        indicator: StrategyIndicatorType,
        comparison: ComparisonOperator,
        value: ConditionValue,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.indicator = indicator
        self.comparison = comparison
        self.value = value
        self.isEnabled = isEnabled
    }
    
    /// Human-readable description of the condition
    public var description: String {
        "\(indicator.displayName) \(comparison.symbol) \(value.displayValue)"
    }
    
    public static func == (lhs: StrategyCondition, rhs: StrategyCondition) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Indicator Type

/// Technical indicators that can be used in conditions
public enum StrategyIndicatorType: String, Codable, CaseIterable {
    // Price-based
    case price = "price"
    case priceChange = "price_change"
    
    // Moving Averages
    case sma10 = "sma_10"
    case sma20 = "sma_20"
    case sma50 = "sma_50"
    case sma200 = "sma_200"
    case ema12 = "ema_12"
    case ema26 = "ema_26"
    
    // Oscillators
    case rsi = "rsi"
    case macdLine = "macd_line"
    case macdSignal = "macd_signal"
    case macdHistogram = "macd_histogram"
    case stochK = "stoch_k"
    case stochD = "stoch_d"
    
    // Volatility
    case bollingerUpper = "bb_upper"
    case bollingerMiddle = "bb_middle"
    case bollingerLower = "bb_lower"
    case atr = "atr"
    
    // Volume
    case volume = "volume"
    case volumeChange = "volume_change"
    case obv = "obv"
    
    // Momentum
    case momentum = "momentum"
    case roc = "roc"
    case williamsR = "williams_r"
    case cci = "cci"
    
    // Crossovers (special)
    case smaCrossover = "sma_crossover"
    case emaCrossover = "ema_crossover"
    case macdCrossover = "macd_crossover"
    
    public var displayName: String {
        switch self {
        case .price: return "Price"
        case .priceChange: return "Price Change %"
        case .sma10: return "SMA (10)"
        case .sma20: return "SMA (20)"
        case .sma50: return "SMA (50)"
        case .sma200: return "SMA (200)"
        case .ema12: return "EMA (12)"
        case .ema26: return "EMA (26)"
        case .rsi: return "RSI (14)"
        case .macdLine: return "MACD Line"
        case .macdSignal: return "MACD Signal"
        case .macdHistogram: return "MACD Histogram"
        case .stochK: return "Stochastic %K"
        case .stochD: return "Stochastic %D"
        case .bollingerUpper: return "Bollinger Upper"
        case .bollingerMiddle: return "Bollinger Middle"
        case .bollingerLower: return "Bollinger Lower"
        case .atr: return "ATR (14)"
        case .volume: return "Volume"
        case .volumeChange: return "Volume Change %"
        case .obv: return "OBV"
        case .momentum: return "Momentum"
        case .roc: return "Rate of Change"
        case .williamsR: return "Williams %R"
        case .cci: return "CCI"
        case .smaCrossover: return "SMA Crossover"
        case .emaCrossover: return "EMA Crossover"
        case .macdCrossover: return "MACD Crossover"
        }
    }
    
    public var category: StrategyIndicatorCategory {
        switch self {
        case .price, .priceChange:
            return .price
        case .sma10, .sma20, .sma50, .sma200, .ema12, .ema26:
            return .movingAverage
        case .rsi, .macdLine, .macdSignal, .macdHistogram, .stochK, .stochD:
            return .oscillator
        case .bollingerUpper, .bollingerMiddle, .bollingerLower, .atr:
            return .volatility
        case .volume, .volumeChange, .obv:
            return .volume
        case .momentum, .roc, .williamsR, .cci:
            return .momentum
        case .smaCrossover, .emaCrossover, .macdCrossover:
            return .crossover
        }
    }
    
    /// Whether this indicator compares against another indicator (crossover)
    public var isCrossover: Bool {
        category == .crossover
    }
    
    /// Default value range for this indicator
    public var valueRange: ClosedRange<Double>? {
        switch self {
        case .rsi, .stochK, .stochD:
            return 0...100
        case .williamsR:
            return -100...0
        case .cci:
            return -200...200
        default:
            return nil
        }
    }
    
    /// Common threshold values for this indicator
    public var commonThresholds: [Double] {
        switch self {
        case .rsi:
            return [30, 50, 70]
        case .stochK, .stochD:
            return [20, 50, 80]
        case .williamsR:
            return [-80, -50, -20]
        case .cci:
            return [-100, 0, 100]
        case .macdHistogram:
            return [-1, 0, 1]
        default:
            return []
        }
    }
}

// MARK: - Strategy Indicator Category

public enum StrategyIndicatorCategory: String, Codable, CaseIterable {
    case price = "Price"
    case movingAverage = "Moving Averages"
    case oscillator = "Oscillators"
    case volatility = "Volatility"
    case volume = "Volume"
    case momentum = "Momentum"
    case crossover = "Crossovers"
    
    public var icon: String {
        switch self {
        case .price: return "dollarsign.circle"
        case .movingAverage: return "chart.line.uptrend.xyaxis"
        case .oscillator: return "waveform.path"
        case .volatility: return "arrow.up.arrow.down"
        case .volume: return "chart.bar.fill"
        case .momentum: return "bolt.fill"
        case .crossover: return "arrow.triangle.swap"
        }
    }
    
    public var color: Color {
        switch self {
        case .price: return .blue
        case .movingAverage: return .purple
        case .oscillator: return .orange
        case .volatility: return .red
        case .volume: return .green
        case .momentum: return .yellow
        case .crossover: return .cyan
        }
    }
    
    public var indicators: [StrategyIndicatorType] {
        StrategyIndicatorType.allCases.filter { $0.category == self }
    }
}

// MARK: - Comparison Operator

public enum ComparisonOperator: String, Codable, CaseIterable {
    case greaterThan = ">"
    case lessThan = "<"
    case greaterOrEqual = ">="
    case lessOrEqual = "<="
    case equals = "=="
    case crossesAbove = "crosses_above"
    case crossesBelow = "crosses_below"
    
    public var symbol: String {
        switch self {
        case .greaterThan: return ">"
        case .lessThan: return "<"
        case .greaterOrEqual: return "≥"
        case .lessOrEqual: return "≤"
        case .equals: return "="
        case .crossesAbove: return "↗ crosses above"
        case .crossesBelow: return "↘ crosses below"
        }
    }
    
    public var displayName: String {
        switch self {
        case .greaterThan: return "Greater than"
        case .lessThan: return "Less than"
        case .greaterOrEqual: return "Greater or equal"
        case .lessOrEqual: return "Less or equal"
        case .equals: return "Equals"
        case .crossesAbove: return "Crosses above"
        case .crossesBelow: return "Crosses below"
        }
    }
    
    /// Whether this operator requires historical data (for crossover detection)
    public var requiresHistory: Bool {
        self == .crossesAbove || self == .crossesBelow
    }
}

// MARK: - Condition Value

/// The target value for a condition comparison
public enum ConditionValue: Codable, Equatable {
    case number(Double)
    case indicator(StrategyIndicatorType)
    case percentage(Double)
    
    public var displayValue: String {
        switch self {
        case .number(let value):
            return String(format: "%.2f", value)
        case .indicator(let ind):
            return ind.displayName
        case .percentage(let pct):
            return String(format: "%.1f%%", pct)
        }
    }
    
    public var numericValue: Double? {
        switch self {
        case .number(let value): return value
        case .percentage(let pct): return pct
        case .indicator: return nil
        }
    }
}

// MARK: - Risk Management

/// Risk management settings for a strategy
public struct RiskManagement: Codable, Equatable {
    /// Stop loss percentage (e.g., 5 = 5% stop loss)
    public var stopLossPercent: Double?
    
    /// Take profit percentage (e.g., 10 = 10% take profit)
    public var takeProfitPercent: Double?
    
    /// Trailing stop percentage (dynamic stop loss)
    public var trailingStopPercent: Double?
    
    /// Maximum drawdown allowed before strategy stops
    public var maxDrawdownPercent: Double
    
    /// Maximum number of consecutive losses before pausing
    public var maxConsecutiveLosses: Int
    
    /// Daily loss limit percentage
    public var dailyLossLimitPercent: Double?
    
    public init(
        stopLossPercent: Double? = 5.0,
        takeProfitPercent: Double? = 10.0,
        trailingStopPercent: Double? = nil,
        maxDrawdownPercent: Double = 20.0,
        maxConsecutiveLosses: Int = 5,
        dailyLossLimitPercent: Double? = nil
    ) {
        self.stopLossPercent = stopLossPercent
        self.takeProfitPercent = takeProfitPercent
        self.trailingStopPercent = trailingStopPercent
        self.maxDrawdownPercent = maxDrawdownPercent
        self.maxConsecutiveLosses = maxConsecutiveLosses
        self.dailyLossLimitPercent = dailyLossLimitPercent
    }
    
    /// Calculate risk/reward ratio
    public var riskRewardRatio: Double? {
        guard let sl = stopLossPercent, let tp = takeProfitPercent, sl > 0 else { return nil }
        return tp / sl
    }
}

// MARK: - Position Sizing

/// Position sizing configuration
public struct PositionSizing: Codable, Equatable {
    public var method: PositionSizingMethod
    
    /// Fixed amount in quote currency (e.g., $100)
    public var fixedAmount: Double
    
    /// Percentage of portfolio per trade
    public var portfolioPercent: Double
    
    /// Risk percentage per trade (for risk-based sizing)
    public var riskPercent: Double
    
    /// Maximum position size as percentage of portfolio
    public var maxPositionPercent: Double
    
    public init(
        method: PositionSizingMethod = .fixedAmount,
        fixedAmount: Double = 100,
        portfolioPercent: Double = 5,
        riskPercent: Double = 1,
        maxPositionPercent: Double = 25
    ) {
        self.method = method
        self.fixedAmount = fixedAmount
        self.portfolioPercent = portfolioPercent
        self.riskPercent = riskPercent
        self.maxPositionPercent = maxPositionPercent
    }
}

// MARK: - Position Sizing Method

public enum PositionSizingMethod: String, Codable, CaseIterable {
    case fixedAmount = "fixed"
    case percentOfPortfolio = "percent"
    case riskBased = "risk"
    
    public var displayName: String {
        switch self {
        case .fixedAmount: return "Fixed Amount"
        case .percentOfPortfolio: return "% of Portfolio"
        case .riskBased: return "Risk-Based"
        }
    }
    
    public var description: String {
        switch self {
        case .fixedAmount:
            return "Trade a fixed dollar amount each time"
        case .percentOfPortfolio:
            return "Trade a percentage of your total portfolio"
        case .riskBased:
            return "Size based on stop loss and max risk per trade"
        }
    }
}

// MARK: - Backtest Summary

/// Summary of backtest results for a strategy
public struct BacktestSummary: Codable, Equatable {
    public let strategyId: UUID
    public let startDate: Date
    public let endDate: Date
    public let initialBalance: Double
    public let finalBalance: Double
    
    // Performance metrics
    public let totalTrades: Int
    public let winningTrades: Int
    public let losingTrades: Int
    public let winRate: Double
    
    // Returns
    public let totalReturnPercent: Double
    public let annualizedReturn: Double
    public let maxDrawdownPercent: Double
    
    // Risk-adjusted metrics
    public let sharpeRatio: Double
    public let sortinoRatio: Double?
    public let calmarRatio: Double?
    
    // Trade statistics
    public let averageWin: Double
    public let averageLoss: Double
    public let largestWin: Double
    public let largestLoss: Double
    public let averageHoldingPeriod: TimeInterval
    
    // Profit factor
    public let profitFactor: Double
    
    public init(
        strategyId: UUID,
        startDate: Date,
        endDate: Date,
        initialBalance: Double,
        finalBalance: Double,
        totalTrades: Int,
        winningTrades: Int,
        losingTrades: Int,
        winRate: Double,
        totalReturnPercent: Double,
        annualizedReturn: Double,
        maxDrawdownPercent: Double,
        sharpeRatio: Double,
        sortinoRatio: Double? = nil,
        calmarRatio: Double? = nil,
        averageWin: Double,
        averageLoss: Double,
        largestWin: Double,
        largestLoss: Double,
        averageHoldingPeriod: TimeInterval,
        profitFactor: Double
    ) {
        self.strategyId = strategyId
        self.startDate = startDate
        self.endDate = endDate
        self.initialBalance = initialBalance
        self.finalBalance = finalBalance
        self.totalTrades = totalTrades
        self.winningTrades = winningTrades
        self.losingTrades = losingTrades
        self.winRate = winRate
        self.totalReturnPercent = totalReturnPercent
        self.annualizedReturn = annualizedReturn
        self.maxDrawdownPercent = maxDrawdownPercent
        self.sharpeRatio = sharpeRatio
        self.sortinoRatio = sortinoRatio
        self.calmarRatio = calmarRatio
        self.averageWin = averageWin
        self.averageLoss = averageLoss
        self.largestWin = largestWin
        self.largestLoss = largestLoss
        self.averageHoldingPeriod = averageHoldingPeriod
        self.profitFactor = profitFactor
    }
    
    /// Net profit in dollars
    public var netProfit: Double {
        finalBalance - initialBalance
    }
    
    /// Risk/reward ratio based on average win/loss
    public var riskRewardRatio: Double {
        guard averageLoss != 0 else { return 0 }
        return abs(averageWin / averageLoss)
    }
    
    /// Performance grade (A-F based on key metrics)
    public var performanceGrade: String {
        var score = 0.0
        
        // Win rate contribution (30%)
        if winRate >= 60 { score += 30 }
        else if winRate >= 50 { score += 20 }
        else if winRate >= 40 { score += 10 }
        
        // Profit factor contribution (25%)
        if profitFactor >= 2.0 { score += 25 }
        else if profitFactor >= 1.5 { score += 18 }
        else if profitFactor >= 1.2 { score += 12 }
        else if profitFactor >= 1.0 { score += 5 }
        
        // Sharpe ratio contribution (25%)
        if sharpeRatio >= 2.0 { score += 25 }
        else if sharpeRatio >= 1.5 { score += 18 }
        else if sharpeRatio >= 1.0 { score += 12 }
        else if sharpeRatio >= 0.5 { score += 5 }
        
        // Drawdown contribution (20%)
        if maxDrawdownPercent <= 10 { score += 20 }
        else if maxDrawdownPercent <= 20 { score += 15 }
        else if maxDrawdownPercent <= 30 { score += 8 }
        
        if score >= 85 { return "A" }
        if score >= 70 { return "B" }
        if score >= 55 { return "C" }
        if score >= 40 { return "D" }
        return "F"
    }
}

// MARK: - Strategy Signal

/// A signal generated by evaluating strategy conditions
public struct StrategySignal: Identifiable {
    public let id: UUID
    public let strategyId: UUID
    public let type: SignalType
    public let timestamp: Date
    public let price: Double
    public let confidence: Double // 0-1
    public let triggeredConditions: [String]
    public var executedTradeId: UUID?
    
    public init(
        id: UUID = UUID(),
        strategyId: UUID,
        type: SignalType,
        timestamp: Date = Date(),
        price: Double,
        confidence: Double,
        triggeredConditions: [String],
        executedTradeId: UUID? = nil
    ) {
        self.id = id
        self.strategyId = strategyId
        self.type = type
        self.timestamp = timestamp
        self.price = price
        self.confidence = confidence
        self.triggeredConditions = triggeredConditions
        self.executedTradeId = executedTradeId
    }
}

// MARK: - Signal Type

public enum SignalType: String, Codable {
    case buy = "BUY"
    case sell = "SELL"
    case hold = "HOLD"
    
    public var color: Color {
        switch self {
        case .buy: return .green
        case .sell: return .red
        case .hold: return .gray
        }
    }
    
    public var icon: String {
        switch self {
        case .buy: return "arrow.up.circle.fill"
        case .sell: return "arrow.down.circle.fill"
        case .hold: return "pause.circle.fill"
        }
    }
}

// MARK: - Strategy Template

/// Pre-built strategy templates users can start from
public struct StrategyTemplate: Identifiable {
    public let id: String
    public let name: String
    public let description: String
    public let category: TemplateCategory
    public let difficulty: Difficulty
    public let strategy: TradingStrategy
    
    public enum TemplateCategory: String, CaseIterable {
        case sageAI = "CryptoSage AI"  // Premium AI-powered algorithms
        case trend = "Trend Following"
        case meanReversion = "Mean Reversion"
        case momentum = "Momentum"
        case breakout = "Breakout"
        case accumulation = "Accumulation"
        
        /// Short name for compact UI (category filter tabs)
        public var shortName: String {
            switch self {
            case .sageAI: return "Sage AI"
            case .trend: return "Trend"
            case .meanReversion: return "Mean Rev."
            case .momentum: return "Momentum"
            case .breakout: return "Breakout"
            case .accumulation: return "Accum."
            }
        }
        
        public var icon: String {
            switch self {
            case .sageAI: return "brain"
            case .trend: return "chart.line.uptrend.xyaxis"
            case .meanReversion: return "arrow.triangle.swap"
            case .momentum: return "bolt.fill"
            case .breakout: return "arrow.up.right.circle"
            case .accumulation: return "repeat.circle"
            }
        }
    }
    
    public enum Difficulty: String, CaseIterable {
        case beginner = "Beginner"
        case intermediate = "Intermediate"
        case advanced = "Advanced"
        
        public var color: Color {
            switch self {
            case .beginner: return .green
            case .intermediate: return .orange
            case .advanced: return .red
            }
        }
    }
}

// MARK: - Market Data for Strategy Evaluation

/// Market data snapshot used for strategy evaluation
public struct StrategyMarketData {
    public let symbol: String
    public let timestamp: Date
    public let open: Double
    public let high: Double
    public let low: Double
    public let close: Double
    public let volume: Double
    
    // Calculated indicators (populated by StrategyEngine)
    public var indicators: [StrategyIndicatorType: Double] = [:]
    
    // Previous candle data for crossover detection
    public var previousClose: Double?
    public var previousIndicators: [StrategyIndicatorType: Double] = [:]
    
    public init(
        symbol: String,
        timestamp: Date,
        open: Double,
        high: Double,
        low: Double,
        close: Double,
        volume: Double
    ) {
        self.symbol = symbol
        self.timestamp = timestamp
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.volume = volume
    }
}
