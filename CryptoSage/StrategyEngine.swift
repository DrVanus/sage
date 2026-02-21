//
//  StrategyEngine.swift
//  CryptoSage
//
//  Core engine for evaluating trading strategy conditions against
//  live market data using TechnicalsEngine for indicator calculations.
//

import Foundation
import Combine

// MARK: - Strategy Engine

/// Evaluates trading strategies against market data and generates signals
@MainActor
public final class StrategyEngine: ObservableObject {
    public static let shared = StrategyEngine()
    
    // MARK: - Published State
    
    @Published public var activeStrategies: [TradingStrategy] = []
    @Published public var recentSignals: [StrategySignal] = []
    @Published public var isEvaluating: Bool = false
    
    // MARK: - Storage
    
    private static let strategiesKey = "saved_strategies"
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Price Data Cache
    
    /// Cache of historical closes for indicator calculations
    private var priceHistoryCache: [String: [Double]] = [:]
    private var volumeHistoryCache: [String: [Double]] = [:]
    private var lastCacheUpdate: [String: Date] = [:]
    private let cacheDuration: TimeInterval = 60 // 1 minute cache
    
    // MARK: - Initialization
    
    private init() {
        loadStrategies()
    }
    
    // MARK: - Strategy Management
    
    /// Save a new or updated strategy
    public func saveStrategy(_ strategy: TradingStrategy) {
        var updated = strategy
        updated.lastModifiedAt = Date()
        
        if let index = activeStrategies.firstIndex(where: { $0.id == strategy.id }) {
            activeStrategies[index] = updated
        } else {
            activeStrategies.insert(updated, at: 0)
        }
        
        persistStrategies()
    }
    
    /// Delete a strategy
    public func deleteStrategy(id: UUID) {
        activeStrategies.removeAll { $0.id == id }
        persistStrategies()
    }
    
    /// Get a strategy by ID
    public func getStrategy(id: UUID) -> TradingStrategy? {
        activeStrategies.first { $0.id == id }
    }
    
    /// Toggle strategy enabled state
    public func toggleStrategy(id: UUID) {
        if let index = activeStrategies.firstIndex(where: { $0.id == id }) {
            activeStrategies[index].isEnabled.toggle()
            activeStrategies[index].lastModifiedAt = Date()
            persistStrategies()
        }
    }
    
    // MARK: - Core Evaluation
    
    /// Evaluate a strategy against current market conditions
    /// Returns a signal if entry/exit conditions are met
    public func evaluateStrategy(
        _ strategy: TradingStrategy,
        marketData: StrategyMarketData,
        priceHistory: [Double],
        volumeHistory: [Double]? = nil
    ) -> StrategySignal? {
        guard strategy.isEnabled else { return nil }
        guard !strategy.entryConditions.isEmpty || !strategy.exitConditions.isEmpty else { return nil }
        
        // Calculate all indicators for the strategy
        var indicatorValues = calculateIndicators(
            for: strategy,
            closes: priceHistory,
            volumes: volumeHistory ?? [],
            currentPrice: marketData.close
        )
        
        // Include price in indicator values
        indicatorValues[.price] = marketData.close
        
        // Calculate price change if we have history
        if priceHistory.count >= 2 {
            let previousClose = priceHistory[priceHistory.count - 2]
            if previousClose > 0 {
                indicatorValues[.priceChange] = ((marketData.close - previousClose) / previousClose) * 100
            }
        }
        
        // Calculate previous indicator values for crossover detection
        var previousIndicatorValues: [StrategyIndicatorType: Double] = [:]
        if priceHistory.count > 1 {
            let previousCloses = Array(priceHistory.dropLast())
            previousIndicatorValues = calculateIndicators(
                for: strategy,
                closes: previousCloses,
                volumes: Array(volumeHistory?.dropLast() ?? []),
                currentPrice: previousCloses.last ?? 0
            )
        }
        
        // Evaluate entry conditions
        let entryResult = evaluateConditions(
            strategy.entryConditions,
            logic: strategy.conditionLogic,
            currentValues: indicatorValues,
            previousValues: previousIndicatorValues
        )
        
        // Evaluate exit conditions
        let exitResult = evaluateConditions(
            strategy.exitConditions,
            logic: strategy.conditionLogic,
            currentValues: indicatorValues,
            previousValues: previousIndicatorValues
        )
        
        // Generate signal based on evaluation
        if exitResult.triggered {
            return StrategySignal(
                strategyId: strategy.id,
                type: .sell,
                price: marketData.close,
                confidence: exitResult.confidence,
                triggeredConditions: exitResult.triggeredConditions
            )
        } else if entryResult.triggered {
            return StrategySignal(
                strategyId: strategy.id,
                type: .buy,
                price: marketData.close,
                confidence: entryResult.confidence,
                triggeredConditions: entryResult.triggeredConditions
            )
        }
        
        return nil
    }
    
