//
//  CacheManager.swift
//  CryptoSage
//
//  Created by <you> on <today’s date>.
//

import Foundation

/// A simple “load/write JSON to Documents” helper.
/// Usage in your ViewModels/Services:
///    let cachedCoins = CacheManager.shared.load([Coin].self, from: "coins_cache.json")
///    CacheManager.shared.save(coinsArray, to: "coins_cache.json")
///
final class CacheManager {
    static let shared = CacheManager()
    private init() { }
    
    // THREAD SAFETY FIX: Serial queue to synchronize file access
    private let fileAccessQueue = DispatchQueue(label: "com.cryptosage.CacheManager.fileAccess")
    
    // PERFORMANCE FIX: In-memory cache for recently accessed files
    // This prevents blocking main thread during scroll when same data is needed
    private var memoryCache: [String: Any] = [:]
    private let memoryCacheQueue = DispatchQueue(label: "com.cryptosage.CacheManager.memoryCache")
    private let memoryCacheMaxEntries = 30
    private var memoryCacheAccessOrder: [String] = []
    
    /// PERFORMANCE FIX: Check if we should skip blocking I/O
    /// Returns true during scroll to prevent main thread blocking
    private func shouldSkipBlockingIO() -> Bool {
        // THREAD SAFETY: Use MainActor to safely check scroll state
        // Since file I/O is already expensive, this check is negligible
        if Thread.isMainThread {
            return ScrollStateManager.shared.shouldBlockHeavyOperation()
        }
        // If not on main thread, don't skip - background operations should proceed
        return false
    }
    
    /// PERFORMANCE FIX: Get from memory cache (non-blocking)
    private func getFromMemoryCache<T>(_ filename: String, as type: T.Type) -> T? {
        var result: T? = nil
        memoryCacheQueue.sync {
            result = memoryCache[filename] as? T
            // Update LRU order
            if result != nil {
                memoryCacheAccessOrder.removeAll { $0 == filename }
                memoryCacheAccessOrder.append(filename)
            }
        }
        return result
    }
    
    /// PERFORMANCE FIX: Store in memory cache (non-blocking async)
    private func storeInMemoryCache(_ value: Any, for filename: String) {
        memoryCacheQueue.async { [weak self] in
            guard let self = self else { return }
            self.memoryCache[filename] = value
            self.memoryCacheAccessOrder.removeAll { $0 == filename }
            self.memoryCacheAccessOrder.append(filename)
            // Evict oldest if over limit
            while self.memoryCacheAccessOrder.count > self.memoryCacheMaxEntries,
                  let oldest = self.memoryCacheAccessOrder.first {
                self.memoryCacheAccessOrder.removeFirst()
                self.memoryCache.removeValue(forKey: oldest)
            }
        }
    }

    /// MEMORY FIX: Clear all in-memory caches when system is under memory pressure
    func clearMemoryCache() {
        memoryCacheQueue.async { [weak self] in
            guard let self = self else { return }
            self.memoryCache.removeAll()
            self.memoryCacheAccessOrder.removeAll()
        }
    }
    
    // SAFETY FIX: Use safe directory accessor instead of force unwrap
    private var documentsURL: URL {
        FileManager.documentsDirectory
    }

    /// Files that should fall back to bundled versions on fresh install.
    /// Do not include live market price payloads here.
    private static let bundleFallbackFiles: Set<String> = ["global_cache.json"]
    
    /// Files that are safe to auto-delete when corrupted (sidecar caches, not critical user data)
    private static let autoDeleteOnCorruptionFiles: Set<String> = [
        "percent_1h_sidecar.json",
        "percent_24h_sidecar.json",
        "percent_7d_sidecar.json",
        "percent_cache_1h.json",
        "percent_cache_24h.json",
        "percent_cache_7d.json",
        "binance_supported_bases.json",
        "volume_sidecar.json"
    ]
    
    /// Load a Decodable array/object from a JSON file in Documents.
    /// For certain files, falls back to bundled version if not found in Documents.
    /// Corrupted sidecar cache files are automatically deleted to prevent crashes.
    /// THREAD SAFETY: All file operations are synchronized via fileAccessQueue.
    /// PERFORMANCE FIX: Uses in-memory cache and skips blocking I/O during scroll.
    func load<T: Decodable>(_ type: T.Type, from filename: String) -> T? {
        // PERFORMANCE FIX: Try memory cache first (non-blocking)
        if let cached = getFromMemoryCache(filename, as: T.self) {
            return cached
        }
        
        // PERFORMANCE FIX: During scroll, return nil rather than blocking main thread
        // The data will be loaded on next non-scroll access
        if shouldSkipBlockingIO() {
            return nil
        }
        
        // THREAD SAFETY: Synchronize file access to prevent race conditions
        let result: T? = fileAccessQueue.sync {
            loadUnsafe(type, from: filename)
        }
        
        // PERFORMANCE FIX: Store in memory cache for future fast access
        if let result = result {
            storeInMemoryCache(result, for: filename)
        }
        
        return result
    }
    
