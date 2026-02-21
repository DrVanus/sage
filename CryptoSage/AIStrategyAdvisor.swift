//
//  AIStrategyAdvisor.swift
//  CryptoSage
//
//  AI-powered strategy advisor that explains indicators,
//  suggests improvements, and analyzes backtest results.
//

import Foundation
import SwiftUI

// MARK: - AI Strategy Advisor

@MainActor
public final class AIStrategyAdvisor: ObservableObject {
    public static let shared = AIStrategyAdvisor()
    
    @Published public var isAnalyzing: Bool = false
    @Published public var lastAnalysis: StrategyAnalysis?
    
    private init() {}
    
    // MARK: - Strategy Analysis
    
    /// Analyze a strategy and provide recommendations
    public func analyzeStrategy(_ strategy: TradingStrategy, backtestResult: BacktestResult? = nil) async -> StrategyAnalysis {
        isAnalyzing = true
        defer { isAnalyzing = false }
        
        var analysis = StrategyAnalysis(strategyId: strategy.id, strategyName: strategy.name)
        
        // Analyze entry conditions
        analysis.entryAnalysis = analyzeConditions(strategy.entryConditions, type: "entry")
        
        // Analyze exit conditions
        analysis.exitAnalysis = analyzeConditions(strategy.exitConditions, type: "exit")
        
        // Analyze risk management
        analysis.riskAnalysis = analyzeRiskManagement(strategy.riskManagement)
        
        // Analyze position sizing
        analysis.sizingAnalysis = analyzePositionSizing(strategy.positionSizing)
        
        // Generate overall recommendations
        analysis.recommendations = generateRecommendations(strategy, backtestResult: backtestResult)
        
        // Calculate overall score
        analysis.overallScore = calculateOverallScore(analysis)
        
        // Generate AI-powered summary if backtest available
        if let result = backtestResult {
            analysis.backtestInsights = generateBacktestInsights(result)
        }
        
        lastAnalysis = analysis
        return analysis
    }
    
    // MARK: - Condition Analysis
    
    private func analyzeConditions(_ conditions: [StrategyCondition], type: String) -> [ConditionAnalysis] {
        return conditions.map { condition in
            var analysis = ConditionAnalysis(conditionId: condition.id)
            
            // Get indicator info
            let indicatorInfo = getIndicatorExplanation(condition.indicator)
            analysis.explanation = indicatorInfo.explanation
            analysis.strengthScore = indicatorInfo.strengthScore
            
            // Analyze the specific condition setup
            analysis.suggestions = analyzeConditionSetup(condition)
            
            // Check for common issues
            analysis.warnings = checkConditionWarnings(condition)
            
            return analysis
        }
    }
    
    private func analyzeConditionSetup(_ condition: StrategyCondition) -> [String] {
        var suggestions: [String] = []
        
        switch condition.indicator {
        case .rsi:
            if case .number(let value) = condition.value {
                if condition.comparison == .lessThan && value < 25 {
                    suggestions.append("RSI < 25 is very aggressive. Consider using 30 for more trades.")
                } else if condition.comparison == .greaterThan && value > 75 {
                    suggestions.append("RSI > 75 is very aggressive. Consider using 70 for more trades.")
                }
            }
            
        case .macdHistogram:
            if condition.comparison == .crossesAbove || condition.comparison == .crossesBelow {
                suggestions.append("MACD crossover signals work best with trend confirmation (e.g., price above SMA).")
            }
            
        case .bollingerLower, .bollingerUpper:
            suggestions.append("Bollinger Band touches work well combined with RSI for confirmation.")
            
        case .sma50, .sma200:
            suggestions.append("Long-term MAs like SMA(50) and SMA(200) are best for trend following strategies.")
            
        default:
            break
        }
        
        return suggestions
    }
    
    private func checkConditionWarnings(_ condition: StrategyCondition) -> [String] {
        var warnings: [String] = []
        
        // Check for potentially problematic setups
        if condition.indicator.isCrossover && !condition.comparison.requiresHistory {
            warnings.append("Crossover indicators should use 'crosses above' or 'crosses below' comparisons.")
        }
        
        return warnings
    }
    
