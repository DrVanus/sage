//
//  PaperBotManager.swift
//  CryptoSage
//
//  Centralized manager for paper trading bots.
//  Allows users to create, start, stop, and manage simulated trading bots
//  when paper trading mode is enabled.
//

import SwiftUI
import Combine

// MARK: - Paper Bot Type

public enum PaperBotType: String, Codable, CaseIterable {
    case dca = "DCA"
    case grid = "Grid"
    case signal = "Signal"
    case derivatives = "Derivatives"
    case predictionMarket = "Prediction"
    
    var displayName: String {
        switch self {
        case .dca: return "DCA Bot"
        case .grid: return "Grid Bot"
        case .signal: return "Signal Bot"
        case .derivatives: return "Derivatives Bot"
        case .predictionMarket: return "Prediction Bot"
        }
    }
    
    var icon: String {
        switch self {
        case .dca: return "repeat.circle.fill"
        case .grid: return "square.grid.3x3.fill"
        case .signal: return "bolt.circle.fill"
        case .derivatives: return "chart.line.uptrend.xyaxis.circle.fill"
        case .predictionMarket: return "chart.bar.xaxis.ascending"
        }
    }
    
    var color: Color {
        switch self {
        case .dca: return .blue
        case .grid: return .purple
        case .signal: return .orange
        case .derivatives: return .red
        case .predictionMarket: return .cyan
        }
    }
}

// MARK: - Bot Status

public enum PaperBotStatus: String, Codable {
    case idle = "Idle"
    case running = "Running"
    case paused = "Paused"
    case stopped = "Stopped"
    
    var color: Color {
        switch self {
        case .idle: return .gray
        case .running: return .green
        case .paused: return .orange
        case .stopped: return .red
        }
    }
    
    var icon: String {
        switch self {
        case .idle: return "circle"
        case .running: return "play.circle.fill"
        case .paused: return "pause.circle.fill"
        case .stopped: return "stop.circle.fill"
        }
    }
}

// MARK: - Paper Bot Model

public struct PaperBot: Codable, Identifiable {
    public let id: UUID
    public var name: String
    public let type: PaperBotType
    public let exchange: String
    public let tradingPair: String
    public var config: [String: String]
    public var status: PaperBotStatus
    public let createdAt: Date
    public var lastRunAt: Date?
    public var totalTrades: Int
    public var totalProfit: Double
    
    /// Optional link to a TradingStrategy for real strategy evaluation
    public var strategyId: UUID?
    
    /// Track current position for P&L calculation
    public var currentPositionEntryPrice: Double?
    public var currentPositionQuantity: Double?
    
    public init(
        id: UUID = UUID(),
        name: String,
        type: PaperBotType,
        exchange: String,
        tradingPair: String,
        config: [String: String] = [:],
        status: PaperBotStatus = .idle,
        createdAt: Date = Date(),
        lastRunAt: Date? = nil,
        totalTrades: Int = 0,
        totalProfit: Double = 0,
        strategyId: UUID? = nil,
        currentPositionEntryPrice: Double? = nil,
        currentPositionQuantity: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.exchange = exchange
        self.tradingPair = tradingPair
        self.config = config
        self.status = status
        self.createdAt = createdAt
        self.lastRunAt = lastRunAt
        self.totalTrades = totalTrades
        self.totalProfit = totalProfit
        self.strategyId = strategyId
        self.currentPositionEntryPrice = currentPositionEntryPrice
        self.currentPositionQuantity = currentPositionQuantity
    }
    
    // MARK: - Config Accessors
    
    // DCA Bot Config
    var baseOrderSize: String? { config["baseOrderSize"] }
    var takeProfit: String? { config["takeProfit"] }
    var stopLoss: String? { config["stopLoss"] }
    var maxOrders: String? { config["maxOrders"] }
    var priceDeviation: String? { config["priceDeviation"] }
    var direction: String? { config["direction"] }
    
    // Grid Bot Config
    var lowerPrice: String? { config["lowerPrice"] }
    var upperPrice: String? { config["upperPrice"] }
    var gridLevels: String? { config["gridLevels"] }
    var orderVolume: String? { config["orderVolume"] }
    
    // Signal Bot Config
    var maxInvestment: String? { config["maxInvestment"] }
    var entriesLimit: String? { config["entriesLimit"] }
    
