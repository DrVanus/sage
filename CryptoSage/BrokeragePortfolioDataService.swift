//
//  BrokeragePortfolioDataService.swift
//  CryptoSage
//
//  Created by CryptoSage on 1/19/26.
//  Service for syncing portfolio holdings from connected brokerages via Plaid.
//

import Foundation
import Combine
import SwiftUI

/// Service that manages brokerage-synced stock and ETF holdings from Plaid
final class BrokeragePortfolioDataService: PortfolioDataService {
    
    // MARK: - Singleton
    
    static let shared = BrokeragePortfolioDataService()
    
    // MARK: - Publishers
    
    private let holdingsSubject = CurrentValueSubject<[Holding], Never>([])
    private let transactionsSubject = CurrentValueSubject<[Transaction], Never>([])
    
    var holdingsPublisher: AnyPublisher<[Holding], Never> {
        holdingsSubject.eraseToAnyPublisher()
    }
    
    var transactionsPublisher: AnyPublisher<[Transaction], Never> {
        transactionsSubject.eraseToAnyPublisher()
    }
    
    // MARK: - State
    
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshTime: Date?
    @Published private(set) var lastError: Error?
    
    /// All stock holdings from connected brokerages
    private(set) var stockHoldings: [Holding] = []
    
    /// Connected Plaid accounts
    private(set) var connectedAccounts: [PlaidAccount] = []
    
    private let refreshCooldown: TimeInterval = 60 // 1 minute cooldown for brokerage sync
    
    // User preferences
    @AppStorage("showStocksInPortfolio") private var showStocksEnabled: Bool = false
    
    // Persistence
    private let holdingsFileURL: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    
    // MARK: - Initialization
    
    private init() {
        // SAFETY FIX: Use safe directory accessor instead of force unwrap
        let docs = FileManager.documentsDirectory
        self.holdingsFileURL = docs.appendingPathComponent("brokerage_holdings.json")
        
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        
        // Load cached holdings
        loadCachedHoldings()
        
        // Load connected Plaid accounts
        Task {
            await loadConnectedAccounts()
        }
    }
    
    // MARK: - Account Management
    
    /// Load all connected Plaid accounts
    func loadConnectedAccounts() async {
        do {
            connectedAccounts = try await PlaidService.shared.loadAccounts()
        } catch {
            #if DEBUG
            print("⚠️ BrokeragePortfolioDataService: Failed to load accounts: \(error)")
            #endif
            connectedAccounts = []
        }
    }
    
    /// Check if any brokerage accounts are connected
    var hasConnectedAccounts: Bool {
        !connectedAccounts.isEmpty
    }
    
    // MARK: - Feature Toggle Cleanup
    
    /// Call when the stocks feature is disabled to clean up state
    /// Note: This does NOT delete connected Plaid accounts - just clears the local holdings display
    func onStocksFeatureDisabled() {
        // Clear displayed holdings (keeps them cached for re-enable)
        stockHoldings = []
        holdingsSubject.send([])
        
        // Stop any pending refreshes
        isRefreshing = false
        lastRefreshTime = nil
        lastError = nil
        
        #if DEBUG
        print("📴 BrokeragePortfolioDataService: Stocks feature disabled, cleared local state")
        #endif
    }
    
    /// Call when the stocks feature is enabled to restore state
    func onStocksFeatureEnabled() async {
        // Reload cached holdings
        loadCachedHoldings()
        
        // Sync with connected accounts
        await syncAllAccounts()
        
        #if DEBUG
        print("📱 BrokeragePortfolioDataService: Stocks feature enabled, syncing...")
        #endif
    }
    
    // MARK: - Holdings Sync
    
