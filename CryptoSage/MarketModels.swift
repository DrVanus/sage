import Foundation

public struct MMEAsset {
    public let id: String
    public let symbol: String
    public let name: String
}

public struct MMEExchange {
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

public struct MMEMarketPair: Hashable, Codable {
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

public struct MMETicker: Codable {
    public let pair: MMEMarketPair
    public let last: Double
    public let bid: Double?
    public let ask: Double?
    public let volume24hBase: Double?
    public let ts: TimeInterval

    public init(pair: MMEMarketPair, last: Double, bid: Double?, ask: Double?, volume24hBase: Double?, ts: TimeInterval) {
        self.pair = pair
        self.last = last
        self.bid = bid
        self.ask = ask
        self.volume24hBase = volume24hBase
        self.ts = ts
    }
}

public enum MMECandleInterval: String, Codable, CaseIterable {
    case m1 = "1m"
    case m5 = "5m"
    case m15 = "15m"
    case h1 = "1h"
    case h4 = "4h"
    case d1 = "1d"
}

public struct MMECandle: Codable {
    public let pair: MMEMarketPair
    public let interval: MMECandleInterval
    public let open: Double
    public let high: Double
    public let low: Double
    public let close: Double
    public let volume: Double?
    public let ts: TimeInterval

    public init(pair: MMEMarketPair, interval: MMECandleInterval, open: Double, high: Double, low: Double, close: Double, volume: Double?, ts: TimeInterval) {
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

public struct MMECompositeConstituent {
    public let pair: MMEMarketPair
    public let priceUSD: Double
    public let weight: Double
}

public struct MMECompositePrice {
    public let assetSymbol: String
    public let priceUSD: Double
    public let method: String
    public let constituents: [MMECompositeConstituent]
    public let ts: TimeInterval
}

public struct MMECompositeSeries {
    public let assetSymbol: String
    public let interval: MMECandleInterval
    public let closesUSD: [Double]
    public let timestamps: [TimeInterval]
    public let ts: TimeInterval
}
