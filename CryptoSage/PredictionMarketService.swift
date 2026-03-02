   //
//  PredictionMarketService.swift
//  CryptoSage
//
//  Service for fetching prediction market data from Polymarket and Kalshi.
//  Provides trending markets, odds, and market analysis for AI-assisted trading.
//

import Foundation
import Combine

// MARK: - Prediction Market Models

/// Represents a prediction market from any platform
struct PredictionMarket: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let description: String?
    let platform: PredictionPlatform
    let category: PredictionCategory
    let outcomes: [MarketOutcome]
    let volume: Double?
    let liquidity: Double?
    let endDate: Date?
    let createdAt: Date?
    let imageUrl: String?
    let marketUrl: String?
    let isResolved: Bool
    let resolution: String?
    
    /// The implied probability of the YES outcome (for binary markets)
    var yesPrice: Double? {
        outcomes.first(where: { $0.name.lowercased() == "yes" })?.price
    }
    
    /// The implied probability of the NO outcome (for binary markets)
    var noPrice: Double? {
        outcomes.first(where: { $0.name.lowercased() == "no" })?.price
    }
    
    /// Volume formatted for display
    var formattedVolume: String {
        guard let vol = volume else { return "—" }
        if vol >= 1_000_000 {
            return String(format: "$%.1fM", vol / 1_000_000)
        } else if vol >= 1_000 {
            return String(format: "$%.1fK", vol / 1_000)
        }
        return String(format: "$%.0f", vol)
    }
    
    /// Time remaining until market closes
    var timeRemaining: String? {
        guard let endDate = endDate else { return nil }
        let now = Date()
        if endDate < now { return "Ended" }
        
        let interval = endDate.timeIntervalSince(now)
        let days = Int(interval / 86400)
        let hours = Int((interval.truncatingRemainder(dividingBy: 86400)) / 3600)
        
        if days > 30 {
            let months = days / 30
            return "\(months) month\(months == 1 ? "" : "s")"
        } else if days > 0 {
            return "\(days) day\(days == 1 ? "" : "s")"
        } else if hours > 0 {
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        } else {
            let minutes = Int(interval / 60)
            return "\(minutes) min"
        }
    }
}

/// Individual outcome within a prediction market
struct MarketOutcome: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let price: Double // 0.0 to 1.0 representing probability/price
    let volume: Double?
    
    /// Price as percentage string
    var pricePercentage: String {
        String(format: "%.0f%%", price * 100)
    }
    
    /// Potential return if this outcome wins
    var potentialReturn: String {
        guard price > 0 && price < 1 else { return "—" }
        let multiplier = 1.0 / price
        return String(format: "%.1fx", multiplier)
    }
}

/// Supported prediction market platforms
enum PredictionPlatform: String, Codable, CaseIterable {
    case polymarket = "Polymarket"
    case kalshi = "Kalshi"
    
    var displayName: String { rawValue }
    
    var icon: String {
        switch self {
        case .polymarket: return "chart.bar.xaxis"
        case .kalshi: return "chart.line.uptrend.xyaxis"
        }
    }
    
    var color: String {
        switch self {
        case .polymarket: return "purple"
        case .kalshi: return "blue"
        }
    }
    
    var baseUrl: String {
        switch self {
        case .polymarket: return "https://polymarket.com"
        case .kalshi: return "https://kalshi.com"
        }
    }
}

/// Categories for prediction markets
enum PredictionCategory: String, Codable, CaseIterable {
    case crypto = "Crypto"
    case politics = "Politics"
    case sports = "Sports"
    case economics = "Economics"
    case entertainment = "Entertainment"
    case science = "Science"
    case weather = "Weather"
    case other = "Other"
    
    var icon: String {
        switch self {
        case .crypto: return "bitcoinsign.circle"
        case .politics: return "building.columns"
        case .sports: return "sportscourt"
        case .economics: return "chart.line.uptrend.xyaxis"
        case .entertainment: return "film"
        case .science: return "atom"
        case .weather: return "cloud.sun"
        case .other: return "questionmark.circle"
        }
    }
}

