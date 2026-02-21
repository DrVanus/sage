//
//  TradingPairPickerView.swift
//  CryptoSage
//
//  Enhanced trading pair picker that shows actual trading pairs grouped by exchange
//  with live prices, distinguishing between tradable and view-only pairs.
//

import SwiftUI
import Combine

// MARK: - TradingPair Model

struct TradingPair: Identifiable, Hashable, Codable {
    let id: String
    let baseSymbol: String
    let quoteSymbol: String
    let exchangeID: String
    let exchangeName: String
    let priceUSD: Double
    let change24h: Double?
    let change1h: Double?
    let volume24hUSD: Double?  // 24-hour trading volume in USD for sorting
    let isTradable: Bool  // True if connected to this exchange
    let iconURL: URL?
    
    /// Popularity rank based on market cap (lower = more popular)
    /// BTC=1, ETH=2, SOL=3, etc.
    var popularityRank: Int {
        let ranks: [String: Int] = [
            // Tier 1: Top 10
            "BTC": 1, "ETH": 2, "USDT": 3, "BNB": 4, "SOL": 5,
            "XRP": 6, "USDC": 7, "ADA": 8, "DOGE": 9, "AVAX": 10,
            // Tier 2: 11-20
            "TRX": 11, "LINK": 12, "DOT": 13, "MATIC": 14, "TON": 15,
            "SHIB": 16, "LTC": 17, "BCH": 18, "UNI": 19, "ATOM": 20,
            // Tier 3: 21-30
            "NEAR": 21, "APT": 22, "ARB": 23, "OP": 24, "FIL": 25,
            "INJ": 26, "SUI": 27, "SEI": 28, "TIA": 29, "PEPE": 30,
            // Tier 4: 31-40
            "WIF": 31, "RENDER": 32, "IMX": 33, "FET": 34, "GRT": 35,
            "AAVE": 36, "MKR": 37, "SAND": 38, "MANA": 39, "AXS": 40,
            "GALA": 41, "ENJ": 42
        ]
        return ranks[baseSymbol.uppercased()] ?? 999
    }
    
    init(
        baseSymbol: String,
        quoteSymbol: String,
        exchangeID: String,
        exchangeName: String,
        priceUSD: Double,
        change24h: Double? = nil,
        change1h: Double? = nil,
        volume24hUSD: Double? = nil,
        isTradable: Bool = false,
        iconURL: URL? = nil
    ) {
        self.id = "\(exchangeID)-\(baseSymbol)-\(quoteSymbol)"
        self.baseSymbol = baseSymbol
        self.quoteSymbol = quoteSymbol
        self.exchangeID = exchangeID
        self.exchangeName = exchangeName
        self.priceUSD = priceUSD
        self.change24h = change24h
        self.change1h = change1h
        self.volume24hUSD = volume24hUSD
        self.isTradable = isTradable
        self.iconURL = iconURL
    }
    
    var displayPair: String {
        "\(baseSymbol)/\(quoteSymbol)"
    }
}

// MARK: - TradingPairPickerViewModel

@MainActor
final class TradingPairPickerViewModel: ObservableObject {
    @Published var pairs: [TradingPair] = []
    @Published var isLoading: Bool = false
    @Published var isRefreshing: Bool = false  // Background refresh indicator
    @Published var searchText: String = ""
    @Published var selectedExchange: String? = nil  // nil = All
    @Published var recentPairs: [TradingPair] = []
    @Published var showFavoritesOnly: Bool = false
    @Published var lastUpdated: Date?
    @Published var hasLoadedOnce: Bool = false  // Track if initial load completed
    
    private let router: CompositeMarketRouter
    private let rateService: InMemoryExchangeRateService
    
    // Storage keys
    private static let recentPairsKey = "trading_recent_pairs"
    private static let favoritePairsKey = "trading_favorite_pairs"
    private static let pairsCacheKey = "trading_pairs_cache"
    private static let cacheTimestampKey = "trading_pairs_cache_timestamp"
    
    // Cache validity: 15 minutes (prices update via background refresh)
    // Longer cache = faster loading, pull-to-refresh gets latest data
    private static let cacheValiditySeconds: TimeInterval = 900
    
    // Expanded list of popular trading pairs (sorted by market cap) - 40 coins
    private let popularBases = [
        // Tier 1: Top 10 by market cap
        "BTC", "ETH", "SOL", "XRP", "BNB",
        "ADA", "DOGE", "AVAX", "TRX", "LINK",
        // Tier 2: 11-20
        "DOT", "MATIC", "TON", "SHIB", "LTC",
        "BCH", "UNI", "ATOM", "NEAR", "APT",
        // Tier 3: 21-30
        "ARB", "OP", "FIL", "INJ", "TIA",
        "SUI", "SEI", "PEPE", "WIF", "RENDER",
        // Tier 4: 31-40 (Additional popular trading pairs)
        "IMX", "FET", "GRT", "AAVE", "MKR",
        "SAND", "MANA", "AXS", "GALA", "ENJ"
    ]
    
