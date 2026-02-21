import SwiftUI
import Combine

// MARK: - Cache Models

private struct CachedPriceData: Codable {
    let symbol: String
    let quotes: [CachedQuote]
}

private struct CachedQuote: Codable {
    let exchangeName: String
    let quote: String
    let bid: Double
    let ask: Double
}

// MARK: - Models

/// Exchange quote with bid/ask prices
struct ExchangeQuote: Identifiable, Hashable {
    enum Exchange: String, CaseIterable, Hashable {
        case binance = "Binance"
        case coinbase = "Coinbase"
        case kucoin = "KuCoin"
        case bybit = "Bybit"
        case kraken = "Kraken"
        case okx = "OKX"
        case gateio = "Gate.io"
        case gemini = "Gemini"
        
        var icon: String {
            switch self {
            case .binance: return "b.circle.fill"
            case .coinbase: return "c.circle.fill"
            case .kucoin: return "k.circle.fill"
            case .bybit: return "b.square.fill"
            case .kraken: return "k.square.fill"
            case .okx: return "o.circle.fill"
            case .gateio: return "g.circle.fill"
            case .gemini: return "g.square.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .binance: return Color(red: 0.95, green: 0.76, blue: 0.15)
            case .coinbase: return Color(red: 0.0, green: 0.45, blue: 0.95)
            case .kucoin: return Color(red: 0.15, green: 0.75, blue: 0.55)
            case .bybit: return Color(red: 0.95, green: 0.65, blue: 0.15)
            case .kraken: return Color(red: 0.55, green: 0.35, blue: 0.85)
            case .okx: return Color(red: 0.85, green: 0.85, blue: 0.85)
            case .gateio: return Color(red: 0.0, green: 0.6, blue: 0.4)
            case .gemini: return Color(red: 0.0, green: 0.8, blue: 0.9)
            }
        }
        
        /// Typical maker/taker fee for the exchange
        var fee: Double {
            switch self {
            case .binance: return 0.001   // 0.10%
            case .kucoin:  return 0.001   // 0.10%
            case .bybit:   return 0.001   // 0.10%
            case .kraken:  return 0.0026  // 0.26%
            case .coinbase: return 0.005  // 0.50%
            case .okx:     return 0.001   // 0.10%
            case .gateio:  return 0.002   // 0.20%
            case .gemini:  return 0.0035  // 0.35%
            }
        }
        
        var feeLabel: String {
            String(format: "%.2f%%", fee * 100)
        }
    }
    
    let id = UUID()
    let exchange: Exchange
    let symbol: String
    let quote: String
    let bid: Double
    let ask: Double
    let time: Date
    
    /// Bid-ask spread as percentage
    var spreadPct: Double {
        guard ask > 0 else { return 0 }
        return (ask - bid) / ask
    }
    
    /// Mid price (average of bid and ask)
    var midPrice: Double {
        (bid + ask) / 2
    }
    
    /// Effective buy price after fees
    var effectiveBuyPrice: Double {
        ask * (1 + exchange.fee)
    }
    
    /// Effective sell price after fees
    var effectiveSellPrice: Double {
        bid * (1 - exchange.fee)
    }
}

/// Comparison result for a single coin across exchanges
struct CoinPriceComparison: Identifiable {
    let id = UUID()
    let symbol: String
    let quotes: [ExchangeQuote]
    let fetchedAt: Date
    
    var bestBuyQuote: ExchangeQuote? {
        quotes.filter { $0.ask > 0 }.min(by: { $0.effectiveBuyPrice < $1.effectiveBuyPrice })
    }
    
    var bestSellQuote: ExchangeQuote? {
        quotes.filter { $0.bid > 0 }.max(by: { $0.effectiveSellPrice < $1.effectiveSellPrice })
    }
    
    var priceRange: (min: Double, max: Double)? {
        let prices = quotes.compactMap { $0.midPrice > 0 ? $0.midPrice : nil }
        guard let min = prices.min(), let max = prices.max() else { return nil }
        return (min, max)
    }
    
    /// Price variance as percentage (max - min) / min
    var priceVariance: Double {
        guard let range = priceRange, range.min > 0 else { return 0 }
        return (range.max - range.min) / range.min
    }
}

// MARK: - ViewModel

@MainActor
final class ExchangePriceComparisonViewModel: ObservableObject {
    @Published var comparisons: [CoinPriceComparison] = []
    @Published var isLoading: Bool = false
    @Published var lastUpdated: Date? = nil
    @Published var error: String? = nil
    @Published var loadProgress: Double = 0
    
    @Published var selectedSymbol: String = "BTC"
    @Published var enabledExchanges: Set<ExchangeQuote.Exchange> = Set(ExchangeQuote.Exchange.allCases)
    
    private var autoTimer: AnyCancellable?
    private var symbols: [String] = []
    private var isScanning: Bool = false
    @Published var hasCompletedFirstLoad: Bool = false
    
    /// True when refreshing in background with existing cached data (show subtle indicator instead of full progress bar)
    @Published var isBackgroundRefresh: Bool = false
    
    /// True when showing sample/demo data because all exchanges failed
    @Published var isUsingSampleData: Bool = false
    
    private let kExchanges = "pricecomp.exchanges"
    private let kSelectedSymbol = "pricecomp.symbol"
    private let kCachedPrices = "pricecomp.cached_prices"
    private let kCacheTimestamp = "pricecomp.cache_timestamp"
    private let cacheStaleThreshold: TimeInterval = 5 * 60 // 5 minutes
    
