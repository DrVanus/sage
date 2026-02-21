//
//  DemoModeManager.swift
//  CryptoSage
//
//  Unified demo mode manager that controls all mock/demo data across the app.
//

import SwiftUI
import Combine

/// Centralized manager for demo mode state across the entire app.
/// When demo mode is ON: Shows sample portfolio data, mock trading balances, and fake connected exchanges.
/// When demo mode is OFF: Shows only real data from connected exchanges, or empty states if nothing is connected.
///
/// DATA CONSISTENCY: Demo mode ONLY affects:
/// - Portfolio view (shows sample holdings)
/// - Trading view (shows mock balances)
/// - Connected accounts (shows fake exchanges)
///
/// Demo mode does NOT affect (and should NEVER affect):
/// - Market heat map data (always shows real Firestore/API data)
/// - Market prices (always real)
/// - News feed (always real)
/// - AI insights (always real)
///
/// This ensures consistent market data across all users regardless of demo mode setting.
@MainActor
final class DemoModeManager: ObservableObject {
    static let shared = DemoModeManager()
    
    // MARK: - Legacy Keys (for migration)
    private static let legacyHomeKey = "demoModeEnabled"
    private static let legacyPortfolioKey = "portfolio_demo_mode"
    private static let legacyTradingKey = "trading_demo_mode"
    nonisolated private static let unifiedKey = "unified_demo_mode"
    private static let migrationCompleteKey = "demo_mode_migration_v1_complete"
    
    // MARK: - Published State
    /// The single source of truth for demo mode across the entire app.
    /// When true, mock data is shown. When false, only real data or empty states are shown.
    @Published var isDemoMode: Bool {
        didSet {
            UserDefaults.standard.set(isDemoMode, forKey: Self.unifiedKey)
            // Also sync to legacy keys for any components not yet migrated
            syncToLegacyKeys()
            // Defer to avoid "Modifying state during view update" warnings
            Task { self.objectWillChange.send() }
        }
    }
    
    // MARK: - Initialization
    private init() {
        // First check if migration has been done
        let migrationComplete = UserDefaults.standard.bool(forKey: Self.migrationCompleteKey)
        
        if migrationComplete {
            // Use the unified key directly
            // DATA CONSISTENCY: Default to false for new users to avoid confusion
            // Users can enable demo mode manually if they want to see sample portfolio data
            self.isDemoMode = UserDefaults.standard.object(forKey: Self.unifiedKey) as? Bool ?? false
        } else {
            // Perform migration from legacy keys
            self.isDemoMode = false // DATA CONSISTENCY: Default to false
            migrateFromLegacyKeys()
        }
        
        // Schedule a check after ConnectedAccountsManager is initialized
        // This ensures demo mode is disabled if user has connected accounts
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay for managers to init
            self.validateDemoModeState()
        }
    }
    
    /// Validates that demo mode state is consistent with connected accounts
    /// Called after app initialization to catch any edge cases
    func validateDemoModeState() {
        if isDemoMode && hasConnectedAccounts {
            print("[DemoModeManager] Disabling demo mode - user has connected accounts")
            disableDemoMode()
        }
    }
    
    // MARK: - Migration
    /// Migrates from the three legacy demo mode keys to the unified key.
    /// DATA CONSISTENCY: Changed to default to false for cleaner initial state.
    /// Demo mode is opt-in, not opt-out.
    private func migrateFromLegacyKeys() {
        let defaults = UserDefaults.standard
        
        // Read legacy values (default to false - demo mode is now opt-in)
        let homeDemo = defaults.object(forKey: Self.legacyHomeKey) as? Bool ?? false
        let portfolioDemo = defaults.object(forKey: Self.legacyPortfolioKey) as? Bool ?? false
        let tradingDemo = defaults.object(forKey: Self.legacyTradingKey) as? Bool ?? false
        
        // Only enable demo mode if user explicitly had it enabled before
        // For new users or mixed states, default to off
        _ = homeDemo || portfolioDemo || tradingDemo
        
        // Check if any key was ever explicitly set to true
        let homeWasExplicitlyTrue = defaults.object(forKey: Self.legacyHomeKey) as? Bool == true
        let portfolioWasExplicitlyTrue = defaults.object(forKey: Self.legacyPortfolioKey) as? Bool == true
        let tradingWasExplicitlyTrue = defaults.object(forKey: Self.legacyTradingKey) as? Bool == true
        
        if homeWasExplicitlyTrue || portfolioWasExplicitlyTrue || tradingWasExplicitlyTrue {
            // User explicitly enabled demo mode before - keep it on
            isDemoMode = true
        } else {
            // DATA CONSISTENCY: Default to demo mode off for cleaner state
            // New users or those who never enabled demo mode should see real (empty) data
            isDemoMode = false
        }
        
        // Sync to all keys for consistency
        syncToLegacyKeys()
        
        // Mark migration as complete
        defaults.set(true, forKey: Self.migrationCompleteKey)
    }
    
    /// Syncs the unified demo mode state to legacy keys for backward compatibility
    /// during the transition period. This ensures components not yet updated still work.
    private func syncToLegacyKeys() {
        let defaults = UserDefaults.standard
        defaults.set(isDemoMode, forKey: Self.legacyHomeKey)
        defaults.set(isDemoMode, forKey: Self.legacyPortfolioKey)
        defaults.set(isDemoMode, forKey: Self.legacyTradingKey)
    }
    
    // MARK: - Public API
    
    /// Enables demo mode and seeds demo data across all components.
    /// Note: Demo mode cannot be enabled if user has connected accounts.
    func enableDemoMode() {
        // Don't allow demo mode if user has real data
        guard !hasConnectedAccounts else {
            print("[DemoModeManager] Cannot enable demo mode - user has connected accounts")
            return
        }
        isDemoMode = true
    }
    
    /// Disables demo mode. All views should show empty states or real data only.
    func disableDemoMode() {
        isDemoMode = false
    }
    
    /// Toggles demo mode.
    func toggle() {
        if isDemoMode {
            disableDemoMode()
        } else {
            enableDemoMode()
        }
    }
    
    /// Called when user connects a portfolio/exchange. Auto-disables demo mode.
    func onPortfolioConnected() {
        if isDemoMode {
            print("[DemoModeManager] Auto-disabling demo mode - user connected portfolio")
            disableDemoMode()
        }
    }
    
    /// Whether the user has connected accounts (real data available)
    var hasConnectedAccounts: Bool {
        !ConnectedAccountsManager.shared.accounts.isEmpty
    }
    
    /// Whether demo mode toggle should be available
    /// Demo mode is only useful for users without connected accounts
    var canEnableDemoMode: Bool {
        !hasConnectedAccounts && !PaperTradingManager.isEnabled
    }
    
    /// Resets migration flag (for testing purposes only).
    func resetMigration() {
        UserDefaults.standard.removeObject(forKey: Self.migrationCompleteKey)
    }
    
    // MARK: - Non-Isolated Access
    
    /// Thread-safe check for demo mode status that can be called from any context.
    /// Use this when you need to check demo mode from a non-MainActor context.
    /// For MainActor contexts (Views, ViewModels), prefer using `DemoModeManager.shared.isDemoMode`.
    nonisolated static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: unifiedKey)
    }
}

// MARK: - Convenience Extension for Views
extension View {
    /// Observes demo mode changes and triggers the given action.
    func onDemoModeChange(perform action: @escaping (Bool) -> Void) -> some View {
        self.onReceive(DemoModeManager.shared.$isDemoMode) { newValue in
            // Defer to avoid "Modifying state during view update"
            Task { @MainActor in
                action(newValue)
            }
        }
    }
}
