import SwiftUI
import Combine
import Foundation

/// Encodable model combining holdings and transactions for AI insights
struct Portfolio: Encodable {
    let holdings: [Holding]
    let transactions: [Transaction]
}


// MARK: - Sample Data for Previews
extension PortfolioViewModel {
    /// A sample instance with demo holdings for SwiftUI previews and Debug builds.
    static let sample: PortfolioViewModel = {
        let manualService = ManualPortfolioDataService(initialHoldings: [], initialTransactions: [])
        let liveService = LivePortfolioDataService()
        // PERFORMANCE FIX: Use shared singleton to reduce API request storms
        let priceService = CoinGeckoPriceService.shared
        let repository = PortfolioRepository(
            manualService: manualService,
            liveService: liveService,
            priceService: priceService
        )
        let vm = PortfolioViewModel(repository: repository)
        // Override holdings to match realistic demo values for App Store submission
        vm.holdings = [
            // 0.5 BTC at $65,000 = $32,500
            Holding(coinName: "Bitcoin", coinSymbol: "BTC", quantity: 0.5, currentPrice: 65_000, costBasis: 50_000, imageUrl: nil, isFavorite: true, dailyChange: 1.2, purchaseDate: Date()),
            // 8 ETH at $2,400 = $19,200
            Holding(coinName: "Ethereum", coinSymbol: "ETH", quantity: 8, currentPrice: 2_400, costBasis: 1_800, imageUrl: nil, isFavorite: false, dailyChange: -0.8, purchaseDate: Date()),
            // 50 SOL at $80 = $4,000
            Holding(coinName: "Solana", coinSymbol: "SOL", quantity: 50, currentPrice: 80, costBasis: 60, imageUrl: nil, isFavorite: false, dailyChange: 2.5, purchaseDate: Date()),
            // 2,500 XRP at $1.35 = $3,375
            Holding(coinName: "XRP", coinSymbol: "XRP", quantity: 2_500, currentPrice: 1.35, costBasis: 0.5, imageUrl: nil, isFavorite: false, dailyChange: 0.3, purchaseDate: Date())
        ]
        // Optionally clear or set demo transactions
        vm.transactions = []
        // Build a mock history where yesterday’s total was 2% lower than today
        let today = Date()
        let previousValue = vm.totalValue * 0.98
        var mockPoints: [ChartPoint] = []
        for daysAgo in 0...30 {
            // SAFETY FIX: Use guard let instead of force unwrap
            guard let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            let value = (daysAgo == 0) ? vm.totalValue : previousValue
            mockPoints.append(ChartPoint(date: date, value: value))
        }
        vm.history = mockPoints
        return vm
    }()
}

// MARK: - Chart Data Model
struct ChartPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

extension ChartPoint: Equatable {
    static func == (lhs: ChartPoint, rhs: ChartPoint) -> Bool {
        return lhs.date == rhs.date && lhs.value == rhs.value
    }
}


// MARK: - Color Mapping for Pie Charts
extension PortfolioViewModel {
    /// Returns the chart color associated with a given coin symbol.
    func color(for symbol: String) -> Color {
        // Curated palette designed for dark backgrounds; high contrast, minimal confusion
        let palette: [UInt32] = [
            0x2891FF, // blue
            0x1ABC9C, // teal
            0xF39C12, // orange
            0x9B59B6, // purple
            0xE74C3C, // red
            0x2ECC71, // green
            0xE84393, // pink
            0x8E44AD, // deep purple
            0x2980B9, // blue 2
            0x00C2FF, // cyan
            0xF1C40F, // gold
            0x16A085, // green‑teal
            0x34495E, // slate
            0xFF4D4F, // coral red
            0x27AE60, // green 2
            0xD35400  // burnt orange
        ]

        // Preferred brand mappings for well‑known symbols (crypto + stocks)
        let map: [String: UInt32] = [
            // Crypto
            "BTC": 0x2891FF,
            "ETH": 0x1ABC9C,
            "SOL": 0xF39C12,
            "XRP": 0x9B59B6,
            "BNB": 0xF1C40F,
            "ADA": 0x3498DB,
            "DOGE": 0xE67E22,
            "LTC": 0x95A5A6,
            "DOT": 0xE84393,
            "AVAX": 0xE74C3C,
            "MATIC": 0x8E44AD,
            "LINK": 0x2980B9,
            "ATOM": 0x16A085,
            "NEAR": 0x2ECC71,
            "FTM": 0x2C3E50,
            "SUI": 0x00C2FF,
            "APT": 0xC0392B,
            "ARB": 0x00A3FF,
            "OP":  0xFF4D4F,
            "USDC": 0x3C7BF6,
            "USDT": 0x26A17B,
            "DAI":  0xF4B731,
            // Stocks
            "AAPL": 0x999999,   // Apple - silver/gray
            "TSLA": 0xE74C3C,   // Tesla - red
            "NVDA": 0x76B900,   // Nvidia - green
            "MSFT": 0x00A4EF,   // Microsoft - blue
            "GOOGL": 0x4285F4,  // Google - blue
            "GOOG": 0x4285F4,   // Google - blue
            "AMZN": 0xFF9900,   // Amazon - orange
            "META": 0x0866FF,   // Meta - blue
            "NFLX": 0xE50914,   // Netflix - red
            "AMD": 0x008888,    // AMD - teal
            "INTC": 0x0071C5,   // Intel - blue
            "CRM": 0x00A1E0,    // Salesforce - blue
            "PYPL": 0x003087,   // PayPal - dark blue
            "SQ": 0x00D632,     // Block/Square - green
            "COIN": 0x0052FF,   // Coinbase - blue
            "HOOD": 0x00D632,   // Robinhood - green
            // ETFs
            "VOO": 0x951B1E,    // Vanguard - maroon
            "SPY": 0x005544,    // SPDR - dark green
            "QQQ": 0x005BA1,    // Invesco - blue
            "VTI": 0x951B1E,    // Vanguard - maroon
            "IWM": 0x000000,    // iShares - black
            "DIA": 0x005544     // SPDR - dark green
        ]

        let sym = symbol.uppercased()
        if let hex = map[sym] { return Color(hex: hex) }

        // Stable assignment: hash into the curated palette so different symbols pick different colors
        let h = abs(sym.hashValue)
        let idx = h % palette.count
        return Color(hex: palette[idx])
    }
}

// Convenience initializer for Color(hex:)
private extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b, opacity: alpha)
    }
}


// MARK: - Formatters for Signed Values
extension PortfolioViewModel {
    /// Formatter for signed percent (e.g. "+1.23%", "−0.45%")
    static let percentFormatter: NumberFormatter = {
        let fmt = NumberFormatter()
        fmt.numberStyle = .percent
        fmt.minimumFractionDigits = 2
        fmt.maximumFractionDigits = 2
        fmt.positivePrefix = "+"
        fmt.negativePrefix = "−"
        return fmt
    }()

    /// Formatter for signed currency (e.g. "+$1,234.56", "−$987.65")
    static let signedCurrencyFormatter: NumberFormatter = {
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.minimumFractionDigits = 2
        fmt.maximumFractionDigits = 2
        let symbol = fmt.currencySymbol ?? "$"
        fmt.positivePrefix = "+" + symbol
        fmt.negativePrefix = "−" + symbol
        return fmt
    }()
}

// MARK: - Computed Metrics
extension PortfolioViewModel {
    /// 24h percentage change based on previous total value, mock-aware.
    var dailyChangePercent: Double {
        // If demo override is active, prefer the persisted mock percent when history is insufficient
        if demoOverrideEnabled {
            // Try to compute from history first
            let cal = Calendar.current
            let yDate = cal.date(byAdding: .day, value: -1, to: Date())!
            if let prev = history.first(where: { cal.isDate($0.date, inSameDayAs: yDate) })?.value, prev != 0, prev != totalValue {
                return (totalValue - prev) / prev * 100
            }
            // Fallback to the configured mock percent
            let mock = UserDefaults.standard.object(forKey: "portfolio_mock_daily_change") as? Double ?? 2.0
            return mock
        }
        // Normal path: compute from history; if missing, return 0
        let cal = Calendar.current
        let yDate = cal.date(byAdding: .day, value: -1, to: Date())!
        let previousTotalValue = history.first(where: { cal.isDate($0.date, inSameDayAs: yDate) })?.value ?? totalValue
        guard previousTotalValue != 0 else { return 0 }
        return (totalValue - previousTotalValue) / previousTotalValue * 100
    }

    /// Formatted daily change percent string (e.g. "+1.23%")
    var dailyChangePercentString: String {
        return Self.percentFormatter.string(from: NSNumber(value: dailyChangePercent / 100)) ?? "0.00%"
    }

    /// Unrealized profit/loss (current total minus cost basis of holdings)
    var unrealizedPL: Double {
        // Sum of (currentValue - costBasis * quantity) for each holding
        holdings.reduce(0) { result, holding in
            let cost = holding.costBasis * holding.quantity
            return result + (holding.currentValue - cost)
        }
    }

    /// Formatted unrealized P/L string (e.g. "+$123.45")
    var unrealizedPLString: String {
        return Self.signedCurrencyFormatter.string(from: NSNumber(value: unrealizedPL)) ?? "$0.00"
    }
}

// MARK: - Allocation Data for Charts
extension PortfolioViewModel {
    /// Represents one slice of the portfolio allocation for charting.
    /// Uses `symbol` as the stable identity so SwiftUI can animate smoothly
    /// when allocation percentages change (e.g., on price updates).
    struct AllocationSlice: Identifiable, Equatable {
        var id: String { symbol }
        let symbol: String
        let percent: Double
        let color: Color

        static func == (lhs: AllocationSlice, rhs: AllocationSlice) -> Bool {
            lhs.symbol == rhs.symbol
                && lhs.percent == rhs.percent
                && lhs.color == rhs.color
        }
    }

