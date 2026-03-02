import SwiftUI
import Foundation
import Combine
import UIKit
import os.log

/// News categories for filtering the feed
enum NewsCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case bitcoin = "Bitcoin"
    case ethereum = "Ethereum"
    case solana = "Solana"
    case defi = "DeFi"
    case nfts = "NFTs"
    case macro = "Macro"
    case layer2 = "Layer 2"
    case altcoins = "Altcoins"
    // Add more categories as needed

    var id: String { rawValue }

    /// Query parameter to use when fetching from the News API
    var query: String {
        switch self {
        case .all: return "crypto"
        case .bitcoin: return "bitcoin"
        case .ethereum: return "ethereum"
        case .solana: return "solana"
        case .defi: return "defi"
        case .nfts: return "nft OR nfts"
        case .macro: return "macro AND (crypto OR bitcoin OR ethereum)"
        case .layer2: return "layer 2 OR l2 OR optimistic rollup OR zk rollup"
        case .altcoins: return "altcoins OR altcoin"
        }
    }
}

@MainActor
final class CryptoNewsFeedViewModel: ObservableObject {
    /// Shared singleton instance to prevent duplicate network requests
    static let shared = CryptoNewsFeedViewModel()
    
    private let imagePolicyKey = "News.ImagePolicy.HostKeepsParams"
    private var hostKeepParamsCache: [String: Bool] = UserDefaults.standard.dictionary(forKey: "News.ImagePolicy.HostKeepsParams") as? [String: Bool] ?? [:]
    private func setHostKeepParams(_ host: String, keep: Bool) {
        hostKeepParamsCache[host] = keep
        UserDefaults.standard.set(hostKeepParamsCache, forKey: imagePolicyKey)
    }
    
    @Published var articles: [CryptoNewsArticle] = []
    
    /// Post-processing after articles are updated - pre-computes thumbnail URLs for stability
    private func processNewArticles() {
        // Pre-compute thumbnail URLs for visible articles (ensures stability)
        // NOTE: We do NOT prune the displayedThumbnailURLs cache here to avoid
        // thumbnail flickering during scrolling when articles are refreshed.
        // The cache is bounded naturally by article turnover.
        prefetchTop(count: 20)
    }
    
    /// Articles filtered by current category and diversified by source.
    /// Ensures category filtering always happens at display time regardless of how articles were loaded.
    /// Source diversity prevents any single publisher from dominating the feed.
    var filteredArticles: [CryptoNewsArticle] {
        let categoryFiltered = filterByCategory(articles, category: selectedCategory)
        return enforceSourceDiversity(categoryFiltered)
    }
    
    @Published var isLoading: Bool = false
    @Published var isLoadingPage: Bool = false
    /// Published refresh state for UI to show subtle indicator during background refreshes
    @Published var isRefreshingNews: Bool = false
    /// Counts how many consecutive pages produced no appendable items (after filtering)
    private var emptyPageStreak: Int = 0
    private let maxEmptyPageStreak: Int = 3
    private var currentPage: Int = 1
    /// Indicates if more pages are available
    @Published var hasMore: Bool = true
    
    // MARK: - Request Deduplication
    /// Prevents duplicate concurrent fetches
    private var isRefreshing: Bool = false
    /// Timestamp of last successful refresh
    private var lastRefreshTime: Date?
    /// Minimum interval between refreshes (seconds)
    private let minRefreshInterval: TimeInterval = 5.0
    /// Flag to bypass throttling on first app launch - ensures fresh content loads immediately
    private var isFirstLoad: Bool = true
    @Published var homeNewCount: Int = 0
    /// Optional query override when user performs a search
    @Published var queryOverride: String? = nil
    /// Bound to the search field in UI
    @Published var searchText: String = ""
    /// Selected publisher sources to include (empty = all)
    @Published var selectedSources: Set<String> = [] {
        didSet {
            saveFilters()
            // Defer to avoid "Publishing changes from within view updates"
            Task { @MainActor [weak self] in
                self?.loadAllNews(force: true)
            }
        }
    }
    /// Only show articles that have an image URL
    @Published var withImagesOnly: Bool = false {
        didSet {
            saveFilters()
            // Defer to avoid "Publishing changes from within view updates"
            Task { @MainActor [weak self] in
                self?.loadAllNews(force: true)
            }
        }
    }
    @Published var isOffline: Bool = false

    /// Token that changes whenever the feed context changes (category/search)
    @Published private(set) var feedToken: UUID = UUID()

    // Persistence keys for filters
    private let selectedCategoryKey = "news_selected_category"
    private let withImagesOnlyKey   = "news_with_images_only"
    private let selectedSourcesKey  = "news_selected_sources"

    /// Indicates if the last error was retryable
    @Published var isRetryableError: Bool = false
    
    /// Throttle full refreshes to avoid API rate limits
    private var lastFullRefreshAt: Date? = nil
    private let minFullRefreshInterval: TimeInterval = 120
    
    /// Known publisher names for quick filtering UI
    let knownSources: [String] = [
        "Coindesk","CoinTelegraph","The Block","Decrypt","Blockworks","Reuters","Bloomberg",
        "Bankless","Messari","Coin Bureau","CryptoSlate","CoinGape","NewsBTC","The Defiant"
    ]
    private var prefetchNextScheduled: Bool = false
    private var pagingBurstAttempts: Int = 0

    /// Track in-flight tasks so we can cancel when needed
    private var loadAllTask: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?
    
    /// Currently selected news category - filtering happens instantly via filteredArticles computed property
    @Published var selectedCategory: NewsCategory = .all {
        didSet {
            saveFilters()
            // Category filtering is handled by filteredArticles computed property
            // No network reload needed - filtering happens instantly in memory
            // Defer notification to next runloop to avoid "Modifying state during view update" errors
            Task { @MainActor [weak self] in
                self?.objectWillChange.send()
            }
        }
    }
    
    private let newsService = CryptoNewsService()

    private var refreshTimer: Timer?
    private var autoRefreshBackoffFactor: Double = 1.0
    private var didStartAutoRefresh: Bool = false
    private static var warmPrefetchesMade: Int = 0

    // Freshness controls
    // STALENESS FIX: Reduced thresholds for fresher news content
    private let staleThreshold: TimeInterval = 60 * 60        // 60 minutes (reduced from 90)
    private let freshnessWindow: TimeInterval = 8 * 3600      // prefer last 8 hours (reduced from 12)
    private let maxAgeWindow: TimeInterval = 24 * 3600        // drop items older than 24 hours (reduced from 36)
    
    // NOTE: Domain lists and crypto relevance logic are centralized in NewsQualityFilter.swift
    // Do not duplicate them here. Use NewsQualityFilter.passesQualityCheck() for all filtering.
    
    private func qualityFilter(_ list: [CryptoNewsArticle]) -> [CryptoNewsArticle] {
        // Use centralized NewsQualityFilter for consistent filtering across the app
        return list.filter { art in
            NewsQualityFilter.passesQualityCheck(
                url: art.url,
                title: art.title,
                description: art.description,
                sourceName: art.sourceName
            )
        }
    }
    
    // MARK: - Pre-compiled Category Filters (Performance Optimization)
    /// Pre-compiled regex patterns for category filtering - created once at class load
    private struct CategoryFilter {
        let boundaryRegexes: [NSRegularExpression]
        let containsKeywords: [String]
        
        func matches(_ text: String) -> Bool {
            // Check contains keywords first (faster, more common)
            if containsKeywords.contains(where: { text.contains($0) }) {
                return true
            }
            // Check pre-compiled boundary regexes
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for regex in boundaryRegexes {
                if regex.firstMatch(in: text, options: [], range: range) != nil {
                    return true
                }
            }
            return false
        }
    }
    
    /// Pre-compiled filters for each category (created once)
    private static let categoryFilters: [NewsCategory: CategoryFilter] = {
        func buildFilter(boundary: [String], contains: [String]) -> CategoryFilter {
            let regexes = boundary.compactMap { keyword -> NSRegularExpression? in
                let pattern = "\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b"
                return try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            }
            return CategoryFilter(boundaryRegexes: regexes, containsKeywords: contains)
        }
        
        return [
            .bitcoin: buildFilter(boundary: ["btc"], contains: ["bitcoin", "satoshi", "lightning network"]),
            .ethereum: buildFilter(boundary: ["eth"], contains: ["ethereum", "vitalik", "erc-20", "erc20", "eip-"]),
            .solana: buildFilter(boundary: ["sol", "jup"], contains: [
                "solana", "phantom wallet", "jupiter", "raydium", "orca", "marinade",
                "magic eden", "tensor", "jito", "pyth", "wormhole", "serum",
                "metaplex", "helium", "render", "bonk", "solana mobile", "saga phone",
                "solana defi", "solana nft", "solana ecosystem", "sol price",
                "drip haus", "backpack", "mad lads", "stepn", "audius"
            ]),
            .defi: buildFilter(boundary: ["dex", "amm", "tvl", "apr", "apy", "dao"], contains: [
                "defi", "decentralized finance", "yield farm", "liquidity pool", "lending protocol",
                "staking reward", "aave", "uniswap", "curve", "compound", "maker", "sushiswap",
                "pancakeswap", "yearn", "convex", "lido", "rocket pool", "balancer", "synthetix",
                "liquidity", "swap", "staking", "farming", "vault", "protocol", "lend", "borrow",
                "decentralized exchange", "yield", "raydium", "jupiter", "orca", "marinade",
                "eigen", "eigenlayer", "restaking", "liquid staking", "pendle", "gmx", "dydx",
                "morpho", "spark", "sky protocol", "makerdao", "aerodrome", "velodrome"
            ]),
            .nfts: buildFilter(boundary: ["nft"], contains: [
                "nfts", "opensea", "blur", "collectible", "ordinals", "inscriptions", "digital art",
                "mint", "minting", "collection", "pudgy", "bored ape", "bayc", "azuki", "doodles",
                "cryptopunks", "magic eden", "tensor", "metaplex", "art blocks", "foundation",
                "superrare", "rarible", "nft marketplace", "pfp", "generative art", "on-chain art"
            ]),
            .macro: buildFilter(boundary: ["fed", "sec", "etf"], contains: [
                "macro", "federal reserve", "inflation", "interest rate", "economy", "regulation",
                "congress", "institutional", "bitcoin etf", "crypto regulation"
            ]),
            .layer2: buildFilter(boundary: ["l2", "zk"], contains: [
                "layer 2", "layer2", "rollup", "optimism", "arbitrum", "polygon", "base chain", "blast", "zksync", "starknet"
            ]),
            .altcoins: buildFilter(boundary: ["ada", "xrp"], contains: [
                "altcoin", "meme coin", "shiba", "doge", "dogecoin", "ripple", "cardano",
                "avalanche", "avax", "polkadot", "chainlink", "pepe coin", "memecoin"
            ])
        ]
    }()
    