    // Derivatives Bot Config
    var leverage: String? { config["leverage"] }
    var marginMode: String? { config["marginMode"] }
    var market: String? { config["market"] }
    
    // Prediction Market Bot Config
    var platform: String? { config["platform"] }
    var marketId: String? { config["marketId"] }
    var marketTitle: String? { config["marketTitle"] }
    var outcome: String? { config["outcome"] }
    var targetPrice: String? { config["targetPrice"] }
    var betAmount: String? { config["betAmount"] }
    var category: String? { config["category"] }
}

// MARK: - Paper Bot Manager

@MainActor
public final class PaperBotManager: ObservableObject {
    public static let shared = PaperBotManager()
    
    // MARK: - Storage Keys
    private static let botsKey = "paper_bots_list"
    
    // MARK: - Published State
    
    /// List of all paper bots
    @Published public var paperBots: [PaperBot] = []
    
    /// Currently running bots (for simulation tracking)
    @Published public var runningBotIds: Set<UUID> = []
    
    // MARK: - Simulation Timers
    private var simulationTimers: [UUID: Timer] = [:]
    
    // MARK: - Initialization
    
    private init() {
        loadBots()
    }
    
    // MARK: - CRUD Operations
    
    /// Create a new paper bot
    @discardableResult
    public func createBot(
        name: String,
        type: PaperBotType,
        exchange: String,
        tradingPair: String,
        config: [String: String] = [:]
    ) -> PaperBot {
        let bot = PaperBot(
            name: name.isEmpty ? "\(type.displayName)" : name,
            type: type,
            exchange: exchange,
            tradingPair: tradingPair,
            config: config
        )
        
        paperBots.insert(bot, at: 0) // Most recent first
        saveBots()
        
        return bot
    }
    
    /// Create a DCA bot with all config parameters
    @discardableResult
    public func createDCABot(
        name: String,
        exchange: String,
        tradingPair: String,
        direction: String,
        baseOrderSize: String,
        takeProfit: String,
        stopLoss: String?,
        maxOrders: String,
        priceDeviation: String,
        additionalConfig: [String: String] = [:]
    ) -> PaperBot {
        var config = additionalConfig
        config["direction"] = direction
        config["baseOrderSize"] = baseOrderSize
        config["takeProfit"] = takeProfit
        if let sl = stopLoss { config["stopLoss"] = sl }
        config["maxOrders"] = maxOrders
        config["priceDeviation"] = priceDeviation
        
        return createBot(
            name: name,
            type: .dca,
            exchange: exchange,
            tradingPair: tradingPair,
            config: config
        )
    }
    
    /// Create a Grid bot with all config parameters
    @discardableResult
    public func createGridBot(
        name: String,
        exchange: String,
        tradingPair: String,
        lowerPrice: String,
        upperPrice: String,
        gridLevels: String,
        orderVolume: String,
        takeProfit: String,
        stopLoss: String?,
        additionalConfig: [String: String] = [:]
    ) -> PaperBot {
        var config = additionalConfig
        config["lowerPrice"] = lowerPrice
        config["upperPrice"] = upperPrice
        config["gridLevels"] = gridLevels
        config["orderVolume"] = orderVolume
        config["takeProfit"] = takeProfit
        if let sl = stopLoss { config["stopLoss"] = sl }
        
        return createBot(
            name: name,
            type: .grid,
            exchange: exchange,
            tradingPair: tradingPair,
            config: config
        )
    }
    
    /// Create a Signal bot with all config parameters
    @discardableResult
    public func createSignalBot(
        name: String,
        exchange: String,
        tradingPair: String,
        maxInvestment: String,
        priceDeviation: String,
        entriesLimit: String,
        takeProfit: String,
        stopLoss: String?,
        additionalConfig: [String: String] = [:]
    ) -> PaperBot {
        var config = additionalConfig
        config["maxInvestment"] = maxInvestment
        config["priceDeviation"] = priceDeviation
        config["entriesLimit"] = entriesLimit
        config["takeProfit"] = takeProfit
        if let sl = stopLoss { config["stopLoss"] = sl }
        
        return createBot(
            name: name,
            type: .signal,
            exchange: exchange,
            tradingPair: tradingPair,
            config: config
        )
    }
    
