//
//  BacktestEngine.swift
//  CryptoSage
//
//  Backtest engine for simulating trading strategy performance
//  against historical price data with detailed metrics and reporting.
//

import Foundation
import Combine

// MARK: - Backtest Engine

@MainActor
public final class BacktestEngine: ObservableObject {
    public static let shared = BacktestEngine()
    
    // MARK: - Published State
    
    @Published public var isRunning: Bool = false
    @Published public var progress: Double = 0
    @Published public var currentBacktest: BacktestResult?
    @Published public var backtestHistory: [BacktestResult] = []
    
    // MARK: - Configuration
    
    private let defaultInitialBalance: Double = 10000
    private let tradingFeePercent: Double = 0.1 // 0.1% fee per trade
    private let slippagePercent: Double = 0.05 // 0.05% slippage
    
    private init() {
        loadHistory()
    }
    
    // MARK: - Backtest Execution
    
    /// Run a backtest on a strategy with historical data
    public func runBacktest(
        strategy: TradingStrategy,
        priceHistory: [OHLCV],
        initialBalance: Double? = nil
    ) async -> BacktestResult {
        guard !priceHistory.isEmpty else {
            return BacktestResult.empty(strategyId: strategy.id)
        }
        
        isRunning = true
        progress = 0
        
        let balance = initialBalance ?? defaultInitialBalance
        var result = BacktestResult(
            id: UUID(),
            strategyId: strategy.id,
            strategyName: strategy.name,
            tradingPair: strategy.tradingPair,
            startDate: priceHistory.first?.date ?? Date(),
            endDate: priceHistory.last?.date ?? Date(),
            initialBalance: balance
        )
        
        // Initialize tracking variables
        var currentBalance = balance
        var currentPosition: Position? = nil
        var equityCurve: [EquityPoint] = []
        var trades: [BacktestTrade] = []
        var consecutiveLosses = 0
        var maxConsecutiveLosses = 0
        var peakBalance = balance
        var maxDrawdown = 0.0
        
        // Need enough history for indicator calculation
        let warmupPeriod = 50
        guard priceHistory.count > warmupPeriod else {
            isRunning = false
            return result
        }
        
        // Run through each candle
        let totalCandles = priceHistory.count - warmupPeriod
        
        for i in warmupPeriod..<priceHistory.count {
            // Update progress
            progress = Double(i - warmupPeriod) / Double(totalCandles)
            
            let currentCandle = priceHistory[i]
            let historicalCloses = Array(priceHistory[0...i].map { $0.close })
            let historicalVolumes = Array(priceHistory[0...i].map { $0.volume })
            
            // Create market data for this point
            let marketData = StrategyMarketData(
                symbol: strategy.tradingPair,
                timestamp: currentCandle.date,
                open: currentCandle.open,
                high: currentCandle.high,
                low: currentCandle.low,
                close: currentCandle.close,
                volume: currentCandle.volume
            )
            
            // Check stop loss / take profit if in position
            if let position = currentPosition {
                let exitResult = checkExitConditions(
                    position: position,
                    currentPrice: currentCandle.close,
                    highPrice: currentCandle.high,
                    lowPrice: currentCandle.low,
                    strategy: strategy
                )
                
                if let exitPrice = exitResult.exitPrice {
                    // Close position
                    let trade = closePosition(
                        position: position,
                        exitPrice: exitPrice,
                        exitDate: currentCandle.date,
                        exitReason: exitResult.reason
                    )
                    trades.append(trade)
                    currentBalance += trade.profitLoss
                    currentPosition = nil
                    
                    // Track consecutive losses
                    if trade.profitLoss < 0 {
                        consecutiveLosses += 1
                        maxConsecutiveLosses = max(maxConsecutiveLosses, consecutiveLosses)
                    } else {
                        consecutiveLosses = 0
                    }
                    
                    // Check max drawdown
                    if currentBalance > peakBalance {
                        peakBalance = currentBalance
                    }
                    let drawdown = (peakBalance - currentBalance) / peakBalance * 100
                    maxDrawdown = max(maxDrawdown, drawdown)
                }
            }
            
            // Evaluate strategy for new signals
            if currentPosition == nil {
                let signal = StrategyEngine.shared.evaluateStrategy(
                    strategy,
                    marketData: marketData,
                    priceHistory: historicalCloses,
                    volumeHistory: historicalVolumes
                )
                
                if let signal = signal, signal.type == .buy {
                    // Open new position
                    let positionSize = calculatePositionSize(
                        strategy: strategy,
                        balance: currentBalance,
                        price: currentCandle.close
                    )
                    
                    let entryPrice = applySlippage(currentCandle.close, isBuy: true)
                    let fee = positionSize * entryPrice * (tradingFeePercent / 100)
                    
                    currentPosition = Position(
                        entryPrice: entryPrice,
                        quantity: positionSize,
                        entryDate: currentCandle.date,
                        entryFee: fee
                    )
                    
                    currentBalance -= fee
                }
            }
            
            // Calculate current equity
            let positionValue = currentPosition.map { $0.quantity * currentCandle.close } ?? 0
            let equity = currentBalance + positionValue
            
            equityCurve.append(EquityPoint(
                date: currentCandle.date,
                equity: equity,
                balance: currentBalance,
                positionValue: positionValue
            ))
            
            // Small delay for UI responsiveness
            if i % 100 == 0 {
                try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
            }
        }
        
        // Close any remaining position at end
        if let position = currentPosition {
            let finalPrice = priceHistory.last?.close ?? 0
            let trade = closePosition(
                position: position,
                exitPrice: finalPrice,
                exitDate: priceHistory.last?.date ?? Date(),
                exitReason: "Backtest End"
            )
            trades.append(trade)
            currentBalance += trade.profitLoss
        }
        
        // Calculate final metrics
        result.finalBalance = currentBalance
        result.trades = trades
        result.equityCurve = equityCurve
        result.maxDrawdownPercent = maxDrawdown
        result.maxConsecutiveLosses = maxConsecutiveLosses
        
        // Calculate summary metrics
        result.calculateMetrics()
        
        // Save to history
        currentBacktest = result
        backtestHistory.insert(result, at: 0)
        if backtestHistory.count > 50 {
            backtestHistory = Array(backtestHistory.prefix(50))
        }
        saveHistory()
        
        isRunning = false
        progress = 1.0
        
        return result
    }
    