    /// Breaks holdings into percentage slices for the donut chart.
    /// Respects user preferences for including stocks in the pie chart.
    var allocationData: [AllocationSlice] {
        // Check user preferences (with proper defaults)
        let showStocks = UserDefaults.standard.bool(forKey: "showStocksInPortfolio")
        // Default to true if key doesn't exist
        let includeStocksInPie = UserDefaults.standard.object(forKey: "includeStocksInPieChart") as? Bool ?? true
        
        // Filter holdings based on preferences
        let filteredHoldings: [Holding]
        if showStocks && includeStocksInPie {
            // Include all holdings (crypto + stocks + commodities)
            filteredHoldings = holdings
        } else {
            // Include crypto AND commodities (precious metals from Coinbase)
            // Commodities should always be visible in the pie chart
            filteredHoldings = holdings.filter { $0.assetType == .crypto || $0.assetType == .commodity }
        }
        
        // Calculate total value of filtered holdings
        let total = filteredHoldings.reduce(0) { $0 + $1.currentValue }
        guard total > 0 else { return [] }
        
        // Merge holdings that share the same display symbol (e.g., BTC from multiple exchanges)
        // so each slice has a unique symbol for stable SwiftUI identity.
        // For commodities, use the human-readable name (e.g., "Gold") instead of the raw
        // Yahoo Finance ticker (e.g., "GC=F") for a cleaner UI in chips and pie chart.
        var merged: [String: (value: Double, holding: Holding)] = [:]
        for position in filteredHoldings {
            let sym: String
            // Always try the commodity mapper first — handles cases where assetType
            // may not be .commodity but the ticker is a Yahoo Finance commodity (e.g., "GC=F")
            let rawTicker = position.ticker ?? position.coinSymbol
            if let info = CommoditySymbolMapper.getCommodity(for: rawTicker) {
                sym = info.name  // "Gold", "Silver", "Crude Oil WTI", etc.
            } else {
                sym = position.displaySymbol
            }
            if let existing = merged[sym] {
                merged[sym] = (existing.value + position.currentValue, existing.holding)
            } else {
                merged[sym] = (position.currentValue, position)
            }
        }
        
        let raw = merged.map { (sym, info) in
            AllocationSlice(
                symbol: sym,
                percent: (info.value / total) * 100,
                color: color(for: info.holding)
            )
        }
        // Group <1% into Other
        let (large, small) = raw.partitioned { $0.percent >= 1.0 }
        let otherPercent = small.reduce(0) { $0 + $1.percent }
        let otherSlice = otherPercent > 0 ? [AllocationSlice(symbol: "OTHER", percent: otherPercent, color: .gray)] : []
        return large.sorted { $0.percent > $1.percent } + otherSlice
    }
}

@MainActor
class PortfolioViewModel: ObservableObject {
    static let shared = PortfolioViewModel(repository: PortfolioRepository.shared)

    // Demo/Mock controls - now uses unified DemoModeManager
    private static let mockDailyChangeKey = "portfolio_mock_daily_change"
    
    /// Returns whether demo mode is enabled via the unified DemoModeManager
    private var isDemoModeEnabled: Bool {
        DemoModeManager.shared.isDemoMode
    }
    
