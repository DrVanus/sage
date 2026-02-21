//
//  PumpFunService.swift
//  CryptoSage
//
//  Service for tracking newly launched tokens from Pump.fun on Solana.
//  Provides real-time updates for meme coins and new token launches.
//

import Foundation
import Combine

/// Service for fetching and tracking tokens from Pump.fun
@MainActor
final class PumpFunService: ObservableObject {
    
    static let shared = PumpFunService()
    
    // MARK: - Published Properties
    
    /// Recently launched tokens from Pump.fun
    @Published private(set) var recentTokens: [PumpFunToken] = []
    
    /// Trending/graduated tokens that have gained traction
    @Published private(set) var trendingTokens: [PumpFunToken] = []
    
    /// Indicates if we're showing cached data due to API failure
    @Published private(set) var isUsingCachedData: Bool = false
    
    /// Publisher for new token alerts
    let newTokenPublisher = PassthroughSubject<PumpFunToken, Never>()
    
    // MARK: - Private Properties
    
    private var lastFetchAt: Date = .distantPast
    private let fetchCooldown: TimeInterval = 60 // 1 minute
    private var isConnected = false
    
    // API endpoints (Pump.fun's public API)
    private let baseURL = "https://frontend-api.pump.fun"
    
    // Minimum SOL liquidity to consider a token significant
    private let minimumLiquiditySOL: Double = 10
    
    // MARK: - Caching
    
    private let recentTokensCacheFile = "pumpfun_recent_tokens.json"
    private let trendingTokensCacheFile = "pumpfun_trending_tokens.json"
    
    /// Circuit breaker: track consecutive failures to avoid hammering a down service
    private var consecutiveFailures: Int = 0
    private var serviceBlockedUntil: Date? = nil
    private let maxConsecutiveFailures: Int = 3
    private let serviceBlockDuration5xx: TimeInterval = 120 // 2 minutes for transient server errors
    private let serviceBlockDuration4xx: TimeInterval = 300 // 5 minutes for client/permanent errors
    
    /// Exponential backoff delays for retries (1s, 2s, 4s)
    private let retryDelays: [UInt64] = [1_000_000_000, 2_000_000_000, 4_000_000_000]
    private let maxRetries: Int = 3
    