    // MARK: - Risk Management Analysis
    
    private func analyzeRiskManagement(_ risk: RiskManagement) -> RiskAnalysis {
        var analysis = RiskAnalysis()
        
        // Analyze stop loss
        if let sl = risk.stopLossPercent {
            if sl < 2 {
                analysis.stopLossRating = .tight
                analysis.stopLossSuggestion = "Stop loss of \(sl)% is quite tight. You may get stopped out by normal volatility. Consider 3-5% for crypto."
            } else if sl > 10 {
                analysis.stopLossRating = .wide
                analysis.stopLossSuggestion = "Stop loss of \(sl)% is wide. This could lead to large losses per trade. Consider tightening to 5-8%."
            } else {
                analysis.stopLossRating = .good
                analysis.stopLossSuggestion = "Stop loss of \(sl)% is reasonable for crypto volatility."
            }
        } else {
            analysis.stopLossRating = .missing
            analysis.stopLossSuggestion = "No stop loss set! This is risky. Always use a stop loss to protect capital."
        }
        
        // Analyze take profit
        if let tp = risk.takeProfitPercent {
            if let sl = risk.stopLossPercent {
                let rr = tp / sl
                if rr < 1.5 {
                    analysis.takeProfitRating = .low
                    analysis.takeProfitSuggestion = "Risk/reward ratio of 1:\(String(format: "%.1f", rr)) is low. Aim for at least 1:1.5 or higher."
                } else if rr >= 2 {
                    analysis.takeProfitRating = .good
                    analysis.takeProfitSuggestion = "Risk/reward ratio of 1:\(String(format: "%.1f", rr)) is excellent!"
                } else {
                    analysis.takeProfitRating = .acceptable
                    analysis.takeProfitSuggestion = "Risk/reward ratio of 1:\(String(format: "%.1f", rr)) is acceptable."
                }
            }
        }
        
        // Analyze max drawdown
        if risk.maxDrawdownPercent > 30 {
            analysis.drawdownSuggestion = "Max drawdown of \(risk.maxDrawdownPercent)% is high. Consider reducing to 20-25% to preserve capital."
        }
        
        return analysis
    }
    
    // MARK: - Position Sizing Analysis
    
    private func analyzePositionSizing(_ sizing: PositionSizing) -> SizingAnalysis {
        var analysis = SizingAnalysis()
        
        switch sizing.method {
        case .fixedAmount:
            analysis.methodRating = .basic
            analysis.suggestion = "Fixed amount sizing doesn't adapt to portfolio growth. Consider % of portfolio for better scaling."
            
        case .percentOfPortfolio:
            if sizing.portfolioPercent > 20 {
                analysis.methodRating = .risky
                analysis.suggestion = "\(sizing.portfolioPercent)% per trade is aggressive. Risk of ruin is high. Consider 5-10%."
            } else if sizing.portfolioPercent < 2 {
                analysis.methodRating = .conservative
                analysis.suggestion = "\(sizing.portfolioPercent)% per trade is very conservative. Growth will be slow but safe."
            } else {
                analysis.methodRating = .good
                analysis.suggestion = "\(sizing.portfolioPercent)% per trade is a reasonable position size."
            }
            
        case .riskBased:
            analysis.methodRating = .professional
            analysis.suggestion = "Risk-based sizing is professional! This automatically adjusts position size based on volatility."
        }
        
        // Check max position
        if sizing.maxPositionPercent > 50 {
            analysis.maxPositionWarning = "Max position of \(sizing.maxPositionPercent)% is very high. Consider limiting to 25-30%."
        }
        
        return analysis
    }
    
    // MARK: - Recommendations
    
