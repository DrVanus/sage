//
//  CoinbaseService.swift
//  CSAI1
//
//  Created by DM on 3/21/25.
//  Updated with improved error handling, retry logic, coin pair filtering, session reuse,
//  caching for invalid coin pair logging, Exchange endpoints, request headers, unified non-throwing retry for 24h stats, Retry-After handling, and in-memory caching with inflight de-duplication.
//

import Foundation

// MARK: – Coinbase Pro 24‑hr Stats Response
struct CoinbaseProStatsResponse: Decodable {
    let open: String
    let high: String
    let low: String
    let last: String
    let volume: String?
}

struct CoinbaseSpotPriceResponse: Decodable {
    let data: DataField?

    struct DataField: Decodable {
        let base: String
        let currency: String
        let amount: String
    }
}

struct CoinbaseExchangeTicker: Decodable {
    let price: String
}

// MARK: - Precious Metals Detection

/// Helper struct for identifying precious metals symbols from Coinbase
/// Coinbase offers gold, silver, copper, and platinum futures
enum PreciousMetalsHelper {
    /// Known precious metals symbols that Coinbase may use
    /// Includes both ISO currency codes and potential Coinbase-specific symbols
    static let preciousMetalsSymbols: Set<String> = [
        // ISO 4217 currency codes for precious metals
        "XAU", "GOLD",           // Gold
        "XAG", "SILVER",         // Silver
        "XPT", "PLATINUM", "PLT", // Platinum
        "XPD", "PALLADIUM", "PAL", // Palladium
        // Industrial metals (copper is now on Coinbase)
        "XCU", "COPPER", "CU",   // Copper
        // Additional variations Coinbase might use
        "GLD", "SLV", "PLAT", "COPR"
    ]
    
    /// Check if a symbol represents a precious metal or industrial metal commodity
    static func isPreciousMetal(_ symbol: String) -> Bool {
        preciousMetalsSymbols.contains(symbol.uppercased())
    }
    
    /// Get the display name for a precious metal symbol
    static func displayName(for symbol: String) -> String? {
        let upper = symbol.uppercased()
        switch upper {
        case "XAU", "GOLD", "GLD":
            return "Gold"
        case "XAG", "SILVER", "SLV":
            return "Silver"
        case "XPT", "PLATINUM", "PLT", "PLAT":
            return "Platinum"
        case "XPD", "PALLADIUM", "PAL":
            return "Palladium"
        case "XCU", "COPPER", "CU", "COPR":
            return "Copper"
        default:
            return nil
        }
    }
}

