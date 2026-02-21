import SwiftUI
import Combine

@MainActor
class TradeViewModel: ObservableObject {
    /// Shared singleton instance for performance - prevents recreation on tab switches
    static let shared = TradeViewModel(symbol: "BTC")
    
    /// Guard to prevent duplicate subscription setup
    private var didSetupSubscriptions = false
    
    @Published var currentSymbol: String
    @Published var currentPrice: Double = 0.0
    @Published var balance: Double = 0.0
    @Published var quoteBalance: Double = 0.0  // Balance in quote currency (USDT/USD)
    
    // Exchange selection
    @Published var selectedExchange: TradingExchange? = TradingCredentialsManager.shared.defaultExchange
    @Published var connectedExchanges: [TradingExchange] = []
    
    // Exchange-specific price
    @Published var exchangePrice: Double = 0.0
    @Published var priceSource: PriceSource = .aggregate
    @Published var isLoadingExchangePrice: Bool = false
    
    /// Price source indicator
    enum PriceSource: String {
        case aggregate = "Market"
        case binance = "Binance"
        case binanceUS = "Binance US"
        case coinbase = "Coinbase"
        case kraken = "Kraken"
        case kucoin = "KuCoin"
        case bybit = "Bybit"
        case okx = "OKX"
        
        var color: Color {
            switch self {
            case .aggregate: return .gray
            case .binance, .binanceUS: return .yellow
            case .coinbase: return .blue
            case .kraken: return .purple
            case .kucoin: return .green
            case .bybit: return .orange
            case .okx: return .gray
            }
        }
    }
    
    // Order execution state
    @Published var isExecutingOrder: Bool = false
    @Published var lastOrderResult: OrderResult?
    @Published var orderErrorMessage: String?
    @Published var showOrderConfirmation: Bool = false
    
    // SECURITY: Trade execution rate limiting — prevents rapid successive order submissions
    // that could result from UI bugs, automation, or accidental double-taps.
    private var lastTradeTimestamp: Date = .distantPast
    private static let minimumTradeInterval: TimeInterval = 2.0 // Minimum 2 seconds between trades
    
    // Stop order parameters
    @Published var stopPrice: Double = 0.0
    @Published var stopLimitPrice: Double = 0.0  // Limit price for stop-limit orders
    
    // Balance loading state
    @Published var isLoadingBalance: Bool = false
    @Published var balanceError: String?
    
    // All balances for the selected exchange
    @Published var allBalances: [AssetBalance] = []
    
    // Keep trade-related subscriptions separate so we don't cancel our own symbol observer
    private var priceCancellables = Set<AnyCancellable>()
    private var cancellables = Set<AnyCancellable>()
    private var exchangePriceTask: Task<Void, Never>?
    
    /// PRICE ACCURACY: Timestamp of last order book mid-price update.
    /// When the order book is actively streaming (WebSocket), it provides sub-second
    /// exchange-specific pricing. CoinGecko/Firebase updates are suppressed while
    /// the order book price is fresh (within 3 seconds) to prevent the display price
    /// from "bouncing" between the real-time exchange price and the lagging CoinGecko price.
    private var lastOrderBookPriceAt: Date = .distantPast

    init(symbol: String) {
        self.currentSymbol = symbol
        self.connectedExchanges = TradingCredentialsManager.shared.getConnectedExchanges()
        self.selectedExchange = TradingCredentialsManager.shared.defaultExchange
        
        setupSubscriptions()
    }
    
