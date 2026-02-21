//
//  PriceMovementExplainer.swift
//  CryptoSage
//
//  Service and UI for explaining sudden price movements.
//  Combines news, market data, and AI analysis to provide
//  context for significant price changes.
//

import SwiftUI
import Foundation

// MARK: - Movement Explanation Model

/// A structured explanation for a price movement
public struct PriceMovementExplanation: Codable, Identifiable {
    public let id: String
    public let coinSymbol: String
    public let coinName: String
    public let priceChange24h: Double
    public let currentPrice: Double
    public let explanationSummary: String
    public let possibleReasons: [MovementReason]
    public let relatedNews: [RelatedNewsItem]
    public let marketContext: MarketContextInfo?
    public let generatedAt: Date
    
    /// Whether this is a significant movement worth explaining
    public var isSignificant: Bool {
        abs(priceChange24h) >= 5.0 // 5% threshold
    }
    
    /// Movement direction
    public var direction: MovementDirection {
        if priceChange24h > 3 { return .up }
        if priceChange24h < -3 { return .down }
        return .sideways
    }
    
    /// Formatted change string
    public var formattedChange: String {
        let sign = priceChange24h >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", priceChange24h))%"
    }
}

/// Direction of price movement
public enum MovementDirection: String, Codable {
    case up = "up"
    case down = "down"
    case sideways = "sideways"
    
    public var icon: String {
        switch self {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .sideways: return "arrow.right"
        }
    }
    
    public var color: Color {
        switch self {
        case .up: return .green
        case .down: return .red
        case .sideways: return .yellow
        }
    }
    
    public var label: String {
        switch self {
        case .up: return "Rising"
        case .down: return "Falling"
        case .sideways: return "Stable"
        }
    }
}

/// A possible reason for the price movement
public struct MovementReason: Codable, Identifiable {
    public let id: String
    public let category: ReasonCategory
    public let title: String
    public let description: String
    public let confidence: ReasonConfidence
    public let impact: ReasonImpact
    
    public init(category: ReasonCategory, title: String, description: String, confidence: ReasonConfidence, impact: ReasonImpact) {
        self.id = UUID().uuidString
        self.category = category
        self.title = title
        self.description = description
        self.confidence = confidence
        self.impact = impact
    }
}

public enum ReasonCategory: String, Codable {
    case news = "news"
    case whale = "whale"
    case technical = "technical"
    case sentiment = "sentiment"
    case market = "market"
    case regulatory = "regulatory"
    case exchange = "exchange"
    case retail = "retail"
    case other = "other"
    
    public var icon: String {
        switch self {
        case .news: return "newspaper.fill"
        case .whale: return "fish.fill"
        case .technical: return "chart.xyaxis.line"
        case .sentiment: return "heart.fill"
        case .market: return "chart.bar.fill"
        case .regulatory: return "building.columns.fill"
        case .exchange: return "arrow.left.arrow.right.circle.fill"
        case .retail: return "person.3.fill"
        case .other: return "questionmark.circle.fill"
        }
    }
    
    public var color: Color {
        switch self {
        case .news: return .blue
        case .whale: return .purple
        case .technical: return .orange
        case .sentiment: return .pink
        case .market: return .cyan
        case .regulatory: return .red
        case .exchange: return .green
        case .retail: return .teal
        case .other: return .gray
        }
    }
}

public enum ReasonConfidence: String, Codable {
    case high = "high"
    case medium = "medium"
    case low = "low"
    
    public var label: String {
        switch self {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }
}

public enum ReasonImpact: String, Codable {
    case positive = "positive"
    case negative = "negative"
    case neutral = "neutral"
    
    public var color: Color {
        switch self {
        case .positive: return .green
        case .negative: return .red
        case .neutral: return .gray
        }
    }
}

/// Related news item for context
public struct RelatedNewsItem: Codable, Identifiable {
    public let id: String
    public let title: String
    public let source: String
    public let publishedAt: Date?
    public let url: String?
    
    public init(title: String, source: String, publishedAt: Date?, url: String?) {
        self.id = UUID().uuidString
        self.title = title
        self.source = source
        self.publishedAt = publishedAt
        self.url = url
    }
}

/// Market context information
public struct MarketContextInfo: Codable {
    public let btcChange24h: Double?
    public let ethChange24h: Double?
    public let fearGreedIndex: Int?
    public let marketCapChange24h: Double?
    public let isMarketWideMove: Bool
}

// MARK: - Price Movement Explainer Service

@MainActor
public final class PriceMovementExplainer: ObservableObject {
    public static let shared = PriceMovementExplainer()
    
    // MARK: - Published Properties
    
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var lastExplanation: PriceMovementExplanation?
    @Published public private(set) var cachedExplanations: [String: PriceMovementExplanation] = [:]
    
    // MARK: - Cache Configuration
    // Local in-memory cache prevents redundant Firebase calls within the same session.
    // Firebase handles the shared server-side cache (TTL managed backend-side).
    // Keep this shorter so auto-refresh can fetch updated Firebase data regularly.
    private let cacheValiditySeconds: TimeInterval = 30 * 60 // 30 minutes local cache
    private var cacheTimestamps: [String: Date] = [:]
    
    // MARK: - Daily Limit Tracking
    
    /// Daily explanation limits per subscription tier (uses centralized SubscriptionManager values)
    private func dailyLimit(for tier: SubscriptionTierType) -> Int {
        tier.priceMovementExplainersPerDay
    }
    
    private let usageKey = "PriceMovement.UsageToday"
    private let usageResetKey = "PriceMovement.LastUsageResetDate"
    @Published public private(set) var explanationsUsedToday: Int = 0
    private var lastResetDate: Date = Date()
    
    /// Current user's daily explanation limit
    public var currentDailyLimit: Int {
        dailyLimit(for: SubscriptionManager.shared.effectiveTier)
    }
    
    /// Whether user can generate a new explanation
    public var canGenerateExplanation: Bool {
        // Developer mode bypasses all limits
        if SubscriptionManager.shared.isDeveloperMode { return true }
        checkDailyReset()
        return explanationsUsedToday < currentDailyLimit
    }
    
    /// Remaining explanations for today
    public var remainingExplanations: Int {
        checkDailyReset()
        return max(0, currentDailyLimit - explanationsUsedToday)
    }
    
    private func checkDailyReset() {
        if !Calendar.current.isDateInToday(lastResetDate) {
            explanationsUsedToday = 0
            lastResetDate = Date()
            saveUsageState()
        }
    }
    
    private func loadUsageState() {
        explanationsUsedToday = UserDefaults.standard.integer(forKey: usageKey)
        if let date = UserDefaults.standard.object(forKey: usageResetKey) as? Date {
            lastResetDate = date
        }
        checkDailyReset()
    }
    
    private func saveUsageState() {
        UserDefaults.standard.set(explanationsUsedToday, forKey: usageKey)
        UserDefaults.standard.set(lastResetDate, forKey: usageResetKey)
    }
    
    private func recordUsage() {
        // Don't count usage in developer mode (allows unlimited testing)
        if SubscriptionManager.shared.isDeveloperMode { return }
        checkDailyReset()
        explanationsUsedToday += 1
        saveUsageState()
    }
    
    // MARK: - Initialization
    
    private init() {
        loadUsageState()
    }
    
    // MARK: - Public API
    
