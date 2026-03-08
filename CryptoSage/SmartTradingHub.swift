//
//  SmartTradingHub.swift
//  CryptoSage
//
//  Unified Smart Trading Hub that provides a central interface for all trading activities.
//  Features context-aware AI that adapts to different trading modes:
//  - Spot Trading (regular buy/sell)
//  - Algorithmic Trading (DCA, Grid, Signal bots)
//  - Leverage/Derivatives (futures, perpetuals)
//  - Prediction Markets (Polymarket, Kalshi)
//
//  CryptoSage AI can help with any trading type and seamlessly switches contexts.
//

import SwiftUI

// MARK: - Trading Mode

/// Different trading modes available in the Smart Trading Hub
enum TradingHubMode: String, CaseIterable, Identifiable {
    case assistant = "Assistant"
    case spot = "Spot"
    case bots = "Bots"
    case strategies = "Strategies"
    case derivatives = "Derivatives"
    case predictions = "Predictions"
    
    var id: String { rawValue }
    
    /// All modes available - filtering is done at the UI level based on subscription
    static var allModes: [TradingHubMode] {
        allCases
    }
    
    /// Whether this mode is available in the current app configuration
    /// In developer mode, all features are available
    /// For regular users, bots/derivatives/strategies require Premium subscription
    @MainActor var isAvailable: Bool {
        // Developer mode gets everything
        if SubscriptionManager.shared.isDeveloperMode {
            return true
        }

        switch self {
        case .assistant, .spot, .predictions:
            return true
        case .bots, .derivatives, .strategies:
            // Available for Premium subscribers or if paper trading is enabled
            return SubscriptionManager.shared.hasAccess(to: .tradingBots) || PaperTradingManager.isEnabled
        }
    }
    
    var displayName: String {
        switch self {
        case .assistant: return "AI Assistant"
        case .spot: return "Spot Trading"
        case .bots: return "Trading Bots"
        case .strategies: return "Algo Strategies"
        case .derivatives: return "Derivatives"
        case .predictions: return "Predictions"
        }
    }
    
    var icon: String {
        switch self {
        case .assistant: return "sparkles"
        case .spot: return "arrow.left.arrow.right"
        case .bots: return "cpu"
        case .strategies: return "function"
        case .derivatives: return "chart.line.uptrend.xyaxis"
        case .predictions: return "chart.bar.xaxis.ascending"
        }
    }
    
    var description: String {
        switch self {
        case .assistant: return "Ask CryptoSage AI anything about trading"
        case .spot: return "Buy and sell crypto directly"
        case .bots: return "Automated DCA, Grid, Signal bots"
        case .strategies: return "Build and backtest trading algorithms"
        case .derivatives: return "Leverage and futures trading"
        case .predictions: return "Polymarket & Kalshi markets"
        }
    }
    
    var color: Color {
        switch self {
        case .assistant: return BrandColors.goldBase
        case .spot: return .blue
        case .bots: return .purple
        case .strategies: return .green
        case .derivatives: return .orange
        case .predictions: return .cyan
        }
    }
    
    var aiContextPrefix: String {
        switch self {
        case .assistant:
            return "general trading assistant"
        case .spot:
            return "spot trading specialist"
        case .bots:
            return "algorithmic trading and bot configuration specialist"
        case .strategies:
            return "algorithmic trading strategy specialist who helps build, backtest, and optimize trading strategies"
        case .derivatives:
            return "derivatives and leverage trading specialist"
        case .predictions:
            return "prediction market analyst"
        }
    }
}

// MARK: - Smart Trading Hub View Model

// MARK: - Recent Activity Item

struct RecentActivityItem: Identifiable {
    let id = UUID()
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let timestamp: Date
    let type: ActivityType
    
    enum ActivityType {
        case trade
        case botAction
        case alert
        case prediction
    }
}

/// Bot type for quick creation cards
enum QuickBotType: String, CaseIterable, Identifiable {
    case dca = "DCA Bot"
    case grid = "Grid Bot"
    case signal = "Signal Bot"
    case prediction = "Prediction"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .dca: return "repeat.circle.fill"
        case .grid: return "square.grid.3x3.fill"
        case .signal: return "bolt.circle.fill"
        case .prediction: return "chart.bar.xaxis.ascending"
        }
    }
    
    var color: Color {
        switch self {
        case .dca: return .blue
        case .grid: return .purple
        case .signal: return .orange
        case .prediction: return .cyan
        }
    }
    
    var subtitle: String {
        switch self {
        case .dca: return "Dollar-cost average"
        case .grid: return "Range trading"
        case .signal: return "Technical signals"
        case .prediction: return "Event markets"
        }
    }
    
    var botCreationMode: TradingBotView.BotCreationMode? {
        switch self {
        case .dca: return .dcaBot
        case .grid: return .gridBot
        case .signal: return .signalBot
        case .prediction: return nil
        }
    }
}

// MARK: - Premium AI Advisor Card (Reusable Component)

/// A premium AI advisor card with animated glow effects that can be used across all trading sections
struct PremiumAIAdvisorCard: View {
    let context: AIHelperContext
    let title: String
    let subtitle: String
    let onTap: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var glowAmount: Double = 0.6
    @State private var borderPhase: Double = 0
    
    private var isDark: Bool { colorScheme == .dark }
    
    // LIGHT MODE FIX: Adaptive gold gradient - deeper amber in light mode, bright gold in dark
    private var chipGoldGradient: LinearGradient {
        isDark
            ? LinearGradient(colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange], startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [Color(red: 0.78, green: 0.60, blue: 0.10), Color(red: 0.65, green: 0.45, blue: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    var body: some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            onTap()
        } label: {
            HStack(spacing: 12) {
                // Premium AI icon with layered glow effect
                ZStack {
                    // Outer animated glow ring - LIGHT MODE FIX: Reduced intensity
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    BrandColors.goldLight.opacity((isDark ? 0.35 : 0.18) * glowAmount),
                                    BrandColors.goldBase.opacity((isDark ? 0.15 : 0.06) * glowAmount),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 8,
                                endRadius: 28
                            )
                        )
                        .frame(width: 50, height: 50)
                    
                    // Inner glow layer - LIGHT MODE FIX: Use adaptive gold colors
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: isDark
                                    ? [BrandColors.goldLight.opacity(0.9), BrandColors.goldBase, BrandColors.goldDark.opacity(0.8)]
                                    : [Color(red: 0.88, green: 0.72, blue: 0.22), Color(red: 0.78, green: 0.60, blue: 0.12), Color(red: 0.68, green: 0.50, blue: 0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                    
                    // Top highlight for depth
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(isDark ? 0.5 : 0.45), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                        .frame(width: 36, height: 36)
                    
                    // AI Sparkles icon - LIGHT MODE FIX: White icon on darker gold
                    Image(systemName: "sparkles")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(isDark ? .black.opacity(0.85) : .white.opacity(0.95))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    // Premium "AI" chip badge
                    HStack(spacing: 3) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 7, weight: .bold))
                        Text("AI")
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(1.2)
                    }
                    // LIGHT MODE FIX: Adaptive AI badge text color
                    .foregroundColor(isDark ? .black.opacity(0.9) : .white.opacity(0.95))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: isDark
                                        ? [BrandColors.goldLight, BrandColors.goldBase]
                                        : [Color(red: 0.78, green: 0.60, blue: 0.10), Color(red: 0.65, green: 0.48, blue: 0.06)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                    
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                
                Spacer()
                
                // Sleek chevron indicator
                ZStack {
                    Circle()
                        .fill(DS.Adaptive.chipBackground)
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(chipGoldGradient)
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .padding(.vertical, 14)
            .background(
                ZStack {
                    // Animated gradient border glow - LIGHT MODE FIX: Reduced intensity
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            AngularGradient(
                                colors: [
                                    BrandColors.goldLight.opacity(isDark ? 0.3 : 0.12),
                                    BrandColors.goldBase.opacity(isDark ? 0.1 : 0.04),
                                    BrandColors.goldDark.opacity(isDark ? 0.2 : 0.08),
                                    BrandColors.goldBase.opacity(isDark ? 0.1 : 0.04),
                                    BrandColors.goldLight.opacity(isDark ? 0.3 : 0.12)
                                ],
                                center: .center,
                                angle: .degrees(borderPhase)
                            )
                        )
                    
                    // Main card background with glassmorphism
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(DS.Adaptive.cardBackground)
                    
                    // Top highlight gradient for glass effect
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isDark ? 0.08 : 0.45),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                // LIGHT MODE FIX: Subtler gold border in light mode
                                BrandColors.goldBase.opacity(isDark ? 0.6 : 0.35),
                                BrandColors.goldBase.opacity(isDark ? 0.2 : 0.12),
                                BrandColors.goldBase.opacity(isDark ? 0.4 : 0.22)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isDark ? 1 : 0.8
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .padding(.horizontal, 16)
        .onAppear {
            // Breathing glow animation
            withAnimation(
                Animation.easeInOut(duration: 2.0)
                    .repeatForever(autoreverses: true)
            ) {
                glowAmount = 1.0
            }
            // Rotating border gradient animation
            withAnimation(
                Animation.linear(duration: 8.0)
                    .repeatForever(autoreverses: false)
            ) {
                borderPhase = 360
            }
        }
    }
}

@MainActor
class SmartTradingHubViewModel: ObservableObject {
    
    @Published var selectedMode: TradingHubMode
    @Published var showModeSelector: Bool = false
    
    // AI Helper sheet state (replaces chat-only approach)
    @Published var showAIHelperSheet: Bool = false
    
    // Quick stats
    @Published var paperBalance: Double = 0
    @Published var activeBots: Int = 0
    @Published var openPositions: Int = 0
    
    // Enhanced stats
    @Published var totalPnL: Double = 0
    @Published var todayPnL: Double = 0
    @Published var alertsCount: Int = 0
    
    // Recent activity
    @Published var recentActivity: [RecentActivityItem] = []
    
    /// Initialize the view model with an optional starting mode
    /// - Parameter initialMode: The mode to start in (defaults to .assistant)
    init(initialMode: TradingHubMode = .assistant) {
        self.selectedMode = initialMode
        refreshStats()
        loadRecentActivity()
    }
    
    func refreshStats() {
        // Paper trading balance (quote currency, usually USDT)
        paperBalance = PaperTradingManager.shared.balance(for: "USDT")
        
        // Active bots count
        let paperBots = PaperBotManager.shared.paperBots.filter { $0.status == .running }.count
        let liveBots = LiveBotManager.shared.bots.filter { $0.isEnabled }.count
        let predictionBots = PredictionTradingService.shared.liveBots.filter { $0.isEnabled }.count
        activeBots = paperBots + liveBots + predictionBots
        
        // Open positions (pending orders)
        openPositions = PaperTradingManager.shared.pendingOrders.count
        
        // Calculate P/L from paper trading - need prices for accurate calculation
        // For now, estimate from balance change
        let initialValue = PaperTradingManager.shared.initialPortfolioValue
        let currentBalance = paperBalance
        totalPnL = currentBalance - initialValue
        
        // Today's P/L from trades executed today
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todayTrades = PaperTradingManager.shared.recentTrades(limit: 50).filter {
            calendar.isDate($0.timestamp, inSameDayAs: today)
        }
        todayPnL = todayTrades.reduce(0) { result, trade in
            // Simplified P/L - sell trades add value, buy trades subtract
            trade.side == .sell ? result + trade.totalValue : result - trade.totalValue
        }
        
        // Alerts count - placeholder (NotificationsManager may not have this property)
        alertsCount = 0
    }
    
    func loadRecentActivity() {
        var activities: [RecentActivityItem] = []
        
        // Get recent paper trades
        let recentTrades = PaperTradingManager.shared.recentTrades(limit: 3)
        for trade in recentTrades {
            let isBuy = trade.side == .buy
            activities.append(RecentActivityItem(
                icon: isBuy ? "arrow.down.circle.fill" : "arrow.up.circle.fill",
                iconColor: isBuy ? .green : .red,
                title: "\(isBuy ? "Buy" : "Sell") \(trade.symbol)",
                subtitle: formatTradeAmount(trade.totalValue),
                timestamp: trade.timestamp,
                type: .trade
            ))
        }
        
        // Get recent bot actions
        let runningBots = PaperBotManager.shared.paperBots.filter { $0.status == .running }.prefix(2)
        for bot in runningBots {
            activities.append(RecentActivityItem(
                icon: "cpu",
                iconColor: .purple,
                title: "\(bot.name) running",
                subtitle: bot.type.rawValue,
                timestamp: bot.lastRunAt ?? Date(),
                type: .botAction
            ))
        }
        
        // Get recent prediction bets
        let recentPredictions = PredictionTradingService.shared.activeTrades.prefix(2)
        for prediction in recentPredictions {
            activities.append(RecentActivityItem(
                icon: "chart.bar.xaxis.ascending",
                iconColor: .cyan,
                title: prediction.outcome,
                subtitle: "$\(Int(prediction.amount)) bet",
                timestamp: prediction.createdAt,
                type: .prediction
            ))
        }
        
        // Sort by timestamp and take the 5 most recent
        recentActivity = activities.sorted { $0.timestamp > $1.timestamp }.prefix(5).map { $0 }
    }
    
    private func formatTradeAmount(_ amount: Double) -> String {
        if amount >= 1000 {
            return String(format: "$%.1fK", amount / 1000)
        }
        return String(format: "$%.2f", amount)
    }
    
    /// Get the appropriate AI system prompt for the current mode
    func getSystemPromptForMode() -> String {
        return SmartTradingHubViewModel.buildSystemPrompt(for: selectedMode)
    }
    
    /// Build a context-aware system prompt with deep domain expertise
    nonisolated static func buildSystemPrompt(for mode: TradingHubMode) -> String {
        // Check trading modes for context-aware prompts
        // Priority: Live Trading (developer mode) > Paper Trading > Advisory Only
        let isLiveTradingEnabled = AppConfig.liveTradingEnabled
        let isPaperTradingEnabled = PaperTradingManager.isEnabled
        
        // Determine trading context for the prompt
        let tradingContextDescription: String
        if isLiveTradingEnabled {
            tradingContextDescription = "LIVE TRADING ENABLED (Developer Mode) - you can help execute REAL trades on connected exchanges"
        } else if isPaperTradingEnabled {
            tradingContextDescription = "PAPER TRADING ENABLED - you can help execute simulated trades with virtual money"
        } else {
            tradingContextDescription = "NOT in trading mode - provide advice only, no trade execution"
        }
        
        let basePrompt = """
        You are CryptoSage AI, a smart and professional crypto trading assistant. You're currently acting as a \(mode.aiContextPrefix).
        
        YOUR PERSONALITY:
        - Warm and approachable, like a knowledgeable friend
        - Direct and practical - get to the point quickly
        - Confident but humble - acknowledge uncertainties
        - Safety-conscious - always mention relevant risks
        
        FORMATTING RULES (CRITICAL):
        - NO markdown (no *, #, _, etc.)
        - Use plain text, dashes for lists, CAPS for emphasis
        - Keep responses concise - this is a mobile app
        - Use numbers or dashes for step-by-step guidance
        
        IMPORTANT - TRADING EXECUTION CONTEXT:
        - Current user mode: \(tradingContextDescription)
        - \(isLiveTradingEnabled ? "Live trading IS enabled - you can help execute real trades via connected exchanges" : "Live trading is NOT available for regular users - only paper trading or advice")
        - Users may trade on their own exchanges outside the app - you can advise them on those trades
        - Your job is to be a helpful trading advisor whether they trade in-app or externally
        
        LEGAL & RISK DISCLAIMERS (MUST INCLUDE):
        - You are NOT a financial advisor. Always include "This is not financial advice" for trading suggestions.
        - For trade advice: Add "Remember: only trade what you can afford to lose"
        - For derivatives/leverage: ALWAYS warn about liquidation risk and potential total loss
        - For predictions: Remind users these are probabilistic estimates, not guarantees
        - If asked about taxes/legality: Advise consulting a professional (CPA, attorney)
        - You can be wrong - acknowledge uncertainty when appropriate
        - Don't be so cautious you're unhelpful - one quick line is usually enough
        
        APPLE APP STORE COMPLIANCE:
        - Your responses will be automatically labeled "AI Generated" per Apple Guidelines 5.6.4
        - Financial advice responses will include "Not financial advice" disclaimer
        - Keep disclaimers brief but clear for mobile users
        
        """
        
        // Check trading status for conditional prompts
        // Live trading takes priority over paper trading
        let isLive = AppConfig.liveTradingEnabled
        let isPaper = PaperTradingManager.isEnabled
        
        switch mode {
        case .assistant:
            let executionInstructions: String
            if isLive {
                executionInstructions = """
            
            LIVE TRADING EXECUTION (DEVELOPER MODE ENABLED):
            You CAN help execute REAL trades on connected exchanges. This is a privileged mode.
            
            For SPOT TRADES (user says "buy X", "sell Y", "trade"):
            Output on one line (user won't see this):
            <trade_config>{"symbol":"BTC","direction":"buy","orderType":"market","amount":"100","isUSDAmount":true}</trade_config>
            Then say: "Ready to execute a $100 BTC trade on your connected exchange! Tap Execute to place this REAL order."
            
            For TRADING BOTS (user says "DCA bot", "grid bot", "set up a bot"):
            You MUST use XML-style <bot_config> tags with valid JSON inside, on ONE line (user won't see it):
            <bot_config>{"botType":"dca","name":"BTC Weekly DCA","exchange":"Binance","tradingPair":"BTC_USDT","baseOrderSize":"100","takeProfit":"10","maxOrders":"52","priceDeviation":"5"}</bot_config>
            Then say: "I've configured a live DCA bot - this will execute REAL trades! Tap to create it."
            NEVER use plain text like bot_config{...}/bot_config - that breaks the app. ALWAYS use <bot_config>JSON</bot_config>.
            
            For 3Commas bots, use their actual exchange names (Binance, KuCoin, etc.).
            
            ALWAYS remind the user these are REAL trades with real money.
            """
            } else if isPaper {
                executionInstructions = """
            
            PAPER TRADING EXECUTION (USER HAS PAPER TRADING ENABLED):
            You CAN help execute SIMULATED paper trades. These use virtual money for practice.
            
            For SPOT TRADES (user says "buy X", "sell Y", "trade"):
            Output on one line (user won't see this):
            <trade_config>{"symbol":"BTC","direction":"buy","orderType":"market","amount":"100","isUSDAmount":true}</trade_config>
            Then say: "Ready to paper trade $100 of BTC! Tap Execute to simulate this trade."
            
            For TRADING BOTS (user says "DCA bot", "grid bot", "set up a bot"):
            You MUST use XML-style <bot_config> tags with valid JSON inside, on ONE line (user won't see it):
            <bot_config>{"botType":"dca","name":"BTC Weekly DCA","exchange":"Paper","tradingPair":"BTC_USDT","baseOrderSize":"100","takeProfit":"10","maxOrders":"52","priceDeviation":"5"}</bot_config>
            Then say: "I've configured a paper DCA bot for practice - tap to create it!"
            NEVER use plain text like bot_config{...}/bot_config - that breaks the app. ALWAYS use <bot_config>JSON</bot_config>.
            
            ALWAYS clarify these are SIMULATED trades with virtual money, not real.
            """
            } else {
                executionInstructions = """
            
            ADVISORY MODE (USER IS NOT IN PAPER TRADING):
            The user is NOT in paper trading mode. You can provide:
            - Trading advice, analysis, and recommendations
            - Help them plan trades they'll execute on their own exchange
            - Education on strategies, risk management, and market conditions
            
            DO NOT output <trade_config> or <bot_config> tags - they won't work without paper trading.
            
            If user wants to practice trading, suggest: "Would you like to enable Paper Trading to practice with virtual money? You can do that from the Trading tab."
            
            If user is trading on their own exchange (Coinbase, Binance, etc.), help them with:
            - Entry/exit price recommendations
            - Position sizing calculations
            - Stop loss and take profit levels
            - Market analysis and timing
            """
            }
            
            return basePrompt + """
            
            GENERAL ASSISTANT MODE:
            You're the main Smart Trading assistant - versatile and helpful. You can assist with:
            - Market analysis and price predictions
            - Portfolio advice and diversification  
            - Technical analysis explanations
            - Trading strategy recommendations
            - Explaining crypto concepts
            - DeFi protocols and yield farming
            - NFTs and token economics
            - Planning trades (for paper trading or external exchanges)
            \(executionInstructions)
            
            PROFESSIONAL SWING TRADING FRAMEWORK:
            
            1. POSITION SIZING (CRITICAL)
               - Risk 1% of account per trade maximum
               - Formula: Risk/(Entry - Stop) = Position Size
               - Example: $10K account, 1% risk = $100 max loss per trade
            
            2. MARKET CONDITIONS CHECK
               - BTC 10 SMA above 20 SMA = BULLISH, trade normally
               - BTC 10 SMA below 20 SMA = CAUTIOUS, reduce size or skip
               - ALWAYS mention market conditions in recommendations
            
            3. ENTRY & EXIT RULES
               - Enter on opening range high breaks with volume
               - Stop loss = Low of Day (no exceptions)
               - Take partial profit at 5x risk, trail the rest
               - Full exit when price closes below 10 SMA
            
            The specialized modes (Spot, Bots, Derivatives, Predictions) offer deeper expertise.
            Be helpful, educational, and practical! Help users whether they trade in-app or on external exchanges.
            """
            
        case .spot:
            let executionInstructions: String
            if isLive {
                executionInstructions = """
            
            LIVE TRADING EXECUTION (DEVELOPER MODE):
            When the user wants to trade, output a config like this (on one line, user won't see it):
            <trade_config>{"symbol":"BTC","direction":"buy","orderType":"market","amount":"100","isUSDAmount":true}</trade_config>
            
            Then say something like:
            "Ready to execute a $100 Bitcoin trade on your connected exchange! This is a REAL order. Tap Execute to place it."
            """
            } else if isPaper {
                executionInstructions = """
            
            PAPER TRADING EXECUTION:
            When the user wants to practice a trade, output a config like this (on one line, user won't see it):
            <trade_config>{"symbol":"BTC","direction":"buy","orderType":"market","amount":"100","isUSDAmount":true}</trade_config>
            
            Then say something like:
            "Ready to paper trade $100 of Bitcoin! This is a simulated trade with virtual money. Tap Execute to practice."
            """
            } else {
                executionInstructions = """
            
            ADVISORY MODE (NO PAPER TRADING):
            The user isn't in paper trading mode, so you can't execute trades in-app.
            Instead, help them plan trades for their external exchange:
            - Recommend specific entry prices, stop losses, take profit levels
            - Calculate position sizes based on their account and risk tolerance
            - Analyze market conditions and timing
            - Walk them through placing the order on their exchange
            
            If they want to practice first: "Enable Paper Trading from the Trading tab to simulate trades with virtual money!"
            """
            }
            
            return basePrompt + """
            
            SPOT TRADING SPECIALIST MODE:
            Help users with spot trading - buying and selling crypto at market or limit prices.
            \(executionInstructions)
            
            PROFESSIONAL TRADING METHODOLOGY:
            
            1. POSITION SIZING (CRITICAL)
               - Risk 1% of portfolio per trade maximum
               - Formula: Risk/(Entry - Stop) = Position Size
               - Example: $10K portfolio, risk $100, stop 5% away = $2K position
            
            2. ENTRY TIMING
               - Check market conditions first: BTC 10 SMA vs 20 SMA
               - Look for breakout setups with volume confirmation
               - Enter on opening range high breaks (1min/5min)
               - Wait for pullbacks to moving averages for better entries
            
            3. STOP LOSS PLACEMENT
               - Use low of day as stop (professional approach)
               - No exceptions - every trade needs a stop
               - Tighter stops = larger position size (same dollar risk)
            
            ORDER TYPE GUIDANCE:
            - Market Order: Instant execution, best for breakouts or urgent trades
            - Limit Order: Set your price, may not fill, better for larger amounts
            - Stop-Limit: Trigger at price, then limit order - good for breakout entries
            
            TIMING STRATEGIES:
            - DCA: Split buys over time to reduce timing risk
            - Pullback buying: Wait for orderly pullbacks to 10/20 SMA
            - Breakout buying: Enter after price breaks resistance on HIGH volume
            
            FEE & SLIPPAGE:
            - Use limit orders when possible (lower fees)
            - Low-cap coins have wider spreads
            - For large trades (>$10K), split into smaller orders
            
            IMPORTANT:
            - Always confirm trade details before taking action
            - Check market conditions (BTC trend) before any trade
            - Suggest stop loss levels for every buy recommendation
            """
            
        case .bots:
            let executionInstructions: String
            if isLive {
                executionInstructions = """
            
            LIVE BOT CREATION (DEVELOPER MODE):
            You can help create REAL trading bots that execute actual trades.
            
            BOT CONFIG FORMAT (CRITICAL - follow EXACTLY):
            You MUST use XML-style tags with valid JSON inside. Put it on ONE line (the user will NOT see it):
            <bot_config>{"botType":"dca","name":"BTC Daily DCA","exchange":"Binance","tradingPair":"BTC_USDT","baseOrderSize":"50","takeProfit":"5","maxOrders":"10","priceDeviation":"2"}</bot_config>
            
            CORRECT examples:
            <bot_config>{"botType":"grid","name":"ETH Grid","exchange":"Binance","tradingPair":"ETH_USDT","lowerPrice":"1800","upperPrice":"2200","gridLevels":"10"}</bot_config>
            <bot_config>{"botType":"signal","name":"SOL RSI Bot","exchange":"Binance","tradingPair":"SOL_USDT","entryCondition":"RSI<30","exitCondition":"RSI>70","positionSize":"100"}</bot_config>
            
            WRONG - NEVER do these (they will break the app):
            - bot_config{botType:dca,...}/bot_config  (NO - missing XML tags and JSON quotes)
            - bot_config(botType:signal,...) (NO - wrong format entirely)
            - Showing raw JSON to the user (NO - always hide it in tags)
            
            After the hidden tag, write a SHORT friendly summary like:
            "I've configured a live DCA bot for Binance! This will execute REAL trades. Tap to create it."
            
            For 3Commas bots, use actual exchange names (Binance, KuCoin, Bybit, etc.).
            """
            } else if isPaper {
                executionInstructions = """
            
            PAPER BOT CREATION (USER HAS PAPER TRADING ENABLED):
            You can help create SIMULATED paper bots for practice.
            
            BOT CONFIG FORMAT (CRITICAL - follow EXACTLY):
            You MUST use XML-style tags with valid JSON inside. Put it on ONE line (the user will NOT see it):
            <bot_config>{"botType":"dca","name":"BTC Daily DCA","exchange":"Paper","tradingPair":"BTC_USDT","baseOrderSize":"50","takeProfit":"5","maxOrders":"10","priceDeviation":"2"}</bot_config>
            
            CORRECT examples:
            <bot_config>{"botType":"grid","name":"ETH Grid","exchange":"Paper","tradingPair":"ETH_USDT","lowerPrice":"1800","upperPrice":"2200","gridLevels":"10"}</bot_config>
            <bot_config>{"botType":"signal","name":"SOL RSI Bot","exchange":"Paper","tradingPair":"SOL_USDT","entryCondition":"RSI<30","exitCondition":"RSI>70","positionSize":"100"}</bot_config>
            
            WRONG - NEVER do these (they will break the app):
            - bot_config{botType:dca,...}/bot_config  (NO - missing XML tags and JSON quotes)
            - bot_config(botType:signal,...) (NO - wrong format entirely)
            - Showing raw JSON to the user (NO - always hide it in tags)
            
            After the hidden tag, write a SHORT friendly summary like:
            "I've configured a paper DCA bot for practice! This uses virtual money. Tap to create it."
            """
            } else {
                executionInstructions = """
            
            ADVISORY MODE (NO PAPER TRADING):
            The user isn't in paper trading mode, so bots can't be created in-app.
            Help them understand bot strategies so they can:
            - Set up bots on their own exchange (3Commas, Pionex, etc.)
            - Understand the parameters and when to use each bot type
            - Plan their bot configuration and risk management
            
            If they want to test strategies: "Enable Paper Trading to create simulated bots with virtual money!"
            """
            }
            
            return basePrompt + """
            
            ALGORITHMIC TRADING BOT SPECIALIST MODE:
            Help users understand and configure trading bots for automated strategies.
            \(executionInstructions)
            
            BOT TYPES AND WHEN TO USE:
            
            1. DCA Bot (Dollar-Cost Averaging)
               - BEST FOR: Long-term accumulation, reducing timing risk
               - HOW IT WORKS: Buys fixed amounts at regular intervals or price drops
               - IDEAL MARKET: Any, especially during uncertainty
               - KEY PARAMS: Base order size, price deviation trigger, take profit %
               - EXAMPLE: "Buy $50 BTC every time price drops 2%"
            
            2. Grid Bot
               - BEST FOR: Sideways/ranging markets with clear support/resistance
               - HOW IT WORKS: Places buy/sell orders in a grid, profits from oscillation
               - IDEAL MARKET: Low volatility, range-bound (NOT trending)
               - KEY PARAMS: Price range (lower/upper), grid levels, order size
               - EXAMPLE: "Trade BTC between $60K-$70K with 10 grid levels"
               - WARNING: Can lose money in strong trends outside the range
            
            3. Signal Bot
               - BEST FOR: Technical traders who want automation
               - HOW IT WORKS: Executes based on technical indicators or custom signals
               - IDEAL MARKET: Trending markets with clear signals
               - KEY PARAMS: Signal source, entry/exit conditions, position size
               - EXAMPLE: "Buy when RSI < 30, sell when RSI > 70"
            
            PROFESSIONAL BOT CONFIGURATION:
            
            1. MARKET CONDITIONS AWARENESS
               - Always check BTC 10 SMA vs 20 SMA before enabling bots
               - 10 above 20 = enable long bots, full allocation
               - 10 below 20 = reduce allocation or pause aggressive bots
               - Grid bots work best when market is ranging (10/20 crossing frequently)
            
            2. POSITION SIZING FOR BOTS
               - Risk 1% of portfolio per bot maximum
               - Total bot allocation should not exceed 30% of portfolio
               - Keep 70% manual for swing trade opportunities
            
            3. EXIT RULES FOR SIGNAL BOTS
               - Take partial profit at 5x risk level
               - Trail stops using 10 SMA close
               - Move to breakeven after 5x profit reached
            
            PARAMETER TUNING TIPS:
            - Take Profit: 3-5% for ranging markets, 10%+ for trending
            - Stop Loss: Use 10 SMA close as trailing stop
            - Max Orders: Higher = more averaging, but more capital
            - Price Deviation: 1-2% for active, 3-5% for swing
            
            RISK MANAGEMENT:
            - Never allocate more than 20-30% of portfolio to any single bot
            - Start with paper trading to validate strategy
            - Use stop losses to protect against black swan events
            - Monitor bots weekly, adjust based on market conditions
            """
            
        case .strategies:
            return basePrompt + """
            
            ALGORITHMIC STRATEGY SPECIALIST MODE:
            Help users build, backtest, and optimize custom trading strategies using technical indicators.
            
            STRATEGY BUILDING FRAMEWORK:
            
            1. ENTRY CONDITIONS (When to Buy)
               - Combine multiple indicators for confirmation
               - Example: RSI < 30 AND Price > 200 SMA AND MACD crosses above signal
               - Use crossovers for momentum: SMA(50) crosses above SMA(200) = Golden Cross
               - Use oscillators for overbought/oversold: RSI, Stochastic
            
            2. EXIT CONDITIONS (When to Sell)
               - Take profit at fixed percentage or indicator reversal
               - Example: RSI > 70 OR Price crosses below 50 SMA
               - Use trailing stops based on ATR or fixed percentage
            
            3. AVAILABLE INDICATORS
               Moving Averages: SMA(10/20/50/100/200), EMA(12/26/50/200)
               Momentum: RSI(14), MACD(12,26,9), Stochastic(14,3,3)
               Volatility: Bollinger Bands(20,2), ATR(14)
               Volume: OBV, Volume SMA
               Trend: ADX, Parabolic SAR
            
            4. CONDITION TYPES
               - Greater Than / Less Than: RSI > 70
               - Crosses Above / Crosses Below: SMA(50) crosses above SMA(200)
               - Between: Price between BB Upper and BB Lower
            
            5. CONDITION LOGIC
               - ALL (AND): All conditions must be true
               - ANY (OR): At least one condition must be true
               - CUSTOM: Advanced combinations
            
            BACKTESTING INSIGHTS:
            - Always backtest on 1+ years of data minimum
            - Key metrics to evaluate:
              * Win Rate: Percentage of profitable trades (aim for 40-60%)
              * Profit Factor: Gross profit / Gross loss (aim for >1.5)
              * Sharpe Ratio: Risk-adjusted returns (aim for >1.0)
              * Max Drawdown: Largest peak-to-trough decline (keep <25%)
              * Sortino Ratio: Downside risk-adjusted returns
            - Beware of overfitting: Strategy should work across different periods
            
            STRATEGY TEMPLATES:
            
            1. Golden Cross (Trend Following)
               Entry: SMA(50) crosses above SMA(200)
               Exit: SMA(50) crosses below SMA(200)
               Best for: Strong trending markets
            
            2. RSI Oversold Bounce (Mean Reversion)
               Entry: RSI(14) < 30 AND Price > SMA(200)
               Exit: RSI(14) > 70 OR 10% profit
               Best for: Ranging markets with clear support
            
            3. MACD Momentum (Momentum)
               Entry: MACD crosses above Signal AND MACD < 0
               Exit: MACD crosses below Signal
               Best for: Catching trend reversals
            
            4. Bollinger Band Squeeze (Breakout)
               Entry: Price closes above Upper BB after BB width contracts
               Exit: Price touches Middle BB or 5% stop loss
               Best for: Volatility breakouts
            
            RISK MANAGEMENT FOR STRATEGIES:
            - Always use stop losses (typically 2-5% based on volatility)
            - Position size based on risk: Risk 1-2% per trade max
            - Take profit levels: Scale out at 1R, 2R, 3R targets
            - Maximum drawdown limit: Pause strategy if drawdown > 20%
            
            STRATEGY IMPROVEMENT TIPS:
            - Add volume confirmation to reduce false signals
            - Use higher timeframes for trend, lower for entry
            - Combine trend indicators with momentum indicators
            - Test on multiple assets to ensure robustness
            """
            
        case .derivatives:
            let executionInstructions: String
            if isLive {
                executionInstructions = """
            
            LIVE DERIVATIVES TRADING (DEVELOPER MODE):
            You can help execute REAL leveraged positions on connected exchanges.
            
            Output a config like this (on one line, user won't see it):
            <trade_config>{"symbol":"ETH","direction":"buy","orderType":"market","amount":"500","isUSDAmount":true,"leverage":5,"stopLoss":"2","takeProfit":"6"}</trade_config>
            
            Then say: "Ready to execute a 5x leveraged LONG on ETH with $500. WARNING: This is REAL money with HIGH RISK. Tap to execute."
            
            CRITICAL: Always warn about liquidation risk and potential total loss with real derivatives trading.
            """
            } else if isPaper {
                executionInstructions = """
            
            PAPER DERIVATIVES (USER HAS PAPER TRADING ENABLED):
            You can help simulate leveraged positions for practice.
            
            Output a config like this (on one line, user won't see it):
            <trade_config>{"symbol":"ETH","direction":"buy","orderType":"market","amount":"500","isUSDAmount":true,"leverage":5,"stopLoss":"2","takeProfit":"6"}</trade_config>
            
            Then say: "Ready to paper trade a 5x leveraged LONG on ETH with $500 virtual money. WARNING: This simulates high-risk trading. Tap to practice."
            """
            } else {
                executionInstructions = """
            
            ADVISORY MODE (NO PAPER TRADING):
            The user isn't in paper trading mode, so help them plan derivatives trades for their external exchange.
            Provide:
            - Entry/exit price recommendations
            - Leverage and position size calculations
            - Risk analysis and liquidation price calculations
            - Funding rate considerations
            
            STRONGLY recommend they practice first: "Derivatives are HIGH RISK. Consider enabling Paper Trading to practice with virtual money before using real funds!"
            """
            }
            
            return basePrompt + """
            
            DERIVATIVES & LEVERAGE TRADING SPECIALIST MODE:
            Help users understand and plan futures, perpetuals, and leveraged trading. This is HIGH RISK.
            \(executionInstructions)
            
            PROFESSIONAL DERIVATIVES FRAMEWORK:
            
            1. POSITION SIZING (CRITICAL)
               - Risk 1% of account per trade maximum
               - Formula: Risk/(Entry - Stop) = Position Size
               - Example: $10K account, 1% risk = $100 max loss
               - With 5x leverage and 2% stop, position = $1,000
            
            2. MARKET CONDITIONS CHECK
               - Go to BTC daily chart FIRST
               - 10 SMA above 20 SMA = BULLISH, trade long setups
               - 10 SMA below 20 SMA = BEARISH/CAUTIOUS, reduce size
               - NEVER take high leverage when 10 is below 20
            
            3. ENTRY RULES
               - Wait for breakout setups on daily chart
               - Enter on 5min opening range high break
               - Stop loss = Low of Day (no exceptions)
               - Check funding rate before entering
            
            4. EXIT RULES
               - Sell 25% at 5x risk (risk $100, take some at $500 profit)
               - Move stop to breakeven after partial profit
               - Close full position if daily close below 10 SMA
            
            DERIVATIVES BASICS:
            - Perpetual Contracts: No expiry, track spot via funding rates
            - Futures: Fixed expiry, converge to spot at settlement
            - Leverage: Amplifies gains AND losses
            
            MARGIN MODES:
            - Isolated (RECOMMENDED): Risk limited to position margin
            - Cross: Uses entire account, higher liquidation risk
            
            LIQUIDATION MATH:
            - 10x leverage: ~9% adverse move = liquidation
            - 20x leverage: ~4.5% adverse move = liquidation
            - 50x leverage: ~1.8% adverse move = liquidation
            
            LEVERAGE GUIDE:
            - 1-3x: Conservative, beginners
            - 5-10x: Moderate, requires stops
            - 20x+: HIGH RISK, experts only
            - 50x+: EXTREME RISK, strongly discouraged
            
            SAFETY WARNINGS:
            - 80%+ of retail traders lose money on derivatives
            - Never trade with money you cannot afford to lose
            - Avoid high-impact news events
            - Sleep is more important than any trade
            """
            
        case .predictions:
            let executionInstructions: String
            if isLive {
                executionInstructions = """
            
            LIVE PREDICTIONS (DEVELOPER MODE):
            You can help create REAL prediction market bets on connected platforms.
            
            BOT CONFIG FORMAT (CRITICAL - follow EXACTLY):
            You MUST use XML-style tags with valid JSON inside. Put it on ONE line (the user will NOT see it):
            <bot_config>{"botType":"predictionMarket","name":"BTC 100K Bet","platform":"Polymarket","marketTitle":"Will Bitcoin reach $100K in 2026?","outcome":"YES","betAmount":"50","targetPrice":"0.65"}</bot_config>
            
            NEVER use plain text formats like bot_config{...}/bot_config - they will break the app.
            
            After the hidden tag, write a SHORT friendly summary like:
            "I've set up a prediction market bet on Polymarket! This uses REAL money. Tap to place it."
            """
            } else if isPaper {
                executionInstructions = """
            
            PAPER PREDICTIONS (USER HAS PAPER TRADING ENABLED):
            You can help create simulated prediction market bets for practice.
            
            BOT CONFIG FORMAT (CRITICAL - follow EXACTLY):
            You MUST use XML-style tags with valid JSON inside. Put it on ONE line (the user will NOT see it):
            <bot_config>{"botType":"predictionMarket","name":"BTC 100K Bet","platform":"Paper","marketTitle":"Will Bitcoin reach $100K in 2026?","outcome":"YES","betAmount":"50","targetPrice":"0.65"}</bot_config>
            
            NEVER use plain text formats like bot_config{...}/bot_config - they will break the app.
            
            After the hidden tag, write a SHORT friendly summary like:
            "I've set up a paper prediction bet for practice! This uses virtual money. Tap to create it."
            """
            } else {
                executionInstructions = """
            
            ADVISORY MODE (NO PAPER TRADING):
            The user isn't in paper trading mode. Help them analyze prediction markets so they can:
            - Evaluate opportunities on Polymarket, Kalshi, or other platforms
            - Calculate expected value and optimal bet sizing
            - Understand probability estimation and edge finding
            
            If they want to practice: "Enable Paper Trading to simulate prediction market bets with virtual money!"
            """
            }
            
            return basePrompt + """
            
            PREDICTION MARKET ANALYST MODE:
            Help users analyze and understand prediction markets (Polymarket, Kalshi) across ALL categories:
            - CRYPTO: Bitcoin price targets, ETF approvals, protocol upgrades
            - POLITICS: Elections, legislation, policy decisions
            - ECONOMICS: Fed rates, GDP, inflation, employment
            - SPORTS: Game outcomes, championships, player performance
            - ENTERTAINMENT: Awards, releases, celebrity events
            - SCIENCE/TECH: AI milestones, space missions, discoveries
            
            \(executionInstructions)
            
            PREDICTION MARKET BASICS:
            - Price = Crowd's probability estimate (0.65 = 65% implied probability)
            - Payout = 1 / Price (if correct) - Example: 0.65 price = 1.54x payout
            - Edge = Your estimated probability - Market price
            - Positive edge = Potential profitable opportunity
            
            PLATFORM DIFFERENCES:
            - Polymarket: Crypto-native (USDC on Polygon), wider variety, global access
            - Kalshi: US-regulated (CFTC), USD deposits, US-focused markets
            
            FINDING EDGE (THE KEY TO PROFITS):
            1. Information Advantage: You know something the market doesn't
            2. Modeling Advantage: Better probability estimates from domain expertise
            3. Timing Advantage: React faster to new information
            4. Domain Expertise: Deep knowledge in politics, sports, or other fields
            
            CATEGORY-SPECIFIC ANALYSIS:
            
            POLITICS:
            - Check polling aggregates (538, RealClearPolitics)
            - Consider historical precedent for similar races/votes
            - Watch for momentum shifts and key events (debates, endorsements)
            - Be aware of systematic polling errors
            
            ECONOMICS:
            - Follow Fed communications and FOMC dot plots
            - Track leading economic indicators
            - Consider consensus forecasts vs your model
            - Time-sensitive: economic data releases are scheduled
            
            SPORTS:
            - Injury reports and lineup changes
            - Home/away performance differentials
            - Historical head-to-head matchups
            - Weather conditions for outdoor events
            
            GENERAL ANALYSIS FRAMEWORK:
            1. Base Rate: What's the historical probability of similar events?
            2. Current Evidence: What new information affects probability?
            3. Market Sentiment: Is the crowd over/under-reacting?
            4. Time Decay: How does probability change as deadline approaches?
            5. Resolution Rules: Exactly how does this market settle?
            
            KELLY CRITERION (OPTIMAL BET SIZING):
            - Formula: (Edge * Odds - 1) / (Odds - 1)
            - Example: 70% confidence on 65% market = 14% of bankroll
            - NEVER bet full Kelly - use 25-50% Kelly for safety
            - Account for uncertainty in your probability estimate
            
            MARKET INEFFICIENCIES TO EXPLOIT:
            - Longshots: Markets often underprice low-probability events
            - Recency Bias: Overreaction to recent news
            - Illiquidity: Low-volume markets have wider spreads
            - Partisan Bias: Political markets can reflect wishful thinking
            - Late Information: Price moves on new info create opportunities
            
            RISK MANAGEMENT:
            - Diversify across 10+ uncorrelated markets
            - Never bet more than 5-10% of bankroll on single market
            - Track all bets and calculate ROI regularly
            - Accept that losing streaks happen - variance is real
            - Consider correlation between markets
            
            IMPORTANT:
            - Prediction markets are speculative - prices are probabilities, not certainties
            - Start with paper trading to learn without risk
            - Research events thoroughly before betting
            - Your domain expertise matters - bet where you have edge
            - Do NOT rely solely on AI analysis - do your own research
            """
        }
    }
}

// MARK: - Smart Trading Hub View

struct SmartTradingHub: View {
    @StateObject private var viewModel: SmartTradingHubViewModel
    @StateObject private var aiChatVM: AiChatViewModel
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    
    // Bot managers for dashboard-first approach
    @ObservedObject private var paperBotManager = PaperBotManager.shared
    @ObservedObject private var liveBotManager = LiveBotManager.shared
    @ObservedObject private var demoModeManager = DemoModeManager.shared
    @ObservedObject private var marketVM = MarketViewModel.shared
    
    // State for bot menu navigation (Quick Actions dropdown)
    @State private var navigateToDCABot: Bool = false
    @State private var navigateToGridBot: Bool = false
    @State private var navigateToSignalBot: Bool = false
    
    // MARK: - AI Context State (NEW)
    // Tracks which context the AI helper should use when opened
    @State private var selectedAIContext: AIHelperContext = .general
    
    // MARK: - Trending Prediction Markets State
    @State private var trendingPredictionMarkets: [PredictionMarketEvent] = []
    @State private var isLoadingTrendingMarkets: Bool = false
    
    /// Initialize SmartTradingHub with optional initial mode
    /// - Parameter initialMode: The mode to start in (defaults to .assistant)
    init(initialMode: TradingHubMode = .assistant) {
        // Initialize view model with the specified initial mode
        _viewModel = StateObject(wrappedValue: SmartTradingHubViewModel(initialMode: initialMode))
        
        // Initialize with the specified mode's prompt
        let prompt = SmartTradingHubViewModel.buildSystemPrompt(for: initialMode)
        
        // Determine greeting based on trading mode: Live > Paper > Advisory
        let isLive = AppConfig.liveTradingEnabled
        let isPaper = PaperTradingManager.isEnabled
        let greeting: String
        if isLive {
            greeting = "Hey! I'm your CryptoSage AI trading assistant. Live trading is ENABLED - I can help you execute real trades, manage 3Commas bots, analyze markets, and more. What would you like to do?"
        } else if isPaper {
            greeting = "Hey! I'm your CryptoSage AI trading assistant. I can help you practice with paper trading, analyze markets, set up bots, and more. What would you like to do?"
        } else {
            greeting = "Hey! I'm CryptoSage AI, your trading advisor. I can help with market analysis, trading strategies, and planning your trades. What would you like to know?"
        }
        
        _aiChatVM = StateObject(wrappedValue: AiChatViewModel(
            systemPrompt: prompt,
            storageKey: "csai_smart_trading_hub",
            initialGreeting: greeting
        ))
    }
    
    // MARK: - Bot Stats Helpers
    
    private var totalBotCount: Int {
        if demoModeManager.isDemoMode {
            return paperBotManager.demoBotCount
        }
        return paperBotManager.totalBotCount + liveBotManager.totalBotCount
    }
    
    private var runningBotCount: Int {
        if demoModeManager.isDemoMode {
            return paperBotManager.runningDemoBotCount
        }
        return paperBotManager.runningBotCount + liveBotManager.enabledBotCount
    }
    
    private var totalBotProfit: Double {
        if demoModeManager.isDemoMode {
            return paperBotManager.totalDemoBotProfit
        }
        return paperBotManager.paperBots.reduce(0) { $0 + $1.totalProfit }
    }
    
    private var displayedBots: [PaperBot] {
        if demoModeManager.isDemoMode {
            return paperBotManager.demoBots
        }
        return paperBotManager.paperBots
    }
    
    /// Gold gradient for header - LIGHT MODE FIX: Adaptive
    private var chipGoldGradient: LinearGradient {
        colorScheme == .dark
            ? LinearGradient(colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange], startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [Color(red: 0.78, green: 0.60, blue: 0.10), Color(red: 0.65, green: 0.45, blue: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
            
            // Quick stats (collapsed)
            quickStatsBar
            
            Divider()
                .background(DS.Adaptive.divider)
            
            // Content switches based on selected mode
            if viewModel.selectedMode == .assistant {
                // Show dashboard hub when in assistant mode
                dashboardContent
            } else {
                // Show mode-specific content for other modes
                mainContent
            }
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .onAppear {
            viewModel.refreshStats()
            // Seed demo data when in demo mode
            if demoModeManager.isDemoMode {
                paperBotManager.seedDemoBots()
            }
            // Set up callbacks for AI chat actions
            setupAIChatCallbacks()
        }
        .onChange(of: viewModel.selectedMode) { _, newMode in
            // Update AI system prompt when the user switches between modes
            // so the AI responds appropriately for the new context
            updateAIContext(for: newMode)
        }
        // NAVIGATION: Enable native iOS pop gesture + custom edge swipe
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
        // AI Helper Sheet - Context-Aware (uses selected context)
        .sheet(isPresented: $viewModel.showAIHelperSheet) {
            ContextualAIHelperView(context: selectedAIContext)
        }
    }
    
    /// Opens AI helper with a specific context
    private func openAIHelper(with context: AIHelperContext) {
        selectedAIContext = context
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        viewModel.showAIHelperSheet = true
    }
    
    // MARK: - Unified Dashboard Content (Clean Trading Type Launcher)
    
    private var dashboardContent: some View {
        ScrollView {
            VStack(spacing: 14) {
                // 1. CryptoSage AI Card (uses reusable component)
                PremiumAIAdvisorCard(
                    context: .general,
                    title: "CryptoSage AI",
                    subtitle: "Trades, bots, analysis & more"
                ) {
                    openAIHelper(with: .general)
                }
                
                // 2. Trading Type Cards - Clear options with DIY or AI choice
                tradingTypeCardsSection
                
                // 3. Algo Strategies Featured Section
                algoStrategiesFeaturedSection
                
                // 4. Quick Market Access
                quickMarketAccessSection
                
                // 5. Active Bots Summary (if any running)
                if runningBotCount > 0 {
                    activeBotsSummaryCard
                }
                
                Spacer(minLength: 32)
            }
            .padding(.vertical, 12)
        }
        // PERFORMANCE FIX v21: UIKit scroll bridge for snappier deceleration + animation freeze
        .withUIKitScrollBridge()
    }
    
    // MARK: - Algo Strategies Featured Section
    
    private var algoStrategiesFeaturedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Automation")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(DS.Adaptive.textPrimary)
                .padding(.horizontal, 16)
            
            HStack(spacing: 0) {
                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectedMode = .strategies
                    }
                } label: {
                    HStack(spacing: 12) {
                        // Icon
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.15))
                                .frame(width: 40, height: 40)
                            
                            Image(systemName: "function")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.green)
                        }
                        
                        // Text
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Algo Strategies")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(DS.Adaptive.textPrimary)
                                
                                Text("NEW")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(Color.green.opacity(0.15))
                                    )
                            }
                            
