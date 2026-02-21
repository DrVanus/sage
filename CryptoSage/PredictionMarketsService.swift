//
//  PredictionMarketsService.swift
//  CryptoSage
//
//  THIRD-PARTY CLIENT - Direct Prediction Market API Integration
//  ==============================================================
//  This service connects DIRECTLY to prediction market APIs from the user's device.
//  
//  Supported Platforms:
//  - Polymarket (gamma-api.polymarket.com) - Crypto prediction markets
//  - Kalshi (api.elections.kalshi.com) - CFTC-regulated event contracts
//  
//  Security Model:
//  - All API calls go directly from device → platform (no middleman)
//  - Public market data requires no authentication
//  - Trading requires platform-specific authentication (handled separately)
//  
//  Note: Coinbase does NOT have prediction markets. For event-based trading,
//  users must use dedicated platforms like Polymarket or Kalshi directly.
//

import Foundation
import Combine

// MARK: - Prediction Market Models

/// Represents a prediction market event
public struct PredictionMarketEvent: Codable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let description: String?
    public let category: String
    public let source: PredictionMarketSource
    public let outcomes: [PredictionOutcome]
    public let volume: Double?              // Total volume traded
    public let liquidity: Double?           // Available liquidity
    public let endDate: Date?               // When the market resolves
    public let imageUrl: URL?
    public let marketUrl: URL?              // Direct link to market
    public let slug: String?                // URL-friendly identifier for the market
    public let isResolved: Bool
    public let resolvedOutcome: String?     // Which outcome won (if resolved)
    public let isSampleData: Bool           // Indicates if this is fallback sample data
    
    public var isActive: Bool {
        !isResolved && (endDate ?? Date.distantFuture) > Date()
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: PredictionMarketEvent, rhs: PredictionMarketEvent) -> Bool {
        lhs.id == rhs.id
    }
    
    /// Initializer with default values for new fields
    public init(
        id: String,
        title: String,
        description: String?,
        category: String,
        source: PredictionMarketSource,
        outcomes: [PredictionOutcome],
        volume: Double?,
        liquidity: Double?,
        endDate: Date?,
        imageUrl: URL?,
        marketUrl: URL?,
        slug: String? = nil,
        isResolved: Bool,
        resolvedOutcome: String?,
        isSampleData: Bool = false
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.category = category
        self.source = source
        self.outcomes = outcomes
        self.volume = volume
        self.liquidity = liquidity
        self.endDate = endDate
        self.imageUrl = imageUrl
        self.marketUrl = marketUrl
        self.slug = slug
        self.isResolved = isResolved
        self.resolvedOutcome = resolvedOutcome
        self.isSampleData = isSampleData
    }
}

/// Represents a possible outcome in a prediction market
public struct PredictionOutcome: Codable, Identifiable, Hashable {
    public let id: String
    public let name: String                 // e.g., "Yes", "No", "Trump", "Biden"
    public let probability: Double          // 0.0 to 1.0
    public let price: Double               // Price to buy (usually same as probability for binary markets)
    
    /// Formatted probability as percentage
    public var formattedProbability: String {
        String(format: "%.0f%%", probability * 100)
    }
    
    /// Formatted price in cents
    public var formattedPrice: String {
        String(format: "%.0f¢", price * 100)
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Source platform for prediction market
public enum PredictionMarketSource: String, Codable, CaseIterable {
    case polymarket = "Polymarket"
    case kalshi = "Kalshi"
    
    public var displayName: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .polymarket: return "chart.pie.fill"
        case .kalshi: return "chart.bar.xaxis"
        }
    }
    
    public var color: String {
        switch self {
        case .polymarket: return "#6366F1"  // Indigo
        case .kalshi: return "#10B981"       // Emerald
        }
    }
}

/// Category for filtering markets
public enum PredictionMarketCategory: String, CaseIterable {
    case all = "All"
    case crypto = "Crypto"
    case politics = "Politics"
    case sports = "Sports"
    case economics = "Economics"
    case entertainment = "Entertainment"
    case science = "Science"
    case other = "Other"
    