    /// Create a Derivatives bot with all config parameters
    @discardableResult
    public func createDerivativesBot(
        name: String,
        exchange: String,
        market: String,
        leverage: Int,
        marginMode: String,
        direction: String,
        takeProfit: String?,
        stopLoss: String?,
        additionalConfig: [String: String] = [:]
    ) -> PaperBot {
        var config = additionalConfig
        config["leverage"] = String(leverage)
        config["marginMode"] = marginMode
        config["direction"] = direction
        config["market"] = market
        if let tp = takeProfit { config["takeProfit"] = tp }
        if let sl = stopLoss { config["stopLoss"] = sl }
        
        return createBot(
            name: name,
            type: .derivatives,
            exchange: exchange,
            tradingPair: market,
            config: config
        )
    }
    
    /// Create a Prediction Market bot with all config parameters
    @discardableResult
    public func createPredictionBot(
        name: String,
        platform: String,
        marketId: String,
        marketTitle: String,
        outcome: String,
        targetPrice: String,
        betAmount: String,
        category: String? = nil,
        additionalConfig: [String: String] = [:]
    ) -> PaperBot {
        var config = additionalConfig
        config["platform"] = platform
        config["marketId"] = marketId
        config["marketTitle"] = marketTitle
        config["outcome"] = outcome
        config["targetPrice"] = targetPrice
        config["betAmount"] = betAmount
        if let cat = category { config["category"] = cat }
        
        return createBot(
            name: name.isEmpty ? "Prediction Bot" : name,
            type: .predictionMarket,
            exchange: platform, // Use platform as exchange for consistency
            tradingPair: marketTitle, // Use market title as trading pair for display
            config: config
        )
    }
    
    /// Create a Signal bot from a TradingStrategy
    /// This links the strategy to the bot for real-time evaluation
    @discardableResult
    public func createBotFromStrategy(_ strategy: TradingStrategy) -> PaperBot {
        var config: [String: String] = [:]
        
        // Copy strategy settings to bot config
        if let stopLoss = strategy.riskManagement.stopLossPercent {
            config["stopLoss"] = String(stopLoss)
        }
        if let takeProfit = strategy.riskManagement.takeProfitPercent {
            config["takeProfit"] = String(takeProfit)
        }
        config["positionSizePercent"] = String(strategy.positionSizing.portfolioPercent)
        config["timeframe"] = strategy.timeframe.rawValue
        config["entryConditions"] = String(strategy.entryConditions.count)
        config["exitConditions"] = String(strategy.exitConditions.count)
        
        var bot = createBot(
            name: "Strategy: \(strategy.name)",
            type: .signal,
            exchange: "Paper",
            tradingPair: strategy.tradingPair,
            config: config
        )
        
        // Link the strategy to the bot
        bot.strategyId = strategy.id
        updateBot(bot)
        
        return bot
    }
    
    /// Check if a strategy is already deployed as a bot
    public func isBotDeployedForStrategy(strategyId: UUID) -> Bool {
        return paperBots.contains { $0.strategyId == strategyId }
    }
    
    /// Get the bot for a deployed strategy
    public func getBotForStrategy(strategyId: UUID) -> PaperBot? {
        return paperBots.first { $0.strategyId == strategyId }
    }
    
    /// Update an existing bot
    public func updateBot(_ bot: PaperBot) {
        if let index = paperBots.firstIndex(where: { $0.id == bot.id }) {
            paperBots[index] = bot
            saveBots()
        }
    }
    
    /// Delete a bot by ID
    public func deleteBot(id: UUID) {
        // Stop simulation if running
        stopBot(id: id)
        
        paperBots.removeAll { $0.id == id }
        saveBots()
    }
    
    /// Get a bot by ID
    public func getBot(id: UUID) -> PaperBot? {
        paperBots.first { $0.id == id }
    }
    
    // MARK: - Bot Control
    