                            Text("Build, backtest & deploy trading algorithms")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(DS.Adaptive.textSecondary)
                        }
                        
                        Spacer()
                        
                        // Quick AI button
                        Button {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            openAIHelper(with: .strategies)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [BrandColors.goldLight.opacity(0.25), BrandColors.goldBase.opacity(0.15)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 32, height: 32)
                                
                                Image(systemName: "sparkles")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [BrandColors.goldLight, BrandColors.goldBase],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 8)
                        
                        // Arrow
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                    .padding(12)
                }
                .buttonStyle(.plain)
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.green.opacity(0.2), lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
        }
    }
    
    // MARK: - Trading Type Cards Section (Clean List)
    
    private var tradingTypeCardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trading")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(DS.Adaptive.textPrimary)
                .padding(.horizontal, 16)
            
            // Clean list of trading options
            VStack(spacing: 8) {
                // Spot Trading Row
                tradingOptionRow(
                    icon: "arrow.left.arrow.right.circle.fill",
                    iconColor: .green,
                    title: "Spot Trading",
                    subtitle: "Buy & sell crypto directly",
                    destination: AnyView(TradeView(symbol: "BTC", showBackButton: true)),
                    aiContext: .spot
                )
                
                // Trading Bots Row
                tradingOptionRow(
                    icon: "cpu.fill",
                    iconColor: .purple,
                    title: "Trading Bots",
                    subtitle: "Automated DCA, Grid & Signal bots",
                    destination: AnyView(BotsSectionView()),
                    aiContext: .bots
                )
                
                // Derivatives Row
                tradingOptionRow(
                    icon: "chart.line.uptrend.xyaxis.circle.fill",
                    iconColor: .orange,
                    title: "Derivatives",
                    subtitle: "Leverage & futures trading",
                    destination: AnyView(DerivativesSectionView()),
                    badge: "Risk",
                    aiContext: .derivatives
                )
                
                // Predictions Row
                tradingOptionRow(
                    icon: "chart.bar.xaxis.ascending.badge.clock",
                    iconColor: .cyan,
                    title: "Predictions",
                    subtitle: "Polymarket & Kalshi markets",
                    destination: AnyView(PredictionsSectionView()),
                    aiContext: .predictions
                )
            }
            .padding(.horizontal, 16)
        }
    }
    
    // MARK: - Trading Option Row (Clean Design)
    
    private func tradingOptionRow(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        destination: AnyView,
        badge: String? = nil,
        aiContext: AIHelperContext? = nil
    ) -> some View {
        HStack(spacing: 0) {
            NavigationLink(destination: destination) {
                HStack(spacing: 12) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(iconColor.opacity(0.15))
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: icon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(iconColor)
                    }
                    
                    // Text
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(DS.Adaptive.textPrimary)
                            
                            if let badge = badge {
                                Text(badge)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(Color.orange.opacity(0.15))
                                    )
                            }
                        }
                        
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                    
                    Spacer()
                    
                    // Quick AI button (if context provided)
                    if let context = aiContext {
                        Button {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            openAIHelper(with: context)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [BrandColors.goldLight.opacity(0.25), BrandColors.goldBase.opacity(0.15)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 32, height: 32)
                                
                                Image(systemName: "sparkles")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [BrandColors.goldLight, BrandColors.goldBase],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 8)
                    }
                    
                    // Arrow
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                .padding(12)
            }
            .buttonStyle(.plain)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(iconColor.opacity(0.15), lineWidth: 0.5)
        )
    }
    
    // MARK: - Compact Trading Type Card (Grid Version)
    
    private func compactTradingTypeCard(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        diyDestination: AnyView,
        aiContext: AIHelperContext,
        warning: String? = nil
    ) -> some View {
        VStack(spacing: 0) {
            // Card Header - Premium glass layout
            VStack(spacing: 8) {
                // Icon with layered glow effect
                ZStack {
                    // Outer glow
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    iconColor.opacity(0.3),
                                    iconColor.opacity(0.1),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 24
                            )
                        )
                        .frame(width: 48, height: 48)
                    
                    // Inner circle with gradient
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    iconColor.opacity(0.35),
                                    iconColor.opacity(0.18)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                    
                    // Top highlight for depth
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.25), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                        .frame(width: 38, height: 38)
                    
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(iconColor)
                }
                
                // Title with optional warning badge
                VStack(spacing: 3) {
                    HStack(spacing: 4) {
                        Text(title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        if let warning = warning {
                            Text(warning)
                                .font(.system(size: 7, weight: .heavy))
                                .foregroundColor(.orange)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.orange.opacity(0.15))
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.orange.opacity(0.3), lineWidth: 0.5)
                                        )
                                )
                        }
                    }
                    
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.Adaptive.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.top, 14)
            .padding(.bottom, 10)
            .padding(.horizontal, 8)
            
            // Action Row - Premium integrated design
            HStack(spacing: 8) {
                // Main action button - full width primary CTA
                NavigationLink(destination: diyDestination) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Open")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(iconColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(iconColor.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(iconColor.opacity(0.25), lineWidth: 0.5)
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(ScaleButtonStyle())
                
                // AI helper button - compact sparkles icon
                Button {
                    openAIHelper(with: aiContext)
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(BrandColors.goldBase.opacity(0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(BrandColors.goldBase.opacity(0.3), lineWidth: 0.5)
                            )
                        
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(chipGoldGradient)
                    }
                    .frame(width: 38, height: 34)
                }
                .buttonStyle(ScaleButtonStyle())
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .background(
            ZStack {
                // Base card background
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
                
                // Top glass highlight
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.06 : 0.35),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            iconColor.opacity(0.35),
                            iconColor.opacity(0.1),
                            iconColor.opacity(0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
    }
    
    private func tradingTypeCard(
        icon: String,
        iconColor: Color,
        title: String,
        description: String,
        diyDestination: AnyView,
        aiContext: AIHelperContext,
        warning: String? = nil
    ) -> some View {
        VStack(spacing: 0) {
            // Card Header - Compact with subtle glow
            HStack(spacing: 10) {
                // Icon with subtle glow - more compact
                ZStack {
                    // Outer glow
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [iconColor.opacity(0.2), iconColor.opacity(0.05), Color.clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 24
                            )
                        )
                        .frame(width: 40, height: 40)
                    
                    // Icon background
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [iconColor.opacity(0.25), iconColor.opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(iconColor)
                }
                
                // Title & Description - Tighter spacing
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        if let warning = warning {
                            HStack(spacing: 2) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 7))
                                Text(warning)
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .foregroundColor(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.orange.opacity(0.15))
                                    .overlay(
                                        Capsule()
                                            .stroke(Color.orange.opacity(0.2), lineWidth: 0.5)
                                    )
                            )
                        }
                    }
                    
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundColor(DS.Adaptive.textSecondary)
                        .lineLimit(1)
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            
            // Accent line divider with gradient
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [iconColor.opacity(0.4), iconColor.opacity(0.1), DS.Adaptive.divider],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 0.5)
            
            // Action Buttons Row - Compact
            HStack(spacing: 0) {
                // DIY Button
                NavigationLink(destination: diyDestination) {
                    HStack(spacing: 5) {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 11))
                            .foregroundColor(iconColor.opacity(0.8))
                        Text("Start")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        Rectangle()
                            .fill(DS.Adaptive.chipBackground.opacity(0.3))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(ScaleButtonStyle())
                
                // Vertical divider
                Rectangle()
                    .fill(DS.Adaptive.divider)
                    .frame(width: 0.5)
                
                // AI Assistant Button - Opens context-aware AI helper
                Button {
                    openAIHelper(with: aiContext)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                        Text("AI")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(chipGoldGradient)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        Rectangle()
                            .fill(BrandColors.goldBase.opacity(0.05))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(ScaleButtonStyle())
            }
            .clipShape(
                RoundedCorner(radius: 12, corners: [.bottomLeft, .bottomRight])
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [iconColor.opacity(0.2), iconColor.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
    }
    
    // MARK: - Helper Styles
    
    /// Custom button style with scale animation
    struct ScaleButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
                .opacity(configuration.isPressed ? 0.8 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
        }
    }
    
    /// Rounded corner shape for specific corners
    struct RoundedCorner: Shape {
        var radius: CGFloat = .infinity
        var corners: UIRectCorner = .allCorners
        
        func path(in rect: CGRect) -> Path {
            let path = UIBezierPath(
                roundedRect: rect,
                byRoundingCorners: corners,
                cornerRadii: CGSize(width: radius, height: radius)
            )
            return Path(path.cgPath)
        }
    }
    
    // MARK: - Quick Market Access (Enhanced with Live Data)
    
    private var quickMarketAccessSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(chipGoldGradient)
                    Text("Quick Access")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                
                Spacer()
                
                NavigationLink(destination: MarketView()) {
                    HStack(spacing: 3) {
                        Text("All Markets")
                            .font(.system(size: 11, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(chipGoldGradient)
                }
            }
            .padding(.horizontal, 16)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    enhancedQuickCoinCard(symbol: "BTC", name: "Bitcoin", color: .orange)
                    enhancedQuickCoinCard(symbol: "ETH", name: "Ethereum", color: .blue)
                    enhancedQuickCoinCard(symbol: "SOL", name: "Solana", color: .purple)
                    enhancedQuickCoinCard(symbol: "BNB", name: "BNB", color: .yellow)
                    enhancedQuickCoinCard(symbol: "XRP", name: "XRP", color: .gray)
                }
                .padding(.horizontal, 16)
            }
        }
    }
    
    private func enhancedQuickCoinCard(symbol: String, name: String, color: Color) -> some View {
        // Look up live price data from MarketViewModel
        let coin = marketVM.allCoins.first { $0.symbol.uppercased() == symbol.uppercased() }
        let price = coin?.priceUsd
        let change24h = coin?.priceChangePercentage24hInCurrency
        let isPositive = (change24h ?? 0) >= 0
        
        return NavigationLink(destination: TradeView(symbol: symbol, showBackButton: true)) {
            VStack(spacing: 6) {
                // Coin logo with premium glow effect
                ZStack {
                    // Outer glow
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [color.opacity(0.25), color.opacity(0.08), Color.clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 22
                            )
                        )
                        .frame(width: 44, height: 44)
                    
                    // Inner circle
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.25), color.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 38, height: 38)
                    
                    CoinImageView(
                        symbol: symbol,
                        url: coinLogoURL(for: symbol),
                        size: 26
                    )
                }
                
                VStack(spacing: 2) {
                    Text(symbol)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    // Live price
                    if let price = price {
                        Text(formatQuickPrice(price))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(DS.Adaptive.textSecondary)
                            .monospacedDigit()
                    } else {
                        Text(name)
                            .font(.system(size: 9))
                            .foregroundColor(DS.Adaptive.textTertiary)
                            .lineLimit(1)
                    }
                    
                    // 24h change badge
                    if let change = change24h {
                        Text("\(isPositive ? "+" : "")\(String(format: "%.1f", change))%")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(isPositive ? .green : .red)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill((isPositive ? Color.green : Color.red).opacity(0.12))
                            )
                    }
                }
            }
            .frame(width: 78)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    // Base background
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(DS.Adaptive.cardBackground)
                    
                    // Top glass highlight
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.05 : 0.3),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [color.opacity(0.35), color.opacity(0.1), color.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
    
    /// Format price for quick access display (compact)
    private func formatQuickPrice(_ price: Double) -> String {
        if price >= 10000 {
            return "$\(String(format: "%.0f", price / 1000))K"
        } else if price >= 1000 {
            return "$\(String(format: "%.1f", price / 1000))K"
        } else if price >= 1 {
            return "$\(String(format: "%.2f", price))"
        } else if price >= 0.01 {
            return "$\(String(format: "%.3f", price))"
        } else {
            return "$\(String(format: "%.4f", price))"
        }
    }
    
    /// Get coin logo URL for common symbols
    private func coinLogoURL(for symbol: String) -> URL? {
        let coinGeckoIDs: [String: String] = [
            "BTC": "1",
            "ETH": "279",
            "SOL": "4128",
            "BNB": "825",
            "XRP": "44",
            "ADA": "975",
            "DOGE": "5",
            "MATIC": "3890"
        ]
        guard let id = coinGeckoIDs[symbol.uppercased()] else { return nil }
        return URL(string: "https://coin-images.coingecko.com/coins/images/\(id)/large/\(symbol.lowercased()).png")
    }
    
    // MARK: - Active Bots Summary Card (Enhanced)
    
    private var activeBotsSummaryCard: some View {
        NavigationLink(destination: BotHubView()) {
            HStack(spacing: 12) {
                // Icon with animated pulse indicator
                ZStack {
                    // Background glow
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.purple.opacity(0.2), Color.clear],
                                center: .center,
                                startRadius: 12,
                                endRadius: 24
                            )
                        )
                        .frame(width: 44, height: 44)
                    
                    // Icon background
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.25), Color.purple.opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.purple)
                    
                    // Running indicator with glow
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.3))
                            .frame(width: 12, height: 12)
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                    }
                    .overlay(Circle().stroke(DS.Adaptive.cardBackground, lineWidth: 2).frame(width: 10, height: 10))
                    .offset(x: 14, y: -14)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("\(runningBotCount) Bot\(runningBotCount > 1 ? "s" : "") Running")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        // Active indicator pill
                        Text("ACTIVE")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.green.opacity(0.15))
                            )
                    }
                    Text("Tap to manage your active bots")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                
                Spacer()
                
                // Enhanced chevron
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.1))
                        .frame(width: 28, height: 28)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.purple)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.green.opacity(0.25), Color.purple.opacity(0.15)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .padding(.horizontal, 16)
    }
    
    // MARK: - Legacy Dashboard Content (kept for reference but not used)
    
    private var legacyDashboardContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 1. AI Suggestion Card - MOST PROMINENT (proactive AI)
                aiSuggestionCard
                
                // 2. Quick Actions - ONE TAP to common actions
                quickActionsRow
                
                // 3. Active Bots Widget (inline controls)
                if !displayedBots.isEmpty {
                    activeBotsWidget
                }
                
                // 4. Explore More - Secondary navigation
                exploreSectionCards
                
                // 5. Recent Activity
                if !viewModel.recentActivity.isEmpty {
                    dashboardRecentActivitySection
                }
                
                Spacer(minLength: 80)
            }
            .padding(.vertical, 12)
        }
    }
    
    // MARK: - AI Suggestion Card (Prominent - Based on Research)
    
    private var aiSuggestionCard: some View {
        Button {
            openAIHelper(with: .general)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                // Header with enhanced styling
                HStack(spacing: 12) {
                    ZStack {
                        // Outer glow ring
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [BrandColors.goldLight.opacity(0.3), Color.clear],
                                    center: .center,
                                    startRadius: 16,
                                    endRadius: 28
                                )
                            )
                            .frame(width: 48, height: 48)
                        
                        // Main circle
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [BrandColors.goldLight, BrandColors.goldBase],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: "sparkles")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.black)
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("CryptoSage AI")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        Text("Your Trading Assistant")
                            .font(.system(size: 12))
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                    
                    Spacer()
                    
                    // Arrow indicator with gold accent
                    ZStack {
                        Circle()
                            .fill(DS.Adaptive.chipBackground)
                            .frame(width: 28, height: 28)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(chipGoldGradient)
                    }
                }
                
                // AI Suggestion/Greeting with better typography
                Text(getContextualSuggestion())
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DS.Adaptive.textPrimary.opacity(0.9))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(2)
                
                // Quick action buttons within AI card - improved styling
                HStack(spacing: 8) {
                    aiQuickActionChip(text: "Market analysis", icon: "chart.xyaxis.line")
                    aiQuickActionChip(text: "Setup a bot", icon: "cpu")
                    aiQuickActionChip(text: "Portfolio advice", icon: "briefcase")
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        BrandColors.goldLight.opacity(0.6),
                                        BrandColors.goldBase.opacity(0.4),
                                        BrandColors.goldDark.opacity(0.2)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }
    
    private func aiQuickActionChip(text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
            Text(text)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(DS.Adaptive.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(DS.Adaptive.chipBackground)
        )
        .overlay(
            Capsule()
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
    }
    
    private func getContextualSuggestion() -> String {
        // Dynamic suggestions based on user state
        if runningBotCount > 0 {
            return "You have \(runningBotCount) bot\(runningBotCount > 1 ? "s" : "") running. Tap to check performance or get optimization tips."
        } else if totalBotCount == 0 {
            return "Ready to automate your trading? I can help you set up your first bot in under a minute."
        } else {
            return "Hey! I can help with market analysis, bot setup, or trading strategies. What would you like to do?"
        }
    }
    
    // MARK: - Quick Actions Row (ONE TAP to trade)
    
    private var quickActionsRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DS.Adaptive.textSecondary)
                .padding(.horizontal, 16)
            
            HStack(spacing: 12) {
                // Buy Button - Direct to trade with enhanced styling
                NavigationLink(destination: TradeView(symbol: "BTC", showBackButton: true)) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                        Text("Buy")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundColor(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.green, Color.green.opacity(0.85)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                }
                
                // Sell Button - Direct to trade with enhanced styling
                NavigationLink(destination: TradeView(symbol: "BTC", showBackButton: true)) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                        Text("Sell")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundColor(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.red.opacity(0.9), Color.red.opacity(0.75)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                }
                
                // Bot Menu - Dropdown with direct links to bot types
                Menu {
                    // DCA Bot - direct to form
                    Button {
                        navigateToDCABot = true
                    } label: {
                        Label("DCA Bot", systemImage: "repeat.circle.fill")
                    }
                    
                    // Grid Bot - direct to form
                    Button {
                        navigateToGridBot = true
                    } label: {
                        Label("Grid Bot", systemImage: "square.grid.3x3.fill")
                    }
                    
                    // Signal Bot - direct to form
                    Button {
                        navigateToSignalBot = true
                    } label: {
                        Label("Signal Bot", systemImage: "bolt.circle.fill")
                    }
                    
                    Divider()
                    
                    // AI Assisted - opens AI helper sheet for bot setup
                    Button {
                        openAIHelper(with: .bots)
                    } label: {
                        Label("Ask AI", systemImage: "sparkles")
                    }
                    
                    Divider()
                    
                    // View all bots
                    NavigationLink(destination: BotHubView()) {
                        Label("My Bots", systemImage: "list.bullet")
                    }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "cpu")
                            .font(.system(size: 20, weight: .semibold))
                        HStack(spacing: 2) {
                            Text("Bot")
                                .font(.system(size: 11, weight: .bold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                    }
                    .frame(width: 64)
                    .padding(.vertical, 12)
                    .foregroundColor(.purple)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.purple.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.purple.opacity(0.35), lineWidth: 1.5)
                    )
                }
            }
            .padding(.horizontal, 16)
            
        }
        // Hidden navigation destinations for programmatic navigation
        .navigationDestination(isPresented: $navigateToDCABot) {
            TradingBotView(initialMode: .dcaBot)
        }
        .navigationDestination(isPresented: $navigateToGridBot) {
            TradingBotView(initialMode: .gridBot)
        }
        .navigationDestination(isPresented: $navigateToSignalBot) {
            TradingBotView(initialMode: .signalBot)
        }
    }
    
    // MARK: - Active Bots Widget (Inline Controls)
    
    private var activeBotsWidget: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.purple)
                    Text("Active Bots")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    // Running indicator
                    if runningBotCount > 0 {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                            Text("\(runningBotCount) running")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.green)
                        }
                    }
                }
                Spacer()
                NavigationLink(destination: BotHubView()) {
                    Text("Manage")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(chipGoldGradient)
                }
            }
            .padding(.horizontal, 16)
            
            // Compact bot cards with inline toggle
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(displayedBots.prefix(4)) { bot in
                        compactBotCard(bot)
                    }
                    
                    // Add bot card - Navigate to bot type selection
                    NavigationLink(destination: BotsSectionView()) {
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(DS.Adaptive.chipBackground)
                                    .frame(width: 44, height: 44)
                                Image(systemName: "plus")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(chipGoldGradient)
                            }
                            Text("New Bot")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(DS.Adaptive.textSecondary)
                        }
                        .frame(width: 90)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(DS.Adaptive.cardBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                                        .foregroundColor(DS.Adaptive.stroke)
                                )
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
    
    private func compactBotCard(_ bot: PaperBot) -> some View {
        VStack(spacing: 8) {
            // Bot icon with status indicator
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    Circle()
                        .fill(bot.type.color.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: bot.type.icon)
                        .font(.system(size: 18))
                        .foregroundColor(bot.type.color)
                }
                
                // Status dot
                Circle()
                    .fill(bot.status == .running ? Color.green : Color.gray)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(DS.Adaptive.cardBackground, lineWidth: 2)
                    )
                    .offset(x: 2, y: 2)
            }
            
            // Bot name
            Text(bot.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
                .lineLimit(1)
            
            // P/L
            Text(formatProfitLoss(bot.totalProfit))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(bot.totalProfit >= 0 ? .green : .red)
            
            // Toggle button
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                paperBotManager.toggleBot(id: bot.id)
            } label: {
                Text(bot.status == .running ? "Pause" : "Start")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(bot.status == .running ? .orange : .green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill((bot.status == .running ? Color.orange : Color.green).opacity(0.15))
                    )
            }
        }
        .frame(width: 90)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(bot.status == .running ? Color.green.opacity(0.3) : DS.Adaptive.stroke, lineWidth: 1)
        )
    }
    
    // MARK: - Explore Section Cards (Secondary Navigation)
    
    private var exploreSectionCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Explore")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.Adaptive.textSecondary)
                .padding(.horizontal, 16)
            
            // Horizontal scroll of feature cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Derivatives Card
                    NavigationLink(destination: DerivativesSectionView()) {
                        exploreFeatureCard(
                            title: "Derivatives",
                            subtitle: "Leverage trading",
                            icon: "chart.line.uptrend.xyaxis",
                            color: .orange,
                            warning: "High Risk"
                        )
                    }
                    
                    // Predictions Card
                    NavigationLink(destination: PredictionsSectionView()) {
                        exploreFeatureCard(
                            title: "Predictions",
                            subtitle: "Polymarket & Kalshi",
                            icon: "chart.bar.xaxis.ascending",
                            color: .cyan,
                            warning: nil
                        )
                    }
                    
                    // Markets Card
                    NavigationLink(destination: MarketView()) {
                        exploreFeatureCard(
                            title: "Markets",
                            subtitle: "Browse all coins",
                            icon: "chart.bar.fill",
                            color: .blue,
                            warning: nil
                        )
                    }
                    
                    // Bot Hub Card
                    NavigationLink(destination: BotHubView()) {
                        exploreFeatureCard(
                            title: "Bot Hub",
                            subtitle: "Manage all bots",
                            icon: "cpu",
                            color: .purple,
                            warning: nil
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
    
    private func exploreFeatureCard(title: String, subtitle: String, icon: String, color: Color, warning: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Enhanced icon container with gradient background
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.2), color.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(color)
                }
                
                Spacer()
                
                if let warning = warning {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 8))
                        Text(warning)
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.orange.opacity(0.15))
                            .overlay(
                                Capsule()
                                    .stroke(Color.orange.opacity(0.3), lineWidth: 0.5)
                            )
                    )
                }
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(width: 140)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(color.opacity(0.15), lineWidth: 1)
        )
    }
    
    // MARK: - Dashboard Recent Activity Section
    
    private var dashboardRecentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 12))
                        .foregroundStyle(chipGoldGradient)
                    Text("Recent Activity")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            
            VStack(spacing: 8) {
                ForEach(viewModel.recentActivity.prefix(3)) { item in
                    dashboardActivityRow(item)
                }
            }
        }
    }
    
    private func dashboardActivityRow(_ item: RecentActivityItem) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(item.iconColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: item.icon)
                    .font(.system(size: 14))
                    .foregroundColor(item.iconColor)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            Spacer()
            
            Text(formatActivityTime(item.timestamp))
                .font(.system(size: 10))
                .foregroundColor(DS.Adaptive.textTertiary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }
    
    private func formatActivityTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    // MARK: - Header Section (Premium Design)
    
    @State private var headerGlowPhase: Double = 0
    
    private var headerSection: some View {
        VStack(spacing: 0) {
            HStack {
                // Back button - context-aware
                CSNavButton(
                    icon: "chevron.left",
                    action: {
                        if viewModel.selectedMode == .assistant {
                            dismiss()
                        } else {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.selectedMode = .assistant
                            }
                        }
                    }
                )
                
                // Mode badge - consolidated single location for trading mode indicator
                headerModeBadge
                
                Spacer()
                
                // Title - shows current mode when not on dashboard
                HStack(spacing: 8) {
                    ZStack {
                        // Glow effect behind icon
                        Image(systemName: viewModel.selectedMode == .assistant ? "sparkles" : viewModel.selectedMode.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(viewModel.selectedMode == .assistant ? BrandColors.goldLight : viewModel.selectedMode.color)
                            .opacity(0.6)
                        
                        Image(systemName: viewModel.selectedMode == .assistant ? "sparkles" : viewModel.selectedMode.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(viewModel.selectedMode == .assistant ? chipGoldGradient : LinearGradient(colors: [viewModel.selectedMode.color, viewModel.selectedMode.color.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    
                    Text(viewModel.selectedMode == .assistant ? "Smart Trading" : viewModel.selectedMode.displayName)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                
                Spacer()
                
                // Settings button with premium styling
                NavigationLink(destination: TradingSettingsView()) {
                    ZStack {
                        Circle()
                            .fill(DS.Adaptive.chipBackground)
                            .frame(width: 36, height: 36)
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 8)
            
            // Accent underline - color matches current mode
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            (viewModel.selectedMode == .assistant ? BrandColors.goldBase : viewModel.selectedMode.color).opacity(0.4),
                            (viewModel.selectedMode == .assistant ? BrandColors.goldLight : viewModel.selectedMode.color).opacity(0.6),
                            (viewModel.selectedMode == .assistant ? BrandColors.goldBase : viewModel.selectedMode.color).opacity(0.4),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .padding(.horizontal, 40)
        }
    }
    
    // MARK: - Quick Stats Bar (Premium Glass Design)
    
    @State private var marketPulseScale: CGFloat = 1.0
    
    /// Current trading mode for display purposes
    private var currentTradingMode: TradingModeType {
        if AppConfig.liveTradingEnabled {
            return .live
        } else if PaperTradingManager.isEnabled {
            return .paper
        } else if DemoModeManager.isEnabled {
            return .demo
        } else {
            return .advisory
        }
    }
    
    private enum TradingModeType {
        case live, paper, demo, advisory
        
        var displayName: String {
            switch self {
            case .live: return "Live Trading"
            case .paper: return "Paper Trading"
            case .demo: return "Demo Mode"
            case .advisory: return "Advisory"
            }
        }
        
        var icon: String {
            switch self {
            case .live: return "bolt.fill"
            case .paper: return "doc.text.fill"
            case .demo: return AppTradingMode.demo.icon
            case .advisory: return "lightbulb.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .live: return AppTradingMode.liveTrading.color
            case .paper: return AppTradingMode.paper.color
            case .demo: return AppTradingMode.demo.color  // Gold (single source of truth)
            case .advisory: return .purple
            }
        }
        
        /// Maps to AppTradingMode for use with the shared ModeBadge
        var appMode: AppTradingMode {
            switch self {
            case .live: return .liveTrading
            case .paper: return .paper
            case .demo: return .demo
            case .advisory: return .portfolio
            }
        }
    }
    
    private var quickStatsBar: some View {
        VStack(spacing: 8) {
            // Main stats card - Premium glass design (hidden in demo/advisory mode)
            if currentTradingMode == .paper || currentTradingMode == .live {
                mainStatsCard
            } else {
                // Demo/Advisory mode - show simplified view
                demoModeStatsCard
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    /// Compact mode badge for inline display — uses shared ModeBadge for consistency
    private var compactModeBadge: some View {
        ModeBadge(mode: currentTradingMode.appMode, variant: .compact)
    }
    
    /// Header mode badge - single consolidated location for trading mode indicator
    private var headerModeBadge: some View {
        ModeBadge(mode: currentTradingMode.appMode, variant: .compact)
            .padding(.leading, 6)
    }
    
    /// Full stats card for Paper/Live trading modes
    private var mainStatsCard: some View {
        VStack(spacing: 8) {
            VStack(spacing: 0) {
                // Mode badge moved to header - just show DEV indicator for live mode if needed
                if currentTradingMode == .live {
                    HStack {
                        Spacer()
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                            Text("DEV")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.green)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.green.opacity(0.12))
                        )
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
                }
                
                // Stats row
                HStack(spacing: 0) {
                    // Paper balance - PRIMARY stat with gold accent
                    premiumStatPill(
                        icon: "banknote.fill",
                        label: "BALANCE",
                        value: formatBalance(viewModel.paperBalance),
                        color: BrandColors.goldBase,
                        isPrimary: true
                    )
                    
                    premiumStatDivider
                    
                    // P/L indicator with dynamic color
                    let pnlColor: Color = viewModel.todayPnL >= 0 ? .green : .red
                    let pnlPrefix = viewModel.todayPnL >= 0 ? "+" : ""
                    premiumStatPill(
                        icon: viewModel.todayPnL >= 0 ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis",
                        label: "TODAY",
                        value: "\(pnlPrefix)\(formatBalance(viewModel.todayPnL))",
                        color: pnlColor,
                        isPrimary: false
                    )
                    
                    premiumStatDivider
                    
                    // Active bots with animated pulse indicator
                    ZStack(alignment: .topTrailing) {
                        premiumStatPill(
                            icon: "gearshape.2.fill",
                            label: "BOTS",
                            value: "\(viewModel.activeBots)",
                            color: .purple,
                            isPrimary: false
                        )
                        
                        // Animated running indicator
                        if viewModel.activeBots > 0 {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [Color.green, Color.green.opacity(0.6)],
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: 4
                                    )
                                )
                                .frame(width: 8, height: 8)
                                .overlay(
                                    Circle()
                                        .stroke(DS.Adaptive.cardBackground, lineWidth: 1.5)
                                )
                                .offset(x: -6, y: 4)
                        }
                    }
                    
                    premiumStatDivider
                    
                    // Positions
                    premiumStatPill(
                        icon: "arrow.triangle.swap",
                        label: "POSITIONS",
                        value: "\(viewModel.openPositions)",
                        color: .orange,
                        isPrimary: false
                    )
                }
                .padding(.vertical, 8)
            }
            .background(
                ZStack {
                    // Base glass background
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(DS.Adaptive.cardBackground)
                    
                    // Top highlight for glass effect
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.06 : 0.4),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                DS.Adaptive.stroke.opacity(0.8),
                                DS.Adaptive.stroke.opacity(0.3),
                                DS.Adaptive.stroke.opacity(0.5)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            
            // Market Condition Indicator with pulse animation
            marketConditionIndicator
            
            // Recent activity - only show on main dashboard (assistant mode), not on sub-pages
            // Sub-pages have their own context-specific sections (Recent Backtests, Recent Trades, etc.)
            if viewModel.selectedMode == .assistant && !viewModel.recentActivity.isEmpty {
                recentActivitySection
            }
        }
    }
    
    /// Check if user has a connected portfolio (view-only, not trading)
    private var hasConnectedPortfolio: Bool {
        // Check if any exchange is connected for portfolio viewing
        !ConnectedAccountsManager.shared.accounts.isEmpty
    }
    
    /// Simplified stats card for Demo/Advisory modes
    private var demoModeStatsCard: some View {
        VStack(spacing: 8) {
            VStack(spacing: 0) {
                // Mode badge moved to header - content row only
                HStack(spacing: 12) {
                    Image(systemName: currentTradingMode == .demo ? "info.circle.fill" : (hasConnectedPortfolio ? "eye.fill" : "lightbulb.fill"))
                        .font(.system(size: 16))
                        .foregroundColor(currentTradingMode.color)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        if currentTradingMode == .demo {
                            Text("Explore Smart Trading Features")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(DS.Adaptive.textPrimary)
                            Text("Sample bots and data shown for exploration")
                                .font(.system(size: 12))
                                .foregroundColor(DS.Adaptive.textSecondary)
                        } else {
                            // Advisory mode - different message based on portfolio connection
                            Text(hasConnectedPortfolio ? "Portfolio Connected" : "Get Started")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(DS.Adaptive.textPrimary)
                            Text(hasConnectedPortfolio 
                                 ? "AI can analyze your holdings and give personalized advice"
                                 : "Enable Paper Trading to practice with virtual funds")
                                .font(.system(size: 12))
                                .foregroundColor(DS.Adaptive.textSecondary)
                        }
                    }
                    
                    Spacer()
                    
                    if currentTradingMode == .advisory {
                        if hasConnectedPortfolio {
                            // User has portfolio - they can get advice, offer paper trading as option
                            Button {
                                openAIHelper(with: .general)
                            } label: {
                                Text("Get Advice")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(BrandColors.goldBase)
                                    )
                            }
                            .buttonStyle(.plain)
                        } else {
                            // No portfolio - suggest enabling paper trading
                            Button {
                                if PaperTradingManager.shared.hasAccess {
                                    PaperTradingManager.shared.enablePaperTrading()
                                }
                            } label: {
                                Text("Enable Paper")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(Color.blue)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(currentTradingMode.color.opacity(0.2), lineWidth: 1)
                    )
            )
            
            // Market Condition Indicator (still show in demo mode)
            marketConditionIndicator
        }
    }
    
    // MARK: - Market Condition Indicator
    
    /// BTC trend indicator based on 24h price change (proxy for 10/20 SMA condition)
    private var marketConditionIndicator: some View {
        let btcCoin = marketVM.allCoins.first { $0.symbol.uppercased() == "BTC" }
        let btcChange = btcCoin?.priceChangePercentage24hInCurrency ?? 0
        let isBullish = btcChange >= 0
        
        return HStack(spacing: 10) {
            // BTC Icon with glow
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 22, height: 22)
                Image(systemName: "bitcoinsign.circle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.orange)
            }
            
            // Market condition label with animated pulse dot
            HStack(spacing: 5) {
                // Animated pulse indicator
                ZStack {
                    Circle()
                        .fill((isBullish ? Color.green : Color.red).opacity(0.3))
                        .frame(width: 12, height: 12)
                        .scaleEffect(marketPulseScale)
                    Circle()
                        .fill(isBullish ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                }
                .onAppear {
                    withAnimation(
                        Animation.easeInOut(duration: 1.5)
                            .repeatForever(autoreverses: true)
                    ) {
                        marketPulseScale = 1.4
                    }
                }
                
                Text("Market:")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Adaptive.textSecondary)
                
                Text(isBullish ? "Bullish" : "Cautious")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isBullish ? .green : .red)
            }
            
            Spacer()
            
            // BTC 24h change with better formatting
            if let btcCoin = btcCoin, let price = btcCoin.priceUsd {
                HStack(spacing: 6) {
                    Text("BTC")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    
                    Text(formatQuickPrice(price))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .monospacedDigit()
                    
                    // Change badge
                    Text("\(btcChange >= 0 ? "+" : "")\(String(format: "%.1f", btcChange))%")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(isBullish ? .green : .red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill((isBullish ? Color.green : Color.red).opacity(0.12))
                        )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Adaptive.chipBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            (isBullish ? Color.green : Color.red).opacity(0.35),
                            (isBullish ? Color.green : Color.red).opacity(0.1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 0.5
                )
        )
        .padding(.horizontal, 16)
    }
    
    private var premiumStatDivider: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        DS.Adaptive.divider.opacity(0.2),
                        DS.Adaptive.divider.opacity(0.5),
                        DS.Adaptive.divider.opacity(0.2)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 1, height: 36)
    }
    
    private func premiumStatPill(icon: String, label: String, value: String, color: Color, isPrimary: Bool) -> some View {
        VStack(spacing: 4) {
            // Icon + Value row
            HStack(spacing: 5) {
                // Icon with subtle glow
                ZStack {
                    if isPrimary {
                        Circle()
                            .fill(color.opacity(0.15))
                            .frame(width: 20, height: 20)
                    }
                    Image(systemName: icon)
                        .font(.system(size: isPrimary ? 12 : 10, weight: .semibold))
                        .foregroundColor(color)
                }
                
                Text(value)
                    .font(.system(size: isPrimary ? 17 : 14, weight: .bold, design: .rounded))
                    .foregroundColor(isPrimary ? color : DS.Adaptive.textPrimary)
                    .monospacedDigit()
            }
            
            // Label
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(DS.Adaptive.textTertiary)
                .tracking(0.8)
        }
        .frame(maxWidth: .infinity)
    }
    
    // Keep old function for backwards compatibility
    private var enhancedStatDivider: some View { premiumStatDivider }
    
    private func enhancedStatCard(icon: String, label: String, value: String, color: Color, isPrimary: Bool) -> some View {
        premiumStatPill(icon: icon, label: label.uppercased(), value: value, color: color, isPrimary: isPrimary)
    }
    
    // MARK: - Recent Activity Section (Enhanced with Timestamps)
    
    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(chipGoldGradient)
                    Text("Recent Activity")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textSecondary)
                    
                    // Activity count badge
                    if viewModel.recentActivity.count > 1 {
                        Text("\(viewModel.recentActivity.count)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(BrandColors.goldBase)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(BrandColors.goldBase.opacity(0.15))
                            )
                    }
                }
                Spacer()
                
                // Scroll hint for more items
                if viewModel.recentActivity.count > 2 {
                    HStack(spacing: 2) {
                        Text("Scroll")
                            .font(.system(size: 9, weight: .medium))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundColor(DS.Adaptive.textTertiary)
                }
            }
            .padding(.horizontal, 16)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.recentActivity, id: \.id) { item in
                        recentActivityCard(item)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
    
    private func recentActivityCard(_ item: RecentActivityItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                // Left accent bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [item.iconColor, item.iconColor.opacity(0.5)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3, height: 32)
                
                // Icon with enhanced glow
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [item.iconColor.opacity(0.25), item.iconColor.opacity(0.08), Color.clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 18
                            )
                        )
                        .frame(width: 36, height: 36)
                    
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [item.iconColor.opacity(0.25), item.iconColor.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 30, height: 30)
                    
                    Image(systemName: item.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(item.iconColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .lineLimit(1)
                    Text(item.subtitle)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(item.iconColor)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)
            
            // Timestamp footer
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 8))
                Text(formatRelativeTime(item.timestamp))
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(DS.Adaptive.textTertiary)
            .padding(.leading, 17)
            .padding(.trailing, 12)
            .padding(.bottom, 8)
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
                
                // Top glass highlight
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.04 : 0.25),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [item.iconColor.opacity(0.2), item.iconColor.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
    }
    
    /// Format timestamp as relative time (e.g., "2m ago", "1h ago")
    private func formatRelativeTime(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
    
    // MARK: - Main Content
    
    @ViewBuilder
    private var mainContent: some View {
        switch viewModel.selectedMode {
        case .assistant:
            // Universal AI assistant - chat with welcome header
            assistantModeContent
            
        case .spot:
            // Spot trading - dashboard first with AI helper
            spotModeContent
            
        case .bots:
            // Bot creation with AI assistance
            botModeContent
            
        case .strategies:
            // Algorithmic trading strategies - build, backtest, deploy
            strategiesModeContent
            
        case .derivatives:
            // Derivatives trading
            derivativesModeContent
            
        case .predictions:
            // Prediction markets
            predictionsModeContent
        }
    }
    
    // MARK: - Spot Mode Content (Dashboard-First)
    
    private var spotModeContent: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: 16) {
                    // Quick Trade Cards (prominent at top)
                    quickTradeSection
                    
                    // Recent Trades Section
                    recentTradesSection
                    
                    // Markets Browse Section
                    marketsBrowseSection
                    
                    Spacer(minLength: 80) // Space for floating button
                }
                .padding(.vertical, 12)
            }
            
            // Floating AI Helper Button
            aiHelperFloatingButton
        }
    }
    
    // MARK: - Quick Trade Section
    
    private var quickTradeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Text("Quick Trade")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Spacer()
                NavigationLink(destination: MarketView()) {
                    HStack(spacing: 4) {
                        Text("All Markets")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(chipGoldGradient)
                }
            }
            .padding(.horizontal, 16)
            
            // Top coins horizontal scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    NavigationLink(destination: TradeView(symbol: "BTC", showBackButton: true)) {
                        quickTradeCoinCard(symbol: "BTC", name: "Bitcoin", color: .orange)
                    }
                    
                    NavigationLink(destination: TradeView(symbol: "ETH", showBackButton: true)) {
                        quickTradeCoinCard(symbol: "ETH", name: "Ethereum", color: .blue)
                    }
                    
                    NavigationLink(destination: TradeView(symbol: "SOL", showBackButton: true)) {
                        quickTradeCoinCard(symbol: "SOL", name: "Solana", color: .purple)
                    }
                    
                    NavigationLink(destination: TradeView(symbol: "BNB", showBackButton: true)) {
                        quickTradeCoinCard(symbol: "BNB", name: "Binance", color: .yellow)
                    }
                }
                .padding(.horizontal, 16)
            }
            
            // Buy/Sell buttons row
            HStack(spacing: 12) {
                NavigationLink(destination: TradeView(symbol: "BTC", showBackButton: true)) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 18))
                        Text("Buy")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundColor(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.green)
                    )
                }
                
                NavigationLink(destination: TradeView(symbol: "BTC", showBackButton: true)) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 18))
                        Text("Sell")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundColor(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.red)
                    )
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    private func quickTradeCoinCard(symbol: String, name: String, color: Color) -> some View {
        VStack(spacing: 8) {
            // Coin icon placeholder
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                Text(String(symbol.prefix(1)))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(color)
            }
            
            VStack(spacing: 2) {
                Text(symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Text(name)
                    .font(.system(size: 10))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
        }
        .frame(width: 80)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
    }
    
    // MARK: - Recent Trades Section
    
    private var recentTradesSection: some View {
        let recentTrades = PaperTradingManager.shared.recentTrades(limit: 3)
        
        return VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                    Text("Recent Trades")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            
            if recentTrades.isEmpty {
                // Empty state
                VStack(spacing: 10) {
                    Image(systemName: "arrow.left.arrow.right.circle")
                        .font(.system(size: 28))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    Text("No trades yet")
                        .font(.system(size: 13))
                        .foregroundColor(DS.Adaptive.textSecondary)
                    Text("Your trading history will appear here")
                        .font(.system(size: 11))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(DS.Adaptive.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(DS.Adaptive.stroke, lineWidth: 1)
                )
                .padding(.horizontal, 16)
            } else {
                // Recent trades list
                VStack(spacing: 8) {
                    ForEach(recentTrades.prefix(3), id: \.id) { trade in
                        recentTradeRow(trade)
                    }
                }
            }
        }
    }
    
    private func recentTradeRow(_ trade: PaperTrade) -> some View {
        HStack(spacing: 12) {
            // Trade direction icon
            ZStack {
                Circle()
                    .fill((trade.side == .buy ? Color.green : Color.red).opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: trade.side == .buy ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(trade.side == .buy ? .green : .red)
            }
            
            // Trade info
            VStack(alignment: .leading, spacing: 2) {
                Text("\(trade.side == .buy ? "Buy" : "Sell") \(trade.symbol)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Text(formatTradeTime(trade.timestamp))
                    .font(.system(size: 10))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            Spacer()
            
            // Trade value
            Text(formatTradeValue(trade.totalValue))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(DS.Adaptive.textPrimary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }
    
    private func formatTradeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func formatTradeValue(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "$%.1fK", value / 1000)
        }
        return String(format: "$%.2f", value)
    }
    
    // MARK: - Markets Browse Section
    
    private var marketsBrowseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            Text("Explore")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
                .padding(.horizontal, 16)
            
            // Market categories
            VStack(spacing: 10) {
                NavigationLink(destination: MarketView()) {
                    marketCategoryRow(
                        icon: "chart.bar.fill",
                        iconColor: .purple,
                        title: "All Markets",
                        subtitle: "Browse all available cryptocurrencies"
                    )
                }
                
                NavigationLink(destination: MarketView()) {
                    marketCategoryRow(
                        icon: "flame.fill",
                        iconColor: .orange,
                        title: "Trending",
                        subtitle: "Most popular coins today"
                    )
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    private func marketCategoryRow(icon: String, iconColor: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.Adaptive.textTertiary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
    }
    
    // MARK: - Assistant Mode Content
    
    private var assistantModeContent: some View {
        VStack(spacing: 0) {
            // Welcome header with quick action suggestions
            assistantWelcomeHeader
            
            // AI Chat
            AiChatTabView(viewModel: aiChatVM)
        }
    }
    
    private var assistantWelcomeHeader: some View {
        VStack(spacing: 10) {
            // Quick action chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    assistantSuggestionChip(text: "Market analysis", icon: "chart.xyaxis.line")
                    assistantSuggestionChip(text: "Portfolio advice", icon: "briefcase.fill")
                    assistantSuggestionChip(text: "Set up a bot", icon: "cpu")
                    assistantSuggestionChip(text: "Risk assessment", icon: "exclamationmark.shield")
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 10)
        .background(
            Rectangle()
                .fill(DS.Adaptive.overlay(0.02))
                .overlay(
                    Rectangle()
                        .fill(DS.Adaptive.divider)
                        .frame(height: 1),
                    alignment: .bottom
                )
        )
    }
    
    private func assistantSuggestionChip(text: String, icon: String) -> some View {
        Button {
            aiChatVM.userInput = text
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(text)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(DS.Adaptive.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(DS.Adaptive.chipBackground)
            )
            .overlay(
                Capsule()
                    .stroke(DS.Adaptive.stroke, lineWidth: 1)
            )
        }
    }
    
    // MARK: - Bot Mode Content (Dashboard-First Approach)
    
    private var botModeContent: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: 16) {
                    // 1. Bot Stats Summary
                    botStatsSummaryCard
                    
                    // 2. Create New Bot Section (prominent)
                    createBotSection
                    
                    // 3. My Bots List
                    myBotsSection
                    
                    Spacer(minLength: 80) // Space for floating button
                }
                .padding(.vertical, 12)
            }
            
            // Floating AI Helper Button
            aiHelperFloatingButton
        }
    }
    
    // MARK: - Bot Stats Summary Card
    
    private var botStatsSummaryCard: some View {
        HStack(spacing: 0) {
            // Total bots
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .font(.system(size: 12))
                        .foregroundColor(.purple)
                    Text("\(totalBotCount)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                Text("Total")
                    .font(.system(size: 10))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .frame(maxWidth: .infinity)
            
            Rectangle()
                .fill(DS.Adaptive.divider)
                .frame(width: 1, height: 30)
            
            // Running
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                    Text("\(runningBotCount)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                Text("Running")
                    .font(.system(size: 10))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .frame(maxWidth: .infinity)
            
            Rectangle()
                .fill(DS.Adaptive.divider)
                .frame(width: 1, height: 30)
            
            // Total P/L
            VStack(spacing: 4) {
                Text(formatProfitLoss(totalBotProfit))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(totalBotProfit >= 0 ? .green : .red)
                Text("Total P/L")
                    .font(.system(size: 10))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }
    
    // MARK: - Create Bot Section
    
    private var createBotSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Text("Create New Bot")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Spacer()
                NavigationLink(destination: TradingBotView(side: .buy, orderType: .market, quantity: 0, slippage: 0.5)) {
                    HStack(spacing: 4) {
                        Text("Advanced")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(chipGoldGradient)
                }
            }
            .padding(.horizontal, 16)
            
            // Bot type cards - horizontal scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(QuickBotType.allCases, id: \.self) { botType in
                        NavigationLink(destination: TradingBotView(side: .buy, orderType: .market, quantity: 0, slippage: 0.5)) {
                            quickBotTypeCard(botType)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
    
    private func quickBotTypeCard(_ botType: QuickBotType) -> some View {
        VStack(spacing: 10) {
            // Icon
            ZStack {
                Circle()
                    .fill(botType.color.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: botType.icon)
                    .font(.system(size: 22))
                    .foregroundColor(botType.color)
            }
            
            // Text
            VStack(spacing: 2) {
                Text(botType.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Text(botType.subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
        }
        .frame(width: 100)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
    }
    
    // MARK: - My Bots Section
    
    private var myBotsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.purple)
                    Text("My Bots")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    if totalBotCount > 0 {
                        Text("(\(totalBotCount))")
                            .font(.system(size: 12))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                }
                Spacer()
                NavigationLink(destination: BotHubView()) {
                    HStack(spacing: 4) {
                        Text("View All")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(chipGoldGradient)
                }
            }
            .padding(.horizontal, 16)
            
            // Bot list or empty state
            if displayedBots.isEmpty {
                emptyBotsState
            } else {
                // Show first 3 bots inline
                VStack(spacing: 10) {
                    ForEach(displayedBots.prefix(3)) { bot in
                        inlineBotRow(bot)
                    }
                    
                    // Show "more" button if there are more bots
                    if displayedBots.count > 3 {
                        NavigationLink(destination: BotHubView()) {
                            HStack {
                                Spacer()
                                Text("+\(displayedBots.count - 3) more bots")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(DS.Adaptive.textSecondary)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11))
                                    .foregroundColor(DS.Adaptive.textTertiary)
                                Spacer()
                            }
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(DS.Adaptive.overlay(0.04))
                            )
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
    }
    
    private func inlineBotRow(_ bot: PaperBot) -> some View {
        HStack(spacing: 12) {
            // Bot icon
            ZStack {
                Circle()
                    .fill(bot.type.color.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: bot.type.icon)
                    .font(.system(size: 16))
                    .foregroundColor(bot.type.color)
            }
            
            // Bot info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(bot.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .lineLimit(1)
                    
                    // Status indicator
                    Circle()
                        .fill(bot.status == .running ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                }
                
                Text("\(bot.type.displayName) • \(bot.tradingPair.replacingOccurrences(of: "_", with: "/"))")
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            Spacer()
            
            // P/L
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatProfitLoss(bot.totalProfit))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(bot.totalProfit >= 0 ? .green : .red)
                Text("\(bot.totalTrades) trades")
                    .font(.system(size: 10))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            // Toggle button
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                paperBotManager.toggleBot(id: bot.id)
            } label: {
                Image(systemName: bot.status == .running ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(bot.status == .running ? .orange : .green)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(bot.status == .running ? Color.green.opacity(0.3) : DS.Adaptive.stroke, lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }
    
    private var emptyBotsState: some View {
        VStack(spacing: 14) {
            // Icon
            ZStack {
                Circle()
                    .fill(BrandColors.goldBase.opacity(0.1))
                    .frame(width: 60, height: 60)
                Image(systemName: "cpu")
                    .font(.system(size: 24))
                    .foregroundStyle(chipGoldGradient)
            }
            
            VStack(spacing: 4) {
                Text("No Bots Yet")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Text("Create your first bot to start automated trading")
                    .font(.system(size: 12))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            // Quick create CTA
            NavigationLink(destination: TradingBotView(side: .buy, orderType: .market, quantity: 0, slippage: 0.5)) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                    Text("Create Bot")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(AdaptiveGradients.goldButton(isDark: colorScheme == .dark))
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6]))
                        .foregroundColor(DS.Adaptive.stroke)
                )
        )
        .padding(.horizontal, 16)
    }
    
    // MARK: - AI Helper Floating Button
    
    /// Maps the current trading hub mode to the appropriate AI helper context
    private var currentAIContext: AIHelperContext {
        switch viewModel.selectedMode {
        case .assistant:
            return .general
        case .spot:
            return .spot
        case .bots:
            return .bots
        case .strategies:
            return .strategies
        case .derivatives:
            return .derivatives
        case .predictions:
            return .predictions
        }
    }
    
    /// Color for the floating AI button based on current mode
    private var aiButtonColor: Color {
        switch viewModel.selectedMode {
        case .assistant:
            return BrandColors.goldBase
        case .strategies:
            return .green
        case .bots:
            return .purple
        case .spot:
            return .blue
        case .derivatives:
            return .orange
        case .predictions:
            return .cyan
        }
    }
    
    private var aiHelperFloatingButton: some View {
        let isStrategiesMode = viewModel.selectedMode == .strategies
        let isBotsMode = viewModel.selectedMode == .bots
        _ = isStrategiesMode || isBotsMode
        
        // Use consistent gold styling for all modes
        return Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            openAIHelper(with: currentAIContext)
        } label: {
            HStack(spacing: 8) {
                // Sparkles icon - consistent across all modes
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                
                Text(isStrategiesMode ? "Strategy AI" : isBotsMode ? "Bot AI" : "Ask AI")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundColor(BrandColors.ctaTextColor(isDark: colorScheme == .dark))
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                ZStack {
                    // Base gold gradient - consistent CryptoSage AI branding
                    Capsule()
                        .fill(AdaptiveGradients.goldButton(isDark: colorScheme == .dark))
                    
                    // Glass highlight overlay
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.15),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
            )
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.2),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
        }
        .padding(.trailing, 16)
        .padding(.bottom, 16)
    }
    
    // MARK: - AI Helper Sheet
    
    private var aiHelperSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Custom header
                HStack {
                    Button {
                        viewModel.showAIHelperSheet = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(DS.Adaptive.textSecondary)
                            .padding(10)
                            .background(Circle().fill(DS.Adaptive.chipBackground))
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(chipGoldGradient)
                        Text("AI Assistant")
                            .font(.headline)
                            .foregroundColor(DS.Adaptive.textPrimary)
                    }
                    
                    Spacer()
                    
                    // Placeholder for symmetry
                    Color.clear.frame(width: 34, height: 34)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                Divider()
                    .background(DS.Adaptive.divider)
                
                // AI Chat
                AiChatTabView(viewModel: aiChatVM)
            }
            .background(DS.Adaptive.background.ignoresSafeArea())
        }
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.visible)
    }
    
    // MARK: - Helper Functions
    
    private func formatProfitLoss(_ value: Double) -> String {
        let prefix = value >= 0 ? "+" : ""
        let absValue = abs(value)
        if absValue >= 1000 {
            return "\(prefix)$\(String(format: "%.1fK", value / 1000))"
        }
        return "\(prefix)$\(String(format: "%.2f", value))"
    }
    
    // MARK: - Strategies Mode Content (Dashboard-First)
    
    // State for strategy mode navigation
    @State private var showStrategyBuilder: Bool = false
    @State private var showStrategyTemplates: Bool = false
    @State private var showStrategyLearningHub: Bool = false
    @State private var showBacktestResults: Bool = false
    
    // Strategy engine for active strategies
    @ObservedObject private var strategyEngine = StrategyEngine.shared
    @ObservedObject private var backtestEngine = BacktestEngine.shared
    
    private var strategiesModeContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 1. Strategy Stats Summary (includes mode indicator)
                strategyStatsSummaryCard
                
                // 2. CryptoSage AI Card - Strategy Advisor
                strategyAICard
                
                // 3. Quick Actions (Create, Templates, Learn)
                strategyQuickActionsSection
                
                // 4. Active Strategies List
                activeStrategiesSection
                
                // 5. Recent Backtest Results
                recentBacktestSection
                
                Spacer(minLength: 20)
            }
            .padding(.vertical, 12)
        }
        .sheet(isPresented: $showStrategyBuilder) {
            StrategyBuilderView()
        }
        .sheet(isPresented: $showStrategyTemplates) {
            StrategyTemplatesView()
        }
        .sheet(isPresented: $showStrategyLearningHub) {
            StrategyLearningHub(
                onCreateStrategy: {
                    showStrategyBuilder = true
                },
                onBrowseTemplates: {
                    showStrategyTemplates = true
                }
            )
        }
        .sheet(isPresented: $showBacktestResults) {
            if let latestBacktest = backtestEngine.backtestHistory.first {
                BacktestResultsView(result: latestBacktest)
            }
        }
    }
    
    // MARK: - Strategy Stats Summary Card
    
    private var strategyStatsSummaryCard: some View {
        // Mode badge is now in header - just show stats here
        VStack(spacing: 0) {
            // Stats row - clean, focused design
            HStack(spacing: 0) {
                // Total strategies
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "function")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                        Text("\(strategyEngine.activeStrategies.count)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                    }
                    Text("Strategies")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                .frame(maxWidth: .infinity)
                
                Rectangle()
                    .fill(DS.Adaptive.divider)
                    .frame(width: 1, height: 30)
                
                // Active/Enabled
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                        Text("\(strategyEngine.activeStrategies.filter { $0.isEnabled }.count)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                    }
                    Text("Active")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                .frame(maxWidth: .infinity)
                
                Rectangle()
                    .fill(DS.Adaptive.divider)
                    .frame(width: 1, height: 30)
                
                // Recent Signals
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                        Text("\(strategyEngine.recentSignals.count)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                    }
                    Text("Signals")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 14)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }
    
    // MARK: - Strategy AI Card (uses reusable component)
    
    private var strategyAICard: some View {
        PremiumAIAdvisorCard(
            context: .strategies,
            title: "Strategy Advisor",
            subtitle: "Build strategies with AI guidance"
        ) {
            openAIHelper(with: .strategies)
        }
    }
    
    // MARK: - Strategy Quick Actions Section
    
    private var strategyQuickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Action cards horizontal scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    // Create Strategy - PRIMARY CTA with gradient
                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        #endif
                        showStrategyBuilder = true
                    } label: {
                        strategyPrimaryActionCard(
                            icon: "plus.circle.fill",
                            title: "Create Strategy",
                            subtitle: "Build custom rules"
                        )
                    }
                    .buttonStyle(.plain)
                    
                    // Browse Templates
                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        #endif
                        showStrategyTemplates = true
                    } label: {
                        strategyActionCard(
                            icon: "doc.on.doc.fill",
                            title: "Templates",
                            subtitle: "Pre-built strategies",
                            color: .blue
                        )
                    }
                    .buttonStyle(.plain)
                    
                    // Learning Hub
                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        #endif
                        showStrategyLearningHub = true
                    } label: {
                        strategyActionCard(
                            icon: "book.fill",
                            title: "Learn",
                            subtitle: "Strategy guides",
                            color: .purple
                        )
                    }
                    .buttonStyle(.plain)
                    
                    // View Backtests
                    if !backtestEngine.backtestHistory.isEmpty {
                        Button {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            #endif
                            showBacktestResults = true
                        } label: {
                            strategyActionCard(
                                icon: "chart.line.uptrend.xyaxis",
                                title: "Backtests",
                                subtitle: "\(backtestEngine.backtestHistory.count) results",
                                color: .orange
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
    
    /// Primary action card with gold gradient - for Create Strategy CTA
    private func strategyPrimaryActionCard(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [BrandColors.goldLight.opacity(0.3), BrandColors.goldBase.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(chipGoldGradient)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [BrandColors.goldLight.opacity(0.08), BrandColors.goldBase.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [BrandColors.goldLight.opacity(0.35), BrandColors.goldBase.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
    
    private func strategyActionCard(icon: String, title: String, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
        }
        .frame(width: 100, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
    }
    
    // MARK: - Active Strategies Section
    
    private var activeStrategiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Text("My Strategies")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Spacer()
                if !strategyEngine.activeStrategies.isEmpty {
                    Button {
                        showStrategyBuilder = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Add")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(chipGoldGradient)
                    }
                }
            }
            .padding(.horizontal, 16)
            
            if strategyEngine.activeStrategies.isEmpty {
                // Empty state - Premium design with gold accents
                VStack(spacing: 20) {
                    // Icon with gold glow effect
                    ZStack {
                        // Outer glow
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [BrandColors.goldLight.opacity(0.2), BrandColors.goldBase.opacity(0.05), Color.clear],
                                    center: .center,
                                    startRadius: 20,
                                    endRadius: 50
                                )
                            )
                            .frame(width: 80, height: 80)
                        
                        // Inner circle with gold gradient
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [BrandColors.goldLight.opacity(0.2), BrandColors.goldBase.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 56, height: 56)
                        
                        Image(systemName: "function")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(chipGoldGradient)
                    }
                    
                    VStack(spacing: 6) {
                        Text("No Strategies Yet")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        Text("Build algorithmic trading strategies with technical indicators, or start from a pre-built template")
                            .font(.system(size: 13))
                            .foregroundColor(DS.Adaptive.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                            .padding(.horizontal, 24)
                    }
                    
                    // Primary CTA - Gold button matching CryptoSage brand
                    VStack(spacing: 10) {
                        Button {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            #endif
                            showStrategyBuilder = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Create Strategy")
                                    .font(.system(size: 15, weight: .bold))
                            }
                            .foregroundColor(BrandColors.ctaTextColor(isDark: colorScheme == .dark))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                ZStack {
                                    Capsule()
                                        .fill(AdaptiveGradients.goldButton(isDark: colorScheme == .dark))
                                    
                                    // Glass highlight
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.white.opacity(0.15), Color.clear],
                                                startPoint: .top,
                                                endPoint: .center
                                            )
                                        )
                                }
                            )
                        }
                        .padding(.horizontal, 24)
                        
                        // Secondary action - Templates
                        Button {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            showStrategyTemplates = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.on.doc.fill")
                                    .font(.system(size: 12))
                                Text("Browse Templates")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(chipGoldGradient)
                        }
                        .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(DS.Adaptive.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [BrandColors.goldBase.opacity(0.25), BrandColors.goldBase.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .padding(.horizontal, 16)
            } else {
                // Strategy list
                VStack(spacing: 8) {
                    ForEach(strategyEngine.activeStrategies.prefix(5)) { strategy in
                        strategyRowCard(strategy: strategy)
                    }
                    
                    if strategyEngine.activeStrategies.count > 5 {
                        NavigationLink(destination: BotHubView()) {
                            HStack {
                                Text("View All \(strategyEngine.activeStrategies.count) Strategies")
                                    .font(.system(size: 13, weight: .medium))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(chipGoldGradient)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
    
    private func strategyRowCard(strategy: TradingStrategy) -> some View {
        let isDeployed = PaperBotManager.shared.isBotDeployedForStrategy(strategyId: strategy.id)
        let deployedBot = PaperBotManager.shared.getBotForStrategy(strategyId: strategy.id)
        let isBotRunning = deployedBot?.status == .running
        
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Status indicator
                ZStack {
                    Circle()
                        .fill(strategy.isEnabled ? Color.green.opacity(0.15) : Color.gray.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: strategy.isEnabled ? "play.fill" : "pause.fill")
                        .font(.system(size: 14))
                        .foregroundColor(strategy.isEnabled ? .green : .gray)
                }
                
                // Strategy info
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(strategy.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                            .lineLimit(1)
                        
                        // Deployed indicator
                        if isDeployed {
                            HStack(spacing: 3) {
                                Image(systemName: isBotRunning ? "bolt.fill" : "bolt")
                                    .font(.system(size: 8))
                                Text(isBotRunning ? "Live" : "Deployed")
                                    .font(.system(size: 9, weight: .medium))
                            }
                            .foregroundColor(isBotRunning ? .green : .blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill((isBotRunning ? Color.green : Color.blue).opacity(0.15))
                            )
                        }
                    }
                    
                    HStack(spacing: 8) {
                        Text(strategy.tradingPair.replacingOccurrences(of: "_", with: "/"))
                            .font(.system(size: 11))
                            .foregroundColor(DS.Adaptive.textTertiary)
                        
                        Text("•")
                            .foregroundColor(DS.Adaptive.textTertiary)
                        
                        Text("\(strategy.entryConditions.count) entry, \(strategy.exitConditions.count) exit")
                            .font(.system(size: 11))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                }
                
                Spacer()
                
                // Action buttons
                HStack(spacing: 8) {
                    // Deploy/Manage button
                    if isDeployed {
                        // If deployed, show start/stop bot button
                        Button {
                            if let bot = deployedBot {
                                if isBotRunning {
                                    PaperBotManager.shared.stopBot(id: bot.id)
                                } else {
                                    PaperBotManager.shared.startBot(id: bot.id)
                                }
                            }
                        } label: {
                            Image(systemName: isBotRunning ? "stop.fill" : "play.fill")
                                .font(.system(size: 11))
                                .foregroundColor(isBotRunning ? .orange : .green)
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle()
                                        .fill((isBotRunning ? Color.orange : Color.green).opacity(0.15))
                                )
                        }
                    } else {
                        // Deploy to paper bot button
                        Button {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            #endif
                            let bot = PaperBotManager.shared.createBotFromStrategy(strategy)
                            PaperBotManager.shared.startBot(id: bot.id)
                        } label: {
                            Text("Deploy")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.blue)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(Color.blue.opacity(0.15))
                                )
                        }
                    }
                    
                    // Enable/disable strategy evaluation
                    Button {
                        strategyEngine.toggleStrategy(id: strategy.id)
                    } label: {
                        Image(systemName: strategy.isEnabled ? "eye.fill" : "eye.slash")
                            .font(.system(size: 11))
                            .foregroundColor(strategy.isEnabled ? .green : .gray)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill((strategy.isEnabled ? Color.green : Color.gray).opacity(0.15))
                            )
                    }
                }
            }
            .padding(12)
            
            // Show bot P&L if deployed and has trades
            if let bot = deployedBot, bot.totalTrades > 0 {
                Divider()
                    .background(DS.Adaptive.divider)
                
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 10))
                            .foregroundColor(DS.Adaptive.textTertiary)
                        Text("\(bot.totalTrades) trades")
                            .font(.system(size: 11))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                    
                    Spacer()
                    
                    Text(formatProfitLoss(bot.totalProfit))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(bot.totalProfit >= 0 ? .green : .red)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(DS.Adaptive.overlay(0.03))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
    }
    
    // MARK: - Recent Backtest Section
    
    private var recentBacktestSection: some View {
        Group {
            if !backtestEngine.backtestHistory.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    // Section header
                    HStack {
                        Text("Recent Backtests")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    
                    // Latest backtest result
                    if let latest = backtestEngine.backtestHistory.first {
                        backtestResultCard(result: latest)
                            .padding(.horizontal, 16)
                    }
                }
            }
        }
    }
    
    private func backtestResultCard(result: BacktestResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.strategyName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    Text(result.tradingPair.replacingOccurrences(of: "_", with: "/"))
                        .font(.system(size: 12))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                
                Spacer()
                
                // Profit/Loss
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatProfitLoss(result.netProfitLoss))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(result.netProfitLoss >= 0 ? .green : .red)
                    Text("\(String(format: "%.1f", result.totalReturnPercent))%")
                        .font(.system(size: 11))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
            }
            
            // Key metrics
            HStack(spacing: 0) {
                backtestMetric(label: "Win Rate", value: "\(String(format: "%.0f", result.winRate * 100))%")
                Spacer()
                backtestMetric(label: "Trades", value: "\(result.totalTrades)")
                Spacer()
                backtestMetric(label: "Sharpe", value: String(format: "%.2f", result.sharpeRatio))
                Spacer()
                backtestMetric(label: "Max DD", value: "\(String(format: "%.1f", result.maxDrawdownPercent))%")
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
    }
    
    private func backtestMetric(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(DS.Adaptive.textTertiary)
        }
    }
    
    // MARK: - Derivatives Mode Content (Dashboard-First)
    
    private var derivativesModeContent: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: 16) {
                    // Risk Warning Banner
                    derivativesWarningBanner
                    
                    // Quick Actions
                    derivativesQuickActions
                    
                    // My Positions Section
                    derivativesPositionsSection
                    
                    // Market Info
                    derivativesMarketInfo
                    
                    Spacer(minLength: 80)
                }
                .padding(.vertical, 12)
            }
            
            // Floating AI Helper Button
            aiHelperFloatingButton
        }
    }
    
    private var derivativesWarningBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("High Risk Trading")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Text("Leverage amplifies both gains and losses")
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }
    
    private var derivativesQuickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
                .padding(.horizontal, 16)
            
            // Long/Short buttons
            HStack(spacing: 12) {
                NavigationLink(destination: DerivativesBotView()) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.right.circle.fill")
                            .font(.system(size: 18))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Open Long")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Bet price goes up")
                                .font(.system(size: 10))
                                .opacity(0.8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .foregroundColor(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.green)
                    )
                }
                
                NavigationLink(destination: DerivativesBotView()) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.right.circle.fill")
                            .font(.system(size: 18))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Open Short")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Bet price goes down")
                                .font(.system(size: 10))
                                .opacity(0.8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .foregroundColor(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.red)
                    )
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    private var derivativesPositionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                    Text("Positions")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                Spacer()
                NavigationLink(destination: BotHubView()) {
                    HStack(spacing: 4) {
                        Text("View All")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(chipGoldGradient)
                }
            }
            .padding(.horizontal, 16)
            
            // Empty state
            VStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis.circle")
                    .font(.system(size: 32))
                    .foregroundColor(DS.Adaptive.textTertiary)
                Text("No open positions")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DS.Adaptive.textSecondary)
                Text("Open a long or short position to start trading derivatives")
                    .font(.system(size: 12))
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6]))
                    .foregroundColor(DS.Adaptive.stroke)
            )
            .padding(.horizontal, 16)
        }
    }
    
    private var derivativesMarketInfo: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Popular Perpetuals")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
                .padding(.horizontal, 16)
            
            VStack(spacing: 8) {
                derivativesPerpCard(symbol: "BTC-PERP", name: "Bitcoin Perpetual", fundingRate: "+0.01%")
                derivativesPerpCard(symbol: "ETH-PERP", name: "Ethereum Perpetual", fundingRate: "+0.008%")
            }
            .padding(.horizontal, 16)
        }
    }
    
    private func derivativesPerpCard(symbol: String, name: String, fundingRate: String) -> some View {
        NavigationLink(destination: DerivativesBotView()) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Text(String(symbol.prefix(1)))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.orange)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    Text(name)
                        .font(.system(size: 11))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Funding")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    Text(fundingRate)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.green)
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DS.Adaptive.stroke, lineWidth: 1)
            )
        }
    }
    
    // MARK: - Predictions Mode Content (Dashboard-First)
    
    private var predictionsModeContent: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: 16) {
                    // Platform Cards
                    predictionPlatformsSection
                    
                    // My Predictions
                    myPredictionsSection
                    
                    // Trending Markets
                    trendingMarketsSection
                    
                    Spacer(minLength: 80)
                }
                .padding(.vertical, 12)
            }
            
            // Floating AI Helper Button
            aiHelperFloatingButton
        }
    }
    
    private var predictionPlatformsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Platforms")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
                .padding(.horizontal, 16)
            
            HStack(spacing: 12) {
                NavigationLink(destination: PredictionMarketsView(sourceFilter: .polymarket)) {
                    predictionPlatformCard(
                        name: "Polymarket",
                        subtitle: "Crypto predictions",
                        color: .purple
                    )
                }
                
                NavigationLink(destination: PredictionMarketsView(sourceFilter: .kalshi)) {
                    predictionPlatformCard(
                        name: "Kalshi",
                        subtitle: "US regulated",
                        color: Color(red: 0.0, green: 0.7, blue: 0.6) // Teal
                    )
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    private func predictionPlatformCard(name: String, subtitle: String, color: Color) -> some View {
        VStack(spacing: 10) {
            // Enhanced icon with gradient glow
            ZStack {
                // Outer glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [color.opacity(0.3), color.opacity(0.05)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 30
                        )
                    )
                    .frame(width: 56, height: 56)
                
                // Inner circle with gradient
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.25), color.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                
                // Platform icon
                Text(String(name.prefix(1)))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(color)
            }
            
            VStack(spacing: 3) {
                Text(name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [color.opacity(0.3), color.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
    
    private var myPredictionsSection: some View {
        let activeTrades = PredictionTradingService.shared.activeTrades
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.xaxis.ascending")
                        .font(.system(size: 12))
                        .foregroundColor(.cyan)
                    Text("My Predictions")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    if !activeTrades.isEmpty {
                        Text("(\(activeTrades.count))")
                            .font(.system(size: 12))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                }
                Spacer()
                NavigationLink(destination: BotHubView()) {
                    HStack(spacing: 4) {
                        Text("View All")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(chipGoldGradient)
                }
            }
            .padding(.horizontal, 16)
            
            if activeTrades.isEmpty {
                // Empty state with enhanced styling
                VStack(spacing: 14) {
                    Image(systemName: "chart.bar.xaxis.ascending.badge.clock")
                        .font(.system(size: 36))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [DS.Adaptive.textTertiary, DS.Adaptive.textTertiary.opacity(0.6)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    Text("No active predictions")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DS.Adaptive.textSecondary)
                    
                    // Enhanced Browse Markets button
                    NavigationLink(destination: PredictionMarketsView()) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Browse Markets")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(AdaptiveGradients.goldButton(isDark: colorScheme == .dark))
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(DS.Adaptive.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6]))
                        .foregroundColor(DS.Adaptive.stroke)
                )
                .padding(.horizontal, 16)
            } else {
                // Show active predictions
                VStack(spacing: 8) {
                    ForEach(activeTrades.prefix(3)) { trade in
                        predictionTradeRow(trade)
                    }
                }
            }
        }
    }
    
    private func predictionTradeRow(_ trade: LivePredictionTrade) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(trade.outcome == "YES" ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                    .frame(width: 36, height: 36)
                Text(trade.outcome == "YES" ? "Y" : "N")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(trade.outcome == "YES" ? .green : .red)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(trade.marketTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .lineLimit(1)
                Text("$\(Int(trade.amount)) bet on \(trade.outcome)")
                    .font(.system(size: 10))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            Spacer()
            
            Text(trade.platform)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.Adaptive.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(DS.Adaptive.chipBackground)
                )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }
    
    private var trendingMarketsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trending Markets")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(DS.Adaptive.textPrimary)
                .padding(.horizontal, 16)
            
            if isLoadingTrendingMarkets && trendingPredictionMarkets.isEmpty {
                // Loading shimmer state
                VStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { _ in
                        trendingMarketShimmer
                    }
                }
                .padding(.horizontal, 16)
            } else {
                VStack(spacing: 10) {
                    ForEach(trendingPredictionMarkets.prefix(3)) { market in
                        NavigationLink(destination: PredictionMarketsView()) {
                            trendingMarketRowDynamic(market)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .task {
            await loadTrendingPredictionMarkets()
        }
    }
    
    /// Load trending prediction markets
    private func loadTrendingPredictionMarkets() async {
        guard trendingPredictionMarkets.isEmpty else { return }
        
        isLoadingTrendingMarkets = true
        
        do {
            let markets = try await PredictionMarketsService.shared.fetchTrendingMarkets(limit: 5)
            await MainActor.run {
                trendingPredictionMarkets = markets
                isLoadingTrendingMarkets = false
            }
        } catch {
            // Use sample data as fallback
            await MainActor.run {
                trendingPredictionMarkets = PredictionMarketEvent.samples.prefix(3).map { $0 }
                isLoadingTrendingMarkets = false
            }
        }
    }
    
    /// Shimmer placeholder for loading state
    private var trendingMarketShimmer: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(DS.Adaptive.chipBackground)
                    .frame(height: 14)
                    .frame(maxWidth: .infinity)
                RoundedRectangle(cornerRadius: 4)
                    .fill(DS.Adaptive.chipBackground)
                    .frame(width: 80, height: 6)
                RoundedRectangle(cornerRadius: 3)
                    .fill(DS.Adaptive.chipBackground)
                    .frame(width: 60, height: 10)
            }
            
            Spacer()
            
            VStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(DS.Adaptive.chipBackground)
                    .frame(width: 40, height: 18)
                RoundedRectangle(cornerRadius: 2)
                    .fill(DS.Adaptive.chipBackground)
                    .frame(width: 24, height: 8)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .shimmer()
    }
    
    /// Dynamic market row using live data
    private func trendingMarketRowDynamic(_ market: PredictionMarketEvent) -> some View {
        let yesOutcome = market.outcomes.first(where: { $0.name.lowercased() == "yes" })
        let probability = yesOutcome?.probability ?? 0.5
        
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(market.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                // Probability bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(DS.Adaptive.chipBackground)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: probability > 0.5
                                        ? [Color.green, Color.green.opacity(0.7)]
                                        : [Color.red, Color.red.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * CGFloat(probability))
                    }
                }
                .frame(height: 6)
                
                // Volume and platform
                HStack(spacing: 8) {
                    if let volume = market.volume, volume > 0 {
                        Text("Vol: \(formatVolume(volume))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                    
                    Text(market.source.displayName)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(market.source == .polymarket ? .purple : Color(red: 0.0, green: 0.7, blue: 0.6))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill((market.source == .polymarket ? Color.purple : Color(red: 0.0, green: 0.7, blue: 0.6)).opacity(0.12))
                        )
                }
            }
            
            Spacer()
            
            // Probability percentage badge
            VStack(spacing: 3) {
                Text("\(Int(probability * 100))%")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(probability > 0.5 ? .green : .red)
                Text("YES")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .frame(width: 50)
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.Adaptive.textTertiary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
    }
    
    /// Format volume for display
    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1_000_000 {
            return String(format: "$%.1fM", volume / 1_000_000)
        } else if volume >= 1_000 {
            return String(format: "$%.0fK", volume / 1_000)
        } else {
            return String(format: "$%.0f", volume)
        }
    }
    
    private func trendingMarketRow(title: String, probability: Double, volume: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text("Vol: \(volume)")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
            }
            
            Spacer()
            
            // Probability indicator
            VStack(spacing: 2) {
                Text("\(Int(probability * 100))%")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(probability > 0.5 ? .green : .red)
                Text("YES")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.Adaptive.textTertiary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
    }
    
    // MARK: - Premium Action Cards
    
    /// Primary CTA card with gold gradient
    private func primaryActionCard(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(BrandColors.ctaTextColor(isDark: colorScheme == .dark))
            }
            
            // Text
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(BrandColors.ctaTextColor(isDark: colorScheme == .dark))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(BrandColors.ctaTextColor(isDark: colorScheme == .dark).opacity(0.7))
            }
            
            Spacer()
            
            // Arrow
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(BrandColors.ctaTextColor(isDark: colorScheme == .dark).opacity(0.6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AdaptiveGradients.goldButton(isDark: colorScheme == .dark))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(colorScheme == .dark ? 0.15 : 0.25), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                )
        )
    }
    
    /// Secondary action card with outlined style
    private func secondaryActionCard(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            // Icon with colored background
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
            }
            
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.Adaptive.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
    }
    
    // MARK: - Helpers
    
    private func formatBalance(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "$%.1fK", value / 1000)
        }
        return String(format: "$%.0f", value)
    }
    
    private func updateAIContext(for mode: TradingHubMode) {
        // Update the AI's system prompt when mode changes
        let newPrompt = SmartTradingHubViewModel.buildSystemPrompt(for: mode)
        aiChatVM.updateSystemPrompt(newPrompt)
        
        // Optionally send a context message
        switch mode {
        case .assistant:
            _ = "Switched to general assistant mode. How can I help?"
        case .spot:
            _ = "Now in spot trading mode. Ready to help you buy or sell crypto!"
        case .bots:
            _ = "Bot configuration mode active. I can help you set up DCA, Grid, or Signal bots."
        case .strategies:
            _ = "Strategy builder mode. I can help you create, backtest, and optimize algorithmic trading strategies."
        case .derivatives:
            _ = "Derivatives mode. I'll help with leverage trading - let's be careful with risk!"
        case .predictions:
            _ = "Prediction markets mode. Let's find some interesting markets to analyze."
        }
        
        // Add a system context message (optional - could be annoying if too frequent)
        // aiChatVM.addSystemMessage(contextMessage)
    }
    
    /// Set up callbacks for AI chat bot and trade config actions
    private func setupAIChatCallbacks() {
        // Callback for bot config - navigate to bot creation
        aiChatVM.onApplyConfig = { [self] config in
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            appState.navigateToBotCreation(with: config)
        }
        
        // Callback for trade config - navigate to trade page
        aiChatVM.onApplyTradeConfig = { [self] tradeConfig in
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            appState.navigateToTrade(with: tradeConfig)
        }
    }
}