    private var cancellables = Set<AnyCancellable>()
    
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 15  // Longer timeout for reliability
        config.timeoutIntervalForResource = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 8
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
            "Accept-Language": "en-US,en;q=0.9"
        ]
        return URLSession(configuration: config)
    }()
    
    init() {
        // Load persisted values
        if let raw = UserDefaults.standard.string(forKey: kExchanges) {
            let parts = raw.split(separator: ",").map { String($0) }
            let all = Set(ExchangeQuote.Exchange.allCases)
            let mapped = Set(parts.compactMap { ExchangeQuote.Exchange(rawValue: $0) })
            if !mapped.isEmpty { self.enabledExchanges = all.intersection(mapped) }
        }
        // FIX: Always start with BTC as default rather than loading persisted symbol.
        // The old behavior persisted auto-selected symbols (e.g. BNB from alphabetical sort),
        // causing the section to never show Bitcoin on app launch.
        // Users expect BTC as the default; manual selection is preserved per-session only.
        // Clean up stale persisted symbol key
        UserDefaults.standard.removeObject(forKey: kSelectedSymbol)
        
        // Load cached prices for instant display
        loadCachedPrices()
        
        // Observe changes and save
        $enabledExchanges.dropFirst().sink { [weak self] set in
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                let s = set.map { $0.rawValue }.joined(separator: ",")
                UserDefaults.standard.set(s, forKey: self?.kExchanges ?? "")
            }
        }.store(in: &cancellables)
        
        // FIX: Removed selectedSymbol persistence. Always start fresh with BTC.
        // Previously, auto-selected symbols (from the fallback when BTC data was briefly
        // unavailable) were persisted and caused the section to permanently show non-BTC coins.
    }
    
    // MARK: - Caching
    
    private func loadCachedPrices() {
        guard let data = UserDefaults.standard.data(forKey: kCachedPrices),
              let timestamp = UserDefaults.standard.object(forKey: kCacheTimestamp) as? Date else {
            return
        }
        
        do {
            let cached = try JSONDecoder().decode([CachedPriceData].self, from: data)
            // Convert cached data to comparisons
            let comparisons = cached.compactMap { cachedItem -> CoinPriceComparison? in
                let quotes = cachedItem.quotes.compactMap { q -> ExchangeQuote? in
                    guard let exchange = ExchangeQuote.Exchange(rawValue: q.exchangeName) else { return nil }
                    return ExchangeQuote(
                        exchange: exchange,
                        symbol: cachedItem.symbol,
                        quote: q.quote,
                        bid: q.bid,
                        ask: q.ask,
                        time: timestamp
                    )
                }
                guard !quotes.isEmpty else { return nil }
                return CoinPriceComparison(symbol: cachedItem.symbol, quotes: quotes, fetchedAt: timestamp)
            }
            
            if !comparisons.isEmpty {
                self.comparisons = comparisons
                self.lastUpdated = timestamp
                self.hasCompletedFirstLoad = true
                return
            }
        } catch {
            // Cache corrupted, load sample data instead
        }
        
        // LIVE DATA ONLY - No sample data for production
        // Show empty state until real exchange prices are fetched
        self.comparisons = []
        self.isUsingSampleData = false
        self.hasCompletedFirstLoad = false
        #if DEBUG
        print("[ExchangePrice] No cache found, will fetch live prices")
        #endif
    }
    
    private func savePricesToCache() {
        let cacheData = comparisons.map { comparison -> CachedPriceData in
            let quotes = comparison.quotes.map { q -> CachedQuote in
                CachedQuote(exchangeName: q.exchange.rawValue, quote: q.quote, bid: q.bid, ask: q.ask)
            }
            return CachedPriceData(symbol: comparison.symbol, quotes: quotes)
        }
        
        do {
            let data = try JSONEncoder().encode(cacheData)
            UserDefaults.standard.set(data, forKey: kCachedPrices)
            UserDefaults.standard.set(Date(), forKey: kCacheTimestamp)
        } catch {
            // Failed to cache, ignore
        }
    }
    
    // PERFORMANCE FIX: Increased default interval from 30s to 60s to reduce network load
    func startAutoRefresh(symbols: [String], interval: TimeInterval = 60) {
        self.symbols = symbols.map { $0.uppercased() }
        autoTimer?.cancel()
        autoTimer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                // PERFORMANCE FIX: Skip fetch during scroll
                guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
                Task { await self?.loadPrices() }
            }
    }
    
    func stop() { autoTimer?.cancel(); autoTimer = nil }
    
    func loadOnce(symbols: [String]) async {
        self.symbols = symbols.map { $0.uppercased() }
        
        // Skip refresh if cache is very fresh (< 15 seconds) to avoid unnecessary network calls
        // But always load if we have no data
        if let lastUpdate = lastUpdated, !comparisons.isEmpty {
            let cacheAge = Date().timeIntervalSince(lastUpdate)
            if cacheAge < 15 {
                // Cache is very fresh, skip refresh
                return
            }
        }
        
        await loadPrices()
        
        // Auto-retry once if we got no data
        if comparisons.isEmpty && !isScanning {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
            await loadPrices()
        }
    }
    
    func refresh(force: Bool = false) async {
        if force {
            // Reset scanning state to allow refresh even if we just updated
            isScanning = false
        }
        await loadPrices()
    }
    
    /// Get comparison for a specific symbol
    func comparison(for symbol: String) -> CoinPriceComparison? {
        comparisons.first { $0.symbol.uppercased() == symbol.uppercased() }
    }
    
    // MARK: - Exchange Symbol Mappings
    
    /// Kraken uses unique symbol names for many coins
    private static let krakenSymbolMap: [String: String] = [
        "BTC": "XBT", "DOGE": "XDG", "REP": "REP",
        // Most other symbols are the same
    ]
    
    /// Coins that trade against USD on Coinbase (not USDC)
    private static let coinbaseUSDPairs: Set<String> = [
        "BTC", "ETH", "SOL", "XRP", "ADA", "DOGE", "AVAX", "LINK", "MATIC", "DOT",
        "ATOM", "UNI", "LTC", "BCH", "SHIB", "NEAR", "APT", "ARB", "OP", "FIL",
        "ICP", "XLM", "VET", "HBAR", "IMX", "ALGO", "AAVE", "GRT", "STX", "EOS"
    ]
    
    /// Coins that may not have USDT pairs on some exchanges (use USDC or BTC as fallback)
    private static let useFallbackQuote: Set<String> = [
        "GUSD", "PAX", "USDP" // Stablecoins that don't have USDT pairs
    ]
    
    // MARK: - Private
    
    private struct ExchangePairs {
        var binance: [String]   // Primary + fallback pairs
        var coinbase: [String]
        var kucoin: [String]
        var bybit: [String]
        var kraken: [String]
        var okx: [String]
        var gateio: [String]
        var gemini: [String]
    }
    
    /// Track which exchanges failed for diagnostic purposes
    @Published var failedExchanges: Set<ExchangeQuote.Exchange> = []
    
    // MARK: - Circuit Breaker for Geo-Blocked Exchanges
    
    /// Track consecutive failures for each exchange to implement circuit breaker pattern
    private var exchangeFailureCounts: [ExchangeQuote.Exchange: Int] = [:]
    /// Track when each exchange was blocked
    private var exchangeBlockedUntil: [ExchangeQuote.Exchange: Date] = [:]
    /// Number of consecutive failures before blocking an exchange
    private let circuitBreakerThreshold: Int = 3
    /// Duration to block an exchange after threshold failures (5 minutes)
    private let circuitBreakerBlockDuration: TimeInterval = 300
    /// Track if we've already logged a block message this session to avoid log spam
    private var hasLoggedBlockMessage: Set<ExchangeQuote.Exchange> = []
    /// LOG SPAM FIX: Track if we've logged a failure for an exchange (reset on success)
    private var hasLoggedFailureMessage: Set<ExchangeQuote.Exchange> = []
    
    /// Check if an exchange is currently blocked by the circuit breaker
    private func isExchangeBlocked(_ exchange: ExchangeQuote.Exchange) -> Bool {
        if let blockedUntil = exchangeBlockedUntil[exchange] {
            if Date() < blockedUntil {
                return true
            } else {
                // Block expired, reset state
                exchangeBlockedUntil.removeValue(forKey: exchange)
                exchangeFailureCounts[exchange] = 0
                hasLoggedBlockMessage.remove(exchange)
            }
        }
        return false
    }
    
    /// Record a failure for an exchange (HTTP 403, 451, etc.)
    private func recordExchangeFailure(_ exchange: ExchangeQuote.Exchange, statusCode: Int) {
        exchangeFailureCounts[exchange, default: 0] += 1
        let count = exchangeFailureCounts[exchange] ?? 0
        
        if count >= circuitBreakerThreshold {
            // Block this exchange
            exchangeBlockedUntil[exchange] = Date().addingTimeInterval(circuitBreakerBlockDuration)
            exchangeFailureCounts[exchange] = 0
            
            // Only log once per block to avoid spam
            if !hasLoggedBlockMessage.contains(exchange) {
                hasLoggedBlockMessage.insert(exchange)
                #if DEBUG
                print("[ExchangePrice] Circuit breaker triggered for \(exchange.rawValue) after \(count) HTTP \(statusCode) errors - blocking for \(Int(circuitBreakerBlockDuration))s")
                #endif
            }
        }
    }
    
    /// Record a success for an exchange, resetting failure count
    private func recordExchangeSuccess(_ exchange: ExchangeQuote.Exchange) {
        exchangeFailureCounts[exchange] = 0
        hasLoggedFailureMessage.remove(exchange) // Reset so we log again if failures resume
    }
    
    /// LOG SPAM FIX: Check if we should log a failure for an exchange
    private func shouldLogExchangeFailure(_ exchange: ExchangeQuote.Exchange) -> Bool {
        if hasLoggedFailureMessage.contains(exchange) {
            return false
        }
        hasLoggedFailureMessage.insert(exchange)
        return true
    }
    
    private func mapToPairs(_ symbol: String) -> ExchangePairs {
        let upper = symbol.uppercased()
        
        // Binance: Try USDT first, then BUSD, then USDC
        let binancePairs = [
            upper + "USDT",
            upper + "USDC",
            upper + "BUSD"
        ]
        
        // Bybit: USDT is primary
        let bybitPairs = [
            upper + "USDT",
            upper + "USDC"
        ]
        
        // KuCoin: Uses hyphen separator
        let kucoinPairs = [
            upper + "-USDT",
            upper + "-USDC"
        ]
        
        // Coinbase: USD for major coins, USDC for others
        let coinbasePairs: [String]
        if Self.coinbaseUSDPairs.contains(upper) {
            coinbasePairs = [upper + "-USD", upper + "-USDT"]
        } else {
            coinbasePairs = [upper + "-USDT", upper + "-USD", upper + "-USDC"]
        }
        
        // Kraken: Uses unique symbol names and USD pairs
        let krakenBase = Self.krakenSymbolMap[upper] ?? upper
        let krakenPairs: [String]
        switch upper {
        case "BTC": krakenPairs = ["XBTUSD", "XXBTZUSD"]
        case "ETH": krakenPairs = ["ETHUSD", "XETHZUSD"]
        case "DOGE": krakenPairs = ["XDGUSD", "DOGEUSD"]
        default: krakenPairs = [krakenBase + "USD", upper + "USD"]
        }
        
        // OKX: Uses hyphen separator (e.g., BTC-USDT)
        let okxPairs = [
            upper + "-USDT",
            upper + "-USDC"
        ]
        
        // Gate.io: Uses underscore separator (e.g., BTC_USDT)
        let gateioPairs = [
            upper + "_USDT",
            upper + "_USDC"
        ]
        
        // Gemini: Lowercase, no separator (e.g., btcusd)
        let geminiPairs = [
            (upper + "USD").lowercased(),
            (upper + "USDT").lowercased()
        ]
        
        return ExchangePairs(
            binance: binancePairs,
            coinbase: coinbasePairs,
            kucoin: kucoinPairs,
            bybit: bybitPairs,
            kraken: krakenPairs,
            okx: okxPairs,
            gateio: gateioPairs,
            gemini: geminiPairs
        )
    }
    
    private func fetchQuotes(for symbol: String) async -> [ExchangeQuote] {
        let pairs = mapToPairs(symbol)
        let now = Date()
        var quotes: [ExchangeQuote] = []
        await withTaskGroup(of: ExchangeQuote?.self) { group in
            if enabledExchanges.contains(.binance) {
                group.addTask { await self.fetchBinanceWithFallback(pairs: pairs.binance, symbol: symbol, time: now) }
            }
            if enabledExchanges.contains(.coinbase) {
                group.addTask { await self.fetchCoinbaseWithFallback(products: pairs.coinbase, symbol: symbol, time: now) }
            }
            if enabledExchanges.contains(.kucoin) {
                group.addTask { await self.fetchKuCoinWithFallback(symbols: pairs.kucoin, base: symbol, time: now) }
            }
            // Check circuit breaker before fetching from Bybit
            if enabledExchanges.contains(.bybit) && !self.isExchangeBlocked(.bybit) {
                group.addTask { await self.fetchBybitWithFallback(symbols: pairs.bybit, base: symbol, time: now) }
            }
            if enabledExchanges.contains(.kraken) {
                group.addTask { await self.fetchKrakenWithFallback(pairs: pairs.kraken, base: symbol, time: now) }
            }
            if enabledExchanges.contains(.okx) {
                group.addTask { await self.fetchOKXWithFallback(pairs: pairs.okx, base: symbol, time: now) }
            }
            // Check circuit breaker before fetching from Gate.io
            if enabledExchanges.contains(.gateio) && !self.isExchangeBlocked(.gateio) {
                group.addTask { await self.fetchGateIOWithFallback(pairs: pairs.gateio, base: symbol, time: now) }
            }
            if enabledExchanges.contains(.gemini) {
                group.addTask { await self.fetchGeminiWithFallback(pairs: pairs.gemini, base: symbol, time: now) }
            }
            for await q in group { if let q { quotes.append(q) } }
        }
        return quotes
    }
    
    private func clampSymbols(_ list: [String]) -> [String] {
        let defaults = ["BTC", "ETH", "SOL", "XRP", "ADA", "DOGE", "BNB", "AVAX", "LINK", "MATIC", "DOT", "ATOM"]
        let cleaned = list.map { $0.uppercased() }.filter { !$0.isEmpty }
        if cleaned.isEmpty { return defaults }
        return Array(cleaned.prefix(16)) // Increased from 12 to 16
    }
    
    // MARK: - Batch Fetching for Better Performance
    
    /// Fetch all Binance prices in one API call (tries Binance US as fallback for geo-blocked users)
    private func fetchBinanceBatch(symbols: [String], time: Date) async -> [String: ExchangeQuote] {
        // Try main Binance first, then fall back to Binance US if empty/blocked
        var results = await fetchBinanceBatchFromEndpoint(
            baseURL: "https://api.binance.com/api/v3/ticker/bookTicker",
            symbols: symbols,
            time: time
        )
        
        // If main Binance returned no results, try Binance US as fallback
        if results.isEmpty {
            #if DEBUG
            print("[ExchangePrice] Main Binance empty, trying Binance US fallback")
            #endif
            // BINANCE-US-FIX: Binance.US is shut down - use global mirror
            results = await fetchBinanceBatchFromEndpoint(
                baseURL: "https://api4.binance.com/api/v3/ticker/bookTicker",
                symbols: symbols,
                time: time
            )
        }
        
        return results
    }
    
    /// Helper to fetch from a specific Binance endpoint (main or US)
    private func fetchBinanceBatchFromEndpoint(baseURL: String, symbols: [String], time: Date) async -> [String: ExchangeQuote] {
        var results: [String: ExchangeQuote] = [:]
        guard let url = URL(string: baseURL) else { return results }
        
        do {
            let (data, response) = try await session.data(from: url)
            
            // Check for geo-blocking or rate limiting
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 451 || httpResponse.statusCode == 403 {
                    #if DEBUG
                    print("[ExchangePrice] Binance endpoint geo-blocked: \(baseURL)")
                    #endif
                    // PERFORMANCE FIX: Record failure for circuit breaker
                    recordExchangeFailure(.binance, statusCode: httpResponse.statusCode)
                    return results
                }
                if httpResponse.statusCode == 429 {
                    #if DEBUG
                    print("[ExchangePrice] Binance endpoint rate limited: \(baseURL)")
                    #endif
                    // PERFORMANCE FIX: Record failure for circuit breaker
                    recordExchangeFailure(.binance, statusCode: httpResponse.statusCode)
                    return results
                }
            }
            
            if let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                let symbolSet = Set(symbols.map { $0.uppercased() })
                for item in array {
                    guard let pairSymbol = item["symbol"] as? String,
                          let bidStr = item["bidPrice"] as? String,
                          let askStr = item["askPrice"] as? String,
                          let bid = Double(bidStr), let ask = Double(askStr),
                          bid > 0, ask > 0 else { continue }
                    
                    // Check if this pair matches any of our symbols (USDT, USDC, or USD for Binance US)
                    for baseSymbol in symbolSet {
                        if pairSymbol == baseSymbol + "USDT" || pairSymbol == baseSymbol + "USDC" || pairSymbol == baseSymbol + "USD" {
                            let quote: String
                            if pairSymbol.hasSuffix("USDT") {
                                quote = "USDT"
                            } else if pairSymbol.hasSuffix("USDC") {
                                quote = "USDC"
                            } else {
                                quote = "USD"
                            }
                            results[baseSymbol] = ExchangeQuote(
                                exchange: .binance,
                                symbol: baseSymbol,
                                quote: quote,
                                bid: bid,
                                ask: ask,
                                time: time
                            )
                            break
                        }
                    }
                }
                // Record success if we got data
                if !results.isEmpty {
                    recordExchangeSuccess(.binance)
                }
            }
        } catch {
            #if DEBUG
            print("[ExchangePrice] Binance batch fetch error from \(baseURL): \(error.localizedDescription)")
            #endif
        }
        return results
    }
    
    /// Fetch all KuCoin prices in one API call
    private func fetchKuCoinBatch(symbols: [String], time: Date) async -> [String: ExchangeQuote] {
        var results: [String: ExchangeQuote] = [:]
        guard let url = URL(string: "https://api.kucoin.com/api/v1/market/allTickers") else { return results }
        
        do {
            let (data, response) = try await session.data(from: url)
            
            // PERFORMANCE FIX: Check HTTP status code and record failures for circuit breaker
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 403 || httpResponse.statusCode == 451 {
                    recordExchangeFailure(.kucoin, statusCode: httpResponse.statusCode)
                    return results
                }
                if httpResponse.statusCode == 429 {
                    recordExchangeFailure(.kucoin, statusCode: httpResponse.statusCode)
                    return results
                }
                if !(200...299).contains(httpResponse.statusCode) {
                    recordExchangeFailure(.kucoin, statusCode: httpResponse.statusCode)
                    return results
                }
            }
            
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataObj = obj["data"] as? [String: Any],
               let ticker = dataObj["ticker"] as? [[String: Any]] {
                
                let symbolSet = Set(symbols.map { $0.uppercased() })
                for item in ticker {
                    guard let pairSymbol = item["symbol"] as? String,
                          let bidStr = item["buy"] as? String,
                          let askStr = item["sell"] as? String,
                          let bid = Double(bidStr), let ask = Double(askStr),
                          bid > 0, ask > 0 else { continue }
                    
                    // Check if this pair matches any of our symbols
                    for baseSymbol in symbolSet {
                        if pairSymbol == baseSymbol + "-USDT" || pairSymbol == baseSymbol + "-USDC" {
                            let quote = pairSymbol.hasSuffix("-USDT") ? "USDT" : "USDC"
                            results[baseSymbol] = ExchangeQuote(
                                exchange: .kucoin,
                                symbol: baseSymbol,
                                quote: quote,
                                bid: bid,
                                ask: ask,
                                time: time
                            )
                            break
                        }
                    }
                }
                // Record success if we got data
                if !results.isEmpty {
                    recordExchangeSuccess(.kucoin)
                }
            }
        } catch {
            #if DEBUG
            print("[ExchangePrice] KuCoin batch fetch failed: \(error.localizedDescription)")
            #endif
        }
        return results
    }
    
    /// Fetch all OKX prices in one API call
    private func fetchOKXBatch(symbols: [String], time: Date) async -> [String: ExchangeQuote] {
        var results: [String: ExchangeQuote] = [:]
        guard let url = URL(string: "https://www.okx.com/api/v5/market/tickers?instType=SPOT") else { return results }
        
        do {
            let (data, response) = try await session.data(from: url)
            
            // PERFORMANCE FIX: Check HTTP status code and record failures for circuit breaker
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 403 || httpResponse.statusCode == 451 {
                    recordExchangeFailure(.okx, statusCode: httpResponse.statusCode)
                    return results
                }
                if httpResponse.statusCode == 429 {
                    recordExchangeFailure(.okx, statusCode: httpResponse.statusCode)
                    return results
                }
                if !(200...299).contains(httpResponse.statusCode) {
                    recordExchangeFailure(.okx, statusCode: httpResponse.statusCode)
                    return results
                }
            }
            
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let code = obj["code"] as? String, code == "0",
               let dataArray = obj["data"] as? [[String: Any]] {
                
                let symbolSet = Set(symbols.map { $0.uppercased() })
                for item in dataArray {
                    guard let instId = item["instId"] as? String,
                          let bidStr = item["bidPx"] as? String,
                          let askStr = item["askPx"] as? String,
                          let bid = Double(bidStr), let ask = Double(askStr),
                          bid > 0, ask > 0 else { continue }
                    
                    // OKX format: BTC-USDT
                    for baseSymbol in symbolSet {
                        if instId == baseSymbol + "-USDT" || instId == baseSymbol + "-USDC" {
                            let quote = instId.hasSuffix("-USDT") ? "USDT" : "USDC"
                            results[baseSymbol] = ExchangeQuote(
                                exchange: .okx,
                                symbol: baseSymbol,
                                quote: quote,
                                bid: bid,
                                ask: ask,
                                time: time
                            )
                            break
                        }
                    }
                }
                // Record success if we got data
                if !results.isEmpty {
                    recordExchangeSuccess(.okx)
                }
            }
        } catch {
            #if DEBUG
            print("[ExchangePrice] OKX batch fetch failed: \(error.localizedDescription)")
            #endif
        }
        return results
    }
    
    /// Fetch all Gate.io prices in one API call
    private func fetchGateIOBatch(symbols: [String], time: Date) async -> [String: ExchangeQuote] {
        var results: [String: ExchangeQuote] = [:]
        guard let url = URL(string: "https://api.gateio.ws/api/v4/spot/tickers") else { return results }
        
        do {
            let (data, response) = try await session.data(from: url)
            
            // PERFORMANCE FIX: Check HTTP status code and record failures for circuit breaker
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 403 || httpResponse.statusCode == 451 {
                    recordExchangeFailure(.gateio, statusCode: httpResponse.statusCode)
                    return results
                }
                if httpResponse.statusCode == 429 || httpResponse.statusCode == 400 {
                    recordExchangeFailure(.gateio, statusCode: httpResponse.statusCode)
                    return results
                }
                if !(200...299).contains(httpResponse.statusCode) {
                    recordExchangeFailure(.gateio, statusCode: httpResponse.statusCode)
                    return results
                }
            }
            
            if let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                let symbolSet = Set(symbols.map { $0.uppercased() })
                for item in array {
                    guard let currencyPair = item["currency_pair"] as? String,
                          let bidStr = item["highest_bid"] as? String,
                          let askStr = item["lowest_ask"] as? String,
                          let bid = Double(bidStr), let ask = Double(askStr),
                          bid > 0, ask > 0 else { continue }
                    
                    // Gate.io format: BTC_USDT
                    for baseSymbol in symbolSet {
                        if currencyPair == baseSymbol + "_USDT" || currencyPair == baseSymbol + "_USDC" {
                            let quote = currencyPair.hasSuffix("_USDT") ? "USDT" : "USDC"
                            results[baseSymbol] = ExchangeQuote(
                                exchange: .gateio,
                                symbol: baseSymbol,
                                quote: quote,
                                bid: bid,
                                ask: ask,
                                time: time
                            )
                            break
                        }
                    }
                }
                // Record success if we got data
                if !results.isEmpty {
                    recordExchangeSuccess(.gateio)
                }
            }
        } catch {
            #if DEBUG
            print("[ExchangePrice] Gate.io batch fetch failed: \(error.localizedDescription)")
            #endif
        }
        return results
    }
    
    private func loadPrices() async {
        // PERFORMANCE FIX: Check API coordinator before making requests
        // This prevents thundering herd during startup and foreground transitions
        guard APIRequestCoordinator.shared.canMakeRequest(for: .exchangeComparison) else {
            #if DEBUG
            print("[ExchangePrice] Blocked by APIRequestCoordinator - skipping load")
            #endif
            return
        }
        APIRequestCoordinator.shared.recordRequest(for: .exchangeComparison)
        
        // Prevent concurrent loads, but allow if stuck for > 30 seconds
        if isScanning {
            // Check if we've been scanning too long (stuck state)
            if let lastUpdate = lastUpdated, Date().timeIntervalSince(lastUpdate) < 30 {
                return
            }
            // Reset stuck state
            #if DEBUG
            print("[ExchangePrice] Resetting stuck scanning state")
            #endif
        }
        isScanning = true
        
        // Determine if this is a background refresh (we already have data to show)
        let hasCachedData = !comparisons.isEmpty
        
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isLoading = true
            self.isBackgroundRefresh = hasCachedData
            self.error = nil
            // Only reset progress if this is a fresh load (no cached data)
            if !hasCachedData {
                self.loadProgress = 0
                self.failedExchanges = [] // Reset failed exchanges on fresh load
            }
        }
        
        let list = clampSymbols(symbols)
        var newComparisons: [CoinPriceComparison] = []
        var completedCount = 0
        let totalCount = list.count
        
        let scanStartTime = Date()
        let maxScanDuration: TimeInterval = 20 // Increased from 15 to 20
        
        // Step 1: Batch fetch from exchanges that support it (Binance, KuCoin, OKX, Gate.io)
        var binanceBatch: [String: ExchangeQuote] = [:]
        var kucoinBatch: [String: ExchangeQuote] = [:]
        var okxBatch: [String: ExchangeQuote] = [:]
        var gateioBatch: [String: ExchangeQuote] = [:]
        
        // Track which exchanges failed for diagnostics
        var batchFailedExchanges: Set<ExchangeQuote.Exchange> = []
        
        let shouldBatchFetch = enabledExchanges.contains(.binance) || enabledExchanges.contains(.kucoin) ||
                               enabledExchanges.contains(.okx) || enabledExchanges.contains(.gateio)
        
        if shouldBatchFetch {
            #if DEBUG
            print("[ExchangePrice] Starting batch fetch for \(list.count) symbols...")
            #endif
            
            // PERFORMANCE FIX: Check circuit breaker BEFORE starting batch fetches
            // This prevents wasted network requests to geo-blocked or failing exchanges
            let binanceBlocked = isExchangeBlocked(.binance)
            let kucoinBlocked = isExchangeBlocked(.kucoin)
            let okxBlocked = isExchangeBlocked(.okx)
            let gateioBlocked = isExchangeBlocked(.gateio)
            
            // Use a timeout task to ensure we don't hang forever
            let batchTask = Task {
                await withTaskGroup(of: Void.self) { group in
                    if enabledExchanges.contains(.binance) && !binanceBlocked {
                        group.addTask {
                            binanceBatch = await self.fetchBinanceBatch(symbols: list, time: Date())
                            #if DEBUG
                            print("[ExchangePrice] Binance batch: \(binanceBatch.count) quotes")
                            #endif
                        }
                    }
                    if enabledExchanges.contains(.kucoin) && !kucoinBlocked {
                        group.addTask {
                            kucoinBatch = await self.fetchKuCoinBatch(symbols: list, time: Date())
                            #if DEBUG
                            print("[ExchangePrice] KuCoin batch: \(kucoinBatch.count) quotes")
                            #endif
                        }
                    }
                    if enabledExchanges.contains(.okx) && !okxBlocked {
                        group.addTask {
                            okxBatch = await self.fetchOKXBatch(symbols: list, time: Date())
                            #if DEBUG
                            print("[ExchangePrice] OKX batch: \(okxBatch.count) quotes")
                            #endif
                        }
                    }
                    if enabledExchanges.contains(.gateio) && !gateioBlocked {
                        group.addTask {
                            gateioBatch = await self.fetchGateIOBatch(symbols: list, time: Date())
                            #if DEBUG
                            print("[ExchangePrice] Gate.io batch: \(gateioBatch.count) quotes")
                            #endif
                        }
                    }
                }
            }
            
            // Wait for batch task with 12 second timeout
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                return true
            }
            
            // Race between batch completion and timeout
            _ = await withTaskGroup(of: Bool.self) { group in
                group.addTask { await batchTask.value; return false }
                group.addTask { await timeoutTask.value }
                
                // Return first completed result
                if let result = await group.next() {
                    if result {
                        #if DEBUG
                        print("[ExchangePrice] Batch fetch timed out, continuing with partial data")
                        #endif
                        batchTask.cancel()
                    }
                    group.cancelAll()
                    return result
                }
                return false
            }
            
            // Check which batch fetches failed
            if enabledExchanges.contains(.binance) && binanceBatch.isEmpty {
                batchFailedExchanges.insert(.binance)
            }
            if enabledExchanges.contains(.okx) && okxBatch.isEmpty {
                batchFailedExchanges.insert(.okx)
            }
            if enabledExchanges.contains(.gateio) && gateioBatch.isEmpty {
                batchFailedExchanges.insert(.gateio)
            }
            
            // Update progress after batch fetches
            DispatchQueue.main.async { [weak self] in
                self?.loadProgress = 0.3
            }
        }
        
        do {
            // Step 2: Fetch remaining exchanges per-symbol (Coinbase, Bybit, Kraken)
            // Capture MainActor-isolated values before entering task groups
            let currentEnabledExchanges = enabledExchanges
            
            // Pre-compute pairs for all symbols (MainActor context)
            var allPairs: [String: ExchangePairs] = [:]
            for sym in list {
                allPairs[sym] = mapToPairs(sym)
            }
            
            let batchSize = 6 // Increased from 3 to 6
            var idx = 0
            while idx < list.count {
                if Date().timeIntervalSince(scanStartTime) > maxScanDuration { break }
                
                let end = min(idx + batchSize, list.count)
                let batch = Array(list[idx..<end])
                
                try await withThrowingTaskGroup(of: CoinPriceComparison.self) { group in
                    for sym in batch {
                        // Capture pairs for this symbol
                        let pairs = allPairs[sym] ?? mapToPairs(sym)
                        let hasBinanceBatch = binanceBatch[sym] != nil
                        let hasKuCoinBatch = kucoinBatch[sym] != nil
                        let hasOKXBatch = okxBatch[sym] != nil
                        let hasGateIOBatch = gateioBatch[sym] != nil
                        let binanceQuote = binanceBatch[sym]
                        let kucoinQuote = kucoinBatch[sym]
                        let okxQuote = okxBatch[sym]
                        let gateioQuote = gateioBatch[sym]
                        
                        group.addTask { [weak self] in
                            guard let self else {
                                return CoinPriceComparison(symbol: sym, quotes: [], fetchedAt: Date())
                            }
                            
                            var quotes: [ExchangeQuote] = []
                            let now = Date()
                            
                            // Add batch results for exchanges that support it
                            if let bQuote = binanceQuote {
                                quotes.append(bQuote)
                            }
                            if let kQuote = kucoinQuote {
                                quotes.append(kQuote)
                            }
                            if let oQuote = okxQuote {
                                quotes.append(oQuote)
                            }
                            if let gQuote = gateioQuote {
                                quotes.append(gQuote)
                            }
                            
                            // PERFORMANCE FIX: If we have 3+ quotes from batch, skip individual fetches
                            // This dramatically reduces network overhead when batch fetches are working
                            let hasSufficientBatchData = quotes.count >= 3
                            if hasSufficientBatchData {
                                return CoinPriceComparison(symbol: sym, quotes: quotes, fetchedAt: now)
                            }
                            
                            // PERFORMANCE FIX: Check circuit breaker for all exchanges before individual fetches
                            // This prevents spawning many tasks that will fail
                            // Use MainActor.run to access MainActor-isolated state
                            let (binanceIndividualBlocked, kucoinIndividualBlocked, okxIndividualBlocked, 
                                 gateioIndividualBlocked, coinbaseBlocked, bybitBlocked, 
                                 krakenBlocked, geminiBlocked) = await MainActor.run {
                                (self.isExchangeBlocked(.binance),
                                 self.isExchangeBlocked(.kucoin),
                                 self.isExchangeBlocked(.okx),
                                 self.isExchangeBlocked(.gateio),
                                 self.isExchangeBlocked(.coinbase),
                                 self.isExchangeBlocked(.bybit),
                                 self.isExchangeBlocked(.kraken),
                                 self.isExchangeBlocked(.gemini))
                            }
                            
                            // Fetch remaining exchanges in parallel (only if not blocked)
                            await withTaskGroup(of: ExchangeQuote?.self) { innerGroup in
                                // Only fetch Binance individually if batch failed AND not blocked
                                if !hasBinanceBatch && currentEnabledExchanges.contains(.binance) && !binanceIndividualBlocked {
                                    innerGroup.addTask { await self.fetchBinanceWithFallback(pairs: pairs.binance, symbol: sym, time: now) }
                                }
                                // Only fetch KuCoin individually if batch failed AND not blocked
                                if !hasKuCoinBatch && currentEnabledExchanges.contains(.kucoin) && !kucoinIndividualBlocked {
                                    innerGroup.addTask { await self.fetchKuCoinWithFallback(symbols: pairs.kucoin, base: sym, time: now) }
                                }
                                // Only fetch OKX individually if batch failed AND not blocked
                                if !hasOKXBatch && currentEnabledExchanges.contains(.okx) && !okxIndividualBlocked {
                                    innerGroup.addTask { await self.fetchOKXWithFallback(pairs: pairs.okx, base: sym, time: now) }
                                }
                                // Only fetch Gate.io individually if batch failed AND not blocked
                                if !hasGateIOBatch && currentEnabledExchanges.contains(.gateio) && !gateioIndividualBlocked {
                                    innerGroup.addTask { await self.fetchGateIOWithFallback(pairs: pairs.gateio, base: sym, time: now) }
                                }
                                // Coinbase, Bybit, Kraken, Gemini - check circuit breaker
                                if currentEnabledExchanges.contains(.coinbase) && !coinbaseBlocked {
                                    innerGroup.addTask { await self.fetchCoinbaseWithFallback(products: pairs.coinbase, symbol: sym, time: now) }
                                }
                                if currentEnabledExchanges.contains(.bybit) && !bybitBlocked {
                                    innerGroup.addTask { await self.fetchBybitWithFallback(symbols: pairs.bybit, base: sym, time: now) }
                                }
                                if currentEnabledExchanges.contains(.kraken) && !krakenBlocked {
                                    innerGroup.addTask { await self.fetchKrakenWithFallback(pairs: pairs.kraken, base: sym, time: now) }
                                }
                                if currentEnabledExchanges.contains(.gemini) && !geminiBlocked {
                                    innerGroup.addTask { await self.fetchGeminiWithFallback(pairs: pairs.gemini, base: sym, time: now) }
                                }
                                for await q in innerGroup { if let q { quotes.append(q) } }
                            }
                            
                            return CoinPriceComparison(symbol: sym, quotes: quotes, fetchedAt: now)
                        }
                    }
                    for try await comparison in group {
                        completedCount += 1
                        let progress = 0.3 + (Double(completedCount) / Double(totalCount)) * 0.7
                        DispatchQueue.main.async { [weak self] in
                            self?.loadProgress = progress
                        }
                        // Add comparison even with partial data (at least 1 exchange)
                        if !comparison.quotes.isEmpty {
                            newComparisons.append(comparison)
                        }
                    }
                }
                idx = end
                
                if idx < list.count {
                    try? await Task.sleep(nanoseconds: 50_000_000) // Reduced from 100ms to 50ms
                }
            }
            
            // Determine which exchanges returned no data across all symbols
            let successfulExchanges = Set(newComparisons.flatMap { $0.quotes.map { $0.exchange } })
            let allFailedExchanges = enabledExchanges.subtracting(successfulExchanges)
            
            #if DEBUG
            if !allFailedExchanges.isEmpty {
                print("[ExchangePrice] Exchanges with no data: \(allFailedExchanges.map { $0.rawValue }.joined(separator: ", "))")
            }
            print("[ExchangePrice] Successful exchanges: \(successfulExchanges.map { $0.rawValue }.joined(separator: ", "))")
            #endif
            
            Task { @MainActor [weak self] in
                guard let self else { return }
                
                // LIVE DATA ONLY - No sample data fallback
                if newComparisons.isEmpty || newComparisons.allSatisfy({ $0.quotes.isEmpty }) {
                    #if DEBUG
                    print("[ExchangePrice] All exchanges failed, no data available")
                    #endif
                    // Keep existing data if any, otherwise show empty
                    if self.comparisons.isEmpty {
                        self.error = "Unable to connect to exchanges"
                    } else {
                        self.error = "Using cached prices (offline)"
                    }
                    self.isUsingSampleData = false
                } else {
                    self.comparisons = newComparisons.sorted { $0.symbol < $1.symbol }
                    self.isUsingSampleData = false
                    self.error = nil
                    // Save to cache for instant display on next launch
                    self.savePricesToCache()
                }
                
                self.lastUpdated = Date()
                self.isLoading = false
                self.isBackgroundRefresh = false
                self.hasCompletedFirstLoad = true
                self.loadProgress = 1.0
                self.isScanning = false
                self.failedExchanges = allFailedExchanges
            }
        } catch {
            Task { @MainActor [weak self] in
                guard let self else { return }
                
                // LIVE DATA ONLY - No sample data on error
                if !newComparisons.isEmpty {
                    self.comparisons = newComparisons.sorted { $0.symbol < $1.symbol }
                }
                // Keep existing cached data if available, otherwise show error
                self.isUsingSampleData = false
                
                self.lastUpdated = Date()
                self.isLoading = false
                self.isBackgroundRefresh = false
                self.hasCompletedFirstLoad = true
                self.error = "Connection issue" + (self.comparisons.isEmpty ? "" : " - showing cached data")
                self.isScanning = false
                self.failedExchanges = batchFailedExchanges
            }
        }
    }
    
    // MARK: - Exchange API Fetchers with Fallback Support
    
    /// Try multiple Binance pairs until one works, then try Binance US as fallback
    private func fetchBinanceWithFallback(pairs: [String], symbol: String, time: Date) async -> ExchangeQuote? {
        // Try main Binance first
        for pair in pairs {
            if let quote = await fetchBinance(pair: pair, symbol: symbol, time: time, useUS: false) {
                return quote
            }
        }
        
        // If main Binance failed, try Binance US as fallback
        #if DEBUG
        print("[ExchangePrice] Main Binance failed for \(symbol), trying Binance US")
        #endif
        
        // Binance US pairs (includes USD pairs)
        let usPairs = [symbol + "USD", symbol + "USDT", symbol + "USDC"]
        for pair in usPairs {
            if let quote = await fetchBinance(pair: pair, symbol: symbol, time: time, useUS: true) {
                return quote
            }
        }
        
        return nil
    }
    
    private func fetchBinance(pair: String, symbol: String, time: Date, useUS: Bool) async -> ExchangeQuote? {
        // BINANCE-US-FIX: Binance.US is shut down - use global mirror for "US" fallback
        let baseURL = useUS ? "https://api4.binance.com" : "https://api.binance.com"
        guard let url = URL(string: "\(baseURL)/api/v3/ticker/bookTicker?symbol=\(pair)") else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            // Check for HTTP errors
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 451 || httpResponse.statusCode == 403 {
                    #if DEBUG
                    // LOG SPAM FIX: Only log first geo-block (both Binance and Binance US use .binance enum)
                    let shouldLog = await MainActor.run { self.shouldLogExchangeFailure(.binance) }
                    if shouldLog {
                        print("[ExchangePrice] Binance\(useUS ? " US" : "") geo-blocked (HTTP \(httpResponse.statusCode)) - suppressing further logs")
                    }
                    #endif
                    return nil
                }
                if httpResponse.statusCode == 429 {
                    #if DEBUG
                    print("[ExchangePrice] Binance\(useUS ? " US" : "") rate limited for \(symbol)")
                    #endif
                    return nil
                }
                if httpResponse.statusCode != 200 {
                    return nil
                }
            }
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let bidStr = obj["bidPrice"] as? String,
               let askStr = obj["askPrice"] as? String,
               let bid = Double(bidStr), let ask = Double(askStr), bid > 0, ask > 0 {
                // Extract quote currency from pair
                let quote: String
                if pair.hasSuffix("USDT") {
                    quote = "USDT"
                } else if pair.hasSuffix("USDC") {
                    quote = "USDC"
                } else {
                    quote = "USD"
                }
                return ExchangeQuote(exchange: .binance, symbol: symbol, quote: quote, bid: bid, ask: ask, time: time)
            }
        } catch {
            #if DEBUG
            // LOG SPAM FIX: Only log first failure, skip cancelled errors entirely
            if !(error.localizedDescription.contains("cancelled")) {
                let shouldLog = await MainActor.run { self.shouldLogExchangeFailure(.binance) }
                if shouldLog {
                    print("[ExchangePrice] Binance\(useUS ? " US" : "") fetch error for \(symbol): \(error.localizedDescription)")
                }
            }
            #endif
        }
        return nil
    }
    
    /// Try multiple Coinbase products until one works
    private func fetchCoinbaseWithFallback(products: [String], symbol: String, time: Date) async -> ExchangeQuote? {
        for product in products {
            if let quote = await fetchCoinbase(product: product, symbol: symbol, time: time) {
                return quote
            }
        }
        return nil
    }
    
    private func fetchCoinbase(product: String, symbol: String, time: Date) async -> ExchangeQuote? {
        guard let url = URL(string: "https://api.exchange.coinbase.com/products/\(product)/ticker") else { return nil }
        do {
            var req = URLRequest(url: url)
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.timeoutInterval = 6
            let (data, response) = try await session.data(for: req)
            
            // PERFORMANCE FIX: Check HTTP status and record failures for circuit breaker
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 403 || httpResponse.statusCode == 451 || httpResponse.statusCode == 429 {
                    await MainActor.run { self.recordExchangeFailure(.coinbase, statusCode: httpResponse.statusCode) }
                    return nil
                }
            }
            
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let bid = (obj["bid"] as? String).flatMap(Double.init) ?? (obj["price"] as? String).flatMap(Double.init) ?? 0
                let ask = (obj["ask"] as? String).flatMap(Double.init) ?? (obj["price"] as? String).flatMap(Double.init) ?? 0
                guard bid > 0 && ask > 0 else { return nil }
                let quote = product.hasSuffix("-USD") ? "USD" : (product.hasSuffix("-USDT") ? "USDT" : "USDC")
                await MainActor.run { self.recordExchangeSuccess(.coinbase) }
                return ExchangeQuote(exchange: .coinbase, symbol: symbol, quote: quote, bid: bid, ask: ask, time: time)
            }
        } catch {
            // ERROR HANDLING FIX: Log errors for debugging (but suppress spam)
            #if DEBUG
            let shouldLog = await MainActor.run { self.shouldLogExchangeFailure(.coinbase) }
            if shouldLog {
                print("[ExchangePriceComparison] Coinbase fetch error: \(error.localizedDescription)")
            }
            #endif
        }
        return nil
    }
    
    /// Try multiple KuCoin symbols until one works
    private func fetchKuCoinWithFallback(symbols: [String], base: String, time: Date) async -> ExchangeQuote? {
        for symbol in symbols {
            if let quote = await fetchKuCoin(symbol: symbol, base: base, time: time) {
                return quote
            }
        }
        return nil
    }
    
    private func fetchKuCoin(symbol: String, base: String, time: Date) async -> ExchangeQuote? {
        guard let url = URL(string: "https://api.kucoin.com/api/v1/market/orderbook/level1?symbol=\(symbol)") else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            
            // PERFORMANCE FIX: Check HTTP status and record failures for circuit breaker
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 403 || httpResponse.statusCode == 451 || httpResponse.statusCode == 429 {
                    await MainActor.run { self.recordExchangeFailure(.kucoin, statusCode: httpResponse.statusCode) }
                    return nil
                }
            }
            
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataObj = obj["data"] as? [String: Any] {
                let bid = (dataObj["bestBid"] as? String).flatMap(Double.init) ?? 0
                let ask = (dataObj["bestAsk"] as? String).flatMap(Double.init) ?? 0
                guard bid > 0 && ask > 0 else { return nil }
                let quote = symbol.hasSuffix("-USDT") ? "USDT" : "USDC"
                await MainActor.run { self.recordExchangeSuccess(.kucoin) }
                return ExchangeQuote(exchange: .kucoin, symbol: base, quote: quote, bid: bid, ask: ask, time: time)
            }
        } catch {
            // ERROR HANDLING FIX: Log errors for debugging (but suppress spam)
            #if DEBUG
            let shouldLog = await MainActor.run { self.shouldLogExchangeFailure(.kucoin) }
            if shouldLog {
                print("[ExchangePriceComparison] KuCoin fetch error: \(error.localizedDescription)")
            }
            #endif
        }
        return nil
    }
    
    /// Try multiple Bybit symbols until one works
    private func fetchBybitWithFallback(symbols: [String], base: String, time: Date) async -> ExchangeQuote? {
        for symbol in symbols {
            if let quote = await fetchBybit(symbol: symbol, base: base, time: time) {
                return quote
            }
        }
        return nil
    }
    
    private func fetchBybit(symbol: String, base: String, time: Date) async -> ExchangeQuote? {
        guard let url = URL(string: "https://api.bybit.com/v5/market/tickers?category=spot&symbol=\(symbol)") else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            // Check for HTTP errors - record failures for circuit breaker
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 403 || httpResponse.statusCode == 451 {
                    // Geo-blocked - record failure for circuit breaker
                    await MainActor.run { self.recordExchangeFailure(.bybit, statusCode: httpResponse.statusCode) }
                    #if DEBUG
                    // LOG SPAM FIX: Only log first failure, circuit breaker will log when triggered
                    let shouldLog = await MainActor.run { self.shouldLogExchangeFailure(.bybit) }
                    if shouldLog {
                        print("[ExchangePrice] Bybit HTTP \(httpResponse.statusCode) - geo-blocked, suppressing further logs until success")
                    }
                    #endif
                    return nil
                }
                if httpResponse.statusCode != 200 {
                    #if DEBUG
                    // LOG SPAM FIX: Only log first failure
                    let shouldLog = await MainActor.run { self.shouldLogExchangeFailure(.bybit) }
                    if shouldLog {
                        print("[ExchangePrice] Bybit HTTP \(httpResponse.statusCode) for \(base)")
                    }
                    #endif
                    return nil
                }
            }
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let result = obj["result"] as? [String: Any],
               let list = result["list"] as? [[String: Any]], let first = list.first {
                let bid = (first["bid1Price"] as? String).flatMap(Double.init) ?? 0
                let ask = (first["ask1Price"] as? String).flatMap(Double.init) ?? 0
                guard bid > 0 && ask > 0 else {
                    #if DEBUG
                    print("[ExchangePrice] Bybit returned zero prices for \(base)")
                    #endif
                    return nil
                }
                let quote = symbol.hasSuffix("USDT") ? "USDT" : "USDC"
                // Success - reset failure count
                await MainActor.run { self.recordExchangeSuccess(.bybit) }
                return ExchangeQuote(exchange: .bybit, symbol: base, quote: quote, bid: bid, ask: ask, time: time)
            } else {
                #if DEBUG
                print("[ExchangePrice] Bybit returned empty list for \(base)")
                #endif
            }
        } catch {
            #if DEBUG
            // LOG SPAM FIX: Only log first failure, skip cancelled errors entirely
            if !(error.localizedDescription.contains("cancelled")) {
                let shouldLog = await MainActor.run { self.shouldLogExchangeFailure(.bybit) }
                if shouldLog {
                    print("[ExchangePrice] Bybit fetch error for \(base): \(error.localizedDescription)")
                }
            }
            #endif
        }
        return nil
    }
    
    /// Try multiple Kraken pairs until one works
    private func fetchKrakenWithFallback(pairs: [String], base: String, time: Date) async -> ExchangeQuote? {
        for pair in pairs {
            if let quote = await fetchKraken(pair: pair, base: base, time: time) {
                return quote
            }
        }
        return nil
    }
    
    private func fetchKraken(pair: String, base: String, time: Date) async -> ExchangeQuote? {
        guard let url = URL(string: "https://api.kraken.com/0/public/Ticker?pair=\(pair)") else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            
            // PERFORMANCE FIX: Check HTTP status and record failures for circuit breaker
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 403 || httpResponse.statusCode == 451 || httpResponse.statusCode == 429 {
                    await MainActor.run { self.recordExchangeFailure(.kraken, statusCode: httpResponse.statusCode) }
                    return nil
                }
            }
            
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let result = obj["result"] as? [String: Any],
               let first = result.values.first as? [String: Any],
               let a = first["a"] as? [Any], let b = first["b"] as? [Any] {
                let askStr = (a.first as? String) ?? String(describing: a.first ?? "0")
                let bidStr = (b.first as? String) ?? String(describing: b.first ?? "0")
                if let bid = Double(bidStr), let ask = Double(askStr), bid > 0, ask > 0 {
                    await MainActor.run { self.recordExchangeSuccess(.kraken) }
                    return ExchangeQuote(exchange: .kraken, symbol: base, quote: "USD", bid: bid, ask: ask, time: time)
                }
            }
        } catch {
            #if DEBUG
            // LOG SPAM FIX: Only log first failure, skip cancelled errors entirely
            if !(error.localizedDescription.contains("cancelled")) {
                let shouldLog = await MainActor.run { self.shouldLogExchangeFailure(.kraken) }
                if shouldLog {
                    print("[ExchangePrice] Kraken fetch error for \(base): \(error.localizedDescription)")
                }
            }
            #endif
        }
        return nil
    }
    
    // MARK: - OKX API Fetchers
    
    /// Try multiple OKX pairs until one works
    private func fetchOKXWithFallback(pairs: [String], base: String, time: Date) async -> ExchangeQuote? {
        for pair in pairs {
            if let quote = await fetchOKX(pair: pair, base: base, time: time) {
                return quote
            }
        }
        #if DEBUG
        print("[ExchangePrice] OKX failed for \(base) - all pairs exhausted")
        #endif
        return nil
    }
    
    private func fetchOKX(pair: String, base: String, time: Date) async -> ExchangeQuote? {
        guard let url = URL(string: "https://www.okx.com/api/v5/market/ticker?instId=\(pair)") else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                // PERFORMANCE FIX: Record failures for circuit breaker
                if httpResponse.statusCode == 403 || httpResponse.statusCode == 451 || httpResponse.statusCode == 429 {
                    await MainActor.run { self.recordExchangeFailure(.okx, statusCode: httpResponse.statusCode) }
                }
                #if DEBUG
                // LOG SPAM FIX: Only log first failure
                let shouldLog = await MainActor.run { self.shouldLogExchangeFailure(.okx) }
                if shouldLog {
                    print("[ExchangePrice] OKX HTTP \(httpResponse.statusCode) - suppressing further logs until success")
                }
                #endif
                return nil
            }
            // Success - reset failure tracking
            await MainActor.run { self.recordExchangeSuccess(.okx) }
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let code = obj["code"] as? String, code == "0",
               let dataArray = obj["data"] as? [[String: Any]], let first = dataArray.first {
                let bid = (first["bidPx"] as? String).flatMap(Double.init) ?? 0
                let ask = (first["askPx"] as? String).flatMap(Double.init) ?? 0
                guard bid > 0 && ask > 0 else { return nil }
                let quote = pair.hasSuffix("-USDT") ? "USDT" : "USDC"
                return ExchangeQuote(exchange: .okx, symbol: base, quote: quote, bid: bid, ask: ask, time: time)
            }
        } catch {
            #if DEBUG
            // LOG SPAM FIX: Only log first failure
            let shouldLog = await MainActor.run { self.shouldLogExchangeFailure(.okx) }
            if shouldLog {
                print("[ExchangePrice] OKX fetch error for \(base): \(error.localizedDescription)")
            }
            #endif
        }
        return nil
    }
    
    // MARK: - Gate.io API Fetchers
    
    /// Try multiple Gate.io pairs until one works
    private func fetchGateIOWithFallback(pairs: [String], base: String, time: Date) async -> ExchangeQuote? {
        for pair in pairs {
            if let quote = await fetchGateIO(pair: pair, base: base, time: time) {
                return quote
            }
        }
        #if DEBUG
        print("[ExchangePrice] Gate.io failed for \(base) - all pairs exhausted")
        #endif
        return nil
    }
    
    private func fetchGateIO(pair: String, base: String, time: Date) async -> ExchangeQuote? {
        guard let url = URL(string: "https://api.gateio.ws/api/v4/spot/tickers?currency_pair=\(pair)") else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 400 || httpResponse.statusCode == 403 || httpResponse.statusCode == 451 {
                    // Bad request or geo-blocked - record failure for circuit breaker
                    await MainActor.run { self.recordExchangeFailure(.gateio, statusCode: httpResponse.statusCode) }
                    #if DEBUG
                    // LOG SPAM FIX: Only log first failure
                    let shouldLog = await MainActor.run { self.shouldLogExchangeFailure(.gateio) }
                    if shouldLog {
                        print("[ExchangePrice] Gate.io HTTP \(httpResponse.statusCode) - suppressing further logs until success")
                    }
                    #endif
                    return nil
                }
                if httpResponse.statusCode != 200 {
                    #if DEBUG
                    // LOG SPAM FIX: Only log first failure
                    let shouldLog = await MainActor.run { self.shouldLogExchangeFailure(.gateio) }
                    if shouldLog {
                        print("[ExchangePrice] Gate.io HTTP \(httpResponse.statusCode) for \(base)")
                    }
                    #endif
                    return nil
                }
            }
            if let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], let first = array.first {
                let bid = (first["highest_bid"] as? String).flatMap(Double.init) ?? 0
                let ask = (first["lowest_ask"] as? String).flatMap(Double.init) ?? 0
                guard bid > 0 && ask > 0 else { return nil }
                let quote = pair.hasSuffix("_USDT") ? "USDT" : "USDC"
                // Success - reset failure count
                await MainActor.run { self.recordExchangeSuccess(.gateio) }
                return ExchangeQuote(exchange: .gateio, symbol: base, quote: quote, bid: bid, ask: ask, time: time)
            }
        } catch {
            #if DEBUG
            // LOG SPAM FIX: Only log first failure, skip cancelled errors entirely
            if !(error.localizedDescription.contains("cancelled")) {
                let shouldLog = await MainActor.run { self.shouldLogExchangeFailure(.gateio) }
                if shouldLog {
                    print("[ExchangePrice] Gate.io fetch error for \(base): \(error.localizedDescription)")
                }
            }
            #endif
        }
        return nil
    }
    
    // MARK: - Gemini API Fetchers
    
    /// Try multiple Gemini pairs until one works
    private func fetchGeminiWithFallback(pairs: [String], base: String, time: Date) async -> ExchangeQuote? {
        for pair in pairs {
            if let quote = await fetchGemini(pair: pair, base: base, time: time) {
                return quote
            }
        }
        #if DEBUG
        print("[ExchangePrice] Gemini failed for \(base) - all pairs exhausted")
        #endif
        return nil
    }
    
    private func fetchGemini(pair: String, base: String, time: Date) async -> ExchangeQuote? {
        // Gemini uses lowercase symbol format: btcusd
        guard let url = URL(string: "https://api.gemini.com/v1/pubticker/\(pair)") else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                // PERFORMANCE FIX: Record failures for circuit breaker
                if httpResponse.statusCode == 403 || httpResponse.statusCode == 451 || 
                   httpResponse.statusCode == 429 || httpResponse.statusCode == 400 {
                    await MainActor.run { self.recordExchangeFailure(.gemini, statusCode: httpResponse.statusCode) }
                }
                #if DEBUG
                // LOG SPAM FIX: Only log first failure
                let shouldLog = await MainActor.run { self.shouldLogExchangeFailure(.gemini) }
                if shouldLog {
                    print("[ExchangePrice] Gemini HTTP \(httpResponse.statusCode) - suppressing further logs until success")
                }
                #endif
                return nil
            }
            // Success - reset failure tracking
            await MainActor.run { self.recordExchangeSuccess(.gemini) }
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let bid = (obj["bid"] as? String).flatMap(Double.init) ?? 0
                let ask = (obj["ask"] as? String).flatMap(Double.init) ?? 0
                guard bid > 0 && ask > 0 else { return nil }
                let quote = pair.hasSuffix("usd") ? "USD" : "USDT"
                return ExchangeQuote(exchange: .gemini, symbol: base, quote: quote, bid: bid, ask: ask, time: time)
            }
        } catch {
            #if DEBUG
            // LOG SPAM FIX: Only log first failure
            let shouldLog = await MainActor.run { self.shouldLogExchangeFailure(.gemini) }
            if shouldLog {
                print("[ExchangePrice] Gemini fetch error for \(base): \(error.localizedDescription)")
            }
            #endif
        }
        return nil
    }
}