    public var displayName: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .crypto: return "bitcoinsign.circle"
        case .politics: return "building.columns"
        case .sports: return "sportscourt"
        case .economics: return "chart.line.uptrend.xyaxis"
        case .entertainment: return "film"
        case .science: return "atom"
        case .other: return "ellipsis.circle"
        }
    }
}

// MARK: - Prediction Markets Service

/// Main service for fetching prediction market data
public actor PredictionMarketsService {
    public static let shared = PredictionMarketsService()
    private init() {}
    
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8  // Reduced for faster fallback
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }()
    
    // MARK: - Cache
    private var cachedMarkets: [PredictionMarketEvent] = []
    private var lastFetchTime: Date?
    private let cacheDuration: TimeInterval = 60 // 1 minute cache
    
    // MARK: - Public API
    
    /// Fetch trending/popular markets from all sources
    public func fetchTrendingMarkets(limit: Int = 20, source: PredictionMarketSource? = nil) async throws -> [PredictionMarketEvent] {
        // Check cache (only if fetching all sources)
        if source == nil,
           let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < cacheDuration,
           !cachedMarkets.isEmpty {
            return Array(cachedMarkets.prefix(limit))
        }
        
        var allEvents: [PredictionMarketEvent] = []
        
        // Fetch based on source filter
        if source == nil || source == .polymarket {
            if let poly = try? await fetchPolymarketEvents(limit: source == nil ? limit / 2 : limit) {
                allEvents.append(contentsOf: poly)
            }
        }
        
        if source == nil || source == .kalshi {
            if let kalshi = try? await fetchKalshiEvents(limit: source == nil ? limit / 2 : limit) {
                allEvents.append(contentsOf: kalshi)
            }
        }
        
        // PRODUCTION FIX: Show empty state instead of fake sample data when APIs fail.
        // Previously showed hardcoded sample prediction markets as if they were real.
        
        // Sort by volume (most popular first)
        allEvents.sort { ($0.volume ?? 0) > ($1.volume ?? 0) }
        
        // Update cache only for full fetch
        if source == nil {
            cachedMarkets = allEvents
            lastFetchTime = Date()
        }
        
        return Array(allEvents.prefix(limit))
    }
    
    /// Fetch markets for a specific platform
    public func fetchMarkets(forSource source: PredictionMarketSource, limit: Int = 20) async throws -> [PredictionMarketEvent] {
        return try await fetchTrendingMarkets(limit: limit, source: source)
    }
    
    /// Fetch markets by category
    public func fetchMarkets(category: PredictionMarketCategory, limit: Int = 20) async throws -> [PredictionMarketEvent] {
        let allMarkets = try await fetchTrendingMarkets(limit: 50)
        
        if category == .all {
            return Array(allMarkets.prefix(limit))
        }
        
        let filtered = allMarkets.filter { $0.category.lowercased() == category.rawValue.lowercased() }
        return Array(filtered.prefix(limit))
    }
    
    /// Fetch crypto-specific prediction markets
    public func fetchCryptoMarkets() async throws -> [PredictionMarketEvent] {
        return try await fetchMarkets(category: .crypto, limit: 15)
    }
    
    /// Search markets by query
    public func searchMarkets(query: String) async throws -> [PredictionMarketEvent] {
        let allMarkets = try await fetchTrendingMarkets(limit: 100)
        
        let lowercasedQuery = query.lowercased()
        return allMarkets.filter { event in
            event.title.lowercased().contains(lowercasedQuery) ||
            (event.description?.lowercased().contains(lowercasedQuery) ?? false) ||
            event.category.lowercased().contains(lowercasedQuery)
        }
    }
    
    /// Clear cached data
    public func clearCache() {
        cachedMarkets = []
        lastFetchTime = nil
    }
    
    // MARK: - Polymarket Integration
    
    /// Fetch events from Polymarket's Gamma API
    private func fetchPolymarketEvents(limit: Int) async throws -> [PredictionMarketEvent] {
        // Polymarket uses a GraphQL API through their CLOB (Central Limit Order Book)
        // Documentation: https://docs.polymarket.com/
        guard let url = URL(string: "https://gamma-api.polymarket.com/markets?closed=false&limit=\(limit)") else {
            return []  // PRODUCTION FIX: Return empty instead of fake sample data
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CryptoSage/1.0", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return []  // PRODUCTION FIX: Return empty on HTTP error
            }
            
            // Parse Polymarket response
            guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], !jsonArray.isEmpty else {
                return []  // PRODUCTION FIX: Return empty if parsing fails
            }
            
            let events = jsonArray.compactMap { item -> PredictionMarketEvent? in
                guard let id = item["id"] as? String ?? item["condition_id"] as? String,
                      let question = item["question"] as? String else {
                    return nil
                }
                
                let description = item["description"] as? String
                let category = mapPolymarketCategory(item["category"] as? String)
                let volume = (item["volume"] as? String).flatMap { Double($0) } ?? (item["volume"] as? Double)
                let liquidity = (item["liquidity"] as? String).flatMap { Double($0) } ?? (item["liquidity"] as? Double)
                
                // Parse end date
                let endDate: Date? = {
                    if let endDateStr = item["end_date_iso"] as? String {
                        return ISO8601DateFormatter().date(from: endDateStr)
                    }
                    return nil
                }()
                
                // Parse outcomes
                let outcomes = parsePolymarketOutcomes(item)
                
                let imageUrl = (item["image"] as? String).flatMap { URL(string: $0) }
                
                // Use slug for URL if available (Polymarket URLs use slugs, not IDs)
                let slug = item["slug"] as? String
                let marketUrl: URL? = {
                    if let slug = slug, !slug.isEmpty {
                        return URL(string: "https://polymarket.com/event/\(slug)")
                    }
                    if let conditionId = item["condition_id"] as? String {
                        return URL(string: "https://polymarket.com/event/\(conditionId)")
                    }
                    return nil
                }()
                
                let isResolved = item["closed"] as? Bool ?? false
                
                return PredictionMarketEvent(
                    id: "poly_\(id)",
                    title: question,
                    description: description,
                    category: category,
                    source: .polymarket,
                    outcomes: outcomes,
                    volume: volume,
                    liquidity: liquidity,
                    endDate: endDate,
                    imageUrl: imageUrl,
                    marketUrl: marketUrl,
                    slug: slug,
                    isResolved: isResolved,
                    resolvedOutcome: nil,
                    isSampleData: false
                )
            }
            
            return events
        } catch {
            return []  // PRODUCTION FIX: Return empty on error
        }
    }
    
    private func parsePolymarketOutcomes(_ item: [String: Any]) -> [PredictionOutcome] {
        // Polymarket usually has Yes/No outcomes with prices
        var outcomes: [PredictionOutcome] = []
        
        if let outcomePrices = item["outcomePrices"] as? String,
           let data = outcomePrices.data(using: .utf8),
           let prices = try? JSONSerialization.jsonObject(with: data) as? [String] {
            
            let outcomeNames = ["Yes", "No"]
            for (index, priceStr) in prices.enumerated() where index < outcomeNames.count {
                if let price = Double(priceStr) {
                    outcomes.append(PredictionOutcome(
                        id: "\(index)",
                        name: outcomeNames[index],
                        probability: price,
                        price: price
                    ))
                }
            }
        } else {
            // Default binary market outcomes
            let yesPrice = (item["yes_bid"] as? String).flatMap { Double($0) } ?? 0.5
            let noPrice = (item["no_bid"] as? String).flatMap { Double($0) } ?? (1.0 - yesPrice)
            
            outcomes = [
                PredictionOutcome(id: "yes", name: "Yes", probability: yesPrice, price: yesPrice),
                PredictionOutcome(id: "no", name: "No", probability: noPrice, price: noPrice)
            ]
        }
        
        return outcomes
    }
    
    private func mapPolymarketCategory(_ category: String?) -> String {
        guard let cat = category?.lowercased() else { return "Other" }
        
        if cat.contains("crypto") || cat.contains("bitcoin") || cat.contains("ethereum") {
            return "Crypto"
        } else if cat.contains("politic") || cat.contains("election") || cat.contains("president") {
            return "Politics"
        } else if cat.contains("sport") || cat.contains("nfl") || cat.contains("nba") {
            return "Sports"
        } else if cat.contains("econ") || cat.contains("fed") || cat.contains("rate") {
            return "Economics"
        } else if cat.contains("entertainment") || cat.contains("movie") || cat.contains("award") {
            return "Entertainment"
        } else if cat.contains("science") || cat.contains("ai") || cat.contains("tech") {
            return "Science"
        }
        return "Other"
    }
    
    // MARK: - Kalshi Integration
    
    /// Fetch events from Kalshi API
    private func fetchKalshiEvents(limit: Int) async throws -> [PredictionMarketEvent] {
        // Kalshi has a public REST API
        // Documentation: https://trading-api.readme.io/reference/getmarkets
        guard let url = URL(string: "https://api.elections.kalshi.com/trade-api/v2/markets?limit=\(limit)&status=open") else {
            return []  // PRODUCTION FIX: Return empty instead of fake sample data
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CryptoSage/1.0", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return []  // PRODUCTION FIX: Return empty on HTTP error
            }
            
            // Parse Kalshi response
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let markets = json["markets"] as? [[String: Any]], !markets.isEmpty else {
                return []  // PRODUCTION FIX: Return empty if parsing fails
            }
            
            let events = markets.compactMap { item -> PredictionMarketEvent? in
                guard let ticker = item["ticker"] as? String,
                      let title = item["title"] as? String else {
                    return nil
                }
                
                let subtitle = item["subtitle"] as? String
                let category = mapKalshiCategory(item["category"] as? String ?? item["event_ticker"] as? String)
                
                // Parse volume - Kalshi returns volume in cents
                let volumeCents = item["volume"] as? Int ?? item["volume_24h"] as? Int ?? 0
                let volume = Double(volumeCents) / 100.0
                
                // Parse end date
                let endDate: Date? = {
                    if let closeTime = item["close_time"] as? String {
                        let formatter = ISO8601DateFormatter()
                        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        return formatter.date(from: closeTime)
                    }
                    return nil
                }()
                
                // Parse outcomes (Kalshi markets are typically Yes/No)
                let yesPrice = (item["yes_bid"] as? Double ?? item["last_price"] as? Double ?? 50) / 100.0
                let noPrice = 1.0 - yesPrice
                
                let outcomes = [
                    PredictionOutcome(id: "yes", name: "Yes", probability: yesPrice, price: yesPrice),
                    PredictionOutcome(id: "no", name: "No", probability: noPrice, price: noPrice)
                ]
                
                let marketUrl = URL(string: "https://kalshi.com/markets/\(ticker)")
                
                let status = item["status"] as? String ?? "active"
                let isResolved = status == "closed" || status == "finalized"
                
                return PredictionMarketEvent(
                    id: "kalshi_\(ticker)",
                    title: title,
                    description: subtitle,
                    category: category,
                    source: .kalshi,
                    outcomes: outcomes,
                    volume: volume,
                    liquidity: nil,
                    endDate: endDate,
                    imageUrl: nil,
                    marketUrl: marketUrl,
                    slug: ticker,
                    isResolved: isResolved,
                    resolvedOutcome: nil,
                    isSampleData: false
                )
            }
            
            return events
        } catch {
            return []  // PRODUCTION FIX: Return empty on error
        }
    }
    
    private func mapKalshiCategory(_ ticker: String?) -> String {
        guard let t = ticker?.uppercased() else { return "Other" }
        
        if t.contains("BTC") || t.contains("ETH") || t.contains("CRYPTO") {
            return "Crypto"
        } else if t.contains("PRES") || t.contains("ELECT") || t.contains("CONG") || t.contains("SENATE") {
            return "Politics"
        } else if t.contains("NFL") || t.contains("NBA") || t.contains("MLB") || t.contains("SPORT") {
            return "Sports"
        } else if t.contains("FED") || t.contains("RATE") || t.contains("GDP") || t.contains("CPI") || t.contains("INFL") {
            return "Economics"
        } else if t.contains("OSCAR") || t.contains("EMMY") || t.contains("GRAMMY") {
            return "Entertainment"
        } else if t.contains("AI") || t.contains("TECH") || t.contains("SPACE") {
            return "Science"
        }
        return "Other"
    }
}

