//
//  SubscriptionManager.swift
//  CryptoSage
//
//  Manages user subscription state and feature gating.
//
//  SUBSCRIPTION TIER MIGRATION (January 2026)
//  ==========================================
//  The app has migrated from a 4-tier system to a simplified 3-tier system:
//
//  OLD STRUCTURE:                   NEW STRUCTURE:
//  - Free ($0)                      - Free ($0)
//  - Pro ($12.99/mo)        -->     - Pro ($9.99/mo) - price reduced!
//  - Elite ($24.99/mo)      -->     - Premium ($19.99/mo) - combined Elite + Platinum
//  - Platinum ($59.99/mo)   -->     - Premium ($19.99/mo) - combined Elite + Platinum
//
//  MIGRATION HANDLING:
//  - Existing Elite/Platinum subscribers are automatically upgraded to Premium
//  - Premium includes all features from both Elite AND Platinum at the Elite price
//  - Pro subscribers benefit from a price reduction ($12.99 -> $9.99)
//  - Legacy StoreKit product IDs (elite.*, platinum.*) map to Premium tier
//
//  PRO TIER FEATURES ($9.99/mo):
//  - Paper Trading ($100k virtual)
//  - AI Chat (30/day), Predictions (5/day), Insights (10/day)
//  - Whale Tracking, Smart Money Alerts
//  - Tax Reports (2,500 transactions)
//  - Ad-free experience
//
//  PREMIUM TIER FEATURES ($19.99/mo):
//  - Everything in Pro
//  - Premium CryptoSage AI Chat
//  - Trading Bots (DCA, Grid, Signal)
//  - Copy Trading & Bot Marketplace
//  - Derivatives features
//  - Arbitrage Scanner
//  - Unlimited Tax Transactions
//  - DeFi Yield Optimization
//  - Early Access Features
//
//  DEVELOPER MODE:
//  - All features available regardless of tier
//  - Live trading enabled (when developer live trading toggle is on)
//

import Foundation
import SwiftUI
import Combine

// MARK: - Subscription Tier Enum

public enum SubscriptionTierType: String, CaseIterable, Codable {
    case free = "free"
    case pro = "pro"
    case premium = "premium"
    
    // MARK: - Legacy tier aliases (for migration)
    // These are deprecated but kept for backward compatibility with existing subscribers
    
    /// Legacy Elite tier - now maps to Premium
    public static let elite: SubscriptionTierType = .premium
    /// Legacy Platinum tier - now maps to Premium
    public static let platinum: SubscriptionTierType = .premium
    
    public var displayName: String {
        switch self {
        case .free: return "Free"
        case .pro: return "Pro"
        case .premium: return "Premium"
        }
    }
    
    public var monthlyPrice: String {
        switch self {
        case .free: return "$0"
        case .pro: return "$9.99"
        case .premium: return "$19.99"
        }
    }
    
    public var yearlyPrice: String {
        switch self {
        case .free: return "$0"
        case .pro: return "$89.99"
        case .premium: return "$179.99"
        }
    }
    
    public var aiPromptsPerDay: Int {
        switch self {
        case .free: return 5
        case .pro: return 30       // Generous daily chat limit
        case .premium: return 100  // Effectively unlimited (CryptoSage AI Pro for chat)
        }
    }
    
    public var aiPromptsDisplay: String {
        switch self {
        case .free: return "5/day"
        case .pro: return "30/day"
        case .premium: return "Unlimited"
        }
    }
    
    // MARK: - AI Feature Limits (Cost Control)
    // These limits ensure sustainable costs while providing value
    // Free/Pro use standard CryptoSage AI (~$0.0003/call) for cost efficiency
    // Premium uses CryptoSage AI Pro (~$0.005/call) for best quality chat
    
    /// Daily AI prediction limit
    public var predictionsPerDay: Int {
        switch self {
        case .free: return 3   // Limited to top 5 coins only
        case .pro: return 15   // Generous for paid tier, all coins
        case .premium: return 50 // Generous limit for power users
        }
    }
    
    /// Daily coin insight limit
    public var coinInsightsPerDay: Int {
        switch self {
        case .free: return 2   // Limited to top 5 coins only
        case .pro: return 10   // ~$0.02/day max
        case .premium: return 30 // Generous limit
        }
    }
    
    /// Daily portfolio insight limit
    public var portfolioInsightsPerDay: Int {
        switch self {
        case .free: return 0   // Locked - Pro+ feature
        case .pro: return 5    // ~$0.01/day max
        case .premium: return 20 // Generous limit
        }
    }
    
    /// Daily Fear/Greed AI observation limit
    public var fearGreedAIPerDay: Int {
        switch self {
        case .free: return 2
        case .pro: return 10   // ~$0.02/day max
        case .premium: return 20 // Generous limit
        }
    }
    
    /// Daily price movement explanation limit
    public var priceMovementExplainersPerDay: Int {
        switch self {
        case .free: return 2   // Limited to top 5 coins only
        case .pro: return 10   // ~$0.02/day max
        case .premium: return 20 // Generous limit
        }
    }
    