    private var mockDailyChangePercent: Double {
        get {
            let v = UserDefaults.standard.double(forKey: Self.mockDailyChangeKey)
            return v == 0 ? 2.0 : v // default to +2% if unset
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.mockDailyChangeKey) }
    }

    // MARK: - Persistence URL
    // SAFETY FIX: Use safe directory accessor instead of force unwrap
    private let transactionsFileURL: URL = {
        return FileManager.documentsDirectory.appendingPathComponent("transactions.json")
    }()

    // Repository providing unified holdings (manual, synced, live-priced)
    private let repository: PortfolioRepository

    // Combine cancellables (internal for extension access)
    var cancellables = Set<AnyCancellable>()
    @Published var isRefreshing: Bool = false

    /// Reload holdings from the repository
    func refreshHoldings() async {
        await repository.syncBrokerageAccounts()
    }
    // Mock price ticker to keep demo portfolios feeling live
    private var mockTickerTimer: Timer?
    // Commodity price refresh timer for precious metals
    private var commodityPriceTimer: Timer?
    private var lastLiveUpdateAt: Date = .distantPast

    /// Initialize with a repository providing unified holdings.
    init(repository: PortfolioRepository) {
        self.repository = repository

        // PERFORMANCE FIX: Load transactions asynchronously to avoid blocking main thread
        // This allows the UI to render immediately while data loads in background
        Task { @MainActor [weak self] in
            await self?.loadTransactionsAsync()
        }

        // Subscribe to exchange-synced holdings from repository
        // MERGE with local holdings (from CSV/manual transactions) rather than replacing
        // PERFORMANCE FIX: Added 300ms debounce to prevent rapid updates
        repository.holdingsPublisher
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] exchangeHoldings in
                guard let self = self else { return }
                // Defer state modifications to avoid "Modifying state during view update"
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    // Ignore repository updates while demo override is active
                    guard !self.demoOverrideEnabled else { return }
                    
                    // Merge exchange holdings with local holdings (CSV/manual take precedence)
                    self.mergeExchangeHoldings(exchangeHoldings)
                    
                    // STARTUP FIX: Immediately refresh prices from the best available source.
                    // Without this, holdings arrive with currentPrice=0 from the repository
                    // and the portfolio shows a wrong total value until slowPublisher fires (~2s).
                    self.refreshHoldingPricesFromBestSource()
                    
                    self.loadHistory()
                }
            }
            .store(in: &cancellables)

        // Subscribe to live prices and update holdings
        // Note: startPolling() is called by CryptoSageAIApp.startHeavyLoading() during app startup
        // PERFORMANCE FIX: Use slowPublisher (2s throttle) for portfolio - doesn't need real-time updates
        // This significantly reduces UI update frequency and improves scrolling performance
        LivePriceManager.shared.slowPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] marketCoins in
                guard let self = self else { return }
                // PERFORMANCE FIX: Skip updates during scroll to prevent jank
                guard !ScrollStateManager.shared.isScrolling else { return }
                // Defer state modifications to avoid "Modifying state during view update"
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    // Skip live price updates when demo override is active to keep demo values consistent
                    guard !self.demoOverrideEnabled else { return }
                    self.updateHoldingsWithMarketData(marketCoins)
                }
            }
            .store(in: &cancellables)
        
        // FIX v25: Eagerly update holdings with fresh market data once available.
        // On cold start, holdings may have zero or stale prices from the repository.
        // MarketViewModel.allCoins gets populated from cache first, then from Firestore/API.
        // Subscribe to ALL updates (not just first) to ensure prices are refreshed ASAP.
        // The first non-empty emission triggers immediate price refresh.
        MarketViewModel.shared.$allCoins
            .filter { !$0.isEmpty }
            .first()      // One-shot: only need the first meaningful update
            .receive(on: DispatchQueue.main)
            .sink { [weak self] allCoins in
                guard let self = self else { return }
                guard !self.demoOverrideEnabled else { return }
                guard !self.holdings.isEmpty else { return }
                self.updateHoldingsWithMarketData(allCoins)
            }
            .store(in: &cancellables)
        
        // STARTUP FIX: Also subscribe to LivePriceManager's raw publisher (no throttle)
        // for the FIRST emission only. This catches Firestore-delivered prices that arrive
        // before the 2s slowPublisher throttle, eliminating the window where portfolio
        // shows $0 for BTC/SOL/etc. while USDT shows correctly.
        LivePriceManager.shared.publisher
            .filter { !$0.isEmpty }
            .first()      // One-shot: just need the first fresh emission
            .receive(on: DispatchQueue.main)
            .sink { [weak self] freshCoins in
                guard let self = self else { return }
                guard !self.demoOverrideEnabled else { return }
                guard !self.holdings.isEmpty else { return }
                // Use refreshHoldingPricesFromBestSource which checks ALL sources
                self.refreshHoldingPricesFromBestSource()
            }
            .store(in: &cancellables)
        
        // Subscribe to live stock price updates
        // PERFORMANCE FIX: Added 1-second throttle to prevent excessive UI updates
        LiveStockPriceManager.shared.quotesPublisher
            .throttle(for: .seconds(1), scheduler: DispatchQueue.main, latest: true)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] quotes in
                guard let self = self else { return }
                // PERFORMANCE FIX: Skip updates during scroll
                guard !ScrollStateManager.shared.isScrolling else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    // Skip updates when demo override is active
                    guard !self.demoOverrideEnabled else { return }
                    self.updateStockHoldingsWithQuotes(quotes)
                }
            }
            .store(in: &cancellables)
        
        // Start tracking stocks from existing holdings after a short delay
        // This allows the view model to be fully initialized first
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.startStockPriceTracking()
        }
        
        // Start commodity (precious metals) price updates after initialization
        // Refresh every 60 seconds if there are commodity holdings
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.startCommodityPriceTracking()
        }
        
        // MISSING PRICE FIX: Short retry window to catch holdings whose prices were unavailable
        // at first render. Fires at 3s and 6s after init — enough time for Firestore/API data
        // to arrive, but not so aggressive as to be wasteful. Only runs if prices are still missing.
        for delay in [3.0, 6.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self, !self.demoOverrideEnabled, !self.holdings.isEmpty else { return }
                let hasMissing = self.holdings.contains { $0.currentPrice <= 0 }
                if hasMissing {
                    self.refreshHoldingPricesFromBestSource()
                }
            }
        }
        
        // If demo mode is enabled, seed demo data and start mock ticker
        // Note: We no longer auto-enable demo mode when holdings are empty - the user controls this via Settings
        // FIX: Always reseed demo data when demo mode is active, regardless of existing holdings.
        // Previously this only seeded when holdings.isEmpty, which caused the demo portfolio to show
        // the user's real/manual holdings (e.g. "Gold 100%") instead of the demo crypto portfolio.
        if isDemoModeEnabled {
            let seed = Self.buildDemoSeed(mockDailyPercent: mockDailyChangePercent)
            applyDemoSeed(holdings: seed.holdings, history: seed.history)
            startMockTicker()
        }
        
        // Subscribe to demo mode changes from DemoModeManager.
        // This ensures demo data is cleared when demo mode is disabled from ANY location
        // (e.g., Trading page, Settings, etc.) - not just when explicitly called here.
        DemoModeManager.shared.$isDemoMode
            .dropFirst() // Skip initial value - we handle initial state above
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isDemoEnabled in
                guard let self = self else { return }
                if !isDemoEnabled {
                    // Demo mode was disabled - clear demo data
                    self.disableDemoMode()
                } else {
                    // Demo mode was enabled - always reseed demo data
                    // FIX: Previously only seeded when holdings.isEmpty, which caused demo mode
                    // to incorrectly show the user's real/manual holdings instead of demo data.
                    let seed = Self.buildDemoSeed(mockDailyPercent: self.mockDailyChangePercent)
                    self.applyDemoSeed(holdings: seed.holdings, history: seed.history)
                    self.startMockTicker()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Published Properties
    @Published var holdings: [Holding] = []
    @Published var history: [ChartPoint] = []
    @Published var highlightedDate: Date? = nil
    @Published var transactions: [Transaction] = []

    /// When true, ignore repository-driven holdings updates and use seeded demo data.
    @Published var demoOverrideEnabled: Bool = false
    
    // MARK: - Staleness Tracking (for UI indicators)
    /// Threshold for considering portfolio prices stale (30 seconds)
    static let stalePriceThreshold: TimeInterval = 30.0
    
    /// Returns true if portfolio prices haven't been updated in >30 seconds
    var arePricesStale: Bool {
        guard !demoOverrideEnabled else { return false } // Demo mode never shows stale
        return Date().timeIntervalSince(lastLiveUpdateAt) > Self.stalePriceThreshold
    }
    
    /// Human-readable description of when prices were last updated
    var lastUpdateDescription: String? {
        guard lastLiveUpdateAt != .distantPast else { return nil }
        let interval = Date().timeIntervalSince(lastLiveUpdateAt)
        
        if interval < 5 {
            return "just now"
        } else if interval < 60 {
            return "\(Int(interval))s ago"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        }
    }
    
    /// Returns the time since last update, or nil if never updated
    var timeSinceLastUpdate: TimeInterval? {
        guard lastLiveUpdateAt != .distantPast else { return nil }
        return Date().timeIntervalSince(lastLiveUpdateAt)
    }

    /// Combined portfolio data for AIInsightService
    var portfolio: Portfolio {
        Portfolio(holdings: holdings, transactions: transactions)
    }

    // Computed property for total portfolio value.
    var totalValue: Double {
        holdings.reduce(0) { $0 + $1.currentValue }
    }
    
    // MARK: - Transaction and Holding Management
    
    /// Removes a holding at the given index set.
    func removeHolding(at indexSet: IndexSet) {
        holdings.remove(atOffsets: indexSet)
    }
    
    // MARK: - Add a Holding
    
    /// Creates and appends a new Holding to the array, matching what AddHoldingView calls.
    func addHolding(
        coinName: String,
        coinSymbol: String,
        quantity: Double,
        currentPrice: Double,
        costBasis: Double,
        imageUrl: String?,
        purchaseDate: Date
    ) {
        let newHolding = Holding(
            coinName: coinName,
            coinSymbol: coinSymbol,
            quantity: quantity,
            currentPrice: currentPrice,
            costBasis: costBasis,
            imageUrl: imageUrl,
            isFavorite: false,    // default to not-favorite
            dailyChange: 0.0,     // or fetch real data if available
            purchaseDate: purchaseDate
        )
        
        holdings.append(newHolding)
    }
    
    // MARK: - Toggle Favorite
    
    /// Toggles the isFavorite flag on a specific holding.
    func toggleFavorite(_ holding: Holding) {
        guard let index = holdings.firstIndex(where: { $0.id == holding.id }) else { return }
        holdings[index].isFavorite.toggle()
    }
    
    /// Manually refreshes market and portfolio-related data for pull-to-refresh.
    func manualRefresh() {
        // Kick off a market refresh; this updates coins and derived slices used across the app.
        Task { await MarketViewModel.shared.loadAllData() }
        // Optionally reload history or recompute derived metrics if needed.
        loadHistory()
        // Defer to avoid "Modifying state during view update" warnings
        Task { self.objectWillChange.send() }
    }
    
    // MARK: - Live Price Updates
    
    /// FIX v24: Shared logic for updating holdings with fresh market data.
    /// Extracted from the slowPublisher sink to be reusable by the eager one-shot
    /// subscription that fires when MarketViewModel first loads fresh data.
    /// This ensures portfolio total value is correct as soon as prices arrive,
    /// rather than waiting for the next slowPublisher emission (up to 2s throttle).
    private func updateHoldingsWithMarketData(_ marketCoins: [MarketCoin]) {
        self.lastLiveUpdateAt = Date()
        // Update each holding's currentPrice and dailyChange based on market data.
        // Preserve existing non-zero price if live price is missing or zero.
        self.holdings = self.holdings.map { holding in
            let coin = marketCoins.first(where: { $0.symbol.uppercased() == holding.coinSymbol.uppercased() })
            
            // FIX: When coin is not found in the marketCoins array (e.g. during startup
            // before allCoins loads), fall back to bestPrice(forSymbol:) which checks
            // LivePriceManager, allCoins, lastGoodAllCoins, and price books.
            let livePrice: Double
            if let coin = coin {
                // PRICE CONSISTENCY FIX: Use bestPrice() for consistent pricing across all views
                livePrice = MarketViewModel.shared.bestPrice(for: coin.id) ?? coin.priceUsd ?? 0.0
            } else {
                // Fallback: Try symbol-based lookup (covers startup race conditions)
                livePrice = MarketViewModel.shared.bestPrice(forSymbol: holding.coinSymbol.uppercased()) ?? 0.0
            }
            
            // FIX: Guard against NaN/Infinity propagation — only use prices that are finite and positive
            let newPrice: Double = {
                if livePrice > 0, livePrice.isFinite { return livePrice }
                if holding.currentPrice > 0, holding.currentPrice.isFinite { return holding.currentPrice }
                return 0
            }()
            let newDaily: Double = {
                // Prefer any non-trivial live daily change; otherwise keep existing
                let v = (coin?.dailyChange ?? 0.0)
                return abs(v) > 0.000001 ? v : holding.dailyChange
            }()
            return Holding(
                coinName: holding.coinName,
                coinSymbol: holding.coinSymbol,
                quantity: holding.quantity,
                currentPrice: newPrice,
                costBasis: holding.costBasis,
                imageUrl: holding.imageUrl,
                isFavorite: holding.isFavorite,
                dailyChange: newDaily,
                purchaseDate: holding.purchaseDate
            )
        }
    }
    
    /// STARTUP FIX: Immediately refresh holding prices from the best available source.
    /// Called when holdings are first loaded to avoid showing $0 or stale prices.
    /// Uses MarketViewModel.bestPrice(forSymbol:) which checks LivePriceManager,
    /// cached coins, and all other sources — much faster than waiting for slowPublisher.
    private func refreshHoldingPricesFromBestSource() {
        guard !holdings.isEmpty else { return }
        guard !demoOverrideEnabled else { return }
        
        var anyUpdated = false
        var updated = holdings
        
        for i in 0..<updated.count {
            let holding = updated[i]
            let symbol = holding.coinSymbol.uppercased()
            
            // Try bestPrice by symbol (checks LivePriceManager, allCoins, lastGoodAllCoins, etc.)
            let freshPrice = MarketViewModel.shared.bestPrice(forSymbol: symbol)
            
            if let price = freshPrice, price > 0, price.isFinite {
                // Only update if the price is meaningfully different from current
                if holding.currentPrice <= 0 || abs(price - holding.currentPrice) / max(holding.currentPrice, 1e-9) > 0.001 {
                    updated[i] = Holding(
                        coinName: holding.coinName,
                        coinSymbol: holding.coinSymbol,
                        quantity: holding.quantity,
                        currentPrice: price,
                        costBasis: holding.costBasis,
                        imageUrl: holding.imageUrl,
                        isFavorite: holding.isFavorite,
                        dailyChange: holding.dailyChange,
                        purchaseDate: holding.purchaseDate
                    )
                    anyUpdated = true
                }
            } else {
                #if DEBUG
                print("⚠️ [PortfolioVM] No price found for holding \(symbol) (qty: \(holding.quantity), current: $\(holding.currentPrice))")
                #endif
            }
        }
        
        if anyUpdated {
            holdings = updated
            lastLiveUpdateAt = Date()
        }
    }
    
    // MARK: - Demo Override Controls
    /// Apply a seeded demo portfolio and freeze repository-driven updates until disabled.
    func applyDemoSeed(holdings: [Holding], history: [ChartPoint]) {
        demoOverrideEnabled = true
        self.holdings = holdings
        self.history = history
    }

    /// Disable the demo override so repository/live updates resume normally.
    /// FIX: Also triggers an immediate price refresh so portfolio doesn't show
    /// stale demo prices after switching to live/paper mode.
    func disableDemoOverrideAndResumeRepository() {
        demoOverrideEnabled = false
        // Immediately refresh prices from best available source
        // to replace any stale demo-mode prices
        refreshHoldingPricesFromBestSource()
    }
}