/// AI analysis of a prediction market
struct MarketAnalysis: Identifiable, Codable {
    let id: String
    let marketId: String
    let estimatedProbability: Double // AI's estimate of true probability
    let marketPrice: Double // Current market price
    let edge: Double // Difference between AI estimate and market price
    let confidence: AnalysisConfidence
    let reasoning: String
    let factors: [AnalysisFactor]
    let timestamp: Date
    
    /// Whether this represents a potential opportunity
    var isOpportunity: Bool {
        abs(edge) >= 0.05 && confidence != .low
    }
    
    /// Direction of the edge (buy YES or buy NO)
    var recommendation: String {
        if edge > 0.05 {
            return "YES is underpriced"
        } else if edge < -0.05 {
            return "NO is underpriced"
        }
        return "Fairly priced"
    }
}

enum AnalysisConfidence: String, Codable, CaseIterable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"
    
    var color: String {
        switch self {
        case .high: return "green"
        case .medium: return "orange"
        case .low: return "gray"
        }
    }
}

struct AnalysisFactor: Identifiable, Codable {
    let id: String
    let factor: String
    let impact: String // "bullish", "bearish", "neutral"
    let weight: Double // 0.0 to 1.0
}

// MARK: - Polymarket API Models

/// Polymarket market response
private struct PolymarketMarket: Codable {
    let id: String
    let question: String
    let description: String?
    let slug: String?
    let outcomePrices: String? // JSON string of prices
    let volume: String?
    let volume24hr: String?
    let liquidity: String?
    let endDateIso: String?
    let createdAt: String?
    let image: String?
    let closed: Bool?
    let resolved: Bool?
    let resolution: String?
    let category: String?
    
    enum CodingKeys: String, CodingKey {
        case id, question, description, slug
        case outcomePrices = "outcomePrices"
        case volume, volume24hr, liquidity
        case endDateIso = "endDateIso"
        case createdAt, image, closed, resolved, resolution, category
    }
}

/// Polymarket event response (contains multiple markets)
private struct PolymarketEvent: Codable {
    let id: String
    let title: String
    let slug: String?
    let description: String?
    let markets: [PolymarketMarket]?
    let category: String?
    let image: String?
    let volume: String?
    let volume24hr: String?
    let liquidity: String?
    let endDate: String?
    let startDate: String?
    let closed: Bool?
}

/// Polymarket API response wrapper
private struct PolymarketResponse: Codable {
    let data: [PolymarketEvent]?
    let events: [PolymarketEvent]?
    let markets: [PolymarketMarket]?
    let count: Int?
    let limit: Int?
    let offset: Int?
}

// MARK: - Kalshi API Models (Simplified - actual API requires auth)

/// Kalshi market response
private struct KalshiMarket: Codable {
    let ticker: String
    let eventTicker: String?
    let title: String
    let subtitle: String?
    let status: String?
    let yesPrice: Double?
    let noPrice: Double?
    let lastPrice: Double?
    let volume: Double?
    let volume24h: Double?
    let openInterest: Double?
    let closeTime: String?
    let category: String?
    
    enum CodingKeys: String, CodingKey {
        case ticker
        case eventTicker = "event_ticker"
        case title, subtitle, status
        case yesPrice = "yes_price"
        case noPrice = "no_price"
        case lastPrice = "last_price"
        case volume
        case volume24h = "volume_24h"
        case openInterest = "open_interest"
        case closeTime = "close_time"
        case category
    }
}

private struct KalshiResponse: Codable {
    let markets: [KalshiMarket]?
    let cursor: String?
}

// MARK: - Prediction Market Service

/// Service for fetching and managing prediction market data
@MainActor
final class PredictionMarketService: ObservableObject {
    static let shared = PredictionMarketService()
    
