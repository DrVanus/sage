//
//  StockMarketCache.swift
//  CryptoSage
//
//  Created by CryptoSage on 1/20/26.
//  Caching layer for stock market data with TTL management.
//  Optimized for Yahoo Finance API with extended cache times.
//

import Foundation
import Combine
import os

// MARK: - Cached Stock Data

/// Represents a stock with combined data from multiple sources
struct CachedStock: Identifiable, Codable, Equatable {
    let symbol: String
    var name: String
    var currentPrice: Double
    var change: Double
    var changePercent: Double
    var dayHigh: Double
    var dayLow: Double
    var previousClose: Double
    var marketCap: Double?
    var volume: Int?
    var assetType: AssetType
    var exchange: String?
    var sector: String?
    var lastUpdated: Date
    
    var id: String { symbol }
    
    /// Check if data is stale based on market hours
    /// Extended TTLs to reduce API calls to Yahoo Finance
    func isStale(marketOpen: Bool) -> Bool {
        // 2 minutes during market hours, 15 minutes otherwise
        let ttl: TimeInterval = marketOpen ? 120 : 900
        return Date().timeIntervalSince(lastUpdated) > ttl
    }
    
    /// Current value (same as currentPrice for consistency)
    var currentValue: Double { currentPrice }
    
    /// Convert to Holding for unified display
    func toHolding(shares: Double = 0, costBasis: Double = 0) -> Holding {
        Holding(
            ticker: symbol,
            companyName: name,
            shares: shares,
            currentPrice: currentPrice,
            costBasis: costBasis > 0 ? costBasis : currentPrice,
            assetType: assetType,
            stockExchange: exchange,
            isin: nil,
            imageUrl: nil,
            isFavorite: false,
            dailyChange: changePercent,
            purchaseDate: Date(),
            source: "market"
        )
    }
}

// MARK: - Stock Market Cache

/// Centralized cache for stock market data
/// Optimized for Yahoo Finance with extended TTLs to stay within rate limits
@MainActor
final class StockMarketCache: ObservableObject {
    static let shared = StockMarketCache()
    
    private let logger = Logger(subsystem: "CryptoSage", category: "StockMarketCache")
    
    // MARK: - Published State
    
    /// All cached stocks keyed by symbol
    @Published private(set) var stocks: [String: CachedStock] = [:]
    
    /// Index constituents
    @Published private(set) var indexConstituents: [StockIndex: [String]] = [:]
    
    /// Loading states
    @Published private(set) var isLoadingIndices: Bool = false
    @Published private(set) var isLoadingQuotes: Bool = false
    
    /// Last update times
    @Published private(set) var lastIndexUpdate: Date?
    @Published private(set) var lastQuoteUpdate: Date?
    
    /// Market status
    @Published private(set) var isMarketOpen: Bool = false
    
    /// Error state
    @Published private(set) var lastError: Error?
    
    // MARK: - Cache Configuration (Optimized for Yahoo Finance)
    
    /// Index constituents cache TTL - 7 days (indices don't change often)
    private let indexConstituentsTTL: TimeInterval = 604800
    
    /// Quote TTL during market hours - 2 minutes (balance freshness vs rate limits)
    private let quoteTTLMarketOpen: TimeInterval = 120
    
    /// Quote TTL when market is closed - 15 minutes
    private let quoteTTLMarketClosed: TimeInterval = 900
    
    /// Minimum time between full refreshes - 30 seconds
    private let minRefreshInterval: TimeInterval = 30
    
    /// Last full refresh timestamp
    private var lastFullRefresh: Date?
    
    // MARK: - Persistence
    
    private let cacheFileURL: URL
    private let indexCacheFileURL: URL
    private let metadataFileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    // MARK: - Subscriptions
    
