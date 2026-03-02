//
//  CryptoAPIService.swift
//  CryptoSage
//

import Foundation
import Combine
import Network
import os

/// Monitors network connectivity using NWPathMonitor
final class NetworkMonitor {
    static let shared = NetworkMonitor()
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    private(set) var isOnline: Bool = false

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.isOnline = (path.status == .satisfied)
        }
        monitor.start(queue: queue)
        isOnline = monitor.currentPath.status == .satisfied
    }
    /// Live-updating publisher for market data (top-20 + watchlist) on a timer.
    @MainActor
    func liveMarketDataPublisher(visibleIDs: [String], interval: TimeInterval = 45) -> AnyPublisher<(allCoins: [MarketCoin], watchlistCoins: [MarketCoin]), Never> {
        Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .prepend(Date())
            .flatMap { _ in
                Future { promise in
                    Task {
                        let idMap = LivePriceManager.shared.geckoIDMap
                        let mappedIDs = visibleIDs.map { idMap[$0.lowercased()] ?? $0.lowercased() }
                        do {
                            let result = try await CryptoAPIService.shared.fetchAllAndWatchlist(visibleIDs: mappedIDs)
                            promise(.success(result))
                        } catch {
                            #if DEBUG
                            print("❌ [CryptoAPIService] liveMarketDataPublisher error:", error)
                            #endif
                            promise(.success((allCoins: [], watchlistCoins: [])))
                        }
                    }
                }
            }
            .scan((allCoins: [MarketCoin](), watchlistCoins: [MarketCoin]())) { last, next in
                // Keep last non-empty tick to avoid UI flicker on transient failures
                if next.allCoins.isEmpty && next.watchlistCoins.isEmpty { return last }
                return next
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    /// Closure-based wrapper for async fetchCoins(ids:)
    func fetchMarketData(ids: [String], completion: @escaping ([MarketCoin]) -> Void) {
        Task {
            let markets = await CryptoAPIService.shared.fetchCoins(ids: ids)
            DispatchQueue.main.async {
                completion(markets)
            }
        }
    }

    /// Closure-based wrapper for async fetchSpotPrice(coin:)
    func fetchSpotPrice(coin: String, completion: @escaping (Double) -> Void) {
        Task {
            let price: Double
            do {
                price = try await CryptoAPIService.shared.fetchSpotPrice(coin: coin)
            } catch {
                price = 0
            }
            DispatchQueue.main.async {
                completion(price)
            }
        }
    }
}

/// Builds a URL for fetching price history for a given coin and timeframe.
extension CryptoAPIService {
    static func buildPriceHistoryURL(
        for coinID: String,
        timeframe: ChartTimeframe
    ) -> URL? {
        var daysParam: String
        switch timeframe {
        case .oneDay, .live:
            daysParam = "1"
        case .oneWeek:
            daysParam = "7"
        case .oneMonth:
            daysParam = "30"
        case .threeMonths:
            daysParam = "90"
        case .oneYear:
            daysParam = "365"
        case .allTime:
            daysParam = "max"
        default:
            daysParam = "1"
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.coingecko.com"
        components.path = "/api/v3/coins/\(coinID)/market_chart"
        let currency = CurrencyManager.apiValue
        components.queryItems = [
            URLQueryItem(name: "vs_currency", value: currency),
            URLQueryItem(name: "days", value: daysParam)
        ]
        return components.url
    }
    
    struct MarketChartResponse: Decodable { let prices: [[Double]] }

    /// Fetch price history (prices only) for charts. Returns an array of price values ordered by time.
    func fetchPriceHistory(coinID: String, timeframe: ChartTimeframe) async -> [Double] {
        // Map incoming symbol or ID to a proper CoinGecko ID to avoid missing data when callers pass symbols
        let mappedID: String = {
            // If already looks like a Gecko ID (lowercased slug with a dash), keep it
            let trimmed = coinID.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains("-") && trimmed.lowercased() == trimmed { return trimmed }
            // Else map common tickers via our helper
            return coingeckoID(for: trimmed)
        }()
        guard NetworkMonitor.shared.isOnline, let url = Self.buildPriceHistoryURL(for: mappedID, timeframe: timeframe) else {
            return []
        }
        let request = Self.makeRequest(url)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if Self.isRateLimited(response, data: data) { return [] }
            let resp = try JSONDecoder().decode(MarketChartResponse.self, from: data)
            let prices = resp.prices.compactMap { $0.count >= 2 ? $0[1] : nil }
            // Basic quality check to avoid plotting junk
            if prices.count < 7 { return [] }
            return prices
        } catch {
            return []
        }
    }
}

/// Error thrown when the API returns a rate-limit status (HTTP 429).
enum CryptoAPIError: LocalizedError {
    case rateLimited
    case badServerResponse(statusCode: Int)
    case firebaseNotConfigured
    case networkUnavailable
    case invalidResponse
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .rateLimited:
            return "Rate limit exceeded. Please try again in a few moments."
        case .badServerResponse(let statusCode):
            return "Server error (code \(statusCode)). Please try again later."
        case .firebaseNotConfigured:
            return "Firebase is not configured. Using direct API."
        case .networkUnavailable:
            return "No internet connection. Please check your network and try again."
        case .invalidResponse:
            return "Received invalid data from server. Please try again."
        case .decodingFailed:
            return "Failed to process server response. Please try again."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .rateLimited:
            return "The app has made too many requests. Wait a moment and try again."
        case .badServerResponse:
            return "The server encountered an issue. This is usually temporary."
        case .networkUnavailable:
            return "Make sure you're connected to the internet via WiFi or cellular data."
        case .invalidResponse, .decodingFailed:
            return "This may be a temporary issue. Please try refreshing the data."
        case .firebaseNotConfigured:
            return nil
        }
    }
}

/// Service wrapper for CoinGecko API calls
final class CryptoAPIService {
    static let shared = CryptoAPIService()
    // Startup cap for normal runtime behavior.
    private static let maxMarketCoinsForStartup = 250
    
    // MARK: - Debug Logging
    // Set to true to enable verbose cache loading logs (useful for debugging, noisy in production)
    #if DEBUG
    private static let verboseCacheLogging = false
    #else
    private static let verboseCacheLogging = false
    #endif
    
    // Rate-limit cooldowns to avoid hammering CoinGecko when throttled
    private static var lastMarketsRateLimitAt: Date? = nil
    private static let marketsRateLimitCooldown: TimeInterval = 120 // seconds
    private static var lastGlobalRateLimitAt: Date? = nil
    private static let globalRateLimitCooldown: TimeInterval = 300 // seconds
    
    // DEPRECATED: Old inflight guard replaced by Task-based deduplication (see inFlightMarketRequests)
    // Keeping for backward compatibility but no longer used
    private static var lastRateLimitLogAt: Date? = nil
    
    // PERFORMANCE FIX: Rate-limited logging for repetitive messages
    private static var _logTimes: [String: Date] = [:]
    private static let _logLock = NSLock()
    private static func rateLimitedLog(_ key: String, _ message: String, minInterval: TimeInterval = 30.0) {
        _logLock.lock()
        defer { _logLock.unlock() }
        let now = Date()
        if let last = _logTimes[key], now.timeIntervalSince(last) < minInterval {
            return
        }
        _logTimes[key] = now
        #if DEBUG
        print(message)
        #endif
    }

    // MARK: - In-Memory Cache for loadCachedMarketCoins
    // Prevents repeated disk I/O during startup when the function is called many times
    private var inMemoryCachedCoins: [MarketCoin]?
    private var inMemoryCacheTimestamp: Date?
    private let inMemoryCacheValiditySeconds: TimeInterval = 5.0
    
    /// Invalidates the in-memory coins cache, forcing the next loadCachedMarketCoins() to read from disk
    func invalidateInMemoryCoinsCache() {
        inMemoryCachedCoins = nil
        inMemoryCacheTimestamp = nil
    }
    
    // MARK: - In-Flight Request Deduplication (PERFORMANCE FIX)
    // Prevents multiple concurrent requests for the same endpoint/coin
    // Multiple callers can share the same Task result, reducing redundant API calls
    
    private var inFlightSpotPriceRequests: [String: Task<Double, Error>] = [:]
    private let inFlightLock = NSLock()
    
    // REQUEST DEDUPLICATION: Track inflight market requests by endpoint key
    // This allows multiple callers to share the same result without duplicate API calls
    private var inFlightMarketRequests: [String: Task<[MarketCoin], Error>] = [:]
    private let marketRequestsLock = NSLock()
    
    // REQUEST DEDUPLICATION: Track inflight fetchCoins(ids:) requests by sorted ID list
    private var inFlightCoinsByIdRequests: [String: Task<[MarketCoin], Never>] = [:]
    private let coinsByIdLock = NSLock()
    
    // PERFORMANCE FIX: Throttle logging to prevent console spam
    private var lastInFlightLogTime: [String: Date] = [:]
    private let logThrottleInterval: TimeInterval = 120 // Only log once per 2 minutes per coinID
    
    // MARK: - Request Deduplication Statistics (for monitoring)
    private(set) var deduplicationStats = DeduplicationStats()
    
    struct DeduplicationStats {
        var totalRequests: Int = 0
        var deduplicatedRequests: Int = 0
        var savedRequests: Int { deduplicatedRequests }
        
        mutating func recordRequest(deduplicated: Bool) {
            totalRequests += 1
            if deduplicated { deduplicatedRequests += 1 }
        }
        
        var description: String {
            guard totalRequests > 0 else { return "No requests yet" }
            let pct = Double(deduplicatedRequests) / Double(totalRequests) * 100
            return "Total: \(totalRequests), Saved: \(deduplicatedRequests) (\(String(format: "%.1f", pct))%)"
        }
    }

    // Centralized request setup and rate-limit detection
    private static func makeRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("CryptoSage/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        // RATE LIMIT FIX: Add CoinGecko Demo API key for higher rate limits (30/min vs 10/min)
        // This is the fallback path when Firestore pipeline data is stale
        if let host = url.host, host.contains("coingecko.com") {
            request.setValue(APIConfig.coingeckoDemoAPIKey, forHTTPHeaderField: "x-cg-demo-api-key")
        }
        return request
    }