    /// Load ONLY from Documents directory - NO bundle fallback
    /// Use this when you want REAL previously-fetched data only, not bundled placeholder data
    /// Returns nil if no cached data exists (app should show loading state)
    func loadFromDocumentsOnly<T: Decodable>(_ type: T.Type, from filename: String) -> T? {
        return fileAccessQueue.sync {
            loadFromDocumentsOnlyUnsafe(type, from: filename)
        }
    }
    
    /// Internal Documents-only load - must be called within fileAccessQueue context
    private func loadFromDocumentsOnlyUnsafe<T: Decodable>(_ type: T.Type, from filename: String) -> T? {
        let fileURL = documentsURL.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil  // No cached data - return nil, don't fall back to bundle
        }
        do {
            let data = try Data(contentsOf: fileURL)
            if data.isEmpty { return nil }
            let decoder = JSONDecoder()
            if let decoded = try? decoder.decode(T.self, from: data) {
                return decoded
            }
            // Try CoinGecko format for MarketCoin arrays
            if T.self == [MarketCoin].self {
                let geckoDecoder = JSONDecoder()
                geckoDecoder.keyDecodingStrategy = .convertFromSnakeCase
                if let geckoCoins = try? geckoDecoder.decode([CoinGeckoCoin].self, from: data) {
                    return geckoCoins.map { MarketCoin(gecko: $0) } as? T
                }
            }
        } catch {
            // Corrupted file - return nil
        }
        return nil
    }
    
    /// Internal load implementation - must be called within fileAccessQueue.sync
    private func loadUnsafe<T: Decodable>(_ type: T.Type, from filename: String) -> T? {
        let fileURL = documentsURL.appendingPathComponent(filename)
        
        // If file doesn't exist in Documents, try loading from bundle for specific files
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            // Check if this file supports bundle fallback
            if Self.bundleFallbackFiles.contains(filename) {
                return loadFromBundle(type, filename: filename)
            }
            return nil
        }
        do {
            let data = try Data(contentsOf: fileURL)
            
            // Early validation: check for obviously corrupted data
            // Empty files or files that don't start with valid JSON should be deleted
            if data.isEmpty {
                handleCorruptedFileUnsafe(filename: filename, reason: "empty file")
                return nil
            }
            
            let decoder = JSONDecoder()
            // 1) Try direct decode
            if let decoded = try? decoder.decode(T.self, from: data) {
                return decoded
            }
            // 2) MIGRATION: File may contain a JSON-encoded String (base64 or escaped JSON). Decode String then re-decode.
            if let innerString = try? JSONDecoder().decode(String.self, from: data),
               let innerData = innerString.data(using: .utf8) {
                // Try decode requested type from repaired data
                if let repaired = try? decoder.decode(T.self, from: innerData) {
                    // Write back repaired bytes to fix future loads
                    try? innerData.write(to: fileURL, options: [.atomic])
                    return repaired
                }
                // Special-case: If T == [MarketCoin].self, try decoding CoinGecko array and map
                if T.self == [MarketCoin].self {
                    let geckoDecoder = JSONDecoder()
                    geckoDecoder.keyDecodingStrategy = .convertFromSnakeCase
                    if let geckoCoins = try? geckoDecoder.decode([CoinGeckoCoin].self, from: innerData) {
                        let mapped = geckoCoins.map { MarketCoin(gecko: $0) }
                        // Save repaired raw JSON for future
                        try? innerData.write(to: fileURL, options: [.atomic])
                        return mapped as? T
                    }
                }
            }
            // 3) As a last resort, if T == [MarketCoin].self, try decoding CoinGecko array directly from original data
            if T.self == [MarketCoin].self {
                let geckoDecoder = JSONDecoder()
                geckoDecoder.keyDecodingStrategy = .convertFromSnakeCase
                if let geckoCoins = try? geckoDecoder.decode([CoinGeckoCoin].self, from: data) {
                    let mapped = geckoCoins.map { MarketCoin(gecko: $0) }
                    return mapped as? T
                }
            }
            // If all decodes fail, throw to hit catch and return nil
            return try decoder.decode(T.self, from: data)
        } catch {
            // All decode attempts failed - file is likely corrupted
            handleCorruptedFileUnsafe(filename: filename, reason: error.localizedDescription)
            return nil
        }
    }
    
    // MARK: - Async Loading (Performance Optimization)
    
    /// Async variant of load() that performs file I/O on a background thread.
    /// Use this instead of load() to avoid blocking the main thread during startup.
    /// THREAD SAFETY: Uses fileAccessQueue internally for synchronization.
    func loadAsync<T: Decodable>(_ type: T.Type, from filename: String) async -> T? {
        await withCheckedContinuation { continuation in
            fileAccessQueue.async { [self] in
                let result = loadUnsafe(type, from: filename)
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Async variant of loadFromDocumentsOnly() - NO bundle fallback.
    /// Use this when you want REAL previously-fetched data only, not stale bundled placeholder data.
    /// THREAD SAFETY: Uses fileAccessQueue internally for synchronization.
    func loadFromDocumentsOnlyAsync<T: Decodable>(_ type: T.Type, from filename: String) async -> T? {
        await withCheckedContinuation { continuation in
            fileAccessQueue.async { [self] in
                let result = loadFromDocumentsOnlyUnsafe(type, from: filename)
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Async variant of save() that performs file I/O on a background thread.
    /// THREAD SAFETY: Uses fileAccessQueue internally for synchronization.
    func saveAsync<T: Encodable>(_ object: T, to filename: String) async {
        await withCheckedContinuation { continuation in
            fileAccessQueue.async { [self] in
                saveUnsafe(object, to: filename)
                continuation.resume()
            }
        }
    }
    
    /// Async variant of loadStringDoubleDict() for background loading.
    /// THREAD SAFETY: Uses fileAccessQueue internally for synchronization.
    func loadStringDoubleDictAsync(from filename: String) async -> [String: Double] {
        await withCheckedContinuation { continuation in
            fileAccessQueue.async { [self] in
                let result = loadStringDoubleDictUnsafe(from: filename)
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Async variant of clearPercentCaches() for background execution.
    /// THREAD SAFETY: Uses fileAccessQueue internally for synchronization.
    func clearPercentCachesAsync() async {
        await withCheckedContinuation { continuation in
            fileAccessQueue.async { [self] in
                clearPercentCachesUnsafe()
                continuation.resume()
            }
        }
    }
    
    /// Handle a corrupted cache file by logging and optionally deleting it
    /// THREAD SAFETY: Acquires fileAccessQueue lock
    private func handleCorruptedFile(filename: String, reason: String) {
        fileAccessQueue.sync {
            handleCorruptedFileUnsafe(filename: filename, reason: reason)
        }
    }
    
    /// Internal implementation - must be called within fileAccessQueue.sync
    private func handleCorruptedFileUnsafe(filename: String, reason: String) {
        #if DEBUG
        print("❌ [CacheManager] Corrupted cache '\(filename)': \(reason)")
        #endif
        
        // Only auto-delete known sidecar cache files to prevent data loss
        if Self.autoDeleteOnCorruptionFiles.contains(filename) {
            let fileURL = documentsURL.appendingPathComponent(filename)
            do {
                try FileManager.default.removeItem(at: fileURL)
                #if DEBUG
                print("🗑️ [CacheManager] Deleted corrupted cache: \(filename)")
                #endif
            } catch {
                #if DEBUG
                print("⚠️ [CacheManager] Failed to delete corrupted cache '\(filename)': \(error)")
                #endif
            }
        }
    }

    /// Save an Encodable object/array to a JSON file in Documents.
    /// THREAD SAFETY: All file operations are synchronized via fileAccessQueue.
    /// PERFORMANCE FIX: During scroll, saves are deferred to background to avoid blocking UI.
    func save<T: Encodable>(_ object: T, to filename: String) {
        // PERFORMANCE FIX: Update memory cache immediately (non-blocking)
        if let decodable = object as? Decodable {
            storeInMemoryCache(decodable, for: filename)
        }
        
        // PERFORMANCE FIX: During scroll, defer disk I/O to avoid blocking main thread
        if shouldSkipBlockingIO() {
            fileAccessQueue.async { [weak self] in
                self?.saveUnsafe(object, to: filename)
            }
            return
        }
        
        fileAccessQueue.sync {
            saveUnsafe(object, to: filename)
        }
    }
    
    /// Internal save implementation - must be called within fileAccessQueue.sync
    private func saveUnsafe<T: Encodable>(_ object: T, to filename: String) {
        let fileURL = documentsURL.appendingPathComponent(filename)
        do {
            let encoder = JSONEncoder()
            // MEMORY FIX: Don't use prettyPrinted for large files - saves ~30% disk space
            // which means less data to read into memory on next launch
            if filename != "coins_cache.json" {
                encoder.outputFormatting = .prettyPrinted
            }
            
            // Keep a normal top-of-market cache for startup structure and offline diagnostics.
            if filename == "coins_cache.json", let coins = object as? [MarketCoin], coins.count > 250 {
                let capped = Array(coins.prefix(250))
                let data = try encoder.encode(capped)
                try data.write(to: fileURL, options: .atomic)
                return
            }
            
            let data = try encoder.encode(object)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            #if DEBUG
            print("CacheManager: failed to save \(filename): \(error)")
            #endif
        }
    }

    /// Delete a cache file
    /// THREAD SAFETY: All file operations are synchronized via fileAccessQueue.
    func delete(_ filename: String) {
        fileAccessQueue.sync {
            deleteUnsafe(filename)
        }
    }
    
    /// Internal delete implementation - must be called within fileAccessQueue.sync
    private func deleteUnsafe(_ filename: String) {
        let fileURL = documentsURL.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
    
    /// Safely load a [String: Double] dictionary with extra validation to prevent crashes
    /// Returns empty dictionary on any failure instead of potentially corrupted data
    /// THREAD SAFETY: Uses fileAccessQueue internally for synchronization.
    func loadStringDoubleDict(from filename: String) -> [String: Double] {
        return fileAccessQueue.sync {
            loadStringDoubleDictUnsafe(from: filename)
        }
    }
    
    /// Internal implementation - must be called within fileAccessQueue
    private func loadStringDoubleDictUnsafe(from filename: String) -> [String: Double] {
        guard let loaded = loadUnsafe([String: Double].self, from: filename) else {
            return [:]
        }
        // Extra validation: ensure all keys are non-empty strings and values are finite
        var validated: [String: Double] = [:]
        for (key, value) in loaded {
            guard !key.isEmpty, value.isFinite, !value.isNaN else { continue }
            validated[key] = value
        }
        return validated
    }
    
    /// Clear all percent cache files (call on crash recovery or corruption detection)
    /// THREAD SAFETY: Uses fileAccessQueue internally for synchronization.
    func clearPercentCaches() {
        fileAccessQueue.sync {
            clearPercentCachesUnsafe()
        }
    }
    
    /// Internal implementation - must be called within fileAccessQueue
    private func clearPercentCachesUnsafe() {
        let percentCacheFiles = [
            "percent_cache_1h.json",
            "percent_cache_24h.json",
            "percent_cache_7d.json",
            "percent_1h_sidecar.json",
            "percent_24h_sidecar.json",
            "percent_7d_sidecar.json"
        ]
        for filename in percentCacheFiles {
            deleteUnsafe(filename)
        }
        #if DEBUG
        print("🗑️ [CacheManager] Cleared all percent cache files")
        #endif
    }
    
    // MARK: - Bundle Fallback
    
    /// Load a Decodable object from a bundled JSON file (for fresh install fallback)
    private func loadFromBundle<T: Decodable>(_ type: T.Type, filename: String) -> T? {
        // Try both resource naming styles
        let baseName = filename.replacingOccurrences(of: ".json", with: "")
        let candidates: [URL?] = [
            Bundle.main.url(forResource: baseName, withExtension: "json"),
            Bundle.main.url(forResource: filename, withExtension: nil)
        ]
        
        for urlOpt in candidates {
            guard let url = urlOpt else { continue }
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                
                // Try direct decode
                if let decoded = try? decoder.decode(T.self, from: data) {
                    #if DEBUG
                    print("[CacheManager] Loaded bundled fallback: \(filename)")
                    #endif
                    return decoded
                }
                
                // Try with snake_case conversion (for CoinGecko-style JSON)
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                if let decoded = try? decoder.decode(T.self, from: data) {
                    #if DEBUG
                    print("[CacheManager] Loaded bundled fallback (snake_case): \(filename)")
                    #endif
                    return decoded
                }
            } catch {
                continue
            }
        }
        
        return nil
    }
}