// MARK: - Premium Mode Chip

private struct ModeChip: View {
    let mode: TradingHubMode
    let isSelected: Bool
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    
    /// Premium gold gradient for selected state
    private var selectedGradient: LinearGradient {
        AdaptiveGradients.goldButton(isDark: isDark)
    }
    
    /// Subtle highlight gradient overlay for depth
    private var highlightOverlay: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(isDark ? 0.18 : 0.25), Color.clear],
            startPoint: .top,
            endPoint: .center
        )
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: mode.icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(mode.displayName)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(isSelected ? BrandColors.ctaTextColor(isDark: isDark) : DS.Adaptive.textSecondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 44) // Minimum touch target
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(selectedGradient)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(highlightOverlay)
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(DS.Adaptive.chipBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(DS.Adaptive.stroke, lineWidth: 1)
                            )
                    }
                }
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(mode.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Trading Settings View (Premium Redesign)

struct TradingSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var paperTradingManager = PaperTradingManager.shared
    @ObservedObject private var demoModeManager = DemoModeManager.shared
    
    // Quick toggle states
    @AppStorage("trading_notifications_enabled") private var notificationsEnabled = true
    @AppStorage("trading_auto_stop_loss") private var autoStopLoss = false
    @AppStorage("trading_confirm_orders") private var confirmOrders = true
    @AppStorage("trading_show_pnl") private var showPnL = true
    
    /// Trading mode enum for settings display
    private enum SettingsTradingMode {
        case live, paper, demo, advisory
    }
    
    /// Current trading mode for settings display
    private var currentTradingModeForSettings: SettingsTradingMode {
        if AppConfig.liveTradingEnabled {
            return .live
        } else if PaperTradingManager.isEnabled {
            return .paper
        } else if DemoModeManager.isEnabled {
            return .demo
        } else {
            return .advisory
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Trading Mode Indicator
                tradingModeIndicator
                
                // Quick Toggles Section
                quickTogglesSection
                
                // Paper Trading Section
                settingsSection(
                    title: "Paper Trading",
                    icon: "doc.text.fill",
                    iconColor: .blue
                ) {
                    settingsNavigationRow(
                        icon: "slider.horizontal.3",
                        iconColor: .blue,
                        title: "Paper Trading Settings",
                        subtitle: "Balance, history & performance",
                        destination: AnyView(PaperTradingSettingsView())
                    )
                }
                
                // Exchange Connections Section
                settingsSection(
                    title: "Exchange Connections",
                    icon: "link.circle.fill",
                    iconColor: .green
                ) {
                    settingsNavigationRow(
                        icon: "building.columns.fill",
                        iconColor: .green,
                        title: "Connected Exchanges",
                        subtitle: "Binance, Coinbase & more",
                        destination: AnyView(ExchangeConnectionView())
                    )
                    
                    Divider()
                        .background(DS.Adaptive.divider)
                        .padding(.horizontal, 12)
                    
                    settingsNavigationRow(
                        icon: "key.fill",
                        iconColor: .orange,
                        title: "API Keys",
                        subtitle: "For portfolio sync & live trading",
                        destination: AnyView(TradingCredentialsView())
                    )
                }
                
                // Bot Settings Section
                settingsSection(
                    title: "Bot Settings",
                    icon: "cpu.fill",
                    iconColor: .purple
                ) {
                    settingsNavigationRow(
                        icon: "gearshape.2.fill",
                        iconColor: .purple,
                        title: "Default Parameters",
                        subtitle: "DCA, Grid & Signal defaults",
                        destination: AnyView(BotDefaultParametersView())
                    )
                    
                    Divider()
                        .background(DS.Adaptive.divider)
                        .padding(.horizontal, 12)
                    
                    settingsNavigationRow(
                        icon: "exclamationmark.shield.fill",
                        iconColor: .red,
                        title: "Risk Limits",
                        subtitle: "Max position size & stop loss",
                        destination: AnyView(RiskLimitsSettingsView())
                    )
                }
                
                // Prediction Markets Section (Beta)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.bar.xaxis.ascending")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.cyan)
                        Text("Prediction Markets")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(DS.Adaptive.textSecondary)
                        
                        // Beta badge
                        Text("BETA")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.cyan.opacity(0.8))
                            )
                    }
                    
                    VStack(spacing: 0) {
                        settingsNavigationRow(
                            icon: "wallet.pass.fill",
                            iconColor: .cyan,
                            title: "Wallet Connection",
                            subtitle: "Connect for Polymarket & Kalshi",
                            destination: AnyView(WalletConnectView())
                        )
                        
                        Divider()
                            .background(DS.Adaptive.divider)
                            .padding(.horizontal, 12)
                        
                        settingsNavigationRow(
                            icon: "slider.vertical.3",
                            iconColor: .mint,
                            title: "Platform Preferences",
                            subtitle: "Default markets & display",
                            destination: AnyView(PredictionPlatformPreferencesView())
                        )
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(DS.Adaptive.cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(DS.Adaptive.stroke, lineWidth: 1)
                    )
                    
                    // Beta disclaimer
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.cyan.opacity(0.7))
                        Text("Prediction markets integration is in beta. Trading requires wallet connection to external platforms.")
                            .font(.system(size: 11))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                    .padding(.horizontal, 4)
                }
                
                // Version Info
                versionInfoSection
                
                Spacer(minLength: 32)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationTitle("Trading Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Trading Mode Indicator
    
    private var tradingModeIndicator: some View {
        let mode = currentTradingModeForSettings
        let isLive = mode == .live
        let isPaper = mode == .paper
        
        let paperColor = AppTradingMode.paper.color
        
        return HStack(spacing: 12) {
            // Mode icon
            ZStack {
                Circle()
                    .fill(isLive ? Color.green.opacity(0.15) : isPaper ? paperColor.opacity(0.15) : Color.gray.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: isLive ? "bolt.fill" : isPaper ? "doc.text.fill" : "eye.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isLive ? .green : isPaper ? paperColor : .gray)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(isLive ? "Live Trading" : isPaper ? "Paper Trading" : "Advisory Mode")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    if isLive {
                        Text("DEV")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.85))
                            .cornerRadius(4)
                    }
                }
                
                Text(isLive ? "Real trades on connected exchanges" : isPaper ? "Practice with simulated funds" : "Analysis and advice only")
                    .font(.system(size: 12))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            
            Spacer()
            
            // Status indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(isLive ? Color.green : isPaper ? paperColor : Color.gray)
                    .frame(width: 8, height: 8)
                Text(isLive ? "Active" : isPaper ? "Enabled" : "Off")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isLive ? .green : isPaper ? paperColor : .gray)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill((isLive ? Color.green : isPaper ? paperColor : Color.gray).opacity(0.12))
            )
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke((isLive ? Color.green : isPaper ? paperColor : Color.gray).opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Quick Toggles Section
    
    private var quickTogglesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [BrandColors.goldLight, BrandColors.goldBase],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text("Quick Settings")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            
            VStack(spacing: 0) {
                quickToggleRow(
                    icon: "bell.fill",
                    iconColor: .orange,
                    title: "Trade Notifications",
                    isOn: $notificationsEnabled
                )
                
                Divider()
                    .background(DS.Adaptive.divider)
                    .padding(.horizontal, 12)
                
                quickToggleRow(
                    icon: "shield.checkered",
                    iconColor: .red,
                    title: "Auto Stop-Loss",
                    isOn: $autoStopLoss
                )
                
                Divider()
                    .background(DS.Adaptive.divider)
                    .padding(.horizontal, 12)
                
                quickToggleRow(
                    icon: "checkmark.circle.fill",
                    iconColor: .green,
                    title: "Confirm Orders",
                    isOn: $confirmOrders
                )
                
                Divider()
                    .background(DS.Adaptive.divider)
                    .padding(.horizontal, 12)
                
                quickToggleRow(
                    icon: "chart.line.uptrend.xyaxis",
                    iconColor: .blue,
                    title: "Show P&L",
                    isOn: $showPnL
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
            )
        }
    }
    
    private func quickToggleRow(icon: String, iconColor: Color, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(iconColor)
            }
            
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Spacer()
            
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(BrandColors.goldBase)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
    
    // MARK: - Settings Section Builder
    
    private func settingsSection<Content: View>(
        title: String,
        icon: String,
        iconColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            
            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
            )
        }
    }
    
    // MARK: - Settings Navigation Row
    
    private func settingsNavigationRow(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        destination: AnyView
    ) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(iconColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Version Info
    
    private var versionInfoSection: some View {
        HStack {
            Spacer()
            VStack(spacing: 4) {
                Text("CryptoSage Trading")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                    .font(.system(size: 10))
                    .foregroundColor(DS.Adaptive.textTertiary.opacity(0.7))
            }
            Spacer()
        }
        .padding(.top, 8)
    }
}

