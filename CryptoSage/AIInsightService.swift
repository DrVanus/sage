//
//  AIInsightService.swift
//  CryptoSage
//
//  Created by DM on 5/28/25.
//
//  Provides AI-generated portfolio insights using OpenAI Chat Completions API.
//  Now supports Firebase backend for secure, cached AI responses.
//

import Foundation

/// Represents a single AI-generated insight text with its timestamp
struct AIInsight: Codable {
    let text: String
    let timestamp: Date
    
    init(text: String, timestamp: Date = Date()) {
        self.text = text
        self.timestamp = timestamp
    }
}

/// Error types for AIInsightService
enum AIInsightError: LocalizedError {
    case noAPIKey
    case encodingFailed
    case aiServiceFailed(String)
    case firebaseError(String)
    case authenticationRequired
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "AI service temporarily unavailable"
        case .encodingFailed:
            return "Failed to encode portfolio data"
        case .aiServiceFailed(let message):
            return "AI service error: \(message)"
        case .firebaseError(let message):
            return "Server error: \(message)"
        case .authenticationRequired:
            return "Sign in to get personalized portfolio insights"
        }
    }
}

/// Service responsible for fetching AI-generated portfolio insights
@MainActor
final class AIInsightService {
    static let shared = AIInsightService()
    
    // MARK: - Helpers
    
    /// Resolve a holding's display name — prefers commodity-friendly names (e.g., "Gold" not "GC=F")
    static func friendlyHoldingName(_ holding: Holding) -> String {
        let ticker = holding.ticker ?? holding.coinSymbol
        if let info = CommoditySymbolMapper.getCommodity(for: ticker) {
            return info.name
        }
        return holding.coinSymbol
    }
    
    // MARK: - Cache Keys
    private let cacheInsightKey = "AIInsightService.cachedInsight"
    private let cacheTimestampKey = "AIInsightService.cacheTimestamp"
    private let lastRequestKey = "AIInsightService.lastRequestTimestamp"
    
    // MARK: - Cache
    private var cachedInsight: AIInsight?
    private var cacheTimestamp: Date?
    private var lastSageContextHash: String?
    // COST OPTIMIZATION: Portfolio only changes when user trades, so long cache is fine
    // 4 hours = ~6 API calls/day max per active user (down from 24/day with 1hr cache)
    // At $0.015/call (gpt-4o-mini), saves ~$0.27/user/day
    private let cacheValiditySeconds: TimeInterval = 4 * 3600 // 4 hours (extended from 1 hour)
    
    // MARK: - Cooldown (prevents rapid refresh even if cache is cleared)
    private var lastRequestTimestamp: Date?
    /// Minimum time between portfolio insight requests (prevents rapid refresh)
    /// COST OPTIMIZATION: 30 min cooldown prevents spam while allowing occasional refresh
    private let minimumCooldownSeconds: TimeInterval = 30 * 60 // 30 minutes (extended from 10 min)
    
    private init() {
        loadCacheFromDisk()
    }
    
    // MARK: - Cache Persistence
    
    /// Load cached insight from disk on app launch
    private func loadCacheFromDisk() {
        let defaults = UserDefaults.standard
        
        // Load cached insight
        if let data = defaults.data(forKey: cacheInsightKey) {
            do {
                cachedInsight = try JSONDecoder().decode(AIInsight.self, from: data)
            } catch {
                print("[AIInsightService] Failed to load cached insight: \(error)")
            }
        }
        
        // Load cache timestamp
        cacheTimestamp = defaults.object(forKey: cacheTimestampKey) as? Date
        
        // Load last request timestamp
        lastRequestTimestamp = defaults.object(forKey: lastRequestKey) as? Date
        
        // Validate cache freshness
        if let timestamp = cacheTimestamp,
           Date().timeIntervalSince(timestamp) >= cacheValiditySeconds {
            // Cache is stale, clear it
            cachedInsight = nil
            cacheTimestamp = nil
        }
        
        #if DEBUG
        if cachedInsight != nil {
            print("[AIInsightService] Loaded cached portfolio insight from disk")
        }
        #endif
    }
    
    /// Save cached insight to disk
    private func saveCacheToDisk() {
        let defaults = UserDefaults.standard
        
        if let insight = cachedInsight {
            do {
                let data = try JSONEncoder().encode(insight)
                defaults.set(data, forKey: cacheInsightKey)
            } catch {
                print("[AIInsightService] Failed to save cached insight: \(error)")
            }
        } else {
            defaults.removeObject(forKey: cacheInsightKey)
        }
        
        defaults.set(cacheTimestamp, forKey: cacheTimestampKey)
        defaults.set(lastRequestTimestamp, forKey: lastRequestKey)
    }
    
