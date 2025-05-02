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

// MARK: – NewsAPI response wrapper
private struct CryptoNewsResponse: Codable {
    let status: String
    let totalResults: Int
    let articles: [CryptoNewsArticle]
}

final class CryptoNewsFeedService {
    // ← your NewsAPI key
    private let apiKey = "fe1702f65ad54c4aa51b209b54f8ba3f"
    private let baseURL = URL(string: "https://newsapi.org/v2/top-headlines")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Async fetch for preview news (first page, limited items)
    @MainActor
    func fetchPreviewNews() async throws -> [CryptoNewsArticle] {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: "crypto"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "pageSize", value: "3"),
            URLQueryItem(name: "page", value: "1")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(CryptoNewsResponse.self, from: data)
        return decoded.articles
    }

    /// Async fetch for paginated news (all pages)
    @MainActor
    func fetchNews(page: Int) async throws -> [CryptoNewsArticle] {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: "crypto"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "pageSize", value: "20"),
            URLQueryItem(name: "page", value: "\(page)")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(CryptoNewsResponse.self, from: data)
        return decoded.articles
    }

    /// Combine publisher version
    func fetchNewsPublisher() -> AnyPublisher<[CryptoNewsArticle], Error> {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "q",          value: "crypto"),
            .init(name: "language",   value: "en"),
            .init(name: "pageSize",   value: "20")
        ]
        var request = URLRequest(url: components.url!)
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
            .map(\.articles)
            .eraseToAnyPublisher()
    }

    /// Completion handler fallback
    func fetchNews(completion: @escaping (Result<[CryptoNewsArticle], Error>) -> Void) {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "q",          value: "crypto"),
            .init(name: "language",   value: "en"),
            .init(name: "pageSize",   value: "20")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")

        session.dataTask(with: request) { data, resp, err in
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
                DispatchQueue.main.async { completion(.success(wrapped.articles)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }
}
