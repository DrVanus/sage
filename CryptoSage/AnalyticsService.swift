//
//  AnalyticsService.swift
//  CryptoSage
//
//  Analytics and telemetry service for product improvement.
//  Privacy-first: No personal data, anonymous usage only.
//

import Foundation
import os.log
import FirebaseAnalytics

// MARK: - Analytics Events

/// All trackable analytics events in CryptoSage
public enum AnalyticsEvent: String, CaseIterable {
    // MARK: Screen Views
    case screenView = "screen_view"
    
    // MARK: Tab Navigation
    case tabHome = "tab_home"
    case tabMarket = "tab_market"
    case tabTrade = "tab_trade"
    case tabPortfolio = "tab_portfolio"
    case tabAI = "tab_ai"
    
    // MARK: Feature Engagement
    case chartViewed = "chart_viewed"
    case chartTimeframeChanged = "chart_timeframe_changed"
    case aiChatStarted = "ai_chat_started"
    case aiChatMessageSent = "ai_chat_message_sent"
    case heatmapViewed = "heatmap_viewed"
    case heatmapInteraction = "heatmap_interaction"
    case alertCreated = "alert_created"
    case alertTriggered = "alert_triggered"
    case watchlistAdded = "watchlist_added"
    case watchlistRemoved = "watchlist_removed"
    case newsArticleViewed = "news_article_viewed"
    case coinDetailViewed = "coin_detail_viewed"
    
    // MARK: Business Events
    case exchangeConnected = "exchange_connected"
    case exchangeDisconnected = "exchange_disconnected"
    case portfolioViewed = "portfolio_viewed"
    case portfolioRefreshed = "portfolio_refresh"
    case subscriptionViewed = "subscription_viewed"
    case subscriptionStarted = "subscription_started"
    case tradeExecuted = "trade_executed"
    case paperTradeExecuted = "paper_trade_executed"
    
    // MARK: App Lifecycle
    case appLaunched = "app_launched"
    case appBackgrounded = "app_backgrounded"
    case appForegrounded = "app_foregrounded"
    case sessionStarted = "session_started"
    case sessionEnded = "session_ended"
    
    // MARK: Settings
    case settingsChanged = "settings_changed"
    case themeChanged = "theme_changed"
    case privacyModeToggled = "privacy_mode_toggled"
    case analyticsOptOut = "analytics_opt_out"
    case analyticsOptIn = "analytics_opt_in"
    
    // MARK: Errors (anonymous)
    case errorOccurred = "error_occurred"
    case apiError = "api_error"
    case networkError = "network_error"
    
    // MARK: Subscription & Monetization
    case subscriptionUpgradeStarted = "subscription_upgrade_started"
    case subscriptionUpgradeCompleted = "subscription_upgrade_completed"
    case subscriptionUpgradeFailed = "subscription_upgrade_failed"
    case subscriptionCancelled = "subscription_cancelled"
    case subscriptionRestored = "subscription_restored"
    case paywallViewed = "paywall_viewed"
    case paywallDismissed = "paywall_dismissed"
    case paywallConversion = "paywall_conversion"
    
    // MARK: Feature Access & Limits
    case featureAccessAttempt = "feature_access_attempt"
    case featureAccessGranted = "feature_access_granted"
    case featureAccessDenied = "feature_access_denied"
    case aiPromptUsed = "ai_prompt_used"
    case aiPromptLimitReached = "ai_prompt_limit_reached"
    case aiPromptLimitWarning = "ai_prompt_limit_warning"
    case priceAlertLimitReached = "price_alert_limit_reached"
    
    // MARK: AI Features
    case aiPredictionGenerated = "ai_prediction_generated"
    case aiInsightGenerated = "ai_insight_generated"
    case aiModelUpgrade = "ai_model_upgrade"  // When Elite user uses GPT-4o
    
