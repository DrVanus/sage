//
//  AnalyticsService.swift
//  CryptoSage
//
//  Analytics and telemetry service for product improvement.
//  Privacy-first: No personal data, anonymous usage only.
//

import Foundation
import os.log

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
        // Default to enabled for new users (industry standard)
        // User can opt out in Settings
        if UserDefaults.standard.object(forKey: analyticsEnabledKey) == nil {
            UserDefaults.standard.set(true, forKey: analyticsEnabledKey)
        }
        
        // Configure TelemetryDeck if available
        configureTelemetryDeck()
        
        // Set default user properties
        setDefaultUserProperties()
    }
    
    // MARK: - TelemetryDeck Configuration
    
    private func configureTelemetryDeck() {
        #if canImport(TelemetryDeck)
        // TelemetryDeck configuration
        // App ID should be set here when you create a TelemetryDeck account
        // TelemetryDeck is privacy-first: no personal data, GDPR-compliant
        let config = TelemetryDeck.Config(appID: "YOUR_TELEMETRY_DECK_APP_ID")
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
    
    /// Track connected exchange count
    public func updateConnectedExchangeCount(_ count: Int) {
        setUserProperty(.connectedExchangeCount, value: String(count))
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