    // MARK: - Published Properties
    @Published var trendingMarkets: [PredictionMarket] = []
    @Published var cryptoMarkets: [PredictionMarket] = []
    @Published var isLoading: Bool = false
    @Published var lastError: String? = nil
    @Published var lastUpdated: Date? = nil
    
    // MARK: - Private Properties
    private let polymarketBaseUrl = "https://gamma-api.polymarket.com"
    private let kalshiBaseUrl = "https://api.elections.kalshi.com/trade-api/v2" // Public endpoint
    
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()
    
    // Cache
    private var marketCache: [String: PredictionMarket] = [:]
    private var cacheTimestamp: Date? = nil
    private let cacheMaxAge: TimeInterval = 300 // 5 minutes
    
    private init() {}
    
    // MARK: - Public API
    
    /// Fetch trending markets from all platforms
    func fetchTrendingMarkets() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        
        // Check cache
        if let cacheTime = cacheTimestamp,
           Date().timeIntervalSince(cacheTime) < cacheMaxAge,
           !trendingMarkets.isEmpty {
            return
        }
        
        var allMarkets: [PredictionMarket] = []
        
        // Fetch from Polymarket
        do {
            let polyMarkets = try await fetchPolymarketTrending()
            allMarkets.append(contentsOf: polyMarkets)
        } catch {
            print("[PredictionMarketService] Polymarket error: \(error)")
        }
        
        // Fetch from Kalshi (limited without auth)
        do {
            let kalshiMarkets = try await fetchKalshiMarkets()
            allMarkets.append(contentsOf: kalshiMarkets)
        } catch {
            print("[PredictionMarketService] Kalshi error: \(error)")
        }
        
        // Sort by volume
        allMarkets.sort { ($0.volume ?? 0) > ($1.volume ?? 0) }
        
        // Update cache
        trendingMarkets = allMarkets
        cryptoMarkets = allMarkets.filter { $0.category == .crypto }
        cacheTimestamp = Date()
        lastUpdated = Date()
        