    // MARK: - Position Management
    
    private struct Position {
        let entryPrice: Double
        let quantity: Double
        let entryDate: Date
        let entryFee: Double
    }
    
    private func calculatePositionSize(
        strategy: TradingStrategy,
        balance: Double,
        price: Double
    ) -> Double {
        let sizing = strategy.positionSizing
        
        var positionValue: Double
        
        switch sizing.method {
        case .fixedAmount:
            positionValue = min(sizing.fixedAmount, balance * 0.95)
        case .percentOfPortfolio:
            positionValue = balance * (sizing.portfolioPercent / 100)
        case .riskBased:
            let riskAmount = balance * (sizing.riskPercent / 100)
            if let stopLoss = strategy.riskManagement.stopLossPercent {
                let riskPerUnit = price * (stopLoss / 100)
                positionValue = (riskAmount / riskPerUnit) * price
            } else {
                positionValue = sizing.fixedAmount
            }
        }
        
        // Apply max position limit
        let maxPosition = balance * (sizing.maxPositionPercent / 100)
        positionValue = min(positionValue, maxPosition, balance * 0.95)
        
        return positionValue / price
    }
    
    private func applySlippage(_ price: Double, isBuy: Bool) -> Double {
        let slippageFactor = slippagePercent / 100
        return isBuy ? price * (1 + slippageFactor) : price * (1 - slippageFactor)
    }
    
    private struct ExitResult {
        let exitPrice: Double?
        let reason: String
    }
    
    private func checkExitConditions(
        position: Position,
        currentPrice: Double,
        highPrice: Double,
        lowPrice: Double,
        strategy: TradingStrategy
    ) -> ExitResult {
        let risk = strategy.riskManagement
        
        // Check stop loss
        if let stopLossPercent = risk.stopLossPercent {
            let stopLossPrice = position.entryPrice * (1 - stopLossPercent / 100)
            if lowPrice <= stopLossPrice {
                return ExitResult(exitPrice: stopLossPrice, reason: "Stop Loss")
            }
        }
        
        // Check take profit
        if let takeProfitPercent = risk.takeProfitPercent {
            let takeProfitPrice = position.entryPrice * (1 + takeProfitPercent / 100)
            if highPrice >= takeProfitPrice {
                return ExitResult(exitPrice: takeProfitPrice, reason: "Take Profit")
            }
        }
        
        return ExitResult(exitPrice: nil, reason: "")
    }
    
