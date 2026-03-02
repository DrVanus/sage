//
//  SageBacktestRunner.swift
//  CryptoSage
//
//  Backtesting infrastructure for validating CryptoSage AI algorithms.
//  Runs algorithms against historical data to validate performance criteria.
//
//  Validation Criteria (all must pass before algorithm goes user-facing):
//  - Minimum 2 years backtest on BTC, ETH, SOL
//  - Sharpe Ratio > 1.0
//  - Max Drawdown < 25%
//  - Win Rate > 45%
//  - Profit Factor > 1.5
//

import Foundation
import Combine

// MARK: - Sage Backtest Runner

/// Runs backtests on CryptoSage AI algorithms
@MainActor
public final class SageBacktestRunner: ObservableObject {
    public static let shared = SageBacktestRunner()
    
    // MARK: - Published State
    
    @Published public var isRunning: Bool = false
    @Published public var progress: Double = 0
    @Published public var currentAlgorithm: String = ""
    @Published public var currentSymbol: String = ""
    @Published public var results: [SageBacktestResult] = []
    
    // MARK: - Configuration
    
    /// Validation criteria that algorithms must pass
    public let validationCriteria = SageValidationCriteria(
        minimumSharpeRatio: 1.0,
        maximumDrawdownPercent: 25.0,
        minimumWinRate: 45.0,
        minimumProfitFactor: 1.5,
        minimumTrades: 20,
        minimumDataDays: 365 * 2  // 2 years
    )
    
    /// Symbols to test
    public let testSymbols = ["BTC", "ETH", "SOL"]
    
    /// Primary timeframe for testing
    public let testTimeframe: SageTimeframe = .h4
    
    // MARK: - Private
    
    private var cancellables = Set<AnyCancellable>()
    private let backtestEngine = BacktestEngine.shared
    
    private init() {
        loadResults()
    }
    
    // MARK: - Run Backtest
    
    /// Run backtest on all Sage algorithms
    public func runFullBacktest() async -> [SageBacktestResult] {
        guard !isRunning else { return results }
        
        isRunning = true
        progress = 0
        results = []
        
        let algorithms = SageAlgorithmEngine.shared.algorithms
        let totalTests = algorithms.count * testSymbols.count
        var completedTests = 0
        
        for algorithm in algorithms {
            currentAlgorithm = algorithm.name
            
            for symbol in testSymbols {
                currentSymbol = symbol
                
                do {
                    // Fetch historical data
                    let data = try await fetchHistoricalData(symbol: symbol, days: validationCriteria.minimumDataDays)
                    
                    // Run backtest
                    let result = await runAlgorithmBacktest(
                        algorithm: algorithm,
                        symbol: symbol,
                        data: data
                    )
                    
                    results.append(result)
                    
                } catch {
                    #if DEBUG
                    print("[SageBacktestRunner] Failed to backtest \(algorithm.name) on \(symbol): \(error)")
                    #endif
                    
                    // Add failed result
                    let failedResult = SageBacktestResult(
                        algorithmId: algorithm.id,
                        algorithmName: algorithm.name,
                        symbol: symbol,
                        timeframe: testTimeframe,
                        startDate: Date(),
                        endDate: Date(),
                        errorMessage: error.localizedDescription
                    )
                    results.append(failedResult)
                }
                
                completedTests += 1
                progress = Double(completedTests) / Double(totalTests)
            }
        }
        
        isRunning = false
        progress = 1.0
        
        saveResults()
        
        return results
    }
    
    /// Run backtest on a single algorithm
    public func runSingleBacktest(
        algorithmId: String,
        symbol: String,
        days: Int = 730
    ) async -> SageBacktestResult? {
        guard let algorithm = SageAlgorithmEngine.shared.algorithms.first(where: { $0.id == algorithmId }) else {
            return nil
        }
        
        isRunning = true
        currentAlgorithm = algorithm.name
        currentSymbol = symbol
        
        defer { isRunning = false }
        
        do {
            let data = try await fetchHistoricalData(symbol: symbol, days: days)
            let result = await runAlgorithmBacktest(algorithm: algorithm, symbol: symbol, data: data)
            
            // Update results
            if let index = results.firstIndex(where: { $0.algorithmId == algorithmId && $0.symbol == symbol }) {
                results[index] = result
            } else {
                results.append(result)
            }
            
            saveResults()
            return result
            
        } catch {
            #if DEBUG
            print("[SageBacktestRunner] Backtest failed: \(error)")
            #endif
            return nil
        }
    }
    