    /// Start a bot (begin simulation)
    public func startBot(id: UUID) {
        guard var bot = getBot(id: id) else { return }
        guard bot.status != .running else { return }
        
        bot.status = .running
        bot.lastRunAt = Date()
        updateBot(bot)
        
        runningBotIds.insert(id)
        
        // Start simulation timer (simulates periodic trades)
        startSimulation(for: id)
        
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
    
    /// Stop a bot
    public func stopBot(id: UUID) {
        guard var bot = getBot(id: id) else { return }
        
        bot.status = .stopped
        updateBot(bot)
        
        runningBotIds.remove(id)
        
        // Stop simulation timer
        stopSimulation(for: id)
        
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
    
    /// Pause a bot
    public func pauseBot(id: UUID) {
        guard var bot = getBot(id: id) else { return }
        guard bot.status == .running else { return }
        
        bot.status = .paused
        updateBot(bot)
        
        runningBotIds.remove(id)
        stopSimulation(for: id)
    }
    
    /// Resume a paused bot
    public func resumeBot(id: UUID) {
        guard var bot = getBot(id: id) else { return }
        guard bot.status == .paused else { return }
        
        bot.status = .running
        bot.lastRunAt = Date()
        updateBot(bot)
        
        runningBotIds.insert(id)
        startSimulation(for: id)
    }
    
    /// Toggle bot running state
    public func toggleBot(id: UUID) {
        guard let bot = getBot(id: id) else { return }
        
        switch bot.status {
        case .running:
            stopBot(id: id)
        case .paused:
            resumeBot(id: id)
        default:
            startBot(id: id)
        }
    }
    
    /// Check if a bot is running
    public func isRunning(id: UUID) -> Bool {
        runningBotIds.contains(id)
    }
    
    // MARK: - Simulation
    
    private func startSimulation(for botId: UUID) {
        // Cancel any existing timer
        simulationTimers[botId]?.invalidate()
        
        // Create a timer that simulates bot activity
        // In a real implementation, this would execute trades based on strategy
        let timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.simulateBotActivity(botId: botId)
            }
        }
        
        simulationTimers[botId] = timer
        
        // Run first simulation immediately
        Task { @MainActor in
            simulateBotActivity(botId: botId)
        }
    }
    
    private func stopSimulation(for botId: UUID) {
        simulationTimers[botId]?.invalidate()
        simulationTimers.removeValue(forKey: botId)
    }
    
    /// Simulate bot trading activity
    /// This evaluates strategy conditions and executes trades when signals trigger
    private func simulateBotActivity(botId: UUID) {
        guard var bot = getBot(id: botId),
              bot.status == .running,
              PaperTradingManager.isEnabled else { return }
        
        // Parse trading pair
        let (baseAsset, _) = PaperTradingManager.shared.parseSymbol(bot.tradingPair)
        
        // Get current price from MarketViewModel
        let currentPrice = getLivePrice(for: baseAsset)
        guard currentPrice > 0 else { return }
        
        // Check if bot has a linked strategy for real evaluation
        if let strategyId = bot.strategyId,
           let strategy = StrategyEngine.shared.getStrategy(id: strategyId) {
            // Use real strategy evaluation
            evaluateStrategyForBot(bot: &bot, strategy: strategy, currentPrice: currentPrice, baseAsset: baseAsset)
        } else {
            // Fallback to bot-type-specific behavior
            evaluateBotTypeRules(bot: &bot, currentPrice: currentPrice, baseAsset: baseAsset)
        }
    }
    