    /// Get explanation for a coin's price movement
    /// Uses Firebase shared caching - first user triggers AI, all subsequent users get cached result
    public func explain(
        symbol: String,
        coinName: String,
        forceRefresh: Bool = false
    ) async throws -> PriceMovementExplanation {
        let key = symbol.uppercased()
        
        // STEP 1: Check local in-memory cache first (fastest)
        if !forceRefresh,
           let cached = cachedExplanations[key],
           let timestamp = cacheTimestamps[key],
           Date().timeIntervalSince(timestamp) < cacheValiditySeconds {
            #if DEBUG
            print("[PriceMovementExplainer] Using local cache for \(key)")
            #endif
            return cached
        }
        
        // Check coin restriction for free tier users
        // Developer mode bypasses coin restrictions for testing
        if !SubscriptionManager.shared.isDeveloperMode {
            guard SubscriptionManager.shared.canAccessAIForCoin(symbol) else {
                throw NSError(domain: "PriceMovementExplainer", code: -4,
                             userInfo: [NSLocalizedDescriptionKey: "Price movement explanations for \(symbol.uppercased()) require Pro. Upgrade to unlock all coins, or try BTC, ETH, SOL, XRP, or BNB."])
            }
        }
        
        // Check daily limit before making API call (Firebase cached results don't count)
        guard canGenerateExplanation else {
            throw NSError(domain: "PriceMovementExplainer", code: -3,
                         userInfo: [NSLocalizedDescriptionKey: "Daily limit reached (\(currentDailyLimit) explanations/day). Try again tomorrow or upgrade your plan."])
        }
        
        isLoading = true
        defer { isLoading = false }
        
        // PERFORMANCE: Gather market data, market context, and news IN PARALLEL
        // Previously these ran sequentially, adding several seconds of latency
        async let marketDataTask = gatherMarketData(symbol: symbol)
        async let marketContextTask = gatherMarketContext()
        async let recentNewsTask = gatherRecentNews(symbol: symbol, coinName: coinName)
        
        let (marketData, marketContext, recentNews) = await (marketDataTask, marketContextTask, recentNewsTask)
        
        // CRITICAL VALIDATION: Never send $0 or 0% data to Firebase
        // If we do, the AI generates a meaningless "no change at $0" explanation
        // that gets cached for 2+ hours and shown to ALL users.
        guard marketData.currentPrice > 0 else {
            throw NSError(domain: "PriceMovementExplainer", code: -5,
                         userInfo: [NSLocalizedDescriptionKey: "Market data is still loading. Please wait a moment and try again."])
        }
        
        // STEP 2: Try Firebase shared cache (shared across ALL users)
        // First user triggers AI generation, subsequent users get cached result
        let firebaseService = FirebaseService.shared
        if firebaseService.isConfigured {
            do {
                #if DEBUG
                print("[PriceMovementExplainer] Trying Firebase shared cache for \(key)")
                #endif
                
                let response = try await firebaseService.getPriceMovementExplanation(
                    symbol: symbol,
                    coinName: coinName,
                    currentPrice: marketData.currentPrice,
                    change24h: marketData.change24h,
                    change7d: marketData.change7d,
                    volume24h: marketData.volume24h,
                    btcChange24h: marketContext.btcChange24h,
                    ethChange24h: marketContext.ethChange24h,
                    fearGreedIndex: marketContext.fearGreedIndex,
                    smartMoneyScore: marketData.smartMoneyScore,
                    exchangeFlowSentiment: marketData.exchangeFlowSentiment,
                    marketRegime: marketData.marketRegime?.rawValue
                )
                
                // Convert Firebase response to our model
                let explanation = convertFirebaseResponse(
                    response: response,
                    symbol: symbol,
                    coinName: coinName,
                    marketData: marketData,
                    marketContext: marketContext,
                    relatedNews: recentNews
                )
                
                // Cache locally
                self.cachedExplanations[key] = explanation
                self.cacheTimestamps[key] = Date()
                self.lastExplanation = explanation
                
                // Only count against daily limit if Firebase generated fresh (not cached)
                if !response.cached {
                    self.recordUsage()
                }
                
                #if DEBUG
                print("[PriceMovementExplainer] Firebase \(response.cached ? "cache hit" : "generated fresh") for \(key)")
                #endif
                
                return explanation
            } catch {
                #if DEBUG
                print("[PriceMovementExplainer] Firebase failed, falling back to local: \(error.localizedDescription)")
                #endif
                // Fall through to local generation
            }
        }
        
        // STEP 3: Fallback to local AI generation
        // This path is used when Firebase is unavailable or fails
        let explanationTask = Task { () -> PriceMovementExplanation in
            try Task.checkCancellation()
            
            // Generate explanation using AI (news already gathered above)
            let explanation = try await self.generateExplanation(
                symbol: symbol,
                coinName: coinName,
                marketData: marketData,
                recentNews: recentNews,
                marketContext: marketContext
            )
            
            return explanation
        }
        
        // Timeout task
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: 30_000_000_000) // 30 second timeout
            explanationTask.cancel()
        }
        
        do {
            let result = try await explanationTask.value
            timeoutTask.cancel()
            
            // Cache result and record usage
            self.cachedExplanations[key] = result
            self.cacheTimestamps[key] = Date()
            self.lastExplanation = result
            self.recordUsage()
            
            return result
        } catch is CancellationError {
            throw NSError(domain: "PriceMovementExplainer", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Request timed out. Please try again."])
        } catch {
            timeoutTask.cancel()
            throw error
        }
    }
    
    /// Returns a stale cached explanation if available (for optimistic UI loading)
    public func cachedExplanation(for symbol: String) -> PriceMovementExplanation? {
        let key = symbol.uppercased()
        return cachedExplanations[key]
    }
    
    /// Convert Firebase response to our local PriceMovementExplanation model
    private func convertFirebaseResponse(
        response: PriceMovementExplanationResponse,
        symbol: String,
        coinName: String,
        marketData: MarketDataForExplanation,
        marketContext: MarketContextInfo,
        relatedNews: [RelatedNewsItem] = []
    ) -> PriceMovementExplanation {
        // Convert Firebase reasons to our local model
        let reasons: [MovementReason] = response.reasons.map { r in
            MovementReason(
                category: ReasonCategory(rawValue: r.category.lowercased()) ?? .other,
                title: r.title,
                description: r.description,
                confidence: ReasonConfidence(rawValue: r.confidence.lowercased()) ?? .medium,
                impact: ReasonImpact(rawValue: r.impact.lowercased()) ?? .neutral
            )
        }
        
        return PriceMovementExplanation(
            id: UUID().uuidString,
            coinSymbol: symbol.uppercased(),
            coinName: coinName,
            priceChange24h: marketData.change24h,
            currentPrice: marketData.currentPrice,
            explanationSummary: response.summary,
            possibleReasons: reasons,
            relatedNews: relatedNews,
            marketContext: MarketContextInfo(
                btcChange24h: response.btcChange24h ?? marketContext.btcChange24h,
                ethChange24h: response.ethChange24h ?? marketContext.ethChange24h,
                fearGreedIndex: response.fearGreedIndex ?? marketContext.fearGreedIndex,
                marketCapChange24h: marketContext.marketCapChange24h,
                isMarketWideMove: response.isMarketWideMove
            ),
            generatedAt: Date()
        )
    }
    
    /// Check if a coin has significant movement worth explaining
    public func hasSignificantMovement(symbol: String) -> Bool {
        let marketVM = MarketViewModel.shared
        guard let coin = marketVM.allCoins.first(where: { $0.symbol.uppercased() == symbol.uppercased() }) else {
            return false
        }
        let change = coin.unified24hPercent ?? coin.changePercent24Hr ?? 0
        return abs(change) >= 2.0
    }
    
    /// Get quick summary for inline display
    public func quickSummary(for symbol: String) -> String? {
        guard let explanation = cachedExplanations[symbol.uppercased()] else { return nil }
        guard !explanation.possibleReasons.isEmpty else { return nil }
        let topReason = explanation.possibleReasons[0]
        return "\(explanation.direction.label) \(explanation.formattedChange) - \(topReason.title)"
    }
    
    // MARK: - Data Gathering
    
    private struct MarketDataForExplanation {
        let currentPrice: Double
        let change24h: Double
        let change7d: Double
        let volume24h: Double
        let volumeChange: Double?
        
        // Smart Money / Whale data
        let smartMoneyScore: Int?
        let smartMoneyTrend: String?
        let exchangeNetFlow: Double?
        let exchangeFlowSentiment: String?
        let recentWhaleActivity: [WhaleTransaction]?
        
        // Market regime
        let marketRegime: MarketRegime?
        let regimeConfidence: Double?
    }
    
    private func gatherMarketData(symbol: String) async -> MarketDataForExplanation {
        let marketVM = MarketViewModel.shared
        let symbolUpper = symbol.uppercased()
        
        // ROBUSTNESS: Wait for MarketViewModel to have data if it hasn't loaded yet
        // This prevents sending $0 / 0% to Firebase AI, which would produce garbage
        // explanations that get cached for hours and shown to ALL users.
        var coin = marketVM.allCoins.first { $0.symbol.uppercased() == symbolUpper }
        if coin == nil || (coin?.priceUsd ?? 0) <= 0 {
            #if DEBUG
            print("[PriceMovementExplainer] MarketVM not ready for \(symbolUpper), waiting for data...")
            #endif
            // Try refreshing and wait up to ~8 seconds for valid data
            for attempt in 1...4 {
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 500_000_000) // 0.5s, 1s, 1.5s, 2s
                try? Task.checkCancellation()
                coin = marketVM.allCoins.first { $0.symbol.uppercased() == symbolUpper }
                if let c = coin, (c.priceUsd ?? 0) > 0 {
                    #if DEBUG
                    print("[PriceMovementExplainer] MarketVM data available after attempt \(attempt)")
                    #endif
                    break
                }
                // On first attempt, trigger a refresh
                if attempt == 1 {
                    Task { @MainActor in
                        await marketVM.loadAllData()
                    }
                }
            }
        }
        
        // Also try LivePriceManager as a supplemental source
        let lpmCoin = LivePriceManager.shared.currentCoinsList.first { $0.symbol.uppercased() == symbolUpper }
        
        // Use the best available price: prefer MarketVM coin data, fall back to LivePriceManager
        let currentPrice: Double = {
            if let coinPrice = coin?.priceUsd, coinPrice > 0 { return coinPrice }
            if let lpmPrice = lpmCoin?.priceUsd, lpmPrice > 0 { return lpmPrice }
            return 0
        }()
        
