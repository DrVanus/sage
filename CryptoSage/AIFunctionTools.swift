//
//  AIFunctionTools.swift
//  CryptoSage
//
//  Defines function tools that the AI can call to fetch real-time data.
//  Implements OpenAI function calling schema and execution handlers.
//

import Foundation

/// Manages AI function tools for fetching real-time crypto data
@MainActor
final class AIFunctionTools {
    static let shared = AIFunctionTools()
    // PERFORMANCE FIX: Cached ISO8601 formatter — avoids 14+ allocations per AI function call cycle
    private static let _isoFormatter = ISO8601DateFormatter()
    
    /// Portfolio data injected from the view layer
    var portfolioHoldings: [Holding] = []
    var portfolioTotalValue: Double = 0
    
    /// Update portfolio data (call this from AIChatView before AI requests)
    func updatePortfolio(holdings: [Holding], totalValue: Double) {
        self.portfolioHoldings = holdings
        self.portfolioTotalValue = totalValue
    }
    
    private init() {}
    
    // MARK: - Tool Definitions
    
    /// Get all available tools for the AI
    func getAllTools() -> [Tool] {
        return [
            getPriceTool(),
            getPortfolioSummaryTool(),
            getPortfolioAllocationTool(),
            analyzePortfolioRiskTool(),
            getMarketStatsTool(),
            getMarketSentimentTool(),
            getRecentNewsTool(),
            getTechnicalsTool(),
            getTopCoinsTool(),
            getNewsTool(),
            compareCoinsTool(),
            getTopMoversToool(),
            suggestRebalanceTool(),
            createAlertTool(),
            suggestAlertTool(),
            // Professional Swing Trading Tools
            calculatePositionSizeTool(),
            getMarketRegimeTool(),
            analyzeBreakoutSetupTool(),
            calculateRiskRewardTool(),
            analyzeTrendStructureTool(),
            // AI Price Prediction Tool
            getPricePredictionTool(),
            // Trading Pair Preferences Tool
            getTradingPairPreferencesTool(),
            // DeFi & NFT Tools
            getDeFiPositionsTool(),
            getNFTPortfolioTool(),
            getDeFiYieldsTool(),
            getChainAnalysisTool(),
            getSupportedChainsTool(),
            getSupportedProtocolsTool(),
            // Web Search & URL Reading Tools
            webSearchTool(),
            readURLTool()
        ]
    }
    
    // MARK: - Individual Tool Definitions
    
    private func getPriceTool() -> Tool {
        Tool(
            type: "function",
            function: FunctionDefinition(
                name: "get_price",
                description: "Get the current price and 24h change for a specific cryptocurrency by its symbol (e.g., BTC, ETH, SOL)",
                parameters: FunctionParameters(
                    type: "object",
                    properties: [
                        "symbol": ParameterProperty(
                            type: "string",
                            description: "The ticker symbol of the cryptocurrency (e.g., BTC, ETH, SOL, DOGE)",
                            enumValues: nil
                        )
                    ],
                    required: ["symbol"]
                )
            )
        )
    }
    
    private func getPortfolioSummaryTool() -> Tool {
        Tool(
            type: "function",
            function: FunctionDefinition(
                name: "get_portfolio_summary",
                description: "Get a summary of the user's cryptocurrency portfolio including holdings, total value, and profit/loss",
                parameters: FunctionParameters(
                    type: "object",
                    properties: [:],
                    required: nil
                )
            )
        )
    }
    
    private func getMarketStatsTool() -> Tool {
        Tool(
            type: "function",
            function: FunctionDefinition(
                name: "get_market_stats",
                description: "Get global cryptocurrency market statistics including total market cap, 24h volume, and BTC/ETH dominance",
                parameters: FunctionParameters(
                    type: "object",
                    properties: [:],
                    required: nil
                )
            )
        )
    }
    
    private func getMarketSentimentTool() -> Tool {
        Tool(
            type: "function",
            function: FunctionDefinition(
                name: "get_market_sentiment",
                description: "Get the current market sentiment (Fear & Greed Index) including the score (0-100), classification (extreme fear/fear/neutral/greed/extreme greed), trend direction, and trading bias. Use this to inform buy/sell recommendations.",
                parameters: FunctionParameters(
                    type: "object",
                    properties: [:],
                    required: nil
                )
            )
        )
    }
    
    private func getRecentNewsTool() -> Tool {
        Tool(
            type: "function",
            function: FunctionDefinition(
                name: "get_recent_news",
                description: "Get the most recent cryptocurrency news headlines. Use this to understand current market narratives and events that may impact trading decisions.",
                parameters: FunctionParameters(
                    type: "object",
                    properties: [
                        "count": ParameterProperty(
                            type: "integer",
                            description: "Number of news articles to return (default 5, max 10)",
                            enumValues: nil
                        )
                    ],
                    required: nil
                )
            )
        )
    }
    
    private func getTechnicalsTool() -> Tool {
        Tool(
            type: "function",
            function: FunctionDefinition(
                name: "get_technicals",
                description: "Get technical analysis indicators for a specific cryptocurrency including RSI, MACD signals, and overall sentiment",
                parameters: FunctionParameters(
                    type: "object",
                    properties: [
                        "symbol": ParameterProperty(
                            type: "string",
                            description: "The ticker symbol of the cryptocurrency (e.g., BTC, ETH)",
                            enumValues: nil
                        )
                    ],
                    required: ["symbol"]
                )
            )
        )
    }
    
    private func getTopCoinsTool() -> Tool {
        Tool(
            type: "function",
            function: FunctionDefinition(
                name: "get_top_coins",
                description: "Get the top cryptocurrencies by market cap with their prices and 24h changes",
                parameters: FunctionParameters(
                    type: "object",
                    properties: [
                        "count": ParameterProperty(
                            type: "integer",
                            description: "Number of top coins to return (default 10, max 50)",
                            enumValues: nil
                        )
                    ],
                    required: nil
                )
            )
        )
    }
    
    private func getNewsTool() -> Tool {
        Tool(
            type: "function",
            function: FunctionDefinition(
                name: "get_news",
                description: "Get recent cryptocurrency news headlines",
                parameters: FunctionParameters(
                    type: "object",
                    properties: [
                        "topic": ParameterProperty(
                            type: "string",
                            description: "Optional topic to filter news (e.g., 'bitcoin', 'ethereum', 'defi')",
                            enumValues: nil
                        )
                    ],
                    required: nil
                )
            )
        )
    }
    
    private func compareCoinsTool() -> Tool {
        Tool(
            type: "function",
            function: FunctionDefinition(
                name: "compare_coins",
                description: "Compare two cryptocurrencies by their market metrics",
                parameters: FunctionParameters(
                    type: "object",
                    properties: [
                        "symbol1": ParameterProperty(
                            type: "string",
                            description: "First cryptocurrency symbol (e.g., BTC)",
                            enumValues: nil
                        ),
                        "symbol2": ParameterProperty(
                            type: "string",
                            description: "Second cryptocurrency symbol (e.g., ETH)",
                            enumValues: nil
                        )
                    ],
                    required: ["symbol1", "symbol2"]
                )
            )
        )
    }
    
    private func getPortfolioAllocationTool() -> Tool {
        Tool(
            type: "function",
            function: FunctionDefinition(
                name: "get_portfolio_allocation",
                description: "Get the user's portfolio allocation breakdown by asset, showing percentage of total value in each coin",
                parameters: FunctionParameters(
                    type: "object",
                    properties: [:],
                    required: nil
                )
            )
        )
    }
    
    private func analyzePortfolioRiskTool() -> Tool {
        Tool(
            type: "function",
            function: FunctionDefinition(
                name: "analyze_portfolio_risk",
                description: "Analyze the user's portfolio for risk factors including concentration, volatility exposure, and diversification",
                parameters: FunctionParameters(
                    type: "object",
                    properties: [:],
                    required: nil
                )
            )
        )
    }
    
    private func getTopMoversToool() -> Tool {
        Tool(
            type: "function",
            function: FunctionDefinition(
                name: "get_top_movers",
                description: "Get today's top gaining and losing cryptocurrencies",
                parameters: FunctionParameters(
                    type: "object",
                    properties: [
                        "count": ParameterProperty(
                            type: "integer",
                            description: "Number of top gainers/losers to return (default 5)",
                            enumValues: nil
                        )
                    ],
                    required: nil
                )
            )
        )
    }
    
    private func suggestRebalanceTool() -> Tool {
        Tool(
            type: "function",
            function: FunctionDefinition(
                name: "suggest_rebalance",
                description: "Suggest portfolio rebalancing moves based on current allocation and target diversification",
                parameters: FunctionParameters(
                    type: "object",
                    properties: [
                        "target_btc_percent": ParameterProperty(
                            type: "number",
                            description: "Target BTC allocation percentage (default 40)",
                            enumValues: nil
                        ),
                        "target_eth_percent": ParameterProperty(
                            type: "number",
                            description: "Target ETH allocation percentage (default 30)",
                            enumValues: nil
                        )
                    ],
                    required: nil
                )
            )
        )
    }
    
    private func createAlertTool() -> Tool {
        Tool(
            type: "function",
            function: FunctionDefinition(
                name: "create_alert",
                description: "Create a price alert for the user. Use this when the user explicitly asks to create an alert, or when you want to suggest setting up an alert based on the conversation. Returns a confirmation and the alert details.",
                parameters: FunctionParameters(
                    type: "object",
                    properties: [
                        "symbol": ParameterProperty(
                            type: "string",
                            description: "The cryptocurrency symbol (e.g., BTC, ETH, SOL)",
                            enumValues: nil
                        ),
                        "target_price": ParameterProperty(
                            type: "number",
                            description: "The target price in USD that should trigger the alert",
                            enumValues: nil
                        ),
                        "direction": ParameterProperty(
                            type: "string",
                            description: "Alert when price goes 'above' or 'below' the target",
                            enumValues: ["above", "below"]
                        ),
                        "enable_ai_features": ParameterProperty(
                            type: "boolean",
                            description: "Enable AI-powered features like sentiment analysis and smart timing (optional, default false)",
                            enumValues: nil
                        )
                    ],
                    required: ["symbol", "target_price", "direction"]
                )
            )
        )
    }
    
    private func suggestAlertTool() -> Tool {
        Tool(
            type: "function",
            function: FunctionDefinition(
                name: "suggest_alert",
                description: "Analyze the current market conditions and suggest a price alert for a specific cryptocurrency. Use this when discussing a coin to proactively offer helpful alert suggestions. Only use when contextually relevant (e.g., user is discussing trading, prices, or asks about a specific coin).",
                parameters: FunctionParameters(
                    type: "object",
                    properties: [
                        "symbol": ParameterProperty(
                            type: "string",
                            description: "The cryptocurrency symbol to analyze and suggest an alert for",
                            enumValues: nil
                        ),
                        "context": ParameterProperty(
                            type: "string",
                            description: "Brief context about why this alert might be useful (e.g., 'near support level', 'breakout potential', 'high volatility')",
                            enumValues: nil
                        )
                    ],
                    required: ["symbol"]
                )
            )
        )
    }
    
    // MARK: - Professional Swing Trading Tool Definitions
    
    private func calculatePositionSizeTool() -> Tool {
        Tool(
            type: "function",
            function: FunctionDefinition(
                name: "calculate_position_size",
                description: "Calculate the proper position size for a trade based on account value, risk percentage, entry price, and stop loss price. Uses the formula: Risk Amount / (Entry - Stop) = Position Size. Essential for proper risk management.",
                parameters: FunctionParameters(
                    type: "object",
                    properties: [
                        "account_value": ParameterProperty(
                            type: "number",
                            description: "Total account value in USD",
                            enumValues: nil
                        ),
                        "risk_percent": ParameterProperty(
                            type: "number",
                            description: "Percentage of account to risk (typically 1%, max 2%)",
                            enumValues: nil
                        ),
                        "entry_price": ParameterProperty(
                            type: "number",
                            description: "Planned entry price for the trade",
                            enumValues: nil
                        ),
                        "stop_price": ParameterProperty(
                            type: "number",
                            description: "Stop loss price (where you'll exit if trade goes against you)",
                            enumValues: nil
                        )
                    ],
                    required: ["account_value", "risk_percent", "entry_price", "stop_price"]
                )
            )
        )
    }
    
    private func getMarketRegimeTool() -> Tool {
        Tool(
            type: "function",
            function: FunctionDefinition(
                name: "get_market_regime",
                description: "Analyze the overall market regime by checking BTC's 10 SMA vs 20 SMA on daily chart. Returns whether market conditions favor long trades (bullish) or suggest caution (bearish). ALWAYS check this before suggesting swing trade entries.",
                parameters: FunctionParameters(
                    type: "object",
                    properties: [:],
                    required: nil
                )
            )
        )
    }
    
    private func analyzeBreakoutSetupTool() -> Tool {
        Tool(
            type: "function",
            function: FunctionDefinition(
                name: "analyze_breakout_setup",
                description: "Analyze a cryptocurrency for a potential breakout setup using the professional 5-step process: 1) Prior move 30%+, 2) 10/20 SMA inclining, 3) Orderly pullback with tightening range, 4) Volume drying up, 5) Breakout on volume. Returns a score and specific entry/exit levels.",
                parameters: FunctionParameters(
                    type: "object",
                    properties: [
                        "symbol": ParameterProperty(
                            type: "string",
                            description: "The cryptocurrency symbol to analyze (e.g., BTC, ETH, SOL)",
                            enumValues: nil
                        )
                    ],
                    required: ["symbol"]
                )
            )
        )
    }
    