    private static func isRateLimited(_ response: URLResponse?, data: Data) -> Bool {
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 429 { return true }
            if let remaining = http.value(forHTTPHeaderField: "x-ratelimit-remaining"), remaining.trimmingCharacters(in: .whitespacesAndNewlines) == "0" {
                return true
            }
        }
        if let snippet = String(data: data.prefix(200), encoding: .utf8), snippet.contains("\"error_code\":429") {
            return true
        }
        return false
    }
    
    // MARK: - Page-Level Caching for Pagination
    
    /// Page cache expiration: cached pages are valid for 30 minutes
    private static let pageCacheMaxAge: TimeInterval = 30 * 60
    
    /// Cache version suffix - increment when changing per_page count to avoid stale data
    private static let pageCacheVersion = "v2_250" // v2 with 250 per page
    
    /// Wrapper to store page data with timestamp
    private struct PageCacheEntry: Codable {
        let coins: [MarketCoin]
        let timestamp: Date
    }
    
    /// Save a page of coins to persistent cache
    static func savePageCache(page: Int, coins: [MarketCoin]) {
        let entry = PageCacheEntry(coins: coins, timestamp: Date())
        let fileName = "coins_page_\(page)_\(pageCacheVersion)_cache.json"
        saveCache(entry, to: fileName)
    }
    
    /// Load a page of coins from cache if still fresh
    static func loadPageCache(page: Int) -> [MarketCoin]? {
        let fileName = "coins_page_\(page)_\(pageCacheVersion)_cache.json"
        guard let entry: PageCacheEntry = loadCache(from: fileName, as: PageCacheEntry.self) else {
            return nil
        }
        // Check if cache is still fresh
        let age = Date().timeIntervalSince(entry.timestamp)
        if age > pageCacheMaxAge {
            return nil // Cache expired
        }
        return entry.coins
    }
    
    /// Clear all page caches (useful for force refresh)
    /// Clears both old v1 caches and new versioned caches
    static func clearPageCaches() {
        let fileManager = FileManager.default
        guard let docsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        // Clear old v1 format caches (100 per page)
        for page in 1...10 {
            let oldFileName = "coins_page_\(page)_cache.json"
            let oldFileURL = docsURL.appendingPathComponent(oldFileName)
            try? fileManager.removeItem(at: oldFileURL)
        }
        // Clear new versioned caches (250 per page)
        for page in 1...5 {
            let newFileName = "coins_page_\(page)_\(pageCacheVersion)_cache.json"
            let newFileURL = docsURL.appendingPathComponent(newFileName)
            try? fileManager.removeItem(at: newFileURL)
        }
    }
    
    /// Curated top IDs to ensure we can always display a healthy market list when the API is rate-limited or caches are empty.
    private static let fallbackTopIDs: [String] = [
        "bitcoin","ethereum","solana","tether","binancecoin","ripple","usd-coin",
        "staked-ether","cardano","dogecoin","tron","the-open-network","polkadot",
        "avalanche-2","matic-network","chainlink","litecoin","bitcoin-cash","uniswap",
        "stellar","near","internet-computer","aptos","arbitrum","optimism","sui",
        "filecoin","hedera","render-token","aave","kaspa","bittensor","qnt","fetch-ai",
        "injective-protocol","maker","seirei","celestia","gala","algorand"
    ]

    /// Fallback fetch for a stable set of top markets by explicit IDs.
    private func fetchFallbackTopMarkets() async -> [MarketCoin] {
        if Self.verboseCacheLogging {
            #if DEBUG
            print("[CryptoAPIService] Curated top-ID fallback disabled (live-only policy)")
            #endif
        }
        return []
    }
    
    // MARK: - Firebase Proxy Methods
    
    /// Fetches market coins via Firebase proxy (shared cache across all users)
    /// This solves rate limiting issues at scale - 1000 users share the same cached response
    private func fetchMarketsViaFirebase() async throws -> [MarketCoin] {
        guard await FirebaseService.shared.isConfigured else {
            throw CryptoAPIError.firebaseNotConfigured
        }
        
        // Fetch only the capped startup set to avoid decoding/retaining oversized payloads.
        let response = try await FirebaseService.shared.getCoinGeckoMarkets(
            page: 1,
            perPage: Self.maxMarketCoinsForStartup,
            sparkline: true
        )
        
        // Convert Firebase response to [MarketCoin]
        let coins = Array(convertFirebaseCoinsToMarketCoins(response.coins).prefix(Self.maxMarketCoinsForStartup))
        
        // DIAGNOSTIC: Log how many coins have percentage data
        #if DEBUG
        let with1h = coins.filter { $0.priceChangePercentage1hInCurrency != nil }.count
        let with24h = coins.filter { $0.priceChangePercentage24hInCurrency != nil }.count
        let with7d = coins.filter { $0.priceChangePercentage7dInCurrency != nil }.count
        if with1h > 0 || with24h > 0 {
            print("[CryptoAPIService] Percent coverage: 1h=\(with1h), 24h=\(with24h), 7d=\(with7d) of \(coins.count) coins")
        }
        
        if response.stale == true {
            print("[CryptoAPIService] source=firebase_proxy stale=true - forcing direct API fallback")
            throw CryptoAPIError.rateLimited
        }
        #endif
        
        return coins
    }
    
    /// Converts Firebase's [[String: AnyCodable]] response to [MarketCoin]
    private func convertFirebaseCoinsToMarketCoins(_ rawCoins: [[String: AnyCodable]]) -> [MarketCoin] {
        var coins: [MarketCoin] = []
        
        for rawCoin in rawCoins {
            guard let id = rawCoin["id"]?.value as? String,
                  let symbol = rawCoin["symbol"]?.value as? String,
                  let name = rawCoin["name"]?.value as? String else {
                continue
            }
            
            let imageUrl: URL? = {
                if let imageStr = rawCoin["image"]?.value as? String {
                    return URL(string: imageStr)
                }
                return nil
            }()
            
            let currentPrice = (rawCoin["current_price"]?.value as? Double) ?? (rawCoin["currentPrice"]?.value as? Double)
            let marketCap = (rawCoin["market_cap"]?.value as? Double) ?? (rawCoin["marketCap"]?.value as? Double)
            let totalVolume = (rawCoin["total_volume"]?.value as? Double) ?? (rawCoin["totalVolume"]?.value as? Double)
            let marketCapRank = (rawCoin["market_cap_rank"]?.value as? Int) ?? (rawCoin["marketCapRank"]?.value as? Int)
            let maxSupply = (rawCoin["max_supply"]?.value as? Double) ?? (rawCoin["maxSupply"]?.value as? Double)
            let circulatingSupply = (rawCoin["circulating_supply"]?.value as? Double) ?? (rawCoin["circulatingSupply"]?.value as? Double)
            let totalSupply = (rawCoin["total_supply"]?.value as? Double) ?? (rawCoin["totalSupply"]?.value as? Double)
            
            // Extract percentage changes (try both snake_case and camelCase)
            let pct1h = (rawCoin["price_change_percentage_1h_in_currency"]?.value as? Double) ?? 
                        (rawCoin["priceChangePercentage1hInCurrency"]?.value as? Double) ??
                        (rawCoin["price_change_percentage_1h"]?.value as? Double)
            let pct24h = (rawCoin["price_change_percentage_24h_in_currency"]?.value as? Double) ?? 
                         (rawCoin["priceChangePercentage24hInCurrency"]?.value as? Double) ??
                         (rawCoin["price_change_percentage_24h"]?.value as? Double)
            let pct7d = (rawCoin["price_change_percentage_7d_in_currency"]?.value as? Double) ?? 
                        (rawCoin["priceChangePercentage7dInCurrency"]?.value as? Double) ??
                        (rawCoin["price_change_percentage_7d"]?.value as? Double)
            
            // Extract sparkline
            var sparkline: [Double] = []
            if let sparklineObj = rawCoin["sparkline_in_7d"]?.value as? [String: Any],
               let priceArr = sparklineObj["price"] as? [Double] {
                sparkline = priceArr
            } else if let sparklineObj = rawCoin["sparklineIn7d"]?.value as? [String: Any],
                      let priceArr = sparklineObj["price"] as? [Double] {
                sparkline = priceArr
            }
            
            let coin = MarketCoin(
                id: id,
                symbol: symbol,
                name: name,
                imageUrl: imageUrl,
                priceUsd: currentPrice,
                marketCap: marketCap,
                totalVolume: totalVolume,
                priceChangePercentage1hInCurrency: pct1h,
                priceChangePercentage24hInCurrency: pct24h,
                priceChangePercentage7dInCurrency: pct7d,
                sparklineIn7d: sparkline,
                marketCapRank: marketCapRank,
                maxSupply: maxSupply,
                circulatingSupply: circulatingSupply,
                totalSupply: totalSupply
            )
            coins.append(coin)
        }
        
        return coins
    }
    
    /// Fetches global market data via Firebase proxy (shared cache across all users)
    private func fetchGlobalViaFirebase() async throws -> GlobalMarketData {
        guard await FirebaseService.shared.isConfigured else {
            throw CryptoAPIError.firebaseNotConfigured
        }
        
        let response = try await FirebaseService.shared.getCoinGeckoGlobal()
        
        // Convert Firebase response to GlobalMarketData
        let globalData = convertFirebaseGlobalToGlobalMarketData(response.global)
        
        if response.stale == true {
            #if DEBUG
            print("[CryptoAPIService] Firebase returned stale global data (cache hit during rate limit)")
            #endif
        }
        
        return globalData
    }
    
    /// Converts Firebase's [String: AnyCodable] response to GlobalMarketData
    private func convertFirebaseGlobalToGlobalMarketData(_ rawGlobal: [String: AnyCodable]) -> GlobalMarketData {
        // Extract dictionaries for market cap and volume (or create from single values)
        let totalMarketCapDict: [String: Double] = {
            if let dict = rawGlobal["total_market_cap"]?.value as? [String: Double] {
                return dict
            } else if let dict = rawGlobal["total_market_cap"]?.value as? [String: Any] {
                var result: [String: Double] = [:]
                for (key, value) in dict {
                    if let d = value as? Double { result[key] = d }
                    else if let n = value as? NSNumber { result[key] = n.doubleValue }
                }
                return result
            }
            return [:]
        }()
        
        let totalVolumeDict: [String: Double] = {
            if let dict = rawGlobal["total_volume"]?.value as? [String: Double] {
                return dict
            } else if let dict = rawGlobal["total_volume"]?.value as? [String: Any] {
                var result: [String: Double] = [:]
                for (key, value) in dict {
                    if let d = value as? Double { result[key] = d }
                    else if let n = value as? NSNumber { result[key] = n.doubleValue }
                }
                return result
            }
            return [:]
        }()
        
        let marketCapPercentage: [String: Double] = {
            if let dict = rawGlobal["market_cap_percentage"]?.value as? [String: Double] {
                return dict
            } else if let dict = rawGlobal["market_cap_percentage"]?.value as? [String: Any] {
                var result: [String: Double] = [:]
                for (key, value) in dict {
                    if let d = value as? Double { result[key] = d }
                    else if let n = value as? NSNumber { result[key] = n.doubleValue }
                }
                return result
            }
            return [:]
        }()
        
        let activeCryptocurrencies = rawGlobal["active_cryptocurrencies"]?.value as? Int ?? 0
        let markets = rawGlobal["markets"]?.value as? Int ?? 0
        let marketCapChangePercentage24hUsd = rawGlobal["market_cap_change_percentage_24h_usd"]?.value as? Double ?? 0
        
        return GlobalMarketData(
            totalMarketCap: totalMarketCapDict,
            totalVolume: totalVolumeDict,
            marketCapPercentage: marketCapPercentage,
            marketCapChangePercentage24HUsd: marketCapChangePercentage24hUsd,
            activeCryptocurrencies: activeCryptocurrencies,
            markets: markets
        )
    }
    
    private init() {}
    
    // MEMORY FIX v12: Track app launch time to defer multi-page fetching during startup.
    // During the first 60 seconds, only page 1 is fetched; pages 2-10 are deferred.
    // This prevents the concurrent data loading storm that causes 200MB→2GB memory explosion.
    private static let launchTime = Date()
    private static let startupPageFetchDeferralPeriod: TimeInterval = 60
    
    /// True if the app is still in the startup window where multi-page fetching should be deferred.
    private static var isInStartupDeferralWindow: Bool {
        Date().timeIntervalSince(launchTime) < startupPageFetchDeferralPeriod
    }
    
    /// Filters a list of coins by matching the provided raw IDs or symbols (case-insensitive),
    /// mapping raw ticker symbols to CoinGecko IDs first.
    private func filterCoins(_ coins: [MarketCoin], matching rawIDs: [String]) -> [MarketCoin] {
        let mappedIDs = rawIDs.map { coingeckoID(for: $0).lowercased() }
        let idSet = Set(mappedIDs)
        let symSet = Set(rawIDs.map { $0.lowercased() })
        return coins.filter { idSet.contains($0.id.lowercased()) || symSet.contains($0.symbol.lowercased()) }
    }

    /// Loads coins directly from bundled cache (ignoring Documents cache)
    private func loadBundledCoins() -> [MarketCoin]? {
        // Live-integrity mode: never promote bundled market payload to runtime market data.
        return nil
    }
    
    private func loadCachedMarketCoins() -> [MarketCoin]? {
        // Check in-memory cache first to avoid repeated disk I/O
        if let cached = inMemoryCachedCoins,
           let timestamp = inMemoryCacheTimestamp,
           Date().timeIntervalSince(timestamp) < inMemoryCacheValiditySeconds {
            return cached
        }
        
        // Helper to store result in in-memory cache before returning
        func cacheAndReturn(_ coins: [MarketCoin]?) -> [MarketCoin]? {
            if let coins = coins {
                inMemoryCachedCoins = coins
                inMemoryCacheTimestamp = Date()
            }
            return coins
        }
        
        // Minimum viable cache size to consider as a valid "All" market list
        let minCount = 20
        
        // Load from bundled cache first to get the baseline
        let bundledCoins = loadBundledCoins()
        let bundledCount = bundledCoins?.count ?? 0

        // Try decoding from Documents/Cache as [MarketCoin] first
        if let direct: [MarketCoin] = loadCache(from: "coins_cache.json", as: [MarketCoin].self), direct.count >= minCount {
            // Validate data quality - if corrupted, clear and use bundle
            if !isDataValid(direct) {
                clearCoinsCache()
                if let bundled = bundledCoins, bundled.count >= minCount {
                    #if DEBUG
                if Self.verboseCacheLogging { print("[loadCachedMarketCoins] Documents cache corrupted, using bundled cache with \(bundled.count) coins") }
                #endif
                    return cacheAndReturn(bundled)
                }
            }
            // If Documents has FEWER coins than bundle, merge them or prefer bundle
            if direct.count < bundledCount, let bundled = bundledCoins {
                #if DEBUG
                if Self.verboseCacheLogging { print("[loadCachedMarketCoins] Documents cache (\(direct.count) coins) smaller than bundle (\(bundledCount)), using bundle") }
                #endif
                return cacheAndReturn(bundled)
            }
            return cacheAndReturn(direct)
        }
        // Fallback: decode raw CoinGeckoCoin array and map
        if let raw: [CoinGeckoCoin] = loadCache(from: "coins_cache.json", as: [CoinGeckoCoin].self) {
            let mapped = raw.map { MarketCoin(gecko: $0) }
            if mapped.count >= minCount {
                // Validate data quality
                if !isDataValid(mapped) {
                    clearCoinsCache()
                    if let bundled = bundledCoins, bundled.count >= minCount {
                        #if DEBUG
                if Self.verboseCacheLogging { print("[loadCachedMarketCoins] Documents cache corrupted, using bundled cache with \(bundled.count) coins") }
                #endif
                        return cacheAndReturn(bundled)
                    }
                }
                if mapped.count < bundledCount, let bundled = bundledCoins {
                    #if DEBUG
                if Self.verboseCacheLogging { print("[loadCachedMarketCoins] Documents cache (\(mapped.count) coins) smaller than bundle (\(bundledCount)), using bundle") }
                #endif
                    return cacheAndReturn(bundled)
                }
                return cacheAndReturn(mapped)
            }
        }
        
        // No valid Documents cache - use bundled cache
        if let bundled = bundledCoins, bundled.count >= minCount {
            #if DEBUG
            if Self.verboseCacheLogging { print("[loadCachedMarketCoins] Using bundled cache with \(bundled.count) coins") }
            #endif
            return cacheAndReturn(bundled)
        }
        
        // Also allow watchlist cache to backfill when full cache is missing
        if let wlDirect: [MarketCoin] = loadCache(from: "watchlist_cache.json", as: [MarketCoin].self), wlDirect.count >= minCount {
            return cacheAndReturn(wlDirect)
        }
        if let wlRaw: [CoinGeckoCoin] = loadCache(from: "watchlist_cache.json", as: [CoinGeckoCoin].self) {
            let mapped = wlRaw.map { MarketCoin(gecko: $0) }
            if mapped.count >= minCount { return cacheAndReturn(mapped) }
        }
        // MIGRATION: Some older builds saved Data as a JSON string (base64). Detect and repair.
        if let data = loadRawCacheData("coins_cache.json"),
           let asString = String(data: data, encoding: .utf8),
           asString.first == "\"", asString.last == "\"" {
            // Strip surrounding quotes and unescape
            let trimmed = String(asString.dropFirst().dropLast())
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\\"", with: "\"")
            if let repairedData = trimmed.data(using: .utf8) {
                // Try decoding repairedData into gecko coins first
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                if let geckoCoins = try? decoder.decode([CoinGeckoCoin].self, from: repairedData) {
                    let mapped = geckoCoins.map { MarketCoin(gecko: $0) }
                    if mapped.count >= minCount {
                        saveCache(repairedData, to: "coins_cache.json")
                        return cacheAndReturn(mapped)
                    }
                }
                if let marketCoins = try? JSONDecoder().decode([MarketCoin].self, from: repairedData), marketCoins.count >= minCount {
                    saveCache(repairedData, to: "coins_cache.json")
                    return cacheAndReturn(marketCoins)
                }
            }
        }
        return nil
    }
    
    /// Checks if coin data looks corrupted (e.g., Bitcoin priced at ~$1 instead of >$10,000)
    /// Returns true if data seems valid, false if obviously corrupted
    private func isDataValid(_ coins: [MarketCoin]) -> Bool {
        // Find Bitcoin in the list
        guard let btc = coins.first(where: { $0.symbol.uppercased() == "BTC" || $0.id == "bitcoin" }) else {
            // No Bitcoin - can't validate, assume okay
            return true
        }
        
        // Bitcoin should be worth at least $10,000 - if it's showing ~$1, data is corrupted
        if let price = btc.priceUsd, price < 100 {
            #if DEBUG
            print("[isDataValid] CORRUPTED DATA DETECTED: Bitcoin price is $\(price) - clearing cache")
            #endif
            return false
        }
        
        // Check if too many coins have ~$1 prices (suggests stablecoin-only data)
        let suspiciousCount = coins.filter { coin in
            if let p = coin.priceUsd, p >= 0.95 && p <= 1.05 { return true }
            return false
        }.count
        
        let suspiciousRatio = Double(suspiciousCount) / Double(max(1, coins.count))
        if suspiciousRatio > 0.5 && coins.count > 20 {
            #if DEBUG
            print("[isDataValid] CORRUPTED DATA DETECTED: \(Int(suspiciousRatio * 100))% of coins have ~$1 prices")
            #endif
            return false
        }
        
        return true
    }
    
    /// Clears the Documents directory coins cache (corrupted data)
    private func clearCoinsCache() {
        // Also invalidate in-memory cache
        invalidateInMemoryCoinsCache()
        
        // SAFETY FIX: Use safe directory accessor instead of force unwrap
        let fileManager = FileManager.default
        let documentsURL = FileManager.documentsDirectory
        let cacheURL = documentsURL.appendingPathComponent("coins_cache.json")
        
        if fileManager.fileExists(atPath: cacheURL.path) {
            do {
                try fileManager.removeItem(at: cacheURL)
                #if DEBUG
                print("[clearCoinsCache] Removed corrupted coins_cache.json from Documents")
                #endif
            } catch {
                #if DEBUG
                print("[clearCoinsCache] Failed to remove cache: \(error)")
                #endif
            }
        }
        
        // Also clear page caches
        for page in 1...8 {
            let pageURL = documentsURL.appendingPathComponent("coins_page_\(page)_cache_v2_250.json")
            try? fileManager.removeItem(at: pageURL)
        }
    }
    
    /// Loads cached coins AND appends all cached pages for maximum coverage
    /// Use this when rate limited to get the best possible coin list
    private func loadAllCachedCoins() -> [MarketCoin]? {
        guard var coins = loadCachedMarketCoins() else { return nil }
        
        // Validate data quality - if corrupted, clear cache and reload from bundle
        if !isDataValid(coins) {
            clearCoinsCache()
            // Try loading from bundle
            if let bundled = loadBundledCoins() {
                coins = bundled
            } else {
                return nil
            }
        }
        
        var seen = Set(coins.map { $0.id })
        var addedFromPages = 0
        
        // Append all cached pages (1-8)
        for page in 1...8 {
            if let pageCoins = Self.loadPageCache(page: page) {
                for coin in pageCoins where !seen.contains(coin.id) {
                    coins.append(coin)
                    seen.insert(coin.id)
                    addedFromPages += 1
                }
            }
        }
        
        if addedFromPages > 0 {
            #if DEBUG
            print("[loadAllCachedCoins] Base cache: \(coins.count - addedFromPages), added from pages: \(addedFromPages), total: \(coins.count)")
            #endif
        }
        
        return coins.isEmpty ? nil : coins
    }

    /// Map common ticker symbols to CoinGecko IDs
    private func coingeckoID(for symbol: String) -> String {
        switch symbol.uppercased() {
        case "BTC": return "bitcoin"
        case "ETH": return "ethereum"
        case "SOL": return "solana"
        case "XRP": return "ripple"
        case "ADA": return "cardano"
        case "DOGE": return "dogecoin"
        case "BNB": return "binancecoin"
        case "USDT": return "tether"
        case "USDC": return "usd-coin"
        case "TRX": return "tron"
        case "TON": return "the-open-network"
        case "XMR": return "monero"
        case "BCH": return "bitcoin-cash"
        case "AAVE": return "aave"
        case "TAO": return "bittensor"
        case "KAS": return "kaspa"
        case "KCS": return "kucoin-shares"
        case "LEO": return "leo-token"
        case "WBTC": return "wrapped-bitcoin"
        case "WETH": return "weth"
        case "DAI": return "dai"
        // Project-specific symbols seen in logs
        case "ASTER": return "aster-2"
        case "BNSOL": return "binance-staked-sol"
        case "BFUSD": return "bfusd"
        default:
            // If the caller already passed a likely CoinGecko ID (contains a dash and lowercase), keep it
            let s = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.contains("-") && s.lowercased() == s { return s }
            return symbol.lowercased()
        }
    }

    /// Fetches coins by IDs.
    /// Note: This method caches watchlist/specific-ID fetches separately in "watchlist_cache.json"
    /// to avoid overwriting the full market list cache in "coins_cache.json".
    @MainActor
    func fetchCoins(ids: [String]) async -> [MarketCoin] {
        // If offline, attempt to return cached coins filtered by IDs
        if !NetworkMonitor.shared.isOnline {
            if let cached = loadCachedMarketCoins() {
                return filterCoins(cached, matching: ids)
            }
            return []
        }
        // Guard against empty ID list
        guard !ids.isEmpty else {
            return []
        }
        
        // Cooldown: if markets are rate-limited, avoid network and return cache/fallback filtered by IDs
        if let last = Self.lastMarketsRateLimitAt, Date().timeIntervalSince(last) < Self.marketsRateLimitCooldown {
            if let cached = loadCachedMarketCoins() { return filterCoins(cached, matching: ids) }
            let fallback = await fetchFallbackTopMarkets()
            if !fallback.isEmpty {
                let filtered = filterCoins(fallback, matching: ids)
                return filtered.isEmpty ? fallback : filtered
            }
            return []
        }

        // Map raw symbols to CoinGecko IDs
        let mappedIDs = ids.map { coingeckoID(for: $0) }
        let idString = mappedIDs.joined(separator: ",")
        #if DEBUG
        print("[fetchCoins] Requesting ids=\(idString)")
        #endif
        guard var components = URLComponents(string: "https://api.coingecko.com/api/v3/coins/markets") else {
            #if DEBUG
            print("❌ [CryptoAPIService] Invalid URL in fetchCoins(ids:).")
            #endif
            return []
        }
        components.queryItems = [
            URLQueryItem(name: "vs_currency", value: CurrencyManager.apiValue),
            URLQueryItem(name: "ids", value: idString),
            URLQueryItem(name: "order", value: "market_cap_desc"),
            URLQueryItem(name: "sparkline", value: "true"),
            URLQueryItem(name: "price_change_percentage", value: "1h,24h,7d")
        ]
        guard let url = components.url else {
            #if DEBUG
            print("❌ [CryptoAPIService] Invalid URL in fetchCoins(ids:).")
            #endif
            return []
        }

        let maxRetries = 3
        var attempt = 0
        var delay: TimeInterval = 1
        while attempt < maxRetries {
            attempt += 1
            do {
                let request = Self.makeRequest(url)
                let (data, response) = try await URLSession.shared.data(for: request)
                if Self.isRateLimited(response, data: data) {
                    Self.lastMarketsRateLimitAt = Date()
                    if let cached = loadCachedMarketCoins() { return filterCoins(cached, matching: ids) }
                    throw CryptoAPIError.rateLimited
                }
                if let snippetStr = String(data: data.prefix(200), encoding: .utf8), snippetStr.contains("\"error_code\":429") {
                    Self.lastMarketsRateLimitAt = Date()
                    if let cached = loadCachedMarketCoins() { return filterCoins(cached, matching: ids) }
                    throw CryptoAPIError.rateLimited
                }
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                struct Wrapper<T: Decodable>: Decodable { let data: T? }
                struct CoinsWrapper<T: Decodable>: Decodable { let coins: T? }
                struct ResultWrapper<T: Decodable>: Decodable { let result: T? }
                // 1) Try top-level array
                if let geckoCoins = try? decoder.decode([CoinGeckoCoin].self, from: data) {
                    var coins = geckoCoins.map { MarketCoin(gecko: $0) }

                    // Avoid caching/using obviously degraded sparkline payloads
                    if Self.isDegradedSparklinePayload(coins) {
                        if let cached = loadCachedMarketCoins(), !Self.isDegradedSparklinePayload(cached) { return filterCoins(cached, matching: ids) }
                        let fallback = await fetchFallbackTopMarkets()
                        if !fallback.isEmpty {
                            let filtered = filterCoins(fallback, matching: ids)
                            return filtered.isEmpty ? fallback : filtered
                        }
                        // Return live result but do not cache
                        return coins
                    }

                    // If the first page returns too few items (rate limits or CDN quirks),
                    // try to fetch pages 2 and 3 and merge unique IDs to build a healthy list.
                    if coins.count < 20 {
                        func pageURL(_ page: Int) -> URL? {
                            var comps = URLComponents(string: "https://api.coingecko.com/api/v3/coins/markets")
                            comps?.queryItems = [
                                URLQueryItem(name: "vs_currency", value: CurrencyManager.apiValue),
                                URLQueryItem(name: "order", value: "market_cap_desc"),
                                URLQueryItem(name: "per_page", value: "250"),
                                URLQueryItem(name: "page", value: "\(page)"),
                                URLQueryItem(name: "sparkline", value: "true"),
                                URLQueryItem(name: "price_change_percentage", value: "1h,24h,7d")
                            ]
                            return comps?.url
                        }
                        let pages = [2, 3]
                        var seen = Set(coins.map { $0.id })
                        for p in pages {
                            if let urlP = pageURL(p) {
                                var reqP = Self.makeRequest(urlP)
                                reqP.timeoutInterval = 10
                                if let (d, r) = try? await URLSession.shared.data(for: reqP) {
                                    if Self.isRateLimited(r, data: d) { continue }
                                    if let more = try? decoder.decode([CoinGeckoCoin].self, from: d) {
                                        for item in more.map({ MarketCoin(gecko: $0) }) where !seen.contains(item.id) {
                                            coins.append(item)
                                            seen.insert(item.id)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if coins.count >= 20 && !Self.isDegradedSparklinePayload(coins) {
                        // Cache the merged payload for stability across launches
                        if let encoded = try? JSONEncoder().encode(coins) {
                            saveCache(encoded, to: "coins_cache.json")
                        } else {
                            saveCache(data, to: "coins_cache.json")
                        }
                    }
                    return coins
                }
                // 2) Try { data: [...] }
                if let wrapped = try? decoder.decode(Wrapper<[CoinGeckoCoin]>.self, from: data), let geckoCoins = wrapped.data {
                    var coins = geckoCoins.map { MarketCoin(gecko: $0) }

                    // Avoid caching/using obviously degraded sparkline payloads
                    if Self.isDegradedSparklinePayload(coins) {
                        if let cached = loadCachedMarketCoins(), !Self.isDegradedSparklinePayload(cached) { return filterCoins(cached, matching: ids) }
                        let fallback = await fetchFallbackTopMarkets()
                        if !fallback.isEmpty {
                            let filtered = filterCoins(fallback, matching: ids)
                            return filtered.isEmpty ? fallback : filtered
                        }
                        // Return live result but do not cache
                        return coins
                    }

                    if coins.count < 20 {
                        func pageURL(_ page: Int) -> URL? {
                            var comps = URLComponents(string: "https://api.coingecko.com/api/v3/coins/markets")
                            comps?.queryItems = [
                                URLQueryItem(name: "vs_currency", value: CurrencyManager.apiValue),
                                URLQueryItem(name: "order", value: "market_cap_desc"),
                                URLQueryItem(name: "per_page", value: "250"),
                                URLQueryItem(name: "page", value: "\(page)"),
                                URLQueryItem(name: "sparkline", value: "true"),
                                URLQueryItem(name: "price_change_percentage", value: "1h,24h,7d")
                            ]
                            return comps?.url
                        }
                        let pages = [2, 3]
                        var seen = Set(coins.map { $0.id })
                        for p in pages {
                            if let urlP = pageURL(p) {
                                var reqP = Self.makeRequest(urlP)
                                reqP.timeoutInterval = 10
                                if let (d, r) = try? await URLSession.shared.data(for: reqP) {
                                    if Self.isRateLimited(r, data: d) { continue }
                                    if let wMore = try? decoder.decode(Wrapper<[CoinGeckoCoin]>.self, from: d), let more = wMore.data {
                                        for item in more.map({ MarketCoin(gecko: $0) }) where !seen.contains(item.id) {
                                            coins.append(item)
                                            seen.insert(item.id)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if coins.count >= 20 && !Self.isDegradedSparklinePayload(coins) {
                        if let encoded = try? JSONEncoder().encode(coins) {
                            saveCache(encoded, to: "coins_cache.json")
                        } else {
                            saveCache(data, to: "coins_cache.json")
                        }
                    }
                    return coins
                }
                // 3) Try { coins: [...] }
                if let wrapped = try? decoder.decode(CoinsWrapper<[CoinGeckoCoin]>.self, from: data), let geckoCoins = wrapped.coins {
                    let coins = geckoCoins.map { MarketCoin(gecko: $0) }
                    if Self.isDegradedSparklinePayload(coins) {
                        if let cached = loadCachedMarketCoins(), !Self.isDegradedSparklinePayload(cached) { return filterCoins(cached, matching: ids) }
                        let fallback = await fetchFallbackTopMarkets()
                        if !fallback.isEmpty {
                            let set = Set(ids)
                            let filtered = fallback.filter { set.contains($0.id) || set.contains($0.symbol.lowercased()) }
                            if !filtered.isEmpty { return filtered }
                            return fallback
                        }
                        return coins
                    }
                    if !Self.isDegradedSparklinePayload(coins) {
                        saveCache(data, to: "coins_cache.json")
                    }
                    return coins
                }
                // 4) Try { result: [...] }
                if let wrapped = try? decoder.decode(ResultWrapper<[CoinGeckoCoin]>.self, from: data), let geckoCoins = wrapped.result {
                    let coins = geckoCoins.map { MarketCoin(gecko: $0) }
                    if Self.isDegradedSparklinePayload(coins) {
                        if let cached = loadCachedMarketCoins(), !Self.isDegradedSparklinePayload(cached) { return filterCoins(cached, matching: ids) }
                        let fallback = await fetchFallbackTopMarkets()
                        if !fallback.isEmpty {
                            let set = Set(ids)
                            let filtered = fallback.filter { set.contains($0.id) || set.contains($0.symbol.lowercased()) }
                            if !filtered.isEmpty { return filtered }
                            return fallback
                        }
                        return coins
                    }
                    if !Self.isDegradedSparklinePayload(coins) {
                        saveCache(data, to: "coins_cache.json")
                    }
                    return coins
                }
                let snippet = String(data: data.prefix(300), encoding: .utf8) ?? "<non-utf8>"
                #if DEBUG
                print("❌ [CryptoAPIService] Failed to decode fetchCoins(ids:). Body snippet:\n\(snippet)")
                #endif
                let fallback = await fetchFallbackTopMarkets()
                if !fallback.isEmpty { return fallback }
                if let cached = loadCachedMarketCoins() { return filterCoins(cached, matching: ids) }
                return []
            } catch CryptoAPIError.rateLimited {
                Self.lastMarketsRateLimitAt = Date()
                let wait = delay
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                delay *= 2
            } catch let urlError as URLError where urlError.code == .timedOut || urlError.code == .networkConnectionLost {
                let wait = delay
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                delay *= 2
            } catch {
                #if DEBUG
                print("❌ [CryptoAPIService] Failed to fetchCoins(ids:) error: \(error)")
                #endif
                // On failure, return cached results if available filtered by ids
                if let cached = loadCachedMarketCoins() {
                    return filterCoins(cached, matching: ids)
                }
                let fallback = await fetchFallbackTopMarkets()
                if !fallback.isEmpty {
                    // If the caller requested specific IDs, filter to those if non-empty; else return full fallback
                    if !ids.isEmpty {
                        let set = Set(ids)
                        let filtered = fallback.filter { set.contains($0.id) || set.contains($0.symbol.lowercased()) }
                        if !filtered.isEmpty { return filtered }
                    }
                    return fallback
                }
                return []
            }
        }
        // If we exhausted retries, try returning cache filtered by ids, else attempt a curated fallback
        if let cached = loadCachedMarketCoins() {
            return filterCoins(cached, matching: ids)
        }
        let fallback = await fetchFallbackTopMarkets()
        if !fallback.isEmpty {
            // If the caller requested specific IDs, filter to those if non-empty; else return full fallback
            if !ids.isEmpty {
                let set = Set(ids)
                let filtered = fallback.filter { set.contains($0.id) || set.contains($0.symbol.lowercased()) }
                if !filtered.isEmpty { return filtered }
            }
            return fallback
        }
        return []
    }

    /// Fetches global market data from the CoinGecko `/global` endpoint.
    /// RATE LIMIT FIX: Tries Firebase proxy first (shared cache across all users), then falls back to direct API
    func fetchGlobalData() async throws -> GlobalMarketData {
        guard NetworkMonitor.shared.isOnline else {
            if let cached: GlobalMarketData = loadCache(from: "global_cache.json", as: GlobalMarketData.self) {
                return cached
            }
            throw URLError(.notConnectedToInternet)
        }
        
        // RATE LIMIT FIX: Try Firebase proxy first - all users share the same cached response
        do {
            let globalData = try await fetchGlobalViaFirebase()
            #if DEBUG
            print("[CryptoAPIService] Fetched global data via Firebase proxy")
            #endif
            // Cache locally too
            saveCache(globalData, to: "global_cache.json")
            return globalData
        } catch {
            #if DEBUG
            print("[CryptoAPIService] Firebase global proxy failed, falling back to direct API: \(error.localizedDescription)")
            #endif
            // Continue to direct API call below
        }
        
        // Cooldown: if we recently detected rate limiting on /global, use cache if available
        if let last = Self.lastGlobalRateLimitAt, Date().timeIntervalSince(last) < Self.globalRateLimitCooldown {
            if let cached: GlobalMarketData = loadCache(from: "global_cache.json", as: GlobalMarketData.self) {
                return cached
            }
            throw CryptoAPIError.rateLimited
        }
        
        guard let url = URL(string: "https://api.coingecko.com/api/v3/global") else {
            throw URLError(.badURL)
        }
        var attempts = 0
        var lastError: Error?
        while attempts < 2 {
            do {
                let request = Self.makeRequest(url)
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 429 {
                        // Rate limited: prefer cached data if present and set cooldown
                        Self.lastGlobalRateLimitAt = Date()
                        if let cached: GlobalMarketData = loadCache(from: "global_cache.json", as: GlobalMarketData.self) {
                            return cached
                        }
                        throw CryptoAPIError.rateLimited
                    }
                    guard (200...299).contains(http.statusCode) else {
                        throw CryptoAPIError.badServerResponse(statusCode: http.statusCode)
                    }
                    if let remaining = http.value(forHTTPHeaderField: "x-ratelimit-remaining"), remaining.trimmingCharacters(in: .whitespacesAndNewlines) == "0" {
                        Self.lastGlobalRateLimitAt = Date()
                        if let cached: GlobalMarketData = loadCache(from: "global_cache.json", as: GlobalMarketData.self) {
                            return cached
                        }
                        throw CryptoAPIError.rateLimited
                    }
                }
                // Some CDNs return 200 with a JSON body that contains an error_code 429. Detect and fallback.
                if let snippetStr = String(data: data.prefix(200), encoding: .utf8), snippetStr.contains("\"error_code\":429") {
                    Self.lastGlobalRateLimitAt = Date()
                    if let cached: GlobalMarketData = loadCache(from: "global_cache.json", as: GlobalMarketData.self) {
                        return cached
                    }
                    throw CryptoAPIError.rateLimited
                }
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let wrapper = try decoder.decode(GlobalDataResponse.self, from: data)
                
                let d = wrapper.data
                let cap = d.totalMarketCap["usd"] ?? 0
                let vol = d.totalVolume["usd"] ?? 0
                let btc = d.marketCapPercentage["btc"] ?? 0
                let eth = d.marketCapPercentage["eth"] ?? 0
                
                if (cap <= 0 || !cap.isFinite) || (vol <= 0 || !vol.isFinite) || (!btc.isFinite) || (!eth.isFinite) {
                    if let cached: GlobalMarketData = loadCache(from: "global_cache.json", as: GlobalMarketData.self) {
                        return cached
                    }
                    throw URLError(.cannotParseResponse)
                }
                
                // Save ONLY the unwrapped GlobalMarketData so future loads decode consistently
                if let encoded = try? JSONEncoder().encode(d) {
                    saveCache(encoded, to: "global_cache.json")
                } else {
                    // Fallback to raw data if encoding fails (should not happen)
                    saveCache(data, to: "global_cache.json")
                }
                return d
            } catch let urlError as URLError
                  where urlError.code == .timedOut
                     || urlError.code == .notConnectedToInternet
                     || urlError.code == .networkConnectionLost {
                attempts += 1
                lastError = urlError
                let backoff = 500_000_000 * UInt64(1 << attempts)
                try await Task.sleep(nanoseconds: backoff)
                if attempts >= 2,
                   let cached: GlobalMarketData = loadCache(from: "global_cache.json", as: GlobalMarketData.self) {
                    return cached
                }
            } catch {
                throw error
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    /// Fetches the current spot price (USD) for a single coin via CoinGecko's simple/price endpoint.
    func fetchSpotPrice(coin: String) async throws -> Double {
        let coinID = coingeckoID(for: coin)
        
        // PERFORMANCE FIX: Check for in-flight request for same coin and reuse it
        let (existingTask, myTask): (Task<Double, Error>?, Task<Double, Error>?) = inFlightLock.withLock {
            if let existing = inFlightSpotPriceRequests[coinID] {
                // PERFORMANCE FIX: Throttle logging to prevent console spam (only log once per 30s per coinID)
                #if DEBUG
                let now = Date()
                if let lastLog = lastInFlightLogTime[coinID], now.timeIntervalSince(lastLog) < logThrottleInterval {
                    // Skip logging - too recent
                } else {
                    lastInFlightLogTime[coinID] = now
                    print("[CryptoAPIService] Reusing in-flight request for \(coinID)")
                }
                #endif
                return (existing, nil)
            }
            let task = Task<Double, Error> {
                try await self.performSpotPriceFetch(coinID: coinID)
            }
            inFlightSpotPriceRequests[coinID] = task
            return (nil, task)
        }
        
        if let existing = existingTask {
            return try await existing.value
        }
        
        // Execute and clean up
        defer {
            inFlightLock.withLock {
                inFlightSpotPriceRequests.removeValue(forKey: coinID)
            }
        }
        
        guard let task = myTask else {
            throw CryptoAPIError.rateLimited // Should not happen: either existingTask or myTask is set
        }
        return try await task.value
    }
    
    /// Internal method that performs the actual API fetch (called by fetchSpotPrice with deduplication)
    private func performSpotPriceFetch(coinID: String) async throws -> Double {
        guard NetworkMonitor.shared.isOnline else {
            throw URLError(.notConnectedToInternet)
        }
        
        // PERFORMANCE FIX: Check coordinator before making request to prevent API spam
        guard APIRequestCoordinator.shared.canMakeRequest(for: .coinGecko) else {
            throw CryptoAPIError.rateLimited
        }
        APIRequestCoordinator.shared.recordRequest(for: .coinGecko)
        
        guard var components = URLComponents(string: "https://api.coingecko.com/api/v3/simple/price") else {
            throw URLError(.badURL)
        }
        components.queryItems = [
            URLQueryItem(name: "ids", value: coinID),
            URLQueryItem(name: "vs_currencies", value: "usd")
        ]
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        let request = Self.makeRequest(url)
        let (data, response) = try await URLSession.shared.data(for: request)
        if Self.isRateLimited(response, data: data) {
            APIRequestCoordinator.shared.recordFailure(for: .coinGecko)
            throw CryptoAPIError.rateLimited
        }
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 429 {
                APIRequestCoordinator.shared.recordFailure(for: .coinGecko)
                throw CryptoAPIError.rateLimited
            }
            guard (200...299).contains(http.statusCode) else {
                throw CryptoAPIError.badServerResponse(statusCode: http.statusCode)
            }
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let coinData = json?[coinID] as? [String: Any]
        if let price = coinData?["usd"] as? Double {
            // FIX: Record success to decrement active request count
            APIRequestCoordinator.shared.recordSuccess(for: .coinGecko)
            // Report healthy status to global API health manager
            Task { @MainActor in
                APIHealthManager.shared.reportHealthy(.coinGecko)
            }
            return price
        }
        throw CryptoAPIError.badServerResponse(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
    }
    
    // MARK: - Batch Price Fetching (PERFORMANCE FIX)
    
    /// Fetches spot prices for multiple coins in a single API request.
    /// This is much more efficient than calling fetchSpotPrice() for each coin individually.
    /// CoinGecko supports up to 250 coin IDs per request.
    func fetchSpotPrices(coins: [String]) async throws -> [String: Double] {
        guard !coins.isEmpty else { return [:] }
        guard NetworkMonitor.shared.isOnline else {
            throw URLError(.notConnectedToInternet)
        }
        
        // PERFORMANCE FIX: Check coordinator before making request
        guard APIRequestCoordinator.shared.canMakeRequest(for: .coinGecko) else {
            throw CryptoAPIError.rateLimited
        }
        APIRequestCoordinator.shared.recordRequest(for: .coinGecko)
        
        // Convert symbols to CoinGecko IDs and batch them
        let coinIDs = coins.map { coingeckoID(for: $0) }
        let uniqueIDs = Array(Set(coinIDs))  // Remove duplicates
        
        // CoinGecko allows up to 250 IDs per request
        let batchSize = 250
        var results: [String: Double] = [:]
        
        for batch in stride(from: 0, to: uniqueIDs.count, by: batchSize) {
            let endIndex = min(batch + batchSize, uniqueIDs.count)
            let batchIDs = Array(uniqueIDs[batch..<endIndex])
            let idsParam = batchIDs.joined(separator: ",")
            
            guard var components = URLComponents(string: "https://api.coingecko.com/api/v3/simple/price") else {
                continue
            }
            components.queryItems = [
                URLQueryItem(name: "ids", value: idsParam),
                URLQueryItem(name: "vs_currencies", value: "usd")
            ]
            guard let url = components.url else { continue }
            
            let request = Self.makeRequest(url)
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                if Self.isRateLimited(response, data: data) {
                    APIRequestCoordinator.shared.recordFailure(for: .coinGecko)
                    throw CryptoAPIError.rateLimited
                }
                
                if let http = response as? HTTPURLResponse {
                    guard (200...299).contains(http.statusCode) else {
                        continue
                    }
                }
                
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] {
                    for (coinID, coinData) in json {
                        if let price = coinData["usd"] as? Double {
                            results[coinID] = price
                            // Also map back to original symbol if different
                            for (index, originalID) in coinIDs.enumerated() where originalID == coinID {
                                let originalSymbol = coins[index]
                                results[originalSymbol.lowercased()] = price
                            }
                        }
                    }
                }
            } catch {
                #if DEBUG
                print("[CryptoAPIService] Batch price fetch error: \(error)")
                #endif
            }
        }
        
        // FIX: Record success to decrement active request count
        APIRequestCoordinator.shared.recordSuccess(for: .coinGecko)
        // Report healthy status to global API health manager
        if !results.isEmpty {
            Task { @MainActor in
                APIHealthManager.shared.reportHealthy(.coinGecko)
            }
        }
        return results
    }

    /// Fetches top coins from CoinGecko `/coins/markets`, decoding into `[MarketCoin]`.
    /// RATE LIMIT FIX: Tries Firebase proxy first (shared cache across all users), then falls back to direct API
    /// REQUEST DEDUPLICATION: Multiple callers share the same inflight request result
    /// PERFORMANCE FIX v17: Added 60s local cooldown to prevent back-to-back duplicate network calls
    private var lastFetchCoinMarketsAt: Date = .distantPast
    private var lastFetchCoinMarketsResult: [MarketCoin]?
    private let fetchCoinMarketsCooldown: TimeInterval = 60 // LIVE DATA FIX v5.2: shorter cooldown so stale snapshots recover faster
    // STARTUP COALESCING FIX: when Firestore CoinGecko is stale, callers may repeatedly
    // bypass cooldown and force fresh fetches. Cap stale-bypass frequency to reduce
    // back-to-back getCoinGeckoMarkets requests during startup overlap windows.
    private var lastStaleBypassFetchAt: Date = .distantPast
    private let staleBypassMinInterval: TimeInterval = 60
    
    func fetchCoinMarkets() async throws -> [MarketCoin] {
        // If offline, return cached coins if available
        guard NetworkMonitor.shared.isOnline else {
            if let cached = loadCachedMarketCoins() {
                return cached
            }
            throw URLError(.notConnectedToInternet)
        }
        
        // PERFORMANCE FIX v17: Return recent result if within cooldown period
        // This prevents MarketDataSyncService and LivePriceManager from making
        // back-to-back getCoinGeckoMarkets calls within seconds of each other
        let now = Date()
        if now.timeIntervalSince(lastFetchCoinMarketsAt) < fetchCoinMarketsCooldown,
           let recent = lastFetchCoinMarketsResult, !recent.isEmpty {
            // LIVE DATA FIX v5.2: When Firestore CoinGecko feed is stale, do NOT lock onto
            // local cached cooldown results. Attempt a fresh fetch path instead.
            if !FirestoreMarketSync.shared.isCoinGeckoDataFresh {
                // STARTUP COALESCING FIX: allow stale bypass, but no more than once every
                // staleBypassMinInterval so startup triggers can converge on one fetch.
                if now.timeIntervalSince(lastStaleBypassFetchAt) >= staleBypassMinInterval {
                    lastStaleBypassFetchAt = now
                    // Reuse any in-flight markets fetch before forcing a direct bypass fetch.
                    let existingTask: Task<[MarketCoin], Error>? = marketRequestsLock.withLock {
                        inFlightMarketRequests["markets_top"]
                    }
                    if let existingTask = existingTask {
                        return try await existingTask.value
                    }
                    return try await _fetchCoinMarketsImpl()
                }
                #if DEBUG
                Self.rateLimitedLog("stale_bypass_coalesced", "♻️ [CryptoAPIService] Coalescing stale CoinGecko refresh (returning recent cache)")
                #endif
                return recent
            }
            #if DEBUG
            Self.rateLimitedLog("cooldown_markets", "♻️ [CryptoAPIService] Returning cached result (within \(Int(fetchCoinMarketsCooldown))s cooldown)")
            #endif
            return recent
        }
        
        // REQUEST DEDUPLICATION: Check for existing inflight request
        // If found, wait for its result instead of starting a new request
        let requestKey = "markets_top"
        let existingTask: Task<[MarketCoin], Error>? = marketRequestsLock.withLock {
            return inFlightMarketRequests[requestKey]
        }
        
        if let existingTask = existingTask {
            // Another caller is already fetching - wait for their result
            deduplicationStats.recordRequest(deduplicated: true)
            #if DEBUG
            Self.rateLimitedLog("dedup_markets", "♻️ [CryptoAPIService] Request deduplicated - sharing inflight markets fetch")
            #endif
            return try await existingTask.value
        }
        
        // No inflight request - create one and store it
        let newTask = Task<[MarketCoin], Error> { [weak self] in
            guard let self = self else { throw URLError(.cancelled) }
            defer {
                // Clean up when done
                _ = self.marketRequestsLock.withLock {
                    self.inFlightMarketRequests.removeValue(forKey: requestKey)
                }
            }
            let result = try await self._fetchCoinMarketsImpl()
            // Update cooldown tracking
            self.lastFetchCoinMarketsAt = Date()
            self.lastFetchCoinMarketsResult = result
            return result
        }
        
        marketRequestsLock.withLock {
            inFlightMarketRequests[requestKey] = newTask
        }
        deduplicationStats.recordRequest(deduplicated: false)
        
        return try await newTask.value
    }
    
    /// Internal implementation of fetchCoinMarkets (separated for deduplication)
    private func _fetchCoinMarketsImpl() async throws -> [MarketCoin] {
        var firebaseProxyFailed = false
        
        // RATE LIMIT FIX: Try Firebase proxy first - all users share the same cached response
        // This eliminates per-user rate limiting issues at scale
        do {
            let firebaseCoins = Array((try await fetchMarketsViaFirebase()).prefix(Self.maxMarketCoinsForStartup))
            if !firebaseCoins.isEmpty {
                #if DEBUG
                print("[CryptoAPIService] source=firebase_proxy stale=false coins=\(firebaseCoins.count)")
                #endif
                // Cache the result locally too
                CacheManager.shared.save(firebaseCoins, to: "coins_cache.json")
                return firebaseCoins
            }
        } catch {
            #if DEBUG
            print("[CryptoAPIService] source=firebase_proxy failed=\(error.localizedDescription) -> source=direct_api")
            #endif
            firebaseProxyFailed = true
            // Continue to direct API call below
        }
        
        // PERFORMANCE: Check global request coordinator to prevent startup/foreground thundering herd
        // LIVE DATA FIX v5.1: If Firebase proxy fails (e.g., 401 from Cloud Function),
        // do not immediately fall back to stale local cache because that makes prices look
        // "hardcoded". Instead attempt one direct CoinGecko request even when coordinator
        // is currently throttling, so market data can recover.
        if !firebaseProxyFailed && !APIRequestCoordinator.shared.canMakeRequest(for: .coinGecko) {
            throw CryptoAPIError.rateLimited
        }
        
        // Cooldown: if we recently detected rate limiting, avoid network and return cache/fallback
        if let last = Self.lastMarketsRateLimitAt, Date().timeIntervalSince(last) < Self.marketsRateLimitCooldown {
            throw CryptoAPIError.rateLimited
        }
        
        // Record request with coordinator
        APIRequestCoordinator.shared.recordRequest(for: .coinGecko)
        
        // Build URLComponents for top markets endpoint
        guard var components = URLComponents(string: "https://api.coingecko.com/api/v3/coins/markets") else {
            throw URLError(.badURL)
        }
        components.queryItems = [
            URLQueryItem(name: "vs_currency", value: CurrencyManager.apiValue),
            URLQueryItem(name: "order", value: "market_cap_desc"),
            URLQueryItem(name: "per_page", value: "250"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "sparkline", value: "true"),
            URLQueryItem(name: "price_change_percentage", value: "1h,24h,7d")
        ]
        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var attempts = 0
        var lastError: Error?
        while attempts < 2 {
            do {
                let request = Self.makeRequest(url)
                let (data, response) = try await URLSession.shared.data(for: request)
                if Self.isRateLimited(response, data: data) {
                    // Rate-limit the log message to avoid console spam
                    let now = Date()
                    if Self.lastRateLimitLogAt.map({ now.timeIntervalSince($0) > 30 }) ?? true {
                        #if DEBUG
                        print("[fetchCoinMarkets] Detected rate limit. Using all cached coins.")
                        #endif
                        Self.lastRateLimitLogAt = now
                    }
                    Self.lastMarketsRateLimitAt = Date()
                    // Report to global API health manager and request coordinator
                    APIRequestCoordinator.shared.recordFailure(for: .coinGecko)
                    Task { @MainActor in
                        APIHealthManager.shared.reportBlocked(.coinGecko, until: Date().addingTimeInterval(Self.marketsRateLimitCooldown), reason: "Rate limited")
                    }
                    throw CryptoAPIError.rateLimited
                }
                if let snippetStr = String(data: data.prefix(200), encoding: .utf8), snippetStr.contains("\"error_code\":429") {
                    // Rate-limit the log message to avoid console spam
                    let now = Date()
                    if Self.lastRateLimitLogAt.map({ now.timeIntervalSince($0) > 30 }) ?? true {
                        #if DEBUG
                        print("[fetchCoinMarkets] Detected rate limit body. Using all cached coins.")
                        #endif
                        Self.lastRateLimitLogAt = now
                    }
                    Self.lastMarketsRateLimitAt = Date()
                    // Report failure to request coordinator
                    APIRequestCoordinator.shared.recordFailure(for: .coinGecko)
                    throw CryptoAPIError.rateLimited
                }
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                struct Wrapper<T: Decodable>: Decodable { let data: T? }
                do {
                    // First try top-level array
                    if let geckoCoins = try? decoder.decode([CoinGeckoCoin].self, from: data) {
                        var coins = geckoCoins.map { MarketCoin(gecko: $0) }

                        // Avoid caching/using obviously degraded sparkline payloads
                        if Self.isDegradedSparklinePayload(coins) {
                            // FIX: Record success to decrement active request count
                            APIRequestCoordinator.shared.recordSuccess(for: .coinGecko)
                            // Return live result but do not cache
                            return coins
                        }

                        // Always fetch multiple pages to get 500+ coins for comprehensive market coverage
                        // This gives users access to more altcoins and newer listings
                        func pageURL(_ page: Int, perPage: Int = 250) -> URL? {
                            var comps = URLComponents(string: "https://api.coingecko.com/api/v3/coins/markets")
                            comps?.queryItems = [
                                URLQueryItem(name: "vs_currency", value: CurrencyManager.apiValue),
                                URLQueryItem(name: "order", value: "market_cap_desc"),
                                URLQueryItem(name: "per_page", value: "\(perPage)"),
                                URLQueryItem(name: "page", value: "\(page)"),
                                URLQueryItem(name: "sparkline", value: "true"),
                                URLQueryItem(name: "price_change_percentage", value: "1h,24h,7d")
                            ]
                            return comps?.url
                        }
                        
                        // Save page 1 to cache immediately for quick startup
                        Self.savePageCache(page: 1, coins: coins)
                        #if DEBUG
                        print("[fetchCoinMarkets] Page 1 fetched with \(coins.count) coins")
                        #endif
                        
                        // Load any cached pages we have from previous sessions (extend to page 10 for broader coverage)
                        var seen = Set(coins.map { $0.id })
                        for cachedPage in 2...10 {
                            if let cachedCoins = Self.loadPageCache(page: cachedPage) {
                                var added = 0
                                for coin in cachedCoins where !seen.contains(coin.id) {
                                    coins.append(coin)
                                    seen.insert(coin.id)
                                    added += 1
                                }
                                if added > 0 {
                                    #if DEBUG
                                    print("[fetchCoinMarkets] Loaded \(added) coins from cached page \(cachedPage)")
                                    #endif
                                }
                            }
                        }
                        let initialCachedCount = coins.count
                        let isFirstLaunch = initialCachedCount <= 250 // Only have page 1
                        #if DEBUG
                        print("[fetchCoinMarkets] Total after loading caches: \(initialCachedCount) coins")
                        #endif
                        
                        // Page fetching strategy:
                        // - Always try to fetch at least pages 2-4 to get 750+ coins
                        // - On first launch or small cache: fetch up to page 10 for 2500 coins
                        // MEMORY FIX v12: During the first 60 seconds of app life, skip additional
                        // page fetching entirely. The multi-page fetch (up to 2500 coins with sparklines)
                        // runs concurrently with Firestore data + ensureBaseline, causing a memory storm.
                        // Pages 2-10 are deferred until the home screen is stable and memory is settled.
                        let allPages = [2, 3, 4, 5, 6, 7, 8, 9, 10]
                        let needsMoreCoins = coins.count < 500
                        let maxPagesToFetchPerSession = (isFirstLaunch || needsMoreCoins) ? 8 : 5
                        
                        // Determine which pages need fetching (no valid cache)
                        var pagesToFetch = allPages.filter { Self.loadPageCache(page: $0) == nil }
                        
                        // MEMORY FIX v12: Defer all additional page fetches during startup window
                        if Self.isInStartupDeferralWindow {
                            let elapsed = Int(Date().timeIntervalSince(Self.launchTime))
                            #if DEBUG
                            print("[fetchCoinMarkets] 🛡️ Startup deferral active (\(elapsed)s elapsed, \(Int(Self.startupPageFetchDeferralPeriod) - elapsed)s remaining) — skipping pages 2-10 fetch")
                            #endif
                            pagesToFetch = []
                        }
                        
                        let limitedPages = Array(pagesToFetch.prefix(maxPagesToFetchPerSession))
                        
                        #if DEBUG
                        print("[fetchCoinMarkets] Current coin count: \(coins.count), needsMoreCoins: \(needsMoreCoins), pagesToFetch: \(pagesToFetch.count)")
                        #endif
                        
                        if (isFirstLaunch || needsMoreCoins) && !limitedPages.isEmpty {
                            #if DEBUG
                            print("[fetchCoinMarkets] Aggressively fetching \(limitedPages.count) pages: \(limitedPages)")
                            #endif
                        }
                        
                        if !limitedPages.isEmpty {
                            #if DEBUG
                            print("[fetchCoinMarkets] Staggered fetch: \(limitedPages.count) uncached pages to fetch: \(limitedPages)")
                            #endif
                        }
                        
                        var rateLimitHit = false
                        var totalFailures = 0
                        let maxTotalFailures = 3 // Fewer failures tolerated per session
                        
                        for p in limitedPages {
                            // Stop only if we hit explicit rate limit OR too many total failures
                            guard !rateLimitHit && totalFailures < maxTotalFailures else { break }
                            
                            // MEMORY FIX v12: Skip further page fetches if memory is getting tight.
                            // Each page of 250 coins with sparklines can consume 5-15 MB of transient memory.
                            let availMB = Double(os_proc_available_memory()) / (1024 * 1024)
                            if availMB > 0 && availMB < 1500 {
                                #if DEBUG
                                print("[fetchCoinMarkets] ⚠️ Low memory (\(Int(availMB)) MB available) — stopping multi-page fetch at page \(p)")
                                #endif
                                break
                            }
                            
                            if let urlP = pageURL(p) {
                                var reqP = Self.makeRequest(urlP)
                                reqP.timeoutInterval = 20
                                
                                // Longer delay with jitter to avoid rate limits (2000-3000ms)
                                // CoinGecko free tier allows ~30 calls/minute, so we need 2+ seconds between pages
                                let baseDelay: UInt64 = 2_000_000_000
                                let jitter = UInt64.random(in: 0...1_000_000_000)
                                try? await Task.sleep(nanoseconds: baseDelay + jitter)
                                
                                // Retry logic with exponential backoff
                                var retries = 0
                                var success = false
                                let maxRetries = 3
                                
                                while retries < maxRetries && !success && !rateLimitHit {
                                    do {
                                        let (d, r) = try await URLSession.shared.data(for: reqP)
                                        
                                        if Self.isRateLimited(r, data: d) {
                                            #if DEBUG
                                            print("[fetchCoinMarkets] Rate limit hit on page \(p), pausing pagination")
                                            #endif
                                            rateLimitHit = true
                                            // Wait longer before giving up entirely
                                            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                                            break
                                        }
                                        
                                        if let more = try? decoder.decode([CoinGeckoCoin].self, from: d), !more.isEmpty {
                                            var newCoins: [MarketCoin] = []
                                            for item in more.map({ MarketCoin(gecko: $0) }) where !seen.contains(item.id) {
                                                coins.append(item)
                                                newCoins.append(item)
                                                seen.insert(item.id)
                                            }
                                            // Cache this page for future use
                                            let pageCoins = more.map { MarketCoin(gecko: $0) }
                                            Self.savePageCache(page: p, coins: pageCoins)
                                            #if DEBUG
                                            print("[fetchCoinMarkets] Page \(p) added \(newCoins.count) new coins, total: \(coins.count)")
                                            #endif
                                            success = true
                                        } else {
                                            retries += 1
                                            if retries < maxRetries {
                                                // Exponential backoff: 1s, 2s, 4s
                                                let backoffNs = UInt64(1_000_000_000 * (1 << retries))
                                                try? await Task.sleep(nanoseconds: backoffNs)
                                            }
                                        }
                                    } catch {
                                        retries += 1
                                        if retries < maxRetries {
                                            let backoffNs = UInt64(1_000_000_000 * (1 << retries))
                                            try? await Task.sleep(nanoseconds: backoffNs)
                                        }
                                    }
                                }
                                
                                if !success && !rateLimitHit {
                                    totalFailures += 1
                                    #if DEBUG
                                    print("[fetchCoinMarkets] Page \(p) failed after \(maxRetries) retries, totalFailures=\(totalFailures)")
                                    #endif
                                    // Skip to next page instead of stopping
                                }
                            }
                        }
                        
                        // After CoinGecko pagination, ALWAYS merge with Binance tickers for additional coverage
                        // Binance provides 300+ coins without rate limits, so we run this regardless of CoinGecko status
                        let enrichedCoins = await self.mergeWithBinanceData(coins)
                        if enrichedCoins.count > coins.count {
                            #if DEBUG
                            print("[fetchCoinMarkets] Binance merge added \(enrichedCoins.count - coins.count) coins, new total: \(enrichedCoins.count)")
                            #endif
                            coins = enrichedCoins
                        }
                        
                        // Also merge with Coinbase for comprehensive coverage (ensures RLC and other Coinbase coins appear)
                        let coinbaseEnriched = await self.mergeWithCoinbaseData(coins)
                        if coinbaseEnriched.count > coins.count {
                            #if DEBUG
                            print("[fetchCoinMarkets] Coinbase merge added \(coinbaseEnriched.count - coins.count) coins, new total: \(coinbaseEnriched.count)")
                            #endif
                            coins = coinbaseEnriched
                        }
                        
                        #if DEBUG
                        print("[fetchCoinMarkets] Pagination complete, total coins: \(coins.count)")
                        #endif

                        if coins.count >= 20 && !Self.isDegradedSparklinePayload(coins) {
                            // Cache the merged payload for stability across launches
                            if let encoded = try? JSONEncoder().encode(coins) {
                                saveCache(encoded, to: "coins_cache.json")
                            } else {
                                saveCache(data, to: "coins_cache.json")
                            }
                        }
                        // FIX: Record success to decrement active request count
                        APIRequestCoordinator.shared.recordSuccess(for: .coinGecko)
                        // Report healthy status to global API health manager
                        Task { @MainActor in
                            APIHealthManager.shared.reportHealthy(.coinGecko)
                        }
                        return coins
                    }
                    // Then try a wrapper with `data: [...]`
                    if let wrapped = try? decoder.decode(Wrapper<[CoinGeckoCoin]>.self, from: data),
                       let geckoCoins = wrapped.data {
                        var coins = geckoCoins.map { MarketCoin(gecko: $0) }

                        // Avoid caching/using obviously degraded sparkline payloads
                        if Self.isDegradedSparklinePayload(coins) {
                            // FIX: Record success to decrement active request count
                            APIRequestCoordinator.shared.recordSuccess(for: .coinGecko)
                            if let cached = loadCachedMarketCoins(), !Self.isDegradedSparklinePayload(cached) { return cached }
                            let fallback = await fetchFallbackTopMarkets()
                            if !fallback.isEmpty { return fallback }
                            // Return live result but do not cache
                            return coins
                        }

                        // Always fetch multiple pages to get 500+ coins
                        func pageURLWrapped(_ page: Int, perPage: Int = 250) -> URL? {
                            var comps = URLComponents(string: "https://api.coingecko.com/api/v3/coins/markets")
                            comps?.queryItems = [
                                URLQueryItem(name: "vs_currency", value: CurrencyManager.apiValue),
                                URLQueryItem(name: "order", value: "market_cap_desc"),
                                URLQueryItem(name: "per_page", value: "\(perPage)"),
                                URLQueryItem(name: "page", value: "\(page)"),
                                URLQueryItem(name: "sparkline", value: "true"),
                                URLQueryItem(name: "price_change_percentage", value: "1h,24h,7d")
                            ]
                            return comps?.url
                        }
                        
                        // Save page 1 to cache and load any cached pages (up to page 10 for broader coverage)
                        Self.savePageCache(page: 1, coins: coins)
                        var seenW = Set(coins.map { $0.id })
                        for cachedPage in 2...10 {
                            if let cachedCoins = Self.loadPageCache(page: cachedPage) {
                                for coin in cachedCoins where !seenW.contains(coin.id) {
                                    coins.append(coin)
                                    seenW.insert(coin.id)
                                }
                            }
                        }
                        
                        // Staggered page fetching: fetch up to 8 uncached pages per session
                        let allPagesW = [2, 3, 4, 5, 6, 7, 8, 9, 10]
                        let maxPagesToFetchW = 8
                        let pagesToFetchW = allPagesW.filter { Self.loadPageCache(page: $0) == nil }
                        let limitedPagesW = Array(pagesToFetchW.prefix(maxPagesToFetchW))
                        
                        if !limitedPagesW.isEmpty {
                            #if DEBUG
                            print("[fetchCoinMarkets-wrapped] Staggered fetch: \(limitedPagesW.count) uncached pages: \(limitedPagesW)")
                            #endif
                        }
                        
                        var rateLimitHitW = false
                        var totalFailuresW = 0
                        
                        for p in limitedPagesW {
                            guard !rateLimitHitW && totalFailuresW < 3 else { break }
                            
                            if let urlP = pageURLWrapped(p) {
                                var reqP = Self.makeRequest(urlP)
                                reqP.timeoutInterval = 20
                                
                                // Longer delay with jitter (2000-3000ms)
                                // CoinGecko free tier allows ~30 calls/minute, so we need 2+ seconds between pages
                                let baseDelay: UInt64 = 2_000_000_000
                                let jitter = UInt64.random(in: 0...1_000_000_000)
                                try? await Task.sleep(nanoseconds: baseDelay + jitter)
                                
                                if let (d, r) = try? await URLSession.shared.data(for: reqP) {
                                    if Self.isRateLimited(r, data: d) {
                                        rateLimitHitW = true
                                        continue
                                    }
                                    if let wMore = try? decoder.decode(Wrapper<[CoinGeckoCoin]>.self, from: d), let more = wMore.data {
                                        var newCoins: [MarketCoin] = []
                                        for item in more.map({ MarketCoin(gecko: $0) }) where !seenW.contains(item.id) {
                                            coins.append(item)
                                            newCoins.append(item)
                                            seenW.insert(item.id)
                                        }
                                        Self.savePageCache(page: p, coins: more.map { MarketCoin(gecko: $0) })
                                        #if DEBUG
                                        print("[fetchCoinMarkets-wrapped] Page \(p) added \(newCoins.count) coins, total: \(coins.count)")
                                        #endif
                                    } else {
                                        totalFailuresW += 1
                                    }
                                } else {
                                    totalFailuresW += 1
                                }
                            }
                        }
                        
                        // ALWAYS merge with Binance tickers regardless of CoinGecko rate limit status
                        // Binance provides 300+ coins without rate limits
                        let enrichedCoins = await self.mergeWithBinanceData(coins)
                        if enrichedCoins.count > coins.count {
                            #if DEBUG
                            print("[fetchCoinMarkets-wrapped] Binance merge added \(enrichedCoins.count - coins.count) coins, new total: \(enrichedCoins.count)")
                            #endif
                            coins = enrichedCoins
                        }
                        
                        // Also merge with Coinbase for comprehensive coverage
                        let coinbaseEnriched = await self.mergeWithCoinbaseData(coins)
                        if coinbaseEnriched.count > coins.count {
                            #if DEBUG
                            print("[fetchCoinMarkets-wrapped] Coinbase merge added \(coinbaseEnriched.count - coins.count) coins, new total: \(coinbaseEnriched.count)")
                            #endif
                            coins = coinbaseEnriched
                        }

                        if coins.count >= 20 && !Self.isDegradedSparklinePayload(coins) {
                            if let encoded = try? JSONEncoder().encode(coins) {
                                saveCache(encoded, to: "coins_cache.json")
                            } else {
                                saveCache(data, to: "coins_cache.json")
                            }
                        }
                        // FIX: Record success to decrement active request count
                        APIRequestCoordinator.shared.recordSuccess(for: .coinGecko)
                        return coins
                    }
                    // If neither decode path works, log a snippet and throw
                    let snippet = String(data: data.prefix(200), encoding: .utf8) ?? "<non-utf8>"
                    #if DEBUG
                    print("[fetchCoinMarkets] Decoding failed for both array and wrapper. Body snippet:\n\(snippet)")
                    #endif
                    // FIX: Record success (request completed, even if decoding failed)
                    APIRequestCoordinator.shared.recordSuccess(for: .coinGecko)
                    let fallback = await fetchFallbackTopMarkets()
                    if !fallback.isEmpty { return fallback }
                    throw URLError(.cannotParseResponse)
                }
            } catch let error as CryptoAPIError {
                throw error
            } catch let urlError as URLError
                  where urlError.code == .timedOut
                     || urlError.code == .notConnectedToInternet
                     || urlError.code == .networkConnectionLost {
                attempts += 1
                lastError = urlError
                let backoff = 500_000_000 * UInt64(1 << attempts)
                try await Task.sleep(nanoseconds: backoff)
                if attempts >= 2,
                   let cached = loadCachedMarketCoins() {
                    // FIX: Record success to decrement active request count (using cache after network error)
                    APIRequestCoordinator.shared.recordSuccess(for: .coinGecko)
                    return cached
                }
            } catch {
                #if DEBUG
                print("❌ [CryptoAPIService] fetchCoinMarkets error: \(error)")
                #endif
                // FIX: Record success to decrement active request count (request completed, returning fallback)
                APIRequestCoordinator.shared.recordSuccess(for: .coinGecko)
                if let cached = loadCachedMarketCoins() {
                    return cached
                }
                let fallback = await fetchFallbackTopMarkets()
                if !fallback.isEmpty { return fallback }
                return []
            }
        }
        // FIX: Record success before throwing (request completed but all retries exhausted)
        APIRequestCoordinator.shared.recordSuccess(for: .coinGecko)
        throw lastError ?? URLError(.unknown)
    }

    /// Convenience alias for LivePriceManager compatibility
    func fetchMarketCoins() async throws -> [MarketCoin] {
        return try await fetchCoinMarkets()
    }
    
    // MARK: - Category-Based Fetching
    
    /// CoinGecko category IDs for fetching coins by category
    enum CoinGeckoCategory: String {
        case gaming = "gaming"
        case ai = "artificial-intelligence"
        case meme = "meme-token"
        case solana = "solana-ecosystem"
        case defi = "decentralized-finance-defi"
        case layer2 = "layer-2"
    }
    
    /// Fetches coins from a specific CoinGecko category
    /// Returns up to 100 coins from the category, sorted by market cap
    func fetchCoinsByCategory(_ category: CoinGeckoCategory) async throws -> [MarketCoin] {
        guard NetworkMonitor.shared.isOnline else {
            return []
        }
        
        // Check rate limit cooldown
        if let last = Self.lastMarketsRateLimitAt, Date().timeIntervalSince(last) < Self.marketsRateLimitCooldown {
            // PERFORMANCE FIX: Rate-limit this log to avoid console spam
            Self.rateLimitedLog("fetchCoinsByCategory.cooldown", "[fetchCoinsByCategory] Rate limit cooldown active, skipping")
            return []
        }
        
        guard var components = URLComponents(string: "https://api.coingecko.com/api/v3/coins/markets") else {
            return []
        }
        
        components.queryItems = [
            URLQueryItem(name: "vs_currency", value: CurrencyManager.apiValue),
            URLQueryItem(name: "category", value: category.rawValue),
            URLQueryItem(name: "order", value: "market_cap_desc"),
            URLQueryItem(name: "per_page", value: "100"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "sparkline", value: "true"),
            URLQueryItem(name: "price_change_percentage", value: "1h,24h,7d")
        ]
        
        guard let url = components.url else {
            return []
        }
        
        var request = Self.makeRequest(url)
        request.timeoutInterval = 15
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if Self.isRateLimited(response, data: data) {
                Self.lastMarketsRateLimitAt = Date()
                // PERFORMANCE FIX: Rate-limit this log to avoid console spam
                Self.rateLimitedLog("fetchCoinsByCategory.rateLimit.\(category.rawValue)", "[fetchCoinsByCategory] Rate limited for category: \(category.rawValue)")
                return []
            }
            
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            
            if let geckoCoins = try? decoder.decode([CoinGeckoCoin].self, from: data) {
                let coins = geckoCoins.map { MarketCoin(gecko: $0) }
                #if DEBUG
                print("[fetchCoinsByCategory] Fetched \(coins.count) coins for category: \(category.rawValue)")
                #endif
                return coins
            }
            
            // Try wrapped response
            struct Wrapper: Decodable {
                let data: [CoinGeckoCoin]?
            }
            if let wrapped = try? decoder.decode(Wrapper.self, from: data), let geckoCoins = wrapped.data {
                let coins = geckoCoins.map { MarketCoin(gecko: $0) }
                #if DEBUG
                print("[fetchCoinsByCategory] Fetched \(coins.count) coins (wrapped) for category: \(category.rawValue)")
                #endif
                return coins
            }
            
        } catch {
            #if DEBUG
            print("[fetchCoinsByCategory] Error fetching category \(category.rawValue): \(error)")
            #endif
        }
        
        return []
    }
    
    /// Fetches coins from multiple categories and merges them with existing coins
    /// This expands market coverage beyond the top 500 by market cap
    /// PERFORMANCE: Reduced category count and increased delays to avoid rate limits
    func fetchCategoryCoins() async -> [MarketCoin] {
        // PERFORMANCE: Reduced from 5 categories to 3 most valuable ones to minimize API calls
        let categories: [CoinGeckoCategory] = [.gaming, .meme, .defi]
        var allCoins: [String: MarketCoin] = [:] // Keyed by ID to avoid duplicates
        
        for category in categories {
            // PERFORMANCE: Increased delay from 200ms to 1.5s between category requests
            // CoinGecko free tier has strict rate limits
            if category != categories.first {
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
            }
            
            let coins = try? await fetchCoinsByCategory(category)
            for coin in coins ?? [] {
                if allCoins[coin.id] == nil {
                    allCoins[coin.id] = coin
                }
            }
        }
        
        #if DEBUG
        print("[fetchCategoryCoins] Total unique coins from categories: \(allCoins.count)")
        #endif
        return Array(allCoins.values)
    }
    
    // MARK: - Binance Ticker Fallback
    
    /// Binance ticker response structure
    private struct BinanceTicker: Decodable {
        let symbol: String
        let lastPrice: String
        let priceChangePercent: String
        let volume: String
        let quoteVolume: String
        
        var priceDouble: Double? { Double(lastPrice) }
        var changePercent: Double? { Double(priceChangePercent) }
        var volumeDouble: Double? { Double(quoteVolume) }
    }
    
    /// Fetches tickers from Binance as a fallback/supplement to CoinGecko
    /// This provides real-time data for 500+ trading pairs without rate limits
    func fetchBinanceTickers() async -> [MarketCoin] {
        // If Binance is known geo-blocked for this session, skip direct calls entirely.
        if UserDefaults.standard.bool(forKey: "BinanceGlobalGeoBlocked") {
            return []
        }
        
        // FIX: Use ExchangeHostPolicy to get correct endpoint (US if geo-blocked)
        let endpoints = await ExchangeHostPolicy.shared.currentEndpoints()
        guard let url = URL(string: "\(endpoints.restBase)/ticker/24hr") else {
            return []
        }
        
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.setValue("CryptoSage/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // FIX: Report HTTP status to policy for geo-block detection
            if let httpResponse = response as? HTTPURLResponse {
                await ExchangeHostPolicy.shared.onHTTPStatus(httpResponse.statusCode)
                guard httpResponse.statusCode == 200 else {
                    #if DEBUG
                    print("[fetchBinanceTickers] Bad response: \(httpResponse.statusCode)")
                    #endif
                    return []
                }
            } else {
                #if DEBUG
                print("[fetchBinanceTickers] Bad response: not HTTP")
                #endif
                return []
            }
            
            let tickers = try JSONDecoder().decode([BinanceTicker].self, from: data)
            
            // Filter to USDT and FDUSD pairs (most liquid) and convert to MarketCoin
            // Prefer USDT pairs, but include FDUSD for broader coverage
            let liquidPairs = tickers.filter { 
                $0.symbol.hasSuffix("USDT") || $0.symbol.hasSuffix("FDUSD") 
            }
            
            // Deduplicate by base symbol, preferring USDT over FDUSD
            var seenBases: Set<String> = []
            let usdtPairs = liquidPairs.sorted { a, b in
                // USDT pairs come first
                if a.symbol.hasSuffix("USDT") && !b.symbol.hasSuffix("USDT") { return true }
                if !a.symbol.hasSuffix("USDT") && b.symbol.hasSuffix("USDT") { return false }
                return a.symbol < b.symbol
            }.filter { ticker in
                let base = ticker.symbol.hasSuffix("USDT") 
                    ? String(ticker.symbol.dropLast(4)) 
                    : String(ticker.symbol.dropLast(5))
                if seenBases.contains(base) { return false }
                seenBases.insert(base)
                return true
            }
            
            var coins: [MarketCoin] = []
            for ticker in usdtPairs {
                // Determine base symbol based on quote currency
                let baseSymbol: String
                if ticker.symbol.hasSuffix("USDT") {
                    baseSymbol = String(ticker.symbol.dropLast(4))
                } else if ticker.symbol.hasSuffix("FDUSD") {
                    baseSymbol = String(ticker.symbol.dropLast(5))
                } else {
                    continue
                }
                
                // Skip stablecoins, leveraged tokens, and other unwanted pairs
                let upperBase = baseSymbol.uppercased()
                guard !upperBase.contains("UP") && !upperBase.contains("DOWN") &&
                      !upperBase.contains("BULL") && !upperBase.contains("BEAR") &&
                      !upperBase.contains("3L") && !upperBase.contains("3S") &&
                      upperBase != "USDC" && upperBase != "BUSD" && upperBase != "DAI" &&
                      upperBase != "TUSD" && upperBase != "USDP" && upperBase != "FDUSD" &&
                      upperBase != "EUR" && upperBase != "GBP" && upperBase != "AUD" &&
                      upperBase != "TRY" && upperBase != "BRL" && upperBase != "BIDR" else {
                    continue
                }
                
                guard let price = ticker.priceDouble,
                      let change = ticker.changePercent,
                      let volume = ticker.volumeDouble,
                      price > 0 && price.isFinite else {
                    continue
                }
                
                // Use CoinNameMapping to get proper name and ID
                let properName = CoinNameMapping.name(for: baseSymbol)
                let geckoID = CoinNameMapping.geckoID(for: baseSymbol)
                
                // Create MarketCoin with proper metadata
                let coin = MarketCoin(
                    id: geckoID,
                    symbol: baseSymbol.uppercased(),
                    name: properName,
                    imageUrl: nil, // Will be resolved by CoinImageView fallbacks
                    priceUsd: price,
                    marketCap: nil, // Not available from Binance ticker
                    totalVolume: volume,
                    priceChangePercentage1hInCurrency: nil, // Not available from 24hr ticker
                    priceChangePercentage24hInCurrency: change,
                    priceChangePercentage7dInCurrency: nil, // Not available from 24hr ticker
                    sparklineIn7d: [], // Not available from Binance
                    marketCapRank: nil,
                    maxSupply: nil,
                    circulatingSupply: nil,
                    totalSupply: nil
                )
                coins.append(coin)
            }
            
            #if DEBUG
            print("[fetchBinanceTickers] Loaded \(coins.count) coins from Binance")
            #endif
            return coins
            
        } catch {
            #if DEBUG
            print("[fetchBinanceTickers] Error: \(error)")
            #endif
            return []
        }
    }
    
    /// Merges Binance tickers with existing coins, preferring CoinGecko data when available
    /// Also filters Binance-only coins to those with meaningful volume
    func mergeWithBinanceData(_ existingCoins: [MarketCoin]) async -> [MarketCoin] {
        let binanceCoins = await fetchBinanceTickers()
        guard !binanceCoins.isEmpty else { return existingCoins }
        
        // Create lookups by symbol and ID (uppercased/lowercased)
        var coinsBySymbol: [String: MarketCoin] = [:]
        var coinsByID: [String: MarketCoin] = [:]
        for coin in existingCoins {
            coinsBySymbol[coin.symbol.uppercased()] = coin
            coinsByID[coin.id.lowercased()] = coin
        }
        
        // Minimum volume threshold for Binance-only coins (filter out dust)
        let minVolumeUSD: Double = 25_000 // $25k daily volume minimum for broader coverage
        
        // Add Binance coins that we don't have from CoinGecko
        var newCoins: [MarketCoin] = []
        var enrichedCount = 0
        
        for binanceCoin in binanceCoins {
            let sym = binanceCoin.symbol.uppercased()
            let coinID = binanceCoin.id.lowercased()
            
            // Check if we already have this coin from CoinGecko
            if let existingBySymbol = coinsBySymbol[sym] {
                // FIX: Enrich if missing price OR missing volume (not just price)
                // This ensures coins with CoinGecko price but no volume get Binance volume
                let missingPrice = existingBySymbol.priceUsd == nil || existingBySymbol.priceUsd == 0
                let missingVolume = existingBySymbol.totalVolume == nil || (existingBySymbol.totalVolume ?? 0) <= 0
                
                if missingPrice || missingVolume {
                    // Create enriched coin with Binance data for missing fields
                    let enriched = existingBySymbol.updating(
                        priceUsd: missingPrice ? binanceCoin.priceUsd : existingBySymbol.priceUsd,
                        totalVolume: missingVolume ? (binanceCoin.totalVolume ?? existingBySymbol.totalVolume) : existingBySymbol.totalVolume,
                        priceChangePercentage24hInCurrency: binanceCoin.priceChangePercentage24hInCurrency ?? existingBySymbol.priceChangePercentage24hInCurrency
                    )
                    coinsBySymbol[sym] = enriched
                    coinsByID[existingBySymbol.id.lowercased()] = enriched
                    enrichedCount += 1
                }
                continue
            }
            
            if coinsByID[coinID] != nil {
                continue // Already have this coin by ID
            }
            
            // For new Binance-only coins, apply volume filter
            guard let volume = binanceCoin.totalVolume, volume >= minVolumeUSD else {
                continue
            }
            
            newCoins.append(binanceCoin)
            coinsBySymbol[sym] = binanceCoin
            coinsByID[coinID] = binanceCoin
        }
        
        if enrichedCount > 0 {
            #if DEBUG
            print("[mergeWithBinanceData] Enriched \(enrichedCount) existing coins with Binance data")
            #endif
        }
        if !newCoins.isEmpty {
            #if DEBUG
            print("[mergeWithBinanceData] Added \(newCoins.count) new coins from Binance (volume >= $\(Int(minVolumeUSD)))")
            #endif
        }
        
        // Build result: start with existing coins (possibly enriched), then add new ones
        var result = existingCoins.map { coinsBySymbol[$0.symbol.uppercased()] ?? $0 }
        result.append(contentsOf: newCoins)
        
        return result
    }
    
    /// Merges Coinbase trading pairs with existing coins, adding any coins not already in the list.
    /// This ensures all Coinbase-tradeable coins appear in the market list even if CoinGecko/Binance missed them.
    func mergeWithCoinbaseData(_ existingCoins: [MarketCoin]) async -> [MarketCoin] {
        // Get all Coinbase symbols
        let coinbaseSymbols = await CoinbaseService.shared.getAllCoinbaseSymbols()
        guard !coinbaseSymbols.isEmpty else { return existingCoins }
        
        // Create lookup by symbol
        var coinsBySymbol: [String: MarketCoin] = [:]
        for coin in existingCoins {
            coinsBySymbol[coin.symbol.uppercased()] = coin
        }
        
        // Find symbols we don't have yet
        let missingSymbols = coinbaseSymbols.filter { coinsBySymbol[$0] == nil }
        
        if missingSymbols.isEmpty {
            return existingCoins
        }
        
        #if DEBUG
        print("[mergeWithCoinbaseData] Found \(missingSymbols.count) Coinbase coins not in current list: \(missingSymbols.prefix(10).joined(separator: ", "))...")
        #endif
        
        // Fetch stats for missing coins from Coinbase (with volume)
        var newCoins: [MarketCoin] = []
        let statsResults = await CoinbaseService.shared.fetch24hStats(for: missingSymbols, fiat: "USD", maxConcurrency: 6)
        
        for stats in statsResults {
            let sym = stats.symbol.uppercased()
            
            // Map to CoinGecko ID for consistency
            let geckoID = coingeckoID(for: sym)
            
            // Create a minimal MarketCoin with Coinbase data
            let coin = MarketCoin(
                id: geckoID,
                symbol: sym,
                name: CoinNameMapping.name(for: sym),
                imageUrl: nil, // Will be resolved by CoinImageView fallbacks
                priceUsd: stats.lastPrice,
                marketCap: nil, // Not available from Coinbase
                totalVolume: stats.volume,
                priceChangePercentage1hInCurrency: nil,
                priceChangePercentage24hInCurrency: stats.change24h,
                priceChangePercentage7dInCurrency: nil,
                sparklineIn7d: [],
                marketCapRank: nil, // Will be handled by deduplication fix
                maxSupply: nil,
                circulatingSupply: nil,
                totalSupply: nil
            )
            newCoins.append(coin)
            coinsBySymbol[sym] = coin
        }
        
        if !newCoins.isEmpty {
            #if DEBUG
            print("[mergeWithCoinbaseData] Added \(newCoins.count) new coins from Coinbase")
            #endif
        }
        
        var result = existingCoins
        result.append(contentsOf: newCoins)
        return result
    }

    /// Fetches watchlist coins by ID list; debounced calls will use a single network request.
    func fetchWatchlistMarkets(ids: [String]) async throws -> [MarketCoin] {
        // Helper to reorder any returned coins to the caller's ids order (after symbol->id mapping)
        func reorder(_ coins: [MarketCoin], by ids: [String]) -> [MarketCoin] {
            let orderKeys = ids.map { self.coingeckoID(for: $0).lowercased() }
            var result: [MarketCoin] = []
            var used = Set<String>()
            let idMap = Dictionary(coins.map { ($0.id.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
            let symMap = Dictionary(coins.map { ($0.symbol.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
            for key in orderKeys {
                if let c = idMap[key], used.insert(c.id.lowercased()).inserted {
                    result.append(c)
                } else if let c = symMap[key], used.insert(c.id.lowercased()).inserted {
                    result.append(c)
                }
            }
            // Append any leftovers deterministically
            for c in coins where !used.contains(c.id.lowercased()) {
                result.append(c)
                used.insert(c.id.lowercased())
            }
            return result
        }

        // If offline, return filtered cached coins if available (ordered to match ids)
        guard NetworkMonitor.shared.isOnline else {
            if let cached = loadCachedMarketCoins() {
                let filtered = filterCoins(cached, matching: ids)
                return reorder(filtered, by: ids)
            }
            throw URLError(.notConnectedToInternet)
        }
        // Early exit if no IDs
        guard !ids.isEmpty else {
            return []
        }
        
        // Cooldown: if markets are rate-limited, avoid network and return cache filtered by IDs
        if let last = Self.lastMarketsRateLimitAt, Date().timeIntervalSince(last) < Self.marketsRateLimitCooldown {
            if let cached = loadCachedMarketCoins() {
                let filtered = filterCoins(cached, matching: ids)
                return reorder(filtered, by: ids)
            }
            throw CryptoAPIError.rateLimited
        }

        // Map raw symbols to CoinGecko IDs
        let mappedIDs = ids.map { coingeckoID(for: $0) }
        let idList = mappedIDs.joined(separator: ",")
        guard var components = URLComponents(string: "https://api.coingecko.com/api/v3/coins/markets") else {
            throw URLError(.badURL)
        }
        components.queryItems = [
            URLQueryItem(name: "vs_currency", value: CurrencyManager.apiValue),
            URLQueryItem(name: "ids", value: idList),
            URLQueryItem(name: "order", value: "market_cap_desc"),
            URLQueryItem(name: "sparkline", value: "true"),
            URLQueryItem(name: "price_change_percentage", value: "1h,24h,7d")
        ]
        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var attempts = 0
        while attempts < 2 {
            do {
                let request = Self.makeRequest(url)
                let (data, response) = try await URLSession.shared.data(for: request)
                if Self.isRateLimited(response, data: data) {
                    Self.lastMarketsRateLimitAt = Date()
                    if let cached = loadCachedMarketCoins() {
                        let filtered = filterCoins(cached, matching: ids)
                        return reorder(filtered, by: ids)
                    }
                    throw CryptoAPIError.rateLimited
                }
                // Detect rate limit body (some CDNs return 200 with error_code 429)
                if let snippetStr = String(data: data.prefix(200), encoding: .utf8), snippetStr.contains("\"error_code\":429") {
                    Self.lastMarketsRateLimitAt = Date()
                    if let cached = loadCachedMarketCoins() {
                        let filtered = filterCoins(cached, matching: ids)
                        return reorder(filtered, by: ids)
                    }
                    throw CryptoAPIError.rateLimited
                }
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                struct Wrapper<T: Decodable>: Decodable { let data: T? }
                if let geckoCoins = try? decoder.decode([CoinGeckoCoin].self, from: data) {
                    let coins = geckoCoins.map { MarketCoin(gecko: $0) }
                    if !Self.isDegradedSparklinePayload(coins) {
                        saveCache(data, to: "watchlist_cache.json")
                    }
                    return reorder(coins, by: ids)
                }
                if let wrapped = try? decoder.decode(Wrapper<[CoinGeckoCoin]>.self, from: data), let geckoCoins = wrapped.data {
                    let coins = geckoCoins.map { MarketCoin(gecko: $0) }
                    if !Self.isDegradedSparklinePayload(coins) {
                        saveCache(data, to: "watchlist_cache.json")
                    }
                    return reorder(coins, by: ids)
                }
                // If decode fails, try cache filtered by IDs
                if let cached = loadCachedMarketCoins() {
                    let filtered = filterCoins(cached, matching: ids)
                    return reorder(filtered, by: ids)
                }
                throw URLError(.cannotParseResponse)
            } catch let error as CryptoAPIError {
                throw error
            } catch let urlError as URLError
                  where urlError.code == .timedOut
                     || urlError.code == .notConnectedToInternet
                     || urlError.code == .networkConnectionLost {
                attempts += 1
                let backoff = 500_000_000 * UInt64(1 << attempts)
                try await Task.sleep(nanoseconds: backoff)
                if attempts >= 2,
                   let cached = loadCachedMarketCoins() {
                    let filtered = filterCoins(cached, matching: ids)
                    return reorder(filtered, by: ids)
                }
            } catch {
                if let cached = loadCachedMarketCoins() {
                    let filtered = filterCoins(cached, matching: ids)
                    return reorder(filtered, by: ids)
                }
                throw error
            }
        }
        return []
    }

    /// Fetches both top-20 markets and watchlist markets in a single call.
    func fetchAllAndWatchlist(visibleIDs: [String]) async throws -> (allCoins: [MarketCoin], watchlistCoins: [MarketCoin]) {
        // 1) Always fetch top markets snapshot first
        let allCoins = try await fetchCoinMarkets()

        // 2) If no watchlist, we're done
        guard !visibleIDs.isEmpty else {
            return (allCoins, [])
        }

        // Build quick lookup maps from the same snapshot to keep values consistent (handle duplicate IDs)
        let idMap = Dictionary(allCoins.map { ($0.id.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        let symMap = Dictionary(allCoins.map { ($0.symbol.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })

        // Determine which watchlist IDs are already covered by the allCoins payload
        var missing: [String] = []
        for raw in visibleIDs {
            let key = coingeckoID(for: raw).lowercased()
            if idMap[key] == nil && symMap[key] == nil {
                missing.append(key)
            }
        }

        // 3) Fetch only the missing coins (not present in allCoins)
        var fetchedMissing: [MarketCoin] = []
        if !missing.isEmpty {
            fetchedMissing = try await fetchWatchlistMarkets(ids: missing)
        }
        let fetchedIDMap = Dictionary(fetchedMissing.map { ($0.id.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        let fetchedSymMap = Dictionary(fetchedMissing.map { ($0.symbol.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })

        // 4) Assemble the final watchlist in the exact order of visibleIDs, preferring the allCoins snapshot
        var watchlist: [MarketCoin] = []
        var used = Set<String>()
        for raw in visibleIDs {
            let key = coingeckoID(for: raw).lowercased()
            if let c = idMap[key], used.insert(c.id.lowercased()).inserted {
                watchlist.append(c)
                continue
            }
            if let c = symMap[key], used.insert(c.id.lowercased()).inserted {
                watchlist.append(c)
                continue
            }
            if let c = fetchedIDMap[key], used.insert(c.id.lowercased()).inserted {
                watchlist.append(c)
                continue
            }
            if let c = fetchedSymMap[key], used.insert(c.id.lowercased()).inserted {
                watchlist.append(c)
                continue
            }
        }

        return (allCoins, watchlist)
    }

    /// Combine publisher for fetching top-coin markets.
    func fetchCoinMarketsPublisher() -> AnyPublisher<[MarketCoin], Error> {
        Future { promise in
            Task {
                do {
                    let coins = try await self.fetchCoinMarkets()
                    promise(.success(coins))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }

    /// Combine-friendly entry point for loading top market coins.
    static func loadMarketData() -> AnyPublisher<[MarketCoin], Error> {
        return CryptoAPIService.shared.fetchCoinMarketsPublisher()
    }

    /// Combine publisher for fetching watchlist coin markets by IDs.
    func fetchWatchlistMarketsPublisher(ids: [String]) -> AnyPublisher<[MarketCoin], Error> {
        Future { promise in
            Task {
                do {
                    let coins = try await self.fetchWatchlistMarkets(ids: ids)
                    promise(.success(coins))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }
}

extension CryptoAPIService {
    /// Live-updating publisher for a single coin’s spot price, mapping symbol to Gecko ID.
    func liveSpotPricePublisher(for symbol: String, interval: TimeInterval = 5) -> AnyPublisher<Double, Never> {
        // PERFORMANCE FIX: Increase minimum interval to reduce request spam
        let effectiveInterval = max(interval, 30.0)  // At least 30 seconds between polls
        
        return Timer.publish(every: effectiveInterval, on: .main, in: .common)
            .autoconnect()
            .prepend(Date())  // trigger an immediate fetch
            .flatMap { _ in
                Future<Double, Never> { promise in
                    Task {
                        // PERFORMANCE FIX: Check coordinator before making request
                        guard APIRequestCoordinator.shared.canMakeRequest(for: .coinGecko) else {
                            // Skip this tick if rate limited, return 0 to indicate no update
                            promise(.success(0))
                            return
                        }
                        
                        // 1) Try CoinGecko simple price
                        let gecko = (try? await self.fetchSpotPrice(coin: symbol)) ?? 0
                        if gecko > 0 {
                            promise(.success(gecko))
                            return
                        }
                        
                        // PERFORMANCE FIX: Check coordinator for Coinbase too
                        guard APIRequestCoordinator.shared.canMakeRequest(for: .coinbase) else {
                            promise(.success(0))
                            return
                        }
                        APIRequestCoordinator.shared.recordRequest(for: .coinbase)
                        
                        // 2) Fallback: Coinbase ticker for SYMBOL-USD
                        let pair = symbol.uppercased() + "-USD"
                        if let url = URL(string: "https://api.exchange.coinbase.com/products/\(pair)/ticker"),
                           let (data, _) = try? await URLSession.shared.data(from: url),
                           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let priceStr = obj["price"] as? String,
                           let val = Double(priceStr), val > 0 {
                            // FIX: Record success to decrement active request count
                            APIRequestCoordinator.shared.recordSuccess(for: .coinbase)
                            promise(.success(val))
                            return
                        }
                        // FIX: Record success even if price wasn't found (request completed)
                        APIRequestCoordinator.shared.recordSuccess(for: .coinbase)
                        // 3) Give up with 0 for this tick
                        promise(.success(0))
                    }
                }
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}

extension CryptoAPIService {
    static func isDegradedSparklinePayload(_ coins: [MarketCoin]) -> Bool {
        // Enhanced heuristic:
        // - If any of the first 10 coins has an empty or too-short sparkline, treat as degraded.
        // - If >=3 share the same (count, first, last) signature, treat as degraded.
        // - If BTC or ETH share the same signature, treat as degraded.
        // - If BTC or ETH sparkline is "too flat" (very small relative range), treat as degraded.
        if coins.isEmpty { return false }
        let top = Array(coins.prefix(10))

        func signature(_ arr: [Double]) -> String {
            "\(arr.count)-\(arr.first ?? .nan)-\(arr.last ?? .nan)"
        }
        func range(_ arr: [Double]) -> Double {
            guard let minV = arr.min(), let maxV = arr.max() else { return 0 }
            return maxV - minV
        }
        func isTooFlat(_ arr: [Double], epsilon: Double) -> Bool {
            let r = range(arr)
            let denom = max(abs(arr.last ?? 0), 1.0)
            return (denom == 0) ? true : (r / denom) < epsilon
        }

        // New: reject if any sparkline is empty or too short
        if top.contains(where: { $0.sparklineIn7d.isEmpty || $0.sparklineIn7d.count < 7 }) {
            return true
        }

        var counts: [String: Int] = [:]
        for c in top {
            let key = signature(c.sparklineIn7d)
            counts[key, default: 0] += 1
        }
        if (counts.values.max() ?? 0) >= 3 { return true }

        let btc = top.first { $0.symbol.lowercased() == "btc" }
        let eth = top.first { $0.symbol.lowercased() == "eth" }
        if let b = btc, let e = eth {
            let sb = signature(b.sparklineIn7d)
            let se = signature(e.sparklineIn7d)
            if sb == se, (counts[sb] ?? 0) >= 2 { return true }
            // New: consider BTC/ETH too flat as degraded
            if isTooFlat(b.sparklineIn7d, epsilon: 0.0001) { return true }
            if isTooFlat(e.sparklineIn7d, epsilon: 0.0001) { return true }
        }

        // Detect likely normalized [0..1] sparklines across multiple top coins
        func looksNormalized01(_ arr: [Double]) -> Bool {
            guard !arr.isEmpty else { return false }
            guard let mn = arr.min(), let mx = arr.max(), mx > 0 else { return false }
            // Consider near-zero min and near-one max as normalized signature
            let nearZero = abs(mn) <= 1e-3
            let nearOne = abs(mx - 1.0) <= 1e-3
            return nearZero && nearOne
        }
        let normalizedCount = top.filter { looksNormalized01($0.sparklineIn7d) }.count
        if normalizedCount >= 3 { return true }

        return false
    }
}

