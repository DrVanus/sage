import SwiftUI

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif
import CryptoKit

#if canImport(UIKit)
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
typealias PlatformImage = NSImage
#endif

struct CoinImageView: View {
    let symbol: String
    let url: URL?
    let size: CGFloat

    @State private var currentIndex: Int = 0
    @State private var currentURL: URL? = nil
    @State private var triedURLs: [URL] = []
    @State private var isAdvancing: Bool = false

    @State private var loadedImage: PlatformImage? = nil
    @State private var lastGoodImage: PlatformImage? = nil

    private static var cachedSuccessBySymbol: [String: URL] = [:]
    // MEMORY FIX: Limit on symbol URL cache to prevent unbounded growth
    private static let maxCachedSuccessEntries = 300

    // PERFORMANCE FIX: Added cache size limits to prevent unbounded memory growth
    private static let memoryCache: NSCache<NSString, PlatformImage> = {
        let cache = NSCache<NSString, PlatformImage>()
        cache.countLimit = 30   // MEMORY FIX v3: Reduced from 75 to 30
        cache.totalCostLimit = 3 * 1024 * 1024  // MEMORY FIX v3: Reduced from 8MB to 3MB
        return cache
    }()
    private static let diskCacheFolderName = "CoinImageCache"
    
    // Firebase Storage configuration for coin images
    // Images are synced to Firebase Storage by Cloud Functions for reliability and speed
    private static let firebaseStorageBucket = "cryptosage-ai.firebasestorage.app"
    private static let firebaseStoragePath = "coin-images"
    
    /// Generate Firebase Storage URL for a coin symbol
    /// This is the primary source for coin images - synced by Cloud Functions
    static func firebaseStorageURL(for symbol: String) -> URL? {
        let lower = symbol.lowercased()
        // URL-encoded path: coin-images/{symbol}.png
        let encodedPath = "\(firebaseStoragePath)%2F\(lower).png"
        return URL(string: "https://firebasestorage.googleapis.com/v0/b/\(firebaseStorageBucket)/o/\(encodedPath)?alt=media")
    }
    
