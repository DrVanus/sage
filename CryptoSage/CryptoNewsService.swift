//
//  NewsAPIResponse 2.swift
//  CryptoSage
//
//  Created by DM on 5/26/25.
//


//
// CryptoNewsService.swift
// CryptoSage
//


import Foundation

/// Errors surfaceable by CryptoNewsService
enum CryptoNewsError: Error {
    case timeout
    case badServerResponse(statusCode: Int)
    case cancelled
    case decodingFailed(Error)
    case networkError(URLError)
    case unknown(Error)
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

// MARK: - CryptoNews Service
actor CryptoNewsService {
    private static let cachedSession: URLSession = {
        let config = URLSessionConfiguration.default
        // 50 MB RAM, 200 MB disk cache
        config.urlCache = URLCache(memoryCapacity: 50 * 1024 * 1024,
                                   diskCapacity: 200 * 1024 * 1024,
                                   diskPath: "CryptoNewsCache")
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()
    private let apiKey = "46517a8f35a34c0e88e7c2cc31f63fac"
    
    /// Default number of articles per page
    private let defaultPageSize = 20

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
                    throw CryptoNewsError.badServerResponse(statusCode: http.statusCode)
                }
                return data
            } catch {
                lastError = error
                if let urlError = error as? URLError {
                    switch urlError.code {
                    case .timedOut:
                        throw CryptoNewsError.timeout
                    case .cancelled:
                        throw CryptoNewsError.cancelled
                    default:
                        throw CryptoNewsError.networkError(urlError)
                    }
                }
                // Exponential backoff: 0.5s, 1s, 2s, etc.
                let delay = UInt64(pow(2.0, Double(attempt)) * 500_000_000)
                try? await Task.sleep(nanoseconds: delay)
            }
        }
        if let urlError = lastError as? URLError {
            throw CryptoNewsError.networkError(urlError)
        } else {
            throw CryptoNewsError.unknown(lastError!)
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
    func fetchNews(query: String, page: Int, pageSize: Int? = nil) async throws -> [CryptoNewsArticle] {
        let finalSize = pageSize ?? defaultPageSize
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard var components = URLComponents(string: "https://newsapi.org/v2/everything") else {
            return []
        }
        components.queryItems = [
            .init(name: "q", value: encodedQuery),
            .init(name: "pageSize", value: "\(finalSize)"),
            .init(name: "page",     value: "\(page)"),
            .init(name: "sortBy",   value: "publishedAt")
        ]
        guard let url = components.url else {
            print("🗞️ CryptoNewsService: failed to construct URL from components")
            return []
        }
        // Build a request with a timeout
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        request.timeoutInterval = 15

        let data = try await fetchDataWithRetry(request, retries: 3)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let apiResponse = try decoder.decode(NewsAPIResponse.self, from: data)
        return apiResponse.articles.map { article in
            CryptoNewsArticle(
                title: article.title,
                description: article.description,
                url: article.url,
                urlToImage: article.urlToImage,
                sourceName: article.source.name ?? "Unknown Source",
                publishedAt: article.publishedAt
            )
        }
    }
}
