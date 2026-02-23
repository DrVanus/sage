//
//  HomeViewModel.swift
//  CSAI1
//
//  ViewModel to provide data for Home screen: portfolio, news, heatmap, market overview.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class HomeViewModel: ObservableObject {
    // MARK: - Child ViewModels
    // PERFORMANCE FIX: Removed @Published from nested ViewModels to prevent double re-renders.
    // When child ViewModels change, they were triggering parent's objectWillChange, causing
    // cascading updates. Views that need these VMs should observe them directly.
    var portfolioVM: PortfolioViewModel
    var newsVM      = CryptoNewsFeedViewModel.shared
    var heatMapVM   = HeatMapViewModel()
    /// ViewModel for global market stats
    var statsVM = MarketStatsViewModel()
    
    // MARK: - Error State (USER-FACING)
    /// Error message to display to user when data loading fails
    @Published var errorMessage: String? = nil
    /// Indicates if home data failed to load
    @Published var hasLoadError: Bool = false

    // Combine subscriptions container
    private var cancellables = Set<AnyCancellable>()

    // Shared Market ViewModel (injected at creation)
    let marketVM: MarketViewModel

    private var didSeedDemo = false
    private var isSeedingDemo = false
    private var lastSectionsFingerprint: Int? = nil
    // PERFORMANCE FIX v22: Track allCoins fingerprint to skip redundant computations
    private var lastAllCoinsFingerprint: Int = 0
    /// Maximum coins to process for trending/gainers/losers sections.
    /// PERFORMANCE FIX: Reduced from 800 to 400 to decrease main thread work.
    /// 400 coins is sufficient for accurate top gainers/losers (top 10 of each).
    /// The top coins by market cap are already sorted first in allCoins.
    private let maxCoinsToProcess = 400

    // Quiet-start and spacing gates
    // PERFORMANCE: Increased quiet period from 1.0 to 1.5 seconds for smoother app launch
    private var firstFrameQuietUntil: Date = Date().addingTimeInterval(1.5)
    private var bootstrapUntil: Date = Date().addingTimeInterval(120)
    private var startupRecomputeSuppressUntil: Date = Date().addingTimeInterval(20)
    private var lastSectionsComputeAt: Date = .distantPast
    // PERFORMANCE: Increased spacing from 1.5 to 2.0 seconds during bootstrap
    private let minSectionsComputeSpacing: TimeInterval = 2.0
    // PERFORMANCE FIX: Enhanced scroll-aware throttling - even longer spacing during scroll
    private var effectiveMinSectionsComputeSpacing: TimeInterval {
        // During fast scroll, use maximum throttling (6 seconds) to ensure smooth scrolling
        if ScrollStateManager.shared.isFastScrolling {
            return 6.0
        }
        // During normal scroll, use increased throttling (4 seconds)
        if ScrollStateManager.shared.isScrolling {
            return 4.0
        }
        // During bootstrap, use 2.0 seconds minimum
        if Date() < self.bootstrapUntil {
            return max(self.minSectionsComputeSpacing, 2.0)
        }
        return self.minSectionsComputeSpacing
    }
    private var lastSectionsResult: (trending: [MarketCoin], gainers: [MarketCoin], losers: [MarketCoin]) = ([], [], [])
    private var didScheduleSeedPostQuiet: Bool = false
    
    // TASK TRACKING: Prevents overlapping fetchMarketData calls
    private var fetchMarketDataTask: Task<Void, Never>?

    /// FIX v24: Accept an external PortfolioViewModel to share a single instance app-wide.
    /// Previously HomeViewModel created its own PortfolioViewModel, while CryptoSageAIApp
    /// created a separate one for `.environmentObject(portfolioVM)`. This caused two independent
    /// portfolio instances with separate price updates, potentially showing different totals
    /// across views (Home vs AI Chat vs Settings).
    init(portfolioVM: PortfolioViewModel? = nil) {
        if let portfolioVM = portfolioVM {
            self.portfolioVM = portfolioVM
        } else {
            // Fallback: create own instance (for previews / tests)
            let manualService = ManualPortfolioDataService()
            let liveService   = LivePortfolioDataService()
            let priceService  = CoinGeckoPriceService.shared
            let repository    = PortfolioRepository(
                manualService: manualService,
                liveService:   liveService,
                priceService:  priceService
            )
            self.portfolioVM = PortfolioViewModel(repository: repository)
        }
        self.marketVM = MarketViewModel.shared
        // PERFORMANCE FIX v18: Defer market data fetching further to avoid competing with
        // startHeavyLoading() which also calls marketVM.loadAllData() at Phase 3 (800ms).
        // The splash screen shows for 2.5s anyway, so we don't need to rush this.
        Task { [weak self] in
            guard let self = self else { return }
            // Wait longer - startHeavyLoading Phase 3 calls loadAllData at 800ms
            // We wait for that to complete rather than duplicating the work
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
            
            // Only fetch if marketVM didn't already load (e.g. from startHeavyLoading)
            if self.marketVM.allCoins.isEmpty && self.marketVM.coins.isEmpty {
                await self.fetchMarketData()
            }
            
            // News loading is handled by HomeView phase gating.
            // Avoid duplicate startup fetches from HomeViewModel init.
        }

        // PERFORMANCE FIX: Removed empty placeholder subscriptions that were firing callbacks but doing nothing
        // statsVM.objectWillChange and marketVM.$coins subscriptions with empty sinks were wasting resources

        // PERFORMANCE FIX v22: Debounce FIRST, then fingerprint on background thread.
        // Previously: .map { fingerprint() } → .removeDuplicates → .debounce(1500ms)
        // This ran O(300) hash operations on the main thread for EVERY allCoins emission
        // (18+ assignment sites in MarketViewModel), wasting CPU before debounce could filter.
        // Now: .debounce(1500ms) → .sink → fingerprint + compute on background thread
        marketVM.$allCoins
            .debounce(for: .milliseconds(1500), scheduler: DispatchQueue.main)
            .sink { [weak self] coins in
                guard let self = self else { return }
                Task.detached(priority: .userInitiated) { [weak self] in
                    guard let self = self else { return }
                    
                    let fp = coins.fingerprint()
                    let shouldCompute = await MainActor.run {
                        let now = Date()
                        if now < self.startupRecomputeSuppressUntil && coins.count < 80 {
                            return false
                        }
                        let timingOK = now.timeIntervalSince(self.lastSectionsComputeAt) >= self.effectiveMinSectionsComputeSpacing
                        let changed = self.lastAllCoinsFingerprint != fp
                        return timingOK && changed
                    }
                    guard shouldCompute else { return }
                    
                    let result = self.computeTopSections(from: coins)
                    
                    await MainActor.run { [weak self] in
                        guard let self = self else { return }
                        self.lastAllCoinsFingerprint = fp
                        guard !ScrollStateManager.shared.isScrolling && !ScrollStateManager.shared.isFastScrolling else {
                            self.lastSectionsResult = result
                            return
                        }
                        self.lastSectionsComputeAt = Date()
                        self.lastSectionsResult = result
                        let sectionsFP = self.sectionsFingerprint(trending: result.trending, gainers: result.gainers, losers: result.losers)
                        if let last = self.lastSectionsFingerprint, last == sectionsFP { return }
                        self.lastSectionsFingerprint = sectionsFP
                        self.liveTrending   = result.trending
                        self.liveTopGainers = result.gainers
                        self.liveTopLosers  = result.losers
                        if !self.didScheduleSeedPostQuiet {
                            self.didScheduleSeedPostQuiet = true
                            self.scheduleAfterQuiet { [weak self] in self?.seedDemoIfNeeded() }
                        }
                    }
                }
            }
            .store(in: &cancellables)
        
        // Subscribe to Paper Trading changes to properly handle mode switches
        PaperTradingManager.shared.$isPaperTradingEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPaperTradingEnabled in
                guard let self = self else { return }
                if isPaperTradingEnabled {
                    // Paper Trading enabled - disable demo mode if active
                    if self.portfolioVM.demoOverrideEnabled {
                        self.portfolioVM.disableDemoOverrideAndResumeRepository()
                    }
                    self.didSeedDemo = false // Reset so demo can be re-seeded when Paper Trading is disabled
                }
            }
            .store(in: &cancellables)
        
        // Ensure a demo portfolio exists even if Home tab isn't opened first
        seedDemoIfNeeded()
    }

    init(marketVM: MarketViewModel, portfolioVM: PortfolioViewModel? = nil) {
        if let portfolioVM = portfolioVM {
            self.portfolioVM = portfolioVM
        } else {
            let manualService = ManualPortfolioDataService()
            let liveService   = LivePortfolioDataService()
            let priceService  = CoinGeckoPriceService.shared
            let repository    = PortfolioRepository(
                manualService: manualService,
                liveService:   liveService,
                priceService:  priceService
            )
            self.portfolioVM = PortfolioViewModel(repository: repository)
        }
        self.marketVM = marketVM
        // PERFORMANCE FIX v18: Same deferred approach as init()
        Task { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
            
            if self.marketVM.allCoins.isEmpty && self.marketVM.coins.isEmpty {
                await self.fetchMarketData()
            }
            
            // News loading is handled by HomeView phase gating.
            // Avoid duplicate startup fetches from HomeViewModel init.
        }

        // PERFORMANCE FIX: Removed empty placeholder subscriptions that were firing callbacks but doing nothing
        // statsVM.objectWillChange and marketVM.$coins subscriptions with empty sinks were wasting resources

        // PERFORMANCE FIX v22: Debounce FIRST, then fingerprint on background thread.
        // Previously: .map { fingerprint() } → .removeDuplicates → .debounce(1500ms)
        // This ran O(300) hash operations on the main thread for EVERY allCoins emission
        // (18+ assignment sites in MarketViewModel), wasting CPU before debounce could filter.
        // Now: .debounce(1500ms) → .sink → fingerprint + compute on background thread
        marketVM.$allCoins
            .debounce(for: .milliseconds(1500), scheduler: DispatchQueue.main)
            .sink { [weak self] coins in
                guard let self = self else { return }
                Task.detached(priority: .userInitiated) { [weak self] in
                    guard let self = self else { return }
                    
                    let fp = coins.fingerprint()
                    let shouldCompute = await MainActor.run {
                        let now = Date()
                        if now < self.startupRecomputeSuppressUntil && coins.count < 80 {
                            return false
                        }
                        let timingOK = now.timeIntervalSince(self.lastSectionsComputeAt) >= self.effectiveMinSectionsComputeSpacing
                        let changed = self.lastAllCoinsFingerprint != fp
                        return timingOK && changed
                    }
                    guard shouldCompute else { return }
                    
                    let result = self.computeTopSections(from: coins)
                    
                    await MainActor.run { [weak self] in
                        guard let self = self else { return }
                        self.lastAllCoinsFingerprint = fp
                        guard !ScrollStateManager.shared.isScrolling && !ScrollStateManager.shared.isFastScrolling else {
                            self.lastSectionsResult = result
                            return
                        }
                        self.lastSectionsComputeAt = Date()
                        self.lastSectionsResult = result
                        let sectionsFP = self.sectionsFingerprint(trending: result.trending, gainers: result.gainers, losers: result.losers)
                        if let last = self.lastSectionsFingerprint, last == sectionsFP { return }
                        self.lastSectionsFingerprint = sectionsFP
                        self.liveTrending   = result.trending
                        self.liveTopGainers = result.gainers
                        self.liveTopLosers  = result.losers
                        if !self.didScheduleSeedPostQuiet {
                            self.didScheduleSeedPostQuiet = true
                            self.scheduleAfterQuiet { [weak self] in self?.seedDemoIfNeeded() }
                        }
                    }
                }
            }
            .store(in: &cancellables)
        
        // Subscribe to Paper Trading changes to properly handle mode switches
        PaperTradingManager.shared.$isPaperTradingEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPaperTradingEnabled in
                guard let self = self else { return }
                if isPaperTradingEnabled {
                    // Paper Trading enabled - disable demo mode if active
                    if self.portfolioVM.demoOverrideEnabled {
                        self.portfolioVM.disableDemoOverrideAndResumeRepository()
                    }
                    self.didSeedDemo = false // Reset so demo can be re-seeded when Paper Trading is disabled
                }
            }
            .store(in: &cancellables)

        // Ensure a demo portfolio exists even if Home tab isn't opened first
        seedDemoIfNeeded()
    }

    // MARK: - Market Data Fetching
    /// Fetches the full coin list once, then updates our three @Published slices.
    func fetchMarketData() async {
        // Avoid duplicating heavy work if MarketViewModel already loaded a baseline
        if marketVM.allCoins.isEmpty && marketVM.coins.isEmpty {
            await marketVM.loadAllData()
        }
    }
    
    /// PERFORMANCE FIX: Progressive data loading to prevent homepage sections from loading simultaneously.
    /// This batches related API calls with timing gaps to reduce network congestion and main thread blocking.
    func loadDataProgressively(phase: Int) async {
        switch phase {
        case 1:
            // Phase 1: Critical data only (portfolio, watchlist prices)
            async let portfolio = portfolioVM.refreshIfNeeded()
            async let watchlistPrices = marketVM.loadWatchlistPrices()
            await [portfolio, watchlistPrices]
            
        case 2:
            // Phase 2: Context data (news, sentiment, market stats)
            // Small delay to prevent network congestion from Phase 1
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
            
            async let news = newsVM.loadArticlesIfNeeded()
            async let stats = statsVM.refreshIfNeeded()
            await [news, stats]
            
        case 3:
            // Phase 3: Heavy/optional data (heatmap, whale activity, detailed analytics)
            // Longer delay to ensure core UI is responsive first
            try? await Task.sleep(nanoseconds: 400_000_000) // 400ms
            
            async let heatmap = heatMapVM.loadDataIfNeeded()
            // Additional heavy operations can be added here as needed
            await heatmap
            
        default:
            break
        }
    }

    // Note: computeTopSectionsThrottled was removed - throttling is now done inline in the Task.detached block
    // to allow background thread execution

    private func sectionsFingerprint(trending: [MarketCoin], gainers: [MarketCoin], losers: [MarketCoin]) -> Int {
        var hasher = Hasher()
        func hashList(_ list: [MarketCoin]) {
            for c in list {
                hasher.combine(c.id)
                hasher.combine(Int((c.priceUsd ?? 0) * 100))
                hasher.combine(Int((c.changePercent24Hr ?? 0) * 100))
            }
        }
        hashList(trending)
        hashList(gainers)
        hashList(losers)
        return hasher.finalize()
    }

    /// PERFORMANCE FIX: Pre-compute percent changes to avoid repeated property accesses during sorting
    /// This also allows us to use stored properties (unified24hPercent, changePercent24Hr) which are fast,
    /// avoiding @MainActor dependency from best24hPercent when possible.
    /// NOTE: nonisolated allows calling from Task.detached for background processing
    private nonisolated func computeTopSections(from coins: [MarketCoin]) -> (trending: [MarketCoin], gainers: [MarketCoin], losers: [MarketCoin]) {
        // Cap processing to reduce CPU for very large lists
        let capped = Array(coins.prefix(maxCoinsToProcess))
        // Trending: first 10 (already reasonably ordered by your data source)
        let trending = Array(capped.prefix(10))

        // PERFORMANCE FIX: Pre-compute all changes into a dictionary to avoid repeated property access
        // Use stored properties first (fast), only fall back to computed best24hPercent if needed
        var changeCache: [String: Double] = [:]
        changeCache.reserveCapacity(capped.count)
        
        for coin in capped {
            // Prefer stored properties (no @MainActor) over computed best24hPercent
            let v = coin.unified24hPercent ?? coin.changePercent24Hr ?? coin.priceChangePercentage24hInCurrency ?? 0
            changeCache[coin.id] = v.isFinite ? v : 0
        }
        
        // Helper using cached values (O(1) lookup instead of property computation)
        func change(_ c: MarketCoin) -> Double {
            return changeCache[c.id] ?? 0
        }

        // Compute top 10 gainers/losers without sorting the entire array (O(n·k))
        func topN(by areInIncreasingOrder: @escaping (MarketCoin, MarketCoin) -> Bool, n: Int) -> [MarketCoin] {
            var result: [MarketCoin] = []
            result.reserveCapacity(n)
            for coin in capped {
                if result.count < n {
                    result.append(coin)
                    result.sort(by: areInIncreasingOrder)
                } else if let last = result.last, areInIncreasingOrder(coin, last) {
                    result.removeLast()
                    // Insert coin keeping array sorted (binary insertion could be used; n is tiny so linear is fine)
                    var inserted = false
                    for i in 0..<result.count {
                        if areInIncreasingOrder(coin, result[i]) {
                            result.insert(coin, at: i)
                            inserted = true
                            break
                        }
                    }
                    if !inserted { result.append(coin) }
                }
            }
            return result
        }

        // For gainers we want highest change first
        // CONSISTENCY FIX: Add secondary sort by coin ID to ensure deterministic ordering
        // When two coins have the same change percentage, sort by ID for consistent cross-device results
        let gainers = topN(by: { 
            let c0 = change($0), c1 = change($1)
            if c0 == c1 { return $0.id < $1.id }  // Deterministic tiebreaker
            return c0 > c1
        }, n: 10)
        // For losers we want most negative first (smallest values)
        // CONSISTENCY FIX: Same deterministic secondary sort
        let losers = topN(by: { 
            let c0 = change($0), c1 = change($1)
            if c0 == c1 { return $0.id < $1.id }  // Deterministic tiebreaker
            return c0 < c1
        }, n: 10)

        return (trending, gainers, losers)
    }
    
    // MARK: - Demo Portfolio Seeding (runs even if Home tab isn't opened first)
    private func seedDemoIfNeeded(force: Bool = false) {
        // Skip demo seeding if Paper Trading is enabled - Paper Trading takes priority
        guard !PaperTradingManager.shared.isPaperTradingEnabled else { return }
        // Respect the unified demo mode setting
        guard DemoModeManager.shared.isDemoMode else { return }
        if !force {
            guard !didSeedDemo else { return }
            guard !isSeedingDemo else { return }
            guard portfolioVM.holdings.isEmpty else { return }
        }

        isSeedingDemo = true
        defer { isSeedingDemo = false }

        // Use the standardized demo seed from PortfolioViewModel for consistent values
        // across all views (portfolio header, chart, home page, etc.)
        portfolioVM.enableDemoMode()
        didSeedDemo = true
    }

    private func scheduleAfterQuiet(_ work: @escaping () -> Void) {
        let now = Date()
        if now >= self.firstFrameQuietUntil {
            work()
        } else {
            let delay = max(0, self.firstFrameQuietUntil.timeIntervalSince(now))
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                work()
            }
        }
    }

    // TASK TRACKING FIX: Consolidated fetch methods to prevent overlapping requests
    // All three methods call the same fetchMarketData(), so we track the task
    func fetchTrending() {
        guard fetchMarketDataTask == nil else { return }
        fetchMarketDataTask = Task { [weak self] in
            await self?.fetchMarketData()
            self?.fetchMarketDataTask = nil
        }
    }
    func fetchTopGainers()  { fetchTrending() }  // Reuse same logic
    func fetchTopLosers()   { fetchTrending() }  // Reuse same logic

    // MARK: - Cached market slices (internal use only)
    // PERFORMANCE FIX: Removed @Published - these were causing unnecessary UI re-renders
    // TrendingSectionView computes its own lists from marketVM.allCoins
    // These are kept as private cache for any future internal use
    private var liveTrending: [MarketCoin] = []
    private var liveTopGainers: [MarketCoin] = []
    private var liveTopLosers: [MarketCoin] = []
}

private extension Array where Element == MarketCoin {
    func fingerprint(maxCount: Int = 300) -> Int {
        var hasher = Hasher()
        for c in self.prefix(maxCount) {
            hasher.combine(c.id)
            hasher.combine(Int((c.priceUsd ?? 0) * 100))
            hasher.combine(Int((c.changePercent24Hr ?? 0) * 100))
            hasher.combine(Int((c.totalVolume ?? 0) / 1000))
        }
        return hasher.finalize()
    }
}

