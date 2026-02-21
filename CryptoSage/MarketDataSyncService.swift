//
//  MarketDataSyncService.swift
//  CryptoSage
//
//  Orchestrates background data sync from multiple sources.
//  Coordinates CoinGecko, Binance, and Pump.fun data refreshes.
//

import Foundation
import Combine

/// Orchestrates market data synchronization from multiple sources
@MainActor
final class MarketDataSyncService: ObservableObject {
    
    static let shared = MarketDataSyncService()
    
    // MARK: - Published Properties
    
    /// Combined list of all coins from all sources
    @Published private(set) var allMarketCoins: [MarketCoin] = []
    
    /// Sync status for UI display
    @Published private(set) var syncStatus: SyncStatus = .idle
    
    /// Last successful sync time
    @Published private(set) var lastSyncAt: Date?
    
    /// Total coin count from all sources
    @Published private(set) var totalCoinCount: Int = 0
    
    // MARK: - Publishers
    
    /// Publisher for when new coins are detected from any source
    let newCoinsDetectedPublisher = PassthroughSubject<[MarketCoin], Never>()
    
    /// Publisher for sync completion
    let syncCompletedPublisher = PassthroughSubject<SyncResult, Never>()
    
    // MARK: - Private Properties
    
    private var syncTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    /// Sync intervals for different data sources (increased to reduce API load)
    private let primarySyncInterval: TimeInterval = 10 * 60 // 10 minutes for CoinGecko (was 5 min)
    private let secondarySyncInterval: TimeInterval = 5 * 60 // 5 minutes for Binance (was 2 min)
    private let pumpFunSyncInterval: TimeInterval = 3 * 60 // 3 minutes for Pump.fun (was 1 min)
    
    /// Track last sync times per source
    private var lastCoinGeckoSyncAt: Date = .distantPast
    private var lastBinanceSyncAt: Date = .distantPast
    private var lastPumpFunSyncAt: Date = .distantPast
    private var lastCategorySyncAt: Date = .distantPast
    /// Startup coalescing window: avoid duplicate CoinGecko pulls while app-level loaders are still active.
    private var startupCoinGeckoSuppressUntil: Date = Date().addingTimeInterval(120)
    
    /// Prevent concurrent syncs
    private var isSyncing = false
    
    // MARK: - Types
    
    enum SyncStatus: Equatable {
        case idle
        case syncing(source: String)
        case completed(coinCount: Int)
        case error(message: String)
    }
    
    struct SyncResult {
        let totalCoins: Int
        let newCoins: Int
        let sources: [String]
        let duration: TimeInterval
    }
    
    // MARK: - Initialization
    
    private init() {
        setupSubscriptions()
    }
    