        // Use the best available 24h change: MarketVM → LivePriceManager → 0
        // CRITICAL: If both sources return 0 for a major coin, the AI generates a
        // "remained flat" explanation that gets cached for 2+ hours for ALL users.
        let change24h: Double = {
            if let coinChange = coin?.unified24hPercent, coinChange != 0 { return coinChange }
            if let coinChange = coin?.changePercent24Hr, coinChange != 0 { return coinChange }
            if let lpmChange = lpmCoin?.unified24hPercent, lpmChange != 0 { return lpmChange }
            if let lpmChange = lpmCoin?.changePercent24Hr, lpmChange != 0 { return lpmChange }
            return 0
        }()
        let change7d: Double = {
            if let c = coin?.unified7dPercent, c != 0 { return c }
            if let c = coin?.weeklyChange, c != 0 { return c }
            if let c = lpmCoin?.unified7dPercent, c != 0 { return c }
            if let c = lpmCoin?.weeklyChange, c != 0 { return c }
            return 0
        }()
        let volume24h: Double = {
            if let v = coin?.volumeUsd24Hr, v > 0 { return v }
            if let v = lpmCoin?.volumeUsd24Hr, v > 0 { return v }
            return 0
        }()
        
        // CRASH FIX: Safely gather whale/smart money data with error handling
        var smi: SmartMoneyIndex? = nil
        var stats: WhaleStatistics? = nil
        var coinWhaleActivity: [WhaleTransaction] = []
        
        do {
            try Task.checkCancellation()
            let whaleService = WhaleTrackingService.shared
            smi = whaleService.smartMoneyIndex
            stats = whaleService.statistics
            let recentTransactions = whaleService.recentTransactions
            
            // Filter whale transactions for this coin (case-insensitive)
            coinWhaleActivity = recentTransactions.filter {
                $0.symbol.uppercased() == symbolUpper
            }
        } catch {
            // If whale data gathering fails or is cancelled, continue without it
            #if DEBUG
            print("[PriceMovementExplainer] Whale data gathering skipped: \(error)")
            #endif
        }
        
        // Determine exchange flow sentiment
        var flowSentiment: String? = nil
        if let stats = stats {
            if stats.netExchangeFlow < -100_000_000 {
                flowSentiment = "Strong Outflow (Bullish)"
            } else if stats.netExchangeFlow < -10_000_000 {
                flowSentiment = "Moderate Outflow (Slightly Bullish)"
            } else if stats.netExchangeFlow > 100_000_000 {
                flowSentiment = "Strong Inflow (Bearish)"
            } else if stats.netExchangeFlow > 10_000_000 {
                flowSentiment = "Moderate Inflow (Slightly Bearish)"
            } else {
                flowSentiment = "Neutral Flow"
            }
        }
        
        // CRASH FIX: Safely detect market regime from sparkline
        // Ensure sparkline data is valid before processing
        var regime: MarketRegime? = nil
        var regimeConf: Double? = nil
        if let sparkline = coin?.sparklineIn7d,
           sparkline.count >= 20,
           sparkline.allSatisfy({ $0.isFinite && $0 > 0 }) {
            let result = MarketRegimeDetector.detectRegime(closes: sparkline)
            regime = result.regime
            regimeConf = result.confidence
        }
        