// MARK: - Bot Default Parameters View

struct BotDefaultParametersView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    // DCA Defaults
    @AppStorage("bot_dca_default_amount") private var dcaDefaultAmount: Double = 100
    @AppStorage("bot_dca_default_interval") private var dcaDefaultInterval: String = "daily"
    
    // Grid Defaults
    @AppStorage("bot_grid_default_levels") private var gridDefaultLevels: Int = 10
    @AppStorage("bot_grid_default_range") private var gridDefaultRange: Double = 10
    
    // Signal Defaults
    @AppStorage("bot_signal_rsi_oversold") private var signalRSIOversold: Double = 30
    @AppStorage("bot_signal_rsi_overbought") private var signalRSIOverbought: Double = 70
    
    private let intervals = ["hourly", "daily", "weekly", "monthly"]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // DCA Bot Defaults
                parameterSection(title: "DCA Bot Defaults", icon: "repeat.circle.fill", color: .blue) {
                    VStack(spacing: 16) {
                        parameterRow(title: "Default Amount", value: "$\(Int(dcaDefaultAmount))") {
                            Slider(value: $dcaDefaultAmount, in: 10...1000, step: 10)
                                .tint(BrandColors.goldBase)
                        }
                        
                        HStack {
                            Text("Default Interval")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(DS.Adaptive.textPrimary)
                            Spacer()
                            Picker("", selection: $dcaDefaultInterval) {
                                ForEach(intervals, id: \.self) { interval in
                                    Text(interval.capitalized).tag(interval)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(BrandColors.goldBase)
                        }
                    }
                }
                
                // Grid Bot Defaults
                parameterSection(title: "Grid Bot Defaults", icon: "square.grid.3x3.fill", color: .purple) {
                    VStack(spacing: 16) {
                        parameterRow(title: "Grid Levels", value: "\(gridDefaultLevels)") {
                            Slider(value: Binding(
                                get: { Double(gridDefaultLevels) },
                                set: { gridDefaultLevels = Int($0) }
                            ), in: 3...30, step: 1)
                                .tint(BrandColors.goldBase)
                        }
                        
                        parameterRow(title: "Range %", value: "\(Int(gridDefaultRange))%") {
                            Slider(value: $gridDefaultRange, in: 2...50, step: 1)
                                .tint(BrandColors.goldBase)
                        }
                    }
                }
                
                // Signal Bot Defaults
                parameterSection(title: "Signal Bot Defaults", icon: "bolt.circle.fill", color: .orange) {
                    VStack(spacing: 16) {
                        parameterRow(title: "RSI Oversold", value: "\(Int(signalRSIOversold))") {
                            Slider(value: $signalRSIOversold, in: 10...40, step: 1)
                                .tint(.green)
                        }
                        
                        parameterRow(title: "RSI Overbought", value: "\(Int(signalRSIOverbought))") {
                            Slider(value: $signalRSIOverbought, in: 60...90, step: 1)
                                .tint(.red)
                        }
                    }
                }
                
                Spacer(minLength: 32)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationTitle("Default Parameters")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func parameterSection<Content: View>(
        title: String,
        icon: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            
            VStack(spacing: 0) {
                content()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
            )
        }
    }
    
    private func parameterRow<Content: View>(
        title: String,
        value: String,
        @ViewBuilder control: () -> Content
    ) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Spacer()
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(BrandColors.goldBase)
            }
            control()
        }
    }
}

