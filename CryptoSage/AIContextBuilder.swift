//
//  AIContextBuilder.swift
//  CryptoSage
//
//  Builds context-rich system prompts by injecting live portfolio and market data.
//  Ensures the AI has current information to provide relevant responses.
//

import Foundation

/// Service responsible for building AI system prompts with live data context
@MainActor
final class AIContextBuilder {
    static let shared = AIContextBuilder()
    
    private init() {}
    
    // MARK: - System Prompt Building
    
    /// Build a comprehensive system prompt with current portfolio and market context
    func buildSystemPrompt() -> String {
        var sections: [String] = []
        
        // Trading mode indicator (at the very top for immediate context)
        sections.append(buildTradingModeSection())
        
        // Core identity
        sections.append(buildIdentitySection())
        
        // Portfolio context (if available)
        if let portfolioSection = buildPortfolioSection() {
            sections.append(portfolioSection)
        }
        
        // Market overview
        if let marketSection = buildMarketOverviewSection() {
            sections.append(marketSection)
        }
        
        // Market sentiment (Fear & Greed)
        if let sentimentSection = buildSentimentSection() {
            sections.append(sentimentSection)
        }
        
        // Smart Money / Whale data (REAL blockchain data)
        if let smartMoneySection = buildSmartMoneySection() {
            sections.append(smartMoneySection)
        }
        
        // Market regime detection
        if let regimeSection = buildMarketRegimeSection() {
            sections.append(regimeSection)
        }
        
        // Recent news headlines
        if let newsSection = buildNewsSection() {
            sections.append(newsSection)
        }
        
        // Watchlist
        if let watchlistSection = buildWatchlistSection() {
            sections.append(watchlistSection)
        }
        
        // Trading pair preferences (favorites, recents, preferred exchanges)
        if let pairPrefsSection = buildTradingPairPreferencesSection() {
            sections.append(pairPrefsSection)
        }
        
        // Prediction markets (if available)
        if let predictionSection = buildPredictionMarketsSection() {
            sections.append(predictionSection)
        }
        
        // AI Price Predictions (if user has generated any)
        if let aiPredictionSection = buildAIPredictionsSection() {
            sections.append(aiPredictionSection)
        }
        
        // AI Trading Signals (cached from signal service)
        if let signalsSection = buildTradingSignalsSection() {
            sections.append(signalsSection)
        }
        
        // Prediction accuracy track record
        if let accuracySection = buildPredictionAccuracySection() {
            sections.append(accuracySection)
        }
        
        // Technical levels for watchlist coins
        if let techLevelsSection = buildTechnicalLevelsSection() {
            sections.append(techLevelsSection)
        }
        
        // App feature overview (helps AI direct users to relevant features)
        if let overviewSection = buildAppOverviewSection() {
            sections.append(overviewSection)
        }
        
        // Guidelines
        sections.append(buildGuidelinesSection())
        
        return sections.joined(separator: "\n\n")
    }
    
    /// Build a lightweight system prompt for simple queries
    func buildLightweightPrompt() -> String {
        return """
        You are CryptoSage AI, a smart crypto assistant. Be friendly, direct, and helpful. \
        Give concise answers focused on what the user asked. \
        Use plain text only - no markdown (no #, **, * symbols). Use dashes or numbers for lists.
        """
    }
    
    /// Determine if a query needs the full context or can use the lightweight prompt
    /// Returns true for portfolio, trading, or market data queries
    func needsFullContext(for query: String) -> Bool {
        let lowercased = query.lowercased()
        
        // Keywords that indicate user is asking about THEIR portfolio or wants personalized advice
        let portfolioKeywords = [
            "my portfolio", "my holdings", "my coins", "my balance", "my position",
            "paper portfolio", "paper trading", "paper balance", "paper holdings",
            "should i buy", "should i sell", "should i hold", "should i invest",
            "rebalance", "my allocation", "my profit", "my loss", "my p&l",
            "how am i doing", "my performance", "my returns", "my watchlist",
            "buy or sell", "what should i do", "is it time to",
            "my trade", "my order", "execute", "place order",
            "my alert", "my alerts", "price alert", "alert close", "alerts close",
            "portfolio", "holdings", "balance"
        ]
        
        // Keywords that indicate user needs real-time market data
        let marketKeywords = [
            "price", "top gainers", "top losers", "gainers", "losers", "movers",
            "market", "trending", "volume", "market cap", "fear", "greed",
            "sentiment", "bullish", "bearish", "breaking out", "breakout",
            "support", "resistance", "ath", "all time", "today", "right now",
            "current", "latest", "live", "real-time", "realtime",
            "top 10", "top 5", "top coins", "best performing", "worst performing",
            "news", "what's happening", "update", "triggering"
        ]
        
        // Check if query contains portfolio-specific keywords
        for keyword in portfolioKeywords {
            if lowercased.contains(keyword) {
                return true
            }
        }
        
        // Check if query needs market data
        for keyword in marketKeywords {
            if lowercased.contains(keyword) {
                return true
            }
        }
        
        // Short general questions (< 40 chars) without keywords can use lightweight prompt
        // Examples: "What is Bitcoin?", "Explain DeFi", "What is staking?"
        if query.count < 40 {
            return false
        }
        
        // Longer queries might need context - be conservative
        return true
    }
    
    /// Get the appropriate system prompt based on query complexity
    /// Uses lightweight prompt for simple queries, full context for portfolio-related queries
    func getSystemPrompt(for query: String, portfolio: PortfolioViewModel? = nil) async -> String {
        if needsFullContext(for: query) {
            if let portfolio = portfolio {
                return buildSystemPrompt(portfolio: portfolio)
            }
            return buildSystemPrompt()
        }
        return buildLightweightPrompt()
    }
    
    // MARK: - Section Builders
    
    private struct TradingModeCapabilities {
        let isLiveTradingEnabled: Bool
        let isPaperTradingEnabled: Bool
        let hasPaperTradingAccess: Bool
        let isDemoMode: Bool
        let hasConnectedAccounts: Bool

        var canExecuteLiveTrade: Bool { isLiveTradingEnabled }
        var canExecutePaperTrade: Bool {
            !isLiveTradingEnabled && isPaperTradingEnabled && hasPaperTradingAccess
        }
    }

    private func currentTradingCapabilities() -> TradingModeCapabilities {
        TradingModeCapabilities(
            isLiveTradingEnabled: AppConfig.liveTradingEnabled,
            isPaperTradingEnabled: PaperTradingManager.isEnabled,
            hasPaperTradingAccess: PaperTradingManager.shared.hasAccess,
            isDemoMode: DemoModeManager.isEnabled,
            hasConnectedAccounts: !ConnectedAccountsManager.shared.accounts.isEmpty
        )
    }
    
    /// Build a clear trading mode indicator for the top of the system prompt
    private func buildTradingModeSection() -> String {
        let capabilities = currentTradingCapabilities()
        
        // Mode priority: Live Trading (Developer) > Paper Trading > Demo Mode > Advisory
        if capabilities.canExecuteLiveTrade {
            return """
            === CURRENT MODE: LIVE TRADING (Developer Mode) ===
            User is a DEVELOPER with LIVE TRADING ENABLED.
            You CAN help execute REAL trades on connected exchanges.
            
            CAPABILITIES:
            - Execute real buy/sell orders via trade_config
            - Set up live trading bots via bot_config
            - All trades use REAL money - always confirm with user before executing
            - Full access to portfolio data and trading features
            
            IMPORTANT: Always remind user that trades are REAL with real money at stake.
            Output trade configs when user wants to execute: <trade_config>{"symbol":"BTC",...}</trade_config>
            """
        } else if capabilities.canExecutePaperTrade {
            if capabilities.hasConnectedAccounts {
                return """
                === CURRENT MODE: PAPER TRADING (Real Accounts Also Connected) ===
                User is practicing with simulated paper funds AND has real exchange accounts connected.
                You have access to BOTH portfolios - use context to determine which one they mean:
                
                CONTEXT CLUES TO USE:
                - If they mention specific coins, check which portfolio holds them
                - Keywords like "practice", "paper", "simulated", "try" = paper portfolio
                - Keywords like "real", "actual", "live" = real portfolio
                - If genuinely ambiguous, you can reference both or ask naturally
                
                Trade execution defaults to PAPER unless they explicitly say "real trade".
                
                When user wants to execute a paper trade, output a trade config on one line:
                <trade_config>{"symbol":"SOL","direction":"buy","orderType":"limit","amount":"100","isUSDAmount":true,"price":"125.50"}</trade_config>
                """
            } else {
                return """
                === CURRENT MODE: PAPER TRADING ===
                User is practicing with $100K simulated funds. All trades are simulated - no real money.
                You CAN help execute paper trades.
                
                When user wants to execute a paper trade, output a trade config on one line:
                <trade_config>{"symbol":"SOL","direction":"buy","orderType":"limit","amount":"100","isUSDAmount":true,"price":"125.50"}</trade_config>
                """
            }
        } else if capabilities.isPaperTradingEnabled && !capabilities.hasPaperTradingAccess {
            return """
            === CURRENT MODE: PAPER TRADING SELECTED (ACCESS LOCKED) ===
            User selected paper trading, but their current tier does not allow paper trade execution.
            You CANNOT execute paper trades or output trade_config in this state.
            You SHOULD provide a concrete trade setup plan and tell them to unlock Paper Trading (Pro+) to execute in-app.
            """
        } else if capabilities.isDemoMode {
            if capabilities.hasConnectedAccounts {
                return """
                === CURRENT MODE: DEMO MODE (Has Real Accounts) ===
                User is viewing SAMPLE data but has real exchange accounts connected.
                This is FAKE demo portfolio data - NOT their real holdings.
                You CANNOT execute trades. Suggest switching to Live Mode or Paper Trading.
                """
            } else {
                return """
                === CURRENT MODE: DEMO MODE ===
                User is viewing SAMPLE/DEMO portfolio data - NOT real holdings.
                You CANNOT execute trades. Suggest connecting an exchange or enabling Paper Trading.
                """
            }
        } else if capabilities.hasConnectedAccounts {
            let accountCount = ConnectedAccountsManager.shared.accounts.count
            let accountsText = accountCount == 1 ? "1 exchange connected" : "\(accountCount) exchanges connected"
            return """
            === CURRENT MODE: PORTFOLIO VIEW (Real Data) ===
            User has \(accountsText) with REAL portfolio data.
            You can VIEW their portfolio and provide trading ADVICE.
            IMPORTANT: Live trade execution is NOT available in CryptoSage.
            Suggest Paper Trading to practice, or help them plan trades for their external exchange.
            """
        } else {
            return """
            === CURRENT MODE: NO DATA ===
            User has no connected exchanges - portfolio is empty.
            Guide them to connect an exchange for portfolio tracking, or try Paper Trading to practice.
            """
        }
    }
    
    private func buildIdentitySection() -> String {
        let capabilities = currentTradingCapabilities()
        
        var identityText = """
        You are CryptoSage AI, a smart crypto trading assistant.
        
        YOUR PERSONALITY:
        - Friendly and direct - like a knowledgeable friend who knows crypto
        - Get straight to the point - no lengthy intros or excessive caveats
        - Use natural conversational language, not corporate speak
        - Be confident in your analysis while noting key risks
        
        YOUR EXPERTISE:
        - Portfolio analysis and strategy
        - Market trends and sentiment
        - Entry/exit timing suggestions
        - DCA strategies
        - Diversification advice
        
        """
        
        // Mode priority: Live Trading (Developer) > Paper Trading > Demo Mode > Advisory
        if capabilities.canExecuteLiveTrade {
            identityText += """
        
        TRADING MODE: LIVE TRADING (Developer Mode)
        - DEVELOPER MODE IS ACTIVE - Live trade execution is ENABLED
        - You CAN execute REAL trades on the user's connected exchanges
        - This is a privileged mode - trades use REAL MONEY
        
        CAPABILITIES IN THIS MODE:
        - Execute market/limit buy/sell orders via <trade_config>
        - Set up live trading bots (DCA, Grid, Signal) via <bot_config>
        - Set price alerts
        - Full portfolio analysis with real data
        
        ALWAYS:
        - Confirm trade details before executing
        - Remind user that trades are REAL with real money
        - Show trade config for transparency
        - Prefer high-liquidity majors (BTC, ETH, SOL, BNB, XRP) unless user explicitly asks for a specific alt/meme coin
        - If confidence is low/uncertain, prefer watchlist/alert/setup guidance over aggressive execution language
        
        When user asks to trade, output on one line:
        <trade_config>{"symbol":"BTC","direction":"buy","orderType":"market","amount":"100","isUSDAmount":true}</trade_config>
        """
        } else if capabilities.canExecutePaperTrade {
            if capabilities.hasConnectedAccounts {
                identityText += """
        
        TRADING MODE: PAPER TRADING + REAL ACCOUNTS
        - The user is in PAPER TRADING mode with SIMULATED funds (no real money for paper trades)
        - They ALSO have real exchange accounts connected with actual holdings
        - You have access to BOTH portfolios:
          * PAPER TRADING: $100K simulated starting balance for practice
          * REAL PORTFOLIO: Their actual holdings on connected exchanges
        
        HOW TO HANDLE PORTFOLIO QUESTIONS:
        - Use context to determine which portfolio they mean (their wording, which coins they mention)
        - If they ask about a coin only in one portfolio, use that one
        - If genuinely unclear and it matters, naturally ask which they mean
        - Don't ask redundantly when it's obvious from context
        - Trades default to PAPER unless they explicitly say "real"
        
        Both portfolios are shown below. Reference the appropriate one based on context.
        
        EXECUTING PAPER TRADES:
        When user wants to execute a paper trade, output a trade config on one line:
        <trade_config>{"symbol":"BTC","direction":"buy","orderType":"market","amount":"100","isUSDAmount":true}</trade_config>
        - Use their paper USDT balance when sizing trades
        - For limit orders, include "price" field with target price
        - Set isUSDAmount:true for dollar amounts like "$100", false for quantities like "0.5 BTC"
        - Prefer high-liquidity majors by default; only use meme/micro-cap assets if user explicitly requests them
        - If confidence is low, frame as a cautious setup and suggest an alert instead of forceful execution language
        """
            } else {
                identityText += """
        
        TRADING MODE: PAPER TRADING (Practice Mode)
        - The user is in PAPER TRADING mode with SIMULATED funds (no real money)
        - They started with $100,000 in virtual USDT and may have made paper trades
        - You CAN and SHOULD help them execute paper trades to practice
        - Treat their paper portfolio as real for advice purposes
        - All trades will be simulated - encourage them to practice!
        
        You have access to the user's PAPER TRADING portfolio data below. Reference their paper balances and trades when relevant.
        
        EXECUTING PAPER TRADES:
        When user wants to execute a paper trade, output a trade config on one line:
        <trade_config>{"symbol":"BTC","direction":"buy","orderType":"market","amount":"100","isUSDAmount":true}</trade_config>
        - Use their paper USDT balance when sizing trades
        - For limit orders, include "price" field with target price
        - Set isUSDAmount:true for dollar amounts like "$100", false for quantities like "0.5 BTC"
        - Prefer high-liquidity majors by default; only use meme/micro-cap assets if user explicitly requests them
        - If confidence is low, frame as a cautious setup and suggest an alert instead of forceful execution language
        """
            }
        } else if capabilities.isPaperTradingEnabled && !capabilities.hasPaperTradingAccess {
            identityText += """
        
        TRADING MODE: PAPER TRADING SELECTED (LOCKED)
        - The user selected paper trading mode, but their plan does not permit in-app paper execution
        - You CANNOT execute trades or output <trade_config> in this state
        - You SHOULD still provide concrete trade setups (entry, sizing, stop, target) they can review
        - If they want one-tap in-app execution, tell them Paper Trading requires Pro+
        """
        } else if capabilities.isDemoMode {
            identityText += """
        
        TRADING MODE: DEMO MODE (Sample Data Only)
        - The user is viewing SAMPLE/DEMO portfolio data - this is NOT their real portfolio
        - The holdings shown are FAKE example data for demonstration purposes
        - DO NOT give personalized trading advice based on these demo holdings
        - You CANNOT execute any trades in demo mode
        - Suggest they either:
          1. Enable Paper Trading to practice with $100K simulated funds
          2. Connect a real exchange to see their actual portfolio
        """
            
            // Add reminder if they have connected accounts but are in demo mode
            if capabilities.hasConnectedAccounts {
                identityText += """
        
        NOTE: The user has real exchange accounts connected but is currently viewing demo data.
        Remind them they can switch off Demo Mode in Settings to see their actual portfolio.
        """
            }
        } else if capabilities.hasConnectedAccounts {
            identityText += """
        
        TRADING MODE: ADVISORY MODE (Real Portfolio Data)
        - The user has connected exchange accounts and you can see their REAL portfolio
        - In-app trade execution is NOT available for regular users
        - You CAN provide personalized advice based on their actual holdings
        
        WHAT YOU CAN DO:
        - Analyze their portfolio and suggest improvements
        - Recommend specific trades (entry, exit, stop loss, take profit levels)
        - Set up PRICE ALERTS to notify them of opportunities
        - Help them calculate position sizes based on risk tolerance
        - Walk them through placing orders on their exchange (Coinbase, Binance, etc.)
        - Explain market conditions and timing
        
        WHAT YOU CANNOT DO:
        - Execute trades directly (they must do this on their exchange)
        - Output <trade_config> tags (these won't work in advisory mode)
        
        If they want to practice trading in-app: Suggest enabling Paper Trading
        
        You have access to the user's real portfolio data below. Reference their actual holdings when relevant.
        If you spot something important (concentration risk, big movers, opportunities), mention it proactively.
        Help them plan their next moves - they'll execute the trades themselves on their exchange.
        """
        } else {
            identityText += """
        
        TRADING MODE: ADVISORY MODE (No Portfolio)
        - The user has NOT connected any exchange accounts yet
        - You don't have access to any portfolio data
        
        WHAT YOU CAN STILL DO:
        - Answer questions about crypto, trading strategies, market analysis
        - Set up PRICE ALERTS for coins they're interested in (output alert_suggestion tags)
        - Explain how to use the app features
        - Provide general trading education
        
        CREATING ALERTS (you CAN do this even without connected accounts):
        <alert_suggestion>{"symbol":"BTC","targetPrice":100000,"direction":"above","reason":"Price target alert","enableAI":true,"currentPrice":null}</alert_suggestion>
        
        SUGGEST THEY GET STARTED BY:
        1. Connect an exchange (Binance, Coinbase, etc.) for personalized portfolio advice
        2. Enable Paper Trading to practice with $100K simulated funds
        
        Help guide them to get started with crypto trading!
        """
        }
        
        identityText += "\n\nCurrent Time: \(formatCurrentTime())"
        
        return identityText
    }
    
