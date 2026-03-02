//
//  SageTradingService.swift
//  CryptoSage
//
//  Developer Mode: Live trading execution based on CryptoSage AI signals.
//  This service is ONLY for developer/internal use - not exposed to regular users.
//
//  IMPORTANT: This executes REAL TRADES on connected exchanges.
//  Only use in developer mode with appropriate risk management.
//

import Foundation
import Combine

// MARK: - Sage Trading Service

/// Executes trades based on CryptoSage AI algorithm signals
/// DEVELOPER MODE ONLY - Not for regular users
@MainActor
public final class SageTradingService: ObservableObject {
    public static let shared = SageTradingService()
    
    // MARK: - Published State
    
    @Published public var isAutoTradingEnabled: Bool = false
    @Published public var lastExecutedSignal: SageSignal?
    @Published public var executionHistory: [SageTradeExecution] = []
    @Published public var activePositions: [SagePosition] = []
    
    // MARK: - Configuration
    
    /// Minimum confidence required to execute a trade (0-100)
    public var minimumConfidence: Double = 70
    
    /// Minimum signal strength to execute (0-100)
    public var minimumSignalStrength: Double = 50
    
    /// Maximum position size as percentage of portfolio
    public var maxPositionSizePercent: Double = 10
    
    /// Default exchange to use for trading (persisted)
    @Published public var defaultExchange: TradingExchange = .coinbase {
        didSet { saveConfiguration() }
    }
    
    /// Quote currency for trading (e.g., "USDT", "USD")
    public var quoteCurrency: String = "USDT"
    
    /// Enable paper trading mode (simulate trades without execution)
    public var usePaperTrading: Bool = true
    
    /// Available exchanges that have credentials configured
    public var availableExchanges: [TradingExchange] {
        TradingCredentialsManager.shared.getConnectedExchanges()
    }
    
    // MARK: - Private
    
    private var cancellables = Set<AnyCancellable>()
    private var evaluationTimer: Timer?
    private let evaluationIntervalSeconds: TimeInterval = 300 // 5 minutes
    
    private init() {
        loadConfiguration()
        loadExecutionHistory()
    }
    
    // MARK: - Developer Mode Check
    
    /// Check if developer mode is enabled and live trading is allowed
    public var canExecuteLiveTrades: Bool {
        return AppConfig.isDeveloperMode && 
               AppConfig.liveTradingEnabled &&
               !usePaperTrading
    }
    
    // MARK: - Signal Execution
    
    /// Execute a trade based on a Sage signal
    /// - Parameters:
    ///   - signal: The Sage signal to execute
    ///   - portfolioValue: Total portfolio value for position sizing
    /// - Returns: Execution result
    public func executeSignal(
        _ signal: SageSignal,
        portfolioValue: Double
    ) async throws -> SageTradeExecution {
        
        // Safety check: Developer mode only
        guard AppConfig.isDeveloperMode else {
            throw SageTradingError.developerModeRequired
        }
        
        // Validate signal meets criteria
        guard signal.confidence >= minimumConfidence / 100 else {
            throw SageTradingError.confidenceTooLow(required: minimumConfidence, actual: signal.confidence * 100)
        }
        
        guard abs(signal.score) >= minimumSignalStrength else {
            throw SageTradingError.signalTooWeak(required: minimumSignalStrength, actual: abs(signal.score))
        }
        
        // Determine trade side and size
        let side: TradeSide
        switch signal.type {
        case .strongBuy, .buy:
            side = .buy
        case .strongSell, .sell:
            side = .sell
        case .hold:
            throw SageTradingError.holdSignalNotTradeable
        }
        
        // Calculate position size based on signal and regime
        let positionSizePercent = calculatePositionSize(
            signal: signal,
            maxPercent: maxPositionSizePercent
        )
        
        let positionValue = portfolioValue * (positionSizePercent / 100)
        
        // Get current price for quantity calculation
        let currentPrice = signal.suggestedEntry ?? 0
        
        guard currentPrice > 0 else {
            throw SageTradingError.invalidPrice
        }
        
        let quantity = positionValue / currentPrice
        
        // Create execution record
        var execution = SageTradeExecution(
            id: UUID(),
            signalId: signal.id,
            algorithmId: signal.algorithmId,
            algorithmName: signal.algorithmName,
            symbol: signal.symbol,
            side: side,
            signalType: signal.type,
            signalScore: signal.score,
            signalConfidence: signal.confidence,
            regime: signal.regime,
            requestedQuantity: quantity,
            requestedPrice: currentPrice,
            positionSizePercent: positionSizePercent,
            exchange: defaultExchange,
            timestamp: Date()
        )
        
        // Execute trade (paper or live)
        if usePaperTrading {
            execution = try await executePaperTrade(execution)
        } else if canExecuteLiveTrades {
            execution = try await executeLiveTrade(execution)
        } else {
            throw SageTradingError.liveTradingDisabled
        }
        
        // Store execution
        executionHistory.insert(execution, at: 0)
        if executionHistory.count > 100 {
            executionHistory = Array(executionHistory.prefix(100))
        }
        saveExecutionHistory()
        
        lastExecutedSignal = signal
        
        // Track position
        if execution.success {
            updatePositions(from: execution)
        }
        
        return execution
    }
    
