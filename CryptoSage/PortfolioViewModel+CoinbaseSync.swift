//
//  PortfolioViewModel+CoinbaseSync.swift
//  CryptoSage
//
//  Extension to integrate Coinbase portfolio sync with PortfolioViewModel
//

import Foundation
import Combine

extension PortfolioViewModel {

    // MARK: - Coinbase Integration

    /// Sync Coinbase portfolio into the main portfolio
    public func syncCoinbasePortfolio() async {
        isRefreshing = true

        // Trigger Coinbase sync
        await CoinbasePortfolioSyncService.shared.syncPortfolio()

        // Reload holdings
        await refreshHoldings()

        #if DEBUG
        print("✅ Coinbase portfolio synced successfully")
        #endif

        isRefreshing = false
    }

    /// Start automatic Coinbase sync on app launch
    public func startCoinbaseAutoSync() async {
        // Check if Coinbase credentials exist
        guard TradingCredentialsManager.shared.hasCredentials(for: .coinbase) else {
            #if DEBUG
            print("⚠️ No Coinbase credentials found. Skipping auto-sync.")
            #endif
            return
        }

        // Start polling service
        await CoinbasePortfolioSyncService.shared.startPolling()

        // Setup notification listener for sync updates
        setupCoinbaseSyncListener()

        #if DEBUG
        print("✅ Coinbase auto-sync enabled")
        #endif
    }

    /// Stop automatic Coinbase sync
    public func stopCoinbaseAutoSync() async {
        await CoinbasePortfolioSyncService.shared.stopPolling()
        #if DEBUG
        print("🔌 Coinbase auto-sync stopped")
        #endif
    }

    // MARK: - Private Helpers

    private func setupCoinbaseSyncListener() {
        // Listen for portfolio sync notifications
        NotificationCenter.default.publisher(for: NSNotification.Name("CoinbasePortfolioSynced"))
            .sink { [weak self] notification in
                // Portfolio was synced, trigger refresh
                Task { @MainActor in
                    await self?.refreshHoldings()
                }
            }
            .store(in: &cancellables)
    }

    /// Get Coinbase trading status
    public var coinbaseTradingEnabled: Bool {
        TradingCredentialsManager.shared.hasCredentials(for: .coinbase)
    }

    /// Get last Coinbase sync time
    public func getLastCoinbaseSyncTime() async -> Date? {
        await CoinbasePortfolioSyncService.shared.getLastSyncTime()
    }
}

// MARK: - LivePortfolioDataService Extension

extension LivePortfolioDataService {

    /// Update holdings from Coinbase sync
    public func updateCoinbaseHoldings(_ holdings: [Holding]) {
        // Merge with existing holdings or replace based on strategy
        holdingsSubject.send(holdings)
    }

    /// Setup Coinbase sync integration
    public func setupCoinbaseIntegration() {
        // Listen for Coinbase portfolio sync notifications
        NotificationCenter.default.publisher(for: NSNotification.Name("CoinbasePortfolioSynced"))
            .compactMap { notification in
                notification.userInfo?["holdings"] as? [Holding]
            }
            .sink { [weak self] holdings in
                self?.updateCoinbaseHoldings(holdings)
            }
            .store(in: &cancellables)
    }
}
