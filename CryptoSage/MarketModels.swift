import Foundation

public struct Asset {
    public let id: String
    public let symbol: String
    public let name: String
}

public struct Exchange {
    public let id: String
    public let name: String
    public let region: String?
    public let reliabilityScore: Double?

    public init(id: String, name: String, region: String?, reliabilityScore: Double?) {
        self.id = id
        self.name = name
        self.region = region
        self.reliabilityScore = reliabilityScore
    }
}

public struct MarketPair: Hashable, Codable {
    public let exchangeID: String
    public let baseSymbol: String
    public let quoteSymbol: String

    public var pairID: String {
        "\(exchangeID):\(baseSymbol)-\(quoteSymbol)"
    }

    public init(exchangeID: String, baseSymbol: String, quoteSymbol: String) {
        self.exchangeID = exchangeID
        self.baseSymbol = baseSymbol
        self.quoteSymbol = quoteSymbol
    }
}

public struct Ticker: Codable {
    public let pair: MarketPair
    public let last: Double
    public let bid: Double?
    public let ask: Double?
    public let volume24hBase: Double?
    public let ts: TimeInterval

    public init(pair: MarketPair, last: Double, bid: Double?, ask: Double?, volume24hBase: Double?, ts: TimeInterval) {
        self.pair = pair
        self.last = last
        self.bid = bid
        self.ask = ask
        self.volume24hBase = volume24hBase
        self.ts = ts
    }
}

public enum CandleInterval: String, Codable, CaseIterable {
    case m1 = "1m"
    case m5 = "5m"
    case m15 = "15m"
    case h1 = "1h"
    case h4 = "4h"
    case d1 = "1d"
}

public struct Candle: Codable {
    public let pair: MarketPair
    public let interval: CandleInterval
    public let open: Double
    public let high: Double
    public let low: Double
    public let close: Double
    public let volume: Double?
    public let ts: TimeInterval

    public init(pair: MarketPair, interval: CandleInterval, open: Double, high: Double, low: Double, close: Double, volume: Double?, ts: TimeInterval) {
        self.pair = pair
        self.interval = interval
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.volume = volume
        self.ts = ts
    }
}

public struct CompositeConstituent {
    public let pair: MarketPair
    public let priceUSD: Double
    public let weight: Double
}

public struct CompositePrice {
    public let assetSymbol: String
    public let priceUSD: Double
    public let method: String
    public let constituents: [CompositeConstituent]
    public let ts: TimeInterval
}

public struct CompositeSeries {
    public let assetSymbol: String
    public let interval: CandleInterval
    public let closesUSD: [Double]
    public let timestamps: [TimeInterval]
    public let ts: TimeInterval
}
