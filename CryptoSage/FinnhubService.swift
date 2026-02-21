//
//  FinnhubService.swift
//  CryptoSage
//
//  Created by CryptoSage on 1/20/26.
//  Finnhub API client for stock market data including quotes, indices, and market status.
//

import Foundation
import os

// MARK: - Finnhub Response Models

/// Finnhub stock quote response
struct FinnhubQuote: Codable, Equatable {
    let c: Double   // Current price
    let d: Double?  // Change
    let dp: Double? // Percent change
    let h: Double   // High price of the day
    let l: Double   // Low price of the day
    let o: Double   // Open price of the day
    let pc: Double  // Previous close price
    let t: Int      // Timestamp
    
    /// Current price
    var currentPrice: Double { c }
    
    /// Daily change amount
    var change: Double { d ?? 0 }
    
    /// Daily change percent
    var changePercent: Double { dp ?? 0 }
    
    /// Day high
    var dayHigh: Double { h }
    
    /// Day low
    var dayLow: Double { l }
    
    /// Open price
    var openPrice: Double { o }
    
    /// Previous close
    var previousClose: Double { pc }
    
    /// Timestamp as Date
    var timestamp: Date { Date(timeIntervalSince1970: TimeInterval(t)) }
}

/// Index constituents response
struct FinnhubIndexConstituents: Codable {
    let constituents: [String]
    let symbol: String
    
    /// Constituent weights (may be nil for some indices)
    let constituentWeights: [String: Double]?
    
    enum CodingKeys: String, CodingKey {
        case constituents
        case symbol
        case constituentWeights = "constituentWeights"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        constituents = try container.decode([String].self, forKey: .constituents)
        symbol = try container.decode(String.self, forKey: .symbol)
        constituentWeights = try container.decodeIfPresent([String: Double].self, forKey: .constituentWeights)
    }
}

/// Market status response
struct FinnhubMarketStatus: Codable {
    let exchange: String
    let holiday: String?
    let isOpen: Bool
    let session: String?
    let timezone: String
    let t: Int  // Timestamp
    
    var timestamp: Date { Date(timeIntervalSince1970: TimeInterval(t)) }
}

/// Stock symbol info from Finnhub
struct FinnhubSymbol: Codable, Identifiable {
    let description: String
    let displaySymbol: String
    let symbol: String
    let type: String
    let mic: String?
    let figi: String?
    let shareClassFIGI: String?
    let currency: String?
    
    var id: String { symbol }
    
    /// Check if this is an ETF
    var isETF: Bool {
        type.uppercased() == "ETF" || type.uppercased() == "ETP"
    }
    
    /// Asset type derived from type field
    var assetType: AssetType {
        isETF ? .etf : .stock
    }
}

/// Stock candle (OHLCV) data
struct FinnhubCandle: Codable {
    let c: [Double]  // Close prices
    let h: [Double]  // High prices
    let l: [Double]  // Low prices
    let o: [Double]  // Open prices
    let t: [Int]     // Timestamps
    let v: [Double]  // Volume
    let s: String    // Status ("ok" or "no_data")
    
    var isValid: Bool { s == "ok" && !c.isEmpty }
    
    /// Convert to chart points
    func toChartPoints() -> [StockChartPoint] {
        guard isValid else { return [] }
        return zip(t, c).map { timestamp, price in
            StockChartPoint(
                date: Date(timeIntervalSince1970: TimeInterval(timestamp)),
                price: price
            )
        }
    }
}

/// Company profile
struct FinnhubCompanyProfile: Codable {
    let country: String?
    let currency: String?
    let exchange: String?
    let finnhubIndustry: String?
    let ipo: String?
    let logo: String?
    let marketCapitalization: Double?
    let name: String?
    let phone: String?
    let shareOutstanding: Double?
    let ticker: String?
    let weburl: String?
}

// MARK: - Stock Index Enum

/// Supported stock market indices
enum StockIndex: String, CaseIterable, Identifiable {
    case sp500 = "^GSPC"
    case nasdaq100 = "^NDX"
    case dowJones = "^DJI"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .sp500: return "S&P 500"
        case .nasdaq100: return "Nasdaq 100"
        case .dowJones: return "Dow Jones"
        }
    }
    
    var shortName: String {
        switch self {
        case .sp500: return "S&P"
        case .nasdaq100: return "NDX"
        case .dowJones: return "DOW"
        }
    }
    
    var stockCount: Int {
        switch self {
        case .sp500: return 500
        case .nasdaq100: return 100
        case .dowJones: return 30
        }
    }
}