    private static let imageSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 30
        config.httpMaximumConnectionsPerHost = 4
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    private static func cacheDirectoryURL() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent(diskCacheFolderName, isDirectory: true)
    }

    private static func ensureDiskCacheDirectory() {
        if let dir = cacheDirectoryURL() {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private static func hashed(_ string: String) -> String {
        let data = Data(string.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func cacheFileURL(for url: URL) -> URL? {
        ensureDiskCacheDirectory()
        guard let dir = cacheDirectoryURL() else { return nil }
        let name = hashed(url.absoluteString) + ".img"
        return dir.appendingPathComponent(name)
    }

    // PERFORMANCE FIX: Synchronous version for legacy compatibility - prefer async version
    private static func loadImageFromDisk(for url: URL) -> PlatformImage? {
        guard let fileURL = cacheFileURL(for: url), let data = try? Data(contentsOf: fileURL) else { return nil }
        #if canImport(UIKit)
        return UIImage(data: data)
        #elseif canImport(AppKit)
        return NSImage(data: data)
        #endif
    }
    
    // PERFORMANCE FIX: Async disk read to prevent main thread blocking during scroll
    private static func loadImageFromDiskAsync(for url: URL) async -> PlatformImage? {
        guard let fileURL = cacheFileURL(for: url) else { return nil }
        
        // Perform disk I/O on background queue
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                guard let data = try? Data(contentsOf: fileURL) else {
                    continuation.resume(returning: nil)
                    return
                }
                #if canImport(UIKit)
                let image = UIImage(data: data)
                #elseif canImport(AppKit)
                let image = NSImage(data: data)
                #endif
                continuation.resume(returning: image)
            }
        }
    }

    private static func saveImageToDisk(_ image: PlatformImage, for url: URL) {
        guard let fileURL = cacheFileURL(for: url) else { return }
        // PERFORMANCE FIX: Move disk write to background queue
        DispatchQueue.global(qos: .utility).async {
            #if canImport(UIKit)
            guard let data = image.pngData() else { return }
            #elseif canImport(AppKit)
            guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let data = rep.representation(using: .png, properties: [:]) else { return }
            #endif
            try? data.write(to: fileURL, options: [.atomic])
        }
    }
    
    // MARK: - Image Downsampling
    
    /// PERFORMANCE FIX: Downsample images to target display size to reduce memory usage.
    /// Coin images are typically displayed at 24-32pt, but source images can be 200-400px.
    /// Downsampling to 2x target size (for retina) saves significant memory.
    ///
    /// - Parameters:
    ///   - data: Raw image data from network
    ///   - targetSize: Display size in points (e.g., 32)
    ///   - scale: Screen scale (typically 2.0 or 3.0)
    /// - Returns: Downsampled UIImage or nil if downsampling fails
    #if canImport(UIKit)
    // MEMORY FIX: Changed from private to internal so CoinLogoPrefetcher can downsample
    // images during prefetch instead of loading full-resolution images into memory.
    static func downsample(imageData data: Data, to targetSize: CGFloat, scale: CGFloat = UIScreen.main.scale) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        
        // Calculate max dimension based on target size and screen scale
        // Add a small buffer (1.2x) to ensure crisp rendering
        let maxDimension = targetSize * scale * 1.2
        
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailWithTransform: true
        ] as CFDictionary
        
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else {
            // Fall back to regular image creation if downsampling fails
            return UIImage(data: data)
        }
        
        return UIImage(cgImage: cgImage)
    }
    #endif

    private static let cacheKey = "CoinImageView.cachedSuccessBySymbol"
    private static var cacheLoaded: Bool = false
    private static var failuresBySymbol: [String: Int] = [:]
    private static var lastFailureAtBySymbol: [String: Date] = [:]
    private static let maxFailuresPerSession: Int = 10  // Allow more retries for network variations
    private static let failureCooldownSeconds: TimeInterval = 90
    private static let maxFailureEntries = 300  // MEMORY FIX: Limit failure tracking dictionary

    // Use only symbol for attempt key - URL changes shouldn't trigger resets
    private var attemptKey: String {
        symbol.lowercased()
    }

    private static func ensureCacheLoaded() {
        if cacheLoaded { return }
        defer { cacheLoaded = true }
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            var out: [String: URL] = [:]
            for (k, v) in dict {
                if let u = URL(string: v) {
                    out[k] = u
                }
            }
            cachedSuccessBySymbol = out
        }
    }

    private static func persistCache() {
        // MEMORY FIX: Prune dictionaries if they exceed limits
        if cachedSuccessBySymbol.count > maxCachedSuccessEntries {
            // Keep only the most recently added entries (approximation - dictionary is unordered)
            let toRemove = cachedSuccessBySymbol.count - maxCachedSuccessEntries
            let keysToRemove = Array(cachedSuccessBySymbol.keys.prefix(toRemove))
            for key in keysToRemove { cachedSuccessBySymbol.removeValue(forKey: key) }
        }
        if failuresBySymbol.count > maxFailureEntries {
            failuresBySymbol.removeAll()  // Reset failure tracking
        }
        let dict = cachedSuccessBySymbol.mapValues { $0.absoluteString }
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }
    
    /// MEMORY FIX: Aggressively clear all in-memory caches.
    /// Called by the memory watchdog when memory pressure is critical.
    /// Disk cache is preserved - images will be reloaded from disk on next access.
    static func clearAllCaches() {
        memoryCache.removeAllObjects()
        cachedSuccessBySymbol.removeAll()
        failuresBySymbol.removeAll()
        lastFailureAtBySymbol.removeAll()
    }
    
    /// Store an image in the cache for the given URL and symbol.
    /// Used by CoinLogoPrefetcher to pre-populate the cache.
    static func cacheImage(_ image: PlatformImage, for url: URL, symbol: String) {
        let key = url.absoluteString as NSString
        memoryCache.setObject(image, forKey: key)
        saveImageToDisk(image, for: url)
        cachedSuccessBySymbol[symbol.lowercased()] = url
        persistCache()
    }
    
    /// Check if an image is already cached (memory or disk) for the given symbol/URL.
    /// Used by CoinLogoPrefetcher to skip redundant downloads.
    /// NOTE: This synchronous version only checks memory cache to avoid main thread blocking.
    static func getCachedImage(symbol: String, url: URL?) -> PlatformImage? {
        // PERFORMANCE FIX: Only check memory cache synchronously to avoid blocking main thread
        // Disk cache is checked asynchronously via getCachedImageAsync
        if let url = url {
            let key = url.absoluteString as NSString
            if let cached = memoryCache.object(forKey: key) {
                return cached
            }
        }
        // Check if we have a cached success URL for this symbol (memory only)
        ensureCacheLoaded()
        if let cachedURL = cachedSuccessBySymbol[symbol.lowercased()] {
            let key = cachedURL.absoluteString as NSString
            if let cached = memoryCache.object(forKey: key) {
                return cached
            }
        }
        return nil
    }
    
    /// PERFORMANCE FIX: Async version that checks both memory and disk cache without blocking main thread.
    /// Use this in async contexts like .task {} modifiers.
    static func getCachedImageAsync(symbol: String, url: URL?) async -> PlatformImage? {
        // Check memory cache first (fast path)
        if let url = url {
            let key = url.absoluteString as NSString
            if let cached = memoryCache.object(forKey: key) {
                return cached
            }
            // Check disk cache asynchronously
            if let diskImage = await loadImageFromDiskAsync(for: url) {
                memoryCache.setObject(diskImage, forKey: key)
                return diskImage
            }
        }
        // Check if we have a cached success URL for this symbol
        ensureCacheLoaded()
        if let cachedURL = cachedSuccessBySymbol[symbol.lowercased()] {
            let key = cachedURL.absoluteString as NSString
            if let cached = memoryCache.object(forKey: key) {
                return cached
            }
            if let diskImage = await loadImageFromDiskAsync(for: cachedURL) {
                memoryCache.setObject(diskImage, forKey: key)
                return diskImage
            }
        }
        return nil
    }

    private func httpsURL(_ url: URL?) -> URL? {
        guard let url = url else { return nil }
        if let scheme = url.scheme?.lowercased(), scheme == "http" {
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            comps?.scheme = "https"
            return comps?.url
        }
        return url
    }

    private func sanitize(_ url: URL?) -> URL? {
        guard let raw = url else { return nil }
        // First, normalize using the centralized policy (blocks bad hosts and drops fragments/tracking noise)
        let normalized = NewsImagePolicy.normalizedURL(from: raw) ?? raw
        // Enforce HTTPS (handles http and protocol-relative forms)
        let httpsed = httpsURL(normalized) ?? normalized
        // Strip common tracking params (leave image sizing params alone here)
        if var comps = URLComponents(url: httpsed, resolvingAgainstBaseURL: false), let items = comps.queryItems, !items.isEmpty {
            let blocked = Set(["utm_source","utm_medium","utm_campaign","utm_term","utm_content","fbclid","gclid"])
            comps.queryItems = items.filter { !blocked.contains($0.name.lowercased()) }
            return comps.url ?? httpsed
        }
        return httpsed
    }

    private func fallbackURLs(for symbol: String) -> [URL] {
        let lower = symbol.lowercased()
        var list: [URL] = []
        // Priority 1: Firebase Storage (synced by Cloud Functions - most reliable)
        if let u = Self.firebaseStorageURL(for: symbol) { list.append(u) }
        // Priority 2: CoinGecko CDN (primary external source)
        // Note: CoinGecko URL comes from MarketCoin.imageUrl and is handled separately in buildAttemptList
        // Priority 3: CoinCap icons (ticker-based, reliable fallback)
        if let u = URL(string: "https://assets.coincap.io/assets/icons/\(lower)@2x.png") { list.append(u) }
        // Priority 4: CryptoIcons (reliable, ticker-based)
        if let u = URL(string: "https://cryptoicons.org/api/icon/\(lower)/200") { list.append(u) }
        // Priority 5: SpotHQ cryptocurrency-icons (GitHub raw)
        if let u = URL(string: "https://raw.githubusercontent.com/spothq/cryptocurrency-icons/master/128/color/\(lower).png") { list.append(u) }
        return list
    }

    private func localIconName(for symbol: String) -> String? {
        let name = "coin-\(symbol.lowercased())"
        #if canImport(UIKit)
        if UIImage(named: name) != nil { return name }
        #elseif canImport(AppKit)
        if NSImage(named: NSImage.Name(name)) != nil { return name }
        #endif
        return nil
    }

    private func buildAttemptList() -> [URL] {
        var attempts: [URL] = []
        Self.ensureCacheLoaded()
        let lowerSym = symbol.lowercased()
        
        // Priority 1: Previously successful URL (fastest path)
        if let cached = Self.cachedSuccessBySymbol[lowerSym] {
            attempts.append(cached)
        }
        
        // Priority 2: Firebase Storage (our CDN - synced by Cloud Functions)
        if let firebaseURL = Self.firebaseStorageURL(for: symbol) {
            attempts.append(firebaseURL)
        }
        
        // Priority 3: Primary URL from CoinGecko API (passed in via MarketCoin.imageUrl)
        if let primary = sanitize(url) { attempts.append(primary) }
        
        // Priority 4-6: External fallback CDNs (CoinCap, CryptoIcons, SpotHQ)
        // Note: fallbackURLs no longer includes Firebase since we add it above
        let fallbacks = fallbackURLs(for: symbol).filter { u in
            // Skip Firebase URL since we already added it
            !u.absoluteString.contains("firebasestorage.googleapis.com")
        }
        attempts.append(contentsOf: fallbacks)
        
        // Dedupe while preserving order
        var seen = Set<String>()
        var out: [URL] = []
        for u in attempts {
            let key = u.absoluteString.lowercased()
            if !seen.contains(key) { seen.insert(key); out.append(u) }
        }
        return out
    }

    private func resetAttempts() {
        let key = symbol.lowercased()
        if let failures = Self.failuresBySymbol[key], failures >= Self.maxFailuresPerSession {
            if let lastFailureAt = Self.lastFailureAtBySymbol[key],
               Date().timeIntervalSince(lastFailureAt) < Self.failureCooldownSeconds {
                // Keep placeholder briefly after repeated failures, then allow retries again.
                triedURLs = []
                currentIndex = 0
                currentURL = nil
                return
            } else {
                // Cooldown expired; allow retries for this symbol.
                Self.failuresBySymbol[key] = 0
                Self.lastFailureAtBySymbol.removeValue(forKey: key)
            }
        }
        if localIconName(for: symbol) != nil {
            // Local icon available; avoid network attempts
            triedURLs = []
            currentIndex = 0
            currentURL = nil
            return
        }
        let list = buildAttemptList()
        triedURLs = list
        currentIndex = 0
        currentURL = list.first
    }

    private func advanceToNextURL() {
        guard !isAdvancing else { return }
        isAdvancing = true
        defer { isAdvancing = false }
        guard currentIndex + 1 < triedURLs.count else { return }
        currentIndex += 1
        currentURL = triedURLs[currentIndex]
    }

    private func loadImage(for url: URL) async {
        // PERFORMANCE FIX: Early cancellation check
        guard !Task.isCancelled else { return }
        
        let key = url.absoluteString as NSString
        if let cached = Self.memoryCache.object(forKey: key) {
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.loadedImage = cached
                self.lastGoodImage = self.loadedImage
                Self.cachedSuccessBySymbol[symbol.lowercased()] = url
                Self.failuresBySymbol[symbol.lowercased()] = 0
                Self.lastFailureAtBySymbol.removeValue(forKey: symbol.lowercased())
                Self.persistCache()
            }
            return
        }
        
        // PERFORMANCE FIX: Use async disk loading to avoid blocking main thread
        if let diskImage = await Self.loadImageFromDiskAsync(for: url) {
            guard !Task.isCancelled else { return }
            Self.memoryCache.setObject(diskImage, forKey: key)
            await MainActor.run {
                self.loadedImage = diskImage
                self.lastGoodImage = self.loadedImage
                Self.cachedSuccessBySymbol[symbol.lowercased()] = url
                Self.failuresBySymbol[symbol.lowercased()] = 0
                Self.lastFailureAtBySymbol.removeValue(forKey: symbol.lowercased())
                Self.persistCache()
            }
            return
        }
        
        // PERFORMANCE FIX: Check cancellation before network request
        guard !Task.isCancelled else { return }
        
        // PERFORMANCE FIX v2: Defer network requests during scroll
        // Network I/O and image decoding compete with scroll rendering
        let shouldDefer = await MainActor.run {
            ScrollStateManager.shared.shouldBlockHeavyOperation()
        }
        
        if shouldDefer {
            // Wait for scroll to settle before network request
            // Use exponential backoff: 200ms, 400ms, 800ms...
            for attempt in 0..<5 {
                guard !Task.isCancelled else { return }
                let delay = UInt64(200 * (1 << attempt)) * 1_000_000 // ms to ns
                try? await Task.sleep(nanoseconds: min(delay, 1_500_000_000)) // cap at 1.5s
                
                let stillScrolling = await MainActor.run {
                    ScrollStateManager.shared.shouldBlockHeavyOperation()
                }
                if !stillScrolling { break }
            }
        }
        
        // Final cancellation check after potential wait
        guard !Task.isCancelled else { return }
        
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
        request.setValue("image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await Self.imageSession.data(for: request)
            
            // PERFORMANCE FIX: Check cancellation after network request
            guard !Task.isCancelled else { return }
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), !data.isEmpty {
                // Validate content-type header; allow image/* or octet-stream fallback
                if let ct = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() {
                    let ok = ct.contains("image/") || ct.contains("application/octet-stream")
                    if !ok {
                        await handleLoadFailure()
                        return
                    }
                }
                // Reject obviously tiny payloads (likely errors)
                if data.count < 64 {
                    await handleLoadFailure()
                    return
                }
                // Quick HTML sniff to avoid decoding error pages as images
                if data.prefix(32).contains(0x3C) { // '<'
                    // Heuristic: if payload looks like text/html, bail out
                    if let s = String(data: data.prefix(64), encoding: .utf8), s.lowercased().contains("<html") {
                        await handleLoadFailure()
                        return
                    }
                }
                
                // PERFORMANCE FIX v2: Defer image decoding during fast scroll
                // Image decoding is CPU-intensive and can cause jank
                let isFastScrolling = await MainActor.run {
                    ScrollStateManager.shared.isFastScrolling
                }
                if isFastScrolling {
                    // Brief pause to let scroll settle
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                }
                
                // PERFORMANCE FIX v3: Decode images on background thread to avoid main thread blocking
                // PERFORMANCE FIX v4: Downsample images to target size to reduce memory usage
                // Coin images displayed at 24-32pt don't need full 400px source resolution
                #if canImport(UIKit)
                let targetSize = await MainActor.run { self.size }
                let decodedImage: UIImage? = await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        // Use downsampling for memory efficiency
                        if let downsampled = Self.downsample(imageData: data, to: targetSize) {
                            continuation.resume(returning: downsampled)
                        } else {
                            // Fall back to regular decoding if downsampling fails
                            continuation.resume(returning: UIImage(data: data))
                        }
                    }
                }
                if let img = decodedImage {
                    Self.memoryCache.setObject(img, forKey: key)
                    Self.saveImageToDisk(img, for: url)
                    await MainActor.run {
                        self.loadedImage = img
                        self.lastGoodImage = self.loadedImage
                        Self.cachedSuccessBySymbol[symbol.lowercased()] = url
                        Self.failuresBySymbol[symbol.lowercased()] = 0
                        Self.lastFailureAtBySymbol.removeValue(forKey: symbol.lowercased())
                        Self.persistCache()
                    }
                    return
                }
                #elseif canImport(AppKit)
                let decodedImage: NSImage? = await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        continuation.resume(returning: NSImage(data: data))
                    }
                }
                if let img = decodedImage {
                    Self.memoryCache.setObject(img, forKey: key)
                    Self.saveImageToDisk(img, for: url)
                    await MainActor.run {
                        self.loadedImage = img
                        self.lastGoodImage = self.loadedImage
                        Self.cachedSuccessBySymbol[symbol.lowercased()] = url
                        Self.failuresBySymbol[symbol.lowercased()] = 0
                        Self.lastFailureAtBySymbol.removeValue(forKey: symbol.lowercased())
                        Self.persistCache()
                    }
                    return
                }
                #endif
            }
            await handleLoadFailure()
        } catch {
            await handleLoadFailure()
        }
    }

    private func handleLoadFailure() async {
        var canTryMore = true
        await MainActor.run {
            let key = symbol.lowercased()
            let newCount = (Self.failuresBySymbol[key] ?? 0) + 1
            Self.failuresBySymbol[key] = newCount
            Self.lastFailureAtBySymbol[key] = Date()
            canTryMore = newCount < Self.maxFailuresPerSession
        }
        if canTryMore {
            try? await Task.sleep(nanoseconds: 120_000_000)
            await MainActor.run { advanceToNextURL() }
        } else {
            await MainActor.run { self.currentURL = nil }
            // Auto-recover after cooldown so icons don't stay stuck for the whole session.
            try? await Task.sleep(nanoseconds: UInt64(Self.failureCooldownSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if self.currentURL == nil {
                    self.resetAttempts()
                }
            }
        }
    }

    var body: some View {
        ZStack {
            // Lightweight placeholder so rows never shrink
            Circle().fill(Color.white.opacity(0.10))
            Text(String(symbol.prefix(1)).uppercased())
                .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                .foregroundColor(Color.white.opacity(0.28))
                .accessibilityHidden(true)
            
            // Display image content
            imageContent
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .onAppear {
            // PERFORMANCE FIX: Quick memory-only cache check (non-blocking)
            initializeFromCacheSync()
        }
        .task(id: attemptKey) {
            // Check memory cache first (instant if already loaded)
            await MainActor.run {
                if let cachedImage = Self.getCachedImage(symbol: symbol, url: url) {
                    loadedImage = cachedImage
                    lastGoodImage = cachedImage
                }
            }
            if loadedImage != nil { return }
            
            // CRITICAL FIX: When the symbol changes (task restarts due to new attemptKey),
            // the old symbol's image may still be in loadedImage/lastGoodImage.
            // We MUST check the cache for the NEW symbol and clear old state if needed.
            // Without this, the old image prevents loading — `loadedImage != nil` skips all logic.
            await MainActor.run {
                // Fast path: check memory cache for the new symbol
                if let cachedImage = Self.getCachedImage(symbol: symbol, url: url) {
                    loadedImage = cachedImage
                    lastGoodImage = cachedImage
                } else if loadedImage != nil {
                    // Old symbol's image is present — clear it so we load the correct one
                    loadedImage = nil
                    lastGoodImage = nil
                }
            }
            
            // If memory cache hit, we're done
            if loadedImage != nil { return }
            
            // PERFORMANCE FIX: Async disk cache check (non-blocking)
            await initializeFromCacheAsync()
            
            // Only reset if we still don't have an image
            if loadedImage == nil && lastGoodImage == nil {
                await MainActor.run { resetAttempts() }
            }
        }
        .transaction { $0.disablesAnimations = true }
        .accessibilityLabel(Text("\(symbol.uppercased()) icon"))
    }
    
    // MARK: - Image Content View
    
    @ViewBuilder
    private var imageContent: some View {
        if let localName = localIconName(for: symbol) {
            Image(localName)
                .resizable()
                .scaledToFit()
        } else if let img = loadedImage ?? lastGoodImage {
            // Show cached/loaded image immediately
            #if canImport(UIKit)
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
            #elseif canImport(AppKit)
            Image(nsImage: img)
                .resizable()
                .scaledToFit()
            #endif
        } else if let activeURL = currentURL {
            // Loading state - trigger load
            Color.clear
                .task(id: activeURL) {
                    await loadImage(for: activeURL)
                }
        } else {
            // No URL available; show placeholder only
            Color.clear
        }
    }
    
    // MARK: - Initialize from Cache
    
    /// PERFORMANCE FIX: Quick synchronous memory-only cache check (non-blocking)
    /// Called in onAppear for instant display if image is already in memory
    private func initializeFromCacheSync() {
        // Skip if already loaded
        guard loadedImage == nil else { return }
        
        // Check memory cache only (fast, non-blocking)
        if let cachedImage = Self.getCachedImage(symbol: symbol, url: url) {
            self.loadedImage = cachedImage
            self.lastGoodImage = cachedImage
        }
    }
    
    /// PERFORMANCE FIX: Async disk cache check (non-blocking)
    /// Called in .task {} to check disk cache without blocking main thread
    private func initializeFromCacheAsync() async {
        // Skip if already loaded
        guard loadedImage == nil else { return }
        
        // Check cancellation
        guard !Task.isCancelled else { return }
        
        // Check both memory and disk cache asynchronously
        if let cachedImage = await Self.getCachedImageAsync(symbol: symbol, url: url) {
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.loadedImage = cachedImage
                self.lastGoodImage = cachedImage
            }
        }
    }
}

struct CoinImageView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            CoinImageView(symbol: "BTC", url: URL(string: "https://coin-images.coingecko.com/coins/images/1/large/bitcoin.png"), size: 32)
            CoinImageView(symbol: "BNB", url: URL(string: "https://coin-images.coingecko.com/coins/images/825/large/binance-coin-logo.png"), size: 32)
            CoinImageView(symbol: "XRP", url: URL(string: "http://example.com/xrp.png"), size: 32)
        }
        .previewLayout(.sizeThatFits)
        .padding()
        .background(Color.black)
        .preferredColorScheme(.dark)
    }
}