    /// Set up Combine subscriptions (guarded to prevent duplicate setup)
    private func setupSubscriptions() {
        guard !didSetupSubscriptions else { return }
        didSetupSubscriptions = true
        
        $currentSymbol
            .prepend(self.currentSymbol)
            .removeDuplicates()
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { [weak self] newSymbol in
                guard let self = self else { return }
                // Defer all state modifications to avoid "Modifying state during view update"
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    // Cancel previous price stream only
                    self.priceCancellables.removeAll()

                    // If offline, set currentPrice to 0 and skip network work
                    if !NetworkReachability.shared.isReachable {
                        self.currentPrice = 0
                        self.fetchBalance(for: newSymbol)
                        return
                    }

                    // PRICE CONSISTENCY FIX: Use ONLY LivePriceManager as single source of truth
                    // This ensures TradeView shows the same price as CoinDetailView and HomeView
                    // The LivePriceManager already aggregates from Binance WS, CoinGecko, and Firestore
                    
                    // CRITICAL FIX: Extract the BASE symbol (e.g., "ETH" from "ETHUSDT").
                    // Previously used the full pair symbol ("ETHUSDT") to match against coin.symbol ("ETH"),
                    // which NEVER matched. This caused the price to remain at the PREVIOUS coin's price
                    // (e.g., BTC price used for ETH trade), leading to massive incorrect trade execution.
                    // NOTE: Compute from newSymbol (not self.baseAsset) to avoid race with currentSymbol changes.
                    let baseSymbol: String = {
                        let upper = newSymbol.uppercased()
                        let quotes = ["USDT", "USD", "BUSD", "USDC", "FDUSD"]
                        for q in quotes where upper.hasSuffix(q) {
                            return String(upper.dropLast(q.count))
                        }
                        return upper
                    }()
                    
                    // CRITICAL FIX: Always reset price to 0 when switching symbols.
                    // Previously this only happened in the offline branch, so the old symbol's
                    // price persisted and could be used for the new symbol's trade.
                    self.currentPrice = 0
                    
                    // INSTANT PRICE FIX: Show cached price immediately while waiting for live stream.
                    // Check LivePriceManager's current coins (fastest, already in memory)
                    if let cachedCoin = LivePriceManager.shared.currentCoinsList.first(where: {
                        $0.symbol.uppercased() == baseSymbol
                    }), let price = cachedCoin.priceUsd, price > 0, price.isFinite {
                        self.currentPrice = price
                    }
                    // Fallback: check MarketViewModel's allCoins
                    else if let cachedCoin = MarketViewModel.shared.allCoins.first(where: {
                        $0.symbol.uppercased() == baseSymbol
                    }), let price = cachedCoin.priceUsd, price > 0, price.isFinite {
                        self.currentPrice = price
                    }
                    // Fallback: use bestPrice(forSymbol:) which checks all sources
                    else if let bestPrice = MarketViewModel.shared.bestPrice(forSymbol: baseSymbol),
                            bestPrice > 0, bestPrice.isFinite {
                        self.currentPrice = bestPrice
                    }
                    
                    // Single unified stream from LivePriceManager (no parallel API calls)
                    LivePriceManager.shared.realtimePublisher  // 200ms throttle for trading responsiveness
                        .compactMap { coins -> Double? in
                            // CRITICAL FIX: Match by base symbol, not full pair
                            coins.first(where: { $0.symbol.uppercased() == baseSymbol })?.priceUsd
                        }
                        .filter { $0.isFinite && $0 > 0 }
                        .removeDuplicates(by: { a, b in
                            // Reduced tolerance for trading precision
                            let tol = max(0.01, 0.0001 * max(a, b))  // 0.01% tolerance
                            return abs(a - b) < tol
                        })
                        .receive(on: DispatchQueue.main)
                        .sink { [weak self] price in
                            guard let self = self else { return }
                            // PRICE ACCURACY: When the order book is actively streaming
                            // real-time exchange data, skip the CoinGecko/Firebase update
                            // to prevent the display price from "bouncing" between sources.
                            // CoinGecko updates every 30-60s and would overwrite the more
                            // accurate exchange price with stale aggregated data.
                            let orderBookAge = Date().timeIntervalSince(self.lastOrderBookPriceAt)
                            if orderBookAge < 3.0 && self.currentPrice > 0 {
                                return  // Order book price is fresh — skip CoinGecko update
                            }
                            self.currentPrice = price
                        }
                        .store(in: &self.priceCancellables)
                    
                    // PRICE ACCURACY: Subscribe to order book mid-price for real-time exchange pricing.
                    // The order book uses WebSocket data from Binance/Coinbase with sub-second latency,
                    // while CoinGecko via Firebase polls every 30-60 seconds. On the Trading screen,
                    // this gives users the most accurate price for making trading decisions.
                    OrderBookViewModel.shared.$midPrice
                        .filter { $0 > 0 && $0.isFinite }
                        .removeDuplicates(by: { a, b in
                            let tol = max(0.01, 0.0001 * max(a, b))
                            return abs(a - b) < tol
                        })
                        .receive(on: DispatchQueue.main)
                        .sink { [weak self] midPrice in
                            guard let self = self else { return }
                            // Only apply if the order book is tracking the same symbol
                            let obSymbol = OrderBookViewModel.shared.currentSymbol.uppercased()
                            guard obSymbol == baseSymbol else { return }
                            
                            // If we have no price yet, use mid-price directly
                            guard self.currentPrice > 0 else {
                                self.currentPrice = midPrice
                                self.lastOrderBookPriceAt = Date()
                                return
                            }
                            
                            // Sanity check: mid-price should be within 5% of current price.
                            // Larger divergence suggests the order book symbol doesn't match
                            // or there's a data issue — fall back to CoinGecko price.
                            let divergence = abs(midPrice - self.currentPrice) / self.currentPrice
                            guard divergence < 0.05 else { return }
                            
                            self.currentPrice = midPrice
                            self.lastOrderBookPriceAt = Date()
                        }
                        .store(in: &self.priceCancellables)

                    // Fetch balance from connected exchange
                    self.fetchBalance(for: newSymbol)
                    
                    // PRICE CONSISTENCY FIX: Removed separate exchange price fetching
                    // Exchange-specific prices are only used for order execution, not display
                    // This prevents conflicting prices from different sources
                }
            }
            .store(in: &cancellables)
        