    /// Execute a consensus signal (from Sage Neural)
    public func executeConsensus(
        _ consensus: SageConsensus,
        portfolioValue: Double
    ) async throws -> SageTradeExecution {
        
        // Create a synthetic signal from consensus
        let signal = SageSignal(
            algorithmId: "sage_neural",
            algorithmName: "Sage Neural (Consensus)",
            category: .ai,
            symbol: consensus.symbol,
            type: consensus.masterSignal,
            score: consensus.averageScore,
            confidence: consensus.confidence / 100,
            regime: consensus.regime,
            factors: ["Consensus from \(consensus.bullishCount) bullish, \(consensus.bearishCount) bearish algorithms"],
            suggestedEntry: nil,  // Will be fetched
            suggestedStopLoss: nil,
            suggestedTakeProfit: nil
        )
        
        return try await executeSignal(signal, portfolioValue: portfolioValue)
    }
    
    // MARK: - Auto Trading
    
    /// Start automatic trading based on Sage signals
    /// DEVELOPER MODE ONLY
    public func startAutoTrading(symbols: [String], portfolioValue: Double) {
        guard AppConfig.isDeveloperMode else { return }
        
        isAutoTradingEnabled = true
        
        // Start periodic evaluation
        evaluationTimer?.invalidate()
        evaluationTimer = Timer.scheduledTimer(withTimeInterval: evaluationIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.evaluateAndTrade(symbols: symbols, portfolioValue: portfolioValue)
            }
        }
        
