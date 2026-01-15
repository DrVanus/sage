//  MarketSentimentProviders.swift
//  CryptoSage
//
//  Providers for Market Sentiment (Fear & Greed–style) with pluggable sources.
//  Add the following keys to your App/Info.plist (String):
//  - COINMARKETCAP_API_KEY
//  - CMC_SENTIMENT_URL   (required; endpoint returning a list of items)
//  - UNUSUALWHALES_API_KEY
//  - UNUSUALWHALES_SENTIMENT_URL (required; endpoint returning a list of items)
//
//  Expected JSON shape for custom endpoints is flexible. The adapters attempt to
//  map common key names to FearGreedData: value (0..100), classification string,
//  timestamp (seconds since epoch), and optional time_until_update.

import Foundation

// MARK: - Protocol
protocol SentimentProvider {
    var source: SentimentSource { get }
    func fetch(limit: Int, timeout: TimeInterval) async throws -> [FearGreedData]
}

enum SentimentProviderError: LocalizedError {
    case missingAPIKey(String)
    case missingEndpoint(String)
    case invalidResponse
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let name): return "Missing API key: \(name). Add it to Info.plist."
        case .missingEndpoint(let name): return "Missing endpoint: \(name). Add it to Info.plist."
        case .invalidResponse: return "Invalid response from server."
        case .decodingFailed(let reason): return "Failed to decode response: \(reason)"
        }
    }
}

// MARK: - Alternative.me Provider (native)
struct AlternativeMeProvider: SentimentProvider {
    let source: SentimentSource = .alternativeMe

    func fetch(limit: Int, timeout: TimeInterval) async throws -> [FearGreedData] {
        guard let url = URL(string: "https://api.alternative.me/fng/?limit=\(max(1, limit))") else {
            throw SentimentProviderError.invalidResponse
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        let (raw, _) = try await URLSession.shared.data(for: req)
        let decoded = try JSONDecoder().decode(FearGreedResponse.self, from: raw)
        return decoded.data
    }
}

// MARK: - CoinMarketCap Provider
// This adapter requires an endpoint that returns a list of items representing sentiment.
// Configure Info.plist:
//   COINMARKETCAP_API_KEY = <your key>
//   CMC_SENTIMENT_URL = https://pro-api.coinmarketcap.com/<your sentiment endpoint>
// The adapter tries to map common keys: value | score | index, classification | label,
// timestamp | time | updated_at (seconds since epoch or ISO8601).
struct CoinMarketCapProvider: SentimentProvider {
    let source: SentimentSource = .coinMarketCap

    private var apiKey: String {
        (Bundle.main.infoDictionary?["COINMARKETCAP_API_KEY"] as? String) ?? ""
    }
    private var endpoint: String? {
        Bundle.main.infoDictionary?["CMC_SENTIMENT_URL"] as? String
    }

    func fetch(limit: Int, timeout: TimeInterval) async throws -> [FearGreedData] {
        guard !apiKey.isEmpty else { throw SentimentProviderError.missingAPIKey("COINMARKETCAP_API_KEY") }
        guard let urlStr = endpoint, let url = URL(string: urlStr) else {
            throw SentimentProviderError.missingEndpoint("CMC_SENTIMENT_URL")
        }
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var q = comps?.queryItems ?? []
        q.append(URLQueryItem(name: "limit", value: String(max(1, limit))))
        comps?.queryItems = q
        guard let finalURL = comps?.url else { throw SentimentProviderError.invalidResponse }

        var req = URLRequest(url: finalURL)
        req.timeoutInterval = timeout
        req.setValue(apiKey, forHTTPHeaderField: "X-CMC_PRO_API_KEY")
        let (data, _) = try await URLSession.shared.data(for: req)
        if let list = try decodeFlexibleList(data: data) { return list }
        throw SentimentProviderError.decodingFailed("Unexpected JSON for CMC endpoint")
    }
}

// MARK: - Unusual Whales Provider
// Configure Info.plist:
//   UNUSUALWHALES_API_KEY = <your key>
//   UNUSUALWHALES_SENTIMENT_URL = https://api.unusualwhales.com/<your sentiment endpoint>
struct UnusualWhalesProvider: SentimentProvider {
    let source: SentimentSource = .unusualWhales