    private init() {
        // PERFORMANCE FIX v18: Defer cache loading to after first frame
        // PumpFun data isn't visible on initial home screen render
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000) // 400ms
            self.loadCachedTokens()
        }
    }
    
    /// Load tokens from disk cache
    private func loadCachedTokens() {
        if let cached: [PumpFunToken] = CacheManager.shared.load([PumpFunToken].self, from: recentTokensCacheFile) {
            recentTokens = cached
            isUsingCachedData = true
            #if DEBUG
            print("[PumpFunService] Loaded \(cached.count) recent tokens from cache")
            #endif
        }
        if let cached: [PumpFunToken] = CacheManager.shared.load([PumpFunToken].self, from: trendingTokensCacheFile) {
            trendingTokens = cached
            #if DEBUG
            print("[PumpFunService] Loaded \(cached.count) trending tokens from cache")
            #endif
        }
    }
    
    /// Save tokens to disk cache
    private func cacheRecentTokens(_ tokens: [PumpFunToken]) {
        CacheManager.shared.save(tokens, to: recentTokensCacheFile)
    }
    
    private func cacheTrendingTokens(_ tokens: [PumpFunToken]) {
        CacheManager.shared.save(tokens, to: trendingTokensCacheFile)
    }
    
    /// Check if the service is blocked due to repeated failures
    private func isServiceBlocked() -> Bool {
        if let blockedUntil = serviceBlockedUntil {
            if Date() < blockedUntil {
                return true
            } else {
                // Block expired, reset
                serviceBlockedUntil = nil
                consecutiveFailures = 0
            }
        }
        return false
    }
    
    /// Record a failure and potentially trigger circuit breaker
    /// Uses the shorter 5xx duration since repeated failures suggest transient issues
    private func recordFailure() {
        consecutiveFailures += 1
        if consecutiveFailures >= maxConsecutiveFailures {
            serviceBlockedUntil = Date().addingTimeInterval(serviceBlockDuration5xx)
            #if DEBUG
            print("[PumpFunService] Circuit breaker triggered - blocking service for \(Int(serviceBlockDuration5xx))s")
            #endif
        }
    }
    
    /// Record a success, resetting the failure counter
    private func recordSuccess() {
        consecutiveFailures = 0
        isUsingCachedData = false
    }
    
    // MARK: - Token Model
    
    struct PumpFunToken: Identifiable, Codable {
        let mint: String // Token mint address
        let name: String
        let symbol: String
        let description: String?
        let imageUri: String?
        let createdTimestamp: Int64
        let marketCapSol: Double?
        let usdMarketCap: Double?
        let replyCount: Int?
        let lastReply: Int64?
        let creator: String?
        let raydiumPool: String? // nil if not yet graduated to Raydium
        let complete: Bool? // true if bonding curve is complete
        
        var id: String { mint }
        
        var isGraduated: Bool { raydiumPool != nil || complete == true }
        
        var createdDate: Date {
            Date(timeIntervalSince1970: Double(createdTimestamp) / 1000.0)
        }
        
        var ageInHours: Int {
            let seconds = Date().timeIntervalSince(createdDate)
            return Int(seconds / 3600)
        }
        
        var imageURL: URL? {
            guard let uri = imageUri else { return nil }
            return URL(string: uri)
        }
        
        /// Convert to MarketCoin for integration with the main market list
        func toMarketCoin(solPrice: Double) -> MarketCoin {
            let priceUsd = (usdMarketCap ?? (marketCapSol ?? 0) * solPrice) / 1_000_000_000 // Assuming 1B supply
            
            return MarketCoin(
                id: "pumpfun-\(mint.prefix(8))",
                symbol: symbol.uppercased(),
                name: name,
                imageUrl: imageURL,
                priceUsd: priceUsd,
                marketCap: usdMarketCap ?? (marketCapSol ?? 0) * solPrice,
                totalVolume: nil, // Not provided by Pump.fun
                priceChangePercentage1hInCurrency: nil,
                priceChangePercentage24hInCurrency: nil,
                priceChangePercentage7dInCurrency: nil,
                sparklineIn7d: [],
                marketCapRank: nil,
                maxSupply: 1_000_000_000,
                circulatingSupply: 1_000_000_000,
                totalSupply: 1_000_000_000
            )
        }
    }
    
    // MARK: - API Response Models
    
    private struct CoinsResponse: Decodable {
        let coins: [PumpFunToken]?
    }
    
    // MARK: - Fetching Methods (Firebase-backed)
    
    /// Fetch recently created tokens via Firebase proxy
    func fetchRecentTokens() async {
        let now = Date()
        guard now.timeIntervalSince(lastFetchAt) > fetchCooldown else { return }
        
        // Check circuit breaker before making request
        if isServiceBlocked() {
            #if DEBUG
            print("[PumpFunService] Service blocked by circuit breaker, using cached data")
            #endif
            return // Will use cached data
        }
        
        lastFetchAt = now
        
        // Try Firebase first (preferred - no geo-blocking)
        if FirebaseService.shared.shouldUseFirebase {
            do {
                let response = try await FirebaseService.shared.getPumpFunTokens(type: "recent")
                let tokens = response.tokens.map { convertToToken($0) }
                
                // Filter to tokens with minimum liquidity
                let filtered = tokens.filter { ($0.marketCapSol ?? 0) >= minimumLiquiditySOL }
                
                // Check for truly new tokens
                let existingMints = Set(recentTokens.map { $0.mint })
                let newTokens = filtered.filter { !existingMints.contains($0.mint) }
                
                // Alert about new tokens
                for token in newTokens {
                    newTokenPublisher.send(token)
                    
                    // Also record in NewlyListedCoinsService
                    let solPrice = await getSolPrice()
                    let marketCoin = token.toMarketCoin(solPrice: solPrice)
                    NewlyListedCoinsService.shared.recordFirstSeen(
                        coin: marketCoin,
                        source: "pumpfun",
                        category: "meme"
                    )
                }
                
                recentTokens = filtered
                cacheRecentTokens(filtered)
                recordSuccess()
                isUsingCachedData = response.stale ?? false
                #if DEBUG
                print("[PumpFunService] Firebase: \(filtered.count) recent tokens, \(newTokens.count) new (cached: \(response.cached))")
                #endif
                return
                
            } catch {
                #if DEBUG
                print("[PumpFunService] Firebase failed, trying direct API: \(error.localizedDescription)")
                #endif
                // Fall through to direct API
            }
        }
        
        // Fallback to direct API
        do {
            let tokens = try await fetchCoins(sortBy: "created_timestamp", order: "DESC", limit: 50)
            let filtered = tokens.filter { ($0.marketCapSol ?? 0) >= minimumLiquiditySOL }
            
            let existingMints = Set(recentTokens.map { $0.mint })
            let newTokens = filtered.filter { !existingMints.contains($0.mint) }
            
            for token in newTokens {
                newTokenPublisher.send(token)
                let solPrice = await getSolPrice()
                let marketCoin = token.toMarketCoin(solPrice: solPrice)
                NewlyListedCoinsService.shared.recordFirstSeen(
                    coin: marketCoin,
                    source: "pumpfun",
                    category: "meme"
                )
            }
            
            recentTokens = filtered
            cacheRecentTokens(filtered)
            recordSuccess()
            #if DEBUG
            print("[PumpFunService] Direct API: \(filtered.count) recent tokens, \(newTokens.count) new")
            #endif
            
        } catch {
            #if DEBUG
            print("[PumpFunService] Failed to fetch recent tokens: \(error)")
            #endif
            recordFailure()
            isUsingCachedData = !recentTokens.isEmpty
        }
    }
    
    /// Fetch trending/graduated tokens via Firebase proxy
    func fetchTrendingTokens() async {
        // Check circuit breaker before making request
        if isServiceBlocked() {
            #if DEBUG
            print("[PumpFunService] Service blocked by circuit breaker, using cached trending data")
            #endif
            return // Will use cached data
        }
        
        // Try Firebase first
        if FirebaseService.shared.shouldUseFirebase {
            do {
                let response = try await FirebaseService.shared.getPumpFunTokens(type: "trending")
                let tokens = response.tokens.map { convertToToken($0) }
                let graduated = tokens.filter { $0.isGraduated }
                
                trendingTokens = graduated
                cacheTrendingTokens(graduated)
                recordSuccess()
                #if DEBUG
                print("[PumpFunService] Firebase: \(graduated.count) trending tokens (cached: \(response.cached))")
                #endif
                return
                
            } catch {
                #if DEBUG
                print("[PumpFunService] Firebase trending failed, trying direct: \(error.localizedDescription)")
                #endif
            }
        }
        
        // Fallback to direct API
        do {
            let tokens = try await fetchCoins(sortBy: "market_cap", order: "DESC", limit: 30)
            let graduated = tokens.filter { $0.isGraduated }
            
            trendingTokens = graduated
            cacheTrendingTokens(graduated)
            recordSuccess()
            #if DEBUG
            print("[PumpFunService] Fetched \(graduated.count) trending graduated tokens")
            #endif
            
        } catch {
            #if DEBUG
            print("[PumpFunService] Failed to fetch trending tokens: \(error)")
            #endif
            recordFailure()
            // Cached data will continue to be displayed
        }
    }
    
    /// Fetch tokens by various criteria with retry logic for transient errors
    private func fetchCoins(sortBy: String, order: String, limit: Int, retryCount: Int = 0) async throws -> [PumpFunToken] {
        guard var components = URLComponents(string: "\(baseURL)/coins") else {
            throw URLError(.badURL)
        }
        
        components.queryItems = [
            URLQueryItem(name: "offset", value: "0"),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "sort", value: sortBy),
            URLQueryItem(name: "order", value: order),
            URLQueryItem(name: "includeNsfw", value: "false")
        ]
        
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("CryptoSage/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        // Handle 5xx errors (transient server errors) with exponential backoff
        let is5xxError = (500...599).contains(http.statusCode)
        let is4xxError = (400...499).contains(http.statusCode)
        
        if is5xxError {
            // Cloudflare/origin errors - exponential backoff retry (1s, 2s, 4s)
            if retryCount < maxRetries {
                let delay = retryDelays[min(retryCount, retryDelays.count - 1)]
                #if DEBUG
                print("[PumpFunService] HTTP \(http.statusCode), retry \(retryCount + 1)/\(maxRetries) after \(delay / 1_000_000_000)s")
                #endif
                try? await Task.sleep(nanoseconds: delay)
                return try await fetchCoins(sortBy: sortBy, order: order, limit: limit, retryCount: retryCount + 1)
            }
            // All retries exhausted - use shorter block for transient errors
            #if DEBUG
            print("[PumpFunService] API returned status \(http.statusCode) after \(maxRetries) retries")
            #endif
            Task { @MainActor in
                APIHealthManager.shared.reportBlocked(.pumpFun, until: Date().addingTimeInterval(serviceBlockDuration5xx), reason: "HTTP \(http.statusCode)")
            }
            throw URLError(.badServerResponse)
        }
        
        guard (200...299).contains(http.statusCode) else {
            #if DEBUG
            print("[PumpFunService] API returned status \(http.statusCode)")
            #endif
            // 4xx errors (client errors) or other - use longer block
            let blockDuration = is4xxError ? serviceBlockDuration4xx : serviceBlockDuration5xx
            Task { @MainActor in
                APIHealthManager.shared.reportBlocked(.pumpFun, until: Date().addingTimeInterval(blockDuration), reason: "HTTP \(http.statusCode)")
            }
            throw URLError(.badServerResponse)
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        // Try direct array decode
        if let tokens = try? decoder.decode([PumpFunToken].self, from: data) {
            // Report healthy status
            Task { @MainActor in
                APIHealthManager.shared.reportHealthy(.pumpFun)
            }
            return tokens
        }
        
        // Try wrapped response
        if let wrapped = try? decoder.decode(CoinsResponse.self, from: data), let coins = wrapped.coins {
            // Report healthy status
            Task { @MainActor in
                APIHealthManager.shared.reportHealthy(.pumpFun)
            }
            return coins
        }
        
        return []
    }
    
    /// Get a specific token by mint address
    func fetchToken(mint: String) async -> PumpFunToken? {
        guard let url = URL(string: "\(baseURL)/coins/\(mint)") else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("CryptoSage/1.0", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(PumpFunToken.self, from: data)
        } catch {
            #if DEBUG
            print("[PumpFunService] Failed to fetch token \(mint): \(error)")
            #endif
            return nil
        }
    }
    
    // MARK: - Helper Methods
    
    /// Convert Firebase PumpFunTokenData to local PumpFunToken
    private func convertToToken(_ data: PumpFunTokensResponse.PumpFunTokenData) -> PumpFunToken {
        return PumpFunToken(
            mint: data.mint,
            name: data.name,
            symbol: data.symbol,
            description: data.description,
            imageUri: data.imageUri,
            createdTimestamp: data.createdTimestamp,
            marketCapSol: data.marketCapSol,
            usdMarketCap: data.usdMarketCap,
            replyCount: data.replyCount,
            lastReply: data.lastReply,
            creator: data.creator,
            raydiumPool: data.raydiumPool,
            complete: data.complete
        )
    }
    
    /// Get current SOL price for USD calculations
    private func getSolPrice() async -> Double {
        // Try to get from LivePriceManager
        if let solCoin = LivePriceManager.shared.currentCoinsList.first(where: { $0.symbol.uppercased() == "SOL" }),
           let price = solCoin.priceUsd, price > 0 {
            return price
        }
        
        // Fallback: fetch from CoinGecko
        do {
            return try await CryptoAPIService.shared.fetchSpotPrice(coin: "solana")
        } catch {
            return 200 // Reasonable fallback
        }
    }
    
    /// Convert all recent tokens to MarketCoins
    func recentTokensAsMarketCoins() async -> [MarketCoin] {
        let solPrice = await getSolPrice()
        return recentTokens.map { $0.toMarketCoin(solPrice: solPrice) }
    }
    
    /// Convert all trending tokens to MarketCoins
    func trendingTokensAsMarketCoins() async -> [MarketCoin] {
        let solPrice = await getSolPrice()
        return trendingTokens.map { $0.toMarketCoin(solPrice: solPrice) }
    }
    
    // MARK: - Refresh All
    
    /// Refresh all Pump.fun data
    func refreshAll() async {
        await fetchRecentTokens()
        await fetchTrendingTokens()
    }
}