    /// Evaluate a single condition
    public func evaluateCondition(
        _ condition: StrategyCondition,
        currentValues: [StrategyIndicatorType: Double],
        previousValues: [StrategyIndicatorType: Double]
    ) -> Bool {
        guard condition.isEnabled else { return false }
        
        guard let indicatorValue = currentValues[condition.indicator] else {
            return false
        }
        
        let targetValue: Double
        switch condition.value {
        case .number(let num):
            targetValue = num
        case .percentage(let pct):
            targetValue = pct
        case .indicator(let ind):
            guard let indValue = currentValues[ind] else { return false }
            targetValue = indValue
        }
        
        switch condition.comparison {
        case .greaterThan:
            return indicatorValue > targetValue
        case .lessThan:
            return indicatorValue < targetValue
        case .greaterOrEqual:
            return indicatorValue >= targetValue
        case .lessOrEqual:
            return indicatorValue <= targetValue
        case .equals:
            return abs(indicatorValue - targetValue) < 0.0001
        case .crossesAbove:
            guard let prevValue = previousValues[condition.indicator] else { return false }
            return prevValue <= targetValue && indicatorValue > targetValue
        case .crossesBelow:
            guard let prevValue = previousValues[condition.indicator] else { return false }
            return prevValue >= targetValue && indicatorValue < targetValue
        }
    }
    
    // MARK: - Condition Evaluation
    
    private struct EvaluationResult {
        let triggered: Bool
        let confidence: Double
        let triggeredConditions: [String]
    }
    
    private func evaluateConditions(
        _ conditions: [StrategyCondition],
        logic: ConditionLogic,
        currentValues: [StrategyIndicatorType: Double],
        previousValues: [StrategyIndicatorType: Double]
    ) -> EvaluationResult {
        let enabledConditions = conditions.filter { $0.isEnabled }
        guard !enabledConditions.isEmpty else {
            return EvaluationResult(triggered: false, confidence: 0, triggeredConditions: [])
        }
        
        var triggeredConditions: [String] = []
        var passedCount = 0
        
        for condition in enabledConditions {
            let passed = evaluateCondition(condition, currentValues: currentValues, previousValues: previousValues)
            if passed {
                passedCount += 1
                triggeredConditions.append(condition.description)
            }
        }
        
        let confidence = Double(passedCount) / Double(enabledConditions.count)
        
        let triggered: Bool
        switch logic {
        case .all:
            triggered = passedCount == enabledConditions.count
        case .any:
            triggered = passedCount > 0
        case .custom:
            // For custom logic, require at least 50% of conditions
            triggered = confidence >= 0.5
        }
        
        return EvaluationResult(
            triggered: triggered,
            confidence: confidence,
            triggeredConditions: triggeredConditions
        )
    }
    
    // MARK: - Indicator Calculations
    
    /// Calculate all indicators needed for a strategy
    public func calculateIndicators(
        for strategy: TradingStrategy,
        closes: [Double],
        volumes: [Double],
        currentPrice: Double
    ) -> [StrategyIndicatorType: Double] {
        var values: [StrategyIndicatorType: Double] = [:]
        
        // Collect all indicators used in conditions
        var neededIndicators = Set<StrategyIndicatorType>()
        for condition in strategy.entryConditions + strategy.exitConditions {
            neededIndicators.insert(condition.indicator)
            if case .indicator(let ind) = condition.value {
                neededIndicators.insert(ind)
            }
        }
        
        // Calculate each needed indicator
        for indicator in neededIndicators {
            if let value = calculateIndicator(indicator, closes: closes, volumes: volumes, currentPrice: currentPrice) {
                values[indicator] = value
            }
        }
        
        return values
    }
    
