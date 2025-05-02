//
//  APIConfig.swift
//  CSAI1
//
//  Created by DM on 3/24/25.
//
//  IMPORTANT: Do not commit this file with your actual API key to your public repository.
//

import Foundation

/// Centralized API configuration and shared URLSession.
final class APIConfig {
    /// Singleton instance for shared use.
    static let shared = APIConfig()

    /// Shared URLSession for all network calls.
    let session: URLSession

    /// OpenAI API key. Replace with your actual key.
    static let openAIKey = "keygoeshere"
    
    /// NewsAPI.org key. Replace with your actual NewsAPI key.
    static let newsAPIKey = "YOUR_NEWSAPI_KEY"

    /// Base URLs for cryptocurrency data.
    static let coingeckoBaseURL = "https://api.coingecko.com/api/v3"
    static let coinpaprikaBaseURL = "https://api.coinpaprika.com/api/v1"
    static let coinbaseBaseURL = "https://api.coinbase.com/api/v2"
    
    /// Base URL for NewsAPI.org top headlines.
    static let newsBaseURL = "https://newsapi.org/v2"

    private init() {
        session = URLSession(configuration: .default)
    }
}