// MARK: - Demo/Mock Data Helpers
extension PortfolioViewModel {
    /// Builds demo holdings and a realistic 540-day history with organic growth patterns,
    /// daily volatility, and occasional drawdowns for a believable portfolio chart.
    /// - Parameters:
    ///   - mockDailyPercent: The mock 24h change percent for the chart
    ///   - includeStocks: Whether to include demo stock holdings (default: checks UserDefaults)
    static func buildDemoSeed(mockDailyPercent: Double = 2.0, includeStocks: Bool? = nil) -> (holdings: [Holding], history: [ChartPoint]) {
        // Check if stocks should be included (from setting or parameter)
        let showStocks = includeStocks ?? UserDefaults.standard.bool(forKey: "showStocksInPortfolio")
        
        // Demo crypto holdings
        var demoHoldings: [Holding] = [
            Holding(coinName: "Bitcoin",  coinSymbol: "BTC", quantity: 50,     currentPrice: 100_000, costBasis: 50_000,  imageUrl: nil, isFavorite: true,  dailyChange: 1.31, purchaseDate: Date()),
            Holding(coinName: "Solana",   coinSymbol: "SOL", quantity: 10_000, currentPrice: 400,     costBasis: 100,    imageUrl: nil, isFavorite: false, dailyChange: 2.57, purchaseDate: Date()),
            Holding(coinName: "XRP",      coinSymbol: "XRP", quantity: 1_000_000, currentPrice: 1,   costBasis: 0.5,    imageUrl: nil, isFavorite: false, dailyChange: 0.62, purchaseDate: Date()),
            Holding(coinName: "Ethereum", coinSymbol: "ETH", quantity: 200,    currentPrice: 2_500,   costBasis: 1_800,  imageUrl: nil, isFavorite: false, dailyChange: -0.64, purchaseDate: Date())
        ]
        
        // Demo stock holdings (only included if stocks feature is enabled)
        if showStocks {
            let stockHoldings: [Holding] = [
                // Apple - large position
                Holding(
                    ticker: "AAPL",
                    companyName: "Apple Inc.",
                    shares: 500,
                    currentPrice: 248.50,
                    costBasis: 175.00,
                    assetType: .stock,
                    stockExchange: "NASDAQ",
                    isin: "US0378331005",
                    imageUrl: nil,
                    isFavorite: true,
                    dailyChange: 1.25,
                    purchaseDate: Calendar.current.date(byAdding: .month, value: -18, to: Date()) ?? Date(),
                    source: "demo"
                ),
                // Tesla
                Holding(
                    ticker: "TSLA",
                    companyName: "Tesla, Inc.",
                    shares: 150,
                    currentPrice: 425.80,
                    costBasis: 280.00,
                    assetType: .stock,
                    stockExchange: "NASDAQ",
                    isin: "US88160R1014",
                    imageUrl: nil,
                    isFavorite: false,
                    dailyChange: 3.42,
                    purchaseDate: Calendar.current.date(byAdding: .month, value: -12, to: Date()) ?? Date(),
                    source: "demo"
                ),
                // Nvidia
                Holding(
                    ticker: "NVDA",
                    companyName: "NVIDIA Corporation",
                    shares: 200,
                    currentPrice: 875.25,
                    costBasis: 450.00,
                    assetType: .stock,
                    stockExchange: "NASDAQ",
                    isin: "US67066G1040",
                    imageUrl: nil,
                    isFavorite: true,
                    dailyChange: 2.18,
                    purchaseDate: Calendar.current.date(byAdding: .month, value: -24, to: Date()) ?? Date(),
                    source: "demo"
                ),
                // VOO ETF
                Holding(
                    ticker: "VOO",
                    companyName: "Vanguard S&P 500 ETF",
                    shares: 100,
                    currentPrice: 545.00,
                    costBasis: 420.00,
                    assetType: .etf,
                    stockExchange: "NYSE",
                    isin: "US9229083632",
                    imageUrl: nil,
                    isFavorite: false,
                    dailyChange: 0.85,
                    purchaseDate: Calendar.current.date(byAdding: .month, value: -36, to: Date()) ?? Date(),
                    source: "demo"
                )
            ]
            demoHoldings.append(contentsOf: stockHoldings)
        }
        
        // Compute today's total from demo holdings
        let todayTotal = demoHoldings.reduce(0) { $0 + $1.currentValue }
        
        // Generate realistic history with growth curve and volatility
        let history = generateRealisticHistory(
            currentTotal: todayTotal,
            mockDailyPercent: mockDailyPercent,
            days: 540
        )
        
        return (demoHoldings, history)
    }
    
    /// Generates realistic portfolio history that looks like actual market movements.
    /// 
    /// DESIGN GOALS:
    /// - Look like REAL portfolio movements with visible daily fluctuations
    /// - Small pullbacks, recoveries, and micro-trends (2-5 day runs)
    /// - Market-correlated volatility (not too smooth, not jagged)
    /// - Overall upward trend with realistic noise
    /// 
    /// KEY INSIGHT: Real portfolios don't have smooth curves - they have texture from
    /// actual market movements. We simulate this with random walk + momentum + mean reversion.
    /// 
    /// - Parameters:
    ///   - currentTotal: The current portfolio total value (today's value)
    ///   - mockDailyPercent: Used to influence recent volatility level
    ///   - days: Number of days of history to generate (default 540 for ~1.5 years)
    /// - Returns: Array of ChartPoints sorted by date ascending
    private static func generateRealisticHistory(
        currentTotal: Double,
        mockDailyPercent: Double,
        days: Int = 540
    ) -> [ChartPoint] {
        // Use a seeded random generator for consistent results within a session
        let daySeed = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        var rng = SeededRandomNumberGenerator(seed: UInt64(daySeed))
        
        let today = Date()
        let calendar = Calendar.current
        
        // Start from 18-28% of current total for realistic long-term growth
        let startFraction = Double.random(in: 0.18...0.28, using: &rng)
        let startValue = max(1, currentTotal * startFraction)
        
        // ============================================================
        // STEP 1: Build time series
        // ============================================================
        
        struct TimePoint {
            let date: Date
            let hoursFromStart: Double
            let intervalHours: Int
        }
        
        var timePoints: [TimePoint] = []
        let totalHours = Double(days * 24)
        
        // Daily points for days 31+
        for d in stride(from: days, through: 31, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -d, to: today) else { continue }
            let hoursFromStart = totalHours - Double(d * 24)
            timePoints.append(TimePoint(date: date, hoursFromStart: hoursFromStart, intervalHours: 24))
        }
        
        // 4-hour points for days 8-30
        for d in stride(from: 30, through: 8, by: -1) {
            for hourOffset in stride(from: 0, to: 24, by: 4) {
                guard let dayDate = calendar.date(byAdding: .day, value: -d, to: today),
                      let date = calendar.date(byAdding: .hour, value: hourOffset, to: dayDate) else { continue }
                if date > today { continue }
                let hoursFromStart = totalHours - Double(d * 24) + Double(hourOffset)
                timePoints.append(TimePoint(date: date, hoursFromStart: hoursFromStart, intervalHours: 4))
            }
        }
        