    init() {
        self.rateService = InMemoryExchangeRateService()
        self.router = CompositeMarketRouter(rateService: rateService)
        loadRecentPairs()
        
        // Load cached pairs immediately on init for instant display
        loadCachedPairs()
    }
    
    var connectedExchangeIDs: Set<String> {
        Set(TradingCredentialsManager.shared.getConnectedExchanges().map { $0.rawValue })
    }
    
    var availableExchanges: [String] {
        let exchanges = Set(pairs.map { $0.exchangeID })
        return Array(exchanges).sorted { exchangeSortOrder($0) < exchangeSortOrder($1) }
    }
    
    /// Returns pair count for a specific exchange
    func pairCount(for exchangeID: String?) -> Int {
        if let id = exchangeID {
            return pairs.filter { $0.exchangeID == id }.count
        }
        return pairs.count
    }
    
    /// Returns sort order for exchange ID (pure function, no state access)
    nonisolated private func exchangeSortOrder(_ id: String) -> Int {
        switch id.lowercased() {
        case "binance": return 0
        case "coinbase": return 1
        case "kraken": return 2
        case "kucoin": return 3
        default: return 99
        }
    }
    
    var filteredPairs: [TradingPair] {
        var result = pairs
        
        // Filter by search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { pair in
                pair.baseSymbol.lowercased().contains(query) ||
                pair.quoteSymbol.lowercased().contains(query) ||
                pair.exchangeName.lowercased().contains(query)
            }
        }
        
        // Filter by exchange
        if let exchange = selectedExchange {
            result = result.filter { $0.exchangeID == exchange }
        }
        
        // Filter by favorites if enabled
        if showFavoritesOnly {
            let favorites = TradingPairPreferencesService.shared.getAllFavoriteIDs()
            result = result.filter { favorites.contains($0.id) }
        }
        
        return result
    }
    
    var tradablePairs: [TradingPair] {
        filteredPairs.filter { $0.isTradable }
    }
    
    var viewOnlyPairs: [TradingPair] {
        filteredPairs.filter { !$0.isTradable }
    }
    
    /// Check if a pair is in favorites (delegates to shared service)
    func isFavorite(_ pair: TradingPair) -> Bool {
        TradingPairPreferencesService.shared.isFavorite(pair)
    }
    
    /// Toggle favorite status for a pair (delegates to shared service)
    func toggleFavorite(_ pair: TradingPair) {
        TradingPairPreferencesService.shared.toggleFavorite(pair)
        // Trigger UI refresh since favorites changed
        objectWillChange.send()
    }
    
    func load() async {
        // FAST PATH: If we have valid cached data, use it immediately and skip network
        // This makes the view appear instantly on subsequent opens
        let hasCachedData = !pairs.isEmpty
        
        if hasCachedData && isCacheValid {
            // Cache is fresh - just mark as loaded and return immediately
            hasLoadedOnce = true
            return
        }
        
        // Cache is stale or empty - need to refresh
        if hasCachedData {
            // Show "refreshing" indicator instead of blocking loading
            isRefreshing = true
        } else {
            isLoading = true
        }
        
        defer {
            isLoading = false
            isRefreshing = false
        }
        
        await performNetworkFetch(hasCachedData: hasCachedData)
    }
    
    /// Force a fresh network fetch regardless of cache state
    /// Use this for pull-to-refresh
    func forceRefresh() async {
        let hasCachedData = !pairs.isEmpty
        isRefreshing = true
        defer { isRefreshing = false }
        await performNetworkFetch(hasCachedData: hasCachedData)
    }
    
    /// Internal method that performs the actual network fetch
    private func performNetworkFetch(hasCachedData: Bool) async {
        let connected = connectedExchangeIDs
        
        // Pre-fetch caches on main actor before entering task group
        let imageURLCache = buildImageURLCache()
        let volumeCache = buildVolumeCache()
        let priceChangeCache = buildPriceChangeCache()
        
        // Fetch all pairs from exchanges
        let fetchedPairs: [TradingPair] = await withTaskGroup(of: [TradingPair].self, returning: [TradingPair].self) { group in
            for base in popularBases {
                group.addTask { [weak self] in
                    guard let self = self else { return [] }
                    
                    // Use fast ticker-only loading
                    let snapshots = await self.router.listPairSnapshotsFast(
                        for: base,
                        preferredQuotes: ["USD", "USDT", "FDUSD", "BUSD"],
                        limit: 8
                    )
                    
                    return snapshots.map { snap in
                        let isTradable = connected.contains(snap.exchangeID)
                        let imageURL = imageURLCache[snap.baseSymbol.uppercased()]
                        let volume = volumeCache[snap.baseSymbol.uppercased()]
                        // Use cached price change if available, otherwise use snapshot data
                        let priceChange = priceChangeCache[snap.baseSymbol.uppercased()] ?? snap.dayFrac
                        
                        return TradingPair(
                            baseSymbol: snap.baseSymbol,
                            quoteSymbol: snap.quoteSymbol,
                            exchangeID: snap.exchangeID,
                            exchangeName: self.exchangeDisplayName(snap.exchangeID),
                            priceUSD: snap.lastUSD,
                            change24h: priceChange,
                            change1h: snap.oneHFrac,
                            volume24hUSD: volume,
                            isTradable: isTradable,
                            iconURL: imageURL
                        )
                    }
                }
            }
            
            // Collect all pairs from task group
            var allPairs: [TradingPair] = []
            for await pairBatch in group {
                allPairs.append(contentsOf: pairBatch)
                
                // Only update UI progressively if we DON'T have cached data
                // This prevents visual jumping (e.g., ADA showing before BTC) when background refreshing
                if !hasCachedData {
                    let sorted = sortPairs(allPairs)
                    pairs = sorted
                }
            }
            return allPairs
        }
        
        // Final sort and update - always apply after all data is loaded
        pairs = sortPairs(fetchedPairs)
        lastUpdated = Date()
        hasLoadedOnce = true  // Mark that initial load completed
        savePairsCache()
    }
    
    /// Pre-warm the cache in the background (call on app launch)
    /// This ensures instant loading when user opens the trading pair picker
    static func prewarmCache() {
        Task { @MainActor in
            let viewModel = TradingPairPickerViewModel()
            // Only prewarm if cache is stale
            if !viewModel.isCacheValid {
                await viewModel.performNetworkFetch(hasCachedData: false)
            }
        }
    }
    
    /// Sort pairs by tradability, popularity, and exchange
    private func sortPairs(_ pairsToSort: [TradingPair]) -> [TradingPair] {
        pairsToSort.sorted { a, b in
            // 1. Tradable pairs always come first
            if a.isTradable != b.isTradable { return a.isTradable }
            
            // 2. Sort by popularity rank (based on market cap)
            if a.popularityRank != b.popularityRank {
                return a.popularityRank < b.popularityRank
            }
            
            // 3. Within same coin, prefer exchanges with higher volume/liquidity
            return exchangeSortOrder(a.exchangeID) < exchangeSortOrder(b.exchangeID)
        }
    }
    
    /// Build cache of 24h price changes from MarketViewModel
    private func buildPriceChangeCache() -> [String: Double] {
        var cache: [String: Double] = [:]
        for coin in MarketViewModel.shared.allCoins {
            if let change = coin.priceChangePercentage24hInCurrency {
                cache[coin.symbol.uppercased()] = change / 100.0 // Convert to fraction
            }
        }
        return cache
    }
    
    // MARK: - Pairs Cache (for instant loading)
    
    private func loadCachedPairs() {
        guard let data = UserDefaults.standard.data(forKey: Self.pairsCacheKey),
              let cached = try? JSONDecoder().decode([TradingPair].self, from: data) else {
            return
        }
        
        // Load timestamp
        let timestamp = UserDefaults.standard.object(forKey: Self.cacheTimestampKey) as? Date
        lastUpdated = timestamp
        
        // Update tradability based on current connected exchanges
        let connected = connectedExchangeIDs
        let updatedPairs = cached.map { pair -> TradingPair in
            let isTradable = connected.contains(pair.exchangeID)
            return TradingPair(
                baseSymbol: pair.baseSymbol,
                quoteSymbol: pair.quoteSymbol,
                exchangeID: pair.exchangeID,
                exchangeName: pair.exchangeName,
                priceUSD: pair.priceUSD,
                change24h: pair.change24h,
                change1h: pair.change1h,
                volume24hUSD: pair.volume24hUSD,
                isTradable: isTradable,
                iconURL: pair.iconURL
            )
        }
        
        pairs = sortPairs(updatedPairs)
        
        // If we have cached data, mark as loaded so we don't show "No pairs found"
        if !updatedPairs.isEmpty {
            hasLoadedOnce = true
        }
    }
    
    private func savePairsCache() {
        if let data = try? JSONEncoder().encode(pairs) {
            UserDefaults.standard.set(data, forKey: Self.pairsCacheKey)
            UserDefaults.standard.set(Date(), forKey: Self.cacheTimestampKey)
        }
    }
    
    /// Check if cache is still valid
    var isCacheValid: Bool {
        guard let timestamp = UserDefaults.standard.object(forKey: Self.cacheTimestampKey) as? Date else {
            return false
        }
        return Date().timeIntervalSince(timestamp) < Self.cacheValiditySeconds
    }
    
    /// Builds a cache of symbol -> 24h volume for sorting
    private func buildVolumeCache() -> [String: Double] {
        var cache: [String: Double] = [:]
        for coin in MarketViewModel.shared.allCoins {
            if let vol = coin.totalVolume, vol > 0 {
                cache[coin.symbol.uppercased()] = vol
            }
        }
        return cache
    }
    
    // MARK: - Recent Pairs
    
    /// Save a pair to recent history (updates both local state and shared service)
    func saveToRecentPairs(_ pair: TradingPair) {
        var recent = recentPairs
        
        // Remove if already exists (to move to front)
        recent.removeAll { $0.id == pair.id }
        
        // Add to front
        recent.insert(pair, at: 0)
        
        // Keep only last 5 for UI
        if recent.count > 5 {
            recent = Array(recent.prefix(5))
        }
        
        recentPairs = recent
        persistRecentPairs()
        
        // Also sync to shared service for AI context access
        TradingPairPreferencesService.shared.addToRecent(pair)
    }
    
    private func loadRecentPairs() {
        // Try loading from local storage first (for full TradingPair objects)
        if let data = UserDefaults.standard.data(forKey: Self.recentPairsKey),
           let pairs = try? JSONDecoder().decode([TradingPair].self, from: data) {
            recentPairs = pairs
            
            // Sync to shared service if we have local data
            for pair in pairs {
                TradingPairPreferencesService.shared.addToRecent(pair)
            }
        }
    }
    
    private func persistRecentPairs() {
        if let data = try? JSONEncoder().encode(recentPairs) {
            UserDefaults.standard.set(data, forKey: Self.recentPairsKey)
        }
    }
    
    /// Returns display name for exchange ID (pure function, no state access)
    nonisolated private func exchangeDisplayName(_ id: String) -> String {
        switch id.lowercased() {
        case "binance": return "Binance"
        case "coinbase": return "Coinbase"
        case "kraken": return "Kraken"
        case "kucoin": return "KuCoin"
        default: return id.capitalized
        }
    }
    
    /// Builds a cache of symbol -> imageURL for use in concurrent contexts
    /// Called on main actor before entering task groups to avoid actor-hopping
    private func buildImageURLCache() -> [String: URL] {
        var cache: [String: URL] = [:]
        for coin in MarketViewModel.shared.allCoins {
            if let url = coin.imageUrl {
                cache[coin.symbol.uppercased()] = url
            }
        }
        return cache
    }
    
    /// Resolves coin image URL from MarketViewModel's coin data
    /// Falls back to nil if coin is not found (CoinImageView has its own fallback chain)
    private func resolveImageURL(for symbol: String) -> URL? {
        let upper = symbol.uppercased()
        return MarketViewModel.shared.allCoins
            .first { $0.symbol.uppercased() == upper }?.imageUrl
    }
    
    /// Check if an exchange supports trading execution (has API implementation)
    /// Currently only Binance, BinanceUS, and Coinbase support actual order execution
    nonisolated func exchangeSupportsTradingExecution(_ exchangeID: String) -> Bool {
        // These exchanges have full trading API implementation
        let tradingExchanges = ["binance", "binance_us", "coinbase"]
        return tradingExchanges.contains(exchangeID.lowercased())
    }
}