    private func generateRecommendations(_ strategy: TradingStrategy, backtestResult: BacktestResult?) -> [StrategyRecommendation] {
        var recommendations: [StrategyRecommendation] = []
        
        // Check for missing exit conditions
        if strategy.exitConditions.isEmpty {
            recommendations.append(StrategyRecommendation(
                type: .critical,
                title: "No Exit Conditions",
                description: "Your strategy has no exit conditions besides stop loss/take profit. Consider adding indicator-based exits for better performance.",
                action: "Add exit conditions like RSI > 70 or MACD bearish crossover"
            ))
        }
        
        // Check for trend confirmation
        let hasTrendIndicator = strategy.entryConditions.contains(where: { condition in
            [StrategyIndicatorType.sma20, .sma50, .sma200, .ema26].contains(condition.indicator)
        })
        if !hasTrendIndicator {
            recommendations.append(StrategyRecommendation(
                type: .suggestion,
                title: "Add Trend Filter",
                description: "Consider adding a trend confirmation like 'Price > SMA(50)' to avoid trading against the trend.",
                action: "Add condition: Price greater than SMA(50)"
            ))
        }
        
        // Check for volume confirmation
        let hasVolumeIndicator = strategy.entryConditions.contains(where: { condition in
            [StrategyIndicatorType.volume, .volumeChange, .obv].contains(condition.indicator)
        })
        if !hasVolumeIndicator {
            recommendations.append(StrategyRecommendation(
                type: .suggestion,
                title: "Consider Volume",
                description: "Volume confirmation can improve signal quality. High volume on entries indicates stronger moves.",
                action: "Add condition: Volume Change > 20%"
            ))
        }
        
        // Analyze backtest results if available
        if let result = backtestResult {
            if result.winRate < 40 {
                recommendations.append(StrategyRecommendation(
                    type: .improvement,
                    title: "Low Win Rate",
                    description: "Win rate of \(String(format: "%.1f", result.winRate))% is below average. Consider adding confirmation conditions.",
                    action: "Review entry conditions and add filters"
                ))
            }
            
            if result.maxDrawdownPercent > 25 {
                recommendations.append(StrategyRecommendation(
                    type: .warning,
                    title: "High Drawdown",
                    description: "Max drawdown of \(String(format: "%.1f", result.maxDrawdownPercent))% indicates significant risk.",
                    action: "Tighten stop losses or reduce position sizes"
                ))
            }
            
            if result.profitFactor < 1 {
                recommendations.append(StrategyRecommendation(
                    type: .critical,
                    title: "Unprofitable Strategy",
                    description: "Profit factor below 1 means the strategy loses money over time.",
                    action: "Fundamentally rethink entry/exit conditions"
                ))
            }
        }
        
        return recommendations
    }
    
    // MARK: - Backtest Insights
    
    private func generateBacktestInsights(_ result: BacktestResult) -> [String] {
        var insights: [String] = []
        
        // Performance insight
        if result.totalReturnPercent > 0 {
            insights.append("Your strategy generated a \(String(format: "%.1f", result.totalReturnPercent))% return over the test period.")
        } else {
            insights.append("The strategy lost \(String(format: "%.1f", abs(result.totalReturnPercent)))% during the test period.")
        }
        
        // Win rate insight
        if result.winRate >= 60 {
            insights.append("Excellent win rate of \(String(format: "%.0f", result.winRate))%! Your entry conditions are well-tuned.")
        } else if result.winRate >= 50 {
            insights.append("Win rate of \(String(format: "%.0f", result.winRate))% is above coin-flip odds - this is positive.")
        } else {
            insights.append("Win rate of \(String(format: "%.0f", result.winRate))% means most trades lose. Consider more selective entries.")
        }
        
        // Risk-adjusted insight
        if result.sharpeRatio >= 1.5 {
            insights.append("Sharpe ratio of \(String(format: "%.2f", result.sharpeRatio)) indicates excellent risk-adjusted returns.")
        } else if result.sharpeRatio >= 1 {
            insights.append("Sharpe ratio of \(String(format: "%.2f", result.sharpeRatio)) shows decent risk-adjusted performance.")
        } else if result.sharpeRatio > 0 {
            insights.append("Sharpe ratio of \(String(format: "%.2f", result.sharpeRatio)) is positive but could be improved.")
        }
        
        // Drawdown insight
        if result.maxDrawdownPercent <= 10 {
            insights.append("Max drawdown of \(String(format: "%.1f", result.maxDrawdownPercent))% is excellent risk management.")
        } else if result.maxDrawdownPercent <= 20 {
            insights.append("Max drawdown of \(String(format: "%.1f", result.maxDrawdownPercent))% is acceptable for crypto strategies.")
        } else {
            insights.append("Max drawdown of \(String(format: "%.1f", result.maxDrawdownPercent))% is high - consider tighter risk controls.")
        }
        
        // Profit factor insight
        if result.profitFactor >= 2 {
            insights.append("Profit factor of \(String(format: "%.1f", result.profitFactor)) means winners are twice as large as losers - great!")
        } else if result.profitFactor >= 1.5 {
            insights.append("Profit factor of \(String(format: "%.1f", result.profitFactor)) shows winners outpace losers nicely.")
        }
        
        return insights
    }
    
