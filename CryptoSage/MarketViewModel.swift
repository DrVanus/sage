import Foundation
import _Concurrency
import Combine

@MainActor
final class MarketViewModel: ObservableObject {
    /// Shared singleton instance for global access
    static let shared = MarketViewModel()

    // MARK: - Published Properties
    @Published var state: LoadingState<[MarketCoin]> = .idle
    @Published var favoriteIDs: Set<String> = FavoritesManager.shared.getAllIDs()
    @Published var watchlistCoins: [MarketCoin] = []
    private var watchlistTask: Task<Void, Never>? = nil

    @Published var showSearchBar: Bool = false
    @Published var searchText: String = ""
    @Published var selectedSegment: MarketSegment = .all {
        didSet { applyAllFiltersAndSort() }
    }
    @Published var sortField: SortField = .marketCap {
        didSet { applyAllFiltersAndSort() }
    }
    @Published var sortDirection: SortDirection = .desc {
        didSet { applyAllFiltersAndSort() }
    }
    @Published var filteredCoins: [MarketCoin] = []
    /// Live-updated list of MarketCoin from LivePriceManager
    @Published var coins: [MarketCoin] = []

    // MARK: - Derived Published Slices
    @Published private(set) var allCoins: [MarketCoin] = []
    @Published private(set) var trendingCoins: [MarketCoin] = []
    @Published private(set) var topGainers: [MarketCoin] = []
    @Published private(set) var topLosers: [MarketCoin] = []

    private var cancellables = Set<AnyCancellable>()
    private var livePriceCancellable: AnyCancellable?
    private let priceService: PriceService

    /// Expose watchlist coins under a simpler name
    var watchlist: [MarketCoin] {
        watchlistCoins
    }

    private var refreshCancellable: AnyCancellable?
    private var searchCancellable: AnyCancellable?
    private let stableSymbols: Set<String> = ["USDT", "USDC", "BUSD", "DAI"]



    // MARK: - Initialization

    init(priceService: PriceService = CoinGeckoPriceService()) {
        self.priceService = priceService
        // Load cached coins so UI shows data immediately
        if let saved: [MarketCoin] = CacheManager.shared.load([MarketCoin].self, from: "coins_cache.json"),
           !saved.isEmpty {
            self.allCoins = saved
            self.state = .success(saved)
        } else {
            self.state = .loading
        }

        // Set up Combine pipelines to derive slices
        $allCoins
            .receive(on: DispatchQueue.main)
            .map { Array($0.prefix(10)) }
            .assign(to: \.trendingCoins, on: self)
            .store(in: &cancellables)

        $allCoins
            .receive(on: DispatchQueue.main)
            .map { coins in
                coins.sorted { ($0.changePercent24Hr ?? 0) > ($1.changePercent24Hr ?? 0) }
                      .prefix(10)
            }
            .map(Array.init)
            .assign(to: \.topGainers, on: self)
            .store(in: &cancellables)

        $allCoins
            .receive(on: DispatchQueue.main)
            .map { coins in
                coins.sorted { ($0.changePercent24Hr ?? 0) < ($1.changePercent24Hr ?? 0) }
                      .prefix(10)
            }
            .map(Array.init)
            .assign(to: \.topLosers, on: self)
            .store(in: &cancellables)

        // Debounce search input
        searchCancellable = $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyAllFiltersAndSort()
            }

