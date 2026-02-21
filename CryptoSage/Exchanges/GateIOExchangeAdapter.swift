//
//  GateIOExchangeAdapter.swift
//  CryptoSage
//
//  Gate.io V4 API exchange adapter for market data.
//

import Foundation

// MARK: - Gate.io Exchange Adapter

public final class GateIOExchangeAdapter: ExchangeAdapter {
    public var id: String { "gateio" }
    public var name: String { "Gate.io" }
    
    private let session: URLSession
    private let baseURL: URL
    
    // MARK: - Initialization
    
    public init(session: URLSession = .shared) {
        self.session = session
        self.baseURL = URL(string: "https://api.gateio.ws/api/v4")!
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
        
        // Gate.io can fetch all tickers at once
        let allTickers = try await fetchAllTickers()
        
        for pair in pairs {
            // Gate.io format: BTC_USDT
            let currencyPair = "\(pair.baseSymbol.uppercased())_\(pair.quoteSymbol.uppercased())"
            
            if let ticker = allTickers[currencyPair] {
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
        let currencyPair = "\(pair.baseSymbol.uppercased())_\(pair.quoteSymbol.uppercased())"
        let gateInterval = mapInterval(interval)
        
        var components = URLComponents(url: baseURL.appendingPathComponent("spot/candlesticks"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "currency_pair", value: currencyPair),
            URLQueryItem(name: "interval", value: gateInterval),
            URLQueryItem(name: "limit", value: String(min(limit, 1000)))
        ]
        
        guard let url = components.url else {
            throw GateIOError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw GateIOError.invalidResponse
        }
        
        let candles = try JSONDecoder().decode([[String]].self, from: data)
        
        return candles.compactMap { candle -> MMECandle? in
            // Gate.io candle format: [timestamp, volume, close, high, low, open]
            guard candle.count >= 6,
                  let timestamp = Double(candle[0]),
                  let volume = Double(candle[1]),
                  let close = Double(candle[2]),
                  let high = Double(candle[3]),
                  let low = Double(candle[4]),
                  let open = Double(candle[5]) else {
                return nil
            }
            
            return MMECandle(
                pair: pair,
                interval: interval,
                open: open,
                high: high,
                low: low,
                close: close,
                volume: volume,
                ts: timestamp
            )
        }
    }
    
    // MARK: - Private Methods
    
    private func fetchAllTickers() async throws -> [String: GateIOTickerData] {
        let url = baseURL.appendingPathComponent("spot/tickers")
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw GateIOError.invalidResponse
        }
        
        let tickers = try JSONDecoder().decode([GateIOTicker].self, from: data)
        
        var tickerMap: [String: GateIOTickerData] = [:]
        let now = Date().timeIntervalSince1970
        
        for ticker in tickers {
            let tickerData = GateIOTickerData(
                last: Double(ticker.last) ?? 0,
                bid: Double(ticker.highestBid) ?? 0,
                ask: Double(ticker.lowestAsk) ?? 0,
                volume: Double(ticker.baseVolume) ?? 0,
                timestamp: now
            )
            tickerMap[ticker.currencyPair] = tickerData
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

// MARK: - Gate.io Response Models

private struct GateIOTicker: Codable {
    let currencyPair: String
    let last: String
    let highestBid: String
    let lowestAsk: String
    let baseVolume: String
    let quoteVolume: String
    let high24h: String?
    let low24h: String?
    let changePercentage: String?
    
    enum CodingKeys: String, CodingKey {
        case currencyPair = "currency_pair"
        case last
        case highestBid = "highest_bid"
        case lowestAsk = "lowest_ask"
        case baseVolume = "base_volume"
        case quoteVolume = "quote_volume"
        case high24h = "high_24h"
        case low24h = "low_24h"
        case changePercentage = "change_percentage"
    }
}

private struct GateIOTickerData {
    let last: Double
    let bid: Double
    let ask: Double
    let volume: Double
    let timestamp: TimeInterval
}

// MARK: - Gate.io Errors

public enum GateIOError: LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(String)
    case decodingError
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Gate.io API URL"
        case .invalidResponse:
            return "Invalid response from Gate.io API"
        case .apiError(let message):
            return "Gate.io API error: \(message)"
        case .decodingError:
            return "Failed to decode Gate.io response"
        }
    }
}
