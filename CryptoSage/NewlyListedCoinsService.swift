//
//  NewlyListedCoinsService.swift
//  CryptoSage
//
//  Service for tracking and fetching newly listed coins.
//  Uses CoinGecko's API, Binance announcements, and local "first seen" tracking.
//

import Foundation
import Combine

/// Tracks when coins were first seen by the app and fetches newly listed coins
@MainActor
final class NewlyListedCoinsService: ObservableObject {
    
    static let shared = NewlyListedCoinsService()
    
    /// Coins that have been newly listed (within last 30 days)
    @Published private(set) var newlyListedCoins: [MarketCoin] = []
    
    /// Trending meme coins from various sources
    @Published private(set) var trendingMemeCoins: [MarketCoin] = []
    
    /// Publisher for new coin alerts
    let newCoinAlertPublisher = PassthroughSubject<[MarketCoin], Never>()
    
    /// Dictionary of coin ID -> first seen date (when this app first encountered it)
    private var firstSeenDates: [String: Date] = [:]
    
    /// Dictionary of coin ID -> metadata (volume when first seen, category, etc.)
    private var coinMetadata: [String: CoinFirstSeenMetadata] = [:]
    
    /// Cache file for first seen dates
    private let cacheFileName = "coin_first_seen_dates.json"
    private let metadataCacheFileName = "coin_first_seen_metadata.json"
    
    /// How old a coin can be and still considered "new" (14 days)
    private let newCoinThresholdDays: TimeInterval = 14 * 24 * 60 * 60
    
    /// Minimum volume to consider a coin significant
    private let minimumVolumeUSD: Double = 100_000
    
    /// Last fetch timestamps for different endpoints
    private var lastFetchAt: Date = .distantPast
    private var lastMemeFetchAt: Date = .distantPast
    private var lastBinanceFetchAt: Date = .distantPast
    private let fetchCooldown: TimeInterval = 300 // 5 minutes
    private let memeFetchCooldown: TimeInterval = 180 // 3 minutes for trending memes
    
    /// Metadata about when and how a coin was first seen
    struct CoinFirstSeenMetadata: Codable {
        let firstSeenDate: Date
        let volumeWhenFirstSeen: Double?
        let source: String // "coingecko", "binance", "pumpfun"
        let category: String? // "meme", "ai", "gaming", etc.
    }
    