    // MARK: - Algorithm Backtest
    
    private func runAlgorithmBacktest(
        algorithm: any SageAlgorithm,
        symbol: String,
        data: [OHLCV]
    ) async -> SageBacktestResult {
        
        let startDate = data.first?.date ?? Date()
        let endDate = data.last?.date ?? Date()
        
        var result = SageBacktestResult(
            algorithmId: algorithm.id,
            algorithmName: algorithm.name,
            symbol: symbol,
            timeframe: testTimeframe,
            startDate: startDate,
            endDate: endDate
        )
        
        // Initial capital
        let initialCapital: Double = 10000
        var capital = initialCapital
        var position: BacktestPosition? = nil
        var trades: [SageBacktestTrade] = []
        var equityCurve: [Double] = [initialCapital]
        var peakEquity = initialCapital
        var maxDrawdown: Double = 0
        
        // Warmup period for indicators
        let warmupPeriod = max(algorithm.minDataPoints, 200)
        guard data.count > warmupPeriod else {
            result.errorMessage = "Insufficient data: need \(warmupPeriod) candles, have \(data.count)"
            return result
        }
        
        // Run through each candle
        for i in warmupPeriod..<data.count {
            let candle = data[i]
            let closes = data[0...i].map { $0.close }
            let volumes = data[0...i].map { $0.volume }
            
            // Build market data
            let marketData = SageMarketData(
                symbol: symbol,
                currentPrice: candle.close,
                closes: Array(closes),
                highs: data[0...i].map { $0.high },
                lows: data[0...i].map { $0.low },
                volumes: Array(volumes),
                timeframe: testTimeframe
            )
            
            // Detect regime
            let regime = SageAlgorithmEngine.shared.detectRegime(closes: Array(closes), volumes: Array(volumes))
            
            // Evaluate algorithm
            if let signal = algorithm.evaluate(data: marketData, regime: regime) {
                
                // Process signal
                if position == nil {
                    // No position - check for entry
                    if signal.type == .strongBuy || signal.type == .buy {
                        // Enter long
                        let positionSize = capital * (regime.positionSizeMultiplier * 0.5)  // Conservative sizing
                        let quantity = positionSize / candle.close
                        
                        position = BacktestPosition(
                            entryPrice: candle.close,
                            quantity: quantity,
                            entryDate: candle.date,
                            stopLoss: signal.suggestedStopLoss,
                            takeProfit: signal.suggestedTakeProfit,
                            regime: regime
                        )
                    }
                } else if let pos = position {
                    // Have position - check for exit
                    var shouldExit = false
                    var exitReason = ""
                    
                    // Check stop loss
                    if let stopLoss = pos.stopLoss, candle.low <= stopLoss {
                        shouldExit = true
                        exitReason = "Stop Loss"
                    }
                    
                    // Check take profit
                    if let takeProfit = pos.takeProfit, candle.high >= takeProfit {
                        shouldExit = true
                        exitReason = "Take Profit"
                    }
                    
                    // Check signal reversal
                    if signal.type == .sell || signal.type == .strongSell {
                        shouldExit = true
                        exitReason = "Signal Reversal"
                    }
                    
                    if shouldExit {
                        // Exit position
                        let exitPrice = candle.close
                        let pnl = (exitPrice - pos.entryPrice) * pos.quantity
                        let pnlPercent = ((exitPrice - pos.entryPrice) / pos.entryPrice) * 100
                        
                        capital += pnl
                        
                        let trade = SageBacktestTrade(
                            entryDate: pos.entryDate,
                            exitDate: candle.date,
                            entryPrice: pos.entryPrice,
                            exitPrice: exitPrice,
                            quantity: pos.quantity,
                            pnl: pnl,
                            pnlPercent: pnlPercent,
                            exitReason: exitReason
                        )
                        trades.append(trade)
                        
                        position = nil
                    }
                }
            }
            
            // Update equity curve
            let currentEquity = capital + (position.map { $0.quantity * candle.close } ?? 0)
            equityCurve.append(currentEquity)
            
            // Track drawdown
            if currentEquity > peakEquity {
                peakEquity = currentEquity
            }
            let drawdown = (peakEquity - currentEquity) / peakEquity * 100
            maxDrawdown = max(maxDrawdown, drawdown)
        }
        
        // Close any remaining position
        if let pos = position, let lastCandle = data.last {
            let pnl = (lastCandle.close - pos.entryPrice) * pos.quantity
            let pnlPercent = ((lastCandle.close - pos.entryPrice) / pos.entryPrice) * 100
            capital += pnl
            
            let trade = SageBacktestTrade(
                entryDate: pos.entryDate,
                exitDate: lastCandle.date,
                entryPrice: pos.entryPrice,
                exitPrice: lastCandle.close,
                quantity: pos.quantity,
                pnl: pnl,
                pnlPercent: pnlPercent,
                exitReason: "Backtest End"
            )
            trades.append(trade)
        }
        
        // Calculate metrics
        result.totalTrades = trades.count
        result.winningTrades = trades.filter { $0.pnl > 0 }.count
        result.losingTrades = trades.filter { $0.pnl <= 0 }.count
        result.winRate = result.totalTrades > 0 ? Double(result.winningTrades) / Double(result.totalTrades) * 100 : 0
        
        result.totalReturnPercent = ((capital - initialCapital) / initialCapital) * 100
        result.maxDrawdownPercent = maxDrawdown
        
        // Profit factor
        let grossProfit = trades.filter { $0.pnl > 0 }.reduce(0) { $0 + $1.pnl }
        let grossLoss = abs(trades.filter { $0.pnl < 0 }.reduce(0) { $0 + $1.pnl })
        result.profitFactor = grossLoss > 0 ? grossProfit / grossLoss : (grossProfit > 0 ? Double.infinity : 0)
        
        // Sharpe ratio (simplified)
        result.sharpeRatio = calculateSharpeRatio(equityCurve: equityCurve)
        
        // Validation
        result.passesValidation = validateResult(result)
        
        return result
    }
    
