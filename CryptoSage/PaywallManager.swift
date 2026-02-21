//
//  PaywallManager.swift
//  CryptoSage
//
//  Central manager for paywall logic, session tracking, and periodic upgrade prompts.
//

import Foundation
import SwiftUI
import Combine

// MARK: - Paywall Manager

/// Manages paywall display logic, session tracking, and periodic upgrade prompts
@MainActor
public final class PaywallManager: ObservableObject {
    public static let shared = PaywallManager()
    
    // MARK: - Published Properties
    
    /// Total number of app sessions since install
    @Published public private(set) var sessionCount: Int = 0
    
    /// Whether the periodic prompt should be shown
    @Published public var shouldShowPeriodicPrompt: Bool = false
    
    /// Last time a periodic prompt was shown
    @Published public private(set) var lastPromptDate: Date?
    
    /// Number of times user has dismissed upgrade prompts
    @Published public private(set) var promptDismissCount: Int = 0
    
    /// Features the user has attempted to access
    @Published public private(set) var attemptedFeatures: [PremiumFeature] = []
    
    /// The most recently attempted feature (for context in prompts)
    @Published public private(set) var lastAttemptedFeature: PremiumFeature?
    
    // MARK: - Configuration
    
    /// Number of sessions before showing first periodic prompt
    public let firstPromptAfterSessions: Int = 3
    
    /// Show periodic prompt every N sessions after the first
    public let promptEveryNSessions: Int = 3
    
    /// Minimum time between periodic prompts (24 hours)
    public let minTimeBetweenPrompts: TimeInterval = 86400
    
    /// After this many dismissals, reduce prompt frequency
    public let maxDismissalsBeforeReducing: Int = 5
    
    /// Reduced frequency multiplier after max dismissals
    public let reducedFrequencyMultiplier: Int = 2
    
    // MARK: - Storage Keys
    
    private let sessionCountKey = "Paywall.SessionCount"
    private let lastPromptDateKey = "Paywall.LastPromptDate"
    private let dismissCountKey = "Paywall.DismissCount"
    private let attemptedFeaturesKey = "Paywall.AttemptedFeatures"
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    private init() {
        loadState()
        setupSubscriptions()
    }
    
    // MARK: - State Management
    
    private func loadState() {
        sessionCount = UserDefaults.standard.integer(forKey: sessionCountKey)
        promptDismissCount = UserDefaults.standard.integer(forKey: dismissCountKey)
        
        if let lastDate = UserDefaults.standard.object(forKey: lastPromptDateKey) as? Date {
            lastPromptDate = lastDate
        }
        
        if let attemptedData = UserDefaults.standard.data(forKey: attemptedFeaturesKey),
           let features = try? JSONDecoder().decode([String].self, from: attemptedData) {
            attemptedFeatures = features.compactMap { PremiumFeature(rawValue: $0) }
        }
    }
    
    private func saveState() {
        UserDefaults.standard.set(sessionCount, forKey: sessionCountKey)
        UserDefaults.standard.set(promptDismissCount, forKey: dismissCountKey)
        
        if let lastDate = lastPromptDate {
            UserDefaults.standard.set(lastDate, forKey: lastPromptDateKey)
        }
        
        if let attemptedData = try? JSONEncoder().encode(attemptedFeatures.map { $0.rawValue }) {
            UserDefaults.standard.set(attemptedData, forKey: attemptedFeaturesKey)
        }
    }
    