// MARK: - PreferenceKey for Exchange Filter Button Frame

private struct ExchangeFilterButtonFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    private static var lastUpdateAt: CFTimeInterval = 0
    
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        guard next != .zero else { return }
        
        // Throttle to ~15Hz to prevent multiple updates per frame
        let now = CACurrentMediaTime()
        guard now - lastUpdateAt >= (1.0 / 15.0) else { return }
        
        // Ignore jitter (changes < 2px)
        let dx = abs(next.origin.x - value.origin.x)
        let dy = abs(next.origin.y - value.origin.y)
        if dx < 2 && dy < 2 && abs(next.width - value.width) < 2 { return }
        
        value = next
        lastUpdateAt = now
    }
}

// MARK: - Section View

struct ExchangePriceSection: View {
    @EnvironmentObject var marketVM: MarketViewModel
    @StateObject private var vm = ExchangePriceComparisonViewModel()
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var hasAppeared = false
    @State private var showExchangePopover = false
    @State private var exchangeButtonFrame: CGRect = .zero
    @State private var pulseAnimation = false
    @State private var showAllExchanges = false
    
    /// Priority coins that should always appear first in the selector
    private static let prioritySymbols = ["BTC", "ETH", "SOL", "XRP"]
    
    private var candidateSymbols: [String] {
        let priority = Self.prioritySymbols
        let fromMarket = marketVM.allCoins.prefix(30)
            .map { $0.symbol.uppercased() }
            .filter { !priority.contains($0) && !$0.isEmpty }
        // Always start with BTC, ETH, SOL, XRP then fill from market data
        let combined = priority + Array(fromMarket.prefix(12))
        // Deduplicate while preserving order
        var seen = Set<String>()
        return combined.filter { seen.insert($0).inserted }
    }
    
