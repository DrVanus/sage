//
//  CryptoCompareNewsService.swift
//  CryptoSage
//
//  Free news API that works from mobile apps without restrictions.
//

import Foundation

// Logging now handled via DebugLog utility

// MARK: - CryptoCompare API Response Models

private struct CCNewsResponse: Codable {
    let responseType: Int
    let message: String
    let data: [CCNewsItem]
    
    private enum CodingKeys: String, CodingKey {
        case responseType = "Type"
        case message = "Message"
        case data = "Data"
    }
}

private struct CCNewsItem: Codable {
    let id: String
    let published_on: Int
    let imageurl: String?
    let title: String
    let url: String
    let source: String
    let body: String?
    let categories: String?
    let source_info: CCSourceInfo?
    
    private enum CodingKeys: String, CodingKey {
        case id
        case published_on
        case imageurl
        case title
        case url
        case source
        case body
        case categories
        case source_info
    }
}

private struct CCSourceInfo: Codable {
    let name: String?
    let img: String?
}

// MARK: - CryptoCompare News Service

/// Service that fetches crypto news from CryptoCompare's free API.
/// This API works from mobile apps without API key restrictions.
actor CryptoCompareNewsService {
    static let shared = CryptoCompareNewsService()
    
    private let baseURL = "https://min-api.cryptocompare.com/data/v2/news/"
    
    /// Session configured for fast news fetching
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        config.waitsForConnectivity = true
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }()
    
    /// Track failures for backoff
    private var consecutiveFailures: Int = 0
    private var lastFailureTime: Date?
    private let maxFailures = 5
    private let backoffDuration: TimeInterval = 120 // 2 minutes
    
    private var shouldSkip: Bool {
        if consecutiveFailures >= maxFailures {
            if let lastFailure = lastFailureTime,
               Date().timeIntervalSince(lastFailure) < backoffDuration {
                return true
            }
            // Reset after backoff
            consecutiveFailures = 0
            lastFailureTime = nil
        }
        return false
    }
    
    private func recordSuccess() {
        consecutiveFailures = 0
        lastFailureTime = nil
    }
    
    private func recordFailure() {
        consecutiveFailures += 1
        lastFailureTime = Date()
    }
    
    /// Fetch news from CryptoCompare API
    /// - Parameters:
    ///   - categories: Optional category filter (e.g., "BTC", "ETH", "Trading", "Technology")
    ///   - limit: Maximum number of articles to return (API max is 50)
    /// - Returns: Array of CryptoNewsArticle
    func fetchNews(categories: String? = nil, limit: Int = 50) async -> [CryptoNewsArticle] {
        guard !shouldSkip else {
            DebugLog.log("CryptoCompare", "Skipping due to repeated failures")
            return []
        }
        
        // Build URL
        var urlString = baseURL + "?lang=EN"
        if let cats = categories, !cats.isEmpty {
            urlString += "&categories=\(cats)"
        }
        
        guard let url = URL(string: urlString) else {
            DebugLog.log("CryptoCompare", "Invalid URL")
            return []
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        
        DebugLog.log("CryptoCompare", "Fetching news...")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let http = response as? HTTPURLResponse else {
                DebugLog.log("CryptoCompare", "No HTTP response")
                recordFailure()
                return []
            }
            
            guard (200..<300).contains(http.statusCode) else {
                DebugLog.log("CryptoCompare", "HTTP \(http.statusCode)")
                recordFailure()
                return []
            }
            
            // Decode response
            let decoder = JSONDecoder()
            let ccResponse = try decoder.decode(CCNewsResponse.self, from: data)
            
            // Map to CryptoNewsArticle
            let articles = ccResponse.data.prefix(limit).compactMap { item -> CryptoNewsArticle? in
                guard let articleURL = URL(string: item.url) else { return nil }
                
                // Parse image URL
                var imageURL: URL? = nil
                if let imgStr = item.imageurl, !imgStr.isEmpty {
                    // Handle protocol-relative URLs
                    var imgPath = imgStr
                    if imgPath.hasPrefix("//") {
                        imgPath = "https:" + imgPath
                    }
                    imageURL = URL(string: imgPath)
                    // Upgrade HTTP to HTTPS
                    if imageURL?.scheme?.lowercased() == "http" {
                        var comps = URLComponents(url: imageURL!, resolvingAgainstBaseURL: false)
                        comps?.scheme = "https"
                        imageURL = comps?.url
                    }
                }
                
                // Convert Unix timestamp to Date
                let publishedDate = Date(timeIntervalSince1970: TimeInterval(item.published_on))
                
                // Use source_info.name if available, otherwise fallback to source
                let sourceName = item.source_info?.name ?? item.source
                
                // Use body as description if available
                let description = item.body?.prefix(500).description
                
                return CryptoNewsArticle(
                    title: item.title,
                    description: description,
                    url: articleURL,
                    urlToImage: imageURL,
                    sourceName: sourceName,
                    publishedAt: publishedDate
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
            
            recordSuccess()
            DebugLog.log("CryptoCompare", "Fetched \(articles.count) articles, \(qualityFiltered.count) after quality filter")
            return qualityFiltered
            
        } catch {
            DebugLog.log("CryptoCompare", "Error - \(error.localizedDescription)")
            recordFailure()
            return []
        }
    }
    
    /// Fetch news filtered by category query
    /// Maps NewsCategory queries to CryptoCompare categories
    func fetchNews(query: String, limit: Int = 50) async -> [CryptoNewsArticle] {
        // Map common queries to CryptoCompare categories
        let categoryMap: [String: String] = [
            "bitcoin": "BTC",
            "btc": "BTC",
            "ethereum": "ETH",
            "eth": "ETH",
            "solana": "SOL",
            "defi": "Trading",
            "nft": "Blockchain",
            "nfts": "Blockchain",
            "trading": "Trading",
            "altcoins": "Altcoin",
            "altcoin": "Altcoin",
            "crypto": "", // All categories
            "layer 2": "Blockchain",
            "l2": "Blockchain",
            "macro": "Market"
        ]
        
        let lowerQuery = query.lowercased()
        let category = categoryMap[lowerQuery] ?? ""
        
        return await fetchNews(categories: category.isEmpty ? nil : category, limit: limit)
    }
}
