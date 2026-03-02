//
//  CoinAIInsightService.swift
//  CryptoSage
//
//  AI-powered insight generation for individual coins.
//  Combines technical indicators, market sentiment, news, and portfolio context.
//  Now supports Firebase backend for shared, cached AI responses.
//

import Foundation
import SwiftUI
import Combine

// MARK: - Coin AI Insight Model

/// Represents an AI-generated insight for a specific coin
public struct CoinAIInsight: Codable, Identifiable {
    public let id: String
    public let symbol: String
    public let insightText: String
    public let timestamp: Date
    
    // Context data used for generation
    public let price: Double
    public let change24h: Double
    public let rsiValue: Double?
    public let rsiSignal: String?
    public let sentimentScore: Int?
    public let sentimentClassification: String?
    
    public init(
        symbol: String,
        insightText: String,
        price: Double,
        change24h: Double,
        rsiValue: Double? = nil,
        rsiSignal: String? = nil,
        sentimentScore: Int? = nil,
        sentimentClassification: String? = nil
    ) {
        self.id = UUID().uuidString
        self.symbol = symbol
        self.insightText = insightText
        self.timestamp = Date()
        self.price = price
        self.change24h = change24h
        self.rsiValue = rsiValue
        self.rsiSignal = rsiSignal
        self.sentimentScore = sentimentScore
        self.sentimentClassification = sentimentClassification
    }
    
    /// Check if insight is still fresh (within cache validity)
    public var isFresh: Bool {
        Date().timeIntervalSince(timestamp) < CoinAIInsightService.cacheValiditySeconds
    }
    
    /// Time since insight was generated
    public var age: TimeInterval {
        Date().timeIntervalSince(timestamp)
    }
    
    /// Formatted age string (e.g., "2m ago", "1h ago")
    public var ageText: String {
        let seconds = Int(age)
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }
}

// MARK: - Error Types

enum CoinAIInsightError: LocalizedError {
    case noAPIKey
    case rateLimited
    case generationFailed(String)
    case insufficientData
    case coinNotAllowedForFreeTier(String)
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "AI service temporarily unavailable"
        case .rateLimited:
            return "Daily insight limit reached. Upgrade for unlimited insights."
        case .generationFailed(let message):
            return "Failed to generate insight: \(message)"
        case .insufficientData:
            return "Insufficient data to generate insight"
        case .coinNotAllowedForFreeTier(let symbol):
            return "AI insights for \(symbol) require Pro. Upgrade to unlock all coins, or try BTC, ETH, SOL, XRP, or BNB."
        }
    }
}

// MARK: - Coin AI Insight Service

/// Service for generating AI-powered insights for individual coins
@MainActor
public final class CoinAIInsightService: ObservableObject {
    public static let shared = CoinAIInsightService()
    
    // MARK: - Configuration
    // COST OPTIMIZATION: Coin insights don't change rapidly - 4 hour cache is safe
    // With Firebase, these are SHARED across all users viewing the same coin
    // So cost is amortized: 1 API call serves potentially thousands of users
    nonisolated static let cacheValiditySeconds: TimeInterval = 4 * 3600 // 4 hours (extended from 2 hours)
    private let insightUsageKey = "CoinAIInsightUsesToday"
    private let insightUsageDateKey = "CoinAIInsightUsageDate"
    
    // MARK: - Daily Limit Configuration (all tiers now have limits)
    /// Daily insight limits per subscription tier (uses centralized SubscriptionManager values)
    private func dailyLimit(for tier: SubscriptionTierType) -> Int {
        tier.coinInsightsPerDay
    }
    
    // MARK: - Published Properties
    @Published public var isGenerating: Bool = false
    @Published public var lastError: String? = nil
    
    // MARK: - Cache
    private var insightCache: [String: CoinAIInsight] = [:]
    private let cacheKey = "CoinAIInsightCache"
    private let timestampsKey = "CoinAIInsightTimestamps"
    
    // MARK: - Deep Dive Cache
    /// In-memory cache for deep dive results, keyed by symbol.
    /// Deep dives are longer analyses; cached for 2 hours to avoid redundant API calls.
    private var deepDiveCache: [String: (text: String, timestamp: Date, price: Double, change24h: Double)] = [:]
    private static let deepDiveCacheValiditySeconds: TimeInterval = 2 * 3600 // 2 hours
    
    /// Returns a cached deep dive if it exists and is still fresh, otherwise nil.
    public func cachedDeepDive(for symbol: String) -> String? {
        let key = symbol.uppercased()
        guard let entry = deepDiveCache[key] else { return nil }
        let age = Date().timeIntervalSince(entry.timestamp)
        guard age < Self.deepDiveCacheValiditySeconds else {
            deepDiveCache.removeValue(forKey: key)
            return nil
        }
        return entry.text
    }

    /// Returns cached deep dive only when still fresh and market state hasn't drifted materially.
    public func cachedDeepDive(for symbol: String, currentPrice: Double, currentChange24h: Double) -> String? {
        let key = symbol.uppercased()
        guard let entry = deepDiveCache[key] else { return nil }
        let age = Date().timeIntervalSince(entry.timestamp)
        guard age < Self.deepDiveCacheValiditySeconds else {
            deepDiveCache.removeValue(forKey: key)
            return nil
        }

        // Keep cached deep dive only when context is still close enough to current market state.
        let priceDiffPct = abs(entry.price - currentPrice) / max(abs(currentPrice), 1e-9)
        let changeDiff = abs(entry.change24h - currentChange24h)
        if priceDiffPct > 0.0125 || changeDiff > 1.0 {
            deepDiveCache.removeValue(forKey: key)
            return nil
        }
        return entry.text
    }
    