    /// Sync holdings from all connected brokerage accounts
    func syncAllAccounts() async {
        guard showStocksEnabled else {
            // Stocks are disabled, clear any existing stock holdings
            await MainActor.run {
                stockHoldings = []
                holdingsSubject.send([])
            }
            return
        }
        
        guard !isRefreshing else { return }
        
        // Check cooldown
        if let lastRefresh = lastRefreshTime,
           Date().timeIntervalSince(lastRefresh) < refreshCooldown {
            return
        }
        
        await MainActor.run {
            isRefreshing = true
            lastError = nil
        }
        
        defer {
            Task { @MainActor in
                isRefreshing = false
            }
        }
        
        // Refresh account list
        await loadConnectedAccounts()
        
        guard !connectedAccounts.isEmpty else {
            await MainActor.run {
                stockHoldings = []
                holdingsSubject.send([])
                lastRefreshTime = Date()
            }
            return
        }
        
        var allHoldings: [Holding] = []
        var syncErrors: [Error] = []
        
        for account in connectedAccounts {
            do {
                let plaidHoldings = try await PlaidService.shared.fetchHoldings(for: account)
                
                // Convert to portfolio holdings
                let portfolioHoldings = plaidHoldings.map { plaidHolding -> Holding in
                    plaidHolding.toHolding(source: "plaid:\(account.institutionName)")
                }
                
                // Merge into all holdings, aggregating by ticker
                for holding in portfolioHoldings {
                    if let existingIndex = allHoldings.firstIndex(where: { $0.ticker == holding.ticker }) {
                        // Aggregate quantity for same ticker from different accounts
                        allHoldings[existingIndex].quantity += holding.quantity
                    } else {
                        allHoldings.append(holding)
                    }
                }
                
                // Update account's last sync time
                var updatedAccount = account
                updatedAccount.lastSyncedAt = Date()
                try await PlaidService.shared.saveAccount(updatedAccount)
                
            } catch {
                syncErrors.append(error)
                #if DEBUG
                print("❌ BrokeragePortfolioDataService: Failed to sync \(account.institutionName): \(error)")
                #endif
            }
        }
        
        // Sort by value (descending)
        allHoldings.sort { $0.currentValue > $1.currentValue }
        
        // Update live prices for stock holdings
        await updateStockPrices(for: &allHoldings)
        
        // Capture immutable copies to avoid "captured var in concurrently-executing code"
        let finalHoldings = allHoldings
        let firstSyncError = syncErrors.first
        
        await MainActor.run {
            stockHoldings = finalHoldings
            holdingsSubject.send(finalHoldings)
            lastRefreshTime = Date()
            
            if let firstSyncError = firstSyncError {
                lastError = firstSyncError
            }
        }
        
        // Cache holdings
        saveCachedHoldings(finalHoldings)
        
        // Start tracking these stocks for live updates
        let tickers = finalHoldings.compactMap { $0.ticker }
        if !tickers.isEmpty {
            await MainActor.run {
                LiveStockPriceManager.shared.setTickers(tickers, source: "portfolio")
            }
        }
    }
    
    /// Update stock prices using StockPriceService
    private func updateStockPrices(for holdings: inout [Holding]) async {
        let tickers = holdings.compactMap { $0.ticker }
        guard !tickers.isEmpty else { return }
        
        let quotes = await StockPriceService.shared.fetchQuotes(tickers: tickers)
        
        for i in holdings.indices {
            if let ticker = holdings[i].ticker,
               let quote = quotes[ticker.uppercased()] {
                holdings[i].currentPrice = quote.regularMarketPrice
                // Calculate change: prefer API value, fallback to previousClose calculation
                holdings[i].dailyChange = quote.regularMarketChangePercent ?? {
                    if let prevClose = quote.regularMarketPreviousClose, prevClose > 0 {
                        return ((quote.regularMarketPrice - prevClose) / prevClose) * 100
                    }
                    return 0
                }()
            }
        }
    }
    
    /// Force refresh ignoring cooldown
    func forceSync() async {
        await MainActor.run {
            lastRefreshTime = nil
        }
        await syncAllAccounts()
    }
    
    // MARK: - Manual Holdings Management
    
    /// Add a manually-entered stock holding (not from brokerage sync)
    func addManualHolding(_ holding: Holding) {
        var updated = stockHoldings
        
        // Check if we already have this ticker
        if let existingIndex = updated.firstIndex(where: { $0.ticker == holding.ticker }) {
            // Merge quantities
            updated[existingIndex].quantity += holding.quantity
        } else {
            updated.append(holding)
        }
        
        updated.sort { $0.currentValue > $1.currentValue }
        
        stockHoldings = updated
        holdingsSubject.send(updated)
        saveCachedHoldings(updated)
        
        // Start tracking for live updates
        if let ticker = holding.ticker {
            Task { @MainActor in
                LiveStockPriceManager.shared.addTickers([ticker], source: "portfolio")
            }
        }
    }
    
