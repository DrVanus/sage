//
//  StockPriceService.swift
//  CryptoSage
//
//  Created by CryptoSage on 1/19/26.
//  Stock price service for fetching real-time stock quotes.
//  Uses Yahoo Finance API (unofficial) with fallback support.
//

import Foundation

// MARK: - Stock Quote Model

/// Represents a stock quote with price and market data
struct StockQuote: Codable, Equatable {
    let symbol: String
    let shortName: String?
    let longName: String?
    let regularMarketPrice: Double
    let regularMarketChange: Double?           // Optional to distinguish nil from 0
    let regularMarketChangePercent: Double?    // Optional to distinguish nil from 0
    let regularMarketPreviousClose: Double?
    let regularMarketOpen: Double?
    let regularMarketDayHigh: Double?
    let regularMarketDayLow: Double?
    let regularMarketVolume: Int?
    let marketCap: Double?
    let fiftyTwoWeekHigh: Double?
    let fiftyTwoWeekLow: Double?
    let currency: String?
    let exchange: String?
    let quoteType: String?  // "EQUITY", "ETF", etc.
    let timestamp: Date
    
    // Additional fundamental data
    let trailingPE: Double?
    let forwardPE: Double?
    let epsTrailingTwelveMonths: Double?
    let dividendYield: Double?
    let beta: Double?
    let priceToBook: Double?
    let fiftyDayAverage: Double?
    let twoHundredDayAverage: Double?
    
    /// Display name (company name or symbol)
    var displayName: String {
        longName ?? shortName ?? symbol
    }
    
    /// Asset type derived from quoteType
    var assetType: AssetType {
        switch quoteType?.uppercased() {
        case "ETF": return .etf
        case "FUTURE", "COMMODITY": return .commodity
        default: return .stock
        }
    }
}

// MARK: - Stock Search Result

/// Represents a stock search result for autocomplete
struct StockSearchResult: Codable, Identifiable {
    var id: String { symbol }
    let symbol: String
    let shortName: String?
    let longName: String?
    let exchange: String?
    let quoteType: String?
    let score: Double?
    
    var displayName: String {
        longName ?? shortName ?? symbol
    }
    
    var assetType: AssetType {
        switch quoteType?.uppercased() {
        case "ETF": return .etf
        case "FUTURE", "COMMODITY": return .commodity
        default: return .stock
        }
    }
}

// MARK: - Yahoo Finance Response Models

private struct YahooQuoteResponse: Codable {
    let quoteResponse: QuoteResponseBody?
    
    struct QuoteResponseBody: Codable {
        let result: [YahooQuote]?
        let error: YahooError?
    }
    
    struct YahooError: Codable {
        let code: String?
        let description: String?
    }
}

private struct YahooQuote: Codable {
    let symbol: String
    let shortName: String?
    let longName: String?
    let regularMarketPrice: Double?
    let regularMarketChange: Double?
    let regularMarketChangePercent: Double?
    let regularMarketPreviousClose: Double?
    let regularMarketOpen: Double?
    let regularMarketDayHigh: Double?
    let regularMarketDayLow: Double?
    let regularMarketVolume: Int?
    let marketCap: Double?
    let fiftyTwoWeekHigh: Double?
    let fiftyTwoWeekLow: Double?
    let currency: String?
    let exchange: String?
    let fullExchangeName: String?
    let quoteType: String?
    
    // Fundamental data
    let trailingPE: Double?
    let forwardPE: Double?
    let epsTrailingTwelveMonths: Double?
    let dividendYield: Double?
    let trailingAnnualDividendYield: Double?
    let beta: Double?
    let priceToBook: Double?
    let fiftyDayAverage: Double?
    let twoHundredDayAverage: Double?
}

private struct YahooSearchResponse: Codable {
    let quotes: [YahooSearchQuote]?
}

private struct YahooSearchQuote: Codable {
    let symbol: String
    let shortname: String?
    let longname: String?
    let exchange: String?
    let quoteType: String?
    let score: Double?
}

// MARK: - Yahoo Chart Response Models

private struct YahooChartResponse: Codable {
    let chart: ChartData?
    
    struct ChartData: Codable {
        let result: [ChartResult]?
        let error: ChartError?
    }
    
    struct ChartError: Codable {
        let code: String?
        let description: String?
    }
    
    struct ChartResult: Codable {
        let meta: ChartMeta?
        let timestamp: [Int]?
        let indicators: Indicators?
    }
    
    struct ChartMeta: Codable {
        let currency: String?
        let symbol: String?
        let exchangeName: String?
        let regularMarketPrice: Double?
        let previousClose: Double?
    }
    
    struct Indicators: Codable {
        let quote: [QuoteIndicator]?
    }
    
