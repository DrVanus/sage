//
//  CommodityLivePriceManager.swift
//  CryptoSage
//
//  Created by CryptoSage on 1/30/26.
//  Manages live price updates for commodities from Yahoo Finance.
//  Provides a Combine publisher for real-time price streaming across the app.
//

import Foundation
import Combine
import os

// MARK: - Commodity Price Data

/// Live price data for a commodity
struct CommodityPriceData: Identifiable, Equatable {
    let id: String                    // Commodity ID (e.g., "gold", "silver")
    let symbol: String                // Display symbol (e.g., "GC", "SI")
    let name: String                  // Display name (e.g., "Gold")
    let price: Double                 // Current price in USD
    let change24h: Double?            // 24-hour change percentage (nil = unavailable)
    let previousClose: Double?        // Previous day close price
    let lastUpdated: Date             // When this price was last updated
    let source: CommodityPriceSource  // Data source
    
    static func == (lhs: CommodityPriceData, rhs: CommodityPriceData) -> Bool {
        lhs.id == rhs.id && lhs.price == rhs.price && lhs.change24h == rhs.change24h
    }
}

/// Source of commodity price data
enum CommodityPriceSource: String {
    case yahooFinance = "Yahoo Finance"
    case cached = "Cached"
    case fallback = "Fallback"
}

// MARK: - Commodity Live Price Manager

/// Singleton manager for commodity live price updates
/// Polls Yahoo Finance for all commodity data at configurable intervals.
final class CommodityLivePriceManager: ObservableObject {
    static let shared = CommodityLivePriceManager()
    
    private let logger = Logger(subsystem: "CryptoSage", category: "CommodityLivePriceManager")
    
    // MARK: - Published State
    
    /// Current prices for all tracked commodities
    @Published private(set) var prices: [String: CommodityPriceData] = [:]
    
    /// Whether price updates are currently active
    @Published private(set) var isPolling: Bool = false
    
    /// Whether initial data is being loaded
    @Published private(set) var isLoading: Bool = false
    
    /// Last successful update time
    @Published private(set) var lastUpdateTime: Date? = nil
    
    /// Last error encountered during fetch
    @Published private(set) var lastError: Error? = nil
    
    /// Number of consecutive failures
    @Published private(set) var consecutiveFailures: Int = 0
    
    // MARK: - Publisher
    
    /// Publisher that emits price updates for specific commodities
    let priceUpdatePublisher = PassthroughSubject<[CommodityPriceData], Never>()
    
    // MARK: - Configuration
    
    /// Polling interval for Yahoo Finance (45 seconds for fresh data)
    private let pollingInterval: TimeInterval = 45.0
    
    /// Commodities to track (from CommoditySymbolMapper)
    private var trackedCommodities: Set<String> = []
    
    // MARK: - Private State
    
    private var pollingTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // Price cache with timestamps
    private var priceCache: [String: (price: Double, change24h: Double?, timestamp: Date)] = [:]
    private let cacheTTL: TimeInterval = 300.0 // 5 minutes cache for better reliability
    private let staleCacheMaxAge: TimeInterval = 1800.0 // 30 minutes max stale data
    
    // Retry configuration
    private let maxRetries: Int = 3
    private var currentRetryAttempt: Int = 0
    private var retryTask: Task<Void, Never>?
    
    /// Base delay for exponential backoff (in seconds)
    private let baseRetryDelay: TimeInterval = 2.0
    
    /// Maximum delay between retries (in seconds)
    private let maxRetryDelay: TimeInterval = 30.0
    
    // MARK: - Initialization
    
    private init() {
        // Start with default commodities (precious metals)
        let defaults = CommoditySymbolMapper.preciousMetals.map { $0.id }
        trackedCommodities = Set(defaults)
        
        #if DEBUG
        logger.info("🏗️ CommodityLivePriceManager initialized with \(defaults.count) commodities: \(defaults.joined(separator: ", "))")
        #endif
    }
    
    // MARK: - Public API
    