    // MARK: AI Cost Tracking (for utilization analysis)
    case aiFeatureUsage = "ai_feature_usage"           // Tracks each AI feature use with details
    case aiCostEstimate = "ai_cost_estimate"           // Tracks estimated cost per call
    case aiUtilizationReport = "ai_utilization_report" // Daily utilization summary
    case aiCacheHit = "ai_cache_hit"                   // Track when cache is used (cost savings)
    case aiCooldownTriggered = "ai_cooldown_triggered" // Track when cooldown prevents API call
    
    // MARK: Ads (Free Tier)
    case bannerAdImpression = "banner_ad_impression"
    case bannerAdClicked = "banner_ad_clicked"
    case interstitialAdShown = "interstitial_ad_shown"
    case interstitialAdDismissed = "interstitial_ad_dismissed"
    case interstitialAdFailed = "interstitial_ad_failed"
}

// MARK: - User Properties

/// User properties for segmentation (anonymous, no PII)
public enum AnalyticsUserProperty: String {
    case subscriptionTier = "subscription_tier"
    case connectedExchangeCount = "connected_exchange_count"
    case portfolioSizeRange = "portfolio_size_range"  // e.g., "1k-10k", not exact value
    case preferredTheme = "preferred_theme"
    case appVersion = "app_version"
    case deviceType = "device_type"
    case osVersion = "os_version"
    case aiPromptsUsedToday = "ai_prompts_used_today"
    case totalFeatureAttempts = "total_feature_attempts"
    case paywallViews = "paywall_views"
    case daysAsUser = "days_as_user"
}

// MARK: - Analytics Service