// MARK: - Errors

public enum PredictionMarketsError: LocalizedError {
    case apiError(message: String)
    case parseError
    case networkError
    case unauthorized
    
    public var errorDescription: String? {
        switch self {
        case .apiError(let message):
            return "API Error: \(message)"
        case .parseError:
            return "Failed to parse prediction market data"
        case .networkError:
            return "Network connection error"
        case .unauthorized:
            return "Authentication required for this feature"
        }
    }
}

// MARK: - Preview Helpers

extension PredictionMarketEvent {
    /// Sample event for previews and testing
    public static var sample: PredictionMarketEvent {
        PredictionMarketEvent(
            id: "sample_1",
            title: "[Sample] Will Bitcoin reach $150,000 by end of 2026?",
            description: "This market resolves to Yes if the price of Bitcoin reaches or exceeds $150,000 at any point before December 31, 2026.",
            category: "Crypto",
            source: .polymarket,
            outcomes: [
                PredictionOutcome(id: "yes", name: "Yes", probability: 0.42, price: 0.42),
                PredictionOutcome(id: "no", name: "No", probability: 0.58, price: 0.58)
            ],
            volume: 1_500_000,
            liquidity: 250_000,
            endDate: Calendar.current.date(byAdding: .year, value: 1, to: Date()),
            imageUrl: nil,
            marketUrl: nil,  // Sample data has no valid URL
            slug: nil,
            isResolved: false,
            resolvedOutcome: nil,
            isSampleData: true
        )
    }
    
