//
//  AppConfig.swift
//  CryptoSage
//
//  Central configuration for app-wide feature flags.
//  Controls major features that may have legal, regulatory, or App Store compliance implications.
//

import Foundation

/// App-wide feature configuration
///
/// IMPORTANT: These flags control major features that may have
/// legal, regulatory, or App Store compliance implications.
/// Consult legal counsel before enabling trading features.
///
/// NOTE: Properties that need to be accessed from both @MainActor and nonisolated
/// contexts read directly from UserDefaults (which is thread-safe) rather than
/// going through `SubscriptionManager.shared` (which is @MainActor-isolated).
/// This avoids cross-actor isolation warnings while keeping all callers working.
public enum AppConfig {

    // MARK: - UserDefaults Keys (mirror SubscriptionManager's keys)

    private static let developerModeKey = "Subscription.DeveloperMode"
    private static let developerLiveTradingKey = "Subscription.DeveloperLiveTrading"

    // MARK: - Trading Features

    /// Master switch for live trading functionality
    ///
    /// When `false`:
    /// - Real trade execution is blocked at multiple levels
    /// - Paper trading remains fully functional
    /// - Trading UI shows paper trading mode
    /// - Bot creation works in paper-only mode
    /// - Portfolio tracking via exchanges still works (read-only)
    ///
    /// When `true`:
    /// - Pro+ users can execute real trades via connected exchanges
    /// - Live trading bots enabled for Elite+ users
    /// - Full exchange integration active
    ///
    /// **Legal Considerations for Enabling:**
    /// - Money transmitter licenses may be required (49 US states)
    /// - Apple App Store requires proof of exchange licensing
    /// - Terms of service updates needed
    /// - Risk disclosure agreements required
    /// - SEC/regulatory compliance verification
    ///
    /// **Developer Mode:**
    /// Live trading requires BOTH:
    /// 1. Developer Mode to be active (secret code entered)
    /// 2. Developer Live Trading toggle to be ON (explicit opt-in)
    ///
    /// This two-step safety allows the developer to:
    /// - Test different subscription tiers WITHOUT risking real trades
    /// - Explicitly enable live trading only when they want to trade
    public static var liveTradingEnabled: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: developerModeKey) &&
               UserDefaults.standard.bool(forKey: developerLiveTradingKey)
        #else
        return false // Developer features are disabled in release builds
        #endif
    }

    /// Convenience: whether developer mode is currently active.
    /// Used by SageTradingService, SageAlgorithmEngine, and other subsystems
    /// to gate internal/experimental features.
    public static var isDeveloperMode: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: developerModeKey)
        #else
        return false // Developer mode is always off in release builds
        #endif
    }

    /// Error message shown when live trading is attempted but disabled
    public static let liveTradingDisabledMessage: String =
        "Live trading is currently unavailable. Practice with paper trading instead!"

    /// Whether live trading bots are enabled (Elite feature)
    /// Follows the main liveTradingEnabled flag for consistency
    public static var liveTradingBotsEnabled: Bool {
        return liveTradingEnabled
    }

    /// Whether AI can execute real trades (vs paper trades)
    /// Disabled when live trading is off
    public static var aiLiveTradingEnabled: Bool {
        return liveTradingEnabled
    }

    // MARK: - Feature Descriptions

    /// Returns the appropriate description for trading features based on current config
    public static var tradingFeatureDescription: String {
        if liveTradingEnabled {
            return "Execute trades via exchanges"
        } else {
            return "Paper Trading ($100k virtual)"
        }
    }

    /// Returns the appropriate upgrade message for trade execution feature
    public static var tradeExecutionUpgradeMessage: String {
        if liveTradingEnabled {
            return "Upgrade to Pro to execute trades directly through your connected exchanges."
        } else {
            return "Practice trading with $100,000 in virtual funds with Paper Trading!"
        }
    }
}