    // MARK: - Metrics Calculation
    
    private func calculateSharpeRatio(equityCurve: [Double]) -> Double {
        guard equityCurve.count > 1 else { return 0 }
        
        var returns: [Double] = []
        for i in 1..<equityCurve.count {
            let ret = (equityCurve[i] - equityCurve[i-1]) / equityCurve[i-1]
            returns.append(ret)
        }
        
        let avgReturn = returns.reduce(0, +) / Double(returns.count)
        let variance = returns.reduce(0) { $0 + pow($1 - avgReturn, 2) } / Double(returns.count)
        let stdDev = sqrt(variance)
        
        guard stdDev > 0 else { return 0 }
        
        // Annualized (assuming 4H candles, ~6 per day, ~2190 per year)
        let annualizedReturn = avgReturn * 2190
        let annualizedStdDev = stdDev * sqrt(2190)
        
        return annualizedReturn / annualizedStdDev
    }
    
    private func validateResult(_ result: SageBacktestResult) -> Bool {
        guard result.errorMessage == nil else { return false }
        guard result.totalTrades >= validationCriteria.minimumTrades else { return false }
        
        return result.sharpeRatio >= validationCriteria.minimumSharpeRatio &&
               result.maxDrawdownPercent <= validationCriteria.maximumDrawdownPercent &&
               result.winRate >= validationCriteria.minimumWinRate &&
               result.profitFactor >= validationCriteria.minimumProfitFactor
    }
    
    // MARK: - Data Fetching
    
    private func fetchHistoricalData(symbol: String, days: Int) async throws -> [OHLCV] {
        // This would fetch from your candle service
        // For now, we'll throw an error indicating data needs to be fetched
        throw SageBacktestError.dataNotAvailable(symbol: symbol, days: days)
    }
    
    // MARK: - Persistence
    
    private static let resultsKey = "sage_backtest_results"
    
    private func saveResults() {
        do {
            let data = try JSONEncoder().encode(results)
            UserDefaults.standard.set(data, forKey: Self.resultsKey)
        } catch {
            #if DEBUG
            print("[SageBacktestRunner] Failed to save results: \(error)")
            #endif
        }
    }
    
