//
//  FileManager+Directories.swift
//  CryptoSage
//
//  CONSOLIDATION: Centralized directory access to eliminate duplicate code
//  across the codebase. Use these instead of inline FileManager.default.urls calls.
//

import Foundation

extension FileManager {
    
    // MARK: - Base Directories
    
    /// Returns the user's documents directory URL
    /// Safe: Returns temporary directory as fallback if unavailable
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("Documents", isDirectory: true)
    }
    
    /// Returns the user's caches directory URL
    /// Safe: Returns temporary directory as fallback if unavailable
    static var cachesDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("Caches", isDirectory: true)
    }
    
    // MARK: - Subdirectory Helpers
    
    /// Returns a subdirectory within the caches directory, creating it if needed
    /// - Parameter name: The subdirectory name
    /// - Returns: URL to the subdirectory
    static func cacheSubdirectory(_ name: String) -> URL {
        let dir = cachesDirectory.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    /// Returns a subdirectory within the documents directory, creating it if needed
    /// - Parameter name: The subdirectory name
    /// - Returns: URL to the subdirectory
    static func documentsSubdirectory(_ name: String) -> URL {
        let dir = documentsDirectory.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    // MARK: - Common Cache Directories
    
    /// Chart data cache directory
    static var chartCacheDirectory: URL {
        cacheSubdirectory("ChartCache")
    }
    
    /// Coin image cache directory
    static var coinImageCacheDirectory: URL {
        cacheSubdirectory("CoinImageCache")
    }
    
    /// Exchange logo cache directory
    static var exchangeLogoCacheDirectory: URL {
        cacheSubdirectory("ExchangeLogoCache")
    }
    
    /// Stock logo cache directory
    static var stockLogoCacheDirectory: URL {
        cacheSubdirectory("StockLogoCache")
    }
    
    /// News cache directory
    static var newsCacheDirectory: URL {
        cacheSubdirectory("CryptoNewsCache")
    }
    
    /// Market data cache directory
    static var marketCacheDirectory: URL {
        cacheSubdirectory("MarketCache")
    }
}
