import Combine
import Foundation

// Map common ticker symbols to CoinGecko IDs
private let tickerToGeckoID: [String: String] = [
    "btc": "bitcoin",
    "eth": "ethereum",
    "bnb": "binancecoin"
    // add other tickers as needed
]

/// Protocol for services that publish live price updates for given symbols.
protocol PriceService {
    func pricePublisher(
        for symbols: [String],
        interval: TimeInterval
    ) -> AnyPublisher<[String: Double], Never>
}

/// Live implementation using Binance WebSocket for real-time price updates.
/// Currently falls back to CoinGecko polling until WebSocket logic is finalized.
final class BinanceWebSocketPriceService: PriceService {
    private let fallback = CoinGeckoPriceService()
    
    func pricePublisher(
        for symbols: [String],
        interval: TimeInterval
    ) -> AnyPublisher<[String: Double], Never> {
        // TODO: wire up actual WebSocket here
        return fallback.pricePublisher(for: symbols, interval: interval)
    }
}

/// Live implementation using CoinGecko's simple price API to emit up-to-date prices.
final class CoinGeckoPriceService: PriceService {
    func pricePublisher(
        for symbols: [String],
        interval: TimeInterval
    ) -> AnyPublisher<[String: Double], Never> {
        let pollInterval = interval > 0 ? interval : 5.0

        // Build comma-separated CoinGecko IDs from symbols, using ticker mappings first
        let idList = symbols
            .map { symbol in
                let lower = symbol.lowercased()
                let clean = lower.hasSuffix("usdt")
                    ? String(lower.dropLast(4))
                    : lower
                // Check our ticker map before falling back
                if let mappedID = tickerToGeckoID[clean] {
                    return mappedID
                }
                return LivePriceManager.shared.geckoIDMap[clean] ?? clean
            }
            .joined(separator: ",")
        print("CoinGeckoPriceService: set up pricePublisher for IDs: \(idList)")
        
        let timer = Timer.publish(every: pollInterval, on: .main, in: .common)
            .autoconnect()
            .handleEvents(receiveOutput: { _ in
                print("CoinGeckoPriceService: tick for IDs: \(idList)")
            })
            .prepend(Date())

        return timer
            .flatMap { _ -> AnyPublisher<[String: Double], Never> in
                // If no IDs, emit empty dictionary and continue polling
                if idList.isEmpty {
                    print("CoinGeckoPriceService: idList is empty, skipping request")
                    return Just([:]).eraseToAnyPublisher()
                }
                // Construct URL for non-empty ID list
                guard let url = URL(
                    string: "https://api.coingecko.com/api/v3/simple/price?ids=\(idList)&vs_currencies=usd"
                ) else {
                    return Just([:]).eraseToAnyPublisher()
                }
                print("CoinGeckoPriceService: sending request for IDs: \(idList) to URL: \(url)")
                return URLSession.shared.dataTaskPublisher(for: url)
                    .handleEvents(receiveOutput: { data, _ in
                        print("CoinGeckoPriceService: received \(data.count) bytes for IDs: \(idList)")
                    })
                    .map(\.data)
                    .decode(type: [String: [String: Double]].self, decoder: JSONDecoder())
                    .map { dict in dict.compactMapValues { $0["usd"] } }
                    .replaceError(with: [:])
                    .eraseToAnyPublisher()
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}
