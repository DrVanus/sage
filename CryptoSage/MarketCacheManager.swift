import Foundation

/// Manages saving and loading MarketCoin arrays to disk.
final class MarketCacheManager {
    static let shared = MarketCacheManager()
    private let cacheURL: URL

    private init() {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        cacheURL = docs.appendingPathComponent("coins_cache.json")
    }

    /// Saves the given coins array to disk as JSON.
    func saveCoinsToDisk(_ coins: [MarketCoin]) {
        do {
            let data = try JSONEncoder().encode(coins)
            try data.write(to: cacheURL, options: [.atomic])
            print("🟢 Saved \(coins.count) coins to cache at \(cacheURL.path)")
        } catch {
            print("🔴 Cache Save Error:", error)
        }
    }

    /// Loads coins array from disk, or returns nil if not found or on error.
    func loadCoinsFromDisk() -> [MarketCoin]? {
        do {
            let data = try Data(contentsOf: cacheURL)
            let coins = try JSONDecoder().decode([MarketCoin].self, from: data)
            print("🟢 Loaded \(coins.count) coins from cache at \(cacheURL.path)")
            return coins
        } catch {
            print("🔴 Cache Load Error:", error)
            return nil
        }
    }
}