    // MARK: - Public Methods
    
    /// Generate an AI insight for the given portfolio
    /// - Parameter portfolio: The portfolio data to analyze
    /// - Returns: An AIInsight with analysis text
    func fetchInsight(for portfolio: Portfolio) async throws -> AIInsight {
        // Check cache first
        if let cached = cachedInsight,
           let timestamp = cacheTimestamp,
           Date().timeIntervalSince(timestamp) < cacheValiditySeconds {
            // Track cache hit (cost savings)
            AnalyticsService.shared.trackAIFeatureUsage(
                feature: .portfolioInsight,
                model: "gpt-4o-mini",
                maxTokens: 256,
                tier: SubscriptionManager.shared.effectiveTier,
                cached: true
            )
            return cached
        }
        
        // Cooldown check: prevent rapid requests even if cache was cleared
        // This protects against users rapidly refreshing and burning API costs
        if !SubscriptionManager.shared.isDeveloperMode {
            if let lastRequest = lastRequestTimestamp,
               Date().timeIntervalSince(lastRequest) < minimumCooldownSeconds {
                // Track cooldown triggered (cost savings)
                AnalyticsService.shared.trackAICooldownTriggered(
                    feature: .portfolioInsight,
                    tier: SubscriptionManager.shared.effectiveTier
                )
                // Return stale cached insight if within cooldown
                if let cached = cachedInsight {
                    return cached
                }
                throw AIInsightError.aiServiceFailed("Please wait before refreshing again")
            }
        }
        
        // FIREBASE: Try Firebase backend first for authenticated users
        // Portfolio insights are personalized, so they require authentication
        if FirebaseService.shared.useFirebaseForAI,
           AuthenticationManager.shared.isAuthenticated {
            do {
                let insight = try await fetchInsightViaFirebase(for: portfolio)
                return insight
            } catch FirebaseServiceError.authenticationRequired {
                // Fall through to direct API call
                print("[AIInsightService] Firebase auth required, falling back to direct API")
            } catch {
                // Log Firebase error but fall through to direct API
                print("[AIInsightService] Firebase error: \(error.localizedDescription), falling back to direct API")
            }
        }
        
        // FALLBACK: Direct OpenAI call (legacy behavior)
        // Check for API key - if missing, use dynamic fallback
        guard APIConfig.hasValidOpenAIKey else {
            // Generate a dynamic fallback insight based on portfolio data
            let fallbackText = generatePortfolioFallbackInsight(for: portfolio)
            let insight = AIInsight(text: fallbackText, timestamp: Date())
            cachedInsight = insight
            cacheTimestamp = Date()
            saveCacheToDisk()
            return insight
        }
        
        // Build the insight prompt
        let prompt = buildInsightPrompt(for: portfolio)
        
        // Use AIService to get the insight
        do {
            // OPTIMIZED PROMPT: More specific, encourages variety, focuses on actionable advice
            let insightTypes = ["risk assessment", "rebalancing opportunity", "market timing", "concentration risk", "momentum play", "defensive move"]
            let focusType = insightTypes.randomElement() ?? "key observation"
            
            let systemPrompt = """
            You are a crypto portfolio analyst. Give ONE specific, actionable insight in 2 sentences max.
            Focus on: \(focusType).
            Rules:
            - Be specific (mention actual coins from their holdings)
            - Give a concrete action (buy, sell, hold, rebalance)
            - Never be generic like "diversify more" without specifics
            - Never mention exact dollar amounts for privacy
            """
            
            let response = try await AIService.shared.sendMessage(
                prompt,
                systemPrompt: systemPrompt,
                usePremiumModel: false, // Use gpt-4o-mini for cost efficiency
                includeTools: false, // No tools needed for simple insight generation
                isAutomatedFeature: false, // Use Firebase backend for all users
                maxTokens: 256 // Reduced from 2048 - portfolio insights are brief (2-3 sentences)
            )
            
            let insight = AIInsight(text: response, timestamp: Date())
            
            // Cache the result and persist to disk
            cachedInsight = insight
            cacheTimestamp = Date()
            
            // Update cooldown timestamp
            lastRequestTimestamp = Date()
            saveCacheToDisk()
            
            // Track AI usage for cost analysis
            AnalyticsService.shared.trackAIFeatureUsage(
                feature: .portfolioInsight,
                model: "gpt-4o-mini",
                maxTokens: 256,
                tier: SubscriptionManager.shared.effectiveTier,
                cached: false
            )
            
            return insight
        } catch {
            throw AIInsightError.aiServiceFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Firebase Backend
    
    /// Fetch portfolio insight via Firebase Cloud Function
    /// This is the preferred method when user is authenticated
    private func fetchInsightViaFirebase(for portfolio: Portfolio) async throws -> AIInsight {
        // Build holdings data for Firebase
        let holdings: [[String: Any]] = portfolio.holdings.prefix(10).map { holding in
            [
                "symbol": holding.coinSymbol,
                "value": holding.currentValue,
                "change24h": holding.dailyChange
            ]
        }
        
        let totalValue = portfolio.holdings.reduce(0) { $0 + $1.currentValue }
        let marketVM = MarketViewModel.shared
        
        let response = try await FirebaseService.shared.getPortfolioInsight(
            holdings: holdings,
            totalValue: totalValue,
            btcDominance: marketVM.btcDominance,
            marketCap: marketVM.globalMarketCap
        )
        
        let insight = AIInsight(text: response.content, timestamp: Date())
        
        // Cache the result and persist to disk
        cachedInsight = insight
        cacheTimestamp = Date()
        lastRequestTimestamp = Date()
        saveCacheToDisk()
        
        // Track usage with actual model from Firebase response
        AnalyticsService.shared.trackAIFeatureUsage(
            feature: .portfolioInsight,
            model: response.model ?? "gpt-4o-mini", // Personalized content uses gpt-4o-mini
            maxTokens: 256,
            tier: SubscriptionManager.shared.effectiveTier,
            cached: response.cached
        )
        
        return insight
    }
    
    /// Generate an insight for a PortfolioViewModel (convenience method)
    func fetchInsight(for portfolioVM: PortfolioViewModel) async throws -> AIInsight {
        return try await fetchInsight(for: portfolioVM.portfolio)
    }
    
    /// Clear the cached insight
    func clearCache() {
        cachedInsight = nil
        cacheTimestamp = nil
        lastRequestTimestamp = nil
        saveCacheToDisk()
    }
    
    // MARK: - Private Methods
    
    private func buildInsightPrompt(for portfolio: Portfolio) -> String {
        // OPTIMIZED: Streamlined prompt uses ~40% fewer tokens while keeping essential context
        var parts: [String] = []
        
        // Holdings summary (compact format)
        if !portfolio.holdings.isEmpty {
            let sortedHoldings = portfolio.holdings.sorted { $0.currentValue > $1.currentValue }
            let totalValue = portfolio.holdings.reduce(0) { $0 + $1.currentValue }
            
            // Compact holdings list with allocation %
            let holdingsList = sortedHoldings.prefix(8).map { holding -> String in
                let pct = totalValue > 0 ? (holding.currentValue / totalValue) * 100 : 0
                let change = holding.dailyChange
                return "\(Self.friendlyHoldingName(holding)) \(String(format: "%.0f", pct))% (\(change >= 0 ? "+" : "")\(String(format: "%.1f", change))%)"
            }.joined(separator: ", ")
            
            parts.append("Holdings: \(holdingsList)")
            
            if portfolio.holdings.count > 8 {
                parts.append("+\(portfolio.holdings.count - 8) more")
            }
        } else {
            return "Empty portfolio - no holdings to analyze."
        }
        
        // Market context (compact)
        let marketVM = MarketViewModel.shared
        var marketContext: [String] = []
        if let btcDom = marketVM.btcDominance, btcDom > 0 {
            marketContext.append("BTC dom: \(String(format: "%.0f", btcDom))%")
        }
        
        // Market regime (valuable context)
        if let btc = marketVM.allCoins.first(where: { $0.symbol.uppercased() == "BTC" }),
           btc.sparklineIn7d.count >= 20 {
            let regime = MarketRegimeDetector.detectRegime(closes: btc.sparklineIn7d)
            marketContext.append("Market: \(regime.regime.displayName)")
        }
        
        // Whale activity (only if significant)
        let whaleService = WhaleTrackingService.shared
        if let smi = whaleService.smartMoneyIndex {
            let trend = smi.score >= 60 ? "accumulating" : (smi.score <= 40 ? "distributing" : "neutral")
            marketContext.append("Whales: \(trend)")
        }
        
        if !marketContext.isEmpty {
            parts.append("Market: " + marketContext.joined(separator: ", "))
        }
        
        // Recent activity hint
        if !portfolio.transactions.isEmpty {
            let recentCount = portfolio.transactions.filter { 
                Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .weekOfYear) 
            }.count
            if recentCount > 0 {
                parts.append("Recent trades: \(recentCount) this week")
            }
        }
        
        return parts.joined(separator: "\n")
    }
    
    /// Generates a dynamic fallback insight when AI is unavailable
    /// Uses portfolio data to provide meaningful analysis without API calls
    private func generatePortfolioFallbackInsight(for portfolio: Portfolio) -> String {
        guard !portfolio.holdings.isEmpty else {
            return "Add holdings to get personalized portfolio insights."
        }
        
        let sortedHoldings = portfolio.holdings.sorted { $0.currentValue > $1.currentValue }
        let totalValue = portfolio.holdings.reduce(0) { $0 + $1.currentValue }
        
        var observations: [String] = []
        
        // Concentration analysis
        if let topHolding = sortedHoldings.first, totalValue > 0 {
            let topPct = (topHolding.currentValue / totalValue) * 100
            // Resolve commodity tickers to friendly names (e.g., "GC=F" → "Gold")
            let topName: String = {
                let ticker = topHolding.ticker ?? topHolding.coinSymbol
                if let info = CommoditySymbolMapper.getCommodity(for: ticker) {
                    return info.name
                }
                return topHolding.coinSymbol
            }()
            if topPct > 50 {
                observations.append("\(topName) dominates at \(Int(topPct))% — consider diversifying to reduce single-asset risk.")
            } else if topPct > 30 {
                observations.append("\(topName) leads at \(Int(topPct))% — moderate concentration, monitor closely.")
            }
        }
        
        // Performance analysis
        let gainers = sortedHoldings.filter { $0.dailyChange > 0 }
        let losers = sortedHoldings.filter { $0.dailyChange < 0 }
        
        if let topGainer = gainers.max(by: { $0.dailyChange < $1.dailyChange }) {
            if topGainer.dailyChange > 5 {
                let gainerName = Self.friendlyHoldingName(topGainer)
                observations.append("\(gainerName) up \(String(format: "%.1f", topGainer.dailyChange))% — consider taking partial profits on extended moves.")
            }
        }
        
        if let topLoser = losers.min(by: { $0.dailyChange < $1.dailyChange }) {
            if topLoser.dailyChange < -5 {
                let loserName = Self.friendlyHoldingName(topLoser)
                observations.append("\(loserName) down \(String(format: "%.1f", abs(topLoser.dailyChange)))% — evaluate if thesis still holds.")
            }
        }
        
        // Market sentiment context
        if let sentiment = ExtendedFearGreedViewModel.shared.currentValue,
           let classification = ExtendedFearGreedViewModel.shared.currentClassificationKey {
            if sentiment < 30 {
                observations.append("Market in \(classification) (\(sentiment)) — historically good for DCA accumulation.")
            } else if sentiment > 70 {
                observations.append("Market in \(classification) (\(sentiment)) — consider tightening stops on positions.")
            }
        }
        
        // Default observation if nothing notable
        if observations.isEmpty {
            let holdingsCount = portfolio.holdings.count
            observations.append("Portfolio holds \(holdingsCount) asset\(holdingsCount == 1 ? "" : "s"). Review allocations periodically to stay aligned with your strategy.")
        }
        
        return observations.first ?? "Portfolio analysis available when AI is connected."
    }
    
    private func formatCurrency(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "$%.2f", value)
        } else if value >= 1 {
            return String(format: "$%.2f", value)
        } else {
            return String(format: "$%.4f", value)
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
}

// MARK: - CryptoSage AI Algorithm Integration

extension AIInsightService {
    