    /// Maximum active price alerts allowed
    public var maxPriceAlerts: Int {
        switch self {
        case .free: return 3
        case .pro, .premium: return Int.max  // Unlimited
        }
    }
    
    /// Maximum tax transactions allowed
    public var maxTaxTransactions: Int {
        switch self {
        case .free: return 0        // No tax reports
        case .pro: return 2500      // Up to 2,500 transactions
        case .premium: return Int.max // Unlimited
        }
    }
    
    /// Maximum AI agent connections allowed
    public var maxAgentConnections: Int {
        switch self {
        case .free: return 0      // Agent feature requires Pro+
        case .pro: return 1       // 1 agent connection
        case .premium: return 3   // Up to 3 agents
        }
    }

    /// Whether this tier gets the premium CryptoSage AI model for chat
    /// Only Premium gets the advanced model, and only for direct chat interactions
    /// All automated features (insights, predictions) use the standard model for cost efficiency
    public var usesPremiumAIForChat: Bool {
        self == .premium
    }
    
    /// Legacy property name - kept for compatibility
    @available(*, deprecated, renamed: "usesPremiumAIForChat")
    public var usesPremiumAIEverywhere: Bool {
        usesPremiumAIForChat
    }
}

// MARK: - Free Tier Coin Restrictions

/// Coins that free tier users can access for AI features
/// These are the top 5 coins by market cap
public let freeTierAllowedCoins: Set<String> = ["BTC", "ETH", "SOL", "XRP", "BNB"]

/// Check if a coin is allowed for AI features based on subscription tier
/// - Parameters:
///   - symbol: The coin symbol to check
///   - tier: The user's subscription tier
/// - Returns: True if the coin is allowed for AI features
public func canAccessAIForCoin(_ symbol: String, tier: SubscriptionTierType) -> Bool {
    // Pro and Elite can access all coins
    if tier != .free { return true }
    // Free tier limited to top 5 coins
    return freeTierAllowedCoins.contains(symbol.uppercased())
}

// MARK: - Feature Access

public enum PremiumFeature: String, CaseIterable {
    // Pro tier features ($9.99/mo)
    case tradeExecution = "trade_execution"
    case aiPoweredAlerts = "ai_powered_alerts"
    case advancedAlerts = "advanced_alerts"
    case paperTrading = "paper_trading"
    case adFreeExperience = "ad_free"
    case personalizedPortfolioAnalysis = "personalized_portfolio_analysis"
    case taxReports = "tax_reports"
    case aiPricePredictions = "ai_price_predictions"
    case whaleTracking = "whale_tracking"
    case smartMoneyAlerts = "smart_money_alerts"
    case unlimitedPriceAlerts = "unlimited_price_alerts"
    case socialProfile = "social_profile"
    case riskReport = "risk_report"
    
    // Premium tier features ($19.99/mo)
    case tradingBots = "trading_bots"
    case customStrategies = "custom_strategies"
    case advancedInsights = "advanced_insights"
    case derivativesFeatures = "derivatives_features"
    case copyTrading = "copy_trading"
    case botMarketplace = "bot_marketplace"
    case premiumAIModel = "premium_ai_model"
    case unlimitedTaxTransactions = "unlimited_tax_transactions"
    case arbitrageScanner = "arbitrage_scanner"
    case defiYieldOptimization = "defi_yield_optimization"
    case earlyAccessFeatures = "early_access_features"
    
    public var displayName: String {
        switch self {
        case .tradeExecution: return "Trade Execution"
        case .aiPoweredAlerts: return "AI Alerts"
        case .advancedAlerts: return "Advanced Alerts"
        case .paperTrading: return "Paper Trading"
        case .tradingBots: return "Strategy Simulator"
        case .customStrategies: return "Custom Strategies"
        case .advancedInsights: return "Advanced AI Insights"
        case .adFreeExperience: return "Ad-Free Experience"
        case .derivativesFeatures: return "Paper Derivatives"
        case .personalizedPortfolioAnalysis: return "AI Portfolio Analysis"
        case .taxReports: return "Tax Reports"
        case .whaleTracking: return "Whale Tracking"
        case .smartMoneyAlerts: return "Smart Money Alerts"
        case .copyTrading: return "Strategy Marketplace"
        case .botMarketplace: return "Bot Marketplace"
        case .aiPricePredictions: return "AI Price Predictions"
        case .unlimitedPriceAlerts: return "Unlimited Price Alerts"
        case .socialProfile: return "Social Profile"
        case .riskReport: return "AI Risk Report"
        case .premiumAIModel: return "Premium CryptoSage AI"
        case .unlimitedTaxTransactions: return "Unlimited Tax Transactions"
        case .arbitrageScanner: return "Arbitrage Scanner"
        case .defiYieldOptimization: return "DeFi Yield Optimization"
        case .earlyAccessFeatures: return "Early Access Features"
        }
    }
    
