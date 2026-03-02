import Foundation
import _Concurrency
import Combine
import os

@MainActor
final class MarketViewModel: ObservableObject {
    // PERFORMANCE FIX: Cached ISO8601 formatter — avoids 4+ allocations per global stats update
    private static let _isoFormatter = ISO8601DateFormatter()
    // Note: 1h/24h percent sourcing is centralized in LivePriceManager; this VM should not maintain its own percent caches.
    // MARK: - Internal State & Caches (added)
    private var isSanitizingWatchlist: Bool = false
    private var enableStatsLogging: Bool = false
    private var enableDiagLogs: Bool = false
    
    // MARK: - Debug Logging Control
    // Set to true to enable verbose deduplication logging (noisy in production)
    #if DEBUG
    private static let verboseDedupeLogging = false
    #else
    private static let verboseDedupeLogging = false
    #endif
    
    /// PERFORMANCE: Guard to prevent duplicate loadAllData() calls
    /// This prevents cascading API requests when multiple views trigger loads simultaneously
    private var isLoadingAllData: Bool = false
    
    /// MEMORY FIX: Guard to prevent multiple simultaneous cache loading tasks.
    /// Without this, the livePriceCancellable sink (fires every 500ms) spawns a new
    /// async Task to load+decode the 1.8MB coins cache EACH TIME allCoins.count < 50.
    /// This caused 20+ simultaneous cache decode tasks, each creating 250+ MarketCoin
    /// objects, leading to the 1.54 GB memory explosion that crashed the app.
    private var isCacheLoadInFlight: Bool = false
    // Diagnostics controls for overlay
    var diagnosticsEnabled: Bool { enableDiagLogs }
    func setDiagnosticsLoggingEnabled(_ on: Bool) { enableDiagLogs = on }
    private var useLiveForWatchlist: Bool = true // keep watchlist percent changes derived/snapshotted

    // Price/volume books (rebuilt from snapshots)
    private var idPriceBook: [String: Double] = [:]
    private var symbolPriceBook: [String: Double] = [:]
    private var idVolumeBook: [String: Double] = [:]
    private var symbolVolumeBook: [String: Double] = [:]

    // Hysteresis caches for prices and percent changes

    // Orientation/display caches for sparkline rendering and stability
    private var orientationCache: [String: Bool] = [:]          // id -> isReversed
    private var orientationCacheAt: [String: Date] = [:]        // id -> last orientation decision time
    private var orientationSeriesFP: [String: Int] = [:]        // id -> fingerprint of the series used for orientation
    private var displaySeriesCache: [String: [Double]] = [:]    // id -> last display-ready series
    private var displaySeriesCacheKey: [String: Int] = [:]      // id -> fingerprint+bucket key for cache validation
    // CACHE FIX: Added timestamps for display series cache expiration
    private var displaySeriesCacheAt: [String: Date] = [:]      // id -> last cache update time
    private let displaySeriesCacheTTL: TimeInterval = 300       // 5 minutes expiration

    // Restore normal cache capacity for a full market universe.
    private let maxOrientationCacheEntries: Int = 600
    private let maxDisplayCacheEntries: Int = 600

    // Inserted properties for stickiness timestamps for percent changes

    private let orientationStickinessTTL: TimeInterval = 5400 // 90 minutes

    // Sorting throttling
    private var pendingFilterWork: DispatchWorkItem?
    private var lastSortedIDs: [String] = []
    private var lastSortedAt: Date = .distantPast
    private var lastTopSetHash: Int = 0
    // STALE PRICE FIX: Track whether first live data has been received to force immediate filter/sort
    private var hasReceivedFirstLiveData: Bool = false
    // FIX v14: Once fresh API data has been received, block all cache loads from overwriting it.
    // Multiple code paths (sink handler line 1117, applyAllFiltersAndSort cache fallback) can
    // asynchronously load stale coins_cache.json and overwrite fresh Firebase/API prices.
    private var hasFreshAPIData: Bool = false
    private let minResortInterval: TimeInterval = 1.2
    // During bootstrap, slightly increase resort throttling to reduce early churn
    private var effectiveMinResortInterval: TimeInterval { Date() < self.bootstrapUntil ? max(self.minResortInterval, 1.8) : self.minResortInterval }

    // Added constant
    private let minUsableSnapshotCount: Int = 3

    // Stickiness log rate-limiting
    private var lastUnionBaselineLogAt: Date = .distantPast
    private var lastGeckoSkipLogAt: Date = .distantPast


    // Network health/backoff (with exponential backoff)
    private var degradedUntil: Date = .distantPast
    private var degradeBackoff: TimeInterval = 30 // starts at 30s, grows on repeated failures
    private var lastNetworkFailureAt: Date = .distantPast
    private var isNetworkDegraded: Bool { Date() < degradedUntil }
    private func recordNetworkFailure(_ error: Error) {
        let now = Date()
        // If failures are close together, grow backoff; otherwise reset to baseline
        if now.timeIntervalSince(lastNetworkFailureAt) < 60 {
            degradeBackoff = min(degradeBackoff * 1.5, 180) // cap at 3 minutes
        } else {
            degradeBackoff = 30
        }
        lastNetworkFailureAt = now
        degradedUntil = now.addingTimeInterval(degradeBackoff)
        diag("Diag: Network failure recorded; degraded for \(Int(degradeBackoff))s")
        
        // ERROR STATE: Expose network error to UI
        errorMessage = "Network issue — using cached data"
        isUsingCachedData = true
    }
    private func recordNetworkSuccess() {
        degradedUntil = .distantPast
        degradeBackoff = 30
        // Clear error state on success
        errorMessage = nil
        isUsingCachedData = false
    }

    // Gecko-specific rate limit/backoff and in-flight guards
    private var geckoRateLimitedUntil: Date = .distantPast
    private var geckoPenaltyBackoff: TimeInterval = 120 // RATE LIMIT FIX: Increased from 90s - Firestore is primary source
    private var geckoFetchInFlight: Bool = false
    private var pendingGeckoFetchWork: DispatchWorkItem?

    // Backfill control
    private var lastBackfillAt: Date = .distantPast
    private let backfillCooldown: TimeInterval = 60

    // Gecko global stats control
    private var lastGeckoFetchAt: Date = .distantPast
    private var minStatsComputeSpacing: TimeInterval { Date() < self.bootstrapUntil ? 4.0 : 2.5 }
    private let geckoFetchCooldown: TimeInterval = 45

    // Watchlist kickstart control
    private var isKickstartingWatchlist: Bool = false
    private var lastKickstartAt: Date = .distantPast
    private var recentKickstartIDs: [String: Date] = [:]
    private let kickstartCooldown: TimeInterval = 45

    // First-frame quiet start to avoid heavy work during initial render
    private var firstFrameQuietUntil: Date = .distantPast
    private var hasScheduledPostQuietBaseline: Bool = false

    // Gate global stats recomputation to avoid running every filter pass
    private var lastStatsComputeAt: Date = .distantPast

    /// Exchange-like hard priority ordering used as a primary sort key for the All segment.
    /// Note: Stablecoins (USDT, USDC, etc.) excluded - they are handled separately and pushed lower in the list.
    static let exchangePrioritySymbols: [String] = [
        "BTC","ETH","BNB","SOL","XRP","TON","ADA","DOGE",
        "TRX","DOT","AVAX","SHIB","LINK","LTC","BCH","XLM","ATOM","NEAR",
        "MATIC","APT","OP","ARB","ETC","UNI","XMR","FIL","ICP","HBAR",
        "ALGO","VET","INJ","TIA","SUI","AAVE","RNDR","TAO","SEI"
    ]
    static let exchangePriorityIndex: [String: Int] = {
        var map: [String: Int] = [:]
        for (i, s) in exchangePrioritySymbols.enumerated() { map[s] = i }
        return map
    }()

    /// Known fallback icons by symbol (lowercased)
    static let fallbackImageURLs: [String: URL] = [
        "btc": URL(string: "https://assets.coingecko.com/coins/images/1/large/bitcoin.png")!,
        "eth": URL(string: "https://assets.coingecko.com/coins/images/279/large/ethereum.png")!,
        "usdt": URL(string: "https://assets.coingecko.com/coins/images/325/large/Tether.png")!,
        "usdc": URL(string: "https://assets.coingecko.com/coins/images/6319/large/USD_Coin_icon.png")!,
        "bnb": URL(string: "https://assets.coingecko.com/coins/images/825/large/bnb-icon2_2x.png")!,
        "sol": URL(string: "https://assets.coingecko.com/coins/images/4128/large/solana.png")!,
        "xrp": URL(string: "https://assets.coingecko.com/coins/images/44/large/xrp-symbol-white-128.png")!,
        "ada": URL(string: "https://assets.coingecko.com/coins/images/975/large/cardano.png")!,
        "doge": URL(string: "https://assets.coingecko.com/coins/images/5/large/dogecoin.png")!
    ]

    /// Shared singleton instance for global access
    static let shared = MarketViewModel()

    // MARK: - Published Properties
    @Published var state: LoadingState<[MarketCoin]> = .idle
    /// USER-FACING ERROR: Exposes network/data errors to the UI for user feedback
    @Published var errorMessage: String? = nil
    /// Indicates if data is stale (using cached data due to network issues)
    @Published var isUsingCachedData: Bool = false
    /// FIX: Indicates that initial cache has been loaded and coins are ready
    /// Views and services should wait for this before accessing allCoins/watchlistCoins
    @Published var isInitialized: Bool = false
    
    /// FIX: Async method to wait until initialization completes (cache loaded)
    /// Use this to ensure data is ready before accessing allCoins/watchlistCoins
    /// Times out after maxWait seconds to prevent infinite waiting
    func waitForInitialization(maxWait: TimeInterval = 3.0) async {
        // Already initialized - return immediately
        if isInitialized { return }
        
        let startTime = Date()
        while !isInitialized {
            // Check timeout
            if Date().timeIntervalSince(startTime) > maxWait {
                diag("Diag: waitForInitialization timed out after \(maxWait)s")
                break
            }
            // Small sleep to avoid busy-waiting
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }
    }
    @Published var favoriteIDs: Set<String> = FavoritesManager.shared.getAllIDs()
    private var favoriteOrder: [String] { FavoritesManager.shared.getOrder() }
    // PERFORMANCE FIX: Track last watchlist content hash to avoid redundant processing
    private var lastWatchlistContentHash: Int = 0
    
    @Published var watchlistCoins: [MarketCoin] = [] {
        didSet {
            // REFACTOR: Extracted to separate method for maintainability
            updateWatchlistCoins(from: oldValue)
        }
    }
    