        // Hourly points for last 7 days
        for hoursAgo in stride(from: 168, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .hour, value: -hoursAgo, to: today) else { continue }
            let hoursFromStart = totalHours - Double(hoursAgo)
            timePoints.append(TimePoint(date: date, hoursFromStart: hoursFromStart, intervalHours: 1))
        }
        
        timePoints.sort { $0.date < $1.date }
        
        // ============================================================
        // STEP 2: Generate realistic market-like movements
        // Using random walk with momentum and mean reversion
        // ============================================================
        
        // Target growth rate per hour to reach currentTotal from startValue
        let totalGrowth = currentTotal / startValue
        let growthPerHour = pow(totalGrowth, 1.0 / totalHours)
        
        var values: [Double] = []
        var currentValue = startValue
        var momentum: Double = 0  // Momentum for micro-trends
        var trendDuration: Int = 0  // How long current micro-trend has been running
        var trendDirection: Double = 1  // Current micro-trend direction
        
        for (_, tp) in timePoints.enumerated() {
            let progress = tp.hoursFromStart / totalHours
            
            // Expected value at this point (for mean reversion target)
            let expectedValue = startValue * pow(totalGrowth, progress)
            
            // Volatility scales with time interval and decreases near end
            let baseVolatility: Double = {
                switch tp.intervalHours {
                case 1: return 0.003   // Hourly: ~0.3% moves
                case 4: return 0.006   // 4-hour: ~0.6% moves
                default: return 0.012  // Daily: ~1.2% moves
                }
            }()
            
            // Reduce volatility near the end for smooth landing
            let endFalloff = min(1.0, (1.0 - progress) * 10)
            let effectiveVolatility = baseVolatility * (0.5 + 0.5 * endFalloff)
            
            // Random market movement
            let randomMove = Double.random(in: -1...1, using: &rng)
            
            // Add slight positive bias to trend upward overall
            let upwardBias = 0.15
            let biasedMove = randomMove + upwardBias
            
            // Micro-trend logic: markets tend to trend for a few periods
            trendDuration += 1
            if trendDuration > Int.random(in: 3...12, using: &rng) {
                // Randomly reverse or continue trend
                if Double.random(in: 0...1, using: &rng) > 0.6 {
                    trendDirection *= -1
                }
                trendDuration = 0
            }
            
            // Momentum with decay
            momentum = momentum * 0.7 + biasedMove * trendDirection * 0.3
            
            // Calculate price change
            let priceChange = (momentum + randomMove * 0.5) * effectiveVolatility
            
            // Mean reversion: pull toward expected growth curve
            let deviation = (currentValue - expectedValue) / expectedValue
            let meanReversionStrength: Double = {
                // Stronger reversion when far from target or near end
                if progress > 0.95 { return 0.15 }  // Strong pull at end
                if abs(deviation) > 0.15 { return 0.08 }  // Pull back big deviations
                return 0.02  // Gentle normal reversion
            }()
            let meanReversion = -deviation * meanReversionStrength
            
            // Apply growth, random movement, and mean reversion
            let growthFactor = growthPerHour
            let changeFactor = 1.0 + priceChange + meanReversion
            currentValue = currentValue * growthFactor * changeFactor
            
            // Prevent negative or extreme values
            currentValue = max(startValue * 0.3, min(currentValue, currentTotal * 1.5))
            
            values.append(currentValue)
        }
        
        // ============================================================
        // STEP 3: Light smoothing to remove jaggedness while keeping texture
        // ============================================================
        
        func lightSmooth(_ vals: [Double], windowSize: Int) -> [Double] {
            guard vals.count > windowSize else { return vals }
            var smoothed = vals
            let half = windowSize / 2
            
            for i in half..<(vals.count - half) {
                var sum: Double = 0
                for j in (i - half)...(i + half) {
                    sum += vals[j]
                }
                // Blend: keep 60% original, 40% smoothed to preserve texture
                smoothed[i] = vals[i] * 0.6 + (sum / Double(windowSize)) * 0.4
            }
            return smoothed
        }
        
        // Just one light smoothing pass - keep the texture
        values = lightSmooth(values, windowSize: 3)
        
        // ============================================================
        // STEP 4: Scale to hit exact endpoint
        // ============================================================
        
        // Calculate what value we ended up with
        let generatedEndValue = values.last ?? currentTotal
        let scaleFactor = currentTotal / generatedEndValue
        
        // Apply scaling with gradual blend (more scaling near end)
        var points: [ChartPoint] = []
        for (i, tp) in timePoints.enumerated() {
            let progress = tp.hoursFromStart / totalHours
            // Gradually increase scaling influence toward the end
            let blendedScale = 1.0 + (scaleFactor - 1.0) * (progress * progress)
            let finalValue = values[i] * blendedScale
            points.append(ChartPoint(date: tp.date, value: max(1, finalValue)))
        }
        
        // Ensure exact endpoint
        if let lastIdx = points.indices.last {
            points[lastIdx] = ChartPoint(date: today, value: currentTotal)
        }
        
        return points
    }

    /// Enables demo mode and seeds holdings/history using the current mockDailyChangePercent.
    /// Note: The caller should also call DemoModeManager.shared.enableDemoMode() to update the unified state.
    func enableDemoMode() {
        let seed = Self.buildDemoSeed(mockDailyPercent: mockDailyChangePercent)
        applyDemoSeed(holdings: seed.holdings, history: seed.history)
        startMockTicker()
    }

    /// Disables demo mode and resumes repository updates.
    /// Note: The caller should also call DemoModeManager.shared.disableDemoMode() to update the unified state.
    /// FIX: Order matters — stop mock ticker first to prevent it from injecting jitter prices,
    /// clear demo holdings, then re-enable repository updates which will deliver real holdings
    /// with fresh prices.
    /// GUARD: Idempotent — safe to call multiple times (e.g., both inline + subscriber path).
    /// Prevents double-clearing that would cause a holdings flicker.
    func disableDemoMode() {
        guard demoOverrideEnabled else { return }
        
        stopMockTicker()
        // Clear demo holdings (before disabling override)
        holdings = []
        history = []
        // Re-enable repository updates — this triggers mergeExchangeHoldings +
        // refreshHoldingPricesFromBestSource for any real holdings from connected accounts
        disableDemoOverrideAndResumeRepository()
        
        // FIX: Rebuild manual holdings from saved transactions.
        // Without this, manually-added holdings (e.g. Gold, manual crypto) are lost
        // when switching from Demo back to Portfolio mode, because clearing holdings
        // above wipes them and the repository publisher only delivers exchange holdings.
        if !transactions.isEmpty {
            recalcHoldingsFromAllTransactions()
            refreshHoldingPricesFromBestSource()
            loadHistory()
        }
    }
    
    /// Refreshes demo data when stock settings change while in demo mode.
    /// Call this when toggling "Show Stocks in Portfolio" to update the demo holdings.
    func refreshDemoDataForStocksToggle() {
        guard demoOverrideEnabled else { return }
        
        // Rebuild demo seed with current stock setting
        let seed = Self.buildDemoSeed(mockDailyPercent: mockDailyChangePercent)
        
        // Preserve current total value scale while updating holdings
        let currentTotal = totalValue
        let newTotal = seed.holdings.reduce(0) { $0 + $1.currentValue }
        
        // Apply new holdings (with or without stocks based on setting)
        holdings = seed.holdings
        
        // Regenerate history to match new total
        if newTotal > 0 && currentTotal > 0 {
            // Scale holdings to approximately match previous total
            holdings = holdings.map { holding in
                let scaled = holding
                // Don't scale, just use the new seed values for consistency
                return scaled
            }
        }
        
        // Regenerate history for new holdings composition
        history = Self.generateRealisticHistory(
            currentTotal: holdings.reduce(0) { $0 + $1.currentValue },
            mockDailyPercent: mockDailyChangePercent,
            days: 540
        )
        
        // Defer to avoid "Modifying state during view update" warnings
        Task { self.objectWillChange.send() }
    }

    /// Updates the mock 24h change percent and regenerates demo history if demo mode is active.
    func updateMockDailyChange(to percent: Double) {
        mockDailyChangePercent = percent
        guard demoOverrideEnabled else { return }
        let total = totalValue
        let today = Date()
        let yesterdayValue = max(0.0, total * (1.0 - percent / 100.0))
        var newHistory = history
        // Ensure we have at least two points; if not, rebuild via seed
        if newHistory.count < 2 {
            let seed = Self.buildDemoSeed(mockDailyPercent: percent)
            applyDemoSeed(holdings: holdings.isEmpty ? seed.holdings : holdings, history: seed.history)
            return
        }
        // Replace last two days to reflect the new percent
        let lastIdx = newHistory.count - 1
        newHistory[lastIdx] = ChartPoint(date: today, value: total)
        let yDate = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
        newHistory[lastIdx - 1] = ChartPoint(date: yDate, value: yesterdayValue)
        history = newHistory
        // Defer to avoid "Modifying state during view update" warnings
        Task { self.objectWillChange.send() }
    }
}

// MARK: - Mock Ticker (keeps demo prices moving when no live feed)
extension PortfolioViewModel {
    private func startMockTicker() {
        stopMockTicker()
        // Slow ticker interval (30s) to prevent chart instability from rapid updates
        mockTickerTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                // If we received a live update recently, skip this tick
                if Date().timeIntervalSince(self.lastLiveUpdateAt) < 35 { return }
                // Nudge each holding price by a tiny random walk so totals move
                self.holdings = self.holdings.map { h in
                let base = max(0.0000001, h.currentPrice)
                // Smaller jitter (+/- 0.1%) since updates are less frequent
                let jitter = Double.random(in: -0.001...0.001)
                let newPrice = max(0.0000001, base * (1.0 + jitter))
                let newDaily = h.dailyChange + jitter * 100.0
                return Holding(
                    coinName: h.coinName,
                    coinSymbol: h.coinSymbol,
                    quantity: h.quantity,
                    currentPrice: newPrice,
                    costBasis: h.costBasis,
                    imageUrl: h.imageUrl,
                    isFavorite: h.isFavorite,
                    dailyChange: newDaily,
                    purchaseDate: h.purchaseDate
                )
            }
            }
        }
        if let timer = mockTickerTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func stopMockTicker() {
        mockTickerTimer?.invalidate()
        mockTickerTimer = nil
    }
}

// MARK: - Top/Worst Performers
extension PortfolioViewModel {
    /// Stablecoins to exclude from top/worst computations
    private var stablecoinSymbols: Set<String> { ["USDC", "USDT", "DAI", "TUSD", "BUSD", "USD", "FDUSD"] }

    /// Candidates after excluding stablecoins, sorted by performance (best first)
    private var performanceCandidates: [Holding] {
        holdings
            .filter { !stablecoinSymbols.contains($0.coinSymbol.uppercased()) }
            .sorted { $0.dailyChangePercent > $1.dailyChangePercent }
    }

    /// User-friendly symbol for a holding — resolves commodity tickers (e.g., "GC=F" → "Gold")
    private func friendlySymbol(for holding: Holding) -> String {
        // Always try the commodity mapper — handles cases where assetType
        // may not be .commodity but the ticker is still a Yahoo commodity symbol
        let ticker = holding.ticker ?? holding.coinSymbol
        if let info = CommoditySymbolMapper.getCommodity(for: ticker) {
            return info.name  // "Gold", "Silver", etc.
        }
        return holding.coinSymbol
    }

    /// Formatted string for the top 24h performer (e.g., "BTC +4.2%")
    var topPerformerString: String {
        guard let top = performanceCandidates.first else { return "--" }
        let sign = top.dailyChangePercent >= 0 ? "+" : ""
        return "\(friendlySymbol(for: top)) \(sign)\(String(format: "%.1f", top.dailyChangePercent))%"
    }

    /// Formatted string for the worst 24h performer (e.g., "DOGE -3.5%")
    /// Returns "--" if there's only one non-stablecoin asset (same as top)
    var worstPerformerString: String {
        // Need at least 2 candidates to have a meaningful worst performer
        guard performanceCandidates.count >= 2, let worst = performanceCandidates.last else { return "--" }
        let sign = worst.dailyChangePercent >= 0 ? "+" : ""
        return "\(friendlySymbol(for: worst)) \(sign)\(String(format: "%.1f", worst.dailyChangePercent))%"
    }
}

// MARK: - Transaction & Portfolio Management
extension PortfolioViewModel {
    /// Adds a transaction and updates the corresponding holding.
    func addTransaction(_ transaction: Transaction) {
        transactions.append(transaction)
        updateHolding(with: transaction)
        saveTransactions()
    }
    