    private func buildPortfolioSection() -> String? {
        // Access portfolio data from the shared PortfolioViewModel
        // This runs on MainActor so we can safely access @Published properties
        
        let holdings = getPortfolioHoldings()
        guard !holdings.isEmpty else { return nil }
        
        var lines: [String] = ["CURRENT PORTFOLIO:"]
        
        var totalValue: Double = 0
        var totalPL: Double = 0
        
        for holding in holdings.prefix(10) { // Top 10 holdings
            let value = holding.currentValue
            let pl = holding.profitLoss
            let dailySign = holding.dailyChange >= 0 ? "+" : ""
            
            totalValue += value
            totalPL += pl
            
            lines.append("- \(holding.coinSymbol): \(formatQuantity(holding.quantity)) (\(formatCurrency(value))) \(dailySign)\(formatPercent(holding.dailyChange))% today")
        }
        
        if holdings.count > 10 {
            lines.append("- ... and \(holdings.count - 10) more holdings")
        }
        
        let totalCostBasis = totalValue - totalPL
        let totalPLPercent = totalCostBasis > 0 ? (totalPL / totalCostBasis) * 100 : 0
        let plSign = totalPL >= 0 ? "+" : ""
        lines.append("")
        lines.append("Total Portfolio Value: \(formatCurrency(totalValue))")
        lines.append("Overall P/L: \(plSign)\(formatCurrency(totalPL)) (\(plSign)\(formatPercent(totalPLPercent))%)")
        
        return lines.joined(separator: "\n")
    }
    
    private func buildMarketOverviewSection() -> String? {
        let marketVM = MarketViewModel.shared
        
        var lines: [String] = ["MARKET OVERVIEW:"]
        
        // Global stats
        if let marketCap = marketVM.globalMarketCap, marketCap > 0 {
            lines.append("- Global Market Cap: \(formatLargeCurrency(marketCap))")
        }
        
        if let volume = marketVM.globalVolume24h, volume > 0 {
            lines.append("- 24h Volume: \(formatLargeCurrency(volume))")
        }
        
        if let btcDom = marketVM.btcDominance, btcDom > 0 {
            lines.append("- BTC Dominance: \(formatPercent(btcDom))%")
        }
        
        if let ethDom = marketVM.ethDominance, ethDom > 0 {
            lines.append("- ETH Dominance: \(formatPercent(ethDom))%")
        }
        
        // Global market change
        if let globalChange = marketVM.globalChange24hPercent {
            let sign = globalChange >= 0 ? "+" : ""
            lines.append("- Market 24h: \(sign)\(formatPercent(globalChange))%")
        }
        
        // Top coins by market cap
        let topCoins = Array(marketVM.allCoins.prefix(5))
        if !topCoins.isEmpty {
            lines.append("")
            lines.append("Top Coins by Market Cap:")
            for coin in topCoins {
                let change24h = coin.priceChangePercentage24hInCurrency ?? 0
                let changeSign = change24h >= 0 ? "+" : ""
                let priceStr = coin.priceUsd != nil ? formatCurrency(coin.priceUsd!) : "N/A"
                lines.append("- \(coin.symbol.uppercased()): \(priceStr) (\(changeSign)\(formatPercent(change24h))% 24h)")
            }
        }
        
        // Top gainers - coins with biggest 24h gains (important for spotting momentum)
        let gainers = marketVM.topGainers.prefix(3)
        if !gainers.isEmpty {
            lines.append("")
            lines.append("TOP GAINERS (24h):")
            for coin in gainers {
                let change = coin.priceChangePercentage24hInCurrency ?? 0
                let priceStr = coin.priceUsd != nil ? formatCurrency(coin.priceUsd!) : "N/A"
                lines.append("- \(coin.symbol.uppercased()): +\(formatPercent(change))% (\(priceStr))")
            }
            lines.append("Consider these for momentum plays, but verify volume and fundamentals.")
        }
        
        // Top losers - coins with biggest 24h losses (potential dip buying opportunities)
        let losers = marketVM.topLosers.prefix(3)
        if !losers.isEmpty {
            lines.append("")
            lines.append("TOP LOSERS (24h):")
            for coin in losers {
                let change = coin.priceChangePercentage24hInCurrency ?? 0
                let priceStr = coin.priceUsd != nil ? formatCurrency(coin.priceUsd!) : "N/A"
                lines.append("- \(coin.symbol.uppercased()): \(formatPercent(change))% (\(priceStr))")
            }
            lines.append("Potential dip opportunities - research why they dropped before suggesting.")
        }
        
        // Trending coins - what the market is watching
        let trending = marketVM.trendingCoins.prefix(3)
        if !trending.isEmpty {
            lines.append("")
            lines.append("TRENDING COINS:")
            for coin in trending {
                let change = coin.priceChangePercentage24hInCurrency ?? 0
                let sign = change >= 0 ? "+" : ""
                lines.append("- \(coin.symbol.uppercased()) (\(coin.name)): \(sign)\(formatPercent(change))% 24h")
            }
        }
        
        // MARKET REGIME - Critical for swing trading decisions
        if let btc = marketVM.allCoins.first(where: { $0.symbol.uppercased() == "BTC" }) {
            let sparkline = btc.sparklineIn7d
            if sparkline.count >= 50 {
                let sma10 = TechnicalsEngine.sma(sparkline, period: 10)
                let sma20 = TechnicalsEngine.sma(sparkline, period: 20)
                
                if let s10 = sma10, let s20 = sma20 {
                    lines.append("")
                    lines.append("MARKET REGIME (Critical for Trade Decisions):")
                    
                    let is10Above20 = s10 > s20
                    let currentPrice = btc.priceUsd ?? sparkline.last ?? 0
                    
                    // Check if MAs are inclining
                    let olderData = Array(sparkline.dropLast(5))
                    let sma10Old = TechnicalsEngine.sma(olderData, period: 10)
                    let sma20Old = TechnicalsEngine.sma(olderData, period: 20)
                    let sma10Inclining = sma10Old.map { s10 > $0 } ?? false
                    let sma20Inclining = sma20Old.map { s20 > $0 } ?? false
                    
                    lines.append("- BTC 10 SMA: \(formatCurrency(s10))")
                    lines.append("- BTC 20 SMA: \(formatCurrency(s20))")
                    lines.append("- 10 SMA vs 20 SMA: \(is10Above20 ? "ABOVE (Bullish)" : "BELOW (Bearish)")")
                    lines.append("- 10 SMA Trend: \(sma10Inclining ? "Inclining" : "Declining/Flat")")
                    lines.append("- 20 SMA Trend: \(sma20Inclining ? "Inclining" : "Declining/Flat")")
                    
                    // Trading bias recommendation
                    if is10Above20 && sma10Inclining && sma20Inclining {
                        lines.append("- TRADING BIAS: BULLISH - Favor LONG breakout setups, full position sizes OK")
                    } else if is10Above20 && !sma10Inclining {
                        lines.append("- TRADING BIAS: CAUTIOUS BULLISH - Longs OK but momentum slowing, use smaller sizes")
                    } else if !is10Above20 && !sma10Inclining && !sma20Inclining {
                        lines.append("- TRADING BIAS: BEARISH - AVOID long breakouts or significantly reduce position sizes")
                    } else if !is10Above20 {
                        lines.append("- TRADING BIAS: CAUTIOUS - 10 below 20 SMA, be very selective with longs")
                    } else {
                        lines.append("- TRADING BIAS: MIXED - No clear direction, trade with caution")
                    }
                    
                    // Price vs MAs
                    let priceVs20 = currentPrice > s20 ? "above" : "below"
                    lines.append("- BTC Price vs 20 SMA: \(priceVs20)")
                }
            }
        }
        
        return lines.count > 1 ? lines.joined(separator: "\n") : nil
    }
    