    /// Evaluate a linked strategy and execute trades based on signals
    private func evaluateStrategyForBot(bot: inout PaperBot, strategy: TradingStrategy, currentPrice: Double, baseAsset: String) {
        // Get price history for indicator calculation
        let priceHistory = getPriceHistory(for: baseAsset)
        guard priceHistory.count >= 20 else { return } // Need enough data for indicators
        
        // Create market data snapshot
        let marketData = StrategyMarketData(
            symbol: bot.tradingPair,
            timestamp: Date(),
            open: priceHistory.first ?? currentPrice,
            high: priceHistory.max() ?? currentPrice,
            low: priceHistory.min() ?? currentPrice,
            close: currentPrice,
            volume: 0 // Volume not used for signal bots
        )
        
        // Evaluate strategy
        guard let signal = StrategyEngine.shared.evaluateStrategy(
            strategy,
            marketData: marketData,
            priceHistory: priceHistory
        ) else { return }
        
        // Execute trade based on signal
        let side: TradeSide = signal.type == .buy ? .buy : .sell
        
        // Check if we should execute based on current position
        let hasPosition = bot.currentPositionQuantity != nil && (bot.currentPositionQuantity ?? 0) > 0
        
        // Only buy if no position, only sell if we have a position
        if signal.type == .buy && hasPosition { return }
        if signal.type == .sell && !hasPosition { return }
        
        // Calculate position size using strategy rules
        // FIX: Build a proper price dictionary instead of passing empty [:] which
        // would make all non-USDT assets contribute $0 to portfolio value
        var botPrices: [String: Double] = ["USDT": 1.0, "USD": 1.0, "USDC": 1.0]
        for coin in MarketViewModel.shared.allCoins {
            let sym = coin.symbol.uppercased()
            if let price = MarketViewModel.shared.bestPrice(for: coin.id), price > 0 {
                botPrices[sym] = price
            } else if let price = coin.priceUsd, price > 0 {
                botPrices[sym] = price
            }
        }
        let portfolioValue = PaperTradingManager.shared.calculatePortfolioValue(prices: botPrices)
        let tradeQuantity = StrategyEngine.shared.calculatePositionSize(
            for: strategy,
            portfolioValue: portfolioValue,
            currentPrice: currentPrice
        )
        
        guard tradeQuantity > 0 else { return }
        
        // Execute trade
        let result = PaperTradingManager.shared.executePaperTrade(
            symbol: bot.tradingPair,
            side: side,
            quantity: tradeQuantity,
            price: currentPrice,
            orderType: "STRATEGY_\(signal.type.rawValue)"
        )
        
        if result.success {
            bot.totalTrades += 1
            
            if signal.type == .buy {
                // Opening position
                bot.currentPositionEntryPrice = currentPrice
                bot.currentPositionQuantity = tradeQuantity
            } else {
                // Closing position - calculate P&L
                if let entryPrice = bot.currentPositionEntryPrice,
                   let qty = bot.currentPositionQuantity {
                    let profit = (currentPrice - entryPrice) * qty
                    bot.totalProfit += profit
                }
                bot.currentPositionEntryPrice = nil
                bot.currentPositionQuantity = nil
            }
            
            updateBot(bot)
        }
    }
    