    public static var samples: [PredictionMarketEvent] {
        polymarketSamples + kalshiSamples
    }
    
    /// Polymarket-specific sample data
    public static var polymarketSamples: [PredictionMarketEvent] {
        [
            PredictionMarketEvent(
                id: "sample_btc_100k",
                title: "Will Bitcoin reach $100K in 2026?",
                description: "This market resolves YES if BTC trades at or above $100,000 at any point in 2026.",
                category: "Crypto",
                source: .polymarket,
                outcomes: [
                    PredictionOutcome(id: "yes", name: "Yes", probability: 0.72, price: 0.72),
                    PredictionOutcome(id: "no", name: "No", probability: 0.28, price: 0.28)
                ],
                volume: 2_400_000,
                liquidity: 450_000,
                endDate: Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 31)),
                imageUrl: nil,
                marketUrl: URL(string: "https://polymarket.com"),
                slug: "bitcoin-100k-2026",
                isResolved: false,
                resolvedOutcome: nil,
                isSampleData: true
            ),
            PredictionMarketEvent(
                id: "sample_eth_etf",
                title: "ETH ETF approval by March?",
                description: "Will an Ethereum spot ETF be approved by the SEC by March 31, 2026?",
                category: "Crypto",
                source: .polymarket,
                outcomes: [
                    PredictionOutcome(id: "yes", name: "Yes", probability: 0.45, price: 0.45),
                    PredictionOutcome(id: "no", name: "No", probability: 0.55, price: 0.55)
                ],
                volume: 890_000,
                liquidity: 180_000,
                endDate: Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 31)),
                imageUrl: nil,
                marketUrl: URL(string: "https://polymarket.com"),
                slug: "eth-etf-march",
                isResolved: false,
                resolvedOutcome: nil,
                isSampleData: true
            ),
            PredictionMarketEvent(
                id: "sample_sol_500",
                title: "Will Solana reach $500 in 2026?",
                description: "This market resolves YES if SOL trades at or above $500 at any point in 2026.",
                category: "Crypto",
                source: .polymarket,
                outcomes: [
                    PredictionOutcome(id: "yes", name: "Yes", probability: 0.18, price: 0.18),
                    PredictionOutcome(id: "no", name: "No", probability: 0.82, price: 0.82)
                ],
                volume: 520_000,
                liquidity: 95_000,
                endDate: Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 31)),
                imageUrl: nil,
                marketUrl: URL(string: "https://polymarket.com"),
                slug: "solana-500",
                isResolved: false,
                resolvedOutcome: nil,
                isSampleData: true
            ),
            PredictionMarketEvent(
                id: "sample_btc_150k",
                title: "Will Bitcoin reach $150K by end of 2026?",
                description: "This market resolves YES if BTC reaches $150,000 before Dec 31, 2026.",
                category: "Crypto",
                source: .polymarket,
                outcomes: [
                    PredictionOutcome(id: "yes", name: "Yes", probability: 0.35, price: 0.35),
                    PredictionOutcome(id: "no", name: "No", probability: 0.65, price: 0.65)
                ],
                volume: 1_800_000,
                liquidity: 320_000,
                endDate: Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 31)),
                imageUrl: nil,
                marketUrl: URL(string: "https://polymarket.com"),
                slug: "bitcoin-150k",
                isResolved: false,
                resolvedOutcome: nil,
                isSampleData: true
            )
        ]
    }
    
    /// Kalshi-specific sample data
    public static var kalshiSamples: [PredictionMarketEvent] {
        [
            PredictionMarketEvent(
                id: "sample_fed_rate",
                title: "Fed rate cut in Q1 2026?",
                description: "Will the Federal Reserve cut interest rates in Q1 2026?",
                category: "Economics",
                source: .kalshi,
                outcomes: [
                    PredictionOutcome(id: "yes", name: "Yes", probability: 0.57, price: 0.57),
                    PredictionOutcome(id: "no", name: "No", probability: 0.43, price: 0.43)
                ],
                volume: 1_200_000,
                liquidity: nil,
                endDate: Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 31)),
                imageUrl: nil,
                marketUrl: URL(string: "https://kalshi.com"),
                slug: "FED-26Q1",
                isResolved: false,
                resolvedOutcome: nil,
                isSampleData: true
            ),
            PredictionMarketEvent(
                id: "sample_gdp_growth",
                title: "US GDP growth above 2.5% in 2026?",
                description: "Will US GDP growth exceed 2.5% for the full year 2026?",
                category: "Economics",
                source: .kalshi,
                outcomes: [
                    PredictionOutcome(id: "yes", name: "Yes", probability: 0.48, price: 0.48),
                    PredictionOutcome(id: "no", name: "No", probability: 0.52, price: 0.52)
                ],
                volume: 780_000,
                liquidity: nil,
                endDate: Calendar.current.date(from: DateComponents(year: 2027, month: 1, day: 31)),
                imageUrl: nil,
                marketUrl: URL(string: "https://kalshi.com"),
                slug: "GDP-26",
                isResolved: false,
                resolvedOutcome: nil,
                isSampleData: true
            ),
            PredictionMarketEvent(
                id: "sample_inflation",
                title: "CPI inflation below 3% by June 2026?",
                description: "Will the Consumer Price Index show year-over-year inflation below 3% by June 2026?",
                category: "Economics",
                source: .kalshi,
                outcomes: [
                    PredictionOutcome(id: "yes", name: "Yes", probability: 0.62, price: 0.62),
                    PredictionOutcome(id: "no", name: "No", probability: 0.38, price: 0.38)
                ],
                volume: 650_000,
                liquidity: nil,
                endDate: Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 30)),
                imageUrl: nil,
                marketUrl: URL(string: "https://kalshi.com"),
                slug: "CPI-26JUN",
                isResolved: false,
                resolvedOutcome: nil,
                isSampleData: true
            ),
            PredictionMarketEvent(
                id: "sample_btc_etf_vol",
                title: "BTC Spot ETF daily volume > $5B average in Feb?",
                description: "Will Bitcoin spot ETFs average over $5 billion in daily trading volume in February 2026?",
                category: "Crypto",
                source: .kalshi,
                outcomes: [
                    PredictionOutcome(id: "yes", name: "Yes", probability: 0.55, price: 0.55),
                    PredictionOutcome(id: "no", name: "No", probability: 0.45, price: 0.45)
                ],
                volume: 420_000,
                liquidity: nil,
                endDate: Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 28)),
                imageUrl: nil,
                marketUrl: URL(string: "https://kalshi.com"),
                slug: "BTCETF-VOL",
                isResolved: false,
                resolvedOutcome: nil,
                isSampleData: true
            )
        ]
    }
}