    public var requiredTier: SubscriptionTierType {
        switch self {
        // Pro tier features ($9.99/mo)
        case .tradeExecution, .aiPoweredAlerts, .advancedAlerts, .paperTrading,
             .adFreeExperience, .personalizedPortfolioAnalysis, .taxReports, 
             .whaleTracking, .smartMoneyAlerts, .aiPricePredictions,
             .unlimitedPriceAlerts, .socialProfile, .riskReport:
            return .pro
        // Premium tier features ($19.99/mo)
        case .tradingBots, .customStrategies, .advancedInsights,
             .derivativesFeatures, .copyTrading, .botMarketplace, .premiumAIModel,
             .unlimitedTaxTransactions, .arbitrageScanner, .defiYieldOptimization,
             .earlyAccessFeatures:
            return .premium
        }
    }
    
    public var upgradeMessage: String {
        switch self {
        case .tradeExecution:
            return AppConfig.tradeExecutionUpgradeMessage
        case .aiPoweredAlerts:
            return "Upgrade to Pro for AI alerts: AI-enhanced price alerts plus AI market and portfolio monitoring with smart notifications."
        case .advancedAlerts:
            return "Upgrade to Pro to access advanced alert conditions including RSI, volume spikes, and percentage change alerts."
        case .paperTrading:
            return "Practice trading with $100,000 in virtual funds. Execute market, limit, and stop orders against live prices, get AI-powered insights on your trades, and compete on leaderboards."
        case .tradingBots:
            return "Upgrade to Premium to simulate automated trading strategies like DCA, Grid, and Signal bots with virtual money. Perfect for learning and testing before committing real funds!"
        case .customStrategies:
            return "Upgrade to Premium to create custom algorithmic trading strategies."
        case .advancedInsights:
            return "Upgrade to Premium for advanced CryptoSage AI insights and strategy recommendations."
        case .adFreeExperience:
            return "Upgrade to Pro for an ad-free experience."
        case .derivativesFeatures:
            return "Upgrade to Premium to access derivatives trading, futures, and leverage features."
        case .personalizedPortfolioAnalysis:
            return "Upgrade to Pro for personalized AI analysis of your portfolio with actionable insights and recommendations."
        case .taxReports:
            return "Upgrade to Pro to generate comprehensive tax reports for your crypto transactions. Export to Form 8949, TurboTax, and more!"
        case .whaleTracking:
            return "Upgrade to Pro to track whale wallet movements and large transactions in real-time. Stay ahead of market-moving trades!"
        case .smartMoneyAlerts:
            return "Upgrade to Pro to receive alerts when smart money wallets make significant moves. Follow the whales!"
        case .copyTrading:
            return "Upgrade to Premium to view and follow top traders' strategies and performance."
        case .botMarketplace:
            return "Upgrade to Premium to access the bot marketplace and discover proven trading strategies."
        case .aiPricePredictions:
            return "Upgrade to Pro for AI-powered price predictions with confidence levels and key market drivers analysis."
        case .unlimitedPriceAlerts:
            return "Upgrade to Pro to create unlimited price alerts. Free users are limited to 3 active alerts."
        case .socialProfile:
            return "Upgrade to Pro to create your social profile and appear on leaderboards."
        case .riskReport:
            return "Upgrade to Pro for AI-powered portfolio risk analysis with personalized recommendations to optimize your holdings."
        case .premiumAIModel:
            return "Upgrade to Premium for the most powerful CryptoSage AI with more intelligent and nuanced responses."
        case .unlimitedTaxTransactions:
            return "Upgrade to Premium for unlimited tax transactions. Pro users are limited to 2,500 transactions per tax year."
        case .arbitrageScanner:
            return "Upgrade to Premium to scan for price differences across exchanges."
        case .defiYieldOptimization:
            return "Upgrade to Premium for AI-powered DeFi yield optimization suggestions."
        case .earlyAccessFeatures:
            return "Upgrade to Premium to get early access to new features before they're released to everyone."
        }
    }
    
    /// Icon for the feature
    public var iconName: String {
        switch self {
        case .tradeExecution: return "arrow.left.arrow.right.circle.fill"
        case .aiPoweredAlerts: return "bell.badge.fill"
        case .advancedAlerts: return "bell.and.waves.left.and.right.fill"
        case .paperTrading: return "doc.text.fill"
        case .tradingBots: return "cpu.fill"
        case .customStrategies: return "gearshape.2.fill"
        case .advancedInsights: return "lightbulb.max.fill"
        case .adFreeExperience: return "checkmark.seal.fill"
        case .derivativesFeatures: return "chart.line.uptrend.xyaxis.circle.fill"
        case .personalizedPortfolioAnalysis: return "chart.pie.fill"
        case .taxReports: return "doc.text.magnifyingglass"
        case .whaleTracking: return "water.waves"
        case .smartMoneyAlerts: return "dollarsign.arrow.circlepath"
        case .copyTrading: return "doc.on.doc.fill"
        case .botMarketplace: return "storefront.fill"
        case .aiPricePredictions: return "wand.and.stars"
        case .unlimitedPriceAlerts: return "bell.badge.fill"
        case .socialProfile: return "person.crop.circle.fill"
        case .riskReport: return "shield.lefthalf.filled"
        case .premiumAIModel: return "sparkles"
        case .unlimitedTaxTransactions: return "doc.text.magnifyingglass"
        case .arbitrageScanner: return "arrow.triangle.2.circlepath"
        case .defiYieldOptimization: return "leaf.fill"
        case .earlyAccessFeatures: return "clock.badge.checkmark.fill"
        }
    }
}