    private var availableSymbols: [String] {
        let fetched = Set(vm.comparisons.map { $0.symbol.uppercased() })
        if fetched.isEmpty { return candidateSymbols }
        // Always keep priority coins visible even if no exchange data yet,
        // and add any other coins that have exchange data
        let priority = Self.prioritySymbols
        let fromCandidate = candidateSymbols.filter { fetched.contains($0) || priority.contains($0) }
        let extra = vm.comparisons.map { $0.symbol.uppercased() }
            .filter { sym in !fromCandidate.contains(sym) }
        return fromCandidate + extra
    }
    
    private var selectedComparison: CoinPriceComparison? {
        vm.comparison(for: vm.selectedSymbol)
    }
    
    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 10) {
                // Premium header with live indicator
                sectionHeader
                
                Divider()
                    .background(DS.Adaptive.divider)
                
                // Coin selector row
                coinSelectorRow
                
                // Progress bar - only show for initial load (not background refresh)
                // Background refreshes show just a subtle spinner in the header
                if vm.isLoading && !vm.isBackgroundRefresh {
                    VStack(spacing: 4) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.csGoldSolid.opacity(0.12))
                                    .frame(height: 3)
                                
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.csGoldSolid, Color.orange, Color.csGoldSolid],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(geo.size.width * vm.loadProgress, 20), height: 3)
                                    .animation(.easeInOut(duration: 0.3), value: vm.loadProgress)
                            }
                        }
                        .frame(height: 3)
                        
                        // Progress text
                        HStack {
                            Text("Loading prices...")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(DS.Adaptive.textTertiary)
                            Spacer()
                            Text("\(Int(vm.loadProgress * 100))%")
                                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Color.csGoldSolid)
                        }
                    }
                    .padding(.top, 2)
                }
                
                // Error message if any
                if let error = vm.error {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                        
                        Text(error)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DS.Adaptive.textSecondary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            Task { await vm.refresh(force: true) }
                        } label: {
                            Text("Retry")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(DS.Adaptive.textPrimary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.orange.opacity(0.1))
                    )
                    .padding(.top, 4)
                }
                
                // Main content
                contentView
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
        }
        .padding(.horizontal, 16)
        .overlay {
            if showExchangePopover {
                exchangeFilterPopover
            }
        }
        .onAppear {
            // Start pulse animation for live indicator
            if !pulseAnimation {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    pulseAnimation = true
                }
            }
        }
        .task {
            guard !hasAppeared else { return }
            guard AppState.shared.selectedTab == .home else { return }
            hasAppeared = true
            // Let Home settle before starting large multi-exchange scans.
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard AppState.shared.selectedTab == .home else { return }
            
            // Initial load with retry logic
            await vm.loadOnce(symbols: candidateSymbols)
            
            // If still no data after initial load, try once more after a short delay
            if vm.comparisons.isEmpty {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                await vm.refresh()
            }
            
            // Start auto-refresh (every 30 seconds)
            vm.startAutoRefresh(symbols: candidateSymbols, interval: 30)
        }
        .onDisappear { vm.stop() }
        .onChange(of: vm.comparisons.isEmpty) { _, isEmpty in
            // Auto-retry if data becomes empty
            if isEmpty && vm.hasCompletedFirstLoad {
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                    await vm.refresh()
                }
            }
        }
    }
    
    // MARK: - Header
    
    private var sectionHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            GoldHeaderGlyph(systemName: "building.columns.fill")
            
            Text("Exchange Prices")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.Adaptive.textPrimary)
            
            Spacer()
            
            // Header right side: Status badges and refresh
            HStack(spacing: 6) {
                // Background refresh indicator - subtle "Updating" badge
                if vm.isLoading && vm.isBackgroundRefresh {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 10, height: 10)
                        Text("Updating")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(DS.Adaptive.chipBackground.opacity(0.8))
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
                
                // Status indicator (only when there's something worth showing)
                if !vm.comparisons.isEmpty && !vm.isLoading {
                    if vm.isUsingSampleData {
                        HStack(spacing: 4) {
                            Image(systemName: "play.circle")
                                .font(.system(size: 9, weight: .semibold))
                            Text("Sample")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.orange.opacity(0.15))
                        )
                        .fixedSize()
                    } else {
                        let hasFailures = !vm.failedExchanges.isEmpty
                        let isStale = vm.lastUpdated.map { Date().timeIntervalSince($0) > 300 } ?? false
                        
                        if isStale || hasFailures {
                            // Only show a label when something is wrong
                            Menu {
                                if hasFailures {
                                    Section("Unavailable Exchanges") {
                                        ForEach(Array(vm.failedExchanges).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { exchange in
                                            Label(exchange.rawValue, systemImage: "xmark.circle")
                                        }
                                    }
                                }
                                
                                Button {
                                    Task { await vm.refresh(force: true) }
                                } label: {
                                    Label("Refresh", systemImage: "arrow.clockwise")
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(isStale ? Color.orange : DS.Adaptive.neutralYellow)
                                        .frame(width: 6, height: 6)
                                    
                                    Text(isStale ? timeAgo(vm.lastUpdated ?? Date()) : "\(vm.failedExchanges.count) Offline")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(isStale ? .orange : DS.Adaptive.textTertiary)
                                }
                                .lineLimit(1)
                                .fixedSize()
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(DS.Adaptive.chipBackground)
                                )
                            }
                        } else {
                            // Everything healthy — just the pulsing green dot
                            ZStack {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                                
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                                    .scaleEffect(pulseAnimation ? 2 : 1.0)
                                    .opacity(pulseAnimation ? 0 : 0.5)
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: vm.isLoading)
        }
    }
    
    // MARK: - Coin Selector
    
    /// Get coin image URL from market data
    private func coinImageURL(for symbol: String) -> URL? {
        let upper = symbol.uppercased()
        return marketVM.allCoins.first { $0.symbol.uppercased() == upper }?.imageUrl
    }
    
    private var coinSelectorRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(availableSymbols.prefix(12), id: \.self) { symbol in
                    CoinSelectorChipWithIcon(
                        symbol: symbol,
                        imageURL: coinImageURL(for: symbol),
                        isSelected: vm.selectedSymbol == symbol,
                        exchangeCount: vm.comparison(for: symbol)?.quotes.count
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            vm.selectedSymbol = symbol
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
                
                // Show more button if there are additional coins
                if availableSymbols.count > 12 {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        // Cycle to next set of coins or show all
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "ellipsis")
                                .font(.caption2.weight(.bold))
                            Text("+\(availableSymbols.count - 12)")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(DS.Adaptive.textSecondary)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(DS.Adaptive.chipBackground)
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                // Exchange filter button
                // PROFESSIONAL UX: Shows active state when filter popover is open
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showExchangePopover = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: showExchangePopover ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .font(.caption2.weight(.medium))
                        Text("\(vm.enabledExchanges.count)")
                            .font(.caption2.weight(.semibold))
                    }
                    // PROFESSIONAL UX: Gold styling when active
                    .foregroundStyle(showExchangePopover ? DS.Colors.gold : DS.Adaptive.textPrimary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(showExchangePopover 
                                  ? DS.Colors.gold.opacity(colorScheme == .dark ? 0.15 : 0.12)
                                  : DS.Adaptive.chipBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(showExchangePopover ? DS.Colors.gold : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .animation(.easeOut(duration: 0.15), value: showExchangePopover)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: ExchangeFilterButtonFrameKey.self, value: proxy.frame(in: .global))
                    }
                )
                .onPreferenceChange(ExchangeFilterButtonFrameKey.self) { frame in
                    DispatchQueue.main.async {
                        exchangeButtonFrame = frame
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .overlay(coinSelectorEdgeFade)
    }
    
    /// Edge fade for coin selector scroll
    private var coinSelectorEdgeFade: some View {
        HStack {
            LinearGradient(
                colors: [DS.Adaptive.cardBackground, DS.Adaptive.cardBackground.opacity(0)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 12)
            .allowsHitTesting(false)
            
            Spacer()
            
            LinearGradient(
                colors: [DS.Adaptive.cardBackground.opacity(0), DS.Adaptive.cardBackground],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 12)
            .allowsHitTesting(false)
        }
    }
    
    // MARK: - Exchange Filter Popover
    
    private var exchangeFilterPopover: some View {
        let items: [CSAnchoredMenuItem] = ExchangeQuote.Exchange.allCases.map { ex in
            let isEnabled = vm.enabledExchanges.contains(ex)
            return CSAnchoredMenuItem(
                id: ex.rawValue,
                title: ex.rawValue,
                iconSystemName: isEnabled ? "checkmark.circle.fill" : "circle",
                isEnabled: true,
                isSelected: isEnabled,
                action: {
                    if isEnabled {
                        vm.enabledExchanges.remove(ex)
                    } else {
                        vm.enabledExchanges.insert(ex)
                    }
                    Task { await vm.refresh(force: true) }
                }
            )
        } + [
            CSAnchoredMenuItem(
                id: "enable-all",
                title: "Enable All",
                iconSystemName: "checkmark.circle",
                isEnabled: true,
                isSelected: false,
                action: {
                    vm.enabledExchanges = Set(ExchangeQuote.Exchange.allCases)
                    Task { await vm.refresh(force: true) }
                }
            )
        ]
        
        return CSAnchoredMenu(
            isPresented: $showExchangePopover,
            anchorRect: exchangeButtonFrame,
            items: items,
            preferredWidth: 200,
            maxHeight: 300
        )
        .zIndex(1000)
    }
    
    // MARK: - Content
    
    @ViewBuilder
    private var contentView: some View {
        if let comparison = selectedComparison {
            // Show data
            VStack(alignment: .leading, spacing: 8) {
                // Summary row
                summaryRow(for: comparison)
                
                // Price grid
                priceGrid(for: comparison)
            }
            .transition(.opacity)
        } else if vm.isLoading || !vm.hasCompletedFirstLoad {
            // Show premium shimmer skeleton while loading
            exchangePriceSkeleton
        } else if vm.comparisons.isEmpty {
            // No data at all - show empty state with refresh
            emptyStateView
        } else {
            // Data exists but selected symbol not found - show skeleton briefly then switch
            // FIX: Prefer priority symbols (BTC first) instead of blindly picking comparisons.first
            // which was alphabetically sorted and would pick ADA, BNB, etc. over BTC.
            exchangePriceSkeleton
                .onAppear {
                    // Auto-select best available symbol, preferring BTC > ETH > SOL > XRP
                    let availableSymbols = Set(vm.comparisons.map { $0.symbol.uppercased() })
                    let bestSymbol = Self.prioritySymbols.first { availableSymbols.contains($0) }
                        ?? vm.comparisons.first?.symbol
                    
                    if let symbol = bestSymbol {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                vm.selectedSymbol = symbol
                            }
                        }
                    }
                }
        }
    }
    
    private func summaryRow(for comparison: CoinPriceComparison) -> some View {
        let exchangeCount = comparison.quotes.count
        let totalExchanges = vm.enabledExchanges.count
        let hasPartialData = exchangeCount < totalExchanges
        
        return HStack(spacing: 8) {
            // Best buy
            if let bestBuy = comparison.bestBuyQuote {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                        Text("Best Buy")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DS.Adaptive.textTertiary)
                    }
                    HStack(spacing: 4) {
                        Text(bestBuy.exchange.rawValue)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(bestBuy.exchange.color)
                        Text(formatPrice(bestBuy.ask))
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(DS.Adaptive.textPrimary)
                    }
                }
            } else {
                // No best buy available
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(DS.Adaptive.textTertiary.opacity(0.5))
                        Text("Best Buy")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DS.Adaptive.textTertiary)
                    }
                    Text("N/A")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Adaptive.textTertiary)
                }
            }
            
            Spacer()
            
            // Price variance indicator
            varianceIndicator(for: comparison)
            
            Spacer()
            
            // Best sell
            if let bestSell = comparison.bestSellQuote {
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("Best Sell")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DS.Adaptive.textTertiary)
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.csGoldSolid)
                    }
                    HStack(spacing: 4) {
                        Text(formatPrice(bestSell.bid))
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(DS.Adaptive.textPrimary)
                        Text(bestSell.exchange.rawValue)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(bestSell.exchange.color)
                    }
                }
            } else {
                // No best sell available
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("Best Sell")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DS.Adaptive.textTertiary)
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(DS.Adaptive.textTertiary.opacity(0.5))
                    }
                    Text("N/A")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Adaptive.textTertiary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hasPartialData ? DS.Adaptive.chipBackground.opacity(0.5) : DS.Adaptive.chipBackground.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(hasPartialData ? DS.Adaptive.stroke.opacity(0.3) : DS.Adaptive.stroke.opacity(0.5), lineWidth: 0.5)
                )
        )
        // Partial data indicator overlay - subtle, non-distracting
        .overlay(alignment: .topTrailing) {
            if hasPartialData {
                Text("Partial")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(DS.Adaptive.textTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(DS.Adaptive.chipBackground)
                    )
                    .offset(x: -4, y: -4)
            }
        }
    }
    
    private func varianceIndicator(for comparison: CoinPriceComparison) -> some View {
        let variance = comparison.priceVariance
        let varianceText = String(format: "%.2f%%", variance * 100)
        let varianceColor: Color = variance < 0.001 ? .green : (variance < 0.005 ? DS.Adaptive.neutralYellow : .orange)
        
        return VStack(spacing: 2) {
            Text("Variance")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(DS.Adaptive.textTertiary)
            Text(varianceText)
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(varianceColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(varianceColor.opacity(0.1))
        )
    }
    
    private func priceGrid(for comparison: CoinPriceComparison) -> some View {
        // Get best buy/sell exchanges first
        let bestBuyExchange = comparison.bestBuyQuote?.exchange
        let bestSellExchange = comparison.bestSellQuote?.exchange
        
        // Sort: prioritize best buy/sell at top, then by spread (tightest first)
        let sortedQuotes = comparison.quotes.sorted { q1, q2 in
            let q1IsBest = q1.exchange == bestBuyExchange || q1.exchange == bestSellExchange
            let q2IsBest = q2.exchange == bestBuyExchange || q2.exchange == bestSellExchange
            if q1IsBest != q2IsBest { return q1IsBest }
            return q1.spreadPct < q2.spreadPct
        }
        
        // Show top 3 exchanges by default for cleaner UI
        let maxDisplay = showAllExchanges ? sortedQuotes.count : min(3, sortedQuotes.count)
        let displayQuotes = Array(sortedQuotes.prefix(maxDisplay))
        let hasMore = sortedQuotes.count > 3
        
        return VStack(spacing: 0) {
            // Header row - fixed layout to match data rows
            HStack(spacing: 0) {
                Text("Exchange")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.Adaptive.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text("Bid")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.Adaptive.textTertiary)
                    .frame(minWidth: 80, alignment: .trailing)
                
                Text("Ask")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.Adaptive.textTertiary)
                    .frame(minWidth: 80, alignment: .trailing)
                
                Text("Spread")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.Adaptive.textTertiary)
                    .frame(minWidth: 52, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(DS.Adaptive.chipBackground.opacity(0.3))
            
            // Exchange rows (top 5 by spread, or all if expanded)
            ForEach(Array(displayQuotes.enumerated()), id: \.element.id) { index, quote in
                ExchangePriceRow(
                    quote: quote,
                    isBestBuy: quote.exchange == bestBuyExchange,
                    isBestSell: quote.exchange == bestSellExchange
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
            }
            
            // Show more/less button if there are more than 5 exchanges
            if hasMore {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showAllExchanges.toggle()
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 4) {
                        Text(showAllExchanges ? "Show less" : "Show \(sortedQuotes.count - 3) more")
                            .font(.system(size: 10, weight: .medium))
                        Image(systemName: showAllExchanges ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(DS.Adaptive.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .background(DS.Adaptive.chipBackground.opacity(0.2))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DS.Adaptive.cardBackgroundElevated)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DS.Adaptive.stroke.opacity(0.7), lineWidth: 1)
        )
    }
    
    // MARK: - Premium Shimmer Skeleton
    
    private var exchangePriceSkeleton: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Summary row skeleton
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    skeletonPill(width: 55, height: 10)
                    skeletonPill(width: 80, height: 12)
                }
                
                Spacer()
                
                VStack(spacing: 4) {
                    skeletonPill(width: 45, height: 10)
                    skeletonPill(width: 35, height: 12)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    skeletonPill(width: 50, height: 10)
                    skeletonPill(width: 80, height: 12)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(DS.Adaptive.chipBackground.opacity(0.5))
            )
            
            // Price grid skeleton
            VStack(spacing: 4) {
                // Header row
                HStack(spacing: 0) {
                    skeletonPill(width: 55, height: 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    skeletonPill(width: 45, height: 10)
                        .frame(minWidth: 80, maxWidth: .infinity, alignment: .trailing)
                    skeletonPill(width: 45, height: 10)
                        .frame(minWidth: 80, maxWidth: .infinity, alignment: .trailing)
                    skeletonPill(width: 35, height: 10)
                        .frame(minWidth: 52, maxWidth: 60, alignment: .trailing)
                }
                .padding(.horizontal, 6)
                
                Divider()
                    .background(DS.Adaptive.stroke.opacity(0.3))
                
                // Exchange rows skeleton
                ForEach(0..<3, id: \.self) { index in
                    exchangeRowSkeleton
                        .opacity(1.0 - Double(index) * 0.15)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DS.Adaptive.cardBackgroundElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(DS.Adaptive.stroke.opacity(0.5), lineWidth: 1)
            )
        }
    }
    
    private var exchangeRowSkeleton: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.1))
                    .frame(width: 7, height: 7)
                    .shimmeringEffect()
                skeletonPill(width: 55, height: 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            skeletonPill(width: 65, height: 12)
                .frame(minWidth: 80, maxWidth: .infinity, alignment: .trailing)
            
            skeletonPill(width: 65, height: 12)
                .frame(minWidth: 80, maxWidth: .infinity, alignment: .trailing)
            
            skeletonPill(width: 38, height: 12)
                .frame(minWidth: 52, maxWidth: 60, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }
    
    private func skeletonPill(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 3)
            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
            .frame(width: width, height: height)
            .shimmeringEffect()
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 14) {
            // Animated icon
            ZStack {
                // Outer ring
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color.csGoldSolid.opacity(0.3), Color.orange.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 56, height: 56)
                
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.csGoldSolid.opacity(0.15), Color.orange.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.csGoldSolid, .orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 6) {
                Text("No Exchange Data")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Adaptive.textPrimary)
                
                Text("Unable to fetch prices from exchanges.\nCheck your connection and try again.")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Adaptive.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            
            // Info badges
            HStack(spacing: 8) {
                InfoBadge(icon: "wifi.slash", text: "Network issue?")
                InfoBadge(icon: "globe", text: "Geo-blocked?")
                InfoBadge(icon: "clock", text: "Try later")
            }
            
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task { await vm.refresh(force: true) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Try Again")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(DS.Adaptive.textPrimary)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(DS.Adaptive.chipBackground)
                )
                .overlay(
                    Capsule()
                        .stroke(DS.Adaptive.stroke, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
    
    /// Small info badge for empty state
    private struct InfoBadge: View {
        let icon: String
        let text: String
        
        var body: some View {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .medium))
                Text(text)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(DS.Adaptive.textTertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(DS.Adaptive.chipBackground)
            )
        }
    }
    
    // MARK: - Helpers
    
    private func isLive(_ date: Date) -> Bool {
        Date().timeIntervalSince(date) < 60
    }
    
    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 10 { return "Just now" }
        if seconds < 60 { return "<1m ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        return "\(hours)h ago"
    }
    
    private func formatPrice(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = value < 1 ? 4 : 2
        f.maximumFractionDigits = value < 1 ? 6 : 2
        return "$" + (f.string(from: value as NSNumber) ?? String(format: "%.2f", value))
    }
}

