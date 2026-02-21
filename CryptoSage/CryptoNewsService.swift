//
//  NewsAPIResponse 2.swift
//  CryptoSage
//
//


//
// CryptoNewsService.swift
// CryptoSage
//

import Foundation
import Network

/// Errors surfaceable by CryptoNewsService
enum CryptoNewsError: Error {
    case timeout
    case badServerResponse(statusCode: Int)
    case cancelled
    case decodingFailed(Error)
    case networkError(URLError)
    case apiError(message: String)
    case unknown(Error)
}

extension CryptoNewsError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .timeout:
            return "The news service timed out. Please try again."
        case .badServerResponse(let code):
            return "News server returned status code \(code)."
        case .cancelled:
            return "The request was cancelled."
        case .decodingFailed:
            return "Failed to decode news response."
        case .networkError(let urlError):
            return urlError.localizedDescription
        case .apiError(let message):
            return message
        case .unknown(let err):
            return err.localizedDescription
        }
    }
}

// MARK: - NewsAPI Models
struct NewsAPIResponse: Codable {
    let articles: [NewsAPIArticle]
}

struct NewsAPIArticle: Codable {
    let source: NewsAPISource
    let title: String
    let description: String?
    let url: URL
    let urlToImage: URL?
    let publishedAt: Date
}

/// Represents the source object from NewsAPI
struct NewsAPISource: Codable {
    let id: String?
    let name: String?
}

/// Success envelope used by NewsAPI when status == "ok"
private struct NewsAPIOkResponse: Codable {
    let status: String
    let totalResults: Int?
    let articles: [NewsAPIArticle]
}

/// Error envelope used by NewsAPI when status == "error"
private struct NewsAPIErrorEnvelope: Codable {
    let status: String
    let code: String?
    let message: String?
}

private func detectAPIError(in data: Data) -> String? {
    if let env = try? JSONDecoder().decode(NewsAPIErrorEnvelope.self, from: data), env.status.lowercased() == "error" {
        return env.message ?? env.code ?? "Unknown API error"
    }
    return nil
}

private func decodeArticles(from data: Data) throws -> [NewsAPIArticle] {
    // Build a tolerant ISO8601 date parser that accepts fractional and non-fractional seconds
    let isoWithFraction = ISO8601DateFormatter()
    isoWithFraction.formatOptions = [.withFullDate, .withFullTime, .withColonSeparatorInTime, .withColonSeparatorInTimeZone, .withFractionalSeconds]

    let isoNoFraction = ISO8601DateFormatter()
    isoNoFraction.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]

    // Primary decoder: accepts multiple ISO8601 variants
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { dec in
        let container = try dec.singleValueContainer()
        let raw = try container.decode(String.self)
        if let d = isoWithFraction.date(from: raw) { return d }
        if let d = isoNoFraction.date(from: raw) { return d }
        // Fallback common patterns
        let patterns = [
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssZ"
        ]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        for p in patterns {
            df.dateFormat = p
            if let d = df.date(from: raw) { return d }
        }
        throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "Unrecognized ISO8601 date: \(raw)"))
    }

    // Try the modern ok envelope first
    if let ok = try? decoder.decode(NewsAPIOkResponse.self, from: data), ok.status.lowercased() == "ok" {
        return ok.articles
    }
    // Try legacy shape without status
    if let legacy = try? decoder.decode(NewsAPIResponse.self, from: data) {
        return legacy.articles
    }

    // FINAL FALLBACK: decode with a relaxed model that treats publishedAt as String?, then map manually
    struct FallbackArticle: Codable {
        let source: NewsAPISource
        let title: String
        let description: String?
        let url: URL
        let urlToImage: URL?
        let publishedAt: String?
    }
    struct FallbackOkEnvelope: Codable { let status: String; let totalResults: Int?; let articles: [FallbackArticle] }
    struct FallbackLegacy: Codable { let articles: [FallbackArticle] }

    func parseDate(_ s: String?) -> Date? {
        guard let s = s, !s.isEmpty else { return nil }
        if let d = isoWithFraction.date(from: s) { return d }
        if let d = isoNoFraction.date(from: s) { return d }
        let patterns = [
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssZ"
        ]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        for p in patterns {
            df.dateFormat = p
            if let d = df.date(from: s) { return d }
        }
        return nil
    }

    if let relaxedOk = try? JSONDecoder().decode(FallbackOkEnvelope.self, from: data), relaxedOk.status.lowercased() == "ok" {
        let mapped: [NewsAPIArticle] = relaxedOk.articles.compactMap { fa in
            guard let date = parseDate(fa.publishedAt) else { return nil }
            return NewsAPIArticle(source: fa.source, title: fa.title, description: fa.description, url: fa.url, urlToImage: fa.urlToImage, publishedAt: date)
        }
        if !mapped.isEmpty { return mapped }
    }
    if let relaxedLegacy = try? JSONDecoder().decode(FallbackLegacy.self, from: data) {
        let mapped: [NewsAPIArticle] = relaxedLegacy.articles.compactMap { fa in
            guard let date = parseDate(fa.publishedAt) else { return nil }
            return NewsAPIArticle(source: fa.source, title: fa.title, description: fa.description, url: fa.url, urlToImage: fa.urlToImage, publishedAt: date)
        }
        if !mapped.isEmpty { return mapped }
    }

    throw CryptoNewsError.decodingFailed(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unrecognized news payload")))
}