/// Main analytics service - privacy-first, anonymous telemetry only.
/// Respects user opt-out preference.
public final class AnalyticsService: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = AnalyticsService()
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "ai.cryptosage", category: "Analytics")
    private let queue = DispatchQueue(label: "ai.cryptosage.analytics", qos: .utility)
    
    /// User defaults key for analytics opt-in
    private let analyticsEnabledKey = "Analytics.Enabled"
    
    /// User defaults key for first launch consent
    private let consentShownKey = "Analytics.ConsentShown"
    
    /// Session ID for grouping events (regenerated each launch)
    private var sessionID: String = UUID().uuidString
    
    /// Session start time
    private var sessionStartTime: Date = Date()
    
    /// Whether analytics is enabled by user
    public var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: analyticsEnabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: analyticsEnabledKey)
            
            // CRITICAL: Enforce Firebase Analytics collection opt-out
            Analytics.setAnalyticsCollectionEnabled(newValue)
            
            if newValue {
                track(.analyticsOptIn)
            }
            // Note: Don't track opt-out since analytics is disabled
        }
    }
    
    /// Whether consent dialog has been shown
    public var hasShownConsent: Bool {
        get { UserDefaults.standard.bool(forKey: consentShownKey) }
        set { UserDefaults.standard.set(newValue, forKey: consentShownKey) }
    }
    
    // MARK: - Initialization
    
    private init() {
        #if targetEnvironment(simulator)
        // Simulator stability: disable outbound analytics collection entirely.
        // Recent simulator runtimes can churn memory on analytics upload retries,
        // which masks app-level startup behavior and causes false crash loops.
        UserDefaults.standard.set(false, forKey: analyticsEnabledKey)
        Analytics.setAnalyticsCollectionEnabled(false)
        logger.info("Analytics disabled on Simulator")
        return
        #endif

        // Default to enabled for new users (industry standard)
        // User can opt out in Settings
        if UserDefaults.standard.object(forKey: analyticsEnabledKey) == nil {
            UserDefaults.standard.set(true, forKey: analyticsEnabledKey)
        }
        
        // CRITICAL: Sync Firebase Analytics collection state with user preference
        let analyticsEnabled = UserDefaults.standard.bool(forKey: analyticsEnabledKey)
        Analytics.setAnalyticsCollectionEnabled(analyticsEnabled)
        
        // Configure TelemetryDeck if available
        configureTelemetryDeck()
        
        // Set default user properties
        setDefaultUserProperties()
    }
    
    // MARK: - TelemetryDeck Configuration
    
    /// TelemetryDeck App ID - Configure this with your App ID from https://telemetrydeck.com
    /// Leave empty or as placeholder to disable TelemetryDeck (Firebase Analytics will still work)
    private let telemetryDeckAppID: String? = {
        // SETUP: TelemetryDeck - privacy-first, GDPR-compliant analytics
        // 1. Create account at https://telemetrydeck.com
        // 2. Create an app to get your App ID
        // 3. Add Swift Package: https://github.com/TelemetryDeck/SwiftSDK
        // 4. Replace the placeholder below with your App ID
        let appID = ""  // Empty = disabled, set to your App ID to enable
        return appID.isEmpty || appID.contains("YOUR_") ? nil : appID
    }()
    
    private func configureTelemetryDeck() {
        #if canImport(TelemetryDeck)
        // Skip TelemetryDeck initialization if App ID is not configured
        guard let appID = telemetryDeckAppID else {
            logger.info("TelemetryDeck App ID not configured - using Firebase Analytics only")
            return
        }
        
        let config = TelemetryDeck.Config(appID: appID)
        TelemetryDeck.initialize(config: config)
        logger.info("TelemetryDeck initialized")
        #else
        logger.info("TelemetryDeck not available - analytics will log locally only")
        #endif
    }
    
    // MARK: - Event Tracking
    
    /// Track an analytics event
    /// - Parameters:
    ///   - event: The event type to track
    ///   - parameters: Optional parameters (no PII allowed)
    public func track(_ event: AnalyticsEvent, parameters: [String: String]? = nil) {
        guard isEnabled else { return }
        
        queue.async { [weak self] in
            self?.trackInternal(event, parameters: parameters)
        }
    }
    
    private func trackInternal(_ event: AnalyticsEvent, parameters: [String: String]?) {
        var allParams = parameters ?? [:]
        allParams["session_id"] = sessionID
        allParams["timestamp"] = ISO8601DateFormatter().string(from: Date())
        
        // Log locally for debugging
        #if DEBUG
        let paramString = allParams.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        logger.debug("📊 Analytics: \(event.rawValue) [\(paramString)]")
        #endif
        
        // Send to Firebase Analytics
        Analytics.logEvent(event.rawValue, parameters: allParams)
        
        // Send to TelemetryDeck if available
        #if canImport(TelemetryDeck)
        TelemetryDeck.signal(event.rawValue, parameters: allParams)
        #endif
    }
    
    // MARK: - Screen Tracking
    
    /// Track a screen view
    /// - Parameter screenName: The name of the screen being viewed
    public func trackScreen(_ screenName: String) {
        track(.screenView, parameters: ["screen_name": screenName])
    }
    
    /// Track tab selection
    /// - Parameter tab: The selected tab
    public func trackTabSelection(_ tab: String) {
        let event: AnalyticsEvent
        switch tab.lowercased() {
        case "home": event = .tabHome
        case "market": event = .tabMarket
        case "trade": event = .tabTrade
        case "portfolio": event = .tabPortfolio
        case "ai": event = .tabAI
        default:
            track(.screenView, parameters: ["screen_name": tab])
            return
        }
        track(event)
    }
    
    // MARK: - User Properties
    
    /// Set a user property for segmentation
    /// - Parameters:
    ///   - property: The property to set
    ///   - value: The value (no PII allowed)
    public func setUserProperty(_ property: AnalyticsUserProperty, value: String?) {
        guard isEnabled, let value = value else { return }
        
        // Send to Firebase Analytics
        Analytics.setUserProperty(value, forName: property.rawValue)
        
        #if canImport(TelemetryDeck)
        TelemetryDeck.updateDefaultParameters([property.rawValue: value])
        #endif
        
        #if DEBUG
        logger.debug("📊 User Property: \(property.rawValue) = \(value)")
        #endif
    }
    
    private func setDefaultUserProperties() {
        // App version
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            setUserProperty(.appVersion, value: version)
        }
        
        // Device type
        #if os(iOS)
        setUserProperty(.deviceType, value: UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")
        setUserProperty(.osVersion, value: UIDevice.current.systemVersion)
        #endif
    }
    
    // MARK: - Session Management
    
    /// Start a new analytics session (call on app launch)
    public func startSession() {
        sessionID = UUID().uuidString
        sessionStartTime = Date()
        track(.sessionStarted)
        track(.appLaunched)
    }
    
    /// End the current session (call on app termination/background)
    public func endSession() {
        let duration = Date().timeIntervalSince(sessionStartTime)
        track(.sessionEnded, parameters: [
            "duration_seconds": String(Int(duration))
        ])
    }
    
    /// App entered foreground
    public func appDidBecomeActive() {
        track(.appForegrounded)
    }
    
    /// App entered background
    public func appDidEnterBackground() {
        track(.appBackgrounded)
        endSession()
    }
    
    // MARK: - Business Event Helpers
    
    /// Track portfolio size range (anonymized, not exact value)
    public func updatePortfolioSizeRange(totalValue: Double) {
        let range: String
        switch totalValue {
        case ..<100: range = "0-100"
        case 100..<1000: range = "100-1k"
        case 1000..<10000: range = "1k-10k"
        case 10000..<100000: range = "10k-100k"
        case 100000..<1000000: range = "100k-1M"
        default: range = "1M+"
        }
        setUserProperty(.portfolioSizeRange, value: range)
    }
    
    /// Track subscription tier
    public func updateSubscriptionTier(_ tier: String) {
        setUserProperty(.subscriptionTier, value: tier)
    }
    
    // MARK: - Error Tracking (Anonymous)
    
    /// Track an error (no stack traces or user data)
    /// - Parameters:
    ///   - domain: Error domain (e.g., "API", "Network", "Chart")
    ///   - code: Error code or type
    public func trackError(domain: String, code: String) {
        track(.errorOccurred, parameters: [
            "error_domain": domain,
            "error_code": code
        ])
    }
    
    // MARK: - Subscription & Monetization Tracking
    
    /// Track when user views the subscription/paywall screen
    /// - Parameters:
    ///   - source: Where the paywall was triggered from (e.g., "feature_gate", "periodic", "settings")
    ///   - feature: The feature that triggered the paywall (if any)
    @MainActor public func trackPaywallViewed(source: String, feature: String? = nil) {
        var params = ["source": source]
        if let feature = feature {
            params["trigger_feature"] = feature
        }
        params["current_tier"] = SubscriptionManager.shared.effectiveTier.rawValue
        track(.paywallViewed, parameters: params)
    }
    
    /// Track when user dismisses the paywall without upgrading
    /// - Parameter source: Where the paywall was triggered from
    @MainActor public func trackPaywallDismissed(source: String) {
        track(.paywallDismissed, parameters: [
            "source": source,
            "current_tier": SubscriptionManager.shared.effectiveTier.rawValue
        ])
    }
    
    /// Track subscription upgrade attempt
    /// - Parameters:
    ///   - fromTier: Current tier
    ///   - toTier: Target tier
    ///   - isAnnual: Whether annual billing was selected
    public func trackSubscriptionUpgradeStarted(fromTier: String, toTier: String, isAnnual: Bool) {
        track(.subscriptionUpgradeStarted, parameters: [
            "from_tier": fromTier,
            "to_tier": toTier,
            "billing_period": isAnnual ? "annual" : "monthly"
        ])
    }
    
    /// Track successful subscription upgrade
    /// - Parameters:
    ///   - tier: New subscription tier
    ///   - isAnnual: Whether annual billing was selected
    ///   - price: Subscription price (optional, for revenue tracking)
    ///   - currency: Currency code (optional, defaults to USD)
    public func trackSubscriptionUpgradeCompleted(tier: String, isAnnual: Bool, price: Double? = nil, currency: String = "USD") {
        track(.subscriptionUpgradeCompleted, parameters: [
            "tier": tier,
            "billing_period": isAnnual ? "annual" : "monthly"
        ])
        track(.paywallConversion, parameters: [
            "converted_to": tier
        ])
        
        // REVENUE TRACKING: Log Firebase purchase event for App Store revenue analytics
        if let price = price {
            let purchaseParams: [String: Any] = [
                AnalyticsParameterItemID: "\(tier)_\(isAnnual ? "annual" : "monthly")",
                AnalyticsParameterItemName: "\(tier.capitalized) Subscription",
                AnalyticsParameterItemCategory: "subscription",
                AnalyticsParameterPrice: price,
                AnalyticsParameterCurrency: currency,
                AnalyticsParameterValue: price,
                "billing_period": isAnnual ? "annual" : "monthly",
                "tier": tier
            ]
            Analytics.logEvent(AnalyticsEventPurchase, parameters: purchaseParams)
            
            #if DEBUG
            logger.debug("📊 Revenue tracked: \(tier) - \(currency) \(price)")
            #endif
        }
        
        // Update user property
        setUserProperty(.subscriptionTier, value: tier)
    }
    
    /// Track failed subscription upgrade
    /// - Parameters:
    ///   - tier: Attempted tier
    ///   - reason: Failure reason (anonymized)
    public func trackSubscriptionUpgradeFailed(tier: String, reason: String) {
        track(.subscriptionUpgradeFailed, parameters: [
            "attempted_tier": tier,
            "failure_reason": reason
        ])
    }
    
    /// Track subscription restoration
    /// - Parameter tier: Restored subscription tier
    public func trackSubscriptionRestored(tier: String) {
        track(.subscriptionRestored, parameters: [
            "tier": tier
        ])
        setUserProperty(.subscriptionTier, value: tier)
        
        #if DEBUG
        logger.debug("📊 Subscription restored: \(tier)")
        #endif
    }
    
    /// Track subscription cancellation
    /// - Parameters:
    ///   - tier: Cancelled subscription tier
    ///   - reason: Cancellation reason (if available)
    public func trackSubscriptionCancelled(tier: String, reason: String? = nil) {
        var params: [String: String] = ["tier": tier]
        if let reason = reason {
            params["reason"] = reason
        }
        track(.subscriptionCancelled, parameters: params)
        setUserProperty(.subscriptionTier, value: "free")
        
        #if DEBUG
        logger.debug("📊 Subscription cancelled: \(tier)")
        #endif
    }
    
    // MARK: - Exchange & Portfolio Tracking
    
    /// Track exchange connection
    /// - Parameters:
    ///   - exchangeName: Name of the exchange (e.g., "Coinbase", "Binance")
    ///   - provider: Connection provider/method
    public func trackExchangeConnected(exchangeName: String, provider: String? = nil) {
        var params: [String: String] = ["exchange": exchangeName]
        if let provider = provider {
            params["provider"] = provider
        }
        track(.exchangeConnected, parameters: params)
        
        #if DEBUG
        logger.debug("📊 Exchange connected: \(exchangeName)")
        #endif
    }
    
    /// Track exchange disconnection
    /// - Parameter exchangeName: Name of the exchange
    public func trackExchangeDisconnected(exchangeName: String) {
        track(.exchangeDisconnected, parameters: [
            "exchange": exchangeName
        ])
        
        #if DEBUG
        logger.debug("📊 Exchange disconnected: \(exchangeName)")
        #endif
    }
    
    /// Update connected exchange count user property
    /// - Parameter count: Number of connected exchanges
    public func updateConnectedExchangeCount(_ count: Int) {
        setUserProperty(.connectedExchangeCount, value: String(count))
    }
    
    /// Track portfolio sync
    /// - Parameters:
    ///   - success: Whether sync was successful
    ///   - exchangeCount: Number of exchanges synced
    public func trackPortfolioSync(success: Bool, exchangeCount: Int) {
        track(.portfolioRefreshed, parameters: [
            "success": success ? "true" : "false",
            "exchange_count": String(exchangeCount)
        ])
    }
    
    // MARK: - Feature Access Tracking
    
    /// Track when user attempts to access a premium feature
    /// - Parameters:
    ///   - feature: The feature being accessed
    ///   - granted: Whether access was granted
    @MainActor public func trackFeatureAccess(feature: PremiumFeature, granted: Bool) {
        let params: [String: String] = [
            "feature": feature.rawValue,
            "feature_name": feature.displayName,
            "required_tier": feature.requiredTier.rawValue,
            "current_tier": SubscriptionManager.shared.effectiveTier.rawValue
        ]
        
        if granted {
            track(.featureAccessGranted, parameters: params)
        } else {
            track(.featureAccessDenied, parameters: params)
            track(.featureAccessAttempt, parameters: params)
        }
    }
    
    // MARK: - AI Usage Tracking
    
    /// Track AI prompt usage
    /// - Parameters:
    ///   - promptNumber: Which prompt number this is today
    ///   - limit: The user's daily limit
    ///   - modelUsed: Which AI model was used
    @MainActor public func trackAIPromptUsed(promptNumber: Int, limit: Int, modelUsed: String) {
        let tier = SubscriptionManager.shared.effectiveTier
        track(.aiPromptUsed, parameters: [
            "prompt_number": String(promptNumber),
            "daily_limit": limit == Int.max ? "unlimited" : String(limit),
            "tier": tier.rawValue,
            "model_used": modelUsed
        ])
        
        // Track if using premium model (Elite)
        if modelUsed == "gpt-4o" {
            track(.aiModelUpgrade, parameters: ["tier": tier.rawValue])
        }
        
        // Update user property
        setUserProperty(.aiPromptsUsedToday, value: String(promptNumber))
        
        // Track limit warnings
        if tier != .premium {
            let remaining = limit - promptNumber
            if remaining == 0 {
                track(.aiPromptLimitReached, parameters: [
                    "tier": tier.rawValue,
                    "limit": String(limit)
                ])
            } else if remaining <= 2 && remaining > 0 {
                track(.aiPromptLimitWarning, parameters: [
                    "tier": tier.rawValue,
                    "remaining": String(remaining)
                ])
            }
        }
    }
    
    /// Track AI prediction generation
    /// - Parameters:
    ///   - coinSymbol: The coin symbol (e.g., "BTC")
    ///   - tier: User's subscription tier
    public func trackAIPredictionGenerated(coinSymbol: String, tier: String) {
        track(.aiPredictionGenerated, parameters: [
            "coin_symbol": coinSymbol,
            "tier": tier
        ])
    }
    
    /// Track AI insight generation
    /// - Parameter insightType: Type of insight (e.g., "portfolio", "market", "coin")
    @MainActor public func trackAIInsightGenerated(insightType: String) {
        track(.aiInsightGenerated, parameters: [
            "insight_type": insightType,
            "tier": SubscriptionManager.shared.effectiveTier.rawValue
        ])
    }
    
    // MARK: - AI Cost & Utilization Tracking
    
    /// AI feature types for tracking
    public enum AIFeatureType: String {
        case chat = "chat"
        case coinInsight = "coin_insight"
        case portfolioInsight = "portfolio_insight"
        case prediction = "prediction"
        case priceMovement = "price_movement"
        case fearGreed = "fear_greed"
        case deepDive = "deep_dive"
        case riskAnalysis = "risk_analysis"
    }
    
    /// Track detailed AI feature usage for cost analysis
    /// - Parameters:
    ///   - feature: The AI feature being used
    ///   - model: The model used (gpt-4o or gpt-4o-mini)
    ///   - maxTokens: Max tokens requested
    ///   - tier: User's subscription tier
    ///   - cached: Whether this was a cache hit (no API cost)
    ///   - isChat: Whether this is a direct chat interaction (vs automated feature)
    public func trackAIFeatureUsage(
        feature: AIFeatureType,
        model: String,
        maxTokens: Int,
        tier: SubscriptionTierType,
        cached: Bool = false,
        isChat: Bool = false
    ) {
        // Estimate cost based on model and tokens
        let estimatedCost: Double
        if cached {
            estimatedCost = 0
        } else if model == "gpt-4o" {
            // GPT-4o: ~$2.50/1M input + $10/1M output ≈ $0.025 per call
            estimatedCost = 0.025
        } else {
            // GPT-4o-mini: ~$0.15/1M input + $0.60/1M output ≈ $0.002 per call
            estimatedCost = 0.002
        }
        
        // Determine if user got premium model upgrade
        let gotPremiumModel = model == "gpt-4o" && tier == .platinum && isChat
        
        if cached {
            track(.aiCacheHit, parameters: [
                "feature": feature.rawValue,
                "tier": tier.rawValue
            ])
        } else {
            track(.aiFeatureUsage, parameters: [
                "feature": feature.rawValue,
                "model": model,
                "max_tokens": String(maxTokens),
                "tier": tier.rawValue,
                "is_chat": isChat ? "true" : "false",
                "premium_model_used": gotPremiumModel ? "true" : "false",
                "estimated_cost_cents": String(Int(estimatedCost * 100))
            ])
            
            track(.aiCostEstimate, parameters: [
                "feature": feature.rawValue,
                "tier": tier.rawValue,
                "cost_per_call": String(format: "%.4f", estimatedCost)
            ])
            
            // Track premium model upgrade for Platinum chat
            if gotPremiumModel {
                track(.aiModelUpgrade, parameters: [
                    "tier": tier.rawValue,
                    "feature": feature.rawValue
                ])
            }
        }
    }
    
    /// Track when cooldown prevents an API call (cost savings)
    /// - Parameters:
    ///   - feature: The AI feature
    ///   - tier: User's subscription tier
    public func trackAICooldownTriggered(feature: AIFeatureType, tier: SubscriptionTierType) {
        track(.aiCooldownTriggered, parameters: [
            "feature": feature.rawValue,
            "tier": tier.rawValue
        ])
    }
    
    /// Generate and track a daily AI utilization report
    /// Call this at end of day or on app termination
    @MainActor
    public func generateDailyUtilizationReport() {
        let tier = SubscriptionManager.shared.effectiveTier
        let manager = SubscriptionManager.shared
        
        // Get usage data from various sources
        let chatUsed = manager.aiPromptsUsedToday
        let chatLimit = tier.aiPromptsPerDay
        let chatUtilization = chatLimit > 0 ? Double(chatUsed) / Double(chatLimit) * 100 : 0
        
        track(.aiUtilizationReport, parameters: [
            "tier": tier.rawValue,
            "chat_used": String(chatUsed),
            "chat_limit": String(chatLimit),
            "chat_utilization_pct": String(Int(chatUtilization)),
            "date": ISO8601DateFormatter().string(from: Date())
        ])
        
        #if DEBUG
        logger.info("📊 AI Utilization Report - Tier: \(tier.rawValue), Chat: \(chatUsed)/\(chatLimit) (\(Int(chatUtilization))%)")
        #endif
    }
    
    // MARK: - Conversion Funnel Helpers
    
    /// Track the complete subscription funnel for a user
    /// Call this periodically or on key events to update funnel stage
    @MainActor
    public func updateConversionFunnelStage() {
        let tier = SubscriptionManager.shared.effectiveTier
        let paywallManager = PaywallManager.shared
        
        // Update user properties for funnel analysis
        setUserProperty(.subscriptionTier, value: tier.rawValue)
        setUserProperty(.totalFeatureAttempts, value: String(paywallManager.totalFeatureAttempts))
        setUserProperty(.paywallViews, value: String(paywallManager.promptDismissCount))
    }
}

// MARK: - SwiftUI View Extension

import SwiftUI

extension View {
    /// Track when this view appears
    /// - Parameter screenName: The name to log for this screen
    public func trackScreen(_ screenName: String) -> some View {
        self.onAppear {
            AnalyticsService.shared.trackScreen(screenName)
        }
    }
}

// MARK: - TelemetryDeck Stub (for compilation without package)

#if !canImport(TelemetryDeck)
/// Stub for TelemetryDeck when package is not installed
/// Remove this when you add the TelemetryDeck package
private enum TelemetryDeck {
    struct Config {
        let appID: String
        init(appID: String) { self.appID = appID }
    }
    static func initialize(config: Config) {}
    static func signal(_ name: String, parameters: [String: String]) {}
    static func updateDefaultParameters(_ params: [String: String]) {}
}
#endif
