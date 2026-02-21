//
//  GeminiExchangeAdapter.swift
//  CryptoSage
//
//  Gemini API exchange adapter for market data.
//

import Foundation

// MARK: - Gemini Exchange Adapter

public final class GeminiExchangeAdapter: ExchangeAdapter {
    public var id: String { "gemini" }
    public var name: String { "Gemini" }
    
    private let session: URLSession
    private let baseURL: URL
    private let v2URL: URL
    
    // MARK: - Initialization
    
    public init(session: URLSession = .shared) {
        self.session = session
        self.baseURL = URL(string: "https://api.gemini.com/v1")!
        self.v2URL = URL(string: "https://api.gemini.com/v2")!
    }
    
    // MARK: - ExchangeAdapter Protocol
    
    public func supportedPairs(for baseSymbol: String) async -> [MMEMarketPair] {
        let base = baseSymbol.uppercased()
        // Gemini primarily uses USD pairs
        let quotes = ["USD", "USDT"]
        return quotes.map { MMEMarketPair(exchangeID: id, baseSymbol: base, quoteSymbol: $0) }
    }
    
    public func fetchTickers(for pairs: [MMEMarketPair]) async throws -> [MMETicker] {
        guard !pairs.isEmpty else { return [] }
        
        var results: [MMETicker] = []
        
        // Gemini requires individual ticker requests
        // Use concurrent fetching with rate limiting
        let batchSize = 5
        var index = 0
        
        while index < pairs.count {
            try Task.checkCancellation()
            
            let end = min(index + batchSize, pairs.count)
            let batch = Array(pairs[index..<end])
            
            let batchResults: [MMETicker] = await withTaskGroup(of: MMETicker?.self) { group in
                for pair in batch {
                    group.addTask {
                        do {
                            return try await self.fetchTicker(for: pair)
                        } catch {
                            return nil
                        }
                    }
                }
                
                var tickers: [MMETicker] = []
                for await result in group {
                    if let ticker = result {
                        tickers.append(ticker)
                    }
                }
                return tickers
            }
            
            results.append(contentsOf: batchResults)
            index = end
            
            // Rate limit pause
            if index < pairs.count {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        }
        
        return results
    }
    
    public func fetchCandles(pair: MMEMarketPair, interval: MMECandleInterval, limit: Int) async throws -> [MMECandle] {
        // Gemini format: btcusd (lowercase, no separator)
        let symbol = (pair.baseSymbol + pair.quoteSymbol).lowercased()
        let timeFrame = mapInterval(interval)
        
        let url = v2URL.appendingPathComponent("candles/\(symbol)/\(timeFrame)")
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw GeminiError.invalidResponse
        }
        
        let candles = try JSONDecoder().decode([[Double]].self, from: data)
        
        return candles.prefix(limit).compactMap { candle -> MMECandle? in
            // Gemini candle format: [timestamp, open, high, low, close, volume]
            guard candle.count >= 6 else { return nil }
            
            return MMECandle(
                pair: pair,
                interval: interval,
                open: candle[1],
                high: candle[2],
                low: candle[3],
                close: candle[4],
                volume: candle[5],
                ts: candle[0] / 1000 // Gemini uses milliseconds
            )
        }.reversed() // Gemini returns newest first
    }
    
    // MARK: - Private Methods
    
    private func fetchTicker(for pair: MMEMarketPair) async throws -> MMETicker {
        // Gemini format: btcusd (lowercase, no separator)
        let symbol = (pair.baseSymbol + pair.quoteSymbol).lowercased()
        let url = baseURL.appendingPathComponent("pubticker/\(symbol)")
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw GeminiError.invalidResponse
        }
        
        let ticker = try JSONDecoder().decode(GeminiTicker.self, from: data)
        
        let timestamp = Double(ticker.volume.timestamp) ?? Date().timeIntervalSince1970 * 1000
        
        return MMETicker(
            pair: pair,
            last: Double(ticker.last) ?? 0,
            bid: Double(ticker.bid) ?? 0,
            ask: Double(ticker.ask) ?? 0,
            volume24hBase: Double(ticker.volume.value) ?? 0,
            ts: timestamp / 1000
        )
    }
    
    private func mapInterval(_ interval: MMECandleInterval) -> String {
        switch interval {
        case .m1: return "1m"
        case .m5: return "5m"
        case .m15: return "15m"
        case .h1: return "1hr"
        case .h4: return "4hr"
        case .d1: return "1day"
        }
    }
}

// MARK: - Gemini Response Models

private struct GeminiTicker: Codable {
    let bid: String
    let ask: String
    let last: String
    let volume: GeminiVolume
    
    struct GeminiVolume: Codable {
        let value: String
        let timestamp: String
        
        enum CodingKeys: String, CodingKey {
            case value = "BTC" // This varies by pair, but we'll handle it
            case timestamp
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicCodingKey.self)
            
            // Find the volume value (it's named after the base currency)
            var foundValue: String?
            var foundTimestamp: String?
            
            for key in container.allKeys {
                if key.stringValue == "timestamp" {
                    foundTimestamp = try container.decode(String.self, forKey: key)
                } else if key.stringValue != "USD" && key.stringValue != "USDT" {
                    // This is likely the base currency volume
                    if let val = try? container.decode(String.self, forKey: key) {
                        foundValue = val
                    }
                }
            }
            
            self.value = foundValue ?? "0"
            self.timestamp = foundTimestamp ?? String(Date().timeIntervalSince1970 * 1000)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(value, forKey: .value)
            try container.encode(timestamp, forKey: .timestamp)
        }
    }
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    
    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }
    
    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

// MARK: - Gemini Errors

public enum GeminiError: LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(String)
    case decodingError
    case rateLimited
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Gemini API URL"
        case .invalidResponse:
            return "Invalid response from Gemini API"
        case .apiError(let message):
            return "Gemini API error: \(message)"
        case .decodingError:
            return "Failed to decode Gemini response"
        case .rateLimited:
            return "Gemini API rate limit exceeded"
        }
    }
}