    /// Updates or creates a holding based on a transaction.
    private func updateHolding(with transaction: Transaction) {
        // Try to find an existing holding by coin symbol (case-insensitive).
        if let index = holdings.firstIndex(where: { $0.coinSymbol.uppercased() == transaction.coinSymbol.uppercased() }) {
            var holding = holdings[index]
            
            if transaction.isBuy {
                // For a buy, calculate the new total cost and quantity, then update the average cost basis.
                let currentTotalCost = holding.costBasis * holding.quantity
                let transactionCost = transaction.pricePerUnit * transaction.quantity
                let newQuantity = holding.quantity + transaction.quantity
                let newCostBasis = newQuantity > 0 ? (currentTotalCost + transactionCost) / newQuantity : 0
                
                holding.quantity = newQuantity
                holding.costBasis = newCostBasis
            } else {
                // For a sell, subtract the sold quantity from the holding.
                holding.quantity -= transaction.quantity
                // If holding.quantity <= 0, consider removing it or resetting cost basis.
            }
            
            holdings[index] = holding
        } else {
            // No existing holding found.
            if transaction.isBuy {
                // Create a new holding for a buy transaction.
                let newHolding = Holding(
                    // We don't have transaction.coinName, so reuse coinSymbol as coinName for now.
                    coinName: transaction.coinSymbol,
                    coinSymbol: transaction.coinSymbol,
                    quantity: transaction.quantity,
                    currentPrice: transaction.pricePerUnit,  // Placeholder; update as needed
                    costBasis: transaction.pricePerUnit,
                    imageUrl: nil,
                    isFavorite: false,
                    dailyChange: 0.0,
                    purchaseDate: transaction.date
                )
                holdings.append(newHolding)
            } else {
                // Correctly formatted error message:
                #if DEBUG
                print("Error: Trying to sell a coin that doesn't exist in holdings.")
                #endif
            }
        }
    }
}

// MARK: - Transaction Editing & Recalculation
extension PortfolioViewModel {
    /// Recalculates holdings from all transactions.
    func recalcHoldingsFromAllTransactions() {
        // Preserve exchange-only holdings (holdings that have NO corresponding manual transaction)
        let exchangeOnlyHoldings = holdings.filter { holding in
            !transactions.contains { $0.coinSymbol.uppercased() == holding.coinSymbol.uppercased() }
        }
        holdings.removeAll()
        
        // Sort transactions by date
        let sortedTransactions = transactions.sorted { $0.date < $1.date }
        
        // Reapply each transaction to rebuild holdings
        for tx in sortedTransactions {
            updateHolding(with: tx)
        }
        
        // Add back exchange-only holdings (those without manual transactions)
        for exchangeHolding in exchangeOnlyHoldings {
            if !holdings.contains(where: { $0.coinSymbol.uppercased() == exchangeHolding.coinSymbol.uppercased() }) {
                holdings.append(exchangeHolding)
            }
        }
    }
    
    /// Merges exchange-synced holdings with local holdings (from CSV/manual transactions).
    /// Local holdings take precedence for duplicate symbols.
    private func mergeExchangeHoldings(_ exchangeHoldings: [Holding]) {
        // Get symbols that already exist from local transactions
        let localSymbols = Set(transactions.map { $0.coinSymbol.uppercased() })
        
        // Add exchange holdings that don't conflict with local data
        for exchangeHolding in exchangeHoldings {
            let symbol = exchangeHolding.coinSymbol.uppercased()
            
            // Skip if we have local transactions for this symbol (local takes precedence)
            if localSymbols.contains(symbol) {
                // Update price info on existing local holding if available
                if let index = holdings.firstIndex(where: { $0.coinSymbol.uppercased() == symbol }) {
                    var updated = holdings[index]
                    // Only update price data, keep local quantity and cost basis
                    if exchangeHolding.currentPrice > 0 {
                        updated.currentPrice = exchangeHolding.currentPrice
                    }
                    if exchangeHolding.dailyChange != 0 {
                        updated.dailyChange = exchangeHolding.dailyChange
                    }
                    if let imageUrl = exchangeHolding.imageUrl, !imageUrl.isEmpty, updated.imageUrl?.isEmpty ?? true {
                        updated.imageUrl = imageUrl
                    }
                    holdings[index] = updated
                }
                continue
            }
            
            // Add exchange holding if not already present
            if !holdings.contains(where: { $0.coinSymbol.uppercased() == symbol }) {
                holdings.append(exchangeHolding)
            }
        }
    }
    
    /// Updates an existing manual transaction.
    func updateTransaction(oldTx: Transaction, newTx: Transaction) {
        // Only allow editing of manual transactions
        guard oldTx.isManual else {
            #if DEBUG
            print("Error: Cannot update an exchange transaction.")
            #endif
            return
        }

        if let index = transactions.firstIndex(where: { $0.id == oldTx.id }) {
            transactions[index] = newTx
        } else {
            #if DEBUG
            print("Error: Transaction not found.")
            #endif
        }
        
        recalcHoldingsFromAllTransactions()
        saveTransactions()
    }
    
    /// Deletes a manual transaction and recalculates holdings.
    func deleteManualTransaction(_ tx: Transaction) {
        // Only allow deletion of manual transactions
        guard tx.isManual else {
            #if DEBUG
            print("Error: Cannot delete an exchange transaction.")
            #endif
            return
        }

        if let index = transactions.firstIndex(where: { $0.id == tx.id }) {
            transactions.remove(at: index)
        } else {
            #if DEBUG
            print("Error: Transaction not found.")
            #endif
        }
        
        recalcHoldingsFromAllTransactions()
        saveTransactions()
    }
}

// MARK: - Persistence
extension PortfolioViewModel {
    /// Loads saved transactions from disk.
    /// PERFORMANCE FIX: Now supports async loading to avoid blocking main thread during init
    private func loadTransactions() {
        // Check if the file exists; if not, initialize with an empty array
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: transactionsFileURL.path) {
            self.transactions = []
            return
        }

        do {
            let data = try Data(contentsOf: transactionsFileURL)
            let decoded = try JSONDecoder().decode([Transaction].self, from: data)
            self.transactions = decoded
        } catch {
            #if DEBUG
            print("Failed to load transactions:", error)
            #endif
            self.transactions = []
        }
    }

    /// PERFORMANCE FIX: Async version of loadTransactions to avoid blocking main thread
    private func loadTransactionsAsync() async {
        let fileURL = transactionsFileURL
        
        // Perform disk I/O on background queue
        let loadedTransactions: [Transaction] = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let fileManager = FileManager.default
                if !fileManager.fileExists(atPath: fileURL.path) {
                    continuation.resume(returning: [])
                    return
                }
                
                do {
                    let data = try Data(contentsOf: fileURL)
                    let decoded = try JSONDecoder().decode([Transaction].self, from: data)
                    continuation.resume(returning: decoded)
                } catch {
                    #if DEBUG
                    print("Failed to load transactions:", error)
                    #endif
                    continuation.resume(returning: [])
                }
            }
        }
        
        // Update on main thread
        await MainActor.run {
            self.transactions = loadedTransactions
            if !loadedTransactions.isEmpty {
                self.recalcHoldingsFromAllTransactions()
            }
        }
    }

    /// Saves current transactions to disk.
    /// PERFORMANCE FIX: Now performs disk I/O on background queue
    private func saveTransactions() {
        let transactionsToSave = transactions
        let fileURL = transactionsFileURL
        
        // Perform disk I/O on background queue
        DispatchQueue.global(qos: .utility).async {
            do {
                let data = try JSONEncoder().encode(transactionsToSave)
                // SECURITY: .completeFileProtection ensures portfolio transaction data
                // is encrypted by iOS and inaccessible when the device is locked.
                try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            } catch {
                #if DEBUG
                print("Failed to save transactions:", error)
                #endif
            }
        }
    }
    
    /// Builds a time-series of portfolio total value for the past 30 days based on transactions.
    /// HIGH-RESOLUTION DATA:
    /// - Last 7 days: hourly points (168 points) for detailed 1D/1W views
    /// - Days 8-30: 4-hour points (138 points) for detailed 1M views
    func loadHistory() {
        var points: [ChartPoint] = []
        let sortedTx = transactions.sorted { $0.date < $1.date }
        let now = Date()
        let calendar = Calendar.current
        
        /// Helper to calculate portfolio value at a given date
        func valueAtDate(_ targetDate: Date) -> Double {
            var holdingsAtDate: [String: (quantity: Double, costBasis: Double)] = [:]
            
            for tx in sortedTx where tx.date <= targetDate {
                let symbol = tx.coinSymbol
                var record = holdingsAtDate[symbol] ?? (0, 0)
                
                if tx.isBuy {
                    let totalCost = record.costBasis * record.quantity + tx.pricePerUnit * tx.quantity
                    let newQty = record.quantity + tx.quantity
                    let newCostBasis = newQty > 0 ? totalCost / newQty : 0
                    record = (newQty, newCostBasis)
                } else {
                    let newQty = record.quantity - tx.quantity
                    record = (newQty, record.costBasis)
                }
                
                holdingsAtDate[symbol] = record
            }
            
            return holdingsAtDate.values.reduce(0) { acc, rec in
                acc + (rec.quantity * rec.costBasis)
            }
        }
        
        // ============================================================
        // Generate 4-hour points for days 8-30 (23 days * 6 = 138 points)
        // ============================================================
        for daysAgo in stride(from: 30, through: 8, by: -1) {
            for hourOffset in stride(from: 0, to: 24, by: 4) {
                guard let dayDate = calendar.date(byAdding: .day, value: -daysAgo, to: now),
                      let targetDate = calendar.date(byAdding: .hour, value: hourOffset, to: dayDate) else { continue }
                
                if targetDate > now { continue }
                
                let value = valueAtDate(targetDate)
                points.append(ChartPoint(date: targetDate, value: value))
            }
        }
        
        // ============================================================
        // Generate hourly points for last 7 days (168 points)
        // ============================================================
        for hoursAgo in stride(from: 168, through: 0, by: -1) {
            guard let targetDate = calendar.date(byAdding: .hour, value: -hoursAgo, to: now) else { continue }
            
            let value = valueAtDate(targetDate)
            points.append(ChartPoint(date: targetDate, value: value))
        }
        
        // Sort and deduplicate by date
        points.sort { $0.date < $1.date }
        
        // Remove duplicates (keep last occurrence for each unique hour)
        var seen = Set<Int>()
        var uniquePoints: [ChartPoint] = []
        for point in points.reversed() {
            let hourKey = Int(point.date.timeIntervalSince1970 / 3600)
            if !seen.contains(hourKey) {
                seen.insert(hourKey)
                uniquePoints.append(point)
            }
        }
        
        history = uniquePoints.reversed()
    }
}