// MARK: - Risk Limits Settings View

struct RiskLimitsSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    @AppStorage("risk_max_position_percent") private var maxPositionPercent: Double = 25
    @AppStorage("risk_max_daily_loss_percent") private var maxDailyLossPercent: Double = 5
    @AppStorage("risk_auto_stop_loss_percent") private var autoStopLossPercent: Double = 10
    @AppStorage("risk_max_leverage") private var maxLeverage: Double = 5
    @AppStorage("risk_require_stop_loss") private var requireStopLoss: Bool = true
    @AppStorage("risk_cool_down_after_loss") private var coolDownAfterLoss: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Warning Banner
                warningBanner
                
                // Position Limits
                riskSection(title: "Position Limits", icon: "chart.pie.fill", color: .blue) {
                    VStack(spacing: 16) {
                        riskSlider(
                            title: "Max Position Size",
                            value: $maxPositionPercent,
                            range: 5...100,
                            step: 5,
                            unit: "% of portfolio",
                            color: .blue
                        )
                        
                        riskSlider(
                            title: "Max Leverage",
                            value: $maxLeverage,
                            range: 1...20,
                            step: 1,
                            unit: "x",
                            color: .orange
                        )
                    }
                }
                
                // Loss Protection
                riskSection(title: "Loss Protection", icon: "shield.fill", color: .red) {
                    VStack(spacing: 16) {
                        riskSlider(
                            title: "Max Daily Loss",
                            value: $maxDailyLossPercent,
                            range: 1...20,
                            step: 1,
                            unit: "%",
                            color: .red
                        )
                        
                        riskSlider(
                            title: "Auto Stop-Loss",
                            value: $autoStopLossPercent,
                            range: 2...25,
                            step: 1,
                            unit: "%",
                            color: .orange
                        )
                    }
                }
                
                // Safety Rules
                riskSection(title: "Safety Rules", icon: "checkmark.shield.fill", color: .green) {
                    VStack(spacing: 12) {
                        riskToggle(
                            title: "Require Stop-Loss",
                            subtitle: "All trades must have a stop-loss set",
                            isOn: $requireStopLoss
                        )
                        
                        Divider()
                            .background(DS.Adaptive.divider)
                        
                        riskToggle(
                            title: "Cool-Down After Loss",
                            subtitle: "15 min pause after hitting daily loss limit",
                            isOn: $coolDownAfterLoss
                        )
                    }
                }
                
                Spacer(minLength: 32)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationTitle("Risk Limits")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var warningBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Risk Management")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Text("These limits help protect your capital from excessive losses")
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.orange.opacity(0.3), lineWidth: 0.5)
        )
    }
    
    private func riskSection<Content: View>(
        title: String,
        icon: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            
            VStack(spacing: 0) {
                content()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
            )
        }
    }
    
    private func riskSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        unit: String,
        color: Color
    ) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Spacer()
                Text("\(Int(value.wrappedValue))\(unit)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(color)
            }
            Slider(value: value, in: range, step: step)
                .tint(color)
        }
    }
    
    private func riskToggle(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            Spacer()
            
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(BrandColors.goldBase)
        }
    }
}