    /// Generate insight that incorporates Sage algorithm signals
    /// This enhances portfolio insights with algorithmic analysis
    func fetchInsightWithSageSignals(
        for portfolio: Portfolio,
        sageConsensus: [String: SageConsensus]? = nil
    ) async throws -> AIInsight {
        // If no Sage signals available, fall back to regular insight
        guard let consensus = sageConsensus, !consensus.isEmpty else {
            return try await fetchInsight(for: portfolio)
        }

        // Check cache with Sage context
        let currentHash = buildSageContextHash(consensus)
        if let cached = cachedInsight,
           let timestamp = cacheTimestamp,
           Date().timeIntervalSince(timestamp) < cacheValiditySeconds,
           lastSageContextHash == currentHash {
            return cached
        }

        // Cooldown check: prevent rapid requests even if cache was cleared
        if !SubscriptionManager.shared.isDeveloperMode {
            if let lastRequest = lastRequestTimestamp,
               Date().timeIntervalSince(lastRequest) < minimumCooldownSeconds {
                AnalyticsService.shared.trackAICooldownTriggered(
                    feature: .portfolioInsight,
                    tier: SubscriptionManager.shared.effectiveTier
                )
                if let cached = cachedInsight {
                    return cached
                }
                throw AIInsightError.aiServiceFailed("Please wait before refreshing again")
            }
        }
        
        // Build enhanced prompt with Sage signals
        let prompt = buildInsightPromptWithSage(for: portfolio, consensus: consensus)
        
        // Generate insight
        let insightTypes = ["algorithmic analysis", "signal confluence", "regime-based recommendation", "risk-adjusted outlook"]
        let focusType = insightTypes.randomElement() ?? "algorithmic analysis"
        
        let systemPrompt = """
        You are CryptoSage AI, combining portfolio analysis with algorithmic trading signals.
        Give ONE specific, actionable insight in 2-3 sentences.
        Focus on: \(focusType).
        Rules:
        - Reference the CryptoSage AI algorithm signals when relevant
        - Explain WHY the algorithms suggest their recommendations
        - Be specific about which coins are affected
        - Mention the market regime if it affects the recommendation
        - Never be generic - tie insights to the actual signals
        """
        
        do {
            let response = try await AIService.shared.sendMessage(
                prompt,
                systemPrompt: systemPrompt,
                usePremiumModel: false,
                includeTools: false,
                isAutomatedFeature: false, // Use Firebase backend for all users
                maxTokens: 300
            )
            
            let insight = AIInsight(text: response, timestamp: Date())
            cachedInsight = insight
            cacheTimestamp = Date()
            lastRequestTimestamp = Date()
            lastSageContextHash = currentHash
            saveCacheToDisk()

            return insight
        } catch {
            throw AIInsightError.aiServiceFailed(error.localizedDescription)
        }
    }