    private func closePosition(
        position: Position,
        exitPrice: Double,
        exitDate: Date,
        exitReason: String
    ) -> BacktestTrade {
        let adjustedExitPrice = applySlippage(exitPrice, isBuy: false)
        let exitFee = position.quantity * adjustedExitPrice * (tradingFeePercent / 100)
        
        let grossPnL = (adjustedExitPrice - position.entryPrice) * position.quantity
        let netPnL = grossPnL - position.entryFee - exitFee
        let returnPercent = (netPnL / (position.entryPrice * position.quantity)) * 100
        
        return BacktestTrade(
            id: UUID(),
            entryDate: position.entryDate,
            exitDate: exitDate,
            entryPrice: position.entryPrice,
            exitPrice: adjustedExitPrice,
            quantity: position.quantity,
            side: .buy,
            profitLoss: netPnL,
            returnPercent: returnPercent,
            exitReason: exitReason,
            fees: position.entryFee + exitFee
        )
    }
    
    // MARK: - Persistence
    
    private static let historyKey = "backtest_history"
    
    private func saveHistory() {
        do {
            let data = try JSONEncoder().encode(backtestHistory)
            UserDefaults.standard.set(data, forKey: Self.historyKey)
        } catch {
            #if DEBUG
            print("[BacktestEngine] Failed to save history: \(error)")
            #endif
        }
    }
    
    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: Self.historyKey) else { return }
        do {
            backtestHistory = try JSONDecoder().decode([BacktestResult].self, from: data)
        } catch {
            #if DEBUG
            print("[BacktestEngine] Failed to load history: \(error)")
            #endif
        }
    }
    
    /// Clear backtest history
    public func clearHistory() {
        backtestHistory.removeAll()
        currentBacktest = nil
        saveHistory()
    }
}

// MARK: - OHLCV Data

/// Candlestick data for backtesting
public struct OHLCV: Codable {
    public let date: Date
    public let open: Double
    public let high: Double
    public let low: Double
    public let close: Double
    public let volume: Double
    
    public init(date: Date, open: Double, high: Double, low: Double, close: Double, volume: Double) {
        self.date = date
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.volume = volume
    }
}

// MARK: - Backtest Result

public struct BacktestResult: Codable, Identifiable {
    public let id: UUID
    public let strategyId: UUID
    public let strategyName: String
    public let tradingPair: String
    public let startDate: Date
    public let endDate: Date
    public let initialBalance: Double
    
    // Results (populated after backtest)
    public var finalBalance: Double = 0
    public var trades: [BacktestTrade] = []
    public var equityCurve: [EquityPoint] = []
    public var maxDrawdownPercent: Double = 0
    public var maxConsecutiveLosses: Int = 0
    
    // Calculated metrics
    public var totalTrades: Int = 0
    public var winningTrades: Int = 0
    public var losingTrades: Int = 0
    public var winRate: Double = 0
    public var totalReturnPercent: Double = 0
    public var annualizedReturn: Double = 0
    public var sharpeRatio: Double = 0
    public var sortinoRatio: Double = 0
    public var profitFactor: Double = 0
    public var averageWin: Double = 0
    public var averageLoss: Double = 0
    public var largestWin: Double = 0
    public var largestLoss: Double = 0
    public var averageHoldingDays: Double = 0
    
    public init(
        id: UUID = UUID(),
        strategyId: UUID,
        strategyName: String,
        tradingPair: String,
        startDate: Date,
        endDate: Date,
        initialBalance: Double
    ) {
        self.id = id
        self.strategyId = strategyId
        self.strategyName = strategyName
        self.tradingPair = tradingPair
        self.startDate = startDate
        self.endDate = endDate
        self.initialBalance = initialBalance
    }
    
    /// Calculate all metrics from trades
    public mutating func calculateMetrics() {
        totalTrades = trades.count
        
        let winners = trades.filter { $0.profitLoss > 0 }
        let losers = trades.filter { $0.profitLoss <= 0 }
        
        winningTrades = winners.count
        losingTrades = losers.count
        
        winRate = totalTrades > 0 ? Double(winningTrades) / Double(totalTrades) * 100 : 0
        
        // Total return
        totalReturnPercent = initialBalance > 0 ? ((finalBalance - initialBalance) / initialBalance) * 100 : 0
        
        // Annualized return
        let days = max(1, Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 1)
        let years = Double(days) / 365.0
        if years > 0 && finalBalance > 0 && initialBalance > 0 {
            annualizedReturn = (pow(finalBalance / initialBalance, 1 / years) - 1) * 100
        }
        
        // Profit factor
        let totalWins = winners.reduce(0) { $0 + $1.profitLoss }
        let totalLosses = abs(losers.reduce(0) { $0 + $1.profitLoss })
        profitFactor = totalLosses > 0 ? totalWins / totalLosses : (totalWins > 0 ? Double.infinity : 0)
        
        // Average win/loss
        averageWin = winningTrades > 0 ? totalWins / Double(winningTrades) : 0
        averageLoss = losingTrades > 0 ? totalLosses / Double(losingTrades) : 0
        
        // Largest win/loss
        largestWin = winners.max(by: { $0.profitLoss < $1.profitLoss })?.profitLoss ?? 0
        largestLoss = losers.min(by: { $0.profitLoss < $1.profitLoss })?.profitLoss ?? 0
        
        // Average holding period
        if totalTrades > 0 {
            let totalHoldingSeconds = trades.reduce(0.0) { 
                $0 + $1.exitDate.timeIntervalSince($1.entryDate) 
            }
            averageHoldingDays = (totalHoldingSeconds / Double(totalTrades)) / 86400
        }
        
        // Sharpe ratio (simplified - using daily returns)
        calculateRiskAdjustedMetrics()
    }
    
