//
//  AIInsight.swift
//  CryptoSage
//
//  Created by DM on 5/28/25.
//


import Foundation

/// Represents a single AI‐generated insight text with its timestamp
struct AIInsight: Decodable {
  let text: String
  let timestamp: Date
}

/// Service responsible for fetching AI‐generated portfolio insights
final class AIInsightService {
  static let shared = AIInsightService()
  private init() {}

  /// Sends the portfolio to your AI endpoint and returns an insight
  func fetchInsight<T: Encodable>(for portfolio: T) async throws -> AIInsight {
    guard let url = URL(string: "https://api.your‐ai‐endpoint.com/insight") else {
      throw URLError(.badURL)
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    request.httpBody = try encoder.encode(portfolio)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let code = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) else {
      throw URLError(.badServerResponse)
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(AIInsight.self, from: data)
  }
}