// MARK: - Subscription Manager

public final class SubscriptionManager: ObservableObject {
    public static let shared = SubscriptionManager()
    
    // MARK: - Published Properties
    
    @Published public private(set) var currentTier: SubscriptionTierType = .free
    @Published public private(set) var aiPromptsUsedToday: Int = 0
    @Published public private(set) var lastPromptResetDate: Date = Date()
    @Published public private(set) var isDeveloperMode: Bool = false
    
    /// The tier to simulate when in developer mode (allows testing Free/Pro/Elite experiences)
    @Published public var developerSimulatedTier: SubscriptionTierType = .elite {
        didSet {
            saveDeveloperSimulatedTier()
            // Note: @Published already sends objectWillChange - no need to call manually
            // Calling synchronously causes "Publishing changes from within view updates"
        }
    }
    
    /// Whether live trading is enabled in developer mode (separate from developer mode itself)
    /// This allows testing the app without accidentally executing real trades.
    /// SAFETY: Defaults to false - must be explicitly enabled to trade with real money.
    @Published public var developerLiveTradingEnabled: Bool = false {
        didSet {
            saveDeveloperLiveTradingEnabled()
            // Note: @Published already sends objectWillChange - no need to call manually
        }
    }

    /// SECURITY: Tracks whether StoreKit has verified the subscription tier since launch.
    /// Until this is true, the cached UserDefaults tier has NOT been validated against
    /// Apple's receipt/entitlement data and may be stale or tampered.
    @Published public private(set) var hasVerifiedWithStoreKit: Bool = false

    // MARK: - Storage Keys
    
    private let tierKey = "Subscription.CurrentTier"
    private let promptsUsedKey = "Subscription.AIPromptsUsedToday"
    private let lastResetDateKey = "Subscription.LastPromptResetDate"
    private let developerModeKey = "Subscription.DeveloperMode"
    private let developerSimulatedTierKey = "Subscription.DeveloperSimulatedTier"
    private let developerLiveTradingKey = "Subscription.DeveloperLiveTrading"
    
    // MARK: - Developer Mode Secret Code
    // SECURITY: Developer mode is only available in DEBUG builds to prevent
    // end users from bypassing subscriptions or enabling live trading.
    // In release builds the code check always fails.
    #if DEBUG
    private static let developerCode = "CSDEV2026"
    #else
    private static let developerCode = UUID().uuidString // Unreachable random value
    #endif
    
    // MARK: - Initialization
    
    private init() {
        loadState()
        checkDailyReset()
    }
    
    // MARK: - State Management
    
    private func loadState() {
        // Load and migrate tier from storage
        if let tierRaw = UserDefaults.standard.string(forKey: tierKey) {
            // MIGRATION: Convert legacy tier names to new structure
            // - "elite" -> "premium"
            // - "platinum" -> "premium"
            let migratedTier: SubscriptionTierType
            switch tierRaw {
            case "elite", "platinum":
                migratedTier = .premium
                // Save migrated tier
                UserDefaults.standard.set("premium", forKey: tierKey)
                #if DEBUG
                print("[SubscriptionManager] Migrated legacy tier '\(tierRaw)' to 'premium'")
                #endif
            case "pro":
                migratedTier = .pro
            case "free":
                migratedTier = .free
            default:
                // Try direct conversion, fallback to free
                migratedTier = SubscriptionTierType(rawValue: tierRaw) ?? .free
            }
            currentTier = migratedTier
        }
        
        aiPromptsUsedToday = UserDefaults.standard.integer(forKey: promptsUsedKey)
        
        if let resetDate = UserDefaults.standard.object(forKey: lastResetDateKey) as? Date {
            lastPromptResetDate = resetDate
        }
        
        #if DEBUG
        isDeveloperMode = UserDefaults.standard.bool(forKey: developerModeKey)
        #else
        // SECURITY: Force developer mode off in release builds — even if a persisted
        // flag exists from a debug session, it must never carry over to production.
        if UserDefaults.standard.bool(forKey: developerModeKey) {
            UserDefaults.standard.set(false, forKey: developerModeKey)
        }
        isDeveloperMode = false
        #endif
        
        // Load developer simulated tier (defaults to .premium if not set)
        // MIGRATION: Also migrate legacy tier names for developer mode
        if let simulatedTierRaw = UserDefaults.standard.string(forKey: developerSimulatedTierKey) {
            switch simulatedTierRaw {
            case "elite", "platinum":
                developerSimulatedTier = .premium
            case "pro":
                developerSimulatedTier = .pro
            default:
                developerSimulatedTier = SubscriptionTierType(rawValue: simulatedTierRaw) ?? .premium
            }
        }
        
        // Load developer live trading setting (defaults to false for safety)
        developerLiveTradingEnabled = UserDefaults.standard.bool(forKey: developerLiveTradingKey)
    }
    