// MARK: - TradingPairPickerView

struct TradingPairPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var vm = TradingPairPickerViewModel()
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    
    @Binding var selectedPair: String  // Base symbol
    @Binding var selectedQuote: String // Quote symbol
    @Binding var selectedExchange: String? // Exchange ID
    
    var onSelect: ((TradingPair) -> Void)?
    
    // State for view-only confirmation
    @State private var showViewOnlyAlert: Bool = false
    @State private var pendingViewOnlyPair: TradingPair?
    @State private var alternativeTradablePair: TradingPair?
    @FocusState private var isSearchFocused: Bool
    
    private var baseBG: Color {
        colorScheme == .dark ? Color.black : Color(.systemBackground)
    }
    
    private let goldBase = Color(red: 0.98, green: 0.82, blue: 0.20)
    
    private var relativeTimeFormatter: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }
    
    /// Whether to show the full exchange-specific view (developer mode) or simplified coin picker
    private var showDeveloperView: Bool {
        subscriptionManager.isDeveloperMode
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                baseBG.ignoresSafeArea()
                
                // Use unified picker for all users - developer mode adds exchange-specific elements
                mainPickerContent
            }
            .navigationTitle(showDeveloperView ? "Select Trading Pair" : "Select Coin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    CSNavButton(icon: "xmark", action: { dismiss() }, accessibilityText: "Close", compact: true)
                }
            }
            .task { await vm.load() }
            .refreshable {
                await vm.forceRefresh()
            }
            // View-only pair confirmation alert
            .alert("Market Data Only", isPresented: $showViewOnlyAlert) {
                if let alternative = alternativeTradablePair {
                    Button("Use \(alternative.exchangeName) Instead") {
                        if let pair = alternativeTradablePair {
                            confirmSelection(pair)
                        }
                    }
                }
                
                Button("View Anyway") {
                    if let pair = pendingViewOnlyPair {
                        // Still save to recent and select, even though view-only
                        vm.saveToRecentPairs(pair)
                        selectedPair = pair.baseSymbol
                        selectedQuote = pair.quoteSymbol
                        selectedExchange = pair.exchangeID
                        onSelect?(pair)
                        dismiss()
                    }
                }
                
                Button("Cancel", role: .cancel) {
                    pendingViewOnlyPair = nil
                    alternativeTradablePair = nil
                }
            } message: {
                if let pair = pendingViewOnlyPair {
                    if let alternative = alternativeTradablePair {
                        Text("\(pair.displayPair) on \(pair.exchangeName) is view-only. You can watch market data but cannot execute trades.\n\nThe same pair is available for trading on \(alternative.exchangeName).")
                    } else {
                        Text("\(pair.displayPair) on \(pair.exchangeName) is view-only. You can watch market data but cannot execute trades on this exchange.\n\nConnect an exchange in Settings for portfolio tracking.")
                    }
                }
            }
        }
    }
    
    // MARK: - Content Views
    
    /// Main picker content - used for all users
    /// Developer mode adds exchange-specific elements (tabs, badges)
    @ViewBuilder
    private var mainPickerContent: some View {
        VStack(spacing: 0) {
            searchBar
            
            // Only show exchange filter chips in developer mode
            if showDeveloperView {
                exchangeFilterChips
            }
            
            // Refreshing indicator (non-blocking)
            if vm.isRefreshing {
                HStack(spacing: 5) {
                    ProgressView()
                        .scaleEffect(0.65)
                    Text("Updating prices...")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .padding(.vertical, 2)
            }
            
            recentPairsSection
            
            // State-based content display
            if vm.isLoading && vm.pairs.isEmpty {
                loadingView
            } else if !vm.hasLoadedOnce && vm.pairs.isEmpty {
                loadingView
            } else if vm.filteredPairs.isEmpty {
                if !vm.searchText.isEmpty || vm.selectedExchange != nil || vm.showFavoritesOnly {
                    emptyStateView
                } else {
                    loadingView
                }
            } else {
                pairsList
            }
            
            // Last updated timestamp
            if let lastUpdated = vm.lastUpdated, !vm.pairs.isEmpty {
                HStack {
                    Spacer()
                    Text("Updated \(lastUpdated, formatter: relativeTimeFormatter)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.6))
                    Spacer()
                }
                .padding(.vertical, 6)
            }
        }
    }
    
    // MARK: - Subviews
    
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 15))
            
            // Different placeholder for regular users vs developers
            TextField(showDeveloperView ? "Search pairs or exchanges" : "Search coins", text: $vm.searchText)
                .foregroundColor(.primary)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture {
            isSearchFocused = true
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color(.systemGray6))
        )
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }
    
    private var exchangeFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" chip with count
                ExchangeFilterChip(
                    title: "All",
                    isSelected: vm.selectedExchange == nil && !vm.showFavoritesOnly,
                    color: goldBase,
                    pairCount: vm.pairCount(for: nil)
                ) {
                    vm.selectedExchange = nil
                    vm.showFavoritesOnly = false
                }
                
                // Favorites filter chip
                ExchangeFilterChip(
                    title: "Favorites",
                    isSelected: vm.showFavoritesOnly,
                    color: .orange,
                    showStar: true
                ) {
                    vm.showFavoritesOnly.toggle()
                    if vm.showFavoritesOnly {
                        vm.selectedExchange = nil
                    }
                }
                
                // Exchange chips with pair counts
                ForEach(vm.availableExchanges, id: \.self) { exchangeID in
                    let isConnected = vm.connectedExchangeIDs.contains(exchangeID)
                    let supportsTrade = vm.exchangeSupportsTradingExecution(exchangeID)
                    ExchangeFilterChip(
                        title: exchangeDisplayName(exchangeID),
                        isSelected: vm.selectedExchange == exchangeID && !vm.showFavoritesOnly,
                        color: exchangeColor(exchangeID),
                        showConnectionDot: isConnected,
                        isViewOnly: !supportsTrade,
                        pairCount: vm.pairCount(for: exchangeID)
                    ) {
                        vm.selectedExchange = exchangeID
                        vm.showFavoritesOnly = false
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }
    
    // MARK: - Recent Pairs Section
    
    @ViewBuilder
    private var recentPairsSection: some View {
        if !vm.recentPairs.isEmpty && vm.searchText.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("Recent")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(vm.recentPairs) { pair in
                            RecentPairChip(pair: pair, isSelected: isSelected(pair)) {
                                selectPair(pair)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 6)
        }
    }
    
    private var pairsList: some View {
        List {
            if showDeveloperView {
                // DEVELOPER MODE: Show sections for tradable vs view-only pairs
                
                // Tradable pairs section
                if !vm.tradablePairs.isEmpty {
                    Section {
                        ForEach(vm.tradablePairs) { pair in
                            TradingPairRow(
                                pair: pair,
                                isSelected: isSelected(pair),
                                onFavoriteToggle: { vm.toggleFavorite(pair) },
                                isFavorite: vm.isFavorite(pair),
                                showExchangeInfo: true
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { selectPair(pair) }
                            .swipeActions(edge: .trailing) {
                                Button {
                                    vm.toggleFavorite(pair)
                                } label: {
                                    Label(
                                        vm.isFavorite(pair) ? "Unfavorite" : "Favorite",
                                        systemImage: vm.isFavorite(pair) ? "star.slash" : "star.fill"
                                    )
                                }
                                .tint(.orange)
                            }
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 12))
                            Text("Ready to Trade")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Text("\(vm.tradablePairs.count) pairs")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                    }
                    .listRowBackground(baseBG)
                }
                
                // View-only pairs section
                if !vm.viewOnlyPairs.isEmpty {
                    Section {
                        ForEach(vm.viewOnlyPairs) { pair in
                            TradingPairRow(
                                pair: pair,
                                isSelected: isSelected(pair),
                                onFavoriteToggle: { vm.toggleFavorite(pair) },
                                isFavorite: vm.isFavorite(pair),
                                showExchangeInfo: true
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { selectPair(pair) }
                            .swipeActions(edge: .trailing) {
                                Button {
                                    vm.toggleFavorite(pair)
                                } label: {
                                    Label(
                                        vm.isFavorite(pair) ? "Unfavorite" : "Favorite",
                                        systemImage: vm.isFavorite(pair) ? "star.slash" : "star.fill"
                                    )
                                }
                                .tint(.orange)
                            }
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Image(systemName: "eye.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 12))
                            Text("Market Data Only")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Text("\(vm.viewOnlyPairs.count) pairs")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                    } footer: {
                        Text("Connect Kraken or KuCoin in Settings to track these pairs in your portfolio.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                    .listRowBackground(baseBG)
                }
            } else {
                // REGULAR USER MODE: Single unified list for paper trading
                // No sections, no exchange-specific info
                ForEach(unifiedCoinList) { pair in
                    TradingPairRow(
                        pair: pair,
                        isSelected: isSelected(pair),
                        onFavoriteToggle: { vm.toggleFavorite(pair) },
                        isFavorite: vm.isFavorite(pair),
                        showExchangeInfo: false  // Hide exchange badges for paper trading
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { selectPairForPaperTrading(pair) }
                    .swipeActions(edge: .trailing) {
                        Button {
                            vm.toggleFavorite(pair)
                        } label: {
                            Label(
                                vm.isFavorite(pair) ? "Unfavorite" : "Favorite",
                                systemImage: vm.isFavorite(pair) ? "star.slash" : "star.fill"
                            )
                        }
                        .tint(.orange)
                    }
                }
                .listRowBackground(baseBG)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
    
    /// Unified coin list for paper trading - deduplicated by symbol, sorted by popularity
    private var unifiedCoinList: [TradingPair] {
        // Group pairs by base symbol and pick the best one (highest volume)
        var coinMap: [String: TradingPair] = [:]
        
        for pair in vm.filteredPairs {
            let symbol = pair.baseSymbol.uppercased()
            
            // Keep the pair with the highest volume (or first if equal)
            if let existing = coinMap[symbol] {
                if (pair.volume24hUSD ?? 0) > (existing.volume24hUSD ?? 0) {
                    coinMap[symbol] = pair
                }
            } else {
                coinMap[symbol] = pair
            }
        }
        
        // Sort by popularity rank, then by symbol
        return coinMap.values.sorted { 
            if $0.popularityRank != $1.popularityRank {
                return $0.popularityRank < $1.popularityRank
            }
            return $0.baseSymbol < $1.baseSymbol
        }
    }
    
    /// Select a coin for paper trading (no specific exchange)
    private func selectPairForPaperTrading(_ pair: TradingPair) {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        
        vm.saveToRecentPairs(pair)
        selectedPair = pair.baseSymbol
        selectedQuote = "USD"  // Always use USD for paper trading
        selectedExchange = nil  // No specific exchange
        onSelect?(pair)
        dismiss()
    }
    
    private var loadingView: some View {
        VStack(spacing: 0) {
            // Header with loading indicator
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Loading trading pairs...")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 12)
            
            // Skeleton rows for better perceived performance
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { _ in
                        SkeletonPairRow()
                            .padding(.horizontal, 16)
                    }
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No pairs found")
                .font(.headline)
                .foregroundColor(.primary)
            Text("Try a different search or filter")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Helpers
    
    private func isSelected(_ pair: TradingPair) -> Bool {
        pair.baseSymbol == selectedPair && pair.quoteSymbol == selectedQuote
    }
    
    private func selectPair(_ pair: TradingPair) {
        // ONLY show view-only warning when live trading is actually enabled (developer mode)
        // For regular users (paper trading, portfolio tracking), exchange tradability doesn't matter:
        // - Paper trading is simulated, doesn't use exchange APIs
        // - Portfolio tracking is view-only by design
        // - Live trading is developer-only feature
        let shouldWarnAboutViewOnly = AppConfig.liveTradingEnabled && !pair.isTradable
        
        if shouldWarnAboutViewOnly {
            // Find an alternative tradable pair with the same base symbol
            let tradableAlternative = vm.pairs.first { alt in
                alt.baseSymbol == pair.baseSymbol && alt.isTradable
            }
            
            pendingViewOnlyPair = pair
            alternativeTradablePair = tradableAlternative
            showViewOnlyAlert = true
            return
        }
        
        confirmSelection(pair)
    }
    
    private func confirmSelection(_ pair: TradingPair) {
        // Save to recent pairs for quick access
        vm.saveToRecentPairs(pair)
        
        selectedPair = pair.baseSymbol
        selectedQuote = pair.quoteSymbol
        selectedExchange = pair.exchangeID
        onSelect?(pair)
        dismiss()
    }
    
    private func exchangeDisplayName(_ id: String) -> String {
        switch id.lowercased() {
        case "binance": return "Binance"
        case "coinbase": return "Coinbase"
        case "kraken": return "Kraken"
        case "kucoin": return "KuCoin"
        default: return id.capitalized
        }
    }
    
    private func exchangeColor(_ id: String) -> Color {
        switch id.lowercased() {
        case "binance": return .yellow
        case "coinbase": return .blue
        case "kraken": return .purple
        case "kucoin": return .green
        default: return .gray
        }
    }
}

// MARK: - Exchange Filter Chip

private struct ExchangeFilterChip: View {
    let title: String
    let isSelected: Bool
    let color: Color
    var showConnectionDot: Bool = false
    var isViewOnly: Bool = false
    var pairCount: Int? = nil
    var showStar: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if showStar {
                    Image(systemName: isSelected ? "star.fill" : "star")
                        .font(.system(size: 10))
                        .foregroundColor(isSelected ? .black : .orange)
                }
                
                if showConnectionDot {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 5, height: 5)
                }
                
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                
                // Show pair count badge
                if let count = pairCount, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(isSelected ? color.opacity(0.8) : .secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.black.opacity(0.2) : Color.secondary.opacity(0.15))
                        )
                }
                
                // Show eye icon for view-only exchanges
                if isViewOnly && !isSelected {
                    Image(systemName: "eye")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            .foregroundColor(isSelected ? .black : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? color : Color.clear)
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recent Pair Chip

private struct RecentPairChip: View {
    let pair: TradingPair
    let isSelected: Bool
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    private let goldBase = Color(red: 0.98, green: 0.82, blue: 0.20)
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                CoinImageView(symbol: pair.baseSymbol, url: pair.iconURL, size: 22)
                
                VStack(alignment: .leading, spacing: 0) {
                    Text(pair.displayPair)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 3) {
                        Circle()
                            .fill(exchangeColor)
                            .frame(width: 4, height: 4)
                        Text(pair.exchangeName)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(goldBase)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? goldBase.opacity(0.15) : (colorScheme == .dark ? Color.white.opacity(0.08) : Color(.systemGray6)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? goldBase.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var exchangeColor: Color {
        switch pair.exchangeID.lowercased() {
        case "binance": return .yellow
        case "coinbase": return .blue
        case "kraken": return .purple
        case "kucoin": return .green
        default: return .gray
        }
    }
}

// MARK: - Skeleton Loading Row

private struct SkeletonPairRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Skeleton coin icon
            Circle()
                .fill(shimmerGradient)
                .frame(width: 40, height: 40)
            
            // Skeleton text
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(shimmerGradient)
                    .frame(width: 100, height: 14)
                
                RoundedRectangle(cornerRadius: 3)
                    .fill(shimmerGradient)
                    .frame(width: 70, height: 10)
            }
            
            Spacer()
            
            // Skeleton price
            VStack(alignment: .trailing, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(shimmerGradient)
                    .frame(width: 80, height: 14)
                
                RoundedRectangle(cornerRadius: 3)
                    .fill(shimmerGradient)
                    .frame(width: 50, height: 10)
            }
        }
        .padding(.vertical, 10)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
    
    private var shimmerGradient: LinearGradient {
        LinearGradient(
            colors: [
                colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06),
                colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.12),
                colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
            ],
            startPoint: isAnimating ? .leading : .trailing,
            endPoint: isAnimating ? .trailing : .leading
        )
    }
}

// MARK: - Trading Pair Row

private struct TradingPairRow: View {
    let pair: TradingPair
    let isSelected: Bool
    var onFavoriteToggle: (() -> Void)? = nil
    var isFavorite: Bool = false
    /// When false, hides exchange-specific elements (badges, exchange name, view-only indicators)
    /// Used for paper trading mode where exchange doesn't matter
    var showExchangeInfo: Bool = true
    
    @Environment(\.colorScheme) private var colorScheme
    
    private let goldBase = Color(red: 0.98, green: 0.82, blue: 0.20)
    
    var body: some View {
        HStack(spacing: 12) {
            // Coin icon - uses CoinImageView with fallback chain
            ZStack(alignment: .bottomTrailing) {
                CoinImageView(symbol: pair.baseSymbol, url: pair.iconURL, size: 40)
                
                // Show trading status badge on icon (only in developer/exchange mode)
                if showExchangeInfo && pair.isTradable {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 12, height: 12)
                        .overlay(
                            Image(systemName: "checkmark")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundColor(.white)
                        )
                        .offset(x: 2, y: 2)
                }
            }
            
            // Pair info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    // Show just the coin symbol for paper trading, full pair for exchange mode
                    Text(showExchangeInfo ? pair.displayPair : pair.baseSymbol.uppercased())
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    // Only show View Only badge in exchange mode
                    if showExchangeInfo && !pair.isTradable {
                        // Prominent view-only indicator
                        HStack(spacing: 3) {
                            Image(systemName: "eye.fill")
                                .font(.system(size: 9))
                            Text("View Only")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.orange.opacity(0.15))
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.orange.opacity(0.3), lineWidth: 0.5)
                        )
                    }
                }
                
                // Exchange info row - only in developer mode
                if showExchangeInfo {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(exchangeColor)
                            .frame(width: 6, height: 6)
                        Text(pair.exchangeName)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        
                        // Show "Connected" label for tradable pairs
                        if pair.isTradable {
                            Text("Connected")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.green)
                        }
                    }
                } else {
                    // Paper trading subtitle
                    Text("Paper Trading")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.8))
                }
            }
            
            Spacer()
            
            // Price and change
            VStack(alignment: .trailing, spacing: 3) {
                Text(formatPrice(pair.priceUSD))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                    .monospacedDigit()
                
                if let change = pair.change24h {
                    HStack(spacing: 2) {
                        Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 9, weight: .semibold))
                        Text(formatPercent(change))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(change >= 0 ? .green : .red)
                    .monospacedDigit()
                }
            }
            
            // Favorite star button - easily tappable
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                onFavoriteToggle?()
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 18))
                    .foregroundColor(isFavorite ? Color(red: 0.92, green: 0.75, blue: 0.23) : .white.opacity(0.4))
            }
            .buttonStyle(.plain)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
            
            // Selection indicator - always reserve space for consistent alignment
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(goldBase)
                .opacity(isSelected ? 1 : 0)
                .frame(width: 20, alignment: .center)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        // Add subtle background for view-only pairs (only in exchange mode)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill((showExchangeInfo && !pair.isTradable) ? Color.orange.opacity(0.03) : Color.clear)
        )
    }
    
    private var exchangeColor: Color {
        switch pair.exchangeID.lowercased() {
        case "binance": return .yellow
        case "coinbase": return .blue
        case "kraken": return .purple
        case "kucoin": return .green
        default: return .gray
        }
    }
    
    private func formatPrice(_ value: Double) -> String {
        guard value > 0 else { return "$0.00" }
        if value < 0.01 {
            return String(format: "$%.6f", value)
        } else if value < 1 {
            return String(format: "$%.4f", value)
        } else if value < 1000 {
            return String(format: "$%.2f", value)
        } else {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 2
            return "$" + (formatter.string(from: NSNumber(value: value)) ?? "0.00")
        }
    }
    
    private func formatPercent(_ frac: Double) -> String {
        let pct = frac * 100
        let sign = pct >= 0 ? "+" : ""
        return String(format: "%@%.2f%%", sign, pct)
    }
}

// MARK: - Preview

#Preview {
    TradingPairPickerView(
        selectedPair: .constant("BTC"),
        selectedQuote: .constant("USDT"),
        selectedExchange: .constant(nil)
    )
    .preferredColorScheme(.dark)
}