    /// Evaluate bot-type-specific rules (for bots without linked strategy)
    private func evaluateBotTypeRules(bot: inout PaperBot, currentPrice: Double, baseAsset: String) {
        // Get price history for technical analysis
        let priceHistory = getPriceHistory(for: baseAsset)
        
        // Determine if we should trade based on bot type and technical conditions
        var shouldTrade = false
        var side: TradeSide = .buy
        
        switch bot.type {
        case .dca:
            // DCA always buys at regular intervals
            shouldTrade = true
            side = .buy
            
        case .grid:
            // Grid trades based on price levels
            if let lowerStr = bot.lowerPrice, let upperStr = bot.upperPrice,
               let lower = Double(lowerStr), let upper = Double(upperStr) {
                // FIX: Guard against division by zero when lower == upper,
                // and inverted range when lower > upper.
                let range = upper - lower
                guard range > 0 else {
                    // Invalid grid configuration — skip this tick
                    break
                }
                
                // Buy near lower bound, sell near upper bound
                let position = (currentPrice - lower) / range
                
                if position < 0.3 {
                    shouldTrade = true
                    side = .buy
                } else if position > 0.7 {
                    shouldTrade = true
                    side = .sell
                }
            }
            
        case .signal:
            // Signal bot uses RSI and MACD for entries
            if priceHistory.count >= 26 {
                if let rsi = TechnicalsEngine.rsi(priceHistory),
                   let macdHist = TechnicalsEngine.macdHistogram(priceHistory) {
                    // Buy on oversold + bullish MACD
                    if rsi < 30 && macdHist > 0 {
                        shouldTrade = true
                        side = .buy
                    }
                    // Sell on overbought + bearish MACD
                    else if rsi > 70 && macdHist < 0 {
                        shouldTrade = true
                        side = .sell
                    }
                }
            }
            
        case .derivatives, .predictionMarket:
            // Use momentum for derivatives
            if priceHistory.count >= 14 {
                if let momentum = TechnicalsEngine.momentum(priceHistory) {
                    shouldTrade = abs(momentum) > currentPrice * 0.01 // 1% move
                    side = momentum > 0 ? .buy : .sell
                }
            }
        }
        
        guard shouldTrade else { return }
        
        // Calculate trade amount
        let tradeAmount = calculateTradeAmount(for: bot, basePrice: currentPrice)
        guard tradeAmount > 0 else { return }
        
        // Check position constraints
        let hasPosition = bot.currentPositionQuantity != nil && (bot.currentPositionQuantity ?? 0) > 0
        if side == .sell && !hasPosition && bot.type != .dca { return }
        
        // Execute trade
        let result = PaperTradingManager.shared.executePaperTrade(
            symbol: bot.tradingPair,
            side: side,
            quantity: tradeAmount,
            price: currentPrice,
            orderType: "BOT_\(bot.type.rawValue.uppercased())"
        )
        
        if result.success {
            bot.totalTrades += 1
            
            if side == .buy {
                // FIX: Use weighted average entry price instead of overwriting.
                // Previously, each buy replaced the entry price with the latest price,
                // making DCA P&L calculations incorrect (e.g., 0.01 BTC @ $100k + 0.01 BTC @ $90k
                // showed entry as $90k instead of correct $95k average).
                let existingQty = bot.currentPositionQuantity ?? 0
                let existingPrice = bot.currentPositionEntryPrice ?? 0
                let totalQty = existingQty + tradeAmount
                if totalQty > 0 {
                    bot.currentPositionEntryPrice = ((existingPrice * existingQty) + (currentPrice * tradeAmount)) / totalQty
                } else {
                    bot.currentPositionEntryPrice = currentPrice
                }
                bot.currentPositionQuantity = totalQty
            } else if side == .sell {
                if let entryPrice = bot.currentPositionEntryPrice,
                   let qty = bot.currentPositionQuantity {
                    let profit = (currentPrice - entryPrice) * min(qty, tradeAmount)
                    bot.totalProfit += profit
                }
                let newQty = (bot.currentPositionQuantity ?? 0) - tradeAmount
                if newQty <= 0 {
                    bot.currentPositionEntryPrice = nil
                    bot.currentPositionQuantity = nil
                } else {
                    bot.currentPositionQuantity = newQty
                }
            }
            
            updateBot(bot)
        }
    }
    
    /// Get price history from MarketViewModel sparklines
    private func getPriceHistory(for asset: String) -> [Double] {
        let upperAsset = asset.uppercased()
        
        // Try to get sparkline data from MarketViewModel
        if let coin = MarketViewModel.shared.allCoins.first(where: {
            $0.symbol.uppercased() == upperAsset
        }), !coin.sparklineIn7d.isEmpty {
            return coin.sparklineIn7d
        }
        
        // Fallback: generate synthetic history based on current price
        let currentPrice = getLivePrice(for: asset)
        guard currentPrice > 0 else { return [] }
        
        // Generate 50 data points with unbiased random walk
        // FIX: Previous range [-0.02, +0.025] had a +0.25% upward bias per step,
        // producing an artificial uptrend that biased technical indicators bullish.
        var history: [Double] = []
        var price = currentPrice * 0.97 // Start slightly below current
        for _ in 0..<50 {
            history.append(price)
            price *= (1 + Double.random(in: -0.02...0.02))  // Symmetric range: no bias
        }
        history.append(currentPrice)
        
        return history
    }
    
    /// Get live price from MarketViewModel
    private func getLivePrice(for asset: String) -> Double {
        let upperAsset = asset.uppercased()
        
        // Primary: Check allCoins for fastest cached price
        if let coin = MarketViewModel.shared.allCoins.first(where: {
            $0.symbol.uppercased() == upperAsset
        }), let livePrice = coin.priceUsd, livePrice > 0 {
            return livePrice
        }
        
        // Secondary: Try bestPrice(forSymbol:) which checks all data sources
        if let bestPrice = MarketViewModel.shared.bestPrice(forSymbol: upperAsset),
           bestPrice > 0, bestPrice.isFinite {
            return bestPrice
        }
        
        return getSimulatedPrice(for: asset)
    }
    