    /// Generate a standalone Sage signal explanation
    /// Used when user wants to understand an algorithm's recommendation
    func explainSageSignal(_ consensus: SageConsensus) async throws -> String {
        let prompt = buildSageExplanationPrompt(consensus)
        
        let systemPrompt = """
        You are CryptoSage AI explaining your trading signal analysis.
        Provide a clear, educational explanation in 3-4 sentences.
        Rules:
        - Explain the signal type and confidence level
        - Mention which algorithms contributed most
        - Explain the market regime and why it matters
        - Give context on the risk management suggestions
        - Be accessible to users who aren't trading experts
        """
        
        do {
            let response = try await AIService.shared.sendMessage(
                prompt,
                systemPrompt: systemPrompt,
                usePremiumModel: false,
                includeTools: false,
                isAutomatedFeature: false, // Use Firebase backend for all users
                maxTokens: 400
            )
            return response
        } catch {
            // Return a fallback explanation based on the data
            return generateFallbackSageExplanation(consensus)
        }
    }
    
    // MARK: - Private Sage Helpers
    
    private func buildInsightPromptWithSage(for portfolio: Portfolio, consensus: [String: SageConsensus]) -> String {
        var parts: [String] = []
        
        // Portfolio context (compact)
        if !portfolio.holdings.isEmpty {
            let sortedHoldings = portfolio.holdings.sorted { $0.currentValue > $1.currentValue }
            let totalValue = portfolio.holdings.reduce(0) { $0 + $1.currentValue }
            
            let holdingsList = sortedHoldings.prefix(5).map { holding -> String in
                let pct = totalValue > 0 ? (holding.currentValue / totalValue) * 100 : 0
                return "\(Self.friendlyHoldingName(holding)) \(String(format: "%.0f", pct))%"
            }.joined(separator: ", ")
            
            parts.append("Portfolio: \(holdingsList)")
        }
        
        // Sage algorithm signals
        parts.append("\nCryptoSage AI Algorithm Signals:")
        
        for (symbol, signal) in consensus.prefix(3) {
            let signalDesc = """
            \(symbol): \(signal.masterSignal.displayName) (\(Int(signal.confidence))% confidence)
            - Regime: \(signal.regime.displayName)
            - Bullish algorithms: \(signal.bullishCount)/5
            - Bearish algorithms: \(signal.bearishCount)/5
            - Suggested position: \(Int(signal.suggestedPositionSize))%
            """
            parts.append(signalDesc)
        }
        
        return parts.joined(separator: "\n")
    }
    