    struct QuoteIndicator: Codable {
        let open: [Double?]?
        let high: [Double?]?
        let low: [Double?]?
        let close: [Double?]?
        let volume: [Int?]?
    }
}

// MARK: - Safe Array Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Stock Price Service

/// Service for fetching stock prices and quotes
actor StockPriceService {
    static let shared = StockPriceService()
    
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
            "Accept-Language": "en-US,en;q=0.9",
            "Accept-Encoding": "gzip, deflate, br"
        ]
        return URLSession(configuration: config)
    }()
    
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()
    
    // MARK: - Caching
    
    private struct QuoteCacheEntry {
        let quote: StockQuote
        let timestamp: Date
    }
    
    private var quoteCache: [String: QuoteCacheEntry] = [:]
    private let quoteTTL: TimeInterval = 60  // 1 minute cache for quotes
    private let quoteStaleMaxAge: TimeInterval = 300  // 5 minutes stale data
    
    private var inflightQuotes: [String: Task<StockQuote?, Never>] = [:]
    
    // MARK: - API Configuration
    
    /// Yahoo Finance API base URLs (multiple for fallback)
    private let yahooBaseURLs = [
        "https://query1.finance.yahoo.com/v7/finance",
        "https://query2.finance.yahoo.com/v7/finance"
    ]
    
    /// Current base URL index for rotation on failure
    private var currentBaseURLIndex = 0
    
    /// Active base URL
    private var yahooBaseURL: String {
        yahooBaseURLs[currentBaseURLIndex % yahooBaseURLs.count]
    }
    
    /// User agent mimicking a browser for better compatibility
    private let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    
    /// Maximum symbols per batch request
    private let maxBatchSize = 50
    
    /// Rotate to the next base URL
    private func rotateBaseURL() {
        currentBaseURLIndex = (currentBaseURLIndex + 1) % yahooBaseURLs.count
    }
    
    // MARK: - Public Methods
    
    /// Fetch a single stock quote
    /// - Parameter ticker: Stock ticker symbol (e.g., "AAPL", "TSLA")
    /// - Returns: StockQuote if successful, nil otherwise
    func fetchQuote(ticker: String) async -> StockQuote? {
        let symbol = ticker.uppercased()
        
        // Check fresh cache
        if let entry = quoteCache[symbol], Date().timeIntervalSince(entry.timestamp) < quoteTTL {
            return entry.quote
        }
        
        // Inflight de-duplication
        if let existing = inflightQuotes[symbol] {
            return await existing.value
        }
        
        let task = Task<StockQuote?, Never> {
            await fetchQuoteFromAPI(symbol: symbol)
        }
        
        inflightQuotes[symbol] = task
        let result = await task.value
        inflightQuotes[symbol] = nil
        
        if let quote = result {
            quoteCache[symbol] = QuoteCacheEntry(quote: quote, timestamp: Date())
            return quote
        } else if let stale = quoteCache[symbol], Date().timeIntervalSince(stale.timestamp) < quoteStaleMaxAge {
            return stale.quote
        }
        
        return nil
    }
    
    /// Fetch multiple stock quotes with bounded concurrency
    /// - Parameters:
    ///   - tickers: Array of stock ticker symbols
    ///   - maxConcurrency: Maximum concurrent requests
    /// - Returns: Dictionary mapping ticker to StockQuote
    func fetchQuotes(tickers: [String], maxConcurrency: Int = 4) async -> [String: StockQuote] {
        let uniqueTickers = Array(Set(tickers.map { $0.uppercased() })).sorted()
        guard !uniqueTickers.isEmpty else { return [:] }
        
        // Try batch request first (more efficient)
        if let batchResult = await fetchBatchQuotes(symbols: uniqueTickers) {
            return batchResult
        }
        
        // Fallback to individual requests
        var results: [String: StockQuote] = [:]
        let limit = max(1, maxConcurrency)
        var index = 0
        
        await withTaskGroup(of: (String, StockQuote?).self) { group in
            let initial = min(limit, uniqueTickers.count)
            for i in 0..<initial {
                let ticker = uniqueTickers[i]
                group.addTask { [ticker] in
                    let quote = await self.fetchQuote(ticker: ticker)
                    return (ticker, quote)
                }
            }
            index = initial
            
            while let (ticker, quote) = await group.next() {
                if let q = quote { results[ticker] = q }
                if index < uniqueTickers.count {
                    let nextTicker = uniqueTickers[index]
                    index += 1
                    group.addTask { [nextTicker] in
                        let quote = await self.fetchQuote(ticker: nextTicker)
                        return (nextTicker, quote)
                    }
                }
            }
        }
        
        return results
    }
    
    /// Search for stocks by name or symbol
    /// - Parameter query: Search query
    /// - Returns: Array of matching stocks
    func searchStocks(query: String) async -> [StockSearchResult] {
        guard !query.isEmpty else { return [] }
        
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://query1.finance.yahoo.com/v1/finance/search?q=\(encoded)&quotesCount=20&newsCount=0&enableFuzzyQuery=false&quotesQueryId=tss_match_phrase_query"
        
        guard let url = URL(string: urlString) else { return [] }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return []
            }
            
            let searchResponse = try decoder.decode(YahooSearchResponse.self, from: data)
            
            return (searchResponse.quotes ?? [])
                .filter { quote in
                    // Filter to stocks and ETFs only (exclude mutual funds, indices, etc.)
                    let type = quote.quoteType?.uppercased() ?? ""
                    return type == "EQUITY" || type == "ETF"
                }
                .map { quote in
                    StockSearchResult(
                        symbol: quote.symbol,
                        shortName: quote.shortname,
                        longName: quote.longname,
                        exchange: quote.exchange,
                        quoteType: quote.quoteType,
                        score: quote.score
                    )
                }
        } catch {
            #if DEBUG
            print("❌ [StockPriceService] Search error for '\(query)': \(error)")
            #endif
            return []
        }
    }
    
    // MARK: - Historical Data
    
    /// Chart range options for historical data
    enum ChartRange: String {
        case oneDay = "1d"
        case fiveDay = "5d"
        case oneMonth = "1mo"
        case threeMonth = "3mo"
        case sixMonth = "6mo"
        case oneYear = "1y"
        case twoYear = "2y"
        case fiveYear = "5y"
        case tenYear = "10y"
        case max = "max"
        
        var interval: String {
            switch self {
            case .oneDay: return "5m"
            case .fiveDay: return "15m"
            case .oneMonth: return "1d"
            case .threeMonth: return "1d"
            case .sixMonth: return "1d"
            case .oneYear: return "1wk"
            case .twoYear: return "1wk"
            case .fiveYear: return "1mo"
            case .tenYear: return "1mo"
            case .max: return "1mo"
            }
        }
    }
    
    /// Historical price point
    struct HistoricalPoint: Identifiable {
        let id = UUID()
        let date: Date
        let open: Double
        let high: Double
        let low: Double
        let close: Double
        let volume: Int
    }
    
    /// Fetch historical chart data for a stock
    /// - Parameters:
    ///   - ticker: Stock ticker symbol
    ///   - range: Time range for the chart
    /// - Returns: Array of historical price points
    func fetchHistoricalData(ticker: String, range: ChartRange) async -> [HistoricalPoint] {
        await fetchHistoricalData(ticker: ticker, rangeString: range.rawValue, intervalString: range.interval)
    }
    
    /// Fetch historical chart data with custom range and interval strings
    /// - Parameters:
    ///   - ticker: Stock ticker symbol
    ///   - rangeString: Yahoo Finance range (e.g., "1d", "5d", "1mo", "3mo", "1y", "max")
    ///   - intervalString: Yahoo Finance interval (e.g., "1m", "5m", "15m", "30m", "60m", "1d", "1wk", "1mo")
    /// - Returns: Array of historical price points
    func fetchHistoricalData(ticker: String, rangeString: String, intervalString: String) async -> [HistoricalPoint] {
        let symbol = ticker.uppercased()
        
        // Yahoo Finance chart endpoint
        guard var urlComponents = URLComponents(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)") else {
            return []
        }
        
        urlComponents.queryItems = [
            URLQueryItem(name: "range", value: rangeString),
            URLQueryItem(name: "interval", value: intervalString),
            URLQueryItem(name: "includePrePost", value: "false")
        ]
        
        guard let url = urlComponents.url else { return [] }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://finance.yahoo.com", forHTTPHeaderField: "Origin")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                #if DEBUG
                print("❌ [StockPriceService] Chart HTTP error for \(symbol)")
                #endif
                return []
            }
            
            // Parse Yahoo Finance chart response
            let chartResponse = try decoder.decode(YahooChartResponse.self, from: data)
            
            guard let result = chartResponse.chart?.result?.first,
                  let timestamps = result.timestamp,
                  let quote = result.indicators?.quote?.first else {
                return []
            }
            
            var points: [HistoricalPoint] = []
            
            for (index, timestamp) in timestamps.enumerated() {
                guard let close = quote.close?[safe: index],
                      let closeValue = close else { continue }
                
                let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
                let open = quote.open?[safe: index] ?? closeValue
                let high = quote.high?[safe: index] ?? closeValue
                let low = quote.low?[safe: index] ?? closeValue
                let volume = quote.volume?[safe: index] ?? 0
                
                points.append(HistoricalPoint(
                    date: date,
                    open: open ?? closeValue,
                    high: high ?? closeValue,
                    low: low ?? closeValue,
                    close: closeValue,
                    volume: volume ?? 0
                ))
            }
            
            #if DEBUG
            print("✅ [StockPriceService] Fetched \(points.count) chart points for \(symbol) (range: \(rangeString), interval: \(intervalString))")
            #endif
            
            return points
            
        } catch {
            #if DEBUG
            print("❌ [StockPriceService] Chart fetch error for \(symbol): \(error)")
            #endif
            return []
        }
    }
    
    /// Clear all cached quotes
    func clearCache() {
        quoteCache.removeAll()
        inflightQuotes.removeAll()
    }
    
    /// Invalidate cache for a specific ticker
    func invalidate(ticker: String) {
        let symbol = ticker.uppercased()
        quoteCache.removeValue(forKey: symbol)
        inflightQuotes[symbol] = nil
    }
    
    // MARK: - Private Methods
    
    private func fetchQuoteFromAPI(symbol: String) async -> StockQuote? {
        // Try quote API first, then fall back to chart API
        if let quote = await fetchQuoteFromQuoteAPI(symbol: symbol) {
            return quote
        }
        
        // Fallback: Use chart endpoint which is more reliable
        // The chart endpoint provides current price in meta data
        #if DEBUG
        print("📈 [StockPriceService] Using chart fallback for \(symbol)")
        #endif
        return await fetchQuoteFromChartAPI(symbol: symbol)
    }
    
    /// Fetch quote using the /v7/finance/quote endpoint
    private func fetchQuoteFromQuoteAPI(symbol: String) async -> StockQuote? {
        // Build URL with URLComponents for proper encoding
        guard var urlComponents = URLComponents(string: "\(yahooBaseURL)/quote") else { return nil }
        urlComponents.queryItems = [
            URLQueryItem(name: "symbols", value: symbol)
        ]
        
        guard let url = urlComponents.url else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://finance.yahoo.com", forHTTPHeaderField: "Origin")
        request.setValue("https://finance.yahoo.com/", forHTTPHeaderField: "Referer")
        
        var attempt = 0
        let maxRetries = 2  // Reduced retries since we have chart fallback
        
        while attempt < maxRetries {
            attempt += 1
            do {
                let (data, response) = try await session.data(for: request)
                
                guard let http = response as? HTTPURLResponse else { return nil }
                
                if http.statusCode == 429 {
                    // Rate limited - back off
                    let delay = Double(attempt * 2) + Double.random(in: 0.1...0.5)
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                
                // 401/403 = API access restricted, fall through to chart fallback
                if http.statusCode == 401 || http.statusCode == 403 {
                    #if DEBUG
                    print("⚠️ [StockPriceService] Quote API restricted (\(http.statusCode)) for \(symbol), will use chart fallback")
                    #endif
                    return nil
                }
                
                guard (200...299).contains(http.statusCode) else {
                    #if DEBUG
                    print("❌ [StockPriceService] HTTP \(http.statusCode) for \(symbol)")
                    #endif
                    return nil
                }
                
                let quoteResponse = try decoder.decode(YahooQuoteResponse.self, from: data)
                
                guard let quotes = quoteResponse.quoteResponse?.result,
                      let yahooQuote = quotes.first,
                      let price = yahooQuote.regularMarketPrice, price > 0 else {
                    return nil
                }
                
                return StockQuote(
                    symbol: yahooQuote.symbol,
                    shortName: yahooQuote.shortName,
                    longName: yahooQuote.longName,
                    regularMarketPrice: price,
                    regularMarketChange: yahooQuote.regularMarketChange,         // Keep nil if nil
                    regularMarketChangePercent: yahooQuote.regularMarketChangePercent,  // Keep nil if nil
                    regularMarketPreviousClose: yahooQuote.regularMarketPreviousClose,
                    regularMarketOpen: yahooQuote.regularMarketOpen,
                    regularMarketDayHigh: yahooQuote.regularMarketDayHigh,
                    regularMarketDayLow: yahooQuote.regularMarketDayLow,
                    regularMarketVolume: yahooQuote.regularMarketVolume,
                    marketCap: yahooQuote.marketCap,
                    fiftyTwoWeekHigh: yahooQuote.fiftyTwoWeekHigh,
                    fiftyTwoWeekLow: yahooQuote.fiftyTwoWeekLow,
                    currency: yahooQuote.currency,
                    exchange: yahooQuote.fullExchangeName ?? yahooQuote.exchange,
                    quoteType: yahooQuote.quoteType,
                    timestamp: Date(),
                    trailingPE: yahooQuote.trailingPE,
                    forwardPE: yahooQuote.forwardPE,
                    epsTrailingTwelveMonths: yahooQuote.epsTrailingTwelveMonths,
                    dividendYield: yahooQuote.dividendYield ?? yahooQuote.trailingAnnualDividendYield,
                    beta: yahooQuote.beta,
                    priceToBook: yahooQuote.priceToBook,
                    fiftyDayAverage: yahooQuote.fiftyDayAverage,
                    twoHundredDayAverage: yahooQuote.twoHundredDayAverage
                )
                
            } catch {
                #if DEBUG
                print("❌ [StockPriceService] Error fetching \(symbol) attempt \(attempt): \(error)")
                #endif
                
                if attempt < maxRetries {
                    let delay = Double(attempt) + Double.random(in: 0.1...0.3)
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        return nil
    }
    
    /// Fetch quote using the /v8/finance/chart endpoint (more reliable fallback)
    /// This endpoint is less restricted and provides current price in meta data
    private func fetchQuoteFromChartAPI(symbol: String) async -> StockQuote? {
        guard var urlComponents = URLComponents(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)") else {
            return nil
        }
        
        // Request 1d data with 1d interval to get current price + daily change
        urlComponents.queryItems = [
            URLQueryItem(name: "range", value: "1d"),
            URLQueryItem(name: "interval", value: "1d"),
            URLQueryItem(name: "includePrePost", value: "false")
        ]
        
        guard let url = urlComponents.url else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://finance.yahoo.com", forHTTPHeaderField: "Origin")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                #if DEBUG
                print("❌ [StockPriceService] Chart fallback HTTP error for \(symbol)")
                #endif
                return nil
            }
            
            let chartResponse = try decoder.decode(YahooChartResponse.self, from: data)
            
            guard let result = chartResponse.chart?.result?.first,
                  let meta = result.meta,
                  let price = meta.regularMarketPrice, price > 0 else {
                return nil
            }
            
            // FIX: Only calculate change when we have a REAL previousClose from the API.
            // Previously used `meta.previousClose ?? price` which made change=0 and changePercent=0
            // for ALL stocks when previousClose was missing — this was the root cause of the
            // home Stocks & ETFs section always showing +0.00%.
            // Now we pass nil for change fields when previousClose is unavailable, so
            // StockMarketCache.updateStock() can preserve the existing cached percentage.
            let previousClose = meta.previousClose
            let change: Double?
            let changePercent: Double?
            if let prevClose = previousClose, prevClose > 0 {
                change = price - prevClose
                changePercent = (price - prevClose) / prevClose * 100
            } else {
                change = nil
                changePercent = nil
            }
            
            // Extract high/low/open/volume from indicators if available
            var dayHigh: Double?
            var dayLow: Double?
            var dayOpen: Double?
            var volume: Int?
            
            if let quote = result.indicators?.quote?.first {
                dayHigh = quote.high?.compactMap({ $0 }).max()
                dayLow = quote.low?.compactMap({ $0 }).min()
                dayOpen = quote.open?.compactMap({ $0 }).first
                volume = quote.volume?.compactMap({ $0 }).reduce(0, +)
            }
            
            #if DEBUG
            print("✅ [StockPriceService] Chart fallback succeeded for \(symbol): $\(String(format: "%.2f", price)), prevClose=\(previousClose.map { String(format: "%.2f", $0) } ?? "nil")")
            #endif
            
            return StockQuote(
                symbol: meta.symbol ?? symbol,
                shortName: nil,
                longName: nil,
                regularMarketPrice: price,
                regularMarketChange: change,
                regularMarketChangePercent: changePercent,
                regularMarketPreviousClose: previousClose,
                regularMarketOpen: dayOpen,
                regularMarketDayHigh: dayHigh,
                regularMarketDayLow: dayLow,
                regularMarketVolume: volume,
                marketCap: nil,
                fiftyTwoWeekHigh: nil,
                fiftyTwoWeekLow: nil,
                currency: meta.currency,
                exchange: meta.exchangeName,
                quoteType: nil,
                timestamp: Date(),
                trailingPE: nil,
                forwardPE: nil,
                epsTrailingTwelveMonths: nil,
                dividendYield: nil,
                beta: nil,
                priceToBook: nil,
                fiftyDayAverage: nil,
                twoHundredDayAverage: nil
            )
            
        } catch {
            #if DEBUG
            print("❌ [StockPriceService] Chart fallback error for \(symbol): \(error)")
            #endif
            return nil
        }
    }
    
    /// Track if quote API is blocked (401/403)
    private var quoteAPIBlocked = false
    private var quoteAPIBlockedUntil: Date = .distantPast
    private let quoteAPIBlockDuration: TimeInterval = 3600  // 1 hour
    
    private func fetchBatchQuotes(symbols: [String]) async -> [String: StockQuote]? {
        guard !symbols.isEmpty else { return [:] }
        
        // STRATEGY: Try Firebase proxy first (shared cache, no rate limits on client)
        // Fall back to direct Yahoo Finance if Firebase fails
        if let firebaseResults = await fetchBatchViaFirebase(symbols: symbols) {
            #if DEBUG
            print("📈 [StockPriceService] Firebase proxy returned \(firebaseResults.count)/\(symbols.count) stock quotes")
            #endif
            // If Firebase returned most results, use them
            if firebaseResults.count >= symbols.count / 2 {
                // Fetch any missing symbols directly
                let missingSymbols = symbols.filter { firebaseResults[$0] == nil }
                if !missingSymbols.isEmpty {
                    let directResults = await fetchBatchViaDirectYahoo(symbols: missingSymbols)
                    return firebaseResults.merging(directResults ?? [:]) { firebase, _ in firebase }
                }
                return firebaseResults
            }
        }
        
        // Fallback to direct Yahoo Finance
        return await fetchBatchViaDirectYahoo(symbols: symbols)
    }
    
    // Track when getStockQuotes returns 404 (not deployed) to avoid spamming
    private var stockQuotesFirebaseDisabledUntil: Date = .distantPast
    private let stockQuotesFirebaseDisableDuration: TimeInterval = 600 // 10 minutes
    
    /// Fetch stock quotes via Firebase proxy (shared cache across all users)
    private func fetchBatchViaFirebase(symbols: [String]) async -> [String: StockQuote]? {
        // Skip if we recently got a 404 (function not deployed)
        if Date() < stockQuotesFirebaseDisabledUntil {
            return nil
        }
        
        // Check if Firebase is available
        let shouldUseFirebase = await FirebaseService.shared.shouldUseFirebase
        guard shouldUseFirebase else {
            #if DEBUG
            print("📈 [StockPriceService] Firebase not available, skipping proxy")
            #endif
            return nil
        }
        
        do {
            let response = try await FirebaseService.shared.getStockQuotes(symbols: symbols)
            
            var results: [String: StockQuote] = [:]
            for quoteData in response.quotes {
                let quote = StockQuote(
                    symbol: quoteData.symbol,
                    shortName: quoteData.name,
                    longName: quoteData.name,
                    regularMarketPrice: quoteData.price,
                    regularMarketChange: quoteData.change,
                    regularMarketChangePercent: quoteData.changePercent,
                    regularMarketPreviousClose: quoteData.previousClose,
                    regularMarketOpen: quoteData.open,
                    regularMarketDayHigh: quoteData.high,
                    regularMarketDayLow: quoteData.low,
                    regularMarketVolume: quoteData.volume.map { Int($0) },
                    marketCap: quoteData.marketCap,
                    fiftyTwoWeekHigh: nil,
                    fiftyTwoWeekLow: nil,
                    currency: quoteData.currency,
                    exchange: quoteData.exchange,
                    quoteType: quoteData.quoteType,
                    timestamp: Date(),
                    trailingPE: nil,
                    forwardPE: nil,
                    epsTrailingTwelveMonths: nil,
                    dividendYield: nil,
                    beta: nil,
                    priceToBook: nil,
                    fiftyDayAverage: nil,
                    twoHundredDayAverage: nil
                )
                results[quoteData.symbol] = quote
                // Also cache locally
                quoteCache[quoteData.symbol] = QuoteCacheEntry(quote: quote, timestamp: Date())
            }
            
            return results.isEmpty ? nil : results
            
        } catch {
            // If function is not deployed, disable Firebase path for a while to avoid log spam
            if case FirebaseServiceError.functionNotFound = error {
                stockQuotesFirebaseDisabledUntil = Date().addingTimeInterval(stockQuotesFirebaseDisableDuration)
                #if DEBUG
                print("📈 [StockPriceService] getStockQuotes not deployed - disabling Firebase proxy for \(Int(stockQuotesFirebaseDisableDuration/60))min")
                #endif
            } else {
                #if DEBUG
                print("📈 [StockPriceService] Firebase proxy failed: \(error.localizedDescription)")
                #endif
            }
            return nil
        }
    }
    
    /// Fetch stock quotes directly from Yahoo Finance (fallback when Firebase unavailable)
    private func fetchBatchViaDirectYahoo(symbols: [String]) async -> [String: StockQuote]? {
        guard !symbols.isEmpty else { return [:] }
        
        // If quote API is blocked, use chart fallback for all symbols
        if quoteAPIBlocked && Date() < quoteAPIBlockedUntil {
            #if DEBUG
            print("📈 [StockPriceService] Quote API blocked, using chart fallback for \(symbols.count) symbols")
            #endif
            return await fetchBatchViaChart(symbols: symbols)
        }
        
        // Split into smaller batches if needed
        if symbols.count > maxBatchSize {
            var allResults: [String: StockQuote] = [:]
            let batches = symbols.chunked(into: maxBatchSize)
            
            for batch in batches {
                if let batchResults = await fetchSingleBatchWithRetry(symbols: batch) {
                    allResults.merge(batchResults) { _, new in new }
                } else if quoteAPIBlocked {
                    // If API got blocked during batch processing, fetch remaining via chart
                    if let chartResults = await fetchBatchViaChart(symbols: batch) {
                        allResults.merge(chartResults) { _, new in new }
                    }
                }
                // Small delay between batches to avoid rate limiting
                try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
            }
            
            return allResults.isEmpty ? nil : allResults
        }
        
        // Try batch API first
        if let result = await fetchSingleBatchWithRetry(symbols: symbols) {
            return result
        }
        
        // Fall back to chart API if batch failed (likely due to 401)
        return await fetchBatchViaChart(symbols: symbols)
    }
    
    /// Fetch multiple quotes via chart API (fallback when quote API is blocked)
    private func fetchBatchViaChart(symbols: [String]) async -> [String: StockQuote]? {
        var results: [String: StockQuote] = [:]
        
        // Process in parallel with bounded concurrency
        await withTaskGroup(of: (String, StockQuote?).self) { group in
            let maxConcurrent = 6  // Limit concurrent chart requests
            var pending = 0
            var index = 0
            
            while index < symbols.count || pending > 0 {
                // Add tasks up to concurrency limit
                while pending < maxConcurrent && index < symbols.count {
                    let symbol = symbols[index]
                    index += 1
                    pending += 1
                    group.addTask {
                        let quote = await self.fetchQuoteFromChartAPI(symbol: symbol)
                        return (symbol, quote)
                    }
                }
                
                // Collect one result
                if let (symbol, quote) = await group.next() {
                    pending -= 1
                    if let q = quote {
                        results[symbol] = q
                    }
                }
            }
        }
        
        #if DEBUG
        print("📈 [StockPriceService] Chart fallback fetched \(results.count)/\(symbols.count) quotes")
        #endif
        
        return results.isEmpty ? nil : results
    }
    
    /// Fetch a batch with retry using different endpoints
    private func fetchSingleBatchWithRetry(symbols: [String]) async -> [String: StockQuote]? {
        // Skip if API is known to be blocked
        if quoteAPIBlocked && Date() < quoteAPIBlockedUntil {
            return nil
        }
        
        // Try each base URL
        for attempt in 0..<yahooBaseURLs.count {
            let (result, wasBlocked) = await fetchSingleBatchWithBlockDetection(symbols: symbols)
            
            if wasBlocked {
                // API is blocked (401/403), don't retry
                quoteAPIBlocked = true
                quoteAPIBlockedUntil = Date().addingTimeInterval(quoteAPIBlockDuration)
                #if DEBUG
                print("🔴 [StockPriceService] Quote API blocked for \(Int(quoteAPIBlockDuration/60)) minutes")
                #endif
                return nil
            }
            
            if let result = result {
                // Success - clear blocked flag if it was set
                if quoteAPIBlocked {
                    quoteAPIBlocked = false
                    #if DEBUG
                    print("✅ [StockPriceService] Quote API unblocked")
                    #endif
                }
                return result
            }
            
            // Rotate to next URL for retry
            rotateBaseURL()
            
            #if DEBUG
            print("⚠️ [StockPriceService] Retrying with alternate endpoint (attempt \(attempt + 1))")
            #endif
            
            // Brief delay before retry
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
        }
        
        return nil
    }
    
    /// Fetch batch and detect if API is blocked
    private func fetchSingleBatchWithBlockDetection(symbols: [String]) async -> (result: [String: StockQuote]?, wasBlocked: Bool) {
        guard let result = await fetchSingleBatch(symbols: symbols, detectBlock: true) else {
            // Check if it was a block error
            return (nil, quoteAPIBlocked)
        }
        return (result, false)
    }
    
    private func fetchSingleBatch(symbols: [String], detectBlock: Bool = false) async -> [String: StockQuote]? {
        guard !symbols.isEmpty else { return [:] }
        
        // Simple URL construction - just symbols parameter
        let symbolsParam = symbols.joined(separator: ",")
        let urlString = "\(yahooBaseURL)/quote?symbols=\(symbolsParam)"
        
        guard let url = URL(string: urlString) else {
            #if DEBUG
            print("❌ [StockPriceService] Failed to build URL for symbols: \(symbols.prefix(5))...")
            #endif
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        
        #if DEBUG
        print("📊 [StockPriceService] Fetching \(symbols.count) quotes from: \(urlString.prefix(80))...")
        #endif
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let http = response as? HTTPURLResponse else {
                #if DEBUG
                print("❌ [StockPriceService] Invalid response type")
                #endif
                return nil
            }
            
            #if DEBUG
            print("📊 [StockPriceService] Response status: \(http.statusCode)")
            if http.statusCode != 200 {
                if let bodyStr = String(data: data, encoding: .utf8) {
                    print("📊 [StockPriceService] Response body: \(bodyStr.prefix(300))")
                }
            }
            #endif
            
            // Detect API blocking (401/403)
            if detectBlock && (http.statusCode == 401 || http.statusCode == 403) {
                #if DEBUG
                print("🔴 [StockPriceService] Quote API blocked (\(http.statusCode))")
                #endif
                quoteAPIBlocked = true
                return nil
            }
            
            guard (200...299).contains(http.statusCode) else {
                return nil
            }
            
            let quoteResponse = try decoder.decode(YahooQuoteResponse.self, from: data)
            
            if let error = quoteResponse.quoteResponse?.error {
                #if DEBUG
                print("❌ [StockPriceService] API Error: \(error.description ?? "unknown")")
                #endif
                return nil
            }
            
            guard let quotes = quoteResponse.quoteResponse?.result, !quotes.isEmpty else {
                #if DEBUG
                print("⚠️ [StockPriceService] No quotes in response")
                if let bodyStr = String(data: data, encoding: .utf8) {
                    print("📊 [StockPriceService] Raw response: \(bodyStr.prefix(500))")
                }
                #endif
                return nil
            }
            
            #if DEBUG
            print("✅ [StockPriceService] Got \(quotes.count) quotes from Yahoo Finance")
            #endif
            
            var results: [String: StockQuote] = [:]
            let now = Date()
            
            for yahooQuote in quotes {
                guard let price = yahooQuote.regularMarketPrice, price > 0 else { continue }
                
                let quote = StockQuote(
                    symbol: yahooQuote.symbol,
                    shortName: yahooQuote.shortName,
                    longName: yahooQuote.longName,
                    regularMarketPrice: price,
                    regularMarketChange: yahooQuote.regularMarketChange,         // Keep nil if nil
                    regularMarketChangePercent: yahooQuote.regularMarketChangePercent,  // Keep nil if nil
                    regularMarketPreviousClose: yahooQuote.regularMarketPreviousClose,
                    regularMarketOpen: yahooQuote.regularMarketOpen,
                    regularMarketDayHigh: yahooQuote.regularMarketDayHigh,
                    regularMarketDayLow: yahooQuote.regularMarketDayLow,
                    regularMarketVolume: yahooQuote.regularMarketVolume,
                    marketCap: yahooQuote.marketCap,
                    fiftyTwoWeekHigh: yahooQuote.fiftyTwoWeekHigh,
                    fiftyTwoWeekLow: yahooQuote.fiftyTwoWeekLow,
                    currency: yahooQuote.currency,
                    exchange: yahooQuote.fullExchangeName ?? yahooQuote.exchange,
                    quoteType: yahooQuote.quoteType,
                    timestamp: now,
                    trailingPE: yahooQuote.trailingPE,
                    forwardPE: yahooQuote.forwardPE,
                    epsTrailingTwelveMonths: yahooQuote.epsTrailingTwelveMonths,
                    dividendYield: yahooQuote.dividendYield ?? yahooQuote.trailingAnnualDividendYield,
                    beta: yahooQuote.beta,
                    priceToBook: yahooQuote.priceToBook,
                    fiftyDayAverage: yahooQuote.fiftyDayAverage,
                    twoHundredDayAverage: yahooQuote.twoHundredDayAverage
                )
                
                results[yahooQuote.symbol.uppercased()] = quote
                quoteCache[yahooQuote.symbol.uppercased()] = QuoteCacheEntry(quote: quote, timestamp: now)
            }
            
            #if DEBUG
            print("✅ [StockPriceService] Fetched \(results.count) quotes successfully")
            #endif
            
            return results
            
        } catch {
            #if DEBUG
            print("❌ [StockPriceService] Batch fetch error: \(error)")
            #endif
            return nil
        }
    }
}

// MARK: - Array Extension for Chunking

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - StockQuote Extensions

extension StockQuote {
    /// Convert to a Holding for portfolio tracking
    func toHolding(shares: Double, costBasis: Double, purchaseDate: Date = Date(), source: String? = nil) -> Holding {
        // Calculate change percent from previousClose if not available from API
        let effectiveChangePercent: Double = {
            if let change = regularMarketChangePercent {
                return change
            }
            if let prevClose = regularMarketPreviousClose, prevClose > 0 {
                return ((regularMarketPrice - prevClose) / prevClose) * 100
            }
            return 0
        }()
        
        return Holding(
            ticker: symbol,
            companyName: displayName,
            shares: shares,
            currentPrice: regularMarketPrice,
            costBasis: costBasis,
            assetType: assetType,
            stockExchange: exchange,
            isin: nil,
            imageUrl: nil,
            isFavorite: false,
            dailyChange: effectiveChangePercent,
            purchaseDate: purchaseDate,
            source: source
        )
    }
}