// MARK: - Supporting Views

private struct CoinSelectorChip: View {
    @Environment(\.colorScheme) private var colorScheme
    let symbol: String
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        let isDark = colorScheme == .dark
        Button(action: onTap) {
            Text(symbol)
                .font(.caption2.weight(.bold))
                .foregroundStyle(isSelected ? TintedChipStyle.selectedText(isDark: isDark) : DS.Adaptive.textPrimary)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .tintedRoundedChip(isSelected: isSelected, isDark: isDark, cornerRadius: 7)
        }
        .buttonStyle(.plain)
    }
}

/// Enhanced coin selector chip with icon and exchange count indicator
private struct CoinSelectorChipWithIcon: View {
    @Environment(\.colorScheme) private var colorScheme
    let symbol: String
    let imageURL: URL?
    let isSelected: Bool
    let exchangeCount: Int?
    let onTap: () -> Void
    
    var body: some View {
        let isDark = colorScheme == .dark
        Button(action: onTap) {
            HStack(spacing: 4) {
                // Coin icon
                if let url = imageURL {
                    CachingAsyncImage(url: url, referer: nil)
                        .frame(width: 16, height: 16)
                        .clipShape(Circle())
                } else {
                    // Fallback icon
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [DS.Adaptive.textTertiary.opacity(0.3), DS.Adaptive.textTertiary.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 16, height: 16)
                        .overlay(
                            Text(String(symbol.prefix(1)))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(DS.Adaptive.textSecondary)
                        )
                }
                
                Text(symbol)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(isSelected ? TintedChipStyle.selectedText(isDark: isDark) : DS.Adaptive.textPrimary)
                
                // Subtle partial data indicator - only show when very few exchanges responded
                if let count = exchangeCount, count > 0, count <= 2 {
                    Circle()
                        .fill(DS.Adaptive.neutralYellow)
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .tintedRoundedChip(isSelected: isSelected, isDark: isDark, cornerRadius: 7)
        }
        .buttonStyle(.plain)
    }
}

private struct ExchangePriceRow: View {
    let quote: ExchangeQuote
    let isBestBuy: Bool
    let isBestSell: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 0) {
            // Exchange name with color indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(quote.exchange.color)
                    .frame(width: 7, height: 7)
                Text(quote.exchange.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Adaptive.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Bid (sell) price - fixed size to prevent animation resizing
            HStack(spacing: 3) {
                if isBestSell {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.csGoldSolid)
                }
                Text(formatPrice(quote.bid))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(isBestSell ? Color.csGoldSolid : DS.Adaptive.textPrimary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(minWidth: 80, alignment: .trailing)
            
            // Ask (buy) price - fixed size to prevent animation resizing
            HStack(spacing: 3) {
                if isBestBuy {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.green)
                }
                Text(formatPrice(quote.ask))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(isBestBuy ? .green : DS.Adaptive.textPrimary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(minWidth: 80, alignment: .trailing)
            
            // Spread - fixed size to prevent animation resizing
            Text(formatSpread(quote.spreadPct))
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(spreadColor(quote.spreadPct))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 52, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(rowBackground)
        .contentShape(Rectangle())
    }
    
    private var rowBackground: some View {
        Group {
            if isBestBuy && isBestSell {
                // Gold highlight for best overall
                LinearGradient(
                    colors: [Color.csGoldSolid.opacity(0.12), Color.csGoldSolid.opacity(0.06)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            } else if isBestBuy {
                // Green accent for best buy
                LinearGradient(
                    colors: [Color.green.opacity(0.1), Color.green.opacity(0.04)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            } else if isBestSell {
                // Gold accent for best sell
                LinearGradient(
                    colors: [Color.csGoldSolid.opacity(0.1), Color.csGoldSolid.opacity(0.04)],
                    startPoint: .trailing,
                    endPoint: .leading
                )
            } else {
                Color.clear
            }
        }
    }
    
    private func formatPrice(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = value < 1 ? 4 : 2
        f.maximumFractionDigits = value < 1 ? 6 : 2
        return "$" + (f.string(from: value as NSNumber) ?? String(format: "%.2f", value))
    }
    
    private func formatSpread(_ pct: Double) -> String {
        // Convert to basis points for very tight spreads (1 bps = 0.01%)
        let bps = pct * 10000 // Convert decimal to basis points
        if bps < 10 {
            // Show in basis points for tight spreads
            if bps < 0.1 {
                return "<0.1bp"
            }
            return String(format: "%.1fbp", bps)
        } else {
            // Show as percentage for wider spreads
            return String(format: "%.2f%%", pct * 100)
        }
    }
    
    private func spreadColor(_ pct: Double) -> Color {
        let bps = pct * 10000
        if bps < 5 { return .green }                    // < 5 bps = excellent liquidity
        if bps < 20 { return DS.Adaptive.neutralYellow } // < 20 bps = decent
        return .orange                                   // wider = less liquid
    }
}

