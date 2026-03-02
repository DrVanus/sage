//
//  DerivativesBotViewModel.swift
//  CryptoSage
//
//  Created by DM on 5/29/25.
//

import SwiftUI
import Combine

// MARK: - DerivativesBotViewModel
@MainActor
class DerivativesBotViewModel: ObservableObject {
    // MARK: - UI State
    enum BotTab: String, CaseIterable, Identifiable, Hashable {
        case chat = "AI Chat"
        case strategy = "Strategy"
        case risk = "Risk & Accounts"
        var id: String { rawValue }
        var title: String { rawValue }
    }
    
    enum StrategyType: String, CaseIterable, Identifiable {
        case dca = "DCA"
        case grid = "Grid"
        case signal = "Signal"
        case custom = "Custom"
        var id: String { rawValue }
    }
    enum PositionSide: String, CaseIterable, Identifiable { case long = "Long", short = "Short"; var id: String { rawValue } }

    @Published var selectedTab: BotTab = .chat

    // Strategy form inputs
    @Published var botName: String = ""
    @Published var strategyType: StrategyType = .grid
    @Published var positionSide: PositionSide = .long
    @Published var positionSize: String = "" // in quote currency (e.g., USDT)
    @Published var takeProfitPct: String = ""
    @Published var stopLossPct: String = ""
    @Published var trailingStop: Bool = false
    @Published var entryCondition: String = "" // free-form condition or rule

    // Grid strategy inputs
    @Published var lowerPrice: String = ""
    @Published var upperPrice: String = ""
    @Published var gridLevels: String = ""
    @Published var orderVolume: String = ""

    // Chat history
    @Published var chatMessages: [ChatMessage] = []
    @Published var isTyping: Bool = false

    // Maximum leverage for UI
    let maxLeverage: Int = 125
    // MARK: Published properties for UI binding
    @Published var availableDerivativesExchanges: [Exchange] = []
    @Published var marketsForSelectedExchange: [Market] = []
    @Published var selectedExchange: Exchange? = nil {
        didSet {
            // Defer to avoid "Modifying state during view update"
            Task { @MainActor [weak self] in
                self?.fetchMarkets()
            }
        }
    }
    @Published var selectedMarket: Market? = nil
    @Published var leverage: Int = 5
    @Published var isIsolated: Bool = false
    @Published var isRunning: Bool = false

    // Favorites (persisted) for market picker
    @Published var favoriteMarketSymbols: Set<String> = []
    private let favoritesKey = "derivatives_favorite_markets"
    
    // Paper trading bot tracking
    private var currentPaperBotId: UUID?
    @Published var showBotCreatedAlert: Bool = false
    @Published var createdBotName: String = ""
    
    // MARK: Real Trading State
    @Published var openPositions: [FuturesPosition] = []
    @Published var futuresBalance: Double = 0
    @Published var availableMargin: Double = 0
    @Published var isLoadingPositions: Bool = false
    @Published var lastTradeResult: FuturesOrderResult?
    @Published var tradeErrorMessage: String?
    @Published var isExecutingTrade: Bool = false
    @Published var fundingRate: FundingRate?
    
    // MARK: Dependencies
    private var cancellables = Set<AnyCancellable>()
    private let exchangeService: DerivativesExchangeServiceProtocol
    private let botService: DerivativesBotServiceProtocol
    private var positionRefreshTask: Task<Void, Never>?
    
    // MARK: Init
    init(
        exchangeService: DerivativesExchangeServiceProtocol = DerivativesExchangeService(),
        botService: DerivativesBotServiceProtocol = DerivativesBotService()
    ) {
        self.exchangeService = exchangeService
        self.botService = botService
        fetchExchanges()
        if let saved = UserDefaults.standard.array(forKey: favoritesKey) as? [String] {
            self.favoriteMarketSymbols = Set(saved)
        }
    }
    