        return MarketDataForExplanation(
            currentPrice: currentPrice,
            change24h: change24h,
            change7d: change7d,
            volume24h: volume24h,
            volumeChange: nil,
            smartMoneyScore: smi?.score,
            smartMoneyTrend: smi?.trend.rawValue,
            exchangeNetFlow: stats?.netExchangeFlow,
            exchangeFlowSentiment: flowSentiment,
            recentWhaleActivity: coinWhaleActivity.isEmpty ? nil : Array(coinWhaleActivity.prefix(5)),
            marketRegime: regime,
            regimeConfidence: regimeConf
        )
    }
    
    private func gatherRecentNews(symbol: String, coinName: String) async -> [RelatedNewsItem] {
        // CRASH FIX: Safely fetch recent news with error handling
        var newsItems: [RelatedNewsItem] = []
        
        do {
            try Task.checkCancellation()
            
            // Try to get news from the news service
            let newsVM = CryptoNewsFeedViewModel.shared
            let articles = newsVM.articles
            
            // Search through more articles for relevant matches (not just first 5)
            let candidateArticles = articles.prefix(50)
            
            let symbolLower = symbol.lowercased()
            let nameLower = coinName.lowercased()
            
            // Build search terms for broader matching
            // e.g. for "BTC" also check "bitcoin", for "ETH" also check "ethereum"
            var searchTerms: [String] = [symbolLower, nameLower]
            // Add common aliases
            let aliases: [String: [String]] = [
                "btc": ["bitcoin"],
                "eth": ["ethereum"],
                "sol": ["solana"],
                "xrp": ["ripple"],
                "bnb": ["binance coin", "binance"],
                "ada": ["cardano"],
                "doge": ["dogecoin"],
                "dot": ["polkadot"],
                "avax": ["avalanche"],
                "matic": ["polygon"],
                "link": ["chainlink"],
                "uni": ["uniswap"],
                "atom": ["cosmos"],
                "ltc": ["litecoin"]
            ]
            if let extra = aliases[symbolLower] {
                searchTerms.append(contentsOf: extra)
            }
            
            for article in candidateArticles {
                // Check if article is relevant to this coin
                let titleLower = article.title.lowercased()
                let descLower = (article.description ?? "").lowercased()
                
                let isRelevant = searchTerms.contains { term in
                    titleLower.contains(term) || descLower.contains(term)
                }
                
                if isRelevant {
                    newsItems.append(RelatedNewsItem(
                        title: article.title,
                        source: article.sourceName,
                        publishedAt: article.publishedAt,
                        url: article.url.absoluteString
                    ))
                }
                
                // Cap at 5 related news items
                if newsItems.count >= 5 { break }
            }
        } catch {
            // If news gathering fails or is cancelled, continue without it
            #if DEBUG
            print("[PriceMovementExplainer] News gathering skipped: \(error)")
            #endif
        }
        
        return newsItems
    }
    
    private func gatherMarketContext() async -> MarketContextInfo {
        let marketVM = MarketViewModel.shared
        
        let btc = marketVM.allCoins.first { $0.symbol.uppercased() == "BTC" }
        let eth = marketVM.allCoins.first { $0.symbol.uppercased() == "ETH" }
        
        let btcChange = btc?.unified24hPercent ?? btc?.changePercent24Hr
        let ethChange = eth?.unified24hPercent ?? eth?.changePercent24Hr
        
        // Check if this is a market-wide move
        let isMarketWide = (btcChange ?? 0) != 0 && abs(btcChange ?? 0) > 3
        
        // CRASH FIX: Safely try to get Fear & Greed index from cached data
        // Don't fetch if it causes issues - use cached value or skip
        var fearGreed: Int? = nil
        do {
            let fgVM = ExtendedFearGreedViewModel.shared
            // Use existing cached data first (avoid network call that might fail)
            if let cachedValue = fgVM.currentValue {
                fearGreed = cachedValue
            } else if let latestData = fgVM.data.first, let value = Int(latestData.value) {
                fearGreed = value
            }
            // Only fetch if we don't have cached data and task isn't cancelled
            if fearGreed == nil {
                try Task.checkCancellation()
                await fgVM.fetchData()
                if let latestData = fgVM.data.first, let value = Int(latestData.value) {
                    fearGreed = value
                }
            }
        } catch {
            // If Fear & Greed fetch fails or is cancelled, continue without it
            #if DEBUG
            print("[PriceMovementExplainer] Fear & Greed fetch skipped: \(error)")
            #endif
        }
        
        return MarketContextInfo(
            btcChange24h: btcChange,
            ethChange24h: ethChange,
            fearGreedIndex: fearGreed,
            marketCapChange24h: nil,
            isMarketWideMove: isMarketWide
        )
    }
    
    // MARK: - AI Explanation Generation
    
    private func generateExplanation(
        symbol: String,
        coinName: String,
        marketData: MarketDataForExplanation,
        recentNews: [RelatedNewsItem],
        marketContext: MarketContextInfo
    ) async throws -> PriceMovementExplanation {
        
        // Build prompt for AI
        var prompt = """
        Explain why \(coinName) (\(symbol)) has moved \(String(format: "%.2f", marketData.change24h))% in the last 24 hours.
        
        === PRICE DATA ===
        Current Price: $\(String(format: "%.2f", marketData.currentPrice))
        24H Change: \(String(format: "%.2f", marketData.change24h))%
        7D Change: \(String(format: "%.2f", marketData.change7d))%
        24H Volume: $\(formatLargeNumber(marketData.volume24h))
        """
        
        // Market context
        prompt += "\n\n=== MARKET CONTEXT ==="
        if let btcChange = marketContext.btcChange24h {
            prompt += "\nBTC 24H Change: \(String(format: "%.2f", btcChange))%"
        }
        
        if let ethChange = marketContext.ethChange24h {
            prompt += "\nETH 24H Change: \(String(format: "%.2f", ethChange))%"
        }
        
        if let fg = marketContext.fearGreedIndex {
            prompt += "\nFear & Greed Index: \(fg)/100"
        }
        
        if marketContext.isMarketWideMove {
            prompt += "\n⚠️ This appears to be part of a broader market movement"
        }
        
        // Smart Money / Whale Data (REAL DATA - not speculation)
        prompt += "\n\n=== SMART MONEY / WHALE DATA (REAL BLOCKCHAIN DATA) ==="
        if let smiScore = marketData.smartMoneyScore {
            prompt += "\nSmart Money Index: \(smiScore)/100"
            if let trend = marketData.smartMoneyTrend {
                prompt += " (\(trend))"
            }
        }
        
        if let flowSentiment = marketData.exchangeFlowSentiment {
            prompt += "\nExchange Flow: \(flowSentiment)"
            if let netFlow = marketData.exchangeNetFlow {
                prompt += " ($\(formatLargeNumber(abs(netFlow))))"
            }
        }
        
        if let whaleActivity = marketData.recentWhaleActivity, !whaleActivity.isEmpty {
            prompt += "\n\nRECENT \(symbol.uppercased()) WHALE TRANSACTIONS:"
            for tx in whaleActivity.prefix(5) {
                let direction = tx.transactionType == .exchangeDeposit ? "→ Exchange (Sell Pressure)" : "← Exchange (Accumulation)"
                prompt += "\n  • \(formatLargeNumber(tx.amountUSD)) \(direction) from \(tx.fromLabel ?? "Unknown")"
            }
        } else {
            prompt += "\nNo significant whale activity detected for this coin"
        }
        
        // Market Regime
        if let regime = marketData.marketRegime {
            prompt += "\n\n=== MARKET REGIME ==="
            prompt += "\nCurrent Regime: \(regime.displayName)"
            if let conf = marketData.regimeConfidence {
                prompt += " (\(Int(conf))% confidence)"
            }
            prompt += "\nImplication: \(regime.implications)"
        }
        
        // Recent News
        if !recentNews.isEmpty {
            prompt += "\n\n=== RECENT NEWS ==="
            for news in recentNews.prefix(3) {
                prompt += "\n• \(news.title)"
            }
        }
        
        prompt += """
        
        
        === INSTRUCTIONS ===
        Analyze the above data and provide a brief 1-2 sentence summary and list 2-4 possible reasons for the movement.
        
        IMPORTANT:
        - If whale/smart money data shows significant activity, prioritize this as a reason (category: "whale")
        - Use the REAL blockchain data provided above - don't speculate about whale activity
        - Consider market regime when explaining the movement
        - If the move correlates with BTC/ETH, mention market-wide factors
        
        For each reason, categorize it as: news, whale, technical, sentiment, market, regulatory, exchange, or other.
        Also rate confidence (high/medium/low) and impact (positive/negative/neutral).
        
        Respond with ONLY JSON in this format:
        {
            "summary": "Brief 1-2 sentence explanation",
            "reasons": [
                {
                    "category": "news|whale|technical|sentiment|market|regulatory|exchange|other",
                    "title": "Short reason title",
                    "description": "Detailed explanation",
                    "confidence": "high|medium|low",
                    "impact": "positive|negative|neutral"
                }
            ]
        }
        """
        
        let systemPrompt = """
        You are a professional crypto market analyst explaining price movements using REAL ON-CHAIN DATA.
        
        Your analysis methodology:
        1. WHALE/SMART MONEY DATA (Priority if significant activity detected):
           - Exchange inflows suggest selling pressure (bearish)
           - Exchange outflows suggest accumulation (bullish)
           - Smart Money Index > 55 = institutions buying, < 45 = institutions selling
        
        2. MARKET REGIME CONTEXT:
           - In trending markets, movements often extend further
           - In ranging markets, look for mean reversion
           - High volatility regimes require wider context
        
        3. CORRELATION CHECK:
           - If BTC/ETH moving similarly, it's likely market-wide
           - If coin moving independently, look for coin-specific factors
        
        4. NEWS CATALYST:
           - Link news events to price movements when timing aligns
        
        Be concise and factual. Use the REAL blockchain data provided - don't make up whale activity.
        If the whale data shows significant activity, this should be your primary explanation.
        """
        
        // Call AI service via Firebase backend (no local API key required)
        // Setting isAutomatedFeature: false ensures Firebase is used for all users
        let response = try await AIService.shared.sendMessage(
            prompt,
            systemPrompt: systemPrompt,
            usePremiumModel: false, // Use fast model for quick responses
            includeTools: false,
            temperature: 0.3,
            isAutomatedFeature: false, // Use Firebase backend (automated features skip Firebase)
            maxTokens: 512 // Price movement explanations are concise
        )
        
        // Parse response
        return try parseExplanationResponse(
            response: response,
            symbol: symbol,
            coinName: coinName,
            marketData: marketData,
            recentNews: recentNews,
            marketContext: marketContext
        )
    }
    
    private func parseExplanationResponse(
        response: String,
        symbol: String,
        coinName: String,
        marketData: MarketDataForExplanation,
        recentNews: [RelatedNewsItem],
        marketContext: MarketContextInfo
    ) throws -> PriceMovementExplanation {
        
        // Extract JSON from response - handle various formats
        var jsonString = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove markdown code blocks if present
        if jsonString.hasPrefix("```json") {
            jsonString = String(jsonString.dropFirst(7))
        } else if jsonString.hasPrefix("```") {
            jsonString = String(jsonString.dropFirst(3))
        }
        if jsonString.hasSuffix("```") {
            jsonString = String(jsonString.dropLast(3))
        }
        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try to find JSON object in the response
        // SAFETY: Use half-open range and verify bounds to prevent String index out of bounds crash
        if let startRange = jsonString.range(of: "{"),
           let endRange = jsonString.range(of: "}", options: .backwards),
           startRange.lowerBound < endRange.upperBound {
            // Use half-open range: includes startRange.lowerBound up to (not including) endRange.upperBound
            // endRange.upperBound is already past the "}", so this correctly captures "{...}"
            jsonString = String(jsonString[startRange.lowerBound..<endRange.upperBound])
        }
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw NSError(domain: "PriceMovementExplainer", code: 1, 
                         userInfo: [NSLocalizedDescriptionKey: "Could not parse AI response as JSON"])
        }
        
        struct AIResponse: Decodable {
            let summary: String
            let reasons: [AIReason]
            
            struct AIReason: Decodable {
                let category: String
                let title: String
                let description: String
                let confidence: String
                let impact: String
            }
        }
        
        do {
            let decoded = try JSONDecoder().decode(AIResponse.self, from: jsonData)
            
            // Convert to MovementReason objects
            let reasons: [MovementReason] = decoded.reasons.map { r in
                MovementReason(
                    category: ReasonCategory(rawValue: r.category.lowercased()) ?? .other,
                    title: r.title,
                    description: r.description,
                    confidence: ReasonConfidence(rawValue: r.confidence.lowercased()) ?? .medium,
                    impact: ReasonImpact(rawValue: r.impact.lowercased()) ?? .neutral
                )
            }
            
            return PriceMovementExplanation(
                id: UUID().uuidString,
                coinSymbol: symbol.uppercased(),
                coinName: coinName,
                priceChange24h: marketData.change24h,
                currentPrice: marketData.currentPrice,
                explanationSummary: decoded.summary,
                possibleReasons: reasons,
                relatedNews: recentNews,
                marketContext: marketContext,
                generatedAt: Date()
            )
        } catch {
            // If JSON parsing fails, create a fallback explanation using the raw response
            #if DEBUG
            print("[PriceMovementExplainer] JSON parse error: \(error)")
            print("[PriceMovementExplainer] Raw response: \(jsonString.prefix(500))")
            #endif
            
            // Create a basic explanation from the response text
            let summary = response.components(separatedBy: "\n").first ?? "Price movement analysis unavailable"
            
            return PriceMovementExplanation(
                id: UUID().uuidString,
                coinSymbol: symbol.uppercased(),
                coinName: coinName,
                priceChange24h: marketData.change24h,
                currentPrice: marketData.currentPrice,
                explanationSummary: summary.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines),
                possibleReasons: [
                    MovementReason(
                        category: .market,
                        title: "Market Conditions",
                        description: "Analysis based on current market data.",
                        confidence: .medium,
                        impact: marketData.change24h > 0 ? .positive : .negative
                    )
                ],
                relatedNews: recentNews,
                marketContext: marketContext,
                generatedAt: Date()
            )
        }
    }
    
    private func formatLargeNumber(_ value: Double) -> String {
        if value >= 1_000_000_000 {
            return String(format: "%.2fB", value / 1_000_000_000)
        } else if value >= 1_000_000 {
            return String(format: "%.2fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.2fK", value / 1_000)
        }
        return String(format: "%.2f", value)
    }
}

// MARK: - UI Components

/// "Why is it moving?" button for coin detail views
struct WhyIsItMovingButton: View {
    let symbol: String
    let coinName: String
    let coinId: String?
    let priceChange: Double
    
    @State private var showingExplanation: Bool = false
    @ObservedObject private var explainer = PriceMovementExplainer.shared
    