    // MARK: - Cooldown (prevents rapid refresh even with forceRefresh)
    private var lastRequestTimestamps: [String: Date] = [:]
    /// Minimum time between requests for the same coin (even with forceRefresh)
    /// COST OPTIMIZATION: 30 min cooldown prevents spam while still feeling responsive
    private let minimumCooldownSeconds: TimeInterval = 30 * 60 // 30 minutes per coin (extended from 15 min)
    
    // MARK: - Rate Limiting
    private var usesToday: Int {
        get {
            let defaults = UserDefaults.standard
            // Reset if date changed
            if let lastDate = defaults.object(forKey: insightUsageDateKey) as? Date,
               !Calendar.current.isDateInToday(lastDate) {
                defaults.set(0, forKey: insightUsageKey)
                defaults.set(Date(), forKey: insightUsageDateKey)
                return 0
            }
            return defaults.integer(forKey: insightUsageKey)
        }
        set {
            let defaults = UserDefaults.standard
            defaults.set(newValue, forKey: insightUsageKey)
            defaults.set(Date(), forKey: insightUsageDateKey)
        }
    }
    
    /// Current user's daily insight limit
    public var currentDailyLimit: Int {
        dailyLimit(for: SubscriptionManager.shared.effectiveTier)
    }
    
    /// Remaining insights for today (legacy property name kept for compatibility)
    public var remainingFreeInsights: Int {
        max(0, currentDailyLimit - usesToday)
    }
    
    /// Remaining insights for today
    public var remainingInsights: Int {
        remainingFreeInsights
    }
    
    public var canGenerateInsight: Bool {
        // Developer mode bypasses all limits
        if SubscriptionManager.shared.isDeveloperMode { return true }
        // All tiers now have daily limits
        return remainingFreeInsights > 0
    }
    
    private init() {
        loadCacheFromDisk()
        loadTimestampsFromDisk()
    }
    
    // MARK: - Cache Persistence
    