private extension Array {
    func partitioned(by include: (Element) -> Bool) -> ([Element],[Element]) {
        var yes: [Element] = [], no: [Element] = []
        for e in self { include(e) ? yes.append(e) : no.append(e) }
        return (yes, no)
    }
}

// MARK: - Seeded Random Number Generator
/// A simple seeded random number generator for consistent demo data within a session.
/// Uses a linear congruential generator (LCG) algorithm.
private struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64
    
    init(seed: UInt64) {
        self.state = seed
    }
    
    mutating func next() -> UInt64 {
        // LCG parameters (same as glibc)
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

// MARK: - Asset Type Filtering (Stocks + Crypto)
extension PortfolioViewModel {
    /// All crypto holdings
    var cryptoHoldings: [Holding] {
        holdings.filter { $0.assetType == .crypto }
    }
    
    /// All stock holdings
    var stockHoldings: [Holding] {
        holdings.filter { $0.assetType == .stock }
    }
    
    /// All ETF holdings
    var etfHoldings: [Holding] {
        holdings.filter { $0.assetType == .etf }
    }
    
    /// All commodity holdings
    var commodityHoldings: [Holding] {
        holdings.filter { $0.assetType == .commodity }
    }
    
    /// All traditional securities (stocks + ETFs)
    var securitiesHoldings: [Holding] {
        holdings.filter { $0.assetType == .stock || $0.assetType == .etf }
    }
    
    /// Total value of crypto holdings
    var cryptoValue: Double {
        cryptoHoldings.reduce(0) { $0 + $1.currentValue }
    }
    
    /// Total value of stock holdings
    var stocksValue: Double {
        stockHoldings.reduce(0) { $0 + $1.currentValue }
    }
    
    /// Total value of ETF holdings
    var etfValue: Double {
        etfHoldings.reduce(0) { $0 + $1.currentValue }
    }
    
    /// Total value of commodity holdings
    var commodityValue: Double {
        commodityHoldings.reduce(0) { $0 + $1.currentValue }
    }
    
    /// Total value of all securities (stocks + ETFs)
    var securitiesValue: Double {
        securitiesHoldings.reduce(0) { $0 + $1.currentValue }
    }
    
    /// Percentage of portfolio in crypto
    var cryptoPercent: Double {
        guard totalValue > 0 else { return 0 }
        return (cryptoValue / totalValue) * 100
    }
    
    /// Percentage of portfolio in stocks
    var stocksPercent: Double {
        guard totalValue > 0 else { return 0 }
        return (stocksValue / totalValue) * 100
    }
    
    /// Percentage of portfolio in securities (stocks + ETFs)
    var securitiesPercent: Double {
        guard totalValue > 0 else { return 0 }
        return (securitiesValue / totalValue) * 100
    }
    
    /// Filter holdings by asset type
    func holdings(for assetType: AssetType?) -> [Holding] {
        guard let type = assetType else { return holdings }
        return holdings.filter { $0.assetType == type }
    }
    
    /// Check if portfolio has any stock or ETF holdings
    var hasSecurities: Bool {
        !securitiesHoldings.isEmpty
    }
    
    /// Check if portfolio has any crypto holdings
    var hasCrypto: Bool {
        !cryptoHoldings.isEmpty
    }
    
    /// Check if portfolio has any commodity holdings (precious metals)
    var hasCommodities: Bool {
        !commodityHoldings.isEmpty
    }
}

// MARK: - Stock Holding Management
extension PortfolioViewModel {
    /// Adds a stock/ETF holding to the portfolio
    func addStockHolding(_ holding: Holding) {
        // Validate asset type
        guard holding.assetType == .stock || holding.assetType == .etf else {
            #if DEBUG
            print("Error: addStockHolding called with non-stock asset type")
            #endif
            return
        }
        
        // Check if we already have this stock
        if let existingIndex = holdings.firstIndex(where: {
            ($0.ticker ?? $0.coinSymbol).uppercased() == (holding.ticker ?? holding.coinSymbol).uppercased() &&
            ($0.assetType == .stock || $0.assetType == .etf)
        }) {
            // Update existing holding by averaging cost basis
            var existing = holdings[existingIndex]
            let totalCost = (existing.costBasis * existing.quantity) + (holding.costBasis * holding.quantity)
            let totalShares = existing.quantity + holding.quantity
            existing.quantity = totalShares
            existing.costBasis = totalShares > 0 ? totalCost / totalShares : 0
            existing.currentPrice = holding.currentPrice
            existing.dailyChange = holding.dailyChange
            holdings[existingIndex] = existing
        } else {
            // Add as new holding
            holdings.append(holding)
        }
        
        // Defer to avoid "Modifying state during view update" warnings
        Task { self.objectWillChange.send() }
    }
    
    /// Updates stock prices for all stock/ETF holdings
    func refreshStockPrices() async {
        let stockTickers = securitiesHoldings.compactMap { $0.ticker ?? $0.coinSymbol }
        guard !stockTickers.isEmpty else { return }
        
        let quotes = await StockPriceService.shared.fetchQuotes(tickers: stockTickers)
        
        await MainActor.run {
            self.holdings = self.holdings.map { holding in
                guard holding.assetType == .stock || holding.assetType == .etf else {
                    return holding
                }
                
                let ticker = (holding.ticker ?? holding.coinSymbol).uppercased()
                guard let quote = quotes[ticker] else {
                    return holding
                }
                
                var updated = holding
                updated.currentPrice = quote.regularMarketPrice
                // Calculate change: prefer API value, fallback to previousClose calculation
                updated.dailyChange = quote.regularMarketChangePercent ?? {
                    if let prevClose = quote.regularMarketPreviousClose, prevClose > 0 {
                        return ((quote.regularMarketPrice - prevClose) / prevClose) * 100
                    }
                    return 0
                }()
                return updated
            }
            self.objectWillChange.send()
        }
    }
    
    /// Removes a stock holding by ticker
    func removeStockHolding(ticker: String) {
        holdings.removeAll { holding in
            (holding.assetType == .stock || holding.assetType == .etf) &&
            (holding.ticker ?? holding.coinSymbol).uppercased() == ticker.uppercased()
        }
        // Defer to avoid "Modifying state during view update" warnings
        Task { self.objectWillChange.send() }
    }
    
    /// Start tracking stock prices for all securities holdings
    func startStockPriceTracking() {
        let stockTickers = securitiesHoldings.compactMap { $0.ticker ?? $0.coinSymbol }
        guard !stockTickers.isEmpty else { return }
        
        // Only track if live updates are enabled
        guard LiveStockPriceManager.shared.liveUpdatesEnabled else { return }
        
        LiveStockPriceManager.shared.trackFromPortfolio(holdings)
    }
    
    /// Update stock holdings with latest quotes from LiveStockPriceManager
    private func updateStockHoldingsWithQuotes(_ quotes: [String: StockQuote]) {
        guard !quotes.isEmpty else { return }
        
        var didUpdate = false
        holdings = holdings.map { holding in
            // Only update stock/ETF holdings
            guard holding.assetType == .stock || holding.assetType == .etf else {
                return holding
            }
            
            let ticker = (holding.ticker ?? holding.coinSymbol).uppercased()
            guard let quote = quotes[ticker] else {
                return holding
            }
            
            // Update price and daily change
            var updated = holding
            updated.currentPrice = quote.regularMarketPrice
            // Calculate change: prefer API value, fallback to previousClose calculation
            updated.dailyChange = quote.regularMarketChangePercent ?? {
                if let prevClose = quote.regularMarketPreviousClose, prevClose > 0 {
                    return ((quote.regularMarketPrice - prevClose) / prevClose) * 100
                }
                return 0
            }()
            didUpdate = true
            return updated
        }
        
        if didUpdate {
            lastLiveUpdateAt = Date()
        }
    }
    
    // MARK: - Commodity (Precious Metals) Price Refresh
    
    /// Refreshes commodity prices from Coinbase
    /// Precious metals (gold, silver, copper, platinum) are fetched directly from Coinbase
    func refreshCommodityPrices() async {
        let commoditySymbols = commodityHoldings.map { $0.coinSymbol.uppercased() }
        guard !commoditySymbols.isEmpty else { return }
        
        #if DEBUG
        print("💰 [PortfolioVM] Refreshing \(commoditySymbols.count) commodity prices from Coinbase")
        #endif
        
        // Fetch prices from Coinbase (the primary source for precious metals)
        let prices = await CoinbaseService.shared.fetchSpotPrices(for: commoditySymbols, fiat: "USD")
        
        guard !prices.isEmpty else {
            #if DEBUG
            print("⚠️ [PortfolioVM] No commodity prices returned from Coinbase")
            #endif
            return
        }
        
        await MainActor.run {
            var didUpdate = false
            self.holdings = self.holdings.map { holding in
                // Only update commodity holdings
                guard holding.assetType == .commodity else {
                    return holding
                }
                
                let symbol = holding.coinSymbol.uppercased()
                guard let price = prices[symbol], price > 0 else {
                    return holding
                }
                
                var updated = holding
                updated.currentPrice = price
                didUpdate = true
                
                #if DEBUG
                print("💰 [PortfolioVM] Updated \(symbol) price: $\(price)")
                #endif
                
                return updated
            }
            
            if didUpdate {
                self.lastLiveUpdateAt = Date()
                self.objectWillChange.send()
            }
        }
    }
    
    /// Combined refresh for all non-crypto holdings (stocks + commodities)
    func refreshAllSecuritiesAndCommodities() async {
        // Refresh stocks/ETFs from Yahoo Finance
        await refreshStockPrices()
        
        // Refresh commodities (precious metals) from Coinbase
        await refreshCommodityPrices()
    }
    
    /// Start periodic commodity price tracking
    /// Refreshes precious metals prices from Coinbase every 60 seconds
    func startCommodityPriceTracking() {
        // Stop any existing timer
        commodityPriceTimer?.invalidate()
        
        // Only track if we have commodity holdings
        guard !commodityHoldings.isEmpty else {
            #if DEBUG
            print("💰 [PortfolioVM] No commodity holdings to track")
            #endif
            return
        }
        
        #if DEBUG
        print("💰 [PortfolioVM] Starting commodity price tracking for \(commodityHoldings.count) holdings")
        #endif
        
        // Initial refresh
        Task {
            await refreshCommodityPrices()
        }
        
        // Set up periodic refresh every 60 seconds
        commodityPriceTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                // Skip if demo mode is active
                guard !self.demoOverrideEnabled else { return }
                
                await self.refreshCommodityPrices()
            }
        }
    }
    
    /// Stop commodity price tracking
    func stopCommodityPriceTracking() {
        commodityPriceTimer?.invalidate()
        commodityPriceTimer = nil
    }
    
    /// Called when holdings change to update stock tracking
    func updateStockTracking() {
        let stockTickers = securitiesHoldings.compactMap { $0.ticker ?? $0.coinSymbol }
        
        if stockTickers.isEmpty {
            // No portfolio stocks to track.
            LiveStockPriceManager.shared.setTickers([], source: "portfolio")
        } else {
            // Replace portfolio-tracked tickers so removals are reflected too.
            LiveStockPriceManager.shared.setTickers(stockTickers, source: "portfolio")
        }
    }
}