        // Run initial evaluation
        Task {
            await evaluateAndTrade(symbols: symbols, portfolioValue: portfolioValue)
        }
    }
    
    /// Stop automatic trading
    public func stopAutoTrading() {
        isAutoTradingEnabled = false
        evaluationTimer?.invalidate()
        evaluationTimer = nil
    }
    
    private func evaluateAndTrade(symbols: [String], portfolioValue: Double) async {
        guard isAutoTradingEnabled else { return }
        
        for symbol in symbols {
            do {
                // Get market data
                guard let data = await fetchMarketData(for: symbol) else { continue }
                
                // Evaluate with Sage algorithms
                let consensus = await SageAlgorithmEngine.shared.evaluateAll(data: data)
                
                // Check if signal is strong enough
                guard consensus.confidence >= minimumConfidence,
                      consensus.masterSignal != .hold else {
                    continue
                }
                
                // Check if we already have a position
                if let existingPosition = activePositions.first(where: { $0.symbol == symbol }) {
                    // Check for exit signal
                    if shouldExitPosition(existingPosition, newConsensus: consensus) {
                        try await closePosition(existingPosition)
                    }
                } else {
                    // Enter new position
                    _ = try await executeConsensus(consensus, portfolioValue: portfolioValue)
                }
            } catch {
                #if DEBUG
                print("[SageTradingService] Error trading \(symbol): \(error)")
                #endif
            }
        }
    }
    
    // MARK: - Position Management
    
    private func updatePositions(from execution: SageTradeExecution) {
        guard execution.success else { return }
        
        if execution.side == .buy {
            // Add or increase position
            if let index = activePositions.firstIndex(where: { $0.symbol == execution.symbol }) {
                var position = activePositions[index]
                position.quantity += execution.filledQuantity ?? 0
                position.averageEntryPrice = (position.averageEntryPrice + (execution.filledPrice ?? 0)) / 2
                activePositions[index] = position
            } else {
                let position = SagePosition(
                    symbol: execution.symbol,
                    side: .buy,
                    quantity: execution.filledQuantity ?? 0,
                    averageEntryPrice: execution.filledPrice ?? execution.requestedPrice,
                    entryTime: execution.timestamp,
                    algorithmId: execution.algorithmId,
                    regime: execution.regime
                )
                activePositions.append(position)
            }
        } else {
            // Close or reduce position
            if let index = activePositions.firstIndex(where: { $0.symbol == execution.symbol }) {
                var position = activePositions[index]
                position.quantity -= execution.filledQuantity ?? 0
                if position.quantity <= 0 {
                    activePositions.remove(at: index)
                } else {
                    activePositions[index] = position
                }
            }
        }
    }
    
    private func shouldExitPosition(_ position: SagePosition, newConsensus: SageConsensus) -> Bool {
        // Exit if signal reversed strongly
        if position.side == .buy && (newConsensus.masterSignal == .sell || newConsensus.masterSignal == .strongSell) {
            return newConsensus.confidence >= 60
        }
        
        // Exit if regime changed to distribution
        if newConsensus.regime == .distribution {
            return true
        }
        
        return false
    }
    
    private func closePosition(_ position: SagePosition) async throws {
        // Create exit signal
        let signal = SageSignal(
            algorithmId: position.algorithmId,
            algorithmName: "Position Exit",
            category: .ai,
            symbol: position.symbol,
            type: .sell,
            score: -50,
            confidence: 0.8,
            regime: position.regime,
            factors: ["Closing position based on exit signal"]
        )
        
        // Estimate portfolio value (simplified)
        let positionValue = position.quantity * position.averageEntryPrice
        _ = try await executeSignal(signal, portfolioValue: positionValue * 10)
    }
    
    // MARK: - Trade Execution
    
    private func executePaperTrade(_ execution: SageTradeExecution) async throws -> SageTradeExecution {
        var result = execution
        
        // Simulate execution
        result.success = true
        result.filledQuantity = execution.requestedQuantity
        result.filledPrice = execution.requestedPrice
        result.orderId = "PAPER_\(UUID().uuidString.prefix(8))"
        result.isPaperTrade = true
        
        // Small random slippage
        let slippage = Double.random(in: 0.999...1.001)
        result.filledPrice = execution.requestedPrice * slippage
        
        #if DEBUG
        print("[SageTradingService] PAPER TRADE: \(execution.side.rawValue) \(execution.requestedQuantity) \(execution.symbol) @ \(execution.requestedPrice)")
        #endif
        
        return result
    }
    
    private func executeLiveTrade(_ execution: SageTradeExecution) async throws -> SageTradeExecution {
        var result = execution
        
        // Get trading symbol format for exchange
        let tradingSymbol = "\(normalizeSymbol(execution.symbol))\(quoteCurrency)"
        
        do {
            let orderResult = try await TradingExecutionService.shared.submitMarketOrder(
                exchange: execution.exchange,
                symbol: tradingSymbol,
                side: execution.side,
                quantity: execution.requestedQuantity
            )
            
            result.success = orderResult.success
            result.orderId = orderResult.orderId
            result.filledQuantity = orderResult.filledQuantity
            result.filledPrice = orderResult.averagePrice
            result.errorMessage = orderResult.errorMessage
            result.isPaperTrade = false
            
            #if DEBUG
            print("[SageTradingService] LIVE TRADE: \(execution.side.rawValue) \(execution.requestedQuantity) \(tradingSymbol) - Success: \(orderResult.success)")
            #endif
            
        } catch {
            result.success = false
            result.errorMessage = error.localizedDescription
            #if DEBUG
            print("[SageTradingService] LIVE TRADE FAILED: \(error)")
            #endif
        }
        
        return result
    }
    
    // MARK: - Helpers
    
    private func calculatePositionSize(signal: SageSignal, maxPercent: Double) -> Double {
        // Base size from signal regime
        var size = signal.regime.positionSizeMultiplier * maxPercent
        
        // Adjust for confidence
        size *= signal.confidence
        
        // Adjust for signal strength
        let strengthFactor = min(abs(signal.score) / 100, 1.0)
        size *= (0.5 + strengthFactor * 0.5)  // 50% to 100% based on strength
        
        // Cap at max
        return min(size, maxPercent)
    }
    
    private func normalizeSymbol(_ symbol: String) -> String {
        // Remove common suffixes and normalize
        var normalized = symbol.uppercased()
        let suffixes = ["USDT", "USD", "USDC", "BUSD", "-USD", "_USD"]
        for suffix in suffixes {
            if normalized.hasSuffix(suffix) {
                normalized = String(normalized.dropLast(suffix.count))
                break
            }
        }
        return normalized
    }
    
    private func fetchMarketData(for symbol: String) async -> SageMarketData? {
        // This would integrate with your existing market data services
        // For now, return nil to indicate data fetch needed
        return nil
    }
    
    // MARK: - Persistence
    
    private static let configKey = "sage_trading_config"
    private static let historyKey = "sage_trading_history"
    
    private func loadConfiguration() {
        let defaults = UserDefaults.standard
        minimumConfidence = defaults.double(forKey: "sage_min_confidence")
        if minimumConfidence == 0 { minimumConfidence = 70 }
        
        minimumSignalStrength = defaults.double(forKey: "sage_min_strength")
        if minimumSignalStrength == 0 { minimumSignalStrength = 50 }
        
        maxPositionSizePercent = defaults.double(forKey: "sage_max_position")
        if maxPositionSizePercent == 0 { maxPositionSizePercent = 10 }
        
        usePaperTrading = defaults.object(forKey: "sage_paper_trading") as? Bool ?? true
        
        // Load default exchange (prefer Coinbase for developer, auto-detect from connected exchanges)
        if let exchangeRaw = defaults.string(forKey: "sage_default_exchange"),
           let exchange = TradingExchange(rawValue: exchangeRaw) {
            defaultExchange = exchange
        } else if let connected = TradingCredentialsManager.shared.defaultExchange {
            // Auto-select first connected exchange
            defaultExchange = connected
        }
        
        // Load quote currency
        if let quote = defaults.string(forKey: "sage_quote_currency"), !quote.isEmpty {
            quoteCurrency = quote
        }
    }
    
    public func saveConfiguration() {
        let defaults = UserDefaults.standard
        defaults.set(minimumConfidence, forKey: "sage_min_confidence")
        defaults.set(minimumSignalStrength, forKey: "sage_min_strength")
        defaults.set(maxPositionSizePercent, forKey: "sage_max_position")
        defaults.set(usePaperTrading, forKey: "sage_paper_trading")
        defaults.set(defaultExchange.rawValue, forKey: "sage_default_exchange")
        defaults.set(quoteCurrency, forKey: "sage_quote_currency")
    }
    
    private func loadExecutionHistory() {
        guard let data = UserDefaults.standard.data(forKey: Self.historyKey) else { return }
        do {
            executionHistory = try JSONDecoder().decode([SageTradeExecution].self, from: data)
        } catch {
            #if DEBUG
            print("[SageTradingService] Failed to load history: \(error)")
            #endif
        }
    }
    
    private func saveExecutionHistory() {
        do {
            let data = try JSONEncoder().encode(executionHistory)
            UserDefaults.standard.set(data, forKey: Self.historyKey)
        } catch {
            #if DEBUG
            print("[SageTradingService] Failed to save history: \(error)")
            #endif
        }
    }
}

