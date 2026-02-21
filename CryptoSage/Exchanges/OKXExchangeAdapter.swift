//
//  OKXExchangeAdapter.swift
//  CryptoSage
//
//  OKX unified API exchange adapter for market data.
//

import Foundation

// MARK: - OKX Exchange Adapter

public final class OKXExchangeAdapter: ExchangeAdapter {
    public var id: String { "okx" }
    public var name: String { "OKX" }
    
    private let session: URLSession
    private let baseURL: URL
    
    // MARK: - Initialization
    
    public init(session: URLSession = .shared) {
        self.session = session
        self.baseURL = URL(string: "https://www.okx.com/api/v5")!
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
        
        // OKX requires individual ticker requests or can batch by instType
        // Fetch all spot tickers
        let spotTickers = try await fetchSpotTickers()
        
        for pair in pairs {
            // OKX format: BTC-USDT
            let instId = "\(pair.baseSymbol.uppercased())-\(pair.quoteSymbol.uppercased())"
            
            if let ticker = spotTickers[instId] {
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
        let instId = "\(pair.baseSymbol.uppercased())-\(pair.quoteSymbol.uppercased())"
        let okxBar = mapInterval(interval)
        
        var components = URLComponents(url: baseURL.appendingPathComponent("market/candles"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "instId", value: instId),
            URLQueryItem(name: "bar", value: okxBar),
            URLQueryItem(name: "limit", value: String(min(limit, 300)))
        ]
        
        guard let url = components.url else {
            throw OKXError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw OKXError.invalidResponse
        }
        
        let candleResponse = try JSONDecoder().decode(OKXCandleResponse.self, from: data)
        
        guard candleResponse.code == "0" else {
            throw OKXError.apiError(candleResponse.msg)
        }
        
        return candleResponse.data.compactMap { candle -> MMECandle? in
            guard candle.count >= 6,
                  let timestamp = Double(candle[0]),
                  let open = Double(candle[1]),
                  let high = Double(candle[2]),
                  let low = Double(candle[3]),
                  let close = Double(candle[4]),
                  let volume = Double(candle[5]) else {
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
                ts: timestamp / 1000 // OKX uses milliseconds
            )
        }.reversed() // OKX returns newest first
    }
    
    // MARK: - Private Methods
    
    private func fetchSpotTickers() async throws -> [String: OKXTickerData] {
        var components = URLComponents(url: baseURL.appendingPathComponent("market/tickers"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "instType", value: "SPOT")
        ]
        
        guard let url = components.url else {
            throw OKXError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw OKXError.invalidResponse
        }
        
        let tickerResponse = try JSONDecoder().decode(OKXTickerResponse.self, from: data)
        
        guard tickerResponse.code == "0" else {
            throw OKXError.apiError(tickerResponse.msg)
        }
        
        var tickerMap: [String: OKXTickerData] = [:]
        
        for ticker in tickerResponse.data {
            let ts = Double(ticker.ts) ?? Date().timeIntervalSince1970 * 1000
            let tickerData = OKXTickerData(
                last: Double(ticker.last) ?? 0,
                bid: Double(ticker.bidPx) ?? 0,
                ask: Double(ticker.askPx) ?? 0,
                volume: Double(ticker.vol24h) ?? 0,
                timestamp: ts / 1000
            )
            tickerMap[ticker.instId] = tickerData
        }
        
        return tickerMap
    }
    
    private func mapInterval(_ interval: MMECandleInterval) -> String {
        switch interval {
        case .m1: return "1m"
        case .m5: return "5m"
        case .m15: return "15m"
        case .h1: return "1H"
        case .h4: return "4H"
        case .d1: return "1D"
        }
    }
}

// MARK: - OKX Response Models

private struct OKXTickerResponse: Codable {
    let code: String
    let msg: String
    let data: [OKXTicker]
}

private struct OKXTicker: Codable {
    let instId: String
    let last: String
    let bidPx: String
    let askPx: String
    let vol24h: String
    let volCcy24h: String?
    let high24h: String?
    let low24h: String?
    let ts: String
}

private struct OKXCandleResponse: Codable {
    let code: String
    let msg: String
    let data: [[String]]
}

private struct OKXTickerData {
    let last: Double
    let bid: Double
    let ask: Double
    let volume: Double
    let timestamp: TimeInterval
}

// MARK: - OKX Errors

public enum OKXError: LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(String)
    case decodingError
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid OKX API URL"
        case .invalidResponse:
            return "Invalid response from OKX API"
        case .apiError(let message):
            return "OKX API error: \(message)"
        case .decodingError:
            return "Failed to decode OKX response"
        }
    }
}