    private mutating func calculateRiskAdjustedMetrics() {
        guard equityCurve.count > 1 else { return }
        
        // Calculate daily returns
        var dailyReturns: [Double] = []
        for i in 1..<equityCurve.count {
            let prevEquity = equityCurve[i-1].equity
            let currEquity = equityCurve[i].equity
            if prevEquity > 0 {
                dailyReturns.append((currEquity - prevEquity) / prevEquity)
            }
        }
        
        guard dailyReturns.count > 1 else { return }
        
        let avgReturn = dailyReturns.reduce(0, +) / Double(dailyReturns.count)
        let variance = dailyReturns.reduce(0) { $0 + pow($1 - avgReturn, 2) } / Double(dailyReturns.count)
        let stdDev = sqrt(variance)
        
        // Sharpe ratio (annualized, assuming 252 trading days, 0% risk-free rate)
        if stdDev > 0 {
            sharpeRatio = (avgReturn * 252) / (stdDev * sqrt(252))
        }
        
        // Sortino ratio (only negative volatility)
        let negativeReturns = dailyReturns.filter { $0 < 0 }
        if negativeReturns.count > 0 {
            let downVariance = negativeReturns.reduce(0) { $0 + pow($1, 2) } / Double(negativeReturns.count)
            let downDev = sqrt(downVariance)
            if downDev > 0 {
                sortinoRatio = (avgReturn * 252) / (downDev * sqrt(252))
            }
        }
    }
    
    /// Performance grade based on metrics
    public var performanceGrade: String {
        var score = 0.0
        
        if winRate >= 60 { score += 25 }
        else if winRate >= 50 { score += 15 }
        else if winRate >= 40 { score += 8 }
        
        if profitFactor >= 2.0 { score += 25 }
        else if profitFactor >= 1.5 { score += 18 }
        else if profitFactor >= 1.2 { score += 10 }
        
        if sharpeRatio >= 2.0 { score += 25 }
        else if sharpeRatio >= 1.0 { score += 15 }
        else if sharpeRatio >= 0.5 { score += 8 }
        
        if maxDrawdownPercent <= 10 { score += 25 }
        else if maxDrawdownPercent <= 20 { score += 15 }
        else if maxDrawdownPercent <= 30 { score += 8 }
        
        if score >= 85 { return "A" }
        if score >= 70 { return "B" }
        if score >= 55 { return "C" }
        if score >= 40 { return "D" }
        return "F"
    }
    
    /// Net profit/loss
    public var netProfitLoss: Double {
        finalBalance - initialBalance
    }
    
    /// Create empty result for invalid backtests
    public static func empty(strategyId: UUID) -> BacktestResult {
        BacktestResult(
            strategyId: strategyId,
            strategyName: "Unknown",
            tradingPair: "N/A",
            startDate: Date(),
            endDate: Date(),
            initialBalance: 0
        )
    }
}

// MARK: - Backtest Trade

public struct BacktestTrade: Codable, Identifiable {
    public let id: UUID
    public let entryDate: Date
    public let exitDate: Date
    public let entryPrice: Double
    public let exitPrice: Double
    public let quantity: Double
    public let side: TradeSide
    public let profitLoss: Double
    public let returnPercent: Double
    public let exitReason: String
    public let fees: Double
    
    public var isWinner: Bool {
        profitLoss > 0
    }
    
    public var holdingPeriod: TimeInterval {
        exitDate.timeIntervalSince(entryDate)
    }
    
    public var holdingDays: Double {
        holdingPeriod / 86400
    }
}

// MARK: - Equity Point

public struct EquityPoint: Codable {
    public let date: Date
    public let equity: Double
    public let balance: Double
    public let positionValue: Double
}

// Note: TradeSide is defined in TradingTypes.swift