    private var cancellables = Set<AnyCancellable>()
    private var refreshTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    private init() {
        // SAFETY FIX: Use safe directory accessor instead of force unwrap
        let docs = FileManager.documentsDirectory
        cacheFileURL = docs.appendingPathComponent("stock_market_cache.json")
        indexCacheFileURL = docs.appendingPathComponent("stock_index_cache.json")
        metadataFileURL = docs.appendingPathComponent("stock_cache_metadata.json")
        
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        
        // PERFORMANCE FIX: Load cached data asynchronously to avoid blocking main thread during init
        Task { @MainActor [weak self] in
            await self?.loadCachedDataAsync()
            await self?.loadCacheMetadataAsync()
        }
        
        // Update market status periodically
        Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { await self?.updateMarketStatus() }
            }
            .store(in: &cancellables)
        
        // Initial market status check
        Task { await updateMarketStatus() }
    }
    
    /// Check if cache has valid data that can be displayed
    var hasValidCache: Bool {
        !stocks.isEmpty
    }
    
    /// Check if a full refresh is needed based on TTL
    var needsRefresh: Bool {
        guard let lastUpdate = lastQuoteUpdate else { return true }
        let ttl = isMarketOpen ? quoteTTLMarketOpen : quoteTTLMarketClosed
        return Date().timeIntervalSince(lastUpdate) > ttl
    }
    
    /// Check if we can perform a refresh (rate limit protection)
    var canRefresh: Bool {
        guard let lastRefresh = lastFullRefresh else { return true }
        return Date().timeIntervalSince(lastRefresh) > minRefreshInterval
    }
    
    // MARK: - Public Methods
    
    /// Get stocks for a specific index
    func stocks(for index: StockIndex) -> [CachedStock] {
        guard let constituents = indexConstituents[index] else { return [] }
        return constituents.compactMap { stocks[$0] }
    }
    
    /// Only actual stocks & ETFs (excludes commodity futures like GC=F, SI=F, NG=F, etc.)
    /// Use this for stock-specific views to avoid commodity duplicates with the Commodities section.
    var stocksExcludingCommodities: [CachedStock] {
        stocks.values.filter { $0.assetType != .commodity }
    }
    
    /// Count of actual stocks & ETFs (excludes commodity futures)
    var stockOnlyCount: Int {
        stocksExcludingCommodities.count
    }
    
    /// Get all cached items sorted (includes commodities — use for full market views with commodity tabs)
    func allStocks(sortedBy: StockSortOption = .changePercent, ascending: Bool = false) -> [CachedStock] {
        var result = Array(stocks.values)
        
        switch sortedBy {
        case .changePercent:
            result.sort { ascending ? $0.changePercent < $1.changePercent : $0.changePercent > $1.changePercent }
        case .price:
            result.sort { ascending ? $0.currentPrice < $1.currentPrice : $0.currentPrice > $1.currentPrice }
        case .marketCap:
            result.sort { ascending ? ($0.marketCap ?? 0) < ($1.marketCap ?? 0) : ($0.marketCap ?? 0) > ($1.marketCap ?? 0) }
        case .name:
            result.sort { ascending ? $0.name < $1.name : $0.name > $1.name }
        case .symbol:
            result.sort { ascending ? $0.symbol < $1.symbol : $0.symbol > $1.symbol }
        }
        
        return result
    }
    
    /// Get top gainers (stocks & ETFs only — excludes commodity futures)
    func topGainers(limit: Int = 10) -> [CachedStock] {
        stocksExcludingCommodities
            .filter { $0.changePercent > 0 }
            .sorted { $0.changePercent > $1.changePercent }
            .prefix(limit)
            .map { $0 }
    }
    
    /// Get top losers (stocks & ETFs only — excludes commodity futures)
    func topLosers(limit: Int = 10) -> [CachedStock] {
        stocksExcludingCommodities
            .filter { $0.changePercent < 0 }
            .sorted { $0.changePercent < $1.changePercent }
            .prefix(limit)
            .map { $0 }
    }
    
    /// Get stock by symbol
    func stock(for symbol: String) -> CachedStock? {
        stocks[symbol.uppercased()]
    }
    
    /// Search stocks by name or symbol
    func search(query: String) -> [CachedStock] {
        guard !query.isEmpty else { return [] }
        let lowercased = query.lowercased()
        
        return stocks.values
            .filter { $0.symbol.lowercased().contains(lowercased) || $0.name.lowercased().contains(lowercased) }
            .sorted { stock1, stock2 in
                // Prioritize exact symbol matches
                if stock1.symbol.lowercased() == lowercased { return true }
                if stock2.symbol.lowercased() == lowercased { return false }
                // Then prefix matches
                if stock1.symbol.lowercased().hasPrefix(lowercased) { return true }
                if stock2.symbol.lowercased().hasPrefix(lowercased) { return false }
                // Then by market cap
                return (stock1.marketCap ?? 0) > (stock2.marketCap ?? 0)
            }
    }
    
    /// Refresh all data (with rate limiting)
    func refresh() async {
        // PERFORMANCE FIX: Block refresh during startup phase
        // This prevents heavy API calls during the critical first 3 seconds of app launch
        guard !shouldBlockHeavyOperationsDuringStartup() else {
            logger.info("Skipping refresh - blocking heavy operations during startup")
            return
        }
        
        // Rate limiting protection
        guard canRefresh else {
            logger.info("Skipping refresh - too soon since last refresh")
            return
        }
        
        await refreshIndices()
        await refreshQuotes()
        
        lastFullRefresh = Date()
        saveCacheMetadata()
    }
    
    /// Refresh index constituents (only if Finnhub is configured)
    func refreshIndices() async {
        guard !isLoadingIndices else { return }
        guard APIConfig.hasValidFinnhubKey else {
            logger.info("Skipping Finnhub index refresh - no API key configured")
            return
        }
        
        // Check if we need to refresh (TTL check)
        if let lastUpdate = lastIndexUpdate,
           Date().timeIntervalSince(lastUpdate) < indexConstituentsTTL {
            logger.info("Index cache is fresh, skipping refresh")
            return
        }
        
        isLoadingIndices = true
        lastError = nil
        
        defer { isLoadingIndices = false }
        
        for index in StockIndex.allCases {
            do {
                let constituents = try await FinnhubService.shared.fetchIndexConstituents(index: index)
                indexConstituents[index] = constituents
                logger.info("Fetched \(constituents.count) constituents for \(index.displayName)")
            } catch {
                logger.error("Failed to fetch \(index.displayName) constituents: \(error.localizedDescription)")
                lastError = error
            }
        }
        
        lastIndexUpdate = Date()
        saveIndexCache()
        saveCacheMetadata()
    }
    
    // MARK: - Commodity Futures Symbols
    
    /// List of commodity futures symbols to track (Yahoo Finance format)
    static let commodityFuturesSymbols: [String] = [
        // Precious Metals
        "GC=F",   // Gold Futures
        "SI=F",   // Silver Futures
        "PL=F",   // Platinum Futures
        "PA=F",   // Palladium Futures
        // Energy
        "CL=F",   // Crude Oil WTI Futures
        "BZ=F",   // Brent Crude Oil Futures
        "NG=F",   // Natural Gas Futures
        "HO=F",   // Heating Oil Futures
        "RB=F",   // RBOB Gasoline Futures
        // Industrial Metals
        "HG=F",   // Copper Futures
        // Agriculture
        "ZC=F",   // Corn Futures
        "ZS=F",   // Soybean Futures
        "ZW=F",   // Wheat Futures
        "KC=F",   // Coffee Futures
        "CC=F",   // Cocoa Futures
        "CT=F",   // Cotton Futures
        "SB=F",   // Sugar Futures
        // Livestock
        "LE=F",   // Live Cattle Futures
        "HE=F",   // Lean Hogs Futures
    ]
    
    // MARK: - Default Stock Symbols
    
    /// Core set of popular stocks to always include in refreshes.
    /// Without Finnhub API key, index constituents won't load. This ensures
    /// the Stock Market page and home section always have real stock data,
    /// not just commodity futures.
    static let defaultStockSymbols: [String] = [
        // Mega-cap tech
        "AAPL", "MSFT", "GOOGL", "AMZN", "META", "TSLA", "NVDA",
        // Top ETFs
        "SPY", "QQQ", "VOO", "DIA", "IWM",
        // Finance
        "JPM", "V", "MA", "BAC", "GS",
        // Healthcare
        "UNH", "JNJ", "PFE", "LLY", "ABBV",
        // Consumer
        "WMT", "KO", "PG", "MCD", "NKE", "COST",
        // Industrials + Energy
        "HD", "CAT", "BA", "XOM", "CVX",
        // Other mega-caps
        "DIS", "NFLX", "AMD", "CRM", "ADBE", "PYPL",
    ]
    
    /// Refresh stock quotes for all cached symbols using Yahoo Finance (primary) or Finnhub
    func refreshQuotes() async {
        guard !isLoadingQuotes else { return }
        
        // Get all unique symbols from both cached stocks AND index constituents
        var allSymbols = Set(stocks.keys)
        allSymbols.formUnion(indexConstituents.values.flatMap { $0 })
        
        // FIX: Always include default stock symbols so the stock market section
        // has real stock data even without Finnhub API key. Without this, only
        // commodity futures load when the cache starts empty.
        allSymbols.formUnion(Self.defaultStockSymbols)
        
        // Also include commodity futures symbols for the commodities section
        allSymbols.formUnion(Self.commodityFuturesSymbols)
        
        guard !allSymbols.isEmpty else {
            logger.info("No symbols to refresh")
            return
        }
        
        isLoadingQuotes = true
        lastError = nil
        
        defer { isLoadingQuotes = false }
        
        // Batch the symbols to avoid rate limiting (50 per batch)
        let symbolArray = Array(allSymbols)
        let batchSize = 50
        var allYahooQuotes: [String: StockQuote] = [:]
        
        for batchStart in stride(from: 0, to: symbolArray.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, symbolArray.count)
            let batch = Array(symbolArray[batchStart..<batchEnd])
            
            let yahooQuotes = await StockPriceService.shared.fetchQuotes(tickers: batch)
            allYahooQuotes.merge(yahooQuotes) { _, new in new }
            
            // Small delay between batches
            if batchEnd < symbolArray.count {
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
            }
        }
        
        // Fallback to Finnhub for any missing symbols (if configured)
        var finnhubQuotes: [String: FinnhubQuote] = [:]
        if APIConfig.hasValidFinnhubKey {
            let missingSymbols = allSymbols.filter { allYahooQuotes[$0] == nil }
            if !missingSymbols.isEmpty {
                finnhubQuotes = await FinnhubService.shared.fetchQuotes(symbols: Array(missingSymbols))
            }
        }
        
        // Update cache - prefer Yahoo quotes (more data), fall back to Finnhub
        for symbol in allSymbols {
            if let yahooQuote = allYahooQuotes[symbol] {
                updateStock(symbol: symbol, from: yahooQuote)
            } else if let finnhubQuote = finnhubQuotes[symbol] {
                updateStock(symbol: symbol, from: finnhubQuote)
            }
        }
        
        lastQuoteUpdate = Date()
        saveStockCache()
        saveCacheMetadata()
        
        logger.info("Updated quotes for \(allYahooQuotes.count + finnhubQuotes.count) stocks (total symbols: \(allSymbols.count))")
    }
    
    /// Refresh quotes for specific symbols using Yahoo Finance
    func refreshQuotes(for symbols: [String]) async {
        guard !symbols.isEmpty else { return }
        
        // Use Yahoo Finance as primary source
        let quotes = await StockPriceService.shared.fetchQuotes(tickers: symbols)
        
        for (symbol, quote) in quotes {
            updateStock(symbol: symbol, from: quote)
        }
        
        saveStockCache()
    }
    
    // MARK: - Private Methods
    
    private func updateStock(symbol: String, from finnhubQuote: FinnhubQuote) {
        let existing = stocks[symbol]
        
        // VALIDATION: Don't overwrite valid prices with $0
        // If new price is 0 but we have a valid existing price, keep existing
        if finnhubQuote.currentPrice <= 0 && (existing?.currentPrice ?? 0) > 0 {
            logger.debug("Skipping $0 price update for \(symbol) - preserving existing \(existing?.currentPrice ?? 0)")
            return
        }
        
        // Determine asset type - prioritize commodity futures detection
        let assetType: AssetType = Self.commodityFuturesSymbols.contains(symbol)
            ? .commodity
            : existing?.assetType ?? .stock
        
        stocks[symbol] = CachedStock(
            symbol: symbol,
            name: existing?.name ?? symbol,
            currentPrice: finnhubQuote.currentPrice,
            change: finnhubQuote.change,
            changePercent: finnhubQuote.changePercent,
            dayHigh: finnhubQuote.dayHigh,
            dayLow: finnhubQuote.dayLow,
            previousClose: finnhubQuote.previousClose,
            marketCap: existing?.marketCap,
            volume: existing?.volume,
            assetType: assetType,
            exchange: existing?.exchange,
            sector: existing?.sector,
            lastUpdated: Date()
        )
    }
    
    private func updateStock(symbol: String, from yahooQuote: StockQuote) {
        let existing = stocks[symbol]
        
        // VALIDATION: Don't overwrite valid prices with $0
        // If new price is 0 but we have a valid existing price, keep existing
        if yahooQuote.regularMarketPrice <= 0 && (existing?.currentPrice ?? 0) > 0 {
            logger.debug("Skipping $0 price update for \(symbol) - preserving existing \(existing?.currentPrice ?? 0)")
            return
        }
        
        // Determine asset type - prioritize commodity futures detection
        let assetType: AssetType = Self.commodityFuturesSymbols.contains(symbol)
            ? .commodity
            : yahooQuote.assetType
        
        // Use existing values as fallback for missing data
        let price = yahooQuote.regularMarketPrice > 0 ? yahooQuote.regularMarketPrice : (existing?.currentPrice ?? 0)
        let change = yahooQuote.regularMarketChange ?? existing?.change ?? 0
        // Use API value if available, fallback to calculation from previousClose, or use existing.
        // VALIDATION: Sanity-check extreme single-day changes (>25% for blue-chip stocks is unusual)
        // to avoid stale/incorrect previousClose producing wild percentages.
        let changePercent: Double = {
            // Helper: clamp extreme values for non-commodity stocks (commodities can be more volatile)
            let isCommodity = Self.commodityFuturesSymbols.contains(symbol)
            let maxReasonable: Double = isCommodity ? 50.0 : 25.0
            
            func validated(_ pct: Double) -> Double? {
                guard pct.isFinite else { return nil }
                // If the change seems implausible for a blue-chip stock, it's likely a data issue
                // (e.g., wrong previousClose from a different date/split). Prefer existing cache.
                if !isCommodity && abs(pct) > maxReasonable && (existing?.changePercent ?? 0) != 0 {
                    // Only flag as suspicious for large-cap stocks where >25% single-day moves are extremely rare
                    #if DEBUG
                    print("⚠️ [StockMarketCache] \(symbol) change \(String(format: "%.1f", pct))% seems extreme, using cached \(String(format: "%.2f", existing?.changePercent ?? 0))%")
                    #endif
                    return nil // Fall through to existing value
                }
                return pct
            }
            
            if let apiChange = yahooQuote.regularMarketChangePercent,
               let v = validated(apiChange) {
                return v
            }
            if let prevClose = yahooQuote.regularMarketPreviousClose, prevClose > 0 {
                let calc = ((yahooQuote.regularMarketPrice - prevClose) / prevClose) * 100
                if let v = validated(calc) { return v }
            }
            return existing?.changePercent ?? 0
        }()
        
        stocks[symbol] = CachedStock(
            symbol: symbol,
            name: yahooQuote.displayName,
            currentPrice: price,
            change: change,
            changePercent: changePercent,
            dayHigh: yahooQuote.regularMarketDayHigh ?? existing?.dayHigh ?? 0,
            dayLow: yahooQuote.regularMarketDayLow ?? existing?.dayLow ?? 0,
            previousClose: yahooQuote.regularMarketPreviousClose ?? existing?.previousClose ?? 0,
            marketCap: yahooQuote.marketCap ?? existing?.marketCap,
            volume: yahooQuote.regularMarketVolume ?? existing?.volume,
            assetType: assetType,
            exchange: yahooQuote.exchange ?? existing?.exchange,
            sector: existing?.sector,
            lastUpdated: Date()
        )
    }
    
    private func updateMarketStatus() async {
        // Keep market-hours logic aligned with LiveStockPriceManager.
        let calendar = Calendar.current
        let now = Date()
        
        guard let eastern = TimeZone(identifier: "America/New_York") else {
            isMarketOpen = false
            return
        }
        
        let components = calendar.dateComponents(in: eastern, from: now)
        let weekday = components.weekday ?? 1
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        
        // Weekend check
        if weekday == 1 || weekday == 7 {
            isMarketOpen = false
            return
        }
        
        // Time check (9:30 AM - 4:00 PM ET)
        let isAfterOpen = hour > 9 || (hour == 9 && minute >= 30)
        let isBeforeClose = hour < 16
        
        if !(isAfterOpen && isBeforeClose) {
            isMarketOpen = false
            return
        }
        
        if isMarketHoliday(date: now, calendar: calendar, timezone: eastern) {
            isMarketOpen = false
            return
        }
        
        isMarketOpen = true
    }
    
    private func isMarketHoliday(date: Date, calendar: Calendar, timezone: TimeZone) -> Bool {
        var cal = calendar
        cal.timeZone = timezone
        
        let components = cal.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return false
        }
        
        // Major fixed-date holidays.
        let fixedHolidays: [(Int, Int)] = [
            (1, 1),   // New Year's Day
            (7, 4),   // Independence Day
            (12, 25)  // Christmas Day
        ]
        if fixedHolidays.contains(where: { $0.0 == month && $0.1 == day }) {
            return true
        }
        
        // Variable holidays.
        if month == 1, let mlkDay = nthWeekday(nth: 3, weekday: 2, month: 1, year: year, calendar: cal), cal.isDate(date, inSameDayAs: mlkDay) {
            return true
        }
        if month == 2, let presDay = nthWeekday(nth: 3, weekday: 2, month: 2, year: year, calendar: cal), cal.isDate(date, inSameDayAs: presDay) {
            return true
        }
        if month == 5, let memDay = lastWeekday(weekday: 2, month: 5, year: year, calendar: cal), cal.isDate(date, inSameDayAs: memDay) {
            return true
        }
        if month == 9, let laborDay = nthWeekday(nth: 1, weekday: 2, month: 9, year: year, calendar: cal), cal.isDate(date, inSameDayAs: laborDay) {
            return true
        }
        if month == 11, let thanksgiving = nthWeekday(nth: 4, weekday: 5, month: 11, year: year, calendar: cal), cal.isDate(date, inSameDayAs: thanksgiving) {
            return true
        }
        
        return false
    }
    
    private func nthWeekday(nth: Int, weekday: Int, month: Int, year: Int, calendar: Calendar) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.weekday = weekday
        components.weekdayOrdinal = nth
        return calendar.date(from: components)
    }
    
    private func lastWeekday(weekday: Int, month: Int, year: Int, calendar: Calendar) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month + 1
        components.day = 0 // Last day of previous month
        
        guard let lastDay = calendar.date(from: components) else { return nil }
        
        var currentDay = lastDay
        while calendar.component(.weekday, from: currentDay) != weekday {
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: currentDay) else {
                return nil
            }
            currentDay = previousDay
        }
        return currentDay
    }
    
    // MARK: - Persistence
    
    /// Cache metadata for tracking update times across app launches
    private struct CacheMetadata: Codable {
        var lastQuoteUpdate: Date?
        var lastIndexUpdate: Date?
        var lastFullRefresh: Date?
    }
    
    private func loadCachedData() {
        // Load stock cache
        if FileManager.default.fileExists(atPath: cacheFileURL.path) {
            do {
                let data = try Data(contentsOf: cacheFileURL)
                let cached = try decoder.decode([String: CachedStock].self, from: data)
                stocks = cached
                logger.info("Loaded \(cached.count) cached stocks from disk")
            } catch {
                logger.warning("Failed to load stock cache: \(error.localizedDescription)")
            }
        }
        
        // Load index cache
        if FileManager.default.fileExists(atPath: indexCacheFileURL.path) {
            do {
                let data = try Data(contentsOf: indexCacheFileURL)
                let cached = try decoder.decode([String: [String]].self, from: data)
                // Convert string keys back to StockIndex
                for (key, constituents) in cached {
                    if let index = StockIndex(rawValue: key) {
                        indexConstituents[index] = constituents
                    }
                }
                logger.info("Loaded index constituents for \(self.indexConstituents.count) indices")
            } catch {
                logger.warning("Failed to load index cache: \(error.localizedDescription)")
            }
        }
    }
    
    /// PERFORMANCE FIX: Async version that performs disk I/O on background queue
    private func loadCachedDataAsync() async {
        let stocksURL = cacheFileURL
        let indexURL = indexCacheFileURL
        let dec = decoder
        
        // Load data on background queue
        let (loadedStocks, loadedIndex): ([String: CachedStock], [String: [String]]?) = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var stocks: [String: CachedStock] = [:]
                var indexData: [String: [String]]? = nil
                
                // Load stock cache
                if FileManager.default.fileExists(atPath: stocksURL.path) {
                    if let data = try? Data(contentsOf: stocksURL),
                       let cached = try? dec.decode([String: CachedStock].self, from: data) {
                        stocks = cached
                    }
                }
                
                // Load index cache
                if FileManager.default.fileExists(atPath: indexURL.path) {
                    if let data = try? Data(contentsOf: indexURL),
                       let cached = try? dec.decode([String: [String]].self, from: data) {
                        indexData = cached
                    }
                }
                
                continuation.resume(returning: (stocks, indexData))
            }
        }
        
        // Update on main actor
        await MainActor.run {
            if !loadedStocks.isEmpty {
                self.stocks = loadedStocks
                self.logger.info("Loaded \(loadedStocks.count) cached stocks from disk (async)")
            }
            
            if let indexData = loadedIndex {
                for (key, constituents) in indexData {
                    if let index = StockIndex(rawValue: key) {
                        self.indexConstituents[index] = constituents
                    }
                }
                self.logger.info("Loaded index constituents for \(self.indexConstituents.count) indices (async)")
            }
        }
    }
    
    private func loadCacheMetadata() {
        guard FileManager.default.fileExists(atPath: metadataFileURL.path) else { return }
        
        do {
            let data = try Data(contentsOf: metadataFileURL)
            let metadata = try decoder.decode(CacheMetadata.self, from: data)
            lastQuoteUpdate = metadata.lastQuoteUpdate
            lastIndexUpdate = metadata.lastIndexUpdate
            lastFullRefresh = metadata.lastFullRefresh
            logger.info("Loaded cache metadata - last update: \(String(describing: metadata.lastQuoteUpdate))")
        } catch {
            logger.warning("Failed to load cache metadata: \(error.localizedDescription)")
        }
    }
    
    /// PERFORMANCE FIX: Async version that performs disk I/O on background queue
    private func loadCacheMetadataAsync() async {
        let metaURL = metadataFileURL
        let dec = decoder
        
        let loadedMeta: CacheMetadata? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard FileManager.default.fileExists(atPath: metaURL.path) else {
                    continuation.resume(returning: nil)
                    return
                }
                
                if let data = try? Data(contentsOf: metaURL),
                   let metadata = try? dec.decode(CacheMetadata.self, from: data) {
                    continuation.resume(returning: metadata)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
        
        if let metadata = loadedMeta {
            await MainActor.run {
                self.lastQuoteUpdate = metadata.lastQuoteUpdate
                self.lastIndexUpdate = metadata.lastIndexUpdate
                self.lastFullRefresh = metadata.lastFullRefresh
                self.logger.info("Loaded cache metadata (async) - last update: \(String(describing: metadata.lastQuoteUpdate))")
            }
        }
    }
    
    // PERFORMANCE FIX: Save functions now use background queue to avoid blocking main thread
    private func saveStockCache() {
        let stocksToSave = stocks
        let url = cacheFileURL
        let enc = encoder
        
        DispatchQueue.global(qos: .utility).async {
            do {
                let data = try enc.encode(stocksToSave)
                try data.write(to: url, options: .atomic)
            } catch {
                #if DEBUG
                print("Failed to save stock cache: \(error.localizedDescription)")
                #endif
            }
        }
    }
    
    private func saveIndexCache() {
        let indexToSave = indexConstituents
        let url = indexCacheFileURL
        let enc = encoder
        
        DispatchQueue.global(qos: .utility).async {
            do {
                // Convert StockIndex keys to strings for encoding
                let stringKeyed = Dictionary(uniqueKeysWithValues: indexToSave.map { ($0.key.rawValue, $0.value) })
                let data = try enc.encode(stringKeyed)
                try data.write(to: url, options: .atomic)
            } catch {
                #if DEBUG
                print("Failed to save index cache: \(error.localizedDescription)")
                #endif
            }
        }
    }
    
    private func saveCacheMetadata() {
        do {
            let metadata = CacheMetadata(
                lastQuoteUpdate: lastQuoteUpdate,
                lastIndexUpdate: lastIndexUpdate,
                lastFullRefresh: lastFullRefresh
            )
            let data = try encoder.encode(metadata)
            try data.write(to: metadataFileURL, options: .atomic)
        } catch {
            logger.warning("Failed to save cache metadata: \(error.localizedDescription)")
        }
    }
    
    /// Clear all cached data
    func clearCache() {
        stocks.removeAll()
        indexConstituents.removeAll()
        lastIndexUpdate = nil
        lastQuoteUpdate = nil
        lastFullRefresh = nil
        
        try? FileManager.default.removeItem(at: cacheFileURL)
        try? FileManager.default.removeItem(at: indexCacheFileURL)
        try? FileManager.default.removeItem(at: metadataFileURL)
        
        logger.info("Cleared stock market cache")
    }
    
    /// Update a single stock in the cache (for external updates)
    func updateStock(_ stock: CachedStock) {
        stocks[stock.symbol] = stock
    }
    
    /// Update multiple stocks in the cache (for external updates)
    func updateStocks(_ newStocks: [String: CachedStock]) {
        for (symbol, stock) in newStocks {
            stocks[symbol] = stock
        }
    }
    
    /// Set index constituents (for external updates)
    func setIndexConstituents(_ index: StockIndex, symbols: [String]) {
        indexConstituents[index] = symbols
    }
}

// MARK: - Sort Options

enum StockSortOption: String, CaseIterable {
    case changePercent = "Change %"
    case price = "Price"
    case marketCap = "Market Cap"
    case name = "Name"
    case symbol = "Symbol"
    
    var icon: String {
        switch self {
        case .changePercent: return "chart.line.uptrend.xyaxis"
        case .price: return "dollarsign.circle"
        case .marketCap: return "building.2"
        case .name: return "textformat.abc"
        case .symbol: return "number"
        }
    }
}