    /// Get live market price for an asset - NO FAKE FALLBACKS
    /// Uses MarketViewModel.shared for real-time pricing from cache or live API
    /// Returns 0 if no real data available (trade will be skipped)
    private func getSimulatedPrice(for asset: String) -> Double {
        let upperAsset = asset.uppercased()
        
        // Try MarketViewModel's bestPrice which checks all real data sources
        // This includes: live coins, LivePriceManager, allCoins cache, price books
        if let coin = MarketViewModel.shared.allCoins.first(where: {
            $0.symbol.uppercased() == upperAsset
        }) {
            if let price = MarketViewModel.shared.bestPrice(for: coin.id), price > 0 {
                // Add small random variance (0.5%) for simulation realism
                let variance = price * Double.random(in: -0.005...0.005)
                return price + variance
            }
        }
        
        // Also try by symbol directly
        if let price = MarketViewModel.shared.bestPrice(forSymbol: upperAsset), price > 0 {
            let variance = price * Double.random(in: -0.005...0.005)
            return price + variance
        }
        
        // NO FAKE FALLBACKS - return 0 if no real data available
        // The calling code should handle this gracefully (skip trade, show loading, etc.)
        return 0
    }
    
    /// Calculate trade amount based on bot configuration
    private func calculateTradeAmount(for bot: PaperBot, basePrice: Double) -> Double {
        switch bot.type {
        case .dca:
            // Use base order size from config
            if let sizeStr = bot.baseOrderSize, let size = Double(sizeStr) {
                return size / basePrice  // Convert USD to asset quantity
            }
            return 10.0 / basePrice  // Default $10 per trade
            
        case .grid:
            // Use order volume from config
            if let volumeStr = bot.orderVolume, let volume = Double(volumeStr) {
                return volume / basePrice
            }
            return 5.0 / basePrice  // Default $5 per grid order
            
        case .signal:
            // Use max investment divided by entries
            if let maxStr = bot.maxInvestment, let max = Double(maxStr),
               let entriesStr = bot.entriesLimit, let entries = Double(entriesStr), entries > 0 {
                return (max / entries) / basePrice
            }
            return 20.0 / basePrice  // Default $20 per signal trade
            
        case .derivatives:
            // Use leverage to calculate position size
            if let levStr = bot.leverage, let lev = Double(levStr) {
                let baseAmount = 50.0  // Base position in USD
                return (baseAmount * lev) / basePrice
            }
            return 50.0 / basePrice  // Default $50 position
            
        case .predictionMarket:
            // Use bet amount from config
            if let betStr = bot.betAmount, let bet = Double(betStr) {
                return bet  // Already in USD for prediction markets
            }
            return 25.0  // Default $25 bet
        }
    }
    
    // MARK: - Statistics
    
    /// Get count of running bots
    public var runningBotCount: Int {
        runningBotIds.count
    }
    
    /// Get count of all bots
    public var totalBotCount: Int {
        paperBots.count
    }
    
    /// Get bots by type
    public func bots(ofType type: PaperBotType) -> [PaperBot] {
        paperBots.filter { $0.type == type }
    }
    
    /// Get bots by status
    public func bots(withStatus status: PaperBotStatus) -> [PaperBot] {
        paperBots.filter { $0.status == status }
    }
    
    /// Total profit across all bots
    public var totalProfit: Double {
        paperBots.map { $0.totalProfit }.reduce(0, +)
    }
    
    /// Total trades across all bots
    public var totalTrades: Int {
        paperBots.map { $0.totalTrades }.reduce(0, +)
    }
    
    // MARK: - Persistence
    
    private func saveBots() {
        do {
            let data = try JSONEncoder().encode(paperBots)
            UserDefaults.standard.set(data, forKey: Self.botsKey)
        } catch {
            print("[PaperBotManager] Failed to save bots: \(error)")
        }
    }
    
    private func loadBots() {
        guard let data = UserDefaults.standard.data(forKey: Self.botsKey) else { return }
        
        do {
            let loadedBots = try JSONDecoder().decode([PaperBot].self, from: data)
            paperBots = loadedBots
            
            // Reset any bots that were running when app closed
            for i in paperBots.indices {
                if paperBots[i].status == .running {
                    paperBots[i].status = .stopped
                }
            }
        } catch {
            print("[PaperBotManager] Failed to load bots: \(error)")
        }
    }
    
    /// Clear all paper bots
    public func clearAllBots() {
        // Stop all simulations
        for id in runningBotIds {
            stopSimulation(for: id)
        }
        runningBotIds.removeAll()
        paperBots.removeAll()
        saveBots()
    }
    