    private var apiKey: String {
        (Bundle.main.infoDictionary?["UNUSUALWHALES_API_KEY"] as? String) ?? ""
    }
    private var endpoint: String? {
        Bundle.main.infoDictionary?["UNUSUALWHALES_SENTIMENT_URL"] as? String
    }

    func fetch(limit: Int, timeout: TimeInterval) async throws -> [FearGreedData] {
        guard !apiKey.isEmpty else { throw SentimentProviderError.missingAPIKey("UNUSUALWHALES_API_KEY") }
        guard let urlStr = endpoint, let url = URL(string: urlStr) else {
            throw SentimentProviderError.missingEndpoint("UNUSUALWHALES_SENTIMENT_URL")
        }
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var q = comps?.queryItems ?? []
        q.append(URLQueryItem(name: "limit", value: String(max(1, limit))))
        comps?.queryItems = q
        guard let finalURL = comps?.url else { throw SentimentProviderError.invalidResponse }

        var req = URLRequest(url: finalURL)
        req.timeoutInterval = timeout
        req.setValue(apiKey, forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        if let list = try decodeFlexibleList(data: data) { return list }
        throw SentimentProviderError.decodingFailed("Unexpected JSON for Unusual Whales endpoint")
    }
}

// MARK: - Flexible decoding helpers
/// Tries to decode a variety of shapes into [FearGreedData]. Supports:
/// - { "data": [ ... ] }
/// - [ ... ]
/// where each item can be either:
///   { value: Int|Double, value_classification|classification|label: String, timestamp|time|updated_at: Int|String }
private func decodeFlexibleList(data: Data) throws -> [FearGreedData]? {
    // Try direct decode of our native model first
    if let native = try? JSONDecoder().decode(FearGreedResponse.self, from: data) {
        return native.data
    }
    // Generic JSON parsing
    let json = try JSONSerialization.jsonObject(with: data, options: [])
    let array: [Any]
    if let dict = json as? [String: Any], let d = dict["data"] as? [Any] {
        array = d
    } else if let a = json as? [Any] { array = a } else { return nil }

    var items: [FearGreedData] = []
    for el in array {
        guard let obj = el as? [String: Any] else { continue }
        // Value (0..100)
        let value: String? = {
            if let v = obj["value"] as? Int { return String(v) }
            if let v = obj["value"] as? Double { return String(Int(v.rounded())) }
            if let v = obj["score"] as? Double { return String(Int((v <= 1 ? v * 100 : v).rounded())) }
            if let v = obj["index"] as? Double { return String(Int(v.rounded())) }
            if let v = obj["sentiment_score"] as? Double { return String(Int((v <= 1 ? v * 100 : v).rounded())) }
            return nil
        }()
        // Classification
        let cls: String? = (obj["value_classification"] as? String)
            ?? (obj["classification"] as? String)
            ?? (obj["label"] as? String)
        // Timestamp
        let tsStr: String? = {
            if let t = obj["timestamp"] as? Int { return String(t) }
            if let t = obj["timestamp"] as? Double { return String(Int(t)) }
            if let t = obj["time"] as? Int { return String(t) }
            if let t = obj["updated_at"] as? Int { return String(t) }
            if let s = obj["time"] as? String { return String(parseEpochOrISO8601(s)) }
            if let s = obj["updated_at"] as? String { return String(parseEpochOrISO8601(s)) }
            return nil
        }()
        if let value = value, let cls = cls, let ts = tsStr {
            let item = FearGreedData(value: value, value_classification: cls.lowercased(), timestamp: ts, time_until_update: nil)
            items.append(item)
        }
    }
    return items.isEmpty ? nil : items
}

private func parseEpochOrISO8601(_ s: String) -> Int {
    if let i = Int(s) { return i }
    let fmt = ISO8601DateFormatter()
    if let d = fmt.date(from: s) { return Int(d.timeIntervalSince1970) }
    return Int(Date().timeIntervalSince1970)
}
