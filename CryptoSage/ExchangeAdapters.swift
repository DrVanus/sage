import Foundation

public protocol ExchangeAdapter {
    // A stable identifier for the exchange, e.g., "coinbase", "binance"
    var id: String { get }
    var name: String { get }

    // Return market pairs this adapter can provide for a given base symbol (e.g., "BTC").
    // Implementations may ignore the hint and return all supported pairs.
    func supportedPairs(for baseSymbol: String) async -> [MarketPair]

    // Fetch latest tickers for the given pairs. Implementations should best-effort fill `ts` (epoch seconds).
    func fetchTickers(for pairs: [MarketPair]) async throws -> [Ticker]

    // Fetch recent candles for a specific pair and interval. Limit is a soft upper bound.
    func fetchCandles(pair: MarketPair, interval: CandleInterval, limit: Int) async throws -> [Candle]
}

public protocol ExchangeRateService {
    // Return a conversion rate to USD for a quote symbol (e.g., USDT -> 1.0, USDC -> 1.0, EUR -> 1.08).
    func usdRate(for quoteSymbol: String) async -> Double?
}

// A simple, thread-safe in-memory rate service suitable for bootstrapping.
public final class InMemoryExchangeRateService: ExchangeRateService {
    private var rates: [String: Double]
    private let queue = DispatchQueue(label: "InMemoryExchangeRateService.queue")

    public init(initial: [String: Double] = [
        "USD": 1.0,
        "USDT": 1.0,
        "USDC": 1.0,
        "BUSD": 1.0,
        "EUR": 1.08,
        "GBP": 1.27
    ]) {
        self.rates = initial.reduce(into: [:]) { $0[$1.key.uppercased()] = $1.value }
    }

    public func setRate(symbol: String, usd: Double) {
        queue.sync { rates[symbol.uppercased()] = usd }
    }

    public func usdRate(for quoteSymbol: String) async -> Double? {
        queue.sync { rates[quoteSymbol.uppercased()] }
    }
}

// Supporting types

public struct MarketPair: Hashable {
    public let base: String
    public let quote: String

    public init(base: String, quote: String) {
        self.base = base
        self.quote = quote
    }
}

public struct Ticker {
    public let pair: MarketPair
    public let price: Double
    public let volume: Double
    public let ts: Int? // Epoch seconds timestamp

    public init(pair: MarketPair, price: Double, volume: Double, ts: Int?) {
        self.pair = pair
        self.price = price
        self.volume = volume
        self.ts = ts
    }
}

public enum CandleInterval: Equatable {
    case oneMinute
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case fourHours
    case oneDay
    case oneWeek
}

public struct Candle {
    public let pair: MarketPair
    public let interval: CandleInterval
    public let openTime: Int // Epoch seconds
    public let open: Double
    public let high: Double
    public let low: Double
    public let close: Double
    public let volume: Double

    public init(pair: MarketPair, interval: CandleInterval, openTime: Int, open: Double, high: Double, low: Double, close: Double, volume: Double) {
        self.pair = pair
        self.interval = interval
        self.openTime = openTime
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.volume = volume
    }
}
