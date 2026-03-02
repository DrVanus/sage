//
//  MEXCExchangeAdapter.swift
//  CryptoSage
//
//  MEXC V3 API exchange adapter for market data.
//  API is similar to Binance V3.
//

import Foundation

// MARK: - MEXC Exchange Adapter

public final class MEXCExchangeAdapter: ExchangeAdapter {
    public var id: String { "mexc" }
    public var name: String { "MEXC" }
    
    private let session: URLSession
    private let baseURL: URL
    
    // MARK: - Initialization
    
    public init(session: URLSession = .shared) {
        self.session = session
        self.baseURL = URL(string: "https://api.mexc.com/api/v3")!
    }
    
    // MARK: - ExchangeAdapter Protocol
    
    public func supportedPairs(for baseSymbol: String) async -> [MMEMarketPair] {
        let base = baseSymbol.uppercased()
        let quotes = ["USDT", "USDC", "USD"]
        return quotes.map { MMEMarketPair(exchangeID: id, baseSymbol: base, quoteSymbol: $0) }
    }
    
    public func fetchTickers(for pairs: [MMEMarketPair]) async throws -> [MMETicker] {
        guard !pairs.isEmpty else { return [] }
        
        var results: [MMETicker] = []
        
        // MEXC supports batch ticker fetch
        let allTickers = try await fetchAllTickers()
        
        for pair in pairs {
            // MEXC format: BTCUSDT (no separator, uppercase)
            let symbol = pair.baseSymbol.uppercased() + pair.quoteSymbol.uppercased()
            
            if let ticker = allTickers[symbol] {
                results.append(MMETicker(
                    pair: pair,
                    last: ticker.last,
                    bid: ticker.bid,
                    ask: ticker.ask,
                    volume24hBase: ticker.volume,
                    ts: ticker.timestamp
                ))
            }
        }
        
        return results
    }
    
    public func fetchCandles(pair: MMEMarketPair, interval: MMECandleInterval, limit: Int) async throws -> [MMECandle] {
        let symbol = pair.baseSymbol.uppercased() + pair.quoteSymbol.uppercased()
        let mexcInterval = mapInterval(interval)
        
        guard var components = URLComponents(url: baseURL.appendingPathComponent("klines"), resolvingAgainstBaseURL: false) else { throw URLError(.badURL) }
        components.queryItems = [
            URLQueryItem(name: "symbol", value: symbol),
            URLQueryItem(name: "interval", value: mexcInterval),
            URLQueryItem(name: "limit", value: String(min(limit, 1000)))
        ]
        
        guard let url = components.url else {
            throw MEXCError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw MEXCError.invalidResponse
        }
        
        // MEXC klines format is similar to Binance
        let candles = try JSONDecoder().decode([MEXCKline].self, from: data)
        
        return candles.map { kline -> MMECandle in
            MMECandle(
                pair: pair,
                interval: interval,
                open: Double(kline.open) ?? 0,
                high: Double(kline.high) ?? 0,
                low: Double(kline.low) ?? 0,
                close: Double(kline.close) ?? 0,
                volume: Double(kline.volume) ?? 0,
                ts: Double(kline.openTime) / 1000
            )
        }
    }
    
    // MARK: - Private Methods
    
    private func fetchAllTickers() async throws -> [String: MEXCTickerData] {
        let url = baseURL.appendingPathComponent("ticker/24hr")
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw MEXCError.invalidResponse
        }
        
        let tickers = try JSONDecoder().decode([MEXCTicker].self, from: data)
        
        var tickerMap: [String: MEXCTickerData] = [:]
        let now = Date().timeIntervalSince1970
        
        for ticker in tickers {
            let tickerData = MEXCTickerData(
                last: Double(ticker.lastPrice) ?? 0,
                bid: Double(ticker.bidPrice) ?? 0,
                ask: Double(ticker.askPrice) ?? 0,
                volume: Double(ticker.volume) ?? 0,
                timestamp: now
            )
            tickerMap[ticker.symbol] = tickerData
        }
        
        return tickerMap
    }
    
    private func mapInterval(_ interval: MMECandleInterval) -> String {
        switch interval {
        case .m1: return "1m"
        case .m5: return "5m"
        case .m15: return "15m"
        case .h1: return "1h"
        case .h4: return "4h"
        case .d1: return "1d"
        }
    }
}

// MARK: - MEXC Response Models

private struct MEXCTicker: Codable {
    let symbol: String
    let lastPrice: String
    let bidPrice: String
    let askPrice: String
    let volume: String
    let quoteVolume: String?
    let highPrice: String?
    let lowPrice: String?
    let priceChangePercent: String?
    
    enum CodingKeys: String, CodingKey {
        case symbol
        case lastPrice
        case bidPrice
        case askPrice
        case volume
        case quoteVolume
        case highPrice
        case lowPrice
        case priceChangePercent
    }
}

private struct MEXCKline: Codable {
    let openTime: Int64
    let open: String
    let high: String
    let low: String
    let close: String
    let volume: String
    let closeTime: Int64?
    let quoteAssetVolume: String?
    let numberOfTrades: Int?
    
    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        openTime = try container.decode(Int64.self)
        open = try container.decode(String.self)
        high = try container.decode(String.self)
        low = try container.decode(String.self)
        close = try container.decode(String.self)
        volume = try container.decode(String.self)
        closeTime = try container.decodeIfPresent(Int64.self)
        quoteAssetVolume = try container.decodeIfPresent(String.self)
        numberOfTrades = try container.decodeIfPresent(Int.self)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(openTime)
        try container.encode(open)
        try container.encode(high)
        try container.encode(low)
        try container.encode(close)
        try container.encode(volume)
        try container.encode(closeTime ?? 0)
        try container.encode(quoteAssetVolume ?? "0")
        try container.encode(numberOfTrades ?? 0)
    }
}

private struct MEXCTickerData {
    let last: Double
    let bid: Double
    let ask: Double
    let volume: Double
    let timestamp: TimeInterval
}

// MARK: - MEXC Errors

public enum MEXCError: LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(String)
    case decodingError
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid MEXC API URL"
        case .invalidResponse:
            return "Invalid response from MEXC API"
        case .apiError(let message):
            return "MEXC API error: \(message)"
        case .decodingError:
            return "Failed to decode MEXC response"
        }
    }
}