    private func saveState() {
        UserDefaults.standard.set(currentTier.rawValue, forKey: tierKey)
        UserDefaults.standard.set(aiPromptsUsedToday, forKey: promptsUsedKey)
        UserDefaults.standard.set(lastPromptResetDate, forKey: lastResetDateKey)
        UserDefaults.standard.set(isDeveloperMode, forKey: developerModeKey)
        UserDefaults.standard.set(developerSimulatedTier.rawValue, forKey: developerSimulatedTierKey)
        UserDefaults.standard.set(developerLiveTradingEnabled, forKey: developerLiveTradingKey)
    }
    
    private func saveDeveloperSimulatedTier() {
        UserDefaults.standard.set(developerSimulatedTier.rawValue, forKey: developerSimulatedTierKey)
    }
    
    private func saveDeveloperLiveTradingEnabled() {
        UserDefaults.standard.set(developerLiveTradingEnabled, forKey: developerLiveTradingKey)
    }
    
    private func checkDailyReset() {
        let calendar = Calendar.current
        if !calendar.isDateInToday(lastPromptResetDate) {
            // Defer to avoid "Publishing changes from within view updates" warning.
            // This method is called from canUseAIPrompt/remainingAIPrompts which SwiftUI
            // may evaluate during view body, so we must not mutate @Published inline.
            DispatchQueue.main.async { [self] in
                aiPromptsUsedToday = 0
                lastPromptResetDate = Date()
                saveState()
            }
        }
    }
    
    // MARK: - Subscription Tier Management
    
    /// Update the user's subscription tier (call after successful purchase)
    public func setTier(_ tier: SubscriptionTierType) {
        let oldTier = currentTier
        currentTier = tier
        saveState()
        objectWillChange.send()

        // Notify observers if tier actually changed
        if oldTier != tier {
            notifySubscriptionChanged()
        }
    }

    /// SECURITY: Validate the cached subscription tier against StoreKit entitlements.
    /// This should be called early in app startup to ensure the UserDefaults-cached tier
    /// hasn't become stale (e.g., expired subscription) or been tampered with.
    /// Lightweight: only checks entitlements, does NOT load products or initialize ads.
    public func validateWithStoreKit() async {
        #if DEBUG
        // In debug builds, developer mode may override the tier — skip StoreKit validation.
        if isDeveloperMode {
            hasVerifiedWithStoreKit = true
            print("[SubscriptionManager] Skipping StoreKit validation (developer mode)")
            return
        }
        #endif

        let cachedTier = currentTier
        await StoreKitManager.shared.updateSubscriptionStatus()
        hasVerifiedWithStoreKit = true

        #if DEBUG
        if currentTier != cachedTier {
            print("[SubscriptionManager] StoreKit validation corrected tier: \(cachedTier.rawValue) -> \(currentTier.rawValue)")
        } else {
            print("[SubscriptionManager] StoreKit validation confirmed tier: \(currentTier.rawValue)")
        }
        #endif
    }

    /// Check if user has access to a specific tier or higher
    /// In developer mode, respects the simulated tier selection
    public func hasTier(_ minimumTier: SubscriptionTierType) -> Bool {
        let tierToCheck = isDeveloperMode ? developerSimulatedTier : currentTier
        let tierOrder: [SubscriptionTierType] = [.free, .pro, .premium]
        guard let currentIndex = tierOrder.firstIndex(of: tierToCheck),
              let requiredIndex = tierOrder.firstIndex(of: minimumTier) else {
            return false
        }
        return currentIndex >= requiredIndex
    }
    
    // MARK: - Developer Mode
    
    /// Attempt to enable developer mode with a secret code
    /// - Parameter code: The secret developer code
    /// - Returns: True if the code was valid and developer mode is now enabled
    ///
    /// SECURITY: In release builds this always returns false — developer mode
    /// is compile-time gated so that App Store users cannot bypass subscriptions.
    @discardableResult
    public func enableDeveloperMode(code: String) -> Bool {
        #if !DEBUG
        // Release builds: developer mode is never available
        return false
        #else
        guard code == Self.developerCode else { return false }
        isDeveloperMode = true
        saveState()
        objectWillChange.send()
        return true
        #endif
    }
    
    /// Disable developer mode
    /// Also resets live trading toggle to false for safety
    public func disableDeveloperMode() {
        isDeveloperMode = false
        developerLiveTradingEnabled = false  // Safety: always reset live trading when exiting dev mode
        saveState()
        objectWillChange.send()
    }
    
    /// Toggle developer mode (for UI binding)
    public func toggleDeveloperMode() {
        isDeveloperMode.toggle()
        saveState()
        objectWillChange.send()
    }
    
    // MARK: - Feature Access
    
    /// Check if a premium feature is available for the current tier
    /// In developer mode, respects the simulated tier selection
    public func hasAccess(to feature: PremiumFeature) -> Bool {
        let tierToCheck = isDeveloperMode ? developerSimulatedTier : currentTier
        return hasTierLevel(tierToCheck, meetsRequirement: feature.requiredTier)
    }
    
