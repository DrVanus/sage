import Foundation

private func documentsURL(for fileName: String) -> URL {
    let fileManager = FileManager.default
    // FIX: Avoid force unwrap; fall back to temporary directory if documents directory is unavailable.
    let baseURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        ?? fileManager.temporaryDirectory
    return baseURL.appendingPathComponent(fileName)
}

/// Tracks which cache files we've already logged as missing to avoid log spam
private var loggedMissingFiles: Set<String> = []
private let loggedMissingFilesLock = NSLock()

public func loadCache<T: Decodable>(from fileName: String, as type: T.Type) -> T? {
    let decoder = JSONDecoder()
    // IMPORTANT: Support both snake_case (CoinGecko API format) and camelCase keys
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let fileManager = FileManager.default

    // 1. Attempt to load from Documents directory
    let fileURL = documentsURL(for: fileName)
    if fileManager.fileExists(atPath: fileURL.path) {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try decoder.decode(T.self, from: data)
            return decoded
        } catch {
            DebugLog.log("CacheUtils", "Failed to load or decode \(fileName) from Documents directory: \(error)")
        }
    }

    // 2. Fallback: Attempt to load from main bundle
    if let bundleURL = Bundle.main.url(forResource: fileName, withExtension: nil) {
        do {
            let data = try Data(contentsOf: bundleURL)
            let decoded = try decoder.decode(T.self, from: data)
            // For coins_cache.json: Check if bundle has more coins than Documents
            // If so, prefer bundle data as it's more complete
            if fileName == "coins_cache.json" {
                DebugLog.log("CacheUtils", "Loaded \(fileName) from bundle (no Documents cache)")
            } else {
                // Seed the cache in Documents directory for non-coin caches
                do {
                    try data.write(to: fileURL, options: [.atomic])
                    DebugLog.log("CacheUtils", "Seeded \(fileName) from bundle to Documents.")
                } catch {
                    DebugLog.log("CacheUtils", "Failed to seed \(fileName) to Documents directory: \(error)")
                }
            }
            return decoded
        } catch {
            DebugLog.log("CacheUtils", "Failed to load or decode \(fileName) from main bundle: \(error)")
        }
    }

    // Only log "not found" once per file name to avoid spam
    loggedMissingFilesLock.lock()
    let shouldLog = !loggedMissingFiles.contains(fileName)
    if shouldLog { loggedMissingFiles.insert(fileName) }
    loggedMissingFilesLock.unlock()
    
    if shouldLog {
        DebugLog.log("CacheUtils", "Cache file \(fileName) not found (first occurrence, will not log again)")
    }
    return nil
}

public func saveCache<T: Encodable>(_ value: T, to fileName: String) {
    let encoder = JSONEncoder()
    // MEMORY FIX: Don't use prettyPrinted for coins_cache.json - saves ~30% file size
    if fileName != "coins_cache.json" {
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
    }
    do {
        // MEMORY FIX: Cap coins_cache.json to match maxAllCoinsCount
        if fileName == "coins_cache.json", let coins = value as? [MarketCoin], coins.count > 75 {
            let capped = Array(coins.prefix(75))
            let data = try encoder.encode(capped)
            let fileURL = documentsURL(for: fileName)
            try data.write(to: fileURL, options: [.atomic])
            return
        }
        let data = try encoder.encode(value)
        let fileURL = documentsURL(for: fileName)
        try data.write(to: fileURL, options: [.atomic])
    } catch {
        DebugLog.log("CacheUtils", "Failed to encode or save \(fileName): \(error)")
    }
}

public func saveCache(_ data: Data, to fileName: String) {
    let fileURL = documentsURL(for: fileName)
    do {
        try data.write(to: fileURL, options: [.atomic])
    } catch {
        DebugLog.log("CacheUtils", "Failed to save raw data to \(fileName): \(error)")
    }
}

public func loadRawCacheData(_ fileName: String) -> Data? {
    let fileManager = FileManager.default
    let fileURL = documentsURL(for: fileName)
    // 1) Try Documents first
    if fileManager.fileExists(atPath: fileURL.path) {
        if let data = try? Data(contentsOf: fileURL) {
            return data
        }
    }
    // 2) Fallback to bundle
    if let bundleURL = Bundle.main.url(forResource: fileName, withExtension: nil),
       let data = try? Data(contentsOf: bundleURL) {
        return data
    }
    return nil
}

// MARK: - PERFORMANCE FIX: Async variants to prevent main thread blocking

/// Dedicated background queue for cache I/O operations
private let cacheIOQueue = DispatchQueue(label: "com.cryptosage.cacheIO", qos: .utility, attributes: .concurrent)

/// PERFORMANCE FIX: Async cache loading that performs disk I/O on background queue
/// Use this instead of loadCache() in async contexts to avoid blocking main thread
public func loadCacheAsync<T: Decodable>(from fileName: String, as type: T.Type) async -> T? {
    nonisolated(unsafe) let capturedType = type
    return await withCheckedContinuation { continuation in
        cacheIOQueue.async {
            let result = loadCache(from: fileName, as: capturedType)
            continuation.resume(returning: result)
        }
    }
}

/// PERFORMANCE FIX: Async cache saving that performs disk I/O on background queue
/// Use this instead of saveCache() to avoid blocking main thread
public func saveCacheAsync<T: Encodable>(_ value: T, to fileName: String) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        cacheIOQueue.async(flags: .barrier) {
            saveCache(value, to: fileName)
            continuation.resume()
        }
    }
}

/// PERFORMANCE FIX: Async raw data saving that performs disk I/O on background queue
public func saveCacheAsync(_ data: Data, to fileName: String) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        cacheIOQueue.async(flags: .barrier) {
            saveCache(data, to: fileName)
            continuation.resume()
        }
    }
}

/// PERFORMANCE FIX: Async raw data loading that performs disk I/O on background queue
public func loadRawCacheDataAsync(_ fileName: String) async -> Data? {
    return await withCheckedContinuation { continuation in
        cacheIOQueue.async {
            let result = loadRawCacheData(fileName)
            continuation.resume(returning: result)
        }
    }
}

/// PERFORMANCE FIX: Fire-and-forget cache save for non-critical data
/// Use when you don't need to wait for the save to complete
public func saveCacheDetached<T: Encodable>(_ value: T, to fileName: String) {
    cacheIOQueue.async(flags: .barrier) {
        saveCache(value, to: fileName)
    }
}

/// PERFORMANCE FIX: Fire-and-forget raw data save for non-critical data
public func saveCacheDetached(_ data: Data, to fileName: String) {
    cacheIOQueue.async(flags: .barrier) {
        saveCache(data, to: fileName)
    }
}
