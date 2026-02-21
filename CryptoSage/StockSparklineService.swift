//
//  StockSparklineService.swift
//  CryptoSage
//
//  Created by CryptoSage on 1/30/26.
//  Service for fetching and caching 5-day historical data for stock sparklines.
//  Uses Yahoo Finance chart API for price history.
//

import Foundation
import Combine

// MARK: - Stock Sparkline Service

/// Service for fetching and caching stock sparkline data (5-day price history)
@MainActor
final class StockSparklineService: ObservableObject {
    
    static let shared = StockSparklineService()
    
    // MARK: - Published State
    
    /// Sparkline data cache: ticker -> array of close prices
    @Published private(set) var sparklineCache: [String: [Double]] = [:]
    
    /// Loading state for batch fetches
    @Published private(set) var isLoading: Bool = false
    
    // MARK: - Cache Configuration
    
    /// Cache TTL during market hours (15 minutes)
    private let marketOpenTTL: TimeInterval = 900
    
    /// Cache TTL when market is closed (1 hour)
    private let marketClosedTTL: TimeInterval = 3600
    
    /// Timestamp cache for TTL management
    private var cacheTimestamps: [String: Date] = [:]
    
    /// In-flight requests to avoid duplicate fetches
    private var inflightRequests: [String: Task<[Double], Never>] = [:]
    
    /// Disable Firebase sparkline path temporarily if function is missing
    private var firebaseSparklineDisabledUntil: Date = .distantPast
    private let firebaseSparklineDisableDuration: TimeInterval = 600 // 10 minutes
    
    // MARK: - Persistence
    
    private let cacheFileURL: URL
    private let timestampFileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    // MARK: - Initialization
    
    private init() {
        let docs = FileManager.documentsDirectory
        cacheFileURL = docs.appendingPathComponent("stock_sparkline_cache.json")
        timestampFileURL = docs.appendingPathComponent("stock_sparkline_timestamps.json")
        
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        
        // Load cached data asynchronously
        Task { @MainActor in
            await loadCachedDataAsync()
        }
    }
    
    // MARK: - Public Methods
    
    /// Get sparkline data for a ticker (returns cached if available and fresh)
    /// - Parameter ticker: Stock ticker symbol
    /// - Returns: Array of close prices for sparkline rendering
    func sparkline(for ticker: String) -> [Double]? {
        let symbol = ticker.uppercased()
        
        // Check if we have fresh cached data
        if let cached = sparklineCache[symbol],
           !cached.isEmpty,
           !isStale(symbol) {
            return cached
        }
        
        return nil
    }
    
    /// Fetch sparkline data for a ticker (fetches from API if needed)
    /// - Parameter ticker: Stock ticker symbol
    /// - Returns: Array of close prices
    func fetchSparkline(for ticker: String) async -> [Double] {
        let symbol = ticker.uppercased()
        
        // Return cached if fresh
        if let cached = sparklineCache[symbol],
           !cached.isEmpty,
           !isStale(symbol) {
            return cached
        }
        
        // Check for in-flight request
        if let existing = inflightRequests[symbol] {
            return await existing.value
        }
        
        // Start new fetch
        let task = Task<[Double], Never> {
            await fetchSparklineFromAPI(symbol: symbol)
        }
        
        inflightRequests[symbol] = task
        let result = await task.value
        inflightRequests[symbol] = nil
        
        // Cache the result
        if !result.isEmpty {
            sparklineCache[symbol] = result
            cacheTimestamps[symbol] = Date()
            saveCache()
        }
        
        return result
    }
    