    private func calculateRiskRewardTool() -> Tool {
        Tool(
            type: "function",
            function: FunctionDefinition(
                name: "calculate_risk_reward",
                description: "Calculate the risk:reward ratio for a potential trade. Returns the R:R ratio and whether the trade meets minimum criteria (typically 3:1). Helps determine if a trade setup is worth taking.",
                parameters: FunctionParameters(
                    type: "object",
                    properties: [
                        "entry_price": ParameterProperty(
                            type: "number",
                            description: "Planned entry price",
                            enumValues: nil
                        ),
                        "stop_price": ParameterProperty(
                            type: "number",
                            description: "Stop loss price",
                            enumValues: nil
                        ),
                        "target_price": ParameterProperty(
                            type: "number",
                            description: "Target/take profit price",
                            enumValues: nil
                        )
                    ],
                    required: ["entry_price", "stop_price", "target_price"]
                )
            )
        )
    }
    
    private func analyzeTrendStructureTool() -> Tool {
        Tool(
            type: "function",
            function: FunctionDefinition(
                name: "analyze_trend_structure",
                description: "Analyze the trend structure of a cryptocurrency including MA alignment (10/20/50/200), whether MAs are inclining, support levels from MAs, and optimal entry zones. Use this to assess trend health before suggesting trades.",
                parameters: FunctionParameters(
                    type: "object",
                    properties: [
                        "symbol": ParameterProperty(
                            type: "string",
                            description: "The cryptocurrency symbol to analyze (e.g., BTC, ETH, SOL)",
                            enumValues: nil
                        )
                    ],
                    required: ["symbol"]
                )
            )
        )
    }
    
    private func getPricePredictionTool() -> Tool {
        Tool(
            type: "function",
            function: FunctionDefinition(
                name: "get_price_prediction",
                description: "Generate or retrieve an AI-powered price prediction for a cryptocurrency. Uses technical indicators (RSI, MACD, Stochastic RSI, ADX, Bollinger Bands, MA alignment), market sentiment (Fear & Greed Index), and volume analysis to predict price direction, confidence level, and expected price range. Use this when users ask about price predictions, price outlook, whether to buy/sell, or future price movements.",
                parameters: FunctionParameters(
                    type: "object",
                    properties: [
                        "symbol": ParameterProperty(
                            type: "string",
                            description: "The cryptocurrency symbol to predict (e.g., BTC, ETH, SOL)",
                            enumValues: nil
                        ),
                        "timeframe": ParameterProperty(
                            type: "string",
                            description: "Prediction timeframe: '1h' for 1 hour, '4h' for 4 hours, '1d' for 24 hours, '7d' for 7 days, '30d' for 30 days",
                            enumValues: ["1h", "4h", "1d", "7d", "30d"]
                        )
                    ],
                    required: ["symbol"]
                )
            )
        )
    }
    
    private func getTradingPairPreferencesTool() -> Tool {
        Tool(
            type: "function",
            function: FunctionDefinition(
                name: "get_trading_pair_preferences",
                description: "Get the user's trading pair preferences including favorite pairs, recently traded pairs, preferred exchanges, and preferred quote currency. Use this when making trade recommendations to suggest pairs the user is familiar with and uses their preferred exchange/quote currency.",
                parameters: FunctionParameters(
                    type: "object",
                    properties: [:],
                    required: nil
                )
            )
        )
    }
    
    // MARK: - DeFi & NFT Tool Definitions
    
    private func getDeFiPositionsTool() -> Tool {
        Tool(
            type: "function",
            function: FunctionDefinition(
                name: "get_defi_positions",
                description: "Get the user's DeFi positions across all protocols and chains including lending, liquidity, staking, and yield farming positions. Shows protocol names, position values, APYs, and health factors for lending positions. Requires a connected wallet address.",
                parameters: FunctionParameters(
                    type: "object",
                    properties: [
                        "wallet_address": ParameterProperty(
                            type: "string",
                            description: "The wallet address to check DeFi positions for (0x... for EVM chains)",
                            enumValues: nil
                        ),
                        "chain": ParameterProperty(
                            type: "string",
                            description: "Optional: Filter by specific chain (ethereum, arbitrum, polygon, base, optimism, etc.)",
                            enumValues: nil
                        )
                    ],
                    required: ["wallet_address"]
                )
            )
        )
    }
    
    private func getNFTPortfolioTool() -> Tool {
        Tool(
            type: "function",
            function: FunctionDefinition(
                name: "get_nft_portfolio",
                description: "Get the user's NFT portfolio including collections owned, estimated floor values, rarity scores, and recent sales history. Shows NFTs grouped by collection with total portfolio valuation.",
                parameters: FunctionParameters(
                    type: "object",
                    properties: [
                        "wallet_address": ParameterProperty(
                            type: "string",
                            description: "The wallet address to check NFTs for",
                            enumValues: nil
                        ),
                        "chain": ParameterProperty(
                            type: "string",
                            description: "Optional: Filter by chain (ethereum, polygon, solana). Default checks all.",
                            enumValues: nil
                        )
                    ],
                    required: ["wallet_address"]
                )
            )
        )
    }
    
    private func getDeFiYieldsTool() -> Tool {
        Tool(
            type: "function",
            function: FunctionDefinition(
                name: "get_defi_yields",
                description: "Get current yield opportunities for a specific token across DeFi protocols. Shows APYs for lending, liquidity provision, staking, and yield farming options with risk levels and TVL.",
                parameters: FunctionParameters(
                    type: "object",
                    properties: [
                        "token": ParameterProperty(
                            type: "string",
                            description: "The token symbol to find yield opportunities for (e.g., ETH, USDC, BTC)",
                            enumValues: nil
                        ),
                        "min_apy": ParameterProperty(
                            type: "number",
                            description: "Optional: Minimum APY threshold (default 1%)",
                            enumValues: nil
                        ),
                        "risk_level": ParameterProperty(
                            type: "string",
                            description: "Optional: Filter by risk level (low, medium, high). Low = blue chip protocols, High = newer protocols.",
                            enumValues: ["low", "medium", "high"]
                        )
                    ],
                    required: ["token"]
                )
            )
        )
    }
    
    private func getChainAnalysisTool() -> Tool {
        Tool(
            type: "function",
            function: FunctionDefinition(
                name: "get_chain_analysis",
                description: "Analyze a wallet's activity and holdings on a specific blockchain. Shows token balances, transaction history summary, DeFi positions, and NFTs on that chain.",
                parameters: FunctionParameters(
                    type: "object",
                    properties: [
                        "wallet_address": ParameterProperty(
                            type: "string",
                            description: "The wallet address to analyze",
                            enumValues: nil
                        ),
                        "chain": ParameterProperty(
                            type: "string",
                            description: "The blockchain to analyze (ethereum, arbitrum, polygon, base, optimism, solana, etc.)",
                            enumValues: nil
                        )
                    ],
                    required: ["wallet_address", "chain"]
                )
            )
        )
    }
    
    private func getSupportedChainsTool() -> Tool {
        Tool(
            type: "function",
            function: FunctionDefinition(
                name: "get_supported_chains",
                description: "Get the list of all supported blockchains in CryptoSage including Layer 1s (Ethereum, Bitcoin, Solana, etc.) and Layer 2s (Arbitrum, Optimism, Base, etc.). Shows chain names, native tokens, and chain IDs.",
                parameters: FunctionParameters(
                    type: "object",
                    properties: [:],
                    required: nil
                )
            )
        )
    }
    
    private func getSupportedProtocolsTool() -> Tool {
        Tool(
            type: "function",
            function: FunctionDefinition(
                name: "get_supported_protocols",
                description: "Get the list of supported DeFi protocols organized by category (DEX, Lending, Staking, Yield). Shows protocol names, chains, and categories. Use this to help users understand which protocols are tracked.",
                parameters: FunctionParameters(
                    type: "object",
                    properties: [
                        "category": ParameterProperty(
                            type: "string",
                            description: "Optional: Filter by category (dex, lending, staking, yield, derivatives)",
                            enumValues: ["dex", "lending", "staking", "yield", "derivatives"]
                        ),
                        "chain": ParameterProperty(
                            type: "string",
                            description: "Optional: Filter by chain",
                            enumValues: nil
                        )
                    ],
                    required: nil
                )
            )
        )
    }
    
    // MARK: - Web Search & URL Reading Tools
    
    private func webSearchTool() -> Tool {
        Tool(
            type: "function",
            function: FunctionDefinition(
                name: "web_search",
                description: "Search the internet for real-time information about any topic. Use this when the user asks about current events, news, market analysis, regulatory updates, FOMC meetings, or any information that may not be in your training data. Returns relevant results with summaries and source URLs.",
                parameters: FunctionParameters(
                    type: "object",
                    properties: [
                        "query": ParameterProperty(
                            type: "string",
                            description: "The search query to look up on the internet",
                            enumValues: nil
                        )
                    ],
                    required: ["query"]
                )
            )
        )
    }
    
    private func readURLTool() -> Tool {
        Tool(
            type: "function",
            function: FunctionDefinition(
                name: "read_url",
                description: "Fetch and read the content of a web page or news article. Use when the user shares a URL, asks about a specific article, or you need to read the full content of a page found via web_search. Returns the article title, source, and extracted text content.",
                parameters: FunctionParameters(
                    type: "object",
                    properties: [
                        "url": ParameterProperty(
                            type: "string",
                            description: "The full URL of the web page or article to read",
                            enumValues: nil
                        )
                    ],
                    required: ["url"]
                )
            )
        )
    }
    
    // MARK: - Function Execution
    
    /// Execute a function call and return the result as a string
    func executeFunction(name: String, arguments: String) async -> String {
        // Parse arguments JSON
        guard let argsData = arguments.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] else {
            return "Error: Could not parse function arguments"
        }
        