// MARK: - CryptoNews Service
actor CryptoNewsService {
    // NOTE: Filtering patterns moved to NewsQualityFilter.swift (single source of truth)
    
    private static let cachedSession: URLSession = {
        let config = URLSessionConfiguration.default
        // MEMORY FIX v3: Reduced from 5MB/50MB to 2MB/20MB
        config.urlCache = URLCache(memoryCapacity: 2 * 1024 * 1024,
                                   diskCapacity: 20 * 1024 * 1024,
                                   diskPath: "CryptoNewsCache")
        config.requestCachePolicy = .useProtocolCachePolicy
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 25
        config.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: config)
    }()
    /// SECURITY FIX: Use centralized APIConfig with Keychain storage instead of hardcoded key
    private var apiKey: String { APIConfig.newsAPIKey }
    
    /// Default number of articles per page
    private let defaultPageSize = 30

    /// Load cached news only if the newest item is reasonably fresh
    nonisolated private func loadFreshCache(maxAge: TimeInterval = 6 * 3600) -> [CryptoNewsArticle]? {
        guard let cached: [CryptoNewsArticle] = CacheManager.shared.load([CryptoNewsArticle].self, from: "news_cache.json"), !cached.isEmpty else {
            return nil
        }
        let newest = cached.map { $0.publishedAt }.max() ?? .distantPast
        if Date().timeIntervalSince(newest) <= maxAge {
            return cached
        }
        return nil
    }

    /// Helper to perform a URLRequest with retries
    private func fetchDataWithRetry(_ request: URLRequest, retries: Int = 3) async throws -> Data {
        var lastError: Error?
        for attempt in 0...retries {
            do {
                let (data, response) = try await Self.cachedSession.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw CryptoNewsError.unknown(URLError(.badServerResponse))
                }
                guard 200..<300 ~= http.statusCode else {
                    if http.statusCode == 304 {
                        throw CryptoNewsError.badServerResponse(statusCode: 304)
                    }
                    throw CryptoNewsError.badServerResponse(statusCode: http.statusCode)
                }
                // Save Last-Modified and ETag headers for caching validation
                let defaults = UserDefaults.standard
                if let urlString = request.url?.absoluteString {
                    if let lastModified = http.allHeaderFields["Last-Modified"] as? String, !lastModified.isEmpty {
                        defaults.set(lastModified, forKey: "News.LastModified.\(urlString)")
                    }
                    if let eTag = http.allHeaderFields["ETag"] as? String, !eTag.isEmpty {
                        defaults.set(eTag, forKey: "News.ETag.\(urlString)")
                    }
                }
                return data
            } catch {
                lastError = error

                // Propagate cancellations immediately
                if let urlError = error as? URLError, urlError.code == .cancelled { throw CryptoNewsError.cancelled }
                if error is CancellationError { throw CryptoNewsError.cancelled }

                // Determine if this is a transient error worth retrying
                var shouldRetry = true
                if let urlError = error as? URLError {
                    let transient: Set<URLError.Code> = [
                        .timedOut, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
                        .dnsLookupFailed, .notConnectedToInternet, .internationalRoamingOff
                    ]
                    shouldRetry = transient.contains(urlError.code)
                    if !shouldRetry && attempt == retries {
                        if urlError.code == .timedOut { throw CryptoNewsError.timeout }
                        throw CryptoNewsError.networkError(urlError)
                    }
                }

                if attempt == retries { break }
                // Exponential backoff: ~0.4s, 0.8s, 1.6s, ...
                let delay = UInt64(pow(2.0, Double(attempt)) * 400_000_000)
                try? await Task.sleep(nanoseconds: delay)
            }
        }
        if let urlError = lastError as? URLError {
            if urlError.code == .timedOut { throw CryptoNewsError.timeout }
            throw CryptoNewsError.networkError(urlError)
        } else if let err = lastError {
            throw CryptoNewsError.unknown(err)
        } else {
            throw CryptoNewsError.unknown(URLError(.unknown))
        }
    }

    /// Fetch a small preview of news (for the home screen) for a given query
    func fetchPreviewNews(query: String) async throws -> [CryptoNewsArticle] {
        // Return exactly 3 preview articles for home screen
        return try await fetchNews(query: query, page: 1, pageSize: 3)
    }

    /// Fetch the latest full list of news for the default "crypto" query
    func fetchLatestNews() async throws -> [CryptoNewsArticle] {
        return try await fetchNews(query: "crypto", page: 1)
    }

    /// Internal helper to call NewsAPI for a given query, page, and pageSize

    // Strict allowlist of reputable crypto news domains to avoid spam and non-news (e.g., PyPI)
    let allowedDomains: [String] = [
        "coindesk.com","cointelegraph.com","decrypt.co","theblock.co","newsbtc.com",
        "cryptoslate.com","beincrypto.com","reuters.com","bloomberg.com","cnbc.com",
        "ambcrypto.com","finbold.com","bitcoinmagazine.com","blockworks.co","messari.io",
        "thedefiant.io","coinbureau.com","bankless.com","coingape.com","cryptobriefing.com",
        "coindeskmarkets.com","forbes.com","wsj.com","ft.com","coingecko.com","glassnode.com",
        "investopedia.com","nasdaq.com","marketwatch.com","yahoo.com"
    ]
    // Explicitly exclude developer/package hosts and other low-quality domains
    let excludedDomains: [String] = [
        "pypi.org","github.com","npmjs.com","packagist.org","readthedocs.io","medium.com",
        "substack.com","blogspot.com","wordpress.com","sourceforge.net","gitlab.com"
    ]

    func commaList(_ arr: [String]) -> String { arr.joined(separator: ",") }


    func fetchNews(query: String, page: Int, pageSize: Int? = nil, before: Date? = nil) async throws -> [CryptoNewsArticle] {
        let finalSize = pageSize ?? defaultPageSize

        // Prefer cached news if offline; if no cache, attempt network anyway (monitor may be stale)
        let isOnline = NetworkMonitor.shared.isOnline
        if !isOnline {
            if let cached = self.loadFreshCache() {
                return cached
            }
            // No cache available; continue to attempt a network request below as a best effort
        }

        // Build URL components (full featured)
        func buildComponents(simple: Bool) -> URLComponents? {
            // Cursor-aware window: if `before` is provided, set `to` to just before that date
            // and widen the window to 21 days to ensure enough older results. Otherwise, 14 days.
            let cursorToDate: Date = (before?.addingTimeInterval(-1)) ?? Date()
            let windowDays: Double = (before == nil) ? 14 : 21
            let fromDate = cursorToDate.addingTimeInterval(-windowDays * 24 * 3600)
            let fromDateISO: String = {
                let df = ISO8601DateFormatter()
                df.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
                return df.string(from: fromDate)
            }()
            let toDateISO: String = {
                let df = ISO8601DateFormatter()
                df.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
                return df.string(from: cursorToDate)
            }()

            let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            guard var components = URLComponents(string: "https://newsapi.org/v2/everything") else {
                return nil
            }
            if simple {
                components.queryItems = [
                    .init(name: "q", value: encodedQuery),
                    .init(name: "pageSize", value: "\(finalSize)"),
                    .init(name: "page",     value: "\(page)"),
                    .init(name: "sortBy",   value: "publishedAt"),
                    .init(name: "language", value: "en"),
                    .init(name: "excludeDomains", value: commaList(excludedDomains))
                ]
            } else {
                components.queryItems = [
                    .init(name: "q", value: encodedQuery),
                    .init(name: "pageSize", value: "\(finalSize)"),
                    .init(name: "page",     value: "\(page)"),
                    .init(name: "sortBy",   value: "publishedAt"),
                    .init(name: "from",     value: fromDateISO),
                    .init(name: "to",       value: toDateISO),
                    .init(name: "language", value: "en"),
                    .init(name: "searchIn", value: "title,description"),
                    .init(name: "excludeDomains", value: commaList(excludedDomains))
                ]
            }
            return components
        }

        func performRequest(simple: Bool) async throws -> [CryptoNewsArticle] {
            guard let baseComponents = buildComponents(simple: simple) else { return [] }

            // First attempt: header-based API key
            guard let urlHeader = baseComponents.url else { return [] }
            var headerReq = URLRequest(url: urlHeader)
            headerReq.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
            headerReq.timeoutInterval = 12
            headerReq.cachePolicy = .useProtocolCachePolicy

            // Add conditional request headers if available only for page == 1 and simple == false
            let defaults = UserDefaults.standard
            if page == 1 && simple == false {
                if let urlString = headerReq.url?.absoluteString {
                    if let lastModified = defaults.string(forKey: "News.LastModified.\(urlString)") {
                        headerReq.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
                    }
                    if let eTag = defaults.string(forKey: "News.ETag.\(urlString)") {
                        headerReq.setValue(eTag, forHTTPHeaderField: "If-None-Match")
                    }
                }
            }

            do {
                let data = try await fetchDataWithRetry(headerReq, retries: 3)
                if let apiMessage = detectAPIError(in: data) {
                    // If the API complains about the key, try query-param fallback
                    let lower = apiMessage.lowercased()
                    if lower.contains("api key") || lower.contains("apikey") || lower.contains("unauthorized") {
                        throw CryptoNewsError.badServerResponse(statusCode: 401)
                    }
                    throw CryptoNewsError.apiError(message: apiMessage)
                }
                let rawArticles = try decodeArticles(from: data)
                let articles = rawArticles.map { article in
                    CryptoNewsArticle(
                        title: article.title,
                        description: article.description,
                        url: article.url,
                        urlToImage: article.urlToImage,
                        sourceName: article.source.name ?? "Unknown Source",
                        publishedAt: article.publishedAt
                    )
                }
                // Apply comprehensive quality filter using centralized NewsQualityFilter
                let qualityFiltered = articles.filter { art in
                    NewsQualityFilter.passesQualityCheck(
                        url: art.url,
                        title: art.title,
                        description: art.description,
                        sourceName: art.sourceName
                    )
                }
                var limited = (page == 1) ? Array(qualityFiltered.prefix(finalSize)) : qualityFiltered
                if limited.count < finalSize {
                    // Top up with RSS items; when the API returns nothing, use the outer `before` cursor to fetch older items
                    let rssCursor = (limited.last?.publishedAt ?? before)?.addingTimeInterval(-1)
                    let rss = await RSSFetcher.fetch(limit: (finalSize * 2), before: rssCursor)
                    if !rss.isEmpty {
                        let existing = Set(limited.map { $0.id })
                        var merged = limited + rss.filter { !existing.contains($0.id) }
                        merged.sort { $0.publishedAt > $1.publishedAt }
                        limited = Array(merged.prefix(finalSize))
                    }
                }
                if limited.isEmpty {
                    // Try cache first
                    if let cached = self.loadFreshCache() {
                        return Array(cached.prefix(finalSize))
                    }
                    // Then seed to guarantee first paint
                    if page == 1 {
                        let seed = StaticNewsSeed.sampleArticles()
                        if !seed.isEmpty {
                            let limitedSeed = Array(seed.prefix(finalSize))
                            CacheManager.shared.save(limitedSeed, to: "news_cache.json")
                            return limitedSeed
                        }
                    }
                }
                if page == 1 && !limited.isEmpty {
                    CacheManager.shared.save(limited, to: "news_cache.json")
                }
                return limited
            } catch let err as CryptoNewsError {
                // Handle HTTP 304 Not Modified: return cache if available
                if case .badServerResponse(let code) = err, code == 304 {
                    if let cached = self.loadFreshCache() {
                        return cached
                    }
                    throw err
                }
                // If auth-related, retry using query parameter form
                if case .badServerResponse(let code) = err, code == 401 {
                    var qp = baseComponents
                    var items = qp.queryItems ?? []
                    items.append(URLQueryItem(name: "apiKey", value: apiKey))
                    qp.queryItems = items
                    guard let urlQP = qp.url else { throw err }
                    var qpReq = URLRequest(url: urlQP)
                    qpReq.timeoutInterval = 12
                    qpReq.cachePolicy = .useProtocolCachePolicy

                    // Add conditional request headers if available only for page == 1 and simple == false
                    if page == 1 && simple == false {
                        if let urlString = qpReq.url?.absoluteString {
                            if let lastModified = defaults.string(forKey: "News.LastModified.\(urlString)") {
                                qpReq.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
                            }
                            if let eTag = defaults.string(forKey: "News.ETag.\(urlString)") {
                                qpReq.setValue(eTag, forHTTPHeaderField: "If-None-Match")
                            }
                        }
                    }

                    do {
                        let data = try await fetchDataWithRetry(qpReq, retries: 3)
                        if let apiMessage = detectAPIError(in: data) {
                            throw CryptoNewsError.apiError(message: apiMessage)
                        }
                        let rawArticles = try decodeArticles(from: data)
                        let articles = rawArticles.map { article in
                            CryptoNewsArticle(
                                title: article.title,
                                description: article.description,
                                url: article.url,
                                urlToImage: article.urlToImage,
                                sourceName: article.source.name ?? "Unknown Source",
                                publishedAt: article.publishedAt
                            )
                        }
                        // Apply comprehensive quality filter using centralized NewsQualityFilter
                        let qualityFiltered = articles.filter { art in
                            NewsQualityFilter.passesQualityCheck(
                                url: art.url,
                                title: art.title,
                                description: art.description,
                                sourceName: art.sourceName
                            )
                        }
                        var limited = (page == 1) ? Array(qualityFiltered.prefix(finalSize)) : qualityFiltered
                        if limited.count < finalSize {
                            // Top up with RSS items; when the API returns nothing, use the outer `before` cursor to fetch older items
                            let rssCursor = (limited.last?.publishedAt ?? before)?.addingTimeInterval(-1)
                            let rss = await RSSFetcher.fetch(limit: (finalSize * 2), before: rssCursor)
                            if !rss.isEmpty {
                                let existing = Set(limited.map { $0.id })
                                var merged = limited + rss.filter { !existing.contains($0.id) }
                                merged.sort { $0.publishedAt > $1.publishedAt }
                                limited = Array(merged.prefix(finalSize))
                            }
                        }
                        if limited.isEmpty {
                            // Try cache first
                            if let cached = self.loadFreshCache() {
                                return Array(cached.prefix(finalSize))
                            }
                            // Then seed to guarantee first paint
                            if page == 1 {
                                let seed = StaticNewsSeed.sampleArticles()
                                if !seed.isEmpty {
                                    let limitedSeed = Array(seed.prefix(finalSize))
                                    CacheManager.shared.save(limitedSeed, to: "news_cache.json")
                                    return limitedSeed
                                }
                            }
                        }
                        if page == 1 && !limited.isEmpty {
                            CacheManager.shared.save(limited, to: "news_cache.json")
                        }
                        return limited
                    } catch let qpErr as CryptoNewsError {
                        if case .badServerResponse(let code) = qpErr, code == 304 {
                            if let cached = self.loadFreshCache() {
                                return cached
                            }
                        }
                        throw qpErr
                    }
                }
                throw err
            }
        }

        do {
            if page == 1 {
                // First paint: fetch from API and RSS in parallel, merge and sort all results
                // This ensures we get the freshest articles from all sources, properly sorted
                let result = await withTaskGroup(of: [CryptoNewsArticle].self) { group -> [CryptoNewsArticle] in
                    group.addTask { (try? await performRequest(simple: false)) ?? [] }
                    group.addTask { await RSSFetcher.fetch(limit: finalSize) }
                    
                    // Collect ALL results from both sources
                    var allArticles: [CryptoNewsArticle] = []
                    for await list in group {
                        allArticles.append(contentsOf: list)
                    }
                    
                    // If we got nothing from API/RSS, try cache as fallback
                    if allArticles.isEmpty {
                        if let cached = self.loadFreshCache() {
                            return Array(cached.prefix(finalSize))
                        }
                        return []
                    }
                    
                    // Deduplicate by URL
                    var seenURLs = Set<String>()
                    var unique: [CryptoNewsArticle] = []
                    for article in allArticles {
                        let key = article.url.absoluteString.lowercased()
                        if !seenURLs.contains(key) {
                            seenURLs.insert(key)
                            unique.append(article)
                        }
                    }
                    
                    // Sort by newest first to ensure proper order
                    unique.sort { $0.publishedAt > $1.publishedAt }
                    
                    return Array(unique.prefix(finalSize))
                }
                if !result.isEmpty {
                    if page == 1 { CacheManager.shared.save(result, to: "news_cache.json") }
                    return result
                }
                // If the merge produced nothing, return cache immediately for page 1 to avoid spinner
                if page == 1 {
                    if let cached = self.loadFreshCache() {
                        return Array(cached.prefix(finalSize))
                    }
                }
            }
            // Try full featured query first
            let articles = try await performRequest(simple: false)
            if !articles.isEmpty {
                if page == 1 && !articles.isEmpty {
                    CacheManager.shared.save(articles, to: "news_cache.json")
                }
                return articles
            }
            // If empty, try simplified query for broader results
            let fallback = try await performRequest(simple: true)
            if page == 1 && !fallback.isEmpty {
                CacheManager.shared.save(fallback, to: "news_cache.json")
            }
            return fallback
        } catch CryptoNewsError.apiError, CryptoNewsError.decodingFailed {
            // Retry once with simplified parameters if the first attempt failed due to API error/shape
            let fallback = try await performRequest(simple: true)
            if page == 1 && !fallback.isEmpty {
                CacheManager.shared.save(fallback, to: "news_cache.json")
            }
            return fallback
        } catch CryptoNewsError.badServerResponse(let code) where code == 429 {
            // Rate limited: prefer cache, otherwise use RSS fallback
            if let cached = self.loadFreshCache() {
                return cached
            }
            let rss = await RSSFetcher.fetch(limit: page == 1 ? defaultPageSize : 20)
            if page == 1 && !rss.isEmpty { CacheManager.shared.save(rss, to: "news_cache.json") }
            if !rss.isEmpty { return rss }
            throw CryptoNewsError.badServerResponse(statusCode: 429)
        } catch {
            // Any other error: try cache, then RSS fallback
            if let cached = self.loadFreshCache() {
                return Array(cached.prefix(page == 1 ? finalSize : cached.count))
            }
            let rss = await RSSFetcher.fetch(limit: page == 1 ? defaultPageSize : 20)
            if page == 1 && !rss.isEmpty { CacheManager.shared.save(rss, to: "news_cache.json") }
            if !rss.isEmpty { return rss }
            // Final safety: show seed on page 1 to avoid perpetual loading
            if page == 1 {
                let seed = StaticNewsSeed.sampleArticles()
                if !seed.isEmpty {
                    let limitedSeed = Array(seed.prefix(finalSize))
                    CacheManager.shared.save(limitedSeed, to: "news_cache.json")
                    return limitedSeed
                }
            }
            throw error
        }
    }
}