    /// Fetch sparklines for multiple tickers in parallel
    /// - Parameter tickers: Array of stock ticker symbols
    func fetchSparklines(for tickers: [String]) async {
        guard !tickers.isEmpty else { return }
        let normalizedTickers = Array(Set(tickers.map { $0.uppercased() }))
        
        isLoading = true
        defer { isLoading = false }
        
        // Filter to only tickers that need fetching
        let tickersToFetch = normalizedTickers.filter { symbol in
            if let cached = sparklineCache[symbol], !cached.isEmpty, !isStale(symbol) {
                return false
            }
            return true
        }
        
        guard !tickersToFetch.isEmpty else { return }
        
        #if DEBUG
        print("📈 [StockSparklineService] Fetching sparklines for \(tickersToFetch.count) tickers...")
        #endif
        
        // Try Firebase first so all users share the same cached history.
        var remainingToFetch = tickersToFetch
        var fetchedUpdates: [String: [Double]] = [:]
        if let firebaseResults = await fetchSparklinesViaFirebase(symbols: tickersToFetch), !firebaseResults.isEmpty {
            fetchedUpdates.merge(firebaseResults) { _, new in new }
            let got = Set(firebaseResults.keys)
            remainingToFetch = tickersToFetch.filter { !got.contains($0) }
            
            #if DEBUG
            print("📈 [StockSparklineService] Firebase returned \(firebaseResults.count)/\(tickersToFetch.count) sparklines")
            #endif
        }
        
        guard !remainingToFetch.isEmpty else {
            if !fetchedUpdates.isEmpty {
                var updatedCache = sparklineCache
                for (symbol, data) in fetchedUpdates {
                    updatedCache[symbol] = data
                }
                sparklineCache = updatedCache
                let now = Date()
                for symbol in fetchedUpdates.keys {
                    cacheTimestamps[symbol] = now
                }
                saveCache()
            }
            return
        }
        
        // Fetch in parallel with bounded concurrency
        await withTaskGroup(of: (String, [Double]).self) { group in
            let maxConcurrency = 8
            var index = 0
            
            // Add initial batch
            let initialBatch = min(maxConcurrency, remainingToFetch.count)
            for i in 0..<initialBatch {
                let ticker = remainingToFetch[i].uppercased()
                group.addTask {
                    let data = await self.fetchSparklineFromAPI(symbol: ticker)
                    return (ticker, data)
                }
            }
            index = initialBatch
            
            // Process results and add more tasks
            for await (ticker, data) in group {
                if !data.isEmpty {
                    fetchedUpdates[ticker] = data
                }
                
                // Add next task if available
                if index < remainingToFetch.count {
                    let nextTicker = remainingToFetch[index].uppercased()
                    index += 1
                    group.addTask {
                        let data = await self.fetchSparklineFromAPI(symbol: nextTicker)
                        return (nextTicker, data)
                    }
                }
            }
        }
        
        // Apply fetched updates in a single publish cycle to reduce UI churn.
        if !fetchedUpdates.isEmpty {
            var updatedCache = sparklineCache
            for (symbol, data) in fetchedUpdates {
                updatedCache[symbol] = data
            }
            sparklineCache = updatedCache
            
            let now = Date()
            for symbol in fetchedUpdates.keys {
                cacheTimestamps[symbol] = now
            }
        }
        
        // Save updated cache
        saveCache()
        
        #if DEBUG
        print("✅ [StockSparklineService] Sparkline fetch complete")
        #endif
    }
    
    /// Prefetch sparklines for common stocks shown on homepage
    func prefetchCommonStocks() async {
        // Priority stocks likely to be displayed on homepage
        let priorityTickers = [
            "AAPL", "MSFT", "GOOGL", "AMZN", "META", "TSLA", "NVDA",
            "SPY", "QQQ", "VOO", "JPM", "V", "JNJ", "WMT", "PG"
        ]
        
        await fetchSparklines(for: priorityTickers)
    }
    
    /// Clear all cached sparkline data
    func clearCache() {
        sparklineCache.removeAll()
        cacheTimestamps.removeAll()
        
        try? FileManager.default.removeItem(at: cacheFileURL)
        try? FileManager.default.removeItem(at: timestampFileURL)
        
        #if DEBUG
        print("🗑️ [StockSparklineService] Cache cleared")
        #endif
    }
    
    // MARK: - Private Methods
    
    private func isStale(_ symbol: String) -> Bool {
        guard let timestamp = cacheTimestamps[symbol] else { return true }
        
        let ttl = StockMarketCache.shared.isMarketOpen ? marketOpenTTL : marketClosedTTL
        return Date().timeIntervalSince(timestamp) > ttl
    }
    
