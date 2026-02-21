//
//  SmartPromptService.swift
//  CryptoSage
//
//  Generates contextual AI prompts based on user's portfolio state, trading mode,
//  active bots, alerts, watchlist, and market conditions.
//

import Foundation

/// Priority levels for prompt suggestions (lower number = higher priority)
enum PromptPriority: Int, Comparable {
    case timeSensitive = 1    // Alerts near trigger, significant moves
    case actionRelevant = 2   // Bot adjustments, rebalancing
    case engagement = 3       // Portfolio insights, analysis
    case educational = 4      // Learning, feature discovery
    
    static func < (lhs: PromptPriority, rhs: PromptPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A prompt with its priority for sorting
struct PrioritizedPrompt {
    let text: String
    let priority: PromptPriority
    let category: String
}

/// Service responsible for generating context-aware AI prompts
@MainActor
final class SmartPromptService {
    static let shared = SmartPromptService()
    
    private init() {}
    
    // MARK: - Public API
    
    /// Build contextual prompts based on current app state
    /// Returns an array of prioritized prompts, limited to the requested count
    func buildContextualPrompts(count: Int = 3) -> [String] {
        var allPrompts: [PrioritizedPrompt] = []
        
        // Gather prompts from all sources
        allPrompts.append(contentsOf: tradingModePrompts())
        allPrompts.append(contentsOf: portfolioPrompts())
        allPrompts.append(contentsOf: botPrompts())
        allPrompts.append(contentsOf: alertPrompts())
        allPrompts.append(contentsOf: watchlistPrompts())
        allPrompts.append(contentsOf: marketPrompts())
        allPrompts.append(contentsOf: defiPrompts())
        allPrompts.append(contentsOf: tradingStrategyPrompts())
        
        // If we have very few prompts, add educational ones
        if allPrompts.count < count {
            allPrompts.append(contentsOf: educationalPrompts())
        }
        
        // Group prompts by priority, then shuffle within each group for variety
        let groupedByPriority = Dictionary(grouping: allPrompts) { $0.priority }
        var shuffledPrompts: [PrioritizedPrompt] = []
        
        // Process each priority level in order, but shuffle within each level
        for priority in [PromptPriority.timeSensitive, .actionRelevant, .engagement, .educational] {
            if let prompts = groupedByPriority[priority] {
                shuffledPrompts.append(contentsOf: prompts.shuffled())
            }
        }
        
        // Deduplicate and limit
        var seen = Set<String>()
        var result: [String] = []
        
        for prompt in shuffledPrompts {
            let normalized = prompt.text.lowercased()
            if !seen.contains(normalized) {
                seen.insert(normalized)
                result.append(prompt.text)
                if result.count >= count {
                    break
                }
            }
        }
        
        // If still not enough, pad with shuffled fallback prompts
        if result.count < count {
            for fallback in fallbackPrompts().shuffled() {
                if !seen.contains(fallback.lowercased()) {
                    result.append(fallback)
                    seen.insert(fallback.lowercased())
                    if result.count >= count {
                        break
                    }
                }
            }
        }
        
        return Array(result.prefix(count))
    }
    
    // MARK: - Trading Mode Prompts
    
    private func tradingModePrompts() -> [PrioritizedPrompt] {
        var prompts: [PrioritizedPrompt] = []
        
        let isPaperTrading = PaperTradingManager.isEnabled
        let isDemoMode = DemoModeManager.isEnabled
        let hasConnectedAccounts = !ConnectedAccountsManager.shared.accounts.isEmpty
        
        if isDemoMode {
            // Demo mode - guide user to connect or try paper trading
            if !hasConnectedAccounts {
                prompts.append(PrioritizedPrompt(
                    text: "How do I connect my exchange account?",
                    priority: .engagement,
                    category: "onboarding"
                ))
            }
            prompts.append(PrioritizedPrompt(
                text: "What can I do with paper trading?",
                priority: .educational,
                category: "onboarding"
            ))
        } else if isPaperTrading {
            // Paper trading - encourage practice
            let paperManager = PaperTradingManager.shared
            let hasBalance = (paperManager.paperBalances["USDT"] ?? 0) > 0
            
            if hasBalance {
                prompts.append(PrioritizedPrompt(
                    text: "How is my paper portfolio performing?",
                    priority: .engagement,
                    category: "paper_trading"
                ))
                prompts.append(PrioritizedPrompt(
                    text: "What trade should I practice next?",
                    priority: .actionRelevant,
                    category: "paper_trading"
                ))
            }
        } else if !hasConnectedAccounts {
            // Live mode but no accounts
            prompts.append(PrioritizedPrompt(
                text: "How do I get started with CryptoSage?",
                priority: .engagement,
                category: "onboarding"
            ))
            prompts.append(PrioritizedPrompt(
                text: "Which exchange should I connect?",
                priority: .educational,
                category: "onboarding"
            ))
        }
        
        return prompts
    }
    
    // MARK: - Portfolio Prompts
    
    private func portfolioPrompts() -> [PrioritizedPrompt] {
        var prompts: [PrioritizedPrompt] = []
        
        // Get holdings from the appropriate source
        let holdings = getRelevantHoldings()
        guard !holdings.isEmpty else { return prompts }
        
        let totalValue = holdings.reduce(0) { $0 + $1.currentValue }
        
        // Find biggest mover (highest absolute daily change)
        if let biggestMover = holdings.max(by: { abs($0.dailyChange) < abs($1.dailyChange) }),
           abs(biggestMover.dailyChange) > 3.0 {
            let direction = biggestMover.dailyChange > 0 ? "up" : "down"
            let percent = String(format: "%.1f", abs(biggestMover.dailyChange))
            prompts.append(PrioritizedPrompt(
                text: "Why is \(biggestMover.coinSymbol) \(direction) \(percent)% today?",
                priority: .timeSensitive,
                category: "portfolio"
            ))
        }
        
        // Find biggest winner (best P/L)
        if let winner = holdings.max(by: { $0.profitLoss < $1.profitLoss }),
           winner.profitLoss > 0 {
            prompts.append(PrioritizedPrompt(
                text: "Should I take profits on \(winner.coinSymbol)?",
                priority: .actionRelevant,
                category: "portfolio"
            ))
        }
        
        // Find biggest loser (worst P/L)
        if let loser = holdings.min(by: { $0.profitLoss < $1.profitLoss }),
           loser.profitLoss < 0 {
            prompts.append(PrioritizedPrompt(
                text: "Should I cut my losses on \(loser.coinSymbol)?",
                priority: .actionRelevant,
                category: "portfolio"
            ))
        }
        
        // General portfolio questions
        prompts.append(PrioritizedPrompt(
            text: "How is my portfolio performing today?",
            priority: .engagement,
            category: "portfolio"
        ))
        
        // Diversification check for portfolios with 3+ holdings
        if holdings.count >= 3 {
            // Check if top holding is more than 50% of portfolio
            if let topHolding = holdings.max(by: { $0.currentValue < $1.currentValue }),
               totalValue > 0,
               (topHolding.currentValue / totalValue) > 0.5 {
                prompts.append(PrioritizedPrompt(
                    text: "Is my portfolio too concentrated in \(topHolding.coinSymbol)?",
                    priority: .actionRelevant,
                    category: "portfolio"
                ))
            } else {
                prompts.append(PrioritizedPrompt(
                    text: "Should I rebalance my portfolio?",
                    priority: .engagement,
                    category: "portfolio"
                ))
            }
        }
        
        return prompts
    }
    
    // MARK: - Bot Prompts
    
    private func botPrompts() -> [PrioritizedPrompt] {
        var prompts: [PrioritizedPrompt] = []
        
        let isDemoMode = DemoModeManager.isEnabled
        let isPaperTrading = PaperTradingManager.isEnabled
        
        // Check live bots
        let liveBotManager = LiveBotManager.shared
        let liveBotCount = liveBotManager.totalBotCount
        let runningLiveBots = liveBotManager.enabledBotCount
        
        // Check paper bots
        let paperBotManager = PaperBotManager.shared
        let paperBotCount = isDemoMode ? paperBotManager.demoBotCount : paperBotManager.totalBotCount
        let runningPaperBots = isDemoMode ? paperBotManager.runningDemoBotCount : paperBotManager.runningBotCount
        
        // If user has live bots
        if liveBotCount > 0 && !isDemoMode && !isPaperTrading {
            prompts.append(PrioritizedPrompt(
                text: "How are my trading bots performing?",
                priority: .engagement,
                category: "bots"
            ))
            
            if runningLiveBots > 0 {
                prompts.append(PrioritizedPrompt(
                    text: "Should I adjust any of my bot settings?",
                    priority: .actionRelevant,
                    category: "bots"
                ))
            }
            
            // Check bot profitability
            let totalProfit = liveBotManager.totalProfitUsd
            if totalProfit > 0 {
                prompts.append(PrioritizedPrompt(
                    text: "Which of my bots is most profitable?",
                    priority: .engagement,
                    category: "bots"
                ))
            } else if totalProfit < 0 {
                prompts.append(PrioritizedPrompt(
                    text: "Why are my bots underperforming?",
                    priority: .actionRelevant,
                    category: "bots"
                ))
            }
        }
        
        // If user has paper bots
        if paperBotCount > 0 && (isPaperTrading || isDemoMode) {
            prompts.append(PrioritizedPrompt(
                text: "How are my paper trading bots doing?",
                priority: .engagement,
                category: "bots"
            ))
            
            if runningPaperBots > 0 {
                prompts.append(PrioritizedPrompt(
                    text: "Is my bot strategy working well?",
                    priority: .engagement,
                    category: "bots"
                ))
            }
        }
        
        // If no bots at all, suggest creating one
        if liveBotCount == 0 && paperBotCount == 0 {
            if isPaperTrading {
                prompts.append(PrioritizedPrompt(
                    text: "Help me create a paper trading bot",
                    priority: .educational,
                    category: "bots"
                ))
            } else if !isDemoMode && ConnectedAccountsManager.shared.accounts.isEmpty == false {
                prompts.append(PrioritizedPrompt(
                    text: "What kind of trading bot should I try?",
                    priority: .educational,
                    category: "bots"
                ))
            }
        }
        
        return prompts
    }
    
    // MARK: - Alert Prompts
    
    private func alertPrompts() -> [PrioritizedPrompt] {
        var prompts: [PrioritizedPrompt] = []
        
        let notificationManager = NotificationsManager.shared
        let allAlerts = notificationManager.allAlerts
        let triggeredIDs = notificationManager.triggeredAlertIDs
        
        guard !allAlerts.isEmpty else { return prompts }
        
        // Check for recently triggered alerts
        let untriggeredAlerts = allAlerts.filter { !triggeredIDs.contains($0.id) }
        
        if !untriggeredAlerts.isEmpty {
            // Get the first alert's symbol for a specific prompt
            if let firstAlert = untriggeredAlerts.first {
                prompts.append(PrioritizedPrompt(
                    text: "What's the status of my \(firstAlert.symbol) alert?",
                    priority: .engagement,
                    category: "alerts"
                ))
            }
            
            prompts.append(PrioritizedPrompt(
                text: "Are any of my price alerts close to triggering?",
                priority: .timeSensitive,
                category: "alerts"
            ))
        }
        
        // If there are triggered alerts
        if !triggeredIDs.isEmpty {
            prompts.append(PrioritizedPrompt(
                text: "What should I do about my triggered alerts?",
                priority: .actionRelevant,
                category: "alerts"
            ))
        }
        
        return prompts
    }
    
    // MARK: - Watchlist Prompts
    
    private func watchlistPrompts() -> [PrioritizedPrompt] {
        var prompts: [PrioritizedPrompt] = []
        
        let favoriteIDs = FavoritesManager.shared.favoriteIDs
        guard !favoriteIDs.isEmpty else { return prompts }
        
        let watchlistCoins = MarketViewModel.shared.watchlistCoins
        
        if !watchlistCoins.isEmpty {
            // Find best performer on watchlist
            if let bestPerformer = watchlistCoins.max(by: { ($0.dailyChange ?? 0) < ($1.dailyChange ?? 0) }),
               let change = bestPerformer.dailyChange,
               change > 5.0 {
                prompts.append(PrioritizedPrompt(
                    text: "Why is \(bestPerformer.symbol.uppercased()) up \(String(format: "%.1f", change))% today?",
                    priority: .timeSensitive,
                    category: "watchlist"
                ))
            }
            
            // Find worst performer
            if let worstPerformer = watchlistCoins.min(by: { ($0.dailyChange ?? 0) < ($1.dailyChange ?? 0) }),
               let change = worstPerformer.dailyChange,
               change < -5.0 {
                prompts.append(PrioritizedPrompt(
                    text: "Is now a good time to buy \(worstPerformer.symbol.uppercased())?",
                    priority: .actionRelevant,
                    category: "watchlist"
                ))
            }
            
            prompts.append(PrioritizedPrompt(
                text: "How are my watchlist coins performing?",
                priority: .engagement,
                category: "watchlist"
            ))
        } else {
            prompts.append(PrioritizedPrompt(
                text: "Any coins on my watchlist worth buying?",
                priority: .engagement,
                category: "watchlist"
            ))
        }
        
        return prompts
    }
    
    // MARK: - Market Prompts
    
    private func marketPrompts() -> [PrioritizedPrompt] {
        var prompts: [PrioritizedPrompt] = []
        
        let marketVM = MarketViewModel.shared
        let sentimentVM = ExtendedFearGreedViewModel.shared
        
        // Fear & Greed based prompts
        if let fearGreedValue = sentimentVM.currentValue {
            if fearGreedValue <= 25 {
                // Extreme Fear
                prompts.append(PrioritizedPrompt(
                    text: "Market is in extreme fear - any buying opportunities?",
                    priority: .timeSensitive,
                    category: "market"
                ))
            } else if fearGreedValue <= 40 {
                // Fear
                prompts.append(PrioritizedPrompt(
                    text: "Market sentiment is fearful - what does this mean?",
                    priority: .engagement,
                    category: "market"
                ))
            } else if fearGreedValue >= 75 {
                // Extreme Greed
                prompts.append(PrioritizedPrompt(
                    text: "Market is extremely greedy - should I take profits?",
                    priority: .timeSensitive,
                    category: "market"
                ))
            } else if fearGreedValue >= 60 {
                // Greed
                prompts.append(PrioritizedPrompt(
                    text: "Market is getting greedy - time to be cautious?",
                    priority: .engagement,
                    category: "market"
                ))
            }
        }
        
        // BTC dominance based prompts
        if let btcDom = marketVM.btcDominance {
            if btcDom > 55 {
                prompts.append(PrioritizedPrompt(
                    text: "BTC dominance is high - are altcoins due for a rally?",
                    priority: .engagement,
                    category: "market"
                ))
            } else if btcDom < 42 {
                prompts.append(PrioritizedPrompt(
                    text: "Is this alt season? What should I buy?",
                    priority: .engagement,
                    category: "market"
                ))
            }
        }
        
        // SWING TRADING PROMPTS - Based on market regime
        // Check BTC's MA alignment to suggest trading-focused prompts
        if let btc = marketVM.allCoins.first(where: { $0.symbol.uppercased() == "BTC" }) {
            let sparkline = btc.sparklineIn7d
            if sparkline.count >= 20 {
                let sma10 = TechnicalsEngine.sma(sparkline, period: 10)
                let sma20 = TechnicalsEngine.sma(sparkline, period: 20)
                
                if let s10 = sma10, let s20 = sma20 {
                    let is10Above20 = s10 > s20
                    
                    if is10Above20 {
                        // Bullish regime - suggest breakout trades
                        prompts.append(PrioritizedPrompt(
                            text: "Market looks bullish - any breakout setups forming?",
                            priority: .actionRelevant,
                            category: "trading"
                        ))
                        prompts.append(PrioritizedPrompt(
                            text: "What coins are setting up for a breakout?",
                            priority: .actionRelevant,
                            category: "trading"
                        ))
                    } else {
                        // Bearish regime - suggest caution
                        prompts.append(PrioritizedPrompt(
                            text: "BTC trend is bearish - should I wait to buy?",
                            priority: .timeSensitive,
                            category: "trading"
                        ))
                        prompts.append(PrioritizedPrompt(
                            text: "What's the market regime right now?",
                            priority: .engagement,
                            category: "trading"
                        ))
                    }
                }
            }
        }
        
        // General market prompts
        prompts.append(PrioritizedPrompt(
            text: "What's driving the crypto market today?",
            priority: .engagement,
            category: "market"
        ))
        
        prompts.append(PrioritizedPrompt(
            text: "Give me the top gainers and losers today",
            priority: .engagement,
            category: "market"
        ))
        
        return prompts
    }
    
    // MARK: - Trading Strategy Prompts
    
    private func tradingStrategyPrompts() -> [PrioritizedPrompt] {
        var prompts: [PrioritizedPrompt] = []
        
        // Position sizing prompts
        prompts.append(PrioritizedPrompt(
            text: "How do I calculate my position size for a trade?",
            priority: .educational,
            category: "trading_education"
        ))
        
        // Risk management prompts
        prompts.append(PrioritizedPrompt(
            text: "What's a good risk:reward ratio for trades?",
            priority: .educational,
            category: "trading_education"
        ))
        
        // Entry/Exit prompts
        prompts.append(PrioritizedPrompt(
            text: "When should I take profits on a winning trade?",
            priority: .educational,
            category: "trading_education"
        ))
        
        prompts.append(PrioritizedPrompt(
            text: "How do I set proper stop losses?",
            priority: .educational,
            category: "trading_education"
        ))
        
        // Breakout trading prompts
        prompts.append(PrioritizedPrompt(
            text: "How do I identify a breakout setup?",
            priority: .educational,
            category: "trading_education"
        ))
        
        // Additional strategy prompts for variety
        prompts.append(PrioritizedPrompt(
            text: "What's the best strategy for a bear market?",
            priority: .educational,
            category: "trading_education"
        ))
        
        prompts.append(PrioritizedPrompt(
            text: "How do I trade volatility?",
            priority: .educational,
            category: "trading_education"
        ))
        
        prompts.append(PrioritizedPrompt(
            text: "Should I use leverage for trading?",
            priority: .educational,
            category: "trading_education"
        ))
        
        prompts.append(PrioritizedPrompt(
            text: "What's the difference between scalping and swing trading?",
            priority: .educational,
            category: "trading_education"
        ))
        
        prompts.append(PrioritizedPrompt(
            text: "How do I avoid FOMO when trading?",
            priority: .educational,
            category: "trading_education"
        ))
        
        return prompts
    }
    
    // MARK: - DeFi Prompts
    
    private func defiPrompts() -> [PrioritizedPrompt] {
        var prompts: [PrioritizedPrompt] = []
        
        let defiVM = MultiChainPortfolioViewModel.shared
        let connectedWallets = defiVM.connectedWallets
        
        guard !connectedWallets.isEmpty else { return prompts }
        
        let totalDeFiValue = defiVM.totalValue
        
        if totalDeFiValue > 0 {
            prompts.append(PrioritizedPrompt(
                text: "How are my DeFi positions doing?",
                priority: .engagement,
                category: "defi"
            ))
            
            prompts.append(PrioritizedPrompt(
                text: "Any yield farming opportunities I should consider?",
                priority: .actionRelevant,
                category: "defi"
            ))
        }
        
        // NFT prompts
        let nftVM = NFTCollectionViewModel.shared
        if !nftVM.nfts.isEmpty {
            prompts.append(PrioritizedPrompt(
                text: "How is my NFT collection performing?",
                priority: .engagement,
                category: "defi"
            ))
        }
        
        return prompts
    }
    
    // MARK: - Educational Prompts
    
    private func educationalPrompts() -> [PrioritizedPrompt] {
        return [
            // Trading methodology education
            PrioritizedPrompt(text: "Explain the 1% risk rule for trading", priority: .educational, category: "education"),
            PrioritizedPrompt(text: "What is swing trading vs day trading?", priority: .educational, category: "education"),
            PrioritizedPrompt(text: "How do I read moving averages?", priority: .educational, category: "education"),
            PrioritizedPrompt(text: "What makes a good breakout setup?", priority: .educational, category: "education"),
            PrioritizedPrompt(text: "How do I use RSI for trading?", priority: .educational, category: "education"),
            PrioritizedPrompt(text: "What is MACD and how do I use it?", priority: .educational, category: "education"),
            PrioritizedPrompt(text: "Explain support and resistance levels", priority: .educational, category: "education"),
            PrioritizedPrompt(text: "What are Fibonacci retracements?", priority: .educational, category: "education"),
            
            // General crypto education
            PrioritizedPrompt(text: "What is DCA and how does it work?", priority: .educational, category: "education"),
            PrioritizedPrompt(text: "Explain the difference between limit and market orders", priority: .educational, category: "education"),
            PrioritizedPrompt(text: "What is staking and should I do it?", priority: .educational, category: "education"),
            PrioritizedPrompt(text: "How do I minimize trading fees?", priority: .educational, category: "education"),
            PrioritizedPrompt(text: "What is the Fear & Greed Index?", priority: .educational, category: "education"),
            PrioritizedPrompt(text: "Compare Bitcoin and Ethereum", priority: .educational, category: "education"),
            PrioritizedPrompt(text: "What are the risks of crypto trading?", priority: .educational, category: "education"),
            
            // More crypto concepts
            PrioritizedPrompt(text: "What is a blockchain halving?", priority: .educational, category: "education"),
            PrioritizedPrompt(text: "Explain gas fees and how to save on them", priority: .educational, category: "education"),
            PrioritizedPrompt(text: "What are layer 2 solutions?", priority: .educational, category: "education"),
            PrioritizedPrompt(text: "How do crypto ETFs work?", priority: .educational, category: "education"),
            PrioritizedPrompt(text: "What is a crypto wallet and which type is safest?", priority: .educational, category: "education"),
            PrioritizedPrompt(text: "Explain market cap vs fully diluted valuation", priority: .educational, category: "education"),
            PrioritizedPrompt(text: "What are meme coins and are they worth it?", priority: .educational, category: "education"),
            PrioritizedPrompt(text: "How do airdrops work?", priority: .educational, category: "education"),
        ]
    }
    
    // MARK: - Fallback Prompts
    
    private func fallbackPrompts() -> [String] {
        return [
            // Price & Market
            "What's the current price of Bitcoin?",
            "What are the top 10 coins by market cap?",
            "Is the market bullish or bearish right now?",
            "What coins are showing breakout potential?",
            "Which coins are oversold right now?",
            "What's driving the crypto market today?",
            
            // News & Events
            "Any major crypto news I should know?",
            "What upcoming events could move the market?",
            "Any regulatory news I should watch?",
            
            // Trading & Strategy
            "How do trading bots work?",
            "Help me size a position properly",
            "What's a good stop loss strategy?",
            "When should I take profits?",
            "What's the best time to buy crypto?",
            
            // Portfolio & Analysis
            "How should I diversify my portfolio?",
            "What's a healthy portfolio allocation?",
            "Should I rebalance my holdings?",
            
            // Education
            "Explain crypto market cycles",
            "What is yield farming?",
            "How does staking work?",
            "What's the difference between L1 and L2?",
            "Explain DeFi in simple terms",
            "What are the safest ways to store crypto?",
            
            // Specific Coins
            "What's the outlook for Ethereum?",
            "Is Solana a good investment?",
            "Compare Bitcoin to gold",
            "What altcoins have potential?",
        ]
    }
    
    // MARK: - Helper Methods
    
    /// Get holdings based on current trading mode
    private func getRelevantHoldings() -> [Holding] {
        let isPaperTrading = PaperTradingManager.isEnabled
        let isDemoMode = DemoModeManager.isEnabled
        
        // For paper trading, we need to convert paper balances to holdings
        if isPaperTrading && !isDemoMode {
            return getPaperTradingHoldings()
        }
        
        // For regular portfolio (demo or live)
        // Access through the shared PortfolioViewModel would require EnvironmentObject
        // For now, return empty and let the view pass holdings if needed
        // This will be enhanced in the AIChatView integration
        return []
    }
    
    /// Convert paper trading balances to holdings for analysis
    private func getPaperTradingHoldings() -> [Holding] {
        let paperManager = PaperTradingManager.shared
        let balances = paperManager.paperBalances
        var holdings: [Holding] = []
        
        // Skip stablecoins for analysis
        let stablecoins = Set(["USDT", "USDC", "USD", "BUSD", "DAI"])
        
        for (symbol, quantity) in balances where quantity > 0 && !stablecoins.contains(symbol.uppercased()) {
            // Try to get current price from market data
            let marketVM = MarketViewModel.shared
            let coin = marketVM.allCoins.first { $0.symbol.uppercased() == symbol.uppercased() }
            let currentPrice = coin?.priceUsd ?? 0
            let dailyChange = coin?.dailyChange ?? 0
            
            if currentPrice > 0 {
                holdings.append(Holding(
                    coinName: coin?.name ?? symbol,
                    coinSymbol: symbol.uppercased(),
                    quantity: quantity,
                    currentPrice: currentPrice,
                    costBasis: currentPrice, // Simplified - could track actual cost
                    imageUrl: coin?.imageUrl?.absoluteString,
                    isFavorite: false,
                    dailyChange: dailyChange,
                    purchaseDate: Date()
                ))
            }
        }
        
        return holdings
    }
}

// MARK: - Extended API for View Integration

extension SmartPromptService {
    /// Build prompts with additional portfolio context from the view
    func buildContextualPrompts(count: Int = 3, holdings: [Holding]) -> [String] {
        var allPrompts: [PrioritizedPrompt] = []
        
        // Gather prompts from all sources
        allPrompts.append(contentsOf: tradingModePrompts())
        allPrompts.append(contentsOf: portfolioPromptsFromHoldings(holdings))
        allPrompts.append(contentsOf: botPrompts())
        allPrompts.append(contentsOf: alertPrompts())
        allPrompts.append(contentsOf: watchlistPrompts())
        allPrompts.append(contentsOf: marketPrompts())
        allPrompts.append(contentsOf: defiPrompts())
        allPrompts.append(contentsOf: tradingStrategyPrompts())
        
        if allPrompts.count < count {
            allPrompts.append(contentsOf: educationalPrompts())
        }
        
        // Group prompts by priority, then shuffle within each group for variety
        let groupedByPriority = Dictionary(grouping: allPrompts) { $0.priority }
        var shuffledPrompts: [PrioritizedPrompt] = []
        
        // Process each priority level in order, but shuffle within each level
        for priority in [PromptPriority.timeSensitive, .actionRelevant, .engagement, .educational] {
            if let prompts = groupedByPriority[priority] {
                shuffledPrompts.append(contentsOf: prompts.shuffled())
            }
        }
        
        // Deduplicate and limit
        var seen = Set<String>()
        var result: [String] = []
        
        for prompt in shuffledPrompts {
            let normalized = prompt.text.lowercased()
            if !seen.contains(normalized) {
                seen.insert(normalized)
                result.append(prompt.text)
                if result.count >= count {
                    break
                }
            }
        }
        
        // Pad with shuffled fallbacks if needed
        if result.count < count {
            for fallback in fallbackPrompts().shuffled() {
                if !seen.contains(fallback.lowercased()) {
                    result.append(fallback)
                    seen.insert(fallback.lowercased())
                    if result.count >= count {
                        break
                    }
                }
            }
        }
        
        return Array(result.prefix(count))
    }
    
    /// Generate prompts based on provided holdings
    private func portfolioPromptsFromHoldings(_ holdings: [Holding]) -> [PrioritizedPrompt] {
        var prompts: [PrioritizedPrompt] = []
        
        guard !holdings.isEmpty else { return prompts }
        
        let totalValue = holdings.reduce(0) { $0 + $1.currentValue }
        
        // Find biggest mover
        if let biggestMover = holdings.max(by: { abs($0.dailyChange) < abs($1.dailyChange) }),
           abs(biggestMover.dailyChange) > 3.0 {
            let direction = biggestMover.dailyChange > 0 ? "up" : "down"
            let percent = String(format: "%.1f", abs(biggestMover.dailyChange))
            prompts.append(PrioritizedPrompt(
                text: "Why is \(biggestMover.coinSymbol) \(direction) \(percent)% today?",
                priority: .timeSensitive,
                category: "portfolio"
            ))
        }
        
        // Find biggest winner
        if let winner = holdings.max(by: { $0.profitLoss < $1.profitLoss }),
           winner.profitLoss > 0 {
            prompts.append(PrioritizedPrompt(
                text: "Should I take profits on \(winner.coinSymbol)?",
                priority: .actionRelevant,
                category: "portfolio"
            ))
        }
        
        // Find biggest loser
        if let loser = holdings.min(by: { $0.profitLoss < $1.profitLoss }),
           loser.profitLoss < 0 {
            prompts.append(PrioritizedPrompt(
                text: "Should I cut my losses on \(loser.coinSymbol)?",
                priority: .actionRelevant,
                category: "portfolio"
            ))
        }
        
        // General portfolio questions
        prompts.append(PrioritizedPrompt(
            text: "How is my portfolio performing today?",
            priority: .engagement,
            category: "portfolio"
        ))
        
        // Diversification check
        if holdings.count >= 3 {
            if let topHolding = holdings.max(by: { $0.currentValue < $1.currentValue }),
               totalValue > 0,
               (topHolding.currentValue / totalValue) > 0.5 {
                prompts.append(PrioritizedPrompt(
                    text: "Is my portfolio too concentrated in \(topHolding.coinSymbol)?",
                    priority: .actionRelevant,
                    category: "portfolio"
                ))
            } else {
                prompts.append(PrioritizedPrompt(
                    text: "Should I rebalance my portfolio?",
                    priority: .engagement,
                    category: "portfolio"
                ))
            }
        }
        
        return prompts
    }
}
