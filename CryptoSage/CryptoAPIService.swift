//
//  CryptoAPIService.swift
//  CryptoSage
//

import Foundation
import Combine
import Network

/// Monitors network connectivity using NWPathMonitor
final class NetworkMonitor {
    static let shared = NetworkMonitor()
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    private(set) var isOnline: Bool = false

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.isOnline = (path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }
    /// Live-updating publisher for market data (top-20 + watchlist) on a timer.
    @MainActor
    func liveMarketDataPublisher(visibleIDs: [String], interval: TimeInterval = 15) -> AnyPublisher<(allCoins: [MarketCoin], watchlistCoins: [MarketCoin]), Never> {
        Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .prepend(Date())
            .flatMap { _ in
                Future { promise in
                    Task {
                        let idMap = await LivePriceManager.shared.geckoIDMap
                        let mappedIDs = visibleIDs.map { idMap[$0.lowercased()] ?? $0.lowercased() }
                        do {
                            let result = try await CryptoAPIService.shared.fetchAllAndWatchlist(visibleIDs: mappedIDs)
                            promise(.success(result))
                        } catch {
                            print("❌ [CryptoAPIService] liveMarketDataPublisher error:", error)
                            promise(.success((allCoins: [], watchlistCoins: [])))
                        }
                    }
                }
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    /// Closure-based wrapper for async fetchCoins(ids:)
    func fetchMarketData(ids: [String], completion: @escaping ([MarketCoin]) -> Void) {
        Task {
            let markets = await CryptoAPIService.shared.fetchCoins(ids: ids)
            DispatchQueue.main.async {
                completion(markets)
            }
        }
    }

    /// Closure-based wrapper for async fetchSpotPrice(coin:)
    func fetchSpotPrice(coin: String, completion: @escaping (Double) -> Void) {
        Task {
            let price: Double
            do {
                price = try await CryptoAPIService.shared.fetchSpotPrice(coin: coin)
            } catch {
                price = 0
            }
            DispatchQueue.main.async {
                completion(price)
            }
        }
    }
}

/// Builds a URL for fetching price history for a given coin and timeframe.
extension CryptoAPIService {
    static func buildPriceHistoryURL(
        for coinID: String,
        timeframe: ChartTimeframe
    ) -> URL? {
        var daysParam: String
        switch timeframe {
        case .oneDay, .live:
            daysParam = "1"
        case .oneWeek:
            daysParam = "7"
        case .oneMonth:
            daysParam = "30"
        case .threeMonths:
            daysParam = "90"
        case .oneYear:
            daysParam = "365"
        case .allTime:
            daysParam = "max"
        default:
            daysParam = "1"
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.coingecko.com"
        components.path = "/api/v3/coins/\(coinID)/market_chart"
        components.queryItems = [
            URLQueryItem(name: "vs_currency", value: "usd"),
            URLQueryItem(name: "days", value: daysParam)
        ]
        return components.url
    }
}

private extension FileManager {
    static func cacheURL(for fileName: String) -> URL {
        let docs = Self.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(fileName)
    }
}

private func saveCache(data: Data, to fileName: String) {
    let url = FileManager.cacheURL(for: fileName)
    try? data.write(to: url)
}

private func loadCache<T: Decodable>(from fileName: String, as type: T.Type) -> T? {
    let url = FileManager.cacheURL(for: fileName)
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(T.self, from: data)
}

/// Error thrown when the API returns a rate-limit status (HTTP 429).
enum CryptoAPIError: LocalizedError {
    case rateLimited
    case badServerResponse(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .rateLimited:
            return "Rate limit exceeded. Please try again later."
        case .badServerResponse(let statusCode):
            return "Unexpected server response (code \(statusCode))."
        }
    }
}

/// Service wrapper for CoinGecko API calls
final class CryptoAPIService {
    static let shared = CryptoAPIService()
    private init() {}


    /// Map common ticker symbols to CoinGecko IDs
    private func coingeckoID(for symbol: String) -> String {
        switch symbol.uppercased() {
        case "BTC": return "bitcoin"
        case "ETH": return "ethereum"
        case "DOGE": return "dogecoin"
        case "ADA": return "cardano"
        case "SOL": return "solana"
        case "XRP": return "ripple"
        case "DOT": return "polkadot"
        case "MATIC": return "matic-network"
        // add any other symbols you use
        default:
            return symbol.lowercased()
        }
    }

    @MainActor
    func fetchCoins(ids: [String]) async -> [MarketCoin] {
        // If offline, attempt to return cached coins filtered by IDs
        if !NetworkMonitor.shared.isOnline {
            if let cached: [MarketCoin] = loadCache(from: "coins_cache.json", as: [MarketCoin].self) {
                return cached.filter { ids.contains($0.id) }
            }
            return []
        }
        // Guard against empty ID list
        guard !ids.isEmpty else {
            return []
        }

        // Map raw symbols to CoinGecko IDs
        let mappedIDs = ids.map { coingeckoID(for: $0) }
        let idString = mappedIDs.joined(separator: ",")
        guard var components = URLComponents(string: "https://api.coingecko.com/api/v3/coins/markets") else {
            print("❌ [CryptoAPIService] Invalid URL in fetchCoins(ids:).")
            return []
        }
        components.queryItems = [
            URLQueryItem(name: "vs_currency", value: "usd"),
            URLQueryItem(name: "ids", value: idString),
            URLQueryItem(name: "order", value: "market_cap_desc"),
            URLQueryItem(name: "sparkline", value: "true"),
            URLQueryItem(name: "price_change_percentage", value: "1h,24h,7d")
        ]
        guard let url = components.url else {
            print("❌ [CryptoAPIService] Invalid URL in fetchCoins(ids:).")
            return []
        }

        let maxRetries = 3
        var attempt = 0
        var delay: TimeInterval = 1
        while attempt < maxRetries {
            attempt += 1
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let geckoCoins = try decoder.decode([CoinGeckoCoin].self, from: data)
                let coins = geckoCoins.map { MarketCoin(gecko: $0) }
                // Cache the raw JSON for offline fallback
                saveCache(data: data, to: "coins_cache.json")
                return coins
            } catch CryptoAPIError.rateLimited {
                let wait = delay
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                delay *= 2
            } catch let urlError as URLError where urlError.code == .timedOut || urlError.code == .networkConnectionLost {
                let wait = delay
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                delay *= 2
            } catch {
                print("❌ [CryptoAPIService] Failed to fetchCoins(ids:) error: \(error)")
                // On failure, return cached results if available
                if let cached: [MarketCoin] = loadCache(from: "coins_cache.json", as: [MarketCoin].self) {
                    return cached.filter { ids.contains($0.id) }
                }
                return []
            }
        }
        // If we exhausted retries, try returning cache, else empty
        if let cached: [MarketCoin] = loadCache(from: "coins_cache.json", as: [MarketCoin].self) {
            return cached.filter { ids.contains($0.id) }
        }
        return []
    }

    /// Fetches global market data from the CoinGecko `/global` endpoint.
    func fetchGlobalData() async throws -> GlobalMarketData {
        guard NetworkMonitor.shared.isOnline else {
            if let cached: GlobalMarketData = loadCache(from: "global_cache.json", as: GlobalMarketData.self) {
                return cached
            }
            throw URLError(.notConnectedToInternet)
        }
        guard let url = URL(string: "https://api.coingecko.com/api/v3/global") else {
            throw URLError(.badURL)
        }
        var attempts = 0
        var lastError: Error?
        while attempts < 2 {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 10
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 429 {
                        throw CryptoAPIError.rateLimited
                    }
                    guard (200...299).contains(http.statusCode) else {
                        throw CryptoAPIError.badServerResponse(statusCode: http.statusCode)
                    }
                }
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let wrapper = try decoder.decode(GlobalDataResponse.self, from: data)
                saveCache(data: data, to: "global_cache.json")
                return wrapper.data
            } catch let urlError as URLError
                  where urlError.code == .timedOut
                     || urlError.code == .notConnectedToInternet
                     || urlError.code == .networkConnectionLost {
                attempts += 1
                lastError = urlError
                let backoff = 500_000_000 * UInt64(1 << attempts)
                try await Task.sleep(nanoseconds: backoff)
                if attempts >= 2,
                   let cached: GlobalMarketData = loadCache(from: "global_cache.json", as: GlobalMarketData.self) {
                    return cached
                }
            } catch {
                throw error
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    /// Fetches the current spot price (USD) for a single coin via CoinGecko's simple/price endpoint.
    func fetchSpotPrice(coin: String) async throws -> Double {
        let coinID = coingeckoID(for: coin)
        guard NetworkMonitor.shared.isOnline else {
            throw URLError(.notConnectedToInternet)
        }
        guard var components = URLComponents(string: "https://api.coingecko.com/api/v3/simple/price") else {
            throw URLError(.badURL)
        }
        components.queryItems = [
            URLQueryItem(name: "ids", value: coinID),
            URLQueryItem(name: "vs_currencies", value: "usd")
        ]
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 429 {
                throw CryptoAPIError.rateLimited
            }
            guard (200...299).contains(http.statusCode) else {
                throw CryptoAPIError.badServerResponse(statusCode: http.statusCode)
            }
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let coinData = json?[coinID] as? [String: Any]
        if let price = coinData?["usd"] as? Double {
            return price
        }
        throw CryptoAPIError.badServerResponse(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
    }

    /// Fetches top coins from CoinGecko `/coins/markets`, decoding into `[MarketCoin]`.
    func fetchCoinMarkets() async throws -> [MarketCoin] {
        // If offline, return cached coins if available
        guard NetworkMonitor.shared.isOnline else {
            if let cached: [MarketCoin] = loadCache(from: "coins_cache.json", as: [MarketCoin].self) {
                return cached
            }
            throw URLError(.notConnectedToInternet)
        }
        // Build URLComponents for top markets endpoint
        guard var components = URLComponents(string: "https://api.coingecko.com/api/v3/coins/markets") else {
            throw URLError(.badURL)
        }
        components.queryItems = [
            URLQueryItem(name: "vs_currency", value: "usd"),
            URLQueryItem(name: "order", value: "market_cap_desc"),
            URLQueryItem(name: "per_page", value: "20"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "sparkline", value: "true"),
            URLQueryItem(name: "price_change_percentage", value: "1h,24h,7d")
        ]
        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var attempts = 0
        var lastError: Error?
        while attempts < 2 {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let geckoCoins = try decoder.decode([CoinGeckoCoin].self, from: data)
                let coins = geckoCoins.map { MarketCoin(gecko: $0) }
                saveCache(data: data, to: "coins_cache.json")
                return coins
            } catch let error as CryptoAPIError {
                throw error
            } catch let urlError as URLError
                  where urlError.code == .timedOut
                     || urlError.code == .notConnectedToInternet
                     || urlError.code == .networkConnectionLost {
                attempts += 1
                lastError = urlError
                let backoff = 500_000_000 * UInt64(1 << attempts)
                try await Task.sleep(nanoseconds: backoff)
                if attempts >= 2,
                   let cached: [MarketCoin] = loadCache(from: "coins_cache.json", as: [MarketCoin].self) {
                    return cached
                }
            } catch {
                throw error
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    /// Convenience alias for LivePriceManager compatibility
    func fetchMarketCoins() async throws -> [MarketCoin] {
        return try await fetchCoinMarkets()
    }

    /// Fetches watchlist coins by ID list; debounced calls will use a single network request.
    func fetchWatchlistMarkets(ids: [String]) async throws -> [MarketCoin] {
        // If offline, return filtered cached coins if available
        guard NetworkMonitor.shared.isOnline else {
            if let cached: [MarketCoin] = loadCache(from: "coins_cache.json", as: [MarketCoin].self) {
                return cached.filter { ids.contains($0.id) }
            }
            throw URLError(.notConnectedToInternet)
        }
        // Early exit if no IDs
        guard !ids.isEmpty else {
            return []
        }

        // Map raw symbols to CoinGecko IDs
        let mappedIDs = ids.map { coingeckoID(for: $0) }
        let idList = mappedIDs.joined(separator: ",")
        guard var components = URLComponents(string: "https://api.coingecko.com/api/v3/coins/markets") else {
            throw URLError(.badURL)
        }
        components.queryItems = [
            URLQueryItem(name: "vs_currency", value: "usd"),
            URLQueryItem(name: "ids", value: idList),
            URLQueryItem(name: "order", value: "market_cap_desc"),
            URLQueryItem(name: "sparkline", value: "true"),
            URLQueryItem(name: "price_change_percentage", value: "1h,24h,7d")
        ]
        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var attempts = 0
        var lastError: Error?
        while attempts < 2 {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let geckoCoins = try decoder.decode([CoinGeckoCoin].self, from: data)
                let coins = geckoCoins.map { MarketCoin(gecko: $0) }
                saveCache(data: data, to: "coins_cache.json")
                return coins
            } catch let error as CryptoAPIError {
                throw error
            } catch let urlError as URLError
                  where urlError.code == .timedOut
                     || urlError.code == .notConnectedToInternet
                     || urlError.code == .networkConnectionLost {
                attempts += 1
                lastError = urlError
                let backoff = 500_000_000 * UInt64(1 << attempts)
                try await Task.sleep(nanoseconds: backoff)
                if attempts >= 2,
                   let cached: [MarketCoin] = loadCache(from: "coins_cache.json", as: [MarketCoin].self) {
                    return cached.filter { ids.contains($0.id) }
                }
            } catch {
                throw error
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    /// Fetches both top-20 markets and watchlist markets in a single call.
    func fetchAllAndWatchlist(visibleIDs: [String]) async throws -> (allCoins: [MarketCoin], watchlistCoins: [MarketCoin]) {
        // 1) Always fetch top-20
        let allCoins = try await fetchCoinMarkets()

        // 2) Fetch watchlist only if there are IDs
        let watchlistCoins: [MarketCoin]
        if visibleIDs.isEmpty {
            watchlistCoins = []
        } else {
            watchlistCoins = try await fetchWatchlistMarkets(ids: visibleIDs)
        }

        return (allCoins, watchlistCoins)
    }

    /// Combine publisher for fetching top-coin markets.
    func fetchCoinMarketsPublisher() -> AnyPublisher<[MarketCoin], Error> {
        Future { promise in
            Task {
                do {
                    let coins = try await self.fetchCoinMarkets()
                    promise(.success(coins))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }

    /// Combine-friendly entry point for loading top market coins.
    static func loadMarketData() -> AnyPublisher<[MarketCoin], Error> {
        return CryptoAPIService.shared.fetchCoinMarketsPublisher()
    }

    /// Combine publisher for fetching watchlist coin markets by IDs.
    func fetchWatchlistMarketsPublisher(ids: [String]) -> AnyPublisher<[MarketCoin], Error> {
        Future { promise in
            Task {
                do {
                    let coins = try await self.fetchWatchlistMarkets(ids: ids)
                    promise(.success(coins))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
}

extension CryptoAPIService {
    /// Live-updating publisher for a single coin’s spot price, mapping symbol to Gecko ID.
    func liveSpotPricePublisher(for symbol: String, interval: TimeInterval = 5) -> AnyPublisher<Double, Never> {
        return Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .prepend(Date())  // trigger an immediate fetch
            .flatMap { _ in
                Future<Double, Never> { promise in
                    Task {
                        let price = (try? await self.fetchSpotPrice(coin: symbol)) ?? 0
                        promise(.success(price))
                    }
                }
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}