    private func buildSageExplanationPrompt(_ consensus: SageConsensus) -> String {
        return """
        Explain this CryptoSage AI analysis for \(consensus.symbol):
        
        Signal: \(consensus.masterSignal.displayName) with \(Int(consensus.confidence))% confidence
        Market Regime: \(consensus.regime.displayName) - \(consensus.regime.description)
        
        Algorithm Scores:
        - Sage Trend: \(Int(consensus.trendScore)) (trend-following analysis)
        - Sage Momentum: \(Int(consensus.momentumScore)) (momentum factors)
        - Sage Reversion: \(Int(consensus.reversionScore)) (mean reversion)
        - Sage Confluence: \(Int(consensus.confluenceScore)) (multi-timeframe)
        - Sage Volatility: \(Int(consensus.volatilityScore)) (volatility breakout)
        
        Sentiment Score: \(Int(consensus.sentimentScore)) (Fear/Greed contrarian)
        Algorithm Agreement: \(Int(consensus.agreementLevel * 100))%
        
        Risk Management:
        - Suggested Position Size: \(Int(consensus.suggestedPositionSize))%
        - Stop Loss: \(String(format: "%.1f", consensus.suggestedStopLoss))%
        - Take Profit: \(String(format: "%.1f", consensus.suggestedTakeProfit))%
        
        Explain this analysis to help the user understand the recommendation.
        """
    }
    