    private init() {
        // PERFORMANCE FIX v18: Defer file I/O to after first frame renders
        // Loading 891 entries from disk was blocking app launch on the main thread.
        // NewlyListedCoins data isn't needed for the initial home screen render.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
            self.loadCachedFirstSeenDates()
            self.loadCachedMetadata()
        }
    }
    
    // MARK: - First Seen Tracking
    
    /// Record when a coin was first seen (only if not already tracked)
    func recordFirstSeen(coinIDs: [String]) {
        let now = Date()
        var changed = false
        
        for id in coinIDs {
            if firstSeenDates[id] == nil {
                firstSeenDates[id] = now
                changed = true
            }
        }
        
        if changed {
            saveFirstSeenDates()
        }
    }
    
    /// Record when a coin was first seen with metadata
    func recordFirstSeen(coin: MarketCoin, source: String, category: String? = nil) {
        let id = coin.id
        guard firstSeenDates[id] == nil else { return }
        
        let now = Date()
        firstSeenDates[id] = now
        coinMetadata[id] = CoinFirstSeenMetadata(
            firstSeenDate: now,
            volumeWhenFirstSeen: coin.totalVolume,
            source: source,
            category: category
        )
        
        saveFirstSeenDates()
        saveMetadata()
    }
    
    /// Get the first seen date for a coin, or nil if never seen
    func firstSeenDate(for coinID: String) -> Date? {
        return firstSeenDates[coinID]
    }
    
    /// Get metadata about when a coin was first seen
    func metadata(for coinID: String) -> CoinFirstSeenMetadata? {
        return coinMetadata[coinID]
    }
    
    /// Check if a coin is considered "new" (first seen within threshold)
    func isNewCoin(_ coinID: String) -> Bool {
        guard let firstSeen = firstSeenDates[coinID] else {
            // Never seen before - definitely new!
            return true
        }
        let age = Date().timeIntervalSince(firstSeen)
        return age < newCoinThresholdDays
    }
    
    /// Check if a coin is a trending meme coin
    func isTrendingMeme(_ coinID: String) -> Bool {
        guard let meta = coinMetadata[coinID] else { return false }
        return meta.category == "meme" && isNewCoin(coinID)
    }
    
    /// Get days since first seen (for display)
    func daysSinceFirstSeen(_ coinID: String) -> Int? {
        guard let firstSeen = firstSeenDates[coinID] else { return nil }
        let age = Date().timeIntervalSince(firstSeen)
        return Int(age / (24 * 60 * 60))
    }
    
    /// Get a badge string for display ("NEW", "1d", "3d", etc.)
    func newCoinBadge(for coinID: String) -> String? {
        guard let days = daysSinceFirstSeen(coinID) else { return "NEW" }
        if days == 0 { return "NEW" }
        if days <= 14 { return "\(days)d" }
        return nil
    }
    
    // MARK: - Newly Listed Coins
    
    /// Update the newly listed coins from a full market list
    func updateNewlyListedCoins(from allCoins: [MarketCoin]) {
        var trulyNewCoins: [MarketCoin] = []
        
        // First, identify coins we've never seen before
        for coin in allCoins {
            if firstSeenDates[coin.id] == nil {
                // Brand new coin! Record it with source
                recordFirstSeen(coin: coin, source: "coingecko", category: detectCategory(coin))
                trulyNewCoins.append(coin)
            }
        }
        
        // Alert subscribers about truly new coins (with volume filter)
        let significantNewCoins = trulyNewCoins.filter { ($0.totalVolume ?? 0) >= minimumVolumeUSD }
        if !significantNewCoins.isEmpty {
            newCoinAlertPublisher.send(significantNewCoins)
            #if DEBUG
            print("[NewlyListedCoinsService] Detected \(significantNewCoins.count) significant new coins")
            #endif
        }
        
        // Filter to coins that are "new" (first seen within threshold) AND have volume
        let newCoins = allCoins.filter { coin in
            // Must have minimum volume to filter out dead/spam coins
            guard (coin.totalVolume ?? 0) >= minimumVolumeUSD else { return false }
            
            // Check our local first-seen tracking
            return isNewCoin(coin.id)
        }
        
        // Sort by first seen date (most recently seen first) then by volume
        let sorted = newCoins.sorted { a, b in
            // Priority 1: Never-seen coins first
            let aFirstSeen = firstSeenDates[a.id]
            let bFirstSeen = firstSeenDates[b.id]
            
            if aFirstSeen == nil && bFirstSeen != nil { return true }
            if aFirstSeen != nil && bFirstSeen == nil { return false }
            
            // Priority 2: Most recently first-seen
            if let aDate = aFirstSeen, let bDate = bFirstSeen {
                if aDate != bDate { return aDate > bDate }
            }
            
            // Priority 3: Higher volume (more popular)
            let aVol = a.totalVolume ?? 0
            let bVol = b.totalVolume ?? 0
            return aVol > bVol
        }
        
        newlyListedCoins = sorted
    }
    
    /// Detect the category of a coin based on name/symbol patterns
    private func detectCategory(_ coin: MarketCoin) -> String? {
        let name = coin.name.lowercased()
        let symbol = coin.symbol.lowercased()
        
        // Meme coin patterns
        let memePatterns = ["doge", "shib", "pepe", "floki", "bonk", "wif", "meme", "inu", "cat", "frog", "moon", "elon", "trump", "fart", "pnut", "goat"]
        if memePatterns.contains(where: { name.contains($0) || symbol.contains($0) }) {
            return "meme"
        }
        
        // AI coin patterns
        let aiPatterns = ["ai", "gpt", "neural", "brain", "cognitive", "agent"]
        if aiPatterns.contains(where: { name.contains($0) || symbol.contains($0) }) {
            return "ai"
        }
        
        // Gaming patterns
        let gamePatterns = ["game", "play", "nft", "meta", "verse", "pixel"]
        if gamePatterns.contains(where: { name.contains($0) || symbol.contains($0) }) {
            return "gaming"
        }
        
        return nil
    }
    
    /// Fetch newly listed coins from CoinGecko's API
    func fetchNewlyListedCoins() async {
        // Cooldown check
        let now = Date()
        guard now.timeIntervalSince(lastFetchAt) > fetchCooldown else { return }
        lastFetchAt = now
        
        // Try CoinGecko's categories endpoint for newly added coins
        // or fall back to using our local tracking
        do {
            // CoinGecko has a "new" category we can query
            let coins = try await fetchNewCoinsFromAPI()
            
            // Record these as newly seen with metadata
            for coin in coins {
                recordFirstSeen(coin: coin, source: "coingecko", category: detectCategory(coin))
            }
            
            // Update our list (filtered by volume)
            newlyListedCoins = coins.filter { ($0.totalVolume ?? 0) >= minimumVolumeUSD }
        } catch {
            #if DEBUG
            print("[NewlyListedCoinsService] API fetch failed: \(error)")
            #endif
            // Fall back to local tracking - updateNewlyListedCoins() should have been called
        }
    }
    
    /// Fetch trending meme coins from CoinGecko's meme category
    func fetchTrendingMemeCoins() async {
        let now = Date()
        guard now.timeIntervalSince(lastMemeFetchAt) > memeFetchCooldown else { return }
        lastMemeFetchAt = now
        
        do {
            let memeCoins = try await CryptoAPIService.shared.fetchCoinsByCategory(.meme)
            
            // Record and categorize
            for coin in memeCoins {
                recordFirstSeen(coin: coin, source: "coingecko", category: "meme")
            }
            
            // Filter to new ones with volume and sort by 24h change (most volatile first)
            let trending = memeCoins
                .filter { ($0.totalVolume ?? 0) >= minimumVolumeUSD && isNewCoin($0.id) }
                .sorted { abs($0.priceChangePercentage24hInCurrency ?? 0) > abs($1.priceChangePercentage24hInCurrency ?? 0) }
            
            trendingMemeCoins = Array(trending.prefix(50))
            #if DEBUG
            print("[NewlyListedCoinsService] Found \(trendingMemeCoins.count) trending meme coins")
            #endif
        } catch {
            #if DEBUG
            print("[NewlyListedCoinsService] Meme coin fetch failed: \(error)")
            #endif
        }
    }
    
    /// Refresh all new coin data sources
    func refreshAllSources() async {
        await fetchNewlyListedCoins()
        await fetchTrendingMemeCoins()
    }
    
    // MARK: - API Fetching
    
    private func fetchNewCoinsFromAPI() async throws -> [MarketCoin] {
        // CoinGecko doesn't have a dedicated "new coins" endpoint for free tier
        // Instead, we'll use the coins/markets endpoint with category filtering
        // or just track locally based on when we first see coins
        
        // For now, let's try fetching coins sorted by recently added
        // This is a workaround since CoinGecko's free API doesn't expose listing dates
        let curr = CurrencyManager.apiValue
        guard let url = URL(string: "https://api.coingecko.com/api/v3/coins/markets?vs_currency=\(curr)&order=market_cap_asc&per_page=100&page=1&sparkline=true&price_change_percentage=1h,24h,7d") else {
            throw URLError(.badURL)
        }
        
        var request = APIConfig.coinGeckoRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        // Check for rate limiting
        if http.statusCode == 429 {
            throw URLError(.resourceUnavailable)
        }
        
        guard (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        // Try to decode as array of CoinGeckoCoin
        if let geckoCoins = try? decoder.decode([CoinGeckoCoin].self, from: data) {
            return geckoCoins.map { MarketCoin(gecko: $0) }
        }
        
        // Try wrapped response
        struct Wrapper: Decodable {
            let data: [CoinGeckoCoin]?
        }
        if let wrapped = try? decoder.decode(Wrapper.self, from: data), let coins = wrapped.data {
            return coins.map { MarketCoin(gecko: $0) }
        }
        
        return []
    }
    
    // MARK: - Persistence
    
    private func loadCachedFirstSeenDates() {
        guard let url = cacheFileURL(cacheFileName) else { return }
        
        // FIX: Check file existence before attempting to load to avoid noisy
        // "couldn't be opened because there is no such file" errors on first launch.
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let cached = try decoder.decode([String: Date].self, from: data)
            firstSeenDates = cached
            #if DEBUG
            print("[NewlyListedCoinsService] Loaded \(cached.count) first-seen dates from cache")
            #endif
        } catch {
            #if DEBUG
            print("[NewlyListedCoinsService] Could not load cache: \(error)")
            #endif
        }
    }
    
    private func loadCachedMetadata() {
        guard let url = cacheFileURL(metadataCacheFileName) else { return }
        
        // FIX: Check file existence before attempting to load to avoid noisy
        // "couldn't be opened because there is no such file" errors on first launch.
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let cached = try decoder.decode([String: CoinFirstSeenMetadata].self, from: data)
            coinMetadata = cached
            #if DEBUG
            print("[NewlyListedCoinsService] Loaded \(cached.count) coin metadata entries from cache")
            #endif
        } catch {
            #if DEBUG
            print("[NewlyListedCoinsService] Could not load metadata cache: \(error)")
            #endif
        }
    }
    
    private func saveFirstSeenDates() {
        guard let url = cacheFileURL(cacheFileName) else { return }
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(firstSeenDates)
            try data.write(to: url)
        } catch {
            #if DEBUG
            print("[NewlyListedCoinsService] Could not save cache: \(error)")
            #endif
        }
    }

    private func saveMetadata() {
        guard let url = cacheFileURL(metadataCacheFileName) else { return }
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(coinMetadata)
            try data.write(to: url)
        } catch {
            #if DEBUG
            print("[NewlyListedCoinsService] Could not save metadata cache: \(error)")
            #endif
        }
    }

    private func cacheFileURL(_ fileName: String) -> URL? {
        guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return cacheDir.appendingPathComponent(fileName)
    }
    
    // MARK: - Cleanup
    
    /// Remove old entries from tracking to prevent unbounded growth
    func cleanupOldEntries() {
        let cutoff = Date().addingTimeInterval(-90 * 24 * 60 * 60) // 90 days
        var removedDates = 0
        var removedMeta = 0
        
        firstSeenDates = firstSeenDates.filter { _, date in
            if date < cutoff {
                removedDates += 1
                return false
            }
            return true
        }
        
        coinMetadata = coinMetadata.filter { _, meta in
            if meta.firstSeenDate < cutoff {
                removedMeta += 1
                return false
            }
            return true
        }
        
        if removedDates > 0 || removedMeta > 0 {
            saveFirstSeenDates()
            saveMetadata()
            #if DEBUG
            print("[NewlyListedCoinsService] Cleaned up \(removedDates) date entries and \(removedMeta) metadata entries")
            #endif
        }
    }
    
    // MARK: - Statistics
    
    /// Get counts for various categories
    var statistics: (total: Int, new: Int, meme: Int, ai: Int, gaming: Int) {
        let newCount = firstSeenDates.filter { isNewCoin($0.key) }.count
        let memeCount = coinMetadata.filter { $0.value.category == "meme" && isNewCoin($0.key) }.count
        let aiCount = coinMetadata.filter { $0.value.category == "ai" && isNewCoin($0.key) }.count
        let gamingCount = coinMetadata.filter { $0.value.category == "gaming" && isNewCoin($0.key) }.count
        return (firstSeenDates.count, newCount, memeCount, aiCount, gamingCount)
    }
}