    // MARK: Fetch available exchanges (e.g. Binance, KuCoin)
    func fetchExchanges() {
        exchangeService.getSupportedExchanges()
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { [weak self] exs in
                let supported = exs.filter { exchange in
                    guard let tradingExchange = TradingCapabilityMatrix.tradingExchange(forDerivativesExchangeId: exchange.id) else {
                        return false
                    }
                    return TradingCapabilityMatrix.profile(for: tradingExchange).supportsLiveDerivatives
                }
                // Defer state modifications to avoid "Modifying state during view update"
                Task { @MainActor [weak self] in
                    self?.availableDerivativesExchanges = supported
                    if self?.selectedExchange == nil {
                        // Default to Coinbase if available
                        self?.selectedExchange = supported.first(where: { $0.id == "coinbase" }) ?? supported.first
                    }
                }
            })
            .store(in: &cancellables)
    }
    
    // MARK: Fetch markets for selected exchange
    func fetchMarkets() {
        guard let ex = selectedExchange else { return }
        exchangeService.getMarkets(for: ex)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { [weak self] mks in
                // Defer state modifications to avoid "Modifying state during view update"
                Task { @MainActor [weak self] in
                    self?.marketsForSelectedExchange = mks
                    if self?.selectedMarket == nil {
                        self?.selectedMarket = mks.first
                    }
                }
            })
            .store(in: &cancellables)
    }
    
    func refreshMarkets() {
        fetchMarkets()
    }
    
    // MARK: Generate strategy via AI
    /// Generates a derivatives config. First tries to extract from the most recent AI chat
    /// response. If nothing found, populates sensible defaults based on selected market/exchange.
    func generateDerivativesConfig() {
        // Try to extract config from the latest AI chat message
        if let lastAIMessage = chatMessages.last(where: { $0.sender != "User" && $0.sender != "user" }) {
            if let config = parseDerivativesConfigFromText(lastAIMessage.text) {
                applyParsedConfig(config)
                return
            }
        }
        
        // Fallback: populate reasonable defaults based on current selection
        let marketSymbol = selectedMarket?.symbol ?? "BTC-PERP"
        let baseSymbol = marketSymbol.components(separatedBy: "-").first ?? "BTC"
        if botName.isEmpty { botName = "\(baseSymbol) Perp Grid Bot" }
        if positionSize.isEmpty { positionSize = "100" }
        if takeProfitPct.isEmpty { takeProfitPct = "1.0" }
        if stopLossPct.isEmpty { stopLossPct = "0.8" }
        if lowerPrice.isEmpty { lowerPrice = "30000" }
        if upperPrice.isEmpty { upperPrice = "35000" }
        if gridLevels.isEmpty { gridLevels = "20" }
        if orderVolume.isEmpty { orderVolume = "5" }
        entryCondition = entryCondition.isEmpty ? "RSI oversold < 30 then scale in" : entryCondition
    }
    
    /// Parse bot_config from AI text for derivatives
    private func parseDerivativesConfigFromText(_ text: String) -> AIBotConfig? {
        let tagPatterns = [
            ("<bot_config>", "</bot_config>"),
            ("<botconfig>", "</botconfig>"),
            ("<bot-config>", "</bot-config>")
        ]
        
        for (startTag, endTag) in tagPatterns {
            if let startRange = text.range(of: startTag, options: .caseInsensitive),
               let endRange = text.range(of: endTag, options: .caseInsensitive, range: startRange.upperBound..<text.endIndex) {
                let jsonString = String(text[startRange.upperBound..<endRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                if let jsonData = jsonString.data(using: .utf8),
                   let config = try? JSONDecoder().decode(AIBotConfig.self, from: jsonData) {
                    return config
                }
            }
        }
        return nil
    }
    
    /// Apply parsed AI bot config to the derivatives form fields
    private func applyParsedConfig(_ config: AIBotConfig) {
        if let name = config.name, !name.isEmpty {
            botName = name
        }
        if let leverage = config.leverage {
            self.leverage = min(max(leverage, 1), maxLeverage)
        }
        if let marginMode = config.marginMode {
            isIsolated = marginMode.lowercased() == "isolated"
        }
        if let direction = config.direction {
            positionSide = direction.lowercased() == "short" ? .short : .long
        }
        if let tp = config.takeProfit {
            takeProfitPct = tp
        }
        if let sl = config.stopLoss {
            stopLossPct = sl
        }
        if let size = config.baseOrderSize {
            positionSize = size
        }
        // Try to match the market
        if let market = config.market {
            let normalized = market.uppercased().replacingOccurrences(of: "-PERP", with: "")
            if let match = marketsForSelectedExchange.first(where: {
                $0.title.uppercased().contains(normalized) || $0.symbol.uppercased().contains(normalized)
            }) {
                selectedMarket = match
            }
        }
    }

    /// Load previous chat messages from backend or local cache
    func loadChatHistory() {
        // Initialize with a welcome message if empty
        if chatMessages.isEmpty {
            let welcomeMsg = ChatMessage(
                id: UUID(),
                sender: "AI",
                text: "Hello! I'm your AI trading assistant. Would you like to configure a DCA Bot, a Grid Bot, or something else?",
                isUser: false
            )
            chatMessages.append(welcomeMsg)
        }
    }

    // Task for current AI request (allows cancellation)
    private var currentAITask: Task<Void, Never>?
    
    /// System prompt for derivatives trading AI assistant
    private var derivativesSystemPrompt: String {
        buildDerivativesSystemPrompt()
    }
    
    /// Build dynamic derivatives system prompt with current whale/market data
    private func buildDerivativesSystemPrompt() -> String {
        var prompt = """
    You are CryptoSage AI, a professional derivatives trading assistant. You specialize in futures, perpetuals, and leveraged trading.

    YOUR PERSONALITY:
    - Direct and risk-conscious - derivatives are high risk
    - Educational - explain concepts clearly
    - Safety-focused - always emphasize risk management

    FORMATTING RULES (CRITICAL):
    - NO markdown (no *, #, _, etc.)
    - Use plain text, dashes for lists, CAPS for emphasis
    - Keep responses concise for mobile

    DERIVATIVES EXPERTISE:
    
    1. LEVERAGE TRADING FUNDAMENTALS
       - Perpetual Contracts: No expiry, track spot via funding rates
       - Futures: Fixed expiry, converge to spot at settlement
       - Liquidation math: 10x = ~9% adverse move, 20x = ~4.5%, 50x = ~1.8%
    
    2. LEVERAGE RECOMMENDATIONS
       - 1-3x: Conservative, suitable for beginners
       - 5-10x: Moderate risk, requires stop losses
       - 20x+: HIGH RISK, tight stops required
       - 50x+: EXTREME RISK, strongly discouraged
    
    3. MARGIN MODES
       - Isolated (RECOMMENDED): Risk limited to position margin
       - Cross: Uses entire account, higher liquidation risk
    
    4. RISK MANAGEMENT (CRITICAL)
       - ALWAYS use stop losses - no exceptions
       - Position size = (Account Risk %) / (Stop Loss %)
       - Never risk more than 2% per trade
       - Formula: Risk/(Entry - Stop) = Position Size
    
    5. ENTRY STRATEGIES
       - Wait for pullbacks to support/resistance
       - Use limit orders for better fills
       - Scale in: 50% now, 50% on confirmation
       - Check funding rates before entering
    
    6. EXIT RULES
       - Take partial profit at 5x risk (sell 20-30%)
       - Move stop to breakeven after partial profit
       - Trail stop below 10 SMA on daily chart
    
    7. MARKET CONDITIONS
       - Check BTC 10 SMA vs 20 SMA for overall trend
       - 10 above 20 = bullish bias for longs
       - 10 below 20 = cautious, reduced size
"""
        
        // Add REAL-TIME Smart Money / Whale data (crucial for derivatives)
        prompt += "\n\n=== CURRENT SMART MONEY DATA (REAL BLOCKCHAIN DATA) ==="
        prompt += "\nThis is LIVE on-chain data - whale moves often trigger liquidation cascades!"
        
        let whaleService = WhaleTrackingService.shared
        
        if let smi = whaleService.smartMoneyIndex {
            prompt += "\n\nSMART MONEY INDEX: \(smi.score)/100 (\(smi.trend.rawValue))"
            if smi.score >= 60 {
                prompt += "\n  SIGNAL: Institutions accumulating - BIAS LONG (but manage risk)"
            } else if smi.score <= 40 {
                prompt += "\n  SIGNAL: Institutions selling - BIAS SHORT or stay flat"
            } else {
                prompt += "\n  SIGNAL: Mixed positioning - no clear edge, reduce size"
            }
        }
        
        if let stats = whaleService.statistics {
            let flowAmt: String
            if abs(stats.netExchangeFlow) >= 1_000_000_000 {
                flowAmt = String(format: "$%.1fB", abs(stats.netExchangeFlow) / 1_000_000_000)
            } else if abs(stats.netExchangeFlow) >= 1_000_000 {
                flowAmt = String(format: "$%.0fM", abs(stats.netExchangeFlow) / 1_000_000)
            } else {
                flowAmt = "minimal"
            }
            
            prompt += "\n\nEXCHANGE FLOW: \(flowAmt) net \(stats.netExchangeFlow < 0 ? "OUTFLOW" : "INFLOW")"
            if stats.netExchangeFlow < -100_000_000 {
                prompt += "\n  SIGNAL: STRONG outflow = accumulation = bullish for longs"
            } else if stats.netExchangeFlow > 100_000_000 {
                prompt += "\n  WARNING: STRONG inflow = potential selling = bearish, tighten stops"
            }
        }
        
        // Market Regime
        let marketVM = MarketViewModel.shared
        if let btc = marketVM.allCoins.first(where: { $0.symbol.uppercased() == "BTC" }),
           btc.sparklineIn7d.count >= 20 {
            let sparkline = btc.sparklineIn7d
            let regime = MarketRegimeDetector.detectRegime(closes: sparkline)
            prompt += "\n\nMARKET REGIME: \(regime.regime.displayName.uppercased())"
            
            switch regime.regime {
            case .highVolatility:
                prompt += "\n  WARNING: High volatility = wider stops required, reduce leverage!"
            case .trendingUp:
                prompt += "\n  CONTEXT: Trending up - favor longs with pullback entries"
            case .trendingDown:
                prompt += "\n  CONTEXT: Trending down - favor shorts or stay flat"
            case .ranging:
                prompt += "\n  CONTEXT: Ranging - trade the range, avoid breakout traps"
            case .breakoutPotential:
                prompt += "\n  ALERT: Breakout imminent - be ready for big move either direction"
            case .lowVolatility:
                prompt += "\n  CONTEXT: Low volatility - expect volatility expansion soon"
            }
        }
        
        prompt += """


    SAFETY WARNINGS:
    - 80%+ of retail traders lose money on derivatives
    - Never trade with money you cannot afford to lose
    - Avoid high-impact news events
    
    When generating a config, wrap it in tags (user won't see these):
    <bot_config>{"botType":"derivatives","name":"ETH Long","exchange":"Binance Futures","market":"ETH-PERP","leverage":5,"marginMode":"isolated","direction":"Long","takeProfit":"3","stopLoss":"2"}</bot_config>

    Then give a friendly summary with risk warnings.
"""
        return prompt
    }
    
    /// Timeout duration for AI requests (30 seconds)
    private let aiRequestTimeoutSeconds: UInt64 = 30
    
    /// Custom error type for AI request timeout
    private struct AIRequestTimeoutError: Error {
        let message = "Request timed out. Please try again."
    }
    
    /// Send a new message via AI chat - connected to real AIService
    func sendChatMessage(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        // Rate limit check (abuse protection)
        if SubscriptionManager.shared.isRateLimited {
            let wait = SubscriptionManager.shared.rateLimitSecondsRemaining
            chatMessages.append(ChatMessage(id: UUID(), sender: "System", text: "Slow down — try again in \(wait) seconds.", isUser: false))
            return
        }
        
        // Append user message to local history
        let outgoing = ChatMessage(id: UUID(), sender: "User", text: text, isUser: true)
        chatMessages.append(outgoing)
        
        // Cancel any existing request
        currentAITask?.cancel()
        currentAITask = nil
        
        // Show typing indicator with animation
        withAnimation(.easeOut(duration: 0.2)) {
            isTyping = true
        }
        
        // Create placeholder for streaming response
        let placeholderId = UUID()
        let placeholder = ChatMessage(id: placeholderId, sender: "AI", text: "", isUser: false)
        chatMessages.append(placeholder)
        
        // Call the real AI service with streaming and timeout
        currentAITask = Task { @MainActor in
            do {
                // Check for cancellation early
                try Task.checkCancellation()
                
                // Stream the response with timeout
                try await withThrowingTaskGroup(of: Void.self) { group in
                    // Task 1: The actual AI streaming request
                    group.addTask { @MainActor in
                        _ = try await AIService.shared.sendMessageStreaming(
                            text,
                            systemPrompt: self.derivativesSystemPrompt,
                            usePremiumModel: false,
                            includeTools: false
                        ) { [weak self] streamedText in
                            guard let self = self else { return }
                            
                            // Hide typing indicator once text starts flowing
                            if self.isTyping && !streamedText.isEmpty {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    self.isTyping = false
                                }
                            }
                            
                            // Update placeholder with streamed content
                            if let index = self.chatMessages.firstIndex(where: { $0.id == placeholderId }) {
                                self.chatMessages[index] = ChatMessage(
                                    id: placeholderId,
                                    sender: "AI",
                                    text: streamedText,
                                    isUser: false
                                )
                            }
                        }
                    }
                    
                    // Task 2: Timeout watchdog (30 seconds)
                    group.addTask {
                        try await Task.sleep(nanoseconds: self.aiRequestTimeoutSeconds * 1_000_000_000)
                        throw AIRequestTimeoutError()
                    }
                    
                    // Wait for the first task to complete
                    do {
                        try await group.next()
                        group.cancelAll()
                    } catch {
                        group.cancelAll()
                        throw error
                    }
                }
                
                withAnimation(.easeOut(duration: 0.15)) {
                    self.isTyping = false
                }
                self.currentAITask = nil
                
                // Count bot chat message against daily AI limit
                SubscriptionManager.shared.recordAIPromptUsage(modelUsed: "gpt-4o-mini")
                
            } catch is CancellationError {
                // Task was cancelled - silently clean up
                if let index = self.chatMessages.firstIndex(where: { $0.id == placeholderId }),
                   self.chatMessages[index].text.isEmpty {
                    self.chatMessages.remove(at: index)
                }
                withAnimation(.easeOut(duration: 0.15)) {
                    self.isTyping = false
                }
                self.currentAITask = nil
                
            } catch let error as AIRequestTimeoutError {
                // Timeout error
                withAnimation(.easeOut(duration: 0.15)) {
                    self.isTyping = false
                }
                self.currentAITask = nil
                if let index = self.chatMessages.firstIndex(where: { $0.id == placeholderId }) {
                    self.chatMessages[index] = ChatMessage(
                        id: placeholderId,
                        sender: "AI",
                        text: error.message,
                        isUser: false
                    )
                }
                
            } catch {
                withAnimation(.easeOut(duration: 0.15)) {
                    self.isTyping = false
                }
                self.currentAITask = nil
                // Update placeholder with error message
                if let index = self.chatMessages.firstIndex(where: { $0.id == placeholderId }) {
                    self.chatMessages[index] = ChatMessage(
                        id: placeholderId,
                        sender: "AI",
                        text: "Sorry, I encountered an error: \(error.localizedDescription). Please check your API key in Settings.",
                        isUser: false
                    )
                }
            }
        }
    }
    
    /// Clear chat history and cancel any ongoing request
    func clearChat() {
        currentAITask?.cancel()
        currentAITask = nil
        withAnimation(.easeOut(duration: 0.2)) {
            isTyping = false
        }
        chatMessages.removeAll()
        loadChatHistory() // Reload welcome message
    }
    
    // MARK: Start/Stop bot
    func toggleDerivativesBot() {
        if isRunning {
            stopBot()
        } else {
            startBot()
        }
    }

    /// Starts the derivatives bot using a provided configuration.
    func startBot(with config: DerivativesBotConfig) {
        // Update view model state from the passed-in config
        self.selectedExchange = config.exchange
        self.selectedMarket = config.market
        self.leverage = config.leverage
        self.isIsolated = config.isIsolated
        // Call the existing startBot() logic
        startBot()
    }

    private func startBot() {
        guard let ex = selectedExchange, let mk = selectedMarket else { return }
        
        // SAFETY: Force paper trading when live trading is disabled at app config level
        // This ensures regulatory/legal safety while keeping bot features functional
        if !AppConfig.liveTradingEnabled && !PaperTradingManager.isEnabled {
            PaperTradingManager.shared.enablePaperTrading()
        }
        
        // Check if paper trading mode is enabled
        if PaperTradingManager.isEnabled || !AppConfig.liveTradingEnabled {
            if positionSide == .short {
                tradeErrorMessage = "Paper derivatives shorting is not supported yet. Switch to live derivatives mode for short positions."
                return
            }
            
            // Create paper derivatives bot
            let bot = PaperBotManager.shared.createDerivativesBot(
                name: botName.isEmpty ? "Derivatives Bot" : botName,
                exchange: ex.name,
                market: mk.title,
                leverage: leverage,
                marginMode: isIsolated ? "isolated" : "cross",
                direction: positionSide.rawValue,
                takeProfit: takeProfitPct.isEmpty ? nil : takeProfitPct,
                stopLoss: stopLossPct.isEmpty ? nil : stopLossPct,
                additionalConfig: [
                    "strategyType": strategyType.rawValue,
                    "positionSize": positionSize,
                    "trailingStop": String(trailingStop),
                    "entryCondition": entryCondition
                ]
            )
            
            currentPaperBotId = bot.id
            createdBotName = bot.name
            
            // Start the paper bot
            PaperBotManager.shared.startBot(id: bot.id)
            
            isRunning = true
            showBotCreatedAlert = true
            
            #if DEBUG
            print("[Paper Trading] Derivatives Bot created and started: \(bot.name), ID: \(bot.id)")
            #endif
        } else {
            // Live mode - use existing API flow
            let config = DerivativesBotConfig(exchange: ex,
                                              market: mk,
                                              leverage: leverage,
                                              isIsolated: isIsolated)
            botService.startBot(with: config)
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { completion in
                    if case .failure(let err) = completion {
                        #if DEBUG
                        print("Failed to start derivatives bot: \(err)")
                        #endif
                    }
                }, receiveValue: { [weak self] in
                    self?.isRunning = true
                })
                .store(in: &cancellables)
        }
    }
    
    private func stopBot() {
        // Check if paper trading mode is enabled and we have a paper bot
        if PaperTradingManager.isEnabled, let botId = currentPaperBotId {
            // Stop the paper bot
            PaperBotManager.shared.stopBot(id: botId)
            currentPaperBotId = nil
            isRunning = false
            
            #if DEBUG
            print("[Paper Trading] Derivatives Bot stopped")
            #endif
        } else {
            // Live mode - use existing API flow
            botService.stopBot()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] completion in
                    self?.isRunning = false
                } receiveValue: { }
                .store(in: &cancellables)
        }
    }
    
    var strategySummary: String {
        "Name: \(botName) | Type: \(strategyType.rawValue) | Side: \(positionSide.rawValue) | Size: \(positionSize) | TP: \(takeProfitPct)% | SL: \(stopLossPct)%"
    }

    func toggleFavorite(market: Market) {
        if favoriteMarketSymbols.contains(market.symbol) {
            favoriteMarketSymbols.remove(market.symbol)
        } else {
            favoriteMarketSymbols.insert(market.symbol)
        }
        UserDefaults.standard.set(Array(favoriteMarketSymbols), forKey: favoritesKey)
    }

    func isFavorite(_ market: Market) -> Bool {
        favoriteMarketSymbols.contains(market.symbol)
    }

    var isReadyToStart: Bool {
        selectedExchange != nil && selectedMarket != nil
    }
    
    // MARK: - Real Trading Methods
    
    private var selectedTradingExchange: TradingExchange? {
        TradingCapabilityMatrix.tradingExchange(forDerivativesExchangeId: selectedExchange?.id)
    }
    
    private var selectedFuturesExchange: FuturesExchange? {
        switch selectedExchange?.id.lowercased() {
        case "binance":
            return .binanceFutures
        case "kucoin":
            return .kucoinFutures
        case "bybit":
            return .bybit
        default:
            return nil
        }
    }
    
    /// Check if we should use real trading (not paper trading)
    var isRealTradingMode: Bool {
        guard !PaperTradingManager.isEnabled,
              AppConfig.liveTradingEnabled,
              let exchange = selectedTradingExchange else {
            return false
        }
        let profile = TradingCapabilityMatrix.profile(for: exchange)
        guard profile.supportsLiveDerivatives else { return false }
        return TradingCredentialsManager.shared.hasCredentials(for: exchange)
    }
    
    /// Fetch open futures positions
    func fetchPositions() async {
        guard let exchangeId = selectedExchange?.id else { return }
        guard isRealTradingMode else { return }
        
        await MainActor.run { isLoadingPositions = true }
        
        do {
            let positions = try await botService.fetchPositions(exchangeId: exchangeId)
            await MainActor.run {
                self.openPositions = positions
                self.isLoadingPositions = false
            }
        } catch {
            await MainActor.run {
                self.isLoadingPositions = false
                #if DEBUG
                print("[DerivativesBotViewModel] Failed to fetch positions: \(error)")
                #endif
            }
        }
    }
    
    /// Fetch futures account balance
    func fetchFuturesBalance() async {
        guard let exchangeId = selectedExchange?.id else { return }
        guard isRealTradingMode else { return }
        
        do {
            if exchangeId.lowercased() == "coinbase" {
                let balances = try await CoinbaseAdvancedTradeService.shared.getPerpetualBalances()
                if let collateral = balances.portfolioBalances.first(where: { $0.asset.uppercased() == "USDC" }) {
                    await MainActor.run {
                        self.futuresBalance = collateral.quantityValue
                        self.availableMargin = collateral.available
                    }
                }
                return
            }
            
            if let futuresExchange = selectedFuturesExchange {
                await FuturesTradingExecutionService.shared.setActiveExchange(futuresExchange)
            }
            let balances = try await FuturesTradingExecutionService.shared.fetchBalances()
            if let usdtBalance = balances.first(where: { $0.asset.uppercased() == "USDT" }) {
                await MainActor.run {
                    self.futuresBalance = usdtBalance.walletBalance
                    self.availableMargin = usdtBalance.availableBalance
                }
            }
        } catch {
            #if DEBUG
            print("[DerivativesBotViewModel] Failed to fetch balance: \(error)")
            #endif
        }
    }
    
    /// Fetch funding rate for selected market
    func fetchFundingRate() async {
        guard let exchangeId = selectedExchange?.id else { return }
        guard let market = selectedMarket else { return }
        if exchangeId.lowercased() == "coinbase" {
            await MainActor.run { self.fundingRate = nil }
            return
        }
        
        do {
            if let futuresExchange = selectedFuturesExchange {
                await FuturesTradingExecutionService.shared.setActiveExchange(futuresExchange)
            }
            let rate = try await FuturesTradingExecutionService.shared.fetchFundingRate(symbol: market.symbol)
            await MainActor.run {
                self.fundingRate = rate
            }
        } catch {
            #if DEBUG
            print("[DerivativesBotViewModel] Failed to fetch funding rate: \(error)")
            #endif
        }
    }
    
    /// Execute a real futures trade
    func executeFuturesTrade(side: TradeSide, quantity: Double) async {
        guard let exchangeId = selectedExchange?.id else {
            await MainActor.run { tradeErrorMessage = "No exchange selected" }
            return
        }
        guard let market = selectedMarket else {
            await MainActor.run { tradeErrorMessage = "No market selected" }
            return
        }
        
        // SAFETY: Block live trading when disabled at app config level
        guard AppConfig.liveTradingEnabled else {
            await MainActor.run { tradeErrorMessage = AppConfig.liveTradingDisabledMessage }
            return
        }
        guard TradingRiskAcknowledgmentManager.shared.canTrade else {
            await MainActor.run {
                tradeErrorMessage = "Please accept Terms and acknowledge trading risks before live derivatives trading."
            }
            return
        }
        
        guard isRealTradingMode else {
            await MainActor.run { tradeErrorMessage = "Paper trading mode is enabled" }
            return
        }
        
        await MainActor.run {
            isExecutingTrade = true
            tradeErrorMessage = nil
        }
        
        do {
            // Configure leverage and margin mode first
            let marginMode: MarginMode = isIsolated ? .isolated : .cross
            _ = try await botService.configureLeverage(
                exchangeId: exchangeId,
                symbol: market.symbol,
                leverage: leverage,
                marginMode: marginMode
            )
            
            // Determine position side based on direction (convert local enum to global PositionSide)
            let futuresPositionSide: CryptoSage.PositionSide = self.positionSide == .long ? .long : .short
            
            // Submit the order
            let result = try await botService.submitOrder(
                exchangeId: exchangeId,
                symbol: market.symbol,
                side: side,
                quantity: quantity,
                leverage: leverage,
                positionSide: futuresPositionSide
            )
            
            await MainActor.run {
                self.lastTradeResult = result
                self.isExecutingTrade = false
                
                if result.success {
                    // Refresh positions after successful trade
                    Task { await self.fetchPositions() }
                    
                    #if os(iOS)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    #endif
                } else {
                    self.tradeErrorMessage = result.errorMessage
                    #if os(iOS)
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    #endif
                }
            }
        } catch {
            await MainActor.run {
                self.isExecutingTrade = false
                self.tradeErrorMessage = error.localizedDescription
                #if os(iOS)
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                #endif
            }
        }
    }
    
    /// Close an open position
    func closePosition(symbol: String) async {
        guard let exchangeId = selectedExchange?.id else { return }
        guard isRealTradingMode else { return }
        
        await MainActor.run { isExecutingTrade = true }
        
        do {
            let result = try await botService.closePosition(exchangeId: exchangeId, symbol: symbol)
            
            await MainActor.run {
                self.lastTradeResult = result
                self.isExecutingTrade = false
                
                if result.success {
                    // Remove position from list
                    self.openPositions.removeAll { $0.symbol == symbol }
                    
                    #if os(iOS)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    #endif
                } else {
                    self.tradeErrorMessage = result.errorMessage
                }
            }
        } catch {
            await MainActor.run {
                self.isExecutingTrade = false
                self.tradeErrorMessage = error.localizedDescription
            }
        }
    }
    
    /// Start periodic position refresh
    func startPositionRefresh() {
        guard isRealTradingMode else { return }
        
        positionRefreshTask?.cancel()
        positionRefreshTask = Task {
            while !Task.isCancelled {
                await fetchPositions()
                await fetchFuturesBalance()
                if selectedMarket != nil {
                    await fetchFundingRate()
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000) // Refresh every 5 seconds
            }
        }
    }
    
    /// Stop position refresh
    func stopPositionRefresh() {
        positionRefreshTask?.cancel()
        positionRefreshTask = nil
    }
    
    /// Test connection to Binance Futures
    func testFuturesConnection() async -> Bool {
        guard let exchangeId = selectedExchange?.id else { return false }
        do {
            return try await botService.testConnection(exchangeId: exchangeId)
        } catch {
            return false
        }
    }
}

