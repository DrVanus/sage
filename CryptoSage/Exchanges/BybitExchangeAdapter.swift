//
//  BybitExchangeAdapter.swift
//  CryptoSage
//
//  Bybit V5 unified API exchange adapter for market data.
//

import Foundation

// MARK: - Bybit Exchange Adapter

public final class BybitExchangeAdapter: ExchangeAdapter {
    public var id: String { "bybit" }
    public var name: String { "Bybit" }
    
    private let session: URLSession
    private let baseURL: URL
    
    // MARK: - Initialization
    
    public init(session: URLSession = .shared) {
        self.session = session
        self.baseURL = URL(string: "https://api.bybit.com/v5")!
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
        
        // Bybit V5 supports batch ticker fetch
        // We'll fetch spot tickers
        let spotTickers = try await fetchSpotTickers()
        
        for pair in pairs {
            let symbol = pair.baseSymbol.uppercased() + pair.quoteSymbol.uppercased()
            
            if let ticker = spotTickers[symbol] {
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
        let bybitInterval = mapInterval(interval)
        
        var components = URLComponents(url: baseURL.appendingPathComponent("market/kline"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "category", value: "spot"),
            URLQueryItem(name: "symbol", value: symbol),
            URLQueryItem(name: "interval", value: bybitInterval),
            URLQueryItem(name: "limit", value: String(min(limit, 1000)))
        ]
        
        guard let url = components.url else {
            throw BybitError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw BybitError.invalidResponse
        }
        
        let klineResponse = try JSONDecoder().decode(BybitKlineResponse.self, from: data)
        
        guard klineResponse.retCode == 0 else {
            throw BybitError.apiError(klineResponse.retMsg)
        }
        
        return klineResponse.result.list.compactMap { kline -> MMECandle? in
            guard kline.count >= 6,
                  let timestamp = Double(kline[0]),
                  let open = Double(kline[1]),
                  let high = Double(kline[2]),
                  let low = Double(kline[3]),
                  let close = Double(kline[4]),
                  let volume = Double(kline[5]) else {
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
                ts: timestamp / 1000 // Bybit uses milliseconds
            )
        }.reversed() // Bybit returns newest first
    }
    
    // MARK: - Private Methods
    
    private func fetchSpotTickers() async throws -> [String: BybitTickerData] {
        var components = URLComponents(url: baseURL.appendingPathComponent("market/tickers"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "category", value: "spot")
        ]
        
        guard let url = components.url else {
            throw BybitError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw BybitError.invalidResponse
        }
        
        let tickerResponse = try JSONDecoder().decode(BybitTickerResponse.self, from: data)
        
        guard tickerResponse.retCode == 0 else {
            throw BybitError.apiError(tickerResponse.retMsg)
        }
        
        var tickerMap: [String: BybitTickerData] = [:]
        let now = Date().timeIntervalSince1970
        
        for ticker in tickerResponse.result.list {
            let tickerData = BybitTickerData(
                last: Double(ticker.lastPrice) ?? 0,
                bid: Double(ticker.bid1Price) ?? 0,
                ask: Double(ticker.ask1Price) ?? 0,
                volume: Double(ticker.volume24h) ?? 0,
                timestamp: now
            )
            tickerMap[ticker.symbol] = tickerData
        }
        
        return tickerMap
    }
    
    private func mapInterval(_ interval: MMECandleInterval) -> String {
        switch interval {
        case .m1: return "1"
        case .m5: return "5"
        case .m15: return "15"
        case .h1: return "60"
        case .h4: return "240"
        case .d1: return "D"
        }
    }
}

// MARK: - Bybit Response Models

private struct BybitTickerResponse: Codable {
    let retCode: Int
    let retMsg: String
    let result: BybitTickerResult
}

private struct BybitTickerResult: Codable {
    let category: String
    let list: [BybitTicker]
}

private struct BybitTicker: Codable {
    let symbol: String
    let lastPrice: String
    let bid1Price: String
    let ask1Price: String
    let volume24h: String
    let turnover24h: String?
    let highPrice24h: String?
    let lowPrice24h: String?
}

private struct BybitKlineResponse: Codable {
    let retCode: Int
    let retMsg: String
    let result: BybitKlineResult
}

private struct BybitKlineResult: Codable {
    let symbol: String?
    let category: String?
    let list: [[String]]
}

private struct BybitTickerData {
    let last: Double
    let bid: Double
    let ask: Double
    let volume: Double
    let timestamp: TimeInterval
}

// MARK: - Bybit Errors

public enum BybitError: LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(String)
    case decodingError
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Bybit API URL"
        case .invalidResponse:
            return "Invalid response from Bybit API"
        case .apiError(let message):
            return "Bybit API error: \(message)"
        case .decodingError:
            return "Failed to decode Bybit response"
        }
    }
}