        // Populate cache map
        for market in allMarkets {
            marketCache[market.id] = market
        }
    }
    
    /// Fetch markets filtered by category
    func fetchMarkets(category: PredictionCategory) async -> [PredictionMarket] {
        await fetchTrendingMarkets()
        return trendingMarkets.filter { $0.category == category }
    }
    
    /// Fetch crypto-specific markets
    func fetchCryptoMarkets() async -> [PredictionMarket] {
        await fetchTrendingMarkets()
        return cryptoMarkets
    }
    
    /// Get a market by ID
    func getMarket(id: String) -> PredictionMarket? {
        return marketCache[id]
    }
    
    /// Search markets by query
    func searchMarkets(query: String) async -> [PredictionMarket] {
        await fetchTrendingMarkets()
        let lowercased = query.lowercased()
        return trendingMarkets.filter {
            $0.title.lowercased().contains(lowercased) ||
            ($0.description?.lowercased().contains(lowercased) ?? false)
        }
    }
    
    /// Get summary text for AI context
    func getMarketSummaryForAI() -> String {
        guard !trendingMarkets.isEmpty else {
            return "No prediction market data available."
        }
        
        var summary = "PREDICTION MARKET DATA:\n"
        
        // Top markets by volume
        let topMarkets = Array(trendingMarkets.prefix(10))
        summary += "\nTop 10 Trending Markets:\n"
        for (index, market) in topMarkets.enumerated() {
            let yesPrice = market.yesPrice.map { String(format: "%.0f%%", $0 * 100) } ?? "—"
            summary += "\(index + 1). \(market.title) [\(market.platform.displayName)]\n"
            summary += "   YES: \(yesPrice) | Volume: \(market.formattedVolume)\n"
        }
        
        // Crypto-specific markets
        if !cryptoMarkets.isEmpty {
            summary += "\nCrypto Prediction Markets:\n"
            for market in cryptoMarkets.prefix(5) {
                let yesPrice = market.yesPrice.map { String(format: "%.0f%%", $0 * 100) } ?? "—"
                summary += "- \(market.title): YES \(yesPrice)\n"
            }
        }
        
        return summary
    }
    
    // MARK: - Polymarket API
    
    private func fetchPolymarketTrending() async throws -> [PredictionMarket] {
        // Polymarket Gamma API for trending events
        guard let url = URL(string: "\(polymarketBaseUrl)/events?active=true&closed=false&limit=50&order=volume24hr") else {
            throw PredictionMarketError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CryptoSage/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PredictionMarketError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            // Try fallback to sample data if API fails
            if httpResponse.statusCode == 429 || httpResponse.statusCode >= 500 {
                return getSamplePolymarketData()
            }
            throw PredictionMarketError.httpError(httpResponse.statusCode)
        }
        
        // Try to decode as events array or wrapped response
        let decoder = JSONDecoder()
        
        // Try direct array of events
        if let events = try? decoder.decode([PolymarketEvent].self, from: data) {
            return events.compactMap { convertPolymarketEvent($0) }
        }
        
        // Try wrapped response
        if let response = try? decoder.decode(PolymarketResponse.self, from: data) {
            if let events = response.events ?? response.data {
                return events.compactMap { convertPolymarketEvent($0) }
            }
            if let markets = response.markets {
                return markets.compactMap { convertPolymarketMarket($0) }
            }
        }
        
        // Return sample data as fallback
        return getSamplePolymarketData()
    }
    
    private func convertPolymarketEvent(_ event: PolymarketEvent) -> PredictionMarket? {
        // Get the primary market from the event
        guard let primaryMarket = event.markets?.first else {
            return nil
        }
        
        return convertPolymarketMarket(primaryMarket, eventTitle: event.title, eventImage: event.image)
    }
    
    private func convertPolymarketMarket(_ market: PolymarketMarket, eventTitle: String? = nil, eventImage: String? = nil) -> PredictionMarket? {
        // Parse outcome prices
        var outcomes: [MarketOutcome] = []
        if let pricesJson = market.outcomePrices,
           let pricesData = pricesJson.data(using: .utf8),
           let prices = try? JSONSerialization.jsonObject(with: pricesData) as? [String] {
            // Polymarket returns prices as strings like ["0.55", "0.45"]
            if prices.count >= 2 {
                outcomes = [
                    MarketOutcome(id: "\(market.id)-yes", name: "Yes", price: Double(prices[0]) ?? 0.5, volume: nil),
                    MarketOutcome(id: "\(market.id)-no", name: "No", price: Double(prices[1]) ?? 0.5, volume: nil)
                ]
            }
        }
        
        // If no prices parsed, use default
        if outcomes.isEmpty {
            outcomes = [
                MarketOutcome(id: "\(market.id)-yes", name: "Yes", price: 0.5, volume: nil),
                MarketOutcome(id: "\(market.id)-no", name: "No", price: 0.5, volume: nil)
            ]
        }
        
        // Parse dates
        let endDate: Date? = market.endDateIso.flatMap { ISO8601DateFormatter().date(from: $0) }
        let createdAt: Date? = market.createdAt.flatMap { ISO8601DateFormatter().date(from: $0) }
        
        // Parse volume
        let volume = market.volume.flatMap { Double($0) } ?? market.volume24hr.flatMap { Double($0) }
        let liquidity = market.liquidity.flatMap { Double($0) }
        
        // Determine category
        let category = mapCategory(market.category)
        
        return PredictionMarket(
            id: "polymarket-\(market.id)",
            title: eventTitle ?? market.question,
            description: market.description,
            platform: .polymarket,
            category: category,
            outcomes: outcomes,
            volume: volume,
            liquidity: liquidity,
            endDate: endDate,
            createdAt: createdAt,
            imageUrl: eventImage ?? market.image,
            marketUrl: market.slug.map { "https://polymarket.com/event/\($0)" },
            isResolved: market.resolved ?? false,
            resolution: market.resolution
        )
    }
    
    // MARK: - Kalshi API
    
    private func fetchKalshiMarkets() async throws -> [PredictionMarket] {
        // Kalshi public API for market data
        // Note: Full API requires authentication, this uses limited public endpoints
        guard let url = URL(string: "\(kalshiBaseUrl)/markets?status=active&limit=30") else {
            throw PredictionMarketError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CryptoSage/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return getSampleKalshiData()
            }
            
            guard httpResponse.statusCode == 200 else {
                return getSampleKalshiData()
            }
            
            let decoder = JSONDecoder()
            if let response = try? decoder.decode(KalshiResponse.self, from: data),
               let markets = response.markets {
                return markets.compactMap { convertKalshiMarket($0) }
            }
            
            return getSampleKalshiData()
        } catch {
            // Return sample data on network error
            return getSampleKalshiData()
        }
    }
    
    private func convertKalshiMarket(_ market: KalshiMarket) -> PredictionMarket? {
        let yesPrice = market.yesPrice ?? market.lastPrice ?? 0.5
        let noPrice = market.noPrice ?? (1.0 - yesPrice)
        
        let outcomes = [
            MarketOutcome(id: "\(market.ticker)-yes", name: "Yes", price: yesPrice, volume: market.volume24h),
            MarketOutcome(id: "\(market.ticker)-no", name: "No", price: noPrice, volume: nil)
        ]
        
        let endDate: Date? = market.closeTime.flatMap { ISO8601DateFormatter().date(from: $0) }
        let category = mapCategory(market.category)
        
        return PredictionMarket(
            id: "kalshi-\(market.ticker)",
            title: market.title,
            description: market.subtitle,
            platform: .kalshi,
            category: category,
            outcomes: outcomes,
            volume: market.volume,
            liquidity: market.openInterest,
            endDate: endDate,
            createdAt: nil,
            imageUrl: nil,
            marketUrl: "https://kalshi.com/markets/\(market.ticker)",
            isResolved: market.status == "settled",
            resolution: nil
        )
    }
    
    // MARK: - Helpers
    
    private func mapCategory(_ rawCategory: String?) -> PredictionCategory {
        guard let cat = rawCategory?.lowercased() else { return .other }
        
        switch cat {
        case "crypto", "cryptocurrency", "bitcoin", "ethereum":
            return .crypto
        case "politics", "political", "elections", "government":
            return .politics
        case "sports", "nfl", "nba", "mlb", "soccer", "football":
            return .sports
        case "economics", "economy", "finance", "fed", "inflation":
            return .economics
        case "entertainment", "movies", "tv", "celebrities":
            return .entertainment
        case "science", "technology", "space", "ai":
            return .science
        case "weather", "climate":
            return .weather
        default:
            return .other
        }
    }
    
    // MARK: - Sample Data (Fallback when APIs fail)
    
    private func getSamplePolymarketData() -> [PredictionMarket] {
        return [
            PredictionMarket(
                id: "sample-poly-1",
                title: "Will Bitcoin reach $100K in 2026?",
                description: "Refresh to load live markets from Polymarket.",
                platform: .polymarket,
                category: .crypto,
                outcomes: [
                    MarketOutcome(id: "sp1-yes", name: "Yes", price: 0.68, volume: 2_500_000),
                    MarketOutcome(id: "sp1-no", name: "No", price: 0.32, volume: 1_200_000)
                ],
                volume: 15_000_000,
                liquidity: 500_000,
                endDate: Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 31)),
                createdAt: Date(),
                imageUrl: nil,
                marketUrl: nil,  // No URL for sample data
                isResolved: false,
                resolution: nil
            ),
            PredictionMarket(
                id: "sample-poly-2",
                title: "Will Ethereum flip Bitcoin market cap in 2026?",
                description: "Refresh to load live markets from Polymarket.",
                platform: .polymarket,
                category: .crypto,
                outcomes: [
                    MarketOutcome(id: "sp2-yes", name: "Yes", price: 0.12, volume: 800_000),
                    MarketOutcome(id: "sp2-no", name: "No", price: 0.88, volume: 5_800_000)
                ],
                volume: 6_600_000,
                liquidity: 250_000,
                endDate: Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 31)),
                createdAt: Date(),
                imageUrl: nil,
                marketUrl: nil,
                isResolved: false,
                resolution: nil
            ),
            PredictionMarket(
                id: "sample-poly-3",
                title: "Will Fed cut rates in Q1 2026?",
                description: "Refresh to load live markets from Polymarket.",
                platform: .polymarket,
                category: .economics,
                outcomes: [
                    MarketOutcome(id: "sp3-yes", name: "Yes", price: 0.45, volume: 3_000_000),
                    MarketOutcome(id: "sp3-no", name: "No", price: 0.55, volume: 3_700_000)
                ],
                volume: 8_500_000,
                liquidity: 400_000,
                endDate: Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 31)),
                createdAt: Date(),
                imageUrl: nil,
                marketUrl: nil,
                isResolved: false,
                resolution: nil
            ),
            PredictionMarket(
                id: "sample-poly-4",
                title: "Will Solana reach $500 in 2026?",
                description: "Refresh to load live markets from Polymarket.",
                platform: .polymarket,
                category: .crypto,
                outcomes: [
                    MarketOutcome(id: "sp4-yes", name: "Yes", price: 0.22, volume: 1_500_000),
                    MarketOutcome(id: "sp4-no", name: "No", price: 0.78, volume: 5_400_000)
                ],
                volume: 6_900_000,
                liquidity: 180_000,
                endDate: Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 31)),
                createdAt: Date(),
                imageUrl: nil,
                marketUrl: nil,
                isResolved: false,
                resolution: nil
            )
        ]
    }
    
    private func getSampleKalshiData() -> [PredictionMarket] {
        return [
            PredictionMarket(
                id: "sample-kalshi-1",
                title: "US GDP Growth Q1 2026 > 2%",
                description: "Refresh to load live markets from Kalshi.",
                platform: .kalshi,
                category: .economics,
                outcomes: [
                    MarketOutcome(id: "sk1-yes", name: "Yes", price: 0.62, volume: 1_200_000),
                    MarketOutcome(id: "sk1-no", name: "No", price: 0.38, volume: 750_000)
                ],
                volume: 4_500_000,
                liquidity: 200_000,
                endDate: Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 30)),
                createdAt: Date(),
                imageUrl: nil,
                marketUrl: nil,
                isResolved: false,
                resolution: nil
            ),
            PredictionMarket(
                id: "sample-kalshi-2",
                title: "BTC Spot ETF Daily Volume > $5B Average",
                description: "Refresh to load live markets from Kalshi.",
                platform: .kalshi,
                category: .crypto,
                outcomes: [
                    MarketOutcome(id: "sk2-yes", name: "Yes", price: 0.55, volume: 900_000),
                    MarketOutcome(id: "sk2-no", name: "No", price: 0.45, volume: 750_000)
                ],
                volume: 3_200_000,
                liquidity: 150_000,
                endDate: Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 28)),
                createdAt: Date(),
                imageUrl: nil,
                marketUrl: nil,
                isResolved: false,
                resolution: nil
            )
        ]
    }
}

// MARK: - Errors

enum PredictionMarketError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case decodingError(String)
    case rateLimited
    case notAvailable
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid prediction market URL"
        case .invalidResponse:
            return "Invalid response from prediction market API"
        case .httpError(let code):
            return "Prediction market API error (code \(code))"
        case .decodingError(let message):
            return "Failed to decode prediction market data: \(message)"
        case .rateLimited:
            return "Prediction market API rate limited. Try again later."
        case .notAvailable:
            return "Prediction markets not available in your region"
        }
    }
}