    // MARK: - Score Calculation
    
    private func calculateOverallScore(_ analysis: StrategyAnalysis) -> Int {
        var score = 50 // Base score
        
        // Entry conditions (up to +20)
        let avgEntryScore = analysis.entryAnalysis.isEmpty ? 0 : 
            analysis.entryAnalysis.map { $0.strengthScore }.reduce(0, +) / analysis.entryAnalysis.count
        score += min(20, avgEntryScore * 2)
        
        // Risk management (up to +20)
        if case .good = analysis.riskAnalysis.stopLossRating { score += 10 }
        if case .good = analysis.riskAnalysis.takeProfitRating { score += 10 }
        
        // Position sizing (up to +10)
        if case .professional = analysis.sizingAnalysis.methodRating { score += 10 }
        else if case .good = analysis.sizingAnalysis.methodRating { score += 7 }
        
        // Penalties for issues
        let criticalCount = analysis.recommendations.filter { $0.type == .critical }.count
        let warningCount = analysis.recommendations.filter { $0.type == .warning }.count
        
        score -= criticalCount * 15
        score -= warningCount * 5
        
        return max(0, min(100, score))
    }
    
    // MARK: - Indicator Explanations
    
    public func getIndicatorExplanation(_ indicator: StrategyIndicatorType) -> IndicatorInfo {
        switch indicator {
        case .rsi:
            return IndicatorInfo(
                name: "RSI (Relative Strength Index)",
                explanation: "RSI measures momentum on a 0-100 scale. Below 30 is considered oversold (potential buy), above 70 is overbought (potential sell). It works best in ranging markets.",
                bestUseCase: "Mean reversion strategies, identifying exhaustion points",
                limitations: "Can stay overbought/oversold for extended periods in strong trends",
                strengthScore: 8
            )
            
        case .macdHistogram, .macdLine, .macdSignal:
            return IndicatorInfo(
                name: "MACD (Moving Average Convergence Divergence)",
                explanation: "MACD shows trend momentum using EMA differences. Crossovers of the MACD line above/below the signal line indicate buy/sell signals.",
                bestUseCase: "Trend following, momentum confirmation",
                limitations: "Lagging indicator, can give false signals in choppy markets",
                strengthScore: 7
            )
            
        case .sma20, .sma50, .sma200:
            return IndicatorInfo(
                name: "SMA (Simple Moving Average)",
                explanation: "SMA smooths price data over a period. Price above SMA suggests uptrend, below suggests downtrend. Commonly used periods are 20 (short), 50 (medium), 200 (long-term).",
                bestUseCase: "Trend identification, dynamic support/resistance",
                limitations: "Lagging, slow to react to price changes",
                strengthScore: 6
            )
            
        case .bollingerUpper, .bollingerMiddle, .bollingerLower:
            return IndicatorInfo(
                name: "Bollinger Bands",
                explanation: "Bollinger Bands show volatility using standard deviations around a moving average. Price touching bands can indicate overbought/oversold or breakout conditions.",
                bestUseCase: "Volatility trading, mean reversion, breakout identification",
                limitations: "Bands contract during consolidation making signals less reliable",
                strengthScore: 7
            )
            
        case .stochK, .stochD:
            return IndicatorInfo(
                name: "Stochastic Oscillator",
                explanation: "Stochastic shows where current price is relative to its range. Like RSI, below 20 is oversold, above 80 is overbought.",
                bestUseCase: "Short-term momentum, entry timing",
                limitations: "Very sensitive, produces many signals",
                strengthScore: 6
            )
            
        case .atr:
            return IndicatorInfo(
                name: "ATR (Average True Range)",
                explanation: "ATR measures volatility by averaging price range over time. Higher ATR = more volatile. Great for setting stop losses based on market conditions.",
                bestUseCase: "Position sizing, stop loss placement",
                limitations: "Doesn't indicate direction, only volatility",
                strengthScore: 8
            )
            
        case .volume, .volumeChange:
            return IndicatorInfo(
                name: "Volume",
                explanation: "Volume shows trading activity. High volume on price moves confirms the move's strength. Low volume moves may be weak and prone to reversal.",
                bestUseCase: "Confirmation of breakouts and trends",
                limitations: "Crypto volume can be manipulated, varies by exchange",
                strengthScore: 7
            )
            
        default:
            return IndicatorInfo(
                name: indicator.displayName,
                explanation: "Technical indicator used to analyze price action and generate trading signals.",
                bestUseCase: "Strategy dependent",
                limitations: "All indicators have limitations",
                strengthScore: 5
            )
        }
    }
}