    /// Filter articles by selected category using keyword matching in title/description
    /// Uses pre-compiled regex patterns for better performance
    private func filterByCategory(_ articles: [CryptoNewsArticle], category: NewsCategory) -> [CryptoNewsArticle] {
        guard category != .all else { return articles }
        guard let filter = Self.categoryFilters[category] else { return articles }
        
        return articles.filter { article in
            let text = (article.title + " " + (article.description ?? "")).lowercased()
            return filter.matches(text)
        }
    }

    // MARK: - Source Diversity
    
    /// Enforce source diversity so no single publisher dominates the feed.
    /// Rules:
    /// - Top 3 articles (home screen hero + 2 rows): max 1 per source
    /// - Top 10 articles: max 2 per source
    /// - Rest of feed: max 3 per source in any rolling window of 10
    /// Articles that violate limits are pushed down, not removed.
    private func enforceSourceDiversity(_ articles: [CryptoNewsArticle]) -> [CryptoNewsArticle] {
        guard articles.count > 3 else { return articles }
        
        var result: [CryptoNewsArticle] = []
        var deferred: [CryptoNewsArticle] = []
        var sourceCountInTop3: [String: Int] = [:]
        var sourceCountInTop10: [String: Int] = [:]
        
        for article in articles {
            let sourceKey = article.sourceName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let currentIndex = result.count
            
            if currentIndex < 3 {
                // Top 3: max 1 article per source (home screen display)
                let count = sourceCountInTop3[sourceKey, default: 0]
                if count >= 1 {
                    deferred.append(article)
                    continue
                }
                sourceCountInTop3[sourceKey, default: 0] += 1
                sourceCountInTop10[sourceKey, default: 0] += 1
            } else if currentIndex < 10 {
                // Top 10: max 2 articles per source
                let count = sourceCountInTop10[sourceKey, default: 0]
                if count >= 2 {
                    deferred.append(article)
                    continue
                }
                sourceCountInTop10[sourceKey, default: 0] += 1
            }
            // Beyond top 10: no additional per-source limit (they're already filtered)
            
            result.append(article)
        }
        
        // Append deferred articles at the end (they still appear, just lower in feed)
        result.append(contentsOf: deferred)
        return result
    }
    
    // MARK: - Cache Invalidation
    
    /// Known homepage URLs from the old static seed that should trigger cache invalidation
    private static let staticSeedHomepageURLs: Set<String> = [
        "https://www.coindesk.com/markets/",
        "https://cointelegraph.com/",
        "https://www.theblock.co/",
        "https://decrypt.co/",
        "https://bitcoinmagazine.com/",
        "https://blockworks.co/",
        "https://www.reuters.com/technology/cryptocurrency/",
        "https://www.bloomberg.com/crypto",
        "https://www.cnbc.com/cryptoworld/",
        "https://ambcrypto.com/",
        "https://beincrypto.com/",
        "https://www.newsbtc.com/",
        "https://cryptoslate.com/",
        "https://coingape.com/",
        "https://finbold.com/cryptocurrency/",
        "https://thedefiant.io/",
        "https://messari.io/news",
        "https://www.bankless.com/",
        "https://www.coinbureau.com/news/"
    ]
    
    /// Clears the news cache if it contains stale or static seed data
    static func invalidateStaleCacheIfNeeded() {
        guard let cached: [CryptoNewsArticle] = CacheManager.shared.load([CryptoNewsArticle].self, from: "news_cache.json"), !cached.isEmpty else {
            return
        }
        
        // Check 1: If any articles have URLs from the old static seed, clear the cache
        let hasStaticSeedURLs = cached.contains { staticSeedHomepageURLs.contains($0.url.absoluteString) }
        if hasStaticSeedURLs {
            NewsDebug.log("Cache invalidated: contains static seed homepage URLs")
            CacheManager.shared.delete("news_cache.json")
            return
        }
        
        // Check 2: If the newest article is older than 12 hours, clear the cache
        // STALENESS FIX: Reduced from 24h to 12h to ensure users see fresher news content
        if let newest = cached.map({ $0.publishedAt }).max() {
            let age = Date().timeIntervalSince(newest)
            if age > 12 * 3600 {  // 12 hours
                NewsDebug.log("Cache invalidated: newest article is \(Int(age / 3600)) hours old (>12h threshold)")
                CacheManager.shared.delete("news_cache.json")
                return
            }
        }
        
        // Check 3: If most articles have nil images and homepage-like URLs, clear it
        let homepageLikeCount = cached.filter { isHomepageLikeURL($0.url) }.count
        if homepageLikeCount > cached.count / 2 {
            NewsDebug.log("Cache invalidated: \(homepageLikeCount)/\(cached.count) articles have homepage-like URLs")
            CacheManager.shared.delete("news_cache.json")
            return
        }
    }
    
    /// Detect URLs that look like publisher homepages rather than article permalinks
    private static func isHomepageLikeURL(_ url: URL) -> Bool {
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // Empty path = homepage
        if path.isEmpty { return true }
        // Single shallow path segment with no numbers is likely a section page
        let segments = path.split(separator: "/")
        if segments.count == 1 {
            let segment = String(segments[0]).lowercased()
            // Common section names
            let sectionNames: Set<String> = ["markets", "news", "latest", "crypto", "technology", "business", "finance", "cryptocurrency"]
            if sectionNames.contains(segment) { return true }
            // No numbers typically means section, not article
            if segment.rangeOfCharacter(from: .decimalDigits) == nil { return true }
        }
        return false
    }

    deinit {
        refreshTimer?.invalidate()
    }

    private func startAutoRefresh() {
        guard !didStartAutoRefresh else { return }
        didStartAutoRefresh = true
        scheduleNextAutoRefresh()
    }
    