    /// Start polling for commodity prices
    /// - Parameter commodityIds: Optional set of commodity IDs to track. If nil, tracks all precious metals.
    func startPolling(for commodityIds: Set<String>? = nil) {
        // PERFORMANCE FIX v15: Don't restart polling if already polling with same or subset of commodities
        // This prevents excessive restarts when multiple views call startPolling
        if let ids = commodityIds {
            let newIdsAreSubset = ids.isSubset(of: trackedCommodities)
            if isPolling && newIdsAreSubset && pollingTimer != nil {
                logger.debug("Already polling for requested commodities, skipping restart")
                return
            }
            // Add new commodities to tracked set (don't replace)
            trackedCommodities.formUnion(ids)
        }
        
        // Only restart timer if not already polling
        guard !isPolling || pollingTimer == nil else {
            logger.debug("Already polling, just updated tracked commodities")
            return
        }
        
        stopPolling()
        
        guard !trackedCommodities.isEmpty else {
            logger.debug("No commodities to track")
            return
        }
        
        isPolling = true
        isLoading = prices.isEmpty // Only show loading if no data yet
        consecutiveFailures = 0
        lastError = nil
        
        logger.info("Starting commodity price polling for \(self.trackedCommodities.count) commodities")
        
        // PERFORMANCE FIX: Defer initial fetch during startup to avoid overwhelming the system
        // Firebase handles commodity prices, so defer the Yahoo Finance fallback
        Task {
            // Wait for startup to complete before first fetch
            if shouldBlockHeavyOperationsDuringStartup() {
                try? await Task.sleep(nanoseconds: 3_500_000_000) // 3.5 seconds
            }
            await refreshAllPrices()
        }
        
        // PERFORMANCE FIX v17: Increased from 60s to 120s - commodity prices change slowly
        // Firebase already has server-side caching. Polling every 60s was redundant because:
        // 1. Yahoo Finance data updates every 1-5 minutes for most commodities
        // 2. Firebase proxy caches for 5 minutes
        // 3. Each poll triggers @Published updates which cause SwiftUI re-renders
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 120.0, repeats: true) { [weak self] _ in
            Task { [weak self] in
                // Skip refresh during scroll
                guard !ScrollStateAtomicStorage.shared.shouldBlock() else { return }
                await self?.refreshAllPrices()
            }
        }
    }
    
    /// Stop polling for commodity prices
    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        retryTask?.cancel()
        retryTask = nil
        isPolling = false
        currentRetryAttempt = 0
        logger.info("Stopped commodity price polling")
    }
    
    /// Add a commodity to tracking
    func trackCommodity(_ commodityId: String) {
        trackedCommodities.insert(commodityId)
        
        // Immediately fetch price for new commodity
        Task {
            await fetchPriceForCommodity(commodityId)
        }
    }
    
    /// Remove a commodity from tracking
    func untrackCommodity(_ commodityId: String) {
        trackedCommodities.remove(commodityId)
    }
    
    /// Get current price for a commodity
    func getPrice(for commodityId: String) -> CommodityPriceData? {
        prices[commodityId]
    }
    
    /// Get current price by any symbol (Yahoo, etc.)
    func getPriceBySymbol(_ symbol: String) -> CommodityPriceData? {
        if let info = CommoditySymbolMapper.getCommodity(for: symbol) {
            return prices[info.id]
        }
        return nil
    }
    
    /// Force refresh all prices immediately
    func forceRefresh() async {
        currentRetryAttempt = 0
        retryTask?.cancel()
        retryTask = nil
        await refreshAllPrices()
    }
    
    // MARK: - Private Methods
    
    // PERFORMANCE FIX v15: Track last refresh to prevent excessive API calls
    private var lastRefreshAt: Date = .distantPast
    private let minRefreshInterval: TimeInterval = 30.0 // Minimum 30 seconds between refreshes
    
    /// Refresh prices - try Firebase first (shared cache), fallback to direct Yahoo Finance
    private func refreshAllPrices() async {
        // PERFORMANCE FIX v15: Throttle refreshes to prevent excessive API calls
        let now = Date()
        guard now.timeIntervalSince(lastRefreshAt) >= minRefreshInterval else {
            #if DEBUG
            logger.debug("Skipping refresh - called too recently (\(Int(now.timeIntervalSince(self.lastRefreshAt)))s ago)")
            #endif
            return
        }
        lastRefreshAt = now
        
        // Get all tracked commodities
        let commodities = trackedCommodities.compactMap { id -> CommodityInfo? in
            CommoditySymbolMapper.getCommodityById(id)
        }
        
        guard !commodities.isEmpty else {
            #if DEBUG
            logger.debug("No commodities to fetch")
            #endif
            return
        }
        
        let yahooSymbols = commodities.map { $0.yahooSymbol }
        
        // STRATEGY: Try Firebase first (shared cache across all users, no rate limits)
        // Fall back to direct Yahoo Finance if Firebase fails
        
        var updatedPrices: [CommodityPriceData] = []
        var failedCommodities: [String] = []
        var usedFirebase = false
        
        // Try Firebase first
        let shouldUseFirebase = await FirebaseService.shared.shouldUseFirebase
        if shouldUseFirebase {
            do {
                #if DEBUG
                logger.info("📊 Fetching \(yahooSymbols.count) commodity prices via Firebase (shared cache)")
                #endif
                
                let response = try await FirebaseService.shared.getCommodityPrices(symbols: yahooSymbols)
                
                #if DEBUG
                logger.info("📊 Firebase returned \(response.prices.count) prices (cached: \(response.cached))")
                #endif
                
                // Process Firebase response
                for priceData in response.prices {
                    guard let commodity = CommoditySymbolMapper.getCommodityByYahoo(priceData.symbol) else {
                        continue
                    }
                    
                    let commodityPrice = CommodityPriceData(
                        id: commodity.id,
                        symbol: commodity.displaySymbol,
                        name: commodity.name,
                        price: priceData.price,
                        change24h: priceData.changePercent,
                        previousClose: priceData.previousClose,
                        lastUpdated: Date(),
                        source: .yahooFinance  // Data is from Yahoo via Firebase
                    )
                    
                    await MainActor.run {
                        prices[commodity.id] = commodityPrice
                        priceCache[commodity.id] = (priceData.price, priceData.changePercent, Date())
                    }
                    
                    updatedPrices.append(commodityPrice)
                    
                    #if DEBUG
                    let changeStr = priceData.changePercent.map { String(format: "%+.2f", $0) } ?? "N/A"
                    logger.debug("  ✓ \(commodity.name): $\(String(format: "%.2f", priceData.price)) (\(changeStr)%)")
                    #endif
                }
                
                usedFirebase = true
                
                // Check for any symbols that weren't returned
                let returnedSymbols = Set(response.prices.map { $0.symbol })
                failedCommodities = yahooSymbols.filter { !returnedSymbols.contains($0) }
                
            } catch {
                #if DEBUG
                logger.warning("⚠️ Firebase fetch failed, falling back to direct Yahoo Finance: \(error.localizedDescription)")
                #endif
                // Fall through to direct Yahoo Finance
            }
        }
        
        // Fallback to direct Yahoo Finance ONLY when Firebase was completely unavailable.
        // If Firebase succeeded but some symbols are missing, those symbols likely don't exist
        // on Yahoo Finance (e.g., exotic PGMs like iridium, rhodium, ruthenium).
        // Retrying via StockPriceService would hit the same Yahoo API and fail identically,
        // generating noisy 404/401 errors (getStockQuotes not deployed + direct Yahoo blocked).
        if !usedFirebase {
            let symbolsToFetch = yahooSymbols
            
            #if DEBUG
            logger.info("📊 Fetching \(symbolsToFetch.count) commodity prices from direct Yahoo Finance (Firebase unavailable)")
            #endif
            
            // RELIABILITY FIX: Fetch in smaller batches (max 8 symbols each)
            // Yahoo Finance can silently drop symbols from large batch requests,
            // causing agriculture/livestock/some energy commodities to return empty.
            let batchSize = 8
            let batches = stride(from: 0, to: symbolsToFetch.count, by: batchSize).map {
                Array(symbolsToFetch[$0..<min($0 + batchSize, symbolsToFetch.count)])
            }
            
            var directFailures: [String] = []
            
            for (batchIndex, batch) in batches.enumerated() {
                // Small delay between batches to avoid rate limiting (skip first batch)
                if batchIndex > 0 {
                    try? await Task.sleep(nanoseconds: 300_000_000) // 300ms between batches
                }
                
                let quotes = await StockPriceService.shared.fetchQuotes(tickers: batch)
                
                for symbol in batch {
                    guard let commodity = CommoditySymbolMapper.getCommodityByYahoo(symbol) else {
                        directFailures.append(symbol)
                        continue
                    }
                    
                    if let quote = quotes[symbol], quote.regularMarketPrice > 0 {
                        let change24h: Double? = {
                            if let apiChange = quote.regularMarketChangePercent {
                                return apiChange
                            }
                            if let prevClose = quote.regularMarketPreviousClose, prevClose > 0 {
                                return ((quote.regularMarketPrice - prevClose) / prevClose) * 100
                            }
                            // Additional fallback: use regularMarketChange if available
                            if let absChange = quote.regularMarketChange, quote.regularMarketPrice > 0 {
                                let impliedPrevClose = quote.regularMarketPrice - absChange
                                if impliedPrevClose > 0 {
                                    return (absChange / impliedPrevClose) * 100
                                }
                            }
                            return nil
                        }()
                        
                        let priceData = CommodityPriceData(
                            id: commodity.id,
                            symbol: commodity.displaySymbol,
                            name: commodity.name,
                            price: quote.regularMarketPrice,
                            change24h: change24h,
                            previousClose: quote.regularMarketPreviousClose,
                            lastUpdated: Date(),
                            source: .yahooFinance
                        )
                        
                        await MainActor.run {
                            prices[commodity.id] = priceData
                            priceCache[commodity.id] = (quote.regularMarketPrice, change24h, Date())
                        }
                        
                        updatedPrices.append(priceData)
                        
                        #if DEBUG
                        let changeStr = change24h.map { String(format: "%+.2f", $0) } ?? "N/A"
                        logger.debug("  ✓ \(commodity.name): $\(String(format: "%.2f", quote.regularMarketPrice)) (\(changeStr)%)")
                        #endif
                    } else {
                        directFailures.append(symbol)
                        
                        // Use cached price if available
                        if let cached = priceCache[commodity.id],
                           Date().timeIntervalSince(cached.timestamp) < staleCacheMaxAge {
                            let cachedPriceData = CommodityPriceData(
                                id: commodity.id,
                                symbol: commodity.displaySymbol,
                                name: commodity.name,
                                price: cached.price,
                                change24h: cached.change24h,
                                previousClose: nil,
                                lastUpdated: cached.timestamp,
                                source: .cached
                            )
                            
                            await MainActor.run {
                                if prices[commodity.id] == nil {
                                    prices[commodity.id] = cachedPriceData
                                }
                            }
                            
                            #if DEBUG
                            logger.debug("  ⚠️ \(commodity.name): Using cached data from \(Int(-cached.timestamp.timeIntervalSinceNow))s ago")
                            #endif
                        }
                    }
                }
            }
            
            failedCommodities = directFailures
        } else if usedFirebase && !failedCommodities.isEmpty {
            // Firebase returned partial results. Try direct Yahoo for the missing symbols.
            // The v7/quote API often returns data that the chart API missed.
            #if DEBUG
            logger.info("📊 Retrying \(failedCommodities.count) symbols via direct Yahoo (Firebase partial)")
            #endif
            
            let batchSize = 8
            let batches = stride(from: 0, to: failedCommodities.count, by: batchSize).map {
                Array(failedCommodities[$0..<min($0 + batchSize, failedCommodities.count)])
            }
            
            var stillFailed: [String] = []
            
            for (batchIndex, batch) in batches.enumerated() {
                if batchIndex > 0 {
                    try? await Task.sleep(nanoseconds: 300_000_000) // 300ms delay between batches
                }
                
                let quotes = await StockPriceService.shared.fetchQuotes(tickers: batch)
                
                for symbol in batch {
                    guard let commodity = CommoditySymbolMapper.getCommodityByYahoo(symbol) else {
                        stillFailed.append(symbol)
                        continue
                    }
                    
                    if let quote = quotes[symbol], quote.regularMarketPrice > 0 {
                        let change24h: Double? = {
                            if let apiChange = quote.regularMarketChangePercent {
                                return apiChange
                            }
                            if let prevClose = quote.regularMarketPreviousClose, prevClose > 0 {
                                return ((quote.regularMarketPrice - prevClose) / prevClose) * 100
                            }
                            if let absChange = quote.regularMarketChange, quote.regularMarketPrice > 0 {
                                let impliedPrevClose = quote.regularMarketPrice - absChange
                                if impliedPrevClose > 0 {
                                    return (absChange / impliedPrevClose) * 100
                                }
                            }
                            return nil
                        }()
                        
                        let priceData = CommodityPriceData(
                            id: commodity.id,
                            symbol: commodity.displaySymbol,
                            name: commodity.name,
                            price: quote.regularMarketPrice,
                            change24h: change24h,
                            previousClose: quote.regularMarketPreviousClose,
                            lastUpdated: Date(),
                            source: .yahooFinance
                        )
                        
                        await MainActor.run {
                            prices[commodity.id] = priceData
                            priceCache[commodity.id] = (quote.regularMarketPrice, change24h, Date())
                        }
                        updatedPrices.append(priceData)
                        
                        #if DEBUG
                        let changeStr = change24h.map { String(format: "%+.2f", $0) } ?? "N/A"
                        logger.debug("  ✓ \(commodity.name): $\(String(format: "%.2f", quote.regularMarketPrice)) (\(changeStr)%) [direct fallback]")
                        #endif
                    } else {
                        stillFailed.append(symbol)
                        
                        // Use cached price if available
                        if let cached = priceCache[commodity.id],
                           Date().timeIntervalSince(cached.timestamp) < staleCacheMaxAge {
                            let cachedPriceData = CommodityPriceData(
                                id: commodity.id,
                                symbol: commodity.displaySymbol,
                                name: commodity.name,
                                price: cached.price,
                                change24h: cached.change24h,
                                previousClose: nil,
                                lastUpdated: cached.timestamp,
                                source: .cached
                            )
                            await MainActor.run {
                                if prices[commodity.id] == nil {
                                    prices[commodity.id] = cachedPriceData
                                }
                            }
                        }
                    }
                }
            }
            
            failedCommodities = stillFailed
            
            #if DEBUG
            if !stillFailed.isEmpty {
                logger.debug("⚠️ \(stillFailed.count) symbols still have no data after direct fallback: \(stillFailed.joined(separator: ", "))")
            }
            #endif
        }
        
        // Update state based on results
        let fetchSucceeded = !updatedPrices.isEmpty
        let allFailed = updatedPrices.isEmpty && !failedCommodities.isEmpty
        
        // Capture immutable copies for @Sendable closure
        let finalUpdatedPrices = updatedPrices
        let finalUsedFirebase = usedFirebase
        let finalFailedCommodities = failedCommodities
        
        await MainActor.run {
            isLoading = false
            
            if fetchSucceeded {
                lastUpdateTime = Date()
                lastError = nil
                consecutiveFailures = 0
                currentRetryAttempt = 0
                priceUpdatePublisher.send(finalUpdatedPrices)
                
                #if DEBUG
                let sourceStr = finalUsedFirebase ? "Firebase" : "Yahoo Finance"
                logger.info("✅ Updated \(finalUpdatedPrices.count) commodity prices from \(sourceStr)")
                #endif
            } else if allFailed {
                consecutiveFailures += 1
                
                #if DEBUG
                logger.warning("⚠️ Failed to fetch commodity prices for: \(finalFailedCommodities.joined(separator: ", "))")
                #endif
            }
        }
        
        // Schedule retry with exponential backoff if fetch failed completely
        if allFailed && currentRetryAttempt < maxRetries {
            await scheduleRetry(failedSymbols: failedCommodities)
        }
    }
    
    /// Schedule a retry with exponential backoff
    private func scheduleRetry(failedSymbols: [String]) async {
        currentRetryAttempt += 1
        
        // Calculate delay with exponential backoff: 2s, 4s, 8s, ... capped at maxRetryDelay
        let delay = min(baseRetryDelay * pow(2.0, Double(currentRetryAttempt - 1)), maxRetryDelay)
        // Add jitter to prevent thundering herd
        let jitter = Double.random(in: 0...1.0)
        let totalDelay = delay + jitter
        
        #if DEBUG
        logger.info("🔄 Scheduling retry \(self.currentRetryAttempt)/\(self.maxRetries) in \(String(format: "%.1f", totalDelay))s for \(failedSymbols.count) failed commodities")
        #endif
        
        // Cancel any existing retry task
        retryTask?.cancel()
        
        retryTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                try await Task.sleep(nanoseconds: UInt64(totalDelay * 1_000_000_000))
                
                // Check if task was cancelled
                guard !Task.isCancelled else { return }
                
                #if DEBUG
                self.logger.info("🔄 Executing retry \(self.currentRetryAttempt)/\(self.maxRetries)")
                #endif
                
                // Retry the failed symbols specifically
                await self.retryFailedSymbols(failedSymbols)
            } catch {
                // Task was cancelled, that's fine
                #if DEBUG
                self.logger.debug("Retry task cancelled")
                #endif
            }
        }
    }
    
    /// Retry fetching specific failed symbols
    private func retryFailedSymbols(_ symbols: [String]) async {
        let quotes = await StockPriceService.shared.fetchQuotes(tickers: symbols)
        
        var updatedPrices: [CommodityPriceData] = []
        var stillFailed: [String] = []
        
        for symbol in symbols {
            guard let commodity = CommoditySymbolMapper.getCommodityByYahoo(symbol) else {
                stillFailed.append(symbol)
                continue
            }
            
            if let quote = quotes[symbol], quote.regularMarketPrice > 0 {
                let change24h: Double? = {
                    if let apiChange = quote.regularMarketChangePercent {
                        return apiChange
                    }
                    if let prevClose = quote.regularMarketPreviousClose, prevClose > 0 {
                        return ((quote.regularMarketPrice - prevClose) / prevClose) * 100
                    }
                    return nil
                }()
                
                let priceData = CommodityPriceData(
                    id: commodity.id,
                    symbol: commodity.displaySymbol,
                    name: commodity.name,
                    price: quote.regularMarketPrice,
                    change24h: change24h,
                    previousClose: quote.regularMarketPreviousClose,
                    lastUpdated: Date(),
                    source: .yahooFinance
                )
                
                await MainActor.run {
                    prices[commodity.id] = priceData
                    priceCache[commodity.id] = (quote.regularMarketPrice, change24h, Date())
                }
                
                updatedPrices.append(priceData)
                
                #if DEBUG
                logger.debug("  ✓ Retry succeeded for \(commodity.name)")
                #endif
            } else {
                stillFailed.append(symbol)
            }
        }
        
        // Capture immutable copies for @Sendable closures
        let finalUpdatedPrices = updatedPrices
        let finalStillFailed = stillFailed
        
        await MainActor.run {
            if !finalUpdatedPrices.isEmpty {
                lastUpdateTime = Date()
                lastError = nil
                consecutiveFailures = 0
                priceUpdatePublisher.send(finalUpdatedPrices)
                
                #if DEBUG
                logger.info("✅ Retry recovered \(finalUpdatedPrices.count) commodity prices")
                #endif
            }
        }
        
        // If some still failed and we have retries left, schedule another retry
        if !finalStillFailed.isEmpty && currentRetryAttempt < maxRetries {
            await scheduleRetry(failedSymbols: finalStillFailed)
        } else if !finalStillFailed.isEmpty {
            #if DEBUG
            logger.warning("⚠️ Max retries reached. \(finalStillFailed.count) commodities still failed: \(finalStillFailed.joined(separator: ", "))")
            #endif
            
            await MainActor.run {
                // Set error state for UI to display
                lastError = CommodityFetchError.maxRetriesReached(failedSymbols: finalStillFailed)
            }
        }
    }
    
    /// Custom error type for commodity fetching
    enum CommodityFetchError: Error, LocalizedError {
        case maxRetriesReached(failedSymbols: [String])
        case networkError(underlying: Error)
        case noDataAvailable
        
        var errorDescription: String? {
            switch self {
            case .maxRetriesReached(let symbols):
                return "Failed to fetch prices for: \(symbols.joined(separator: ", "))"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .noDataAvailable:
                return "No commodity data available"
            }
        }
    }
    
    /// Fetch price for a single commodity
    private func fetchPriceForCommodity(_ commodityId: String) async {
        guard let info = CommoditySymbolMapper.getCommodityById(commodityId) else { return }
        
        // Fetch from Yahoo Finance
        if let quote = await StockPriceService.shared.fetchQuote(ticker: info.yahooSymbol),
           quote.regularMarketPrice > 0 {
            // Calculate change: prefer API value, fallback to previousClose calculation
            let change24h: Double? = {
                if let apiChange = quote.regularMarketChangePercent {
                    return apiChange
                }
                if let prevClose = quote.regularMarketPreviousClose, prevClose > 0 {
                    return ((quote.regularMarketPrice - prevClose) / prevClose) * 100
                }
                return nil
            }()
            
            let priceData = CommodityPriceData(
                id: info.id,
                symbol: info.displaySymbol,
                name: info.name,
                price: quote.regularMarketPrice,
                change24h: change24h,
                previousClose: quote.regularMarketPreviousClose,
                lastUpdated: Date(),
                source: .yahooFinance
            )
            
            await MainActor.run {
                prices[info.id] = priceData
                priceCache[info.id] = (quote.regularMarketPrice, change24h, Date())
                priceUpdatePublisher.send([priceData])
            }
            
            #if DEBUG
            let changeStr = change24h.map { String(format: "%+.2f", $0) } ?? "N/A"
            logger.debug("✓ Fetched \(info.name): $\(String(format: "%.2f", quote.regularMarketPrice)) (\(changeStr)%)")
            #endif
        } else {
            // If fetch failed, try to use cached data
            if let cached = priceCache[info.id],
               Date().timeIntervalSince(cached.timestamp) < staleCacheMaxAge {
                let cachedPriceData = CommodityPriceData(
                    id: info.id,
                    symbol: info.displaySymbol,
                    name: info.name,
                    price: cached.price,
                    change24h: cached.change24h,
                    previousClose: nil,
                    lastUpdated: cached.timestamp,
                    source: .cached
                )
                
                await MainActor.run {
                    if prices[info.id] == nil {
                        prices[info.id] = cachedPriceData
                    }
                }
                
                #if DEBUG
                logger.debug("⚠️ Using cached data for \(info.name)")
                #endif
            } else {
                #if DEBUG
                logger.warning("Failed to fetch price for \(info.yahooSymbol)")
                #endif
            }
        }
    }
    
    /// Fetch all commodity prices (for market view)
    /// This fetches ALL supported commodities, not just tracked ones
    func fetchAllCommodityPrices() async {
        let allCommodities = CommoditySymbolMapper.allCommodities
        
        await MainActor.run {
            isLoading = prices.isEmpty
        }
        
        // Batch fetch all Yahoo symbols in smaller batches for reliability
        let yahooSymbols = allCommodities.map { $0.yahooSymbol }
        
        #if DEBUG
        logger.info("📊 Fetching all \(yahooSymbols.count) commodity prices from Yahoo Finance")
        #endif
        
        // RELIABILITY FIX: Split into smaller batches (max 8 symbols each)
        // Yahoo Finance can silently drop symbols from large batch requests
        let batchSize = 8
        let batches = stride(from: 0, to: yahooSymbols.count, by: batchSize).map {
            Array(yahooSymbols[$0..<min($0 + batchSize, yahooSymbols.count)])
        }
        
        var updatedPrices: [CommodityPriceData] = []
        var failedCount = 0
        
        for (batchIndex, batch) in batches.enumerated() {
            // Small delay between batches to avoid rate limiting (skip first batch)
            if batchIndex > 0 {
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms between batches
            }
            
            let quotes = await StockPriceService.shared.fetchQuotes(tickers: batch)
            
            for symbol in batch {
                guard let commodity = CommoditySymbolMapper.getCommodityByYahoo(symbol) else {
                    failedCount += 1
                    continue
                }
                
                if let quote = quotes[symbol], quote.regularMarketPrice > 0 {
                    // Calculate change: prefer API value, fallback to previousClose, then absoluteChange
                    let change24h: Double? = {
                        if let apiChange = quote.regularMarketChangePercent {
                            return apiChange
                        }
                        if let prevClose = quote.regularMarketPreviousClose, prevClose > 0 {
                            return ((quote.regularMarketPrice - prevClose) / prevClose) * 100
                        }
                        if let absChange = quote.regularMarketChange, quote.regularMarketPrice > 0 {
                            let impliedPrevClose = quote.regularMarketPrice - absChange
                            if impliedPrevClose > 0 {
                                return (absChange / impliedPrevClose) * 100
                            }
                        }
                        return nil
                    }()
                    
                    let priceData = CommodityPriceData(
                        id: commodity.id,
                        symbol: commodity.displaySymbol,
                        name: commodity.name,
                        price: quote.regularMarketPrice,
                        change24h: change24h,
                        previousClose: quote.regularMarketPreviousClose,
                        lastUpdated: Date(),
                        source: .yahooFinance
                    )
                    
                    await MainActor.run {
                        prices[commodity.id] = priceData
                        priceCache[commodity.id] = (quote.regularMarketPrice, change24h, Date())
                    }
                    
                    updatedPrices.append(priceData)
                } else {
                    failedCount += 1
                    #if DEBUG
                    logger.warning("Failed to fetch price for \(symbol)")
                    #endif
                }
            }
        }
        
        // Capture immutable copies for @Sendable closure
        let finalUpdatedPrices = updatedPrices
        let finalFailedCount = failedCount
        
        await MainActor.run {
            isLoading = false
            
            if !finalUpdatedPrices.isEmpty {
                lastUpdateTime = Date()
                consecutiveFailures = 0
                priceUpdatePublisher.send(finalUpdatedPrices)
            } else {
                consecutiveFailures += 1
            }
        }
        
        #if DEBUG
        logger.info("✅ Fetched \(finalUpdatedPrices.count) of \(allCommodities.count) commodity prices (\(finalFailedCount) failed)")
        #endif
    }
    
    // MARK: - Cache Helpers
    
    /// Get cached price if still valid
    func getCachedPrice(for commodityId: String) -> (price: Double, change24h: Double?)? {
        guard let cached = priceCache[commodityId],
              Date().timeIntervalSince(cached.timestamp) < cacheTTL else {
            return nil
        }
        return (cached.price, cached.change24h)
    }
    
    /// Check if we have fresh data for a commodity
    func isFresh(for commodityId: String) -> Bool {
        guard let cached = priceCache[commodityId] else { return false }
        return Date().timeIntervalSince(cached.timestamp) < 60.0 // 1 minute freshness
    }
}