// MARK: - Analysis Models

public struct StrategyAnalysis {
    public let strategyId: UUID
    public let strategyName: String
    public var entryAnalysis: [ConditionAnalysis] = []
    public var exitAnalysis: [ConditionAnalysis] = []
    public var riskAnalysis: RiskAnalysis = RiskAnalysis()
    public var sizingAnalysis: SizingAnalysis = SizingAnalysis()
    public var recommendations: [StrategyRecommendation] = []
    public var backtestInsights: [String] = []
    public var overallScore: Int = 0
}

public struct ConditionAnalysis {
    public let conditionId: UUID
    public var explanation: String = ""
    public var strengthScore: Int = 5
    public var suggestions: [String] = []
    public var warnings: [String] = []
}

public struct RiskAnalysis {
    public var stopLossRating: RiskRating = .missing
    public var stopLossSuggestion: String = ""
    public var takeProfitRating: RiskRating = .missing
    public var takeProfitSuggestion: String = ""
    public var drawdownSuggestion: String = ""
    
    public enum RiskRating {
        case missing, tight, wide, good, low, acceptable
    }
}

public struct SizingAnalysis {
    public var methodRating: SizingRating = .basic
    public var suggestion: String = ""
    public var maxPositionWarning: String = ""
    
    public enum SizingRating {
        case basic, conservative, risky, good, professional
    }
}

public struct StrategyRecommendation: Identifiable {
    public let id = UUID()
    public let type: RecommendationType
    public let title: String
    public let description: String
    public let action: String
    
    public enum RecommendationType {
        case critical, warning, improvement, suggestion
        
        public var color: Color {
            switch self {
            case .critical: return .red
            case .warning: return .orange
            case .improvement: return .blue
            case .suggestion: return .green
            }
        }
        
        public var icon: String {
            switch self {
            case .critical: return "exclamationmark.triangle.fill"
            case .warning: return "exclamationmark.circle.fill"
            case .improvement: return "arrow.up.circle.fill"
            case .suggestion: return "lightbulb.fill"
            }
        }
    }
}

public struct IndicatorInfo {
    public let name: String
    public let explanation: String
    public let bestUseCase: String
    public let limitations: String
    public let strengthScore: Int
}