    private func loadResults() {
        guard let data = UserDefaults.standard.data(forKey: Self.resultsKey) else { return }
        do {
            results = try JSONDecoder().decode([SageBacktestResult].self, from: data)
        } catch {
            #if DEBUG
            print("[SageBacktestRunner] Failed to load results: \(error)")
            #endif
        }
    }
    
    /// Clear all backtest results
    public func clearResults() {
        results = []
        saveResults()
    }
    
    // MARK: - Validation Summary
    
    /// Get validation summary for all algorithms
    public func getValidationSummary() -> [String: Bool] {
        var summary: [String: Bool] = [:]
        
        for algorithm in SageAlgorithmEngine.shared.algorithms {
            let algorithmResults = results.filter { $0.algorithmId == algorithm.id }
            
            // Algorithm passes if it passes for all test symbols
            let passesAll = testSymbols.allSatisfy { symbol in
                algorithmResults.first { $0.symbol == symbol }?.passesValidation ?? false
            }
            
            summary[algorithm.id] = passesAll
        }
        
        return summary
    }
}

// MARK: - Models

public struct SageValidationCriteria: Codable {
    public let minimumSharpeRatio: Double
    public let maximumDrawdownPercent: Double
    public let minimumWinRate: Double
    public let minimumProfitFactor: Double
    public let minimumTrades: Int
    public let minimumDataDays: Int
}

public struct SageBacktestResult: Codable, Identifiable {
    public var id: String { "\(algorithmId)_\(symbol)" }
    
    public let algorithmId: String
    public let algorithmName: String
    public let symbol: String
    public let timeframe: SageTimeframe
    public let startDate: Date
    public let endDate: Date
    
    // Metrics
    public var totalTrades: Int = 0
    public var winningTrades: Int = 0
    public var losingTrades: Int = 0
    public var winRate: Double = 0
    public var totalReturnPercent: Double = 0
    public var maxDrawdownPercent: Double = 0
    public var sharpeRatio: Double = 0
    public var profitFactor: Double = 0
    
    // Validation
    public var passesValidation: Bool = false
    public var errorMessage: String?
    
    /// Performance grade (A-F)
    public var grade: String {
        guard errorMessage == nil else { return "F" }
        
        var score = 0.0
        
        if sharpeRatio >= 2.0 { score += 25 }
        else if sharpeRatio >= 1.5 { score += 20 }
        else if sharpeRatio >= 1.0 { score += 15 }
        else if sharpeRatio >= 0.5 { score += 10 }
        
        if maxDrawdownPercent <= 10 { score += 25 }
        else if maxDrawdownPercent <= 15 { score += 20 }
        else if maxDrawdownPercent <= 20 { score += 15 }
        else if maxDrawdownPercent <= 25 { score += 10 }
        
        if winRate >= 60 { score += 25 }
        else if winRate >= 55 { score += 20 }
        else if winRate >= 50 { score += 15 }
        else if winRate >= 45 { score += 10 }
        
        if profitFactor >= 2.5 { score += 25 }
        else if profitFactor >= 2.0 { score += 20 }
        else if profitFactor >= 1.5 { score += 15 }
        else if profitFactor >= 1.2 { score += 10 }
        
        if score >= 85 { return "A" }
        if score >= 70 { return "B" }
        if score >= 55 { return "C" }
        if score >= 40 { return "D" }
        return "F"
    }
}

private struct BacktestPosition {
    let entryPrice: Double
    let quantity: Double
    let entryDate: Date
    let stopLoss: Double?
    let takeProfit: Double?
    let regime: SageMarketRegime
}

private struct SageBacktestTrade: Codable {
    let entryDate: Date
    let exitDate: Date
    let entryPrice: Double
    let exitPrice: Double
    let quantity: Double
    let pnl: Double
    let pnlPercent: Double
    let exitReason: String
}

public enum SageBacktestError: LocalizedError {
    case dataNotAvailable(symbol: String, days: Int)
    case insufficientData
    case algorithmNotFound
    
    public var errorDescription: String? {
        switch self {
        case .dataNotAvailable(let symbol, let days):
            return "Historical data for \(symbol) (\(days) days) not available. Fetch data first."
        case .insufficientData:
            return "Not enough data points for reliable backtest"
        case .algorithmNotFound:
            return "Algorithm not found"
        }
    }
}