    /// Remove a stock holding
    func removeHolding(_ holding: Holding) {
        stockHoldings.removeAll { $0.id == holding.id }
        holdingsSubject.send(stockHoldings)
        saveCachedHoldings(stockHoldings)
        
        // Stop tracking if no other holdings have this ticker
        if let ticker = holding.ticker,
           !stockHoldings.contains(where: { $0.ticker == ticker }) {
            Task { @MainActor in
                LiveStockPriceManager.shared.removeTickers([ticker], source: "portfolio")
            }
        }
    }
    
    /// Update a stock holding
    func updateHolding(_ holding: Holding) {
        if let index = stockHoldings.firstIndex(where: { $0.id == holding.id }) {
            stockHoldings[index] = holding
            holdingsSubject.send(stockHoldings)
            saveCachedHoldings(stockHoldings)
        }
    }
    
    // MARK: - Transaction Methods (Protocol Conformance)
    
    func addTransaction(_ tx: Transaction) {
        // Brokerage service doesn't track transactions directly
        // Transactions come from brokerage sync
    }
    
    func updateTransaction(_ old: Transaction, with new: Transaction) {
        // Brokerage service doesn't track transactions directly
    }
    
    func deleteTransaction(_ tx: Transaction) {
        // Brokerage service doesn't track transactions directly
    }
    
    // MARK: - Persistence
    
    private func loadCachedHoldings() {
        guard FileManager.default.fileExists(atPath: holdingsFileURL.path) else {
            return
        }
        
        do {
            let data = try Data(contentsOf: holdingsFileURL)
            let cached = try decoder.decode([Holding].self, from: data)
            stockHoldings = cached
            holdingsSubject.send(cached)
            #if DEBUG
            print("📂 BrokeragePortfolioDataService: Loaded \(cached.count) cached stock holdings")
            #endif
        } catch {
            #if DEBUG
            print("⚠️ BrokeragePortfolioDataService: Failed to load cached holdings: \(error)")
            #endif
        }
    }
    
    private func saveCachedHoldings(_ holdings: [Holding]) {
        do {
            let data = try encoder.encode(holdings)
            // SECURITY: .completeFileProtection ensures brokerage holdings are encrypted
            // by iOS and inaccessible when the device is locked.
            try data.write(to: holdingsFileURL, options: [.atomic, .completeFileProtection])
        } catch {
            #if DEBUG
            print("⚠️ BrokeragePortfolioDataService: Failed to cache holdings: \(error)")
            #endif
        }
    }
}

// MARK: - Live Price Updates Integration

extension BrokeragePortfolioDataService {
    
    /// Call this from PortfolioViewModel when LiveStockPriceManager emits new quotes
    func updateWithLiveQuotes(_ quotes: [String: StockQuote]) {
        guard !quotes.isEmpty else { return }
        
        var didUpdate = false
        var updated = stockHoldings
        
        for i in updated.indices {
            guard let ticker = updated[i].ticker else { continue }
            guard let quote = quotes[ticker.uppercased()] else { continue }
            
            updated[i].currentPrice = quote.regularMarketPrice
            // Calculate change: prefer API value, fallback to previousClose calculation
            updated[i].dailyChange = quote.regularMarketChangePercent ?? {
                if let prevClose = quote.regularMarketPreviousClose, prevClose > 0 {
                    return ((quote.regularMarketPrice - prevClose) / prevClose) * 100
                }
                return 0
            }()
            didUpdate = true
        }
        
        if didUpdate {
            stockHoldings = updated
            holdingsSubject.send(updated)
        }
    }
    
    /// Get all tickers currently in the brokerage portfolio
    var trackedTickers: [String] {
        stockHoldings.compactMap { $0.ticker }
    }
}

// MARK: - Holdings Summary

extension BrokeragePortfolioDataService {
    
    /// Total value of all stock holdings
    var totalStockValue: Double {
        stockHoldings.reduce(0) { $0 + $1.currentValue }
    }
    
    /// Number of unique positions
    var positionCount: Int {
        stockHoldings.count
    }
    
    /// Total unrealized P/L across all stock holdings
    var totalUnrealizedPL: Double {
        stockHoldings.reduce(0) { result, holding in
            let costBasisTotal = holding.costBasis * holding.quantity
            return result + (holding.currentValue - costBasisTotal)
        }
    }
    
    /// Stocks grouped by asset type
    var holdingsByType: [AssetType: [Holding]] {
        Dictionary(grouping: stockHoldings) { $0.assetType }
    }
}