// MARK: - Models

/// Record of a trade executed based on Sage signal
public struct SageTradeExecution: Codable, Identifiable {
    public let id: UUID
    public let signalId: UUID
    public let algorithmId: String
    public let algorithmName: String
    public let symbol: String
    public let side: TradeSide
    public let signalType: SageSignalType
    public let signalScore: Double
    public let signalConfidence: Double
    public let regime: SageMarketRegime
    public let requestedQuantity: Double
    public let requestedPrice: Double
    public let positionSizePercent: Double
    public let exchange: TradingExchange
    public let timestamp: Date
    
    // Results (populated after execution)
    public var success: Bool = false
    public var orderId: String?
    public var filledQuantity: Double?
    public var filledPrice: Double?
    public var errorMessage: String?
    public var isPaperTrade: Bool = true
    
    /// Profit/loss if position was closed
    public var profitLoss: Double?
    public var profitLossPercent: Double?
}

/// Active position from Sage trading
public struct SagePosition: Codable, Identifiable {
    public var id: String { symbol }
    public let symbol: String
    public let side: TradeSide
    public var quantity: Double
    public var averageEntryPrice: Double
    public let entryTime: Date
    public let algorithmId: String
    public let regime: SageMarketRegime
    
    /// Current unrealized P&L
    public func unrealizedPnL(currentPrice: Double) -> Double {
        return (currentPrice - averageEntryPrice) * quantity
    }
    
    public func unrealizedPnLPercent(currentPrice: Double) -> Double {
        guard averageEntryPrice > 0 else { return 0 }
        return ((currentPrice - averageEntryPrice) / averageEntryPrice) * 100
    }
}

// MARK: - Errors

public enum SageTradingError: LocalizedError {
    case developerModeRequired
    case liveTradingDisabled
    case confidenceTooLow(required: Double, actual: Double)
    case signalTooWeak(required: Double, actual: Double)
    case holdSignalNotTradeable
    case invalidPrice
    case executionFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .developerModeRequired:
            return "Sage trading requires developer mode"
        case .liveTradingDisabled:
            return "Live trading is disabled"
        case .confidenceTooLow(let required, let actual):
            return "Signal confidence \(Int(actual))% below required \(Int(required))%"
        case .signalTooWeak(let required, let actual):
            return "Signal strength \(Int(actual)) below required \(Int(required))"
        case .holdSignalNotTradeable:
            return "Hold signals don't generate trades"
        case .invalidPrice:
            return "Unable to determine current price"
        case .executionFailed(let message):
            return "Trade execution failed: \(message)"
        }
    }
}