    private func setupSubscriptions() {
        // Listen for new coin alerts from NewlyListedCoinsService
        NewlyListedCoinsService.shared.newCoinAlertPublisher
            .sink { [weak self] newCoins in
                self?.newCoinsDetectedPublisher.send(newCoins)
            }
            .store(in: &cancellables)
        
        // Listen for new tokens from PumpFunService
        PumpFunService.shared.newTokenPublisher
            .sink { [weak self] token in
                Task { @MainActor [weak self] in
                    let solPrice = await self?.getSolPrice() ?? 200
                    let marketCoin = token.toMarketCoin(solPrice: solPrice)
                    self?.newCoinsDetectedPublisher.send([marketCoin])
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    /// Start periodic background sync
    func startPeriodicSync() {
        guard !CryptoSageAIApp.isEmergencyStopActive() else {
            print("[MarketDataSyncService] Skipping periodic sync start - emergency stop active")
            return
        }
        stopPeriodicSync() // Stop any existing timer
        
        // Initial sync: prefer incremental to avoid heavy duplicate CoinGecko fetch right at launch.
        Task {
            await rebuildCombinedList()
            await performIncrementalSync()
        }
        
        // Schedule periodic sync
        syncTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.performIncrementalSync()
            }
        }
        
        print("[MarketDataSyncService] Started periodic sync")
    }
    
    /// Stop periodic sync
    func stopPeriodicSync() {
        syncTimer?.invalidate()
        syncTimer = nil
    }
    
    /// Perform a full sync from all sources
    func performFullSync() async {
        guard !CryptoSageAIApp.isEmergencyStopActive() else { return }
        guard !isSyncing else { return }
        
        // PERFORMANCE: Check global request coordinator to prevent startup thundering herd
        guard APIRequestCoordinator.shared.canMakeRequest(for: .sync) else {
            return
        }
        APIRequestCoordinator.shared.recordRequest(for: .sync)
        
        isSyncing = true
        
        let startTime = Date()
        var sources: [String] = []
        let previousCount = allMarketCoins.count
        
        syncStatus = .syncing(source: "All sources")
        
        // 1. Fetch from CoinGecko (primary source)
        syncStatus = .syncing(source: "CoinGecko")
        do {
            let geckoCoins = try await CryptoAPIService.shared.fetchCoinMarkets()
            if !geckoCoins.isEmpty {
                sources.append("CoinGecko")
                lastCoinGeckoSyncAt = Date()
                
                // Update NewlyListedCoinsService
                NewlyListedCoinsService.shared.updateNewlyListedCoins(from: geckoCoins)
            }
        } catch {
            print("[MarketDataSyncService] CoinGecko sync failed: \(error)")
        }
        
        // Small delay to avoid rate limits
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        // 2. Fetch category-specific coins (meme, AI, gaming)
        syncStatus = .syncing(source: "Categories")
        await NewlyListedCoinsService.shared.fetchTrendingMemeCoins()
        lastCategorySyncAt = Date()
        sources.append("Categories")
        
        // 3. Fetch from Pump.fun
        syncStatus = .syncing(source: "Pump.fun")
        await PumpFunService.shared.refreshAll()
        lastPumpFunSyncAt = Date()
        sources.append("Pump.fun")
        
        // 4. Combine all sources
        await rebuildCombinedList()
        
        let duration = Date().timeIntervalSince(startTime)
        let newCount = max(0, allMarketCoins.count - previousCount)
        
        let result = SyncResult(
            totalCoins: allMarketCoins.count,
            newCoins: newCount,
            sources: sources,
            duration: duration
        )
        
        syncStatus = .completed(coinCount: allMarketCoins.count)
        lastSyncAt = Date()
        totalCoinCount = allMarketCoins.count
        isSyncing = false
        
        syncCompletedPublisher.send(result)
        print("[MarketDataSyncService] Full sync completed: \(allMarketCoins.count) coins from \(sources.joined(separator: ", "))")
    }
    
    /// Perform incremental sync (only stale sources)
    func performIncrementalSync() async {
        guard !CryptoSageAIApp.isEmergencyStopActive() else { return }
        guard !isSyncing else { return }
        
        // PERFORMANCE FIX v17: Skip sync during scroll to prevent main thread work
        // rebuildCombinedList() iterates through all coins on @MainActor
        if ScrollStateManager.shared.shouldBlockHeavyOperation() {
            return
        }
        
        // Skip sync when in degraded mode to reduce CPU churn and improve UI performance
        if APIHealthManager.shared.isDegradedMode {
            return
        }
        
        let now = Date()
        
        // Check which sources need refresh
        var needsCoinGecko = now.timeIntervalSince(lastCoinGeckoSyncAt) > primarySyncInterval
        let needsPumpFun = now.timeIntervalSince(lastPumpFunSyncAt) > pumpFunSyncInterval
        let needsCategories = now.timeIntervalSince(lastCategorySyncAt) > primarySyncInterval
        if now < startupCoinGeckoSuppressUntil, !MarketViewModel.shared.allCoins.isEmpty {
            needsCoinGecko = false
        }
        
        if !needsCoinGecko && !needsPumpFun && !needsCategories {
            return // Nothing to sync
        }
        
        isSyncing = true
        var sources: [String] = []
        
        // Sync stale sources
        if needsPumpFun {
            syncStatus = .syncing(source: "Pump.fun")
            await PumpFunService.shared.fetchRecentTokens()
            lastPumpFunSyncAt = Date()
            sources.append("Pump.fun")
        }
        
        if needsCategories {
            syncStatus = .syncing(source: "Meme coins")
            await NewlyListedCoinsService.shared.fetchTrendingMemeCoins()
            lastCategorySyncAt = Date()
            sources.append("Categories")
        }
        
        if needsCoinGecko {
            syncStatus = .syncing(source: "CoinGecko")
            do {
                let geckoCoins = try await CryptoAPIService.shared.fetchCoinMarkets()
                if !geckoCoins.isEmpty {
                    NewlyListedCoinsService.shared.updateNewlyListedCoins(from: geckoCoins)
                    lastCoinGeckoSyncAt = Date()
                    sources.append("CoinGecko")
                }
            } catch {
                print("[MarketDataSyncService] Incremental CoinGecko sync failed: \(error)")
            }
        }
        
        // Rebuild combined list
        await rebuildCombinedList()
        
        syncStatus = .completed(coinCount: allMarketCoins.count)
        totalCoinCount = allMarketCoins.count
        isSyncing = false
        
        if !sources.isEmpty {
            print("[MarketDataSyncService] Incremental sync: \(sources.joined(separator: ", "))")
        }
    }
    
    /// Force refresh from all sources
    func forceRefresh() async {
        // Clear page caches to get fresh data
        CryptoAPIService.clearPageCaches()
        
        // Reset sync times to force full refresh
        lastCoinGeckoSyncAt = .distantPast
        lastBinanceSyncAt = .distantPast
        lastPumpFunSyncAt = .distantPast
        lastCategorySyncAt = .distantPast
        
        await performFullSync()
    }
    
    // MARK: - Private Methods
    
    /// Rebuild the combined list from all sources
    private func rebuildCombinedList() async {
        var coinsByID: [String: MarketCoin] = [:]
        var coinsBySymbol: [String: MarketCoin] = [:]
        
        // 1. Start with MarketViewModel's allCoins (CoinGecko + Binance merged)
        let marketCoins = MarketViewModel.shared.allCoins
        for coin in marketCoins {
            coinsByID[coin.id.lowercased()] = coin
            coinsBySymbol[coin.symbol.uppercased()] = coin
        }
        
        // 2. Add trending meme coins from NewlyListedCoinsService
        for coin in NewlyListedCoinsService.shared.trendingMemeCoins {
            let id = coin.id.lowercased()
            let sym = coin.symbol.uppercased()
            if coinsByID[id] == nil && coinsBySymbol[sym] == nil {
                coinsByID[id] = coin
                coinsBySymbol[sym] = coin
            }
        }
        
        // 3. Add Pump.fun tokens
        let pumpFunCoins = await PumpFunService.shared.recentTokensAsMarketCoins()
        for coin in pumpFunCoins {
            let id = coin.id.lowercased()
            let sym = coin.symbol.uppercased()
            // Only add if we don't already have this symbol (to avoid duplicates)
            if coinsBySymbol[sym] == nil {
                coinsByID[id] = coin
                coinsBySymbol[sym] = coin
            }
        }
        
        // Sort by market cap (with fallback to volume for coins without market cap)
        var combined = Array(coinsByID.values)
        combined.sort { a, b in
            let aRank = a.marketCapRank ?? Int.max
            let bRank = b.marketCapRank ?? Int.max
            if aRank != bRank { return aRank < bRank }
            
            let aCap = a.marketCap ?? 0
            let bCap = b.marketCap ?? 0
            if aCap != bCap { return aCap > bCap }
            
            let aVol = a.totalVolume ?? 0
            let bVol = b.totalVolume ?? 0
            return aVol > bVol
        }
        
        allMarketCoins = combined
    }
    
    /// Get current SOL price
    private func getSolPrice() async -> Double {
        if let solCoin = MarketViewModel.shared.allCoins.first(where: { $0.symbol.uppercased() == "SOL" }),
           let price = solCoin.priceUsd, price > 0 {
            return price
        }
        return 200 // Fallback
    }
}