    var body: some View {
        if abs(priceChange) >= 2 {
            Button {
                showingExplanation = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 12))
                    Text("Why?")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(priceChange > 0 ? .green : .red)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill((priceChange > 0 ? Color.green : Color.red).opacity(0.15))
                )
            }
            .sheet(isPresented: $showingExplanation) {
                PriceMovementExplanationSheet(
                    symbol: symbol,
                    coinName: coinName,
                    coinId: coinId
                )
            }
        }
    }
}

/// Full explanation sheet — redesigned with premium look, optimistic loading, and animations
struct PriceMovementExplanationSheet: View {
    let symbol: String
    let coinName: String
    let coinId: String?
    
    @ObservedObject private var explainer = PriceMovementExplainer.shared
    @ObservedObject private var marketVM = MarketViewModel.shared
    @ObservedObject private var newsVM = CryptoNewsFeedViewModel.shared
    @State private var explanation: PriceMovementExplanation?
    @State private var error: String?
    @State private var isLocalLoading: Bool = true
    @State private var isRefreshing: Bool = false
    @State private var cardAppeared: [String: Bool] = [:]
    @State private var coinNews: [CryptoNewsArticle] = []
    @State private var newsLoaded: Bool = false
    @State private var autoRefreshTask: Task<Void, Never>? = nil
    @State private var selectedArticleURL: URL? = nil
    @State private var showArticleReader: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    init(symbol: String, coinName: String, coinId: String? = nil) {
        self.symbol = symbol
        self.coinName = coinName
        self.coinId = coinId
    }
    
    // MARK: - Auto-Refresh Configuration
    /// How stale the data must be before triggering a silent background refresh on open
    private let staleThresholdSeconds: TimeInterval = 15 * 60  // 15 minutes
    /// How often to auto-refresh if the user keeps the sheet open
    private let periodicRefreshInterval: TimeInterval = 10 * 60 // 10 minutes
    
    // MARK: - Live Market Data
    // The explanation model contains the price/change at GENERATION time,
    // which may be hours old (cached). For the header, use LIVE data from
    // MarketViewModel so prices are always current and consistent with
    // the Market/Watchlist/Home pages.
    
    private var liveCoin: MarketCoin? {
        if let coinId,
           let exact = marketVM.allCoins.first(where: { $0.id == coinId }) {
            return exact
        }
        return marketVM.allCoins.first { $0.symbol.uppercased() == symbol.uppercased() }
    }
    
    /// Also check LivePriceManager as fallback when MarketVM hasn't loaded yet
    private var lpmCoin: MarketCoin? {
        if let coinId,
           let exact = LivePriceManager.shared.currentCoinsList.first(where: { $0.id == coinId }) {
            return exact
        }
        return LivePriceManager.shared.currentCoinsList.first { $0.symbol.uppercased() == symbol.uppercased() }
    }

    /// Resolve a coherent live snapshot so price/change come from the same source path.
    private var liveSnapshot: (price: Double, change24h: Double, imageURL: URL?) {
        if let coin = liveCoin {
            let fallbackPrice = coin.priceUsd ?? 0
            let price = marketVM.bestPrice(for: coin.id) ?? (fallbackPrice > 0 ? fallbackPrice : 0)
            let change = LivePriceManager.shared.bestChange24hPercent(for: coin)
                ?? coin.unified24hPercent
                ?? coin.changePercent24Hr
                ?? 0
            if price > 0 {
                return (price, change, coin.imageUrl ?? lpmCoin?.imageUrl)
            }
        }

        if let coin = lpmCoin {
            let fallbackPrice = coin.priceUsd ?? 0
            let price = marketVM.bestPrice(for: coin.id) ?? (fallbackPrice > 0 ? fallbackPrice : 0)
            let change = LivePriceManager.shared.bestChange24hPercent(for: coin)
                ?? coin.unified24hPercent
                ?? coin.changePercent24Hr
                ?? 0
            if price > 0 {
                return (price, change, coin.imageUrl)
            }
        }

        return (explanation?.currentPrice ?? 0, explanation?.priceChange24h ?? 0, nil)
    }
    
    private var livePrice: Double {
        liveSnapshot.price
    }
    
    private var liveChange24h: Double {
        liveSnapshot.change24h
    }
    