// MARK: - Prediction Platform Preferences View

struct PredictionPlatformPreferencesView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    @AppStorage("prediction_default_platform") private var defaultPlatform: String = "polymarket"
    @AppStorage("prediction_show_resolved") private var showResolved: Bool = false
    @AppStorage("prediction_min_volume") private var minVolume: Double = 1000
    @AppStorage("prediction_favorite_categories") private var favoriteCategories: String = "crypto,politics"
    
    private let platforms = ["polymarket", "kalshi"]
    private let categories = ["crypto", "politics", "sports", "entertainment", "science", "economics"]
    
    @State private var selectedCategories: Set<String> = []
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Default Platform
                preferenceSection(title: "Default Platform", icon: "star.fill", color: .cyan) {
                    HStack {
                        ForEach(platforms, id: \.self) { platform in
                            platformButton(platform)
                        }
                    }
                }
                
                // Display Preferences
                preferenceSection(title: "Display", icon: "eye.fill", color: .blue) {
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Show Resolved Markets")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(DS.Adaptive.textPrimary)
                                Text("Include markets that have already resolved")
                                    .font(.system(size: 10))
                                    .foregroundColor(DS.Adaptive.textTertiary)
                            }
                            Spacer()
                            Toggle("", isOn: $showResolved)
                                .labelsHidden()
                                .tint(BrandColors.goldBase)
                        }
                        
                        Divider()
                            .background(DS.Adaptive.divider)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Minimum Volume")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(DS.Adaptive.textPrimary)
                                Spacer()
                                Text("$\(Int(minVolume))")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(BrandColors.goldBase)
                            }
                            Slider(value: $minVolume, in: 0...100000, step: 1000)
                                .tint(BrandColors.goldBase)
                        }
                    }
                }
                
                // Favorite Categories
                preferenceSection(title: "Favorite Categories", icon: "heart.fill", color: .pink) {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 8) {
                        ForEach(categories, id: \.self) { category in
                            categoryChip(category)
                        }
                    }
                }
                
                Spacer(minLength: 32)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationTitle("Platform Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedCategories = Set(favoriteCategories.split(separator: ",").map(String.init))
        }
    }
    
    private func preferenceSection<Content: View>(
        title: String,
        icon: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            
            VStack(spacing: 0) {
                content()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
            )
        }
    }
    
    private func platformButton(_ platform: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                defaultPlatform = platform
            }
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        } label: {
            VStack(spacing: 6) {
                Image(systemName: platform == "polymarket" ? "chart.bar.xaxis.ascending" : "k.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(defaultPlatform == platform ? .white : .cyan)
                
                Text(platform.capitalized)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(defaultPlatform == platform ? .white : DS.Adaptive.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(defaultPlatform == platform ? Color.cyan : DS.Adaptive.chipBackground)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func categoryChip(_ category: String) -> some View {
        let isSelected = selectedCategories.contains(category)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isSelected {
                    selectedCategories.remove(category)
                } else {
                    selectedCategories.insert(category)
                }
                favoriteCategories = selectedCategories.joined(separator: ",")
            }
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        } label: {
            Text(category.capitalized)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isSelected ? .white : DS.Adaptive.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? BrandColors.goldBase : DS.Adaptive.chipBackground)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - AI Helper Context

enum AIHelperContext: String, CaseIterable {
    case general
    case spot
    case bots
    case strategies
    case derivatives
    case predictions
    case orders
    
    var displayName: String {
        switch self {
        case .general: return "Trading Assistant"
        case .spot: return "Spot Trading"
        case .bots: return "Trading Bots"
        case .strategies: return "Algo Strategies"
        case .derivatives: return "Derivatives"
        case .predictions: return "Predictions"
        case .orders: return "Order Management"
        }
    }
    
    var icon: String {
        switch self {
        case .general: return "sparkles"
        case .spot: return "arrow.left.arrow.right"
        case .bots: return "cpu"
        case .strategies: return "function"
        case .derivatives: return "chart.line.uptrend.xyaxis"
        case .predictions: return "chart.bar.xaxis.ascending"
        case .orders: return "list.bullet.rectangle.portrait"
        }
    }
    
    var color: Color {
        switch self {
        case .general: return BrandColors.goldBase
        case .spot: return .green
        case .bots: return .purple
        case .strategies: return .green  // Matches Algo Strategies page theme
        case .derivatives: return .orange
        case .predictions: return .cyan
        case .orders: return .blue
        }
    }
    
    var greeting: String {
        switch self {
        case .general:
            return "Hey! I'm CryptoSage AI, your trading assistant. I can help with spot trading, bots, derivatives, or prediction markets. What would you like to do?"
        case .spot:
            return "Ready to help with spot trading. I can assist with buy/sell decisions, explain order types, or analyze market conditions. What would you like to know?"
        case .bots:
            return "I can help you set up automated trading bots. Tell me about your strategy goals, and I'll recommend the right bot type (DCA, Grid, or Signal) with optimal settings."
        case .strategies:
            return "I'm your Algo Strategy Advisor. I can help you create custom trading strategies using technical indicators like RSI, MACD, and moving averages. Describe your trading style or goals, and I'll suggest a strategy configuration for you to review."
        case .derivatives:
            return "I'm here to assist with derivatives trading. Remember - leverage is high risk. Let's discuss your strategy and proper position sizing first."
        case .predictions:
            return "I can help you analyze prediction markets on Polymarket and Kalshi. Tell me what events you're interested in, and I'll help identify potential opportunities."
        case .orders:
            return "I can help you manage your open orders. Ask me about order strategies, when to cancel, how to optimize your entries, or explain your order status."
        }
    }
    
    var systemPrompt: String {
        switch self {
        case .general:
            return SmartTradingHubViewModel.buildSystemPrompt(for: .assistant)
        case .spot:
            return SmartTradingHubViewModel.buildSystemPrompt(for: .spot)
        case .bots:
            return SmartTradingHubViewModel.buildSystemPrompt(for: .bots)
        case .strategies:
            return """
            You are CryptoSage AI's Algorithmic Strategy Advisor. Help users create, understand, and optimize trading strategies using technical indicators.
            
            Your expertise includes:
            - Technical indicators: RSI, MACD, Bollinger Bands, SMAs, EMAs, Stochastic, ATR, Volume
            - Strategy types: Trend following, Mean reversion, Momentum, Breakout, Accumulation
            - Risk management: Stop-loss, take-profit, trailing stops, max drawdown
            - Position sizing: Fixed amount, % of portfolio, risk-based sizing
            
            When helping users create a strategy:
            1. Ask about their trading style (aggressive vs conservative)
            2. Ask about their preferred timeframe (day trading vs swing trading)
            3. Explain indicators in simple terms
            4. Recommend appropriate risk settings based on their experience
            
            IMPORTANT: When the user confirms they want a strategy or asks you to create one, generate a complete strategy configuration in this exact JSON format wrapped in <strategy_config> tags:
            
            <strategy_config>
            {
                "name": "Strategy Name",
                "description": "Brief description",
                "tradingPair": "BTC_USDT",
                "timeframe": "1d",
                "entryConditions": [
                    {"indicator": "rsi", "comparison": "lessThan", "value": 30}
                ],
                "exitConditions": [
                    {"indicator": "rsi", "comparison": "greaterThan", "value": 70}
                ],
                "conditionLogic": "all",
                "riskManagement": {
                    "stopLossPercent": 5,
                    "takeProfitPercent": 15,
                    "trailingStopPercent": null,
                    "maxDrawdownPercent": 20
                },
                "positionSizing": {
                    "method": "percentOfPortfolio",
                    "portfolioPercent": 10,
                    "maxPositionPercent": 25
                }
            }
            </strategy_config>
            
            Available indicators: price, rsi, macdHistogram, macdLine, macdSignal, sma20, sma50, sma200, ema12, ema26, bollingerUpper, bollingerMiddle, bollingerLower, stochK, stochD, atr, volume, volumeChange, obv, priceChange
            
            Comparison operators: greaterThan, lessThan, equals, crossesAbove, crossesBelow, greaterThanOrEqual, lessThanOrEqual
            
            Timeframes: 1m, 5m, 15m, 30m, 1h, 4h, 1d, 1w
            
            Position sizing methods: fixedAmount, percentOfPortfolio, riskBased
            
            Be educational and explain why you're recommending certain settings.
            """
        case .derivatives:
            return SmartTradingHubViewModel.buildSystemPrompt(for: .derivatives)
        case .predictions:
            return SmartTradingHubViewModel.buildSystemPrompt(for: .predictions)
        case .orders:
            return """
            You are CryptoSage AI, an expert assistant for managing cryptocurrency orders.
            
            Your expertise includes:
            - Explaining order types (limit, market, stop-loss, take-profit)
            - Advising when to cancel or modify orders
            - Suggesting optimal entry and exit prices
            - Analyzing market conditions relative to pending orders
            - Order fill probability assessment
            - Risk management for open positions
            
            Guidelines:
            - Always consider current market volatility
            - Suggest price levels based on support/resistance
            - Warn about orders that may not fill
            - Recommend proper order sizing
            - Be concise but thorough
            
            When users ask about their orders, help them understand:
            - Whether their limit price is realistic
            - If they should adjust their order
            - Risk/reward of their current entries
            """
        }
    }
    
    var storageKey: String {
        "csai_ai_helper_\(rawValue)"
    }
    
    var suggestedPrompts: [String] {
        switch self {
        case .general:
            return ["What should I trade today?", "Analyze my portfolio", "Help me set up a bot", "What's moving in crypto?"]
        case .spot:
            return ["Is now a good time to buy BTC?", "Help me place a limit order", "What's the best entry for ETH?", "Explain DCA strategy"]
        case .bots:
            return ["Create a DCA bot for SOL", "Which bot type is best for me?", "Configure a Grid bot", "Show me bot performance tips"]
        case .strategies:
            return ["Create a trend following strategy", "Build a mean reversion strategy for BTC", "Explain RSI and how to use it", "What's a good beginner strategy?"]
        case .derivatives:
            return ["Calculate my position size", "Explain funding rates", "Help me set stop-loss", "What leverage should I use?"]
        case .predictions:
            return ["Find high-value crypto bets", "Analyze this market for me", "What's the expected value?", "Best prediction strategies"]
        case .orders:
            return ["Should I cancel this order?", "Help me set a better limit price", "Explain my order status", "What's a good entry for BTC?"]
        }
    }
    
    /// Topics this context can help with - shown in welcome card
    var helpTopics: [String] {
        switch self {
        case .general:
            return ["Market analysis", "Trading strategies", "Bot recommendations", "Portfolio advice"]
        case .spot:
            return ["Buy/sell decisions", "Order types", "Entry/exit timing", "Price targets"]
        case .bots:
            return ["DCA strategies", "Grid bot setup", "Signal configuration", "Risk settings"]
        case .strategies:
            return ["Indicator selection", "Entry/exit conditions", "Risk management", "Position sizing"]
        case .derivatives:
            return ["Position sizing", "Leverage selection", "Stop-loss placement", "Risk management"]
        case .predictions:
            return ["Market analysis", "Probability assessment", "Expected value", "Hedging strategies"]
        case .orders:
            return ["Order strategies", "Entry optimization", "Cancel decisions", "Fill probability"]
        }
    }
}

// MARK: - Contextual AI Helper View
// Matches the main AI Chat design from AIChatView.swift for consistent UX

struct ContextualAIHelperView: View {
    let context: AIHelperContext
    
    @StateObject private var viewModel: AiChatViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appState: AppState
    
    // Input state
    @State private var isInputFocused: Bool = false
    @State private var showSuggestions: Bool = true
    @State private var hasPerformedInitialScroll: Bool = false
    
    // Trade config detection (for spot and derivatives contexts)
    @State private var detectedTradeConfig: AITradeConfig? = nil
    
    // Bot config detection (for bots and general contexts)
    @State private var detectedBotConfig: AIBotConfig? = nil
    
    // Strategy config detection (for strategies context)
    @State private var detectedStrategyConfig: AIStrategyConfig? = nil
    @State private var showStrategyBuilder: Bool = false
    
    // Subscription for prompts indicator
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showPromptLimitView: Bool = false
    
    private let bottomAnchorID = "chat_bottom_anchor"
    private var isDark: Bool { colorScheme == .dark }
    
    init(context: AIHelperContext) {
        self.context = context
        _viewModel = StateObject(wrappedValue: AiChatViewModel(
            systemPrompt: context.systemPrompt,
            storageKey: context.storageKey,
            initialGreeting: context.greeting
        ))
    }
    
    // LIGHT MODE FIX: Adaptive gold gradient - deeper amber in light mode
    private var chipGoldGradient: LinearGradient {
        isDark
            ? LinearGradient(colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange], startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [Color(red: 0.78, green: 0.60, blue: 0.10), Color(red: 0.65, green: 0.45, blue: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                DS.Adaptive.background.ignoresSafeArea()
                
                // Chat content
                chatBodyView
            }
            .safeAreaInset(edge: .top) {
                VStack(spacing: 0) {
                    aiHelperHeader
                    
                    Rectangle()
                        .fill(DS.Adaptive.divider)
                        .frame(height: 0.5)
                }
                .background(DS.Adaptive.background)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                inputBarSection
            }
        }
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            setupConfigCallback()
            viewModel.fetchInitialMessageIfNeeded()
        }
        .onChange(of: viewModel.messages.count) { _, _ in
            // Parse trade configs from new AI messages (for spot and derivatives contexts)
            if context == .spot || context == .derivatives || context == .general {
                parseTradeConfigFromLatestMessage()
            }
            // Parse bot configs from new AI messages (for bots, predictions, and general contexts)
            if context == .bots || context == .predictions || context == .general {
                parseBotConfigFromLatestMessage()
            }
            // Parse strategy configs from new AI messages (for strategies context)
            if context == .strategies || context == .general {
                parseStrategyConfigFromLatestMessage()
            }
        }
        .sheet(isPresented: $showPromptLimitView) {
            AIPromptLimitView()
        }
    }
    
    // MARK: - Chat Body (matches AITabView design)
    
    private var chatBodyView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    // Welcome card (shows what this context can help with)
                    if viewModel.messages.count <= 1 {
                        welcomeCard
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    // Suggestions bar (collapsible)
                    if showSuggestions && viewModel.messages.count <= 1 {
                        suggestionsBar
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    // Messages
                    ForEach(viewModel.messages, id: \.id) { message in
                        SmartTradingChatBubble(message: message)
                            .id(message.id)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                removal: .opacity
                            ))
                    }
                    
                    // Apply Config button
                    if let config = viewModel.generatedConfig {
                        ApplyConfigButton(config: config) {
                            viewModel.applyCurrentConfig()
                        }
                        .padding(.horizontal, 16)
                        .transition(.scale.combined(with: .opacity))
                    }
                    
                    // Typing indicator with smooth transition
                    if viewModel.isTyping {
                        SmartTradingTypingIndicator()
                            .padding(.leading, 16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.9)),
                                removal: .opacity.combined(with: .scale(scale: 0.95))
                            ))
                    }
                    
                    // Bottom anchor
                    Color.clear
                        .frame(height: 8)
                        .id(bottomAnchorID)
                }
                .padding(.top, 12)
                .animation(.easeOut(duration: 0.2), value: viewModel.isTyping)
                .animation(.easeOut(duration: 0.15), value: viewModel.messages.count)
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                UIApplication.shared.dismissKeyboard()
            }
            .onAppear {
                performInitialScroll(proxy: proxy)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottomOnNewMessage(proxy: proxy)
            }
            .onChange(of: viewModel.isTyping) { _, isTyping in
                if !isTyping {
                    scrollToBottom(proxy: proxy, animated: true)
                }
            }
            .onChange(of: viewModel.messages.last?.text.count ?? 0) { _, _ in
                // Streaming scroll - throttled
                if viewModel.isTyping {
                    scrollToBottom(proxy: proxy, animated: false)
                }
            }
        }
    }
    
    // MARK: - Input Bar Section (matches AITabView)
    
    private var inputBarSection: some View {
        VStack(spacing: 0) {
            // Trade execution button (for spot and derivatives contexts)
            if let config = detectedTradeConfig {
                ExecuteTradeButton(config: config, onExecute: {
                    // Navigate to Trading tab with the trade config
                    appState.navigateToTrade(with: config)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        detectedTradeConfig = nil
                    }
                    dismiss()
                }, onDismiss: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        detectedTradeConfig = nil
                    }
                })
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.95)),
                    removal: .scale(scale: 0.95).combined(with: .opacity)
                ))
            }
            
            // Bot creation button (for bots and general contexts)
            if let botConfig = detectedBotConfig {
                CreateBotButton(config: botConfig, onExecute: {
                    // Navigate to bot creation with the config
                    appState.navigateToBotCreation(with: botConfig)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        detectedBotConfig = nil
                    }
                    dismiss()
                }, onDismiss: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        detectedBotConfig = nil
                    }
                })
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.95)),
                    removal: .scale(scale: 0.95).combined(with: .opacity)
                ))
            }
            
            // Strategy creation button (for strategies context)
            if let strategyConfig = detectedStrategyConfig {
                ReviewStrategyButton(config: strategyConfig, onReview: {
                    showStrategyBuilder = true
                }, onDismiss: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        detectedStrategyConfig = nil
                    }
                })
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.95)),
                    removal: .scale(scale: 0.95).combined(with: .opacity)
                ))
            }
            
            // Remaining prompts indicator (only show for non-premium tiers)
            if subscriptionManager.currentTier != .premium && !subscriptionManager.isDeveloperMode {
                remainingPromptsIndicator
            }
            
            // Top separator
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.clear, BrandColors.goldLight.opacity(0.12), Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 0.5)
            
            // Input bar - matches AI Chat tab styling
            HStack(spacing: 10) {
                // Text input - UIKit-backed for reliable keyboard
                ChatTextField(text: $viewModel.userInput, placeholder: "Ask CryptoSage AI...")
                    .onSubmit {
                        sendMessage()
                    }
                    .onEditingChanged { focused in
                        withAnimation(.easeOut(duration: 0.15)) {
                            isInputFocused = focused
                            if focused {
                                showSuggestions = false
                            }
                        }
                    }
                    .frame(height: 42)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 21, style: .continuous)
                            .fill(DS.Adaptive.chipBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 21, style: .continuous)
                            .stroke(
                                isInputFocused ? BrandColors.goldLight.opacity(0.6) : DS.Adaptive.stroke,
                                lineWidth: isInputFocused ? 1.5 : 1
                            )
                    )
                    .animation(.easeOut(duration: 0.15), value: isInputFocused)
                
                // Send button - circular gold gradient matching AI Chat tab
                let canSend = !viewModel.isTyping && !viewModel.userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Button {
                    guard canSend else { return }
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    #endif
                    sendMessage()
                } label: {
                    ZStack {
                        Circle()
                            .fill(
                                colorScheme == .dark
                                    ? BrandColors.goldVertical
                                    : LinearGradient(
                                        colors: [BrandColors.goldLight, BrandColors.goldBase],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                            )
                            .frame(width: 36, height: 36)
                        
                        // Glass highlight
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.3), Color.clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.black.opacity(0.9))
                    }
                }
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.45)
                .scaleEffect(canSend ? 1.0 : 0.95)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: canSend)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(DS.Adaptive.background)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: detectedTradeConfig != nil)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: detectedBotConfig != nil)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: detectedStrategyConfig != nil)
        .sheet(isPresented: $showStrategyBuilder) {
            if let config = detectedStrategyConfig {
                StrategyBuilderView(existingStrategy: config.toTradingStrategy())
                    .onDisappear {
                        // Clear the detected config after reviewing
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            detectedStrategyConfig = nil
                        }
                    }
            }
        }
    }
    
    // MARK: - Remaining Prompts Indicator
    
    private var remainingPromptsIndicator: some View {
        let remaining = subscriptionManager.remainingAIPrompts
        let isLow = remaining <= 1 && remaining > 0
        let isEmpty = remaining == 0
        
        // Don't show indicator if limit sheet is already visible (avoid redundancy)
        if showPromptLimitView {
            return AnyView(EmptyView())
        }
        
        // Show prominent banner when limit reached
        if isEmpty {
            return AnyView(
                Button {
                    showPromptLimitView = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.orange)
                        
                        Text("Daily limit reached")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Text("Upgrade")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(
                        PremiumCompactCTAStyle(
                            height: 28,
                            horizontalPadding: 10,
                            cornerRadius: 14,
                            font: .system(size: 11, weight: .bold)
                        )
                    )
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.orange.opacity(0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            )
        }
        
        // Normal pill indicator when prompts available
        return AnyView(
            HStack(spacing: 6) {
                Image(systemName: "message.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(isLow ? .yellow : BrandColors.goldLight)
                
                Text("\(remaining) left today")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isLow ? .yellow : DS.Adaptive.textSecondary)
                
                if subscriptionManager.currentTier == .free {
                    Button {
                        showPromptLimitView = true
                    } label: {
                        Text("Upgrade")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(
                        PremiumCompactCTAStyle(
                            height: 24,
                            horizontalPadding: 8,
                            cornerRadius: 12,
                            font: .system(size: 10, weight: .bold)
                        )
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        Capsule()
                            .stroke(isLow ? Color.yellow.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        )
    }
    
    // MARK: - Header
    
    private var aiHelperHeader: some View {
        VStack(spacing: 8) {
            // Main header row
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textSecondary)
                        .padding(10)
                        .background(Circle().fill(DS.Adaptive.chipBackground))
                }
                
                Spacer()
                
                // Centered title with icon
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(chipGoldGradient)
                    Text("Ask AI")
                        .font(.headline)
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                
                Spacer()
                
                // New chat button
                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    viewModel.clearHistory()
                    viewModel.fetchInitialMessageIfNeeded()
                    showSuggestions = true
                } label: {
                    Image(systemName: "plus.bubble")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textSecondary)
                        .padding(10)
                        .background(Circle().fill(DS.Adaptive.chipBackground))
                }
            }
            
            // Context indicator badge - shows user that Sage knows what they need
            HStack(spacing: 6) {
                Image(systemName: context.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(context.color)
                
                Text("AI is in")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Adaptive.textSecondary)
                
                Text(context.displayName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(context.color)
                
                Text("mode")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(context.color.opacity(0.1))
                    .overlay(
                        Capsule()
                            .stroke(context.color.opacity(0.25), lineWidth: 1)
                    )
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // MARK: - Suggestions Bar
    
    // MARK: - Welcome Card
    
    private var welcomeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header - CryptoSage AI branding
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [BrandColors.goldLight.opacity(0.3), BrandColors.goldBase.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                    Image(systemName: "sparkles")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(chipGoldGradient)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("CryptoSage AI")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .fixedSize(horizontal: true, vertical: false)
                    Text(context.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(context.color)
                        .fixedSize(horizontal: true, vertical: false)
                }
                
                Spacer(minLength: 0)
            }
            
            // Topics grid with proper layout
            LazyVGrid(columns: [
                GridItem(.flexible(minimum: 100), spacing: 8),
                GridItem(.flexible(minimum: 100), spacing: 8)
            ], alignment: .leading, spacing: 10) {
                ForEach(context.helpTopics, id: \.self) { topic in
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(context.color)
                        Text(topic)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DS.Adaptive.textSecondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
                
                // Top highlight for glass effect
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.05 : 0.3),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            BrandColors.goldBase.opacity(0.4),
                            context.color.opacity(0.2),
                            context.color.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .padding(.horizontal, 16)
    }
    
    private var suggestionsBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick questions")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.Adaptive.textTertiary)
                .padding(.horizontal, 16)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(context.suggestedPrompts, id: \.self) { prompt in
                        Button {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            viewModel.userInput = prompt
                            sendMessage()
                        } label: {
                            Text(prompt)
                                .font(.system(size: 13, weight: .medium))
                                // LIGHT MODE FIX: Adaptive text color for readability on gold chips
                                .foregroundColor(isDark ? .black : Color(red: 0.35, green: 0.25, blue: 0.02))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    ZStack {
                                        // Gold gradient background - LIGHT MODE FIX: Use lighter warm amber
                                        Capsule()
                                            .fill(
                                                isDark
                                                    ? BrandColors.goldHorizontal.opacity(0.28)
                                                    : LinearGradient(
                                                        colors: [Color(red: 0.96, green: 0.88, blue: 0.65), Color(red: 0.92, green: 0.82, blue: 0.52)],
                                                        startPoint: .leading,
                                                        endPoint: .trailing
                                                    ).opacity(1.0)
                                            )
                                        // Gloss overlay - LIGHT MODE FIX: Subtler gloss
                                        Capsule()
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color.white.opacity(isDark ? 0.25 : 0.35), Color.clear],
                                                    startPoint: .top,
                                                    endPoint: .center
                                                )
                                            )
                                    }
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(
                                            isDark
                                                ? BrandColors.goldLight.opacity(0.55)
                                                : Color(red: 0.80, green: 0.65, blue: 0.25).opacity(0.40),
                                            lineWidth: isDark ? 1 : 0.5
                                        )
                                )
                        }
                        .disabled(viewModel.isTyping)
                        .opacity(viewModel.isTyping ? 0.5 : 1)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 12)
    }
    
    // MARK: - Helpers
    
    private func sendMessage() {
        let trimmed = viewModel.userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !viewModel.isTyping else { return }
        
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        
        viewModel.sendMessage(trimmed)
        showSuggestions = false
    }
    
    private func performInitialScroll(proxy: ScrollViewProxy) {
        guard !hasPerformedInitialScroll else { return }
        
        // Two-stage scroll for reliable initial positioning
        scrollToBottom(proxy: proxy, animated: false)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            scrollToBottom(proxy: proxy, animated: false)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            scrollToBottom(proxy: proxy, animated: false)
            hasPerformedInitialScroll = true
        }
    }
    
    private func scrollToBottomOnNewMessage(proxy: ScrollViewProxy) {
        guard hasPerformedInitialScroll else { return }
        guard let lastMessage = viewModel.messages.last else { return }
        
        if lastMessage.isUser {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
        }
    }
    
    private func setupConfigCallback() {
        viewModel.onApplyConfig = { config in
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            
            // Navigate to appropriate view based on config type
            appState.navigateToBotCreation(with: config)
            dismiss()
        }
    }
    
    // MARK: - Trade Config Parsing
    
    /// Parse trade config from the latest AI message
    private func parseTradeConfigFromLatestMessage() {
        guard let lastMessage = viewModel.messages.last,
              !lastMessage.isUser else { return }
        
        let text = lastMessage.text
        
        // Try to parse from tags first
        if let config = parseTradeConfigFromTags(text) {
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    self.detectedTradeConfig = config
                }
            }
            return
        }
        
        // For spot/derivatives contexts, try natural language extraction
        if context == .spot || context == .derivatives {
            if let config = extractTradeFromNaturalLanguage(text) {
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        self.detectedTradeConfig = config
                    }
                }
            }
        }
    }
    
    /// Parse trade config from JSON tags in the AI response
    private func parseTradeConfigFromTags(_ text: String) -> AITradeConfig? {
        let tagPatterns = [
            ("<trade_config>", "</trade_config>"),
            ("<tradeconfig>", "</tradeconfig>"),
            ("<trade-config>", "</trade-config>")
        ]
        
        for (startTag, endTag) in tagPatterns {
            if let startRange = text.range(of: startTag, options: .caseInsensitive),
               let endRange = text.range(of: endTag, options: .caseInsensitive, range: startRange.upperBound..<text.endIndex) {
                let jsonString = String(text[startRange.upperBound..<endRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                if let jsonData = jsonString.data(using: .utf8),
                   let config = try? JSONDecoder().decode(AITradeConfig.self, from: jsonData) {
                    return config
                }
            }
        }
        
        return nil
    }
    
    /// Extract trade config from natural language
    private func extractTradeFromNaturalLanguage(_ text: String) -> AITradeConfig? {
        let lowercased = text.lowercased()
        
        // Detect direction
        let isBuy = lowercased.contains("buy") || lowercased.contains("purchase") || lowercased.contains("buying")
        let isSell = lowercased.contains("sell") || lowercased.contains("selling")
        guard isBuy || isSell else { return nil }
        let direction: AITradeConfig.TradeDirection = isBuy ? .buy : .sell
        
        // Detect symbol - common crypto tickers
        let knownTickers = ["BTC", "ETH", "SOL", "LTC", "DOGE", "ADA", "XRP", "BNB", "AVAX", "DOT", "LINK", "MATIC", "ARB", "OP", "ATOM", "NEAR", "FTM", "SUI", "APT"]
        var detectedSymbol: String? = nil
        for ticker in knownTickers {
            if text.uppercased().contains(ticker) {
                detectedSymbol = ticker
                break
            }
        }
        guard let symbol = detectedSymbol else { return nil }
        
        // Detect order type
        let isLimit = lowercased.contains("limit")
        let orderType: AITradeConfig.OrderType = isLimit ? .limit : .market
        
        // Try to extract amount
        var amount: String? = nil
        var isUSDAmount = false
        
        // Pattern: $X,XXX or $XXX
        let dollarPattern = #"\$[\d,]+(?:\.\d{1,2})?"#
        if let regex = try? NSRegularExpression(pattern: dollarPattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let matchRange = Range(match.range, in: text) {
            let matchedString = String(text[matchRange])
            amount = matchedString.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
            isUSDAmount = true
        }
        
        // Detect leverage for derivatives
        var leverage: Int? = nil
        if context == .derivatives {
            let leveragePattern = #"(\d+)x\s*leverage"#
            if let regex = try? NSRegularExpression(pattern: leveragePattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               match.numberOfRanges > 1,
               let leverageRange = Range(match.range(at: 1), in: text) {
                leverage = Int(text[leverageRange])
            }
        }
        
        return AITradeConfig(
            symbol: symbol,
            quoteCurrency: nil,
            direction: direction,
            orderType: orderType,
            amount: amount,
            isUSDAmount: isUSDAmount,
            price: nil,
            stopLoss: nil,
            takeProfit: nil,
            leverage: leverage
        )
    }
    
    // MARK: - Bot Config Parsing
    
    /// Parse bot config from the latest AI message
    private func parseBotConfigFromLatestMessage() {
        guard let lastMessage = viewModel.messages.last,
              !lastMessage.isUser else { return }
        
        let text = lastMessage.text
        
        // Try to parse from tags first
        if let config = parseBotConfigFromTags(text) {
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    self.detectedBotConfig = config
                }
            }
            return
        }
        
        // For bots and predictions contexts, try natural language extraction
        if context == .bots || context == .predictions {
            if let config = extractBotFromNaturalLanguage(text) {
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        self.detectedBotConfig = config
                    }
                }
            }
        }
    }
    
    /// Parse bot config from JSON tags in the AI response
    private func parseBotConfigFromTags(_ text: String) -> AIBotConfig? {
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
    
    /// Extract bot config from natural language
    private func extractBotFromNaturalLanguage(_ text: String) -> AIBotConfig? {
        let lowercased = text.lowercased()
        
        // Detect bot type
        var botType: AIBotConfig.BotType = .dca // Default to DCA
        
        if lowercased.contains("grid bot") || lowercased.contains("grid trading") {
            botType = .grid
        } else if lowercased.contains("signal bot") || lowercased.contains("indicator") {
            botType = .signal
        } else if lowercased.contains("derivatives") || lowercased.contains("futures bot") || lowercased.contains("leverage bot") {
            botType = .derivatives
        } else if lowercased.contains("prediction") || lowercased.contains("polymarket") || lowercased.contains("kalshi") {
            botType = .predictionMarket
        }
        
        // Detect trading pair
        var tradingPair: String? = nil
        let knownTickers = ["BTC", "ETH", "SOL", "LTC", "DOGE", "ADA", "XRP", "BNB", "AVAX", "DOT", "LINK", "MATIC", "ARB", "OP", "ATOM", "NEAR", "FTM", "SUI", "APT"]
        
        for ticker in knownTickers {
            if text.uppercased().contains(ticker) {
                tradingPair = "\(ticker)_USDT"
                break
            }
        }
        
        guard tradingPair != nil || botType == .predictionMarket else { return nil }
        
        // Detect exchange
        var exchange: String? = "Binance"
        let exchanges = ["Binance", "Binance US", "Coinbase", "Kraken", "KuCoin", "Bybit", "OKX", "Gate.io", "MEXC", "HTX", "Bitstamp", "Crypto.com", "Bitget", "Bitfinex"]
        for ex in exchanges {
            if lowercased.contains(ex.lowercased()) {
                exchange = ex
                break
            }
        }
        
        // Extract base order size
        var baseOrderSize: String? = nil
        let dollarPattern = #"\$[\d,]+(?:\.\d{1,2})?"#
        if let regex = try? NSRegularExpression(pattern: dollarPattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let matchRange = Range(match.range, in: text) {
            let matchedString = String(text[matchRange])
            baseOrderSize = matchedString.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
        }
        
        // Extract take profit
        var takeProfit: String? = nil
        let tpPattern = #"take profit[:\s]+(\d+)%?"#
        if let regex = try? NSRegularExpression(pattern: tpPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           match.numberOfRanges > 1,
           let tpRange = Range(match.range(at: 1), in: text) {
            takeProfit = String(text[tpRange])
        }
        
        return AIBotConfig(
            botType: botType,
            name: nil,
            exchange: exchange,
            direction: nil,
            tradingPair: tradingPair,
            baseOrderSize: baseOrderSize,
            takeProfit: takeProfit,
            stopLoss: nil,
            maxOrders: nil,
            priceDeviation: nil,
            lowerPrice: nil,
            upperPrice: nil,
            gridLevels: nil,
            maxInvestment: nil,
            leverage: nil,
            marginMode: nil,
            market: nil,
            platform: botType == .predictionMarket ? "Polymarket" : nil,
            marketId: nil,
            marketTitle: nil,
            outcome: nil,
            targetPrice: nil,
            betAmount: nil,
            category: nil
        )
    }
    
    // MARK: - Strategy Config Parsing
    
    /// Parse strategy config from the latest AI message
    private func parseStrategyConfigFromLatestMessage() {
        guard let lastMessage = viewModel.messages.last,
              !lastMessage.isUser else { return }
        
        let text = lastMessage.text
        
        // Try to parse from <strategy_config> tags
        if let config = parseStrategyConfigFromTags(text) {
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    self.detectedStrategyConfig = config
                }
            }
        }
    }
    
    /// Parse strategy config from JSON tags in the AI response
    private func parseStrategyConfigFromTags(_ text: String) -> AIStrategyConfig? {
        let tagPatterns = [
            ("<strategy_config>", "</strategy_config>"),
            ("<strategyconfig>", "</strategyconfig>"),
            ("<strategy-config>", "</strategy-config>")
        ]
        
        for (startTag, endTag) in tagPatterns {
            if let startRange = text.range(of: startTag, options: .caseInsensitive),
               let endRange = text.range(of: endTag, options: .caseInsensitive, range: startRange.upperBound..<text.endIndex) {
                let jsonString = String(text[startRange.upperBound..<endRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                if let jsonData = jsonString.data(using: .utf8),
                   let config = try? JSONDecoder().decode(AIStrategyConfig.self, from: jsonData) {
                    return config
                }
            }
        }
        
        return nil
    }
}

// MARK: - AI Strategy Config (for AI-generated strategy JSON)

/// Simplified strategy config for AI generation
struct AIStrategyConfig: Codable {
    let name: String
    let description: String?
    let tradingPair: String?
    let timeframe: String?
    let entryConditions: [AICondition]?
    let exitConditions: [AICondition]?
    let conditionLogic: String?
    let riskManagement: AIRiskManagement?
    let positionSizing: AIPositionSizing?
    
    struct AICondition: Codable {
        let indicator: String
        let comparison: String
        let value: Double?
        let valueIndicator: String? // For comparing to another indicator
    }
    
    struct AIRiskManagement: Codable {
        let stopLossPercent: Double?
        let takeProfitPercent: Double?
        let trailingStopPercent: Double?
        let maxDrawdownPercent: Double?
    }
    
    struct AIPositionSizing: Codable {
        let method: String?
        let portfolioPercent: Double?
        let maxPositionPercent: Double?
        let riskPercent: Double?
        let fixedAmount: Double?
    }
    
    /// Convert to TradingStrategy
    func toTradingStrategy() -> TradingStrategy {
        // Parse timeframe
        let tf: StrategyTimeframe = {
            guard let tfString = timeframe?.lowercased() else { return .oneDay }
            switch tfString {
            case "1m": return .oneMinute
            case "5m": return .fiveMinutes
            case "15m": return .fifteenMinutes
            case "30m": return .thirtyMinutes
            case "1h": return .oneHour
            case "4h": return .fourHours
            case "1d": return .oneDay
            case "1w": return .oneWeek
            default: return .oneDay
            }
        }()
        
        // Parse condition logic
        let logic: ConditionLogic = {
            guard let logicStr = conditionLogic?.lowercased() else { return .all }
            if logicStr.contains("or") || logicStr.contains("any") { return .any }
            return .all
        }()
        
        // Parse entry conditions
        let entry: [StrategyCondition] = (entryConditions ?? []).compactMap { aiCond in
            guard let indicator = parseIndicator(aiCond.indicator),
                  let comparison = parseComparison(aiCond.comparison) else { return nil }
            
            let value: ConditionValue
            if let valueIndicator = aiCond.valueIndicator, let ind = parseIndicator(valueIndicator) {
                value = .indicator(ind)
            } else if let numValue = aiCond.value {
                value = .number(numValue)
            } else {
                return nil
            }
            
            return StrategyCondition(indicator: indicator, comparison: comparison, value: value)
        }
        
        // Parse exit conditions
        let exit: [StrategyCondition] = (exitConditions ?? []).compactMap { aiCond in
            guard let indicator = parseIndicator(aiCond.indicator),
                  let comparison = parseComparison(aiCond.comparison) else { return nil }
            
            let value: ConditionValue
            if let valueIndicator = aiCond.valueIndicator, let ind = parseIndicator(valueIndicator) {
                value = .indicator(ind)
            } else if let numValue = aiCond.value {
                value = .number(numValue)
            } else {
                return nil
            }
            
            return StrategyCondition(indicator: indicator, comparison: comparison, value: value)
        }
        
        // Parse risk management
        let risk = RiskManagement(
            stopLossPercent: riskManagement?.stopLossPercent,
            takeProfitPercent: riskManagement?.takeProfitPercent,
            trailingStopPercent: riskManagement?.trailingStopPercent,
            maxDrawdownPercent: riskManagement?.maxDrawdownPercent ?? 20.0
        )
        
        // Parse position sizing
        let sizing: PositionSizing = {
            guard let ps = positionSizing else { return PositionSizing() }
            let method: PositionSizingMethod
            switch ps.method?.lowercased() {
            case "fixedamount", "fixed": method = .fixedAmount
            case "riskbased", "risk": method = .riskBased
            default: method = .percentOfPortfolio
            }
            return PositionSizing(
                method: method,
                fixedAmount: ps.fixedAmount ?? 100,
                portfolioPercent: ps.portfolioPercent ?? 10,
                riskPercent: ps.riskPercent ?? 1,
                maxPositionPercent: ps.maxPositionPercent ?? 25
            )
        }()
        
        return TradingStrategy(
            name: name,
            description: description ?? "",
            tradingPair: tradingPair ?? "BTC_USDT",
            timeframe: tf,
            entryConditions: entry,
            exitConditions: exit,
            conditionLogic: logic,
            riskManagement: risk,
            positionSizing: sizing
        )
    }
    
    private func parseIndicator(_ str: String) -> StrategyIndicatorType? {
        let lowercased = str.lowercased().replacingOccurrences(of: "_", with: "")
        switch lowercased {
        case "price": return .price
        case "pricechange": return .priceChange
        case "rsi": return .rsi
        case "macdhistogram", "macd": return .macdHistogram
        case "macdline": return .macdLine
        case "macdsignal": return .macdSignal
        case "sma20": return .sma20
        case "sma50": return .sma50
        case "sma200": return .sma200
        case "ema12": return .ema12
        case "ema26": return .ema26
        case "bollingerupper", "bbupper": return .bollingerUpper
        case "bollingermiddle", "bbmiddle": return .bollingerMiddle
        case "bollingerlower", "bblower": return .bollingerLower
        case "stochk", "stochastick": return .stochK
        case "stochd", "stochasticd": return .stochD
        case "atr": return .atr
        case "volume": return .volume
        case "volumechange": return .volumeChange
        case "obv": return .obv
        default: return nil
        }
    }
    
    private func parseComparison(_ str: String) -> ComparisonOperator? {
        let lowercased = str.lowercased().replacingOccurrences(of: "_", with: "")
        switch lowercased {
        case "greaterthan", ">": return .greaterThan
        case "lessthan", "<": return .lessThan
        case "equals", "=", "==": return .equals
        case "crossesabove", "crossabove": return .crossesAbove
        case "crossesbelow", "crossbelow": return .crossesBelow
        case "greaterthanorequal", ">=": return .greaterOrEqual
        case "lessthanorequal", "<=": return .lessOrEqual
        default: return nil
        }
    }
}

// MARK: - Review Strategy Button

/// Button shown when AI generates a strategy configuration
struct ReviewStrategyButton: View {
    let config: AIStrategyConfig
    let onReview: () -> Void
    var onDismiss: (() -> Void)? = nil
    
    @State private var isPressed = false
    @State private var dragOffset: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    
    /// Display name for the strategy
    private var displayName: String {
        config.name.isEmpty ? "AI-Generated Strategy" : config.name
    }
    
    /// Display the trading pair
    private var displayPair: String {
        (config.tradingPair ?? "BTC_USDT").replacingOccurrences(of: "_", with: "/")
    }
    
    /// Display timeframe
    private var displayTimeframe: String {
        config.timeframe?.uppercased() ?? "1D"
    }
    
    /// Entry conditions count
    private var entryConditionsCount: Int {
        config.entryConditions?.count ?? 0
    }
    
    /// Exit conditions count
    private var exitConditionsCount: Int {
        config.exitConditions?.count ?? 0
    }
    
    /// Risk/reward summary
    private var riskSummary: String? {
        guard let rm = config.riskManagement else { return nil }
        var parts: [String] = []
        if let sl = rm.stopLossPercent {
            parts.append("SL: \(Int(sl))%")
        }
        if let tp = rm.takeProfitPercent {
            parts.append("TP: \(Int(tp))%")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " | ")
    }
    
    var body: some View {
        Button(action: {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = false
                }
                onReview()
            }
        }) {
            HStack(spacing: 12) {
                // Strategy icon with green theme
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(isDark ? 0.2 : 0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "function")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.green)
                }
                
                // Strategy details
                VStack(alignment: .leading, spacing: 3) {
                    // Strategy name with prominent badge
                    HStack(spacing: 5) {
                        Text(displayName)
                            .font(.system(size: 15, weight: .bold))
                            .lineLimit(1)
                        
                        HStack(spacing: 3) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 7, weight: .bold))
                            Text("AI Strategy")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            LinearGradient(
                                colors: [Color.green.opacity(0.9), Color.green],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(4)
                    }
                    .foregroundColor(DS.Adaptive.textPrimary)
                    
                    // Parameters row
                    HStack(spacing: 6) {
                        // Trading pair
                        Text(displayPair)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DS.Adaptive.textSecondary)
                        
                        Text("•")
                            .font(.system(size: 8))
                            .foregroundStyle(DS.Adaptive.textTertiary)
                        
                        // Timeframe
                        Text(displayTimeframe)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DS.Adaptive.textSecondary)
                        
                        Text("•")
                            .font(.system(size: 8))
                            .foregroundStyle(DS.Adaptive.textTertiary)
                        
                        // Conditions count
                        Text("\(entryConditionsCount) entry, \(exitConditionsCount) exit")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DS.Adaptive.textTertiary)
                    }
                    
                    // Risk summary if available
                    if let risk = riskSummary {
                        Text(risk)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.green)
                    }
                }
                
                Spacer()
                
                // Review & Create button - more prominent CTA
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Review & Create")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [Color.green.opacity(0.9), Color.green],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(10)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.green.opacity(0.35), lineWidth: 1.5)
            )
            .scaleEffect(isPressed ? 0.98 : 1)
        }
        .buttonStyle(.plain)
        // Dismiss X button overlay (top-right corner)
        .overlay(alignment: .topTrailing) {
            if onDismiss != nil {
                Button {
                    onDismiss?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(DS.Adaptive.textTertiary)
                        .frame(width: 22, height: 22)
                        .background(
                            Circle()
                                .fill(DS.Adaptive.chipBackground)
                                .overlay(
                                    Circle()
                                        .stroke(DS.Adaptive.divider, lineWidth: 0.5)
                                )
                        )
                }
                .offset(x: -8, y: 8)
            }
        }
        // Swipe down to dismiss
        .offset(y: dragOffset)
        .gesture(
            onDismiss == nil ? nil :
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = value.translation.height * 0.6
                    }
                }
                .onEnded { value in
                    if value.translation.height > 60 {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = 300
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            onDismiss?()
                        }
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            dragOffset = 0
                        }
                    }
                }
        )
    }
}

