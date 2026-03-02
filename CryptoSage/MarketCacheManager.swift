import Foundation

/// Manages saving and loading MarketCoin arrays to disk.
final class MarketCacheManager {
    static let shared = MarketCacheManager()
    private let cacheURL: URL
    
    // MARK: - Cache TTL Configuration
    /// Maximum age for cache before it's considered stale and should be cleared (24 hours)
    static let maxCacheAge: TimeInterval = 24 * 60 * 60
    
    /// Warning threshold - cache older than this will trigger a warning but still be used (6 hours)
    static let warningCacheAge: TimeInterval = 6 * 60 * 60

    private init() {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        cacheURL = docs.appendingPathComponent("coins_cache.json")
    }
    
    // MARK: - Cache Age Checking
    
    /// Returns the age of the cache file in seconds, or nil if cache doesn't exist
    func cacheAge() -> TimeInterval? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: cacheURL.path) else { return nil }
        
        do {
            let attrs = try fm.attributesOfItem(atPath: cacheURL.path)
            if let modDate = attrs[.modificationDate] as? Date {
                return Date().timeIntervalSince(modDate)
            }
        } catch {
            #if DEBUG
            print("⚠️ [MarketCacheManager] Failed to get cache age: \(error)")
            #endif
        }
        return nil
    }
    
    /// Returns true if the cache is older than the maximum TTL (24 hours)
    func isCacheExpired() -> Bool {
        guard let age = cacheAge() else { return false }
        return age > Self.maxCacheAge
    }
    
    /// Returns true if the cache is older than the warning threshold (6 hours)
    func isCacheStale() -> Bool {
        guard let age = cacheAge() else { return false }
        return age > Self.warningCacheAge
    }
    
    /// Clears the cache file from disk
    func clearCache() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: cacheURL.path) else { return }
        
        do {
            try fm.removeItem(at: cacheURL)
            #if DEBUG
            print("🗑️ [MarketCacheManager] Cache cleared")
            #endif
        } catch {
            #if DEBUG
            print("🔴 [MarketCacheManager] Failed to clear cache: \(error)")
            #endif
        }
    }
    
    /// Returns a human-readable string for the cache age (e.g., "2h 30m ago")
    func cacheAgeDescription() -> String? {
        guard let age = cacheAge() else { return nil }
        
        let hours = Int(age / 3600)
        let minutes = Int((age.truncatingRemainder(dividingBy: 3600)) / 60)
        
        if hours > 0 {
            return "\(hours)h \(minutes)m ago"
        } else if minutes > 0 {
            return "\(minutes)m ago"
        } else {
            return "just now"
        }
    }

    /// Saves the given coins array to disk as JSON.
    func saveCoinsToDisk(_ coins: [MarketCoin]) {
        do {
            let data = try JSONEncoder().encode(coins)
            try data.write(to: cacheURL, options: [.atomic])
            #if DEBUG
            print("🟢 [MarketCacheManager] Saved \(coins.count) coins to cache")
            #endif
        } catch {
            #if DEBUG
            print("🔴 [MarketCacheManager] Cache Save Error: \(error)")
            #endif
        }
    }

    /// Loads coins array from disk, or returns nil if not found, expired, or on error.
    /// If cache is older than 24 hours, it will be cleared and nil returned.
    /// If cache is older than 6 hours, a warning will be logged but data still returned.
    func loadCoinsFromDisk() -> [MarketCoin]? {
        // TTL CHECK: If cache is expired (>24h), clear it and return nil
        if isCacheExpired() {
            if let age = cacheAge() {
                let hours = Int(age / 3600)
                #if DEBUG
                print("⚠️ [MarketCacheManager] Cache expired (\(hours)h old) - clearing stale data")
                #endif
            }
            clearCache()
            return nil
        }
        
        do {
            let data = try Data(contentsOf: cacheURL)
            let coins = try JSONDecoder().decode([MarketCoin].self, from: data)
            
            // Log warning if cache is stale but still usable
            #if DEBUG
            if isCacheStale(), let ageDesc = cacheAgeDescription() {
                print("⚠️ [MarketCacheManager] Cache is stale (\(ageDesc)) - will refresh soon")
            } else if let ageDesc = cacheAgeDescription() {
                print("🟢 [MarketCacheManager] Loaded \(coins.count) coins from cache (\(ageDesc))")
            } else {
                print("🟢 [MarketCacheManager] Loaded \(coins.count) coins from cache")
            }
            #endif
            
            return coins
        } catch {
            #if DEBUG
            print("🔴 [MarketCacheManager] Cache Load Error: \(error)")
            #endif
            return nil
        }
    }
}