        // Recompute filteredCoins whenever allCoins changes
        $allCoins
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyAllFiltersAndSort()
            }
            .store(in: &cancellables)

        startAutoRefresh()
        Task { await loadInitialData() }
        // Subscribe to live MarketCoin updates
        LivePriceManager.shared.startPolling()
        LivePriceManager.shared.coinsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] latest in
                self?.coins = latest
            }
            .store(in: &cancellables)
    }

    // MARK: - Networking & Caching

    /// Loads only the user’s favorited coins
    func loadWatchlistData() async {
        guard !favoriteIDs.isEmpty else {
            watchlistCoins = []
            return
        }
        var lastError: Error?
        for attempt in 1...3 {
            do {
                let list = try await CryptoAPIService.shared.fetchWatchlistMarkets(ids: Array(favoriteIDs))
                watchlistCoins = list
                lastError = nil
                break
            } catch {
                lastError = error
                if attempt < 3 {
                    try? await Task.sleep(nanoseconds: UInt64(1 * 1_000_000_000))
                }
            }
        }
        if let error = lastError {
            print("❗️ loadWatchlistData error:", error)
        }
    }

    /// Wrapper for fetching coins by ID, used by other view models
    func fetchCoins(ids: [String]) async -> [MarketCoin] {
        return await CryptoAPIService.shared.fetchCoins(ids: ids)
    }

    /// Fetches all coins, rebuilds caches, and updates `state`
    func loadAllData() async {
        let oldCoins = coins
        var lastError: Error?
        for attempt in 1...3 {
            do {
                let fetchedCoins = try await CryptoAPIService.shared.fetchCoinMarkets()
                self.state = .success(fetchedCoins)
                self.allCoins = fetchedCoins
                CacheManager.shared.save(fetchedCoins, to: "coins_cache.json")
                applyAllFiltersAndSort()
                setupLivePriceUpdates()
                lastError = nil
                break
            } catch {
                lastError = error
                if attempt < 3 {
                    try? await Task.sleep(nanoseconds: UInt64(2 * 1_000_000_000))
                }
            }
        }
        if let error = lastError {
            print("❗️ loadAllData error:", error)
            if coins.isEmpty {
                state = .failure(error.localizedDescription)
            } else {
                state = .success(oldCoins)
                applyAllFiltersAndSort()
            }
        }
    }

    private var isRefreshing = false

    func refreshAllData() {
        guard !isRefreshing else { return }
        isRefreshing = true
        state = .loading

        Task {
            await loadAllData()
            await loadWatchlistData()
            isRefreshing = false
        }
    }
    /// Manual refresh for pull-to-refresh
    func manualRefresh() {
        refreshAllData()
    }

    // MARK: - Auto Refresh

    private func startAutoRefresh() {
        refreshCancellable = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshAllData()
            }
    }

    // MARK: - Filtering & Sorting

    func updateSegment(_ seg: MarketSegment) {
        selectedSegment = seg
    }

    func toggleSort(for field: SortField) {
        if sortField == field {
            sortDirection.toggle()
        } else {
            sortField = field
            sortDirection = .asc
        }
    }

    func applyAllFiltersAndSort() {
        guard case .success(let coins) = state else {
            filteredCoins = []
            return
        }
        var temp: [MarketCoin]
        switch selectedSegment {
        case .all:
            temp = coins
        case .trending:
            temp = trendingCoins
        case .gainers:
            temp = topGainers
        case .losers:
            temp = topLosers
        case .favorites:
            temp = coins.filter { favoriteIDs.contains($0.id) }
        }

        if !searchText.isEmpty {
            let q = searchText.lowercased()
            temp = temp.filter {
                $0.name.lowercased().contains(q) ||
                $0.symbol.lowercased().contains(q)
            }
        }

        temp.sort(by: {
            let result: Bool
            switch sortField {
            case .coin:        result = $0.name.lowercased() < $1.name.lowercased()
            case .price:       result = ($0.priceUsd ?? 0) < ($1.priceUsd ?? 0)
            case .dailyChange: result = ($0.changePercent24Hr ?? 0) < ($1.changePercent24Hr ?? 0)
            case .volume:      result = ($0.volumeUsd24Hr ?? 0) < ($1.volumeUsd24Hr ?? 0)
            case .marketCap:   result = ($0.marketCap ?? 0) < ($1.marketCap ?? 0)
            }
            return sortDirection == .asc ? result : !result
        })

        filteredCoins = temp
    }

    // MARK: - Favorites

    func toggleFavorite(_ coin: MarketCoin) {
        FavoritesManager.shared.toggle(coinID: coin.id)
        favoriteIDs = FavoritesManager.shared.getAllIDs()
        applyAllFiltersAndSort()

        watchlistTask?.cancel()
        watchlistTask = Task {
            await loadWatchlistData()
        }
    }

    func isFavorite(_ coin: MarketCoin) -> Bool {
        FavoritesManager.shared.isFavorite(coinID: coin.id)
    }

    /// Removes a coin ID from favorites and updates watchlist and filters
    func remove(coinID: String) {
        FavoritesManager.shared.remove(coinID: coinID)
        favoriteIDs = FavoritesManager.shared.getAllIDs()
        applyAllFiltersAndSort()

        watchlistTask?.cancel()
        watchlistTask = Task {
            await loadWatchlistData()
        }
    }

    /// --- Load coins first, then watchlist, then apply filters
    private func loadInitialData() async {
        fetchMarketData()
        await loadWatchlistData()
        applyAllFiltersAndSort()
    }

    // MARK: - Live Price Setup
    func setupLivePriceUpdates() {
        // Start batched polling for all coins
        livePriceCancellable?.cancel()
        LivePriceManager.shared.startPolling()
        livePriceCancellable = LivePriceManager.shared.coinsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] latestCoins in
                self?.coins = latestCoins
            }
    }

    /// Fetches market data and updates state/loading indicators.
    func fetchMarketData() {
        // Show loading indicator
        state = .loading

        Task {
            do {
                // Fetch fresh market data
                let fetchedCoins = try await CryptoAPIService.shared.fetchCoinMarkets()
                // Update on main actor
                await MainActor.run {
                    self.allCoins = fetchedCoins
                    self.state = .success(fetchedCoins)
                    CacheManager.shared.save(fetchedCoins, to: "coins_cache.json")
                    applyAllFiltersAndSort()
                    setupLivePriceUpdates()
                }
            } catch {
                // Ignore user-initiated cancellations or transient network drops
                if let urlErr = error as? URLError, urlErr.code == .cancelled {
                    return
                }
                if error is CancellationError {
                    return
                }
                // On real error, fallback to cached/allCoins if available, otherwise show failure
                await MainActor.run {
                    if !self.allCoins.isEmpty {
                        self.state = .success(self.allCoins)
                    } else {
                        self.state = .failure(error.localizedDescription)
                    }
                }
            }
        }
    }
}

extension SortDirection {
    mutating func toggle() { self = (self == .asc ? .desc : .asc) }
}