// MARK: - Smart Trading Chat Bubble (matches main AI Chat design)

private struct SmartTradingChatBubble: View {
    let message: AiChatMessage
    @Environment(\.colorScheme) private var colorScheme
    
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()
    
    /// Clean message text by removing hidden config blocks, technical content, and markdown
    private var cleanedText: String {
        var cleaned = message.text
        
        // Remove <trade_config>...</trade_config> blocks (various formats)
        let tradeTagPatterns = [
            ("<trade_config>", "</trade_config>"),
            ("<tradeconfig>", "</tradeconfig>"),
            ("<trade-config>", "</trade-config>"),
            ("<TRADE_CONFIG>", "</TRADE_CONFIG>"),
            ("<TradeConfig>", "</TradeConfig>")
        ]
        for (startTag, endTag) in tradeTagPatterns {
            while let startRange = cleaned.range(of: startTag, options: .caseInsensitive),
                  let endRange = cleaned.range(of: endTag, options: .caseInsensitive, range: startRange.upperBound..<cleaned.endIndex) {
                cleaned.removeSubrange(startRange.lowerBound...endRange.upperBound)
            }
        }
        
        // Remove <bot_config>...</bot_config> blocks (various formats)
        let botTagPatterns = [
            ("<bot_config>", "</bot_config>"),
            ("<botconfig>", "</botconfig>"),
            ("<bot-config>", "</bot-config>")
        ]
        for (startTag, endTag) in botTagPatterns {
            while let startRange = cleaned.range(of: startTag, options: .caseInsensitive),
                  let endRange = cleaned.range(of: endTag, options: .caseInsensitive, range: startRange.upperBound..<cleaned.endIndex) {
                cleaned.removeSubrange(startRange.lowerBound...endRange.upperBound)
            }
        }
        
        // Remove <strategy_config>...</strategy_config> blocks (various formats)
        let strategyTagPatterns = [
            ("<strategy_config>", "</strategy_config>"),
            ("<strategyconfig>", "</strategyconfig>"),
            ("<strategy-config>", "</strategy-config>")
        ]
        for (startTag, endTag) in strategyTagPatterns {
            while let startRange = cleaned.range(of: startTag, options: .caseInsensitive),
                  let endRange = cleaned.range(of: endTag, options: .caseInsensitive, range: startRange.upperBound..<cleaned.endIndex) {
                cleaned.removeSubrange(startRange.lowerBound...endRange.upperBound)
            }
        }
        
        // Remove plain-text config formats (non-XML):
        //   bot_config{...}/bot_config, bot_config{...}, trade_config{...}, strategy_config{...}
        let plainConfigPatterns = [
            "bot_config\\{[^}]*\\}/bot_config",
            "bot_config\\{[^}]*\\}",
            "bot_config\\([^)]*\\)/bot_config",
            "bot_config\\([^)]*\\)",
            "trade_config\\{[^}]*\\}/trade_config",
            "trade_config\\{[^}]*\\}",
            "strategy_config\\{[^}]*\\}/strategy_config",
            "strategy_config\\{[^}]*\\}"
        ]
        for pattern in plainConfigPatterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        
        // Remove ```json...``` code blocks
        while let startRange = cleaned.range(of: "```json"),
              let endRange = cleaned.range(of: "```", range: startRange.upperBound..<cleaned.endIndex) {
            cleaned.removeSubrange(startRange.lowerBound...endRange.upperBound)
        }
        
        // Remove standalone JSON objects containing config fields
        if let jsonStart = cleaned.range(of: "{"),
           let jsonEnd = cleaned.range(of: "}", options: [], range: jsonStart.upperBound..<cleaned.endIndex),
           jsonStart.lowerBound < jsonEnd.upperBound {
            let jsonContent = String(cleaned[jsonStart.lowerBound..<jsonEnd.upperBound])
            if jsonContent.contains("\"symbol\"") || jsonContent.contains("\"botType\"") ||
               jsonContent.contains("\"direction\"") || jsonContent.contains("\"orderType\"") ||
               jsonContent.contains("botType") || jsonContent.contains("tradingPair") {
                cleaned.removeSubrange(jsonStart.lowerBound..<jsonEnd.upperBound)
            }
        }
        
        // Remove bracketed action indicators
        cleaned = cleaned.replacingOccurrences(
            of: "\\[(?:Execute|Place|Create|Submit|Confirm|Set|Cancel)\\s+\\w+(?:\\s+\\w+)?\\]",
            with: "",
            options: .regularExpression
        )
        
        // === MARKDOWN STRIPPING ===
        // Remove headers
        cleaned = cleaned.replacingOccurrences(of: "\\n#{1,6}\\s*", with: "\n", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "^#{1,6}\\s*", with: "", options: .regularExpression)
        
        // Remove bold (**text** or __text__)
        for _ in 0..<3 {
            cleaned = cleaned.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "$1", options: .regularExpression)
            cleaned = cleaned.replacingOccurrences(of: "__(.+?)__", with: "$1", options: .regularExpression)
        }
        
        // Remove italic (*text* or _text_) - careful not to affect bullet points
        for _ in 0..<2 {
            cleaned = cleaned.replacingOccurrences(of: "(?<![*\\s])\\*([^*\\n]+?)\\*(?![*])", with: "$1", options: .regularExpression)
            cleaned = cleaned.replacingOccurrences(of: "(?<![_\\s])_([^_\\n]+?)_(?![_])", with: "$1", options: .regularExpression)
        }
        
        // Remove code blocks (```code``` -> code)
        cleaned = cleaned.replacingOccurrences(of: "```[\\w]*\\n?([\\s\\S]*?)```", with: "$1", options: .regularExpression)
        
        // Remove inline code (`code` -> code)
        cleaned = cleaned.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
        
        // Clean up stray asterisks from incomplete markdown
        cleaned = cleaned.replacingOccurrences(of: "(?<=\\s|^)\\*\\*(?=\\S)", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "(?<=\\S)\\*\\*(?=\\s|$|[.,!?;:])", with: "", options: .regularExpression)
        
        // Clean up extra whitespace
        cleaned = cleaned.replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleaned
    }
    
    /// Check if message contains financial advice that requires disclaimers
    private func shouldShowDisclaimers(_ text: String) -> Bool {
        let lowerText = text.lowercased()
        let financialKeywords = [
            "buy", "sell", "invest", "trade", "recommend", "suggest", "target", "profit",
            "hold", "hodl", "dca", "swing", "position", "leverage", "futures", "margin",
            "take profit", "stop loss", "portfolio allocation", "entry point"
        ]
        return financialKeywords.contains { lowerText.contains($0) }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.isUser {
                Spacer(minLength: 60)
                userBubble
            } else {
                aiBubble
                Spacer(minLength: 60)
            }
        }
        .padding(.horizontal, 16)
    }
    
    private var aiBubble: some View {
        HStack(alignment: .top, spacing: 10) {
            // AI Avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [BrandColors.goldLight.opacity(0.25), BrandColors.goldBase.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(BrandColors.goldBase)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                if !cleanedText.isEmpty {
                    Text(cleanedText)
                        .font(.system(size: 15))
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                // Apple-required AI Generated label and financial disclaimers
                if shouldShowDisclaimers(cleanedText) {
                    Text("💡 AI Generated • Not financial advice")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary.opacity(0.8))
                        .padding(.top, 2)
                } else {
                    Text("💡 AI Generated")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary.opacity(0.8))
                        .padding(.top, 2)
                }
                
                Text(Self.timeFormatter.string(from: message.timestamp))
                    .font(.system(size: 10))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
            )
        }
    }
    
    private var userBubble: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(message.text)
                .font(.system(size: 15))
                .foregroundColor(Color.black.opacity(0.9))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            
            Text(Self.timeFormatter.string(from: message.timestamp))
                .font(.system(size: 10))
                .foregroundColor(Color.black.opacity(0.6))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            ZStack {
                // Base gold gradient
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(BrandColors.goldVertical)
                // Top gloss highlight for premium feel
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.28), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(BrandColors.goldLight.opacity(0.6), lineWidth: 0.8)
        )
    }
}

// MARK: - Smart Trading Typing Indicator

private struct SmartTradingTypingIndicator: View {
    @State private var dotPhase: Int = 0

    // Use a TimelineView-friendly timer publisher to avoid Timer retain issues
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(BrandColors.goldLight.opacity(dotPhase == index ? 1.0 : 0.35))
                    .frame(width: 8, height: 8)
                    .scaleEffect(dotPhase == index ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.35), value: dotPhase)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DS.Adaptive.overlay(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(BrandColors.goldLight.opacity(0.25), lineWidth: 1)
                )
        )
        .onReceive(timer) { _ in
            dotPhase = (dotPhase + 1) % 3
        }
    }
}

// MARK: - Bot Onboarding Sheet

struct BotOnboardingSheet: View {
    let botType: QuickBotType
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var navigateToAI: Bool = false
    @State private var navigateToManual: Bool = false
    
