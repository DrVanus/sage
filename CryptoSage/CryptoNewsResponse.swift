//
//  CryptoNewsResponse.swift
//  CryptoSage
//
//  Created by DM on 5/26/25.
//

//
//  CryptoNewsFeedService.swift
//  CryptoSage
//

import Foundation
import Combine

// Logging now handled via DebugLog utility

// MARK: – NewsAPI response wrapper
private struct CryptoNewsResponse: Codable {
    let status: String
    let totalResults: Int
    let articles: [CryptoNewsArticle]
}

final class CryptoNewsFeedService {
    /// NewsAPI key for top-headlines endpoint
    /// Free tier: 100 requests/day, articles up to 1 month old
    /// SECURITY FIX: Use centralized APIConfig with Keychain storage instead of hardcoded key
    private var apiKey: String { APIConfig.newsAPIKey }
    private let baseURL = URL(string: "https://newsapi.org/v2/top-headlines")!
    private let session: URLSession
    
    // NOTE: Domain lists moved to NewsQualityFilter.swift (single source of truth)
    
    /// Filter articles using centralized NewsQualityFilter
    private func filterArticles(_ articles: [CryptoNewsArticle]) -> [CryptoNewsArticle] {
        return articles.filter { article in
            NewsQualityFilter.passesQualityCheck(
                url: article.url,
                title: article.title,
                description: article.description,
                sourceName: article.sourceName
            )
        }
    }

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Async fetch for preview news (first page, limited items)
    @MainActor
    func fetchPreviewNews() async throws -> [CryptoNewsArticle] {
        // SAFETY FIX: Use guard let instead of force unwraps
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: "crypto"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "pageSize", value: "3"),
            URLQueryItem(name: "page", value: "1")
        ]
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        
        DebugLog.log("FeedService", "Fetching preview news")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            DebugLog.log("FeedService", "No HTTP response")
            throw URLError(.badServerResponse)
        }
        
        if http.statusCode == 429 {
            DebugLog.log("FeedService", "Rate limited (429)")
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            DebugLog.log("FeedService", "Auth error (\(http.statusCode)) - API key may be invalid")
            throw URLError(.userAuthenticationRequired)
        }
        
        guard 200..<300 ~= http.statusCode else {
            DebugLog.log("FeedService", "HTTP \(http.statusCode)")
            throw URLError(.badServerResponse)
        }
        
        let decoded = try JSONDecoder().decode(CryptoNewsResponse.self, from: data)
        let filtered = filterArticles(decoded.articles)
        DebugLog.log("FeedService", "Received \(decoded.articles.count) preview articles, \(filtered.count) after quality filter")
        return filtered
    }

    /// Async fetch for paginated news (all pages)
    @MainActor
    func fetchNews(page: Int) async throws -> [CryptoNewsArticle] {
        // SAFETY FIX: Use guard let instead of force unwraps
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: "crypto"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "pageSize", value: "20"),
            URLQueryItem(name: "page", value: "\(page)")
        ]
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        
        DebugLog.log("FeedService", "Fetching page \(page)")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            DebugLog.log("FeedService", "No HTTP response")
            throw URLError(.badServerResponse)
        }
        
        if http.statusCode == 429 {
            DebugLog.log("FeedService", "Rate limited (429)")
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            DebugLog.log("FeedService", "Auth error (\(http.statusCode))")
            throw URLError(.userAuthenticationRequired)
        }
        
        guard 200..<300 ~= http.statusCode else {
            DebugLog.log("FeedService", "HTTP \(http.statusCode)")
            throw URLError(.badServerResponse)
        }
        
        let decoded = try JSONDecoder().decode(CryptoNewsResponse.self, from: data)
        let filtered = filterArticles(decoded.articles)
        DebugLog.log("FeedService", "Received \(decoded.articles.count) articles for page \(page), \(filtered.count) after quality filter")
        return filtered
    }

    /// Combine publisher version
    func fetchNewsPublisher() -> AnyPublisher<[CryptoNewsArticle], Error> {
        // SAFETY FIX: Use guard let instead of force unwraps
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
        }
        components.queryItems = [
            .init(name: "q",          value: "crypto"),
            .init(name: "language",   value: "en"),
            .init(name: "pageSize",   value: "20")
        ]
        guard let url = components.url else {
            return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
        }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")

        return session
            .dataTaskPublisher(for: request)
            .tryMap { data, resp in
                guard let http = resp as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                if http.statusCode == 401 {
                    throw NSError(domain: "NewsAPI", code: 401, userInfo: [NSLocalizedDescriptionKey: "Unauthorized – please check API key"])
                }
                guard 200..<300 ~= http.statusCode else {
                    throw URLError(.badServerResponse)
                }
                return data
            }
            .decode(type: CryptoNewsResponse.self, decoder: JSONDecoder())
            .map { [weak self] response in
                self?.filterArticles(response.articles) ?? response.articles
            }
            .eraseToAnyPublisher()
    }

    /// Completion handler fallback
    func fetchNews(completion: @escaping (Result<[CryptoNewsArticle], Error>) -> Void) {
        // SAFETY FIX: Use guard let instead of force unwraps
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            completion(.failure(URLError(.badURL)))
            return
        }
        components.queryItems = [
            .init(name: "q",          value: "crypto"),
            .init(name: "language",   value: "en"),
            .init(name: "pageSize",   value: "20")
        ]
        guard let url = components.url else {
            completion(.failure(URLError(.badURL)))
            return
        }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")

        session.dataTask(with: request) { [weak self] data, resp, err in
            if let err = err {
                DispatchQueue.main.async { completion(.failure(err)) }
                return
            }
            if let http = resp as? HTTPURLResponse, http.statusCode == 401 {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "NewsAPI", code: 401, userInfo: [NSLocalizedDescriptionKey: "Unauthorized – please check API key"])))
                }
                return
            }
            guard let http = resp as? HTTPURLResponse,
                  200..<300 ~= http.statusCode
            else {
                DispatchQueue.main.async { completion(.failure(URLError(.badServerResponse))) }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async { completion(.failure(URLError(.unknown))) }
                return
            }
            do {
                let wrapped = try JSONDecoder().decode(CryptoNewsResponse.self, from: data)
                let filtered = self?.filterArticles(wrapped.articles) ?? wrapped.articles
                DispatchQueue.main.async { completion(.success(filtered)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }
}