    private func buildWatchlistSection() -> String? {
        let marketVM = MarketViewModel.shared
        let watchlist = marketVM.watchlistCoins
        
        guard !watchlist.isEmpty else { return nil }
        
        var lines: [String] = ["USER'S WATCHLIST (\(watchlist.count) coins):"]
        lines.append("These are coins the user is actively monitoring - prioritize discussing these when relevant.")
        lines.append("")
        
        // Analyze watchlist for notable movements
        var bigMovers: [(coin: MarketCoin, change: Double)] = []
        
        for coin in watchlist.prefix(10) {
            let change24h = coin.priceChangePercentage24hInCurrency ?? 0
            let changeSign = change24h >= 0 ? "+" : ""
            let priceStr = coin.priceUsd != nil ? formatCurrency(coin.priceUsd!) : "N/A"
            lines.append("- \(coin.symbol.uppercased()) (\(coin.name)): \(priceStr) (\(changeSign)\(formatPercent(change24h))% 24h)")
            
            // Track big movers
            if abs(change24h) >= 5 {
                bigMovers.append((coin, change24h))
            }
        }
        
        if watchlist.count > 10 {
            lines.append("- ... and \(watchlist.count - 10) more")
        }
        
        // Highlight significant movements in watchlist
        if !bigMovers.isEmpty {
            lines.append("")
            lines.append("WATCHLIST ALERTS:")
            for (coin, change) in bigMovers.sorted(by: { abs($0.change) > abs($1.change) }).prefix(3) {
                if change >= 10 {
                    lines.append("- \(coin.symbol.uppercased()) surging +\(formatPercent(change))% - user may want to take profit or add")
                } else if change >= 5 {
                    lines.append("- \(coin.symbol.uppercased()) up +\(formatPercent(change))% - good momentum")
                } else if change <= -10 {
                    lines.append("- \(coin.symbol.uppercased()) dropping \(formatPercent(change))% - potential dip buy or stop loss?")
                } else if change <= -5 {
                    lines.append("- \(coin.symbol.uppercased()) down \(formatPercent(change))% - worth monitoring")
                }
            }
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func buildSentimentSection() -> String? {
        let sentimentVM = ExtendedFearGreedViewModel.shared
        
        guard let currentValue = sentimentVM.currentValue else { return nil }
        
        var lines: [String] = ["MARKET SENTIMENT (Fear & Greed Index):"]
        
        // Current sentiment
        let classification = sentimentVM.currentClassificationKey?.capitalized ?? "Unknown"
        lines.append("- Current: \(currentValue)/100 (\(classification))")
        
        // Trend indicators
        if let delta1d = sentimentVM.delta1d {
            let sign = delta1d >= 0 ? "+" : ""
            lines.append("- 24h Change: \(sign)\(delta1d) points")
        }
        
        if let delta7d = sentimentVM.delta7d {
            let sign = delta7d >= 0 ? "+" : ""
            lines.append("- 7d Change: \(sign)\(delta7d) points")
        }
        
        // Overall bias
        let bias = sentimentVM.bias
        let biasStr: String
        switch bias {
        case .bullish: biasStr = "Bullish (momentum rising)"
        case .bearish: biasStr = "Bearish (momentum falling)"
        case .neutral: biasStr = "Neutral (sideways)"
        }
        lines.append("- Market Bias: \(biasStr)")
        
        // AI observation
        let observation = sentimentVM.aiObservationText
        if !observation.isEmpty {
            lines.append("- Insight: \(observation)")
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func buildSmartMoneySection() -> String? {
        let whaleService = WhaleTrackingService.shared
        
        // Check if we have meaningful data
        let smi = whaleService.smartMoneyIndex
        let stats = whaleService.statistics
        let transactions = whaleService.recentTransactions
        
        guard smi != nil || stats != nil || !transactions.isEmpty else { return nil }
        
        var lines: [String] = ["SMART MONEY / WHALE ACTIVITY (REAL BLOCKCHAIN DATA):"]
        lines.append("This is REAL on-chain data from blockchain analysis, not speculation.")
        lines.append("")
        
        // Smart Money Index
        if let smi = smi {
            lines.append("SMART MONEY INDEX: \(smi.score)/100 (\(smi.trend.rawValue))")
            if smi.score >= 60 {
                lines.append("  → Interpretation: Institutions/whales actively accumulating (Bullish)")
            } else if smi.score <= 40 {
                lines.append("  → Interpretation: Institutions/whales selling/reducing exposure (Bearish)")
            } else {
                lines.append("  → Interpretation: Mixed positioning from large players (Neutral)")
            }
        }
        
        // Exchange Flows
        if let stats = stats {
            lines.append("")
            lines.append("EXCHANGE FLOW DATA:")
            
            let netFlowFormatted: String
            if abs(stats.netExchangeFlow) >= 1_000_000_000 {
                netFlowFormatted = String(format: "$%.2fB", abs(stats.netExchangeFlow) / 1_000_000_000)
            } else if abs(stats.netExchangeFlow) >= 1_000_000 {
                netFlowFormatted = String(format: "$%.1fM", abs(stats.netExchangeFlow) / 1_000_000)
            } else {
                netFlowFormatted = String(format: "$%.0f", abs(stats.netExchangeFlow))
            }
            
            if stats.netExchangeFlow < -100_000_000 {
                lines.append("  Net Flow: -\(netFlowFormatted) (STRONG OUTFLOW)")
                lines.append("  → Interpretation: Large amounts leaving exchanges = accumulation = BULLISH")
            } else if stats.netExchangeFlow < -10_000_000 {
                lines.append("  Net Flow: -\(netFlowFormatted) (Moderate Outflow)")
                lines.append("  → Interpretation: Crypto moving off exchanges = slightly bullish")
            } else if stats.netExchangeFlow > 100_000_000 {
                lines.append("  Net Flow: +\(netFlowFormatted) (STRONG INFLOW)")
                lines.append("  → Interpretation: Large amounts entering exchanges = potential selling = BEARISH")
            } else if stats.netExchangeFlow > 10_000_000 {
                lines.append("  Net Flow: +\(netFlowFormatted) (Moderate Inflow)")
                lines.append("  → Interpretation: Crypto moving to exchanges = slightly bearish")
            } else {
                lines.append("  Net Flow: \(netFlowFormatted) (Neutral)")
                lines.append("  → Interpretation: Balanced flows, no strong directional signal")
            }
        }
        
        // Recent Whale Transactions
        if !transactions.isEmpty {
            lines.append("")
            lines.append("RECENT WHALE TRANSACTIONS:")
            
            for tx in transactions.prefix(5) {
                let valueFormatted: String
                if tx.amountUSD >= 1_000_000_000 {
                    valueFormatted = String(format: "$%.2fB", tx.amountUSD / 1_000_000_000)
                } else if tx.amountUSD >= 1_000_000 {
                    valueFormatted = String(format: "$%.1fM", tx.amountUSD / 1_000_000)
                } else {
                    valueFormatted = String(format: "$%.0fK", tx.amountUSD / 1_000)
                }
                
                let direction = tx.transactionType == .exchangeDeposit ? "→ Exchange" : "← Exchange"
                let from = tx.fromLabel ?? "Unknown"
                lines.append("  • \(tx.symbol): \(valueFormatted) \(direction) (from: \(from))")
            }
            
            if transactions.count > 5 {
                lines.append("  ... and \(transactions.count - 5) more whale movements")
            }
        }
        
        lines.append("")
        lines.append("USE THIS DATA to inform your analysis. Whale activity often precedes price moves.")
        
        return lines.joined(separator: "\n")
    }
    
    private func buildMarketRegimeSection() -> String? {
        // Try to detect regime from BTC sparkline (market leader)
        let marketVM = MarketViewModel.shared
        guard let btc = marketVM.allCoins.first(where: { $0.symbol.uppercased() == "BTC" }),
              btc.sparklineIn7d.count >= 20 else {
            return nil
        }
        let sparkline = btc.sparklineIn7d
        
        let regimeResult = MarketRegimeDetector.detectRegime(closes: sparkline)
        
        var lines: [String] = ["MARKET REGIME (Detected from BTC/Market):"]
        lines.append("")
        lines.append("Current Regime: \(regimeResult.regime.displayName) (\(Int(regimeResult.confidence))% confidence)")
        lines.append("")
        
        // Regime-specific insights
        switch regimeResult.regime {
        case .trendingUp:
            lines.append("IMPLICATIONS:")
            lines.append("  - Trend-following strategies tend to work well")
            lines.append("  - Pullbacks may be buying opportunities")
            lines.append("  - Set trailing stops rather than fixed targets")
            
        case .trendingDown:
            lines.append("IMPLICATIONS:")
            lines.append("  - Risk management is critical")
            lines.append("  - Bounces may be selling opportunities")
            lines.append("  - Consider reducing position sizes")
            
        case .ranging:
            lines.append("IMPLICATIONS:")
            lines.append("  - Range-bound strategies work best")
            lines.append("  - Buy near support, sell near resistance")
            lines.append("  - Watch for breakout signals")
            
        case .highVolatility:
            lines.append("IMPLICATIONS:")
            lines.append("  - High risk environment")
            lines.append("  - Reduce position sizes")
            lines.append("  - Use wider stops")
            lines.append("  - Consider sitting on sidelines")
            
        case .lowVolatility:
            lines.append("IMPLICATIONS:")
            lines.append("  - Calm before the storm?")
            lines.append("  - Watch for volatility expansion")
            lines.append("  - Good time to plan entries")
            
        case .breakoutPotential:
            lines.append("IMPLICATIONS:")
            lines.append("  - Market coiling for a big move")
            lines.append("  - Direction uncertain but magnitude likely large")
            lines.append("  - Have plans for both breakout directions")
        }
        
        // Technical details
        lines.append("")
        lines.append("Regime Indicators:")
        if let adx = regimeResult.adxValue {
            lines.append("  ADX: \(String(format: "%.1f", adx)) (trend strength)")
        }
        if let atr = regimeResult.atrPercent {
            lines.append("  ATR: \(String(format: "%.2f", atr))% (volatility)")
        }
        if let trend = regimeResult.trendDirection {
            let trendLabel = trend == "up" ? "Bullish" : (trend == "down" ? "Bearish" : "Neutral")
            lines.append("  Trend Direction: \(trendLabel)")
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func buildNewsSection() -> String? {
        let newsVM = CryptoNewsFeedViewModel.shared
        let articles = newsVM.articles
        
        guard !articles.isEmpty else { return nil }
        
        var lines: [String] = ["RECENT CRYPTO NEWS (Last 24h):"]
        
        // Get top 5 most recent headlines
        let recentArticles = articles.prefix(5)
        
        for article in recentArticles {
            let source = article.sourceName
            let title = article.title
            // Truncate long titles
            let truncatedTitle = title.count > 80 ? String(title.prefix(77)) + "..." : title
            lines.append("- [\(source)] \(truncatedTitle)")
        }
        
        // Add note about more news available
        if articles.count > 5 {
            lines.append("- ... \(articles.count - 5) more articles available in News tab")
        }
        
        lines.append("")
        lines.append("Use news context to inform market outlook, but always combine with technical and portfolio analysis.")
        
        return lines.joined(separator: "\n")
    }
    
    private func buildPredictionMarketsSection() -> String? {
        let service = PredictionMarketService.shared
        
        // Only include if we have market data
        guard !service.trendingMarkets.isEmpty else { return nil }
        
        var lines: [String] = ["PREDICTION MARKETS (Polymarket/Kalshi):"]
        lines.append("Real-time event-based prediction markets. These show crowd-sourced probabilities for future events.")
        lines.append("")
        
        // Top trending markets
        let topMarkets = service.trendingMarkets.prefix(5)
        lines.append("TOP TRENDING MARKETS:")
        for market in topMarkets {
            let yesPrice = market.yesPrice.map { String(format: "%.0f%%", $0 * 100) } ?? "—"
            let platform = market.platform.displayName
            lines.append("- [\(platform)] \(market.title)")
            lines.append("  YES: \(yesPrice) | Volume: \(market.formattedVolume)")
        }
        
        // Crypto-specific markets (most relevant to our users)
        let cryptoMarkets = service.cryptoMarkets.prefix(3)
        if !cryptoMarkets.isEmpty {
            lines.append("")
            lines.append("CRYPTO PREDICTION MARKETS:")
            for market in cryptoMarkets {
                let yesPrice = market.yesPrice.map { String(format: "%.0f%%", $0 * 100) } ?? "—"
                lines.append("- \(market.title): YES \(yesPrice)")
                if let desc = market.description, !desc.isEmpty {
                    let truncated = desc.count > 80 ? String(desc.prefix(77)) + "..." : desc
                    lines.append("  \(truncated)")
                }
            }
        }
        
        // Add guidance for the AI
        lines.append("")
        lines.append("PREDICTION MARKET GUIDANCE:")
        lines.append("- These are speculative markets - outcomes are NOT guaranteed")
        lines.append("- Prices represent crowd probability estimates (0.50 = 50% chance)")
        lines.append("- Low prices (e.g., 0.10) mean the crowd thinks outcome is unlikely but offer high upside")
        lines.append("- High prices (e.g., 0.90) mean high probability but limited upside")
        lines.append("- Volume indicates market liquidity and interest")
        lines.append("- Compare prediction market odds to your own analysis to find potential edges")
        lines.append("- IMPORTANT: These involve real money and carry significant risk")
        
        return lines.joined(separator: "\n")
    }
    
    /// Build a section with the user's recent AI price predictions
    private func buildAIPredictionsSection() -> String? {
        let service = AIPricePredictionService.shared
        let predictions = service.cachedPredictions.values.sorted { $0.generatedAt > $1.generatedAt }
        
        // Only include if we have predictions
        guard !predictions.isEmpty else { return nil }
        
        var lines: [String] = ["AI PRICE PREDICTIONS (Powered by CryptoSage AI):"]
        lines.append("These predictions were generated by CryptoSage AI, our specialized crypto prediction engine. Reference these when discussing related coins or trading strategies. Present them with confidence as they come from our dedicated prediction system.")
        lines.append("")
        
        for prediction in predictions.prefix(5) {
            let timeAgo = formatTimeAgo(prediction.generatedAt)
            lines.append("[\(prediction.coinSymbol)] \(prediction.timeframe.fullName) Forecast (generated \(timeAgo)):")
            lines.append("  Direction: \(prediction.direction.displayName.uppercased())")
            lines.append("  Predicted Change: \(prediction.formattedPriceChange)")
            lines.append("  Confidence: \(prediction.confidenceScore)% (\(prediction.confidence.displayName))")
            lines.append("  Price Range: \(prediction.priceRangeText)")
            
            // Include top drivers
            let topDrivers = prediction.drivers.prefix(3)
            if !topDrivers.isEmpty {
                let driversText = topDrivers.map { "\($0.name): \($0.signal)" }.joined(separator: ", ")
                lines.append("  Key Drivers: \(driversText)")
            }
            
            lines.append("  Analysis: \(prediction.analysis)")
            lines.append("")
        }
        
        lines.append("AI PREDICTION GUIDANCE:")
        lines.append("- These predictions were generated by CryptoSage AI using 10+ real-time data sources: technical indicators (RSI, MACD, Stochastic RSI, ADX, Bollinger Bands), market sentiment (Fear & Greed), whale/smart money data, derivatives data (funding rates, open interest), and Google Trends")
        lines.append("- Reference these predictions when the user asks about the predicted coins — present them as data from our specialized prediction engine")
        lines.append("- If asked about a coin without a prediction, let the user know they can generate one from the Predictions tab")
        lines.append("- Always remind users that predictions are probabilistic estimates, not financial advice")
        lines.append("- Use prediction data to inform trade suggestions and entry/exit discussions")
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Trading Signals Section
    
    /// Build a section with recent AI trading signals from the signal service cache
    private func buildTradingSignalsSection() -> String? {
        let signalService = AITradingSignalService.shared
        let cachedSignals = signalService.cachedSignalsList
        
        guard !cachedSignals.isEmpty else { return nil }
        
        var lines: [String] = ["AI TRADING SIGNALS (Active):"]
        lines.append("These are recent AI-generated trading signals from our DeepSeek-powered signal engine.")
        lines.append("")
        
        for entry in cachedSignals.prefix(5) {
            let signal = entry.signal
            let typeStr = signal.type == .buy ? "BUY" : (signal.type == .sell ? "SELL" : "HOLD")
            let confidence = signal.confidenceLabel
            let timeAgo = formatTimeAgo(signal.timestamp)
            
            lines.append("[\(entry.coinId.uppercased())] Signal: \(typeStr) | Confidence: \(confidence) | \(timeAgo)")
            if !signal.reasoning.isEmpty {
                let truncated = signal.reasoning.count > 120 ? String(signal.reasoning.prefix(117)) + "..." : signal.reasoning
                lines.append("  Analysis: \(truncated)")
            }
            if !signal.reasons.isEmpty {
                let factors = signal.reasons.prefix(3).joined(separator: ", ")
                lines.append("  Key Factors: \(factors)")
            }
            lines.append("  Risk: \(signal.riskLevel) | Sentiment: \(String(format: "%.2f", signal.sentimentScore))")
            lines.append("")
        }
        
        lines.append("SIGNAL GUIDANCE:")
        lines.append("- Reference these signals when the user asks about the relevant coins")
        lines.append("- Signals are generated by our DeepSeek-powered prediction engine using technical indicators, sentiment, and market data")
        lines.append("- Always combine signal data with the user's portfolio context and risk tolerance")
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Prediction Accuracy Section
    
    /// Build a section with prediction accuracy metrics so the AI can calibrate confidence
    private func buildPredictionAccuracySection() -> String? {
        let service = PredictionAccuracyService.shared
        let metrics = service.metrics
        
        // Only include if we have evaluated predictions
        guard metrics.evaluatedPredictions > 0 else { return nil }
        
        var lines: [String] = ["PREDICTION ACCURACY TRACK RECORD:"]
        lines.append("Historical performance of our AI prediction engine (helps calibrate confidence):")
        lines.append("")
        
        // Overall stats
        lines.append("Overall: \(metrics.evaluatedPredictions) predictions evaluated")
        lines.append("  Direction Accuracy: \(metrics.formattedDirectionAccuracy) (\(metrics.directionsCorrect)/\(metrics.evaluatedPredictions) correct)")
        lines.append("  Price Range Accuracy: \(metrics.formattedRangeAccuracy)")
        lines.append("  Avg Price Error: \(metrics.formattedAverageError)")
        
        // DeepSeek-specific metrics
        let dsMetrics = service.deepSeekMetrics
        if dsMetrics.evaluatedPredictions > 0 {
            lines.append("")
            lines.append("DeepSeek Model Performance:")
            lines.append("  Evaluated: \(dsMetrics.evaluatedPredictions) predictions")
            lines.append("  Direction Accuracy: \(dsMetrics.formattedDirectionAccuracy)")
            lines.append("  Range Accuracy: \(dsMetrics.formattedRangeAccuracy)")
        }
        
        // Timeframe breakdown (compact)
        let timeframes = metrics.metricsByTimeframe
        if !timeframes.isEmpty {
            lines.append("")
            lines.append("By Timeframe:")
            for (tf, tfMetrics) in timeframes.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                if tfMetrics.evaluatedPredictions >= 2 {
                    lines.append("  \(tf.displayName): \(String(format: "%.0f%%", tfMetrics.directionAccuracyPercent)) direction accuracy (\(tfMetrics.evaluatedPredictions) evaluated)")
                }
            }
        }
        
        // Recent outcomes (last 5 evaluated predictions)
        let recentPredictions = service.recentPredictions(limit: 5)
        if !recentPredictions.isEmpty {
            lines.append("")
            lines.append("Recent Outcomes:")
            for pred in recentPredictions {
                let directionResult = pred.directionCorrect == true ? "CORRECT" : "WRONG"
                let rangeResult = pred.withinPriceRange == true ? "in-range" : "out-of-range"
                let errorStr = pred.priceError.map { String(format: "%.1f%%", $0) } ?? "—"
                lines.append("  \(pred.coinSymbol) \(pred.timeframe.rawValue): \(pred.predictedDirection.rawValue.uppercased()) → \(directionResult), \(rangeResult), error: \(errorStr)")
            }
        }
        
        lines.append("")
        lines.append("ACCURACY GUIDANCE:")
        lines.append("- Use this track record to calibrate your confidence when referencing predictions")
        lines.append("- If accuracy is low for a timeframe or direction, mention the uncertainty")
        lines.append("- Higher-accuracy timeframes/directions deserve more confident language")
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Technical Levels Section
    
    /// Build a section with cached technical analysis for portfolio/watchlist coins
    private func buildTechnicalLevelsSection() -> String? {
        // Get coins from watchlist/portfolio
        let favoriteIDs = FavoritesManager.shared.favoriteIDs
        
        // We can't easily access TechnicalsViewModel instances for multiple coins
        // since they are per-coin. Instead, we pull any cached Firebase technicals
        // from the shared AI cache.
        // For now, build a lightweight section from any available indicator signals.
        
        guard !favoriteIDs.isEmpty else { return nil }
        
        // Try to access cached technicals from UserDefaults (TechnicalsViewModel caches here)
        var techLines: [String] = []
        let defaults = UserDefaults.standard
        
        for coinId in favoriteIDs.prefix(3) {
            let symbol = coinId.uppercased()
            let cacheKey = "technicals_cache_\(symbol)_1d_cryptosage"
            
            guard let data = defaults.data(forKey: cacheKey),
                  let summary = try? JSONDecoder().decode(TechnicalsSummary.self, from: data) else {
                continue
            }
            
            let verdictStr = summary.verdict.rawValue
            let scoreStr = String(format: "%.0f", summary.score01 * 100)
            
            var coinLine = "[\(symbol)] Score: \(scoreStr)/100 (\(verdictStr))"
            coinLine += " | Buy:\(summary.buyCount) Neutral:\(summary.neutralCount) Sell:\(summary.sellCount)"
            
            if let confidence = summary.confidence {
                coinLine += " | Confidence: \(confidence)%"
            }
            if let trend = summary.trendStrength {
                coinLine += " | Trend: \(trend)"
            }
            if let volatility = summary.volatilityRegime {
                coinLine += " | Volatility: \(volatility)"
            }
            
            // Add key indicator highlights
            var indicators: [String] = []
            for signal in summary.indicators.prefix(5) {
                if signal.signal != .neutral {
                    indicators.append("\(signal.label): \(signal.signal.rawValue)")
                }
            }
            
            techLines.append(coinLine)
            if !indicators.isEmpty {
                techLines.append("  Key Signals: \(indicators.joined(separator: ", "))")
            }
        }
        
        guard !techLines.isEmpty else { return nil }
        
        var lines: [String] = ["TECHNICAL ANALYSIS (Watchlist Coins):"]
        lines.append("Cached technical summaries for the user's watchlist coins:")
        lines.append("")
        lines.append(contentsOf: techLines)
        lines.append("")
        lines.append("Use these technicals to inform trade advice and confirm or challenge predictions.")
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - App Feature Overview Section
    
    /// Build a compact summary of app features so the AI can direct users appropriately
    private func buildAppOverviewSection() -> String? {
        return """
        APP FEATURES AVAILABLE:
        The user has access to these CryptoSage features — reference them when relevant:
        - Predictions Tab: AI price predictions powered by DeepSeek (1h, 4h, 12h, 24h, 7d, 30d timeframes)
        - Trading Signals: AI BUY/SELL/HOLD signals with confidence scores (on coin detail pages)
        - Technical Analysis: 30+ indicators (RSI, MACD, Bollinger Bands, etc.) from multiple sources
        - Market Sentiment: Fear & Greed Index + CryptoSage AI sentiment score
        - Heatmap: Visual market overview showing gainers/losers
        - News: Real-time crypto news from multiple RSS sources
        - Portfolio: Track holdings, P&L, allocation, and risk analysis
        - Trading: Execute paper or live trades (depending on mode)
        - Alerts: Price alerts with AI-enhanced notifications
        - Order Book: Real-time depth charts for supported coins
        - Risk Report: Portfolio risk scoring with AI recommendations
        - Prediction Markets: Polymarket/Kalshi integration for event-based trading
        
        When the user asks about data you don't have in context, suggest they check the relevant tab.
        Example: "You can get a detailed 7-day forecast from the Predictions tab."
        """
    }
    
    private func buildGuidelinesSection() -> String {
        let isPaperTrading = PaperTradingManager.isEnabled
        let isDemoMode = DemoModeManager.isEnabled
        let hasConnectedAccounts = !ConnectedAccountsManager.shared.accounts.isEmpty
        
        var guidelines = """
        RESPONSE GUIDELINES:
        
        CRITICAL FORMATTING RULES (MUST FOLLOW):
        - NEVER use markdown syntax. No asterisks (*), no hashes (#), no underscores for emphasis
        - For emphasis, just use CAPS or say "important:" before key points
        - For lists, use simple dashes (-) or numbers (1. 2. 3.)
        - Keep paragraphs short - 2-3 sentences max
        - Use blank lines between sections for readability
        - This is a mobile app - be concise!
        
        RESPONSE STYLE:
        - Be conversational and direct, like texting a knowledgeable friend
        - Get to the point quickly - lead with the answer, then explain
        - Use simple language, avoid jargon unless necessary
        - If giving multiple points, keep each point brief (one line if possible)
        - End with a clear takeaway or actionable suggestion when appropriate
        
        CRITICAL — WHEN NOT TO SUGGEST TRADES, ALERTS, OR BOTS:
        Do NOT output trade_config, alert_suggestion, bot_config, or strategy_config tags unless the user EXPLICITLY asked for trading advice, an alert, a bot, or a strategy.
        
        Specifically, DO NOT output actionable cards when the user asks to:
        - Summarize or read an article/link
        - Explain a concept, coin, or technology
        - Research news or events
        - Compare assets for educational purposes
        - Ask general "what is" or "how does" questions
        
        Even if your analysis mentions prices, entry levels, or buying opportunities, do NOT attach a trade/alert card unless the user's message specifically requested a trade, alert, or bot. The user wants information, not unsolicited trading actions.
        
        When the user IS asking for trading advice (e.g., "should I buy SOL?", "set up a trade", "give me an entry"), THEN output the appropriate action tags.
        
        WRONG: User says "Summarize this Bitcoin article" -> You mention "consider buying around $69K" -> You output a <trade_config> tag
        RIGHT: User says "Summarize this Bitcoin article" -> You mention "consider buying around $69K" -> NO action tags, just the analysis
        RIGHT: User says "Should I buy BTC? Set up a trade" -> You output a <trade_config> tag with your recommendation
        
        PRICE ALERT CREATION (IMPORTANT - YOU CAN DO THIS):
        You CAN create price alerts for the user. This works in ALL modes (paper trading, demo, live).
        When the user asks you to set up an alert, or when you want to proactively suggest one:
        
        Output an alert_suggestion tag on one line (the user won't see the tags, only a nice card):
        <alert_suggestion>{"symbol":"BTC","targetPrice":50000,"direction":"above","reason":"Breakout above resistance","enableAI":true,"currentPrice":48500}</alert_suggestion>
        
        Fields:
        - symbol: The crypto ticker (e.g., "BTC", "ETH", "SOL")
        - targetPrice: The USD price that triggers the alert (number, not string)
        - direction: "above" or "below"
        - reason: Brief explanation of why this alert is useful
        - enableAI: true for AI-enhanced alerts (sentiment, volume spike detection), false for simple price alerts
        - currentPrice: The current price if you know it (can be null)
        
        WHEN TO CREATE ALERTS:
        - User explicitly asks: "set up an alert", "create an alert", "notify me when", "alert me if"
        - User asks about specific price targets and wants to be notified
        - User explicitly wants to watch for entry/exit points
        - When you suggest a trade idea AND the user asked for trading advice, offer an alert for the entry price
        
        WHEN NOT TO CREATE ALERTS:
        - User is asking to summarize an article or news
        - User is asking for general analysis or explanations
        - User didn't mention wanting alerts, notifications, or monitoring
        - You're just discussing prices/levels in an educational or analytical context
        
        IMPORTANT BEHAVIOR:
        - When user asks you to SET UP or CREATE an alert, DO IT immediately by outputting the tag
        - Don't just explain how alerts work - actually create them
        - After the tag, give a friendly confirmation like "I've set up an alert for you!"
        - You can create multiple alerts in one response if needed
        - The app will show a confirmation card the user can tap to finalize
        
        Example exchange:
        User: "Set up an alert for BTC at 100K"
        You: "I've set up an alert for you! You'll be notified when Bitcoin reaches $100,000.
        <alert_suggestion>{"symbol":"BTC","targetPrice":100000,"direction":"above","reason":"User-requested price target","enableAI":true,"currentPrice":97500}</alert_suggestion>"
        """
        
        // Mode-specific trading advice guidelines
        if isPaperTrading {
            if hasConnectedAccounts {
                guidelines += """
        
        PAPER TRADING WITH REAL ACCOUNTS CONNECTED:
        The user has BOTH paper trading AND real exchange accounts. Be smart about context:
        
        1. INFER which portfolio from context clues:
           - Check which portfolio has the coins they mention
           - Look for keywords: "practice/paper/try" = paper, "real/actual" = real portfolio
           - If asking about P/L, check which portfolio has those positions
        
        2. Only ask for clarification if GENUINELY ambiguous (not as a default)
        
        3. You CAN proactively compare both portfolios when helpful:
           - "Your paper BTC is up 5% while your real BTC is up 3%"
        
        4. For PAPER trades: Reference paper balance, encourage experimentation, you can execute these
        5. For REAL portfolio questions: Help them PLAN trades to execute on their own exchange
        
        TRADE EXECUTION:
        - You can execute PAPER trades (simulated with virtual money)
        - Live trade execution is NOT available - help them plan trades for their exchange
        - If discussing their real portfolio, provide entry/stop/size recommendations
        """
            } else {
                guidelines += """
        
        CRITICAL FOR PAPER TRADING ADVICE:
        When the user asks about trading:
        1. Reference their paper trading balance and positions
        2. Encourage experimentation - it's simulated, so no real risk!
        3. Suggest specific paper trades to practice different strategies
        4. Factor in current market sentiment for realistic practice
        5. Help them learn by explaining the reasoning behind suggestions
        """
            }
        } else if isDemoMode {
            guidelines += """
        
        CRITICAL - DEMO MODE RESTRICTIONS:
        The user is in DEMO MODE viewing SAMPLE/FAKE portfolio data.
        - DO NOT give personalized trading advice based on demo holdings
        - DO NOT reference the demo portfolio as if it were real
        - You CANNOT execute any trades in demo mode
        - Instead, guide them to:
          1. Enable Paper Trading to practice with $100K simulated funds
          2. Connect a real exchange to see their actual portfolio
        - You can still answer general crypto questions and provide market insights
        """
        } else if hasConnectedAccounts {
            guidelines += """
        
        CRITICAL FOR PORTFOLIO-BASED ADVICE (MUST FOLLOW):
        When the user asks "should I buy/sell", "what should I do", or any trading advice:
        1. START by mentioning their specific holdings - name the coins they own and their allocations
        2. Reference their current profit/loss on relevant positions
        3. Consider their portfolio concentration - flag if heavily weighted in one asset
        4. Factor in the current market sentiment (Fear & Greed)
        5. Mention any relevant recent news that could impact the decision
        6. Give PERSONALIZED advice based on THEIR specific situation
        7. Help them PLAN trades they'll execute on their own exchange
        
        IMPORTANT: CryptoSage does NOT execute live trades.
        - Provide specific entry prices, stop losses, position sizes
        - Help them plan the trade, they'll execute it on Coinbase/Binance/etc.
        - If they want to practice: Suggest Paper Trading mode
        
        Example good response: "You're 47% in BTC (+15% P/L) and sentiment is at 35 (Fear). If you want to add more, consider a limit order around $X with a stop at $Y..."
        """
        } else {
            guidelines += """
        
        USER HAS NO EXCHANGES CONNECTED:
        The user hasn't connected any exchanges yet, so:
        - Their portfolio is empty - you cannot give portfolio-based advice
        - Guide them to get started:
          1. Connect an exchange to VIEW their portfolio (Binance, Coinbase, etc.)
          2. Enable Paper Trading to PRACTICE with $100K simulated funds
        - You can still answer general crypto questions and provide market insights
        """
        }
        
        guidelines += """
        
        WHEN GIVING TRADING INSIGHTS:
        - Reference current market sentiment (Fear/Greed score and trend)
        - Mention relevant news if it impacts the discussion
        - Give specific, actionable insights with numbers
        - Briefly explain your reasoning
        - Include a quick risk note for trade suggestions
        
        USING TRADE HISTORY FOR RECOMMENDATIONS:
        - Check user's trade history to understand their preferred pairs
        - Recommend similar pairs to ones they've traded before
        - Use their preferred exchange when suggesting trades
        - Match trade sizes to their typical trading amounts
        - If they trade BTC/USDT often, suggest BTC/USDT not BTC/USD unless on Coinbase
        
        GENERIC TRADE PROMPTS (IMPORTANT SAFETY RULE):
        - If the user says something vague like "set me up a trade" without naming a coin:
          1) Default to a major liquid asset only (BTC, ETH, or SOL)
          2) Ask for quick confirmation of the asset before finalizing details
        - Do NOT pick random low-liquidity or obscure tickers from general context prose.
        """
        
        // Trade execution guidelines based on mode
        if isPaperTrading {
            if hasConnectedAccounts {
                guidelines += """
        
        TRADE EXECUTION (Paper Trading Mode):
        You can help the user execute SIMULATED paper trades only.
        
        FOR PAPER TRADES:
        - Output a trade_config tag so the app shows an Execute button
        - Reference their paper balance when suggesting trade sizes
        - These are SIMULATED trades with virtual money for practice
        - Do NOT say "I can't execute trades directly" in paper mode
        - Instead say you can prepare an in-app paper trade and ask for confirmation
        - Preferred phrasing: "I can set this up as a paper trade in-app for your confirmation."
        
        Example: <trade_config>{"symbol":"SOL","direction":"buy","orderType":"limit","amount":"500","isUSDAmount":true,"price":"126.50"}</trade_config>
        
        PRICE ALERTS (Available in all modes):
        You CAN create price alerts. When user asks to set up alerts, output:
        <alert_suggestion>{"symbol":"BTC","targetPrice":100000,"direction":"above","reason":"Price target alert","enableAI":true,"currentPrice":null}</alert_suggestion>
        
        IMPORTANT: Live trade execution is NOT available in CryptoSage.
        If user asks about trading their REAL holdings:
        - Help them PLAN the trade (entry, stop loss, position size)
        - They'll execute it themselves on their exchange
        - Paper trading is for practice; real trades happen on their exchange
        """
            } else {
                guidelines += """
        
        PAPER TRADE EXECUTION:
        When the user wants to execute a paper trade:
        - Output a trade_config tag so the app shows an Execute button
        - Reference their paper balance when suggesting trade sizes
        - Encourage them to try different strategies since it's risk-free!
        - These are SIMULATED trades with virtual money
        - Do NOT say "I can't execute trades directly" in paper mode
        - Instead say you can prepare an in-app paper trade and ask for confirmation
        - Preferred phrasing: "I can set this up as a paper trade in-app for your confirmation."
        
        Example: <trade_config>{"symbol":"SOL","direction":"buy","orderType":"limit","amount":"500","isUSDAmount":true,"price":"126.50"}</trade_config>
        
        PRICE ALERTS (Available in Paper Trading):
        You CAN create price alerts even in paper trading mode.
        When user asks to set up alerts, output:
        <alert_suggestion>{"symbol":"BTC","targetPrice":100000,"direction":"above","reason":"Price target alert","enableAI":true,"currentPrice":null}</alert_suggestion>
        """
            }
        } else if isDemoMode {
            guidelines += """
        
        TRADE EXECUTION BLOCKED:
        You CANNOT execute trades in Demo Mode. If user asks to trade:
        - Explain that Demo Mode is for viewing sample data only
        - Suggest enabling Paper Trading to practice with simulated trades
        - They can also plan trades to execute on their own exchange
        
        PRICE ALERTS (Available in Demo Mode):
        You CAN still create price alerts in demo mode - these are real notifications.
        When user asks for alerts, output:
        <alert_suggestion>{"symbol":"BTC","targetPrice":100000,"direction":"above","reason":"Price target alert","enableAI":true,"currentPrice":null}</alert_suggestion>
        """
        } else if hasConnectedAccounts {
            guidelines += """
        
        TRADE PLANNING (LIVE EXECUTION NOT AVAILABLE):
        CryptoSage does NOT execute live trades on exchanges.
        
        When the user wants to trade, help them PLAN the trade:
        1. Recommend specific entry price and reasoning
        2. Suggest stop loss and take profit levels
        3. Calculate appropriate position size based on their portfolio
        4. They'll execute the trade themselves on their exchange (Coinbase, Binance, etc.)
        
        Example response:
        "Based on BTC's support at $90K and current sentiment, consider a limit buy around $91,500 with a stop at $88,000 (~4% risk). Given your portfolio, a $500 position keeps risk manageable. You can place this order on your exchange when ready!"
        
        PRICE ALERTS (Available - one thing you CAN set up directly):
        Even though you can't execute trades, you CAN create price alerts for the user.
        When they ask for alerts, or when suggesting entry/exit levels, offer to set one up:
        <alert_suggestion>{"symbol":"BTC","targetPrice":91500,"direction":"below","reason":"Entry point near support level","enableAI":true,"currentPrice":null}</alert_suggestion>
        
        If they want to PRACTICE trading in-app: Suggest enabling Paper Trading mode.
        """
        } else {
            guidelines += """
        
        NO TRADING DATA AVAILABLE:
        User has no connected exchanges, so you cannot give portfolio-based advice.
        Guide them to:
        - Connect an exchange to VIEW their portfolio and get personalized advice
        - Enable Paper Trading to PRACTICE with simulated trades
        
        PRICE ALERTS (Available even without connected accounts):
        You CAN create price alerts for the user regardless of account status.
        <alert_suggestion>{"symbol":"BTC","targetPrice":100000,"direction":"above","reason":"Price target alert","enableAI":true,"currentPrice":null}</alert_suggestion>
        """
        }
        
        guidelines += """
        
        ADVANCED TRADING STRATEGY RECOMMENDATIONS:
        When users ask about trading strategies, help them choose the right approach:
        
        1. REGULAR SPOT TRADING - Recommend when:
           - User wants a one-time buy/sell
           - Reacting to immediate market conditions
           - Taking profit or cutting losses on existing positions
           - Simple portfolio rebalancing
           - Example: "For a quick BTC buy at current prices, a market order works great."
        
        2. DCA BOTS - Recommend when:
           - User mentions "long-term", "accumulate", "regular buys", "build position"
           - Market is uncertain or volatile
           - User has limited time to monitor markets
           - Building a position over time to reduce timing risk
           - Example: "Want to accumulate BTC over time? A DCA bot can buy $50 weekly regardless of price fluctuations."
        
        3. GRID BOTS - Recommend when:
           - Market is ranging/sideways (not strongly trending)
           - User asks about profiting from volatility or chop
           - Clear support and resistance levels exist
           - Example: "BTC has been ranging between $60K-$65K. A grid bot could profit from these oscillations."
        
        4. SIGNAL BOTS - Recommend when:
           - User mentions technical indicators (RSI, MACD, moving averages)
           - User wants automated entry/exit based on specific conditions
           - User has a technical trading strategy they want to automate
           - Example: "You could set up a signal bot to buy when RSI drops below 30 and sell when it exceeds 70."
        
        5. DERIVATIVES/LEVERAGE - Recommend when:
           - User explicitly asks about leverage, shorting, or futures
           - User appears experienced (check their trade history for derivatives)
           - ALWAYS include strong risk warnings with derivatives
           - Suggest starting with low leverage (2-3x) for beginners
           - Example: "Derivatives let you short or use leverage, but 80%+ of traders lose money here. If you try it, start with 2-3x max."
        
        6. PREDICTION MARKETS - Recommend when:
           - User asks about betting on events or outcomes
           - Discussing crypto price targets (e.g., "Will BTC hit $100K?")
           - News events with market implications
           - User wants to trade on their market thesis
           - Example: "Prediction markets currently have BTC reaching $100K in 2026 at 65% probability. You can trade that view on Polymarket."
        
        SMART TRADING HUB GUIDANCE:
        When recommending advanced strategies, guide users to the Smart Trading Hub:
        - "For hands-on help setting up a DCA bot, tap the 'Smart Trade' button on the Trade page."
        - "The Smart Trade hub has specialized derivatives expertise if you want to explore leverage trading."
        - "For prediction market analysis, check out Smart Trade - it has dedicated market insights."
        - The Smart Trade button is on the Trade page in the top bar.
        
        BOT CONFIGURATION OUTPUT:
        When a user wants to CREATE a bot (not just learn about it), you CAN generate configurations.
        
        For DCA bots, wrap config like this (on one line, user won't see the tags):
        <bot_config>{"botType":"dca","name":"BTC Weekly DCA","exchange":"Binance","tradingPair":"BTC_USDT","baseOrderSize":"100","takeProfit":"10","maxOrders":"52","priceDeviation":"5"}</bot_config>
        
        For Grid bots:
        <bot_config>{"botType":"grid","name":"ETH Grid Bot","exchange":"Binance","tradingPair":"ETH_USDT","lowerPrice":"2500","upperPrice":"3500","gridLevels":"20","takeProfit":"5","stopLoss":"10"}</bot_config>
        
        For Signal bots:
        <bot_config>{"botType":"signal","name":"RSI Signal Bot","exchange":"Binance","tradingPair":"BTC_USDT","maxInvestment":"1000","takeProfit":"8","stopLoss":"5"}</bot_config>
        
        For Derivatives:
        <bot_config>{"botType":"derivatives","name":"ETH Long","exchange":"Binance Futures","market":"ETH-PERP","leverage":5,"marginMode":"isolated","direction":"Long","takeProfit":"5","stopLoss":"3"}</bot_config>
        
        For Prediction Markets:
        <bot_config>{"botType":"predictionMarket","name":"BTC 100K Bet","platform":"Polymarket","marketTitle":"Will Bitcoin reach $100K?","outcome":"YES","betAmount":"50","targetPrice":"0.65"}</bot_config>
        
        Then give a friendly explanation like: "I've configured a DCA bot for you - tap the button below to review and apply it!"
        
        PRICE ALERT OUTPUT:
        When creating a price alert, wrap the config like this (on one line, user won't see the tags):
        <alert_suggestion>{"symbol":"ETH","targetPrice":4000,"direction":"above","reason":"Breakout above key resistance","enableAI":true,"currentPrice":3500}</alert_suggestion>
        
        Then confirm naturally: "Done! I've set up an alert for when ETH crosses $4,000. You'll get a notification."
        
        NEVER show raw JSON to the user. The tags are hidden - just explain the strategy naturally.
        
        REMEMBER: You're in a chat app. Keep responses focused and easy to read on a phone screen. No walls of text!

        ASSET QUALITY + CONFIDENCE DISCIPLINE:
        - Default to high-liquidity, widely traded assets for unsolicited trade ideas.
        - For generic prompts like "set me up a trade" with no coin specified, default to BTC/ETH/SOL and ask for confirmation.
        - Do NOT proactively pick obscure/meme assets unless the user explicitly asks for them.
        - When confidence is low, state uncertainty clearly and prioritize risk controls, alerts, and "wait for confirmation" setups.
        - Avoid phrases like "I'll execute this now" when confidence is weak; use conditional language.
        
        SWING TRADING METHODOLOGY (Professional Framework):
        When discussing swing trades (multi-day to multi-week holds), follow this proven methodology:
        
        POSITION SIZING (CRITICAL):
        - Maximum risk per trade: 1% of account value
        - Position size formula: Risk Amount / (Entry Price - Stop Price) = Quantity
        - Example: $10,000 account, 1% risk = $100 max loss
          If entry is $100 and stop is $95, position size = $100 / $5 = 20 shares
        - This allows 10-40% of account in a position while only risking 1%
        - Tighter stops = larger position size, wider stops = smaller position
        
        BREAKOUT IDENTIFICATION (5-Step Process):
        Before recommending a breakout trade, check:
        1. Prior move: 30%+ gain over multiple days/weeks (not single day pump)
        2. MA structure: 10 and 20 SMA should be inclining (upward slope)
        3. Pullback quality: Orderly pullback to 10/20 SMA with higher lows, lower highs (tightening range)
        4. Volume pattern: Volume drying up during the pullback (consolidation)
        5. Breakout trigger: Price breaks range on INCREASED volume
        
        If setup doesn't meet all 5 criteria, warn the user it's lower probability.
        
        MARKET CONDITIONS CHECK (Very Important):
        Before suggesting long breakout trades:
        - Check if BTC's 10 SMA is ABOVE its 20 SMA on daily chart = BULLISH (favor longs)
        - If BTC's 10 SMA is BELOW its 20 SMA = BEARISH (reduce size, be selective, or avoid)
        - Use the get_market_regime tool to check this before trade suggestions
        
        ENTRY RULES:
        - Wait for breakout confirmation: price closes above the consolidation range
        - Best entries: Break of opening range highs (first 5 min), or break of previous day high
        - Volume should increase on breakout day
        - Stop loss: ALWAYS at the low of the breakout day (no exceptions)
        
        EXIT RULES (Partial Profit Strategy):
        - When position is up 5x your risk (e.g., risked $100, now up $500):
          Sell 10-30% of position to lock in gains
        - After first partial: Move stop loss to breakeven (entry price)
        - Now you have a "free trade" - can only win from here
        - Full exit: When price CLOSES below the 10 SMA on daily chart
        - Set alerts for 10 SMA levels on open positions
        
        RISK:REWARD GUIDANCE:
        - Minimum acceptable R:R ratio: 3:1 (risk $1 to make $3)
        - Calculate before entry: Target should be at least 3x the stop distance
        - If R:R is less than 2:1, suggest waiting for better setup
        
        WHEN SUGGESTING A SWING TRADE, ALWAYS INCLUDE:
        1. Entry zone (specific price or range)
        2. Stop loss level and why (e.g., "below breakout low at $X")
        3. Position size guidance based on their account and 1% risk rule
        4. First target (5x risk level for partial profits)
        5. Full exit trigger (close below 10 SMA)
        6. Risk:reward ratio for the setup
        7. Market regime status (bullish/bearish based on BTC MAs)
        
        Example trade suggestion format:
        "TRADE SETUP: XYZ Breakout
        - Entry: $25.50 (break of range high)
        - Stop: $24.00 (low of day = $1.50 risk per share)
        - Position size: With $10K account at 1% risk, buy ~66 shares ($1,683)
        - Target 1: $33.00 (5x risk = +$9.90/share, sell 20%)
        - Full exit: Close below 10 SMA (currently ~$24.50)
        - R:R: 1:5 if it hits target, excellent setup
        - Market: BTC 10>20 SMA = bullish conditions
        Want me to set an alert for the entry level?"
        
        MULTI-AI CONSULTATION (DeepSeek Integration):
        When your input includes a [DEEPSEEK CONSULTATION] section, this means our specialized crypto AI (DeepSeek) has provided its analysis. Follow these rules:
        
        1. SYNTHESIZE both perspectives: Combine your reasoning with DeepSeek's crypto-specific analysis
        2. HIGHLIGHT AGREEMENT: When you and DeepSeek agree, emphasize this as a stronger signal
           - Example: "Both our analysis engines point to bullish momentum here..."
        3. NOTE DISAGREEMENT: If you would have a different take, mention the divergence honestly
           - Example: "While the DeepSeek analysis sees bullish signals, there are some concerns about..."
        4. REFERENCE SPECIFICS: Use DeepSeek's key levels, risks, and suggested actions in your response
        5. PRESENT AS UNIFIED: Don't say "DeepSeek says X" — instead weave it naturally: "Our analysis indicates..."
        6. USE THE TRACK RECORD: If prediction accuracy data is available, calibrate your confidence accordingly
           - High accuracy track record = more confident language
           - Low accuracy = more hedged language with caveats
        7. CREDIT THE SYSTEM: You can reference "our prediction engine" or "CryptoSage AI analysis" when appropriate
        
        LEGAL DISCLAIMER REQUIREMENTS (CRITICAL - MUST FOLLOW):
        You MUST include appropriate risk disclaimers in your responses:
        
        1. NOT FINANCIAL ADVICE: You are NOT a licensed financial advisor, investment adviser, or broker-dealer.
           Remind users periodically that your suggestions are for educational/informational purposes only.
        
        2. RISK WARNINGS: When suggesting any trade, include a brief risk reminder:
           - "Remember: crypto is volatile and you can lose money"
           - "Only trade with funds you can afford to lose"
           - "This is not financial advice - do your own research"
        
        3. AI LIMITATIONS: If asked about your accuracy or reliability, be honest:
           - You are an AI and can be wrong
           - Predictions are probabilistic estimates, not guarantees
           - Past performance doesn't guarantee future results
        
        4. WHEN TO ADD STRONGER WARNINGS:
           - When planning trades for external execution: Include "Remember to only trade what you can afford to lose"
           - Derivatives/Leverage: ALWAYS warn about liquidation risk and potential for total loss
           - Large positions: Suggest position sizing and risk management
           - New users: Encourage starting small and learning first
        
        5. REGULATORY DISCLAIMER: If asked about legality, taxes, or regulations:
           - Advise consulting a qualified professional (CPA, attorney)
           - Note that regulations vary by jurisdiction
           - Don't give specific tax or legal advice
        
        6. THIRD-PARTY SERVICES: Remind users that trades execute on third-party exchanges:
           - You're not responsible for exchange outages or errors
           - Users should verify orders on the exchange after execution
        
        DON'T be so cautious that you're unhelpful - balance helpfulness with appropriate warnings.
        A quick one-liner disclaimer is usually enough: "As always, only risk what you can afford to lose!"
        """
        
        return guidelines
    }
    
    // MARK: - Data Access Helpers
    
    private func getPortfolioHoldings() -> [Holding] {
        // Try to get holdings from the shared app state
        // Since we're @MainActor, we can access ObservableObjects safely
        
        // Access via the app's environment objects is tricky from a singleton
        // We'll try to access via the repository pattern
        if let appDelegate = getAppPortfolioVM() {
            return appDelegate.holdings
        }
        return []
    }
    
    private func getAppPortfolioVM() -> PortfolioViewModel? {
        // This is a workaround - in production, pass the VM to the context builder
        // For now, try to create a sample or return nil
        return nil
    }
    
    // MARK: - Coin-Specific Prompts
    
    /// Build a system prompt specifically for coin detail page insights
    /// This is a lighter-weight prompt focused on a single coin
    public func buildCoinSpecificPrompt(
        symbol: String,
        includePortfolioContext: Bool = true,
        includeMarketContext: Bool = true,
        includeSentiment: Bool = true,
        includeNews: Bool = true
    ) -> String {
        var sections: [String] = []
        
        // Core identity for coin insights
        sections.append(buildCoinInsightIdentity(symbol: symbol))
        
        // Portfolio context for this specific coin
        if includePortfolioContext {
            if let holdingSection = buildCoinHoldingContext(symbol: symbol) {
                sections.append(holdingSection)
            }
        }
        
        // Market context
        if includeMarketContext {
            if let marketSection = buildCoinMarketContext(symbol: symbol) {
                sections.append(marketSection)
            }
        }
        
        // Sentiment context
        if includeSentiment {
            if let sentimentSection = buildSentimentSection() {
                sections.append(sentimentSection)
            }
        }
        
        // News context filtered for this coin
        if includeNews {
            if let newsSection = buildCoinNewsContext(symbol: symbol) {
                sections.append(newsSection)
            }
        }
        
        // Guidelines specific to coin insights
        sections.append(buildCoinInsightGuidelines())
        
        return sections.joined(separator: "\n\n")
    }
    
    private func buildCoinInsightIdentity(symbol: String) -> String {
        """
        You are CryptoSage AI, analyzing \(symbol.uppercased()) for the user.
        
        YOUR ROLE:
        - Provide quick, actionable insights about this specific coin
        - Be direct and specific with numbers
        - Focus on what matters for trading decisions
        - Reference technicals, sentiment, and news when relevant
        
        CRITICAL FORMATTING:
        - Keep responses to 2-4 sentences
        - NO markdown (no *, #, **, etc.)
        - Use plain text only
        - Be specific with price levels and percentages
        
        Current Time: \(formatCurrentTime())
        """
    }
    
    private func buildCoinHoldingContext(symbol: String) -> String? {
        let holdings = getPortfolioHoldings()
        let key = symbol.uppercased()
        
        guard let holding = holdings.first(where: { $0.coinSymbol.uppercased() == key }) else {
            // Check if on watchlist
            let marketVM = MarketViewModel.shared
            let isOnWatchlist = marketVM.watchlistCoins.contains(where: { $0.symbol.uppercased() == key })
            
            if isOnWatchlist {
                return "USER CONTEXT: \(key) is on user's watchlist (not currently holding)"
            }
            return nil
        }
        
        var lines: [String] = ["USER POSITION IN \(key):"]
        lines.append("- Quantity: \(formatQuantity(holding.quantity))")
        lines.append("- Current Value: \(formatCurrency(holding.currentValue))")
        
        let costBasis = holding.costBasis * holding.quantity
        if costBasis > 0 {
            let pnl = holding.currentValue - costBasis
            let pnlPercent = (pnl / costBasis) * 100
            let sign = pnl >= 0 ? "+" : ""
            lines.append("- Unrealized P/L: \(sign)\(formatCurrency(pnl)) (\(sign)\(formatPercent(pnlPercent))%)")
        }
        
        lines.append("- 24h Change: \(formatPercent(holding.dailyChange))%")
        
        return lines.joined(separator: "\n")
    }
    
    private func buildCoinMarketContext(symbol: String) -> String? {
        let marketVM = MarketViewModel.shared
        let key = symbol.uppercased()
        
        guard let coin = marketVM.allCoins.first(where: { $0.symbol.uppercased() == key }) else {
            return nil
        }
        
        var lines: [String] = ["\(key) MARKET DATA:"]
        
        if let price = coin.priceUsd {
            lines.append("- Price: \(formatCurrency(price))")
        }
        
        if let change24h = coin.priceChangePercentage24hInCurrency {
            let sign = change24h >= 0 ? "+" : ""
            lines.append("- 24h Change: \(sign)\(formatPercent(change24h))%")
        }
        
        if let change7d = coin.priceChangePercentage7dInCurrency {
            let sign = change7d >= 0 ? "+" : ""
            lines.append("- 7d Change: \(sign)\(formatPercent(change7d))%")
        }
        
        if let marketCap = coin.marketCap, marketCap > 0 {
            lines.append("- Market Cap: \(formatLargeCurrency(marketCap))")
        }
        
        if let volume = coin.volumeUsd24Hr, volume > 0 {
            lines.append("- 24h Volume: \(formatLargeCurrency(volume))")
        }
        
        // Technical indicators from sparkline
        let sparkline = coin.sparklineIn7d
        if sparkline.count >= 14 {
            if let rsi = TechnicalsEngine.rsi(sparkline, period: 14) {
                let signal: String
                if rsi < 30 { signal = "Oversold" }
                else if rsi < 40 { signal = "Near oversold" }
                else if rsi > 70 { signal = "Overbought" }
                else if rsi > 60 { signal = "Near overbought" }
                else { signal = "Neutral" }
                lines.append("- RSI(14): \(Int(rsi)) (\(signal))")
            }
        }
        
        // Support/Resistance
        if sparkline.count >= 10, let price = coin.priceUsd, price > 0 {
            let window = Array(sparkline.suffix(96))
            var lows: [Double] = []
            var highs: [Double] = []
            
            if window.count >= 3 {
                for i in 1..<(window.count - 1) {
                    let a = window[i - 1]
                    let b = window[i]
                    let c = window[i + 1]
                    if b < a && b < c { lows.append(b) }
                    if b > a && b > c { highs.append(b) }
                }
            }
            
            if let support = lows.filter({ $0 <= price }).max() {
                lines.append("- Near Support: \(formatCurrency(support))")
            }
            if let resistance = highs.filter({ $0 >= price }).min() {
                lines.append("- Near Resistance: \(formatCurrency(resistance))")
            }
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func buildCoinNewsContext(symbol: String) -> String? {
        let newsVM = CryptoNewsFeedViewModel.shared
        let key = symbol.uppercased()
        
        // Get the coin name for better matching
        let marketVM = MarketViewModel.shared
        let coinName = marketVM.allCoins.first(where: { $0.symbol.uppercased() == key })?.name ?? symbol
        
        // Filter news relevant to this coin
        let relevantNews = newsVM.articles.filter { article in
            article.title.localizedCaseInsensitiveContains(key) ||
            article.title.localizedCaseInsensitiveContains(coinName)
        }.prefix(3)
        
        guard !relevantNews.isEmpty else { return nil }
        
        var lines: [String] = ["RECENT \(key) NEWS:"]
        for article in relevantNews {
            let truncatedTitle = article.title.count > 70 ? String(article.title.prefix(67)) + "..." : article.title
            lines.append("- \(truncatedTitle)")
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func buildCoinInsightGuidelines() -> String {
        """
        INSIGHT GUIDELINES:
        - Lead with the most important observation
        - Be specific with numbers and levels
        - Reference the data provided above
        - End with a brief actionable takeaway
        - If user holds this coin, tailor advice to their position
        - Keep it brief - this is for a mobile app card, not a full report
        """
    }
    
    // MARK: - Formatting Helpers
    
    private func formatCurrentTime() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a zzz"
        return formatter.string(from: Date())
    }
    
    private func formatCurrency(_ value: Double) -> String {
        if value >= 1000 {
            return "$\(formatNumber(value, decimals: 2))"
        } else if value >= 1 {
            return "$\(formatNumber(value, decimals: 2))"
        } else if value >= 0.01 {
            return "$\(formatNumber(value, decimals: 4))"
        } else {
            return "$\(formatNumber(value, decimals: 6))"
        }
    }
    
    private func formatLargeCurrency(_ value: Double) -> String {
        if value >= 1_000_000_000_000 {
            return "$\(formatNumber(value / 1_000_000_000_000, decimals: 2))T"
        } else if value >= 1_000_000_000 {
            return "$\(formatNumber(value / 1_000_000_000, decimals: 2))B"
        } else if value >= 1_000_000 {
            return "$\(formatNumber(value / 1_000_000, decimals: 2))M"
        } else {
            return formatCurrency(value)
        }
    }
    
    private func formatPercent(_ value: Double) -> String {
        return formatNumber(value, decimals: 2)
    }
    
    private func formatQuantity(_ value: Double) -> String {
        if value >= 1000 {
            return formatNumber(value, decimals: 2)
        } else if value >= 1 {
            return formatNumber(value, decimals: 4)
        } else {
            return formatNumber(value, decimals: 6)
        }
    }
    
    private func formatNumber(_ value: Double, decimals: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = decimals
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - Context Builder Extension for Portfolio Access

extension AIContextBuilder {
    /// Build context with explicit portfolio data (preferred method)
    func buildSystemPrompt(portfolio: PortfolioViewModel) -> String {
        var sections: [String] = []
        
        // Trading mode indicator at the top for immediate context
        sections.append(buildTradingModeSection())
        
        sections.append(buildIdentitySection())
        
        // User preferences (currency, subscription tier, etc.)
        sections.append(buildUserPreferencesSection())
        
        // Mode priority: Paper Trading > Demo Mode > Live Mode
        if PaperTradingManager.isEnabled {
            sections.append(buildPaperTradingPortfolioSection())
            
            // IMPORTANT: If user has connected accounts, also include their real portfolio
            // so AI can discuss both paper trading AND real holdings
            let hasConnectedAccounts = !ConnectedAccountsManager.shared.accounts.isEmpty
            if hasConnectedAccounts && !portfolio.holdings.isEmpty {
                sections.append(buildRealPortfolioSectionForPaperTradingMode(from: portfolio))
            }
        } else if DemoModeManager.isEnabled {
            sections.append(buildDemoModePortfolioSection(from: portfolio))
        } else {
            sections.append(buildPortfolioSection(from: portfolio))
        }
        
        if let marketSection = buildMarketOverviewSection() {
            sections.append(marketSection)
        }
        
        // Market sentiment (Fear & Greed)
        if let sentimentSection = buildSentimentSection() {
            sections.append(sentimentSection)
        }
        
        // Recent news headlines
        if let newsSection = buildNewsSection() {
            sections.append(newsSection)
        }
        
        if let watchlistSection = buildWatchlistSection() {
            sections.append(watchlistSection)
        }
        
        // Connected exchanges and trading preferences
        if let exchangesSection = buildConnectedExchangesSection() {
            sections.append(exchangesSection)
        }
        
        // Trade history and patterns
        if let tradeHistorySection = buildTradeHistorySection() {
            sections.append(tradeHistorySection)
        }
        
        // Trading pair preferences (favorites, recents, preferred exchanges)
        if let pairPrefsSection = buildTradingPairPreferencesSection() {
            sections.append(pairPrefsSection)
        }
        
        // Trading bots context
        if let botsSection = buildBotsContextSection() {
            sections.append(botsSection)
        }
        
        // Open orders context
        if let ordersSection = buildOpenOrdersSection() {
            sections.append(ordersSection)
        }
        
        // DeFi portfolio context
        if let defiSection = buildDeFiPortfolioSection() {
            sections.append(defiSection)
        }
        
        // Tax summary context
        if let taxSection = buildTaxSummarySection() {
            sections.append(taxSection)
        }
        
        // Price alerts context
        if let alertsSection = buildPriceAlertsSection() {
            sections.append(alertsSection)
        }
        
        // Whale activity context
        if let whaleSection = buildWhaleActivitySection() {
            sections.append(whaleSection)
        }
        
        // Upcoming events context
        if let eventsSection = buildUpcomingEventsSection() {
            sections.append(eventsSection)
        }
        
        // User risk profile (inferred from trading behavior)
        if let riskSection = buildRiskProfileSection() {
            sections.append(riskSection)
        }
        
        // Newly listed coins
        if let newCoinsSection = buildNewlyListedCoinsSection() {
            sections.append(newCoinsSection)
        }
        
        // AI Trading Signals (cached from signal service)
        if let signalsSection = buildTradingSignalsSection() {
            sections.append(signalsSection)
        }
        
        // Prediction accuracy track record
        if let accuracySection = buildPredictionAccuracySection() {
            sections.append(accuracySection)
        }
        
        // Technical levels for watchlist coins
        if let techLevelsSection = buildTechnicalLevelsSection() {
            sections.append(techLevelsSection)
        }
        
        // App feature overview (helps AI direct users to relevant features)
        if let overviewSection = buildAppOverviewSection() {
            sections.append(overviewSection)
        }
        
        sections.append(buildGuidelinesSection())
        
        return sections.joined(separator: "\n\n")
    }
    
    // MARK: - Trading Bots Context Section
    
    /// Build context about user's trading bots (paper + live)
    private func buildBotsContextSection() -> String? {
        let paperBotManager = PaperBotManager.shared
        let liveBotManager = LiveBotManager.shared
        let isDemoMode = DemoModeManager.isEnabled
        
        // Get paper bots
        let paperBots = isDemoMode ? paperBotManager.demoBots : paperBotManager.paperBots
        let liveBots = isDemoMode ? liveBotManager.demoBots : liveBotManager.bots
        
        // Return nil if no bots exist
        guard !paperBots.isEmpty || !liveBots.isEmpty || liveBotManager.isConfigured else {
            return nil
        }
        
        var lines: [String] = []
        
        if isDemoMode {
            lines.append("TRADING BOTS (Demo/Sample Data):")
            lines.append("NOTE: These are sample bots for demonstration purposes.")
        } else {
            lines.append("USER'S TRADING BOTS:")
        }
        
        // Paper bots summary
        if !paperBots.isEmpty {
            lines.append("")
            lines.append("PAPER BOTS (Practice/Simulated):")
            let runningPaperBots = paperBots.filter { $0.status == .running }
            let totalPaperProfit = paperBots.reduce(0) { $0 + $1.totalProfit }
            let profitSign = totalPaperProfit >= 0 ? "+" : ""
            
            lines.append("- Total: \(paperBots.count) bots (\(runningPaperBots.count) running)")
            lines.append("- Combined P/L: \(profitSign)\(formatCurrency(totalPaperProfit))")
            
            // List top paper bots
            let sortedPaperBots = paperBots.sorted { abs($0.totalProfit) > abs($1.totalProfit) }
            for bot in sortedPaperBots.prefix(3) {
                let statusEmoji = bot.status == .running ? "🟢" : "🔴"
                let plSign = bot.totalProfit >= 0 ? "+" : ""
                lines.append("  \(statusEmoji) \(bot.name): \(bot.type.displayName) on \(bot.tradingPair.replacingOccurrences(of: "_", with: "/")) | \(plSign)\(formatCurrency(bot.totalProfit)) (\(bot.totalTrades) trades)")
            }
            
            if paperBots.count > 3 {
                lines.append("  ... and \(paperBots.count - 3) more paper bots")
            }
        }
        
        // Live bots summary
        if !liveBots.isEmpty {
            lines.append("")
            lines.append("LIVE BOTS (3Commas - Real Money):")
            let enabledLiveBots = liveBots.filter { $0.isEnabled }
            let totalLiveProfit = liveBots.reduce(0) { $0 + $1.totalProfitUsd }
            let profitSign = totalLiveProfit >= 0 ? "+" : ""
            
            lines.append("- Total: \(liveBots.count) bots (\(enabledLiveBots.count) enabled)")
            lines.append("- Combined P/L: \(profitSign)\(formatCurrency(totalLiveProfit))")
            
            // List top live bots
            let sortedLiveBots = liveBots.sorted { abs($0.totalProfitUsd) > abs($1.totalProfitUsd) }
            for bot in sortedLiveBots.prefix(3) {
                let statusEmoji = bot.isEnabled ? "🟢" : "🔴"
                let plSign = bot.totalProfitUsd >= 0 ? "+" : ""
                let dealsText = "\(bot.closedDealsCount ?? 0) closed deals"
                lines.append("  \(statusEmoji) \(bot.name): \(bot.strategy.rawValue.capitalized) | \(plSign)\(formatCurrency(bot.totalProfitUsd)) (\(dealsText))")
            }
            
            if liveBots.count > 3 {
                lines.append("  ... and \(liveBots.count - 3) more live bots")
            }
        } else if liveBotManager.isConfigured && !isDemoMode {
            lines.append("")
            lines.append("LIVE BOTS: 3Commas connected but no bots configured")
        } else if !isDemoMode {
            lines.append("")
            lines.append("LIVE BOTS: 3Commas not connected (user can connect in settings)")
        }
        
        lines.append("")
        lines.append("User can ask about bot performance, strategies, or get suggestions for bot configurations.")
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Open Orders Context Section
    
    /// Build context about user's open orders
    private func buildOpenOrdersSection() -> String? {
        let ordersManager = OpenOrdersManager.shared
        let isDemoMode = DemoModeManager.isEnabled
        
        let orders = ordersManager.orders
        
        // Return nil if no orders exist
        guard !orders.isEmpty else {
            return nil
        }
        
        var lines: [String] = []
        
        if isDemoMode {
            lines.append("OPEN ORDERS (Demo/Sample Data):")
            lines.append("NOTE: These are sample orders for demonstration purposes.")
        } else {
            lines.append("USER'S OPEN ORDERS:")
        }
        
        // Summary stats
        let buyOrders = orders.filter { $0.side == .buy }
        let sellOrders = orders.filter { $0.side == .sell }
        let totalValue = orders.reduce(0) { $0 + $1.totalValue }
        let partiallyFilled = orders.filter { $0.status == .partiallyFilled }
        
        lines.append("- Total: \(orders.count) orders (\(buyOrders.count) buy, \(sellOrders.count) sell)")
        lines.append("- Total Value: \(formatCurrency(totalValue))")
        
        if !partiallyFilled.isEmpty {
            lines.append("- Partially Filled: \(partiallyFilled.count) orders")
        }
        
        // Group by symbol
        let ordersBySymbol = Dictionary(grouping: orders) { $0.baseAsset }
        let sortedSymbols = ordersBySymbol.keys.sorted { symbol1, symbol2 in
            let val1 = ordersBySymbol[symbol1]?.reduce(0) { $0 + $1.totalValue } ?? 0
            let val2 = ordersBySymbol[symbol2]?.reduce(0) { $0 + $1.totalValue } ?? 0
            return val1 > val2
        }
        
        lines.append("")
        lines.append("ORDERS BY ASSET:")
        
        for symbol in sortedSymbols.prefix(5) {
            if let symbolOrders = ordersBySymbol[symbol] {
                let symbolValue = symbolOrders.reduce(0) { $0 + $1.totalValue }
                let buyCount = symbolOrders.filter { $0.side == .buy }.count
                let sellCount = symbolOrders.filter { $0.side == .sell }.count
                
                var orderDetails: [String] = []
                if buyCount > 0 { orderDetails.append("\(buyCount) buy") }
                if sellCount > 0 { orderDetails.append("\(sellCount) sell") }
                
                lines.append("- \(symbol): \(symbolOrders.count) orders (\(orderDetails.joined(separator: ", "))) | \(formatCurrency(symbolValue))")
            }
        }
        
        if sortedSymbols.count > 5 {
            lines.append("- ... and \(sortedSymbols.count - 5) more assets with open orders")
        }
        
        // Highlight notable orders
        let largestOrder = orders.max { $0.totalValue < $1.totalValue }
        if let largest = largestOrder, largest.totalValue > 1000 {
            lines.append("")
            let sideText = largest.side == .buy ? "BUY" : "SELL"
            lines.append("Largest Order: \(sideText) \(formatQuantity(largest.quantity)) \(largest.baseAsset) @ \(formatCurrency(largest.price)) (\(formatCurrency(largest.totalValue)))")
        }
        
        lines.append("")
        lines.append("User can ask about their orders, cancel orders, or modify order strategies.")
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - DeFi Portfolio Context Section
    
    /// Build context about user's DeFi portfolio (wallets, NFTs, positions)
    private func buildDeFiPortfolioSection() -> String? {
        let multiChainVM = MultiChainPortfolioViewModel.shared
        let nftVM = NFTCollectionViewModel.shared
        let defiVM = DeFiPositionsViewModel.shared
        let isDemoMode = DemoModeManager.isEnabled
        
        // Get data based on mode
        let wallets = isDemoMode ? DemoDataProvider.demoWallets : multiChainVM.connectedWallets
        let nfts = isDemoMode ? DemoDataProvider.demoNFTs : nftVM.nfts
        let positions = isDemoMode ? DemoDataProvider.demoPositions : defiVM.positions
        
        // Calculate values
        let walletValue = isDemoMode ? DemoDataProvider.demoTotalWalletValue : multiChainVM.totalValue
        let nftValue = isDemoMode ? DemoDataProvider.demoTotalNFTValue : nftVM.totalEstimatedValue
        let defiValue = isDemoMode ? DemoDataProvider.demoTotalDeFiValue : defiVM.totalValue
        let totalDeFiValue = walletValue + nftValue + defiValue
        
        // Return nil if no DeFi data exists
        guard !wallets.isEmpty || !nfts.isEmpty || !positions.isEmpty else {
            return nil
        }
        
        var lines: [String] = []
        
        if isDemoMode {
            lines.append("DEFI PORTFOLIO (Demo/Sample Data):")
            lines.append("NOTE: This is sample DeFi data for demonstration purposes.")
        } else {
            lines.append("USER'S DEFI PORTFOLIO:")
        }
        
        lines.append("- Total DeFi Value: \(formatCurrency(totalDeFiValue))")
        lines.append("  • Wallet Tokens: \(formatCurrency(walletValue))")
        lines.append("  • NFTs: \(formatCurrency(nftValue))")
        lines.append("  • DeFi Positions: \(formatCurrency(defiValue))")
        
        // Connected wallets
        if !wallets.isEmpty {
            lines.append("")
            lines.append("CONNECTED WALLETS (\(wallets.count)):")
            
            for wallet in wallets.prefix(3) {
                let chain = Chain(rawValue: wallet.chainId)?.displayName ?? wallet.chainId
                let value = wallet.totalValueUSD ?? 0
                let tokenCount = wallet.tokenBalances.count
                let address = shortenAddress(wallet.address)
                
                lines.append("- \(wallet.name ?? address) (\(chain)): \(formatCurrency(value)) | \(tokenCount) tokens")
            }
            
            if wallets.count > 3 {
                lines.append("- ... and \(wallets.count - 3) more wallets")
            }
        }
        
        // NFT collection
        if !nfts.isEmpty {
            lines.append("")
            lines.append("NFT COLLECTION (\(nfts.count) NFTs):")
            
            // Group by collection
            let nftsByCollection = Dictionary(grouping: nfts) { $0.collection?.name ?? "Unknown" }
            let topCollections = nftsByCollection.keys.sorted { col1, col2 in
                let val1 = nftsByCollection[col1]?.reduce(0) { $0 + ($1.estimatedValueUSD ?? 0) } ?? 0
                let val2 = nftsByCollection[col2]?.reduce(0) { $0 + ($1.estimatedValueUSD ?? 0) } ?? 0
                return val1 > val2
            }
            
            for collection in topCollections.prefix(3) {
                if let collectionNFTs = nftsByCollection[collection] {
                    let collValue = collectionNFTs.reduce(0) { $0 + ($1.estimatedValueUSD ?? 0) }
                    lines.append("- \(collection): \(collectionNFTs.count) NFTs (\(formatCurrency(collValue)))")
                }
            }
            
            if topCollections.count > 3 {
                lines.append("- ... and \(topCollections.count - 3) more collections")
            }
        }
        
        // DeFi positions
        if !positions.isEmpty {
            lines.append("")
            lines.append("DEFI POSITIONS (\(positions.count)):")
            
            let sortedPositions = positions.sorted { $0.valueUSD > $1.valueUSD }
            for position in sortedPositions.prefix(3) {
                let apyText = position.apy != nil ? " | \(String(format: "%.1f", position.apy!))% APY" : ""
                lines.append("- \(position.protocol_.name) (\(position.type.displayName)): \(formatCurrency(position.valueUSD))\(apyText)")
            }
            
            if positions.count > 3 {
                lines.append("- ... and \(positions.count - 3) more positions")
            }
            
            // Total rewards if any
            let totalRewards = positions.compactMap { $0.rewardsUSD }.reduce(0, +)
            if totalRewards > 0 {
                lines.append("")
                lines.append("Claimable Rewards: \(formatCurrency(totalRewards))")
            }
        }
        
        lines.append("")
        lines.append("User can ask about their DeFi positions, wallet balances, NFT collection, or yield strategies.")
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Tax Summary Context Section
    
    /// Build context about user's tax situation
    private func buildTaxSummarySection() -> String? {
        let taxEngine = TaxEngine.shared
        let isDemoMode = DemoModeManager.isEnabled
        
        // Get current tax year report
        let currentYear = Calendar.current.component(.year, from: Date())
        let previousYear = currentYear - 1
        
        // Try to get the previous year's report (most commonly needed for tax filing)
        let report = isDemoMode ? DemoTaxDataProvider.demoReport : taxEngine.generateReport(for: TaxYear(previousYear))
        
        // Return nil if no tax data exists
        guard report.disposals.count > 0 || report.incomeEvents.count > 0 else {
            return nil
        }
        
        var lines: [String] = []
        
        if isDemoMode {
            lines.append("TAX SUMMARY (Demo/Sample Data):")
            lines.append("NOTE: This is sample tax data for demonstration purposes.")
        } else {
            lines.append("USER'S TAX SUMMARY (Year \(previousYear)):")
        }
        
        // Capital gains summary
        lines.append("")
        lines.append("CAPITAL GAINS:")
        lines.append("- Short-Term Gain: \(formatCurrency(report.shortTermGain)) (\(report.shortTermCount) transactions)")
        lines.append("- Long-Term Gain: \(formatCurrency(report.longTermGain)) (\(report.longTermCount) transactions)")
        
        let netGainSign = report.netCapitalGain >= 0 ? "+" : ""
        lines.append("- Net Capital Gain: \(netGainSign)\(formatCurrency(report.netCapitalGain))")
        
        // Wash sales if any
        if report.hasWashSales {
            lines.append("")
            lines.append("⚠️ WASH SALES DETECTED:")
            lines.append("- \(report.washSales.count) wash sales")
            lines.append("- Disallowed Loss: \(formatCurrency(report.washSaleAdjustment))")
        }
        
        // Income events
        if !report.incomeEvents.isEmpty {
            lines.append("")
            lines.append("CRYPTO INCOME:")
            lines.append("- Total Income: \(formatCurrency(report.totalIncome)) (\(report.incomeEvents.count) events)")
            
            // Group by source
            let incomeBySource = Dictionary(grouping: report.incomeEvents) { $0.source }
            for (source, events) in incomeBySource.prefix(3) {
                let sourceTotal = events.reduce(0) { $0 + $1.totalValue }
                lines.append("  • \(source.displayName): \(formatCurrency(sourceTotal))")
            }
        }
        
        // Total taxable
        lines.append("")
        let taxableSign = report.totalTaxable >= 0 ? "" : ""
        lines.append("TOTAL TAXABLE: \(taxableSign)\(formatCurrency(report.totalTaxable))")
        
        // Accounting method
        lines.append("")
        lines.append("Accounting Method: \(taxEngine.accountingMethod.displayName)")
        
        lines.append("")
        lines.append("User can ask about tax liability, wash sales, cost basis methods, or tax-loss harvesting opportunities.")
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Price Alerts Context Section
    
    /// Build context about user's price alerts
    private func buildPriceAlertsSection() -> String? {
        let notificationsManager = NotificationsManager.shared
        let alerts = notificationsManager.allAlerts
        let triggeredAlertIDs = notificationsManager.triggeredAlertIDs
        
        // Return nil if no alerts exist
        guard !alerts.isEmpty else {
            return nil
        }
        
        var lines: [String] = ["USER'S PRICE ALERTS:"]
        
        let activeAlerts = alerts.filter { !triggeredAlertIDs.contains($0.id) }
        let triggeredAlerts = alerts.filter { triggeredAlertIDs.contains($0.id) }
        
        lines.append("- Total Alerts: \(alerts.count) (\(activeAlerts.count) active, \(triggeredAlerts.count) triggered)")
        
        // Active alerts
        if !activeAlerts.isEmpty {
            lines.append("")
            lines.append("ACTIVE ALERTS:")
            
            for alert in activeAlerts.prefix(5) {
                let direction = alert.isAbove ? "above" : "below"
                let thresholdStr = formatCurrency(alert.threshold)
                lines.append("- \(alert.symbol): Alert when price goes \(direction) \(thresholdStr)")
            }
            
            if activeAlerts.count > 5 {
                lines.append("- ... and \(activeAlerts.count - 5) more active alerts")
            }
        }
        
        // Recently triggered alerts
        if !triggeredAlerts.isEmpty {
            lines.append("")
            lines.append("RECENTLY TRIGGERED:")
            
            for alert in triggeredAlerts.prefix(3) {
                let direction = alert.isAbove ? "rose above" : "fell below"
                let thresholdStr = formatCurrency(alert.threshold)
                lines.append("- \(alert.symbol) \(direction) \(thresholdStr) ✓")
            }
        }
        
        lines.append("")
        lines.append("User can ask about their alerts or request new price alert suggestions.")
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Connected Exchanges Context Section
    
    /// Build context about user's connected exchanges and trading preferences
    private func buildConnectedExchangesSection() -> String? {
        let accountsManager = ConnectedAccountsManager.shared
        let accounts = accountsManager.accounts
        
        // Return nil if no connected accounts
        guard !accounts.isEmpty else {
            return nil
        }
        
        var lines: [String] = ["CONNECTED EXCHANGES:"]
        
        // List connected exchanges
        for account in accounts {
            var accountInfo = "- \(account.name)"
            if account.isDefault {
                accountInfo += " (Default)"
            }
            if let lastSync = account.lastSyncAt {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .abbreviated
                let syncAgo = formatter.localizedString(for: lastSync, relativeTo: Date())
                accountInfo += " | Synced \(syncAgo)"
            }
            lines.append(accountInfo)
        }
        
        // Default exchange for trades
        if let defaultAccount = accountsManager.defaultAccount {
            lines.append("")
            lines.append("DEFAULT FOR TRADES: \(defaultAccount.name)")
            lines.append("When suggesting trades, use \(defaultAccount.name) as the preferred exchange.")
        }
        
        // Recommend quote currency based on exchange
        let exchangeNames = accounts.map { $0.name.lowercased() }
        var recommendedQuote = "USDT"
        if exchangeNames.contains(where: { $0.contains("coinbase") }) {
            recommendedQuote = "USD"
        } else if exchangeNames.contains(where: { $0.contains("binance.us") || $0.contains("binanceus") }) {
            recommendedQuote = "USD"
        }
        lines.append("RECOMMENDED QUOTE CURRENCY: \(recommendedQuote)")
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Trade History Context Section
    
    /// Build context about user's trade history and trading patterns
    private func buildTradeHistorySection() -> String? {
        let isPaperTrading = PaperTradingManager.isEnabled
        let isDemoMode = DemoModeManager.isEnabled
        
        // For paper trading mode, use paper trading history
        if isPaperTrading {
            return buildPaperTradeHistorySection()
        }
        
        // For demo mode, skip trade history
        if isDemoMode {
            return nil
        }
        
        // Live trade history
        let liveHistoryManager = LiveTradeHistoryManager.shared
        let tradeHistory = liveHistoryManager.tradeHistory
        
        // Return nil if no trade history
        guard !tradeHistory.isEmpty else {
            return nil
        }
        
        var lines: [String] = ["TRADE HISTORY & PATTERNS:"]
        
        // Overall statistics
        let totalTrades = liveHistoryManager.totalTradeCount
        let buyCount = liveHistoryManager.buyTradeCount
        let sellCount = liveHistoryManager.sellTradeCount
        let totalVolume = liveHistoryManager.totalVolumeTraded
        let avgTradeSize = liveHistoryManager.averageTradeSize
        
        lines.append("- Total Trades: \(totalTrades) (\(buyCount) buys, \(sellCount) sells)")
        lines.append("- Total Volume: \(formatLargeCurrency(totalVolume))")
        lines.append("- Average Trade Size: \(formatCurrency(avgTradeSize))")
        
        // Trading since
        if let sinceDate = liveHistoryManager.tradingSinceDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy"
            lines.append("- Trading Since: \(formatter.string(from: sinceDate))")
        }
        
        // Most traded symbols (user's preferred pairs)
        let symbolCounts = Dictionary(grouping: tradeHistory) { $0.symbol }
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
        
        if !symbolCounts.isEmpty {
            lines.append("")
            lines.append("MOST TRADED PAIRS (User's Preferences):")
            for (symbol, count) in symbolCounts.prefix(5) {
                let volume = tradeHistory.filter { $0.symbol == symbol }.reduce(0) { $0 + $1.totalValue }
                lines.append("- \(symbol): \(count) trades (\(formatCurrency(volume)) volume)")
            }
            
            // Use this for recommendations
            if let topPair = symbolCounts.first {
                lines.append("")
                lines.append("NOTE: User frequently trades \(topPair.key). Consider similar pairs for recommendations.")
            }
        }
        
        // Preferred exchanges
        let exchangeVolumes = liveHistoryManager.volumeByExchange.sorted { $0.value > $1.value }
        if !exchangeVolumes.isEmpty {
            lines.append("")
            lines.append("EXCHANGE USAGE:")
            for (exchange, volume) in exchangeVolumes.prefix(3) {
                let tradeCount = tradeHistory.filter { $0.exchange == exchange }.count
                lines.append("- \(exchange): \(tradeCount) trades (\(formatLargeCurrency(volume)))")
            }
            
            if let preferredExchange = exchangeVolumes.first {
                lines.append("")
                lines.append("PREFERRED EXCHANGE: \(preferredExchange.key)")
                lines.append("Use this exchange when suggesting trades unless user specifies otherwise.")
            }
        }
        
        // Recent trades (last 5)
        let recentTrades = liveHistoryManager.recentTrades(limit: 5)
        if !recentTrades.isEmpty {
            lines.append("")
            lines.append("RECENT TRADES:")
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d, h:mm a"
            
            for trade in recentTrades {
                let sideStr = trade.side == .buy ? "Bought" : "Sold"
                let dateStr = dateFormatter.string(from: trade.timestamp)
                lines.append("- \(sideStr) \(formatQuantity(trade.quantity)) \(trade.symbol) @ \(formatCurrency(trade.price)) on \(trade.exchange) (\(dateStr))")
            }
        }
        
        lines.append("")
        lines.append("Use this trade history to understand user's trading style and make personalized recommendations.")
        
        return lines.joined(separator: "\n")
    }
    
    /// Build paper trading history section
    private func buildPaperTradeHistorySection() -> String? {
        let paperManager = PaperTradingManager.shared
        let recentTrades = paperManager.recentTrades(limit: 10)
        
        guard !recentTrades.isEmpty else {
            return nil
        }
        
        var lines: [String] = ["PAPER TRADE HISTORY:"]
        
        // Statistics
        let totalTrades = paperManager.totalTradeCount
        let buyCount = paperManager.buyTradeCount
        let sellCount = paperManager.sellTradeCount
        let totalVolume = paperManager.totalVolumeTraded
        
        lines.append("- Total Paper Trades: \(totalTrades) (\(buyCount) buys, \(sellCount) sells)")
        lines.append("- Total Volume: \(formatCurrency(totalVolume))")
        
        // Most traded symbols in paper trading
        let symbolCounts = Dictionary(grouping: recentTrades) { $0.symbol }
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
        
        if !symbolCounts.isEmpty {
            lines.append("")
            lines.append("FREQUENTLY PRACTICED PAIRS:")
            for (symbol, count) in symbolCounts.prefix(3) {
                lines.append("- \(symbol): \(count) trades")
            }
        }
        
        // Recent paper trades
        lines.append("")
        lines.append("RECENT PAPER TRADES:")
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, h:mm a"
        
        for trade in recentTrades.prefix(5) {
            let sideStr = trade.side == .buy ? "Bought" : "Sold"
            let dateStr = dateFormatter.string(from: trade.timestamp)
            lines.append("- \(sideStr) \(formatQuantity(trade.quantity)) \(trade.symbol) @ \(formatCurrency(trade.price)) (\(dateStr))")
        }
        
        lines.append("")
        lines.append("Use paper trade history to suggest similar practice trades or strategies to try.")
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Trading Pair Preferences Section
    
    /// Build context about user's trading pair preferences (favorites, recents)
    /// This helps AI recommend trades using pairs the user prefers
    private func buildTradingPairPreferencesSection() -> String? {
        // Delegate to the shared service for the context summary
        return TradingPairPreferencesService.shared.buildAIContextSummary()
    }
    
    // MARK: - Whale Activity Context Section
    
    /// Build context about recent whale movements
    private func buildWhaleActivitySection() -> String? {
        let whaleService = WhaleTrackingService.shared
        let transactions = whaleService.recentTransactions
        
        // Return nil if no whale data
        guard !transactions.isEmpty else {
            return nil
        }
        
        var lines: [String] = ["RECENT WHALE ACTIVITY (Large Transactions):"]
        
        // Get statistics
        let last24h = transactions.filter { $0.timestamp > Date().addingTimeInterval(-86400) }
        let totalVolume = last24h.reduce(0) { $0 + $1.amountUSD }
        
        lines.append("- Last 24h: \(last24h.count) whale transactions")
        lines.append("- Total Volume: \(formatLargeCurrency(totalVolume))")
        
        // Group by action type
        let exchangeInflows = last24h.filter { $0.transactionType == .exchangeDeposit }
        let exchangeOutflows = last24h.filter { $0.transactionType == .exchangeWithdrawal }
        
        if !exchangeInflows.isEmpty || !exchangeOutflows.isEmpty {
            let inflowVolume = exchangeInflows.reduce(0) { $0 + $1.amountUSD }
            let outflowVolume = exchangeOutflows.reduce(0) { $0 + $1.amountUSD }
            
            lines.append("")
            lines.append("EXCHANGE FLOWS:")
            lines.append("- Inflows (potential sell pressure): \(formatLargeCurrency(inflowVolume)) (\(exchangeInflows.count) txns)")
            lines.append("- Outflows (potential accumulation): \(formatLargeCurrency(outflowVolume)) (\(exchangeOutflows.count) txns)")
            
            // Net flow interpretation
            let netFlow = outflowVolume - inflowVolume
            if abs(netFlow) > 10_000_000 { // Only mention if significant
                let flowDirection = netFlow > 0 ? "net outflows (bullish signal)" : "net inflows (bearish signal)"
                lines.append("- Overall: \(flowDirection)")
            }
        }
        
        // Top recent movements
        let sortedBySize = transactions.sorted { $0.amountUSD > $1.amountUSD }
        if let largest = sortedBySize.first {
            lines.append("")
            lines.append("LARGEST RECENT:")
            let timeAgo = formatTimeAgo(largest.timestamp)
            lines.append("- \(formatLargeCurrency(largest.amountUSD)) \(largest.symbol) moved \(timeAgo) (\(largest.transactionType.rawValue))")
        }
        
        lines.append("")
        lines.append("User can ask about whale movements and their potential market impact.")
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Upcoming Events Context Section
    
    /// Build context about upcoming crypto events
    private func buildUpcomingEventsSection() -> String? {
        let eventsVM = EventsViewModel()
        let events = eventsVM.items
        
        // Filter to upcoming events only (next 14 days)
        let now = Date()
        let twoWeeksLater = now.addingTimeInterval(14 * 24 * 60 * 60)
        let upcomingEvents = events.filter { $0.date > now && $0.date < twoWeeksLater }
        
        // Return nil if no upcoming events
        guard !upcomingEvents.isEmpty else {
            return nil
        }
        
        var lines: [String] = ["UPCOMING CRYPTO EVENTS (Next 14 Days):"]
        
        // Group by impact
        let highImpact = upcomingEvents.filter { $0.impact == .high }
        let mediumImpact = upcomingEvents.filter { $0.impact == .medium }
        
        if !highImpact.isEmpty {
            lines.append("")
            lines.append("HIGH IMPACT EVENTS:")
            
            for event in highImpact.prefix(3) {
                let daysUntil = Calendar.current.dateComponents([.day], from: now, to: event.date).day ?? 0
                let timeText = daysUntil == 0 ? "Today" : daysUntil == 1 ? "Tomorrow" : "In \(daysUntil) days"
                lines.append("- \(event.title) (\(timeText)) - \(event.category.rawValue)")
                if let subtitle = event.subtitle {
                    lines.append("  \(subtitle)")
                }
            }
        }
        
        if !mediumImpact.isEmpty {
            lines.append("")
            lines.append("OTHER NOTABLE:")
            
            for event in mediumImpact.prefix(3) {
                let daysUntil = Calendar.current.dateComponents([.day], from: now, to: event.date).day ?? 0
                let timeText = daysUntil == 0 ? "Today" : daysUntil == 1 ? "Tomorrow" : "In \(daysUntil) days"
                lines.append("- \(event.title) (\(timeText))")
            }
        }
        
        lines.append("")
        lines.append("User can ask about upcoming events and how they might impact the market.")
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - User Preferences Section
    
    /// Build context about user's preferences (currency, subscription, etc.)
    private func buildUserPreferencesSection() -> String {
        var lines: [String] = ["USER PREFERENCES:"]
        
        // Preferred display currency
        let currencyManager = CurrencyManager.shared
        let preferredCurrency = currencyManager.currency
        lines.append("- Display Currency: \(preferredCurrency.displayName) (\(preferredCurrency.symbol))")
        if preferredCurrency != DisplayCurrency.usd {
            lines.append("  When showing prices, the user prefers \(preferredCurrency.rawValue). Convert or note USD equivalent when relevant.")
        }
        
        // Subscription tier - affects what features AI can suggest
        let subscriptionManager = SubscriptionManager.shared
        let tier = subscriptionManager.currentTier
        lines.append("- Subscription: \(tier.displayName)")
        
        switch tier {
        case .free:
            lines.append("  Free user - can suggest upgrading for advanced features like trading bots, tax reports, etc.")
        case .pro:
            lines.append("  Pro user - has access to trade execution, paper trading, whale tracking, alerts.")
        case .premium:
            lines.append("  Premium user - has access to ALL features including bots, copy trading, derivatives, and unlimited AI usage.")
        }
        
        // Compliance/region info
        let isUS = ComplianceManager.shared.isUSUser
        lines.append("- Region: \(isUS ? "US (use USD pairs, Coinbase/Binance.US compatible)" : "International (USDT pairs, Binance compatible)")")
        
        // User's time zone for context
        let timeZone = TimeZone.current
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm a zzz"
        lines.append("- Local Time: \(formatter.string(from: Date()))")
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Risk Profile Section
    
    /// Build a risk profile based on user's trading behavior
    private func buildRiskProfileSection() -> String? {
        let isPaperTrading = PaperTradingManager.isEnabled
        let isDemoMode = DemoModeManager.isEnabled
        
        // Skip for demo mode
        if isDemoMode { return nil }
        
        var lines: [String] = ["INFERRED RISK PROFILE:"]
        var riskIndicators: [String] = []
        var riskScore = 50 // Start neutral (0-100, higher = more aggressive)
        
        if isPaperTrading {
            // Analyze paper trading behavior
            let paperManager = PaperTradingManager.shared
            let totalTrades = paperManager.totalTradeCount
            let totalVolume = paperManager.totalVolumeTraded
            let pnlPercent = paperManager.calculateProfitLossPercent(prices: getPrices())
            
            if totalTrades == 0 {
                lines.append("- No trades yet - unable to assess risk profile")
                lines.append("- Suggest: Start with small practice trades to learn")
                return lines.joined(separator: "\n")
            }
            
            let avgTradeSize = totalTrades > 0 ? totalVolume / Double(totalTrades) : 0
            
            // Analyze trade frequency
            if totalTrades > 20 {
                riskIndicators.append("Active trader (\(totalTrades) trades)")
                riskScore += 10
            } else if totalTrades < 5 {
                riskIndicators.append("Cautious/new trader (\(totalTrades) trades)")
                riskScore -= 10
            }
            
            // Analyze average trade size relative to portfolio
            let portfolioValue = paperManager.calculatePortfolioValue(prices: getPrices())
            if portfolioValue > 0 && avgTradeSize > 0 {
                let sizePercent = (avgTradeSize / portfolioValue) * 100
                if sizePercent > 20 {
                    riskIndicators.append("Large position sizes (\(Int(sizePercent))% avg)")
                    riskScore += 20
                } else if sizePercent < 5 {
                    riskIndicators.append("Conservative position sizes (\(Int(sizePercent))% avg)")
                    riskScore -= 10
                }
            }
            
            // Analyze P/L tolerance
            if pnlPercent < -10 {
                riskIndicators.append("Holding through losses (\(String(format: "%.1f", pnlPercent))%)")
            } else if pnlPercent > 20 {
                riskIndicators.append("Profitable trader (+\(String(format: "%.1f", pnlPercent))%)")
            }
            
        } else {
            // Analyze live trading behavior
            let liveHistory = LiveTradeHistoryManager.shared
            let totalTrades = liveHistory.totalTradeCount
            
            if totalTrades == 0 {
                lines.append("- No live trade history - risk profile unknown")
                lines.append("- Consider paper trading first to practice strategies")
                return lines.joined(separator: "\n")
            }
            
            let avgTradeSize = liveHistory.averageTradeSize
            
            // Trade frequency analysis
            if totalTrades > 50 {
                riskIndicators.append("Very active trader (\(totalTrades) trades)")
                riskScore += 15
            } else if totalTrades > 20 {
                riskIndicators.append("Active trader (\(totalTrades) trades)")
                riskScore += 5
            } else if totalTrades < 5 {
                riskIndicators.append("Cautious trader (\(totalTrades) trades)")
                riskScore -= 10
            }
            
            // Average trade size analysis
            if avgTradeSize > 5000 {
                riskIndicators.append("Large trades (avg \(formatCurrency(avgTradeSize)))")
                riskScore += 15
            } else if avgTradeSize > 1000 {
                riskIndicators.append("Medium trades (avg \(formatCurrency(avgTradeSize)))")
            } else if avgTradeSize < 200 {
                riskIndicators.append("Small trades (avg \(formatCurrency(avgTradeSize)))")
                riskScore -= 10
            }
        }
        
        // Determine risk category
        let riskCategory: String
        let riskAdvice: String
        
        riskScore = max(0, min(100, riskScore))
        
        if riskScore >= 70 {
            riskCategory = "Aggressive"
            riskAdvice = "User comfortable with larger positions and volatility. Can suggest higher-risk opportunities but always include risk warnings."
        } else if riskScore >= 40 {
            riskCategory = "Moderate"
            riskAdvice = "User takes balanced approach. Suggest diversified positions with reasonable risk/reward."
        } else {
            riskCategory = "Conservative"
            riskAdvice = "User prefers safety. Suggest smaller positions, established coins, DCA strategies."
        }
        
        lines.append("- Risk Tolerance: \(riskCategory)")
        for indicator in riskIndicators.prefix(3) {
            lines.append("  • \(indicator)")
        }
        lines.append("")
        lines.append("RECOMMENDATION: \(riskAdvice)")
        
        return lines.joined(separator: "\n")
    }
    
    /// Helper to get current market prices
    /// BUG FIX: Now includes fallback to lastKnownPrices when live prices are unavailable (API rate limiting)
    private func getPrices() -> [String: Double] {
        let marketVM = MarketViewModel.shared
        let paperManager = PaperTradingManager.shared
        var prices: [String: Double] = ["USDT": 1.0, "USD": 1.0, "USDC": 1.0, "BUSD": 1.0]
        
        // Get live prices from market data
        // PRICE CONSISTENCY FIX: Use bestPrice() for consistent pricing
        for coin in marketVM.allCoins {
            let symbol = coin.symbol.uppercased()
            if let price = marketVM.bestPrice(for: coin.id), price > 0 {
                prices[symbol] = price
            } else if let price = coin.priceUsd, price > 0 {
                prices[symbol] = price
            }
        }
        
        // FIX: Try bestPrice(forSymbol:) for held assets not in allCoins
        for (asset, _) in paperManager.paperBalances {
            let symbol = asset.uppercased()
            if prices[symbol] == nil || prices[symbol] == 0 {
                if let symbolPrice = marketVM.bestPrice(forSymbol: symbol), symbolPrice > 0 {
                    prices[symbol] = symbolPrice
                }
            }
        }
        
        // Fallback: Use lastKnownPrices only if fresh (< 30 min old)
        for (asset, _) in paperManager.paperBalances {
            let symbol = asset.uppercased()
            if prices[symbol] == nil || prices[symbol] == 0 {
                if let cachedPrice = paperManager.lastKnownPrices[symbol], cachedPrice > 0,
                   paperManager.isCachedPriceFresh(for: symbol) {
                    prices[symbol] = cachedPrice
                }
            }
        }
        
        return prices
    }
    
    // MARK: - Newly Listed Coins Section
    
    /// Build context about recently listed coins
    private func buildNewlyListedCoinsSection() -> String? {
        let newCoinsService = NewlyListedCoinsService.shared
        let newCoins = newCoinsService.newlyListedCoins
        let trendingMemes = newCoinsService.trendingMemeCoins
        
        // Only include if there are new coins
        guard !newCoins.isEmpty || !trendingMemes.isEmpty else {
            return nil
        }
        
        var lines: [String] = ["NEWLY LISTED & TRENDING:"]
        
        // New listings (last 14 days)
        if !newCoins.isEmpty {
            lines.append("")
            lines.append("NEW LISTINGS (Last 14 Days):")
            for coin in newCoins.prefix(3) {
                let change = coin.priceChangePercentage24hInCurrency ?? 0
                let sign = change >= 0 ? "+" : ""
                let volume = coin.totalVolume ?? 0
                let priceStr = coin.priceUsd != nil ? formatCurrency(coin.priceUsd!) : "N/A"
                lines.append("- \(coin.symbol.uppercased()) (\(coin.name)): \(priceStr) (\(sign)\(formatPercent(change))% 24h)")
                if volume > 0 {
                    lines.append("  Volume: \(formatLargeCurrency(volume))")
                }
            }
            lines.append("NOTE: New listings are HIGH RISK - low liquidity, unproven projects. Warn user accordingly.")
        }
        
        // Trending meme coins
        if !trendingMemes.isEmpty {
            lines.append("")
            lines.append("TRENDING MEME COINS:")
            for coin in trendingMemes.prefix(3) {
                let change = coin.priceChangePercentage24hInCurrency ?? 0
                let sign = change >= 0 ? "+" : ""
                lines.append("- \(coin.symbol.uppercased()): \(sign)\(formatPercent(change))% 24h")
            }
            lines.append("NOTE: Meme coins are EXTREMELY HIGH RISK - speculative, volatile. Only mention if user specifically asks about memes/trending.")
        }
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Time Formatting Helper
    
    private func formatTimeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
    
    // MARK: - Helper for DeFi
    
    private func shortenAddress(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }
    
    // MARK: - Paper Trading Portfolio Section
    
    /// Build portfolio context from paper trading balances
    private func buildPaperTradingPortfolioSection() -> String {
        let paperManager = PaperTradingManager.shared
        let balances = paperManager.nonZeroBalances
        
        // Get current market prices for valuation (with fallback to cached prices)
        let prices = getPrices()
        
        let totalValue = paperManager.calculatePortfolioValue(prices: prices)
        let pnl = paperManager.calculateProfitLoss(prices: prices)
        let pnlPercent = paperManager.calculateProfitLossPercent(prices: prices)
        let startingBalance = paperManager.startingBalance
        
        var lines: [String] = ["=== USER'S PAPER TRADING PORTFOLIO (Their Available Funds) ==="]
        lines.append("IMPORTANT: This is the user's current paper trading balance. Use these values when they ask about their holdings or want to trade.")
        lines.append("")
        lines.append("- Starting Balance: \(formatCurrency(startingBalance))")
        lines.append("- Current Total Value: \(formatCurrency(totalValue))")
        
        let pnlSign = pnl >= 0 ? "+" : ""
        lines.append("- Overall P/L: \(pnlSign)\(formatCurrency(pnl)) (\(pnlSign)\(formatPercent(pnlPercent))%)")
        
        if balances.isEmpty {
            lines.append("")
            lines.append("BALANCES: Only USDT available (no crypto holdings yet)")
            lines.append("- USDT: \(formatCurrency(paperManager.balance(for: "USDT"))) (available cash)")
            lines.append("")
            lines.append("The user has \(formatCurrency(paperManager.balance(for: "USDT"))) available to practice buying crypto. They DO have holdings - they have cash!")
        } else {
            lines.append("")
            lines.append("CURRENT BALANCES:")
            
            // Sort by USD value descending
            let sortedBalances = balances.sorted { item1, item2 in
                let val1 = item1.amount * (prices[item1.asset] ?? 1.0)
                let val2 = item2.amount * (prices[item2.asset] ?? 1.0)
                return val1 > val2
            }
            
            for item in sortedBalances.prefix(10) {
                let price = prices[item.asset] ?? 1.0
                let value = item.amount * price
                let allocation = totalValue > 0 ? (value / totalValue) * 100 : 0
                
                if item.asset == "USDT" || item.asset == "USD" || item.asset == "USDC" {
                    lines.append("- \(item.asset): \(formatCurrency(item.amount)) (cash)")
                } else {
                    lines.append("- \(item.asset): \(formatQuantity(item.amount)) units @ \(formatCurrency(price)) = \(formatCurrency(value)) (\(formatPercent(allocation))%)")
                }
            }
            
            if balances.count > 10 {
                lines.append("- ... and \(balances.count - 10) more assets")
            }
        }
        
        // Add recent paper trades summary
        let recentTrades = paperManager.recentTrades(limit: 5)
        if !recentTrades.isEmpty {
            lines.append("")
            lines.append("RECENT PAPER TRADES:")
            for trade in recentTrades {
                let sideStr = trade.side == .buy ? "Bought" : "Sold"
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "MMM d, h:mm a"
                let dateStr = dateFormatter.string(from: trade.timestamp)
                lines.append("- \(sideStr) \(formatQuantity(trade.quantity)) \(trade.symbol) @ \(formatCurrency(trade.price)) (\(dateStr))")
            }
        }
        
        // Trading stats
        let totalTrades = paperManager.totalTradeCount
        if totalTrades > 0 {
            lines.append("")
            lines.append("PAPER TRADING STATS:")
            lines.append("- Total Trades: \(totalTrades) (\(paperManager.buyTradeCount) buys, \(paperManager.sellTradeCount) sells)")
            lines.append("- Total Volume: \(formatCurrency(paperManager.totalVolumeTraded))")
            if let since = paperManager.tradingSinceDate {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "MMM d, yyyy"
                lines.append("- Trading since: \(dateFormatter.string(from: since))")
            }
        }
        
        lines.append("")
        lines.append("AVAILABLE FOR TRADING (Use this for trade sizing):")
        let availableUSDT = paperManager.balance(for: "USDT")
        lines.append("- Cash: \(formatCurrency(availableUSDT)) USDT available to buy crypto")
        lines.append("- The user CAN trade - they have paper trading funds available!")
        lines.append("- Never say they have 'no holdings' - they have \(formatCurrency(totalValue)) in their paper portfolio")
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Demo Mode Portfolio Section
    
    /// Build portfolio context that clearly indicates this is DEMO/SAMPLE data
    private func buildDemoModePortfolioSection(from portfolio: PortfolioViewModel) -> String {
        let holdings = portfolio.holdings
        let hasConnectedAccounts = !ConnectedAccountsManager.shared.accounts.isEmpty
        
        var lines: [String] = []
        
        // Clear header indicating this is demo data
        lines.append("DEMO PORTFOLIO (SAMPLE DATA - NOT REAL):")
        lines.append("WARNING: The following holdings are FAKE DEMO DATA for demonstration purposes only.")
        lines.append("DO NOT give personalized trading advice based on this demo portfolio.")
        lines.append("")
        
        if hasConnectedAccounts {
            lines.append("NOTE: User has real exchange accounts connected. They can switch off Demo Mode in Settings to see their actual portfolio.")
            lines.append("")
        }
        
        if holdings.isEmpty {
            lines.append("Demo portfolio is currently empty.")
            lines.append("")
            lines.append("SUGGESTIONS FOR USER:")
            lines.append("- Enable Paper Trading to practice with $100K simulated funds")
            lines.append("- Or connect an exchange to see real portfolio data")
            return lines.joined(separator: "\n")
        }
        
        lines.append("SAMPLE HOLDINGS (for demonstration):")
        
        var totalValue: Double = 0
        let sortedHoldings = holdings.sorted { $0.currentValue > $1.currentValue }
        
        for holding in sortedHoldings.prefix(5) {
            let value = holding.currentValue
            totalValue += value
            let dailySign = holding.dailyChange >= 0 ? "+" : ""
            lines.append("- \(holding.coinSymbol): \(formatQuantity(holding.quantity)) units (\(formatCurrency(value))) \(dailySign)\(formatPercent(holding.dailyChange))% today")
        }
        
        if holdings.count > 5 {
            lines.append("- ... and \(holdings.count - 5) more demo holdings")
        }
        
        lines.append("")
        lines.append("Demo Total Value: \(formatCurrency(totalValue))")
        lines.append("")
        lines.append("REMEMBER: This is SAMPLE data. The user should:")
        lines.append("1. Enable Paper Trading to practice trading strategies")
        lines.append("2. Connect a real exchange for actual portfolio management")
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Real Portfolio Section for Paper Trading Mode
    
    /// Build a section showing the user's REAL portfolio holdings when they're in paper trading mode
    /// This allows the AI to discuss both paper trading and real holdings
    private func buildRealPortfolioSectionForPaperTradingMode(from portfolio: PortfolioViewModel) -> String {
        let holdings = portfolio.holdings
        
        guard !holdings.isEmpty else {
            return """
            === USER'S REAL PORTFOLIO (Connected Exchanges) ===
            No holdings found on connected exchanges. The exchange accounts may be empty or sync is in progress.
            """
        }
        
        var lines: [String] = []
        lines.append("=== USER'S REAL PORTFOLIO (Connected Exchanges) ===")
        lines.append("NOTE: This is the user's ACTUAL holdings on their connected exchange(s).")
        lines.append("Use this data when user asks about their 'real portfolio' or 'actual holdings'.")
        lines.append("")
        
        var totalValue: Double = 0
        var totalPL: Double = 0
        var totalCostBasis: Double = 0
        
        let sortedHoldings = holdings.sorted { $0.currentValue > $1.currentValue }
        
        lines.append("REAL HOLDINGS:")
        for holding in sortedHoldings.prefix(8) {
            let value = holding.currentValue
            let costBasis = holding.costBasis * holding.quantity
            let pl = value - costBasis
            let plPercent = costBasis > 0 ? (pl / costBasis) * 100 : 0
            let dailySign = holding.dailyChange >= 0 ? "+" : ""
            let plSign = pl >= 0 ? "+" : ""
            
            totalValue += value
            totalPL += pl
            totalCostBasis += costBasis
            
            lines.append("- \(holding.coinSymbol): \(formatQuantity(holding.quantity)) @ \(formatCurrency(holding.currentPrice)) = \(formatCurrency(value)) (\(plSign)\(formatPercent(plPercent))% P/L, \(dailySign)\(formatPercent(holding.dailyChange))% today)")
        }
        
        if holdings.count > 8 {
            lines.append("- ... and \(holdings.count - 8) more holdings")
        }
        
        totalValue = portfolio.totalValue
        
        lines.append("")
        lines.append("REAL PORTFOLIO SUMMARY:")
        lines.append("- Total Real Value: \(formatCurrency(totalValue))")
        let plSign = totalPL >= 0 ? "+" : ""
        let totalPLPercent = totalCostBasis > 0 ? (totalPL / totalCostBasis) * 100 : 0
        lines.append("- Total Real P/L: \(plSign)\(formatCurrency(totalPL)) (\(plSign)\(formatPercent(totalPLPercent))%)")
        lines.append("- Holdings Count: \(holdings.count)")
        
        // Top allocation
        if let topHolding = sortedHoldings.first, totalValue > 0 {
            let topPercent = (topHolding.currentValue / totalValue) * 100
            lines.append("- Largest Position: \(topHolding.coinSymbol) at \(formatPercent(topPercent))%")
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func buildPortfolioSection(from portfolio: PortfolioViewModel) -> String {
        let holdings = portfolio.holdings
        let hasConnectedAccounts = !ConnectedAccountsManager.shared.accounts.isEmpty
        
        guard !holdings.isEmpty else {
            if hasConnectedAccounts {
                return "PORTFOLIO: Your connected exchanges show no holdings. You may need to fund your exchange accounts or the sync may still be in progress."
            } else {
                return "PORTFOLIO: No holdings yet - no exchanges are connected. Suggest connecting an exchange or enabling Paper Trading to get started."
            }
        }
        
        var lines: [String] = ["USER'S PORTFOLIO (Live Data):"]
        
        var totalValue: Double = 0
        var totalPL: Double = 0
        var totalCostBasis: Double = 0
        
        // Sort by value descending
        let sortedHoldings = holdings.sorted { $0.currentValue > $1.currentValue }
        
        for holding in sortedHoldings.prefix(10) {
            let value = holding.currentValue
            let costBasis = holding.costBasis * holding.quantity
            let pl = value - costBasis
            let plPercent = costBasis > 0 ? (pl / costBasis) * 100 : 0
            let dailySign = holding.dailyChange >= 0 ? "+" : ""
            let plSign = pl >= 0 ? "+" : ""
            
            totalValue += value
            totalPL += pl
            totalCostBasis += costBasis
            
            lines.append("- \(holding.coinSymbol): \(formatQuantity(holding.quantity)) units @ \(formatCurrency(holding.currentPrice))")
            lines.append("  Value: \(formatCurrency(value)) | P/L: \(plSign)\(formatCurrency(pl)) (\(plSign)\(formatPercent(plPercent))%) | Today: \(dailySign)\(formatPercent(holding.dailyChange))%")
        }
        
        if holdings.count > 10 {
            lines.append("- ... and \(holdings.count - 10) more holdings")
        }
        
        // Calculate total from all holdings
        totalValue = portfolio.totalValue
        
        lines.append("")
        lines.append("PORTFOLIO SUMMARY:")
        lines.append("- Total Value: \(formatCurrency(totalValue))")
        
        let plSign = totalPL >= 0 ? "+" : ""
        let totalPLPercent = totalCostBasis > 0 ? (totalPL / totalCostBasis) * 100 : 0
        lines.append("- Total P/L: \(plSign)\(formatCurrency(totalPL)) (\(plSign)\(formatPercent(totalPLPercent))%)")
        lines.append("- Holdings Count: \(holdings.count)")
        
        // Add allocation breakdown with risk notes
        if totalValue > 0 && holdings.count > 1 {
            lines.append("")
            lines.append("ALLOCATION (% of portfolio):")
            for holding in sortedHoldings.prefix(5) {
                let allocation = (holding.currentValue / totalValue) * 100
                var note = ""
                if allocation > 50 { note = " ⚠️ HIGH CONCENTRATION" }
                else if allocation > 30 { note = " (significant position)" }
                lines.append("- \(holding.coinSymbol): \(formatPercent(allocation))%\(note)")
            }
            if sortedHoldings.count > 5 {
                let othersValue = sortedHoldings.dropFirst(5).reduce(0) { $0 + $1.currentValue }
                let othersPercent = (othersValue / totalValue) * 100
                lines.append("- Others: \(formatPercent(othersPercent))%")
            }
        }
        
        // Add quick insights
        lines.append("")
        lines.append("QUICK INSIGHTS:")
        
        // Best performer today
        if let bestToday = sortedHoldings.max(by: { $0.dailyChange < $1.dailyChange }) {
            let sign = bestToday.dailyChange >= 0 ? "+" : ""
            lines.append("- Best today: \(bestToday.coinSymbol) (\(sign)\(formatPercent(bestToday.dailyChange))%)")
        }
        
        // Worst performer today  
        if let worstToday = sortedHoldings.min(by: { $0.dailyChange < $1.dailyChange }) {
            let sign = worstToday.dailyChange >= 0 ? "+" : ""
            lines.append("- Worst today: \(worstToday.coinSymbol) (\(sign)\(formatPercent(worstToday.dailyChange))%)")
        }
        
        // Diversification note
        if let topAlloc = sortedHoldings.first, totalValue > 0 {
            let topPercent = (topAlloc.currentValue / totalValue) * 100
            if topPercent > 60 {
                lines.append("- ⚠️ Portfolio is heavily concentrated in \(topAlloc.coinSymbol)")
            } else if holdings.count < 3 {
                lines.append("- Consider adding more assets for diversification")
            } else {
                lines.append("- Portfolio has \(holdings.count) assets")
            }
        }
        
        return lines.joined(separator: "\n")
    }
}

// MARK: - Quick Context Helpers

extension AIContextBuilder {
    /// Get a brief market summary for quick augmentation
    func getMarketSummary() -> String {
        let marketVM = MarketViewModel.shared
        
        var parts: [String] = []
        
        if let marketCap = marketVM.globalMarketCap, marketCap > 0 {
            parts.append("Market Cap: \(formatLargeCurrency(marketCap))")
        }
        
        if let btcDom = marketVM.btcDominance, btcDom > 0 {
            parts.append("BTC Dom: \(formatPercent(btcDom))%")
        }
        
        // Get BTC and ETH prices
        if let btc = marketVM.allCoins.first(where: { $0.symbol.uppercased() == "BTC" }) {
            if let price = btc.priceUsd {
                let change = btc.priceChangePercentage24hInCurrency ?? 0
                let sign = change >= 0 ? "+" : ""
                parts.append("BTC: \(formatCurrency(price)) (\(sign)\(formatPercent(change))%)")
            }
        }
        
        if let eth = marketVM.allCoins.first(where: { $0.symbol.uppercased() == "ETH" }) {
            if let price = eth.priceUsd {
                let change = eth.priceChangePercentage24hInCurrency ?? 0
                let sign = change >= 0 ? "+" : ""
                parts.append("ETH: \(formatCurrency(price)) (\(sign)\(formatPercent(change))%)")
            }
        }
        
        return parts.joined(separator: " | ")
    }
    
    /// Get a quick portfolio summary for trading advice queries
    /// Returns a concise summary: "Total: $X | BTC: Y% (+Z% P/L) | ETH: W% (-V% P/L)..."
    /// Automatically uses paper trading balances when paper trading mode is enabled
    /// Also includes real portfolio when user has connected accounts in paper trading mode
    func getQuickPortfolioSummary(portfolio: PortfolioViewModel) -> String {
        // Mode priority: Paper Trading > Demo Mode > Live Mode
        
        // Check if paper trading mode is enabled
        if PaperTradingManager.isEnabled {
            let hasConnectedAccounts = !ConnectedAccountsManager.shared.accounts.isEmpty
            let paperSummary = getQuickPaperTradingSummary()
            
            // If user has connected accounts, also include real portfolio summary
            if hasConnectedAccounts && !portfolio.holdings.isEmpty {
                let realSummary = getQuickRealPortfolioSummary(portfolio: portfolio)
                return "\(paperSummary) || REAL: \(realSummary) || Infer from context, default paper for trades"
            }
            
            return paperSummary
        }
        
        // Check if demo mode is enabled
        if DemoModeManager.isEnabled {
            let hasConnectedAccounts = !ConnectedAccountsManager.shared.accounts.isEmpty
            if hasConnectedAccounts {
                return "DEMO MODE (sample data) - Has real accounts connected but viewing demo"
            } else {
                return "DEMO MODE (sample data) - Not real portfolio"
            }
        }
        
        // Live mode
        let hasConnectedAccounts = !ConnectedAccountsManager.shared.accounts.isEmpty
        let holdings = portfolio.holdings
        let totalValue = portfolio.totalValue
        
        guard !holdings.isEmpty else {
            if hasConnectedAccounts {
                return "LIVE MODE - Connected exchanges show no holdings"
            } else {
                return "NO EXCHANGES - User needs to connect an exchange or try Paper Trading"
            }
        }
        
        let sortedHoldings = holdings.sorted { $0.currentValue > $1.currentValue }
        var parts: [String] = []
        
        // Indicate live mode
        parts.append("LIVE")
        
        // Total value
        parts.append("Total: \(formatLargeCurrency(totalValue))")
        
        // Holdings count
        parts.append("\(holdings.count) assets")
        
        // Top holdings with allocation and P/L
        for holding in sortedHoldings.prefix(5) {
            let allocation = totalValue > 0 ? (holding.currentValue / totalValue) * 100 : 0
            let costBasis = holding.costBasis * holding.quantity
            let pl = holding.currentValue - costBasis
            let plPercent = costBasis > 0 ? (pl / costBasis) * 100 : 0
            let plSign = plPercent >= 0 ? "+" : ""
            
            parts.append("\(holding.coinSymbol): \(formatPercent(allocation))% (\(plSign)\(formatPercent(plPercent))% P/L)")
        }
        
        // Note if there are more holdings
        if holdings.count > 5 {
            parts.append("+\(holdings.count - 5) more")
        }
        
        // Add concentration warning if applicable
        if let topHolding = sortedHoldings.first {
            let topPercent = totalValue > 0 ? (topHolding.currentValue / totalValue) * 100 : 0
            if topPercent > 50 {
                parts.append("WARNING: \(topHolding.coinSymbol) is \(formatPercent(topPercent))% - highly concentrated!")
            }
        }
        
        return parts.joined(separator: " | ")
    }
    
    /// Get a quick summary of paper trading portfolio
    private func getQuickPaperTradingSummary() -> String {
        let paperManager = PaperTradingManager.shared
        let balances = paperManager.nonZeroBalances
        
        // Get current market prices (with fallback to cached prices)
        let prices = getPrices()
        
        let totalValue = paperManager.calculatePortfolioValue(prices: prices)
        let pnl = paperManager.calculateProfitLoss(prices: prices)
        let pnlPercent = paperManager.calculateProfitLossPercent(prices: prices)
        
        var parts: [String] = []
        
        // Indicate paper trading mode
        parts.append("PAPER TRADING")
        
        // Total value
        parts.append("Total: \(formatLargeCurrency(totalValue))")
        
        // P/L
        let pnlSign = pnl >= 0 ? "+" : ""
        parts.append("P/L: \(pnlSign)\(formatPercent(pnlPercent))%")
        
        // Available cash
        let availableUSDT = paperManager.balance(for: "USDT")
        parts.append("Available: \(formatCurrency(availableUSDT)) USDT")
        
        // Top non-cash holdings
        let cryptoBalances = balances.filter { !["USDT", "USD", "USDC", "BUSD"].contains($0.asset) }
        let sortedCrypto = cryptoBalances.sorted { item1, item2 in
            let val1 = item1.amount * (prices[item1.asset] ?? 1.0)
            let val2 = item2.amount * (prices[item2.asset] ?? 1.0)
            return val1 > val2
        }
        
        for item in sortedCrypto.prefix(3) {
            let price = prices[item.asset] ?? 1.0
            let value = item.amount * price
            let allocation = totalValue > 0 ? (value / totalValue) * 100 : 0
            parts.append("\(item.asset): \(formatPercent(allocation))%")
        }
        
        if sortedCrypto.count > 3 {
            parts.append("+\(sortedCrypto.count - 3) more")
        }
        
        // Trade count
        let totalTrades = paperManager.totalTradeCount
        if totalTrades > 0 {
            parts.append("\(totalTrades) trades")
        }
        
        return parts.joined(separator: " | ")
    }
    
    /// Get a quick summary of user's REAL portfolio (for paper trading mode with connected accounts)
    private func getQuickRealPortfolioSummary(portfolio: PortfolioViewModel) -> String {
        let holdings = portfolio.holdings
        let totalValue = portfolio.totalValue
        
        guard !holdings.isEmpty else {
            return "No real holdings"
        }
        
        var parts: [String] = []
        
        // Indicate real portfolio
        parts.append("REAL")
        parts.append("Total: \(formatLargeCurrency(totalValue))")
        
        // Top holdings
        let sortedHoldings = holdings.sorted { $0.currentValue > $1.currentValue }
        for holding in sortedHoldings.prefix(3) {
            let allocation = totalValue > 0 ? (holding.currentValue / totalValue) * 100 : 0
            parts.append("\(holding.coinSymbol): \(formatPercent(allocation))%")
        }
        
        if holdings.count > 3 {
            parts.append("+\(holdings.count - 3) more")
        }
        
        return parts.joined(separator: " | ")
    }
    
    /// Get price for a specific symbol
    func getPrice(for symbol: String) -> (price: Double, change24h: Double)? {
        let marketVM = MarketViewModel.shared
        let upperSymbol = symbol.uppercased()
        
        if let coin = marketVM.allCoins.first(where: { $0.symbol.uppercased() == upperSymbol }) {
            if let price = coin.priceUsd {
                return (price, coin.priceChangePercentage24hInCurrency ?? 0)
            }
        }
        
        return nil
    }
}
