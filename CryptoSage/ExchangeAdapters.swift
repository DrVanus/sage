import Foundation

public protocol ExchangeAdapter {
    // A stable identifier for the exchange, e.g., "coinbase", "binance"
    var id: String { get }
    var name: String { get }

    // Return market pairs this adapter can provide for a given base symbol (e.g., "BTC").
    // Implementations may ignore the hint and return all supported pairs.
    func supportedPairs(for baseSymbol: String) async -> [MMEMarketPair]

    // Fetch latest tickers for the given pairs. Implementations should best-effort fill `ts` (epoch seconds).
    func fetchTickers(for pairs: [MMEMarketPair]) async throws -> [MMETicker]

    // Fetch recent candles for a specific pair and interval. Limit is a soft upper bound.
    func fetchCandles(pair: MMEMarketPair, interval: MMECandleInterval, limit: Int) async throws -> [MMECandle]
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
        "FDUSD": 1.0,
        "DAI": 1.0,
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