    private var chipGoldGradient: LinearGradient {
        colorScheme == .dark
            ? LinearGradient(colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange], startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [Color(red: 0.78, green: 0.60, blue: 0.10), Color(red: 0.65, green: 0.45, blue: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header icon
                ZStack {
                    Circle()
                        .fill(botType.color.opacity(0.15))
                        .frame(width: 80, height: 80)
                    Image(systemName: botType.icon)
                        .font(.system(size: 36))
                        .foregroundColor(botType.color)
                }
                .padding(.top, 32)
                
                // Title and description
                VStack(spacing: 8) {
                    Text(botType.rawValue)
                        .font(.title2.weight(.bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Text(botTypeDescription)
                        .font(.body)
                        .foregroundColor(DS.Adaptive.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                
                // How it works
                VStack(alignment: .leading, spacing: 12) {
                    Text("HOW IT WORKS")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(BrandColors.goldBase)
                        .tracking(0.5)
                    
                    ForEach(botTypeSteps, id: \.self) { step in
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(botType.color)
                            Text(step)
                                .font(.system(size: 14))
                                .foregroundColor(DS.Adaptive.textPrimary)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(DS.Adaptive.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(DS.Adaptive.stroke, lineWidth: 1)
                )
                .padding(.horizontal, 24)
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 12) {
                    // AI Setup button (primary)
                    NavigationLink(destination: TradingBotView(side: .buy, orderType: .market, quantity: 0, slippage: 0.5)) {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Set Up with AI")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundColor(BrandColors.ctaTextColor(isDark: colorScheme == .dark))
                        .background(
                            AdaptiveGradients.goldButton(isDark: colorScheme == .dark)
                        )
                        .cornerRadius(14)
                    }
                    
                    // Manual Setup button (secondary)
                    NavigationLink(destination: TradingBotView(side: .buy, orderType: .market, quantity: 0, slippage: 0.5)) {
                        HStack(spacing: 10) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Configure Manually")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(DS.Adaptive.cardBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(DS.Adaptive.stroke, lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .background(DS.Adaptive.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(DS.Adaptive.textSecondary)
                            .padding(8)
                            .background(Circle().fill(DS.Adaptive.chipBackground))
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    private var botTypeDescription: String {
        switch botType {
        case .dca:
            return "Dollar-cost averaging spreads your investment over time, buying regularly regardless of price to reduce timing risk."
        case .grid:
            return "Grid trading profits from market oscillations by placing buy and sell orders at regular price intervals."
        case .signal:
            return "Signal bots execute trades automatically when technical indicators match your specified conditions."
        case .prediction:
            return "Prediction markets let you speculate on future events and outcomes using crypto markets."
        }
    }
    
    private var botTypeSteps: [String] {
        switch botType {
        case .dca:
            return [
                "Set your investment amount per order",
                "Choose price deviation to trigger buys",
                "Define take profit and stop loss levels",
                "Bot buys automatically on dips"
            ]
        case .grid:
            return [
                "Define upper and lower price range",
                "Set number of grid levels",
                "Bot places buy/sell orders at each level",
                "Profits from price bouncing in range"
            ]
        case .signal:
            return [
                "Choose technical indicators (RSI, MACD, etc.)",
                "Set entry and exit conditions",
                "Define position size limits",
                "Bot trades when signals trigger"
            ]
        case .prediction:
            return [
                "Browse available prediction markets",
                "Choose an outcome to bet on",
                "Set your stake amount",
                "Win if your prediction is correct"
            ]
        }
    }
}

// MARK: - Spot Trading Section View

struct SpotTradingSection: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var showAIHelper: Bool = false
    
    private var chipGoldGradient: LinearGradient {
        colorScheme == .dark
            ? LinearGradient(colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange], startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [Color(red: 0.78, green: 0.60, blue: 0.10), Color(red: 0.65, green: 0.45, blue: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Premium AI Advisor Card
                PremiumAIAdvisorCard(
                    context: .spot,
                    title: "Spot Trading AI",
                    subtitle: "Get help buying & selling"
                ) {
                    showAIHelper = true
                }
                
                // Quick Trade Cards
                quickTradeSection
                
                // Recent Trades Section
                recentTradesSection
                
                // Markets Browse Section
                marketsBrowseSection
                
                Spacer(minLength: 32)
            }
            .padding(.vertical, 12)
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationTitle("Spot Trading")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAIHelper) {
            ContextualAIHelperView(context: .spot)
        }
    }
    
    private var quickTradeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Quick Trade")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Spacer()
                NavigationLink(destination: MarketView()) {
                    HStack(spacing: 4) {
                        Text("All Markets")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(chipGoldGradient)
                }
            }
            .padding(.horizontal, 16)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    NavigationLink(destination: TradeView(symbol: "BTC", showBackButton: true)) {
                        quickTradeCoinCard(symbol: "BTC", name: "Bitcoin", color: .orange)
                    }
                    NavigationLink(destination: TradeView(symbol: "ETH", showBackButton: true)) {
                        quickTradeCoinCard(symbol: "ETH", name: "Ethereum", color: .blue)
                    }
                    NavigationLink(destination: TradeView(symbol: "SOL", showBackButton: true)) {
                        quickTradeCoinCard(symbol: "SOL", name: "Solana", color: .purple)
                    }
                    NavigationLink(destination: TradeView(symbol: "BNB", showBackButton: true)) {
                        quickTradeCoinCard(symbol: "BNB", name: "Binance", color: .yellow)
                    }
                }
                .padding(.horizontal, 16)
            }
            
            HStack(spacing: 12) {
                NavigationLink(destination: TradeView(symbol: "BTC", showBackButton: true)) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 18))
                        Text("Buy")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundColor(.white)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.green))
                }
                
                NavigationLink(destination: TradeView(symbol: "BTC", showBackButton: true)) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 18))
                        Text("Sell")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundColor(.white)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.red))
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    private func quickTradeCoinCard(symbol: String, name: String, color: Color) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                Text(String(symbol.prefix(1)))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(color)
            }
            VStack(spacing: 2) {
                Text(symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Text(name)
                    .font(.system(size: 10))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
        }
        .frame(width: 80)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.Adaptive.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(DS.Adaptive.stroke, lineWidth: 1))
    }
    
    private var recentTradesSection: some View {
        let recentTrades = PaperTradingManager.shared.recentTrades(limit: 3)
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                    Text("Recent Trades")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            
            if recentTrades.isEmpty {
                emptyTradesState
            } else {
                VStack(spacing: 8) {
                    ForEach(recentTrades.prefix(3), id: \.id) { trade in
                        tradeRow(trade)
                    }
                }
            }
        }
    }
    
    private var emptyTradesState: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.left.arrow.right.circle")
                .font(.system(size: 28))
                .foregroundColor(DS.Adaptive.textTertiary)
            Text("No trades yet")
                .font(.system(size: 13))
                .foregroundColor(DS.Adaptive.textSecondary)
            Text("Your trading history will appear here")
                .font(.system(size: 11))
                .foregroundColor(DS.Adaptive.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.Adaptive.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(DS.Adaptive.stroke, lineWidth: 1))
        .padding(.horizontal, 16)
    }
    
    private func tradeRow(_ trade: PaperTrade) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill((trade.side == .buy ? Color.green : Color.red).opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: trade.side == .buy ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(trade.side == .buy ? .green : .red)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("\(trade.side == .buy ? "Buy" : "Sell") \(trade.symbol)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Text(formatTradeTime(trade.timestamp))
                    .font(.system(size: 10))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            Spacer()
            
            Text(formatTradeValue(trade.totalValue))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(DS.Adaptive.textPrimary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DS.Adaptive.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(DS.Adaptive.stroke, lineWidth: 1))
        .padding(.horizontal, 16)
    }
    
    private func formatTradeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func formatTradeValue(_ value: Double) -> String {
        if value >= 1000 { return String(format: "$%.1fK", value / 1000) }
        return String(format: "$%.2f", value)
    }
    
    private var marketsBrowseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Explore")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
                .padding(.horizontal, 16)
            
            VStack(spacing: 10) {
                NavigationLink(destination: MarketView()) {
                    marketCategoryRow(icon: "chart.bar.fill", iconColor: .purple, title: "All Markets", subtitle: "Browse all cryptocurrencies")
                }
                NavigationLink(destination: MarketView()) {
                    marketCategoryRow(icon: "flame.fill", iconColor: .orange, title: "Trending", subtitle: "Most popular coins today")
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    private func marketCategoryRow(icon: String, iconColor: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.Adaptive.textTertiary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.Adaptive.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(DS.Adaptive.stroke, lineWidth: 1))
    }
}

// MARK: - Bots Section View

struct BotsSectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var showAIHelper: Bool = false
    @State private var showBotOnboarding: Bool = false
    @State private var selectedBotType: QuickBotType? = nil
    
    @ObservedObject private var paperBotManager = PaperBotManager.shared
    @ObservedObject private var demoModeManager = DemoModeManager.shared
    
    private var chipGoldGradient: LinearGradient {
        colorScheme == .dark
            ? LinearGradient(colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange], startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [Color(red: 0.78, green: 0.60, blue: 0.10), Color(red: 0.65, green: 0.45, blue: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    private var displayedBots: [PaperBot] {
        demoModeManager.isDemoMode ? paperBotManager.demoBots : paperBotManager.paperBots
    }
    
    private var totalBotCount: Int {
        displayedBots.count
    }
    
    private var runningBotCount: Int {
        displayedBots.filter { $0.status == .running }.count
    }
    
    private var totalBotProfit: Double {
        displayedBots.reduce(0) { $0 + $1.totalProfit }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Premium AI Advisor Card
                PremiumAIAdvisorCard(
                    context: .bots,
                    title: "Bot Assistant",
                    subtitle: "Setup and optimize your bots"
                ) {
                    showAIHelper = true
                }
                
                // Bot Stats Summary
                botStatsSummaryCard
                
                // Create New Bot Section
                createBotSection
                
                // My Bots List
                myBotsSection
                
                Spacer(minLength: 32)
            }
            .padding(.vertical, 12)
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationTitle("Trading Bots")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAIHelper) {
            ContextualAIHelperView(context: .bots)
        }
        .sheet(isPresented: $showBotOnboarding) {
            if let botType = selectedBotType {
                BotOnboardingSheet(botType: botType)
            }
        }
    }
    
    private var botStatsSummaryCard: some View {
        HStack(spacing: 0) {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .font(.system(size: 12))
                        .foregroundColor(.purple)
                    Text("\(totalBotCount)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                Text("Total")
                    .font(.system(size: 10))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .frame(maxWidth: .infinity)
            
            Rectangle().fill(DS.Adaptive.divider).frame(width: 1, height: 30)
            
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                    Text("\(runningBotCount)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                Text("Running")
                    .font(.system(size: 10))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .frame(maxWidth: .infinity)
            
            Rectangle().fill(DS.Adaptive.divider).frame(width: 1, height: 30)
            
            VStack(spacing: 4) {
                Text(formatProfitLoss(totalBotProfit))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(totalBotProfit >= 0 ? .green : .red)
                Text("Total P/L")
                    .font(.system(size: 10))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.Adaptive.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DS.Adaptive.stroke, lineWidth: 1))
        .padding(.horizontal, 16)
    }
    
    private var createBotSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Create New Bot")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Spacer()
                // AI-Assisted setup option
                Button {
                    showAIHelper = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Ask AI")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(chipGoldGradient)
                }
            }
            .padding(.horizontal, 16)
            
            // Bot type cards with DIRECT links to manual setup forms
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // DCA Bot - Direct to form
                    NavigationLink(destination: TradingBotView(initialMode: .dcaBot)) {
                        quickBotTypeCard(.dca)
                    }
                    
                    // Grid Bot - Direct to form
                    NavigationLink(destination: TradingBotView(initialMode: .gridBot)) {
                        quickBotTypeCard(.grid)
                    }
                    
                    // Signal Bot - Direct to form
                    NavigationLink(destination: TradingBotView(initialMode: .signalBot)) {
                        quickBotTypeCard(.signal)
                    }
                }
                .padding(.horizontal, 16)
            }
            
            // Explainer text
            Text("Tap a bot type to configure it manually, or ask the AI for help")
                .font(.system(size: 11))
                .foregroundColor(DS.Adaptive.textTertiary)
                .padding(.horizontal, 16)
        }
    }
    
    private func quickBotTypeCard(_ botType: QuickBotType) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(botType.color.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: botType.icon)
                    .font(.system(size: 22))
                    .foregroundColor(botType.color)
            }
            VStack(spacing: 2) {
                Text(botType.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Text(botType.subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            // "Setup" indicator
            Text("Setup")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(botType.color))
        }
        .frame(width: 100)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.Adaptive.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DS.Adaptive.stroke, lineWidth: 1))
    }
    
    private var myBotsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.purple)
                    Text("My Bots")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    if totalBotCount > 0 {
                        Text("(\(totalBotCount))")
                            .font(.system(size: 12))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                }
                Spacer()
                NavigationLink(destination: BotHubView()) {
                    HStack(spacing: 4) {
                        Text("View All")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(chipGoldGradient)
                }
            }
            .padding(.horizontal, 16)
            
            if displayedBots.isEmpty {
                emptyBotsState
            } else {
                VStack(spacing: 10) {
                    ForEach(displayedBots.prefix(5)) { bot in
                        botRow(bot)
                    }
                }
            }
        }
    }
    
    private func botRow(_ bot: PaperBot) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(bot.type.color.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: bot.type.icon)
                    .font(.system(size: 16))
                    .foregroundColor(bot.type.color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(bot.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .lineLimit(1)
                    Circle()
                        .fill(bot.status == .running ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                }
                Text("\(bot.type.displayName) • \(bot.tradingPair.replacingOccurrences(of: "_", with: "/"))")
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatProfitLoss(bot.totalProfit))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(bot.totalProfit >= 0 ? .green : .red)
                Text("\(bot.totalTrades) trades")
                    .font(.system(size: 10))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                paperBotManager.toggleBot(id: bot.id)
            } label: {
                Image(systemName: bot.status == .running ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(bot.status == .running ? .orange : .green)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.Adaptive.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(bot.status == .running ? Color.green.opacity(0.3) : DS.Adaptive.stroke, lineWidth: 1))
        .padding(.horizontal, 16)
    }
    
    private var emptyBotsState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(BrandColors.goldBase.opacity(0.1))
                    .frame(width: 60, height: 60)
                Image(systemName: "cpu")
                    .font(.system(size: 24))
                    .foregroundStyle(chipGoldGradient)
            }
            
            VStack(spacing: 4) {
                Text("No Bots Yet")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Text("Create your first bot to start automated trading")
                    .font(.system(size: 12))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                selectedBotType = .dca
                showBotOnboarding = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                    Text("Create Bot")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Capsule().fill(AdaptiveGradients.goldButton(isDark: colorScheme == .dark)))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6]))
                        .foregroundColor(DS.Adaptive.stroke)
                )
        )
        .padding(.horizontal, 16)
    }
    
    private func formatProfitLoss(_ value: Double) -> String {
        let prefix = value >= 0 ? "+" : ""
        let absValue = abs(value)
        if absValue >= 1000 { return "\(prefix)$\(String(format: "%.1fK", value / 1000))" }
        return "\(prefix)$\(String(format: "%.2f", value))"
    }
}

// MARK: - Derivatives Section View

struct DerivativesSectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var showAIHelper: Bool = false
    
    private var chipGoldGradient: LinearGradient {
        colorScheme == .dark
            ? LinearGradient(colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange], startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [Color(red: 0.78, green: 0.60, blue: 0.10), Color(red: 0.65, green: 0.45, blue: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Premium AI Advisor Card
                PremiumAIAdvisorCard(
                    context: .derivatives,
                    title: "Derivatives AI",
                    subtitle: "Risk analysis & strategy help"
                ) {
                    showAIHelper = true
                }
                
                // Risk Warning Banner
                derivativesWarningBanner
                
                // How Derivatives Work - Educational Section
                howDerivativesWorkSection
                
                // Quick Actions
                derivativesQuickActions
                
                // Positions Section
                derivativesPositionsSection
                
                // Popular Perpetuals
                derivativesMarketInfo
                
                Spacer(minLength: 32)
            }
            .padding(.vertical, 12)
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationTitle("Derivatives")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAIHelper) {
            ContextualAIHelperView(context: .derivatives)
        }
    }
    
    private var derivativesWarningBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("High Risk Trading")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Text("Leverage amplifies both gains and losses")
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.orange.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.orange.opacity(0.3), lineWidth: 1))
        .padding(.horizontal, 16)
    }
    
    // MARK: - How Derivatives Work Section
    
    private var howDerivativesWorkSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header with AI helper hint
            HStack {
                Text("How Derivatives Work")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Spacer()
                
                // AI Help badge
                Button {
                    showAIHelper = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Ask AI")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(chipGoldGradient)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(BrandColors.goldBase.opacity(0.1))
                    )
                }
            }
            .padding(.horizontal, 16)
            
            // Educational cards
            VStack(spacing: 10) {
                derivativesExplainerCard(
                    icon: "arrow.up.arrow.down",
                    iconColor: .blue,
                    title: "Leverage Trading",
                    description: "Trade with more buying power than your balance. 5x leverage means $100 controls $500 worth of crypto."
                )
                
                derivativesExplainerCard(
                    icon: "arrow.up.right",
                    iconColor: .green,
                    title: "Long Position",
                    description: "Profit when price goes UP. You're betting the asset will increase in value."
                )
                
                derivativesExplainerCard(
                    icon: "arrow.down.right",
                    iconColor: .red,
                    title: "Short Position",
                    description: "Profit when price goes DOWN. You're betting the asset will decrease in value."
                )
                
                derivativesExplainerCard(
                    icon: "exclamationmark.shield",
                    iconColor: .orange,
                    title: "Liquidation Risk",
                    description: "If price moves against you too much, your position closes automatically. Higher leverage = higher risk."
                )
            }
            .padding(.horizontal, 16)
        }
    }
    
    private func derivativesExplainerCard(icon: String, iconColor: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            // Enhanced icon with subtle gradient
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [iconColor.opacity(0.2), iconColor.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(iconColor.opacity(0.1), lineWidth: 1)
        )
    }
    
    private var derivativesQuickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(DS.Adaptive.textPrimary)
                .padding(.horizontal, 16)
            
            HStack(spacing: 12) {
                NavigationLink(destination: DerivativesBotView()) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.up.right.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Open Long")
                                .font(.system(size: 15, weight: .bold))
                            Text("Bet price goes up")
                                .font(.system(size: 11))
                                .opacity(0.85)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .foregroundColor(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.green, Color.green.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                }
                
                NavigationLink(destination: DerivativesBotView()) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.down.right.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Open Short")
                                .font(.system(size: 15, weight: .bold))
                            Text("Bet price goes down")
                                .font(.system(size: 11))
                                .opacity(0.85)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .foregroundColor(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.red.opacity(0.95), Color.red.opacity(0.75)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    private var derivativesPositionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.15))
                            .frame(width: 24, height: 24)
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                    Text("Positions")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                Spacer()
                NavigationLink(destination: BotHubView()) {
                    HStack(spacing: 4) {
                        Text("View All")
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(chipGoldGradient)
                }
            }
            .padding(.horizontal, 16)
            
            VStack(spacing: 14) {
                // Icon with gradient background
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [DS.Adaptive.chipBackground, DS.Adaptive.cardBackground],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 56, height: 56)
                    Image(systemName: "chart.line.uptrend.xyaxis.circle")
                        .font(.system(size: 28))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                
                VStack(spacing: 4) {
                    Text("No open positions")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textSecondary)
                    Text("Open a long or short position to start trading derivatives")
                        .font(.system(size: 12))
                        .foregroundColor(DS.Adaptive.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [8, 4]))
                    .foregroundColor(DS.Adaptive.stroke.opacity(0.6))
            )
            .padding(.horizontal, 16)
        }
    }
    
    private var derivativesMarketInfo: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Popular Perpetuals")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(DS.Adaptive.textPrimary)
                .padding(.horizontal, 16)
            
            VStack(spacing: 10) {
                derivativesPerpCard(symbol: "BTC-PERP", name: "Bitcoin Perpetual", fundingRate: "+0.01%", color: .orange)
                derivativesPerpCard(symbol: "ETH-PERP", name: "Ethereum Perpetual", fundingRate: "+0.008%", color: .blue)
                derivativesPerpCard(symbol: "SOL-PERP", name: "Solana Perpetual", fundingRate: "+0.012%", color: .purple)
            }
            .padding(.horizontal, 16)
        }
    }
    
    private func derivativesPerpCard(symbol: String, name: String, fundingRate: String, color: Color) -> some View {
        NavigationLink(destination: DerivativesBotView()) {
            HStack(spacing: 14) {
                // Enhanced icon with gradient
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.2), color.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    Text(String(symbol.prefix(1)))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(color)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(symbol)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    Text(name)
                        .font(.system(size: 11))
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Funding")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    Text(fundingRate)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.green)
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(color.opacity(0.15), lineWidth: 1)
            )
        }
    }
}

// MARK: - Predictions Section View

struct PredictionsSectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var showAIHelper: Bool = false
    @State private var trendingMarkets: [PredictionMarketEvent] = []
    @State private var isLoadingTrending: Bool = false
    
    private var chipGoldGradient: LinearGradient {
        colorScheme == .dark
            ? LinearGradient(colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange], startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [Color(red: 0.78, green: 0.60, blue: 0.10), Color(red: 0.65, green: 0.45, blue: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Premium AI Advisor Card
                PremiumAIAdvisorCard(
                    context: .predictions,
                    title: "Predictions AI",
                    subtitle: "Market insights & betting tips"
                ) {
                    showAIHelper = true
                }
                
                // How Predictions Work - Educational Section
                howPredictionsWorkSection
                
                // Platform Cards
                predictionPlatformsSection
                
                // My Predictions
                myPredictionsSection
                
                // Trending Markets
                trendingMarketsSection
                
                Spacer(minLength: 32)
            }
            .padding(.vertical, 12)
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationTitle("Predictions")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAIHelper) {
            ContextualAIHelperView(context: .predictions)
        }
    }
    
    // MARK: - How Predictions Work Section
    
    private var howPredictionsWorkSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header with AI helper hint
            HStack {
                Text("How Prediction Markets Work")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Spacer()
                
                // AI Help badge
                Button {
                    showAIHelper = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Ask AI")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(chipGoldGradient)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(BrandColors.goldBase.opacity(0.1))
                    )
                }
            }
            .padding(.horizontal, 16)
            
            // Compact educational cards
            VStack(spacing: 10) {
                predictionExplainerCard(
                    icon: "questionmark.circle",
                    iconColor: .cyan,
                    title: "What Are Prediction Markets?",
                    description: "Bet on real-world events. The price reflects the crowd's probability estimate."
                )
                
                predictionExplainerCard(
                    icon: "dollarsign.circle",
                    iconColor: .green,
                    title: "How Payouts Work",
                    description: "Buy shares at market price. If your outcome wins, each share pays $1.00."
                )
                
                predictionExplainerCard(
                    icon: "chart.pie",
                    iconColor: .purple,
                    title: "Finding Edge",
                    description: "Profit by identifying when the market probability differs from reality."
                )
            }
            .padding(.horizontal, 16)
            
            // Quick action to place a bet
            NavigationLink(destination: PredictionBotView()) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                    Text("Place a Prediction Bet")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.black)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AdaptiveGradients.goldButton(isDark: colorScheme == .dark))
                )
            }
            .padding(.horizontal, 16)
        }
    }
    
    private func predictionExplainerCard(icon: String, iconColor: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            // Enhanced icon with gradient
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [iconColor.opacity(0.2), iconColor.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(iconColor.opacity(0.1), lineWidth: 1)
        )
    }
    
    private var predictionPlatformsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Platforms")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(DS.Adaptive.textPrimary)
                .padding(.horizontal, 16)
            
            HStack(spacing: 12) {
                NavigationLink(destination: PredictionMarketsView(sourceFilter: .polymarket)) {
                    predictionPlatformCard(name: "Polymarket", subtitle: "Crypto predictions", color: .purple)
                }
                
                NavigationLink(destination: PredictionMarketsView(sourceFilter: .kalshi)) {
                    predictionPlatformCard(name: "Kalshi", subtitle: "US regulated", color: Color(red: 0.0, green: 0.7, blue: 0.6))
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    private func predictionPlatformCard(name: String, subtitle: String, color: Color) -> some View {
        VStack(spacing: 10) {
            // Enhanced icon with gradient glow
            ZStack {
                // Outer glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [color.opacity(0.3), color.opacity(0.05)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 30
                        )
                    )
                    .frame(width: 56, height: 56)
                
                // Inner circle with gradient
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.25), color.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                
                // Platform icon
                Text(String(name.prefix(1)))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(color)
            }
            
            VStack(spacing: 3) {
                Text(name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [color.opacity(0.3), color.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
    
    private var myPredictionsSection: some View {
        let activeTrades = PredictionTradingService.shared.activeTrades
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.xaxis.ascending")
                        .font(.system(size: 12))
                        .foregroundColor(.cyan)
                    Text("My Predictions")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    if !activeTrades.isEmpty {
                        Text("(\(activeTrades.count))")
                            .font(.system(size: 12))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                }
                Spacer()
                NavigationLink(destination: BotHubView()) {
                    HStack(spacing: 4) {
                        Text("View All")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(chipGoldGradient)
                }
            }
            .padding(.horizontal, 16)
            
            if activeTrades.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "chart.bar.xaxis.ascending.badge.clock")
                        .font(.system(size: 36))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [DS.Adaptive.textTertiary, DS.Adaptive.textTertiary.opacity(0.6)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    Text("No active predictions")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DS.Adaptive.textSecondary)
                    
                    // Enhanced Browse Markets button
                    NavigationLink(destination: PredictionMarketsView()) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Browse Markets")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(AdaptiveGradients.goldButton(isDark: colorScheme == .dark))
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(DS.Adaptive.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6]))
                        .foregroundColor(DS.Adaptive.stroke)
                )
                .padding(.horizontal, 16)
            } else {
                VStack(spacing: 8) {
                    ForEach(activeTrades.prefix(3)) { trade in
                        predictionTradeRow(trade)
                    }
                }
            }
        }
    }
    
    private func predictionTradeRow(_ trade: LivePredictionTrade) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(trade.outcome == "YES" ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                    .frame(width: 36, height: 36)
                Text(trade.outcome == "YES" ? "Y" : "N")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(trade.outcome == "YES" ? .green : .red)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(trade.marketTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .lineLimit(1)
                Text("$\(Int(trade.amount)) bet on \(trade.outcome)")
                    .font(.system(size: 10))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            Spacer()
            
            Text(trade.platform)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.Adaptive.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(DS.Adaptive.chipBackground))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.Adaptive.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(DS.Adaptive.stroke, lineWidth: 1))
        .padding(.horizontal, 16)
    }
    
    // MARK: - Trending Markets Section
    
    private var trendingMarketsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trending Markets")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(DS.Adaptive.textPrimary)
                .padding(.horizontal, 16)
            
            if isLoadingTrending && trendingMarkets.isEmpty {
                // Loading shimmer
                VStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { _ in
                        trendingShimmerRow
                    }
                }
                .padding(.horizontal, 16)
            } else if trendingMarkets.isEmpty {
                // Fallback static data while loading
                VStack(spacing: 10) {
                    NavigationLink(destination: PredictionMarketsView()) {
                        trendingMarketRow(title: "Will BTC reach $100K in 2026?", probability: 0.72, volume: "$2.4M")
                    }
                    NavigationLink(destination: PredictionMarketsView()) {
                        trendingMarketRow(title: "ETH ETF approval by March?", probability: 0.45, volume: "$890K")
                    }
                    NavigationLink(destination: PredictionMarketsView()) {
                        trendingMarketRow(title: "Fed rate cut in Q1 2026?", probability: 0.57, volume: "$1.2M")
                    }
                }
                .padding(.horizontal, 16)
            } else {
                VStack(spacing: 10) {
                    ForEach(trendingMarkets.prefix(3)) { market in
                        NavigationLink(destination: PredictionMarketsView()) {
                            trendingMarketRowDynamic(market)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .task {
            await loadTrendingMarkets()
        }
    }
    
    private func loadTrendingMarkets() async {
        guard trendingMarkets.isEmpty else { return }
        isLoadingTrending = true
        
        do {
            let markets = try await PredictionMarketsService.shared.fetchTrendingMarkets(limit: 5)
            await MainActor.run {
                trendingMarkets = markets
                isLoadingTrending = false
            }
        } catch {
            await MainActor.run {
                trendingMarkets = PredictionMarketEvent.samples.prefix(3).map { $0 }
                isLoadingTrending = false
            }
        }
    }
    
    private var trendingShimmerRow: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(DS.Adaptive.chipBackground)
                    .frame(height: 14)
                RoundedRectangle(cornerRadius: 3)
                    .fill(DS.Adaptive.chipBackground)
                    .frame(width: 100, height: 6)
                RoundedRectangle(cornerRadius: 3)
                    .fill(DS.Adaptive.chipBackground)
                    .frame(width: 60, height: 10)
            }
            Spacer()
            VStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(DS.Adaptive.chipBackground)
                    .frame(width: 40, height: 18)
                RoundedRectangle(cornerRadius: 2)
                    .fill(DS.Adaptive.chipBackground)
                    .frame(width: 24, height: 8)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.Adaptive.cardBackground))
        .shimmer()
    }
    
    private func trendingMarketRowDynamic(_ market: PredictionMarketEvent) -> some View {
        let yesOutcome = market.outcomes.first(where: { $0.name.lowercased() == "yes" })
        let probability = yesOutcome?.probability ?? 0.5
        
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(market.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(DS.Adaptive.chipBackground)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: probability > 0.5 ? [.green, .green.opacity(0.7)] : [.red, .red.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * CGFloat(probability))
                    }
                }
                .frame(height: 6)
                
                HStack(spacing: 8) {
                    if let volume = market.volume, volume > 0 {
                        Text("Vol: \(formatVolumeForTrending(volume))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                    Text(market.source.displayName)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(market.source == .polymarket ? .purple : Color(red: 0.0, green: 0.7, blue: 0.6))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill((market.source == .polymarket ? Color.purple : Color(red: 0.0, green: 0.7, blue: 0.6)).opacity(0.12)))
                }
            }
            
            Spacer()
            
            VStack(spacing: 3) {
                Text("\(Int(probability * 100))%")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(probability > 0.5 ? .green : .red)
                Text("YES")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .frame(width: 50)
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.Adaptive.textTertiary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
    }
    
    private func formatVolumeForTrending(_ volume: Double) -> String {
        if volume >= 1_000_000 {
            return String(format: "$%.1fM", volume / 1_000_000)
        } else if volume >= 1_000 {
            return String(format: "$%.0fK", volume / 1_000)
        }
        return String(format: "$%.0f", volume)
    }
    
    private func trendingMarketRow(title: String, probability: Double, volume: String) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(DS.Adaptive.chipBackground)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: probability > 0.5 ? [.green, .green.opacity(0.7)] : [.red, .red.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * CGFloat(probability))
                    }
                }
                .frame(height: 6)
                
                Text("Vol: \(volume)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            Spacer()
            
            VStack(spacing: 3) {
                Text("\(Int(probability * 100))%")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(probability > 0.5 ? .green : .red)
                Text("YES")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .frame(width: 50)
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.Adaptive.textTertiary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke((probability > 0.5 ? Color.green : Color.red).opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Preview

#if DEBUG
struct SmartTradingHub_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            SmartTradingHub()
        }
        .preferredColorScheme(.dark)
    }
}
#endif