// MARK: - Finnhub Service

/// Service for fetching stock market data from Finnhub API
actor FinnhubService {
    static let shared = FinnhubService()
    
    private let logger = Logger(subsystem: "CryptoSage", category: "FinnhubService")
    
    // MARK: - Configuration
    
    private let baseURL = "https://finnhub.io/api/v1"
    private let userAgent = "CryptoSage/1.0 (iOS)"
    
    // Rate limiting: 60 calls/min for free tier
    private let rateLimitPerMinute: Int = 60
    private var requestTimestamps: [Date] = []
    private let requestWindow: TimeInterval = 60  // 1 minute window
    
    // MARK: - URLSession
    
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()
    
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - API Key
    
    /// Get the Finnhub API key
    private var apiKey: String {
        APIConfig.finnhubAPIKey
    }
    
    /// Check if API key is configured
    var isConfigured: Bool {
        APIConfig.hasValidFinnhubKey
    }
    
    // MARK: - Rate Limiting
    
    /// Check if we can make a request without exceeding rate limit
    private func canMakeRequest() -> Bool {
        let now = Date()
        // Remove timestamps older than the window
        requestTimestamps = requestTimestamps.filter { now.timeIntervalSince($0) < requestWindow }
        return requestTimestamps.count < rateLimitPerMinute
    }
    
    /// Record a request timestamp
    private func recordRequest() {
        requestTimestamps.append(Date())
    }
    
    /// Wait until we can make a request
    private func waitForRateLimit() async {
        while !canMakeRequest() {
            // Wait a bit and try again
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        }
    }
    
    // MARK: - API Helpers
    
    /// Build URL with API key
    private func buildURL(endpoint: String, params: [String: String] = [:]) -> URL? {
        var components = URLComponents(string: "\(baseURL)\(endpoint)")
        var queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        queryItems.append(URLQueryItem(name: "token", value: apiKey))
        components?.queryItems = queryItems
        return components?.url
    }
    
    /// Make an API request with rate limiting
    private func request<T: Decodable>(endpoint: String, params: [String: String] = [:]) async throws -> T {
        guard isConfigured else {
            throw FinnhubError.apiKeyNotConfigured
        }
        
        guard let url = buildURL(endpoint: endpoint, params: params) else {
            throw FinnhubError.invalidURL
        }
        
        // Wait for rate limit
        await waitForRateLimit()
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        recordRequest()
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FinnhubError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200...299:
            return try decoder.decode(T.self, from: data)
        case 401:
            throw FinnhubError.unauthorized
        case 429:
            throw FinnhubError.rateLimitExceeded
        case 403:
            throw FinnhubError.forbidden
        default:
            logger.error("Finnhub API error: HTTP \(httpResponse.statusCode)")
            throw FinnhubError.httpError(statusCode: httpResponse.statusCode)
        }
    }
    
    // MARK: - Public API Methods
    
    /// Fetch a single stock quote
    /// - Parameter symbol: Stock ticker symbol (e.g., "AAPL")
    /// - Returns: FinnhubQuote with current price data
    func fetchQuote(symbol: String) async throws -> FinnhubQuote {
        try await request(endpoint: "/quote", params: ["symbol": symbol.uppercased()])
    }
    
    /// Fetch quotes for multiple symbols (batched to respect rate limits)
    /// - Parameters:
    ///   - symbols: Array of stock ticker symbols
    ///   - batchSize: Number of concurrent requests (default 10)
    /// - Returns: Dictionary mapping symbol to quote
    func fetchQuotes(symbols: [String], batchSize: Int = 10) async -> [String: FinnhubQuote] {
        let uniqueSymbols = Array(Set(symbols.map { $0.uppercased() }))
        var results: [String: FinnhubQuote] = [:]
        
        // Process in batches to avoid overwhelming the rate limit
        for batch in uniqueSymbols.chunked(into: batchSize) {
            await withTaskGroup(of: (String, FinnhubQuote?).self) { group in
                for symbol in batch {
                    group.addTask { [symbol] in
                        do {
                            let quote = try await self.fetchQuote(symbol: symbol)
                            return (symbol, quote)
                        } catch {
                            self.logger.warning("Failed to fetch quote for \(symbol): \(error.localizedDescription)")
                            return (symbol, nil)
                        }
                    }
                }
                
                for await (symbol, quote) in group {
                    if let quote = quote {
                        results[symbol] = quote
                    }
                }
            }
            
            // Small delay between batches to stay within rate limits
            if batch != uniqueSymbols.chunked(into: batchSize).last {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second
            }
        }
        
        return results
    }
    
    /// Fetch index constituents (S&P 500, Nasdaq 100, Dow Jones)
    /// - Parameter index: The stock index to fetch
    /// - Returns: Array of ticker symbols in the index
    func fetchIndexConstituents(index: StockIndex) async throws -> [String] {
        let response: FinnhubIndexConstituents = try await request(
            endpoint: "/index/constituents",
            params: ["symbol": index.rawValue]
        )
        return response.constituents
    }
    
    /// Fetch US market status
    /// - Returns: Market status including open/closed state
    func fetchMarketStatus() async throws -> FinnhubMarketStatus {
        try await request(endpoint: "/stock/market-status", params: ["exchange": "US"])
    }
    
    /// Fetch stock candles (OHLCV data)
    /// - Parameters:
    ///   - symbol: Stock ticker symbol
    ///   - resolution: Candle resolution (1, 5, 15, 30, 60, D, W, M)
    ///   - from: Start timestamp
    ///   - to: End timestamp
    /// - Returns: Candle data
    func fetchCandles(
        symbol: String,
        resolution: String = "D",
        from: Date,
        to: Date
    ) async throws -> FinnhubCandle {
        try await request(
            endpoint: "/stock/candle",
            params: [
                "symbol": symbol.uppercased(),
                "resolution": resolution,
                "from": String(Int(from.timeIntervalSince1970)),
                "to": String(Int(to.timeIntervalSince1970))
            ]
        )
    }
    
    /// Fetch company profile
    /// - Parameter symbol: Stock ticker symbol
    /// - Returns: Company profile with name, industry, market cap, etc.
    func fetchCompanyProfile(symbol: String) async throws -> FinnhubCompanyProfile {
        try await request(endpoint: "/stock/profile2", params: ["symbol": symbol.uppercased()])
    }
    
    /// Search for stocks by query
    /// - Parameter query: Search query
    /// - Returns: Array of matching symbols
    func searchStocks(query: String) async throws -> [FinnhubSymbol] {
        struct SearchResponse: Codable {
            let count: Int
            let result: [FinnhubSymbol]
        }
        
        let response: SearchResponse = try await request(
            endpoint: "/search",
            params: ["q": query]
        )
        
        // Filter to US stocks and ETFs only
        return response.result.filter { symbol in
            let type = symbol.type.uppercased()
            return type == "COMMON STOCK" || type == "ETF" || type == "ETP" || type == "ADR"
        }
    }
    
    /// Fetch all US stock symbols
    /// - Returns: Array of all tradeable US stock symbols
    func fetchUSStocks() async throws -> [FinnhubSymbol] {
        try await request(endpoint: "/stock/symbol", params: ["exchange": "US"])
    }
}