        switch name {
        case "get_price":
            return await executeGetPrice(args: args)
        case "get_portfolio_summary":
            return await executeGetPortfolioSummary()
        case "get_portfolio_allocation":
            return await executeGetPortfolioAllocation()
        case "analyze_portfolio_risk":
            return await executeAnalyzePortfolioRisk()
        case "get_market_stats":
            return await executeGetMarketStats()
        case "get_market_sentiment":
            return await executeGetMarketSentiment()
        case "get_recent_news":
            return await executeGetRecentNews(args: args)
        case "get_technicals":
            return await executeGetTechnicals(args: args)
        case "get_top_coins":
            return await executeGetTopCoins(args: args)
        case "get_top_movers":
            return await executeGetTopMovers(args: args)
        case "get_news":
            return await executeGetNews(args: args)
        case "compare_coins":
            return await executeCompareCoins(args: args)
        case "suggest_rebalance":
            return await executeSuggestRebalance(args: args)
        case "create_alert":
            return await executeCreateAlert(args: args)
        case "suggest_alert":
            return await executeSuggestAlert(args: args)
        // Professional Swing Trading Functions
        case "calculate_position_size":
            return await executeCalculatePositionSize(args: args)
        case "get_market_regime":
            return await executeGetMarketRegime()
        case "analyze_breakout_setup":
            return await executeAnalyzeBreakoutSetup(args: args)
        case "calculate_risk_reward":
            return await executeCalculateRiskReward(args: args)
        case "analyze_trend_structure":
            return await executeAnalyzeTrendStructure(args: args)
        case "get_price_prediction":
            return await executeGetPricePrediction(args: args)
        case "get_trading_pair_preferences":
            return await executeGetTradingPairPreferences()
        // DeFi & NFT Functions
        case "get_defi_positions":
            return await executeGetDeFiPositions(args: args)
        case "get_nft_portfolio":
            return await executeGetNFTPortfolio(args: args)
        case "get_defi_yields":
            return await executeGetDeFiYields(args: args)
        case "get_chain_analysis":
            return await executeGetChainAnalysis(args: args)
        case "get_supported_chains":
            return await executeGetSupportedChains()
        case "get_supported_protocols":
            return await executeGetSupportedProtocols(args: args)
        // Web Search & URL Reading
        case "web_search":
            return await executeWebSearch(args: args)
        case "read_url":
            return await executeReadURL(args: args)
        default:
            return "Error: Unknown function '\(name)'"
        }
    }
    
    // MARK: - Function Implementations
    
    private func executeGetPrice(args: [String: Any]) async -> String {
        guard let symbol = args["symbol"] as? String else {
            return "Error: Missing 'symbol' parameter"
        }
        
        let upperSymbol = symbol.uppercased()
        let marketVM = MarketViewModel.shared
        
        // Try to find in current coins from MarketViewModel
        if let coin = marketVM.allCoins.first(where: { $0.symbol.uppercased() == upperSymbol }) {
            return formatCoinPrice(coin)
        }
        
        // Try watchlist coins as fallback
        if let coin = marketVM.watchlistCoins.first(where: { $0.symbol.uppercased() == upperSymbol }) {
            return formatCoinPrice(coin)
        }
        
        // Not found
        return "Price data not available for \(upperSymbol). The coin may not be in the top coins list or the symbol may be incorrect."
    }
    
    private func executeGetPortfolioSummary() async -> String {
        guard !portfolioHoldings.isEmpty else {
            return "No holdings in portfolio. The user hasn't added any crypto assets yet."
        }
        
        var result: [String: Any] = [:]
        
        // Sort holdings by value
        let sortedHoldings = portfolioHoldings.sorted { $0.currentValue > $1.currentValue }
        
        // Build holdings array
        var holdingsData: [[String: Any]] = []
        var totalCostBasis: Double = 0
        var totalPL: Double = 0
        
        for holding in sortedHoldings {
            let costBasis = holding.costBasis * holding.quantity
            let pl = holding.currentValue - costBasis
            let plPercent = costBasis > 0 ? (pl / costBasis) * 100 : 0
            
            totalCostBasis += costBasis
            totalPL += pl
            
            let allocation = portfolioTotalValue > 0 ? (holding.currentValue / portfolioTotalValue) * 100 : 0
            
            holdingsData.append([
                "symbol": holding.coinSymbol,
                "name": holding.coinName,
                "quantity": holding.quantity,
                "current_price": holding.currentPrice,
                "current_value": holding.currentValue,
                "cost_basis_per_unit": holding.costBasis,
                "total_cost": costBasis,
                "profit_loss": pl,
                "profit_loss_percent": plPercent,
                "daily_change_percent": holding.dailyChange,
                "allocation_percent": allocation,
                "is_favorite": holding.isFavorite
            ])
        }
        
        result["holdings"] = holdingsData
        result["total_value"] = portfolioTotalValue
        result["total_cost_basis"] = totalCostBasis
        result["total_profit_loss"] = totalPL
        result["total_profit_loss_percent"] = totalCostBasis > 0 ? (totalPL / totalCostBasis) * 100 : 0
        result["holdings_count"] = portfolioHoldings.count
        result["timestamp"] = Self._isoFormatter.string(from: Date())
        
        // Add risk metrics
        if let topHolding = sortedHoldings.first, portfolioTotalValue > 0 {
            let topConcentration = (topHolding.currentValue / portfolioTotalValue) * 100
            result["top_holding_symbol"] = topHolding.coinSymbol
            result["top_holding_concentration"] = topConcentration
            result["concentration_warning"] = topConcentration > 40 ? "High concentration in \(topHolding.coinSymbol)" : nil
        }
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return "Portfolio: \(portfolioHoldings.count) holdings, total value \(formatCurrency(portfolioTotalValue))"
    }
    
    private func executeGetMarketStats() async -> String {
        let marketVM = MarketViewModel.shared
        
        var result: [String: Any] = [:]
        
        if let marketCap = marketVM.globalMarketCap, marketCap > 0 {
            result["total_market_cap_usd"] = marketCap
            result["market_cap_formatted"] = formatLargeCurrency(marketCap)
        }
        
        if let volume = marketVM.globalVolume24h, volume > 0 {
            result["total_volume_24h_usd"] = volume
            result["volume_24h_formatted"] = formatLargeCurrency(volume)
        }
        
        if let btcDom = marketVM.btcDominance, btcDom > 0 {
            result["btc_dominance_percent"] = btcDom
        }
        
        if let ethDom = marketVM.ethDominance, ethDom > 0 {
            result["eth_dominance_percent"] = ethDom
        }
        
        // Add top coin prices for context
        if let btc = marketVM.allCoins.first(where: { $0.symbol.uppercased() == "BTC" }) {
            result["btc_price"] = btc.priceUsd ?? 0
            result["btc_24h_change"] = btc.priceChangePercentage24hInCurrency ?? 0
        }
        
        if let eth = marketVM.allCoins.first(where: { $0.symbol.uppercased() == "ETH" }) {
            result["eth_price"] = eth.priceUsd ?? 0
            result["eth_24h_change"] = eth.priceChangePercentage24hInCurrency ?? 0
        }
        
        result["total_coins_tracked"] = marketVM.allCoins.count
        result["timestamp"] = Self._isoFormatter.string(from: Date())
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        let capStr = formatLargeCurrency(marketVM.globalMarketCap ?? 0)
        let domStr = String(format: "%.1f", marketVM.btcDominance ?? 0)
        return "Market stats: Cap \(capStr), BTC Dom \(domStr)%"
    }
    
    private func executeGetMarketSentiment() async -> String {
        let sentimentVM = ExtendedFearGreedViewModel.shared
        
        var result: [String: Any] = [:]
        
        // Current sentiment value and classification
        if let currentValue = sentimentVM.currentValue {
            result["score"] = currentValue
            result["score_out_of"] = 100
        }
        
        if let classification = sentimentVM.currentClassificationKey {
            result["classification"] = classification.capitalized
            
            // Add interpretation for the AI
            switch classification {
            case "extreme fear":
                result["interpretation"] = "Market is in extreme fear - historically a good buying opportunity for long-term investors. Risk is elevated but valuations may be depressed."
            case "fear":
                result["interpretation"] = "Market sentiment is fearful - consider accumulating quality assets. Watch for signs of stabilization before adding large positions."
            case "neutral":
                result["interpretation"] = "Market sentiment is neutral - no strong directional bias. Focus on individual asset fundamentals rather than broad market timing."
            case "greed":
                result["interpretation"] = "Market sentiment is greedy - consider taking some profits or tightening stop losses. New entries should be more selective."
            case "extreme greed":
                result["interpretation"] = "Market is in extreme greed - historically a time for caution. Consider reducing exposure or avoiding new positions. High risk of correction."
            default:
                result["interpretation"] = "Sentiment data updating."
            }
        }
        
        // Trend data
        if let delta1d = sentimentVM.delta1d {
            result["change_24h"] = delta1d
            result["trend_24h"] = delta1d > 0 ? "rising" : (delta1d < 0 ? "falling" : "flat")
        }
        
        if let delta7d = sentimentVM.delta7d {
            result["change_7d"] = delta7d
            result["trend_7d"] = delta7d > 0 ? "rising" : (delta7d < 0 ? "falling" : "flat")
        }
        
        // Overall bias
        let bias = sentimentVM.bias
        result["market_bias"] = bias.rawValue
        
        // AI observation text
        result["ai_observation"] = sentimentVM.aiObservationText
        
        result["timestamp"] = Self._isoFormatter.string(from: Date())
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return "Market sentiment: \(sentimentVM.currentValue ?? 0)/100 (\(sentimentVM.currentClassificationKey?.capitalized ?? "Unknown"))"
    }
    
    private func executeGetRecentNews(args: [String: Any]) async -> String {
        let newsVM = CryptoNewsFeedViewModel.shared
        let count = min(args["count"] as? Int ?? 5, 10)
        
        let articles = Array(newsVM.articles.prefix(count))
        
        guard !articles.isEmpty else {
            return "No recent news available. The news feed may still be loading."
        }
        
        var newsItems: [[String: Any]] = []
        
        for article in articles {
            var item: [String: Any] = [
                "title": article.title,
                "source": article.sourceName,
                "published_at": Self._isoFormatter.string(from: article.publishedAt)
            ]
            
            if let description = article.description, !description.isEmpty {
                // Truncate long descriptions
                let truncated = description.count > 200 ? String(description.prefix(197)) + "..." : description
                item["summary"] = truncated
            }
            
            newsItems.append(item)
        }
        
        let result: [String: Any] = [
            "articles": newsItems,
            "count": newsItems.count,
            "total_available": newsVM.articles.count,
            "timestamp": Self._isoFormatter.string(from: Date())
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        // Fallback text format
        var text = "Recent Crypto News:\n"
        for article in articles {
            text += "- [\(article.sourceName)] \(article.title)\n"
        }
        return text
    }
    
    private func executeGetTechnicals(args: [String: Any]) async -> String {
        guard let symbol = args["symbol"] as? String else {
            return "Error: Missing 'symbol' parameter"
        }
        
        let upperSymbol = symbol.uppercased()
        let marketVM = MarketViewModel.shared
        
        // Find the coin
        guard let coin = marketVM.allCoins.first(where: { $0.symbol.uppercased() == upperSymbol }) else {
            return "Technical data not available for \(upperSymbol)"
        }
        
        // Build technical summary from available data
        var result: [String: Any] = [
            "symbol": upperSymbol,
            "name": coin.name,
            "price_usd": coin.priceUsd ?? 0
        ]
        
        // Price changes
        if let change1h = coin.priceChangePercentage1hInCurrency {
            result["change_1h_percent"] = change1h
        }
        if let change24h = coin.priceChangePercentage24hInCurrency {
            result["change_24h_percent"] = change24h
        }
        if let change7d = coin.priceChangePercentage7dInCurrency {
            result["change_7d_percent"] = change7d
        }
        
        // Sparkline trend analysis
        if !coin.sparklineIn7d.isEmpty {
            let sparkline = coin.sparklineIn7d
            let recent = Array(sparkline.suffix(24)) // Last 24 points (approx 1 day)
            
            if let first = recent.first, let last = recent.last, first > 0 {
                let recentTrend = ((last - first) / first) * 100
                result["recent_trend_percent"] = recentTrend
                result["trend_direction"] = recentTrend > 1 ? "bullish" : (recentTrend < -1 ? "bearish" : "neutral")
            }
            
            // Volatility estimate
            if recent.count > 2 {
                let avg = recent.reduce(0, +) / Double(recent.count)
                let variance = recent.map { pow($0 - avg, 2) }.reduce(0, +) / Double(recent.count)
                let stdDev = sqrt(variance)
                let volatility = (stdDev / avg) * 100
                result["volatility_estimate"] = String(format: "%.2f", volatility) + "%"
            }
        }
        
        // Market cap rank
        if let rank = coin.marketCapRank {
            result["market_cap_rank"] = rank
        }
        
        // Simple sentiment based on changes
        let change24h = coin.priceChangePercentage24hInCurrency ?? 0
        let change7d = coin.priceChangePercentage7dInCurrency ?? 0
        
        var sentimentScore = 0
        if change24h > 5 { sentimentScore += 2 }
        else if change24h > 0 { sentimentScore += 1 }
        else if change24h < -5 { sentimentScore -= 2 }
        else if change24h < 0 { sentimentScore -= 1 }
        
        if change7d > 10 { sentimentScore += 2 }
        else if change7d > 0 { sentimentScore += 1 }
        else if change7d < -10 { sentimentScore -= 2 }
        else if change7d < 0 { sentimentScore -= 1 }
        
        result["sentiment_score"] = sentimentScore
        result["sentiment"] = sentimentScore >= 2 ? "bullish" : (sentimentScore <= -2 ? "bearish" : "neutral")
        
        result["note"] = "This is derived technical data based on price action. For comprehensive TA, use dedicated analysis tools."
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return "Technical data for \(upperSymbol): Price $\(coin.priceUsd ?? 0), 24h: \(change24h)%, 7d: \(change7d)%"
    }
    
    private func executeGetTopCoins(args: [String: Any]) async -> String {
        let count = min(args["count"] as? Int ?? 10, 50)
        let marketVM = MarketViewModel.shared
        
        let topCoins = Array(marketVM.allCoins.prefix(count))
        
        guard !topCoins.isEmpty else {
            return "No market data available at the moment."
        }
        
        var results: [[String: Any]] = []
        
        for (index, coin) in topCoins.enumerated() {
            var coinData: [String: Any] = [
                "rank": index + 1,
                "symbol": coin.symbol.uppercased(),
                "name": coin.name,
                "price_usd": coin.priceUsd ?? 0
            ]
            
            if let change24h = coin.priceChangePercentage24hInCurrency {
                coinData["change_24h_percent"] = change24h
            }
            
            if let marketCap = coin.marketCap {
                coinData["market_cap_usd"] = marketCap
            }
            
            results.append(coinData)
        }
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: ["top_coins": results, "count": results.count], options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        // Fallback text format
        var text = "Top \(count) Cryptocurrencies:\n"
        for (i, coin) in topCoins.enumerated() {
            let price = formatCurrency(coin.priceUsd ?? 0)
            let change = coin.priceChangePercentage24hInCurrency ?? 0
            let changeStr = change >= 0 ? "+\(String(format: "%.2f", change))%" : "\(String(format: "%.2f", change))%"
            text += "\(i + 1). \(coin.symbol.uppercased()): \(price) (\(changeStr))\n"
        }
        return text
    }
    
    private func executeGetNews(args: [String: Any]) async -> String {
        // News would typically come from CryptoNewsFeedViewModel
        // For now, return a placeholder indicating the feature
        let topic = args["topic"] as? String
        
        return """
        News functionality is available in the app's News section. \
        \(topic != nil ? "For \(topic!) news, " : "")Please refer to the News tab for the latest cryptocurrency headlines and articles. \
        The app aggregates news from multiple sources including CoinDesk, CryptoSlate, and other major crypto news outlets.
        """
    }
    
    private func executeCompareCoins(args: [String: Any]) async -> String {
        guard let symbol1 = args["symbol1"] as? String,
              let symbol2 = args["symbol2"] as? String else {
            return "Error: Missing symbol parameters"
        }
        
        let upper1 = symbol1.uppercased()
        let upper2 = symbol2.uppercased()
        let marketVM = MarketViewModel.shared
        
        guard let coin1 = marketVM.allCoins.first(where: { $0.symbol.uppercased() == upper1 }) else {
            return "Could not find data for \(upper1)"
        }
        
        guard let coin2 = marketVM.allCoins.first(where: { $0.symbol.uppercased() == upper2 }) else {
            return "Could not find data for \(upper2)"
        }
        
        var comparison: [String: Any] = [:]
        let coin1PriceUSD: Double = coin1.priceUsd ?? 0
        let coin1MarketCap: Double = coin1.marketCap ?? 0
        let coin1Change24h: Double = coin1.priceChangePercentage24hInCurrency ?? 0
        let coin1Change7d: Double = coin1.priceChangePercentage7dInCurrency ?? 0
        let coin1Rank: Int = coin1.marketCapRank ?? 0
        
        let coin2PriceUSD: Double = coin2.priceUsd ?? 0
        let coin2MarketCap: Double = coin2.marketCap ?? 0
        let coin2Change24h: Double = coin2.priceChangePercentage24hInCurrency ?? 0
        let coin2Change7d: Double = coin2.priceChangePercentage7dInCurrency ?? 0
        let coin2Rank: Int = coin2.marketCapRank ?? 0
        
        // Coin 1 data
        comparison["coin1"] = [
            "symbol": upper1,
            "name": coin1.name,
            "price_usd": coin1PriceUSD,
            "market_cap": coin1MarketCap,
            "change_24h": coin1Change24h,
            "change_7d": coin1Change7d,
            "rank": coin1Rank
        ]
        
        // Coin 2 data
        comparison["coin2"] = [
            "symbol": upper2,
            "name": coin2.name,
            "price_usd": coin2PriceUSD,
            "market_cap": coin2MarketCap,
            "change_24h": coin2Change24h,
            "change_7d": coin2Change7d,
            "rank": coin2Rank
        ]
        
        // Comparisons
        if let cap1 = coin1.marketCap, let cap2 = coin2.marketCap, cap2 > 0 {
            comparison["market_cap_ratio"] = "\(upper1) is \(String(format: "%.2f", cap1 / cap2))x \(upper2)"
        }
        
        let change1_24h = coin1.priceChangePercentage24hInCurrency ?? 0
        let change2_24h = coin2.priceChangePercentage24hInCurrency ?? 0
        comparison["better_24h_performance"] = change1_24h > change2_24h ? upper1 : upper2
        
        let change1_7d = coin1.priceChangePercentage7dInCurrency ?? 0
        let change2_7d = coin2.priceChangePercentage7dInCurrency ?? 0
        comparison["better_7d_performance"] = change1_7d > change2_7d ? upper1 : upper2
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: comparison, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return "Comparison data for \(upper1) vs \(upper2) generated."
    }
    
    private func executeGetPortfolioAllocation() async -> String {
        guard !portfolioHoldings.isEmpty else {
            return "No holdings to analyze. The user's portfolio is empty."
        }
        
        let sortedHoldings = portfolioHoldings.sorted { $0.currentValue > $1.currentValue }
        var allocations: [[String: Any]] = []
        
        for holding in sortedHoldings {
            let allocation = portfolioTotalValue > 0 ? (holding.currentValue / portfolioTotalValue) * 100 : 0
            allocations.append([
                "symbol": holding.coinSymbol,
                "name": holding.coinName,
                "value_usd": holding.currentValue,
                "allocation_percent": round(allocation * 100) / 100,
                "quantity": holding.quantity
            ])
        }
        
        var result: [String: Any] = [
            "allocations": allocations,
            "total_value": portfolioTotalValue,
            "holdings_count": portfolioHoldings.count
        ]
        
        // Calculate diversification score (higher = more diversified)
        let topAllocation = portfolioTotalValue > 0 ? (sortedHoldings.first?.currentValue ?? 0) / portfolioTotalValue * 100 : 0
        let diversificationScore = max(0, 100 - topAllocation)
        result["diversification_score"] = round(diversificationScore)
        result["top_holding"] = sortedHoldings.first?.coinSymbol ?? "N/A"
        result["top_holding_percent"] = round(topAllocation * 100) / 100
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return "Portfolio allocation analysis complete."
    }
    
    private func executeAnalyzePortfolioRisk() async -> String {
        guard !portfolioHoldings.isEmpty else {
            return "No holdings to analyze. The user's portfolio is empty."
        }
        
        let sortedHoldings = portfolioHoldings.sorted { $0.currentValue > $1.currentValue }
        var risks: [[String: Any]] = []
        var riskScore = 0 // 0-100, higher = riskier
        
        // Check concentration risk
        if let topHolding = sortedHoldings.first {
            let topPercent = portfolioTotalValue > 0 ? (topHolding.currentValue / portfolioTotalValue) * 100 : 0
            if topPercent > 50 {
                risks.append([
                    "type": "HIGH_CONCENTRATION",
                    "severity": "high",
                    "description": "\(topHolding.coinSymbol) is \(String(format: "%.1f", topPercent))% of portfolio - very concentrated",
                    "suggestion": "Consider diversifying into other assets to reduce single-asset risk"
                ])
                riskScore += 30
            } else if topPercent > 30 {
                risks.append([
                    "type": "MODERATE_CONCENTRATION",
                    "severity": "medium",
                    "description": "\(topHolding.coinSymbol) is \(String(format: "%.1f", topPercent))% of portfolio",
                    "suggestion": "Monitor this position closely"
                ])
                riskScore += 15
            }
        }
        
        // Check for high volatility positions
        for holding in portfolioHoldings {
            let dailyChange = abs(holding.dailyChange)
            if dailyChange > 10 {
                risks.append([
                    "type": "HIGH_VOLATILITY",
                    "severity": "high",
                    "asset": holding.coinSymbol,
                    "description": "\(holding.coinSymbol) moved \(String(format: "%.1f", dailyChange))% in 24h - high volatility",
                    "suggestion": "Consider position sizing appropriate for volatile assets"
                ])
                riskScore += 10
            }
        }
        
        // Check diversification
        if portfolioHoldings.count < 3 {
            risks.append([
                "type": "LOW_DIVERSIFICATION",
                "severity": "medium",
                "description": "Only \(portfolioHoldings.count) asset(s) in portfolio",
                "suggestion": "Consider adding more assets to spread risk"
            ])
            riskScore += 20
        }
        
        // Check for stablecoin allocation
        let stablecoins = ["USDT", "USDC", "DAI", "BUSD", "TUSD"]
        let stablecoinValue = portfolioHoldings.filter { stablecoins.contains($0.coinSymbol.uppercased()) }.reduce(0) { $0 + $1.currentValue }
        let stablecoinPercent = portfolioTotalValue > 0 ? (stablecoinValue / portfolioTotalValue) * 100 : 0
        
        if stablecoinPercent < 5 && portfolioTotalValue > 1000 {
            risks.append([
                "type": "NO_STABLE_ALLOCATION",
                "severity": "low",
                "description": "No stablecoin allocation for dry powder",
                "suggestion": "Consider keeping some stablecoins to buy dips"
            ])
            riskScore += 5
        }
        
        let overallRisk = riskScore > 50 ? "HIGH" : (riskScore > 25 ? "MEDIUM" : "LOW")
        
        let result: [String: Any] = [
            "risk_score": min(100, riskScore),
            "overall_risk": overallRisk,
            "risks_found": risks.count,
            "risk_details": risks,
            "stablecoin_percent": round(stablecoinPercent * 100) / 100,
            "holdings_count": portfolioHoldings.count,
            "total_value": portfolioTotalValue
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return "Risk analysis complete. Risk level: \(overallRisk)"
    }
    
    private func executeGetTopMovers(args: [String: Any]) async -> String {
        let count = min(args["count"] as? Int ?? 5, 20)
        let marketVM = MarketViewModel.shared
        
        let sortedByGain = marketVM.allCoins.sorted { ($0.priceChangePercentage24hInCurrency ?? 0) > ($1.priceChangePercentage24hInCurrency ?? 0) }
        let sortedByLoss = marketVM.allCoins.sorted { ($0.priceChangePercentage24hInCurrency ?? 0) < ($1.priceChangePercentage24hInCurrency ?? 0) }
        
        let topGainers = Array(sortedByGain.prefix(count))
        let topLosers = Array(sortedByLoss.prefix(count))
        
        var gainersData: [[String: Any]] = []
        for coin in topGainers {
            gainersData.append([
                "symbol": coin.symbol.uppercased(),
                "name": coin.name,
                "price_usd": coin.priceUsd ?? 0,
                "change_24h_percent": coin.priceChangePercentage24hInCurrency ?? 0
            ])
        }
        
        var losersData: [[String: Any]] = []
        for coin in topLosers {
            losersData.append([
                "symbol": coin.symbol.uppercased(),
                "name": coin.name,
                "price_usd": coin.priceUsd ?? 0,
                "change_24h_percent": coin.priceChangePercentage24hInCurrency ?? 0
            ])
        }
        
        let result: [String: Any] = [
            "top_gainers": gainersData,
            "top_losers": losersData,
            "timestamp": Self._isoFormatter.string(from: Date())
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return "Top movers retrieved."
    }
    
    private func executeSuggestRebalance(args: [String: Any]) async -> String {
        guard !portfolioHoldings.isEmpty else {
            return "No holdings to rebalance. The user's portfolio is empty."
        }
        
        let targetBTC = args["target_btc_percent"] as? Double ?? 40.0
        let targetETH = args["target_eth_percent"] as? Double ?? 30.0
        let targetAltcoins = 100.0 - targetBTC - targetETH
        
        // Current allocations
        let btcHolding = portfolioHoldings.first { $0.coinSymbol.uppercased() == "BTC" }
        let ethHolding = portfolioHoldings.first { $0.coinSymbol.uppercased() == "ETH" }
        
        let currentBTC = portfolioTotalValue > 0 ? ((btcHolding?.currentValue ?? 0) / portfolioTotalValue) * 100 : 0
        let currentETH = portfolioTotalValue > 0 ? ((ethHolding?.currentValue ?? 0) / portfolioTotalValue) * 100 : 0
        let currentAltcoins = 100.0 - currentBTC - currentETH
        
        var suggestions: [[String: Any]] = []
        
        // BTC suggestions
        let btcDiff = targetBTC - currentBTC
        if abs(btcDiff) > 5 {
            let action = btcDiff > 0 ? "BUY" : "SELL"
            let amount = abs(btcDiff / 100 * portfolioTotalValue)
            suggestions.append([
                "asset": "BTC",
                "action": action,
                "reason": "Current: \(String(format: "%.1f", currentBTC))%, Target: \(String(format: "%.1f", targetBTC))%",
                "suggested_amount_usd": round(amount * 100) / 100,
                "priority": abs(btcDiff) > 15 ? "high" : "medium"
            ])
        }
        
        // ETH suggestions
        let ethDiff = targetETH - currentETH
        if abs(ethDiff) > 5 {
            let action = ethDiff > 0 ? "BUY" : "SELL"
            let amount = abs(ethDiff / 100 * portfolioTotalValue)
            suggestions.append([
                "asset": "ETH",
                "action": action,
                "reason": "Current: \(String(format: "%.1f", currentETH))%, Target: \(String(format: "%.1f", targetETH))%",
                "suggested_amount_usd": round(amount * 100) / 100,
                "priority": abs(ethDiff) > 15 ? "high" : "medium"
            ])
        }
        
        let result: [String: Any] = [
            "current_allocation": [
                "BTC": round(currentBTC * 100) / 100,
                "ETH": round(currentETH * 100) / 100,
                "Altcoins": round(currentAltcoins * 100) / 100
            ],
            "target_allocation": [
                "BTC": targetBTC,
                "ETH": targetETH,
                "Altcoins": targetAltcoins
            ],
            "suggestions": suggestions,
            "suggestions_count": suggestions.count,
            "portfolio_value": portfolioTotalValue,
            "note": "These are suggestions only. Always do your own research before trading."
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return "Rebalancing suggestions generated."
    }
    
    private func executeCreateAlert(args: [String: Any]) async -> String {
        guard let symbol = args["symbol"] as? String else {
            return "Error: Missing 'symbol' parameter"
        }
        guard let targetPrice = args["target_price"] as? Double else {
            return "Error: Missing 'target_price' parameter"
        }
        guard let directionStr = args["direction"] as? String else {
            return "Error: Missing 'direction' parameter (must be 'above' or 'below')"
        }
        
        let isAbove = directionStr.lowercased() == "above"
        let enableAI = args["enable_ai_features"] as? Bool ?? false
        
        let upperSymbol = symbol.uppercased()
        let formattedSymbol = upperSymbol.hasSuffix("USDT") ? upperSymbol : "\(upperSymbol)USDT"
        
        // Get current price for context
        let marketVM = MarketViewModel.shared
        let currentPrice = marketVM.allCoins.first(where: { $0.symbol.uppercased() == upperSymbol })?.priceUsd
        
        // Create the alert via NotificationsManager
        NotificationsManager.shared.addAlertWithAI(
            symbol: formattedSymbol,
            threshold: targetPrice,
            isAbove: isAbove,
            conditionType: isAbove ? .priceAbove : .priceBelow,
            enablePush: true,
            enableEmail: false,
            enableTelegram: false,
            enableSentimentAnalysis: enableAI,
            enableSmartTiming: enableAI,
            enableAIVolumeSpike: enableAI,
            frequency: .oneTime
        )
        
        var result: [String: Any] = [
            "status": "success",
            "alert_created": true,
            "symbol": formattedSymbol,
            "target_price": targetPrice,
            "direction": directionStr,
            "ai_features_enabled": enableAI
        ]
        
        if let price = currentPrice, price > 0 {
            result["current_price"] = price
            let distance = abs(price - targetPrice)
            let percentDistance = (distance / price) * 100
            result["distance_percent"] = String(format: "%.2f", percentDistance)
        }
        
        result["message"] = "Alert created! You'll be notified when \(upperSymbol) goes \(directionStr) $\(String(format: "%.2f", targetPrice))"
        
        if enableAI {
            result["ai_note"] = "AI features enabled: sentiment analysis, smart timing, and volume spike detection are active for this alert."
        }
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return "Alert created for \(formattedSymbol) at $\(targetPrice) (\(directionStr))"
    }
    
    private func executeSuggestAlert(args: [String: Any]) async -> String {
        guard let symbol = args["symbol"] as? String else {
            return "Error: Missing 'symbol' parameter"
        }
        
        let context = args["context"] as? String ?? ""
        let upperSymbol = symbol.uppercased()
        let marketVM = MarketViewModel.shared
        
        // Find the coin
        guard let coin = marketVM.allCoins.first(where: { $0.symbol.uppercased() == upperSymbol }) else {
            return "Could not find market data for \(upperSymbol) to suggest an alert"
        }
        
        guard let currentPrice = coin.priceUsd, currentPrice > 0 else {
            return "Price data not available for \(upperSymbol)"
        }
        
        // Analyze the coin to suggest appropriate alerts
        let change24h = coin.priceChangePercentage24hInCurrency ?? 0
        let change7d = coin.priceChangePercentage7dInCurrency ?? 0
        
        var suggestions: [[String: Any]] = []
        var analysisNotes: [String] = []
        
        // Determine market trend
        let isBullish = change24h > 2 && change7d > 5
        let isBearish = change24h < -2 && change7d < -5
        let isVolatile = abs(change24h) > 5
        
        if isBullish {
            analysisNotes.append("\(upperSymbol) is showing bullish momentum (+\(String(format: "%.1f", change24h))% 24h)")
            
            // Suggest a take-profit alert
            let takeProfitTarget = currentPrice * 1.10 // 10% above
            suggestions.append([
                "type": "take_profit",
                "direction": "above",
                "target_price": round(takeProfitTarget * 100) / 100,
                "reason": "Take profit if rally continues (+10% from current)",
                "recommended_ai": true
            ])
            
            // Suggest a stop-loss alert
            let stopLossTarget = currentPrice * 0.95 // 5% below
            suggestions.append([
                "type": "stop_loss",
                "direction": "below",
                "target_price": round(stopLossTarget * 100) / 100,
                "reason": "Protect gains if trend reverses",
                "recommended_ai": false
            ])
            
        } else if isBearish {
            analysisNotes.append("\(upperSymbol) is showing bearish momentum (\(String(format: "%.1f", change24h))% 24h)")
            
            // Suggest a dip-buy alert
            let dipBuyTarget = currentPrice * 0.90 // 10% below
            suggestions.append([
                "type": "dip_buy",
                "direction": "below",
                "target_price": round(dipBuyTarget * 100) / 100,
                "reason": "Potential buying opportunity if dip continues",
                "recommended_ai": true
            ])
            
            // Suggest a recovery alert
            let recoveryTarget = currentPrice * 1.05 // 5% above
            suggestions.append([
                "type": "recovery",
                "direction": "above",
                "target_price": round(recoveryTarget * 100) / 100,
                "reason": "Alert when trend reverses upward",
                "recommended_ai": false
            ])
            
        } else {
            analysisNotes.append("\(upperSymbol) is ranging with moderate movement")
            
            // Suggest breakout alerts both directions
            let breakoutUp = currentPrice * 1.05
            let breakoutDown = currentPrice * 0.95
            
            suggestions.append([
                "type": "breakout_up",
                "direction": "above",
                "target_price": round(breakoutUp * 100) / 100,
                "reason": "Catch upward breakout",
                "recommended_ai": true
            ])
            
            suggestions.append([
                "type": "breakout_down",
                "direction": "below",
                "target_price": round(breakoutDown * 100) / 100,
                "reason": "Catch downward breakout",
                "recommended_ai": false
            ])
        }
        
        if isVolatile {
            analysisNotes.append("High volatility detected - consider using AI-powered alerts for smarter timing")
        }
        
        // Get sentiment context
        let sentimentVM = ExtendedFearGreedViewModel.shared
        if let sentimentValue = sentimentVM.currentValue,
           let classification = sentimentVM.currentClassificationKey {
            analysisNotes.append("Market sentiment: \(classification.capitalized) (\(sentimentValue)/100)")
        }
        
        var result: [String: Any] = [
            "symbol": upperSymbol,
            "current_price": currentPrice,
            "change_24h_percent": change24h,
            "change_7d_percent": change7d,
            "analysis": analysisNotes,
            "suggested_alerts": suggestions,
            "ai_recommendation": "For volatile markets, enable AI-powered alerts which include sentiment analysis, smart timing, and volume spike detection.",
            "how_to_create": "To create an alert, you can say 'Create an alert for \(upperSymbol) at $[price] [above/below]' or I can create one for you."
        ]
        if !context.isEmpty {
            result["context_provided"] = context
        }
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return "Alert suggestions generated for \(upperSymbol)"
    }
    
    // MARK: - Professional Swing Trading Function Implementations
    
    private func executeCalculatePositionSize(args: [String: Any]) async -> String {
        guard let accountValue = args["account_value"] as? Double else {
            return "Error: Missing 'account_value' parameter"
        }
        guard let riskPercent = args["risk_percent"] as? Double else {
            return "Error: Missing 'risk_percent' parameter"
        }
        guard let entryPrice = args["entry_price"] as? Double else {
            return "Error: Missing 'entry_price' parameter"
        }
        guard let stopPrice = args["stop_price"] as? Double else {
            return "Error: Missing 'stop_price' parameter"
        }
        
        // Validate inputs
        guard accountValue > 0 else {
            return "Error: Account value must be positive"
        }
        guard riskPercent > 0 && riskPercent <= 5 else {
            return "Error: Risk percent should be between 0.1% and 5% (recommended: 1%)"
        }
        guard entryPrice > 0 && stopPrice > 0 else {
            return "Error: Prices must be positive"
        }
        
        // Calculate risk amount
        let riskAmount = accountValue * (riskPercent / 100.0)
        
        // Calculate the distance between entry and stop
        let stopDistance = abs(entryPrice - stopPrice)
        
        guard stopDistance > 0 else {
            return "Error: Entry and stop prices cannot be the same"
        }
        
        // Calculate position size: Risk / (Entry - Stop) = Shares
        let positionSize = riskAmount / stopDistance
        let positionValue = positionSize * entryPrice
        let positionPercent = (positionValue / accountValue) * 100
        let stopPercent = (stopDistance / entryPrice) * 100
        
        // Calculate the 5x risk target for first partial exit
        let fiveXRiskTarget: Double
        if entryPrice > stopPrice { // Long trade
            fiveXRiskTarget = entryPrice + (stopDistance * 5)
        } else { // Short trade
            fiveXRiskTarget = entryPrice - (stopDistance * 5)
        }
        
        var result: [String: Any] = [
            "position_size": round(positionSize * 10000) / 10000, // 4 decimal places
            "position_value_usd": round(positionValue * 100) / 100,
            "position_percent_of_account": round(positionPercent * 100) / 100,
            "max_loss_usd": round(riskAmount * 100) / 100,
            "risk_percent": riskPercent,
            "entry_price": entryPrice,
            "stop_price": stopPrice,
            "stop_distance_usd": round(stopDistance * 100) / 100,
            "stop_distance_percent": round(stopPercent * 100) / 100,
            "first_target_5x_risk": round(fiveXRiskTarget * 100) / 100,
            "trade_direction": entryPrice > stopPrice ? "long" : "short"
        ]
        
        // Add warnings if needed
        var warnings: [String] = []
        if riskPercent > 2 {
            warnings.append("Risk exceeds recommended 2% maximum - consider reducing")
        }
        if positionPercent > 50 {
            warnings.append("Position is over 50% of account - high concentration risk")
        }
        if stopPercent > 10 {
            warnings.append("Stop is \(String(format: "%.1f", stopPercent))% away - consider tighter stop for better R:R")
        }
        if stopPercent < 1 {
            warnings.append("Stop is very tight (\(String(format: "%.1f", stopPercent))%) - may get stopped out on normal volatility")
        }
        
        if !warnings.isEmpty {
            result["warnings"] = warnings
        }
        
        // Add explanation
        result["explanation"] = "With a $\(formatCurrency(accountValue)) account risking \(riskPercent)%, you can buy \(String(format: "%.4f", positionSize)) units at $\(entryPrice). If stopped out at $\(stopPrice), you lose $\(String(format: "%.2f", riskAmount)) (exactly \(riskPercent)% of account). First profit target at $\(String(format: "%.2f", fiveXRiskTarget)) (5x risk)."
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return "Position size calculated: \(positionSize) units"
    }
    
    private func executeGetMarketRegime() async -> String {
        let marketVM = MarketViewModel.shared
        
        // Find BTC
        guard let btc = marketVM.allCoins.first(where: { $0.symbol.uppercased() == "BTC" }) else {
            return "Error: BTC data not available to determine market regime"
        }
        
        // Get BTC sparkline for MA calculation
        let sparkline = btc.sparklineIn7d
        guard sparkline.count >= 50 else {
            return "Error: Insufficient price history for MA calculation"
        }
        
        // Calculate SMAs from sparkline
        let sma10 = TechnicalsEngine.sma(sparkline, period: 10)
        let sma20 = TechnicalsEngine.sma(sparkline, period: 20)
        let sma50 = TechnicalsEngine.sma(sparkline, period: 50)
        
        guard let s10 = sma10, let s20 = sma20 else {
            return "Error: Could not calculate moving averages"
        }
        
        // Determine market regime
        let is10Above20 = s10 > s20
        let currentPrice = btc.priceUsd ?? sparkline.last ?? 0
        let priceAbove20 = currentPrice > s20
        
        // Check if MAs are inclining (compare current vs older values)
        let olderData = Array(sparkline.dropLast(5))
        let sma10Old = TechnicalsEngine.sma(olderData, period: 10)
        let sma20Old = TechnicalsEngine.sma(olderData, period: 20)
        
        let sma10Inclining = sma10Old.map { s10 > $0 } ?? false
        let sma20Inclining = sma20Old.map { s20 > $0 } ?? false
        
        // Determine overall regime
        let regime: String
        let tradingBias: String
        let confidence: String
        var notes: [String] = []
        
        if is10Above20 && sma10Inclining && sma20Inclining {
            regime = "bullish"
            tradingBias = "Favor LONG breakout setups"
            confidence = "high"
            notes.append("10 SMA is ABOVE 20 SMA and both are inclining - bullish conditions")
            notes.append("This is ideal for swing trading long breakouts")
        } else if is10Above20 && !sma10Inclining {
            regime = "cautious_bullish"
            tradingBias = "LONG setups OK but be selective"
            confidence = "medium"
            notes.append("10 SMA is above 20 SMA but momentum is slowing")
            notes.append("Consider smaller position sizes")
        } else if !is10Above20 && !sma10Inclining && !sma20Inclining {
            regime = "bearish"
            tradingBias = "AVOID long breakout trades or significantly reduce size"
            confidence = "high"
            notes.append("10 SMA is BELOW 20 SMA and both are declining - bearish conditions")
            notes.append("Long breakouts have lower success rate in this environment")
        } else if !is10Above20 {
            regime = "cautious_bearish"
            tradingBias = "Be very selective with longs, consider sitting out"
            confidence = "medium"
            notes.append("10 SMA is below 20 SMA - trend is not favorable for longs")
        } else {
            regime = "neutral"
            tradingBias = "Mixed signals - trade with caution"
            confidence = "low"
        }
        
        // Add market sentiment context
        let sentimentVM = ExtendedFearGreedViewModel.shared
        if let sentimentValue = sentimentVM.currentValue,
           let classification = sentimentVM.currentClassificationKey {
            notes.append("Market sentiment: \(classification.capitalized) (\(sentimentValue)/100)")
            
            // Warn about extremes
            if sentimentValue > 75 {
                notes.append("WARNING: Extreme greed - consider waiting for pullback before entries")
            } else if sentimentValue < 25 {
                notes.append("NOTE: Extreme fear often presents buying opportunities - but wait for regime to turn bullish")
            }
        }
        
        var result: [String: Any] = [
            "regime": regime,
            "trading_bias": tradingBias,
            "confidence": confidence,
            "btc_price": currentPrice,
            "btc_10_sma": round(s10 * 100) / 100,
            "btc_20_sma": round(s20 * 100) / 100,
            "is_10_above_20": is10Above20,
            "sma_10_inclining": sma10Inclining,
            "sma_20_inclining": sma20Inclining,
            "price_above_20_sma": priceAbove20,
            "notes": notes,
            "timestamp": Self._isoFormatter.string(from: Date())
        ]
        
        if let s50 = sma50 {
            result["btc_50_sma"] = round(s50 * 100) / 100
            result["price_above_50_sma"] = currentPrice > s50
        }
        
        // Add 24h change for context
        if let change24h = btc.priceChangePercentage24hInCurrency {
            result["btc_24h_change"] = change24h
        }
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return "Market regime: \(regime) (\(tradingBias))"
    }
    
    private func executeAnalyzeBreakoutSetup(args: [String: Any]) async -> String {
        guard let symbol = args["symbol"] as? String else {
            return "Error: Missing 'symbol' parameter"
        }
        
        let upperSymbol = symbol.uppercased()
        let marketVM = MarketViewModel.shared
        
        // Find the coin
        guard let coin = marketVM.allCoins.first(where: { $0.symbol.uppercased() == upperSymbol }) else {
            return "Breakout analysis not available for \(upperSymbol) - coin not found"
        }
        
        let sparkline = coin.sparklineIn7d
        guard sparkline.count >= 50 else {
            return "Insufficient price history for breakout analysis on \(upperSymbol)"
        }
        
        // Create volume proxy (use price changes as volume proxy since we don't have actual volume)
        var volumeProxy: [Double] = [1.0]
        for i in 1..<sparkline.count {
            let change = abs(sparkline[i] - sparkline[i-1])
            volumeProxy.append(change * 1000) // Scale up for calculations
        }
        
        // Use TechnicalsEngine for analysis
        let breakoutResult = TechnicalsEngine.detectBreakout(closes: sparkline, volumes: volumeProxy)
        let maResult = TechnicalsEngine.maAlignment(closes: sparkline)
        let rangeResult = TechnicalsEngine.rangeTightness(closes: sparkline, period: 10)
        let volumeTrendResult = TechnicalsEngine.volumeTrend(volumes: volumeProxy)
        
        var result: [String: Any] = [
            "symbol": upperSymbol,
            "name": coin.name,
            "current_price": coin.priceUsd ?? sparkline.last ?? 0
        ]
        
        // Build comprehensive analysis
        var analysisNotes: [String] = []
        var score = 0
        
        // Step 1: Prior move check
        if let priorMove = TechnicalsEngine.priorMovePercent(closes: sparkline, lookbackDays: 30) {
            result["prior_move_percent"] = round(priorMove * 100) / 100
            if priorMove >= 30 {
                score += 20
                analysisNotes.append("PASS: Prior move +\(String(format: "%.1f", priorMove))% (meets 30%+ criteria)")
            } else if priorMove >= 15 {
                score += 10
                analysisNotes.append("PARTIAL: Prior move +\(String(format: "%.1f", priorMove))% (below 30% threshold)")
            } else {
                analysisNotes.append("FAIL: Prior move only +\(String(format: "%.1f", priorMove))% (need 30%+)")
            }
        }
        
        // Step 2: MA alignment check
        if let ma = maResult {
            result["ma_alignment"] = ma.order
            result["is_10_above_20_sma"] = ma.sma10Above20
            result["mas_inclining"] = ma.allInclining
            
            if ma.sma10Above20 && ma.allInclining {
                score += 20
                analysisNotes.append("PASS: 10/20 SMA inclining and properly aligned")
            } else if ma.sma10Above20 {
                score += 10
                analysisNotes.append("PARTIAL: 10 > 20 SMA but not all MAs inclining")
            } else {
                analysisNotes.append("FAIL: 10 SMA below 20 SMA - bearish structure")
            }
        }
        
        // Step 3: Range tightening check
        if let range = rangeResult {
            result["range_tightening"] = range.tightening
            result["range_ratio"] = round(range.ratio * 100) / 100
            
            if range.tightening {
                score += 20
                analysisNotes.append("PASS: Range tightening (consolidating) - \(String(format: "%.0f", range.ratio * 100))% of prior range")
            } else {
                analysisNotes.append("PARTIAL: Range not tightening yet")
            }
        }
        
        // Step 4: Volume drying up check
        if let vol = volumeTrendResult {
            result["volume_trend"] = vol.trend
            result["volume_ratio"] = round(vol.ratio * 100) / 100
            
            if vol.dryingUp {
                score += 20
                analysisNotes.append("PASS: Volume drying up (good for setup)")
            } else if vol.trend == "neutral" {
                score += 5
                analysisNotes.append("NEUTRAL: Volume at average levels")
            } else {
                analysisNotes.append("NOTE: Volume expanding - may already be breaking out")
            }
        }
        
        // Step 5: Breakout status
        if let breakout = breakoutResult {
            result["is_breakout"] = breakout.isBreakout
            result["breakout_price"] = round(breakout.breakoutPrice * 100) / 100
            result["support_level"] = round(breakout.supportLevel * 100) / 100
            result["volume_confirmed"] = breakout.volumeConfirmed
            
            if breakout.isBreakout && breakout.volumeConfirmed {
                score += 20
                analysisNotes.append("BREAKOUT: Price at range high with volume confirmation!")
            } else if breakout.isBreakout {
                score += 10
                analysisNotes.append("POTENTIAL: Near breakout level, waiting for volume")
            } else {
                analysisNotes.append("NOT YET: Price not at breakout level")
            }
        }
        
        result["setup_score"] = score
        result["analysis"] = analysisNotes
        
        // Generate trading recommendation
        let recommendation: String
        let entryZone: String
        let stopLevel: String
        
        let currentPrice = coin.priceUsd ?? sparkline.last ?? 0
        let sma20 = TechnicalsEngine.sma(sparkline, period: 20) ?? currentPrice
        let recentLow = sparkline.suffix(10).min() ?? currentPrice * 0.95
        
        if score >= 80 {
            recommendation = "STRONG SETUP: All criteria met - consider entering on breakout confirmation with volume"
            entryZone = "Entry at breakout of \(formatCurrency(breakoutResult?.breakoutPrice ?? currentPrice * 1.02))"
            stopLevel = "Stop at \(formatCurrency(recentLow)) (below consolidation low)"
        } else if score >= 60 {
            recommendation = "DECENT SETUP: Most criteria met - can trade with smaller size"
            entryZone = "Entry near \(formatCurrency(sma20)) on pullback or breakout"
            stopLevel = "Stop at \(formatCurrency(recentLow))"
        } else if score >= 40 {
            recommendation = "DEVELOPING: Setup forming but not ready - add to watchlist"
            entryZone = "Wait for better setup"
            stopLevel = "N/A"
        } else {
            recommendation = "NOT READY: Does not meet breakout criteria - avoid for now"
            entryZone = "Wait for setup to develop"
            stopLevel = "N/A"
        }
        
        result["recommendation"] = recommendation
        result["suggested_entry"] = entryZone
        result["suggested_stop"] = stopLevel
        
        // Add price context
        if let change24h = coin.priceChangePercentage24hInCurrency {
            result["change_24h_percent"] = change24h
        }
        if let change7d = coin.priceChangePercentage7dInCurrency {
            result["change_7d_percent"] = change7d
        }
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return "Breakout analysis for \(upperSymbol): Score \(score)/100"
    }
    
    private func executeCalculateRiskReward(args: [String: Any]) async -> String {
        guard let entryPrice = args["entry_price"] as? Double else {
            return "Error: Missing 'entry_price' parameter"
        }
        guard let stopPrice = args["stop_price"] as? Double else {
            return "Error: Missing 'stop_price' parameter"
        }
        guard let targetPrice = args["target_price"] as? Double else {
            return "Error: Missing 'target_price' parameter"
        }
        
        guard entryPrice > 0 && stopPrice > 0 && targetPrice > 0 else {
            return "Error: All prices must be positive"
        }
        
        // Calculate risk and reward
        let isLong = entryPrice > stopPrice
        let risk = abs(entryPrice - stopPrice)
        let reward = abs(targetPrice - entryPrice)
        
        guard risk > 0 else {
            return "Error: Entry and stop cannot be the same price"
        }
        
        let rrRatio = reward / risk
        let riskPercent = (risk / entryPrice) * 100
        let rewardPercent = (reward / entryPrice) * 100
        
        // Determine quality of trade
        let quality: String
        let recommendation: String
        
        if rrRatio >= 5 {
            quality = "excellent"
            recommendation = "Outstanding R:R - this is a high-quality setup"
        } else if rrRatio >= 3 {
            quality = "good"
            recommendation = "Good R:R meets minimum criteria - trade is worth considering"
        } else if rrRatio >= 2 {
            quality = "acceptable"
            recommendation = "Below ideal 3:1 but acceptable if win rate is high"
        } else if rrRatio >= 1 {
            quality = "poor"
            recommendation = "R:R below 2:1 - need higher win rate to be profitable. Consider tighter stop or higher target."
        } else {
            quality = "avoid"
            recommendation = "R:R below 1:1 - avoid this trade. Risk exceeds potential reward."
        }
        
        // Calculate the 5x risk target for partial profits
        let fiveXTarget = isLong ? entryPrice + (risk * 5) : entryPrice - (risk * 5)
        
        var result: [String: Any] = [
            "entry_price": entryPrice,
            "stop_price": stopPrice,
            "target_price": targetPrice,
            "direction": isLong ? "long" : "short",
            "risk_amount": round(risk * 10000) / 10000,
            "risk_percent": round(riskPercent * 100) / 100,
            "reward_amount": round(reward * 10000) / 10000,
            "reward_percent": round(rewardPercent * 100) / 100,
            "risk_reward_ratio": round(rrRatio * 100) / 100,
            "rr_display": "1:\(String(format: "%.1f", rrRatio))",
            "quality": quality,
            "recommendation": recommendation,
            "first_partial_target_5x": round(fiveXTarget * 100) / 100
        ]
        
        // Add breakeven info after partial
        if rrRatio >= 5 {
            result["partial_profit_note"] = "At 5x risk target ($\(String(format: "%.2f", fiveXTarget))), sell 20-30% and move stop to breakeven"
        }
        
        // Calculate win rate needed to be profitable
        // Breakeven win rate = 1 / (1 + R:R)
        let breakevenWinRate = (1 / (1 + rrRatio)) * 100
        result["breakeven_win_rate"] = round(breakevenWinRate * 100) / 100
        result["win_rate_note"] = "You need >\(String(format: "%.0f", breakevenWinRate))% win rate to be profitable with this R:R"
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return "Risk:Reward ratio is 1:\(String(format: "%.1f", rrRatio)) (\(quality))"
    }
    
    private func executeAnalyzeTrendStructure(args: [String: Any]) async -> String {
        guard let symbol = args["symbol"] as? String else {
            return "Error: Missing 'symbol' parameter"
        }
        
        let upperSymbol = symbol.uppercased()
        let marketVM = MarketViewModel.shared
        
        // Find the coin
        guard let coin = marketVM.allCoins.first(where: { $0.symbol.uppercased() == upperSymbol }) else {
            return "Trend analysis not available for \(upperSymbol) - coin not found"
        }
        
        let sparkline = coin.sparklineIn7d
        guard sparkline.count >= 50 else {
            return "Insufficient price history for trend analysis on \(upperSymbol)"
        }
        
        let currentPrice = coin.priceUsd ?? sparkline.last ?? 0
        
        // Get all SMAs
        let smas = TechnicalsEngine.getAllSMAs(closes: sparkline)
        let maAlignment = TechnicalsEngine.maAlignment(closes: sparkline)
        let trendDir = TechnicalsEngine.trendDirection(closes: sparkline, maPeriod: 20)
        
        var result: [String: Any] = [
            "symbol": upperSymbol,
            "name": coin.name,
            "current_price": currentPrice
        ]
        
        // Add SMA values
        if let s10 = smas.sma10 {
            result["sma_10"] = round(s10 * 100) / 100
            result["price_vs_10_sma"] = currentPrice > s10 ? "above" : "below"
            result["distance_from_10_sma_percent"] = round(((currentPrice - s10) / s10) * 10000) / 100
        }
        if let s20 = smas.sma20 {
            result["sma_20"] = round(s20 * 100) / 100
            result["price_vs_20_sma"] = currentPrice > s20 ? "above" : "below"
            result["distance_from_20_sma_percent"] = round(((currentPrice - s20) / s20) * 10000) / 100
        }
        if let s50 = smas.sma50 {
            result["sma_50"] = round(s50 * 100) / 100
            result["price_vs_50_sma"] = currentPrice > s50 ? "above" : "below"
        }
        if let s200 = smas.sma200 {
            result["sma_200"] = round(s200 * 100) / 100
            result["price_vs_200_sma"] = currentPrice > s200 ? "above" : "below"
        }
        
        // Add MA alignment info
        if let ma = maAlignment {
            result["ma_alignment"] = ma.order
            result["is_bullish_aligned"] = ma.bullish
            result["is_10_above_20"] = ma.sma10Above20
            result["mas_are_inclining"] = ma.allInclining
        }
        
        // Add trend direction
        if let trend = trendDir {
            result["trend_direction"] = trend
        }
        
        // Generate analysis
        var analysis: [String] = []
        var supportLevels: [Double] = []
        var entryZone: String = ""
        
        if let ma = maAlignment {
            if ma.order == "bullish_perfect" {
                analysis.append("STRONG TREND: All MAs in perfect bullish alignment (10 > 20 > 50 > 200)")
            } else if ma.order == "bullish_partial" {
                analysis.append("UPTREND: Short-term MAs aligned bullishly")
            } else if ma.order == "bearish_perfect" {
                analysis.append("DOWNTREND: All MAs in bearish alignment - avoid longs")
            } else if ma.order == "bearish_partial" {
                analysis.append("WEAK: Short-term MAs showing weakness")
            } else {
                analysis.append("MIXED: MAs not aligned - choppy conditions")
            }
            
            if ma.allInclining {
                analysis.append("MAs are INCLINING - momentum is positive")
            } else if ma.sma10Above20 {
                analysis.append("Warning: 10 > 20 SMA but MAs starting to flatten")
            } else {
                analysis.append("MAs DECLINING - not ideal for long entries")
            }
        }
        
        // Identify support levels from MAs
        if let s10 = smas.sma10, currentPrice > s10 {
            supportLevels.append(round(s10 * 100) / 100)
        }
        if let s20 = smas.sma20, currentPrice > s20 {
            supportLevels.append(round(s20 * 100) / 100)
        }
        if let s50 = smas.sma50, currentPrice > s50 {
            supportLevels.append(round(s50 * 100) / 100)
        }
        
        result["support_levels_from_mas"] = supportLevels
        
        // Determine optimal entry zone
        if let s10 = smas.sma10, let s20 = smas.sma20 {
            if let ma = maAlignment, ma.bullish {
                entryZone = "Optimal entry: Pullback to 10 SMA ($\(String(format: "%.2f", s10))) or 20 SMA ($\(String(format: "%.2f", s20)))"
                analysis.append(entryZone)
            } else if currentPrice < s20 {
                entryZone = "Wait for price to reclaim 20 SMA ($\(String(format: "%.2f", s20))) before entering"
                analysis.append(entryZone)
            }
        }
        
        result["analysis"] = analysis
        result["optimal_entry_zone"] = entryZone
        
        // Add RSI context
        if let rsi = TechnicalsEngine.rsi(sparkline) {
            result["rsi_14"] = round(rsi * 100) / 100
            if rsi > 70 {
                result["rsi_condition"] = "overbought"
            } else if rsi < 30 {
                result["rsi_condition"] = "oversold"
            } else {
                result["rsi_condition"] = "neutral"
            }
        }
        
        // Add price changes
        if let change24h = coin.priceChangePercentage24hInCurrency {
            result["change_24h_percent"] = change24h
        }
        if let change7d = coin.priceChangePercentage7dInCurrency {
            result["change_7d_percent"] = change7d
        }
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return "Trend analysis for \(upperSymbol): \(trendDir ?? "unknown")"
    }
    
    private func executeGetPricePrediction(args: [String: Any]) async -> String {
        guard let symbol = args["symbol"] as? String else {
            return "Error: Missing 'symbol' parameter"
        }
        
        let upperSymbol = symbol.uppercased()
        
        // Parse timeframe with default to 7d
        let timeframeStr = (args["timeframe"] as? String) ?? "7d"
        let timeframe: PredictionTimeframe
        switch timeframeStr {
        case "1h": timeframe = .hour
        case "4h": timeframe = .fourHours
        case "12h": timeframe = .twelveHours
        case "1d": timeframe = .day
        case "30d": timeframe = .month
        default: timeframe = .week
        }
        
        // Get coin name from MarketViewModel
        let marketVM = MarketViewModel.shared
        let coinName = marketVM.allCoins.first(where: { $0.symbol.uppercased() == upperSymbol })?.name ?? upperSymbol
        
        // Check if we have a cached prediction
        let predictionService = AIPricePredictionService.shared
        let cacheKey = "\(upperSymbol)_\(timeframe.rawValue)"
        
        if let cached = predictionService.cachedPredictions[cacheKey] {
            // Return cached prediction
            return formatPredictionResult(cached)
        }
        
        // Generate new prediction
        do {
            let prediction = try await predictionService.generatePrediction(
                for: upperSymbol,
                coinName: coinName,
                timeframe: timeframe,
                forceRefresh: false
            )
            return formatPredictionResult(prediction)
        } catch {
            return """
            {
                "error": "Failed to generate prediction",
                "message": "\(error.localizedDescription)",
                "symbol": "\(upperSymbol)",
                "suggestion": "Try again or ask about technical indicators directly"
            }
            """
        }
    }
    
    private func formatPredictionResult(_ prediction: AIPricePrediction) -> String {
        var result: [String: Any] = [
            "symbol": prediction.coinSymbol,
            "name": prediction.coinName,
            "timeframe": prediction.timeframe.fullName,
            "current_price": prediction.currentPrice,
            "current_price_formatted": formatCurrency(prediction.currentPrice),
            "direction": prediction.direction.rawValue,
            "direction_display": prediction.direction.displayName,
            "predicted_price_change_percent": prediction.predictedPriceChange,
            "predicted_price": prediction.predictedPrice,
            "predicted_price_formatted": formatCurrency(prediction.predictedPrice),
            "price_range_low": prediction.predictedPriceLow,
            "price_range_high": prediction.predictedPriceHigh,
            "price_range_formatted": prediction.priceRangeText,
            "confidence_score": prediction.confidenceScore,
            "confidence_level": prediction.confidence.displayName,
            "analysis": prediction.analysis,
            "generated_at": Self._isoFormatter.string(from: prediction.generatedAt)
        ]
        
        // Add key drivers
        var driversArray: [[String: Any]] = []
        for driver in prediction.drivers {
            driversArray.append([
                "name": driver.name,
                "value": driver.value,
                "signal": driver.signal,
                "weight": driver.weight
            ])
        }
        result["key_drivers"] = driversArray
        
        // Add summary for easy interpretation
        let bullishDrivers = prediction.drivers.filter { $0.signal.lowercased() == "bullish" }.count
        let bearishDrivers = prediction.drivers.filter { $0.signal.lowercased() == "bearish" }.count
        result["bullish_signals_count"] = bullishDrivers
        result["bearish_signals_count"] = bearishDrivers
        
        // Add trading suggestion based on prediction
        var suggestion = ""
        if prediction.direction == .bullish && prediction.confidenceScore >= 60 {
            suggestion = "Moderately bullish outlook. Consider accumulating on dips toward support levels."
        } else if prediction.direction == .bullish && prediction.confidenceScore >= 40 {
            suggestion = "Slightly bullish bias but mixed signals. Wait for clearer confirmation before adding positions."
        } else if prediction.direction == .bearish && prediction.confidenceScore >= 60 {
            suggestion = "Bearish outlook. Consider reducing exposure or setting tight stop losses."
        } else if prediction.direction == .bearish && prediction.confidenceScore >= 40 {
            suggestion = "Slight bearish bias. Be cautious with new longs, watch for reversal signals."
        } else {
            suggestion = "Mixed signals suggest range-bound price action. Consider waiting for a clearer setup."
        }
        result["trading_suggestion"] = suggestion
        result["disclaimer"] = AIPricePrediction.disclaimer
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return "Prediction for \(prediction.coinSymbol): \(prediction.direction.displayName) with \(prediction.confidenceScore)% confidence"
    }
    
    // MARK: - Trading Pair Preferences Implementation
    
    private func executeGetTradingPairPreferences() async -> String {
        let prefsService = TradingPairPreferencesService.shared
        
        // Get all preference data
        let favoritePairs = prefsService.getFavoritePairsInfo()
        let recentPairs = prefsService.getRecentPairs(limit: 5)
        let preferredExchanges = prefsService.getPreferredExchanges()
        let preferredQuote = prefsService.getPreferredQuoteCurrency()
        let mostTradedAssets = prefsService.getMostTradedAssets()
        
        var result: [String: Any] = [:]
        
        // Favorite pairs
        if !favoritePairs.isEmpty {
            var favoritesData: [[String: Any]] = []
            for pair in favoritePairs {
                favoritesData.append([
                    "pair": pair.displayPair,
                    "base": pair.baseSymbol,
                    "quote": pair.quoteSymbol,
                    "exchange": pair.exchangeName,
                    "exchange_id": pair.exchangeID
                ])
            }
            result["favorite_pairs"] = favoritesData
            result["favorite_pairs_count"] = favoritePairs.count
        } else {
            result["favorite_pairs"] = []
            result["favorite_pairs_count"] = 0
        }
        
        // Recent pairs
        if !recentPairs.isEmpty {
            var recentsData: [[String: Any]] = []
            for pair in recentPairs {
                recentsData.append([
                    "pair": pair.displayPair,
                    "base": pair.baseSymbol,
                    "quote": pair.quoteSymbol,
                    "exchange": pair.exchangeName
                ])
            }
            result["recent_pairs"] = recentsData
        } else {
            result["recent_pairs"] = []
        }
        
        // Preferred exchange
        if !preferredExchanges.isEmpty {
            result["preferred_exchange"] = preferredExchanges.first ?? "binance"
            result["preferred_exchange_name"] = exchangeDisplayName(preferredExchanges.first ?? "binance")
            result["all_used_exchanges"] = preferredExchanges.map { exchangeDisplayName($0) }
        } else {
            result["preferred_exchange"] = "binance"
            result["preferred_exchange_name"] = "Binance"
        }
        
        // Preferred quote currency
        result["preferred_quote_currency"] = preferredQuote
        
        // Most traded assets
        if !mostTradedAssets.isEmpty {
            result["most_traded_assets"] = mostTradedAssets
        }
        
        // Build recommendation text
        var recommendations: [String] = []
        
        if !favoritePairs.isEmpty {
            let topFavorites = favoritePairs.prefix(3).map { $0.displayPair }.joined(separator: ", ")
            recommendations.append("User's favorite pairs: \(topFavorites)")
        }
        
        if let primaryExchange = preferredExchanges.first {
            recommendations.append("Prefer \(exchangeDisplayName(primaryExchange)) when suggesting trades")
        }
        
        recommendations.append("Use \(preferredQuote) as quote currency unless user specifies otherwise")
        
        if !mostTradedAssets.isEmpty {
            let topAssets = mostTradedAssets.prefix(3).joined(separator: ", ")
            recommendations.append("User frequently trades: \(topAssets)")
        }
        
        result["recommendations"] = recommendations
        result["timestamp"] = Self._isoFormatter.string(from: Date())
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        // Fallback text response
        if favoritePairs.isEmpty && recentPairs.isEmpty {
            return """
            {
                "message": "No trading pair preferences found yet. The user hasn't favorited any pairs or made recent trades.",
                "default_exchange": "Binance",
                "default_quote": "USDT",
                "suggestion": "Recommend popular pairs like BTC/USDT, ETH/USDT on Binance"
            }
            """
        }
        
        return "Trading pair preferences retrieved successfully"
    }
    
    private func exchangeDisplayName(_ id: String) -> String {
        switch id.lowercased() {
        case "binance": return "Binance"
        case "binance_us": return "Binance US"
        case "coinbase": return "Coinbase"
        case "kraken": return "Kraken"
        case "kucoin": return "KuCoin"
        default: return id.capitalized
        }
    }
    
    // MARK: - Formatting Helpers
    
    private func formatCoinPrice(_ coin: MarketCoin) -> String {
        var result: [String: Any] = [
            "symbol": coin.symbol.uppercased(),
            "name": coin.name,
            "price_usd": coin.priceUsd ?? 0,
            "price_formatted": formatCurrency(coin.priceUsd ?? 0)
        ]
        
        if let change1h = coin.priceChangePercentage1hInCurrency {
            result["change_1h_percent"] = change1h
        }
        if let change24h = coin.priceChangePercentage24hInCurrency {
            result["change_24h_percent"] = change24h
        }
        if let change7d = coin.priceChangePercentage7dInCurrency {
            result["change_7d_percent"] = change7d
        }
        if let marketCap = coin.marketCap {
            result["market_cap_usd"] = marketCap
            result["market_cap_formatted"] = formatLargeCurrency(marketCap)
        }
        if let rank = coin.marketCapRank {
            result["rank"] = rank
        }
        
        result["timestamp"] = Self._isoFormatter.string(from: Date())
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return "\(coin.symbol.uppercased()): $\(coin.priceUsd ?? 0)"
    }
    
    private func formatCurrency(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "$%.2f", value)
        } else if value >= 1 {
            return String(format: "$%.2f", value)
        } else if value >= 0.01 {
            return String(format: "$%.4f", value)
        } else {
            return String(format: "$%.6f", value)
        }
    }
    
    private func formatLargeCurrency(_ value: Double) -> String {
        if value >= 1_000_000_000_000 {
            return String(format: "$%.2fT", value / 1_000_000_000_000)
        } else if value >= 1_000_000_000 {
            return String(format: "$%.2fB", value / 1_000_000_000)
        } else if value >= 1_000_000 {
            return String(format: "$%.2fM", value / 1_000_000)
        } else {
            return formatCurrency(value)
        }
    }
    
    // MARK: - DeFi & NFT Function Implementations
    
    private func executeGetDeFiPositions(args: [String: Any]) async -> String {
        guard let walletAddress = args["wallet_address"] as? String else {
            return "Error: Missing 'wallet_address' parameter. Please provide a wallet address (0x... for EVM chains)."
        }
        
        // Check if DeBank API is configured (must access on MainActor)
        let hasKey = await MainActor.run { DeFiAggregatorService.shared.hasAPIKey }
        
        var result: [String: Any] = [
            "wallet_address": walletAddress,
            "timestamp": Self._isoFormatter.string(from: Date())
        ]
        
        if hasKey {
            do {
                let summary = try await DeFiAggregatorService.shared.fetchPortfolioSummary(address: walletAddress)
                
                result["total_value_usd"] = summary.totalValueUSD
                result["total_debt_usd"] = summary.totalDebtUSD
                result["net_value_usd"] = summary.netValueUSD
                result["pending_rewards_usd"] = summary.totalPendingRewardsUSD
                result["positions_count"] = summary.positions.count
                
                // Group positions by protocol
                var positionsByProtocol: [[String: Any]] = []
                for position in summary.positions.prefix(20) {
                    positionsByProtocol.append([
                        "protocol": position.protocol_.name,
                        "chain": position.chain.displayName,
                        "type": position.type.displayName,
                        "value_usd": position.valueUSD,
                        "health_factor": position.healthFactor ?? "N/A",
                        "tokens": position.tokens.map { "\($0.symbol): \($0.amount)" }
                    ])
                }
                result["positions"] = positionsByProtocol
                
                // Breakdown by type
                var byType: [String: Double] = [:]
                for (type, value) in summary.positionsByType {
                    byType[type.displayName] = value
                }
                result["by_type"] = byType
                
                // Breakdown by chain
                var byChain: [String: Double] = [:]
                for (chain, value) in summary.positionsByChain {
                    byChain[chain.displayName] = value
                }
                result["by_chain"] = byChain
                
            } catch {
                result["error"] = "Failed to fetch DeFi positions: \(error.localizedDescription)"
                result["suggestion"] = "Please ensure the wallet address is correct and try again."
            }
        } else {
            result["error"] = "DeFi aggregator API key not configured"
            result["suggestion"] = "Configure a DeBank API key in Settings to enable DeFi position tracking across 1000+ protocols."
            result["manual_check"] = "You can manually check positions on individual protocol websites."
        }
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return "Unable to retrieve DeFi positions. Please check the wallet address format."
    }
    
    private func executeGetNFTPortfolio(args: [String: Any]) async -> String {
        guard let walletAddress = args["wallet_address"] as? String else {
            return "Error: Missing 'wallet_address' parameter."
        }
        
        let chainFilter = args["chain"] as? String
        let nftService = NFTService.shared
        
        var result: [String: Any] = [
            "wallet_address": walletAddress,
            "timestamp": Self._isoFormatter.string(from: Date())
        ]
        
        do {
            // Determine chains to check
            var chains: [Chain] = [.ethereum, .polygon, .solana]
            if let chainStr = chainFilter?.lowercased() {
                switch chainStr {
                case "ethereum", "eth": chains = [.ethereum]
                case "polygon", "matic": chains = [.polygon]
                case "solana", "sol": chains = [.solana]
                case "arbitrum", "arb": chains = [.arbitrum]
                case "base": chains = [.base]
                default: break
                }
            }
            
            let portfolio = try await nftService.fetchNFTs(address: walletAddress, chains: chains)
            
            result["total_nfts"] = portfolio.nfts.count
            result["total_collections"] = portfolio.collectionCount
            result["estimated_value_usd"] = portfolio.totalEstimatedValueUSD
            
            // Group by collection
            var collections: [[String: Any]] = []
            let nftsByCollection = portfolio.nftsByCollection
            for (collectionId, nfts) in nftsByCollection.prefix(10) {
                let collectionValue = nfts.compactMap { $0.estimatedValueUSD }.reduce(0, +)
                collections.append([
                    "name": nfts.first?.collection?.name ?? collectionId,
                    "count": nfts.count,
                    "floor_price": nfts.first?.collection?.floorPrice ?? 0,
                    "total_value_usd": collectionValue,
                    "chain": nfts.first?.chain.displayName ?? "Unknown"
                ])
            }
            result["collections"] = collections
            
            // Recent/notable NFTs
            var notableNFTs: [[String: Any]] = []
            for nft in portfolio.nfts.prefix(5) {
                notableNFTs.append([
                    "name": nft.displayName,
                    "collection": nft.collection?.name ?? "Unknown",
                    "chain": nft.chain.displayName,
                    "estimated_value": nft.estimatedValueUSD ?? 0,
                    "token_standard": nft.tokenStandard.displayName
                ])
            }
            result["notable_nfts"] = notableNFTs
            
        } catch {
            result["error"] = "Failed to fetch NFTs: \(error.localizedDescription)"
        }
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return "Unable to retrieve NFT portfolio."
    }
    
    private func executeGetDeFiYields(args: [String: Any]) async -> String {
        guard let token = args["token"] as? String else {
            return "Error: Missing 'token' parameter. Please specify a token symbol (e.g., ETH, USDC)."
        }
        
        let minApy = args["min_apy"] as? Double ?? 1.0
        let riskLevel = args["risk_level"] as? String
        
        let tokenUpper = token.uppercased()
        
        // Build yield opportunities from known protocols
        var opportunities: [[String: Any]] = []
        
        // Lending protocols
        let lendingProtocols = DeFiProtocolRegistry.lendingProtocols
        for protocol_ in lendingProtocols {
            // Estimate APY ranges based on protocol type (in production, fetch real data)
            let estimatedApy: Double
            let risk: String
            
            switch protocol_.name {
            case "Aave V3", "Compound", "Spark Protocol":
                estimatedApy = 2.5 + Double.random(in: 0...3)
                risk = "low"
            case "Morpho":
                estimatedApy = 4.0 + Double.random(in: 0...4)
                risk = "low"
            default:
                estimatedApy = 5.0 + Double.random(in: 0...8)
                risk = "medium"
            }
            
            if estimatedApy >= minApy {
                if riskLevel == nil || risk == riskLevel {
                    opportunities.append([
                        "protocol": protocol_.name,
                        "chain": protocol_.chain.displayName,
                        "type": "Lending",
                        "estimated_apy": String(format: "%.2f%%", estimatedApy),
                        "risk": risk,
                        "token": tokenUpper
                    ])
                }
            }
        }
        
        // Liquid staking (for ETH)
        if tokenUpper == "ETH" {
            let stakingProtocols = DeFiProtocolRegistry.stakingProtocols
            for protocol_ in stakingProtocols.filter({ $0.chain == .ethereum }) {
                let estimatedApy = 3.5 + Double.random(in: 0...1.5)
                opportunities.append([
                    "protocol": protocol_.name,
                    "chain": protocol_.chain.displayName,
                    "type": "Liquid Staking",
                    "estimated_apy": String(format: "%.2f%%", estimatedApy),
                    "risk": "low",
                    "token": "ETH → stETH/rETH"
                ])
            }
        }
        
        let result: [String: Any] = [
            "token": tokenUpper,
            "min_apy_filter": minApy,
            "risk_filter": riskLevel ?? "all",
            "opportunities_count": opportunities.count,
            "opportunities": opportunities,
            "disclaimer": "APY estimates are approximations. Always verify current rates on protocol websites.",
            "timestamp": Self._isoFormatter.string(from: Date())
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return "Unable to fetch yield opportunities for \(tokenUpper)."
    }
    
    private func executeGetChainAnalysis(args: [String: Any]) async -> String {
        guard let walletAddress = args["wallet_address"] as? String,
              let chainStr = args["chain"] as? String else {
            return "Error: Missing required parameters 'wallet_address' and 'chain'."
        }
        
        // Map chain string to Chain enum
        let chain: Chain
        switch chainStr.lowercased() {
        case "ethereum", "eth": chain = .ethereum
        case "arbitrum", "arb": chain = .arbitrum
        case "polygon", "matic": chain = .polygon
        case "base": chain = .base
        case "optimism", "op": chain = .optimism
        case "solana", "sol": chain = .solana
        case "bsc", "bnb": chain = .bsc
        case "avalanche", "avax": chain = .avalanche
        default:
            return "Error: Unsupported chain '\(chainStr)'. Supported: ethereum, arbitrum, polygon, base, optimism, solana, bsc, avalanche."
        }
        
        var result: [String: Any] = [
            "wallet_address": walletAddress,
            "chain": chain.displayName,
            "native_token": chain.nativeSymbol,
            "timestamp": Self._isoFormatter.string(from: Date())
        ]
        
        // Get token balances (if aggregator available)
        let hasKey = await MainActor.run { DeFiAggregatorService.shared.hasAPIKey }
        if hasKey, let chainId = chain.debankChainId {
            do {
                let tokens = try await DeFiAggregatorService.shared.fetchTokenBalances(address: walletAddress, chainId: chainId)
                
                var tokenBalances: [[String: Any]] = []
                var totalValue: Double = 0
                
                for token in tokens.prefix(15) {
                    let value = token.valueUSD
                    totalValue += value
                    tokenBalances.append([
                        "symbol": token.symbol,
                        "name": token.name,
                        "amount": token.amount,
                        "value_usd": value
                    ])
                }
                
                result["token_balances"] = tokenBalances
                result["total_value_usd"] = totalValue
                result["token_count"] = tokens.count
                
            } catch {
                result["token_error"] = "Could not fetch token balances: \(error.localizedDescription)"
            }
        } else {
            result["note"] = "Token balance details require DeBank API key. Configure in Settings for full chain analysis."
        }
        
        // Add chain info
        result["chain_info"] = [
            "chain_id": chain.chainId ?? "N/A",
            "is_evm": chain.isEVM,
            "native_decimals": chain.nativeDecimals
        ]
        
        // Add explorer link
        if let explorerURL = chain.explorerURL(for: walletAddress) {
            result["explorer_url"] = explorerURL.absoluteString
        }
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return "Unable to analyze wallet on \(chain.displayName)."
    }
    
    private func executeGetSupportedChains() async -> String {
        var chains: [[String: Any]] = []
        
        // Layer 1 chains
        let l1Chains: [Chain] = [.ethereum, .bitcoin, .solana, .avalanche, .bsc, .fantom, .sui, .aptos, .ton, .near, .cosmos, .polkadot, .cardano, .tron]
        
        for chain in l1Chains {
            chains.append([
                "name": chain.displayName,
                "native_token": chain.nativeSymbol,
                "is_evm": chain.isEVM,
                "chain_id": chain.chainId ?? "N/A",
                "layer": "Layer 1"
            ])
        }
        
        // Layer 2 chains
        let l2Chains: [Chain] = [.arbitrum, .optimism, .base, .polygon, .zksync, .linea, .scroll, .manta, .mantle, .blast, .mode, .polygonZkEvm, .starknet]
        
        for chain in l2Chains {
            chains.append([
                "name": chain.displayName,
                "native_token": chain.nativeSymbol,
                "is_evm": chain.isEVM,
                "chain_id": chain.chainId ?? "N/A",
                "layer": "Layer 2"
            ])
        }
        
        // Cosmos ecosystem
        let cosmosChains: [Chain] = [.osmosis, .injective, .sei]
        for chain in cosmosChains {
            chains.append([
                "name": chain.displayName,
                "native_token": chain.nativeSymbol,
                "is_evm": chain.isEVM,
                "layer": "Cosmos Ecosystem"
            ])
        }
        
        let result: [String: Any] = [
            "total_chains": chains.count,
            "chains": chains,
            "note": "CryptoSage supports \(chains.count)+ blockchains for portfolio tracking, DeFi, and NFTs."
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return "Supported chains: Ethereum, Bitcoin, Solana, Arbitrum, Optimism, Base, Polygon, and 20+ more."
    }
    
    private func executeGetSupportedProtocols(args: [String: Any]) async -> String {
        let categoryFilter = args["category"] as? String
        let chainFilter = args["chain"] as? String
        
        var protocols: [[String: Any]] = []
        
        for protocol_ in DeFiProtocolRegistry.all {
            // Apply filters
            if let category = categoryFilter {
                guard protocol_.category.rawValue == category else { continue }
            }
            if let chain = chainFilter {
                guard protocol_.chain.rawValue.lowercased() == chain.lowercased() ||
                      protocol_.chain.displayName.lowercased() == chain.lowercased() else { continue }
            }
            
            protocols.append([
                "name": protocol_.name,
                "chain": protocol_.chain.displayName,
                "category": protocol_.category.rawValue,
                "website": protocol_.websiteURL ?? "N/A"
            ])
        }
        
        // Group by category for easier reading
        var byCategory: [String: [[String: Any]]] = [:]
        for p in protocols {
            let cat = p["category"] as? String ?? "other"
            if byCategory[cat] == nil {
                byCategory[cat] = []
            }
            byCategory[cat]?.append(p)
        }
        
        let result: [String: Any] = [
            "total_protocols": protocols.count,
            "by_category": byCategory,
            "categories": ["dex", "lending", "staking", "yield", "derivatives"],
            "note": "With DeBank integration, CryptoSage tracks 1000+ protocols. This list shows built-in protocol definitions."
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return "Supported protocols include Uniswap, Aave, Lido, GMX, PancakeSwap, and 50+ more across all major chains."
    }
    
    // MARK: - Web Search & URL Reading Implementations
    
    private func executeWebSearch(args: [String: Any]) async -> String {
        guard let query = args["query"] as? String, !query.isEmpty else {
            return "Error: Missing or empty 'query' parameter"
        }
        
        // Try Firebase first (preferred - no user API key needed, rate limited by subscription)
        if FirebaseService.shared.hasWebSearchCapability {
            do {
                let response = try await FirebaseService.shared.webSearch(query: query)
                let formattedResults = FirebaseService.shared.formatWebSearchForAI(response)
                
                if formattedResults.isEmpty {
                    return "No results found for: \(query)"
                }
                
                var result = """
                Search Results for: \(query)
                
                \(formattedResults)
                """
                
                // Include usage info if available
                if let used = response.dailyUsed, let limit = response.dailyLimit {
                    result += "\n\n(Web searches used today: \(used)/\(limit))"
                }
                
                return result
            } catch {
                // Log the error but continue to fallback
                print("Firebase web search error: \(error.localizedDescription)")
                
                // Check if it's a rate limit error
                if error.localizedDescription.contains("limit") {
                    return "Daily web search limit reached. Upgrade your subscription for more searches, or try again tomorrow."
                }
            }
        }
        
        // Fallback to direct Tavily if user has their own API key configured
        if APIConfig.hasValidTavilyKey {
            do {
                let response = try await TavilyService.shared.search(query: query, maxResults: 5)
                let formattedResults = TavilyService.shared.formatResultsForAI(response)
                
                if formattedResults.isEmpty {
                    return "No results found for: \(query)"
                }
                
                return """
                Search Results for: \(query)
                
                \(formattedResults)
                """
            } catch let error as TavilyError {
                return "Search error: \(error.localizedDescription)"
            } catch {
                return "Search failed: \(error.localizedDescription)"
            }
        }
        
        // No web search available
        return """
        Web search is currently unavailable. I can still help with:
        - Live crypto prices and market data
        - Portfolio analysis and recommendations
        - Technical analysis
        - General crypto knowledge
        
        For real-time news and current events, please check our News section or try again later.
        """
    }
    
    private func executeReadURL(args: [String: Any]) async -> String {
        guard let urlString = args["url"] as? String, !urlString.isEmpty else {
            return "Error: Missing or empty 'url' parameter"
        }
        
        guard let url = URL(string: urlString) else {
            return "Error: Invalid URL format: \(urlString)"
        }
        
        // Try Firebase first (rate limited by subscription)
        if FirebaseService.shared.hasWebSearchCapability {
            do {
                let response = try await FirebaseService.shared.readArticle(url: urlString)
                
                var result = """
                Article: \(response.title)
                URL: \(response.url)
                
                Content:
                \(response.content)
                """
                
                // Include usage info if available
                if let used = response.dailyUsed, let limit = response.dailyLimit {
                    result += "\n\n(Article reads used today: \(used)/\(limit))"
                }
                
                return result
            } catch {
                // Log error and fall through to local extraction
                print("Firebase read article error: \(error.localizedDescription)")
                
                // Check if it's a rate limit error
                if error.localizedDescription.contains("limit") {
                    return "Daily article read limit reached. Upgrade your subscription for more, or try again tomorrow."
                }
            }
        }
        
        // Fallback to local ArticleContentExtractor
        let content = await ArticleContentExtractor.shared.extract(from: url)
        
        if content.hasFullContent {
            return """
            Article: \(content.title)
            Source: \(content.source)
            URL: \(content.url.absoluteString)
            
            Content:
            \(content.content)
            """
        } else if !content.content.isEmpty {
            return """
            Article: \(content.title)
            Source: \(content.source)
            URL: \(content.url.absoluteString)
            
            Summary:
            \(content.content)
            
            Note: Full article content could not be extracted. This may be a paywalled or protected article.
            """
        } else {
            return """
            Could not extract content from: \(urlString)
            
            The page may be:
            - Behind a paywall or login
            - Using heavy JavaScript rendering
            - Blocking automated access
            
            Try asking me to search for information about this topic instead.
            """
        }
    }
}