actor CoinbaseService {
    static let shared = CoinbaseService()
    
    // MARK: - Dynamic Products Cache (replaces hardcoded validPairs)
    // Fetches ALL available Coinbase trading pairs dynamically
    private var cachedProducts: Set<String> = []
    private var productsCacheTime: Date?
    private let productsCacheTTL: TimeInterval = 3600 // 1 hour - products list rarely changes
    private var productsFetchInFlight: Task<Set<String>, Never>?
    
    // Fallback pairs used only if dynamic fetch fails completely
    private let fallbackPairs: Set<String> = [
        // Major cryptocurrencies
        "BTC-USD","ETH-USD","USDT-USD","XRP-USD","SOL-USD",
        "USDC-USD","DOGE-USD","ADA-USD","AVAX-USD","LINK-USD",
        "DOT-USD","LTC-USD","BCH-USD","UNI-USD","XLM-USD",
        "NEAR-USD","APT-USD","ATOM-USD","AAVE-USD","SUI-USD",
        "SHIB-USD","HBAR-USD","FIL-USD","ARB-USD","OP-USD",
        // Precious metals (Coinbase futures)
        "XAU-USD", "GOLD-USD",       // Gold
        "XAG-USD", "SILVER-USD",     // Silver
        "XPT-USD", "PLATINUM-USD",   // Platinum
        "XCU-USD", "COPPER-USD",     // Copper
        "XPD-USD", "PALLADIUM-USD"   // Palladium
    ]
    
    // Circuit breaker for products endpoint
    private var productsFailureCount: Int = 0
    private var productsBlockedUntil: Date?
    private let productsMaxFailures: Int = 3
    private let productsBlockDuration: TimeInterval = 300 // 5 minutes
    
    private var invalidPairsLogged: Set<String> = []

    private lazy var session: URLSession = {
        // SECURITY: Ephemeral session prevents disk caching of account balances,
        // portfolio data, and order history that Coinbase API may return.
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        // SECURITY: Route through certificate pinning for MITM protection
        return CertificatePinningManager.shared.createPinnedSession(configuration: config)
    }()
    
    // MARK: - Fetch All Products from Coinbase
    
    /// Fetches all available trading pairs from Coinbase Exchange API.
    /// Returns cached results if still valid, otherwise fetches fresh data.
    private func fetchValidPairs() async -> Set<String> {
        // Return cached data if still valid
        if !cachedProducts.isEmpty, let time = productsCacheTime, Date().timeIntervalSince(time) < productsCacheTTL {
            return cachedProducts
        }
        
        // If a fetch is already in progress, await it
        if let existingTask = productsFetchInFlight {
            return await existingTask.value
        }
        
        // Start new fetch
        let task = Task<Set<String>, Never> {
            let result = await fetchProductsFromAPI()
            if !result.isEmpty {
                cachedProducts = result
                productsCacheTime = Date()
            }
            productsFetchInFlight = nil
            return result.isEmpty ? (cachedProducts.isEmpty ? fallbackPairs : cachedProducts) : result
        }
        
        productsFetchInFlight = task
        return await task.value
    }
    
    /// Fetches products directly from the Coinbase API
    private func fetchProductsFromAPI() async -> Set<String> {
        // Circuit breaker: skip if blocked due to repeated failures
        if let blockedUntil = productsBlockedUntil, Date() < blockedUntil {
            #if DEBUG
            print("⚠️ [CoinbaseService] Products endpoint blocked, using cached/fallback")
            #endif
            return cachedProducts.isEmpty ? fallbackPairs : cachedProducts
        }
        
        guard let url = URL(string: "https://api.exchange.coinbase.com/products") else {
            return cachedProducts.isEmpty ? fallbackPairs : cachedProducts
        }
        
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 15
        req.setValue("CryptoSage/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            var (data, response) = try await session.data(for: req)
            
            if let http = response as? HTTPURLResponse, http.statusCode == 429 {
                // Rate limited - record failure
                productsFailureCount += 1
                if productsFailureCount >= productsMaxFailures {
                    productsBlockedUntil = Date().addingTimeInterval(productsBlockDuration)
                    #if DEBUG
                    print("⚠️ [CoinbaseService] Products endpoint blocked for \(Int(productsBlockDuration))s")
                    #endif
                }
                // Retry once after short delay
                try? await Task.sleep(nanoseconds: 500_000_000)
                (data, response) = try await session.data(for: req)
            }
            
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                productsFailureCount += 1
                if productsFailureCount >= productsMaxFailures {
                    productsBlockedUntil = Date().addingTimeInterval(productsBlockDuration)
                }
                return cachedProducts.isEmpty ? fallbackPairs : cachedProducts
            }
            
            guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return cachedProducts.isEmpty ? fallbackPairs : cachedProducts
            }
            
            var products: Set<String> = []
            for item in arr {
                // Get the product ID (e.g., "BTC-USD")
                guard let productId = item["id"] as? String else { continue }
                // Only include online/active products
                if let status = item["status"] as? String, status.lowercased() != "online" { continue }
                products.insert(productId.uppercased())
            }
            
            // Success - reset failure count
            productsFailureCount = 0
            productsBlockedUntil = nil
            
            #if DEBUG
            print("✅ [CoinbaseService] Fetched \(products.count) Coinbase products dynamically")
            #endif
            
            return products
        } catch {
            #if DEBUG
            print("❌ [CoinbaseService] Failed to fetch products: \(error.localizedDescription)")
            #endif
            productsFailureCount += 1
            if productsFailureCount >= productsMaxFailures {
                productsBlockedUntil = Date().addingTimeInterval(productsBlockDuration)
            }
            return cachedProducts.isEmpty ? fallbackPairs : cachedProducts
        }
    }
    
    /// Check if a trading pair is valid (exists on Coinbase)
    private func isValidPair(_ product: String) async -> Bool {
        let validPairs = await fetchValidPairs()
        return validPairs.contains(product.uppercased())
    }
    
    /// Get all available base currencies (coins) from Coinbase
    func getAvailableCoins(quoteCurrency: String = "USD") async -> [String] {
        let validPairs = await fetchValidPairs()
        let suffix = "-\(quoteCurrency.uppercased())"
        return validPairs
            .filter { $0.hasSuffix(suffix) }
            .map { String($0.dropLast(suffix.count)) }
            .sorted()
    }

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    // Parse Retry-After header as seconds or HTTP-date to drive backoff
    private func retryAfterTTL(_ http: HTTPURLResponse) -> TimeInterval? {
        for (k, v) in http.allHeaderFields {
            if let ks = (k as? String)?.lowercased(), ks == "retry-after" {
                if let s = v as? String {
                    if let secs = TimeInterval(s.trimmingCharacters(in: .whitespacesAndNewlines)) { return secs }
                    let df = DateFormatter()
                    df.locale = Locale(identifier: "en_US_POSIX")
                    df.timeZone = TimeZone(secondsFromGMT: 0)
                    df.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
                    if let date = df.date(from: s) {
                        let delta = date.timeIntervalSinceNow
                        if delta.isFinite { return max(0, delta) }
                    }
                } else if let n = v as? NSNumber {
                    return n.doubleValue
                }
            }
        }
        return nil
    }

    // Simple in-memory caches and inflight de-duplication
    private struct SpotCacheEntry { let price: Double; let timestamp: Date }
    private var spotCache: [String: SpotCacheEntry] = [:]
    private let spotTTL: TimeInterval = 30 // seconds
    private let spotStaleMaxAge: TimeInterval = 300 // seconds

    private struct StatsCacheEntry { let stats: CoinPrice; let timestamp: Date }
    private var statsCache: [String: StatsCacheEntry] = [:]
    private let statsTTL: TimeInterval = 45 // seconds
    private let statsStaleMaxAge: TimeInterval = 300 // seconds

    private var inflightSpot: [String: Task<Double?, Never>] = [:]
    private var inflightStats: [String: Task<CoinPrice?, Never>] = [:]

    /// Fetch the current spot price with caching and inflight de-duplication.
    /// Tries Coinbase Exchange /ticker first, then falls back to Retail /v2/prices/spot.
    /// Honors Retry-After on 429 and uses simple exponential backoff with jitter for transient failures.
    func fetchSpotPrice(
        coin: String = "BTC",
        fiat: String = "USD",
        maxRetries: Int = 3,
        allowUnlistedPairs: Bool = true
    ) async -> Double? {
        let product = "\(coin.uppercased())-\(fiat.uppercased())"
        
        // Check if pair is valid using dynamic product list
        if !allowUnlistedPairs {
            let isValid = await isValidPair(product)
            if !isValid {
                if !invalidPairsLogged.contains(product) {
                    invalidPairsLogged.insert(product)
                    #if DEBUG
                    print("⚠️ [CoinbaseService] skipped invalid pair: \(product)")
                    #endif
                }
                return nil
            }
        }

        // Fresh cache
        if let entry = spotCache[product], Date().timeIntervalSince(entry.timestamp) < spotTTL {
            #if DEBUG
            // print("[CoinbaseService] spot cache hit for \(product)")
            #endif
            return entry.price
        }
        // Inflight de-dup
        if let existing = inflightSpot[product] {
            return await existing.value
        }

        let task = Task<Double?, Never> {
            // 1) Try Coinbase Exchange /ticker first
            if let url = URL(string: "https://api.exchange.coinbase.com/products/\(product)/ticker") {
                var attempt = 0
                while attempt < maxRetries {
                    attempt += 1
                    do {
                        var req = URLRequest(url: url)
                        req.httpMethod = "GET"
                        req.timeoutInterval = 10
                        req.setValue("CryptoSage/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
                        req.setValue("application/json", forHTTPHeaderField: "Accept")
                        let (data, response) = try await session.data(for: req)
                        guard let http = response as? HTTPURLResponse else { break }
                        if (200...299).contains(http.statusCode) {
                            let ticker = try decoder.decode(CoinbaseExchangeTicker.self, from: data)
                            if let price = Double(ticker.price) { return price }
                            break
                        }
                        // Handle rate limits and transient HTTPs
                        if http.statusCode == 429 {
                            let ttl = min(max(retryAfterTTL(http) ?? 2, 1), 600)
                            try? await Task.sleep(nanoseconds: UInt64(ttl * 1_000_000_000))
                            continue
                        }
                        if (500...599).contains(http.statusCode) {
                            let base = Double(attempt * 2)
                            let jitter = Double.random(in: 0.05...0.15)
                            try? await Task.sleep(nanoseconds: UInt64((base + jitter) * 1_000_000_000))
                            continue
                        }
                        // Non-retryable HTTP; fall through to Retail
                        break
                    } catch {
                        #if DEBUG
                        print("❌ [CoinbaseService] exchange ticker error for \(product) attempt \(attempt):", error)
                        #endif
                        if attempt < maxRetries {
                            let base = Double(attempt * 2)
                            let jitter = Double.random(in: 0.05...0.15)
                            try? await Task.sleep(nanoseconds: UInt64((base + jitter) * 1_000_000_000))
                        } else {
                            break
                        }
                    }
                }
            }

            // 2) Fallback to Coinbase Retail /v2/prices/spot
            if let url = URL(string: "https://api.coinbase.com/v2/prices/\(product)/spot") {
                var attempt = 0
                while attempt < maxRetries {
                    attempt += 1
                    do {
                        var req = URLRequest(url: url)
                        req.httpMethod = "GET"
                        req.timeoutInterval = 10
                        req.setValue("CryptoSage/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
                        req.setValue("application/json", forHTTPHeaderField: "Accept")
                        let (data, response) = try await session.data(for: req)
                        guard let http = response as? HTTPURLResponse else { return nil }
                        if (200...299).contains(http.statusCode) {
                            let resp = try decoder.decode(CoinbaseSpotPriceResponse.self, from: data)
                            if let field = resp.data, let price = Double(field.amount) { return price }
                            return nil
                        }
                        if http.statusCode == 429 {
                            let ttl = min(max(retryAfterTTL(http) ?? 2, 1), 600)
                            try? await Task.sleep(nanoseconds: UInt64(ttl * 1_000_000_000))
                            continue
                        }
                        if (500...599).contains(http.statusCode) {
                            let base = Double(attempt * 2)
                            let jitter = Double.random(in: 0.05...0.15)
                            try? await Task.sleep(nanoseconds: UInt64((base + jitter) * 1_000_000_000))
                            continue
                        }
                        return nil
                    } catch {
                        #if DEBUG
                        print("❌ [CoinbaseService] retail spot error for \(product) attempt \(attempt):", error)
                        #endif
                        if attempt < maxRetries {
                            let base = Double(attempt * 2)
                            let jitter = Double.random(in: 0.05...0.15)
                            try? await Task.sleep(nanoseconds: UInt64((base + jitter) * 1_000_000_000))
                        } else {
                            return nil
                        }
                    }
                }
            }
            return nil
        }

        inflightSpot[product] = task
        let result = await task.value
        inflightSpot[product] = nil

        if let price = result {
            spotCache[product] = SpotCacheEntry(price: price, timestamp: Date())
            return price
        } else if let stale = spotCache[product], Date().timeIntervalSince(stale.timestamp) < spotStaleMaxAge {
            return stale.price
        }
        return nil
    }

    /// Fetches 24‑hour open, high, low and last prices from Coinbase Exchange and maps into CoinPrice (change24h as percent).
    /// Retries transient failures, honors Retry-After on 429, caches fresh results, and returns stale data when available.
    func fetch24hStats(
        coin: String = "BTC",
        fiat: String = "USD",
        maxRetries: Int = 3,
        allowUnlistedPairs: Bool = true
    ) async -> CoinPrice? {
        let product = "\(coin.uppercased())-\(fiat.uppercased())"
        
        // Check if pair is valid using dynamic product list
        if !allowUnlistedPairs {
            let isValid = await isValidPair(product)
            if !isValid {
                if !invalidPairsLogged.contains(product) {
                    invalidPairsLogged.insert(product)
                    #if DEBUG
                    print("⚠️ [CoinbaseService] skipped invalid pair for stats: \(product)")
                    #endif
                }
                return nil
            }
        }

        // Fresh cache
        if let entry = statsCache[product], Date().timeIntervalSince(entry.timestamp) < statsTTL {
            #if DEBUG
            // print("[CoinbaseService] stats cache hit for \(product)")
            #endif
            return entry.stats
        }
        // Inflight de-dup
        if let existing = inflightStats[product] {
            return await existing.value
        }

        let task = Task<CoinPrice?, Never> {
            guard let url = URL(string: "https://api.exchange.coinbase.com/products/\(product)/stats") else {
                return nil
            }
            var attempt = 0
            while attempt < maxRetries {
                attempt += 1
                do {
                    var request = URLRequest(url: url)
                    request.httpMethod = "GET"
                    request.timeoutInterval = 10
                    request.setValue("CryptoSage/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
                    request.setValue("application/json", forHTTPHeaderField: "Accept")

                    let (data, response) = try await session.data(for: request)
                    guard let http = response as? HTTPURLResponse else { return nil }
                    if (200...299).contains(http.statusCode) {
                        let resp = try decoder.decode(CoinbaseProStatsResponse.self, from: data)
                        guard
                            let last = Double(resp.last),
                            let openParsed = Double(resp.open),
                            let high = Double(resp.high),
                            let low = Double(resp.low)
                        else {
                            return nil
                        }
                        let open = openParsed > 0 ? openParsed : last
                        let changePct: Double = (open > 0) ? ((last - open) / open) * 100.0 : 0
                        let baseVolume = Double(resp.volume ?? "") ?? 0
                        let volumeUSD = (baseVolume > 0 && last > 0) ? (baseVolume * last) : 0
                        return CoinPrice(
                            symbol: coin.lowercased(),
                            lastPrice: last,
                            openPrice: open,
                            highPrice: high,
                            lowPrice: low,
                            volume: volumeUSD > 0 ? volumeUSD : nil,
                            change24h: changePct
                        )
                    }
                    if http.statusCode == 429 {
                        let ttl = min(max(retryAfterTTL(http) ?? 2, 1), 600)
                        try? await Task.sleep(nanoseconds: UInt64(ttl * 1_000_000_000))
                        continue
                    }
                    if (500...599).contains(http.statusCode) {
                        let base = Double(attempt * 2)
                        let jitter = Double.random(in: 0.05...0.15)
                        try? await Task.sleep(nanoseconds: UInt64((base + jitter) * 1_000_000_000))
                        continue
                    }
                    return nil
                } catch {
                    #if DEBUG
                    print("❌ [CoinbaseService] network error fetching 24‑hr stats for \(product) attempt \(attempt):", error)
                    #endif
                    if attempt < maxRetries {
                        let base = Double(attempt * 2)
                        let jitter = Double.random(in: 0.05...0.15)
                        try? await Task.sleep(nanoseconds: UInt64((base + jitter) * 1_000_000_000))
                    } else {
                        return nil
                    }
                }
            }
            return nil
        }

        inflightStats[product] = task
        let result = await task.value
        inflightStats[product] = nil

        if let stats = result {
            statsCache[product] = StatsCacheEntry(stats: stats, timestamp: Date())
            return stats
        } else if let stale = statsCache[product], Date().timeIntervalSince(stale.timestamp) < statsStaleMaxAge {
            return stale.stats
        }
        return nil
    }

    /// Invalidate cached entries for a single coin/fiat pair.
    func invalidate(coin: String, fiat: String = "USD") {
        let product = "\(coin.uppercased())-\(fiat.uppercased())"
        spotCache.removeValue(forKey: product)
        statsCache.removeValue(forKey: product)
        inflightSpot[product] = nil
        inflightStats[product] = nil
    }

    /// Fetch spot prices for multiple coins with bounded concurrency and reuse of per-coin cache.
    func fetchSpotPrices(
        for coins: [String],
        fiat: String = "USD",
        maxConcurrency: Int = 4
    ) async -> [String: Double] {
        let uniq = Array(Set(coins.map { $0.uppercased() })).sorted()
        guard !uniq.isEmpty else { return [:] }
        
        // FIX: Check coordinator before batch Coinbase requests
        guard APIRequestCoordinator.shared.canMakeRequest(for: .coinbase) else {
            #if DEBUG
            print("[CoinbaseService] fetchSpotPrices blocked by coordinator")
            #endif
            return [:]
        }
        APIRequestCoordinator.shared.recordRequest(for: .coinbase)
        
        var results: [String: Double] = [:]
        // FIX: Reduced max concurrency to 3 to prevent flooding
        let limit = max(1, min(maxConcurrency, 3))
        var index = 0
        await withTaskGroup(of: (String, Double?).self) { group in
            let initial = min(limit, uniq.count)
            if initial > 0 {
                for i in 0..<initial {
                    let coin = uniq[i]
                    group.addTask { [coin] in
                        let price = await self.fetchSpotPrice(coin: coin, fiat: fiat)
                        return (coin, price)
                    }
                }
                index = initial
            }
            while let (coin, price) = await group.next() {
                if let p = price { results[coin] = p }
                if index < uniq.count {
                    let coinNext = uniq[index]; index += 1
                    group.addTask { [coinNext] in
                        let price = await self.fetchSpotPrice(coin: coinNext, fiat: fiat)
                        return (coinNext, price)
                    }
                }
            }
        }
        return results
    }

    /// Fetch 24h stats for multiple coins with bounded concurrency and reuse of per-coin cache.
    func fetch24hStats(
        for coins: [String],
        fiat: String = "USD",
        maxConcurrency: Int = 4
    ) async -> [CoinPrice] {
        let uniq = Array(Set(coins.map { $0.uppercased() })).sorted()
        guard !uniq.isEmpty else { return [] }
        
        // FIX: Check coordinator before batch Coinbase requests
        guard APIRequestCoordinator.shared.canMakeRequest(for: .coinbase) else {
            #if DEBUG
            print("[CoinbaseService] fetch24hStats blocked by coordinator")
            #endif
            return []
        }
        APIRequestCoordinator.shared.recordRequest(for: .coinbase)
        
        var out: [CoinPrice] = []
        // FIX: Reduced max concurrency to 3 to prevent flooding
        let limit = max(1, min(maxConcurrency, 3))
        var index = 0
        await withTaskGroup(of: CoinPrice?.self) { group in
            let initial = min(limit, uniq.count)
            if initial > 0 {
                for i in 0..<initial {
                    let coin = uniq[i]
                    group.addTask { [coin] in
                        return await self.fetch24hStats(coin: coin, fiat: fiat)
                    }
                }
                index = initial
            }
            while let res = await group.next() {
                if let s = res { out.append(s) }
                if index < uniq.count {
                    let coinNext = uniq[index]; index += 1
                    group.addTask { [coinNext] in
                        return await self.fetch24hStats(coin: coinNext, fiat: fiat)
                    }
                }
            }
        }
        return out
    }

    /// Clear all in-memory caches for spot and stats.
    func clearCache() {
        spotCache.removeAll()
        statsCache.removeAll()
        inflightSpot.removeAll()
        inflightStats.removeAll()
    }
    
    /// Clear products cache to force a refresh on next request.
    func clearProductsCache() {
        cachedProducts.removeAll()
        productsCacheTime = nil
        productsFailureCount = 0
        productsBlockedUntil = nil
    }
    
    /// Force refresh the products list from Coinbase API.
    /// Call this on app launch or when user wants fresh data.
    func refreshProducts() async {
        clearProductsCache()
        _ = await fetchValidPairs()
    }
    
    /// Get the count of available trading pairs (for diagnostics).
    func getProductsCount() async -> Int {
        let products = await fetchValidPairs()
        return products.count
    }
    
    /// Get all unique base symbols available on Coinbase (e.g., BTC, ETH, RLC).
    /// This extracts the base currency from all USD trading pairs.
    /// Returns uppercased symbols sorted alphabetically.
    func getAllCoinbaseSymbols() async -> [String] {
        let products = await fetchValidPairs()
        // Extract base symbols from USD pairs (e.g., "BTC-USD" -> "BTC")
        var symbols: Set<String> = []
        for product in products {
            let parts = product.split(separator: "-")
            if parts.count >= 2 {
                let base = String(parts[0]).uppercased()
                let quote = String(parts[1]).uppercased()
                // Only include USD pairs to get unique base coins
                if quote == "USD" || quote == "USDT" || quote == "USDC" {
                    // Skip stablecoins and fiat
                    if !["USD", "USDT", "USDC", "BUSD", "DAI", "EUR", "GBP"].contains(base) {
                        symbols.insert(base)
                    }
                }
            }
        }
        return Array(symbols).sorted()
    }
}