        // Watch for exchange changes to refresh balances and prices
        $selectedExchange
            .dropFirst()
            .sink { [weak self] exchange in
                guard let self = self, exchange != nil else { return }
                Task { @MainActor in
                    self.fetchBalance(for: self.currentSymbol)
                    self.fetchExchangePrice(for: self.currentSymbol)
                }
            }
            .store(in: &cancellables)
    }
    
    /// Update the trading symbol without recreating the ViewModel
    /// This is more efficient than creating a new ViewModel instance
    func updateSymbol(_ newSymbol: String) {
        guard newSymbol.uppercased() != currentSymbol.uppercased() else { return }
        currentSymbol = newSymbol.uppercased()
        // The $currentSymbol subscription will handle fetching new data
    }

    // map ticker symbol to CoinGecko ID
    var coinID: String {
        switch currentSymbol.uppercased() {
        case "BTC", "BTCUSDT": return "bitcoin"
        case "ETH", "ETHUSDT": return "ethereum"
        // add other mappings as needed
        default:
            // If the symbol ends with a common quote, strip it to get the base
            let upper = currentSymbol.uppercased()
            let quotes = ["USDT","USD","BUSD","USDC"]
            if let q = quotes.first(where: { upper.hasSuffix($0) }) {
                let base = String(upper.dropLast(q.count))
                return base.lowercased()
            }
            return currentSymbol.lowercased()
        }
    }
    
    /// Extract base asset from symbol (e.g., "BTCUSDT" -> "BTC")
    var baseAsset: String {
        let upper = currentSymbol.uppercased()
        let quotes = ["USDT", "USD", "BUSD", "USDC", "FDUSD"]
        for q in quotes where upper.hasSuffix(q) {
            return String(upper.dropLast(q.count))
        }
        return upper
    }
    
    /// Extract quote asset from symbol (e.g., "BTCUSDT" -> "USDT")
    var quoteAsset: String {
        let upper = currentSymbol.uppercased()
        let quotes = ["USDT", "USD", "BUSD", "USDC", "FDUSD"]
        for q in quotes where upper.hasSuffix(q) {
            return q
        }
        // Default to USDT for most trading
        return "USDT"
    }
    
    /// Check if user has connected any exchange for trading
    var hasConnectedExchange: Bool {
        !connectedExchanges.isEmpty
    }
    
    /// Refresh the list of connected exchanges
    func refreshConnectedExchanges() {
        connectedExchanges = TradingCredentialsManager.shared.getConnectedExchanges()
        if selectedExchange == nil {
            selectedExchange = TradingCredentialsManager.shared.defaultExchange
        }
    }
    
    /// Reset exchange selection when demo mode changes
    /// This ensures the UI doesn't show a demo exchange after demo mode is turned off
    func resetExchangeSelectionIfNeeded() {
        let connected = TradingCredentialsManager.shared.getConnectedExchanges()
        connectedExchanges = connected
        
        // If current selection is no longer valid (e.g., was a demo exchange), reset it
        if let selected = selectedExchange, !connected.contains(selected) {
            selectedExchange = TradingCredentialsManager.shared.defaultExchange
        }
        
        // If no exchanges connected after demo mode off, ensure selectedExchange is nil
        if connected.isEmpty {
            selectedExchange = nil
        }
        
        // Refresh balance and price for the new state
        fetchBalance(for: currentSymbol)
        fetchExchangePrice(for: currentSymbol)
    }

    /// Check if demo mode is enabled (uses unified DemoModeManager)
    private var isTradingDemoMode: Bool {
        DemoModeManager.shared.isDemoMode
    }
    
    /// Check if paper trading mode is enabled
    private var isPaperTradingMode: Bool {
        PaperTradingManager.shared.isPaperTradingEnabled
    }
    
    /// Current fee rate based on selected exchange (or paper trading default)
    /// - Binance/Binance US: 0.10% taker fee
    /// - Coinbase: 0.50% taker fee (Advanced Trade)
    /// - Paper trading: 0.10% simulated fee
    var currentFeeRate: Double {
        // Paper trading uses 0.1% fee
        if isPaperTradingMode { return 0.001 }
        
        // Demo mode uses default fee
        if isTradingDemoMode { return 0.001 }
        
        // Get fee from selected exchange or default to 0.1%
        guard let exchange = selectedExchange else { return 0.001 }
        switch exchange {
        case .binance, .binanceUS:
            return 0.001   // 0.10% taker fee
        case .coinbase:
            return 0.005   // 0.50% taker fee (Coinbase Advanced Trade)
        case .kraken:
            return 0.0026  // 0.26% taker fee
        case .kucoin:
            return 0.001   // 0.10% taker fee
        case .bybit:
            return 0.001   // 0.10% taker fee
        case .okx:
            return 0.001   // 0.10% taker fee
        }
    }
    
    /// Fetch balance from the selected exchange
    func fetchBalance(for symbol: String) {
        // Return paper trading balances when paper trading is enabled
        if isPaperTradingMode {
            self.balance = PaperTradingManager.shared.balance(for: baseAsset)
            self.quoteBalance = PaperTradingManager.shared.balance(for: quoteAsset)
            self.balanceError = nil
            self.isLoadingBalance = false
            return
        }
        
        // Return mock balances in demo mode
        if isTradingDemoMode {
            self.balance = 1.5  // Mock 1.5 of base asset (e.g., BTC)
            self.quoteBalance = 25000.0  // Mock $25k quote balance (USDT/USD)
            self.balanceError = nil
            self.isLoadingBalance = false
            return
        }
        
        guard let exchange = selectedExchange else {
            self.balance = 0.0
            self.quoteBalance = 0.0
            self.balanceError = "No exchange selected"
            return
        }
        
        isLoadingBalance = true
        balanceError = nil
        
        Task {
            do {
                let balances = try await TradingExecutionService.shared.fetchBalances(exchange: exchange)
                
                await MainActor.run {
                    self.allBalances = balances
                    
                    // Find balance for base asset
                    let base = self.baseAsset
                    if let baseBalance = balances.first(where: { $0.asset.uppercased() == base }) {
                        self.balance = baseBalance.free
                    } else {
                        self.balance = 0.0
                    }
                    
                    // Find balance for quote asset (USDT/USD)
                    let quote = self.quoteAsset
                    if let qBalance = balances.first(where: { $0.asset.uppercased() == quote }) {
                        self.quoteBalance = qBalance.free
                    } else {
                        self.quoteBalance = 0.0
                    }
                    
                    self.isLoadingBalance = false
                }
            } catch {
                await MainActor.run {
                    self.balance = 0.0
                    self.quoteBalance = 0.0
                    self.balanceError = error.localizedDescription
                    self.isLoadingBalance = false
                }
            }
        }
    }
    
    /// Refresh all balances
    func refreshBalances() {
        fetchBalance(for: currentSymbol)
    }
    
    // MARK: - Exchange-Specific Price
    
    /// The best price to use for trading
    /// PRICE CONSISTENCY FIX: Always use currentPrice which now comes from LivePriceManager
    /// This ensures display consistency across all views
    /// Exchange-specific prices are only fetched on-demand for order execution
    var tradingPrice: Double {
        return currentPrice
    }
    
    /// Fetch price from the selected exchange
    func fetchExchangePrice(for symbol: String) {
        guard let exchange = selectedExchange else {
            priceSource = .aggregate
            exchangePrice = 0
            return
        }
        
        // Cancel any existing price fetch
        exchangePriceTask?.cancel()
        isLoadingExchangePrice = true
        
        exchangePriceTask = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                let price = try await self.fetchPriceFromExchange(exchange: exchange, symbol: symbol)
                
                if !Task.isCancelled {
                    await MainActor.run {
                        self.exchangePrice = price
                        self.priceSource = self.priceSourceFor(exchange)
                        self.isLoadingExchangePrice = false
                        // NOTE: exchangePrice is kept separate for order execution only.
                        // currentPrice comes exclusively from LivePriceManager (CoinGecko via Firebase)
                        // to ensure price consistency across all views.
                    }
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        self.exchangePrice = 0
                        self.priceSource = .aggregate
                        self.isLoadingExchangePrice = false
                    }
                }
            }
        }
        
        // Set up recurring price fetch
        startExchangePricePolling(for: symbol, exchange: exchange)
    }
    
    private var exchangePricePollingTask: Task<Void, Never>?
    
    private func startExchangePricePolling(for symbol: String, exchange: TradingExchange) {
        exchangePricePollingTask?.cancel()
        
        exchangePricePollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                
                guard let self = self, !Task.isCancelled else { break }
                
                do {
                    let price = try await self.fetchPriceFromExchange(exchange: exchange, symbol: symbol)
                    
                    if !Task.isCancelled && price > 0 {
                        await MainActor.run {
                            // Smooth transition to avoid jumps
                            let diff = abs(price - self.exchangePrice) / max(self.exchangePrice, 1)
                            if diff < 0.1 { // Less than 10% change
                                self.exchangePrice = price
                                // NOTE: Only exchangePrice is updated (for order execution).
                                // currentPrice comes exclusively from LivePriceManager stream.
                            }
                        }
                    }
                } catch {
                    // Continue polling even on errors
                }
            }
        }
    }
    
    private func fetchPriceFromExchange(exchange: TradingExchange, symbol: String) async throws -> Double {
        switch exchange {
        case .binance, .binanceUS:
            return try await fetchBinancePrice(symbol: symbol, isUS: exchange == .binanceUS)
        case .coinbase:
            return try await fetchCoinbasePrice(symbol: symbol)
        case .kraken:
            return try await fetchKrakenPrice(symbol: symbol)
        case .kucoin:
            return try await fetchKuCoinPrice(symbol: symbol)
        case .bybit:
            return try await fetchBybitPrice(symbol: symbol)
        case .okx:
            return try await fetchOKXPrice(symbol: symbol)
        }
    }
    
    // PERFORMANCE FIX: Static cache for exchange prices to reduce API calls
    private static var priceCache: [String: (price: Double, fetchedAt: Date)] = [:]
    private static let priceCacheTTL: TimeInterval = 10.0  // 10 second cache
    
    private func fetchBinancePrice(symbol: String, isUS: Bool) async throws -> Double {
        // FIX: Use ExchangeHostPolicy for automatic geo-block fallback
        // If user selected global Binance but it's geo-blocked, use US instead
        let endpoints: ExchangeEndpoints
        let quote: String
        
        if isUS {
            endpoints = .us
            quote = "USD"
        } else {
            // Check if global is blocked, if so fall back to US
            let currentEndpoints = await ExchangeHostPolicy.shared.currentEndpoints()
            let currentRegion = await ExchangeHostPolicy.shared.currentRegion()
            endpoints = currentEndpoints
            quote = currentRegion == .us ? "USD" : "USDT"
        }
        
        let pair = baseAsset.uppercased() + quote
        let cacheKey = "\(endpoints.restBase.host ?? "binance"):\(pair)"
        
        // PERFORMANCE FIX: Check cache first
        let now = Date()
        if let cached = Self.priceCache[cacheKey],
           now.timeIntervalSince(cached.fetchedAt) < Self.priceCacheTTL {
            return cached.price
        }
        
        // PERFORMANCE FIX: Check rate limiter before making request
        guard APIRequestCoordinator.shared.canMakeRequest(for: .binance) else {
            // Return cached value if available, otherwise throw
            if let cached = Self.priceCache[cacheKey] {
                return cached.price
            }
            throw TradingError.apiError(message: "Rate limited - please wait")
        }
        
        APIRequestCoordinator.shared.recordRequest(for: .binance)
        
        guard let url = URL(string: "\(endpoints.restBase)/ticker/price?symbol=\(pair)") else {
            APIRequestCoordinator.shared.recordFailure(for: .binance)
            throw TradingError.invalidSymbol
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            // FIX: Report HTTP status to policy for geo-block detection
            if let httpResponse = response as? HTTPURLResponse {
                await ExchangeHostPolicy.shared.onHTTPStatus(httpResponse.statusCode)
                guard httpResponse.statusCode == 200 else {
                    APIRequestCoordinator.shared.recordFailure(for: .binance)
                    throw TradingError.apiError(message: "Failed to fetch Binance price")
                }
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let priceStr = json["price"] as? String,
                  let price = Double(priceStr) else {
                APIRequestCoordinator.shared.recordFailure(for: .binance)
                throw TradingError.parseError
            }
            
            // PERFORMANCE FIX: Update cache
            Self.priceCache[cacheKey] = (price, Date())
            APIRequestCoordinator.shared.recordSuccess(for: .binance)
            
            return price
        } catch {
            APIRequestCoordinator.shared.recordFailure(for: .binance)
            throw error
        }
    }
    
    private func fetchCoinbasePrice(symbol: String) async throws -> Double {
        let productId = baseAsset.uppercased() + "-USD"
        guard let url = URL(string: "https://api.exchange.coinbase.com/products/\(productId)/ticker") else {
            throw TradingError.invalidSymbol
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw TradingError.apiError(message: "Failed to fetch Coinbase price")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let priceStr = json["price"] as? String,
              let price = Double(priceStr) else {
            throw TradingError.parseError
        }
        
        return price
    }
    
    private func fetchKrakenPrice(symbol: String) async throws -> Double {
        // Kraken uses XBT for Bitcoin
        let asset = baseAsset.uppercased() == "BTC" ? "XBT" : baseAsset.uppercased()
        let pair = asset + "USD"
        guard let url = URL(string: "https://api.kraken.com/0/public/Ticker?pair=\(pair)") else {
            throw TradingError.invalidSymbol
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw TradingError.apiError(message: "Failed to fetch Kraken price")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let firstPair = result.first?.value as? [String: Any],
              let priceArray = firstPair["c"] as? [String],  // "c" is last trade closed array [price, lot volume]
              let priceStr = priceArray.first,
              let price = Double(priceStr) else {
            throw TradingError.parseError
        }
        
        return price
    }
    
    private func fetchKuCoinPrice(symbol: String) async throws -> Double {
        let pair = baseAsset.uppercased() + "-USDT"
        guard let url = URL(string: "https://api.kucoin.com/api/v1/market/orderbook/level1?symbol=\(pair)") else {
            throw TradingError.invalidSymbol
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw TradingError.apiError(message: "Failed to fetch KuCoin price")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let priceStr = dataDict["price"] as? String,
              let price = Double(priceStr) else {
            throw TradingError.parseError
        }
        
        return price
    }
    
    private func fetchBybitPrice(symbol: String) async throws -> Double {
        let pair = baseAsset.uppercased() + "USDT"
        guard let url = URL(string: "https://api.bybit.com/v5/market/tickers?category=spot&symbol=\(pair)") else {
            throw TradingError.invalidSymbol
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw TradingError.apiError(message: "Failed to fetch Bybit price")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let retCode = json["retCode"] as? Int, retCode == 0,
              let result = json["result"] as? [String: Any],
              let list = result["list"] as? [[String: Any]],
              let firstTicker = list.first,
              let priceStr = firstTicker["lastPrice"] as? String,
              let price = Double(priceStr) else {
            throw TradingError.parseError
        }
        
        return price
    }
    
    private func fetchOKXPrice(symbol: String) async throws -> Double {
        let instId = baseAsset.uppercased() + "-USDT"
        guard let url = URL(string: "https://www.okx.com/api/v5/market/ticker?instId=\(instId)") else {
            throw TradingError.invalidSymbol
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw TradingError.apiError(message: "Failed to fetch OKX price")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = json["code"] as? String, code == "0",
              let dataArray = json["data"] as? [[String: Any]],
              let firstTicker = dataArray.first,
              let priceStr = firstTicker["last"] as? String,
              let price = Double(priceStr) else {
            throw TradingError.parseError
        }
        
        return price
    }

    private func priceSourceFor(_ exchange: TradingExchange) -> PriceSource {
        switch exchange {
        case .binance: return .binance
        case .binanceUS: return .binanceUS
        case .coinbase: return .coinbase
        case .kraken: return .kraken
        case .kucoin: return .kucoin
        case .bybit: return .bybit
        case .okx: return .okx
        }
    }
    
    /// Stop exchange price polling when view disappears
    func stopExchangePricePolling() {
        exchangePricePollingTask?.cancel()
        exchangePricePollingTask = nil
        exchangePriceTask?.cancel()
        exchangePriceTask = nil
    }

    /// Decrement a typed quantity by 1, clamped at 0.
    func decrementQuantity(_ quantityString: inout String) {
        let raw = (Double(quantityString) ?? 0) - 1
        let value = max(0, raw)
        quantityString = String(format: "%.4f", value)
    }

    /// Increment a typed quantity by 1.
    func incrementQuantity(_ quantityString: inout String) {
        let raw = (Double(quantityString) ?? 0) + 1
        let value = max(0, raw)
        quantityString = String(format: "%.4f", value)
    }

    /// Fill the order quantity based on a percentage of current balance.
    /// For BUY orders, calculate quantity from quote balance / price
    /// For SELL orders, calculate quantity from base balance
    func fillQuantity(forPercent percent: Int, side: TradeSide) -> String {
        let percentFraction = Double(percent) / 100.0
        
        if side == .buy {
            // For buying, use quote balance divided by current price
            guard currentPrice > 0 else { return "0.0000" }
            let maxQty = (quoteBalance * percentFraction) / currentPrice
            return String(format: "%.4f", maxQty.isFinite ? maxQty : 0)
        } else {
            // For selling, use base balance
            let qty = balance * percentFraction
            return String(format: "%.4f", qty.isFinite ? qty : 0)
        }
    }
    
    /// Legacy method for backward compatibility
    func fillQuantity(forPercent percent: Int) -> String {
        return fillQuantity(forPercent: percent, side: .sell)
    }

    /// Published property to trigger upgrade prompt from the view
    @Published var showTradeExecutionUpgradePrompt: Bool = false
    
    /// Execute a trade - defaults to paper trading for all regular users
    ///
    /// IMPORTANT: Live trading is DEVELOPER-ONLY. For all regular users:
    /// - Trades are automatically executed as paper trades
    /// - This is enforced by `AppConfig.liveTradingEnabled` returning false for non-developers
    /// - Paper trading requires Pro+ subscription ($9.99/month)
    /// - Free users see a locked overlay and cannot reach this method
    ///
    /// - Parameters:
    ///   - side: Buy or sell
    ///   - symbol: Trading pair symbol (e.g., "BTC")
    ///   - orderType: Market, limit, stop, or stop-limit
    ///   - quantity: Amount to trade as string
    ///   - limitPriceStr: Limit price for limit/stop-limit orders (optional, from UI)
    ///   - stopPriceStr: Stop price for stop/stop-limit orders (optional, from UI)
    func executeTrade(side: TradeSide, symbol: String, orderType: OrderType, quantity: String, limitPriceStr: String? = nil, stopPriceStr: String? = nil) {
        // SECURITY: Rate limit trade execution to prevent rapid double-submissions
        let now = Date()
        guard now.timeIntervalSince(lastTradeTimestamp) >= Self.minimumTradeInterval else {
            orderErrorMessage = "Please wait a moment before placing another trade"
            return
        }
        
        guard let qty = Double(quantity), qty > 0 else {
            orderErrorMessage = "Invalid quantity"
            return
        }
        
        // Parse and validate price inputs based on order type
        let parsedLimitPrice = Double(limitPriceStr ?? "") ?? 0
        let parsedStopPrice = Double(stopPriceStr ?? "") ?? 0
        
        // Validate order-type specific price inputs BEFORE setting isExecutingOrder
        switch orderType {
        case .limit:
            guard parsedLimitPrice > 0 else {
                orderErrorMessage = "Please enter a valid limit price"
                return
            }
        case .stop:
            guard parsedStopPrice > 0 else {
                orderErrorMessage = "Please enter a valid stop price"
                return
            }
        case .stopLimit:
            guard parsedStopPrice > 0 else {
                orderErrorMessage = "Please enter a valid stop price"
                return
            }
            guard parsedLimitPrice > 0 else {
                orderErrorMessage = "Please enter a valid limit price"
                return
            }
        case .market:
            break  // Market orders don't need price inputs
        }
        
        // Validate we have a valid market price for calculations
        guard currentPrice > 0 else {
            orderErrorMessage = "Unable to get current market price. Please try again."
            return
        }
        
        // Validate sufficient balance before proceeding
        let routesToPaperMode = isPaperTradingMode || !AppConfig.liveTradingEnabled
        if routesToPaperMode && side == .sell && qty > balance {
            orderErrorMessage = "Paper trading short positions are not supported yet. Buy/hold the asset before selling, or use live derivatives for short strategies."
            return
        }
        
        if side == .buy {
            // FIX: For limit orders, use the limit price for balance check (not market price).
            // A limit buy at $50K shouldn't require funds for $100K market price.
            let checkPrice: Double
            switch orderType {
            case .limit, .stopLimit:
                checkPrice = parsedLimitPrice > 0 ? parsedLimitPrice : currentPrice
            default:
                checkPrice = currentPrice
            }
            let requiredQuote = qty * checkPrice
            // Add small buffer (0.1%) for price slippage and fees
            let requiredWithBuffer = requiredQuote * 1.001
            guard quoteBalance >= requiredWithBuffer else {
                let shortfall = requiredWithBuffer - quoteBalance
                orderErrorMessage = "Insufficient \(quoteAsset) balance. Need \(String(format: "%.2f", shortfall)) more."
                return
            }
        } else {
            guard qty <= balance else {
                let shortfall = qty - balance
                orderErrorMessage = "Insufficient \(baseAsset) balance. Need \(String(format: "%.6f", shortfall)) more."
                return
            }
        }
        
        // Clear previous state
        orderErrorMessage = nil
        lastOrderResult = nil
        isExecutingOrder = true
        lastTradeTimestamp = Date() // Record timestamp for rate limiting
        
        // Handle paper trading mode (Paper Trading has its own subscription check in PaperTradingManager)
        if isPaperTradingMode {
            executePaperTrade(side: side, symbol: symbol, orderType: orderType, quantity: qty)
            return
        }
        
        // DEFAULT PATH FOR ALL REGULAR USERS: Paper trading
        // Live trading is developer-only (AppConfig.liveTradingEnabled = false for regular users)
        // This ensures all trades go through paper trading simulation for safety
        guard AppConfig.liveTradingEnabled else {
            // Auto-enable paper trading and execute as paper trade
            if !PaperTradingManager.isEnabled {
                PaperTradingManager.shared.enablePaperTrading()
            }
            executePaperTrade(side: side, symbol: symbol, orderType: orderType, quantity: qty)
            return
        }
        
        // Check subscription access for real trade execution
        guard SubscriptionManager.shared.hasAccess(to: .tradeExecution) else {
            orderErrorMessage = "Upgrade to Pro to execute real trades"
            isExecutingOrder = false
            showTradeExecutionUpgradePrompt = true
            return
        }
        
        // Real trading requires an exchange
        guard let exchange = selectedExchange else {
            orderErrorMessage = "No exchange selected. Please connect an exchange in Settings."
            isExecutingOrder = false
            return
        }
        
        Task {
            do {
                let result: OrderResult
                
                switch orderType {
                case .market:
                    result = try await TradingExecutionService.shared.submitMarketOrder(
                        exchange: exchange,
                        symbol: symbol,
                        side: side,
                        quantity: qty
                    )
                    
                case .limit:
                    // Use the user-specified limit price (already validated above)
                    result = try await TradingExecutionService.shared.submitLimitOrder(
                        exchange: exchange,
                        symbol: symbol,
                        side: side,
                        quantity: qty,
                        price: parsedLimitPrice
                    )
                    
                case .stop:
                    // Stop price already validated above
                    result = try await TradingExecutionService.shared.submitStopOrder(
                        exchange: exchange,
                        symbol: symbol,
                        side: side,
                        quantity: qty,
                        stopPrice: parsedStopPrice
                    )
                    
                case .stopLimit:
                    // Stop and limit prices already validated above
                    result = try await TradingExecutionService.shared.submitStopLimitOrder(
                        exchange: exchange,
                        symbol: symbol,
                        side: side,
                        quantity: qty,
                        stopPrice: parsedStopPrice,
                        limitPrice: parsedLimitPrice
                    )
                }
                
                await MainActor.run {
                    self.lastOrderResult = result
                    self.isExecutingOrder = false
                    
                    if result.success {
                        self.showOrderConfirmation = true
                        // Refresh balances after successful order
                        self.refreshBalances()
                        
                        // Record trade to history
                        // FIX: Use the actual execution price, not self.currentPrice which
                        // may have changed during the async order submission.
                        // For limit orders: use the limit price. For market orders: use
                        // the result's average price (accounts for slippage), falling back
                        // to currentPrice if unavailable.
                        let recordPrice: Double = {
                            if let avgPrice = result.averagePrice, avgPrice > 0 {
                                return avgPrice
                            }
                            switch orderType {
                            case .limit, .stopLimit:
                                return parsedLimitPrice
                            default:
                                return self.currentPrice
                            }
                        }()
                        LiveTradeHistoryManager.shared.recordTrade(
                            from: result,
                            symbol: symbol,
                            side: side,
                            quantity: qty,
                            price: recordPrice,
                            orderType: orderType
                        )
                        
                        // Haptic feedback for success
                        #if os(iOS)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        #endif
                    } else {
                        self.orderErrorMessage = result.errorMessage ?? "Order failed"
                        
                        // Haptic feedback for error
                        #if os(iOS)
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                        #endif
                    }
                }
            } catch {
                await MainActor.run {
                    self.isExecutingOrder = false
                    self.orderErrorMessage = error.localizedDescription
                    
                    #if os(iOS)
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    #endif
                }
            }
        }
    }
    
    /// Execute a paper trade (simulated trade with virtual money)
    private func executePaperTrade(side: TradeSide, symbol: String, orderType: OrderType, quantity: Double) {
        // PRICE ACCURACY FIX: Always cross-validate currentPrice against a fresh lookup.
        // This is a critical safety net to prevent executing trades at the WRONG coin's price.
        // Bug scenario: User views BTC ($70K), switches to ETH, price subscription uses wrong symbol
        // format for matching -> currentPrice stays at BTC price -> ETH trade executes at $70K.
        var price = currentPrice
        // Extract base symbol by stripping quote SUFFIX only (not all occurrences)
        // e.g., "ETHUSDT" -> "ETH", "BTCUSD" -> "BTC", "USDCUSDT" -> "USDC"
        let symUpper: String = {
            let upper = symbol.uppercased()
            let quotes = ["USDT", "USD", "BUSD", "USDC", "FDUSD"]
            for q in quotes where upper.hasSuffix(q) {
                return String(upper.dropLast(q.count))
            }
            return upper
        }()
        
        // CRITICAL: Always attempt to get a fresh verified price for the CORRECT symbol
        if let freshPrice = MarketViewModel.shared.bestPrice(forSymbol: symUpper), freshPrice > 0, freshPrice.isFinite {
            if price <= 0 || !price.isFinite {
                // No valid price at all — use fresh price
                price = freshPrice
                self.currentPrice = freshPrice
            } else {
                // CROSS-VALIDATION: If currentPrice diverges >20% from verified price,
                // it's likely showing the WRONG coin's price (e.g., BTC price for ETH trade).
                // Use the verified price instead.
                let divergence = abs(price - freshPrice) / freshPrice
                if divergence > 0.20 {
                    #if DEBUG
                    print("⚠️ [TradeVM] Price cross-validation FAILED for \(symUpper): currentPrice=$\(price), freshPrice=$\(freshPrice), divergence=\(Int(divergence * 100))%. Using fresh price.")
                    #endif
                    price = freshPrice
                    self.currentPrice = freshPrice
                }
            }
        } else if price <= 0 || !price.isFinite {
            // No fresh price available and currentPrice is invalid
            orderErrorMessage = "Unable to get current price for \(symUpper)"
            isExecutingOrder = false
            return
        }
        
        guard price > 0 else {
            orderErrorMessage = "Unable to get current price"
            isExecutingOrder = false
            return
        }
        
        // Execute the paper trade
        let result = PaperTradingManager.shared.executePaperTrade(
            symbol: symbol,
            side: side,
            quantity: quantity,
            price: price,
            orderType: orderType.rawValue
        )
        
        self.lastOrderResult = result
        self.isExecutingOrder = false
        
        if result.success {
            self.showOrderConfirmation = true
            // Refresh balances after successful order
            self.refreshBalances()
            
            // Haptic feedback for success
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
        } else {
            self.orderErrorMessage = result.errorMessage ?? "Paper trade failed"
            
            // Haptic feedback for error
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            #endif
        }
    }
    
    /// Execute a limit order with a specific price
    func executeLimitOrder(side: TradeSide, symbol: String, quantity: String, price: Double) {
        guard let qty = Double(quantity), qty > 0 else {
            orderErrorMessage = "Invalid quantity"
            return
        }
        
        guard price > 0 else {
            orderErrorMessage = "Invalid price"
            return
        }
        
        // Clear previous state
        orderErrorMessage = nil
        lastOrderResult = nil
        isExecutingOrder = true
        
        // Paper mode currently simulates spot inventory only (no borrowing/margin shorts).
        let routesToPaperMode = isPaperTradingMode || !AppConfig.liveTradingEnabled
        if routesToPaperMode && side == .sell && qty > balance {
            orderErrorMessage = "Paper trading short positions are not supported yet. Buy/hold the asset before selling, or use live derivatives for short strategies."
            isExecutingOrder = false
            return
        }
        
        // Handle paper trading mode - execute limit order as paper trade
        if isPaperTradingMode {
            executePaperLimitTrade(side: side, symbol: symbol, quantity: qty, price: price)
            return
        }
        
        // SAFETY: Block live trading when disabled at app config level
        // This redirects to paper trading for legal/regulatory safety
        guard AppConfig.liveTradingEnabled else {
            // Auto-enable paper trading and execute as paper trade
            if !PaperTradingManager.isEnabled {
                PaperTradingManager.shared.enablePaperTrading()
            }
            executePaperLimitTrade(side: side, symbol: symbol, quantity: qty, price: price)
            return
        }
        
        // Check subscription access for real trade execution
        guard SubscriptionManager.shared.hasAccess(to: .tradeExecution) else {
            orderErrorMessage = "Upgrade to Pro to execute real trades"
            isExecutingOrder = false
            showTradeExecutionUpgradePrompt = true
            return
        }
        
        // Real trading requires an exchange
        guard let exchange = selectedExchange else {
            orderErrorMessage = "No exchange selected. Please connect an exchange in Settings."
            isExecutingOrder = false
            return
        }
        
        Task {
            do {
                let result = try await TradingExecutionService.shared.submitLimitOrder(
                    exchange: exchange,
                    symbol: symbol,
                    side: side,
                    quantity: qty,
                    price: price
                )
                
                await MainActor.run {
                    self.lastOrderResult = result
                    self.isExecutingOrder = false
                    
                    if result.success {
                        self.showOrderConfirmation = true
                        self.refreshBalances()
                        
                        #if os(iOS)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        #endif
                    } else {
                        self.orderErrorMessage = result.errorMessage ?? "Order failed"
                        
                        #if os(iOS)
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                        #endif
                    }
                }
            } catch {
                await MainActor.run {
                    self.isExecutingOrder = false
                    self.orderErrorMessage = error.localizedDescription
                    
                    #if os(iOS)
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    #endif
                }
            }
        }
    }
    
    /// Execute a paper limit trade (simulated trade with virtual money at a specific price)
    private func executePaperLimitTrade(side: TradeSide, symbol: String, quantity: Double, price: Double) {
        // SAFETY: Validate the limit price is reasonable by cross-checking against live market.
        // This prevents executing at obviously wrong prices (e.g., BTC price for ETH trade).
        let validatedPrice = price
        let symUpper: String = {
            let upper = symbol.uppercased()
            let quotes = ["USDT", "USD", "BUSD", "USDC", "FDUSD"]
            for q in quotes where upper.hasSuffix(q) {
                return String(upper.dropLast(q.count))
            }
            return upper
        }()
        
        if let freshPrice = MarketViewModel.shared.bestPrice(forSymbol: symUpper), freshPrice > 0, freshPrice.isFinite {
            let divergence = abs(validatedPrice - freshPrice) / freshPrice
            // For limit orders, allow wider divergence (50%) since users intentionally set prices
            // above/below market. But >50x divergence means wrong coin's price entirely.
            if divergence > 50.0 {
                #if DEBUG
                print("⚠️ [TradeVM] Limit order price cross-validation FAILED for \(symUpper): limitPrice=$\(validatedPrice), marketPrice=$\(freshPrice), divergence=\(Int(divergence * 100))%")
                #endif
                orderErrorMessage = "Price $\(String(format: "%.2f", validatedPrice)) seems incorrect for \(symUpper) (market: $\(String(format: "%.2f", freshPrice))). Please verify."
                isExecutingOrder = false
                return
            }
        }
        
        guard validatedPrice > 0, validatedPrice.isFinite else {
            orderErrorMessage = "Invalid limit price"
            isExecutingOrder = false
            return
        }
        
        // Execute the paper trade with the specified limit price
        let result = PaperTradingManager.shared.executePaperTrade(
            symbol: symbol,
            side: side,
            quantity: quantity,
            price: validatedPrice,
            orderType: "LIMIT"
        )
        
        self.lastOrderResult = result
        self.isExecutingOrder = false
        
        if result.success {
            self.showOrderConfirmation = true
            // Refresh balances after successful order
            self.refreshBalances()
            
            // Haptic feedback for success
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
        } else {
            self.orderErrorMessage = result.errorMessage ?? "Paper limit trade failed"
            
            // Haptic feedback for error
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            #endif
        }
    }
    
    /// Test connection to the selected exchange
    func testExchangeConnection() async -> Bool {
        guard let exchange = selectedExchange else { return false }
        
        do {
            return try await TradingExecutionService.shared.testConnection(exchange: exchange)
        } catch {
            return false
        }
    }
}