// MARK: - Supporting Protocols & Models

protocol DerivativesExchangeServiceProtocol {
    func getSupportedExchanges() -> AnyPublisher<[Exchange], Error>
    func getMarkets(for exchange: Exchange) -> AnyPublisher<[Market], Error>
}

class DerivativesExchangeService: DerivativesExchangeServiceProtocol {
    func getSupportedExchanges() -> AnyPublisher<[Exchange], Error> {
        // Direct API integration - no backend server required
        // All exchanges connect directly via their REST APIs
        Just([Exchange(name: "Coinbase INTX", id: "coinbase"),       // US users - perpetual-style futures via INTX
              Exchange(name: "Binance Futures", id: "binance"),     // Non-US - USDT perpetuals
              Exchange(name: "KuCoin Futures", id: "kucoin"),       // Non-US - USDT perpetuals
              Exchange(name: "Bybit", id: "bybit")])                // Non-US - USDT perpetuals
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
    
    func getMarkets(for exchange: Exchange) -> AnyPublisher<[Market], Error> {
        // Live fetch for exchange-specific perpetuals; fallback to static list.
        switch exchange.id.lowercased() {
        case "coinbase":
            return fetchCoinbasePerpMarkets()
                .catch { _ in Just(self.staticMarkets(for: exchange)) }
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        case "binance":
            return fetchBinancePerpMarkets()
                .catch { _ in Just(self.staticMarkets(for: exchange)) }
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        default:
            return Just(staticMarkets(for: exchange))
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        }
    }
    
    // Static fallback markets per exchange (USDT perpetual naming)
    private func staticMarkets(for exchange: Exchange) -> [Market] {
        if exchange.id.lowercased() == "coinbase" {
            return [
                Market(symbol: "BTC-PERP-INTX", title: "BTC Perp (INTX)"),
                Market(symbol: "ETH-PERP-INTX", title: "ETH Perp (INTX)")
            ]
        }
        
        let common: [Market] = [
            Market(symbol: "BTCUSDT", title: "BTC/USDT Perp"),
            Market(symbol: "ETHUSDT", title: "ETH/USDT Perp"),
            Market(symbol: "SOLUSDT", title: "SOL/USDT Perp"),
            Market(symbol: "ADAUSDT", title: "ADA/USDT Perp"),
            Market(symbol: "XRPUSDT", title: "XRP/USDT Perp"),
            Market(symbol: "DOGEUSDT", title: "DOGE/USDT Perp"),
            Market(symbol: "LTCUSDT", title: "LTC/USDT Perp"),
            Market(symbol: "AVAXUSDT", title: "AVAX/USDT Perp"),
            Market(symbol: "LINKUSDT", title: "LINK/USDT Perp"),
            Market(symbol: "MATICUSDT", title: "MATIC/USDT Perp"),
            Market(symbol: "DOTUSDT", title: "DOT/USDT Perp"),
            Market(symbol: "OPUSDT", title: "OP/USDT Perp"),
            Market(symbol: "ARBUSDT", title: "ARB/USDT Perp"),
            Market(symbol: "SHIBUSDT", title: "SHIB/USDT Perp")
        ]
        if exchange.id.lowercased() == "binance" {
            return common + [Market(symbol: "BNBUSDT", title: "BNB/USDT Perp")]
        }
        return common
    }

    // Fetch Binance Futures exchange info and map to perpetual USDT markets
    private func fetchBinancePerpMarkets() -> AnyPublisher<[Market], Error> {
        guard let url = URL(string: "https://fapi.binance.com/fapi/v1/exchangeInfo") else {
            return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
        }
        return URLSession.shared.dataTaskPublisher(for: url)
            .tryMap { output -> [Market] in
                let data = output.data
                // Minimal decoding for fields we need
                struct ExchangeInfo: Decodable { let symbols: [Symbol] }
                struct Symbol: Decodable {
                    let symbol: String
                    let contractType: String?
                    let quoteAsset: String?
                    let status: String?
                    let pair: String?
                }
                let info = try JSONDecoder().decode(ExchangeInfo.self, from: data)
                let filtered = info.symbols.filter { s in
                    (s.contractType ?? "") == "PERPETUAL" && (s.quoteAsset ?? "") == "USDT" && (s.status ?? "TRADING") == "TRADING"
                }
                let mapped: [Market] = filtered.map { s in
                    let base = s.pair?.replacingOccurrences(of: "USDT", with: "") ?? s.symbol.replacingOccurrences(of: "USDT", with: "")
                    return Market(symbol: s.symbol, title: "\(base)/USDT Perp")
                }
                // Sort alphabetically for a nicer UX
                return mapped.sorted { $0.title < $1.title }
            }
            .eraseToAnyPublisher()
    }
    
    // Fetch Coinbase INTX products and map to derivatives markets.
    private func fetchCoinbasePerpMarkets() -> AnyPublisher<[Market], Error> {
        Future<[Market], Error> { promise in
            Task {
                do {
                    let products = try await CoinbaseAdvancedTradeService.shared.getPerpetualProducts()
                    let mapped = products
                        .filter { $0.status.uppercased() == "ONLINE" }
                        .map { product in
                            let title = product.productId
                                .replacingOccurrences(of: "-PERP-INTX", with: " Perp (INTX)")
                                .replacingOccurrences(of: "-PERP", with: " Perp")
                            return Market(symbol: product.productId, title: title)
                        }
                        .sorted { $0.title < $1.title }
                    promise(.success(mapped))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }
}

protocol DerivativesBotServiceProtocol {
    func startBot(with config: DerivativesBotConfig) -> AnyPublisher<Void, Error>
    func stopBot() -> AnyPublisher<Void, Error>
    func configureLeverage(exchangeId: String, symbol: String, leverage: Int, marginMode: MarginMode) async throws -> Bool
    func submitOrder(exchangeId: String, symbol: String, side: TradeSide, quantity: Double, leverage: Int, positionSide: PositionSide) async throws -> FuturesOrderResult
    func fetchPositions(exchangeId: String) async throws -> [FuturesPosition]
    func closePosition(exchangeId: String, symbol: String) async throws -> FuturesOrderResult
    func testConnection(exchangeId: String) async throws -> Bool
}

class DerivativesBotService: DerivativesBotServiceProtocol {
    private func futuresExchange(for exchangeId: String) -> FuturesExchange? {
        switch exchangeId.lowercased() {
        case "binance":
            return .binanceFutures
        case "kucoin":
            return .kucoinFutures
        case "bybit":
            return .bybit
        default:
            return nil
        }
    }
    
    private func isCoinbase(_ exchangeId: String) -> Bool {
        exchangeId.lowercased() == "coinbase"
    }
    
    private func configureFuturesBackend(for exchangeId: String) async throws {
        guard let futuresExchange = futuresExchange(for: exchangeId) else {
            throw TradingError.apiError(message: "Unsupported derivatives exchange: \(exchangeId)")
        }
        await FuturesTradingExecutionService.shared.setActiveExchange(futuresExchange)
    }
    
    private func mapCoinbaseOrderResult(_ response: CoinbaseOrderResponse) -> FuturesOrderResult {
        FuturesOrderResult(
            success: response.success,
            orderId: response.successResponse?.orderId,
            clientOrderId: response.successResponse?.clientOrderId,
            status: .new,
            errorMessage: response.success
                ? nil
                : (response.errorResponse?.message ?? response.errorResponse?.errorDetails ?? "Coinbase order rejected"),
            exchange: "Coinbase INTX"
        )
    }
    
    private func mapCoinbasePosition(_ position: CoinbasePerpPosition) -> FuturesPosition {
        let side: CryptoSage.PositionSide = {
            if position.netSize > 0 { return .long }
            if position.netSize < 0 { return .short }
            return .both
        }()
        let mark = position.markPriceValue
        let leverage = max(1, Int(position.leverageValue.rounded()))
        return FuturesPosition(
            id: position.productId,
            symbol: position.productId,
            positionSide: side,
            positionAmount: position.netSize,
            entryPrice: Double(position.vwap ?? "") ?? mark,
            markPrice: mark,
            unrealizedPnL: position.unrealizedPnlValue,
            leverage: leverage,
            marginType: .cross,
            liquidationPrice: position.liquidationPriceValue ?? 0,
            notionalValue: abs(position.netSize) * mark,
            isolatedMargin: nil
        )
    }
    
    /// Configure leverage and margin mode for a symbol before trading
    func configureLeverage(exchangeId: String, symbol: String, leverage: Int, marginMode: MarginMode) async throws -> Bool {
        if isCoinbase(exchangeId) {
            // Coinbase INTX accepts leverage per order request.
            return true
        }
        
        try await configureFuturesBackend(for: exchangeId)
        // Set margin type first (isolated or cross)
        _ = try await FuturesTradingExecutionService.shared.setMarginType(symbol: symbol, marginType: marginMode)
        
        // Then set leverage
        return try await FuturesTradingExecutionService.shared.setLeverage(symbol: symbol, leverage: leverage)
    }
    
    /// Submit a futures market order
    func submitOrder(exchangeId: String, symbol: String, side: TradeSide, quantity: Double, leverage: Int, positionSide: PositionSide = .both) async throws -> FuturesOrderResult {
        if isCoinbase(exchangeId) {
            let response = try await CoinbaseAdvancedTradeService.shared.placePerpMarketOrder(
                productId: symbol,
                side: side.rawValue,
                size: quantity,
                leverage: Double(leverage)
            )
            return mapCoinbaseOrderResult(response)
        }
        
        try await configureFuturesBackend(for: exchangeId)
        // Configure leverage before placing order
        _ = try await FuturesTradingExecutionService.shared.setLeverage(symbol: symbol, leverage: leverage)
        
        // Submit the order
        return try await FuturesTradingExecutionService.shared.submitMarketOrder(
            symbol: symbol,
            side: side,
            quantity: quantity,
            positionSide: positionSide,
            reduceOnly: false
        )
    }
    
    /// Fetch all open positions
    func fetchPositions(exchangeId: String) async throws -> [FuturesPosition] {
        if isCoinbase(exchangeId) {
            let portfolio = try await CoinbaseAdvancedTradeService.shared.getPerpetualPortfolio()
            let positions = try await CoinbaseAdvancedTradeService.shared.getPerpetualPositions(
                portfolioUuid: portfolio.portfolioUuid
            )
            return positions.map(mapCoinbasePosition)
        }
        
        try await configureFuturesBackend(for: exchangeId)
        return try await FuturesTradingExecutionService.shared.fetchPositions()
    }
    
    /// Close a position
    func closePosition(exchangeId: String, symbol: String) async throws -> FuturesOrderResult {
        if isCoinbase(exchangeId) {
            let response = try await CoinbaseAdvancedTradeService.shared.closePerpPosition(productId: symbol)
            return mapCoinbaseOrderResult(response)
        }
        
        try await configureFuturesBackend(for: exchangeId)
        return try await FuturesTradingExecutionService.shared.closePosition(symbol: symbol)
    }
    
    func testConnection(exchangeId: String) async throws -> Bool {
        if isCoinbase(exchangeId) {
            return try await CoinbaseAdvancedTradeService.shared.testConnection()
        }
        
        try await configureFuturesBackend(for: exchangeId)
        return try await FuturesTradingExecutionService.shared.testConnection()
    }
    
    func startBot(with config: DerivativesBotConfig) -> AnyPublisher<Void, Error> {
        // For automated bot trading, configure the symbol and start monitoring
        // The actual order execution happens through submitOrder()
        return Future<Void, Error> { promise in
            Task {
                do {
                    // Configure leverage and margin mode
                    let marginMode: MarginMode = config.isIsolated ? .isolated : .cross
                    _ = try await self.configureLeverage(
                        exchangeId: config.exchange.id,
                        symbol: config.market.symbol,
                        leverage: config.leverage,
                        marginMode: marginMode
                    )
                    promise(.success(()))
                } catch {
                    promise(.failure(error))
                }
            }
        }.eraseToAnyPublisher()
    }
    
    func stopBot() -> AnyPublisher<Void, Error> {
        // Stop automated trading - positions remain open unless explicitly closed
        return Just(()).setFailureType(to: Error.self).eraseToAnyPublisher()
    }
}

// Data models
struct Exchange: Identifiable, Hashable {
    let name: String
    let id: String
}

struct Market: Identifiable, Hashable {
    let symbol: String
    let title: String
    var id: String { symbol }
}

struct DerivativesBotConfig {
    let exchange: Exchange
    let market: Market
    let leverage: Int
    let isIsolated: Bool
}