    /// Calculate a single indicator value
    public func calculateIndicator(
        _ indicator: StrategyIndicatorType,
        closes: [Double],
        volumes: [Double],
        currentPrice: Double
    ) -> Double? {
        switch indicator {
        case .price:
            return currentPrice
            
        case .priceChange:
            guard closes.count >= 2 else { return nil }
            let prev = closes[closes.count - 2]
            guard prev > 0 else { return nil }
            return ((currentPrice - prev) / prev) * 100
            
        case .sma10:
            return TechnicalsEngine.sma(closes, period: 10)
            
        case .sma20:
            return TechnicalsEngine.sma(closes, period: 20)
            
        case .sma50:
            return TechnicalsEngine.sma(closes, period: 50)
            
        case .sma200:
            return TechnicalsEngine.sma(closes, period: 200)
            
        case .ema12:
            return TechnicalsEngine.ema(closes, period: 12)
            
        case .ema26:
            return TechnicalsEngine.ema(closes, period: 26)
            
        case .rsi:
            return TechnicalsEngine.rsi(closes)
            
        case .macdLine:
            return TechnicalsEngine.macdLineSignal(closes)?.macd
            
        case .macdSignal:
            return TechnicalsEngine.macdLineSignal(closes)?.signal
            
        case .macdHistogram:
            return TechnicalsEngine.macdHistogram(closes)
            
        case .stochK:
            return TechnicalsEngine.stochK(closes)
            
        case .stochD:
            return TechnicalsEngine.stochRSI(closes)?.d
            
        case .bollingerUpper:
            return TechnicalsEngine.bollingerBands(closes)?.upper
            
        case .bollingerMiddle:
            return TechnicalsEngine.bollingerBands(closes)?.middle
            
        case .bollingerLower:
            return TechnicalsEngine.bollingerBands(closes)?.lower
            
        case .atr:
            // Use ATR approximation from closes only
            return TechnicalsEngine.atrApproxFromCloses(closes)?.atr
            
        case .volume:
            return volumes.last
            
        case .volumeChange:
            guard volumes.count >= 2 else { return nil }
            let prev = volumes[volumes.count - 2]
            guard prev > 0, let current = volumes.last else { return nil }
            return ((current - prev) / prev) * 100
            
        case .obv:
            return TechnicalsEngine.obv(closes: closes, volumes: volumes)
            
        case .momentum:
            return TechnicalsEngine.momentum(closes)
            
        case .roc:
            return TechnicalsEngine.roc(closes)
            
        case .williamsR:
            return TechnicalsEngine.williamsR(closes)
            
        case .cci:
            return TechnicalsEngine.cci(closes)
            
        case .smaCrossover, .emaCrossover, .macdCrossover:
            // Crossovers are handled specially in condition evaluation
            return nil
        }
    }
    
    // MARK: - Position Sizing
    
    /// Calculate position size for a trade
    public func calculatePositionSize(
        for strategy: TradingStrategy,
        portfolioValue: Double,
        currentPrice: Double,
        stopLossPrice: Double? = nil
    ) -> Double {
        let sizing = strategy.positionSizing
        let risk = strategy.riskManagement
        
        var positionValue: Double
        
        switch sizing.method {
        case .fixedAmount:
            positionValue = sizing.fixedAmount
            
        case .percentOfPortfolio:
            positionValue = portfolioValue * (sizing.portfolioPercent / 100)
            
        case .riskBased:
            // Calculate based on stop loss and risk per trade
            let riskAmount = portfolioValue * (sizing.riskPercent / 100)
            
            if let stopLoss = stopLossPrice ?? (risk.stopLossPercent.map { currentPrice * (1 - $0 / 100) }) {
                let riskPerUnit = abs(currentPrice - stopLoss)
                if riskPerUnit > 0 {
                    let units = riskAmount / riskPerUnit
                    positionValue = units * currentPrice
                } else {
                    positionValue = sizing.fixedAmount // Fallback
                }
            } else {
                positionValue = sizing.fixedAmount // Fallback
            }
        }
        
        // Apply maximum position limit
        let maxPosition = portfolioValue * (sizing.maxPositionPercent / 100)
        positionValue = min(positionValue, maxPosition)
        
        // Convert to quantity
        return currentPrice > 0 ? positionValue / currentPrice : 0
    }
    
    // MARK: - Live Price Integration
    
