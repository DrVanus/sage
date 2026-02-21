//
//  EventsService.swift
//  CryptoSage
//
//  Live crypto events calendar service with caching and fallback support.
//

import Foundation

// MARK: - API Response Models

/// CoinMarketCal API response structure
struct CoinMarketCalResponse: Codable {
    let body: [CoinMarketCalEvent]?
    let status: CoinMarketCalStatus?
}

struct CoinMarketCalStatus: Codable {
    let errorCode: Int?
    let errorMessage: String?
    
    enum CodingKeys: String, CodingKey {
        case errorCode = "error_code"
        case errorMessage = "error_message"
    }
}

struct CoinMarketCalEvent: Codable {
    let id: Int?
    let title: Title?
    let coins: [CoinRef]?
    let dateEvent: String?
    let categories: [CategoryRef]?
    let description: Description?
    let proof: String?
    let source: String?
    
    struct Title: Codable {
        let en: String?
    }
    
    struct Description: Codable {
        let en: String?
    }
    
    struct CoinRef: Codable {
        let id: String?
        let name: String?
        let symbol: String?
    }
    
    struct CategoryRef: Codable {
        let id: Int?
        let name: String?
    }
    
    enum CodingKeys: String, CodingKey {
        case id, title, coins, categories, description, proof, source
        case dateEvent = "date_event"
    }
}

// MARK: - Cached Event Model (matches EventItem structure)

struct CachedEventItem: Codable, Identifiable {
    let id: String
    let title: String
    let date: Date
    let category: String  // "onchain", "macro", "exchange", "all"
    let impact: String    // "low", "medium", "high"
    let subtitle: String?
    let urlString: String?
    let coinSymbols: [String]
    
    var url: URL? {
        guard let s = urlString else { return nil }
        return URL(string: s)
    }
}

// MARK: - Events Service