// MARK: - Brokerage Account Sync
extension PortfolioViewModel {
    
    /// Sync holdings from connected brokerage accounts (Plaid)
    func syncBrokerageAccounts() async {
        await BrokeragePortfolioDataService.shared.syncAllAccounts()
        
        // Also update the BrokeragePortfolioDataService with latest stock quotes
        // so the repository gets properly-priced holdings
        await MainActor.run {
            updateStockTracking()
        }
    }
    
    /// Force sync brokerage accounts ignoring cooldown
    func forceSyncBrokerageAccounts() async {
        await BrokeragePortfolioDataService.shared.forceSync()
        
        await MainActor.run {
            updateStockTracking()
        }
    }
    
    /// Add holdings synced from a brokerage connection
    /// Called when BrokerageConnectionView completes a sync
    func addBrokerageHoldings(_ holdings: [Holding]) {
        for holding in holdings {
            BrokeragePortfolioDataService.shared.addManualHolding(holding)
        }
        
        // Update live price tracking
        updateStockTracking()
    }
    
    /// Check if any brokerage accounts are connected
    var hasBrokerageConnections: Bool {
        BrokeragePortfolioDataService.shared.hasConnectedAccounts
    }
    
    /// Get the last time brokerage data was synced
    var lastBrokerageSyncTime: Date? {
        BrokeragePortfolioDataService.shared.lastRefreshTime
    }
    
    /// Whether brokerage sync is currently in progress
    var isBrokerageSyncing: Bool {
        BrokeragePortfolioDataService.shared.isRefreshing
    }
    
    /// Refresh all portfolio data (crypto exchanges + brokerages + commodities)
    func refreshAllPortfolioData() async {
        // Refresh crypto holdings from exchanges
        manualRefresh()
        
        // Refresh stock holdings from brokerages
        await syncBrokerageAccounts()
        
        // Refresh commodity prices (precious metals from Coinbase)
        await refreshCommodityPrices()
    }
    
    /// Handle the stocks feature being toggled on/off
    /// Call this when the user changes the "Show Stocks in Portfolio" setting
    func onStocksFeatureToggled(enabled: Bool) {
        if enabled {
            // Feature enabled - start tracking existing stocks
            startStockPriceTracking()
        } else {
            // Feature disabled - stop tracking and clean up
            LiveStockPriceManager.shared.setTickers([], source: "portfolio")
            LiveStockPriceManager.shared.stopPolling()
            
            // Note: Holdings are filtered out at the view level (displayedHoldings)
            // and at the repository level (showStocksEnabled check).
            // We don't delete the actual holdings data so it can be restored if re-enabled.
        }
        
        // Notify observers - defer to avoid "Modifying state during view update" warnings
        Task { self.objectWillChange.send() }
    }
}

// MARK: - Asset Type Color Mapping
extension PortfolioViewModel {
    /// Returns the chart color for a holding, with asset-type awareness
    func color(for holding: Holding) -> Color {
        // Always try the commodity mapper first — handles cases where assetType
        // may not be .commodity but the ticker is a Yahoo commodity symbol (e.g., "GC=F")
        let rawTicker = (holding.ticker ?? holding.coinSymbol).uppercased()
        if let info = CommoditySymbolMapper.getCommodity(for: rawTicker) {
            switch info.type {
            case .preciousMetal:
                switch info.id {
                case "gold": return Color(red: 0.85, green: 0.65, blue: 0.13)       // Gold
                case "silver": return Color(red: 0.75, green: 0.75, blue: 0.75)      // Silver
                case "platinum": return Color(red: 0.88, green: 0.88, blue: 0.90)    // Platinum
                case "palladium": return Color(red: 0.70, green: 0.70, blue: 0.75)   // Palladium
                default: return Color(red: 0.80, green: 0.70, blue: 0.30)
                }
            case .energy: return Color(red: 0.20, green: 0.60, blue: 0.90)           // Blue
            case .industrialMetal: return Color(red: 0.85, green: 0.55, blue: 0.20)  // Orange
            case .agriculture: return Color(red: 0.45, green: 0.75, blue: 0.30)      // Green
            case .livestock: return Color(red: 0.60, green: 0.40, blue: 0.25)        // Brown
            }
        }

        // Explicit commodity assetType fallback
        if holding.assetType == .commodity {
            return Color(red: 0.80, green: 0.65, blue: 0.20)
        }
        
        // Use asset type color as base for stocks/ETFs
        if holding.assetType == .stock || holding.assetType == .etf {
            let ticker = (holding.ticker ?? holding.coinSymbol).uppercased()
            
            // Well-known stock brand colors
            let stockColors: [String: UInt32] = [
                "AAPL": 0xA2AAAD,   // Apple silver
                "MSFT": 0x00A4EF,   // Microsoft blue
                "GOOGL": 0x4285F4,  // Google blue
                "GOOG": 0x4285F4,
                "AMZN": 0xFF9900,   // Amazon orange
                "TSLA": 0xCC0000,   // Tesla red
                "META": 0x1877F2,   // Meta blue
                "NVDA": 0x76B900,   // NVIDIA green
                "JPM": 0x003087,    // JPMorgan blue
                "V": 0x1A1F71,      // Visa blue
                "MA": 0xEB001B,     // Mastercard red
                "DIS": 0x006E99,    // Disney blue
                "NFLX": 0xE50914,   // Netflix red
                "SPY": 0x00873C,    // S&P ETF green
                "QQQ": 0x2962FF,    // Nasdaq ETF blue
                "VTI": 0x96151D,    // Vanguard red
                "VOO": 0x96151D
            ]
            
            if let hex = stockColors[ticker] {
                return Color(red: Double((hex >> 16) & 0xFF) / 255.0,
                           green: Double((hex >> 8) & 0xFF) / 255.0,
                           blue: Double(hex & 0xFF) / 255.0)
            }
            
            // Default: use asset type color with hash-based variation
            let baseColor = holding.assetType.color
            let h = abs(ticker.hashValue)
            let variation = Double(h % 40) / 100.0 - 0.2 // -0.2 to +0.2
            return baseColor.opacity(0.8 + variation * 0.5)
        }
        
        // Fall back to existing crypto color logic
        return color(for: holding.coinSymbol)
    }
}

// MARK: - Combined Allocation Data
extension PortfolioViewModel {
    /// Asset type breakdown for allocation charts
    struct AssetTypeAllocation: Identifiable {
        let id = UUID()
        let assetType: AssetType
        let value: Double
        let percent: Double
        let color: Color
    }
    
    /// Returns allocation breakdown by asset type
    var assetTypeAllocation: [AssetTypeAllocation] {
        guard totalValue > 0 else { return [] }
        
        var allocations: [AssetTypeAllocation] = []
        
        if cryptoValue > 0 {
            allocations.append(AssetTypeAllocation(
                assetType: .crypto,
                value: cryptoValue,
                percent: cryptoPercent,
                color: AssetType.crypto.color
            ))
        }
        
        if stocksValue > 0 {
            allocations.append(AssetTypeAllocation(
                assetType: .stock,
                value: stocksValue,
                percent: stocksPercent,
                color: AssetType.stock.color
            ))
        }
        
        if etfValue > 0 {
            allocations.append(AssetTypeAllocation(
                assetType: .etf,
                value: etfValue,
                percent: (etfValue / totalValue) * 100,
                color: AssetType.etf.color
            ))
        }
        
        if commodityValue > 0 {
            allocations.append(AssetTypeAllocation(
                assetType: .commodity,
                value: commodityValue,
                percent: (commodityValue / totalValue) * 100,
                color: AssetType.commodity.color
            ))
        }
        
        return allocations.sorted { $0.value > $1.value }
    }
}

