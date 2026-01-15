import Foundation
import SwiftUI

/// A tiny helper that warms the URL cache for coin logos so CoinImageView can render instantly.
actor CoinLogoPrefetcher {
    static let shared = CoinLogoPrefetcher()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        // 30 MB RAM, 120 MB disk specifically for logos
        config.urlCache = URLCache(memoryCapacity: 30 * 1024 * 1024,
                                   diskCapacity: 120 * 1024 * 1024,
                                   diskPath: "CoinLogoCache")
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 6
        config.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: config)
    }()

    /// Prefetch logos for the given symbols (case-insensitive).
    func prefetch(symbols: [String]) async {
        let upper = Set(symbols.map { $0.uppercased() })
        guard !upper.isEmpty else { return }
        let coins = MarketViewModel.shared.allCoins
        let urls: [URL] = upper.compactMap { sym in
            if let c = coins.first(where: { $0.symbol.uppercased() == sym }) { return c.imageUrl }
            return nil
        }
        await prefetch(urls: urls)
    }

    /// Prefetch the first N coins from MarketViewModel (best effort).
    func prefetchTopCoins(count: Int = 24) async {
        let coins = MarketViewModel.shared.allCoins
        guard !coins.isEmpty else { return }
        let urls = Array(coins.prefix(max(0, count))).compactMap { $0.imageUrl }
        await prefetch(urls: urls)
    }

    private func prefetch(urls: [URL]) async {
        guard !urls.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask { [session] in
                    var req = URLRequest(url: url)
                    req.cachePolicy = .returnCacheDataElseLoad
                    req.timeoutInterval = 6
                    // Ignore the data; the goal is to populate URLCache
                    _ = try? await session.data(for: req)
                }
            }
        }
    }
}