    /// Check if user can access AI features for a specific coin
    /// Free tier users are limited to top 5 coins (BTC, ETH, SOL, XRP, BNB)
    public func canAccessAIForCoin(_ symbol: String) -> Bool {
        let tierToCheck = isDeveloperMode ? developerSimulatedTier : currentTier
        return CryptoSage.canAccessAIForCoin(symbol, tier: tierToCheck)
    }
    
    /// Internal helper to check if a tier level meets the requirement
    private func hasTierLevel(_ tier: SubscriptionTierType, meetsRequirement required: SubscriptionTierType) -> Bool {
        let tierOrder: [SubscriptionTierType] = [.free, .pro, .premium]
        guard let tierIndex = tierOrder.firstIndex(of: tier),
              let requiredIndex = tierOrder.firstIndex(of: required) else {
            return false
        }
        return tierIndex >= requiredIndex
    }
    
    /// Check all available features for current/simulated tier
    public var availableFeatures: [PremiumFeature] {
        return PremiumFeature.allCases.filter { hasAccess(to: $0) }
    }
    
    /// Check all locked features for current/simulated tier
    public var lockedFeatures: [PremiumFeature] {
        return PremiumFeature.allCases.filter { !hasAccess(to: $0) }
    }
    
    // MARK: - AI Prompts
    
    // MARK: Rate Limiting (Abuse Protection)
    
    /// Timestamps of recent AI prompts for per-minute rate limiting.
    /// Prevents API abuse by capping messages per minute regardless of tier.
    private var recentPromptTimestamps: [Date] = []
    
    /// Maximum messages allowed per minute (all tiers).
    /// Normal users never hit this — it only catches scripted/automated abuse.
    private let maxPromptsPerMinute: Int = 5
    
    /// Cooldown period in seconds after hitting the per-minute rate limit.
    /// User must wait this long before sending another message.
    private let rateLimitCooldownSeconds: TimeInterval = 30
    
    /// The date when the rate limit cooldown expires (nil = not rate limited)
    private var rateLimitCooldownUntil: Date?
    
    /// Whether the user is currently rate limited (sending too fast)
    public var isRateLimited: Bool {
        // Dev mode bypasses rate limiting
        if isDeveloperMode { return false }
        
        // Check if in cooldown period
        if let cooldownUntil = rateLimitCooldownUntil {
            if Date() < cooldownUntil {
                return true
            } else {
                // Cooldown expired, clear it
                rateLimitCooldownUntil = nil
            }
        }
        return false
    }
    
    /// Seconds remaining on the rate limit cooldown (0 if not rate limited)
    public var rateLimitSecondsRemaining: Int {
        guard let cooldownUntil = rateLimitCooldownUntil else { return 0 }
        let remaining = cooldownUntil.timeIntervalSince(Date())
        return remaining > 0 ? Int(ceil(remaining)) : 0
    }
    
    /// Prune timestamps older than 60 seconds and check per-minute limit
    private func checkAndUpdateRateLimit() {
        let oneMinuteAgo = Date().addingTimeInterval(-60)
        recentPromptTimestamps.removeAll { $0 < oneMinuteAgo }
        
        if recentPromptTimestamps.count >= maxPromptsPerMinute {
            // User is sending too fast — activate cooldown
            rateLimitCooldownUntil = Date().addingTimeInterval(rateLimitCooldownSeconds)
        }
    }
    
    /// Check if user can send another AI prompt today
    /// In developer mode, respects the simulated tier's prompt limits
    public var canSendAIPrompt: Bool {
        // In developer mode, don't actually track prompts but respect tier limits for testing
        if isDeveloperMode {
            return true // Always allow in dev mode
        }
        // Check per-minute rate limit first (abuse protection)
        if isRateLimited { return false }
        checkDailyReset()
        return aiPromptsUsedToday < currentTier.aiPromptsPerDay
    }
    
    /// Get remaining AI prompts for today
    /// In developer mode, shows simulated tier's limits (but doesn't actually count)
    public var remainingAIPrompts: Int {
        let tierToCheck = isDeveloperMode ? developerSimulatedTier : currentTier
        if isDeveloperMode {
            // Show simulated remaining based on tier (always show full amount since we don't count in dev mode)
            return tierToCheck.aiPromptsPerDay
        }
        checkDailyReset()
        let remaining = tierToCheck.aiPromptsPerDay - aiPromptsUsedToday
        return max(0, remaining)
    }
    
    /// Get remaining prompts as display string
    public var remainingPromptsDisplay: String {
        // Show rate limit message if active
        if isRateLimited {
            return "Wait \(rateLimitSecondsRemaining)s"
        }
        let tierToCheck = isDeveloperMode ? developerSimulatedTier : currentTier
        // Premium users see "Unlimited" even though there's a soft cap
        if tierToCheck == .premium {
            if isDeveloperMode {
                return "Unlimited (Dev)"
            }
            return "Unlimited"
        }
        if isDeveloperMode {
            return "\(tierToCheck.aiPromptsPerDay)/day (Dev)"
        }
        return "\(remainingAIPrompts) left today"
    }
    