    /// Update price history cache from MarketViewModel
    public func updatePriceCache(for symbol: String, closes: [Double], volumes: [Double]? = nil) {
        priceHistoryCache[symbol] = closes
        if let vols = volumes {
            volumeHistoryCache[symbol] = vols
        }
        lastCacheUpdate[symbol] = Date()
    }
    
    /// Get cached price history for a symbol
    public func getCachedPriceHistory(for symbol: String) -> [Double]? {
        // Check if cache is still valid
        if let lastUpdate = lastCacheUpdate[symbol] {
            if Date().timeIntervalSince(lastUpdate) < cacheDuration {
                return priceHistoryCache[symbol]
            }
        }
        return nil
    }
    
    /// Evaluate all active strategies against current market data
    public func evaluateAllStrategies(for symbol: String, currentPrice: Double) async -> [StrategySignal] {
        guard !isEvaluating else { return [] }
        
        isEvaluating = true
        defer { isEvaluating = false }
        
        var signals: [StrategySignal] = []
        
        // Get strategies for this symbol
        let relevantStrategies = activeStrategies.filter { 
            $0.tradingPair.contains(symbol.uppercased()) || $0.tradingPair == symbol
        }
        
        guard !relevantStrategies.isEmpty else { return [] }
        
        // Get price history (from cache or fetch)
        let priceHistory = getCachedPriceHistory(for: symbol) ?? [currentPrice]
        let volumeHistory = volumeHistoryCache[symbol]
        
        // Create market data snapshot
        let marketData = StrategyMarketData(
            symbol: symbol,
            timestamp: Date(),
            open: priceHistory.first ?? currentPrice,
            high: priceHistory.max() ?? currentPrice,
            low: priceHistory.min() ?? currentPrice,
            close: currentPrice,
            volume: volumeHistory?.last ?? 0
        )
        
        // Evaluate each strategy
        for strategy in relevantStrategies {
            if let signal = evaluateStrategy(
                strategy,
                marketData: marketData,
                priceHistory: priceHistory,
                volumeHistory: volumeHistory
            ) {
                signals.append(signal)
                recentSignals.insert(signal, at: 0)
                
                // Keep only last 100 signals
                if recentSignals.count > 100 {
                    recentSignals = Array(recentSignals.prefix(100))
                }
            }
        }
        
        return signals
    }
    
    // MARK: - Persistence
    
    private func persistStrategies() {
        do {
            let data = try JSONEncoder().encode(activeStrategies)
            UserDefaults.standard.set(data, forKey: Self.strategiesKey)
        } catch {
            print("[StrategyEngine] Failed to save strategies: \(error)")
        }
    }
    
    private func loadStrategies() {
        guard let data = UserDefaults.standard.data(forKey: Self.strategiesKey) else { return }
        
        do {
            activeStrategies = try JSONDecoder().decode([TradingStrategy].self, from: data)
        } catch {
            print("[StrategyEngine] Failed to load strategies: \(error)")
        }
    }
    
    /// Clear all strategies
    public func clearAllStrategies() {
        activeStrategies.removeAll()
        recentSignals.removeAll()
        persistStrategies()
    }
}

// MARK: - Strategy Validation

extension StrategyEngine {
    /// Validate a strategy configuration
    public func validateStrategy(_ strategy: TradingStrategy) -> [String] {
        var errors: [String] = []
        
        if strategy.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Strategy name is required")
        }
        
        if strategy.entryConditions.isEmpty {
            errors.append("At least one entry condition is required")
        }
        
        // Validate risk management
        if let sl = strategy.riskManagement.stopLossPercent, sl <= 0 {
            errors.append("Stop loss must be greater than 0%")
        }
        
        if let sl = strategy.riskManagement.stopLossPercent,
           let tp = strategy.riskManagement.takeProfitPercent,
           tp <= sl {
            errors.append("Take profit should be greater than stop loss")
        }
        
        // Validate position sizing
        if strategy.positionSizing.fixedAmount <= 0 {
            errors.append("Position size must be greater than 0")
        }
        
        if strategy.positionSizing.maxPositionPercent > 100 {
            errors.append("Maximum position cannot exceed 100% of portfolio")
        }
        
