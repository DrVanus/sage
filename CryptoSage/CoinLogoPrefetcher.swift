import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A tiny helper that warms the CoinImageView cache for coin logos so they render instantly.
/// Now prioritizes Firebase Storage URLs for faster, more reliable image loading.
actor CoinLogoPrefetcher {
    static let shared = CoinLogoPrefetcher()
    
    // MEMORY FIX: Target size for downsampled coin logos (in points)
    // 64pt @ 3x = 192px which is more than enough for coin list icons
    private let logoTargetSize: CGFloat = 64
    // MEMORY FIX: Limit concurrent image downloads to prevent memory spike
    private let maxConcurrentDownloads = 6

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        // MEMORY FIX: Reduced from 6 to 3 to limit concurrent network + memory usage
        config.httpMaximumConnectionsPerHost = 3
        return URLSession(configuration: config)
    }()

    /// Prefetch logos for the given symbols (case-insensitive).
    /// Prioritizes Firebase Storage URLs, falls back to CoinGecko if needed.
    func prefetch(symbols: [String]) async {
        let upper = Set(symbols.map { $0.uppercased() })
        guard !upper.isEmpty else { return }
        let coins = await MainActor.run { MarketViewModel.shared.allCoins }
        
        // Build items with Firebase Storage URL as primary, CoinGecko as fallback
        let items: [(symbol: String, primaryUrl: URL, fallbackUrl: URL?)] = await MainActor.run {
            upper.compactMap { sym in
                guard let c = coins.first(where: { $0.symbol.uppercased() == sym }) else { return nil }
                // Firebase Storage URL (primary - synced by Cloud Functions)
                guard let firebaseUrl = CoinImageView.firebaseStorageURL(for: c.symbol) else { return nil }
                return (symbol: c.symbol, primaryUrl: firebaseUrl, fallbackUrl: c.imageUrl)
            }
        }
        await prefetchItemsWithFallback(items)
    }

    /// Prefetch the first N coins from MarketViewModel (best effort).
    /// Stores images directly in CoinImageView's cache for instant display.
    /// Prioritizes Firebase Storage URLs for faster CDN delivery.
    func prefetchTopCoins(count: Int = 24) async {
        let coins = await MainActor.run { MarketViewModel.shared.allCoins }
        guard !coins.isEmpty else { return }
        
        // Build items with Firebase Storage URL as primary, CoinGecko as fallback
        let items: [(symbol: String, primaryUrl: URL, fallbackUrl: URL?)] = await MainActor.run {
            Array(coins.prefix(max(0, count))).compactMap { coin in
                // Firebase Storage URL (primary - synced by Cloud Functions)
                guard let firebaseUrl = CoinImageView.firebaseStorageURL(for: coin.symbol) else { return nil }
                return (symbol: coin.symbol, primaryUrl: firebaseUrl, fallbackUrl: coin.imageUrl)
            }
        }
        await prefetchItemsWithFallback(items)
    }
    
    /// Prefetch with fallback support - tries Firebase Storage first, then CoinGecko
    /// MEMORY FIX: Uses batched concurrency (maxConcurrentDownloads at a time) instead of
    /// spawning ALL downloads simultaneously. Previously 60 concurrent image downloads would
    /// spike memory by 200+ MB as all images decoded simultaneously without downsampling.
    private func prefetchItemsWithFallback(_ items: [(symbol: String, primaryUrl: URL, fallbackUrl: URL?)]) async {
        guard !items.isEmpty else { return }
        
        // Dedupe by symbol
        var seen = Set<String>()
        var unique: [(symbol: String, primaryUrl: URL, fallbackUrl: URL?)] = []
        for item in items {
            let key = item.symbol.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                unique.append(item)
            }
        }
        
        // MEMORY FIX: Process in batches to limit concurrent memory usage
        let batchSize = maxConcurrentDownloads
        for batchStart in stride(from: 0, to: unique.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, unique.count)
            let batch = Array(unique[batchStart..<batchEnd])
            
            await withTaskGroup(of: Void.self) { group in
                for item in batch {
                    group.addTask { [session] in
                        // Skip if already cached in CoinImageView
                        let alreadyCached = await MainActor.run {
                            CoinImageView.getCachedImage(symbol: item.symbol, url: item.primaryUrl) != nil
                        }
                        if alreadyCached { return }
                        
                        // Try Firebase Storage first (primary)
                        if let image = await self.fetchImage(from: item.primaryUrl, session: session) {
                            await MainActor.run {
                                CoinImageView.cacheImage(image, for: item.primaryUrl, symbol: item.symbol)
                            }
                            return
                        }
                        
                        // Fall back to CoinGecko if Firebase Storage fails
                        if let fallbackUrl = item.fallbackUrl {
                            if let image = await self.fetchImage(from: fallbackUrl, session: session) {
                                await MainActor.run {
                                    CoinImageView.cacheImage(image, for: fallbackUrl, symbol: item.symbol)
                                }
                            }
                        }
                    }
                }
            }
            
            // MEMORY FIX: Small yield between batches to allow autoreleased memory to be reclaimed
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }
    }
    
    /// Fetch image from URL with validation
    /// MEMORY FIX: Now downsamples images to logoTargetSize instead of loading full resolution.
    /// A 1024x1024 image = 4MB in memory, but 192x192 (64pt@3x) = only 144KB.
    /// With 60 images, this reduces peak memory from ~240MB to ~8.6MB.
    private func fetchImage(from url: URL, session: URLSession) async -> PlatformImage? {
        var req = URLRequest(url: url)
        req.setValue("image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        req.cachePolicy = .returnCacheDataElseLoad
        req.timeoutInterval = 8
        
        do {
            let (data, response) = try await session.data(for: req)
            
            // Validate response
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  data.count >= 64 else { return nil }
            
            // MEMORY FIX: Downsample image instead of loading at full resolution
            #if canImport(UIKit)
            let targetSize = logoTargetSize
            let scale = await MainActor.run { UIScreen.main.scale }
            let downsampled: UIImage? = await MainActor.run {
                CoinImageView.downsample(imageData: data, to: targetSize, scale: scale)
            }
            if let downsampled {
                return downsampled
            }
            // Fallback: if downsampling fails, still load but this is rare
            return UIImage(data: data)
            #elseif canImport(AppKit)
            return NSImage(data: data)
            #endif
        } catch {
            // Silently fail - prefetch is best-effort
            return nil
        }
    }

    // MARK: - Legacy support (for backward compatibility)
    
    /// Legacy prefetch method that works with direct URLs
    private func prefetchItems(_ items: [(symbol: String, url: URL)]) async {
        guard !items.isEmpty else { return }
        
        // Dedupe by URL while keeping symbol association
        var seen = Set<String>()
        var unique: [(symbol: String, url: URL)] = []
        for item in items {
            let key = item.url.absoluteString.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                unique.append(item)
            }
        }
        
        await withTaskGroup(of: Void.self) { group in
            for item in unique {
                group.addTask { [session] in
                    // Skip if already cached in CoinImageView
                    let alreadyCached = await MainActor.run {
                        CoinImageView.getCachedImage(symbol: item.symbol, url: item.url) != nil
                    }
                    if alreadyCached { return }
                    
                    if let image = await self.fetchImage(from: item.url, session: session) {
                        await MainActor.run {
                            CoinImageView.cacheImage(image, for: item.url, symbol: item.symbol)
                        }
                    }
                }
            }
        }
    }
}
