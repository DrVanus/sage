import Foundation

// NOTE: This file defines exchange-native Candle and CandleInterval types for Binance and similar services.
// They are intentionally distinct from the MarketModels.swift types (MMECandle/MMECandleInterval) used by the
// composite pricing pipeline. Keep these names as-is for compatibility with Binance REST responses.

public struct Candle: Codable, Equatable {
    public let openTime: Date
    public let open: Double
    public let high: Double
    public let low: Double
    public let close: Double
    public let volume: Double
    public let closeTime: Date
    public let quoteAssetVolume: Double
    public let numberOfTrades: Int
    public let takerBuyBaseAssetVolume: Double
    public let takerBuyQuoteAssetVolume: Double

    public init(
        openTime: Date,
        open: Double,
        high: Double,
        low: Double,
        close: Double,
        volume: Double,
        closeTime: Date,
        quoteAssetVolume: Double,
        numberOfTrades: Int,
        takerBuyBaseAssetVolume: Double,
        takerBuyQuoteAssetVolume: Double
    ) {
        self.openTime = openTime
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.volume = volume
        self.closeTime = closeTime
        self.quoteAssetVolume = quoteAssetVolume
        self.numberOfTrades = numberOfTrades
        self.takerBuyBaseAssetVolume = takerBuyBaseAssetVolume
        self.takerBuyQuoteAssetVolume = takerBuyQuoteAssetVolume
    }
}

public enum CandleInterval: String, CaseIterable {
    case oneMinute = "1m"
    case fiveMinutes = "5m"
    case fifteenMinutes = "15m"
    case thirtyMinutes = "30m"
    case oneHour = "1h"
    case twoHours = "2h"
    case fourHours = "4h"
    case oneDay = "1d"
    case oneWeek = "1w"
}

public protocol CandleService {
    /// Fetches candles asynchronously for a given symbol and interval.
    /// - Parameters:
    ///   - symbol: Trading pair symbol (e.g. "BTCUSDT")
    ///   - interval: Interval for each candle
    ///   - limit: Maximum number of candles to fetch (optional, default 500)
    /// - Returns: An array of `Candle`
    func fetchCandles(symbol: String, interval: CandleInterval, limit: Int) async throws -> [Candle]
}

public final class BinanceCandleService: CandleService {
    private let session: URLSession
    private let baseURL: URL

    public init(session: URLSession = .shared) {
        self.session = session
        // Default to global REST base; request path handles policy switching (e.g., 451 -> US)
        self.baseURL = URL(string: "https://api.binance.com/api/v3")!
    }

    public func fetchCandles(symbol: String, interval: CandleInterval, limit: Int = 500) async throws -> [Candle] {
        func buildURL(base: URL) -> URL? {
            guard var components = URLComponents(url: base.appendingPathComponent("klines"), resolvingAgainstBaseURL: false) else { return nil }
            components.queryItems = [
                URLQueryItem(name: "symbol", value: symbol),
                URLQueryItem(name: "interval", value: interval.rawValue),
                URLQueryItem(name: "limit", value: "\(limit)")
            ]
            return components.url
        }

        guard let initial = buildURL(base: baseURL) else { throw URLError(.badURL) }
        let (data, _) = try await ExchangeHTTP.getWithPolicyFallback(
            initial: initial,
            session: session,
            buildFromEndpoints: { eps in buildURL(base: eps.restBase)! }
        )

        // Binance kline API returns [[Any]] array where each inner array has:
        // [
        //   0 Open time
        //   1 Open
        //   2 High
        //   3 Low
        //   4 Close
        //   5 Volume
        //   6 Close time
        //   7 Quote asset volume
        //   8 Number of trades
        //   9 Taker buy base asset volume
        //  10 Taker buy quote asset volume
        //  11 Ignore.
        // ]
        let raw = try JSONSerialization.jsonObject(with: data, options: []) as? [[Any]]
        guard let rawCandles = raw else {
            throw URLError(.cannotParseResponse)
        }

        var candles: [Candle] = []
        for entry in rawCandles {
            guard entry.count >= 11,
                  let openTimeMs = entry[0] as? Double,
                  let openStr = entry[1] as? String,
                  let highStr = entry[2] as? String,
                  let lowStr = entry[3] as? String,
                  let closeStr = entry[4] as? String,
                  let volumeStr = entry[5] as? String,
                  let closeTimeMs = entry[6] as? Double,
                  let quoteAssetVolumeStr = entry[7] as? String,
                  let numberOfTrades = entry[8] as? Int,
                  let takerBuyBaseAssetVolumeStr = entry[9] as? String,
                  let takerBuyQuoteAssetVolumeStr = entry[10] as? String,
                  let open = Double(openStr),
                  let high = Double(highStr),
                  let low = Double(lowStr),
                  let close = Double(closeStr),
                  let volume = Double(volumeStr),
                  let quoteAssetVolume = Double(quoteAssetVolumeStr),
                  let takerBuyBaseAssetVolume = Double(takerBuyBaseAssetVolumeStr),
                  let takerBuyQuoteAssetVolume = Double(takerBuyQuoteAssetVolumeStr)
            else {
                continue
            }

            let openTime = Date(timeIntervalSince1970: openTimeMs / 1000)
            let closeTime = Date(timeIntervalSince1970: closeTimeMs / 1000)

            let candle = Candle(
                openTime: openTime,
                open: open,
                high: high,
                low: low,
                close: close,
                volume: volume,
                closeTime: closeTime,
                quoteAssetVolume: quoteAssetVolume,
                numberOfTrades: numberOfTrades,
                takerBuyBaseAssetVolume: takerBuyBaseAssetVolume,
                takerBuyQuoteAssetVolume: takerBuyQuoteAssetVolume
            )
            candles.append(candle)
        }
        return candles
    }
}
