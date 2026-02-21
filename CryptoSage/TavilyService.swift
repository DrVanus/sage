//
//  TavilyService.swift
//  CryptoSage
//
//  Service for web search using Tavily API - enables AI to research topics on the internet.
//  Tavily is designed specifically for AI/LLM integration with structured, summarized results.
//

import Foundation
import os.log

private let tavilyLog = OSLog(subsystem: "com.cryptosage.ai", category: "tavily")

// MARK: - Tavily API Models

/// Tavily search request parameters
struct TavilySearchRequest: Codable {
    let apiKey: String
    let query: String
    let searchDepth: String
    let includeAnswer: Bool
    let includeRawContent: Bool
    let maxResults: Int
    let includeDomains: [String]?
    let excludeDomains: [String]?
    
    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
        case query
        case searchDepth = "search_depth"
        case includeAnswer = "include_answer"
        case includeRawContent = "include_raw_content"
        case maxResults = "max_results"
        case includeDomains = "include_domains"
        case excludeDomains = "exclude_domains"
    }
    
    init(
        apiKey: String,
        query: String,
        searchDepth: String = "basic",
        includeAnswer: Bool = true,
        includeRawContent: Bool = false,
        maxResults: Int = 5,
        includeDomains: [String]? = nil,
        excludeDomains: [String]? = nil
    ) {
        self.apiKey = apiKey
        self.query = query
        self.searchDepth = searchDepth
        self.includeAnswer = includeAnswer
        self.includeRawContent = includeRawContent
        self.maxResults = maxResults
        self.includeDomains = includeDomains
        self.excludeDomains = excludeDomains
    }
}

/// Individual search result from Tavily
struct TavilySearchResultItem: Codable {
    let title: String
    let url: String
    let content: String
    let score: Double?
    let publishedDate: String?
    
    enum CodingKeys: String, CodingKey {
        case title
        case url
        case content
        case score
        case publishedDate = "published_date"
    }
}

/// Complete Tavily search response
struct TavilySearchResponse: Codable {
    let query: String
    let answer: String?
    let results: [TavilySearchResultItem]
    let responseTime: Double?
    
    enum CodingKeys: String, CodingKey {
        case query
        case answer
        case results
        case responseTime = "response_time"
    }
}

/// Errors that can occur during Tavily API calls
enum TavilyError: Error, LocalizedError {
    case noAPIKey
    case invalidAPIKey
    case rateLimitExceeded
    case networkError(Error)
    case decodingError(Error)
    case serverError(Int, String?)
    case emptyResults
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "Tavily API key not configured. Add it in Settings > AI Settings."
        case .invalidAPIKey:
            return "Invalid Tavily API key. Please check your key in Settings."
        case .rateLimitExceeded:
            return "Search rate limit exceeded. Please try again later."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to parse search results: \(error.localizedDescription)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message ?? "Unknown error")"
        case .emptyResults:
            return "No results found for your search."
        }
    }
}

// MARK: - Tavily Service

/// Service for performing web searches using Tavily API
final class TavilyService {
    static let shared = TavilyService()
    
    private let baseURL = "https://api.tavily.com"
    private let requestTimeout: TimeInterval = 15
    
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = requestTimeout * 2
        return URLSession(configuration: config)
    }()
    
    private init() {}
    
    // MARK: - Public API
    
    /// Check if Tavily API is available (key configured)
    var isAvailable: Bool {
        APIConfig.hasValidTavilyKey
    }
    
    /// Perform a web search using Tavily API
    /// - Parameters:
    ///   - query: The search query
    ///   - maxResults: Maximum number of results (default 5, max 10)
    ///   - searchDepth: "basic" for faster results, "advanced" for more thorough search
    /// - Returns: TavilySearchResponse with answer and results
    func search(
        query: String,
        maxResults: Int = 5,
        searchDepth: String = "basic"
    ) async throws -> TavilySearchResponse {
        let apiKey = APIConfig.tavilyKey
        guard !apiKey.isEmpty else {
            throw TavilyError.noAPIKey
        }
        
        let url = URL(string: "\(baseURL)/search")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = requestTimeout
        
        // Build request body
        let searchRequest = TavilySearchRequest(
            apiKey: apiKey,
            query: query,
            searchDepth: searchDepth,
            includeAnswer: true,
            includeRawContent: false,
            maxResults: min(maxResults, 10)
        )
        
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(searchRequest)
        
        os_log("Searching Tavily: %{public}@", log: tavilyLog, type: .debug, query)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw TavilyError.networkError(URLError(.badServerResponse))
            }
            
            // Handle error status codes
            switch httpResponse.statusCode {
            case 200:
                break // Success
            case 401:
                throw TavilyError.invalidAPIKey
            case 429:
                throw TavilyError.rateLimitExceeded
            default:
                let errorMessage = String(data: data, encoding: .utf8)
                throw TavilyError.serverError(httpResponse.statusCode, errorMessage)
            }
            
            let decoder = JSONDecoder()
            let searchResponse = try decoder.decode(TavilySearchResponse.self, from: data)
            
            os_log("Tavily returned %d results", log: tavilyLog, type: .debug, searchResponse.results.count)
            
            if searchResponse.results.isEmpty && searchResponse.answer == nil {
                throw TavilyError.emptyResults
            }
            
            return searchResponse
            
        } catch let error as TavilyError {
            throw error
        } catch let error as DecodingError {
            os_log("Tavily decoding error: %{public}@", log: tavilyLog, type: .error, error.localizedDescription)
            throw TavilyError.decodingError(error)
        } catch {
            os_log("Tavily network error: %{public}@", log: tavilyLog, type: .error, error.localizedDescription)
            throw TavilyError.networkError(error)
        }
    }
    
    /// Perform a crypto-focused web search
    /// Automatically adds crypto-related domains for better results
    func searchCrypto(query: String, maxResults: Int = 5) async throws -> TavilySearchResponse {
        // Enhance query with crypto context if not already present
        let cryptoTerms = ["crypto", "bitcoin", "btc", "ethereum", "eth", "blockchain", "defi", "nft"]
        let lowerQuery = query.lowercased()
        let hasCryptoTerm = cryptoTerms.contains { lowerQuery.contains($0) }
        
        let enhancedQuery = hasCryptoTerm ? query : "\(query) cryptocurrency"
        
        return try await search(query: enhancedQuery, maxResults: maxResults)
    }
    
    /// Format search results for AI consumption
    /// Returns a string that can be used as context for the AI
    func formatResultsForAI(_ response: TavilySearchResponse) -> String {
        var output = ""
        
        // Include the AI-generated answer if available
        if let answer = response.answer, !answer.isEmpty {
            output += "Summary:\n\(answer)\n\n"
        }
        
        // Include individual results
        if !response.results.isEmpty {
            output += "Sources:\n"
            for (index, result) in response.results.enumerated() {
                output += "\n[\(index + 1)] \(result.title)\n"
                output += "URL: \(result.url)\n"
                output += "\(result.content)\n"
                if let date = result.publishedDate {
                    output += "Published: \(date)\n"
                }
            }
        }
        
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