// MARK: - Finnhub Errors

enum FinnhubError: LocalizedError {
    case apiKeyNotConfigured
    case invalidURL
    case invalidResponse
    case unauthorized
    case forbidden
    case rateLimitExceeded
    case httpError(statusCode: Int)
    case decodingError(Error)
    
    var errorDescription: String? {
        switch self {
        case .apiKeyNotConfigured:
            return "Finnhub API key is not configured. Please add your API key in Settings."
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .unauthorized:
            return "Invalid API key"
        case .forbidden:
            return "Access forbidden - this endpoint may require a premium subscription"
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please wait a moment and try again."
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}

// MARK: - Array Extension for Chunking

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Convenience Extensions

extension FinnhubQuote {
    /// Convert to a format compatible with StockQuote for unified handling
    func toStockQuote(symbol: String, name: String? = nil) -> StockQuote {
        StockQuote(
            symbol: symbol,
            shortName: name,
            longName: name,
            regularMarketPrice: currentPrice,
            regularMarketChange: change,
            regularMarketChangePercent: changePercent,
            regularMarketPreviousClose: previousClose,
            regularMarketOpen: openPrice,
            regularMarketDayHigh: dayHigh,
            regularMarketDayLow: dayLow,
            regularMarketVolume: nil,
            marketCap: nil,
            fiftyTwoWeekHigh: nil,
            fiftyTwoWeekLow: nil,
            currency: "USD",
            exchange: nil,
            quoteType: nil,
            timestamp: timestamp,
            trailingPE: nil,
            forwardPE: nil,
            epsTrailingTwelveMonths: nil,
            dividendYield: nil,
            beta: nil,
            priceToBook: nil,
            fiftyDayAverage: nil,
            twoHundredDayAverage: nil
        )
    }
}