        return errors
    }
    
    /// Check if a strategy has valid conditions for evaluation
    public func canEvaluate(_ strategy: TradingStrategy) -> Bool {
        guard strategy.isEnabled else { return false }
        guard !strategy.entryConditions.isEmpty else { return false }
        guard strategy.entryConditions.contains(where: { $0.isEnabled }) else { return false }
        return true
    }
}

// MARK: - Signal Formatting & Export

extension StrategySignal {
    /// Formatted description for display
    public var formattedDescription: String {
        let conditionsText = triggeredConditions.isEmpty 
            ? "Strategy conditions met" 
            : triggeredConditions.joined(separator: ", ")
        return "\(type.rawValue): \(conditionsText)"
    }
    
    /// Confidence level as text
    public var confidenceLevel: String {
        if confidence >= 0.8 { return "High" }
        if confidence >= 0.5 { return "Medium" }
        return "Low"
    }
    
    /// Generate shareable signal text for users to use as advisory
    /// This allows users to copy the signal details for their own trading decisions
    public func generateShareableText(strategyName: String? = nil, pair: String? = nil) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        
        var text = """
        📊 CryptoSage Strategy Signal
        ━━━━━━━━━━━━━━━━━━━━━━━━
        
        """
        
        if let name = strategyName {
            text += "Strategy: \(name)\n"
        }
        
        if let tradingPair = pair {
            text += "Pair: \(tradingPair)\n"
        }
        
        text += """
        Signal: \(type.rawValue)
        Time: \(dateFormatter.string(from: timestamp))
        Price: $\(String(format: "%.2f", price))
        Confidence: \(confidenceLevel) (\(Int(confidence * 100))%)
        
        """
        
        if !triggeredConditions.isEmpty {
            text += "Triggered Conditions:\n"
            for condition in triggeredConditions {
                text += "• \(condition)\n"
            }
        }
        
        text += """
        
        ━━━━━━━━━━━━━━━━━━━━━━━━
        ⚠️ Advisory Only - Not financial advice.
        Generated by CryptoSage AI
        """
        
        return text
    }
    
    /// Generate a compact one-line signal summary
    public var compactSummary: String {
        let emoji = type == .buy ? "🟢" : (type == .sell ? "🔴" : "⚪️")
        return "\(emoji) \(type.rawValue) @ $\(String(format: "%.2f", price)) (\(confidenceLevel) confidence)"
    }
}

// MARK: - Strategy Export

extension TradingStrategy {
    /// Generate a shareable strategy summary
    public func generateShareableText() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, yyyy"
        
        var text = """
        📈 CryptoSage Strategy
        ━━━━━━━━━━━━━━━━━━━━━━━━
        
        Name: \(name)
        Pair: \(tradingPair)
        Timeframe: \(timeframe.displayName)
        Logic: \(conditionLogic.displayName)
        
        """
        
        if !entryConditions.isEmpty {
            text += "📥 Entry Conditions:\n"
            for condition in entryConditions where condition.isEnabled {
                text += "• \(condition.description)\n"
            }
            text += "\n"
        }
        
        if !exitConditions.isEmpty {
            text += "📤 Exit Conditions:\n"
            for condition in exitConditions where condition.isEnabled {
                text += "• \(condition.description)\n"
            }
            text += "\n"
        }
        
        // Risk Management
        text += "🛡️ Risk Management:\n"
        if let sl = riskManagement.stopLossPercent {
            text += "• Stop Loss: \(String(format: "%.1f", sl))%\n"
        }
        if let tp = riskManagement.takeProfitPercent {
            text += "• Take Profit: \(String(format: "%.1f", tp))%\n"
        }
        if let ts = riskManagement.trailingStopPercent {
            text += "• Trailing Stop: \(String(format: "%.1f", ts))%\n"
        }
        if let rr = riskManagement.riskRewardRatio {
            text += "• Risk/Reward: 1:\(String(format: "%.1f", rr))\n"
        }
        
        text += """
        
        ━━━━━━━━━━━━━━━━━━━━━━━━
        ⚠️ Educational/Advisory Only
        Not financial advice. Always DYOR.
        Created with CryptoSage AI
        """
        
        return text
    }
    
    /// Generate a JSON export of the strategy for backup/import
    public func exportAsJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        guard let data = try? encoder.encode(self),
              let jsonString = String(data: data, encoding: .utf8) else {
            return nil
        }
        return jsonString
    }
}