    private func fetchSparklineFromAPI(symbol: String) async -> [Double] {
        // Fast path: lighter payload for quicker first render.
        var historicalData = await StockPriceService.shared.fetchHistoricalData(
            ticker: symbol,
            range: .oneDay
        )
        
        // Fallback to richer 5-day series when intraday data is unavailable/too sparse.
        if historicalData.count < 10 {
            historicalData = await StockPriceService.shared.fetchHistoricalData(
            ticker: symbol,
            range: .fiveDay
        )
        }
        
        // Extract close prices for sparkline
        let closePrices = historicalData.map { $0.close }
        
        // Ensure we have enough data points (at least 10 for a meaningful sparkline)
        guard closePrices.count >= 10 else {
            #if DEBUG
            print("⚠️ [StockSparklineService] Insufficient data for \(symbol): \(closePrices.count) points")
            #endif
            return []
        }
        
        return closePrices
    }
    
    /// Fetch sparkline history via Firebase shared cache.
    /// Returns nil when Firebase is unavailable so caller can use direct Yahoo fallback.
    private func fetchSparklinesViaFirebase(symbols: [String]) async -> [String: [Double]]? {
        guard !symbols.isEmpty else { return [:] }
        
        if Date() < firebaseSparklineDisabledUntil {
            return nil
        }
        
        let shouldUseFirebase = FirebaseService.shared.shouldUseFirebase
        guard shouldUseFirebase else { return nil }
        
        do {
            let response = try await FirebaseService.shared.getStockSparklines(
                symbols: symbols,
                range: "1d",
                interval: "5m"
            )
            var results: [String: [Double]] = [:]
            for entry in response.entries {
                let cleaned = entry.values.filter { $0.isFinite && $0 > 0 }
                guard cleaned.count >= 10 else { continue }
                results[entry.symbol.uppercased()] = cleaned
            }
            return results
        } catch {
            if case FirebaseServiceError.functionNotFound = error {
                firebaseSparklineDisabledUntil = Date().addingTimeInterval(firebaseSparklineDisableDuration)
                #if DEBUG
                print("📈 [StockSparklineService] getStockSparklines not deployed - disabling Firebase sparkline path for \(Int(firebaseSparklineDisableDuration / 60))min")
                #endif
            }
            return nil
        }
    }
    
    // MARK: - Persistence
    
    private func loadCachedDataAsync() async {
        let cacheURL = cacheFileURL
        let timestampURL = timestampFileURL
        let dec = decoder
        
        let (loadedCache, loadedTimestamps): ([String: [Double]], [String: Date]?) = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var cache: [String: [Double]] = [:]
                var timestamps: [String: Date]? = nil
                
                // Load sparkline cache
                if FileManager.default.fileExists(atPath: cacheURL.path) {
                    if let data = try? Data(contentsOf: cacheURL),
                       let cached = try? dec.decode([String: [Double]].self, from: data) {
                        cache = cached
                    }
                }
                
                // Load timestamps
                if FileManager.default.fileExists(atPath: timestampURL.path) {
                    if let data = try? Data(contentsOf: timestampURL),
                       let cached = try? dec.decode([String: Date].self, from: data) {
                        timestamps = cached
                    }
                }
                
                continuation.resume(returning: (cache, timestamps))
            }
        }
        
        await MainActor.run {
            if !loadedCache.isEmpty {
                self.sparklineCache = loadedCache
                #if DEBUG
                print("📈 [StockSparklineService] Loaded \(loadedCache.count) cached sparklines from disk")
                #endif
            }
            
            if let timestamps = loadedTimestamps {
                self.cacheTimestamps = timestamps
            }
        }
    }
    
    private func saveCache() {
        let cacheToSave = sparklineCache
        let timestampsToSave = cacheTimestamps
        let cacheURL = cacheFileURL
        let timestampURL = timestampFileURL
        let enc = encoder
        
        DispatchQueue.global(qos: .utility).async {
            // Save sparkline cache
            if let data = try? enc.encode(cacheToSave) {
                try? data.write(to: cacheURL, options: .atomic)
            }
            
            // Save timestamps
            if let data = try? enc.encode(timestampsToSave) {
                try? data.write(to: timestampURL, options: .atomic)
            }
        }
    }
}

// MARK: - FileManager Extension (if not already defined)

// Note: documentsDirectory is defined in FileManager+Directories.swift