// MARK: - Convenience Extensions

extension CommodityLivePriceManager {
    /// Get price for gold
    var goldPrice: CommodityPriceData? { prices["gold"] }
    
    /// Get price for silver
    var silverPrice: CommodityPriceData? { prices["silver"] }
    
    /// Get price for platinum
    var platinumPrice: CommodityPriceData? { prices["platinum"] }
    
    /// Get price for palladium
    var palladiumPrice: CommodityPriceData? { prices["palladium"] }
    
    /// Get price for copper
    var copperPrice: CommodityPriceData? { prices["copper"] }
    
    /// Get price for crude oil
    var oilPrice: CommodityPriceData? { prices["crude_oil"] }
    
    /// Get price for natural gas
    var naturalGasPrice: CommodityPriceData? { prices["natural_gas"] }
    
    /// Get all precious metal prices
    var preciousMetalPrices: [CommodityPriceData] {
        CommoditySymbolMapper.preciousMetals.compactMap { prices[$0.id] }
    }
    
    /// Get all energy commodity prices
    var energyPrices: [CommodityPriceData] {
        CommoditySymbolMapper.commodities(ofType: .energy).compactMap { prices[$0.id] }
    }
    
    /// Check if we have any live data (from Yahoo Finance)
    var hasLiveData: Bool {
        prices.values.contains { $0.source == .yahooFinance }
    }
    
    /// Check if all data is from cache or fallback
    var isUsingCachedData: Bool {
        !prices.isEmpty && !hasLiveData
    }
    
    /// Get data freshness status for UI display
    var dataStatus: DataStatus {
        if isLoading && prices.isEmpty {
            return .loading
        }
        if prices.isEmpty {
            return .noData
        }
        if hasLiveData {
            return .live
        }
        return .cached
    }
    
    /// Data status enum for UI
    enum DataStatus {
        case loading
        case live
        case cached
        case noData
        
        var displayText: String {
            switch self {
            case .loading: return "Loading"
            case .live: return "Live"
            case .cached: return "Cached"
            case .noData: return "Estimated"
            }
        }
        
        var isLive: Bool {
            self == .live
        }
    }
}