    /// REFACTOR: Extracted from watchlistCoins didSet for better maintainability.
    /// Handles watchlist sanitization, ordering, and data enrichment.
    /// PERFORMANCE FIX: Heavy computation moved to background queue
    private func updateWatchlistCoins(from oldValue: [MarketCoin]) {
        guard !isSanitizingWatchlist else { return }
        
        // FIX: Hash only IDs (not prices) to break the didSet feedback loop.
        // Previously the hash included prices, meaning every price tick from LivePriceManager
        // caused the full sanitization/reorder pipeline to re-run, which called
        // publishWatchlistCoinsCoalesced → set watchlistCoins → didSet → loop.
        // Price changes to existing coins don't need reprocessing — only membership changes do.
        var newHasher = Hasher()
        for c in watchlistCoins {
            newHasher.combine(c.id)
        }
        let newHash = newHasher.finalize()
        if newHash == lastWatchlistContentHash && watchlistCoins.count == oldValue.count {
            return  // Same coin membership, skip heavy processing
        }
        lastWatchlistContentHash = newHash
        
        isSanitizingWatchlist = true

        // Enforce favorites-only membership and stable order
        let favs = favoriteIDs
        if favs.isEmpty {
            isSanitizingWatchlist = false
            if !watchlistCoins.isEmpty {
                let makeEmpty: [MarketCoin] = []
                self.publishOnNextRunLoop {
                    if !self.watchlistCoins.isEmpty { self.publishWatchlistCoinsCoalesced(makeEmpty) }
                }
            }
            return
        }

        // Capture values for background processing
        let order = favoriteOrder
        let currentWatchlist = watchlistCoins
        let currentCoins = self.coins
        let oldValueCopy = oldValue
        
        // PERFORMANCE FIX: Move heavy computation to background queue
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            let indexMap: [String: Int] = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })

            // Filter to favorites and deduplicate by id preserving first occurrence
            var seen = Set<String>()
            var filtered: [MarketCoin] = []
            for c in currentWatchlist where favs.contains(c.id) {
                if !seen.contains(c.id) { filtered.append(c); seen.insert(c.id) }
            }

            // Previous snapshot and live maps (handle duplicate IDs gracefully)
            let prevMap: [String: MarketCoin] = Dictionary(oldValueCopy.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let liveMap: [String: MarketCoin] = Dictionary(currentCoins.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

            // Rebuild with a provider-first policy; no hysteresis for watchlist.
            let filteredSnapshot = filtered
            let rebuilt: [MarketCoin] = await MainActor.run {
                filteredSnapshot.map { c in
                    self.rebuildWatchlistCoin(c, prevMap: prevMap, liveMap: liveMap)
                }
            }

            // Order by favorites order
            var ordered = rebuilt
            ordered.sort { (indexMap[$0.id] ?? Int.max) < (indexMap[$1.id] ?? Int.max) }

            // Prepare display-ready sparklines
            let orderedSnapshot = ordered
            let newOrderedDisplay = await MainActor.run {
                orderedSnapshot.map { self.withDisplayReadySparkline($0) }
            }

            // Update UI on main thread
            await MainActor.run {
                self.isSanitizingWatchlist = false
                
                // Only assign back if membership or values changed to avoid churn
                let membershipChanged = newOrderedDisplay.count != oldValueCopy.count
                let valueChanged = zip(newOrderedDisplay, oldValueCopy).contains { self.coinsVisuallyDiffer($0, $1) }
                if membershipChanged || valueChanged {
                    let newOrdered = newOrderedDisplay
                    self.publishOnNextRunLoop {
                        let membershipChanged2 = newOrdered.count != self.watchlistCoins.count
                        let valueChanged2 = zip(newOrdered, self.watchlistCoins).contains { self.coinsVisuallyDiffer($0, $1) }
                        if membershipChanged2 || valueChanged2 {
                            self.publishWatchlistCoinsCoalesced(newOrdered)
                        }
                    }
                }

                // PERFORMANCE FIX: Only kickstart/prime if there are meaningful changes and not too frequently
                // Debounce by checking elapsed time since last operation
                self.publishOnNextRunLoop {
                    // Keep the main Market list fresh without thrashing: only schedule when top-20 membership changes
                    let top20 = Set(self.coins.prefix(20).map { $0.id })
                    var hasher = Hasher()
                    for id in top20.sorted() { hasher.combine(id) }
                    let newTopHash = hasher.finalize()
                    if newTopHash != self.lastTopSetHash {
                        self.lastTopSetHash = newTopHash
                        self.scheduleApplyFilters(delay: 0.5)  // Increased from 0.2 to reduce frequency
                    }
                    // PERFORMANCE FIX: Only kickstart if we have missing prices
                    let hasMissingPrices = self.watchlistCoins.contains { ($0.priceUsd ?? 0) <= 0 }
                    if hasMissingPrices {
                        self.kickstartWatchlistPricesIfNeeded()
                    }
                    self.primeLivePercents(for: self.watchlistCoins)
                }
            }
        }
    }
    
    /// REFACTOR: Helper method to rebuild a single watchlist coin with resolved data.
    /// Extracted from updateWatchlistCoins for clarity.
    private func rebuildWatchlistCoin(_ c: MarketCoin, prevMap: [String: MarketCoin], liveMap: [String: MarketCoin]) -> MarketCoin {
        let live = liveMap[c.id]

        // Price: prefer live, then current, then previous, then best by symbol
        let resolvedPrice: Double? = {
            func validPositive(_ x: Double?) -> Double? { if let v = x, v.isFinite, v > 0 { return v } else { return nil } }
            return validPositive(live?.priceUsd)
                ?? validPositive(c.priceUsd)
                ?? validPositive(prevMap[c.id]?.priceUsd)
                ?? self.bestPrice(forSymbol: c.symbol)
        }()

        // Sparkline: prefer best available (live -> allCoins -> lastGood -> current), synthesize if unusable
        var baseSeries = self.bestSparkline(for: c.id, current: c.sparklineIn7d).filter { $0.isFinite && $0 > 0 }
        if !self.isSparklineUsableForCoin(c, baseSeries) {
            baseSeries = self.synthesizeSparkline(for: c)
        }

        // Percents: unified via LivePriceManager (single source of truth)
        let sourceForPercents = live ?? c
        let oneHour = LivePriceManager.shared.bestChange1hPercent(for: sourceForPercents)
        let day = LivePriceManager.shared.bestChange24hPercent(for: sourceForPercents)
        let weekly = LivePriceManager.shared.bestChange7dPercent(for: sourceForPercents)
            ?? self.snapshot7d(for: c.id)

        // Resolve image URL (prefer API value; otherwise fallback by symbol)
        let resolvedImageURL: URL? = {
            if let img = c.imageUrl { return img }
            let key = c.symbol.lowercased()
            return MarketViewModel.fallbackImageURLs[key]
        }()

        // Market cap and volume: prefer current/live, then previous
        let resolvedCap: Double? = {
            if let cap = c.marketCap, cap.isFinite, cap > 0 { return cap }
            if let cap = prevMap[c.id]?.marketCap, cap.isFinite, cap > 0 { return cap }
            if let p = resolvedPrice, p > 0 {
                if let circ = c.circulatingSupply, circ.isFinite, circ > 0 { return p * circ }
                if let total = c.totalSupply, total.isFinite, total > 0 { return p * total }
                if let maxS = c.maxSupply, maxS.isFinite, maxS > 0 { return p * maxS }
            }
            return nil
        }()

        let currentVol = c.totalVolume ?? c.volumeUsd24Hr
        let priorVol = prevMap[c.id]?.totalVolume ?? prevMap[c.id]?.volumeUsd24Hr
        let resolvedVol: Double? = {
            func validPositive(_ x: Double?) -> Double? { if let v = x, v.isFinite, v > 0 { return v } else { return nil } }
            return validPositive(currentVol) ?? validPositive(priorVol)
        }()

        return MarketCoin(
            id: c.id,
            symbol: c.symbol,
            name: c.name,
            imageUrl: resolvedImageURL,
            priceUsd: resolvedPrice,
            marketCap: resolvedCap,
            totalVolume: resolvedVol,
            priceChangePercentage1hInCurrency: oneHour,
            priceChangePercentage24hInCurrency: day,
            priceChangePercentage7dInCurrency: weekly,
            sparklineIn7d: baseSeries,
            marketCapRank: c.marketCapRank,
            maxSupply: c.maxSupply,
            circulatingSupply: c.circulatingSupply,
            totalSupply: c.totalSupply
        )
    }
    @Published var showSearchBar: Bool = false
    
    // SEARCH PERFORMANCE: Debounce work item for search
    private var searchDebounceWork: DispatchWorkItem?
    private var lastSearchQuery: String = ""
    
    @Published var searchText: String = "" {
        didSet {
            // SEARCH PERFORMANCE FIX: Debounce rapid typing with 100ms delay
            // Cancel any pending search work
            searchDebounceWork?.cancel()
            
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            
            // If search is empty, immediately restore normal view
            if query.isEmpty {
                lastSearchQuery = ""
                applyAllFiltersAndSort()
                return
            }
            
            // Skip if same query (user might have typed and deleted)
            guard query != lastSearchQuery else { return }
            
            // Debounce: wait 100ms before searching to batch rapid keystrokes
            let work = DispatchWorkItem { [weak self] in
                self?.lastSearchQuery = query
                self?.performSearchFiltering()
            }
            searchDebounceWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
        }
    }
    
    /// Direct search filtering that bypasses complex coalescing logic
    /// Called whenever searchText changes for immediate response
    /// PERFORMANCE: Optimized to avoid expensive sparkline processing during search
    func performSearchFiltering() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // If search is empty, apply normal filters to show all coins
        guard !query.isEmpty else {
            applyAllFiltersAndSort()
            return
        }
        
        // SEARCH PERFORMANCE: Use in-memory coins only - avoid disk I/O during typing
        // The coins should already be loaded from cache at app launch
        let allSearchable: [MarketCoin] = {
            if !allCoins.isEmpty { return allCoins }
            if !lastGoodAllCoins.isEmpty { return lastGoodAllCoins }
            // Last resort fallback only if nothing in memory
            return coins
        }()
        
        guard !allSearchable.isEmpty else {
            // No coins to search - apply normal filters as fallback
            applyAllFiltersAndSort()
            return
        }
        
        // SEARCH PERFORMANCE: Pre-compute lowercased values for faster comparison
        // Filter directly without creating intermediate arrays
        var searchResults: [MarketCoin] = []
        searchResults.reserveCapacity(min(50, allSearchable.count / 10)) // Estimate ~10% match
        
        for coin in allSearchable {
            let symLower = coin.symbol.lowercased()
            let nameLower = coin.name.lowercased()
            let idLower = coin.id.lowercased()
            
            if symLower.contains(query) || nameLower.contains(query) || idLower.contains(query) {
                searchResults.append(coin)
            }
            
            // SEARCH PERFORMANCE: Limit to first 100 matches to avoid processing too many
            if searchResults.count >= 100 { break }
        }
        
        // Sort results by relevance: exact symbol match first, then by market cap
        // SEARCH PERFORMANCE: Pre-compute lowercase once per comparison
        let sorted = searchResults.sorted { a, b in
            let aSymLower = a.symbol.lowercased()
            let bSymLower = b.symbol.lowercased()
            
            // Exact symbol match gets highest priority
            let aExact = aSymLower == query
            let bExact = bSymLower == query
            if aExact != bExact { return aExact }
            
            // Symbol starts with query gets second priority
            let aStarts = aSymLower.hasPrefix(query)
            let bStarts = bSymLower.hasPrefix(query)
            if aStarts != bStarts { return aStarts }
            
            // Name starts with query gets third priority
            let aNameStarts = a.name.lowercased().hasPrefix(query)
            let bNameStarts = b.name.lowercased().hasPrefix(query)
            if aNameStarts != bNameStarts { return aNameStarts }
            
            // Then sort by market cap
            let aCap = a.marketCap ?? (a.totalVolume ?? 0) * 10
            let bCap = b.marketCap ?? (b.totalVolume ?? 0) * 10
            return aCap > bCap
        }
        
        // SEARCH PERFORMANCE: Skip expensive withDisplayReadySparkline() during search
        // The sparklines are already in the coins; CoinRowView will handle display optimization
        // Only process first 50 results for display
        let limitedResults = Array(sorted.prefix(50))
        filteredCoins = limitedResults
        
        // If no local results and query looks like a valid symbol (2-10 chars),
        // try to fetch from Coinbase API as fallback (debounced by search debounce already)
        if sorted.isEmpty && query.count >= 2 && query.count <= 10 {
            Task { @MainActor [weak self] in
                await self?.searchCoinbaseForMissingCoin(query: query)
            }
        }
    }
    
    /// Attempts to fetch a coin from Coinbase when not found in local data.
    /// This helps users find coins that exist on Coinbase but aren't in CoinGecko's top 2000.
    @MainActor
    private func searchCoinbaseForMissingCoin(query: String) async {
        let symbol = query.uppercased()
        
        // Check if we already have this coin or are searching for something else now
        guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == query.lowercased() else {
            return // Search text changed, skip
        }
        
        // Try to get Coinbase data for this symbol
        guard let coinPrice = await CoinbaseService.shared.fetch24hStats(coin: symbol, fiat: "USD", allowUnlistedPairs: true) else {
            return // Coin not found on Coinbase either
        }
        
        // Double-check search text hasn't changed
        guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == query.lowercased() else {
            return
        }
        
        // Create a temporary MarketCoin from Coinbase data
        let tempCoin = MarketCoin(
            id: symbol.lowercased(),
            symbol: symbol,
            name: symbol, // Use symbol as name since Coinbase doesn't provide full name
            imageUrl: nil,
            priceUsd: coinPrice.lastPrice,
            marketCap: nil,
            totalVolume: coinPrice.volume,
            priceChangePercentage1hInCurrency: nil,
            priceChangePercentage24hInCurrency: coinPrice.change24h,
            priceChangePercentage7dInCurrency: nil,
            sparklineIn7d: [],
            marketCapRank: nil,
            maxSupply: nil,
            circulatingSupply: nil,
            totalSupply: nil
        )
        
        // Only update if search text is still the same
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == query.lowercased() {
            let mapped = withDisplayReadySparkline(tempCoin)
            // Append to current results (in case user is still typing)
            if !filteredCoins.contains(where: { $0.symbol.uppercased() == symbol }) {
                filteredCoins.append(mapped)
                #if DEBUG
                print("✅ [MarketViewModel] Found \(symbol) on Coinbase API (not in local data)")
                #endif
            }
        }
    }
    
    @Published var selectedSegment: MarketSegment = .all {
        didSet {
            // Defer to avoid "Modifying state during view update"
            Task { @MainActor [weak self] in
                self?.scheduleApplyFilters(delay: 0.0)
            }
        }
    }
    @Published var selectedCategory: MarketCategory = .all {
        didSet {
            // Defer to avoid "Modifying state during view update"
            Task { @MainActor [weak self] in
                self?.scheduleApplyFilters(delay: 0.0)
            }
        }
    }
    
    /// Cached segment counts - updated when allCoins changes
    @Published private(set) var segmentCounts: [MarketSegment: Int] = [:]
    
    /// Recomputes segment counts from allCoins - called after data loads
    private func updateSegmentCounts() {
        let newCoinsService = NewlyListedCoinsService.shared
        let currentFavoriteIDs = favoriteIDs
        let currentAllCoins = allCoins
        
        // Major stablecoins to count (others are filtered from display)
        let majorStablecoins: Set<String> = ["USDT", "USDC", "DAI", "BUSD", "FDUSD"]
        
        // Helper to check if coin will be displayed in All segment
        func isDisplayableCoin(_ coin: MarketCoin) -> Bool {
            let sym = coin.symbol.uppercased()
            // Skip wrapped coins
            if MarketCoin.isWrappedCoin(id: coin.id) || MarketCoin.isWrappedSymbol(sym) {
                // Exception: Keep WBTC in top 100
                if sym == "WBTC" && (coin.marketCapRank ?? 999) <= 100 { return true }
                return false
            }
            // Skip non-major stablecoins
            if coin.isStable && !majorStablecoins.contains(sym) {
                return false
            }
            return true
        }
        
        var counts: [MarketSegment: Int] = [:]
        
        // All: count of coins that will actually be displayed (after filtering)
        counts[.all] = currentAllCoins.filter { isDisplayableCoin($0) }.count
        
        // Trending: coins with significant movement (non-stablecoin)
        // Note: The actual Trending segment displays top 50, but badge shows total eligible
        counts[.trending] = currentAllCoins.filter { coin in
            !coin.isStable &&
            !MarketCoin.isWrappedSymbol(coin.symbol.uppercased()) &&
            (coin.totalVolume ?? 0) > 10_000
        }.count
        
        // Calculate adaptive thresholds based on market conditions
        let thresholds = calculateAdaptiveThresholds()
        
        // Gainers: coins above adaptive threshold (top performers relative to market)
        counts[.gainers] = currentAllCoins.filter { coin in
            !coin.isStable &&
            !MarketCoin.isWrappedSymbol(coin.symbol.uppercased()) &&
            (coin.best24hPercent ?? 0) > thresholds.gainers
        }.count
        
        // Losers: coins below adaptive threshold (underperformers relative to market)
        counts[.losers] = currentAllCoins.filter { coin in
            !coin.isStable &&
            !MarketCoin.isWrappedSymbol(coin.symbol.uppercased()) &&
            (coin.best24hPercent ?? 0) < thresholds.losers
        }.count
        
        // Favorites: user's favorited coins
        counts[.favorites] = currentFavoriteIDs.count
        
        // New: coins first seen within 14 days with volume
        counts[.new] = currentAllCoins.filter { coin in
            !coin.isStable &&
            (coin.totalVolume ?? 0) > 100_000 &&
            newCoinsService.isNewCoin(coin.id)
        }.count
        
        // MEMORY FIX v8: Only update @Published segmentCounts if the values actually changed.
        // Previously this ALWAYS set segmentCounts, triggering objectWillChange on MarketViewModel.
        // Since updateSegmentCounts is called via publishOnNextRunLoop on EVERY allCoins change,
        // this fired objectWillChange ~10+ times/second during startup. Each objectWillChange
        // triggers a full view tree re-render for ALL observing views (HomeView, MarketView, etc.).
        // Each re-render allocates MB of view descriptions that SwiftUI diffs and releases, but
        // when re-renders fire faster than releases, memory accumulates (~63 MB/second).
        if counts != self.segmentCounts {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if counts != self.segmentCounts {
                    self.segmentCounts = counts
                }
            }
        }
    }
    
    @Published var sortField: SortField = .marketCap {
        didSet {
            // Defer to avoid "Modifying state during view update"
            Task { @MainActor [weak self] in
                self?.scheduleApplyFilters(delay: 0.0)
            }
        }
    }
    @Published var sortDirection: SortDirection = .desc {
        didSet {
            // Defer to avoid "Modifying state during view update"
            Task { @MainActor [weak self] in
                self?.scheduleApplyFilters(delay: 0.0)
            }
        }
    }
    @Published var filteredCoins: [MarketCoin] = []
    /// Live-updated list of MarketCoin from LivePriceManager
    @Published var coins: [MarketCoin] = []
    // Diagnostics: internal timestamps for debugging (NOT @Published to avoid triggering UI re-renders)
    // PERFORMANCE FIX: Removed @Published - these diagnostic values were causing unnecessary view updates
    private(set) var liveBeatTick: Int = 0
    private(set) var lastLiveTickAt: Date? = nil
    private(set) var lastEngineRecomputeAt: Date? = nil

    // MARK: - Derived Published Slices
    // Normal-runtime cap: keep a complete top-of-market universe for stable UX.
    static let maxAllCoinsCount = 250
    
    /// Saves coins to cache, capped at maxAllCoinsCount to prevent cache bloat on re-launch.
    private func saveCoinsCacheCapped(_ coins: [MarketCoin]) {
        let capped = coins.count > Self.maxAllCoinsCount ? Array(coins.prefix(Self.maxAllCoinsCount)) : coins
        CacheManager.shared.save(capped, to: "coins_cache.json")
    }
    
    /// Ensures any incoming list is capped before heavy transforms/assignments.
    /// This avoids transient 250-coin arrays from entering normalize/merge pipelines.
    private func capToMaxCoins(_ coins: [MarketCoin]) -> [MarketCoin] {
        coins.count > Self.maxAllCoinsCount ? Array(coins.prefix(Self.maxAllCoinsCount)) : coins
    }
    
    /// MEMORY FIX v8: Track the last allCoins ID set to skip redundant didSet processing.
    /// When allCoins is set to the same coin list (same IDs in same order), the didSet
    /// was still creating 2 GCD blocks (publishOnNextRunLoop) which triggered objectWillChange
    /// on watchlistCoins and segmentCounts — each causing a full view tree re-render.
    private var lastAllCoinsIDHash: Int = 0
    /// Startup coalescing for repeated normalizeCoins calls on identical inputs.
    private var lastNormalizeSignature: Int = 0
    private var lastNormalizeAt: Date = .distantPast
    private var lastNormalizeResult: [MarketCoin] = []
    /// Cache local watchlist merge output when source memberships are unchanged.
    private var lastLocalWatchlistSignature: Int = 0
    private var lastLocalWatchlistResult: [MarketCoin] = []
    
    // MEMORY FIX v13: Global emergency flag. When true, views should return minimal/empty
    // bodies and all data processing should halt. Set by the watchdog emergency stop.
    // This breaks the SwiftUI re-render feedback loop that causes 38 MB/s growth even
    // after the data pipeline is killed.
    @Published private(set) var isMemoryEmergency: Bool = false
    
    @Published private(set) var allCoins: [MarketCoin] = [] {
        didSet {
            // MEMORY FIX v13: When emergency trim clears allCoins to [], skip ALL cascade work.
            // Previously, setting allCoins=[] still triggered objectWillChange → SwiftUI
            // re-evaluated all observing views → allocated temporary view state → memory grew.
            // The repeated critical cleanup (every 10s) kept re-triggering this cascade.
            if allCoins.isEmpty {
                lastAllCoinsIDHash = 0
                return  // No cascade, no objectWillChange from downstream @Published
            }
            
            // MEMORY FIX v13: Skip all didSet work during memory emergency.
            // Even non-empty updates during emergency trigger SwiftUI cascades.
            if isMemoryEmergency { return }
            
            // MEMORY FIX: Cap array size to prevent unbounded growth.
            // NOTE: We defer the truncation to the next run-loop to avoid recursive didSet,
            // which could cause a stack overflow if the cap is repeatedly exceeded.
            if allCoins.count > Self.maxAllCoinsCount {
                let capped = Array(allCoins.prefix(Self.maxAllCoinsCount))
                DispatchQueue.main.async { [weak self] in
                    self?.allCoins = capped
                }
                return
            }
            
            // MEMORY FIX v8: Skip expensive cascade if allCoins membership hasn't changed.
            // Compute a lightweight hash of IDs only (not prices, which change constantly).
            // This prevents the publishOnNextRunLoop → objectWillChange → re-render cascade
            // from firing on every allCoins assignment when the coin list is the same.
            var hasher = Hasher()
            for c in allCoins { hasher.combine(c.id) }
            let idHash = hasher.finalize()
            guard idHash != lastAllCoinsIDHash || allCoins.count != oldValue.count else { return }
            lastAllCoinsIDHash = idHash
            
            // MEMORY FIX v12: Coalesce @Published updates into a single deferred block.
            // Previously this fired TWO separate publishOnNextRunLoop calls — each triggers
            // objectWillChange → SwiftUI view tree rebuild. Batching them into one block
            // halves the number of objectWillChange notifications per allCoins update.
            let needsWatchlistSync = !useLiveForWatchlist && !favoriteIDs.isEmpty
            let localWL = needsWatchlistSync ? self.localWatchlistCoins() : []
            self.publishOnNextRunLoop { [weak self] in
                guard let self else { return }
                if needsWatchlistSync {
                    self.publishWatchlistCoinsCoalesced(localWL)
                }
                self.updateSegmentCounts()
            }
        }
    }
    // MEMORY FIX v4: Changed from @Published to plain var.
    // lastGoodAllCoins was a FULL DUPLICATE of allCoins (75+ MarketCoins with sparklines),
    // kept in sync on every allCoins assignment via @Published, causing SwiftUI observation
    // overhead and doubling the coin array memory. Now it's a plain internal var that's only
    // populated as a fallback when allCoins is being replaced, not on every assignment.
    private(set) var lastGoodAllCoins: [MarketCoin] = []
    
    // MARK: - Computed Top Lists (derived from allCoins)
    // These compute on-demand to always reflect current data
    
    /// Top 10 trending coins by score (|24h change| * log10(volume))
    var trendingCoins: [MarketCoin] {
        allCoins
            .filter { !$0.isStable && !MarketCoin.isWrappedSymbol($0.symbol.uppercased()) }
            .compactMap { coin -> (MarketCoin, Double)? in
                let change = abs(coin.best24hPercent ?? 0)
                let vol = coin.totalVolume ?? 10_000
                guard vol > 0 else { return nil }
                let score = change * log10(max(vol, 10_000))
                return (coin, score)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(10)
            .map { $0.0 }
    }
    
    // MARK: - Adaptive Thresholds for Gainers/Losers
    
    /// Calculates the market median 24h change across all tradeable coins.
    /// Used for adaptive Gainers/Losers thresholds.
    private func calculateMarketMedian() -> Double {
        let tradeableCoins = allCoins.filter { coin in
            !coin.isStable && !MarketCoin.isWrappedSymbol(coin.symbol.uppercased())
        }
        guard !tradeableCoins.isEmpty else { return 0 }
        
        let changes = tradeableCoins.compactMap { $0.best24hPercent }.sorted()
        guard !changes.isEmpty else { return 0 }
        
        let midIndex = changes.count / 2
        if changes.count % 2 == 0 {
            return (changes[midIndex - 1] + changes[midIndex]) / 2
        } else {
            return changes[midIndex]
        }
    }
    
    /// Calculates the 25th and 75th percentile for adaptive thresholds.
    private func calculateMarketPercentiles() -> (p25: Double, median: Double, p75: Double) {
        let tradeableCoins = allCoins.filter { coin in
            !coin.isStable && !MarketCoin.isWrappedSymbol(coin.symbol.uppercased())
        }
        guard !tradeableCoins.isEmpty else { return (0, 0, 0) }
        
        let changes = tradeableCoins.compactMap { $0.best24hPercent }.sorted()
        guard !changes.isEmpty else { return (0, 0, 0) }
        
        let p25Index = changes.count / 4
        let medianIndex = changes.count / 2
        let p75Index = (changes.count * 3) / 4
        
        let p25 = changes[min(p25Index, changes.count - 1)]
        let median = changes[min(medianIndex, changes.count - 1)]
        let p75 = changes[min(p75Index, changes.count - 1)]
        
        return (p25, median, p75)
    }
    
    /// Determines adaptive thresholds based on market conditions.
    /// Returns (gainersThreshold, losersThreshold)
    ///
    /// Logic:
    /// - In strong bull markets (median > 2%): Losers = below median, Gainers = above median
    /// - In strong bear markets (median < -2%): Gainers = above median, Losers = below median
    /// - In flat markets: Traditional 0% threshold (positive = gainer, negative = loser)
    private func calculateAdaptiveThresholds() -> (gainers: Double, losers: Double) {
        let percentiles = calculateMarketPercentiles()
        let median = percentiles.median
        
        // Strong bull market: median > 2%
        // Show relatively underperforming coins (even if slightly positive) in Losers
        if median > 2.0 {
            // Gainers: above median (top performers)
            // Losers: below median (relative underperformers)
            return (median, median)
        }
        
        // Strong bear market: median < -2%
        // Show relatively outperforming coins (even if slightly negative) in Gainers
        if median < -2.0 {
            // Gainers: above median (least bad performers)
            // Losers: below median (worst performers)
            return (median, median)
        }
        
        // Flat/normal market: use traditional positive/negative split
        // But with small buffer to avoid noise
        return (0.0, 0.0)
    }
    
    /// Top 10 gainers by 24h change (excludes stablecoins)
    /// Uses adaptive thresholds based on market conditions
    var topGainers: [MarketCoin] {
        let thresholds = calculateAdaptiveThresholds()
        return allCoins
            .filter { coin in
                !coin.isStable && !MarketCoin.isWrappedSymbol(coin.symbol.uppercased()) &&
                (coin.best24hPercent ?? 0) > thresholds.gainers
            }
            .sorted { ($0.best24hPercent ?? 0) > ($1.best24hPercent ?? 0) }
            .prefix(10)
            .map { $0 }
    }
    
    /// Top 10 losers by 24h change (excludes stablecoins)
    /// Uses adaptive thresholds based on market conditions
    var topLosers: [MarketCoin] {
        let thresholds = calculateAdaptiveThresholds()
        return allCoins
            .filter { coin in
                !coin.isStable && !MarketCoin.isWrappedSymbol(coin.symbol.uppercased()) &&
                (coin.best24hPercent ?? 0) < thresholds.losers
            }
            .sorted { ($0.best24hPercent ?? 0) < ($1.best24hPercent ?? 0) }
            .prefix(10)
            .map { $0 }
    }

    @Published private(set) var globalMarketCap: Double? = nil
    @Published private(set) var globalVolume24h: Double? = nil
    @Published private(set) var btcDominance: Double? = nil
    @Published private(set) var ethDominance: Double? = nil
    @Published private(set) var globalChange24hPercent: Double? = nil
    @Published private(set) var globalVolatility24h: Double? = nil

    private var cancellables = Set<AnyCancellable>()
    private var livePriceCancellable: AnyCancellable?
    private let minLiveListForUI = 40
    private var effectiveMinLiveListForUI: Int { Date() < self.bootstrapUntil ? 5 : self.minLiveListForUI }

    // Rate limiting for percent priming
    private var lastPrimeAt: Date = .distantPast
    private var lastPrimeKey: Int = 0
    private let minPrimeSpacing: TimeInterval = 0.5
    private var isPrimingPercents: Bool = false
    private var primeRetryCount: Int = 0
    private let maxPrimeRetries: Int = 5 // MEMORY FIX: Limit retry chain to prevent unbounded Task creation

    // MARK: - Cleanup
    deinit {
        // Cancel all Combine subscriptions
        cancellables.removeAll()
        livePriceCancellable?.cancel()
        livePriceCancellable = nil
        
        // Cancel pending work items
        pendingFilterWork?.cancel()
        pendingGeckoFetchWork?.cancel()
        pendingFilteredPublish?.cancel()
        pendingWatchlistPublish?.cancel()
    }

    // MARK: - Initialization (minimal)
    init() {
        #if DEBUG
        self.enableDiagLogs = true
        self.enableStatsLogging = true
        #endif
        
        // SPARKLINE INVERSION FIX: Clear ALL sparkline display and orientation caches at startup.
        // All orientation/reversal logic has been removed - API data is always chronological.
        // This ensures no stale reversed data persists from previous sessions.
        MarketMetricsEngine.resetOrientationCache()
        self.displaySeriesCache.removeAll()
        self.displaySeriesCacheKey.removeAll()
        self.displaySeriesCacheAt.removeAll()
        self.orientationCache.removeAll()
        self.orientationCacheAt.removeAll()
        self.orientationSeriesFP.removeAll()
        clearAllMetricsCaches()

        // Bootstrap windows to be more aggressive for the first couple of minutes after cold start
        self.bootstrapUntil = Date().addingTimeInterval(60)
        self.firstGeckoWindowUntil = Date().addingTimeInterval(90)
        // Defer heavy network tasks by ~0.2s so the first frame can render smoothly
        self.firstFrameQuietUntil = Date().addingTimeInterval(0.2)
        
        // MEMORY FIX: Removed synchronous cache loading from init().
        // Previously, loadFromDocumentsOnly() blocked the main thread during app init,
        // reading and decoding a large JSON file (250+ coins) synchronously.
        // Combined with Firebase init, all ViewModel inits, and the oversized launch logo,
        // this caused the app to exceed iOS memory limits and get killed.
        //
        // Cache is now loaded asynchronously in loadFromCacheOnly() which is called
        // from startHeavyLoading() AFTER the splash screen is visible.
        // This reduces peak memory during init by ~30-50MB.
        self.state = .loading
        self.isInitialized = false
        
        // Subscribe to the app-wide live price stream so Market lists and watchlist stay in sync with Heat Map
        // Note: startPolling() is called by CryptoSageAIApp.startHeavyLoading() during app startup
        // PERFORMANCE FIX: Use throttledPublisher (500ms) instead of raw publisher with debounce
        // This reduces UI update frequency and prevents jank during rapid price changes
        livePriceCancellable = LivePriceManager.shared.throttledPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] liveCoins in
                guard let self = self else { return }

                // MEMORY FIX v5.0.12: Skip empty emissions entirely. On simulator safe mode
                // LivePriceManager never starts polling, but stray Firestore/init emissions
                // can still fire the sink. Processing empty data triggers @Published cascades
                // and view re-renders that allocate ~15 MB/3s for no benefit.
                if liveCoins.isEmpty { return }
                
                // MEMORY FIX v13: Block ALL data processing during memory emergency.
                // After emergency stop, in-flight HTTP responses (Binance, CoinGecko Cloud
                // Functions) can still deliver data through the Combine pipeline. Processing
                // it would set @Published properties, trigger objectWillChange → SwiftUI
                // re-renders → continuous memory growth.
                if self.isMemoryEmergency { return }
                
                // Memory gate: only block data when available memory is known AND critically low.
                // Threshold 300 MB — well below jetsam but allows normal operation on most devices.
                // When os_proc_available_memory() returns 0 (simulator/unknown), always proceed.
                let _avail = Double(os_proc_available_memory()) / (1024 * 1024)
                if _avail > 0 && _avail < 300 {
                    self.lastLiveTickAt = Date()
                    return
                }
                
                // PERFORMANCE FIX v11: Skip ALL processing during fast scroll
                // This prevents main thread blocking and "System gesture gate timed out"
                if ScrollStateManager.shared.isFastScrolling {
                    return  // Completely skip - don't even track timestamp
                }
                
                // PERFORMANCE FIX v9: Skip @Published updates during scroll to prevent view re-renders
                // The data is still available via LivePriceManager, views just won't re-render
                if ScrollStateManager.shared.shouldBlockHeavyOperation() {
                    // Update internal state without triggering @Published
                    self.lastLiveTickAt = Date()
                    return
                }
                
                // Defer state modifications to avoid "Modifying state during view update"
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    // PERFORMANCE FIX v11: Double-check scroll state after async dispatch
                    if ScrollStateManager.shared.isFastScrolling { return }
                    if ScrollStateManager.shared.shouldBlockHeavyOperation() { return }
                    
                    // MEMORY FIX v11: Skip sink processing during startup freeze.
                    // The first emission already populated allCoins. Further emissions
                    // trigger cascading @Published updates → view re-renders → memory explosion.
                    if self.hasCompletedInitialFilterPass,
                       let freezeEnd = self.startupFilterFreezeUntil,
                       Date() < freezeEnd {
                        return  // Data is frozen — skip processing
                    }
                    
                    // Re-check memory after async dispatch — only block when critically low
                    let _avail2 = Double(os_proc_available_memory()) / (1024 * 1024)
                    if _avail2 > 0 && _avail2 < 250 { return }
                    
                    // Avoid collapsing the Market list to a tiny live set while network warms up
                    let isColdStart = self.allCoins.isEmpty && self.lastGoodAllCoins.isEmpty
                    if liveCoins.count >= self.effectiveMinLiveListForUI {
                        // MEMORY FIX v8: Only set @Published coins if data meaningfully changed.
                        // The throttled publisher fires every 500ms. Without this guard, each
                        // emission triggers objectWillChange → full view tree re-render, even
                        // when coin data hasn't changed. Each re-render allocates MB of view
                        // descriptions, causing ~63 MB/s memory growth.
                        let coinsChanged = liveCoins.count != self.coins.count ||
                            zip(liveCoins.prefix(10), self.coins.prefix(10)).contains {
                                $0.id != $1.id || $0.priceUsd != $1.priceUsd
                            }
                        if coinsChanged {
                            self.coins = liveCoins
                        }
                    } else if isColdStart {
                        // On cold start, ignore tiny live sets and rely on snapshots/baseline instead
                        self.diag("Diag: Cold start with sparse live (\(liveCoins.count)); not adopting tiny live set")
                        // Proactively ensure a baseline snapshot
                        // MEMORY FIX v6: minCount must match maxAllCoinsCount to avoid infinite recursion
                        self.ensureBaselineSnapshotIfNeeded(minCount: Self.maxAllCoinsCount)
                    } else if !self.coins.isEmpty {
                        self.diag("Diag: Live list sparse (\(liveCoins.count)); keeping previous live set (\(self.coins.count))")
                    } else {
                        // We have snapshots, but no previous live set — accept the small live set for watchlist enrichment
                        self.coins = liveCoins
                    }
                    self.rebuildPriceBooks()
                    
                    // STALE PRICE FIX: On first live data arrival, force immediate full update
                    // This replaces stale cached prices with fresh Firestore/API prices.
                    // Without this, cached $62K BTC could linger while real price is $63K.
                    if !self.hasReceivedFirstLiveData {
                        self.hasReceivedFirstLiveData = true
                        self.hasFreshAPIData = true
                        self.isUsingCachedData = false
                        // MEMORY FIX v8: Update non-@Published state first, then set @Published
                        // properties in a single batch to minimize objectWillChange notifications.
                        // Previously this set coins, allCoins, state in rapid succession — 3 separate
                        // objectWillChange sends, each triggering full view tree re-evaluation.
                        self.lastGoodAllCoins = liveCoins
                        // Batch: only update allCoins if it actually changed (avoid duplicate objectWillChange)
                        // FIX v14: Compare 10 items (not 5) and use tolerance-based price comparison.
                        // Previously, if the top-5 IDs matched and prices were very close, the update
                        // was skipped even though other coins had stale prices.
                        let countDiffers: Bool = self.allCoins.count != liveCoins.count
                        let priceDiffers: Bool = zip(self.allCoins.prefix(10), liveCoins.prefix(10)).contains { (old: MarketCoin, new: MarketCoin) -> Bool in
                            if old.id != new.id { return true }
                            let oldPrice: Double = old.priceUsd ?? 0
                            let newPrice: Double = new.priceUsd ?? 0
                            let threshold: Double = max(oldPrice * 0.0001, 0.001)
                            return abs(oldPrice - newPrice) > threshold
                        }
                        let allChanged: Bool = countDiffers || priceDiffers
                        // BTC DATA FIX: Only replace allCoins with live data if the live set
                        // is at least as large as the existing set, or if allCoins is very small.
                        // Prevents a partial API response from wiping out a complete cached list.
                        if allChanged && (liveCoins.count >= self.allCoins.count || self.allCoins.count < 10) {
                            self.allCoins = self.capToMaxCoins(liveCoins)
                        }
                        self.state = .success(liveCoins)
                        WidgetBridge.syncWatchlist(from: self.allCoins)
                        // MEMORY FIX v7: Use deferred scheduling instead of synchronous call.
                        // Direct applyAllFiltersAndSort() here triggers heavy processing inside
                        // a Combine sink, blocking the main thread and creating cascading
                        // @Published modifications that spawn more Tasks.
                        self.scheduleApplyFilters(delay: 0.0)
                    } else {
                        // Keep the main Market list fresh without thrashing: only schedule when top-20 membership changes
                        let top20 = Set(self.coins.prefix(20).map { $0.id })
                        var hasher = Hasher()
                        for id in top20.sorted() { hasher.combine(id) }
                        let newHash = hasher.finalize()
                        if newHash != self.lastTopSetHash {
                            self.lastTopSetHash = newHash
                            self.scheduleApplyFilters(delay: 0.2)
                        }
                    }
                    
                    // PERFORMANCE FIX: If live is still sparse, load cache asynchronously
                    // MEMORY FIX: Guard with isCacheLoadInFlight to prevent multiple simultaneous
                    // cache loading tasks. Without this guard, each 500ms sink invocation spawns
                    // a new Task that loads+decodes the 1.8MB cache, causing 1.5GB+ memory usage.
                    // FIX v14: Also block cache load if we already have fresh API data.
                    // Previously, fresh Firebase proxy data at +60s was overwritten by async cache
                    // load completing afterward with stale prices from a previous session.
                    if (self.allCoins.isEmpty || self.allCoins.count < 50) && !self.isCacheLoadInFlight && !self.hasFreshAPIData {
                        self.isCacheLoadInFlight = true
                        Task { @MainActor [weak self] in
                            guard let self = self else { return }
                            defer { self.isCacheLoadInFlight = false }
                            // STALE DATA FIX: Use loadFromDocumentsOnlyAsync to avoid loading
                            // bundled fallback data with stale percentages and sparklines.
                            // Documents cache contains REAL data from a previous API call.
                            if let saved: [MarketCoin] = await CacheManager.shared.loadFromDocumentsOnlyAsync([MarketCoin].self, from: "coins_cache.json"),
                               saved.count >= self.minUsableSnapshotCount {
                                // MEMORY FIX v5: Cap before normalization
                                let capped = saved.count > Self.maxAllCoinsCount ? Array(saved.prefix(Self.maxAllCoinsCount)) : saved
                                let normalized = self.normalizeCoins(capped)
                                self.allCoins = normalized
                                self.lastGoodAllCoins = normalized
                                self.state = .success(normalized)
                                self.rebuildPriceBooks()
                                // MEMORY FIX v7: Deferred scheduling
                                self.scheduleApplyFilters(delay: 0.0)
                                self.computeGlobalStatsAsync(base: normalized)
                                self.diag("Diag: Adopted cached coins snapshot while live warms up (count=\(normalized.count))")
                            }
                        }
                    }
                    
                    // If after all fallbacks the list is still small, proactively fetch a baseline snapshot
                    // MEMORY FIX v6: minCount must match maxAllCoinsCount to avoid infinite recursion
                    if self.allCoins.count < Self.maxAllCoinsCount {
                        self.ensureBaselineSnapshotIfNeeded(minCount: Self.maxAllCoinsCount)
                    }
                    
                    // Optionally refresh watchlist from live; disabled when using snapshot-only mode
                    if self.useLiveForWatchlist, !self.favoriteIDs.isEmpty {
                        let local = self.localWatchlistCoins()
                        self.publishOnNextRunLoop { self.publishWatchlistCoinsCoalesced(local) }
                    }
                    self.primeLivePercents(for: Array(self.coins.prefix(80)))
                    self.publishOnNextRunLoop { self.primeLivePercents(for: self.watchlistCoins) }
                    self.liveBeatTick &+= 1
                    self.lastLiveTickAt = Date()
                }
            }

        if AppSettings.isSimulatorLimitedDataMode {
            // Limited simulator profile: allow baseline refresh for parity, skip long-running loops.
            #if DEBUG
            print("🧪 [MarketViewModel] Simulator limited profile: baseline enabled, category/sync timers disabled")
            #endif
            self.ensureBaselineSnapshotIfNeeded(minCount: Self.maxAllCoinsCount)
        } else {
            // Proactively seed a baseline if our snapshots are still tiny at startup
            // MEMORY FIX v6: minCount must match maxAllCoinsCount to avoid infinite recursion
            self.ensureBaselineSnapshotIfNeeded(minCount: Self.maxAllCoinsCount)

            // PERFORMANCE: Removed eager loadAllData() - CryptoSageAIApp.startHeavyLoading() handles this
            // with proper staggering to prevent duplicate API calls and rate limiting.
            // The cache-based initialization above (lines 422-433) provides instant UI.
            
            // Delay category fetch past startup burst — proceed only if we are still under cap.
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 15_000_000_000) // 15 seconds
                let avail = Double(os_proc_available_memory()) / (1024 * 1024)
                if avail > 0 && avail < 200 {
                    #if DEBUG
                    print("⚠️ [MarketViewModel] Skipping category fetch — only \(String(format: "%.0f", avail)) MB available")
                    #endif
                    return
                }
                guard let self = self else { return }
                if self.allCoins.count >= Self.maxAllCoinsCount {
                    #if DEBUG
                    print("⚠️ [MarketViewModel] Skipping category fetch — already at cap (\(self.allCoins.count))")
                    #endif
                    return
                }
                await self.fetchAndMergeCategoryCoins()
            }
            
            // Delay background sync until after startup — proceed unless memory is known-critical.
            Task {
                try? await Task.sleep(nanoseconds: 20_000_000_000) // 20 seconds
                let avail = Double(os_proc_available_memory()) / (1024 * 1024)
                if avail > 0 && avail < 200 {
                    #if DEBUG
                    print("⚠️ [MarketViewModel] Skipping periodic sync start — only \(String(format: "%.0f", avail)) MB available")
                    #endif
                    return
                }
                await MainActor.run {
                    MarketDataSyncService.shared.startPeriodicSync()
                }
            }
        }
        
        // Subscribe to new coin alerts from the sync service
        MarketDataSyncService.shared.newCoinsDetectedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newCoins in
                guard let self = self else { return }
                self.diag("Diag: Detected \(newCoins.count) new coins from sync service")
                // Trigger a refresh to include new coins
                Task { @MainActor [weak self] in
                    self?.scheduleApplyFilters(delay: 0.5)
                }
            }
            .store(in: &cancellables)
        
        // Subscribe to NewlyListedCoinsService for segment counts
        NewlyListedCoinsService.shared.$newlyListedCoins
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateSegmentCounts()
            }
            .store(in: &cancellables)
        
        // WATCHLIST INSTANT-SYNC: Subscribe to FavoritesManager so that favoriteIDs
        // and watchlistCoins update automatically whenever the user adds/removes a favorite
        // from ANY screen (Market star, WatchlistSection swipe, Firestore sync, etc.).
        // Previously this relied on manual sync from CoinRowView which only covered the
        // Market page star button, causing stale watchlist on the Home tab.
        FavoritesManager.shared.$favoriteIDs
            .dropFirst()          // Skip the initial value (already set from getAllIDs())
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newIDs in
                guard let self = self else { return }
                self.favoriteIDs = newIDs
                // Use immediate publish path so the Home watchlist updates instantly
                Task { @MainActor in
                    await self.loadWatchlistDataImmediate()
                }
            }
            .store(in: &cancellables)
    }
    
    /// Fetches coins from specific CoinGecko categories and merges them into allCoins
    /// This ensures Gaming, AI, Solana, and other category filters have coins to show
    private func fetchAndMergeCategoryCoins() async {
        // Never expand beyond the core max coin cap.
        guard allCoins.count < Self.maxAllCoinsCount else { return }
        
        var mergedMap: [String: MarketCoin] = Dictionary(allCoins.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var addedCount = 0
        var skippedWrapped = 0
        
        // Track symbols already in the list to prevent duplicates (e.g., DOGE vs Binance-Peg DOGE)
        var symbolSet: Set<String> = Set(mergedMap.values.map { $0.symbol.uppercased() })
        
        // 1. Fetch category coins from CoinGecko
        let categoryCoins = capToMaxCoins(await CryptoAPIService.shared.fetchCategoryCoins())
        for coin in categoryCoins {
            let sym = coin.symbol.uppercased()
            
            // Skip wrapped/pegged coins if the canonical coin already exists
            if MarketCoin.isWrappedCoin(id: coin.id) {
                // Check if we already have the canonical symbol
                if symbolSet.contains(sym) {
                    skippedWrapped += 1
                    continue
                }
                // Also skip if this is a known duplicate and canonical exists
                if let canonicalSym = MarketCoin.canonicalSymbol(forWrappedId: coin.id),
                   symbolSet.contains(canonicalSym) {
                    skippedWrapped += 1
                    continue
                }
            }
            
            // Skip if we already have this symbol (prevents duplicates with same symbol but different IDs)
            if symbolSet.contains(sym) && mergedMap[coin.id] == nil {
                // Only add if no coin with this symbol exists
                continue
            }
            
            if mergedMap[coin.id] == nil {
                mergedMap[coin.id] = coin
                symbolSet.insert(sym)
                addedCount += 1
            }
        }
        
        // 2. Fetch Binance tickers as supplemental data source
        // Binance provides real-time data for 500+ trading pairs without rate limits
        let binanceCoins = capToMaxCoins(await CryptoAPIService.shared.fetchBinanceTickers())
        var binanceAdded = 0
        
        for coin in binanceCoins {
            let sym = coin.symbol.uppercased()
            
            // Skip wrapped coins from Binance as well
            if MarketCoin.isWrappedCoin(id: coin.id) {
                if symbolSet.contains(sym) {
                    continue
                }
            }
            
            // Only add if we don't already have this symbol
            if !symbolSet.contains(sym) {
                mergedMap[coin.id] = coin
                symbolSet.insert(sym)
                binanceAdded += 1
            }
        }
        
        let totalAdded = addedCount + binanceAdded
        guard totalAdded > 0 else { return }
        
        // Sort and update
        var merged = self.capToMaxCoins(Array(mergedMap.values))
        merged.sort { bestCap(for: $0) > bestCap(for: $1) }
        
        await MainActor.run {
            self.allCoins = merged
            self.lastGoodAllCoins = merged
            self.rebuildPriceBooks()
            // MEMORY FIX v7: Deferred scheduling to avoid synchronous cascades
            self.scheduleApplyFilters(delay: 0.0)
            self.diag("Diag: Merged \(addedCount) category + \(binanceAdded) Binance coins (skipped \(skippedWrapped) wrapped), total: \(merged.count)")
        }
    }
    
    // MARK: - Missing state (added)
    private var bootstrapUntil: Date = .distantPast
    private var firstGeckoWindowUntil: Date = .distantPast

    // Use MarketCoin.stableSymbols as canonical source for stablecoin checks
    private let pinnedMajorSymbols: Set<String> = ["BTC", "ETH", "SOL", "XRP", "BNB"]

    /// Determines if a sparkline is usable (enough points and not flat)
    private func isSparklineUsable(_ series: [Double]) -> Bool {
        let data = series.filter { $0.isFinite }
        guard data.count >= 3 else { return false }
        guard let minV = data.min(), let maxV = data.max(), minV.isFinite, maxV.isFinite else { return false }
        let span = maxV - minV
        // Require at least a tiny variation to avoid flat synthetic-looking lines
        return span / max(1.0, maxV) > 0.00005
    }

    /// Lookup a coin's symbol by id from current snapshots (uppercased)
    private func symbolForID(_ id: String) -> String? {
        if let s = self.allCoins.first(where: { $0.id == id })?.symbol { return s.uppercased() }
        if let s = self.lastGoodAllCoins.first(where: { $0.id == id })?.symbol { return s.uppercased() }
        if let s = self.coins.first(where: { $0.id == id })?.symbol { return s.uppercased() }
        return nil
    }

    /// Relaxed sparkline usability for pinned majors: accept any finite series with at least 2 positive points
    private func isUsableSeries(_ series: [Double], forID id: String) -> Bool {
        let vals = series.filter { $0.isFinite && $0 > 0 }
        if let sym = symbolForID(id), pinnedMajorSymbols.contains(sym) {
            return vals.count >= 2
        }
        return isSparklineUsable(series)
    }

    /// Coin-aware sparkline usability (relaxed for pinned majors)
    private func isSparklineUsableForCoin(_ coin: MarketCoin, _ series: [Double]) -> Bool {
        let vals = series.filter { $0.isFinite && $0 > 0 }
        if pinnedMajorSymbols.contains(coin.symbol.uppercased()) {
            return vals.count >= 2
        }
        return isSparklineUsable(series)
    }
    
    /// Removes wrapped/pegged coin variants and filters out minor stablecoins.
    /// Keeps only canonical versions of coins and major stablecoins (USDT, USDC, DAI).
    private func deduplicateCoins(_ coins: [MarketCoin]) -> [MarketCoin] {
        // Major stablecoins to keep (limit stablecoin clutter)
        let majorStablecoins: Set<String> = ["USDT", "USDC", "DAI", "BUSD", "FDUSD"]
        
        // Debug: Log first 10 coins with prices to diagnose data issues
        #if DEBUG
        if Self.verboseDedupeLogging {
            let first10 = coins.prefix(10)
            print("[deduplicateCoins] First 10 coins: \(first10.map { "\($0.symbol)=$\(String(format: "%.2f", $0.priceUsd ?? 0))" }.joined(separator: ", "))")
            
            // Count coins with suspicious ~$1 prices (possible stablecoins or data issues)
            let suspiciousPriceCoins = coins.filter { coin in
                if let p = coin.priceUsd, p >= 0.95 && p <= 1.05 { return true }
                return false
            }
            if suspiciousPriceCoins.count > 20 {
                print("[deduplicateCoins] WARNING: \(suspiciousPriceCoins.count) coins have ~$1 prices! Examples: \(suspiciousPriceCoins.prefix(5).map { $0.symbol }.joined(separator: ", "))")
            }
        }
        #endif
        
        // First pass: identify which canonical symbols exist (non-wrapped, non-stable)
        var canonicalSymbols: Set<String> = []
        for coin in coins {
            let sym = coin.symbol.uppercased()
            if !MarketCoin.isWrappedCoin(id: coin.id) && !MarketCoin.isWrappedSymbol(sym) {
                canonicalSymbols.insert(sym)
            }
        }
        
        // Second pass: filter out wrapped coins and minor stablecoins
        var result: [MarketCoin] = []
        var seenIDs: Set<String> = []
        var seenStablecoins: Set<String> = [] // Track stablecoins we've already added
        var filteredWrapped = 0
        var filteredStable = 0
        var filteredExamples: [String] = [] // Track some filtered coins for debugging
        
        for coin in coins {
            // Skip if we've already seen this exact ID (true duplicates)
            guard !seenIDs.contains(coin.id) else { continue }
            seenIDs.insert(coin.id)
            
            let sym = coin.symbol.uppercased()
            
            // Filter wrapped coins - skip if canonical exists OR if symbol is a known wrapped pattern
            if MarketCoin.isWrappedCoin(id: coin.id) || MarketCoin.isWrappedSymbol(sym) {
                // Skip wrapped coins entirely - they clutter the list
                // Exception: Keep WBTC if it's in top 100 by market cap (it's commonly traded)
                if sym == "WBTC" && (coin.marketCapRank ?? 999) <= 100 {
                    result.append(coin)
                } else {
                    filteredWrapped += 1
                    if filteredExamples.count < 10 { filteredExamples.append("\(sym)(wrapped)") }
                }
                continue
            }
            
            // Filter stablecoins - only keep major ones, and only one per symbol
            if coin.isStable {
                // Skip if not a major stablecoin
                if !majorStablecoins.contains(sym) {
                    filteredStable += 1
                    if filteredExamples.count < 10 { filteredExamples.append("\(sym)(stable)") }
                    continue
                }
                // Skip if we've already added this stablecoin symbol
                if seenStablecoins.contains(sym) {
                    continue
                }
                seenStablecoins.insert(sym)
            }
            
            result.append(coin)
        }
        
        #if DEBUG
        if Self.verboseDedupeLogging {
            print("[deduplicateCoins] Input: \(coins.count), Output: \(result.count), Filtered: \(filteredWrapped) wrapped, \(filteredStable) stablecoins")
            if !filteredExamples.isEmpty {
                print("[deduplicateCoins] Filtered examples: \(filteredExamples.joined(separator: ", "))")
            }
        }
        #endif
        
        return result
    }

    /// Linearly resamples a sparkline to at least minCount points for smoother rendering (no smoothing applied here).
    private func resampleSparkline(_ series: [Double], minCount: Int = 48) -> [Double] {
        let data = series.filter { $0.isFinite }
        guard data.count >= 2 else { return data }
        if data.count >= minCount { return data }
        let n = max(minCount, data.count)
        var out: [Double] = []
        out.reserveCapacity(n)
        let lastIdx = data.count - 1
        for i in 0..<n {
            let t = Double(i) / Double(n - 1)
            let x = t * Double(lastIdx)
            let i0 = Int(floor(x))
            let i1 = min(lastIdx, i0 + 1)
            let frac = x - Double(i0)
            let v0 = data[i0]
            let v1 = data[i1]
            out.append(v0 + (v1 - v0) * frac)
        }
        return out
    }

    /// Adds subtle, deterministic micro-variation to a nearly-flat series so it renders legibly in small spark cells.
    /// Uses a light sinusoid plus tiny noise scaled to the local value, guided by the 7D/24H trend magnitude when available.
    /// The optional flatnessFactor (0...1) boosts amplitude for very flat series.
    private func microWiggle(_ series: [Double], trendPercent: Double?, seed: String, flatnessFactor: Double? = nil) -> [Double] {
        let data = series.filter { $0.isFinite }
        let n = data.count
        guard n >= 2 else { return data }
        // Determine a tiny relative amplitude based on trend magnitude with safe clamps
        let trendMag = abs(trendPercent ?? 0) / 100.0
        var baseAmp: Double = max(0.0012, min(0.0045, trendMag * 0.010)) // 0.12% .. 0.45% of local value
        // Boost amplitude slightly for very flat series
        if let ff = flatnessFactor {
            let clamped = max(0.0, min(1.0, ff))
            let mult = 1.0 + 0.6 * clamped
            baseAmp *= mult
        }
        // Deterministic seed derived from coin id and count
        var hasher = Hasher()
        hasher.combine(seed)
        hasher.combine(n)
        let s64 = UInt64(bitPattern: Int64(hasher.finalize()))
        var rng = s64 ^ 0x9E3779B97F4A7C15
        func nextNoise() -> Double { rng = rng &* 2862933555777941757 &+ 3037000493; return (Double(rng % 1000) / 1000.0) - 0.5 }
        var out = data
        for i in 0..<n {
            let t = Double(i) / Double(max(1, n - 1))
            let sine = sin(2.0 * .pi * t * 1.6) // about 1.6 cycles across the span
            let noise = nextNoise() * 0.5
            let rel = (sine + noise) * baseAmp
            let v = data[i]
            out[i] = max(0.0000001, v * (1.0 + rel))
        }
        return out
    }

    /// Normalize coins by filling missing images with fallbacks and preserving cached sparklines when API omits them.
    /// MEMORY FIX v7: Wrapped in autoreleasepool to ensure temporary Foundation objects
    /// (from Dictionary creation, map/filter closures) are released immediately rather than
    /// accumulating until the next run loop iteration. This is critical when normalizeCoins
    /// is called multiple times in rapid succession during startup.
    private func normalizeCoins(_ coins: [MarketCoin]) -> [MarketCoin] {
        let withinStartupCoalesceWindow = Date() < self.bootstrapUntil.addingTimeInterval(60)
        var normalizeSignature = 0
        if withinStartupCoalesceWindow {
            var hasher = Hasher()
            hasher.combine(coins.count)
            for c in coins { hasher.combine(c.id) }
            normalizeSignature = hasher.finalize()
            if normalizeSignature == self.lastNormalizeSignature,
               Date().timeIntervalSince(self.lastNormalizeAt) <= 0.75,
               !self.lastNormalizeResult.isEmpty {
                return self.lastNormalizeResult
            }
        }
        
        let normalized = autoreleasepool {
            // Build a previous/cached map to borrow sparkline or image if missing (handle duplicate IDs gracefully)
            var priorMap: [String: MarketCoin] = Dictionary(self.allCoins.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            // Also merge in last known good snapshot to widen coverage (for sparklines/icons)
            for c in self.lastGoodAllCoins where priorMap[c.id] == nil { priorMap[c.id] = c }
            // MEMORY FIX: Removed synchronous cache I/O from this hot path.
            // Previously, when priorMap was empty, this method would synchronously read and decode
            // the 1.8MB coins_cache.json from disk. normalizeCoins is called 13+ times during
            // startup, and this I/O blocks the main thread.
            // Rebuild each coin to safely override let properties (imageUrl, sparkline)
            return coins.map { c in
                // Resolve image URL (prefer API value; otherwise fallback by symbol)
                let lower = c.symbol.lowercased()
                let resolvedImageURL: URL? = c.imageUrl ?? MarketViewModel.fallbackImageURLs[lower]
                // Prefer current sparkline if usable; otherwise borrow prior; otherwise synthesize
                var resolvedSpark: [Double] = c.sparklineIn7d
                if !self.isSparklineUsableForCoin(c, resolvedSpark) {
                    resolvedSpark = priorMap[c.id]?.sparklineIn7d ?? []
                }
                if !self.isSparklineUsableForCoin(c, resolvedSpark) {
                    resolvedSpark = self.synthesizeSparkline(for: c)
                }
                
                // Sanitize market cap & volume: if missing/non-finite/<=0, borrow from prior or LivePriceManager cache
                func validNumber(_ x: Double?) -> Double? { if let v = x, v.isFinite, v > 0 { return v } else { return nil } }
                let resolvedCap: Double? = validNumber(c.marketCap) ?? validNumber(priorMap[c.id]?.marketCap)
                let currentVol = c.volumeUsd24Hr ?? c.totalVolume
                let priorVol = priorMap[c.id]?.volumeUsd24Hr ?? priorMap[c.id]?.totalVolume
                // VOLUME FIX: Also check LivePriceManager's volume cache as ultimate fallback
                let lpmVol = LivePriceManager.shared.bestVolumeUSD(forSymbol: c.symbol)
                let resolvedVol: Double? = validNumber(currentVol) ?? validNumber(priorVol) ?? validNumber(lpmVol)
                
                func validPositive(_ x: Double?) -> Double? { if let v = x, v.isFinite, v > 0 { return v } else { return nil } }
                let resolvedPrice: Double? = validPositive(c.priceUsd) ?? validPositive(priorMap[c.id]?.priceUsd) ?? validPositive(self.bestPrice(forSymbol: c.symbol))
                
                // Return rebuilt struct with patched fields
                return MarketCoin(
                    id: c.id,
                    symbol: c.symbol,
                    name: c.name,
                    imageUrl: resolvedImageURL,
                    priceUsd: resolvedPrice,
                    marketCap: {
                        if let cap = resolvedCap { return cap }
                        // Approximate from price * supply when missing
                        if let p = resolvedPrice, p > 0 {
                            if let circ = c.circulatingSupply, circ.isFinite, circ > 0 { return p * circ }
                            if let total = c.totalSupply, total.isFinite, total > 0 { return p * total }
                            if let maxS = c.maxSupply, maxS.isFinite, maxS > 0 { return p * maxS }
                        }
                        return resolvedCap
                    }(),
                    totalVolume: resolvedVol,
                    priceChangePercentage1hInCurrency: c.priceChangePercentage1hInCurrency,
                    priceChangePercentage24hInCurrency: c.priceChangePercentage24hInCurrency,
                    priceChangePercentage7dInCurrency: c.priceChangePercentage7dInCurrency,
                    sparklineIn7d: resolvedSpark,
                    marketCapRank: c.marketCapRank,
                    maxSupply: c.maxSupply,
                    circulatingSupply: c.circulatingSupply,
                    totalSupply: c.totalSupply
                )
            }
        } // autoreleasepool
        
        if withinStartupCoalesceWindow {
            self.lastNormalizeSignature = normalizeSignature
            self.lastNormalizeAt = Date()
            self.lastNormalizeResult = normalized
        }
        
        return normalized
    }

    // NOTE: orientSparklineForDisplay and ensureNewestOnRightForVM have been removed.
    // Orientation is now handled by lightweight guards in canonicalSpark(), computeAllV2(),
    // displaySparkline(for:), and WatchlistSection.metrics(for:) that compare the sparkline's
    // visual trend against the authoritative provider 7D percentage change and live price.

    /// Lightweight fingerprint of a series to detect material changes without expensive diffs
    private func fingerprint(_ data: [Double]) -> Int {
        let vals = data.filter { $0.isFinite && $0 > 0 }
        guard !vals.isEmpty else { return 0 }
        let n = vals.count
        let first = vals.first ?? 0
        let last = vals.last ?? 0
        let minV = vals.min() ?? 0
        let maxV = vals.max() ?? 0
        let mean = vals.reduce(0, +) / Double(n)
        // Quantize to reduce churn
        func q(_ x: Double) -> Int { Int((x.isFinite ? x : 0).rounded()) }
        var hasher = Hasher()
        hasher.combine(n)
        hasher.combine(q(first * 1000))
        hasher.combine(q(last * 1000))
        hasher.combine(q(minV * 1000))
        hasher.combine(q(maxV * 1000))
        hasher.combine(q(mean * 1000))
        return hasher.finalize()
    }
    private func fpChangedMaterially(_ a: Int?, _ b: Int) -> Bool { guard let aa = a else { return true }; return aa != b }

    /// Coarse price bucketing used to invalidate display caches when the price scale changes
    private func priceBucket(_ p: Double?) -> Int {
        guard let p = p, p.isFinite, p > 0 else { return 0 }
        // Quantize by log10 scale to keep buckets stable across magnitudes
        let lg = log10(p)
        return Int((lg * 100.0).rounded())
    }

    /// Minimal price stabilizer used by orientation scoring; currently a pass-through
    private func stabilizePrice(id: String, new: Double?) -> Double? {
        // Hook for future hysteresis/smoothing if needed; pass-through keeps behavior simple and predictable.
        return new
    }

    /// Estimates percent change over a given hour window from a 7D-like sparkline series.
    /// Assumes the series is ordered oldest -> newest or has been normalized before calling.
    private func derivePercentChange(from series: [Double], hours: Int) -> Double? {
        let vals = series.filter { $0.isFinite && $0 > 0 }
        guard vals.count >= 2, let last = vals.last, last > 0 else { return nil }
        let n = vals.count
        
        // SMART STEP CALCULATION: Detect actual data coverage based on point count
        // Common sparkline formats:
        // - 168 points (140-200): Hourly data over 7 days
        // - 42 points (35-55): 4-hour intervals over 7 days
        // - 7 points (5-14): Daily data over 7 days
        let stepHours: Double = {
            if n >= 140 && n <= 200 { return 1.0 }        // Hourly data
            else if n >= 35 && n < 140 { return 4.0 }     // 4-hour interval
            else if n >= 5 && n < 35 { return 24.0 }      // Daily data
            else { return (24.0 * 7.0) / Double(max(1, n - 1)) }  // Fallback
        }()
        
        let lookbackSteps = max(1, Int(round(Double(hours) / stepHours)))
        let window = max(1, min(n - 1, lookbackSteps))
        let startIdx = max(0, n - 1 - window)
        let start = vals[startIdx]
        guard start > 0 else { return nil }
        let change = (last / start) - 1.0
        return change.isFinite ? change * 100.0 : nil
    }

    /// Returns a sparkline suitable for display for a given coin, resampled/smoothed when needed.
    func displaySparkline(for coin: MarketCoin) -> [Double] {
        // Resolve from raw sources (live -> allCoins -> lastGood), but allow the coin's own series as a fallback so Watchlist never flattens.
        var series = self.bestSparkline(for: coin.id, current: coin.sparklineIn7d)
        series = series.filter { $0.isFinite && $0 > 0 }

        // Compute a stable spot price for orientation/anchoring
        let spot = self.bestPrice(for: coin.id) ?? coin.priceUsd

        // If empty/too short, synthesize a gentle 7D series and anchor to the spot price
        if series.count < 2 {
            let synth = self.synthesizeSparkline(for: coin)
            let anchoredSynth = self.anchorSeriesToPrice(synth, price: spot)
            let out = finalizeDisplaySeries(self.sanitizeSeriesForDisplay(anchoredSynth, spot: spot), for: coin)
            let keyFP = self.fingerprint(out) ^ (self.priceBucket(spot) &* 31)
            self.displaySeriesCache[coin.id] = out
            self.displaySeriesCacheKey[coin.id] = keyFP
            self.displaySeriesCacheAt[coin.id] = Date()  // CACHE FIX: Track timestamp
            if self.displaySeriesCache.count > self.maxDisplayCacheEntries * 12 / 10 || self.orientationCache.count > self.maxOrientationCacheEntries * 12 / 10 {
                self.enforceDisplayCacheBudget()
            }
            return out
        }

        // SPARKLINE DATA INTEGRITY: Do NOT reverse the sparkline array.
        // CoinGecko and Binance APIs always return data in chronological order (oldest → newest).
        // All reversal logic has been removed — trust the data source.
        // Color (red/green) is determined by the actual 7D% percentage, not sparkline visual trend.
        
        let anchored = self.anchorSeriesToPrice(series, price: spot)

        // If the series is nearly flat at display scale, add a subtle micro-wiggle so small cells don't look like a straight line.
        var prepared = anchored
        do {
            let vals = prepared.filter { $0.isFinite && $0 > 0 }
            if let minV = vals.min(), let maxV = vals.max(), maxV > 0 {
                let rangeRatio = (maxV - minV) / max(1.0, maxV)
                if rangeRatio < 0.002 {
                    if Date() >= self.firstFrameQuietUntil {
                        let hint = coin.priceChangePercentage7dInCurrency ?? coin.priceChangePercentage24hInCurrency
                        let ff = max(0.0, min(1.0, (SparklineTuning.flatnessThreshold * 2.0 - rangeRatio) / (SparklineTuning.flatnessThreshold * 2.0)))
                        prepared = microWiggle(prepared, trendPercent: hint, seed: coin.id, flatnessFactor: ff)
                        // Re-anchor after micro-adjustment to keep last point close to spot
                        prepared = self.anchorSeriesToPrice(prepared, price: spot)
                    }
                }
            }
        }

        // Sanitize to guarantee no NaNs/Inf and at least two points before caching/finalizing
        let safePrepared = self.sanitizeSeriesForDisplay(prepared, spot: spot)

        // Cache-aware key includes shape and price bucket to invalidate when scale changes
        // CACHE FIX: Also check if cached entry is expired
        let keyFP = self.fingerprint(safePrepared) ^ (self.priceBucket(spot) &* 31)
        if let cachedKey = displaySeriesCacheKey[coin.id],
           cachedKey == keyFP,
           let cachedSeries = displaySeriesCache[coin.id], !cachedSeries.isEmpty,
           let cachedAt = displaySeriesCacheAt[coin.id],
           Date().timeIntervalSince(cachedAt) < displaySeriesCacheTTL {
            return cachedSeries
        }

        // Finalize for display (upsample only)
        let out = finalizeDisplaySeries(safePrepared, for: coin)
        displaySeriesCache[coin.id] = out
        displaySeriesCacheKey[coin.id] = keyFP
        displaySeriesCacheAt[coin.id] = Date()  // CACHE FIX: Track timestamp
        if self.displaySeriesCache.count > self.maxDisplayCacheEntries * 12 / 10 || self.orientationCache.count > self.maxOrientationCacheEntries * 12 / 10 {
            self.enforceDisplayCacheBudget()
        }
        return out
    }

    private func finalizeDisplaySeries(_ oriented: [Double], for coin: MarketCoin) -> [Double] {
        // Render the raw series with minimal processing: filter invalids and upsample if needed.
        let spot = self.bestPrice(for: coin.id) ?? coin.priceUsd
        var normalized = oriented.filter { $0.isFinite && $0 > 0 }
        if normalized.count < 2 { return minimalSafeSeries(anchoredTo: spot) }
        if normalized.count < SparklineTuning.resampleCount { normalized = resampleSparkline(normalized, minCount: SparklineTuning.resampleCount) }
        // Post-resample safety: ensure all values are finite and positive
        normalized = normalized.compactMap { v in
            guard v.isFinite && v > 0 else { return nil }
            return max(1e-7, v)
        }
        if normalized.count < 2 { return minimalSafeSeries(anchoredTo: spot) }
        return normalized
    }

    private func clipOutliers(_ data: [Double]) -> [Double] {
        let vals = data.filter { $0.isFinite && $0 > 0 }
        guard vals.count >= 3 else { return data }
        let sorted = vals.sorted()
        let median = sorted[sorted.count / 2]
        guard median.isFinite && median > 0 else { return data }
        let lo = median * 0.6
        let hi = median * 1.6
        return data.map { v in
            guard v.isFinite && v > 0 else { return median }
            return min(max(v, lo), hi)
        }
    }

    /// Produces a minimal, safe two-point series anchored near the given price to keep rendering stable.
    private func minimalSafeSeries(anchoredTo price: Double?) -> [Double] {
        let p: Double
        if let v = price, v.isFinite, v > 0 { p = v } else { p = 1.0 }
        let a = max(1e-7, p * 0.999)
        let b = max(1e-7, p * 1.001)
        return [a, b]
    }

    /// Ensures a series contains only finite, positive values and at least two samples; otherwise returns a minimal safe series.
    private func sanitizeSeriesForDisplay(_ series: [Double], spot: Double?) -> [Double] {
        let vals = series.filter { $0.isFinite && $0 > 0 }
        if vals.count >= 2 { return vals }
        return minimalSafeSeries(anchoredTo: spot)
    }

    /// Builds a lightweight synthetic 7D sparkline when upstream data is missing.
    /// - Stablecoins: flat line with tiny variance.
    /// - Others: gentle random walk with drift based on available 24h change, with light noise.
    private func synthesizeSparkline(for coin: MarketCoin) -> [Double] {
        // Generate a gentle, deterministic random walk with drift based on 7D/24H change so Watchlist doesn't look flat when data is missing.
        let n = 60
        let anchor = bestPrice(for: coin.id) ?? coin.priceUsd ?? 1.0
        let base = (anchor.isFinite && anchor > 0) ? anchor : 1.0
        let trendPct = coin.priceChangePercentage7dInCurrency ?? coin.priceChangePercentage24hInCurrency ?? 0
        let clampedTrend = max(-95.0, min(95.0, trendPct))
        let target = base * (1.0 + (clampedTrend / 100.0))
        let stepDrift = (target - base) / Double(max(1, n - 1))
        // Deterministic PRNG seeded by coin id for stable shapes
        var hasher = Hasher()
        hasher.combine(coin.id)
        let seed = UInt64(bitPattern: Int64(hasher.finalize()))
        var rng = seed &* 1103515245 &+ 12345
        func nextNoise() -> Double {
            rng = rng &* 2862933555777941757 &+ 3037000493
            return (Double(rng & 1023) / 1023.0) - 0.5
        }
        var x = base
        var out: [Double] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            // small oscillation plus tiny noise, scaled by price
            let t = Double(i) / Double(max(1, n - 1))
            let sine = sin(2.0 * .pi * t * 1.8) // ~1.8 cycles across span
            let amp = base * 0.0025 // 0.25% of price as oscillation envelope
            let noise = nextNoise() * base * 0.0015
            x = max(0.0000001, x + stepDrift + (sine * amp) / Double(n) + noise / Double(n))
            out.append(x)
        }
        // Add subtle micro-variation guided by trend to avoid straight segments
        return microWiggle(out, trendPercent: trendPct, seed: coin.id)
    }

    /// Returns the best available positive price for a coin id from live, current, or last-good snapshots.
    /// ALL prices come from CoinGecko API via Firebase/Firestore (LivePriceManager).
    /// Exchange-specific prices (Binance order book, Coinbase ticker) are NOT mixed in here —
    /// they are only used for order execution context, not for display.
    ///
    /// PERFORMANCE FIX: idPriceBook (O(1) dictionary) is checked EARLY (Priority 2) as a fast path.
    /// Previously it was Priority 6 (last resort), meaning 4 slow O(n) linear array searches
    /// had to fail before reaching the fast dictionary. idPriceBook is rebuilt from allCoins,
    /// lastGoodAllCoins, and live coins, so it's authoritative and always populated after init().
    /// This prevents BTC (and other coins) from showing "—" during startup when array sources
    /// are temporarily empty but the price book is already populated from cache.
    func bestPrice(for id: String) -> Double? {
        func validPositive(_ x: Double?) -> Double? { if let v = x, v.isFinite, v > 0 { return v } else { return nil } }
        // PRICE SANITY FIX: For well-known high-value coins, reject suspiciously low prices.
        // This prevents data pipeline bugs from showing BTC at $0.99 instead of $96,000.
        // Minimum thresholds are set conservatively low — well below any realistic crash scenario.
        func passesMinPriceCheck(_ price: Double, for coinId: String) -> Bool {
            switch coinId {
            case "bitcoin": return price > 1000
            case "ethereum": return price > 50
            case "binancecoin": return price > 10
            case "solana": return price > 1
            default: return true  // No floor check for other coins
            }
        }
        func validWithSanity(_ x: Double?, source: String) -> Double? {
            guard let v = validPositive(x) else { return nil }
            if !passesMinPriceCheck(v, for: id) {
                #if DEBUG
                print("⚠️ [bestPrice] Rejected \(id) price $\(String(format: "%.4f", v)) from \(source) — below sanity threshold")
                #endif
                return nil
            }
            return v
        }
        // Priority 1: Local live coins (fastest — refreshed by LivePriceManager publisher)
        if let v = validWithSanity(self.coins.first(where: { $0.id == id })?.priceUsd, source: "coins") { return v }
        // Priority 2 (FAST PATH): Price book dictionary — O(1) lookup, populated from all snapshots
        // This is the key fix for BTC "—" on startup: the book is built in init() from cached coins,
        // so it's always available even when the live arrays haven't been populated yet.
        if let v = validWithSanity(self.idPriceBook[id], source: "idPriceBook") { return v }
        // Priority 3: LivePriceManager's current coins list (CoinGecko via Firestore)
        if let v = validWithSanity(LivePriceManager.shared.currentCoinsList.first(where: { $0.id == id })?.priceUsd, source: "LivePriceManager") { return v }
        // Priority 4: All coins cache
        if let v = validWithSanity(self.allCoins.first(where: { $0.id == id })?.priceUsd, source: "allCoins") { return v }
        if let v = validWithSanity(self.lastGoodAllCoins.first(where: { $0.id == id })?.priceUsd, source: "lastGoodAllCoins") { return v }
        if case .success(let snapshot) = self.state, let v = validWithSanity(snapshot.first(where: { $0.id == id })?.priceUsd, source: "state.success") { return v }
        return nil
    }
    private func bestSnapshotPrice(for id: String) -> Double? {
        func validPositive(_ x: Double?) -> Double? { if let v = x, v.isFinite, v > 0 { return v } else { return nil } }
        if let v = validPositive(self.allCoins.first(where: { $0.id == id })?.priceUsd) { return v }
        if let v = validPositive(self.lastGoodAllCoins.first(where: { $0.id == id })?.priceUsd) { return v }
        if case .success(let snapshot) = self.state, let v = validPositive(snapshot.first(where: { $0.id == id })?.priceUsd) { return v }
        return nil
    }

    /// Returns a copy of the coin with price patched from best-known sources when missing/non-positive.
    private func withPatchedPrice(_ coin: MarketCoin) -> MarketCoin {
        if (coin.priceUsd ?? 0) > 0 { return coin }
        if let p = (bestPrice(for: coin.id) ?? bestPrice(forSymbol: coin.symbol)), p.isFinite, p > 0 {
            return MarketCoin(
                id: coin.id,
                symbol: coin.symbol,
                name: coin.name,
                imageUrl: coin.imageUrl,
                priceUsd: p,
                marketCap: coin.marketCap,
                totalVolume: coin.totalVolume,
                priceChangePercentage1hInCurrency: coin.priceChangePercentage1hInCurrency,
                priceChangePercentage24hInCurrency: coin.priceChangePercentage24hInCurrency,
                priceChangePercentage7dInCurrency: coin.priceChangePercentage7dInCurrency,
                sparklineIn7d: coin.sparklineIn7d,
                marketCapRank: coin.marketCapRank,
                maxSupply: coin.maxSupply,
                circulatingSupply: coin.circulatingSupply,
                totalSupply: coin.totalSupply
            )
        }
        return coin
    }

    /// Returns a copy of the coin with totalVolume patched from volumeUsd24Hr or books when missing/non-positive.
    private func withPatchedVolume(_ coin: MarketCoin) -> MarketCoin {
        let providerSnapshotFresh = FirestoreMarketSync.shared.isCoinGeckoDataFresh
        // Prefer totalVolume, then volumeUsd24Hr when present
        let direct = providerSnapshotFresh ? (coin.totalVolume ?? coin.volumeUsd24Hr) : nil
        if let v = direct, v.isFinite, v > 0 {
            // If totalVolume already set and positive, keep as-is; otherwise rebuild with totalVolume=v
            if (coin.totalVolume ?? 0) > 0 { return coin }
            return MarketCoin(
                id: coin.id,
                symbol: coin.symbol,
                name: coin.name,
                imageUrl: coin.imageUrl,
                priceUsd: coin.priceUsd,
                marketCap: coin.marketCap,
                totalVolume: v,
                priceChangePercentage1hInCurrency: coin.priceChangePercentage1hInCurrency,
                priceChangePercentage24hInCurrency: coin.priceChangePercentage24hInCurrency,
                priceChangePercentage7dInCurrency: coin.priceChangePercentage7dInCurrency,
                sparklineIn7d: coin.sparklineIn7d,
                marketCapRank: coin.marketCapRank,
                maxSupply: coin.maxSupply,
                circulatingSupply: coin.circulatingSupply,
                totalSupply: coin.totalSupply
            )
        }
        // Fallback to best-known volume from books (id first, then symbol)
        let key = coin.symbol.uppercased()
        let lpmVol = LivePriceManager.shared.bestVolumeUSD(forSymbol: coin.symbol)
        if let v = (self.idVolumeBook[coin.id] ?? self.symbolVolumeBook[key] ?? lpmVol), v.isFinite, v > 0 {
            return MarketCoin(
                id: coin.id,
                symbol: coin.symbol,
                name: coin.name,
                imageUrl: coin.imageUrl,
                priceUsd: coin.priceUsd,
                marketCap: coin.marketCap,
                totalVolume: v,
                priceChangePercentage1hInCurrency: coin.priceChangePercentage1hInCurrency,
                priceChangePercentage24hInCurrency: coin.priceChangePercentage24hInCurrency,
                priceChangePercentage7dInCurrency: coin.priceChangePercentage7dInCurrency,
                sparklineIn7d: coin.sparklineIn7d,
                marketCapRank: coin.marketCapRank,
                maxSupply: coin.maxSupply,
                circulatingSupply: coin.circulatingSupply,
                totalSupply: coin.totalSupply
            )
        }
        return coin
    }

    /// Load a bundled coins snapshot as a last-resort fallback when cache/network are unavailable
    /// MEMORY FIX: Result is cached after first decode so the 1.8MB JSON is only parsed once.
    /// Previously this was called 4+ times during startup, each time decoding from scratch.
    /// MEMORY FIX: Static cache for bundled coins (decoded once, reused).
    /// Internal visibility so the app-level memory watchdog can clear it.
    static var _cachedBundledCoins: [MarketCoin]?
    private func loadBundledCoins() -> [MarketCoin] {
        // Return cached result if already decoded
        if let cached = Self._cachedBundledCoins { return cached }
        
        // Attempt both resource name styles: (name: "coins_cache", ext: "json") and (name: "coins_cache.json", ext: nil)
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "coins_cache", withExtension: "json"),
            Bundle.main.url(forResource: "coins_cache.json", withExtension: nil)
        ]
        for urlOpt in candidates {
            guard let url = urlOpt else { continue }
            do {
                let data = try Data(contentsOf: url)
                // Try decoding as [MarketCoin]
                if let decoded = try? JSONDecoder().decode([MarketCoin].self, from: data), !decoded.isEmpty {
                    Self._cachedBundledCoins = decoded
                    return decoded
                }
                // Try decoding as [CoinGeckoCoin] and map to MarketCoin
                let geckoDecoder = JSONDecoder()
                geckoDecoder.keyDecodingStrategy = .convertFromSnakeCase
                if let gecko = try? geckoDecoder.decode([CoinGeckoCoin].self, from: data), !gecko.isEmpty {
                    let mapped = gecko.map { MarketCoin(gecko: $0) }
                    Self._cachedBundledCoins = mapped
                    return mapped
                }
            } catch {
                // try next candidate
            }
        }
        return []
    }

    /// PRICE CONSISTENCY FIX: Also checks LivePriceManager for the most up-to-date prices
    /// PERFORMANCE FIX: symbolPriceBook (O(1)) checked early as fast path, same as bestPrice(for:).
    func bestPrice(forSymbol symbol: String) -> Double? {
        let key = symbol.uppercased()
        func validPositive(_ x: Double?) -> Double? { if let v = x, v.isFinite, v > 0 { return v } else { return nil } }
        // Priority 1: Local live coins (fastest)
        let liveBest = self.coins
            .filter { $0.symbol.uppercased() == key }
            .compactMap { validPositive($0.priceUsd) }
            .max()
        if let v = liveBest { return v }
        // Priority 2 (FAST PATH): Symbol price book — O(1) lookup, populated from all snapshots
        if let v = validPositive(self.symbolPriceBook[key]) { return v }
        // Priority 3: LivePriceManager's current coins list (most up-to-date from Binance/Firestore)
        let lpmBest = LivePriceManager.shared.currentCoinsList
            .filter { $0.symbol.uppercased() == key }
            .compactMap { validPositive($0.priceUsd) }
            .max()
        if let v = lpmBest { return v }
        // Priority 4: All coins cache
        let allBest = self.allCoins
            .filter { $0.symbol.uppercased() == key }
            .compactMap { validPositive($0.priceUsd) }
            .max()
        if let v = allBest { return v }
        let lastBest = self.lastGoodAllCoins
            .filter { $0.symbol.uppercased() == key }
            .compactMap { validPositive($0.priceUsd) }
            .max()
        if let v = lastBest { return v }
        if case .success(let snapshot) = self.state {
            let snapBest = snapshot
                .filter { $0.symbol.uppercased() == key }
                .compactMap { validPositive($0.priceUsd) }
                .max()
            if let v = snapBest { return v }
        }
        return nil
    }

    /// Returns the CoinGecko ID (e.g. "bitcoin") for a given symbol (e.g. "BTC").
    /// Searches local coins, allCoins, lastGoodAllCoins, and LivePriceManager in order.
    /// This centralises symbol-to-ID resolution so callers like LivePortfolioDataService
    /// don't have to guess or pass the wrong identifier to bestPrice(for:).
    func coinID(forSymbol symbol: String) -> String? {
        let key = symbol.uppercased()
        // Priority 1: Local live coins
        if let id = self.coins.first(where: { $0.symbol.uppercased() == key })?.id { return id }
        // Priority 2: LivePriceManager coins
        if let id = LivePriceManager.shared.currentCoinsList.first(where: { $0.symbol.uppercased() == key })?.id { return id }
        // Priority 3: allCoins cache
        if let id = self.allCoins.first(where: { $0.symbol.uppercased() == key })?.id { return id }
        // Priority 4: lastGoodAllCoins
        if let id = self.lastGoodAllCoins.first(where: { $0.symbol.uppercased() == key })?.id { return id }
        return nil
    }

    /// Backfills missing 7D sparklines for a limited set of coins using Binance klines.
    /// This runs in the background and rebuilds only coins that currently have an empty sparkline.
    func backfillMissingSparklines(limit: Int = 20) {
        // Quiet-start: don't backfill during the first frame window
        if Date() < self.firstFrameQuietUntil { return }
        // Cooldown to avoid repeated backfills during rate limits
        let _nowBF = Date()
        if _nowBF.timeIntervalSince(lastBackfillAt) < backfillCooldown { return }
        lastBackfillAt = _nowBF
        // Skip backfill during degraded network periods to reduce load
        if isNetworkDegraded { return }
        let effectiveLimit = isNetworkDegraded ? min(limit, 10) : limit
        let binanceSymbols: Set<String> = ["BTC","ETH","SOL","XRP","BNB","ADA","DOGE","MATIC","DOT","LTC"]
        let candidates = allCoins
            .filter { coin in
                let sym = coin.symbol.uppercased()
                let isStable = MarketCoin.stableSymbols.contains(sym)
                let unusable = !self.isSparklineUsable(coin.sparklineIn7d)
                return !isStable && unusable && (binanceSymbols.contains(sym) || coin.marketCapRank ?? Int.max < 200)
            }
            .prefix(effectiveLimit)
        guard !candidates.isEmpty else { return }

        Task {
            var map = Dictionary(allCoins.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            await withTaskGroup(of: (String, [Double]).self) { group in
                for coin in candidates {
                    group.addTask {
                        let series = await BinanceService.fetchSparkline(symbol: coin.symbol.uppercased())
                        return (coin.id, series)
                    }
                }
                for await (id, series) in group {
                    guard !series.isEmpty, let c = map[id] else { continue }
                    let rebuilt = MarketCoin(
                        id: c.id,
                        symbol: c.symbol,
                        name: c.name,
                        imageUrl: c.imageUrl,
                        priceUsd: c.priceUsd,
                        marketCap: c.marketCap,
                        totalVolume: c.totalVolume,
                        priceChangePercentage1hInCurrency: c.priceChangePercentage1hInCurrency,
                        priceChangePercentage24hInCurrency: c.priceChangePercentage24hInCurrency,
                        priceChangePercentage7dInCurrency: c.priceChangePercentage7dInCurrency,
                        // REPLACED LINE - store raw series without resample/smooth
                        sparklineIn7d: series,
                        marketCapRank: c.marketCapRank,
                        maxSupply: c.maxSupply,
                        circulatingSupply: c.circulatingSupply,
                        totalSupply: c.totalSupply
                    )
                    map[id] = rebuilt
                }
            }
            let updated = Array(map.values)
            let ordered = updated.sorted { ($0.marketCapRank ?? Int.max) < ($1.marketCapRank ?? Int.max) }
            await MainActor.run {
                self.publishOnNextRunLoop {
                    let cappedOrdered = self.capToMaxCoins(ordered)
                    self.allCoins = cappedOrdered
                    self.lastGoodAllCoins = cappedOrdered
                    if cappedOrdered.count >= self.minUsableSnapshotCount { self.saveCoinsCacheCapped(cappedOrdered) }
                    self.rebuildPriceBooks()
                    self.scheduleApplyFilters(delay: 0.1)
                }
            }
        }
    }

    /// Best available market cap for a coin: prefer provider-reported marketCap, else approximate as price * supply (circulating > total > max).
    /// For coins without any supply data (e.g., Coinbase-only), uses volume * 10 as a rough proxy to give them reasonable placement.
    private nonisolated func bestCap(for c: MarketCoin) -> Double {
        if let cap = c.marketCap, cap.isFinite, cap > 0 { return cap }
        if let price = c.priceUsd, price.isFinite, price > 0 {
            if let circ = c.circulatingSupply, circ.isFinite, circ > 0 {
                let cap = price * circ
                if cap.isFinite, cap > 0 { return cap }
            }
            if let total = c.totalSupply, total.isFinite, total > 0 {
                let cap = price * total
                if cap.isFinite, cap > 0 { return cap }
            }
            if let maxSup = c.maxSupply, maxSup.isFinite, maxSup > 0 {
                let cap = price * maxSup
                if cap.isFinite, cap > 0 { return cap }
            }
        }
        // COINBASE FIX: For coins without market cap or supply data (e.g., from Coinbase/Binance),
        // use volume * 10 as a rough proxy. This gives them reasonable placement in the list
        // rather than clustering all at the bottom.
        if let vol = c.totalVolume ?? c.volumeUsd24Hr, vol.isFinite, vol > 0 {
            // Volume * 10 is a rough approximation - coins with higher trading activity
            // tend to have higher market caps. This prevents zero-cap coins from all
            // clustering at the absolute bottom of the list.
            return vol * 10
        }
        return 0
    }
    
    /// Best market cap for a symbol by scanning multiple sources and using bestCap(for:)
    private nonisolated func bestCapForSymbol(_ symbol: String, sources: [[MarketCoin]]) -> Double {
        let key = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        var best: Double = 0
        for list in sources {
            for c in list where c.symbol.uppercased() == key {
                let cap = bestCap(for: c)
                if cap > best { best = cap }
                if cap == 0 {
                    if let p = c.priceUsd, p.isFinite, p > 0 {
                        if let circ = c.circulatingSupply, circ.isFinite, circ > 0 { let approx = p * circ; if approx > best { best = approx } }
                        else if let total = c.totalSupply, total.isFinite, total > 0 { let approx = p * total; if approx > best { best = approx } }
                        else if let maxS = c.maxSupply, maxS.isFinite, maxS > 0 { let approx = p * maxS; if approx > best { best = approx } }
                    }
                }
            }
        }
        return best
    }

    /// Returns a positive market cap for display if possible, using reported cap or approximations; otherwise nil
    private func patchedCap(for coin: MarketCoin) -> Double? {
        let cap = bestCap(for: coin)
        return cap > 0 ? cap : nil
    }

    /// Recomputes global stats from the best available snapshot, patching missing prices so caps can be derived
    private func refreshGlobalStatsFromBestSnapshot() {
        // Choose the richest available base snapshot
        let base: [MarketCoin]
        if !self.allCoins.isEmpty { base = self.allCoins }
        else if !self.lastGoodAllCoins.isEmpty { base = self.lastGoodAllCoins }
        else if !self.coins.isEmpty { base = self.coins }
        else { base = self.filteredCoins }
        guard !base.isEmpty else { return }
        // Patch prices so bestCap(for:) can derive market cap via price * supply when needed
        // replaced as per instruction:
        self.computeGlobalStatsAsync(base: base)
    }

    /// Computes a cap-weighted global 24h percent change from a coin list.
    /// Uses the provider 24h percent change per coin without derivation or sanitization.
    private nonisolated func computeGlobal24hChangePercent(from base: [MarketCoin]) -> Double? {
        guard !base.isEmpty else { return nil }
        // Collect valid (cap, pct) pairs and exclude extreme outliers that can skew the aggregate.
        var pairs: [(cap: Double, pct: Double)] = []
        pairs.reserveCapacity(min(500, base.count))
        for coin in base {
            let capNow = self.bestCap(for: coin)
            guard capNow.isFinite, capNow > 0 else { continue }
            guard let p = coin.priceChangePercentage24hInCurrency, p.isFinite else { continue }
            // Skip pathological outliers; keep the aggregate stable across devices.
            if abs(p) > 50 { continue }
            let denom = 1.0 + (p / 100.0)
            if denom <= 0 { continue }
            pairs.append((capNow, p))
        }
        guard !pairs.isEmpty else { return nil }
        // Use top-cap coins only to stabilize the metric and avoid long tails.
        pairs.sort { $0.cap > $1.cap }
        let top = pairs.prefix(300)
        var totalNow = 0.0
        var totalPrev = 0.0
        for (capNow, p) in top {
            let denom = 1.0 + (p / 100.0)
            totalNow += capNow
            totalPrev += capNow / denom
        }
        guard totalNow > 0, totalPrev > 0 else { return nil }
        let pct = (totalNow / totalPrev - 1.0) * 100.0
        return pct.isFinite ? pct : nil
    }

    /// Off-main computation of global stats; publishes results on MainActor.
    /// RACE CONDITION FIX: This method safely uses Task.detached because:
    /// 1. All self methods called (bestCap, computeGlobal24hChangePercent, bestCapForSymbol) are nonisolated
    /// 2. State updates are done via await MainActor.run {}
    /// 3. Mutable state is captured as snapshots before the detached task starts
    private func computeGlobalStatsAsync(base: [MarketCoin]) {
        // Snapshot data needed for background computation to avoid racing mutable state
        let allSnap = self.allCoins
        let lastSnap = self.lastGoodAllCoins
        let liveSnap = self.coins
        let idVolBookSnap = self.idVolumeBook
        let symVolBookSnap = self.symbolVolumeBook
        let idPriceBookSnap = self.idPriceBook
        let symPriceBookSnap = self.symbolPriceBook

        Task.detached(priority: .utility) { [allSnap, lastSnap, liveSnap, idVolBookSnap, symVolBookSnap, idPriceBookSnap, symPriceBookSnap] in
            // Local helpers (no self mutation here)
            func valid(_ x: Double?) -> Double? { if let v = x, v.isFinite, v > 0 { return v } else { return nil } }
            func patched(_ c: MarketCoin) -> MarketCoin {
                // Patch price only if missing; avoid cross-thread bestPrice lookups for simplicity
                let price = valid(c.priceUsd)
                    ?? idPriceBookSnap[c.id]
                    ?? symPriceBookSnap[c.symbol.uppercased()]
                // Patch volume from provider, else from snapped books
                let vol = valid(c.totalVolume ?? c.volumeUsd24Hr)
                    ?? idVolBookSnap[c.id]
                    ?? symVolBookSnap[c.symbol.uppercased()]
                return MarketCoin(
                    id: c.id,
                    symbol: c.symbol,
                    name: c.name,
                    imageUrl: c.imageUrl,
                    priceUsd: price,
                    marketCap: c.marketCap,
                    totalVolume: vol,
                    priceChangePercentage1hInCurrency: c.priceChangePercentage1hInCurrency,
                    priceChangePercentage24hInCurrency: c.priceChangePercentage24hInCurrency,
                    priceChangePercentage7dInCurrency: c.priceChangePercentage7dInCurrency,
                    sparklineIn7d: c.sparklineIn7d,
                    marketCapRank: c.marketCapRank,
                    maxSupply: c.maxSupply,
                    circulatingSupply: c.circulatingSupply,
                    totalSupply: c.totalSupply
                )
            }
            let patchedBase = base.map { patched($0) }

            // Compute total market cap using best available method per coin
            var totalCap = patchedBase.reduce(0.0) { $0 + self.bestCap(for: $1) }
            if !totalCap.isFinite || totalCap < 0 { totalCap = 0 }

            // Compute total 24h volume (prefer totalVolume, then volumeUsd24Hr)
            var totalVol = patchedBase.compactMap { $0.totalVolume ?? $0.volumeUsd24Hr }.reduce(0, +)
            if !totalVol.isFinite || totalVol < 0 { totalVol = 0 }

            // Compute a market-wide 24h change percent using cap-weighted aggregation
            let gp = self.computeGlobal24hChangePercent(from: patchedBase)

            // Local dominance estimation (BTC/ETH) using best available caps
            let btcCap = self.bestCapForSymbol("BTC", sources: [patchedBase, allSnap, lastSnap, liveSnap])
            let ethCap = self.bestCapForSymbol("ETH", sources: [patchedBase, allSnap, lastSnap, liveSnap])
            let btcDomLocal = totalCap > 0 ? (btcCap / totalCap) * 100.0 : 0
            let ethDomLocal = totalCap > 0 ? (ethCap / totalCap) * 100.0 : 0

            let topForVol = patchedBase.sorted { self.bestCap(for: $0) > self.bestCap(for: $1) }.prefix(50)
            let changes = topForVol.compactMap { $0.priceChangePercentage24hInCurrency }.filter { $0.isFinite }
            var volStd: Double? = nil
            if changes.count >= 5 {
                let mean = changes.reduce(0, +) / Double(changes.count)
                let varSum = changes.reduce(0) { $0 + pow($1 - mean, 2) }
                let std = sqrt(varSum / Double(changes.count))
                volStd = std
            }

            let finalTotalCap = totalCap
            let finalTotalVol = totalVol
            let finalVolStd = volStd
            await MainActor.run {
                // Publish without regressing to nil once we have a good value
                if finalTotalCap > 0 { self.globalMarketCap = finalTotalCap }
                if finalTotalVol > 0 { self.globalVolume24h = finalTotalVol }
                if let g = gp { self.globalChange24hPercent = g }
                if let vs = finalVolStd, vs.isFinite, vs > 0 { self.globalVolatility24h = vs }

                if (self.btcDominance ?? 0) <= 0, btcDomLocal > 0 { self.btcDominance = btcDomLocal }
                if (self.ethDominance ?? 0) <= 0, ethDomLocal > 0 { self.ethDominance = ethDomLocal }

                // Persist a lightweight snapshot if any field is valid
                if (self.globalMarketCap ?? 0) > 0 || (self.globalVolume24h ?? 0) > 0 || (self.btcDominance ?? 0) > 0 || (self.ethDominance ?? 0) > 0 {
                    let snap = GlobalStatsSnapshot(marketCap: self.globalMarketCap,
                                                   volume24h: self.globalVolume24h,
                                                   btcDominance: self.btcDominance,
                                                   ethDominance: self.ethDominance,
                                                   change24hPercent: self.globalChange24hPercent,
                                                   publishedAt: Date())
                    CacheManager.shared.save(snap, to: "market_vm_global_stats.json")
                    let iso = Self._isoFormatter
                    let legacy = LegacyGlobalStatsSnapshot(
                        total_market_cap: self.globalMarketCap,
                        total_volume_24h: self.globalVolume24h,
                        btc_dominance: self.btcDominance,
                        eth_dominance: self.ethDominance,
                        published_at: iso.string(from: Date())
                    )
                    CacheManager.shared.save(legacy, to: "global_cache.json")
                }

                // Fill remaining fields from cached snapshot if any are still zero
                if (self.globalMarketCap ?? 0) <= 0 || (self.globalVolume24h ?? 0) <= 0 || (self.btcDominance ?? 0) <= 0 || (self.ethDominance ?? 0) <= 0 {
                    if let snap = self.loadAnyGlobalSnapshot() {
                        if (self.btcDominance ?? 0) <= 0, let b = snap.btcDominance, b > 0 { self.btcDominance = b }
                        if (self.ethDominance ?? 0) <= 0, let e = snap.ethDominance, e > 0 { self.ethDominance = e }
                    }
                }

                // If still missing/zero or base too small, trigger Gecko fetch (internal throttling applies)
                if !AppSettings.isSimulatorLimitedDataMode && ((self.globalMarketCap ?? 0) <= 0 || base.count < 50) {
                    self.scheduleGeckoStatsFetch(force: false, delay: 0.15)
                }

                if self.enableStatsLogging {
                    Diagnostics.shared.log(.marketVM, "Global cap=\(self.globalMarketCap ?? 0), vol24h=\(self.globalVolume24h ?? 0), btcDom=\(self.btcDominance ?? 0), ethDom=\(self.ethDominance ?? 0)", minInterval: 12)
                }
            }
        }
    }

    /// Single-source-of-truth derivation for percent change. Uses raw chronological series only.
    private func bestDerivedChange(id: String, series: [Double], hours: Int) -> Double? {
        // Ensure we derive from a forward-chronological series whose last point is the most recent.
        let spot = self.bestPrice(for: id) ?? self.bestSnapshotPrice(for: id)
        var vals = chronologicalSeriesForDerivation(id: id, series: series, spot: spot)
        guard vals.count >= 2 else { return nil }
        // Clip outliers to avoid single-sample spikes from upstream
        vals = clipOutliers(vals)
        return derivePercentChange(from: vals, hours: hours)
    }

    /// Single source of truth for 1h percent change (updated to use LivePriceManager)
    private func best1h(from coin: MarketCoin?) -> Double? {
        guard let coin = coin else { return nil }
        // Replace forSymbol with for as per instructions
        return LivePriceManager.shared.bestChange1hPercent(for: coin)
    }

    /// Single source of truth for 24h percent change (updated to use LivePriceManager)
    private func best24h(from coin: MarketCoin?) -> Double? {
        guard let coin = coin else { return nil }
        // Replace forSymbol with for as per instructions
        return LivePriceManager.shared.bestChange24hPercent(for: coin)
    }

    /// Computes and publishes basic global market stats from a given coin list.
    private func computeGlobalStats(base: [MarketCoin]) {
        guard !base.isEmpty else { return }

        // Patch prices so bestCap(for:) can derive market cap via price * supply when needed
        let patchedBase = base.map { withPatchedVolume(withPatchedPrice($0)) }

        // Compute total market cap using best available method per coin
        var totalCap = patchedBase.reduce(0.0) { $0 + bestCap(for: $1) }
        if !totalCap.isFinite || totalCap < 0 { totalCap = 0 }

        // If invalid/zero, attempt a secondary pass using lastGoodAllCoins
        if totalCap <= 0, !lastGoodAllCoins.isEmpty {
            let patchedLast = lastGoodAllCoins.map { withPatchedVolume(withPatchedPrice($0)) }
            totalCap = patchedLast.reduce(0.0) { $0 + bestCap(for: $1) }
            if !totalCap.isFinite || totalCap < 0 { totalCap = 0 }
        }

        // Compute total 24h volume (prefer totalVolume, then volumeUsd24Hr)
        var totalVol = patchedBase.compactMap { $0.totalVolume ?? $0.volumeUsd24Hr }.reduce(0, +)
        if (!totalVol.isFinite || totalVol < 0) && !lastGoodAllCoins.isEmpty {
            totalVol = lastGoodAllCoins.compactMap { $0.totalVolume ?? $0.volumeUsd24Hr }.reduce(0, +)
            if !totalVol.isFinite || totalVol < 0 { totalVol = 0 }
        }

        // Publish without regressing to nil once we have a good value
        if totalCap > 0 { self.globalMarketCap = totalCap }
        // If we still failed to compute a cap, preserve the previous non-nil cached value (avoid dash)
        if (self.globalMarketCap ?? 0) <= 0 {
            if let snap = self.loadAnyGlobalSnapshot(), let prevCap = snap.marketCap, prevCap > 0 {
                self.globalMarketCap = prevCap
            }
        }

        if totalVol > 0 {
            self.globalVolume24h = totalVol
        } else if self.globalVolume24h == nil {
            if let snap = self.loadAnyGlobalSnapshot(), let prevVol = snap.volume24h, prevVol > 0 {
                self.globalVolume24h = prevVol
            }
        }

        // Compute and publish a market-wide 24h change percent using cap-weighted aggregation
        if let gp = self.computeGlobal24hChangePercent(from: patchedBase) {
            self.globalChange24hPercent = gp
        }

        // Compute local BTC/ETH dominance if missing using best available caps
        let btcCapLocal = self.bestCapForSymbol("BTC", sources: [patchedBase, self.allCoins, self.lastGoodAllCoins, self.coins])
        let ethCapLocal = self.bestCapForSymbol("ETH", sources: [patchedBase, self.allCoins, self.lastGoodAllCoins, self.coins])
        if totalCap > 0 {
            let btcDomLocal = (btcCapLocal / totalCap) * 100.0
            let ethDomLocal = (ethCapLocal / totalCap) * 100.0
            if (self.btcDominance ?? 0) <= 0, btcDomLocal > 0 { self.btcDominance = btcDomLocal }
            if (self.ethDominance ?? 0) <= 0, ethDomLocal > 0 { self.ethDominance = ethDomLocal }
        }

        // REPLACED BLOCK for fallback dominance with diagnostic log
        if (self.btcDominance == nil || (self.btcDominance ?? 0) <= 0) ||
           (self.ethDominance == nil || (self.ethDominance ?? 0) <= 0) {
            if let snap = self.loadAnyGlobalSnapshot() {
                var usedSnapshot = false
                if (self.btcDominance ?? 0) <= 0, let b = snap.btcDominance, b > 0 { self.btcDominance = b; usedSnapshot = true }
                if (self.ethDominance ?? 0) <= 0, let e = snap.ethDominance, e > 0 { self.ethDominance = e; usedSnapshot = true }
                if usedSnapshot {
                    self.diag("Diag: Dominance fallback from cached snapshot (btc=\(self.btcDominance ?? 0), eth=\(self.ethDominance ?? 0))")
                }
            }
        }

        // Estimate 24h volatility from top-cap coins as a proxy (stddev of 24h pct changes)
        let topForVol = patchedBase.sorted { bestCap(for: $0) > bestCap(for: $1) }.prefix(50)
        let changes = topForVol.compactMap { $0.priceChangePercentage24hInCurrency }.filter { $0.isFinite }
        if changes.count >= 5 {
            let mean = changes.reduce(0, +) / Double(changes.count)
            let varSum = changes.reduce(0) { $0 + pow($1 - mean, 2) }
            let std = sqrt(varSum / Double(changes.count))
            self.globalVolatility24h = std
            diag(String(format: "Diag: estimated 24h volatility=%.2f%% from %d coins", std, changes.count))
        }

        // Persist a lightweight snapshot to bridge rate limits (only if at least one field is valid)
        if (self.globalMarketCap ?? 0) > 0 || (self.globalVolume24h ?? 0) > 0 || (self.btcDominance ?? 0) > 0 || (self.ethDominance ?? 0) > 0 {
            let snap = GlobalStatsSnapshot(marketCap: self.globalMarketCap,
                                           volume24h: self.globalVolume24h,
                                           btcDominance: self.btcDominance,
                                           ethDominance: self.ethDominance,
                                           change24hPercent: self.globalChange24hPercent,
                                           publishedAt: Date())
            CacheManager.shared.save(snap, to: "market_vm_global_stats.json")
            let iso = Self._isoFormatter
            let legacy = LegacyGlobalStatsSnapshot(
                total_market_cap: self.globalMarketCap,
                total_volume_24h: self.globalVolume24h,
                btc_dominance: self.btcDominance,
                eth_dominance: self.ethDominance,
                published_at: iso.string(from: Date())
            )
            CacheManager.shared.save(legacy, to: "global_cache.json")
        }

        // Final safety net: if Market Cap is still missing/zero, fetch from an external global endpoint (CoinGecko)
        // If still missing/zero, or our base list is very small (cold start / rate limits), attempt a Gecko fetch but throttle to avoid spam
        if (self.globalMarketCap ?? 0) <= 0 || base.count < 50 {
            let now = Date()
            let isEarlyWindow = now < self.firstGeckoWindowUntil
            let effectiveCooldown = isEarlyWindow ? 10 : self.geckoFetchCooldown
            if now.timeIntervalSince(self.lastGeckoFetchAt) >= effectiveCooldown {
                self.scheduleGeckoStatsFetch(force: false, delay: 0.15)
            } else {
                if now.timeIntervalSince(self.lastGeckoSkipLogAt) >= 60 {
                    self.diag("Diag: Skipping Gecko fetch (throttled); last=\(self.lastGeckoFetchAt)")
                    self.lastGeckoSkipLogAt = now
                }
            }
        }

        // INSERTED diagnostic block before logging global stats line
        // Diagnostic: BTC/ETH caps per source and local dominance estimates
        if totalCap <= 0 {
            if (self.globalMarketCap ?? 0) <= 0 {
                diag("Diag: local totalCap is zero; no fallback global cap available yet")
            }
        } else {
            let btcCaps: [(String, Double)] = [
                ("base", self.bestCapForSymbol("BTC", sources: [patchedBase])),
                ("allCoins", self.bestCapForSymbol("BTC", sources: [self.allCoins])),
                ("lastGood", self.bestCapForSymbol("BTC", sources: [self.lastGoodAllCoins])),
                ("live", self.bestCapForSymbol("BTC", sources: [self.coins]))
            ]
            let ethCaps: [(String, Double)] = [
                ("base", self.bestCapForSymbol("ETH", sources: [patchedBase])),
                ("allCoins", self.bestCapForSymbol("ETH", sources: [self.allCoins])),
                ("lastGood", self.bestCapForSymbol("ETH", sources: [self.lastGoodAllCoins])),
                ("live", self.bestCapForSymbol("ETH", sources: [self.coins]))
            ]
            func capWinner(_ caps: [(String, Double)]) -> (String, Double) { caps.max(by: { $0.1 < $1.1 }) ?? ("none", 0) }
            let btcWin = capWinner(btcCaps)
            let ethWin = capWinner(ethCaps)
            let localBTC = totalCap > 0 ? (btcWin.1 / totalCap) * 100.0 : 0
            let localETH = totalCap > 0 ? (ethWin.1 / totalCap) * 100.0 : 0
            self.diag("Diag: BTC cap [base/all/last/live] = \(btcCaps.map { "\($0.0):\(Int($0.1))" }.joined(separator: ", ")) | winner=\(btcWin.0)")
            self.diag("Diag: ETH cap [base/all/last/live] = \(ethCaps.map { "\($0.0):\(Int($0.1))" }.joined(separator: ", ")) | winner=\(ethWin.0)")
            self.diag(String(format: "Diag: local dominance est — BTC=%.2f%%, ETH=%.2f%% (totalCap=%0.0f)", localBTC, localETH, totalCap))
        }

        if self.enableStatsLogging {
            Diagnostics.shared.log(.marketVM, "Global cap=\(self.globalMarketCap ?? 0), vol24h=\(self.globalVolume24h ?? 0), btcDom=\(self.btcDominance ?? 0), ethDom=\(self.ethDominance ?? 0)", minInterval: 12)
        }
    }

    /// Gecko 429 handling: record a penalty window and grow backoff if clustered
    private func recordGeckoRateLimit(reason: String) {
        let now = Date()
        if now.timeIntervalSince(geckoRateLimitedUntil) < 60 {
            geckoPenaltyBackoff = min(geckoPenaltyBackoff * 1.5, 300)
        } else {
            geckoPenaltyBackoff = 120
        }
        geckoRateLimitedUntil = now.addingTimeInterval(geckoPenaltyBackoff)
        diag("Diag: Gecko rate-limited (\(reason)); backoff \(Int(geckoPenaltyBackoff))s")
    }

    private func clearGeckoPenaltyOnSuccess() {
        geckoRateLimitedUntil = .distantPast
        geckoPenaltyBackoff = 120
    }

    /// Lightweight fallback fetcher for global stats from CoinGecko when local computation yields no cap
    private struct GeckoGlobalResponse: Decodable {
        struct Payload: Decodable {
            let total_market_cap: [String: Double]?
            let total_volume: [String: Double]?
            let market_cap_percentage: [String: Double]?
        }
        let data: Payload
    }

    private func fetchGlobalStatsFromGecko(force: Bool = false) {
        // Quiet-start: defer the very first global stats fetch until after the first frame
        let nowQuiet = Date()
        if nowQuiet < self.firstFrameQuietUntil {
            let delay = max(0, self.firstFrameQuietUntil.timeIntervalSince(nowQuiet))
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.fetchGlobalStatsFromGecko(force: force)
            }
            return
        }
        // FIX: Check APIRequestCoordinator before CoinGecko requests
        if !force && !APIRequestCoordinator.shared.canMakeRequest(for: .coinGecko) {
            self.diag("Diag: Skipping Gecko fetch (blocked by coordinator)")
            return
        }
        // Respect degraded network and Gecko rate-limit windows unless forced
        if !force {
            if isNetworkDegraded { return }
            if Date() < geckoRateLimitedUntil {
                if Date().timeIntervalSince(self.lastGeckoSkipLogAt) >= 60 {
                    self.diag("Diag: Skipping Gecko fetch (rate-limited until \(geckoRateLimitedUntil))")
                    self.lastGeckoSkipLogAt = Date()
                }
                return
            }
            if geckoFetchInFlight { return }
        }
        // Cooldown between calls
        let now = Date()
        let isEarlyWindow = now < self.firstGeckoWindowUntil
        let effectiveCooldown = isEarlyWindow ? 10 : geckoFetchCooldown
        if !force && now.timeIntervalSince(lastGeckoFetchAt) < effectiveCooldown { return }
        lastGeckoFetchAt = now
        geckoFetchInFlight = true
        // FIX: Record CoinGecko request with coordinator
        APIRequestCoordinator.shared.recordRequest(for: .coinGecko)
        Task {
            defer {
                DispatchQueue.main.async { [weak self] in
                    self?.geckoFetchInFlight = false
                }
            }
            do {
                guard let url = URL(string: "https://api.coingecko.com/api/v3/global") else { return }
                var req = APIConfig.coinGeckoRequest(url: url)
                req.cachePolicy = .reloadIgnoringLocalCacheData
                req.timeoutInterval = 10  // FIX: Increased timeout from 5 to 10
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, http.statusCode == 429 {
                    await MainActor.run { self.recordGeckoRateLimit(reason: "HTTP 429 from /global") }
                    return
                }
                let decoded = try JSONDecoder().decode(GeckoGlobalResponse.self, from: data)
                let capUSD = decoded.data.total_market_cap?["usd"]
                let volUSD = decoded.data.total_volume?["usd"]
                let btcDom = decoded.data.market_cap_percentage?["btc"]
                let ethDom = decoded.data.market_cap_percentage?["eth"]
                await MainActor.run {
                    if let c = capUSD, c.isFinite, c > 0 { self.globalMarketCap = c }
                    if let v = volUSD, v.isFinite, v > 0 { self.globalVolume24h = v }
                    if let b = btcDom, b.isFinite, b > 0 { self.btcDominance = b }
                    if let e = ethDom, e.isFinite, e > 0 { self.ethDominance = e }
                    if (self.globalMarketCap ?? 0) > 0 || (self.globalVolume24h ?? 0) > 0 || (self.btcDominance ?? 0) > 0 || (self.ethDominance ?? 0) > 0 {
                        let snap = GlobalStatsSnapshot(marketCap: self.globalMarketCap,
                                                       volume24h: self.globalVolume24h,
                                                       btcDominance: self.btcDominance,
                                                       ethDominance: self.ethDominance,
                                                       change24hPercent: self.globalChange24hPercent,
                                                       publishedAt: Date())
                        CacheManager.shared.save(snap, to: "market_vm_global_stats.json")
                        let iso = Self._isoFormatter
                        let legacy = LegacyGlobalStatsSnapshot(
                            total_market_cap: self.globalMarketCap,
                            total_volume_24h: self.globalVolume24h,
                            btc_dominance: self.btcDominance,
                            eth_dominance: self.ethDominance,
                            published_at: iso.string(from: Date())
                        )
                        CacheManager.shared.save(legacy, to: "global_cache.json")
                        self.recordNetworkSuccess()
                        self.clearGeckoPenaltyOnSuccess()
                    } else {
                        self.diag("Diag: Gecko global returned no usable fields; keeping previous snapshot")
                        self.recordNetworkFailure(NSError(domain: "GeckoGlobal", code: -1, userInfo: [NSLocalizedDescriptionKey: "Empty/zero global stats"]))
                    }
                }
            } catch {
                await MainActor.run {
                    self.recordNetworkFailure(error)
                }
            }
        }
    }

    // MARK: - Scheduling & Diff Helpers (added)
    /// Schedules a block to run on the next run loop tick on the main thread to avoid re-entrancy churn.
    ///
    /// MEMORY FIX v7: Changed from `Task { @MainActor in }` to `DispatchQueue.main.async`.
    /// Task uses Swift Concurrency's cooperative executor, which can process many tasks
    /// back-to-back WITHOUT returning to the run loop. This starves:
    ///   - Timer events (watchdog never fires)
    ///   - Autorelease pool drains (autoreleased objects accumulate)
    ///   - CADisplayLink callbacks (UI freezes)
    /// GCD's main queue integrates with the run loop — between dispatched blocks, the run loop
    /// processes timers, drains autorelease pools, and handles UI events. This prevents the
    /// unbounded memory growth from undrained autoreleased objects.
    private func publishOnNextRunLoop(_ work: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async {
            autoreleasepool { work() }
        }
    }

    // MEMORY FIX v13: Short startup processing freeze to prevent launch bursts
    // while keeping prices/percentages responsive soon after app opens.
    private var startupFilterFreezeUntil: Date? = nil
    private var startupFilterFreezeDuration: TimeInterval {
        AppSettings.isSimulatorLimitedDataMode ? 0.0 : 0.35
    }
    private var hasCompletedInitialFilterPass: Bool = false
    private var pendingFilterSignature: Int?
    private var lastAppliedFilterSignature: Int?
    
    private func makeFilterWorkSignature() -> Int {
        var hasher = Hasher()
        hasher.combine(selectedSegment.rawValue)
        hasher.combine(selectedCategory.rawValue)
        hasher.combine(sortField.rawValue)
        hasher.combine(sortDirection.rawValue)
        hasher.combine(searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        hasher.combine(coins.count)
        hasher.combine(allCoins.count)
        hasher.combine(liveBeatTick)
        for coin in coins.prefix(12) {
            hasher.combine(coin.id)
            hasher.combine(Int((coin.priceUsd ?? 0) * 100))
        }
        for coin in allCoins.prefix(12) {
            hasher.combine(coin.id)
        }
        return hasher.finalize()
    }
    
    /// Debounces applyAllFiltersAndSort to avoid constant resorting during rapid updates.
    private func scheduleApplyFilters(delay: TimeInterval = 0.5) {
        // MEMORY FIX v13: After the initial filter pass, briefly freeze further passes.
        if hasCompletedInitialFilterPass {
            if let freezeEnd = startupFilterFreezeUntil, Date() < freezeEnd {
                return  // Silently drop — cached data is sufficient for display
            }
        }
        
        let signature = makeFilterWorkSignature()
        if pendingFilterSignature == signature || lastAppliedFilterSignature == signature {
            return
        }
        
        pendingFilterWork?.cancel()
        pendingFilterSignature = signature
        let baseDelay = max(delay, 0.016)
        // Add small jitter (0..50ms) to avoid synchronized bursts across multiple publishers
        let jitter = Double.random(in: 0...0.05)
        let d = baseDelay + jitter
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.pendingFilterSignature = nil
            if self.lastAppliedFilterSignature == signature { return }
            // MEMORY FIX v11: Mark the first filter pass and start the freeze timer
            if !self.hasCompletedInitialFilterPass {
                self.hasCompletedInitialFilterPass = true
                self.startupFilterFreezeUntil = Date().addingTimeInterval(self.startupFilterFreezeDuration)
                #if DEBUG
                print("🧊 [MarketViewModel] Initial filter pass done — freezing further passes for \(String(format: "%.2f", self.startupFilterFreezeDuration))s")
                #endif
            }
            self.applyAllFiltersAndSort()
        }
        pendingFilterWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + d, execute: work)
    }
    /// Coalesce Gecko global stats fetches to avoid back-to-back calls
    private func scheduleGeckoStatsFetch(force: Bool = false, delay: TimeInterval = 0.1) {
        pendingGeckoFetchWork?.cancel()
        let d = max(0, delay)
        let work = DispatchWorkItem { [weak self] in
            self?.fetchGlobalStatsFromGecko(force: force)
        }
        pendingGeckoFetchWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + d, execute: work)
    }

    /// Immediately publish the current snapshot to the UI if the list is empty, to avoid a blank Market screen on cold start.
    private func showSnapshotImmediately() {
        // If we have a decent snapshot, ensure the UI shows it even if a tiny live list was previously displayed.
        guard !self.allCoins.isEmpty else { return }
        // Only skip if we already have a usable list displayed
        if self.filteredCoins.count >= self.minUsableSnapshotCount { return }
        let mapped = self.allCoins.map { self.withDisplayReadySparkline($0) }
        self.filteredCoins = mapped
        self.refreshGlobalStatsFromBestSnapshot()
    }

    /// Approximate equality for numeric values with relative and absolute tolerances
    private func approxEqual(_ x: Double?, _ y: Double?, relTol: Double = 5e-4, absTol: Double = 1e-8) -> Bool {
        let a = x ?? 0
        let b = y ?? 0
        if a == b { return true }
        let diff = abs(a - b)
        if diff <= absTol { return true }
        let scale = max(max(abs(a), abs(b)), 1.0)
        return (diff / scale) <= relTol
    }

    /// Approximate equality for percent values (expressed in percentage points)
    private func approxEqualPercent(_ x: Double?, _ y: Double?, absTol: Double = 0.05) -> Bool {
        let a = x ?? 0
        let b = y ?? 0
        if a == b { return true }
        return abs(a - b) <= absTol
    }

    /// Fast check to avoid re-mapping and re-publishing when only tiny jitter occurs
    private func listSemanticallyUnchanged(new: [MarketCoin], old: [MarketCoin]) -> Bool {
        guard new.count == old.count else { return false }
        for (a, b) in zip(new, old) {
            if a.id != b.id { return false }
            if !approxEqual(a.priceUsd, b.priceUsd, relTol: 5e-4, absTol: 1e-6) { return false }
            if !approxEqualPercent(self.best1h(from: a), self.best1h(from: b), absTol: 0.05) { return false }
            if !approxEqualPercent(self.best24h(from: a), self.best24h(from: b), absTol: 0.05) { return false }
            if !approxEqualPercent(a.priceChangePercentage7dInCurrency, b.priceChangePercentage7dInCurrency, absTol: 0.05) { return false }
        }
        return true
    }

    /// Lightweight visual diff used to avoid large inline boolean expressions that can stress the type checker.
    private func coinsVisuallyDiffer(_ a: MarketCoin, _ b: MarketCoin) -> Bool {
        if a.id != b.id { return true }

        // Prices: ignore sub-0.05% jitter to avoid per-frame churn
        if !approxEqual(a.priceUsd, b.priceUsd, relTol: 5e-4, absTol: 1e-6) { return true }

        // 1h change: treat differences smaller than 0.05 percentage points as equal
        let c1a = self.best1h(from: a)
        let c1b = self.best1h(from: b)
        if !approxEqualPercent(c1a, c1b, absTol: 0.05) { return true }

        // 24h change: same tolerance
        let c24a = self.best24h(from: a)
        let c24b = self.best24h(from: b)
        if !approxEqualPercent(c24a, c24b, absTol: 0.05) { return true }

        // 7d change: same tolerance
        let c7a = a.priceChangePercentage7dInCurrency
        let c7b = b.priceChangePercentage7dInCurrency
        if !approxEqualPercent(c7a, c7b, absTol: 0.05) { return true }

        // Sparkline: count differences imply a different series; otherwise consider visually identical
        if a.sparklineIn7d.count != b.sparklineIn7d.count { return true }

        return false
    }

    // MARK: - Filtering & Sorting (minimal)
    /// MEMORY FIX v7: Reentrancy guard. When applyAllFiltersAndSort is running, it modifies
    /// @Published properties (allCoins, state) whose didSet handlers schedule more filter
    /// updates. Without this guard, the function can execute recursively via:
    ///   applyAllFiltersAndSort → sets allCoins → didSet schedules publishOnNextRunLoop
    ///   → GCD dispatches → calls scheduleApplyFilters → DispatchWorkItem fires →
    ///   applyAllFiltersAndSort again (while previous invocation is still in the stack).
    /// The guard prevents concurrent execution and coalesces redundant calls.
    private var isApplyingFilters = false
    
    func applyAllFiltersAndSort() {
        // MEMORY FIX v12: Block direct calls during startup freeze window.
        // Previously, only scheduleApplyFilters() checked the freeze; direct calls from
        // loadAllData(), MarketView.onAppear, etc. bypassed the freeze and triggered
        // ensureBaselineSnapshotIfNeeded → allCoins didSet → cascading @Published updates.
        if hasCompletedInitialFilterPass,
           let freezeEnd = startupFilterFreezeUntil,
           Date() < freezeEnd {
            return
        }
        
        // MEMORY FIX v7: Reentrancy guard — if already running, skip (the caller already
        // scheduled a deferred update via scheduleApplyFilters which will pick up changes)
        guard !isApplyingFilters else { return }
        isApplyingFilters = true
        defer { isApplyingFilters = false }
        
        // SCROLL FIX: Skip filter updates during scroll to prevent scroll position reset
        // This prevents the "slingshot" effect where scrolling causes jumps back to top
        if ScrollStateManager.shared.isScrolling {
            // Reschedule for when scroll ends (500ms is enough for momentum to settle)
            self.scheduleApplyFilters(delay: 0.5)
            return
        }
        
        // Throttle frequent resorting to reduce churn/logs
        let now = Date()
        let elapsed = now.timeIntervalSince(self.lastSortedAt)
        let throttle = self.effectiveMinResortInterval
        if elapsed < throttle {
            self.scheduleApplyFilters(delay: throttle - elapsed)
            return
        }
        self.lastSortedAt = now
        self.lastAppliedFilterSignature = makeFilterWorkSignature()

        // Choose a base list: prefer live when warm, else fall back to snapshots
        var list: [MarketCoin]
        if self.coins.count >= self.effectiveMinLiveListForUI {
            list = self.coins
        } else if !self.allCoins.isEmpty {
            list = self.allCoins
        } else if !self.lastGoodAllCoins.isEmpty {
            list = self.lastGoodAllCoins
        } else {
            // Do not fall back to a tiny live set; force snapshot/bundled adoption path
            list = []
        }

        // If the chosen list is tiny or empty, immediately fall back to last-good or cached bundle snapshot
        if list.count < 50 {
            if !self.lastGoodAllCoins.isEmpty {
                list = self.lastGoodAllCoins
            } else if !self.allCoins.isEmpty {
                list = self.allCoins
            } else if case .success(let snap) = self.state, !snap.isEmpty {
                list = snap
            }
        }

        // MEMORY FIX v6: Use allCoins.count (raw) instead of list.count (filtered).
        // The filtered list can be smaller than allCoins due to segment filters (trending, etc.).
        // Using list.count triggered ensureBaselineSnapshotIfNeeded on every filter pass even
        // when allCoins was already at max capacity — creating massive wasted work.
        // Also: minCount MUST equal maxAllCoinsCount (50). Previously minCount was 60 but
        // allCoins is capped at 50, so the guard `allCoins.count >= minCount` NEVER returned
        // early, causing an infinite recursion: ensureBaseline → applyAllFiltersAndSort →
        // ensureBaseline → ... each iteration allocating MB of arrays and JSON parsing.
        if !AppSettings.isSimulatorLimitedDataMode && self.allCoins.count < Self.maxAllCoinsCount {
            self.ensureBaselineSnapshotIfNeeded(minCount: Self.maxAllCoinsCount)
        }
        
        // Deduplicate coins - remove wrapped/pegged variants when canonical exists (e.g., Binance-Peg DOGE)
        list = self.deduplicateCoins(list)

        // Segment filtering - apply proper filter for each segment type
        switch self.selectedSegment {
        case .all:
            // Keep full list - will be sorted by market cap / exchange priority below
            break
            
        case .trending:
            // Trending: score by |24h change| * log10(volume) - higher scores rank higher
            // Exclude stablecoins from trending
            list = list
                .filter { !MarketCoin.stableSymbols.contains($0.symbol.uppercased()) }
                .compactMap { coin -> (MarketCoin, Double)? in
                    let change = abs(coin.best24hPercent ?? 0)
                    let vol = coin.totalVolume ?? coin.volumeUsd24Hr ?? 10_000
                    guard vol > 0 else { return nil }
                    let score = change * log10(max(vol, 10_000))
                    return (coin, score)
                }
                .sorted { $0.1 > $1.1 }
                .map { $0.0 }
            
        case .gainers:
            // Gainers: Use adaptive threshold based on market conditions
            // - In bull markets (median > 2%): shows top performers above median
            // - In bear markets (median < -2%): shows outperformers (even if slightly negative)
            // - In flat markets: shows positive change coins
            let thresholds = calculateAdaptiveThresholds()
            list = list
                .filter { coin in
                    let sym = coin.symbol.uppercased()
                    guard !MarketCoin.stableSymbols.contains(sym) else { return false }
                    let change = coin.best24hPercent ?? 0
                    return change > thresholds.gainers
                }
                .sorted { ($0.best24hPercent ?? 0) > ($1.best24hPercent ?? 0) }
            
        case .losers:
            // Losers: Use adaptive threshold based on market conditions
            // - In bull markets (median > 2%): shows underperformers (even if slightly positive)
            // - In bear markets (median < -2%): shows worst performers below median
            // - In flat markets: shows negative change coins
            let thresholds = calculateAdaptiveThresholds()
            list = list
                .filter { coin in
                    let sym = coin.symbol.uppercased()
                    guard !MarketCoin.stableSymbols.contains(sym) else { return false }
                    let change = coin.best24hPercent ?? 0
                    return change < thresholds.losers
                }
                .sorted { ($0.best24hPercent ?? 0) < ($1.best24hPercent ?? 0) }
            
        case .favorites:
            // Favorites: filter to user's favorited coins, preserve their saved order
            let favs = self.favoriteIDs
            let favOrder = self.favoriteOrder
            let orderMap: [String: Int] = Dictionary(uniqueKeysWithValues: favOrder.enumerated().map { ($1, $0) })
            list = list
                .filter { favs.contains($0.id) }
                .sorted { (orderMap[$0.id] ?? Int.max) < (orderMap[$1.id] ?? Int.max) }
            
        case .new:
            // New: show ONLY truly new coins - first seen within 14 days
            // No rank-based fallback to avoid showing the entire list
            let newCoinsService = NewlyListedCoinsService.shared
            
            // Record all current coins as "seen" (but don't filter by this alone)
            newCoinsService.recordFirstSeen(coinIDs: list.map { $0.id })
            
            // Minimum volume threshold to filter out dead/inactive coins ($100k)
            let minVolume: Double = 100_000
            
            // Filter to coins that are truly "new" (first seen within 14 days) and have activity
            list = list
                .filter { coin in
                    let sym = coin.symbol.uppercased()
                    guard !MarketCoin.stableSymbols.contains(sym) else { return false }
                    
                    // Must have minimum trading volume to be considered active
                    let vol = coin.totalVolume ?? coin.volumeUsd24Hr ?? 0
                    guard vol >= minVolume else { return false }
                    
                    // Only show coins first seen within 14 days - strict check
                    guard let daysSeen = newCoinsService.daysSinceFirstSeen(coin.id) else {
                        // Never seen before - this IS a new coin!
                        return true
                    }
                    
                    // Only include if seen within the last 14 days
                    return daysSeen <= 14
                }
                .sorted { a, b in
                    // Priority 1: Days since first seen (fewer days = more recent = higher priority)
                    let aDays = newCoinsService.daysSinceFirstSeen(a.id) ?? 0
                    let bDays = newCoinsService.daysSinceFirstSeen(b.id) ?? 0
                    if aDays != bDays { return aDays < bDays }
                    
                    // Priority 2: Higher 24h volume = more interest
                    let aVol = a.totalVolume ?? a.volumeUsd24Hr ?? 0
                    let bVol = b.totalVolume ?? b.volumeUsd24Hr ?? 0
                    return aVol > bVol
                }
        }

        // Search text filtering
        // IMPROVED: When searching, include ALL coins (not just deduplicated) so users can find
        // wrapped coins, stablecoins, etc. that are filtered from the normal view
        let query = self.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            // Search across ALL coins (allCoins) to find matches, not just the filtered list
            // This ensures users can find any coin by name or symbol, even if filtered from display
            let allSearchable = self.allCoins.isEmpty ? self.lastGoodAllCoins : self.allCoins
            let searchMatches = allSearchable.filter { coin in
                coin.name.lowercased().contains(query) || coin.symbol.lowercased().contains(query)
            }
            
            // Merge search results with the current list, prioritizing matches already in list
            let listIDs = Set(list.map { $0.id })
            var merged = list.filter { coin in
                coin.name.lowercased().contains(query) || coin.symbol.lowercased().contains(query)
            }
            // Add any matches from allCoins that weren't in the filtered list
            for match in searchMatches where !listIDs.contains(match.id) {
                merged.append(match)
            }
            list = merged
        }
        
        // Category sub-filtering (DeFi, Layer 1, Meme, etc.)
        if self.selectedCategory != .all {
            list = list.filter { coin in
                self.selectedCategory.contains(symbol: coin.symbol)
            }
        }

        // Overlay live percents/prices using mergedBest so Market matches Heat Map/Watchlist
        // Use uniquingKeysWith to handle duplicate coin IDs gracefully (keep first occurrence)
        let allMap  = Dictionary(self.allCoins.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let lastMap = Dictionary(self.lastGoodAllCoins.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let liveMap = Dictionary(self.coins.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        list = list.map { c in
            self.mergedBest(c, prev: allMap[c.id] ?? lastMap[c.id], live: liveMap[c.id], allowLiveManager: true)
        }

        // Patch missing prices/volumes for stability in UI/stats
        list = list.map { self.withPatchedVolume(self.withPatchedPrice($0)) }

        // Apply sorting based on sort field, but respect segment-specific ordering for special segments
        // Trending, Gainers, Losers, New are pre-sorted by their segment logic above
        // Only re-sort them if the user explicitly changes the sort field from default
        let shouldApplyGenericSort: Bool = {
            switch self.selectedSegment {
            case .all:
                return true // Always apply sorting for All segment
            case .favorites:
                return false // Favorites preserve user-defined order
            case .trending, .gainers, .losers, .new:
                // Only re-sort if user explicitly chose a sort field
                return self.sortField != .marketCap || self.sortDirection != .desc
            }
        }()
        
        if shouldApplyGenericSort {
            switch self.sortField {
            case .marketCap:
                list.sort { a, b in
                    // Primary: exchange priority when viewing All segment to keep majors (e.g., BTC) first
                    if self.selectedSegment == .all {
                        let ia = MarketViewModel.exchangePriorityIndex[a.symbol.uppercased()] ?? Int.max
                        let ib = MarketViewModel.exchangePriorityIndex[b.symbol.uppercased()] ?? Int.max
                        if ia != ib { return ia < ib }
                    }
                    // Secondary: best available market cap (reported or derived)
                    let ca = self.bestCap(for: a)
                    let cb = self.bestCap(for: b)
                    if ca != cb { return self.sortDirection == .asc ? (ca < cb) : (ca > cb) }
                    // Final tie-breakers: price then symbol to keep ordering stable
                    let pa = a.priceUsd ?? 0
                    let pb = b.priceUsd ?? 0
                    if pa != pb { return self.sortDirection == .asc ? (pa < pb) : (pa > pb) }
                    return a.symbol.uppercased() < b.symbol.uppercased()
                }
            case .price:
                list.sort { a, b in
                    let pa = a.priceUsd ?? -1
                    let pb = b.priceUsd ?? -1
                    return self.sortDirection == .asc ? (pa < pb) : (pa > pb)
                }
            case .dailyChange:
                list.sort { a, b in
                    let ca = a.best24hPercent ?? -999
                    let cb = b.best24hPercent ?? -999
                    return self.sortDirection == .asc ? (ca < cb) : (ca > cb)
                }
            case .coin:
                list.sort { a, b in
                    let sa = a.symbol.uppercased()
                    let sb = b.symbol.uppercased()
                    return self.sortDirection == .asc ? (sa < sb) : (sa > sb)
                }
            case .volume:
                list.sort { a, b in
                    let va = a.totalVolume ?? a.volumeUsd24Hr ?? 0
                    let vb = b.totalVolume ?? b.volumeUsd24Hr ?? 0
                    return self.sortDirection == .asc ? (va < vb) : (va > vb)
                }
            }
        }

        // Push stablecoins below position ~25 in the All segment (after major cryptos)
        // This ensures USDT, USDC, etc. don't appear between BTC and other major coins
        if self.selectedSegment == .all && self.sortField == .marketCap && self.sortDirection == .desc {
            let stablecoinInsertPosition = 25 // Insert stablecoins after position 25
            
            // Separate stablecoins from regular coins
            var stables: [MarketCoin] = []
            var nonStables: [MarketCoin] = []
            for coin in list {
                if MarketCoin.stableSymbols.contains(coin.symbol.uppercased()) {
                    stables.append(coin)
                } else {
                    nonStables.append(coin)
                }
            }
            
            // Rebuild list: top non-stables, then stables, then remaining non-stables
            if !stables.isEmpty && nonStables.count > stablecoinInsertPosition {
                let topNonStables = Array(nonStables.prefix(stablecoinInsertPosition))
                let remainingNonStables = Array(nonStables.dropFirst(stablecoinInsertPosition))
                // Sort stables by market cap among themselves
                stables.sort { (self.bestCap(for: $0)) > (self.bestCap(for: $1)) }
                list = topNonStables + stables + remainingNonStables
            }
        }

        // Push zero-priced items to the bottom
        let nonZero = list.filter { ($0.priceUsd ?? 0) > 0 }
        let zeros   = list.filter { ($0.priceUsd ?? 0) <= 0 }
        list = nonZero + zeros

        // Early exit: if list is semantically unchanged vs currently published filteredCoins, skip mapping/publish
        if self.listSemanticallyUnchanged(new: list, old: self.filteredCoins) {
            let now2 = Date()
            let shouldComputeStats = (now2.timeIntervalSince(self.lastStatsComputeAt) >= self.minStatsComputeSpacing)
            if shouldComputeStats {
                self.refreshGlobalStatsFromBestSnapshot()
                self.lastStatsComputeAt = now2
            }
            return
        }

        if self.enableStatsLogging {
            Diagnostics.shared.log(.marketVM, "Sorted \(list.count) coins. First 3: \(list.prefix(3).map { $0.symbol }.joined(separator: ", "))", minInterval: 10)
        }

        // Assign on next run loop to avoid re-entrancy churn and compute global stats from this snapshot
        self.publishOnNextRunLoop {
            // During first minute of startup, skip extra sparkline derivation passes.
            // This avoids repeated large allocations while Home/Market are still warming up.
            let shouldDeferSparklineDerivation = Date() < self.bootstrapUntil.addingTimeInterval(60)
            let mapped = shouldDeferSparklineDerivation ? list : list.map { self.withDisplayReadySparkline($0) }
            let membershipChanged = mapped.count != self.filteredCoins.count
            let valueChanged = zip(mapped, self.filteredCoins).contains { self.coinsVisuallyDiffer($0, $1) }
            if mapped.isEmpty, self.filteredCoins.count >= self.minUsableSnapshotCount {
                // Preserve previous non-empty list to avoid blank Market screen during transient empties
            } else if membershipChanged || valueChanged {
                // Use coalesced publisher to avoid multiple updates per frame
                self.publishFilteredCoinsCoalesced(mapped)
            }
            let now2 = Date()
            let shouldComputeStats = (now2.timeIntervalSince(self.lastStatsComputeAt) >= self.minStatsComputeSpacing) || membershipChanged
            if shouldComputeStats {
                self.refreshGlobalStatsFromBestSnapshot()
                self.lastStatsComputeAt = now2
            }
        }
    }

    /// Returns a copy of the coin whose sparkline is oriented and normalized for display (resampled/smoothed when needed)
    private func withDisplayReadySparkline(_ coin: MarketCoin) -> MarketCoin {
        let display = self.displaySparkline(for: coin) // computed for views, but not written back
        return MarketCoin(
            id: coin.id,
            symbol: coin.symbol,
            name: coin.name,
            imageUrl: coin.imageUrl,
            priceUsd: coin.priceUsd,
            marketCap: coin.marketCap,
            totalVolume: coin.totalVolume,
            priceChangePercentage1hInCurrency: coin.priceChangePercentage1hInCurrency,
            priceChangePercentage24hInCurrency: coin.priceChangePercentage24hInCurrency,
            priceChangePercentage7dInCurrency: coin.priceChangePercentage7dInCurrency,
            // Use the display-ready sparkline so Watchlist and Market render identically
            sparklineIn7d: display,
            marketCapRank: coin.marketCapRank,
            maxSupply: coin.maxSupply,
            circulatingSupply: coin.circulatingSupply,
            totalSupply: coin.totalSupply
        )
    }

    /// Merge a coin with previous/live snapshots choosing the best non-zero/non-empty fields without sanitization or derivation.
    private func mergedBest(_ coin: MarketCoin, prev: MarketCoin?, live: MarketCoin?, allowLiveManager: Bool = true) -> MarketCoin {
        let latestPrice = live?.priceUsd ?? coin.priceUsd
        let prevPrice   = prev?.priceUsd ?? coin.priceUsd
        let bestPrice   = (latestPrice ?? 0) > 0 ? latestPrice : ((prevPrice ?? 0) > 0 ? prevPrice : coin.priceUsd)

        func nonZero(_ v: Double?) -> Double? { guard let x = v, abs(x) > 0.000001 else { return nil }; return x }
        func valid(_ x: Double?) -> Double? { if let v = x, v.isFinite, v > 0 { return v } else { return nil } }

        // STALE DATA FIX v23: Prefer live (Firestore) sparkline over prev (stale snapshot)
        var bestSpark: [Double] = !coin.sparklineIn7d.isEmpty ? coin.sparklineIn7d : ((live?.sparklineIn7d.isEmpty == false) ? (live?.sparklineIn7d ?? []) : (prev?.sparklineIn7d ?? []))
        if !self.isSparklineUsable(bestSpark) {
            bestSpark = self.synthesizeSparkline(for: coin)
        }

        let best1h = LivePriceManager.shared.bestChange1hPercent(for: coin)
        let best24h = LivePriceManager.shared.bestChange24hPercent(for: coin)
        let weekly = LivePriceManager.shared.bestChange7dPercent(for: coin)
            ?? coin.priceChangePercentage7dInCurrency
            ?? prev?.priceChangePercentage7dInCurrency

        let bestCap: Double? = valid(live?.marketCap) ?? valid(coin.marketCap) ?? prev?.marketCap
        let bestTotalVol: Double? = valid(live?.totalVolume ?? live?.volumeUsd24Hr) ?? valid(coin.totalVolume ?? coin.volumeUsd24Hr) ?? valid(prev?.totalVolume ?? prev?.volumeUsd24Hr)

        // Prefer current image; else previous; else live; else fallback
        var imageURL: URL? = coin.imageUrl ?? prev?.imageUrl ?? live?.imageUrl
        if imageURL == nil {
            let key = coin.symbol.lowercased()
            imageURL = MarketViewModel.fallbackImageURLs[key]
        }

        return MarketCoin(
            id: coin.id,
            symbol: coin.symbol,
            name: coin.name,
            imageUrl: imageURL,
            priceUsd: bestPrice,
            marketCap: bestCap,
            totalVolume: bestTotalVol,
            priceChangePercentage1hInCurrency: best1h,
            priceChangePercentage24hInCurrency: best24h,
            priceChangePercentage7dInCurrency: weekly,
            sparklineIn7d: bestSpark,
            marketCapRank: coin.marketCapRank ?? prev?.marketCapRank ?? live?.marketCapRank,
            maxSupply: coin.maxSupply ?? prev?.maxSupply ?? live?.maxSupply,
            circulatingSupply: coin.circulatingSupply ?? prev?.circulatingSupply ?? live?.circulatingSupply,
            totalSupply: coin.totalSupply ?? prev?.totalSupply ?? live?.totalSupply
        )
    }

    /// Returns a best-effort local snapshot of the user's watchlist using the latest known coins
    private func localWatchlistCoins() -> [MarketCoin] {
        guard !favoriteIDs.isEmpty else { return [] }
        var signatureHasher = Hasher()
        signatureHasher.combine(useLiveForWatchlist)
        signatureHasher.combine(favoriteIDs.count)
        signatureHasher.combine(favoriteOrder.count)
        signatureHasher.combine(allCoins.count)
        signatureHasher.combine(lastGoodAllCoins.count)
        signatureHasher.combine(coins.count)
        signatureHasher.combine(filteredCoins.count)
        for id in favoriteOrder { signatureHasher.combine(id) }
        for c in allCoins { signatureHasher.combine(c.id) }
        for c in lastGoodAllCoins { signatureHasher.combine(c.id) }
        for c in coins { signatureHasher.combine(c.id) }
        for c in filteredCoins { signatureHasher.combine(c.id) }
        let signature = signatureHasher.finalize()
        if signature == lastLocalWatchlistSignature {
            return lastLocalWatchlistResult
        }
        
        let base: [MarketCoin]
        if !allCoins.isEmpty { base = allCoins }
        else if !lastGoodAllCoins.isEmpty { base = lastGoodAllCoins }
        else if case .success(let s) = state { base = s }
        else { base = [] }

        let allMap   = Dictionary(allCoins.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let lastMap  = Dictionary(lastGoodAllCoins.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let liveMap  = Dictionary(coins.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // WATCHLIST INSTANT-SYNC: Also include filteredCoins for coins found via
        // Coinbase search that aren't in allCoins (obscure/unlisted coins).
        let filteredMap = Dictionary(filteredCoins.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var baseMap  = Dictionary(base.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Merge filteredCoins into baseMap (only adds missing coins, doesn't overwrite)
        for (id, coin) in filteredMap where baseMap[id] == nil {
            baseMap[id] = coin
        }

        var out: [MarketCoin] = []
        var seen = Set<String>()
        for id in favoriteOrder where favoriteIDs.contains(id) {
            if let c = baseMap[id] {
                let merged = mergedBest(c, prev: allMap[id] ?? lastMap[id], live: liveMap[id], allowLiveManager: useLiveForWatchlist)
                out.append(merged); seen.insert(id)
            }
        }
        let remaining = favoriteIDs.subtracting(seen).sorted()
        for id in remaining {
            if let c = baseMap[id] {
                let merged = mergedBest(c, prev: allMap[id] ?? lastMap[id], live: liveMap[id], allowLiveManager: useLiveForWatchlist)
                out.append(merged)
            }
        }
        lastLocalWatchlistSignature = signature
        lastLocalWatchlistResult = out
        return out
    }

    /// If any watchlist coins still have a nil or non-positive price, do a quick targeted fetch to fill them.
    private func kickstartWatchlistPricesIfNeeded() {
        guard !isKickstartingWatchlist else { return }
        // Global cooldown to prevent repeated bursts
        let now = Date()
        let isBootstrap = Date() < self.bootstrapUntil
        let effectiveCooldown = isBootstrap ? min(15, kickstartCooldown) : kickstartCooldown
        if now.timeIntervalSince(lastKickstartAt) < effectiveCooldown { return }
        // Avoid targeted fetches during degraded periods
        if isNetworkDegraded { return }
        let missing = watchlistCoins.filter { ($0.priceUsd ?? 0) <= 0 }
        guard !missing.isEmpty else { return }
        isKickstartingWatchlist = true
        // Avoid re-fetching the same IDs within 60 seconds

        let freshness: TimeInterval = (Date() < self.bootstrapUntil) ? 25 : 60
        var candidates: [String] = []
        for id in missing.map({ $0.id }) {
            if let t = recentKickstartIDs[id], now.timeIntervalSince(t) <= freshness { continue }
            candidates.append(id)
        }
        let ids = Array(candidates.prefix(5))

        // If nothing is eligible, bail out early
        guard !ids.isEmpty else { isKickstartingWatchlist = false; return }
        Task { [weak self] in
            defer { self?.isKickstartingWatchlist = false }
            self?.lastKickstartAt = Date()
            for id in ids { self?.recentKickstartIDs[id] = Date() }
            let fetched = await CryptoAPIService.shared.fetchCoins(ids: ids)
            guard let self = self, !fetched.isEmpty else { return }
            // Normalize and merge with existing watchlist to avoid regressions
            let normalized = self.normalizeCoins(self.capToMaxCoins(fetched))
            let map = Dictionary(normalized.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var updated = self.watchlistCoins
            for i in 0..<updated.count {
                let id = updated[i].id
                if let fresh = map[id] {
                    let prev = updated[i]
                    // Choose best non-zero values while preserving sparkline/icon; percent changes from LivePriceManager
                    let best1h = LivePriceManager.shared.bestChange1hPercent(for: fresh)
                    let best24h = LivePriceManager.shared.bestChange24hPercent(for: fresh)
                    let weekly = LivePriceManager.shared.bestChange7dPercent(for: fresh)
                        ?? LivePriceManager.shared.bestChange7dPercent(for: prev)
                        ?? self.snapshot7d(for: prev.id)
                    let bestPrice = (fresh.priceUsd ?? 0) > 0 ? fresh.priceUsd : prev.priceUsd
                    let bestCap = (fresh.marketCap ?? 0) > 0 ? fresh.marketCap : prev.marketCap
                    let bestVol = (fresh.totalVolume ?? fresh.volumeUsd24Hr ?? 0) > 0 ? (fresh.totalVolume ?? fresh.volumeUsd24Hr) : (prev.totalVolume ?? prev.volumeUsd24Hr)
                    let rebuilt = MarketCoin(
                        id: prev.id,
                        symbol: prev.symbol,
                        name: prev.name,
                        imageUrl: prev.imageUrl ?? fresh.imageUrl,
                        priceUsd: bestPrice,
                        marketCap: bestCap,
                        totalVolume: bestVol,
                        priceChangePercentage1hInCurrency: best1h,
                        priceChangePercentage24hInCurrency: best24h,
                        priceChangePercentage7dInCurrency: weekly,
                        sparklineIn7d: prev.sparklineIn7d.isEmpty ? fresh.sparklineIn7d : prev.sparklineIn7d,
                        marketCapRank: prev.marketCapRank ?? fresh.marketCapRank,
                        maxSupply: prev.maxSupply ?? fresh.maxSupply,
                        circulatingSupply: prev.circulatingSupply ?? fresh.circulatingSupply,
                        totalSupply: prev.totalSupply ?? fresh.totalSupply
                    )
                    updated[i] = rebuilt
                }
            }
            await MainActor.run {
                self.publishWatchlistCoinsCoalesced(updated)
            }
        }
    }
    /// Loads or refreshes the watchlist data using the best locally available snapshots, then kickstarts prices if needed.
    func loadWatchlistData() async {
        let local = self.localWatchlistCoins()
        await MainActor.run {
            self.publishOnNextRunLoop {
                self.publishWatchlistCoinsCoalesced(local)
                self.kickstartWatchlistPricesIfNeeded()
            }
        }
    }
    
    /// WATCHLIST INSTANT-SYNC: Immediate variant of loadWatchlistData that bypasses coalescing.
    /// Used when the user explicitly adds/removes a favorite — the watchlist should update instantly
    /// without the 0.5s coalescing delay that's appropriate for background live-price ticks.
    @MainActor func loadWatchlistDataImmediate() async {
        let local = self.localWatchlistCoins()
        guard !local.isEmpty || favoriteIDs.isEmpty else { return }
        // Cancel any pending coalesced publish — we're about to publish fresh data right now
        pendingWatchlistPublish?.cancel()
        pendingWatchlistPublish = nil
        // FIX: Set isSanitizingWatchlist to prevent the didSet from re-running the full
        // updateWatchlistCoins pipeline. localWatchlistCoins() already produced the correct
        // sanitized, ordered list — re-processing it in didSet is redundant heavy work that
        // re-computes localWatchlistCoins() a second time and then sets watchlistCoins again
        // via publishWatchlistCoinsCoalesced, creating a feedback loop.
        isSanitizingWatchlist = true
        self.watchlistCoins = local
        isSanitizingWatchlist = false
        self.primeLivePercents(for: local)
        self.lastWatchlistPublishAt = Date()
        self.kickstartWatchlistPricesIfNeeded()
    }

    /// Debug logging gated by enableStatsLogging
    private func log(_ message: String) {
        if enableStatsLogging {
            Diagnostics.shared.log(.marketVM, message)
        }
    }
    /// Diagnostic logging gated by enableDiagLogs
    private func diag(_ message: String) {
        if enableDiagLogs {
            Diagnostics.shared.logBucketed(.marketVM, key: "MarketVM.diag", capacity: 10, refillPerSec: 2, message)
        }
    }
    var isDiagLoggingEnabled: Bool { enableDiagLogs }

    // MARK: - Helpers (added)

    /// Warm up LivePriceManager sidecar caches for 1h/24h/7d so UI sees live values quickly.
    /// STALE DATA FIX: Skip priming during the startup grace period when coins only have stale
    /// sparkline data and no fresh provider percentages. Priming during this window would seed the
    /// sidecar cache with inaccurate sparkline-derived values (e.g., red -3% when market is actually
    /// green +2%), causing the watchlist to flash wrong colors until fresh API data replaces them.
    /// After the grace period, coins will have fresh Firestore/API data and priming is safe.
    private func primeLivePercents(for list: [MarketCoin]) {
        guard !list.isEmpty else { return }
        
        // STALE DATA FIX: Don't prime during startup grace period — coins have stale sparklines
        // and nil provider percentages. Priming would derive wrong values from stale data and
        // cache them in the sidecar, causing red→green flashing on cold start.
        // LivePriceManager's bestChange*Percent() already guards against caching during grace
        // period, but skipping the entire priming loop avoids unnecessary work and potential
        // edge cases where derived values slip through.
        let manager = LivePriceManager.shared
        guard manager.hasReceivedFreshData else {
            // MEMORY FIX: Limit retry chain to maxPrimeRetries to prevent unbounded Task creation.
            // Previously, if hasReceivedFreshData never became true (network issues), this would
            // create an infinite chain of Tasks, each capturing a copy of the coin array.
            guard primeRetryCount < maxPrimeRetries else { return }
            primeRetryCount += 1
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 4_000_000_000) // 4 seconds
                guard let self = self else { return }
                self.primeLivePercents(for: self.allCoins.isEmpty ? list : Array(self.allCoins.prefix(80)))
            }
            return
        }
        // Reset retry count on success
        primeRetryCount = 0
        
        // Build a lightweight key from the first up-to-80 ids to detect meaningful changes
        let subset = Array(list.prefix(80))
        var hasher = Hasher()
        for c in subset { hasher.combine(c.id) }
        let key = hasher.finalize()

        let now = Date()
        let elapsed = now.timeIntervalSince(lastPrimeAt)
        // Skip if we recently primed with the same set
        if elapsed < minPrimeSpacing && key == lastPrimeKey { return }
        // Avoid overlapping priming tasks
        if isPrimingPercents { return }
        isPrimingPercents = true
        lastPrimeKey = key

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            for c in subset {
                _ = manager.bestChange1hPercent(for: c)
                _ = manager.bestChange24hPercent(for: c.symbol)
                _ = manager.bestChange7dPercent(for: c)
            }
            self.lastPrimeAt = Date()
            self.isPrimingPercents = false
        }
    }

    /// Returns the best 24h percent change and a short source tag ("live", "prov", "engine", or "—") for debug overlays.
    func change24hWithSource(for coin: MarketCoin) -> (value: Double?, source: String) {
        if let v = LivePriceManager.shared.bestChange24hPercent(for: coin.symbol) {
            return (v, "live")
        }
        if let v = coin.priceChangePercentage24hInCurrency {
            return (v, "prov")
        }
        let series = self.bestSparkline(for: coin.id, current: coin.sparklineIn7d)
        if let v = self.bestDerivedChange(id: coin.id, series: series, hours: 24) {
            return (v, "engine")
        }
        return (nil, "—")
    }

    /// Returns live/displayed/pending prices for a coin. `pending` is non-nil when live != displayed (beyond tiny jitter).
    func pricesForDebug(for coin: MarketCoin) -> (live: Double?, displayed: Double?, pending: Double?) {
        let live = self.coins.first(where: { $0.id == coin.id })?.priceUsd
        let displayed = coin.priceUsd
        var pending: Double? = nil
        if let l = live, let d = displayed, !self.approxEqual(l, d, relTol: 5e-4, absTol: 1e-6) {
            pending = l
        }
        return (live, displayed, pending)
    }

    /// Returns a best-effort 24h volume and its source tag ("prov", "live", or "—").
    func volumeWithSource(for coin: MarketCoin) -> (value: Double?, source: String) {
        func valid(_ x: Double?) -> Double? { if let v = x, v.isFinite, v > 0 { return v } else { return nil } }
        if let v = valid(coin.totalVolume ?? coin.volumeUsd24Hr) {
            return (v, "prov")
        }
        if let live = self.coins.first(where: { $0.id == coin.id }), let v = valid(live.totalVolume ?? live.volumeUsd24Hr) {
            return (v, "live")
        }
        return (nil, "—")
    }

    // MARK: - Missing Helper Implementations (restored)

    /// Chooses the best available sparkline for a coin id, preferring live -> allCoins -> lastGood -> current.
    private func bestSparkline(for id: String, current: [Double]) -> [Double] {
        func usable(_ s: [Double]) -> [Double]? {
            let filtered = s.filter { $0.isFinite && $0 > 0 }
            return filtered.count >= 2 ? filtered : nil
        }
        if let s = coins.first(where: { $0.id == id })?.sparklineIn7d, let u = usable(s) { return u }
        if let s = allCoins.first(where: { $0.id == id })?.sparklineIn7d, let u = usable(s) { return u }
        if let s = lastGoodAllCoins.first(where: { $0.id == id })?.sparklineIn7d, let u = usable(s) { return u }
        if let u = usable(current) { return u }
        return []
    }

    /// Returns true when the series appears to be on a compatible scale with the provided spot price.
    private func isScaleCompatibleWithPrice(_ arr: [Double], price: Double?) -> Bool {
        guard let p = price, p.isFinite, p > 0 else { return false }
        let vals = arr.filter { $0.isFinite && $0 > 0 }
        guard !vals.isEmpty, let minV = vals.min(), let maxV = vals.max() else { return false }
        // Accept if price lies reasonably within the series envelope with slack
        if p >= minV * 0.8 && p <= maxV * 1.2 { return true }
        // Otherwise, compare last sample relative error
        if let last = vals.last {
            let rel = abs(last - p) / max(1e-9, max(abs(last), abs(p)))
            return rel < 0.25
        }
        return false
    }

    /// Anchors a series so that its last value matches the provided spot price (when valid).
    private func anchorSeriesToPrice(_ series: [Double], price: Double?) -> [Double] {
        guard let p = price, p.isFinite, p > 0 else { return series }
        guard let last = series.last, last.isFinite, last > 0 else { return series }
        let scale = p / last
        guard scale.isFinite, scale > 0 else { return series }
        return series.map { v in
            guard v.isFinite && v > 0 else { return v }
            return max(1e-7, v * scale)
        }
    }

    /// PRICE SANITY: Minimum price thresholds for well-known coins.
    /// Prevents data pipeline bugs from corrupting the price book with obviously wrong values.
    /// Thresholds are set conservatively low — well below any realistic crash scenario.
    private static let minPriceThresholds: [String: Double] = [
        "bitcoin": 1000,
        "ethereum": 50,
        "binancecoin": 10,
        "solana": 1,
    ]
    
    /// Returns true if the price is plausible for the given coin ID.
    private static func passesPriceSanity(_ price: Double, for coinId: String) -> Bool {
        guard let threshold = minPriceThresholds[coinId] else { return true }
        return price > threshold
    }

    /// Rebuilds quick-lookup books for prices and volumes by id and symbol from available snapshots.
    /// PRICE SANITY FIX: Rejects obviously wrong prices for well-known coins (e.g., BTC at ~$1).
    private func rebuildPriceBooks() {
        var idPrice: [String: Double] = [:]
        var symPrice: [String: Double] = [:]
        var idVol: [String: Double] = [:]
        var symVol: [String: Double] = [:]
        func valid(_ x: Double?) -> Double? { if let v = x, v.isFinite, v > 0 { return v } else { return nil } }
        func consider(_ c: MarketCoin) {
            if let p = valid(c.priceUsd) {
                // PRICE SANITY: Reject obviously wrong prices for well-known coins
                guard Self.passesPriceSanity(p, for: c.id) else {
                    #if DEBUG
                    print("⚠️ [rebuildPriceBooks] Rejected \(c.id) price $\(String(format: "%.4f", p)) — below sanity threshold")
                    #endif
                    return
                }
                idPrice[c.id] = p
                let key = c.symbol.uppercased()
                if let existing = symPrice[key] {
                    symPrice[key] = max(existing, p)
                } else {
                    symPrice[key] = p
                }
            }
            if let v = valid(c.totalVolume ?? c.volumeUsd24Hr) {
                idVol[c.id] = v
                let key = c.symbol.uppercased()
                if let existing = symVol[key] {
                    symVol[key] = max(existing, v)
                } else {
                    symVol[key] = v
                }
            }
        }
        for c in coins { consider(c) }
        for c in allCoins { consider(c) }
        for c in lastGoodAllCoins { consider(c) }
        self.idPriceBook = idPrice
        self.symbolPriceBook = symPrice
        self.idVolumeBook = idVol
        self.symbolVolumeBook = symVol
    }

    /// Trims orientation/display caches to stay within budget.
    /// CACHE FIX: Now uses timestamps for smarter trimming of both caches.
    private func enforceDisplayCacheBudget() {
        let now = Date()
        
        // First pass: remove expired entries proactively
        // Remove expired orientation cache entries
        let expiredOrientationKeys = orientationCacheAt.filter { now.timeIntervalSince($0.value) > orientationStickinessTTL }.map { $0.key }
        for key in expiredOrientationKeys {
            orientationCache.removeValue(forKey: key)
            orientationCacheAt.removeValue(forKey: key)
            orientationSeriesFP.removeValue(forKey: key)
        }
        
        // Remove expired display series cache entries
        let expiredDisplayKeys = displaySeriesCacheAt.filter { now.timeIntervalSince($0.value) > displaySeriesCacheTTL }.map { $0.key }
        for key in expiredDisplayKeys {
            displaySeriesCache.removeValue(forKey: key)
            displaySeriesCacheKey.removeValue(forKey: key)
            displaySeriesCacheAt.removeValue(forKey: key)
        }
        
        // Second pass: trim by age if still over budget
        // Trim orientation cache by age using orientationCacheAt
        if orientationCache.count > maxOrientationCacheEntries {
            let excess = orientationCache.count - maxOrientationCacheEntries
            let sorted = orientationCacheAt.sorted { $0.value < $1.value }
            for (k, _) in sorted.prefix(excess) {
                orientationCache.removeValue(forKey: k)
                orientationCacheAt.removeValue(forKey: k)
                orientationSeriesFP.removeValue(forKey: k)
            }
        }
        
        // Trim display series cache by age using displaySeriesCacheAt
        if displaySeriesCache.count > maxDisplayCacheEntries {
            let excess = displaySeriesCache.count - maxDisplayCacheEntries
            let sorted = displaySeriesCacheAt.sorted { $0.value < $1.value }
            for (k, _) in sorted.prefix(excess) {
                displaySeriesCache.removeValue(forKey: k)
                displaySeriesCacheKey.removeValue(forKey: k)
                displaySeriesCacheAt.removeValue(forKey: k)
            }
        }
    }

    // MARK: - Orientation Cache Management
    
    /// Clears all orientation and display caches to force re-evaluation with updated logic.
    /// FIX: Added to support cache clearing after orientation logic changes.
    /// This ensures sparklines get re-oriented using the corrected algorithm.
    func clearAllOrientationCaches() {
        // Clear local ViewModel caches
        orientationCache.removeAll()
        orientationCacheAt.removeAll()
        orientationSeriesFP.removeAll()
        displaySeriesCache.removeAll()
        displaySeriesCacheKey.removeAll()
        displaySeriesCacheAt.removeAll()
        
        // Clear the MarketMetricsEngine global cache
        MarketMetricsEngine.resetOrientationCache()
        
        diag("Diag: Cleared all orientation caches for re-evaluation")
    }
    
    /// Clears orientation cache for a specific coin.
    /// Use when a single coin's data seems incorrectly oriented.
    func clearOrientationCache(for coinId: String) {
        orientationCache.removeValue(forKey: coinId)
        orientationCacheAt.removeValue(forKey: coinId)
        orientationSeriesFP.removeValue(forKey: coinId)
        displaySeriesCache.removeValue(forKey: coinId)
        displaySeriesCacheKey.removeValue(forKey: coinId)
        displaySeriesCacheAt.removeValue(forKey: coinId)
        
        // Clear the MarketMetricsEngine cache for this coin
        MarketMetricsEngine.resetOrientationCache(for: coinId)
        
        diag("Diag: Cleared orientation cache for \(coinId)")
    }

    /// Returns a snapshot 7d percent change for a coin id from local snapshots.
    private func snapshot7d(for id: String) -> Double? {
        if let v = allCoins.first(where: { $0.id == id })?.priceChangePercentage7dInCurrency { return v }
        if let v = lastGoodAllCoins.first(where: { $0.id == id })?.priceChangePercentage7dInCurrency { return v }
        if case .success(let snap) = state, let v = snap.first(where: { $0.id == id })?.priceChangePercentage7dInCurrency { return v }
        return nil
    }

    /// Loads a cached global stats snapshot (modern or legacy) if available.
    private func loadAnyGlobalSnapshot() -> GlobalStatsSnapshot? {
        if let snap: GlobalStatsSnapshot = CacheManager.shared.load(GlobalStatsSnapshot.self, from: "market_vm_global_stats.json") {
            return snap
        }
        if let legacy: LegacyGlobalStatsSnapshot = CacheManager.shared.load(LegacyGlobalStatsSnapshot.self, from: "global_cache.json") {
            var published: Date = .distantPast
            let s = legacy.published_at
            let fmt = Self._isoFormatter
            if let d = fmt.date(from: s) { published = d }
            return GlobalStatsSnapshot(
                marketCap: legacy.total_market_cap,
                volume24h: legacy.total_volume_24h,
                btcDominance: legacy.btc_dominance,
                ethDominance: legacy.eth_dominance,
                change24hPercent: nil, // Legacy format doesn't include this
                publishedAt: published
            )
        }
        return nil
    }

    // MARK: - Coalesced Publishing (restored)
    private var lastFilteredPublishAt: Date = .distantPast
    private var pendingFilteredPublish: DispatchWorkItem?
    // PERFORMANCE FIX: Increased from 0.16s to 0.5s - market list doesn't need 6Hz updates
    private let minFilteredPublishSpacing: TimeInterval = 0.5 // 2 updates per second max

    private var lastWatchlistPublishAt: Date = .distantPast
    private var pendingWatchlistPublish: DispatchWorkItem?
    // PERFORMANCE FIX: Increased from 0.16s to 0.5s - watchlist doesn't need 6Hz updates
    private let minWatchlistPublishSpacing: TimeInterval = 0.5 // 2 updates per second max

    private func publishFilteredCoinsCoalesced(_ new: [MarketCoin]) {
        pendingFilteredPublish?.cancel()
        let now = Date()
        let elapsed = now.timeIntervalSince(lastFilteredPublishAt)
        
        // PERFORMANCE FIX v14: Skip publishing during scroll to prevent UI jank
        // Defer to later when scroll ends
        if ScrollStateManager.shared.shouldBlockHeavyOperation() {
            // Schedule for later when scroll ends (check again in 1 second)
            let work = DispatchWorkItem { [weak self, new] in
                self?.publishFilteredCoinsCoalesced(new)
            }
            pendingFilteredPublish = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
            return
        }
        
        let assign: () -> Void = { [weak self] in
            guard let self = self else { return }
            self.filteredCoins = new
            self.primeLivePercents(for: new)
            self.lastFilteredPublishAt = Date()
            self.lastEngineRecomputeAt = Date()
        }
        if elapsed >= minFilteredPublishSpacing {
            assign()
        } else {
            let delay = minFilteredPublishSpacing - elapsed
            let work = DispatchWorkItem(block: assign)
            pendingFilteredPublish = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private func publishWatchlistCoinsCoalesced(_ new: [MarketCoin]) {
        pendingWatchlistPublish?.cancel()
        let now = Date()
        let elapsed = now.timeIntervalSince(lastWatchlistPublishAt)
        
        // PERFORMANCE FIX v14: Skip publishing during scroll to prevent UI jank
        // Defer to later when scroll ends
        if ScrollStateManager.shared.shouldBlockHeavyOperation() {
            // Schedule for later when scroll ends (check again in 1 second)
            let work = DispatchWorkItem { [weak self, new] in
                self?.publishWatchlistCoinsCoalesced(new)
            }
            pendingWatchlistPublish = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
            return
        }
        
        let assign: () -> Void = { [weak self] in
            guard let self = self else { return }
            self.watchlistCoins = new
            self.primeLivePercents(for: new)
            self.lastWatchlistPublishAt = Date()
        }
        if elapsed >= minWatchlistPublishSpacing {
            assign()
        } else {
            let delay = minWatchlistPublishSpacing - elapsed
            let work = DispatchWorkItem(block: assign)
            pendingWatchlistPublish = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    // MARK: - Baseline Enrichment (restored)
    private var lastBaselineFetchAt: Date = .distantPast
    private let baselineFetchCooldown: TimeInterval = 60 * 5
    private var baselineFetchInFlight: Bool = false
    static let baselineGeckoIDs: [String] = [
        "bitcoin", "ethereum", "binancecoin", "ripple", "solana", "dogecoin", "polkadot", "matic-network",
        "shiba-inu", "tron", "litecoin", "chainlink", "stellar", "cardano", "vechain", "uniswap",
        "okb", "filecoin", "cosmos", "algorand", "theta-token", "monero", "tezos", "bitcoin-cash",
        "hedera-hashgraph", "internet-computer", "quant-network", "decentraland", "elrond-erd-2", "aave",
        "the-sandbox", "fantom", "celsius-degree-token", "zilliqa", "eos", "huobi-token", "flow",
        "compound", "maker", "theta-fuel", "neo", "waves", "dash", "helium", "kusama",
        "enjincoin", "iota", "pancakeswap-token", "chiliz", "bitcoin-sv", "yearn-finance", "basic-attention-token",
        "kucoin-shares", "amp-token", "decred", "havven", "chiliz", "icon", "huobi-token"
    ]

    private func ensureBaselineSnapshotIfNeeded(minCount: Int = 250) {
        // MEMORY FIX v11: Block during startup freeze window.
        // ensureBaselineSnapshotIfNeeded directly sets allCoins (@Published), which triggers
        // objectWillChange and cascading view re-renders. During the startup freeze,
        // the initial cached data is sufficient for display.
        if hasCompletedInitialFilterPass,
           let freezeEnd = startupFilterFreezeUntil,
           Date() < freezeEnd {
            return
        }
        
        // MEMORY FIX v6: minCount must never exceed maxAllCoinsCount.
        // Previously minCount was 60 while allCoins was capped at 50. The guard below
        // could NEVER return early, causing ensureBaseline → applyAllFiltersAndSort →
        // ensureBaseline infinite recursion that allocated GB of memory and crashed the app.
        let effectiveMinCount = min(minCount, Self.maxAllCoinsCount)
        
        // If we already have enough coins, nothing to do
        if self.allCoins.count >= effectiveMinCount { return }
        // Avoid overlapping enrichments
        if baselineFetchInFlight { return }

        var ids = Array(Set(MarketViewModel.baselineGeckoIDs + Array(self.favoriteIDs)))
        if ids.count > 80 { ids = Array(ids.prefix(80)) }

        // 1) Immediate local adoption path (no network): try cache, bundled, then union of available sources
        var adopted = false
        // MEMORY FIX v6: Track whether any local path changed allCoins so we schedule ONE deferred filter update
        var didAdoptLocally = false

        // Try cached snapshot first (Documents only - no bundle fallback for stale data)
        // MEMORY FIX v6: Only attempt adoption if allCoins is still below cap.
        // Previously, bundled/union paths with >50 coins always passed `normalized.count > allCoins.count`
        // (e.g. 57 > 50) even though allCoins would be capped back to 50 — creating infinite work.
        if self.allCoins.count < Self.maxAllCoinsCount,
           let saved: [MarketCoin] = CacheManager.shared.loadFromDocumentsOnly([MarketCoin].self, from: "coins_cache.json"), !saved.isEmpty {
            let normalized = self.normalizeCoins(self.capToMaxCoins(saved))
            if normalized.count > self.allCoins.count {
                var ordered = normalized
                ordered.sort { self.bestCap(for: $0) > self.bestCap(for: $1) }
                self.allCoins = ordered
                self.lastGoodAllCoins = ordered
                self.rebuildPriceBooks()
                self.showSnapshotImmediately()
                self.diag("Diag: Adopted cached baseline snapshot (count=\(ordered.count))")
                adopted = self.allCoins.count >= effectiveMinCount
                didAdoptLocally = true
            }
        }

        // No bundled baseline fallback in live-integrity mode.

        // Try union of whatever we already have (live/lastGood/state)
        if !adopted && (self.allCoins.count < effectiveMinCount) && (self.allCoins.count < Self.maxAllCoinsCount) {
            var map: [String: MarketCoin] = [:]
            for c in self.coins { map[c.id] = c }
            for c in self.lastGoodAllCoins { if map[c.id] == nil { map[c.id] = c } }
            if case .success(let snap) = self.state {
                for c in snap { if map[c.id] == nil { map[c.id] = c } }
            }
            var union = Array(map.values)
            if !union.isEmpty {
                union = self.capToMaxCoins(self.normalizeCoins(self.capToMaxCoins(union)))
                union.sort { self.bestCap(for: $0) > self.bestCap(for: $1) }
                if union.count >= self.minUsableSnapshotCount && union.count > self.allCoins.count {
                    self.allCoins = union
                    self.lastGoodAllCoins = union
                    if union.count >= self.minUsableSnapshotCount { self.saveCoinsCacheCapped(union) }
                    self.rebuildPriceBooks()
                    self.showSnapshotImmediately()
                    self.diag("Diag: Adopted union baseline snapshot (count=\(union.count))")
                    adopted = true
                    didAdoptLocally = true
                } else {
                    let nowLog = Date()
                    if nowLog.timeIntervalSince(self.lastUnionBaselineLogAt) >= 30 {
                        self.diag("Diag: Skipping union baseline snapshot (count=\(union.count)) — currentAll=\(self.allCoins.count)")
                        self.lastUnionBaselineLogAt = nowLog
                    }
                }
            }
        }
        
        // MEMORY FIX v6: Schedule ONE deferred filter update instead of calling applyAllFiltersAndSort()
        // synchronously from each adoption path. The synchronous calls created infinite recursion:
        // ensureBaseline → applyAllFiltersAndSort → ensureBaseline → applyAllFiltersAndSort → ...
        // Using scheduleApplyFilters breaks the cycle because it cancels any pending work
        // and defers to the next run loop.
        if didAdoptLocally {
            self.scheduleApplyFilters(delay: 0.0)
        }

        // Quiet-start: if we already have a minimally usable local list, postpone the network enrichment until after the first frame
        if Date() < self.firstFrameQuietUntil, self.allCoins.count >= self.minUsableSnapshotCount, !self.hasScheduledPostQuietBaseline {
            self.hasScheduledPostQuietBaseline = true
            let delay = max(0, self.firstFrameQuietUntil.timeIntervalSince(Date()))
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.ensureBaselineSnapshotIfNeeded(minCount: effectiveMinCount)
            }
            return
        }

        // If we still want to enrich from the network, do it in the background with cooldown.
        let now = Date()
        let smallList = self.allCoins.count < max(10, effectiveMinCount/3)
        let early = now < self.bootstrapUntil.addingTimeInterval(180)
        let effectiveCooldown: TimeInterval
        if early {
            effectiveCooldown = smallList ? 12.0 : 30.0
        } else {
            effectiveCooldown = smallList ? 25.0 : baselineFetchCooldown
        }
        if now.timeIntervalSince(lastBaselineFetchAt) < effectiveCooldown { return }
        lastBaselineFetchAt = now
        // Respect degraded mode for the remote step only
        if isNetworkDegraded && self.allCoins.count >= effectiveMinCount/10 { return }

        baselineFetchInFlight = true
        Task { [weak self] in
            guard let self = self else { return }
            let fetched = await CryptoAPIService.shared.fetchCoins(ids: ids)
            var normalized: [MarketCoin] = []
            if fetched.isEmpty {
                // Try a Gecko markets fallback when the normal path returned nothing
                let fallback = await self.fetchTopMarketsFromGeckoFallback(limit: Self.maxAllCoinsCount)
                normalized = fallback
            } else {
                normalized = self.normalizeCoins(self.capToMaxCoins(fetched))
            }
            if normalized.isEmpty {
                // Final attempt: Gecko markets fallback even if we had some network degradation
                let fallback = await self.fetchTopMarketsFromGeckoFallback(limit: Self.maxAllCoinsCount)
                if fallback.isEmpty {
                    await MainActor.run { self.baselineFetchInFlight = false }
                    return
                }
                normalized = fallback
            }
            var mergedMap: [String: MarketCoin] = Dictionary(normalized.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for c in self.allCoins { if mergedMap[c.id] == nil { mergedMap[c.id] = c } }
            var merged = Array(mergedMap.values)
            if merged.count < effectiveMinCount {
                let geckoTop = await self.fetchTopMarketsFromGeckoFallback(limit: Self.maxAllCoinsCount)
                if !geckoTop.isEmpty {
                    for c in geckoTop { if mergedMap[c.id] == nil { mergedMap[c.id] = c } }
                    merged = Array(mergedMap.values)
                }
            }
            merged = self.capToMaxCoins(merged)
            merged.sort { self.bestCap(for: $0) > self.bestCap(for: $1) }
            await MainActor.run {
                self.allCoins = merged
                WidgetBridge.syncWatchlist(from: merged)
                self.lastGoodAllCoins = merged
                if merged.count >= self.minUsableSnapshotCount { self.saveCoinsCacheCapped(merged) }
                self.rebuildPriceBooks()
                // MEMORY FIX v6: Use deferred filter update instead of synchronous call
                // to prevent re-entrant recursion from network completion path
                self.scheduleApplyFilters(delay: 0.0)
                self.diag("Diag: Enriched baseline snapshot from network (count=\(merged.count))")
            }
            await MainActor.run { self.baselineFetchInFlight = false }
        }
    }

    /// Lightweight fallback to fetch top markets from CoinGecko without specifying IDs.
    private func fetchTopMarketsFromGeckoFallback(limit: Int = 250) async -> [MarketCoin] {
        // Respect degraded mode only if we already have a reasonably sized list; otherwise, still try once.
        if isNetworkDegraded && self.allCoins.count >= max(10, limit/5) { return [] }
        // FIX: Check coordinator before CoinGecko requests
        if !APIRequestCoordinator.shared.canMakeRequest(for: .coinGecko) {
            self.diag("Diag: Skipping Gecko markets (blocked by coordinator)")
            return []
        }
        if Date() < geckoRateLimitedUntil {
            if Date().timeIntervalSince(self.lastGeckoSkipLogAt) >= 60 {
                self.diag("Diag: Skipping Gecko markets (rate-limited until \(geckoRateLimitedUntil))")
                self.lastGeckoSkipLogAt = Date()
            }
            return []
        }
        // FIX: Record CoinGecko request with coordinator
        APIRequestCoordinator.shared.recordRequest(for: .coinGecko)

        func attempt(perPage: Int, timeout: TimeInterval) async -> [MarketCoin] {
            let curr = CurrencyManager.apiValue
            guard let url = URL(string: "https://api.coingecko.com/api/v3/coins/markets?vs_currency=\(curr)&order=market_cap_desc&per_page=\(perPage)&page=1&sparkline=true&price_change_percentage=1h,24h,7d") else { return [] }
            var req = APIConfig.coinGeckoRequest(url: url)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            req.timeoutInterval = timeout
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, http.statusCode == 429 {
                    await MainActor.run { self.recordGeckoRateLimit(reason: "HTTP 429 from /coins/markets") }
                    return []
                }
                let dec = JSONDecoder()
                dec.keyDecodingStrategy = .convertFromSnakeCase
                let gecko = try dec.decode([CoinGeckoCoin].self, from: data)
                guard !gecko.isEmpty else { return [] }
                let mapped = gecko.map { MarketCoin(gecko: $0) }
                let normalized = self.normalizeCoins(self.capToMaxCoins(mapped))
                await MainActor.run { self.recordNetworkSuccess(); self.clearGeckoPenaltyOnSuccess() }
                return normalized.sorted { self.bestCap(for: $0) > self.bestCap(for: $1) }
            } catch {
                self.recordNetworkFailure(error)
                return []
            }
        }

        // Primary attempt with full requested limit and reasonable timeout
        // CoinGecko can handle up to 250 per page reliably
        let perPagePrimary = min(Self.maxAllCoinsCount, limit)
        var result = await attempt(perPage: perPagePrimary, timeout: 15)
        if !result.isEmpty { return result }

        // Fallback: moderate page size with shorter timeout
        let perPageFallback = min(Self.maxAllCoinsCount, limit)
        result = await attempt(perPage: perPageFallback, timeout: 8)
        if !result.isEmpty { return result }

        // Final smaller attempt before giving up
        let perPageSmall = min(50, Self.maxAllCoinsCount)
        return await attempt(perPage: perPageSmall, timeout: 5)
    }

    // MARK: - Derivation Helpers (restored)
    // SPARKLINE INVERSION FIX: Removed reversal logic - API data is always chronological [oldest → newest].
    private func chronologicalSeriesForDerivation(id: String, series: [Double], spot: Double?) -> [Double] {
        return series.filter { $0.isFinite && $0 > 0 }
    }

    // MARK: - Cache Loading Helpers
    
    /// REFACTOR: Shared helper to load coins from real cached snapshot only.
    /// This consolidates duplicate code from loadAllData() and loadFromCacheOnly().
    private func adoptCachedOrBundledSnapshot() {
        // Adopt cached snapshot if available (Documents only - no bundle fallback)
        // STALE DATA FIX: Use loadFromDocumentsOnly to prevent stale bundled data
        // from being treated as "recently fetched" with preserved percentages.
        // Documents cache contains REAL data from a previous API call.
        if self.allCoins.isEmpty,
           let saved: [MarketCoin] = CacheManager.shared.loadFromDocumentsOnly([MarketCoin].self, from: "coins_cache.json"),
           saved.count >= self.minUsableSnapshotCount {
            // FIX v25: PRESERVE cached percentage values from Documents cache.
            // These are from the last CoinGecko API fetch (minutes/hours old)
            // and are directionally correct. They're replaced by fresh Firestore/API data
            // within 1-2 seconds anyway. Showing a slightly stale percentage is far more
            // professional than showing dashes or wrong sparkline colors.
            let normalized = self.normalizeCoins(self.capToMaxCoins(saved))
            self.allCoins = normalized
            self.lastGoodAllCoins = normalized
            self.state = .success(normalized)
            // MEMORY FIX v7: Deferred scheduling
            self.scheduleApplyFilters(delay: 0.0)
            self.showSnapshotImmediately()
        }
        
        // No bundled coin payload fallback in live-integrity mode.
    }
    
    // MARK: - Startup Load (restored)
    func loadAllData() async {
        // PERFORMANCE: Guard to prevent duplicate concurrent loads
        // This prevents cascading API requests when multiple views trigger loads simultaneously
        guard !isLoadingAllData else {
            diag("Diag: loadAllData() skipped - already in progress")
            return
        }
        
        // MEMORY FIX v12: During the startup freeze window, the initial filter pass has
        // already populated allCoins from cache. Allowing loadAllData() to run creates
        // redundant ensureBaseline calls and allCoins assignments that trigger the
        // @Published cascade (objectWillChange → SwiftUI re-render → MB of temp allocations).
        // Allow only the first call (before initial filter pass) and block during the freeze.
        if hasCompletedInitialFilterPass,
           let freezeEnd = startupFilterFreezeUntil,
           Date() < freezeEnd {
            diag("Diag: loadAllData() deferred — startup freeze active")
            return
        }
        
        isLoadingAllData = true
        // RACE CONDITION FIX: defer in async functions correctly executes when the function
        // completes, including after all awaits. This is the proper pattern for cleanup.
        defer { isLoadingAllData = false }
        
        // MEMORY FIX: If loadFromCacheOnly already populated allCoins with 50+ coins,
        // skip the redundant cache loading and price book rebuilding. This prevents
        // duplicate normalizeCoins/rebuildPriceBooks calls that create temporary arrays.
        let alreadyHasData = self.allCoins.count >= Self.maxAllCoinsCount
        
        if !alreadyHasData {
            // Build books from whatever we have and kick the first filter pass
            self.rebuildPriceBooks()
            self.scheduleApplyFilters(delay: 0.0)

            // REFACTOR: Use shared cache loading logic
            adoptCachedOrBundledSnapshot()
            
            // If still undersized, proactively fetch a baseline snapshot in the background
            // MEMORY FIX v6: minCount must match maxAllCoinsCount to avoid infinite recursion
            if self.allCoins.count < Self.maxAllCoinsCount {
                self.ensureBaselineSnapshotIfNeeded(minCount: Self.maxAllCoinsCount)
            }
        }

        // Force an early global stats fetch so Home/Market stats don't show zeros
        self.fetchGlobalStatsFromGecko(force: true)

        // Seed watchlist from the best local sources, then kickstart prices if needed
        await self.loadWatchlistData()
        self.primeLivePercents(for: self.watchlistCoins)

        // Refresh global stats from the best snapshot we currently have
        self.refreshGlobalStatsFromBestSnapshot()

        // Opportunistically backfill missing sparklines for a subset of coins
        self.backfillMissingSparklines(limit: 10)
    }
    
    /// MEMORY FIX v4: Aggressively trim memory when the watchdog detects high usage.
    /// Clears non-essential cached data while preserving the minimum needed for display.
    func trimMemory() {
        // Clear the lastGoodAllCoins backup (can be repopulated from current data)
        lastGoodAllCoins = []
        // Clear bundled coins static cache
        Self._cachedBundledCoins = nil
        // MEMORY FIX v4: Also clear display/orientation caches (~500 KB savings)
        displaySeriesCache.removeAll()
        displaySeriesCacheKey.removeAll()
        displaySeriesCacheAt.removeAll()
        orientationCache.removeAll()
        orientationCacheAt.removeAll()
        orientationSeriesFP.removeAll()
        // Clear price/volume books (rebuilt on next data update)
        idPriceBook.removeAll()
        symbolPriceBook.removeAll()
        idVolumeBook.removeAll()
        symbolVolumeBook.removeAll()
    }
    
    /// MEMORY FIX v14: Aggressive memory trim — clears the main @Published coin arrays.
    /// Called during emergency stop when the OS is about to kill us. UI will show empty
    /// state but the app won't crash. Data repopulates from cache on next foreground.
    func emergencyTrimAllData() {
        let coinCount = allCoins.count
        
        // MEMORY FIX v13: Set emergency flag FIRST to prevent didSet cascades.
        // Without this, setting allCoins=[], coins=[], filteredCoins=[], watchlistCoins=[]
        // fires 4 separate objectWillChange notifications, each triggering full SwiftUI
        // view tree re-evaluation. The re-renders allocate temporary view descriptions,
        // sparkline paths, etc. — causing 38 MB/s continuous growth even after data pipeline
        // is killed. The emergency flag tells ALL views to return minimal empty bodies.
        if !isMemoryEmergency {
            isMemoryEmergency = true
            // Notify observing views to tear down heavy sections (e.g., HomeView strips to portfolio-only).
            // Without this, views remain subscribed with stale empty data, causing UI corruption.
            NotificationCenter.default.post(name: .memoryEmergencySectionsStrip, object: nil)
        }

        trimMemory()
        // Clear the main arrays entirely — these hold the bulk of live data.
        // MEMORY FIX v13: Only set @Published properties if they're NOT already empty.
        // @Published sends objectWillChange BEFORE didSet runs, so even setting []=[]
        // triggers a full SwiftUI body re-evaluation. Each re-eval allocates ~10 MB of
        // temporary view state. With 4 arrays × 10 MB = 40 MB per cleanup — exactly
        // matching the "freed -40 MB" (negative) seen in logs.
        if !allCoins.isEmpty { allCoins = [] }
        if !coins.isEmpty { coins = [] }
        if !filteredCoins.isEmpty { filteredCoins = [] }
        if !watchlistCoins.isEmpty { watchlistCoins = [] }
        if case .idle = state {} else { state = .idle }
        #if DEBUG
        print("🗑️ [MarketViewModel] Emergency trim: cleared \(coinCount) coins from all arrays (emergency mode ON)")
        #endif
    }
    
    /// Load from cache only - for instant startup without triggering network calls
    /// This enables showing cached data immediately while delaying API calls to prevent rate limiting
    /// FIX: Sets isInitialized = true when complete so dependent views/services can proceed
    func loadFromCacheOnly() async {
        // Skip if already loaded
        if self.isInitialized && !self.allCoins.isEmpty {
            // Only need to load watchlist (fast - just filtering existing data)
            let favoriteIDs = FavoritesManager.shared.favoriteIDs
            if !favoriteIDs.isEmpty {
                let cached = self.allCoins.filter { favoriteIDs.contains($0.id) }
                if !cached.isEmpty {
                    self.watchlistCoins = cached.sorted { coin1, coin2 in
                        let idx1 = FavoritesManager.shared.getOrder().firstIndex(of: coin1.id) ?? Int.max
                        let idx2 = FavoritesManager.shared.getOrder().firstIndex(of: coin2.id) ?? Int.max
                        return idx1 < idx2
                    }
                }
            }
            return
        }
        
        // MEMORY FIX: Load cache asynchronously off the main thread.
        // Previously this was done synchronously in init(), blocking the main thread
        // and contributing to the memory pressure crash on launch.
        let cachedCoins: [MarketCoin]? = await CacheManager.shared.loadFromDocumentsOnlyAsync([MarketCoin].self, from: "coins_cache.json")
        
        if let cached = cachedCoins, cached.count >= self.minUsableSnapshotCount {
            // MEMORY FIX v5: Cap the loaded cache BEFORE normalization.
            // Previous sessions may have saved 250+ coins. Normalizing 250 coins creates
            // a temporary 250-element array with sparklines before the didSet caps it.
            let capped = cached.count > Self.maxAllCoinsCount ? Array(cached.prefix(Self.maxAllCoinsCount)) : cached
            // MEMORY FIX v4: Normalize ONCE, assign ONCE.
            let normalized = self.normalizeCoins(capped)
            self.allCoins = normalized
            // MEMORY FIX v4: Don't duplicate into lastGoodAllCoins at startup.
            // It's only needed as a fallback when allCoins is about to be replaced with
            // a smaller set. At this point allCoins IS the cache - no backup needed.
            self.state = .success(normalized)
            self.isUsingCachedData = true
            
            // Build books and apply filters (single pass instead of two)
            self.rebuildPriceBooks()
            self.computeGlobalStatsAsync(base: normalized)
            self.primeLivePercents(for: normalized)
            // MEMORY FIX v7: Deferred scheduling
            self.scheduleApplyFilters(delay: 0.0)
            self.showSnapshotImmediately()
        } else {
            // Build books from whatever we have
            self.rebuildPriceBooks()
            self.scheduleApplyFilters(delay: 0.0)
            
            // Fall back to bundled snapshot if async cache load didn't find anything
            if self.allCoins.isEmpty {
                adoptCachedOrBundledSnapshot()
            }
            // COLD START FIX: If Documents cache and adoptCachedOrBundled both failed
            // (fresh install or corrupted cache), use the bundled coins_cache.json.
            // This ensures BTC and other major coins are always present on first launch.
            if self.allCoins.isEmpty {
                let bundled = self.loadBundledCoins()
                if !bundled.isEmpty {
                    let normalized = self.normalizeCoins(self.capToMaxCoins(bundled))
                    self.allCoins = normalized
                    self.state = .success(normalized)
                    self.rebuildPriceBooks()
                    self.showSnapshotImmediately()
                }
            }
        }
        
        // Load global stats from last real fetch
        if let snap = self.loadAnyGlobalSnapshot() {
            if let c = snap.marketCap, c.isFinite, c > 0 { self.globalMarketCap = c }
            if let v = snap.volume24h, v.isFinite, v > 0 { self.globalVolume24h = v }
            if let b = snap.btcDominance, b.isFinite, b > 0 { self.btcDominance = b }
            if let e = snap.ethDominance, e.isFinite, e > 0 { self.ethDominance = e }
            if let ch = snap.change24hPercent, ch.isFinite { self.globalChange24hPercent = ch }
        }
        
        // Load watchlist from cache only (no network)
        let favoriteIDs = FavoritesManager.shared.favoriteIDs
        if !favoriteIDs.isEmpty {
            let cached = self.allCoins.filter { favoriteIDs.contains($0.id) }
            if !cached.isEmpty {
                self.watchlistCoins = cached.sorted { coin1, coin2 in
                    let idx1 = FavoritesManager.shared.getOrder().firstIndex(of: coin1.id) ?? Int.max
                    let idx2 = FavoritesManager.shared.getOrder().firstIndex(of: coin2.id) ?? Int.max
                    return idx1 < idx2
                }
            }
        }
        
        // Mark as initialized so dependent views/services know data is ready
        if !self.isInitialized {
            self.isInitialized = true
            self.diag("Diag: MarketViewModel initialized via loadFromCacheOnly with \(self.allCoins.count) coins")
        }

        // Limited simulator profile still needs one-shot freshness when cache is sparse.
        if AppSettings.isSimulatorLimitedDataMode && self.allCoins.count < Self.maxAllCoinsCount {
            self.ensureBaselineSnapshotIfNeeded(minCount: Self.maxAllCoinsCount)
        }
    }
}

// MARK: - Global Stats Snapshot Types (added)
private struct GlobalStatsSnapshot: Codable {
    let marketCap: Double?
    let volume24h: Double?
    let btcDominance: Double?
    let ethDominance: Double?
    let change24hPercent: Double? // Added for consistency on app launch
    let publishedAt: Date
    
}

private struct LegacyGlobalStatsSnapshot: Codable {
    let total_market_cap: Double?
    let total_volume_24h: Double?
    let btc_dominance: Double?
    let eth_dominance: Double?
    let published_at: String
}

// MARK: - SparklineTuning struct with updated values
private struct SparklineTuning {
    static var resampleCount: Int = 120
    static var smoothingWindow: Int = 5
    static let flatnessThreshold: Double = 0.002
}