    /// Coin image URL from market data
    private var coinImageURL: URL? {
        liveSnapshot.imageURL
    }
    
    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {
                    if isLocalLoading && explanation == nil && error == nil {
                        loadingView
                    } else if let explanation = explanation {
                        explanationContent(explanation)
                    } else if let error = error {
                        errorView(error)
                    } else {
                        errorView("Unable to load explanation. Please try again.")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(DS.Adaptive.background.ignoresSafeArea())
            .navigationTitle("Why \(symbol) is Moving")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    CSNavButton(
                        icon: "xmark",
                        action: { dismiss() },
                        accessibilityText: "Close",
                        accessibilityHintText: "Close explanation",
                        compact: true
                    )
                }
            }
            .task {
                await initialLoad()
            }
            .onDisappear {
                autoRefreshTask?.cancel()
                autoRefreshTask = nil
            }
            .sheet(isPresented: $showArticleReader, onDismiss: {
                selectedArticleURL = nil
            }) {
                if let url = selectedArticleURL {
                    ArticleReaderView(url: url)
                }
            }
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            // Shimmer header placeholder
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.gray.opacity(colorScheme == .dark ? 0.15 : 0.1))
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 6) {
                    ShimmerBar(height: 18)
                        .frame(width: 100)
                    ShimmerBar(height: 12)
                        .frame(width: 50)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    ShimmerBar(height: 16)
                        .frame(width: 80)
                    ShimmerBar(height: 18)
                        .frame(width: 60)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(DS.Adaptive.cardBackground))
            
            // Shimmer summary placeholder
            VStack(alignment: .leading, spacing: 8) {
                ShimmerBar(height: 14)
                    .frame(width: 80)
                ShimmerBar(height: 12)
                ShimmerBar(height: 12)
                ShimmerBar(height: 12)
                    .frame(width: 200)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(DS.Adaptive.cardBackground))
            
            // Shimmer reasons placeholder
            VStack(alignment: .leading, spacing: 12) {
                ShimmerBar(height: 14)
                    .frame(width: 120)
                ForEach(0..<3, id: \.self) { _ in
                    HStack(alignment: .top, spacing: 12) {
                        Circle()
                            .fill(Color.gray.opacity(colorScheme == .dark ? 0.15 : 0.1))
                            .frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 4) {
                            ShimmerBar(height: 13)
                                .frame(width: 140)
                            ShimmerBar(height: 11)
                            ShimmerBar(height: 11)
                                .frame(width: 180)
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(colorScheme == .dark ? 0.03 : 0.05)))
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(DS.Adaptive.cardBackground))
            
            // Analysis in progress label
            HStack(spacing: 10) {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(BrandColors.goldBase)
                Text("Analyzing \(symbol) price movement...")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                Capsule()
                    .fill(DS.Adaptive.cardBackground)
            )
            .padding(.top, 4)
        }
    }
    
    // MARK: - Error View
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 64, height: 64)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.orange)
            }
            
            Text("Couldn't load explanation")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(DS.Adaptive.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            Button {
                error = nil
                explanation = nil
                isLocalLoading = true
                Task {
                    await fetchFreshExplanation(forceRefresh: true)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Try Again")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.blue)
                )
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
    
    // MARK: - Explanation Content
    
    /// Derive overall AI sentiment from the reasons
    private func aiSentiment(for explanation: PriceMovementExplanation) -> (label: String, icon: String, color: Color) {
        let reasons = explanation.possibleReasons
        guard !reasons.isEmpty else { return ("Neutral", "equal.circle.fill", .gray) }
        let positive = reasons.filter { $0.impact == .positive }.count
        let negative = reasons.filter { $0.impact == .negative }.count
        let highConf = reasons.filter { $0.confidence == .high }.count
        
        if positive > negative && positive >= 2 {
            return ("Bullish", "arrow.up.circle.fill", .green)
        } else if negative > positive && negative >= 2 {
            return ("Bearish", "arrow.down.circle.fill", .red)
        } else if highConf > 0 && positive > negative {
            return ("Leaning Bullish", "arrow.up.right.circle.fill", Color.green.opacity(0.8))
        } else if highConf > 0 && negative > positive {
            return ("Leaning Bearish", "arrow.down.right.circle.fill", Color.red.opacity(0.8))
        } else {
            return ("Mixed Signals", "arrow.left.arrow.right.circle.fill", .orange)
        }
    }
    
    /// Build a forward-looking outlook from the AI reasons
    private func aiOutlookText(for explanation: PriceMovementExplanation) -> String {
        let reasons = explanation.possibleReasons
        let change = liveChange24h
        let sentiment = aiSentiment(for: explanation)
        let direction = change >= 0 ? "upward" : "downward"
        let absChange = String(format: "%.1f", abs(change))
        
        let hasWhaleActivity = reasons.contains { $0.category == .whale }
        let hasMarketWide = explanation.marketContext?.isMarketWideMove == true
        let hasTechnical = reasons.contains { $0.category == .technical }
        let hasNews = reasons.contains { $0.category == .news }
        let hasRegulatory = reasons.contains { $0.category == .regulatory }
        let highConfCount = reasons.filter { $0.confidence == .high }.count
        
        var parts = [String]()
        
        // Opening — contextualize the move
        if abs(change) >= 10 {
            parts.append("\(symbol)'s \(absChange)% \(direction) move is significant and likely to attract further attention from traders and analysts.")
        } else if abs(change) >= 5 {
            parts.append("The \(absChange)% \(direction) movement in \(symbol) reflects notable market activity driven by \(reasons.count) identified factor\(reasons.count != 1 ? "s" : "").")
        } else {
            parts.append("\(symbol)'s \(absChange)% \(direction) shift is within a moderate range, with \(reasons.count) contributing factor\(reasons.count != 1 ? "s" : "") identified.")
        }
        
        // Primary driver
        if hasMarketWide && hasWhaleActivity {
            parts.append("Both broad market conditions and on-chain whale activity are contributing — this combination often signals a sustained directional move.")
        } else if hasMarketWide {
            parts.append("This movement is largely correlated with the broader crypto market. BTC's trajectory will likely determine the next leg for \(symbol).")
        } else if hasWhaleActivity {
            parts.append("On-chain data shows notable whale activity, which can often precede further price movement in the same direction.")
        } else if hasRegulatory {
            parts.append("Regulatory developments are influencing price — expect elevated volatility until the situation provides more clarity.")
        } else if hasNews {
            parts.append("News catalysts are a key driver. These effects can be short-lived, so watch for whether the narrative sustains or fades.")
        } else if hasTechnical {
            parts.append("Technical signals are driving this move. Key levels of support and resistance will determine whether this extends further.")
        }
        
        // Confidence-weighted sentiment
        if highConfCount >= 2 && sentiment.label.contains("Bullish") {
            parts.append("Multiple high-confidence bullish factors suggest the \(direction) trend has strong backing.")
        } else if highConfCount >= 2 && sentiment.label.contains("Bearish") {
            parts.append("Several high-confidence bearish factors point to continued \(direction) pressure in the near term.")
        } else if sentiment.label.contains("Mixed") {
            parts.append("Conflicting signals warrant caution — the market hasn't established a clear direction yet.")
        }
        
        return parts.joined(separator: " ")
    }
    
    @ViewBuilder
    private func explanationContent(_ explanation: PriceMovementExplanation) -> some View {
        // Header with price change, coin icon, and AI sentiment badge
        headerCard(explanation)
            .modifier(CardEntranceModifier(cardId: "header", appeared: $cardAppeared))
        
        // AI Summary with key takeaway
        summaryCard(explanation)
            .modifier(CardEntranceModifier(cardId: "summary", appeared: $cardAppeared, delay: 0.05))
        
        // Reasons
        reasonsCard(explanation)
            .modifier(CardEntranceModifier(cardId: "reasons", appeared: $cardAppeared, delay: 0.1))
        
        // AI Outlook - forward-looking analysis derived from reasons
        aiOutlookCard(explanation)
            .modifier(CardEntranceModifier(cardId: "outlook", appeared: $cardAppeared, delay: 0.13))
        
        // Related news - uses live news feed filtered by coin, with AI fallback
        liveRelatedNewsCard(explanation)
            .modifier(CardEntranceModifier(cardId: "news", appeared: $cardAppeared, delay: 0.17))
        
        // Market context
        if let context = explanation.marketContext {
            marketContextCard(context, explanation: explanation)
                .modifier(CardEntranceModifier(cardId: "context", appeared: $cardAppeared, delay: 0.21))
        }
        
        // Freshness indicator + disclaimer
        footerSection(explanation)
            .modifier(CardEntranceModifier(cardId: "footer", appeared: $cardAppeared, delay: 0.25))
    }
    
    // MARK: - Header Card
    
    private func headerCard(_ explanation: PriceMovementExplanation) -> some View {
        let change = liveChange24h
        let price = livePrice
        let direction: MovementDirection = change > 3 ? .up : change < -3 ? .down : .sideways
        let changeSign = change >= 0 ? "+" : ""
        let changeStr = "\(changeSign)\(String(format: "%.2f", change))%"
        let accentColor = direction == .up ? Color.green : direction == .down ? Color.red : Color.yellow
        let sentiment = aiSentiment(for: explanation)
        
        return VStack(spacing: 0) {
            HStack(spacing: 14) {
                // Coin icon
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.13))
                        .frame(width: 50, height: 50)
                    Circle()
                        .stroke(accentColor.opacity(0.25), lineWidth: 1)
                        .frame(width: 50, height: 50)
                    
                    if let imgURL = coinImageURL {
                        CoinImageView(symbol: symbol.uppercased(), url: imgURL, size: 36)
                    } else {
                        Image(systemName: "bitcoinsign.circle.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(accentColor)
                    }
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(explanation.coinName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Text(explanation.coinSymbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 3) {
                    if price > 0 {
                        Text(formatPrice(price))
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: direction.icon)
                            .font(.system(size: 13, weight: .bold))
                        Text(changeStr)
                            .font(.system(size: 17, weight: .bold))
                    }
                    .foregroundColor(accentColor)
                    
                    Text("24H Change")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
            }
            .padding(16)
            
            // AI Sentiment Badge row
            HStack(spacing: 8) {
                // AI Sentiment pill
                HStack(spacing: 5) {
                    Image(systemName: sentiment.icon)
                        .font(.system(size: 11, weight: .semibold))
                    Text(sentiment.label)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(sentiment.color)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(sentiment.color.opacity(colorScheme == .dark ? 0.12 : 0.08))
                )

                Spacer()
                
                // Sparkle AI badge
                HStack(spacing: 3) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 8))
                    Text("CryptoSage AI Analysis")
                        .font(.system(size: 9, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .allowsTightening(true)
                }
                .foregroundColor(BrandColors.goldBase)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .padding(.top, isRefreshing ? 0 : -4)
            
            // Subtle auto-refresh indicator (only visible during background updates)
            if isRefreshing {
                HStack(spacing: 5) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .tint(BrandColors.goldBase)
                    Text("Refreshing...")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(BrandColors.goldBase.opacity(0.04))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DS.Adaptive.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(accentColor.opacity(0.15), lineWidth: 1)
                )
        )
    }
    
    /// Format price with appropriate decimal places and locale-aware grouping
    private func formatPrice(_ price: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = CurrencyManager.currencyCode
        if price >= 1 {
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 2
        } else if price >= 0.01 {
            formatter.maximumFractionDigits = 4
            formatter.minimumFractionDigits = 2
        } else {
            formatter.maximumFractionDigits = 6
            formatter.minimumFractionDigits = 4
        }
        return formatter.string(from: NSNumber(value: price)) ?? String(format: "$%.2f", price)
    }
    
    // MARK: - Summary Card
    
    private func summaryCard(_ explanation: PriceMovementExplanation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(icon: "text.alignleft", title: "Summary", color: BrandColors.goldBase)
            
            Text(explanation.explanationSummary)
                .font(.system(size: 14))
                .foregroundColor(DS.Adaptive.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DS.Adaptive.cardBackground)
        )
    }
    
    // MARK: - Reasons Card
    
    private func reasonsCard(_ explanation: PriceMovementExplanation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(icon: "list.bullet.circle.fill", title: "Possible Reasons", color: BrandColors.goldBase)
            
            ForEach(Array(explanation.possibleReasons.enumerated()), id: \.element.id) { index, reason in
                reasonRow(reason, index: index)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DS.Adaptive.cardBackground)
        )
    }
    
    private func reasonRow(_ reason: MovementReason, index: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Category icon with colored background
            ZStack {
                Circle()
                    .fill(reason.category.color.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: reason.category.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(reason.category.color)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    Text(reason.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Spacer()
                    
                    // Impact dot with label
                    HStack(spacing: 4) {
                        Circle()
                            .fill(reason.impact.color)
                            .frame(width: 6, height: 6)
                        Text(reason.impact.rawValue.capitalized)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(reason.impact.color)
                    }
                }
                
                Text(reason.description)
                    .font(.system(size: 12.5))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Confidence bar + label
                HStack(spacing: 8) {
                    confidenceBar(reason.confidence)
                    Text("Confidence: \(reason.confidence.label)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(reason.category.color.opacity(colorScheme == .dark ? 0.04 : 0.03))
        )
    }
    
    /// Visual confidence bar
    private func confidenceBar(_ confidence: ReasonConfidence) -> some View {
        let fillFraction: CGFloat = confidence == .high ? 1.0 : confidence == .medium ? 0.66 : 0.33
        let barColor: Color = confidence == .high ? .green : confidence == .medium ? .orange : .red
        
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(barColor.opacity(0.15))
                    .frame(height: 4)
                Capsule()
                    .fill(barColor)
                    .frame(width: geo.size.width * fillFraction, height: 4)
            }
        }
        .frame(width: 40, height: 4)
    }
    
    // MARK: - AI Outlook Card
    
    private func aiOutlookCard(_ explanation: PriceMovementExplanation) -> some View {
        let sentiment = aiSentiment(for: explanation)
        let outlook = aiOutlookText(for: explanation)
        
        // Build "what to watch" items from the reasons
        let watchItems = buildWatchItems(from: explanation)
        
        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "sparkles", title: "AI Outlook", color: BrandColors.goldBase)
            
            // Outlook text
            Text(outlook)
                .font(.system(size: 13.5))
                .foregroundColor(DS.Adaptive.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            
            // What to watch
            if !watchItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What to Watch")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    ForEach(watchItems, id: \.text) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: item.icon)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(item.color)
                                .frame(width: 16, height: 16)
                            
                            Text(item.text)
                                .font(.system(size: 12))
                                .foregroundColor(DS.Adaptive.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(sentiment.color.opacity(colorScheme == .dark ? 0.05 : 0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(sentiment.color.opacity(0.1), lineWidth: 0.5)
                        )
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DS.Adaptive.cardBackground)
        )
    }
    
    private struct WatchItem {
        let icon: String
        let text: String
        let color: Color
    }
    
    private func buildWatchItems(from explanation: PriceMovementExplanation) -> [WatchItem] {
        var items = [WatchItem]()
        let reasons = explanation.possibleReasons
        
        if reasons.contains(where: { $0.category == .whale }) {
            items.append(WatchItem(
                icon: "fish.fill",
                text: "Monitor exchange inflow/outflow for continuation of whale activity",
                color: .purple
            ))
        }
        if explanation.marketContext?.isMarketWideMove == true {
            items.append(WatchItem(
                icon: "chart.bar.fill",
                text: "Broader market movement — watch BTC for directional cues",
                color: .cyan
            ))
        }
        if reasons.contains(where: { $0.category == .sentiment }) {
            let fg = explanation.marketContext?.fearGreedIndex ?? 50
            if fg < 25 {
                items.append(WatchItem(
                    icon: "gauge.with.dots.needle.33percent",
                    text: "Extreme fear often precedes short-term bounces — watch for sentiment shift",
                    color: .orange
                ))
            } else if fg > 75 {
                items.append(WatchItem(
                    icon: "gauge.with.dots.needle.67percent",
                    text: "Extreme greed may signal overextension — watch for pullback signals",
                    color: .orange
                ))
            }
        }
        if reasons.contains(where: { $0.category == .technical }) {
            items.append(WatchItem(
                icon: "chart.xyaxis.line",
                text: "Technical indicators are active — key support/resistance levels may be tested",
                color: .orange
            ))
        }
        if reasons.contains(where: { $0.category == .news }) {
            items.append(WatchItem(
                icon: "newspaper.fill",
                text: "News-driven move — monitor for follow-up developments or corrections",
                color: .blue
            ))
        }
        if reasons.contains(where: { $0.category == .regulatory }) {
            items.append(WatchItem(
                icon: "building.columns.fill",
                text: "Regulatory catalyst — expect heightened volatility until clarity emerges",
                color: .red
            ))
        }
        
        // Generic fallback if no specific category matched
        if items.isEmpty {
            let change = liveChange24h
            if abs(change) >= 5 {
                items.append(WatchItem(
                    icon: "exclamationmark.triangle.fill",
                    text: "Significant \(change > 0 ? "upward" : "downward") move — watch for follow-through or reversal at key levels",
                    color: .orange
                ))
            }
            items.append(WatchItem(
                icon: "clock.fill",
                text: "Monitor volume and price action over the next 24 hours for confirmation",
                color: DS.Adaptive.textTertiary
            ))
        }
        
        // Cap at 4 items
        return Array(items.prefix(4))
    }
    
    // MARK: - Live Related News Card
    
    /// Fetch coin-specific news independently (doesn't touch the shared news VM state)
    private func fetchCoinNews() async {
        guard !newsLoaded else { return }
        let sym = symbol.uppercased()
        let name = coinName.lowercased()
        let query = "\(sym) \(name) crypto"
        
        // 1. First try filtering the already-loaded shared articles
        let existing = newsVM.articles.filter { article in
            let text = (article.title + " " + (article.description ?? "")).lowercased()
            return text.contains(sym.lowercased()) || text.contains(name)
        }
        if existing.count >= 3 {
            coinNews = Array(existing.sorted { $0.publishedAt > $1.publishedAt }.prefix(6))
            newsLoaded = true
            return
        }
        
        // 2. Fetch from CryptoCompare (free, no key needed) + RSS in parallel
        async let ccTask = CryptoCompareNewsService.shared.fetchNews(query: query, limit: 20)
        async let rssTask = RSSFetcher.fetch(limit: 30)
        
        let (ccArticles, rssArticles) = await (ccTask, rssTask)
        
        // Filter fetched articles for relevance
        let allFetched = (ccArticles + rssArticles).sorted { $0.publishedAt > $1.publishedAt }
        let relevant = allFetched.filter { article in
            let text = (article.title + " " + (article.description ?? "")).lowercased()
            return text.contains(sym.lowercased()) || text.contains(name)
        }
        
        // Combine with any existing matches, deduplicate by URL
        var seen = Set<String>()
        var combined = [CryptoNewsArticle]()
        for article in (relevant + existing) {
            let key = article.url.absoluteString
            if !seen.contains(key) {
                seen.insert(key)
                combined.append(article)
            }
        }
        
        coinNews = Array(combined.sorted { $0.publishedAt > $1.publishedAt }.prefix(6))
        newsLoaded = true
    }
    
    @ViewBuilder
    private func liveRelatedNewsCard(_ explanation: PriceMovementExplanation) -> some View {
        let hasLiveNews = !coinNews.isEmpty
        let hasAINews = !explanation.relatedNews.isEmpty
        
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "newspaper.fill", title: "Related News", color: BrandColors.goldBase)
            
            if hasLiveNews {
                // Real news articles with thumbnails and proper source attribution
                let displayedArticles = Array(coinNews.prefix(5))
                ForEach(Array(displayedArticles.enumerated()), id: \.element.id) { index, article in
                    liveNewsRow(article)
                    
                    if index < displayedArticles.count - 1 {
                        Divider()
                            .background(DS.Adaptive.stroke.opacity(0.3))
                    }
                }
            } else if !newsLoaded {
                // Loading shimmer for news
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(colorScheme == .dark ? 0.12 : 0.08))
                            .frame(width: 72, height: 52)
                        VStack(alignment: .leading, spacing: 6) {
                            ShimmerBar(height: 12)
                            ShimmerBar(height: 10)
                                .frame(width: 120)
                        }
                        Spacer()
                    }
                }
            } else if hasAINews {
                // Fallback to AI-generated news references
                ForEach(explanation.relatedNews) { news in
                    if let urlStr = news.url, let url = URL(string: urlStr) {
                        Button {
                            openArticleInApp(url)
                        } label: {
                            aiNewsRow(news)
                        }
                        .buttonStyle(.plain)
                    } else {
                        aiNewsRow(news)
                    }
                }
            } else {
                // No news at all
                HStack(spacing: 8) {
                    Image(systemName: "newspaper")
                        .font(.system(size: 13))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    Text("No recent news found for \(symbol)")
                        .font(.system(size: 12))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                .padding(.vertical, 8)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DS.Adaptive.cardBackground)
        )
        .task {
            await fetchCoinNews()
        }
    }
    
    /// Live news row using real CryptoNewsArticle data with thumbnails
    private func liveNewsRow(_ article: CryptoNewsArticle) -> some View {
        let sanitizedURL = ArticleLink.sanitizeAndUnwrap(article.url)
        
        return CompactNewsRow(
            article: article,
            thumbnailURL: newsVM.thumbnailURL(for: article),
            showUnreadDot: false,
            onTap: { openArticleInApp(sanitizedURL) }
        )
        .padding(.vertical, 2)
    }
    
    /// Fallback AI-generated news row (when live news isn't available)
    private func aiNewsRow(_ news: RelatedNewsItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.blue.opacity(0.4))
                .frame(width: 3, height: 28)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(news.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .lineLimit(2)
                
                HStack(spacing: 4) {
                    Text(news.source)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    if let date = news.publishedAt {
                        Text("·")
                            .font(.system(size: 10))
                            .foregroundColor(DS.Adaptive.textTertiary)
                        Text(timeAgo(from: date))
                            .font(.system(size: 10))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                }
            }
            
            Spacer()
            
            if news.url != nil {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .padding(.top, 3)
            }
        }
        .padding(.vertical, 3)
    }

    private func openArticleInApp(_ url: URL) {
        selectedArticleURL = ArticleLink.sanitizeAndUnwrap(url)
        showArticleReader = true
    }
    
    // MARK: - Market Context Card
    
    private func marketContextCard(_ context: MarketContextInfo, explanation: PriceMovementExplanation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "chart.bar.fill", title: "Market Context", color: BrandColors.goldBase)
            
            // Stats grid
            let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: min(4, statCount(context)))
            LazyVGrid(columns: columns, spacing: 10) {
                if let btc = context.btcChange24h {
                    contextStatCard(label: "BTC 24h", value: String(format: "%+.1f%%", btc), color: btc > 0 ? .green : .red, icon: "bitcoinsign.circle.fill")
                }
                if let eth = context.ethChange24h {
                    contextStatCard(label: "ETH 24h", value: String(format: "%+.1f%%", eth), color: eth > 0 ? .green : .red, icon: "e.circle.fill")
                }
                if let fg = context.fearGreedIndex {
                    let fgLabel = fg >= 75 ? "Extreme Greed" : fg >= 55 ? "Greed" : fg >= 45 ? "Neutral" : fg >= 25 ? "Fear" : "Extreme Fear"
                    contextStatCard(label: "F&G Index", value: "\(fg)", subtitle: fgLabel, color: fg > 50 ? .green : fg < 30 ? .red : .orange, icon: "gauge.with.dots.needle.33percent")
                }
                if let vol = liveCoin?.volumeUsd24Hr, vol > 0 {
                    contextStatCard(label: "24h Volume", value: formatVolume(vol), color: DS.Adaptive.textPrimary, icon: "waveform.path.ecg")
                }
            }
            
            if context.isMarketWideMove {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                    Text("This appears to be part of a broader market-wide movement")
                        .font(.system(size: 12))
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.orange.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.orange.opacity(0.15), lineWidth: 0.5)
                        )
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DS.Adaptive.cardBackground)
        )
    }
    
    /// Count how many stats we'll show (for grid layout)
    private func statCount(_ context: MarketContextInfo) -> Int {
        var count = 0
        if context.btcChange24h != nil { count += 1 }
        if context.ethChange24h != nil { count += 1 }
        if context.fearGreedIndex != nil { count += 1 }
        if (liveCoin?.volumeUsd24Hr ?? 0) > 0 { count += 1 }
        return max(count, 2)
    }
    
    /// Format volume for display
    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1_000_000_000 {
            return "$\(String(format: "%.1f", volume / 1_000_000_000))B"
        } else if volume >= 1_000_000 {
            return "$\(String(format: "%.1f", volume / 1_000_000))M"
        } else if volume >= 1_000 {
            return "$\(String(format: "%.1f", volume / 1_000))K"
        }
        return "$\(String(format: "%.0f", volume))"
    }
    
    private func contextStatCard(label: String, value: String, subtitle: String? = nil, color: Color, icon: String? = nil) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: value.count > 6 ? 13 : 16, weight: .bold))
                .foregroundColor(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(color.opacity(0.8))
                    .lineLimit(1)
            }
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DS.Adaptive.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(colorScheme == .dark ? 0.06 : 0.04))
        )
    }
    
    // MARK: - Footer Section
    
    private func footerSection(_ explanation: PriceMovementExplanation) -> some View {
        VStack(spacing: 12) {
            // Freshness / "Generated at" indicator with staleness badge
            HStack(spacing: 6) {
                let staleness = stalenessInfo(for: explanation)
                
                Image(systemName: staleness.icon)
                    .font(.system(size: 10))
                    .foregroundColor(staleness.color)
                
                Text(staleness.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(staleness.color)
                
                Spacer()
                
                // Powered by badge
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9))
                    Text("AI Powered")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(BrandColors.goldBase)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(BrandColors.goldBase.opacity(0.1))
                )
            }
            
            // Disclaimer
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(DS.Adaptive.textTertiary)
                
                Text("AI-generated analysis for educational purposes only. Not financial advice. Always do your own research.")
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(DS.Adaptive.cardBackground)
            )
        }
    }
    
    /// Determine staleness info for the footer indicator
    private func stalenessInfo(for explanation: PriceMovementExplanation) -> (icon: String, label: String, color: Color) {
        let age = Date().timeIntervalSince(explanation.generatedAt)
        let minutes = Int(age / 60)
        
        if isRefreshing {
            return ("arrow.triangle.2.circlepath", "Refreshing analysis...", BrandColors.goldBase)
        } else if minutes < 5 {
            return ("checkmark.circle.fill", "Fresh analysis · just now", .green)
        } else if minutes < 60 {
            return ("clock.fill", "Analysis from \(minutes)m ago · auto-refreshes", DS.Adaptive.textTertiary)
        } else if minutes < 120 {
            return ("clock.fill", "Analysis from \(minutes / 60)h \(minutes % 60)m ago", DS.Adaptive.textTertiary)
        } else {
            return ("clock.badge.exclamationmark.fill", "Analysis from \(timeAgo(from: explanation.generatedAt))", .orange)
        }
    }
    
    // MARK: - Shared Helpers
    
    /// Reusable section header with icon
    private func sectionHeader(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
        }
    }
    
    /// Human-readable "time ago" string
    private func timeAgo(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        return "\(days)d ago"
    }
    
    // MARK: - Smart Loading & Auto-Refresh
    
    /// Initial load: show stale cache optimistically, then background-refresh if needed
    private func initialLoad() async {
        if let cached = explainer.cachedExplanation(for: symbol) {
            // Show cached data immediately
            explanation = cached
            isLocalLoading = false
            
            // Only trigger background refresh if the cached data is actually stale
            let age = Date().timeIntervalSince(cached.generatedAt)
            if age > staleThresholdSeconds {
                withAnimation(.easeInOut(duration: 0.2)) { isRefreshing = true }
                await fetchFreshExplanation(forceRefresh: true)
                withAnimation(.easeInOut(duration: 0.2)) { isRefreshing = false }
            }
        } else {
            // No cache — full loading state, fetch from Firebase/AI
            await fetchFreshExplanation(forceRefresh: false)
        }
        
        // Start periodic auto-refresh for users who keep the sheet open
        startPeriodicRefresh()
    }
    
    /// Periodic silent background refresh
    private func startPeriodicRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(periodicRefreshInterval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                
                #if DEBUG
                print("[PriceMovementExplanationSheet] Periodic auto-refresh for \(symbol)")
                #endif
                
                withAnimation(.easeInOut(duration: 0.2)) { isRefreshing = true }
                await fetchFreshExplanation(forceRefresh: true)
                withAnimation(.easeInOut(duration: 0.2)) { isRefreshing = false }
            }
        }
    }
    
    /// Core fetch logic with retry for market data not ready
    private func fetchFreshExplanation(forceRefresh: Bool) async {
        if explanation == nil {
            isLocalLoading = true
        }
        // Don't clear existing error during background refresh
        if explanation == nil { error = nil }
        
        let maxAttempts = 2
        for attempt in 1...maxAttempts {
            do {
                let result = try await explainer.explain(
                    symbol: symbol,
                    coinName: coinName,
                    forceRefresh: forceRefresh
                )
                self.explanation = result
                self.error = nil
                self.isLocalLoading = false
                return
            } catch let nsError as NSError where nsError.code == -5 && attempt < maxAttempts {
                // Market data not loaded yet — wait and retry
                #if DEBUG
                print("[PriceMovementExplanationSheet] Data not ready, retrying in 3s (attempt \(attempt)/\(maxAttempts))")
                #endif
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                continue
            } catch is CancellationError {
                // View disappeared or task cancelled — don't show error
                return
            } catch let err as AIServiceError {
                // Only show error if we have nothing to display
                if explanation == nil {
                    self.error = err.errorDescription ?? "AI service error"
                    self.isLocalLoading = false
                }
                return
            } catch let nsError as NSError {
                if explanation == nil {
                    self.error = nsError.localizedDescription
                    self.isLocalLoading = false
                }
                return
            } catch {
                if explanation == nil {
                    self.error = "An unexpected error occurred. Please try again."
                    self.isLocalLoading = false
                }
                #if DEBUG
                print("[PriceMovementExplanationSheet] Unexpected error: \(error)")
                #endif
                return
            }
        }
    }
}

// MARK: - Card Entrance Animation

/// Modifier that applies a subtle slide-up + fade entrance to each card
private struct CardEntranceModifier: ViewModifier {
    let cardId: String
    @Binding var appeared: [String: Bool]
    var delay: Double = 0.0
    
    func body(content: Content) -> some View {
        content
            .opacity(appeared[cardId] == true ? 1 : 0)
            .offset(y: appeared[cardId] == true ? 0 : 12)
            .onAppear {
                withAnimation(.easeOut(duration: 0.35).delay(delay)) {
                    appeared[cardId] = true
                }
            }
    }
}

/// Inline "Why?" badge for coin rows
struct WhyMovingBadge: View {
    let symbol: String
    let coinName: String
    let coinId: String?
    let priceChange: Double
    
    @State private var showingSheet = false
    
    var body: some View {
        if abs(priceChange) >= 2 {
            Button {
                showingSheet = true
            } label: {
                Text("Why?")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(priceChange > 0 ? .green : .red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .stroke(priceChange > 0 ? Color.green : Color.red, lineWidth: 1)
                    )
            }
            .sheet(isPresented: $showingSheet) {
                PriceMovementExplanationSheet(symbol: symbol, coinName: coinName, coinId: coinId)
            }
        }
    }
}