    private func generateFallbackSageExplanation(_ consensus: SageConsensus) -> String {
        var explanation = "CryptoSage AI analysis for \(consensus.symbol): "
        
        // Signal interpretation
        switch consensus.masterSignal {
        case .strongBuy:
            explanation += "Strong buying opportunity detected. "
        case .buy:
            explanation += "Favorable conditions for buying. "
        case .hold:
            explanation += "Current levels suggest holding position. "
        case .sell:
            explanation += "Consider reducing exposure. "
        case .strongSell:
            explanation += "Elevated risk detected - consider exiting. "
        }
        
        // Regime context
        explanation += "Market is in \(consensus.regime.displayName.lowercased()) regime. "
        
        // Algorithm agreement
        if consensus.agreementLevel > 0.7 {
            explanation += "High algorithm agreement (\(Int(consensus.agreementLevel * 100))%) increases signal confidence. "
        } else if consensus.agreementLevel < 0.4 {
            explanation += "Mixed signals from algorithms suggest caution. "
        }
        
        // Risk guidance
        explanation += "Suggested position: \(Int(consensus.suggestedPositionSize))% with \(String(format: "%.1f", consensus.suggestedStopLoss))% stop loss."
        
        return explanation
    }
    
    private func buildSageContextHash(_ consensus: [String: SageConsensus]) -> String {
        // Create a simple hash for cache differentiation
        let signals = consensus.values.map { "\($0.symbol)_\($0.masterSignal.rawValue)" }
        return signals.joined(separator: "_")
    }
}

// MARK: - Legacy API Support

extension AIInsightService {
    /// Legacy method for generic Encodable types (kept for backwards compatibility)
    func fetchInsight<T: Encodable>(for portfolio: T) async throws -> AIInsight {
        // Try to convert to Portfolio type
        if let portfolioData = portfolio as? Portfolio {
            return try await fetchInsight(for: portfolioData)
        }
        
        // For other types, create a generic prompt
        guard APIConfig.hasValidOpenAIKey else {
            throw AIInsightError.noAPIKey
        }
        
        // Encode to JSON for context
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        guard let jsonData = try? encoder.encode(portfolio),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw AIInsightError.encodingFailed
        }
        
        let prompt = """
        Analyze this cryptocurrency portfolio data and provide one key insight:
        
        \(jsonString)
        
        Provide a brief, actionable insight.
        """
        
        let systemPrompt = """
        You are a professional cryptocurrency portfolio analyst. Provide a concise, actionable insight. \
        Keep the response to 2-3 sentences maximum. Be direct and specific.
        """
        
        let response = try await AIService.shared.sendMessage(
            prompt,
            systemPrompt: systemPrompt,
            usePremiumModel: false,
            includeTools: false,
            isAutomatedFeature: false, // Use Firebase backend for all users
            maxTokens: 256 // Brief portfolio insights
        )
        
        return AIInsight(text: response, timestamp: Date())
    }
}
