//
//  CoinbasePortfolioSyncService.swift
//  CryptoSage
//
//  Service for syncing Coinbase portfolio into CryptoSage portfolio
//  Automatically polls Coinbase balances and updates LivePortfolioDataService
//

import Foundation
import Combine

/// Service for syncing Coinbase portfolio into CryptoSage portfolio
public actor CoinbasePortfolioSyncService {
    public static let shared = CoinbasePortfolioSyncService()
    private init() {}

    private var syncTimer: Task<Void, Never>?
    private var isPolling = false
    private var lastSyncTime: Date?

    /// Start automatic portfolio sync (every 2 minutes)
    public func startPolling() async {
        guard !isPolling else { return }
        isPolling = true

        syncTimer = Task {
            while !Task.isCancelled {
                await syncPortfolio()
                try? await Task.sleep(nanoseconds: 120_000_000_000) // 2 minutes
            }
        }
    }

    /// Stop automatic sync
    public func stopPolling() async {
        isPolling = false
        syncTimer?.cancel()
    }

    /// Sync Coinbase balances into LivePortfolioDataService
    public func syncPortfolio() async {
        do {
            let accounts = try await CoinbaseAdvancedTradeService.shared.fetchAccounts()

            // Convert Coinbase accounts to Holdings
            var holdings: [Holding] = []

            for account in accounts where account.totalBalance > 0 {
                // Filter out dust (tiny balances)
                if account.totalBalance < 0.00001 && account.currency != "USD" && account.currency != "USDC" {
                    continue
                }

                // Get current price from LivePriceManager
                let currentPrice = await MainActor.run {
                    MarketViewModel.shared.bestPrice(forSymbol: account.currency) ?? 0
                }

                let holding = Holding(
                    id: UUID(),
                    coinName: account.name,
                    coinSymbol: account.currency,
                    quantity: account.totalBalance,
                    currentPrice: currentPrice,
                    costBasis: 0, // Can't determine from balance alone
                    imageUrl: nil,
                    isFavorite: false,
                    dailyChange: 0,
                    purchaseDate: Date()
                )

                holdings.append(holding)
            }

            lastSyncTime = Date()
            print("✅ Synced \(holdings.count) Coinbase holdings")

            // Update LivePortfolioDataService
            await MainActor.run {
                // Store holdings in a way that LivePortfolioDataService can access
                NotificationCenter.default.post(
                    name: NSNotification.Name("CoinbasePortfolioSynced"),
                    object: nil,
                    userInfo: ["holdings": holdings]
                )
            }

        } catch {
            print("❌ Portfolio sync failed: \(error.localizedDescription)")
        }
    }

    /// Get last sync time
    public func getLastSyncTime() -> Date? {
        lastSyncTime
    }
}