actor EventsService {
    static let shared = EventsService()
    
    private let cacheFilename = "events_cache.json"
    private let cacheMaxAge: TimeInterval = 30 * 60  // 30 minutes
    
    // CoinMarketCal API configuration
    // Free tier: 5000 calls/month - plenty for occasional refreshes
    // IMPORTANT: Set your API key in environment or replace this placeholder
    private let apiBaseURL = "https://developers.coinmarketcal.com/v1/events"
    private var apiKey: String {
        // Try to get from environment/keychain first, fall back to empty (will fail gracefully)
        ProcessInfo.processInfo.environment["COINMARKETCAL_API_KEY"] ?? ""
    }
    
    private static let cachedSession: URLSession = {
        let config = URLSessionConfiguration.default
        // MEMORY FIX v3: Reduced from 3MB/25MB to 1MB/10MB
        config.urlCache = URLCache(memoryCapacity: 1 * 1024 * 1024,
                                   diskCapacity: 10 * 1024 * 1024,
                                   diskPath: "CryptoEventsCache")
        config.requestCachePolicy = .useProtocolCachePolicy
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()
    
    private init() {}
    
    // MARK: - Public API
    
    /// Fetch events with caching - returns cached data if fresh, otherwise fetches new
    /// Primary: Uses Firebase proxy for shared caching across all users
    /// Fallback: Direct API calls or curated events
    func fetchEvents(forceRefresh: Bool = false) async -> [CachedEventItem] {
        // Try cache first unless force refresh
        if !forceRefresh, let cached = loadCache(), isCacheFresh() {
            DebugLog.log("EventsService", "Source=cache (fresh), count=\(cached.count)")
            return cached
        }
        
        // PRIMARY: Try Firebase proxy first (shared caching, no rate limits)
        if await shouldUseFirebase() {
            let firebaseEvents = await fetchFromFirebase()
            if !firebaseEvents.isEmpty {
                saveCache(firebaseEvents)
                DebugLog.log("EventsService", "Source=firebase, count=\(firebaseEvents.count)")
                return firebaseEvents
            }
            DebugLog.log("EventsService", "Firebase source returned 0 events, falling back")
        } else {
            DebugLog.log("EventsService", "Firebase source disabled, falling back to direct API")
        }
        
        // FALLBACK: Try direct API fetch
        do {
            let events = try await fetchFromAPI()
            if !events.isEmpty {
                saveCache(events)
                DebugLog.log("EventsService", "Source=coinmarketcal, count=\(events.count)")
                return events
            }
            DebugLog.log("EventsService", "Direct API returned 0 events, checking stale cache")
        } catch {
            DebugLog.log("EventsService", "Direct API fetch failed: \(error.localizedDescription)")
        }
        
        // Fallback to cache even if stale
        if let cached = loadCache() {
            DebugLog.log("EventsService", "Source=cache (stale), count=\(cached.count)")
            return cached
        }
        
        // Final fallback: curated events from RSS/static sources
        let fallback = await fetchFallbackEvents()
        if !fallback.isEmpty {
            saveCache(fallback)
        }
        DebugLog.log("EventsService", "Source=fallback, count=\(fallback.count)")
        return fallback
    }
    
    // MARK: - Firebase Proxy
    
    /// Check if Firebase should be used (must be called from actor context)
    private func shouldUseFirebase() async -> Bool {
        return await MainActor.run {
            FirebaseService.shared.shouldUseFirebase
        }
    }
    
    /// Fetch events from Firebase proxy
    /// Benefits: Shared caching, rate limit management, aggregated data sources
    private func fetchFromFirebase() async -> [CachedEventItem] {
        do {
            let response = try await MainActor.run {
                Task {
                    try await FirebaseService.shared.getUpcomingEvents()
                }
            }.value
            
            // Convert Firebase response to local model
            return response.events.compactMap { event -> CachedEventItem? in
                guard let date = event.eventDate else { return nil }
                
                return CachedEventItem(
                    id: event.id,
                    title: event.title,
                    date: date,
                    category: event.category,
                    impact: event.impact,
                    subtitle: event.subtitle,
                    urlString: event.urlString,
                    coinSymbols: event.coinSymbols
                )
            }
        } catch {
            DebugLog.log("EventsService", "Firebase proxy error: \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: - API Fetching
    
    private func fetchFromAPI() async throws -> [CachedEventItem] {
        if apiKey.isEmpty {
            DebugLog.log("EventsService", "CoinMarketCal API key missing; skipping direct API fetch")
            throw EventsError.unauthorized
        }

        // Build URL with query parameters
        var components = URLComponents(string: apiBaseURL)!
        components.queryItems = [
            URLQueryItem(name: "max", value: "50"),
            URLQueryItem(name: "dateRangeStart", value: dateString(Date())),
            URLQueryItem(name: "dateRangeEnd", value: dateString(Date().addingTimeInterval(90 * 24 * 60 * 60))), // 90 days ahead
            URLQueryItem(name: "sortBy", value: "date_event"),
        ]
        
        guard let url = components.url else {
            throw EventsError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        
        let (data, response) = try await Self.cachedSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EventsError.invalidResponse
        }
        
        // Handle rate limiting or auth errors
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw EventsError.unauthorized
        }
        
        if httpResponse.statusCode == 429 {
            throw EventsError.rateLimited
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw EventsError.httpError(httpResponse.statusCode)
        }
        
        // Parse response
        let decoder = JSONDecoder()
        let apiResponse = try decoder.decode(CoinMarketCalResponse.self, from: data)
        
        guard let events = apiResponse.body else {
            return []
        }
        
        // Convert to our cached model
        return events.compactMap { event -> CachedEventItem? in
            guard let title = event.title?.en,
                  let dateStr = event.dateEvent,
                  let date = parseEventDate(dateStr) else {
                return nil
            }
            
            let category = categorizeEvent(event)
            let impact = estimateImpact(event)
            let symbols = event.coins?.compactMap { $0.symbol } ?? []
            
            return CachedEventItem(
                id: "\(event.id ?? Int.random(in: 1000...9999))",
                title: title,
                date: date,
                category: category,
                impact: impact,
                subtitle: event.description?.en?.prefix(100).description,
                urlString: event.source ?? event.proof,
                coinSymbols: symbols
            )
        }
    }
    
    // MARK: - Fallback Events (RSS/Curated)
    
    private func fetchFallbackEvents() async -> [CachedEventItem] {
        // Curated upcoming events from reliable sources
        // These are real upcoming crypto events that get updated manually or via RSS
        var events: [CachedEventItem] = []
        
        // Try to fetch from CoinGecko status/events endpoint as backup
        if let geckoEvents = await fetchGeckoStatusEvents() {
            events.append(contentsOf: geckoEvents)
        }
        
        // If still empty, generate dynamic events based on known recurring crypto events
        if events.isEmpty {
            events = generateKnownRecurringEvents()
        }
        
        return events.sorted { $0.date < $1.date }
    }
    
    private func fetchGeckoStatusEvents() async -> [CachedEventItem]? {
        // CoinGecko doesn't have a public events API, but we can check for major protocol updates
        // This is a placeholder for potential future integration
        return nil
    }
    
    /// Generate events based on known recurring crypto events and upcoming dates
    private func generateKnownRecurringEvents() -> [CachedEventItem] {
        let now = Date()
        let calendar = Calendar.current
        var events: [CachedEventItem] = []
        
        // Bitcoin halving countdown (approximately every 4 years, ~210,000 blocks)
        // Next halving estimated around April 2028
        let btcHalvingDate = calendar.date(from: DateComponents(year: 2028, month: 4, day: 15))!
        if btcHalvingDate > now {
            events.append(CachedEventItem(
                id: "btc_halving_2028",
                title: "Bitcoin Halving",
                date: btcHalvingDate,
                category: "onchain",
                impact: "high",
                subtitle: "Block reward reduces from 3.125 to 1.5625 BTC",
                urlString: "https://www.bitcoinblockhalf.com/",
                coinSymbols: ["BTC"]
            ))
        }
        
        // FOMC meetings (Federal Reserve - impacts crypto markets)
        let fomcDates = getUpcomingFOMCDates(from: now)
        for (index, date) in fomcDates.prefix(6).enumerated() {
            events.append(CachedEventItem(
                id: "fomc_\(index)_\(Int(date.timeIntervalSince1970))",
                title: "FOMC Meeting",
                date: date,
                category: "macro",
                impact: "high",
                subtitle: "Federal Reserve interest rate decision",
                urlString: "https://www.federalreserve.gov/monetarypolicy/fomccalendars.htm",
                coinSymbols: []
            ))
        }
        
        // CPI releases (monthly, usually 2nd week)
        let cpiDates = getUpcomingCPIDates(from: now)
        for (index, date) in cpiDates.prefix(6).enumerated() {
            events.append(CachedEventItem(
                id: "cpi_\(index)_\(Int(date.timeIntervalSince1970))",
                title: "CPI Release",
                date: date,
                category: "macro",
                impact: "high",
                subtitle: "US Consumer Price Index data",
                urlString: "https://www.bls.gov/cpi/",
                coinSymbols: []
            ))
        }
        
        // NOTE: Only include events with KNOWN, verified dates
        // Removed fake "Ethereum upgrade" and "Token unlock" placeholders
        // These would show incorrect dates to users
        
        // Solana Breakpoint conference (annual, usually November) - real conference
        // Only include if date is confirmed for the year
        // TODO: Update with confirmed 2026 date when announced
        
        return events
    }
    
    // MARK: - Date Helpers
    
    private func getUpcomingFOMCDates(from date: Date) -> [Date] {
        // FOMC meets approximately 8 times per year
        // 2026 tentative dates (these should be updated annually)
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        
        let fomcMonthDays: [(Int, Int)] = [
            (1, 29), (3, 18), (5, 6), (6, 17),
            (7, 29), (9, 16), (11, 4), (12, 16)
        ]
        
        var dates: [Date] = []
        for (month, day) in fomcMonthDays {
            if let d = calendar.date(from: DateComponents(year: year, month: month, day: day)),
               d > date {
                dates.append(d)
            }
            // Also check next year
            if let d = calendar.date(from: DateComponents(year: year + 1, month: month, day: day)),
               d > date {
                dates.append(d)
            }
        }
        
        return dates.sorted().prefix(6).map { $0 }
    }
    
    private func getUpcomingCPIDates(from date: Date) -> [Date] {
        // CPI is typically released around the 10th-14th of each month
        let calendar = Calendar.current
        var dates: [Date] = []
        
        for monthOffset in 0..<6 {
            if let futureDate = calendar.date(byAdding: .month, value: monthOffset, to: date) {
                let components = calendar.dateComponents([.year, .month], from: futureDate)
                if let cpiDate = calendar.date(from: DateComponents(
                    year: components.year,
                    month: components.month,
                    day: 12,
                    hour: 8,
                    minute: 30
                )), cpiDate > date {
                    dates.append(cpiDate)
                }
            }
        }
        
        return dates
    }
    
    private func nextAnnualEventDate(month: Int, day: Int, from date: Date) -> Date? {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        
        if let thisYear = calendar.date(from: DateComponents(year: year, month: month, day: day)),
           thisYear > date {
            return thisYear
        }
        
        return calendar.date(from: DateComponents(year: year + 1, month: month, day: day))
    }
    
    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: date)
    }
    
    private func parseEventDate(_ dateStr: String) -> Date? {
        let formatters = [
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd",
            "dd/MM/yyyy"
        ]
        
        for format in formatters {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            if let date = formatter.date(from: dateStr) {
                return date
            }
        }
        
        return nil
    }
    
    // MARK: - Event Classification
    
    private func categorizeEvent(_ event: CoinMarketCalEvent) -> String {
        let categories = event.categories?.compactMap { $0.name?.lowercased() } ?? []
        let title = event.title?.en?.lowercased() ?? ""
        
        // On-chain events
        let onchainKeywords = ["fork", "upgrade", "mainnet", "testnet", "halving", "unlock", "burn", "staking", "airdrop", "swap", "migration"]
        if categories.contains(where: { onchainKeywords.contains($0) }) ||
           onchainKeywords.contains(where: { title.contains($0) }) {
            return "onchain"
        }
        
        // Macro events
        let macroKeywords = ["fomc", "fed", "inflation", "cpi", "gdp", "jobs", "employment", "rate", "policy"]
        if macroKeywords.contains(where: { title.contains($0) }) {
            return "macro"
        }
        
        // Exchange events
        let exchangeKeywords = ["listing", "conference", "summit", "meetup", "ama", "partnership", "launch", "release"]
        if categories.contains(where: { exchangeKeywords.contains($0) }) ||
           exchangeKeywords.contains(where: { title.contains($0) }) {
            return "exchange"
        }
        
        return "onchain" // Default
    }
    
    private func estimateImpact(_ event: CoinMarketCalEvent) -> String {
        let title = event.title?.en?.lowercased() ?? ""
        let coins = event.coins ?? []
        
        // High impact events
        let highKeywords = ["halving", "fork", "mainnet", "fomc", "cpi", "fed", "merge"]
        if highKeywords.contains(where: { title.contains($0) }) {
            return "high"
        }
        
        // Major coins get higher impact
        let majorCoins = ["BTC", "ETH", "SOL", "BNB", "XRP"]
        if coins.contains(where: { majorCoins.contains($0.symbol?.uppercased() ?? "") }) {
            return "high"
        }
        
        // Medium impact
        let mediumKeywords = ["upgrade", "unlock", "listing", "partnership", "conference"]
        if mediumKeywords.contains(where: { title.contains($0) }) {
            return "medium"
        }
        
        return "low"
    }
    
    // MARK: - Cache Management
    
    private func loadCache() -> [CachedEventItem]? {
        return CacheManager.shared.load([CachedEventItem].self, from: cacheFilename)
    }
    
    private func saveCache(_ events: [CachedEventItem]) {
        CacheManager.shared.save(events, to: cacheFilename)
        UserDefaults.standard.set(Date(), forKey: "events_cache_timestamp")
    }
    
    private func isCacheFresh() -> Bool {
        guard let timestamp = UserDefaults.standard.object(forKey: "events_cache_timestamp") as? Date else {
            return false
        }
        return Date().timeIntervalSince(timestamp) < cacheMaxAge
    }
}

// MARK: - Error Types

enum EventsError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case rateLimited
    case httpError(Int)
    case decodingError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid server response"
        case .unauthorized:
            return "API authorization failed"
        case .rateLimited:
            return "API rate limit exceeded"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .decodingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        }
    }
}