    /// Check if user is approaching their AI prompt limit (for soft warnings)
    public var isApproachingPromptLimit: Bool {
        let tierToCheck = isDeveloperMode ? developerSimulatedTier : currentTier
        // Premium users don't get warnings (soft cap)
        if tierToCheck == .premium { return false }
        let remaining = remainingAIPrompts
        let total = tierToCheck.aiPromptsPerDay
        // Warn when less than 20% remaining
        return remaining > 0 && Double(remaining) / Double(total) < 0.2
    }
    
    /// Record an AI prompt usage
    /// - Parameter modelUsed: The AI model used for this prompt (for analytics)
    public func recordAIPromptUsage(modelUsed: String = "gpt-4o-mini") {
        // Don't count prompts in developer mode (allows unlimited testing)
        if isDeveloperMode { return }
        checkDailyReset()
        aiPromptsUsedToday += 1
        
        // Track per-minute rate for abuse protection
        recentPromptTimestamps.append(Date())
        checkAndUpdateRateLimit()
        
        saveState()
        objectWillChange.send()
        
        // Track analytics
        AnalyticsService.shared.trackAIPromptUsed(
            promptNumber: aiPromptsUsedToday,
            limit: currentTier.aiPromptsPerDay,
            modelUsed: modelUsed
        )
    }
    
    // MARK: - Ads
    
    /// Check if ads should be shown
    /// In developer mode, respects the simulated tier
    public var shouldShowAds: Bool {
        let tierToCheck = isDeveloperMode ? developerSimulatedTier : currentTier
        return tierToCheck == .free
    }
    
    // MARK: - Effective Tier
    
    /// Returns the effective tier (simulated tier if developer mode is on, otherwise actual tier)
    public var effectiveTier: SubscriptionTierType {
        if isDeveloperMode { return developerSimulatedTier }
        return currentTier
    }
}

// MARK: - SwiftUI View Modifiers

/// A view modifier that shows an upgrade prompt when the user doesn't have access to a feature
public struct FeatureGateModifier: ViewModifier {
    let feature: PremiumFeature
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showUpgradePrompt = false
    
    public func body(content: Content) -> some View {
        if subscriptionManager.hasAccess(to: feature) {
            content
        } else {
            content
                .disabled(true)
                .opacity(0.6)
                .overlay(
                    Button(action: {
                        showUpgradePrompt = true
                    }) {
                        Color.clear
                    }
                )
                .unifiedPaywallSheet(feature: feature, isPresented: $showUpgradePrompt)
        }
    }
}

public extension View {
    /// Gate a view behind a premium feature requirement
    func requiresFeature(_ feature: PremiumFeature) -> some View {
        modifier(FeatureGateModifier(feature: feature))
    }
}

// MARK: - Upgrade Prompt View (Legacy - use UnifiedPaywallSheet instead)

@available(*, deprecated, message: "Use UnifiedPaywallSheet instead for consistent paywall presentation")
struct FeatureUpgradePromptView: View {
    let feature: PremiumFeature
    
    var body: some View {
        // Delegates to the unified paywall for consistent design
        UnifiedPaywallSheet(feature: feature)
    }
}

// MARK: - AI Prompt Limit View

struct AIPromptLimitView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.2))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.orange)
                }
                
                // Title
                Text("Daily Limit Reached")
                    .font(.title2.weight(.bold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                // Message
                Text("You've used all \(subscriptionManager.currentTier.aiPromptsPerDay) AI prompts for today. Upgrade your plan for more prompts!")
                    .font(.body)
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                
                // Comparison (uses effectiveTier for developer mode consistency)
                VStack(spacing: 12) {
                    PromptLimitRow(tier: .free, isCurrentTier: subscriptionManager.effectiveTier == .free)
                    PromptLimitRow(tier: .pro, isCurrentTier: subscriptionManager.effectiveTier == .pro)
                    PromptLimitRow(tier: .premium, isCurrentTier: subscriptionManager.effectiveTier == .premium)
                }
                .padding(.horizontal, 24)
                
                Spacer()
                
                // Upgrade button (uses effectiveTier for developer mode consistency)
                if subscriptionManager.effectiveTier != .premium {
                    NavigationLink(destination: SubscriptionPricingView()) {
                        HStack {
                            Image(systemName: "arrow.up.circle.fill")
                            Text("Upgrade for More Prompts")
                        }
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [BrandColors.goldLight, BrandColors.goldBase],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(14)
                    }
                    .padding(.horizontal, 24)
                }
                
                // Dismiss button
                Button("Got It") {
                    dismiss()
                }
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
                .padding(.bottom, 16)
            }
            .padding(.top, 40)
            .background(DS.Adaptive.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                }
            }
        }
    }
}

private struct PromptLimitRow: View {
    let tier: SubscriptionTierType
    let isCurrentTier: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(tier.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    if isCurrentTier {
                        Text("Current")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(BrandColors.goldBase)
                            .cornerRadius(4)
                    }
                }
                
                Text(tier.monthlyPrice + "/mo")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            Spacer()
            
            Text(tier.aiPromptsDisplay)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(tier == .premium ? .green : DS.Adaptive.textSecondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isCurrentTier ? BrandColors.goldBase.opacity(0.1) : DS.Adaptive.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isCurrentTier ? BrandColors.goldBase.opacity(0.5) : DS.Adaptive.stroke, lineWidth: 1)
                )
        )
    }
}