    private func scheduleNextAutoRefresh() {
        refreshTimer?.invalidate()
        // CONSISTENCY FIX: Use fixed interval instead of random to ensure all devices refresh at predictable times
        // This helps maintain data consistency across devices
        let base: TimeInterval = 180 // Fixed 3-minute interval
        let interval = max(90, base * max(1.0, min(autoRefreshBackoffFactor, 3.0)))
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                if self.isOffline {
                    // Light backoff while offline
                    self.autoRefreshBackoffFactor = min(3.0, self.autoRefreshBackoffFactor * 1.25)
                    self.scheduleNextAutoRefresh()
                    return
                }
                await self.loadLatestNews()
                // Adjust backoff based on whether the last state is a retryable error
                if self.isRetryableError {
                    self.autoRefreshBackoffFactor = min(3.0, self.autoRefreshBackoffFactor * 1.5)
                } else {
                    self.autoRefreshBackoffFactor = max(1.0, self.autoRefreshBackoffFactor * 0.8)
                }
                self.scheduleNextAutoRefresh()
            }
        }
    }

    private func noteNewArticles(old: [CryptoNewsArticle], new: [CryptoNewsArticle]) {
        guard !old.isEmpty else { self.homeNewCount = 0; return }
        let oldKeys = Set(old.map { self.normalizedArticleKey(for: $0) })
        var count = 0
        for a in new {
            if oldKeys.contains(self.normalizedArticleKey(for: a)) { break }
            count += 1
        }
        self.homeNewCount = max(0, count)
    }
    
    func resetHomeNewCount() { self.homeNewCount = 0 }

    /// Fetch from primary + fallback source to reduce network overhead and improve responsiveness.
    /// CryptoCompare is primary (free API that works from mobile), RSS is fallback.
    private func fastestNews(query: String, page: Int, rssLimit: Int) async -> [CryptoNewsArticle] {
        // Bypass throttling on first app launch to ensure fresh content loads immediately
        let bypassThrottle = isFirstLoad
        if isFirstLoad {
            isFirstLoad = false
        }
        
        // Request deduplication: skip if already refreshing or too soon since last refresh
        // But allow first load to go through even if another request is in progress
        guard !isRefreshing || bypassThrottle else {
            // Return cached articles if available during deduplication
            if !articles.isEmpty { return articles }
            return []
        }
        if !bypassThrottle, let last = lastRefreshTime, Date().timeIntervalSince(last) < minRefreshInterval {
            // Return current articles if refresh is throttled (but not on first load)
            if !articles.isEmpty { return articles }
            return []
        }
        
        isRefreshing = true
        // Signal UI that refresh is happening
        Task { @MainActor [weak self] in
            self?.isRefreshingNews = true
        }
        defer {
            isRefreshing = false
            lastRefreshTime = Date()
            // Signal UI that refresh completed
            Task { @MainActor [weak self] in
                // Brief delay for visual feedback before hiding indicator
                try? await Task.sleep(nanoseconds: 200_000_000)
                self?.isRefreshingNews = false
            }
        }
        
        // Fetch from 2 sources in parallel (reduced from 4 to improve performance)
        // Primary: CryptoCompare - free API that works reliably from mobile
        // Fallback: RSS feeds - always work, no API restrictions
        async let cryptoCompare: [CryptoNewsArticle] = await CryptoCompareNewsService.shared.fetchNews(query: query, limit: 50)
        async let rss: [CryptoNewsArticle] = await RSSFetcher.fetch(limit: rssLimit)
        
        // Gather results from both sources
        var items = await (cryptoCompare + rss)
        
        if items.isEmpty {
            // If both sources failed, try extended RSS fetch as last resort
            let fallbackRSS = await RSSFetcher.fetch(limit: 100)
            if !fallbackRSS.isEmpty {
                items = fallbackRSS
            }
        }
        
        if items.isEmpty { return [] }
        
        // Sort newest first, apply quality filter, then unique and sort again
        items.sort { $0.publishedAt > $1.publishedAt }
        items = qualityFilter(items)
        items = uniqueArticles(from: items)
        
        // Apply category filter to ensure results match selected category
        items = filterByCategory(items, category: selectedCategory)
        
        items.sort { $0.publishedAt > $1.publishedAt }
        return items
    }

    /// Immediately seeds the UI from cached news if available to avoid initial blank state.
    private func seedFromCacheIfEmpty(previewOnly: Bool) {
        guard self.articles.isEmpty else { return }
        if let cached: [CryptoNewsArticle] = CacheManager.shared.load([CryptoNewsArticle].self, from: "news_cache.json"), !cached.isEmpty {
            let ordered = cached.sorted { $0.publishedAt > $1.publishedAt }
            // Apply quality filter first to remove non-crypto content, then category filter
            let qualityChecked = qualityFilter(ordered)
            let filtered = filterByCategory(qualityChecked, category: selectedCategory)
            guard !filtered.isEmpty else { return }
            // If cache is very old, avoid seeding from it to prevent a stale-locked UI
            if let newest = filtered.first?.publishedAt, Date().timeIntervalSince(newest) < 12 * 3600 {
                // Defer state modification to avoid "Modifying state during view update"
                let articlesToSet = previewOnly ? Array(filtered.prefix(5)) : filtered
                Task { @MainActor [weak self] in
                    self?.articles = articlesToSet
                    // Process thumbnails immediately - view handles async loading
                    self?.processNewArticles()
                }
            }
        }
        // No static seed fallback - let the UI show empty state with error message
    }

    private var cancellables = Set<AnyCancellable>()
    private let fastSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 2.2
        cfg.timeoutIntervalForResource = 4.5
        cfg.waitsForConnectivity = false
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.urlCache = nil
        cfg.httpMaximumConnectionsPerHost = 6
        cfg.allowsConstrainedNetworkAccess = true
        return URLSession(configuration: cfg)
    }()

    private init() {
        loadSavedFilters()
        
        // PERFORMANCE FIX v18: Defer heavy disk I/O and network calls to after first frame
        // Previously, init() synchronously loaded news_cache.json (large file), ran quality filter,
        // sorted articles, AND started network requests + auto-refresh timer.
        // This all blocked CryptoSageAIApp.init() which delays the splash screen.
        // News isn't visible on the initial home screen (user needs to scroll), so defer it.
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            // Small yield to let the splash render first
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
            
            // Clear stale/invalid cache before loading
            Self.invalidateStaleCacheIfNeeded()
            
            // Load cache for instant news UI
            if let cached: [CryptoNewsArticle] = CacheManager.shared.load([CryptoNewsArticle].self, from: "news_cache.json"), !cached.isEmpty {
                let ordered = cached.sorted { $0.publishedAt > $1.publishedAt }
                let filtered = self.qualityFilter(ordered)
                self.articles = Array(filtered.prefix(30))
            }
            
            // Reset all throttle timestamps on app launch
            self.lastRefreshTime = nil
            self.lastFullRefreshAt = nil

            if AppSettings.isSimulatorLimitedDataMode {
                // Limited simulator profile: one-shot network fetch only.
                #if DEBUG
                print("🧪 [NewsFeedVM] Simulator limited profile: single fetch, auto-refresh disabled")
                #endif
                self.loadAllNews(force: true)
                self.loadBookmarks()
            } else {
                self.loadAllNews(force: true)
                self.loadBookmarks()
                self.startAutoRefresh()
            }
        }

        if !AppSettings.isSimulatorLimitedDataMode {
            // Observe reachability and pause/resume work
            NetworkReachability.shared.$isReachable
                .receive(on: DispatchQueue.main)
                .sink { [weak self] up in
                    guard let self = self else { return }
                    // Defer state modification to avoid "Modifying state during view update"
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.isOffline = !up
                        if up {
                            Task { await self.loadLatestNews() }
                        }
                        // Do not cancel in-flight work on transient drops; loaders handle timeouts and cache fallbacks.
                    }
                }
                .store(in: &cancellables)

            #if canImport(UIKit)
            NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self = self else { return }
                    Task { await self.loadLatestNews() }
                }
                .store(in: &cancellables)
            #endif
        }
    }

    func loadAllNews(force: Bool = false) {
        if isOffline {
            // Seed from cache immediately for responsiveness and avoid network churn while offline.
            seedFromCacheIfEmpty(previewOnly: false)
            return
        }
        
        // PERFORMANCE: Check global request coordinator to prevent startup thundering herd
        if !force && !APIRequestCoordinator.shared.canMakeRequest(for: .news) {
            seedFromCacheIfEmpty(previewOnly: false)
            return
        }
        
        // Throttle to avoid hammering the API and hitting 429, but do not block when the feed appears stale
        if let last = lastFullRefreshAt,
           Date().timeIntervalSince(last) < minFullRefreshInterval,
           !force,
           !articles.isEmpty,
           articles.count > 5,
           let newest = articles.map({ $0.publishedAt }).max(),
           Date().timeIntervalSince(newest) < staleThreshold {
            return
        }
        
        // Record request with coordinator
        APIRequestCoordinator.shared.recordRequest(for: .news)
        
        // If a load is already in progress and not forcing, let it complete
        // This prevents task cancellation from killing in-flight RSS fetches
        if loadAllTask != nil && !force {
            return
        }
        
        // Only cancel if force=true - this allows the new fetch to start fresh
        if force {
            loadAllTask?.cancel()
        }

        loadAllTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            let token = self.feedToken
            if self.isOffline {
                // Prefer cached content for immediate paint, but continue attempting network work.
                self.seedFromCacheIfEmpty(previewOnly: false)
            }
            // Defer state modifications to avoid "Modifying state during view update"
            Task { @MainActor [weak self] in
                self?.errorMessage = nil
                self?.isRetryableError = false
                self?.isLoading = true
                self?.emptyPageStreak = 0
            }
            
            // Seed UI instantly from cache if possible while network/RSS are loading
            self.seedFromCacheIfEmpty(previewOnly: false)

            defer {
                Task { @MainActor [weak self] in
                    self?.isLoading = false
                }
            }

            let feed = await self.fastestNews(query: (self.queryOverride ?? self.selectedCategory.query), page: 1, rssLimit: 40)
            let now = Date()
            let twelveHoursAgo = now.addingTimeInterval(-12 * 3600)
            let preferred = feed.filter { $0.publishedAt >= twelveHoursAgo }
            let ordered = (preferred.isEmpty ? feed : preferred).sorted { $0.publishedAt > $1.publishedAt }
            let unique = self.uniqueArticles(from: ordered)
            let uniqueQ = self.qualityFilter(unique)

            // If the newest item appears stale (>2h), fetch Top Headlines to prefer fresher items
            if let newest = uniqueQ.map({ $0.publishedAt }).max(), Date().timeIntervalSince(newest) > 2 * 3600 {
                if let headlines = try? await CryptoNewsFeedService().fetchNews(page: 1), !headlines.isEmpty {
                    var merged = headlines + uniqueQ
                    merged.sort { $0.publishedAt > $1.publishedAt }
                    let uniq = self.uniqueArticles(from: merged)
                    let qualityChecked = self.qualityFilter(uniq)
                    if !qualityChecked.isEmpty {
                        let base = qualityChecked
                        self.publishArticlesIfCurrent(base, token: token)
                        CacheManager.shared.save(base, to: "news_cache.json")
                        // Defer state modifications to avoid "Modifying state during view update"
                        Task { @MainActor [weak self] in
                            self?.lastFullRefreshAt = Date()
                            self?.hasMore = true
                            self?.currentPage = 1
                            self?.isRetryableError = false
                            self?.errorMessage = nil
                        }
                        return
                    }
                }
            }

            if !uniqueQ.isEmpty {
                var base = uniqueQ
                // Ensure the list is scrollable and fresh enough
                // 1) Top up with older RSS items to reach at least 30 items
                if base.count < 30, let last = base.last?.publishedAt {
                    let rssTopUp = await RSSFetcher.fetch(limit: 200, before: last.addingTimeInterval(-1))
                    if !rssTopUp.isEmpty {
                        let existing = Set(base.map { $0.id })
                        var extras = rssTopUp.filter { !existing.contains($0.id) }
                        extras = self.qualityFilter(extras)  // Filter RSS for crypto relevance
                        base.append(contentsOf: extras)
                        base.sort { $0.publishedAt > $1.publishedAt }
                        base = self.uniqueArticles(from: base)
                    }
                }
                // 2) If the newest item is still stale (>3h), merge in Top Headlines and recent RSS aggressively
                if let newest = base.first?.publishedAt, Date().timeIntervalSince(newest) > 3 * 3600 {
                    if let headlines = try? await CryptoNewsFeedService().fetchNews(page: 1), !headlines.isEmpty {
                        var merged = headlines + base
                        // Prefer the last 6 hours strongly
                        let sixHoursAgo = Date().addingTimeInterval(-6 * 3600)
                        let recent = merged.filter { $0.publishedAt >= sixHoursAgo }
                        merged = recent.isEmpty ? merged : recent
                        merged.sort { $0.publishedAt > $1.publishedAt }
                        merged = self.uniqueArticles(from: merged)
                        merged = self.qualityFilter(merged)
                        base = merged
                    }
                    // As a final nudge, try a broad RSS pull without the before cutoff
                    if base.count < 20 {
                        let rss = await RSSFetcher.fetch(limit: 120)
                        if !rss.isEmpty {
                            var merged = base + rss
                            merged.sort { $0.publishedAt > $1.publishedAt }
                            merged = self.uniqueArticles(from: merged)
                            merged = self.qualityFilter(merged)  // Filter for crypto relevance
                            base = merged
                        }
                    }
                }

                // Drop items older than maxAgeWindow only if we still retain a healthy list after trimming.
                let cutoffAll = Date().addingTimeInterval(-maxAgeWindow)
                let trimmedCandidate = base.filter { $0.publishedAt >= cutoffAll }
                
                let minAfterTrimCount = 30
                if trimmedCandidate.count >= minAfterTrimCount {
                    var trimmed = trimmedCandidate
                    if let newest = trimmed.first?.publishedAt, Date().timeIntervalSince(newest) > staleThreshold {
                        // One more attempt to merge fresh headlines to improve recency
                        if let headlines2 = try? await CryptoNewsFeedService().fetchNews(page: 1), !headlines2.isEmpty {
                            var merged2 = headlines2 + trimmed
                            merged2.sort { $0.publishedAt > $1.publishedAt }
                            merged2 = self.uniqueArticles(from: merged2)
                            trimmed = self.qualityFilter(merged2)
                        }
                    }
                    base = trimmed
                } else {
                    // Keep the untrimmed base to preserve a longer, scrollable list.
                    if let newest = base.first?.publishedAt, Date().timeIntervalSince(newest) > staleThreshold {
                        if let headlines2 = try? await CryptoNewsFeedService().fetchNews(page: 1), !headlines2.isEmpty {
                            var merged2 = headlines2 + base
                            merged2.sort { $0.publishedAt > $1.publishedAt }
                            merged2 = self.uniqueArticles(from: merged2)
                            base = self.qualityFilter(merged2)
                        }
                    }
                }

                let filteredRelaxed = self.applyFiltersWithRelaxation(base)
                self.publishArticlesIfCurrent(filteredRelaxed, token: token)
                CacheManager.shared.save(filteredRelaxed, to: "news_cache.json")
                // Defer state modifications to avoid "Modifying state during view update"
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.lastFullRefreshAt = Date()
                    if let newest = self.articles.first?.publishedAt, Date().timeIntervalSince(newest) > self.staleThreshold {
                        Task { await self.loadLatestNews() }
                    }
                    self.hasMore = true
                    self.currentPage = 1
                    self.isRetryableError = false
                    self.errorMessage = nil
                    self.warmNextPageIfNeeded()
                }
                return
            }
            // Existing fallbacks remain below
            do {
                let fetched = try await self.newsService.fetchNews(query: (self.queryOverride ?? self.selectedCategory.query), page: 1)
                var feed = fetched
                if feed.isEmpty {
                    feed = await RSSFetcher.fetch(limit: 40)
                }
                let now = Date()
                let twelveHoursAgo = now.addingTimeInterval(-12 * 3600)
                let preferred = feed.filter { $0.publishedAt >= twelveHoursAgo }
                let ordered = (preferred.isEmpty ? feed : preferred).sorted { $0.publishedAt > $1.publishedAt }
                let unique = self.uniqueArticles(from: ordered)
                if !unique.isEmpty {
                    let filtered = self.applyFiltersWithRelaxation(unique)
                    self.publishArticlesIfCurrent(filtered, token: token)
                    // Defer state modifications to avoid "Modifying state during view update"
                    Task { @MainActor [weak self] in
                        self?.lastFullRefreshAt = Date()
                        self?.currentPage = 1
                        self?.hasMore = true
                        self?.isRetryableError = false
                        self?.warmNextPageIfNeeded()
                    }
                } else {
                    Task { @MainActor [weak self] in
                        self?.errorMessage = "No news available"
                        self?.isRetryableError = false
                    }
                }
            } catch is CancellationError {
                return
            } catch let error as CryptoNewsError {
                let retryable: Bool
                switch error {
                case .timeout, .networkError:
                    retryable = true
                default:
                    retryable = false
                }
                let errorMsg = error.localizedDescription
                Task { @MainActor [weak self] in
                    self?.isRetryableError = retryable
                    self?.errorMessage = errorMsg
                }
                if self.articles.isEmpty {
                    // Try CryptoCompare first (most reliable)
                    let cc = await CryptoCompareNewsService.shared.fetchNews(query: (self.queryOverride ?? self.selectedCategory.query), limit: 40)
                    if !cc.isEmpty {
                        let ordered = cc.sorted { $0.publishedAt > $1.publishedAt }
                        let filteredQ = self.qualityFilter(ordered)
                        let filtered = self.applyFiltersWithRelaxation(filteredQ)
                        self.publishArticlesIfCurrent(filtered, token: token)
                        CacheManager.shared.save(filtered, to: "news_cache.json")
                        Task { @MainActor [weak self] in
                            self?.lastFullRefreshAt = Date()
                            self?.currentPage = 1
                            self?.hasMore = true
                            self?.isRetryableError = false
                            self?.errorMessage = nil
                            self?.warmNextPageIfNeeded()
                        }
                        return
                    }
                    // Then try RSS
                    let rss = await RSSFetcher.fetch(limit: 40)
                    if !rss.isEmpty {
                        let ordered = rss.sorted { $0.publishedAt > $1.publishedAt }
                        let filteredQ = self.qualityFilter(ordered)
                        let filtered = self.applyFiltersWithRelaxation(filteredQ)
                        self.publishArticlesIfCurrent(filtered, token: token)
                        CacheManager.shared.save(filtered, to: "news_cache.json")
                        Task { @MainActor [weak self] in
                            self?.lastFullRefreshAt = Date()
                            self?.currentPage = 1
                            self?.hasMore = true
                            self?.isRetryableError = false
                            self?.errorMessage = nil
                            self?.warmNextPageIfNeeded()
                        }
                        return
                    }
                }
            } catch {
                let errorMsg = error.localizedDescription
                Task { @MainActor [weak self] in
                    self?.isRetryableError = false
                    self?.errorMessage = errorMsg
                }
                if self.articles.isEmpty {
                    // Try CryptoCompare first (most reliable)
                    let cc = await CryptoCompareNewsService.shared.fetchNews(query: (self.queryOverride ?? self.selectedCategory.query), limit: 40)
                    if !cc.isEmpty {
                        let ordered = cc.sorted { $0.publishedAt > $1.publishedAt }
                        let filteredQ = self.qualityFilter(ordered)
                        let filtered = self.applyFiltersWithRelaxation(filteredQ)
                        self.publishArticlesIfCurrent(filtered, token: token)
                        CacheManager.shared.save(filtered, to: "news_cache.json")
                        Task { @MainActor [weak self] in
                            self?.lastFullRefreshAt = Date()
                            self?.currentPage = 1
                            self?.hasMore = true
                            self?.isRetryableError = false
                            self?.errorMessage = nil
                            self?.warmNextPageIfNeeded()
                        }
                        return
                    }
                    // Then try RSS
                    let rss = await RSSFetcher.fetch(limit: 40)
                    if !rss.isEmpty {
                        let ordered = rss.sorted { $0.publishedAt > $1.publishedAt }
                        let filteredQ = self.qualityFilter(ordered)
                        let filtered = self.applyFiltersWithRelaxation(filteredQ)
                        self.publishArticlesIfCurrent(filtered, token: token)
                        CacheManager.shared.save(filtered, to: "news_cache.json")
                        Task { @MainActor [weak self] in
                            self?.lastFullRefreshAt = Date()
                            self?.currentPage = 1
                            self?.hasMore = true
                            self?.isRetryableError = false
                            self?.errorMessage = nil
                            self?.warmNextPageIfNeeded()
                        }
                        return
                    }
                }
            }
            // No static seed fallback - show error message instead
            if self.articles.isEmpty && self.errorMessage == nil {
                Task { @MainActor [weak self] in
                    self?.errorMessage = "Unable to load news. Pull to refresh or check your connection."
                    self?.isRetryableError = true
                }
            }
        }
    }

    func loadMoreNews() {
        if isOffline { return }
        // Avoid double-fetch
        guard !isLoadingPage else { return }
        guard hasMore else { return }
        // Cancel any in-flight paging load
        loadMoreTask?.cancel()

        loadMoreTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            let token = self.feedToken
            if self.isOffline {
                Task { @MainActor [weak self] in
                    self?.isLoadingPage = false
                }
                return
            }
            // Defer state modifications to avoid "Modifying state during view update"
            Task { @MainActor [weak self] in
                self?.errorMessage = nil
                self?.isRetryableError = false
                self?.isLoadingPage = true
            }

            var appendedAny = false
            var shouldAutoContinue = false
            var hadRemoteItems = false
            defer {
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.isLoadingPage = false
                    // If we didn't append and we still think there is more, auto-advance to the next page up to 3 quick attempts
                    if !appendedAny && shouldAutoContinue && self.pagingBurstAttempts < 3 {
                        self.pagingBurstAttempts += 1
                        Task { [weak self] in
                            try? await Task.sleep(nanoseconds: 150_000_000)
                            _ = await MainActor.run {
                                Task { @MainActor [weak self] in
                                    self?.loadMoreNews()
                                }
                            }
                        }
                    } else if appendedAny {
                        self.pagingBurstAttempts = 0
                    }
                    if !appendedAny && !hadRemoteItems { self.hasMore = false }
                }
            }

            let nextPage = self.currentPage + 1
            
            // Use a cursor slightly older than the last article to avoid overlap
            let cursorDate = self.articles.last?.publishedAt.addingTimeInterval(-600) // 10 minutes earlier

            do {
                let query = (self.queryOverride ?? self.selectedCategory.query)
                // let lastDate = self.articles.last?.publishedAt

                async let api: [CryptoNewsArticle] = (try? await self.newsService.fetchNews(query: query, page: 1, pageSize: 30, before: cursorDate)) ?? []
                async let rssA: [CryptoNewsArticle] = await RSSFetcher.fetch(limit: 60, before: cursorDate)
                async let rssB: [CryptoNewsArticle] = { try? await Task.sleep(nanoseconds: 1_200_000_000); return await RSSFetcher.fetch(limit: 40, before: cursorDate) }()
                async let headlines: [CryptoNewsArticle] = (try? await CryptoNewsFeedService().fetchNews(page: nextPage)) ?? []
                var firstBatch = await (api + rssA + rssB + headlines)
                firstBatch.sort { $0.publishedAt > $1.publishedAt }
                firstBatch = uniqueArticles(from: firstBatch)
                firstBatch = qualityFilter(firstBatch)

                hadRemoteItems = !firstBatch.isEmpty

                let existing = Set(self.articles.map { $0.id })
                var filtered = firstBatch.filter { !existing.contains($0.id) }
                let existingLinks = Set(self.articles.map { self.normalizedArticleKey(for: $0) })
                filtered = filtered.filter { !existingLinks.contains(self.normalizedArticleKey(for: $0)) }

                if !filtered.isEmpty {
                    filtered = self.applyFiltersWithRelaxation(filtered, minimumCount: 6)
                    if !filtered.isEmpty {
                        for a in filtered { self.ensureIconOverride(for: a) }
                        self.appendArticlesIfCurrent(filtered, token: token)
                        appendedAny = true
                        self.scheduleThumbnailResolution(for: filtered)
                        if let lastIdx = self.articles.indices.last { self.prefetchAround(index: lastIdx, radius: 12) }
                        Task { @MainActor [weak self] in
                            self?.currentPage = nextPage
                            self?.hasMore = true
                            self?.emptyPageStreak = 0
                        }
                    } else {
                        // Remote returned items but they were filtered out; try an RSS-only fallback before counting as empty
                        Task { @MainActor [weak self] in
                            self?.currentPage = nextPage
                        }
                        let rssFallback = await RSSFetcher.fetch(limit: 120, before: cursorDate?.addingTimeInterval(-3600))
                        if !rssFallback.isEmpty {
                            var rssFiltered = self.uniqueArticles(from: rssFallback)
                            rssFiltered = self.qualityFilter(rssFiltered)
                            let existingIDs = Set(self.articles.map { $0.id })
                            rssFiltered = rssFiltered.filter { !existingIDs.contains($0.id) }
                            rssFiltered = self.applyFiltersWithRelaxation(rssFiltered, minimumCount: 6)
                            if !rssFiltered.isEmpty {
                                for a in rssFiltered { self.ensureIconOverride(for: a) }
                                self.appendArticlesIfCurrent(rssFiltered, token: token)
                                appendedAny = true
                                self.scheduleThumbnailResolution(for: rssFiltered)
                                Task { @MainActor [weak self] in
                                    self?.hasMore = true
                                    self?.emptyPageStreak = 0
                                }
                            } else {
                                Task { @MainActor [weak self] in
                                    guard let self = self else { return }
                                    self.emptyPageStreak += 1
                                    self.hasMore = self.emptyPageStreak < self.maxEmptyPageStreak
                                }
                                shouldAutoContinue = self.hasMore
                            }
                        } else {
                            Task { @MainActor [weak self] in
                                guard let self = self else { return }
                                self.emptyPageStreak += 1
                                self.hasMore = self.emptyPageStreak < self.maxEmptyPageStreak
                            }
                            shouldAutoContinue = self.hasMore
                        }
                    }
                } else {
                    // No items returned at all; try an RSS-only fallback for older items before giving up
                    let rssFallback = await RSSFetcher.fetch(limit: 100, before: cursorDate)
                    if !rssFallback.isEmpty {
                        var rssFiltered = self.uniqueArticles(from: rssFallback)
                        rssFiltered = self.qualityFilter(rssFiltered)
                        let existingIDs = Set(self.articles.map { $0.id })
                        rssFiltered = rssFiltered.filter { !existingIDs.contains($0.id) }
                        rssFiltered = self.applyFiltersWithRelaxation(rssFiltered, minimumCount: 6)
                        if !rssFiltered.isEmpty {
                            for a in rssFiltered { self.ensureIconOverride(for: a) }
                            self.appendArticlesIfCurrent(rssFiltered, token: token)
                            appendedAny = true
                            self.scheduleThumbnailResolution(for: rssFiltered)
                            Task { @MainActor [weak self] in
                                self?.currentPage = nextPage
                                self?.hasMore = true
                                self?.emptyPageStreak = 0
                            }
                        } else {
                            // Final fallback: try Top Headlines page as a last resort
                            if let headlines = try? await CryptoNewsFeedService().fetchNews(page: nextPage), !headlines.isEmpty {
                                let existingIDs = Set(self.articles.map { $0.id })
                                var extra = headlines.filter { !existingIDs.contains($0.id) }
                                let existingLinks = Set(self.articles.map { self.normalizedArticleKey(for: $0) })
                                extra = extra.filter { !existingLinks.contains(self.normalizedArticleKey(for: $0)) }
                                // Apply quality filter to ensure crypto relevance
                                extra = self.qualityFilter(extra)
                                if !extra.isEmpty {
                                    for a in extra { self.ensureIconOverride(for: a) }
                                    self.appendArticlesIfCurrent(extra, token: token)
                                    self.scheduleThumbnailResolution(for: extra)
                                    appendedAny = true
                                    Task { @MainActor [weak self] in
                                        self?.currentPage = nextPage
                                        self?.hasMore = true
                                        self?.emptyPageStreak = 0
                                    }
                                } else {
                                    Task { @MainActor [weak self] in
                                        guard let self = self else { return }
                                        self.emptyPageStreak += 1
                                        self.hasMore = self.emptyPageStreak < self.maxEmptyPageStreak
                                    }
                                    shouldAutoContinue = self.hasMore
                                }
                            } else {
                                Task { @MainActor [weak self] in
                                    guard let self = self else { return }
                                    self.emptyPageStreak += 1
                                    self.hasMore = self.emptyPageStreak < self.maxEmptyPageStreak
                                }
                                shouldAutoContinue = self.hasMore
                            }
                        }
                    } else {
                        Task { @MainActor [weak self] in
                            guard let self = self else { return }
                            self.emptyPageStreak += 1
                            self.hasMore = self.emptyPageStreak < self.maxEmptyPageStreak
                        }
                        shouldAutoContinue = self.hasMore
                    }
                }
                Task { @MainActor [weak self] in
                    self?.isRetryableError = false
                }
            }
        }
    }

    @MainActor
    func loadLatestNews() async {
        if isOffline {
            // Seed Home preview from cache for instant UI, but still try to refresh.
            self.seedFromCacheIfEmpty(previewOnly: true)
        }
        if isOffline { return }
        Task { @MainActor [weak self] in
            self?.errorMessage = nil
        }
        let previewMode = (self.articles.count <= 5)
        if previewMode {
            Task { @MainActor [weak self] in
                self?.isLoading = true
            }
        }
        let token = self.feedToken
        
        // Seed Home preview from cache immediately if available to avoid delay
        self.seedFromCacheIfEmpty(previewOnly: true)

        defer {
            if previewMode {
                Task { @MainActor [weak self] in
                    self?.isLoading = false
                }
            }
        }

        let base = await fastestNews(query: (queryOverride ?? selectedCategory.query), page: 1, rssLimit: 8)
        let baseQ = qualityFilter(base)
        let now = Date()
        let twelveHoursAgo = now.addingTimeInterval(-12 * 3600)
        let recent = baseQ.filter { $0.publishedAt >= twelveHoursAgo }
        
        var pick = (recent.isEmpty ? baseQ : recent).sorted { $0.publishedAt > $1.publishedAt }
        // If newest is stale, aggressively merge in Top Headlines and a broad RSS pull
        if let newest = pick.first?.publishedAt, Date().timeIntervalSince(newest) > staleThreshold {
            if let headlines = try? await CryptoNewsFeedService().fetchNews(page: 1), !headlines.isEmpty {
                var merged = self.uniqueArticles(from: (headlines + pick))
                merged = self.qualityFilter(merged)
                pick = merged.sorted { $0.publishedAt > $1.publishedAt }
            }
            let rss = await RSSFetcher.fetch(limit: 150)
            if !rss.isEmpty {
                var merged = self.uniqueArticles(from: (pick + rss))
                merged = self.qualityFilter(merged)  // Filter for crypto relevance
                pick = merged.sorted { $0.publishedAt > $1.publishedAt }
            }
        }
        // Drop items older than maxAgeWindow only if it doesn't collapse the preview
        let cutoff = Date().addingTimeInterval(-maxAgeWindow)
        let trimmed = pick.filter { $0.publishedAt >= cutoff }
        // Only trim if we still have a decent preview list after trimming
        let finalList = (trimmed.count >= 15) ? trimmed : pick
        if !finalList.isEmpty {
            let top = Array(finalList.prefix(10))
            if self.articles.count > 5 {
                let currentTopIDs = Array(self.articles.prefix(top.count)).map { self.normalizedArticleKey(for: $0) }
                let newTopIDs = top.map { self.normalizedArticleKey(for: $0) }
                if currentTopIDs == newTopIDs {
                    CacheManager.shared.save(finalList, to: "news_cache.json")
                    Task { @MainActor [weak self] in
                        self?.lastFullRefreshAt = Date()
                        self?.homeNewCount = 0
                        self?.errorMessage = nil
                    }
                    return
                }
            }
            if self.articles.count <= 5 {
                self.publishArticlesIfCurrent(Array(top.prefix(5)), token: token)
                Task { @MainActor [weak self] in
                    self?.hasMore = true
                }
            } else {
                // Improved merge logic for visual stability
                // Strategy: Keep the hero article stable if it's still in the top results
                // This prevents jarring partial updates where only the list changes
                let currentHeroKey = self.articles.first.map { self.normalizedArticleKey(for: $0) }
                let newHeroKey = top.first.map { self.normalizedArticleKey(for: $0) }
                
                var seen = Set<String>()
                var merged: [CryptoNewsArticle] = []
                
                // If the hero article is the same, preserve it at position 0
                // Then merge the rest naturally by publish date
                if let currentHero = self.articles.first,
                   currentHeroKey == newHeroKey {
                    // Hero stays the same - stable merge
                    merged.append(currentHero)
                    seen.insert(self.normalizedArticleKey(for: currentHero))
                    
                    // Add remaining new articles
                    for a in top.dropFirst() {
                        if seen.insert(self.normalizedArticleKey(for: a)).inserted {
                            merged.append(a)
                        }
                    }
                    // Add remaining old articles
                    for a in self.articles.dropFirst() {
                        if seen.insert(self.normalizedArticleKey(for: a)).inserted {
                            merged.append(a)
                        }
                    }
                } else {
                    // Hero changed - full update (new articles first)
                    for a in top {
                        if seen.insert(self.normalizedArticleKey(for: a)).inserted {
                            merged.append(a)
                        }
                    }
                    for a in self.articles {
                        if seen.insert(self.normalizedArticleKey(for: a)).inserted {
                            merged.append(a)
                        }
                    }
                }
                
                // Ensure proper sort order by publish date
                merged.sort { $0.publishedAt > $1.publishedAt }
                self.publishArticlesIfCurrent(merged, token: token)
                Task { @MainActor [weak self] in
                    self?.hasMore = true
                }
            }
            CacheManager.shared.save(finalList, to: "news_cache.json")
            Task { @MainActor [weak self] in
                self?.lastFullRefreshAt = Date()
                self?.errorMessage = nil
            }
        } else {
            // Fallback to full refresh path
            self.loadAllNews()
        }
    }

    // Track read/bookmarked articles
    @Published private var readArticleIDs: Set<String> = []
    @Published private var bookmarkedArticleIDs: Set<String> = []
    
    /// Full persisted bookmarked articles - survives feed refreshes and article aging.
    /// This is the source of truth for the BookmarksView.
    @Published var bookmarkedArticles: [CryptoNewsArticle] = []

    /// Persistence keys for saved bookmarks
    private let bookmarksKey = "bookmarkedArticleIDs"
    private let bookmarksArticleCacheFile = "bookmarked_articles.json"

    // MARK: - Read / Bookmark Actions

    func toggleRead(_ article: CryptoNewsArticle) {
        if isRead(article) {
            readArticleIDs.remove(article.id)
        } else {
            readArticleIDs.insert(article.id)
        }
    }

    func isRead(_ article: CryptoNewsArticle) -> Bool {
        readArticleIDs.contains(article.id)
    }

    func toggleBookmark(_ article: CryptoNewsArticle) {
        if isBookmarked(article) {
            bookmarkedArticleIDs.remove(article.id)
            bookmarkedArticles.removeAll { $0.id == article.id }
        } else {
            bookmarkedArticleIDs.insert(article.id)
            // Add the full article object if not already present
            if !bookmarkedArticles.contains(where: { $0.id == article.id }) {
                bookmarkedArticles.insert(article, at: 0) // newest bookmarks first
            }
        }
        // Persist both the IDs (for quick lookup) and full articles (for display)
        saveBookmarks()
    }

    func isBookmarked(_ article: CryptoNewsArticle) -> Bool {
        bookmarkedArticleIDs.contains(article.id)
    }

    /// Load bookmarked articles from persisted storage.
    /// Loads full article objects so bookmarks survive feed refreshes.
    private func loadBookmarks() {
        // Load IDs for quick lookup
        if let saved = UserDefaults.standard.array(forKey: bookmarksKey) as? [String] {
            bookmarkedArticleIDs = Set(saved)
        }
        
        // Load full article objects from disk cache
        if let savedArticles: [CryptoNewsArticle] = CacheManager.shared.load(
            [CryptoNewsArticle].self,
            from: bookmarksArticleCacheFile
        ), !savedArticles.isEmpty {
            bookmarkedArticles = savedArticles
            // Ensure IDs are in sync (articles are source of truth)
            bookmarkedArticleIDs = Set(savedArticles.map { $0.id })
            UserDefaults.standard.set(Array(bookmarkedArticleIDs), forKey: bookmarksKey)
        } else if !bookmarkedArticleIDs.isEmpty {
            // Migration: We have IDs but no article cache.
            // Try to recover articles from the current feed for any matching IDs.
            let recovered = articles.filter { bookmarkedArticleIDs.contains($0.id) }
            if !recovered.isEmpty {
                bookmarkedArticles = recovered.sorted { $0.publishedAt > $1.publishedAt }
                CacheManager.shared.save(bookmarkedArticles, to: bookmarksArticleCacheFile)
            }
            // IDs with no matching articles are kept - they'll be cleaned up eventually
        }
    }

    /// Save current bookmarked articles to persistent storage.
    private func saveBookmarks() {
        // Save IDs for quick lookup
        let ids = Array(bookmarkedArticleIDs)
        UserDefaults.standard.set(ids, forKey: bookmarksKey)
        
        // Save full article objects so bookmarks survive feed refreshes
        CacheManager.shared.save(bookmarkedArticles, to: bookmarksArticleCacheFile)
    }

    private func saveFilters() {
        UserDefaults.standard.set(selectedCategory.rawValue, forKey: selectedCategoryKey)
        UserDefaults.standard.set(withImagesOnly, forKey: withImagesOnlyKey)
        let sourcesArr = Array(selectedSources)
        UserDefaults.standard.set(sourcesArr, forKey: selectedSourcesKey)
    }

    private func loadSavedFilters() {
        if let raw = UserDefaults.standard.string(forKey: selectedCategoryKey),
           let cat = NewsCategory(rawValue: raw) {
            selectedCategory = cat
        }
        if UserDefaults.standard.object(forKey: withImagesOnlyKey) != nil {
            withImagesOnly = UserDefaults.standard.bool(forKey: withImagesOnlyKey)
        }
        if let arr = UserDefaults.standard.array(forKey: selectedSourcesKey) as? [String] {
            selectedSources = Set(arr)
        }
    }

    // MARK: - Simplified Thumbnail URL Provider
    // The view (CachingAsyncImageContent) handles all loading logic including fallbacks.
    // ViewModel just provides a stable URL to prevent flickering during scrolling.
    
    /// Returns the best thumbnail URL for an article
    /// Simple logic: use article's image URL if valid, otherwise return favicon as fallback
    func thumbnailURL(for article: CryptoNewsArticle) -> URL? {
        // Check if we've already determined the URL for this article (stability)
        // This cache ensures thumbnails don't flicker during scrolling or refresh
        if let cached = displayedThumbnailURLs[article.id] {
            return cached
        }
        
        // Compute and cache the URL
        let url = computeThumbnailURL(for: article)
        // Always cache the result (even nil would be cached as favicon below)
        displayedThumbnailURLs[article.id] = url
        return url
    }
    
    /// Compute the thumbnail URL without caching
    /// Returns the article's image if present and valid, otherwise returns favicon as fallback
    private func computeThumbnailURL(for article: CryptoNewsArticle) -> URL? {
        // Use article's image if present
        if let raw = article.urlToImage {
            // Sanitize the URL (upgrade to HTTPS, remove tracking params)
            if let sanitized = NewsImageUtilities.sanitizeImageURL(raw) {
                // Only skip the URL if it's clearly a tiny favicon/icon
                // CryptoCompare and other news sources often have valid images we want to keep
                if !NewsImageUtilities.isLikelyIconURL(sanitized) {
                    return sanitized
                }
                // Even if it looks like an icon, use it if it's from a known image CDN
                // (these are likely valid article thumbnails, not site favicons)
                if isKnownImageCDN(sanitized) {
                    return sanitized
                }
            }
        }
        // Fallback to high-quality favicon - better than showing empty placeholder
        // Use Google's favicon service which provides consistent, high-resolution icons
        if let host = article.url.host {
            let faviconURL = "https://www.google.com/s2/favicons?domain=\(host)&sz=128"
            return URL(string: faviconURL)
        }
        return nil
    }
    
    /// Check if URL is from a known image CDN (trusted to have real article images)
    private func isKnownImageCDN(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let knownCDNs = [
            "cryptocompare.com", "images.cryptocompare.com", "resources.cryptocompare.com",
            "cointelegraph.com", "s3.cointelegraph.com", "images.cointelegraph.com",
            "decrypt.co", "cdn.decrypt.co", "img.decrypt.co",
            "coindesk.com", "static.coindesk.com", "coindesk-coindesk-prod.cdn.arcpublishing.com",
            "theblock.co", "static.theblock.co",
            "bitcoinmagazine.com", "cryptoslate.com", "img.cryptoslate.com",
            "ambcrypto.com", "cryptopotato.com", "u.today", "dailyhodl.com",
            "bitcoinist.com", "cryptonews.com", "newsbtc.com", "beincrypto.com",
            "cloudfront.net", "amazonaws.com", "wp.com", "i0.wp.com", "i1.wp.com", "i2.wp.com"
        ]
        return knownCDNs.contains { host.contains($0) }
    }
    
    /// Check if an article has a thumbnail override (for debug views)
    func hasThumbnailOverride(for article: CryptoNewsArticle) -> Bool {
        displayedThumbnailURLs[article.id] != nil
    }

    // MARK: - Thumbnail Resolution (Simplified)
    // Most resolution is now handled by the view layer.
    // ViewModel only does minimal prefetching for visible articles.
    
    /// Prefetch thumbnails for articles - simplified to just pre-compute URLs
    private func scheduleThumbnailResolution(for articles: [CryptoNewsArticle]) {
        // Pre-compute URLs for stability - actual loading handled by view
        for article in articles {
            _ = thumbnailURL(for: article)
        }
    }

    /// Prefetch thumbnails for a window of articles around a given index
    func prefetchAround(index: Int, radius: Int = 8) {
        guard !articles.isEmpty else { return }
        let lower = max(0, index - radius)
        let upper = min(articles.count, index + radius + 1)
        if lower < upper {
            let window = Array(articles[lower..<upper])
            scheduleThumbnailResolution(for: window)
        }
    }

    /// Prefetch thumbnails for the first N articles (first screenful)
    func prefetchTop(count: Int = 12) {
        guard !articles.isEmpty else { return }
        let subset = Array(articles.prefix(count))
        scheduleThumbnailResolution(for: subset)
    }
    
    /// Pre-warm thumbnail cache - simplified, view handles actual loading
    private func prewarmThumbnailCache(for articles: [CryptoNewsArticle]) async {
        for article in articles.prefix(6) {
            _ = thumbnailURL(for: article)
        }
    }

    // MARK: - Canonical URL helpers and safe publishing

    private func sanitizeURL(_ url: URL) -> URL {
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if comps?.scheme?.lowercased() == "http" { comps?.scheme = "https" }
        let blocked = Set(["utm_source","utm_medium","utm_campaign","utm_term","utm_content","fbclid","gclid","igshid","mc_cid","mc_eid"])
        if let items = comps?.queryItems, !items.isEmpty {
            comps?.queryItems = items.filter { !blocked.contains($0.name.lowercased()) }
        }
        if var c = comps { c.host = c.host?.lowercased(); return c.url ?? url }
        return comps?.url ?? url
    }

    private func isPublisherRoot(_ url: URL) -> Bool {
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty
    }

    private func isLikelySectionPage(_ url: URL) -> Bool {
        let trimmed = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmed.isEmpty { return true }
        let lower = trimmed.lowercased()
        // Common section keywords
        let sectionKeywords: Set<String> = [
            "news","markets","latest","home","stories","story","articles","article","blog","category","categories","tags","tag","topic","topics","business","crypto","technology","tech","economy","finance"
        ]
        if sectionKeywords.contains(lower) { return true }
        // Shallow, non-numeric single-component paths are likely sections (e.g., "/markets")
        let comps = lower.split(separator: "/")
        if comps.count <= 1 && lower.rangeOfCharacter(from: .decimalDigits) == nil { return true }
        // Locale or index shortcuts
        if lower == "en" || lower == "index" { return true }
        return false
    }

    /// Build a Google search URL that searches for the article title on the publisher's site.
    /// This is more reliable than "I'm Feeling Lucky" which often fails.
    private func googleSearchURL(for article: CryptoNewsArticle, host: String) -> URL? {
        // Extract just the domain without www prefix for cleaner search
        let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        // Use exact phrase match for the title
        let title = article.title.replacingOccurrences(of: "\"", with: "")
        let q = "site:\(domain) \"\(title)\""
        guard let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "https://www.google.com/search?q=\(enc)")
    }

    func bestURL(for article: CryptoNewsArticle) -> URL {
        // Use the original article URL with minimal sanitization (tracking params only)
        // Avoid AMP transforms and canonical overrides which can cause 404s
        let clean = sanitizeURL(article.url)
        
        // Only use Google search fallback for truly broken URLs (publisher root pages)
        if isPublisherRoot(clean) {
            if let host = clean.host?.lowercased() {
                NewsDebug.warn("Article has homepage URL, using search fallback: \(clean.absoluteString)")
                if let searchURL = googleSearchURL(for: article, host: host) {
                    return searchURL
                }
            }
        }
        
        // Return sanitized original URL directly - trust the source APIs
        return clean
    }

    private func publishArticlesIfCurrent(_ list: [CryptoNewsArticle], token: UUID) {
        // Defer state changes to next runloop cycle to avoid "Modifying state during view update"
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            guard self.feedToken == token else { return }
            let previous = self.articles
            // Apply category filter before publishing, then ensure sorted by newest first
            let filtered = self.filterByCategory(list, category: self.selectedCategory)
                .sorted { $0.publishedAt > $1.publishedAt }
            
            // Animate list changes for smooth transitions (spring for natural feel)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                self.articles = filtered
            }
            self.noteNewArticles(old: previous, new: filtered)
            
            // Process thumbnails after a brief delay to avoid UI blocking
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms delay
                self.processNewArticles()
            }
        }
    }

    private func appendArticlesIfCurrent(_ list: [CryptoNewsArticle], token: UUID) {
        // Defer state changes to next runloop cycle to avoid "Modifying state during view update"
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            guard self.feedToken == token else { return }
            guard !list.isEmpty else { return }
            // Apply category filter to new articles before appending
            let categoryFiltered = self.filterByCategory(list, category: self.selectedCategory)
            guard !categoryFiltered.isEmpty else { return }
            
            var merged = self.articles
            let existingKeys = Set(merged.map { self.normalizedArticleKey(for: $0) })
            var seenNew = Set<String>()
            for a in categoryFiltered {
                let key = self.normalizedArticleKey(for: a)
                if existingKeys.contains(key) { continue }
                if !seenNew.insert(key).inserted { continue }
                merged.append(a)
            }
            // Ensure proper sort order after merging
            merged.sort { $0.publishedAt > $1.publishedAt }
            
            // Animate list changes for smooth append transitions (spring for natural feel)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                self.articles = merged
            }
            
            // Process thumbnails after a brief delay to avoid UI blocking
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms delay
                self.processNewArticles()
            }
        }
    }

    private func uniqueArticles(from list: [CryptoNewsArticle]) -> [CryptoNewsArticle] {
        // Merge duplicates by normalized URL key
        var bestByKey: [String: CryptoNewsArticle] = [:]
        for a in list {
            let key = normalizedArticleKey(for: a)
            if let existing = bestByKey[key] {
                // Prefer the most recent plausible publish date across duplicates to avoid stale times skewing newer items
                let newest = max(existing.publishedAt, a.publishedAt)
                let mergedDate = min(newest, Date().addingTimeInterval(60)) // clamp to avoid future dates
                // Prefer the entry that has a real image if the other lacks one
                let pickHasImage = (existing.urlToImage != nil)
                let candidateHasImage = (a.urlToImage != nil)
                let chosen: CryptoNewsArticle = (!pickHasImage && candidateHasImage) ? a : existing
                // Rebuild with chosen fields but enforce the merged publish date
                let merged = CryptoNewsArticle(
                    title: chosen.title,
                    description: chosen.description,
                    url: chosen.url,
                    urlToImage: chosen.urlToImage,
                    sourceName: chosen.sourceName,
                    publishedAt: mergedDate
                )
                bestByKey[key] = merged
            } else {
                bestByKey[key] = a
            }
        }
        // CONSISTENCY FIX: Return newest first for UI with deterministic secondary sort by URL
        // When two articles have the same publish date, sort by URL to ensure consistent ordering across devices
        return bestByKey.values.sorted { 
            if $0.publishedAt == $1.publishedAt {
                return $0.url.absoluteString < $1.url.absoluteString // Deterministic tiebreaker
            }
            return $0.publishedAt > $1.publishedAt 
        }
    }

    private func normalizedArticleKey(_ url: URL) -> String {
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        // Drop common tracking params
        let blocked = Set(["utm_source","utm_medium","utm_campaign","utm_term","utm_content","fbclid","gclid","igshid","mc_cid","mc_eid"])
        if let items = comps?.queryItems, !items.isEmpty {
            comps?.queryItems = items.filter { !blocked.contains($0.name.lowercased()) }
        }
        // Remove default ports and lowercase host
        if var c = comps { c.host = c.host?.lowercased(); return (c.url ?? url).absoluteString }
        return url.absoluteString
    }

    private func normalizedArticleKey(for article: CryptoNewsArticle) -> String {
        let url = article.url
        var key = normalizedArticleKey(url)
        if isPublisherRoot(url) || isLikelySectionPage(url) {
            let titleKey = article.title
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            key += "#t=" + titleKey
        }
        return key
    }

    /// Apply active client-side filters to a list of articles
    private func applyActiveFilters(_ list: [CryptoNewsArticle]) -> [CryptoNewsArticle] {
        var arr = list
        if !selectedSources.isEmpty {
            let lowerSelected = Set(selectedSources.map { $0.lowercased() })
            arr = arr.filter { lowerSelected.contains($0.sourceName.lowercased()) }
        }
        if withImagesOnly {
            arr = arr.filter { $0.urlToImage != nil }
        }
        return arr
    }
    
    /// Apply filters, but if they over-filter the list (result too small), relax them for this load.
    private func applyFiltersWithRelaxation(_ list: [CryptoNewsArticle], minimumCount: Int = 10) -> [CryptoNewsArticle] {
        var usedFilters = false
        var arr = list
        if !selectedSources.isEmpty {
            usedFilters = true
            let lowerSelected = Set(selectedSources.map { $0.lowercased() })
            arr = arr.filter { lowerSelected.contains($0.sourceName.lowercased()) }
        }
        if withImagesOnly {
            usedFilters = true
            arr = arr.filter { $0.urlToImage != nil }
        }
        // If filters produce too few results, relax them for this render
        if usedFilters && arr.count < minimumCount {
            return list
        }
        return arr
    }

    /// Warm the next page during idle so the next scroll is instant
    private func warmNextPageIfNeeded() {
        if isOffline { return }
        guard hasMore, !isLoadingPage, !prefetchNextScheduled else { return }
        guard Self.warmPrefetchesMade < 2 else { return }
        prefetchNextScheduled = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            _ = await MainActor.run {
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if self.hasMore && !self.isLoadingPage {
                        Self.warmPrefetchesMade += 1
                        self.loadMoreNews()
                    }
                    self.prefetchNextScheduled = false
                }
            }
        }
    }

    /// Prefer a crisp, high-resolution logo for well-known publishers
    private func highResPublisherLogo(for articleURL: URL) -> URL? {
        guard let host = articleURL.host?.lowercased() else { return nil }
        if host.contains("coindesk") {
            return URL(string: "https://upload.wikimedia.org/wikipedia/commons/5/5c/CoinDesk_Logo.png")
        } else if host.contains("cointelegraph") {
            return URL(string: "https://upload.wikimedia.org/wikipedia/commons/3/3c/Cointelegraph_logo.png")
        } else if host.contains("theblock") {
            return URL(string: "https://upload.wikimedia.org/wikipedia/commons/4/47/The_Block_logo.png")
        }
        return nil
    }

    /// Detect generic/sitewide images that are not specific article heroes
    private func isLikelyGenericSiteImage(_ url: URL?, forArticleURL articleURL: URL) -> Bool {
        guard let url = url else { return false }
        if NewsImageUtilities.isLikelyIconURL(url) { return true }
        
        let p = url.path.lowercased()
        let imgHost = (url.host ?? "").lowercased()
        let lastComponent = url.lastPathComponent.lowercased()
        
        // Treat common non-article assets as generic
        let genericPathPatterns = [
            "/logo", "/logos", "/brand", "/branding",
            "/favicon", "apple-touch-icon",
            "opengraph", "og-image", "/social", "/share",
            "default", "placeholder", "sprite",
            "/header", "/banner", "/masthead",
            "/assets/images/default", "/static/default",
            "generic-", "fallback-", "no-image",
            "/thumbnail-default", "/default-thumb"
        ]
        for pattern in genericPathPatterns {
            if p.contains(pattern) { return true }
        }
        
        // SVG files are usually logos/icons, not article images
        if p.hasSuffix(".svg") { return true }
        
        // Treat common OG/social variants as generic even if not named exactly "og-image"
        if p.contains("/og/") || p.contains("_og") || p.contains("-og") || p.contains("og.") { return true }
        
        // Host-specific detection for known publishers with generic images
        // CoinTelegraph often uses branded OG tiles
        if imgHost.contains("cointelegraph") && (p.contains("cointelegraph") || p.contains("default")) { return true }
        // CryptoSlate default images
        if imgHost.contains("cryptoslate") && p.contains("default") { return true }
        // NewsBTC generic thumbnails
        if imgHost.contains("newsbtc") && (p.contains("default") || p.contains("generic")) { return true }
        // BeInCrypto branded images
        if imgHost.contains("beincrypto") && p.contains("bic-") && p.contains("logo") { return true }
        
        // Very small requested sizes via query params are likely icons
        if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false), let items = comps.queryItems {
            let dict = Dictionary(uniqueKeysWithValues: items.map { ($0.name.lowercased(), $0.value ?? "") })
            func intVal(_ key: String) -> Int? { Int(dict[key] ?? "") }
            let w = intVal("w") ?? intVal("width")
            let h = intVal("h") ?? intVal("height")
            // Icons are typically under 200px; real thumbnails start at 300px+
            if let w = w, w > 0, w <= 200 { return true }
            if let h = h, h > 0, h <= 200 { return true }
        }
        
        // Generic sources (e.g., Wikipedia brand pages - these are publisher logos, not article images)
        if imgHost.contains("wikipedia.org") { return true }
        if imgHost.contains("upload.wikimedia.org") { return true }
        
        // Common generic file names
        let genericFileNames = ["default.jpg", "default.png", "default.webp", "placeholder.jpg", "placeholder.png", "no-image.jpg", "no-image.png", "thumbnail.jpg", "thumbnail.png"]
        if genericFileNames.contains(lastComponent) { return true }
        
        // Detect coin logo CDNs - these are cryptocurrency icons, not article thumbnails
        // NewsAPI sometimes returns coin logos as urlToImage for coin-related articles
        let coinLogoCDNs = [
            "assets.coingecko.com/coins",
            "s2.coinmarketcap.com/static/img/coins",
            "assets.coincap.io/assets/icons",
            "cryptologos.cc/logos",
            "cdn.jsdelivr.net/gh/atomiclabs/cryptocurrency-icons",
            "cryptoicons.org",
            "coinicons.io"
        ]
        let fullURL = imgHost + p
        for cdn in coinLogoCDNs {
            if fullURL.contains(cdn) { return true }
        }
        
        // Detect common coin logo path patterns (e.g., /coins/images/123/thumb/bitcoin.png)
        if p.contains("/coins/") && (p.contains("/thumb/") || p.contains("/small/") || p.contains("/large/") || p.contains("/images/")) {
            return true
        }
        
        // Detect cryptocurrency symbol-based image names (e.g., btc.png, ethereum.png, xrp-logo.png)
        let cryptoSymbolPatterns = [
            "bitcoin", "ethereum", "xrp", "ripple", "solana", "cardano", "dogecoin",
            "litecoin", "polkadot", "avalanche", "chainlink", "polygon", "matic"
        ]
        for symbol in cryptoSymbolPatterns {
            if lastComponent.contains(symbol) && (lastComponent.contains("logo") || lastComponent.contains("icon") || lastComponent.hasSuffix("-\(symbol).png") || lastComponent.hasSuffix("_\(symbol).png")) {
                return true
            }
        }
        
        return false
    }

    /// Fast favicon fallback for a publisher domain so the UI always has an icon immediately.
    private func publisherIconURL(for articleURL: URL) -> URL? {
        // Prefer a curated high-res logo for top publishers, then fall back to Google s2 favicon
        if let hi = highResPublisherLogo(for: articleURL) { return hi }
        guard let host = articleURL.host?.lowercased(), !host.isEmpty else { return nil }
        let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return URL(string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=256")
    }

    /// Perform a search; empty search clears override and reloads default category
    func performSearch() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            queryOverride = nil
        } else {
            queryOverride = trimmed
        }
        // Reset paging state
        hasMore = true
        currentPage = 1
        feedToken = UUID()
        loadAllNews(force: true)
    }
    
    /// Legacy method - now a no-op since view handles fallback loading
    func ensureIconOverride(for article: CryptoNewsArticle) {
        // No-op - view handles all fallback logic
    }

    /// Legacy method - now a no-op since view handles image loading
    func upgradeImageIfPossible(_ article: CryptoNewsArticle) {
        // No-op - view handles all image loading and upgrades
    }

    // MARK: - Thumbnail State
    /// Cache of displayed thumbnail URLs for stability (prevents flickering)
    private var displayedThumbnailURLs: [String: URL] = [:]
    
    @Published var errorMessage: String?

    /// Force a fresh reload that prefers the last 12 hours of news and resets paging.
    func forceFreshReload() {
        // Cancel any in-flight tasks
        loadAllTask?.cancel()
        loadMoreTask?.cancel()

        loadAllTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            let token = self.feedToken
            if self.isOffline {
                // Defer state modification to avoid "Modifying state during view update"
                Task { @MainActor [weak self] in
                    self?.isLoading = false
                }
                self.seedFromCacheIfEmpty(previewOnly: false)
                return
            }
            // Defer state modifications to avoid "Modifying state during view update"
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.errorMessage = nil
                self.isRetryableError = false
                self.isLoading = true
                self.hasMore = true
                self.currentPage = 1
                self.emptyPageStreak = 0
            }

            let merged = await self.fastestNews(query: (self.queryOverride ?? self.selectedCategory.query), page: 1, rssLimit: 80)
            let twelveHoursAgo = Date().addingTimeInterval(-12 * 3600)
            let fresh = merged.filter { $0.publishedAt >= twelveHoursAgo }
            let ordered = (fresh.isEmpty ? merged : fresh).sorted { $0.publishedAt > $1.publishedAt }
            let unique = self.uniqueArticles(from: ordered)
            if !unique.isEmpty {
                self.publishArticlesIfCurrent(unique, token: token)
                // Defer state modifications to avoid "Modifying state during view update"
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.hasMore = true
                    self.isLoading = false
                }
                // Allow immediate subsequent refreshes
                self.lastFullRefreshAt = nil
                CacheManager.shared.save(unique, to: "news_cache.json")
                // Kick off image resolution for first screenful
                self.scheduleThumbnailResolution(for: Array(unique.prefix(20)))
            } else {
                // Defer state modifications to avoid "Modifying state during view update"
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.errorMessage = "No fresh news available"
                    self.isRetryableError = false
                    self.isLoading = false
                }
            }
        }
    }
}

