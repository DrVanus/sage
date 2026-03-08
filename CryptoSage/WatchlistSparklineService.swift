import Foundation

/// Actor-based service for fetching and caching 7D sparkline data from Binance.
/// Thread-safe and designed for use with SwiftUI views.
/// Persists cache to disk for instant sparklines on app launch.
/// Implements retry logic with backoff for failed fetches.
actor WatchlistSparklineService {
    
    static let shared = WatchlistSparklineService()
    
    // MARK: - Cache Storage
    
    /// Cache file name for disk persistence
    private static let cacheFileName = "watchlist_sparklines_cache.json"
    private static let freshnessFileName = "watchlist_sparklines_freshness.json"
    
    /// Cached sparkline data keyed by coin ID (e.g., "bitcoin", "ethereum")
    private var cache: [String: [Double]]
    
    /// Last successful update timestamp per coin ID.
    private var freshnessByID: [String: Date] = [:]
    
    /// Set of coin IDs that have been successfully fetched
    private var successfulIDs: Set<String> = []
    
    /// Coin IDs that failed to fetch, with timestamp of last attempt
    private var failedFetchAttempts: [String: Date] = [:]
    
    /// Retry cooldown for failed fetches (15 seconds for faster first-launch recovery)
    private let retryCooldown: TimeInterval = 15
    
    /// Maximum retry attempts per session before giving up
    private var retryCountByID: [String: Int] = [:]
    private let maxRetryAttempts: Int = 3
    
    /// Timestamp of last fetch to enable periodic refresh
    private var lastFetchTime: Date = .distantPast
    
    /// Minimum interval between full refreshes (3 minutes - reduced from 5 for better responsiveness)
    private let refreshInterval: TimeInterval = 180
    
    /// A sparkline is considered fresh for this window.
    private let freshnessTTL: TimeInterval = 600
    
    // MARK: - Initialization
    
    private init() {
        // STALE DATA FIX: Only use Documents cache (real data from previous API calls).
        // Do NOT fall back to bundled seed - it contains stale sparkline data from build time
        // that shows wrong trends (e.g., green/up sparklines when market is actually down).
        // On first launch, sparklines will be empty until live data loads from Binance/CoinGecko.
        if let docCache = Self.loadCacheFromDisk(), !docCache.isEmpty {
            self.cache = docCache
        } else {
            // First launch: start with empty cache, live data will populate it
            self.cache = [:]
            #if DEBUG
            print("[WatchlistSparklineService] First launch: starting with empty cache, awaiting live data")
            #endif
        }
        // Mark cached IDs as successful
        self.successfulIDs = Set(self.cache.keys)
        self.freshnessByID = Self.loadFreshnessFromDisk() ?? [:]
    }
    
    /// Loads sparkline cache from disk (called during init)
    private static func loadCacheFromDisk() -> [String: [Double]]? {
        return CacheManager.shared.load([String: [Double]].self, from: cacheFileName)
    }
    
    private static func loadFreshnessFromDisk() -> [String: Date]? {
        guard let raw = CacheManager.shared.load([String: TimeInterval].self, from: freshnessFileName) else {
            return nil
        }
        return raw.reduce(into: [:]) { partialResult, pair in
            partialResult[pair.key] = Date(timeIntervalSince1970: pair.value)
        }
    }
    
    /// Loads pre-seeded sparkline data from the app bundle (for first launch)
    private static func loadBundledSparklineSeed() -> [String: [Double]]? {
        guard let url = Bundle.main.url(forResource: "watchlist_sparklines_seed", withExtension: "json") else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([String: [Double]].self, from: data)
        } catch {
            #if DEBUG
            print("[WatchlistSparklineService] Failed to load bundled seed: \(error.localizedDescription)")
            #endif
            return nil
        }
    }
    
    /// Synchronously loads cached sparklines from disk.
    /// Use this for instant UI initialization (non-actor context).
    /// This bypasses the actor to allow synchronous access during View init.
    /// STALE DATA FIX: Does NOT fall back to bundled seed - only returns real data
    /// from previous API calls. Returns empty on first launch.
    static func loadCachedSparklinesSync() -> [String: [Double]] {
        // Only use Documents cache (real data from previous API calls)
        if let docCache = CacheManager.shared.loadFromDocumentsOnly([String: [Double]].self, from: cacheFileName), !docCache.isEmpty {
            return docCache
        }
        // First launch: return empty, live data will populate it
        return [:]
    }
    
    /// Saves current cache to disk
    private func saveCacheToDisk() {
        let cacheToSave = cache
        let freshnessToSave = freshnessByID.reduce(into: [String: TimeInterval]()) { partialResult, pair in
            partialResult[pair.key] = pair.value.timeIntervalSince1970
        }
        Task.detached(priority: .background) {
            CacheManager.shared.save(cacheToSave, to: Self.cacheFileName)
            CacheManager.shared.save(freshnessToSave, to: Self.freshnessFileName)
        }
    }
    
    private func isFresh(_ coinID: String, now: Date = Date()) -> Bool {
        guard let updatedAt = freshnessByID[coinID] else { return false }
        return now.timeIntervalSince(updatedAt) <= freshnessTTL
    }
    
    // MARK: - Public API
    
    /// Returns cached sparkline data for a coin, or nil if not available
    func getSparkline(for coinID: String) -> [Double]? {
        return cache[coinID]
    }
    
    /// Returns true if sparkline data exists in cache for the given coin
    func hasSparkline(for coinID: String) -> Bool {
        return cache[coinID] != nil && !(cache[coinID]?.isEmpty ?? true)
    }
    
    /// Clears the fetch history to allow re-fetching (useful for refresh)
    func clearFetchHistory() {
        successfulIDs.removeAll()
        failedFetchAttempts.removeAll()
        retryCountByID.removeAll()
    }
    
    /// Clears all cached data and fetch history
    func clearAll() {
        cache.removeAll()
        successfulIDs.removeAll()
        freshnessByID.removeAll()
        failedFetchAttempts.removeAll()
        retryCountByID.removeAll()
        lastFetchTime = .distantPast
    }
    
    /// Returns true if enough time has passed for a refresh
    func shouldRefresh() -> Bool {
        return Date().timeIntervalSince(lastFetchTime) >= refreshInterval
    }
    
    /// Checks if a coin ID can be retried (cooldown passed and under max attempts)
    private func canRetry(_ coinID: String) -> Bool {
        // Check retry count
        let attempts = retryCountByID[coinID] ?? 0
        if attempts >= maxRetryAttempts {
            return false
        }
        
        // Check cooldown
        if let lastAttempt = failedFetchAttempts[coinID] {
            let timeSince = Date().timeIntervalSince(lastAttempt)
            // Exponential backoff: 60s, 120s, 240s
            let backoff = retryCooldown * pow(2.0, Double(attempts))
            return timeSince >= backoff
        }
        
        return true
    }
    
    /// Fetches sparklines for the given coins that haven't been fetched yet.
    /// Includes retry logic for previously failed fetches after cooldown.
    /// Returns the IDs of coins that were successfully fetched.
    @discardableResult
    func fetchSparklines(for coins: [(id: String, symbol: String)]) async -> [String] {
        let now = Date()
        
        // SPARKLINE FIX: First, immediately populate cache from CoinGecko data for any coins
        // that don't have sparkline data yet. This ensures instant display while Binance fetches.
        await populateFromCoinGecko(coins: coins)
        
        // Filter coins: include those not yet successful AND (never tried OR can retry)
        let coinsToFetch = coins.filter { coin in
            // Already have successful data with good quality (60+ points from Binance)
            if successfulIDs.contains(coin.id),
               let cached = cache[coin.id],
               cached.count >= 60,
               isFresh(coin.id, now: now) {
                return false
            }
            
            // Never tried before
            if failedFetchAttempts[coin.id] == nil {
                return true
            }
            
            // Can retry after cooldown
            return canRetry(coin.id)
        }
        
        let freshCachedCount = coins.count - coinsToFetch.count
        // Only log when actually fetching (skip if all cached) and keep it concise
        if !coinsToFetch.isEmpty {
            #if DEBUG
            print("[SparklineService] fetch=\(coinsToFetch.count) cached=\(freshCachedCount) of \(coins.count)")
            #endif
        }
        
        guard !coinsToFetch.isEmpty else { return [] }
        
        var newSuccessfulIDs: [String] = []
        
        await withTaskGroup(of: (String, String, [Double]).self) { group in
            for coin in coinsToFetch {
                group.addTask {
                    let series = await Self.fetchHourlySparkline(symbol: coin.symbol, coinID: coin.id)
                    return (coin.id, coin.symbol, series)
                }
            }
            
            for await (id, _, series) in group {
                // Check if fetch was successful
                if !series.isEmpty && series.allSatisfy({ $0.isFinite && $0 > 0 }) {
                    // SPARKLINE FIX: Only replace existing data if new data is better quality
                    let existingCount = cache[id]?.count ?? 0
                    if series.count > existingCount || existingCount < 10 {
                        // Success - cache the data and mark as successful
                        cache[id] = series
                        freshnessByID[id] = now
                        newSuccessfulIDs.append(id)
                    }
                    
                    // Mark as successful if we got high-quality Binance data (60+ points)
                    if series.count >= 60 {
                        successfulIDs.insert(id)
                        // Clear failure tracking
                        failedFetchAttempts.removeValue(forKey: id)
                        retryCountByID.removeValue(forKey: id)
                    }
                } else {
                    // Failure - track for retry (but don't clear existing CoinGecko data)
                    failedFetchAttempts[id] = now
                    retryCountByID[id] = (retryCountByID[id] ?? 0) + 1
                }
            }
        }
        
        lastFetchTime = now
        
        // Persist cache to disk if we got any new data
        if !newSuccessfulIDs.isEmpty {
            saveCacheToDisk()
        }
        
        return newSuccessfulIDs
    }
    
    /// SPARKLINE FIX: Immediately populate cache from CoinGecko data for coins without sparklines.
    /// This ensures sparklines appear instantly for newly favorited coins.
    private func populateFromCoinGecko(coins: [(id: String, symbol: String)]) async {
        // First, get the coins that need data (check cache within actor context)
        let coinsNeedingData = coins.filter { coin in
            guard let existing = cache[coin.id] else { return true }
            return existing.count < 10
        }
        
        guard !coinsNeedingData.isEmpty else { return }
        
        // Fetch sparklines from main actor (MarketViewModel and LivePriceManager are MainActor-isolated)
        let sparklineData = await MainActor.run {
            var result: [String: [Double]] = [:]
            let allCoins = MarketViewModel.shared.allCoins
            let lpmCoins = LivePriceManager.shared.currentCoinsList
            
            for coin in coinsNeedingData {
                var sparkline: [Double] = []
                
                // Try MarketViewModel first
                if let marketCoin = allCoins.first(where: { $0.id == coin.id }) {
                    sparkline = marketCoin.sparklineIn7d.filter { $0.isFinite && $0 > 0 }
                }
                
                // Fall back to LivePriceManager
                if sparkline.count < 10 {
                    if let lpmCoin = lpmCoins.first(where: { $0.id == coin.id }) {
                        sparkline = lpmCoin.sparklineIn7d.filter { $0.isFinite && $0 > 0 }
                    }
                }
                
                if sparkline.count >= 10 {
                    result[coin.id] = sparkline
                }
            }
            return result
        }
        
        if !sparklineData.isEmpty {
            #if DEBUG
            print("[WatchlistSparklineService] CoinGecko bootstrap filled \(sparklineData.count) sparkline(s)")
            #endif
        }
        
        // Update cache within actor context
        for (coinID, sparkline) in sparklineData {
            cache[coinID] = sparkline
            freshnessByID[coinID] = Date()
        }
    }
    
    /// Forces a refresh of sparklines for the given coins, clearing their fetch history first
    @discardableResult
    func refreshSparklines(for coins: [(id: String, symbol: String)]) async -> [String] {
        // Clear fetch history for these coins to allow re-fetch
        for coin in coins {
            successfulIDs.remove(coin.id)
            failedFetchAttempts.removeValue(forKey: coin.id)
            retryCountByID.removeValue(forKey: coin.id)
        }
        let result = await fetchSparklines(for: coins)
        // Save is already called in fetchSparklines
        return result
    }
    
    /// Returns all cached sparklines (for bulk loading into view state)
    func getAllCachedSparklines() -> [String: [Double]] {
        return cache
    }
    
    /// Returns the count of coins pending retry (for diagnostics)
    func pendingRetryCount() -> Int {
        return failedFetchAttempts.filter { id, _ in canRetry(id) }.count
    }
    
    // MARK: - Binance Fetch Implementation
    
    /// Fetches 7-day hourly close prices from Binance (168 data points).
    /// Uses parallel endpoint attempts for faster response on first launch.
    /// Falls back to 4-hour intervals, then daily data, then CoinGecko sparklines if Binance fails.
    private static func fetchHourlySparkline(symbol: String, coinID: String? = nil) async -> [Double] {
        let upperSymbol = symbol.uppercased()
        
        // PERFORMANCE FIX: Skip symbols that are known to not exist on Binance
        // These are typically wrapped tokens, stablecoins, or obscure altcoins
        let invalidPrefixes = ["WBTC", "WETH", "STETH", "WSTETH", "WBETH", "WEETH", "CBBTC", "USDE", "USDT0"]
        let skipBinance = invalidPrefixes.contains(where: { upperSymbol.hasPrefix($0) })
        
        // PERFORMANCE FIX: Skip malformed symbols (detect concatenated coin IDs)
        // Valid symbols are typically 2-6 characters before the quote currency
        let baseLength = upperSymbol
            .replacingOccurrences(of: "USDT", with: "")
            .replacingOccurrences(of: "USDC", with: "")
            .replacingOccurrences(of: "USD", with: "")
            .count
        let isMalformed = baseLength > 10
        
        // Try Binance first (unless we know it won't work)
        if !skipBinance && !isMalformed {
            let binanceResult = await fetchFromBinance(symbol: upperSymbol)
            if !binanceResult.isEmpty {
                return binanceResult
            }
        }
        
        // SPARKLINE FIX: Fall back to CoinGecko sparkline data from MarketViewModel
        // This ensures sparklines always show, even when Binance is rate-limited or geo-blocked
        let geckoSparkline = await fetchFromCoinGecko(symbol: symbol, coinID: coinID)
        if !geckoSparkline.isEmpty {
            return geckoSparkline
        }
        
        // Final fallback: BinanceService (may have cached data)
        return await BinanceService.fetchSparkline(symbol: symbol)
    }
    
    /// Fetches sparkline data from Binance API
    private static func fetchFromBinance(symbol: String) async -> [Double] {
        let upperSymbol = symbol.uppercased()
        
        // Try multiple pair formats
        let pairsToTry: [String]
        if upperSymbol.hasSuffix("USDT") || upperSymbol.hasSuffix("USD") || upperSymbol.hasSuffix("USDC") {
            pairsToTry = [upperSymbol]
        } else {
            // Try USDT first (most common), then USD
            pairsToTry = [upperSymbol + "USDT", upperSymbol + "USD"]
        }
        
        // PERFORMANCE FIX: Check if global Binance is geo-blocked and only use working endpoint
        // This prevents timeout floods when api.binance.com is blocked (HTTP 451)
        // Binance.US is shut down - use global Binance mirrors only
        let endpoints: [String]
        if await ExchangeHostPolicy.shared.isGlobalBinanceBlocked() {
            // Use mirror if global is geo-blocked
            endpoints = ["https://api4.binance.com/api/v3/klines"]
        } else {
            // Try global first, then mirror as fallback
            endpoints = [
                "https://api.binance.com/api/v3/klines",
                "https://api4.binance.com/api/v3/klines"
            ]
        }
        
        // Interval configurations to try: hourly (168 pts), 4-hour (42 pts), daily (7 pts)
        let intervalConfigs: [(interval: String, limit: String, minPoints: Int)] = [
            ("1h", "168", 48),   // 7 days hourly, need at least 2 days
            ("4h", "42", 12),    // 7 days 4-hourly, need at least 2 days
            ("1d", "7", 3)       // 7 days daily, need at least 3 days
        ]
        
        // Try hourly first with parallel endpoint attempts
        for pair in pairsToTry {
            let (interval, limit, minPoints) = intervalConfigs[0] // hourly
            
            // Try endpoints in parallel, return first successful result
            let result = await withTaskGroup(of: [Double].self, returning: [Double].self) { group in
                for endpoint in endpoints {
                    group.addTask {
                        return await Self.tryFetchKlines(endpoint: endpoint, pair: pair, interval: interval, limit: limit, minPoints: minPoints)
                    }
                }
                
                // Return first non-empty result
                for await sparkline in group {
                    if !sparkline.isEmpty {
                        group.cancelAll()
                        return sparkline
                    }
                }
                return []
            }
            
            if !result.isEmpty {
                return result
            }
        }
        
        // If hourly fails, try other intervals sequentially (less common)
        for pair in pairsToTry {
            for (interval, limit, minPoints) in intervalConfigs.dropFirst() {
                for endpoint in endpoints {
                    let result = await tryFetchKlines(endpoint: endpoint, pair: pair, interval: interval, limit: limit, minPoints: minPoints)
                    if !result.isEmpty {
                        return result
                    }
                }
            }
        }
        
        return []
    }
    
    /// Fetches sparkline data from CoinGecko (via MarketViewModel's cached data)
    /// This is the primary fallback when Binance is blocked or rate-limited
    private static func fetchFromCoinGecko(symbol: String, coinID: String?) async -> [Double] {
        let upperSymbol = symbol.uppercased()
        
        // Access MainActor-isolated data
        return await MainActor.run {
            // Try to find the coin in MarketViewModel's cached data
            let allCoins = MarketViewModel.shared.allCoins
            
            // First try by coinID if provided
            if let coinID = coinID,
               let coin = allCoins.first(where: { $0.id == coinID }) {
                let sparkline = coin.sparklineIn7d.filter { $0.isFinite && $0 > 0 }
                if sparkline.count >= 10 {
                    return sparkline
                }
            }
            
            // Fall back to matching by symbol
            if let coin = allCoins.first(where: { $0.symbol.uppercased() == upperSymbol }) {
                let sparkline = coin.sparklineIn7d.filter { $0.isFinite && $0 > 0 }
                if sparkline.count >= 10 {
                    return sparkline
                }
            }
            
            // Try LivePriceManager's coin list as another source
            let lpmCoins = LivePriceManager.shared.currentCoinsList
            if let coinID = coinID,
               let coin = lpmCoins.first(where: { $0.id == coinID }) {
                let sparkline = coin.sparklineIn7d.filter { $0.isFinite && $0 > 0 }
                if sparkline.count >= 10 {
                    return sparkline
                }
            }
            
            if let coin = lpmCoins.first(where: { $0.symbol.uppercased() == upperSymbol }) {
                let sparkline = coin.sparklineIn7d.filter { $0.isFinite && $0 > 0 }
                if sparkline.count >= 10 {
                    return sparkline
                }
            }
            
            return []
        }
    }
    
    /// Helper to fetch klines from a single endpoint
    private static func tryFetchKlines(endpoint: String, pair: String, interval: String, limit: String, minPoints: Int) async -> [Double] {
        guard var components = URLComponents(string: endpoint) else { return [] }
        components.queryItems = [
            URLQueryItem(name: "symbol", value: pair),
            URLQueryItem(name: "interval", value: interval),
            URLQueryItem(name: "limit", value: limit)
        ]
        guard let url = components.url else { return [] }
        
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8 // Reduced from 10 for faster fallback
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return [] }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [[Any]] else { return [] }
            
            // Binance klines format: [open_time, open, high, low, close, volume, close_time, ...]
            // Extract close prices (index 4)
            let closes = json.compactMap { arr -> Double? in
                guard arr.count > 4 else { return nil }
                if let s = arr[4] as? String, let v = Double(s), v > 0 { return v }
                if let v = arr[4] as? Double, v > 0 { return v }
                return nil
            }
            
            if closes.count >= minPoints {
                return closes
            }
        } catch {
            // Silently fail, will try next endpoint
        }
        return []
    }
}