// MARK: - Locked Feature Badge

/// A compact badge showing that a feature requires Pro or Premium tier
public struct LockedFeatureBadge: View {
    let feature: PremiumFeature
    var style: BadgeStyle = .compact
    
    public enum BadgeStyle {
        case compact    // Small pill badge
        case standard   // Medium badge with icon
        case expanded   // Full badge with description
    }
    
    private var tierColor: Color {
        switch feature.requiredTier {
        case .pro: return BrandColors.goldBase
        case .premium: return .purple
        case .free: return .gray
        }
    }
    
    public var body: some View {
        switch style {
        case .compact:
            compactBadge
        case .standard:
            standardBadge
        case .expanded:
            expandedBadge
        }
    }
    
    private var compactBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill")
                .font(.system(size: 8, weight: .bold))
            Text(feature.requiredTier.displayName.uppercased())
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundColor(tierColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(tierColor.opacity(0.15))
        )
    }
    
    private var standardBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "crown.fill")
                .font(.system(size: 12))
            Text(feature.requiredTier.displayName)
                .font(.caption.weight(.semibold))
        }
        .foregroundColor(tierColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(tierColor.opacity(0.15))
                .overlay(
                    Capsule()
                        .stroke(tierColor.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    private var expandedBadge: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 14))
                Text("Requires \(feature.requiredTier.displayName)")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundColor(tierColor)
            
            Text(feature.upgradeMessage)
                .font(.caption)
                .foregroundColor(DS.Adaptive.textSecondary)
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(tierColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(tierColor.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Locked Feature Overlay

/// An overlay that shows a locked feature state with optional tap-to-upgrade
public struct LockedFeatureOverlay: View {
    let feature: PremiumFeature
    var showUpgradeButton: Bool = true
    @State private var showUpgradeSheet = false
    
    private var tierColor: Color {
        switch feature.requiredTier {
        case .pro: return BrandColors.goldBase
        case .premium: return .purple
        case .free: return .gray
        }
    }
    
    public var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.6)
            
            VStack(spacing: 16) {
                // Lock icon
                ZStack {
                    Circle()
                        .fill(tierColor.opacity(0.2))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: "lock.fill")
                        .font(.system(size: 24))
                        .foregroundColor(tierColor)
                }
                
                // Feature name
                Text(feature.displayName)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)
                
                // Tier badge
                LockedFeatureBadge(feature: feature, style: .standard)
                
                // Upgrade button
                if showUpgradeButton {
                    Button {
                        showUpgradeSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.circle.fill")
                            Text("Upgrade to \(feature.requiredTier.displayName)")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [BrandColors.goldLight, BrandColors.goldBase],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                    }
                }
            }
        }
        .unifiedPaywallSheet(feature: feature, isPresented: $showUpgradeSheet)
    }
}

// MARK: - Feature Locked Section

/// A complete locked section that can wrap any content
public struct FeatureLockedSection<Content: View>: View {
    let feature: PremiumFeature
    let content: Content
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showUpgradePrompt = false
    
    public init(feature: PremiumFeature, @ViewBuilder content: () -> Content) {
        self.feature = feature
        self.content = content()
    }
    
    public var body: some View {
        if subscriptionManager.hasAccess(to: feature) {
            content
        } else {
            lockedContent
        }
    }
    
    private var lockedContent: some View {
        VStack(spacing: 12) {
            content
                .opacity(0.5)
                .allowsHitTesting(false)
            
            Button {
                showUpgradePrompt = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 14))
                    Text("Unlock \(feature.displayName)")
                        .font(.subheadline.weight(.semibold))
                    LockedFeatureBadge(feature: feature, style: .compact)
                }
                .foregroundColor(DS.Adaptive.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(DS.Adaptive.cardBackground)
                        .overlay(
                            Capsule()
                                .stroke(DS.Adaptive.stroke, lineWidth: 1)
                        )
                )
            }
        }
        .unifiedPaywallSheet(feature: feature, isPresented: $showUpgradePrompt)
    }
}

// MARK: - Inline Locked Indicator

/// A small inline indicator showing a feature is locked (for settings rows, etc.)
public struct InlineLockedIndicator: View {
    let tier: SubscriptionTierType
    
    private var tierColor: Color {
        switch tier {
        case .pro: return BrandColors.goldBase
        case .premium: return .purple
        case .free: return .gray
        }
    }
    
    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10))
            Text(tier.displayName)
                .font(.caption2.weight(.bold))
        }
        .foregroundColor(tierColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(tierColor.opacity(0.12))
        )
    }
}

// MARK: - View Extension for Inline Lock Badge

public extension View {
    /// Adds a locked badge to views that require a premium feature
    @ViewBuilder
    func lockedBadge(for feature: PremiumFeature, alignment: Alignment = .topTrailing) -> some View {
        let manager = SubscriptionManager.shared
        if manager.hasAccess(to: feature) {
            self
        } else {
            self.overlay(alignment: alignment) {
                LockedFeatureBadge(feature: feature, style: .compact)
                    .padding(8)
            }
        }
    }
}