    private func setupSubscriptions() {
        // Listen for subscription changes - reset prompts when user upgrades
        SubscriptionManager.shared.$currentTier
            .dropFirst()
            .sink { [weak self] newTier in
                if newTier != .free {
                    self?.resetPromptState()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Session Tracking
    
    /// Call this when the app launches to record a new session
    public func recordAppLaunch() {
        sessionCount += 1
        saveState()
        
        // Check if we should show periodic prompt
        checkPeriodicPrompt()
    }
    
    // MARK: - Periodic Prompt Logic
    
    /// Determines if a periodic prompt should be shown
    public func checkPeriodicPrompt() {
        // Don't show prompts to paid users
        guard SubscriptionManager.shared.effectiveTier == .free else {
            shouldShowPeriodicPrompt = false
            return
        }
        
        // Check if enough sessions have passed
        let effectivePromptFrequency = promptDismissCount >= maxDismissalsBeforeReducing
            ? promptEveryNSessions * reducedFrequencyMultiplier
            : promptEveryNSessions
        
        let sessionThreshold = firstPromptAfterSessions + (promptDismissCount > 0 ? effectivePromptFrequency : 0)
        
        guard sessionCount >= sessionThreshold else {
            shouldShowPeriodicPrompt = false
            return
        }
        
        // Check if this session should trigger a prompt
        let sessionsAfterFirst = sessionCount - firstPromptAfterSessions
        let shouldPromptBasedOnSession = sessionsAfterFirst >= 0 && sessionsAfterFirst % effectivePromptFrequency == 0
        
        // Check time since last prompt
        let hasEnoughTimePassed: Bool
        if let lastDate = lastPromptDate {
            hasEnoughTimePassed = Date().timeIntervalSince(lastDate) >= minTimeBetweenPrompts
        } else {
            hasEnoughTimePassed = true
        }
        
        shouldShowPeriodicPrompt = shouldPromptBasedOnSession && hasEnoughTimePassed
    }
    
    /// Call when the periodic prompt is shown
    public func recordPromptShown() {
        lastPromptDate = Date()
        saveState()
    }
    
    /// Call when user dismisses the prompt
    public func recordPromptDismissed() {
        promptDismissCount += 1
        shouldShowPeriodicPrompt = false
        saveState()
    }
    
    /// Reset prompt state (called when user upgrades)
    public func resetPromptState() {
        shouldShowPeriodicPrompt = false
        promptDismissCount = 0
        saveState()
    }
    
    // MARK: - Feature Tracking
    
    /// Track when a user attempts to access a premium feature
    public func trackFeatureAttempt(_ feature: PremiumFeature) {
        lastAttemptedFeature = feature
        
        if !attemptedFeatures.contains(feature) {
            attemptedFeatures.append(feature)
            saveState()
        }
    }
    
    /// Get the most relevant features to highlight in upgrade prompts
    /// Returns features user has tried, sorted by tier (Pro first, then Elite)
    public var relevantFeaturesForPrompt: [PremiumFeature] {
        let attempted = attemptedFeatures.prefix(3)
        if attempted.isEmpty {
            // Return default features if no attempts tracked
            return [.whaleTracking, .copyTrading, .tradingBots]
        }
        return Array(attempted)
    }
    
    /// Check if user has ever attempted a specific feature
    public func hasAttemptedFeature(_ feature: PremiumFeature) -> Bool {
        attemptedFeatures.contains(feature)
    }
    
    /// Get count of locked feature attempts
    public var totalFeatureAttempts: Int {
        attemptedFeatures.count
    }
    
    // MARK: - Convenience Methods
    
    /// Quick check if user should see any paywall (either periodic or feature-triggered)
    public func shouldGateFeature(_ feature: PremiumFeature) -> Bool {
        !SubscriptionManager.shared.hasAccess(to: feature)
    }
    
    /// Get the upgrade CTA text based on the feature's required tier
    public func upgradeCtaText(for feature: PremiumFeature) -> String {
        switch feature.requiredTier {
        case .free:
            return "Get Started"
        case .pro:
            return "Upgrade to Pro"
        case .premium:
            return "Upgrade to Premium"
        }
    }
    
    /// Get benefits list for upgrade prompts
    public func benefitsList(for tier: SubscriptionTierType) -> [PaywallBenefit] {
        switch tier {
        case .free:
            return []
        case .pro:
            return [
                PaywallBenefit(icon: "bubble.left.and.bubble.right.fill", title: "AI Chat Assistant", description: "Ask about any coin, analyze trades & get investment guidance"),
                PaywallBenefit(icon: "wand.and.stars", title: "AI Price Predictions", description: "Price targets, direction & confidence levels for any coin"),
                PaywallBenefit(icon: "chart.xyaxis.line", title: "AI-Powered Charts", description: "AI explains price moves, technicals & key levels"),
                PaywallBenefit(icon: "chart.pie.fill", title: "AI Portfolio Insights", description: "AI risk scores, allocation tips & portfolio summaries"),
                PaywallBenefit(icon: "doc.text.fill", title: "Paper Trading", description: "Practice with $100K virtual portfolio"),
                PaywallBenefit(icon: "water.waves", title: "Whale Tracking", description: "Track large wallet movements"),
                PaywallBenefit(icon: "doc.text.magnifyingglass", title: "Tax Reports", description: "Export up to 2,500 transactions"),
                PaywallBenefit(icon: "bell.badge.fill", title: "Unlimited Alerts", description: "Set alerts for any price target"),
                PaywallBenefit(icon: "checkmark.seal.fill", title: "Ad-Free Experience", description: "Clean, distraction-free interface")
            ]
        case .premium:
            return [
                PaywallBenefit(icon: "sparkles", title: "Unlimited AI Chat", description: "No daily limits on AI conversations"),
                PaywallBenefit(icon: "wand.and.stars", title: "Advanced Predictions", description: "More AI predictions per day with deeper analysis"),
                PaywallBenefit(icon: "lightbulb.max.fill", title: "Deep AI Insights", description: "Comprehensive AI-driven analysis across all features"),
                PaywallBenefit(icon: "chart.pie.fill", title: "AI Portfolio Optimizer", description: "Advanced rebalancing & allocation suggestions"),
                PaywallBenefit(icon: "cpu.fill", title: "Paper Trading Bots", description: "DCA, Grid & Signal bot simulators"),
                PaywallBenefit(icon: "doc.on.doc.fill", title: "Strategy Marketplace", description: "Browse & copy proven bot strategies"),
                PaywallBenefit(icon: "infinity", title: "Unlimited Tax Reports", description: "Export all transactions without limits"),
                PaywallBenefit(icon: "clock.badge.checkmark.fill", title: "Priority Access", description: "Be first to try new features & updates")
            ]
        }
    }
    
    // MARK: - Contextual Upgrade Prompts
    
    /// Get a personalized upgrade message based on user's feature attempts
    public func personalizedUpgradeMessage() -> String {
        guard let lastFeature = lastAttemptedFeature else {
            return "Unlock premium features to supercharge your crypto journey"
        }
        
        switch lastFeature.requiredTier {
        case .free:
            return "Start your crypto journey with CryptoSage"
        case .pro:
            return "Upgrade to Pro for \(lastFeature.displayName) and AI-powered portfolio analysis"
        case .premium:
            return "Upgrade to Premium for \(lastFeature.displayName) with CryptoSage AI and unlimited access"
        }
    }
    
    /// Get the recommended tier based on user's feature attempts
    public var recommendedTier: SubscriptionTierType {
        // If user has attempted Premium features, recommend Premium
        let premiumAttempts = attemptedFeatures.filter { $0.requiredTier == .premium }
        if !premiumAttempts.isEmpty {
            return .premium
        }
        // Otherwise recommend Pro
        return .pro
    }
    
    /// Get pricing text for the recommended tier
    public var recommendedTierPricing: String {
        switch recommendedTier {
        case .free:
            return "Free forever"
        case .pro:
            return "$9.99/month or $89.99/year (save 25%)"
        case .premium:
            return "$19.99/month or $179.99/year (save 25%)"
        }
    }
    
    /// Check if user is a good candidate for an upgrade prompt
    /// Returns true if user has been actively engaging but hitting limits
    public var isGoodCandidateForUpgrade: Bool {
        let tier = SubscriptionManager.shared.effectiveTier
        guard tier == .free else { return false }
        
        // Good candidates have:
        // 1. Used the app for at least 3 sessions
        // 2. Attempted at least 2 premium features
        // 3. Haven't dismissed prompts too many times
        return sessionCount >= 3 && 
               attemptedFeatures.count >= 2 && 
               promptDismissCount < maxDismissalsBeforeReducing
    }
    
    /// Get the most valuable feature to highlight based on user behavior
    public var highlightFeature: PremiumFeature {
        // Prioritize recently attempted features
        if let lastFeature = lastAttemptedFeature {
            return lastFeature
        }
        // Default to whale tracking (popular feature)
        return .whaleTracking
    }
}

// MARK: - Paywall Benefit Model

/// Represents a benefit shown in upgrade prompts
public struct PaywallBenefit: Identifiable {
    public let id = UUID()
    public let icon: String
    public let title: String
    public let description: String
}

// MARK: - Paywall Trigger Context

/// Context for triggering a paywall (for analytics/personalization)
public enum PaywallTriggerContext: String {
    case periodicPrompt = "periodic_prompt"
    case featureGate = "feature_gate"
    case softPaywall = "soft_paywall"
    case directNavigation = "direct_navigation"
}

// MARK: - View Modifier for Paywall Tracking

/// View modifier that tracks feature access attempts
public struct PaywallTrackingModifier: ViewModifier {
    let feature: PremiumFeature
    @ObservedObject private var paywallManager = PaywallManager.shared
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    
    public func body(content: Content) -> some View {
        content
            .onAppear {
                if !subscriptionManager.hasAccess(to: feature) {
                    paywallManager.trackFeatureAttempt(feature)
                }
            }
    }
}

public extension View {
    /// Track when a user views a gated feature area
    func trackPaywallView(for feature: PremiumFeature) -> some View {
        modifier(PaywallTrackingModifier(feature: feature))
    }
}