    /// Load cached insights from disk on app launch
    private func loadCacheFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return }
        do {
            let decoder = JSONDecoder()
            let cached = try decoder.decode([String: CoinAIInsight].self, from: data)
            // Only load insights that are still fresh
            insightCache = cached.filter { $0.value.isFresh }
            #if DEBUG
            print("[CoinAIInsightService] Loaded \(insightCache.count) cached insights from disk")
            #endif
        } catch {
            #if DEBUG
            print("[CoinAIInsightService] Failed to load cache from disk: \(error)")
            #endif
        }
    }
    
    /// Save cached insights to disk
    private func saveCacheToDisk() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(insightCache)
            UserDefaults.standard.set(data, forKey: cacheKey)
        } catch {
            #if DEBUG
            print("[CoinAIInsightService] Failed to save cache to disk: \(error)")
            #endif
        }
    }
    
    /// Load cooldown timestamps from disk
    private func loadTimestampsFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: timestampsKey) else { return }
        do {
            let decoder = JSONDecoder()
            lastRequestTimestamps = try decoder.decode([String: Date].self, from: data)
        } catch {
            #if DEBUG
            print("[CoinAIInsightService] Failed to load timestamps from disk: \(error)")
            #endif
        }
    }
    
    /// Save cooldown timestamps to disk
    private func saveTimestampsToDisk() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(lastRequestTimestamps)
            UserDefaults.standard.set(data, forKey: timestampsKey)
        } catch {
            #if DEBUG
            print("[CoinAIInsightService] Failed to save timestamps to disk: \(error)")
            #endif
        }
    }
    
    // MARK: - Public API
    
    /// Get cached insight for a coin if available and fresh
    public func getCachedInsight(for symbol: String) -> CoinAIInsight? {
        let key = symbol.uppercased()
        guard let cached = insightCache[key], cached.isFresh else {
            return nil
        }
        return cached
    }
    
    /// Get cached insight with percentage drift validation
    /// Returns nil if the cached percentage differs significantly from the current percentage
    /// This ensures the displayed insight matches current market conditions
    public func getCachedInsight(for symbol: String, currentChange24h: Double) -> CoinAIInsight? {
        let key = symbol.uppercased()
        guard let cached = insightCache[key], cached.isFresh else {
            return nil
        }
        
        // Check if percentage has drifted significantly (more than 2% absolute difference)
        // This ensures the displayed insight reflects current market conditions
        let percentageDrift = abs(cached.change24h - currentChange24h)
        if percentageDrift > 2.0 {
            // Percentage has changed significantly, invalidate this cache entry
            return nil
        }
        
        return cached
    }
    
    /// Check if cached insight needs refresh due to percentage drift
    public func needsRefreshDueToPercentageDrift(for symbol: String, currentChange24h: Double) -> Bool {
        let key = symbol.uppercased()
        guard let cached = insightCache[key] else {
            return true // No cache, needs refresh
        }
        
        // If percentage has drifted more than 2%, recommend refresh
        let percentageDrift = abs(cached.change24h - currentChange24h)
        return percentageDrift > 2.0
    }
    
    /// Get any cached insight for a coin, even if stale (for immediate display while refreshing)
    /// Useful for showing something immediately instead of a loading spinner
    public func getAnyCachedInsight(for symbol: String) -> CoinAIInsight? {
        let key = symbol.uppercased()
        return insightCache[key]
    }
    
    /// Check if we have any cached insight for a coin (fresh or stale)
    public func hasAnyCachedInsight(for symbol: String) -> Bool {
        return insightCache[symbol.uppercased()] != nil
    }
    
    /// Store an externally-generated insight into the local cache.
    /// Used by commodity/stock detail views that call Firebase directly but
    /// still want consistent client-side caching and cooldown behavior.
    public func cacheInsight(_ insight: CoinAIInsight, for key: String) {
        let normalizedKey = key.uppercased()
        insightCache[normalizedKey] = insight
        lastRequestTimestamps[normalizedKey] = Date()
        saveCacheToDisk()
        saveTimestampsToDisk()
    }
    
    /// Check if a coin can be refreshed (not within cooldown period)
    /// Use this to avoid triggering unnecessary API calls for stale cache
    public func canRefresh(for symbol: String) -> Bool {
        let key = symbol.uppercased()
        // Developer mode always allows refresh
        if SubscriptionManager.shared.isDeveloperMode { return true }
        // Check cooldown
        guard let lastRequest = lastRequestTimestamps[key] else { return true }
        return Date().timeIntervalSince(lastRequest) >= minimumCooldownSeconds
    }
    
    /// Generate an AI insight for a specific coin
    public func generateInsight(
        symbol: String,
        price: Double,
        change24h: Double,
        change7d: Double? = nil,
        sparkline: [Double] = [],
        forceRefresh: Bool = false
    ) async throws -> CoinAIInsight {
        let key = symbol.uppercased()
        
        // Return cached if available, fresh, and percentage hasn't drifted significantly
        // This ensures the displayed insight matches current market conditions
        if !forceRefresh, let cached = getCachedInsight(for: key, currentChange24h: change24h) {
            // Track cache hit (cost savings)
            AnalyticsService.shared.trackAIFeatureUsage(
                feature: .coinInsight,
                model: "gpt-4o-mini",
                maxTokens: 512,
                tier: SubscriptionManager.shared.effectiveTier,
                cached: true
            )
            return cached
        }
        
        // Cooldown check: even with forceRefresh, prevent rapid requests to the same coin
        // This protects against users rapidly refreshing and burning API costs
        if !SubscriptionManager.shared.isDeveloperMode {
            if let lastRequest = lastRequestTimestamps[key],
               Date().timeIntervalSince(lastRequest) < minimumCooldownSeconds {
                // Track cooldown triggered (cost savings)
                AnalyticsService.shared.trackAICooldownTriggered(
                    feature: .coinInsight,
                    tier: SubscriptionManager.shared.effectiveTier
                )
                // Return cached if within cooldown, even if stale
                if let cached = insightCache[key] {
                    return cached
                }
                throw CoinAIInsightError.rateLimited
            }
        }
        
        // Check coin restriction for free tier users
        // Developer mode bypasses coin restrictions for testing
        if !SubscriptionManager.shared.isDeveloperMode {
            guard SubscriptionManager.shared.canAccessAIForCoin(symbol) else {
                throw CoinAIInsightError.coinNotAllowedForFreeTier(symbol.uppercased())
            }
        }
        
        // Check rate limit for all users (all tiers now have daily limits)
        guard canGenerateInsight else {
            throw CoinAIInsightError.rateLimited
        }
        
        isGenerating = true
        lastError = nil
        defer { isGenerating = false }
        
        // FIREBASE: Try Firebase backend first for shared coin insights
        // Coin insights are the same for all users, so they can be cached server-side
        if FirebaseService.shared.useFirebaseForAI {
            do {
                let insight = try await fetchInsightViaFirebase(
                    symbol: key,
                    price: price,
                    change24h: change24h,
                    change7d: change7d
                )
                
                // Increment usage (all tiers have daily limits, except dev mode)
                if !SubscriptionManager.shared.isDeveloperMode {
                    usesToday += 1
                }
                
                return insight
            } catch {
                // Log Firebase error but fall through to direct API
                #if DEBUG
                print("[CoinAIInsightService] Firebase error: \(error.localizedDescription), falling back to direct API")
                #endif
            }
        }
        
        // FALLBACK: Direct OpenAI call (legacy behavior)
        // Check API key - if missing, use dynamic fallback instead of throwing
        guard APIConfig.hasValidOpenAIKey else {
            // Use technical analysis fallback when no AI capability
            let fallbackText = generateFallbackInsight(
                symbol: key,
                price: price,
                change24h: change24h,
                sparkline: sparkline
            )
            let insight = CoinAIInsight(
                symbol: key,
                insightText: fallbackText,
                price: price,
                change24h: change24h,
                rsiValue: nil,
                rsiSignal: nil,
                sentimentScore: nil,
                sentimentClassification: nil
            )
            insightCache[key] = insight
            lastRequestTimestamps[key] = Date()
            saveCacheToDisk()
            saveTimestampsToDisk()
            return insight
        }
        
        // Gather all context data
        let context = buildCoinContext(
            symbol: key,
            price: price,
            change24h: change24h,
            change7d: change7d,
            sparkline: sparkline
        )
        
        // Build the prompt
        let prompt = buildInsightPrompt(context: context)
        let systemPrompt = buildSystemPrompt()
        
        do {
            // Call AI service (marked as automated feature for cost-effective model on Platinum)
            let response = try await AIService.shared.sendMessage(
                prompt,
                systemPrompt: systemPrompt,
                usePremiumModel: false, // Use gpt-4o-mini for cost efficiency
                includeTools: false,
                temperature: 0.5, // Balanced between creative and factual
                isAutomatedFeature: false, // Use Firebase backend for all users
                maxTokens: 512 // Reduced from 2048 - insights are brief (3-4 sentences)
            )
            
            // Create insight object
            let insight = CoinAIInsight(
                symbol: key,
                insightText: response,
                price: price,
                change24h: change24h,
                rsiValue: context.rsi,
                rsiSignal: context.rsiSignal,
                sentimentScore: context.sentimentScore,
                sentimentClassification: context.sentimentClassification
            )
            
            // Cache the result and persist to disk
            insightCache[key] = insight
            
            // Update cooldown timestamp
            lastRequestTimestamps[key] = Date()
            saveCacheToDisk()
            saveTimestampsToDisk()
            
            // Track AI usage for cost analysis
            AnalyticsService.shared.trackAIFeatureUsage(
                feature: .coinInsight,
                model: "gpt-4o-mini",
                maxTokens: 512,
                tier: SubscriptionManager.shared.effectiveTier,
                cached: false
            )
            
            // Increment usage (all tiers have daily limits, except dev mode)
            if !SubscriptionManager.shared.isDeveloperMode {
                usesToday += 1
            }
            
            return insight
            
        } catch {
            lastError = error.localizedDescription
            throw CoinAIInsightError.generationFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Firebase Backend
    
    /// Fetch coin insight via Firebase Cloud Function
    /// This is the preferred method - coin insights are shared across all users
    private func fetchInsightViaFirebase(
        symbol: String,
        price: Double,
        change24h: Double,
        change7d: Double?
    ) async throws -> CoinAIInsight {
        // Get coin ID from symbol (CoinGecko uses IDs like "bitcoin" not "BTC")
        let coinId = getCoinGeckoId(for: symbol) ?? symbol.lowercased()
        
        // Get market cap and volume from MarketViewModel if available
        let marketVM = MarketViewModel.shared
        let coinData = marketVM.allCoins.first { $0.symbol.uppercased() == symbol.uppercased() }
        
        let response = try await FirebaseService.shared.getCoinInsight(
            coinId: coinId,
            coinName: coinData?.name,
            symbol: symbol,
            price: price,
            change24h: change24h,
            change7d: change7d,
            marketCap: coinData?.marketCap,
            volume24h: coinData?.totalVolume
        )
        
        // Create insight object from Firebase response
        let insight = CoinAIInsight(
            symbol: symbol.uppercased(),
            insightText: response.content,
            price: price,
            change24h: change24h,
            rsiValue: nil, // Technical data not included in Firebase response
            rsiSignal: nil,
            sentimentScore: nil,
            sentimentClassification: nil
        )
        
        // Cache the result locally and persist to disk
        insightCache[symbol.uppercased()] = insight
        lastRequestTimestamps[symbol.uppercased()] = Date()
        saveCacheToDisk()
        saveTimestampsToDisk()
        
        // Track AI usage with actual model from Firebase response
        AnalyticsService.shared.trackAIFeatureUsage(
            feature: .coinInsight,
            model: response.model ?? "gpt-4o", // Firebase shared insights use gpt-4o
            maxTokens: 512,
            tier: SubscriptionManager.shared.effectiveTier,
            cached: response.cached
        )
        
        return insight
    }
    
    /// Map common symbols to CoinGecko IDs
    private func getCoinGeckoId(for symbol: String) -> String? {
        let mapping: [String: String] = [
            "BTC": "bitcoin",
            "ETH": "ethereum",
            "SOL": "solana",
            "XRP": "ripple",
            "ADA": "cardano",
            "DOGE": "dogecoin",
            "AVAX": "avalanche-2",
            "LINK": "chainlink",
            "DOT": "polkadot",
            "MATIC": "matic-network",
            "SHIB": "shiba-inu",
            "LTC": "litecoin",
            "UNI": "uniswap",
            "ATOM": "cosmos",
            "XLM": "stellar",
            "ALGO": "algorand",
            "VET": "vechain",
            "FIL": "filecoin",
            "NEAR": "near",
            "APT": "aptos",
            "ARB": "arbitrum",
            "OP": "optimism",
            "SUI": "sui",
            "SEI": "sei-network",
            "INJ": "injective-protocol",
            "TIA": "celestia",
            "PEPE": "pepe",
            "WIF": "dogwifcoin",
            "BONK": "bonk",
        ]
        return mapping[symbol.uppercased()]
    }
    
    /// Generate a detailed deep dive analysis for a coin.
    /// Uses an in-memory cache (2 hours) so re-opening the sheet doesn't re-call AI.
    /// Set `forceRefresh` to bypass the cache (e.g. user-initiated refresh).
    public func generateDeepDive(
        symbol: String,
        price: Double,
        change24h: Double,
        change7d: Double? = nil,
        sparkline: [Double] = [],
        forceRefresh: Bool = false
    ) async throws -> String {
        let key = symbol.uppercased()
        
        // Return cached deep dive if fresh (unless force-refreshing)
        if !forceRefresh, let cached = cachedDeepDive(for: key) {
            return cached
        }
        
        // Check AI capability (Firebase backend OR local API key)
        guard APIConfig.hasAICapability else {
            throw CoinAIInsightError.noAPIKey
        }
        
        // Check rate limit (all tiers now have limits, canGenerateInsight handles dev mode bypass)
        guard canGenerateInsight else {
            throw CoinAIInsightError.rateLimited
        }
        
        isGenerating = true
        lastError = nil
        defer { isGenerating = false }
        
        let context = buildCoinContext(
            symbol: key,
            price: price,
            change24h: change24h,
            change7d: change7d,
            sparkline: sparkline
        )
        
        let prompt = buildDeepDivePrompt(context: context)
        let systemPrompt = buildDeepDiveSystemPrompt()
        
        do {
            // Deep dive uses more tokens but is still an automated feature
            let response = try await AIService.shared.sendMessage(
                prompt,
                systemPrompt: systemPrompt,
                usePremiumModel: false, // Use gpt-4o-mini for cost efficiency
                includeTools: false,
                temperature: 0.4, // More factual for deep dive
                isAutomatedFeature: false, // Use Firebase backend for all users
                maxTokens: 1024 // Reduced from 2048 - deep dive is longer but still bounded
            )
            
            // Increment usage (all tiers have daily limits, except dev mode)
            if !SubscriptionManager.shared.isDeveloperMode {
                usesToday += 1
            }
            
            // Cache the deep dive result
            deepDiveCache[key] = (
                text: response,
                timestamp: Date(),
                price: price,
                change24h: change24h
            )
            
            return response
            
        } catch {
            lastError = error.localizedDescription
            throw CoinAIInsightError.generationFailed(error.localizedDescription)
        }
    }
    
    /// Clear cached insight for a symbol
    public func clearCache(for symbol: String) {
        insightCache.removeValue(forKey: symbol.uppercased())
        lastRequestTimestamps.removeValue(forKey: symbol.uppercased())
        saveCacheToDisk()
        saveTimestampsToDisk()
    }
    
    /// Clear all cached insights
    public func clearAllCache() {
        insightCache.removeAll()
        lastRequestTimestamps.removeAll()
        saveCacheToDisk()
        saveTimestampsToDisk()
    }
    
    // MARK: - Context Building
    
    private struct CoinContext {
        let symbol: String
        let price: Double
        let change24h: Double
        let change7d: Double?
        
        // Technical indicators
        let rsi: Double?
        let rsiSignal: String?
        let macdSignal: String?
        let sma20: Double?
        let priceVsSma20: String?
        
        // Support/Resistance
        let support: Double?
        let resistance: Double?
        let range7dLow: Double?
        let range7dHigh: Double?
        let positionIn7dRange: Double?
        
        // Market sentiment
        let sentimentScore: Int?
        let sentimentClassification: String?
        let sentimentBias: String?
        
        // Portfolio context
        let userHolds: Bool
        let holdingQuantity: Double?
        let holdingValue: Double?
        let holdingPnL: Double?
        let isOnWatchlist: Bool
        
        // News context
        let recentHeadlines: [String]
        
        // Market regime
        let marketRegime: String?
        let btcDominance: Double?
        
        // Enhanced regime detection
        let detectedRegime: MarketRegime?
        let regimeConfidence: Double?
        
        // Smart Money / Whale data
        let smartMoneyScore: Int?
        let smartMoneyTrend: String?
        let exchangeNetFlow: Double?
        let exchangeFlowSentiment: String?
        let recentWhaleActivity: [WhaleTransaction]?
    }
    
    private func buildCoinContext(
        symbol: String,
        price: Double,
        change24h: Double,
        change7d: Double?,
        sparkline: [Double]
    ) -> CoinContext {
        let key = symbol.uppercased()
        
        // Calculate technical indicators from sparkline
        var rsi: Double? = nil
        var rsiSignal: String? = nil
        var macdSignal: String? = nil
        var sma20: Double? = nil
        var priceVsSma20: String? = nil
        
        if sparkline.count >= 14 {
            // Calculate RSI
            if let rsiValue = TechnicalsEngine.rsi(sparkline, period: 14) {
                rsi = rsiValue
                if rsiValue < 30 {
                    rsiSignal = "Oversold"
                } else if rsiValue < 40 {
                    rsiSignal = "Near oversold"
                } else if rsiValue > 70 {
                    rsiSignal = "Overbought"
                } else if rsiValue > 60 {
                    rsiSignal = "Near overbought"
                } else {
                    rsiSignal = "Neutral"
                }
            }
            
            // Calculate MACD signal
            if let macdResult = TechnicalsEngine.macdLineSignal(sparkline) {
                let m = macdResult.macd
                let s = macdResult.signal
                if m > s && m > 0 {
                    macdSignal = "Bullish"
                } else if m > s && m < 0 {
                    macdSignal = "Turning bullish"
                } else if m < s && m < 0 {
                    macdSignal = "Bearish"
                } else if m < s && m > 0 {
                    macdSignal = "Turning bearish"
                } else {
                    macdSignal = "Neutral"
                }
            }
        }
        
        // SMA 20
        if sparkline.count >= 20 {
            sma20 = TechnicalsEngine.sma(sparkline, period: 20)
            if let s = sma20, s > 0 {
                let ratio = price / s
                if ratio > 1.05 {
                    priceVsSma20 = "5%+ above"
                } else if ratio > 1.02 {
                    priceVsSma20 = "above"
                } else if ratio < 0.95 {
                    priceVsSma20 = "5%+ below"
                } else if ratio < 0.98 {
                    priceVsSma20 = "below"
                } else {
                    priceVsSma20 = "near"
                }
            }
        }
        
        // Support/Resistance from sparkline
        let (support, resistance) = calculateSupportResistance(price: price, sparkline: sparkline)
        
        // 7D range
        let range7dLow = sparkline.min()
        let range7dHigh = sparkline.max()
        var positionIn7dRange: Double? = nil
        if let lo = range7dLow, let hi = range7dHigh, hi > lo {
            positionIn7dRange = (price - lo) / (hi - lo) * 100
        }
        
        // Market sentiment
        let sentimentVM = ExtendedFearGreedViewModel.shared
        let sentimentScore = sentimentVM.currentValue
        let sentimentClassification = sentimentVM.currentClassificationKey?.capitalized
        var sentimentBias: String? = nil
        switch sentimentVM.bias {
        case .bullish: sentimentBias = "Bullish"
        case .bearish: sentimentBias = "Bearish"
        case .neutral: sentimentBias = "Neutral"
        }
        
        // Portfolio context
        var userHolds = false
        var holdingQuantity: Double? = nil
        var holdingValue: Double? = nil
        var holdingPnL: Double? = nil
        
        // Check portfolio for this coin
        if let holdings = getPortfolioHoldings() {
            if let holding = holdings.first(where: { $0.coinSymbol.uppercased() == key }) {
                userHolds = true
                holdingQuantity = holding.quantity
                holdingValue = holding.currentValue
                let costBasis = holding.costBasis * holding.quantity
                if costBasis > 0 {
                    holdingPnL = ((holding.currentValue - costBasis) / costBasis) * 100
                }
            }
        }
        
        // Watchlist status
        let marketVM = MarketViewModel.shared
        let isOnWatchlist = marketVM.watchlistCoins.contains(where: { $0.symbol.uppercased() == key })
        
        // Recent news headlines
        var recentHeadlines: [String] = []
        let newsVM = CryptoNewsFeedViewModel.shared
        let relevantNews = newsVM.articles.filter { article in
            article.title.localizedCaseInsensitiveContains(symbol) ||
            article.title.localizedCaseInsensitiveContains(getCoinName(for: symbol))
        }.prefix(3)
        recentHeadlines = relevantNews.map { $0.title }
        
        // Market regime (basic)
        var marketRegime: String? = nil
        if let btc = marketVM.allCoins.first(where: { $0.symbol.uppercased() == "BTC" }) {
            let btcSparkline = btc.sparklineIn7d
            if btcSparkline.count >= 20 {
                let sma10 = TechnicalsEngine.sma(btcSparkline, period: 10)
                let sma20 = TechnicalsEngine.sma(btcSparkline, period: 20)
                if let s10 = sma10, let s20 = sma20 {
                    if s10 > s20 {
                        marketRegime = "Bullish (BTC 10 SMA > 20 SMA)"
                    } else {
                        marketRegime = "Bearish (BTC 10 SMA < 20 SMA)"
                    }
                }
            }
        }
        
        let btcDominance = marketVM.btcDominance
        
        // Enhanced regime detection using MarketRegimeDetector
        var detectedRegime: MarketRegime? = nil
        var regimeConfidence: Double? = nil
        if sparkline.count >= 20 {
            let regimeResult = MarketRegimeDetector.detectRegime(closes: sparkline)
            detectedRegime = regimeResult.regime
            regimeConfidence = regimeResult.confidence
        }
        
        // Smart Money / Whale data
        let whaleService = WhaleTrackingService.shared
        let smi = whaleService.smartMoneyIndex
        let stats = whaleService.statistics
        let recentTransactions = whaleService.recentTransactions
        
        // Filter whale transactions for this coin
        let coinWhaleActivity = recentTransactions.filter {
            $0.symbol.uppercased() == key
        }
        
        // Determine exchange flow sentiment
        var flowSentiment: String? = nil
        if let stats = stats {
            if stats.netExchangeFlow < -100_000_000 {
                flowSentiment = "Strong Outflow (Bullish)"
            } else if stats.netExchangeFlow < -10_000_000 {
                flowSentiment = "Moderate Outflow"
            } else if stats.netExchangeFlow > 100_000_000 {
                flowSentiment = "Strong Inflow (Bearish)"
            } else if stats.netExchangeFlow > 10_000_000 {
                flowSentiment = "Moderate Inflow"
            } else {
                flowSentiment = "Neutral"
            }
        }
        
        return CoinContext(
            symbol: key,
            price: price,
            change24h: change24h,
            change7d: change7d,
            rsi: rsi,
            rsiSignal: rsiSignal,
            macdSignal: macdSignal,
            sma20: sma20,
            priceVsSma20: priceVsSma20,
            support: support,
            resistance: resistance,
            range7dLow: range7dLow,
            range7dHigh: range7dHigh,
            positionIn7dRange: positionIn7dRange,
            sentimentScore: sentimentScore,
            sentimentClassification: sentimentClassification,
            sentimentBias: sentimentBias,
            userHolds: userHolds,
            holdingQuantity: holdingQuantity,
            holdingValue: holdingValue,
            holdingPnL: holdingPnL,
            isOnWatchlist: isOnWatchlist,
            recentHeadlines: recentHeadlines,
            marketRegime: marketRegime,
            btcDominance: btcDominance,
            detectedRegime: detectedRegime,
            regimeConfidence: regimeConfidence,
            smartMoneyScore: smi?.score,
            smartMoneyTrend: smi?.trend.rawValue,
            exchangeNetFlow: stats?.netExchangeFlow,
            exchangeFlowSentiment: flowSentiment,
            recentWhaleActivity: coinWhaleActivity.isEmpty ? nil : Array(coinWhaleActivity.prefix(5))
        )
    }
    
    private func calculateSupportResistance(price: Double, sparkline: [Double]) -> (Double?, Double?) {
        guard sparkline.count >= 10, price > 0 else { return (nil, nil) }
        
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
        
        let support = lows.filter { $0 <= price }.max() ?? window.filter { $0 <= price }.max()
        let resistance = highs.filter { $0 >= price }.min() ?? window.filter { $0 >= price }.min()
        
        return (support, resistance)
    }
    
    private func getPortfolioHoldings() -> [Holding]? {
        // Access from AIFunctionTools which has the portfolio data
        let holdings = AIFunctionTools.shared.portfolioHoldings
        return holdings.isEmpty ? nil : holdings
    }
    
    private func getCoinName(for symbol: String) -> String {
        let marketVM = MarketViewModel.shared
        return marketVM.allCoins.first(where: { $0.symbol.uppercased() == symbol.uppercased() })?.name ?? symbol
    }
    
    // MARK: - Prompt Building
    
    private func buildSystemPrompt() -> String {
        """
        You are a professional crypto analyst providing actionable insights using REAL ON-CHAIN DATA.
        
        CRITICAL FORMATTING RULES:
        - Write 3-4 complete sentences that flow naturally
        - Start with the MOST IMPORTANT insight first (this will be shown as preview)
        - The first 2 sentences should be self-contained and informative
        - Be specific with numbers, prices, and levels
        - NEVER use markdown (no *, #, **, etc.)
        - Use plain text only - no bullet points, headers, or special formatting
        - End with a brief actionable takeaway or key level to watch
        
        PRIORITIZE DATA IN THIS ORDER:
        1. WHALE/SMART MONEY DATA (if significant activity exists):
           - Exchange outflows = accumulation (bullish)
           - Exchange inflows = selling pressure (bearish)
           - Smart Money Index > 55 = institutions buying, < 45 = selling
        2. MARKET REGIME - adapt your insight to current conditions
        3. TECHNICAL INDICATORS - RSI, MACD, support/resistance
        4. MARKET SENTIMENT - Fear & Greed context
        
        TONE:
        - Professional but conversational
        - Confident, not wishy-washy
        - Focus on what matters for trading decisions
        
        EXAMPLE OUTPUT FORMAT:
        "The Smart Money Index for BTC is at a bullish 68, indicating strong institutional interest despite the market's fear sentiment (28/100). Price is holding above the $42,500 support with RSI at 52 showing neutral momentum. Watch the $44,200 resistance for a potential breakout signal."
        """
    }
    
    private func buildInsightPrompt(context: CoinContext) -> String {
        var prompt = "Generate a quick insight for \(context.symbol):\n\n"
        
        // Price data
        let changeSign = context.change24h >= 0 ? "+" : ""
        prompt += "PRICE: \(formatCurrency(context.price)) (\(changeSign)\(formatPercent(context.change24h))% 24h)\n"
        
        if let change7d = context.change7d {
            let sign7d = change7d >= 0 ? "+" : ""
            prompt += "7D Change: \(sign7d)\(formatPercent(change7d))%\n"
        }
        
        // Technical indicators
        if let rsi = context.rsi, let signal = context.rsiSignal {
            prompt += "RSI(14): \(Int(rsi)) - \(signal)\n"
        }
        
        if let macdSignal = context.macdSignal {
            prompt += "MACD: \(macdSignal)\n"
        }
        
        if let vs20 = context.priceVsSma20 {
            prompt += "Price vs 20 SMA: \(vs20)\n"
        }
        
        // Support/Resistance
        if let support = context.support {
            prompt += "Near-term support: \(formatCurrency(support))\n"
        }
        if let resistance = context.resistance {
            prompt += "Near-term resistance: \(formatCurrency(resistance))\n"
        }
        
        // 7D range position
        if let pos = context.positionIn7dRange, let lo = context.range7dLow, let hi = context.range7dHigh {
            prompt += "7D range: \(formatCurrency(lo)) - \(formatCurrency(hi)) (at \(Int(pos))%)\n"
        }
        
        // Smart Money / Whale Data (REAL ON-CHAIN DATA)
        prompt += "\nSMART MONEY DATA (REAL BLOCKCHAIN DATA):\n"
        if let smiScore = context.smartMoneyScore {
            prompt += "Smart Money Index: \(smiScore)/100"
            if let trend = context.smartMoneyTrend {
                prompt += " (\(trend))"
            }
            prompt += "\n"
        }
        
        if let flowSentiment = context.exchangeFlowSentiment {
            prompt += "Exchange Flow: \(flowSentiment)"
            if let netFlow = context.exchangeNetFlow {
                let formatted = abs(netFlow) >= 1_000_000 ? String(format: "$%.1fM", abs(netFlow) / 1_000_000) : String(format: "$%.0f", abs(netFlow))
                prompt += " (\(formatted))"
            }
            prompt += "\n"
        }
        
        if let whaleActivity = context.recentWhaleActivity, !whaleActivity.isEmpty {
            prompt += "Recent \(context.symbol) Whale Activity:\n"
            for tx in whaleActivity.prefix(3) {
                let direction = tx.transactionType == .exchangeDeposit ? "→ Exchange (Sell Pressure)" : "← Exchange (Accumulation)"
                let formatted = tx.amountUSD >= 1_000_000 ? String(format: "$%.1fM", tx.amountUSD / 1_000_000) : String(format: "$%.0fK", tx.amountUSD / 1_000)
                prompt += "  • \(formatted) \(direction)\n"
            }
        } else {
            prompt += "No significant whale activity for this coin\n"
        }
        
        // Enhanced Market Regime
        if let regime = context.detectedRegime {
            prompt += "\nMARKET REGIME:\n"
            prompt += "Current: \(regime.displayName)"
            if let conf = context.regimeConfidence {
                prompt += " (\(Int(conf))% confidence)"
            }
            prompt += "\nImplication: \(regime.implications)\n"
        }
        
        // Market context
        prompt += "\nMARKET CONTEXT:\n"
        if let sentiment = context.sentimentScore, let classification = context.sentimentClassification {
            prompt += "Fear & Greed: \(sentiment)/100 (\(classification))\n"
        }
        if let regime = context.marketRegime {
            prompt += "BTC Trend: \(regime)\n"
        }
        if let btcDom = context.btcDominance {
            prompt += "BTC Dominance: \(formatPercent(btcDom))%\n"
        }
        
        // Portfolio context
        if context.userHolds {
            prompt += "\nUSER CONTEXT:\n"
            if let qty = context.holdingQuantity, let value = context.holdingValue {
                prompt += "Holds \(formatQuantity(qty)) \(context.symbol) worth \(formatCurrency(value))"
                if let pnl = context.holdingPnL {
                    let pnlSign = pnl >= 0 ? "+" : ""
                    prompt += " (\(pnlSign)\(formatPercent(pnl))% P/L)"
                }
                prompt += "\n"
            }
        } else if context.isOnWatchlist {
            prompt += "\nUSER CONTEXT: On watchlist (not holding)\n"
        }
        
        // News if relevant
        if !context.recentHeadlines.isEmpty {
            prompt += "\nRECENT NEWS:\n"
            for headline in context.recentHeadlines.prefix(2) {
                prompt += "- \(headline)\n"
            }
        }
        
        prompt += """
        
        INSTRUCTIONS:
        Provide a 3-4 sentence insight that's actionable and specific.
        - Start with the most important finding (this will be shown as preview)
        - Write in complete, flowing sentences without bullet points or headers
        - If whale/smart money data shows significant activity, lead with it
        - Consider the market regime when making suggestions
        - Be specific about key price levels and actions
        - Ensure the first 2 sentences are self-contained and informative
        """
        
        return prompt
    }
    
    private func buildDeepDiveSystemPrompt() -> String {
        """
        You are a professional crypto analyst providing detailed technical analysis.
        
        CRITICAL RULES:
        - NEVER use markdown (no *, #, **, etc.)
        - Use plain text only
        - Use dashes (-) for bullet points
        - Be specific with price levels and percentages
        - Include both bullish and bearish scenarios
        - Keep each section concise and actionable
        
        FORMAT REQUIREMENT:
        Return exactly these section headers in this order:
        SUMMARY:
        TREND:
        RISKS:
        ACTION ITEMS:
        
        Under ACTION ITEMS, include 2-4 bullet points with "-" prefix.
        """
    }
    
    private func buildDeepDivePrompt(context: CoinContext) -> String {
        var prompt = "Provide a detailed analysis for \(context.symbol):\n\n"
        
        // All the same context as insight prompt but more detailed
        let changeSign = context.change24h >= 0 ? "+" : ""
        prompt += "CURRENT PRICE: \(formatCurrency(context.price))\n"
        prompt += "24H CHANGE: \(changeSign)\(formatPercent(context.change24h))%\n"
        
        if let change7d = context.change7d {
            let sign7d = change7d >= 0 ? "+" : ""
            prompt += "7D CHANGE: \(sign7d)\(formatPercent(change7d))%\n"
        }
        
        prompt += "\nTECHNICAL INDICATORS:\n"
        if let rsi = context.rsi, let signal = context.rsiSignal {
            prompt += "- RSI(14): \(Int(rsi)) (\(signal))\n"
        }
        if let macdSignal = context.macdSignal {
            prompt += "- MACD Signal: \(macdSignal)\n"
        }
        if let sma20 = context.sma20, let vs20 = context.priceVsSma20 {
            prompt += "- 20 SMA: \(formatCurrency(sma20)) (price \(vs20))\n"
        }
        
        prompt += "\nKEY LEVELS:\n"
        if let support = context.support {
            prompt += "- Support: \(formatCurrency(support))\n"
        }
        if let resistance = context.resistance {
            prompt += "- Resistance: \(formatCurrency(resistance))\n"
        }
        if let lo = context.range7dLow, let hi = context.range7dHigh, let pos = context.positionIn7dRange {
            prompt += "- 7D Range: \(formatCurrency(lo)) - \(formatCurrency(hi))\n"
            prompt += "- Position in range: \(Int(pos))%\n"
        }
        
        prompt += "\nMARKET CONTEXT:\n"
        if let sentiment = context.sentimentScore, let classification = context.sentimentClassification {
            prompt += "- Fear & Greed Index: \(sentiment)/100 (\(classification))\n"
        }
        if let bias = context.sentimentBias {
            prompt += "- Sentiment Bias: \(bias)\n"
        }
        if let regime = context.marketRegime {
            prompt += "- Market Regime: \(regime)\n"
        }
        if let btcDom = context.btcDominance {
            prompt += "- BTC Dominance: \(formatPercent(btcDom))%\n"
        }
        
        if context.userHolds {
            prompt += "\nPORTFOLIO POSITION:\n"
            if let qty = context.holdingQuantity, let value = context.holdingValue {
                prompt += "- Holding: \(formatQuantity(qty)) \(context.symbol) (\(formatCurrency(value)))\n"
                if let pnl = context.holdingPnL {
                    let pnlSign = pnl >= 0 ? "+" : ""
                    prompt += "- Unrealized P/L: \(pnlSign)\(formatPercent(pnl))%\n"
                }
            }
        }
        
        if !context.recentHeadlines.isEmpty {
            prompt += "\nRECENT NEWS:\n"
            for headline in context.recentHeadlines {
                prompt += "- \(headline)\n"
            }
        }
        
        prompt += "\nProvide a comprehensive analysis following the exact section format in your instructions."
        
        return prompt
    }
    
    // MARK: - Formatting Helpers
    
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
    
    private func formatPercent(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
    
    private func formatQuantity(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.0f", value)
        } else if value >= 1 {
            return String(format: "%.2f", value)
        } else {
            return String(format: "%.4f", value)
        }
    }
}

// MARK: - Fallback Algorithmic Insight

extension CoinAIInsightService {
    /// Generate a fallback algorithmic insight when AI is unavailable
    public func generateFallbackInsight(
        symbol: String,
        price: Double,
        change24h: Double,
        sparkline: [Double]
    ) -> String {
        let key = symbol.uppercased()
        let direction = change24h >= 0 ? "up" : "down"
        let changeText = String(format: "%.1f%%", abs(change24h))
        
        var parts: [String] = []
        parts.append("\(key) is \(direction) \(changeText) today, trading near \(formatCurrency(price)).")
        
        // Support/Resistance
        let (support, resistance) = calculateSupportResistance(price: price, sparkline: sparkline)
        if let r = resistance, let s = support {
            parts.append("Watch resistance near \(formatCurrency(r)) and support around \(formatCurrency(s)).")
        } else if let r = resistance {
            parts.append("Near-term resistance sits around \(formatCurrency(r)).")
        } else if let s = support {
            parts.append("Near-term support sits around \(formatCurrency(s)).")
        }
        
        // RSI if available
        if sparkline.count >= 14, let rsi = TechnicalsEngine.rsi(sparkline, period: 14) {
            if rsi < 30 {
                parts.append("RSI at \(Int(rsi)) suggests oversold conditions.")
            } else if rsi > 70 {
                parts.append("RSI at \(Int(rsi)) suggests overbought conditions.")
            }
        }
        
        // Market sentiment
        if let sentiment = ExtendedFearGreedViewModel.shared.currentValue,
           let classification = ExtendedFearGreedViewModel.shared.currentClassificationKey {
            parts.append("Market sentiment: \(sentiment)/100 (\(classification.capitalized)).")
        }
        
        return parts.joined(separator: " ")
    }
}