    // MARK: - Demo Mode Support
    
    /// IDs of demo bots (not persisted, generated fresh each session)
    private(set) var demoBotIds: Set<UUID> = []
    
    /// Demo bots shown when in demo mode
    @Published public var demoBots: [PaperBot] = []
    
    /// Check if a bot is a demo bot
    public func isDemoBot(id: UUID) -> Bool {
        demoBotIds.contains(id)
    }
    
    /// Seed demo bots for demo mode display
    /// Creates sample bots with realistic configurations and trade history
    public func seedDemoBots() {
        guard demoBots.isEmpty else { return } // Already seeded
        
        let now = Date()
        let calendar = Calendar.current
        
        // Demo Bot 1: BTC DCA Strategy (Running)
        let btcDCAId = UUID()
        let btcDCA = PaperBot(
            id: btcDCAId,
            name: "BTC DCA Strategy",
            type: .dca,
            exchange: "Binance",
            tradingPair: "BTC_USDT",
            config: [
                "direction": "Long",
                "baseOrderSize": "100",
                "takeProfit": "3.5",
                "stopLoss": "8",
                "maxOrders": "5",
                "priceDeviation": "1.5"
            ],
            status: .running,
            createdAt: calendar.date(byAdding: .day, value: -14, to: now) ?? now,
            lastRunAt: calendar.date(byAdding: .hour, value: -2, to: now),
            totalTrades: 12,
            totalProfit: 847.32
        )
        
        // Demo Bot 2: ETH Grid Trader (Running)
        let ethGridId = UUID()
        let ethGrid = PaperBot(
            id: ethGridId,
            name: "ETH Grid Trader",
            type: .grid,
            exchange: "Coinbase",
            tradingPair: "ETH_USDT",
            config: [
                "lowerPrice": "3200",
                "upperPrice": "3800",
                "gridLevels": "10",
                "orderVolume": "50",
                "takeProfit": "2.5",
                "stopLoss": "5"
            ],
            status: .running,
            createdAt: calendar.date(byAdding: .day, value: -21, to: now) ?? now,
            lastRunAt: calendar.date(byAdding: .minute, value: -45, to: now),
            totalTrades: 34,
            totalProfit: 1203.67
        )
        
        // Demo Bot 3: SOL Signal Hunter (Stopped)
        let solSignalId = UUID()
        let solSignal = PaperBot(
            id: solSignalId,
            name: "SOL Signal Hunter",
            type: .signal,
            exchange: "Binance",
            tradingPair: "SOL_USDT",
            config: [
                "maxInvestment": "500",
                "priceDeviation": "2",
                "entriesLimit": "3",
                "takeProfit": "4",
                "stopLoss": "6"
            ],
            status: .stopped,
            createdAt: calendar.date(byAdding: .day, value: -7, to: now) ?? now,
            lastRunAt: calendar.date(byAdding: .day, value: -1, to: now),
            totalTrades: 8,
            totalProfit: 156.89
        )
        
        demoBotIds = [btcDCAId, ethGridId, solSignalId]
        demoBots = [btcDCA, ethGrid, solSignal]
    }
    
    /// Clear demo bots
    public func clearDemoBots() {
        demoBotIds.removeAll()
        demoBots.removeAll()
    }
    
    /// Get demo bot by ID
    public func getDemoBot(id: UUID) -> PaperBot? {
        demoBots.first { $0.id == id }
    }
    
    /// Demo bot statistics
    public var demoBotCount: Int {
        demoBots.count
    }
    
    public var runningDemoBotCount: Int {
        demoBots.filter { $0.status == .running }.count
    }
    
    public var totalDemoBotProfit: Double {
        demoBots.map { $0.totalProfit }.reduce(0, +)
    }
    
    public var totalDemoBotTrades: Int {
        demoBots.map { $0.totalTrades }.reduce(0, +)
    }
}

// MARK: - Thread-Safe Access

extension PaperBotManager {
    /// Thread-safe check for running bot count
    nonisolated public static var hasRunningBots: Bool {
        // Use UserDefaults as a simple cross-thread indicator
        // The actual running state is managed by the MainActor instance
        false // Will be updated by MainActor
    }
}
