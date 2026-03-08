// NewsWebView.swift
// CryptoSage
//
// Created by DM on 4/18/25.
// Native SwiftUI crypto‑news feed (no WKWebView).

import SwiftUI
import WebKit
import ImageIO


actor AsyncLimiter {
    // MEMORY FIX v12: Reduced from 16 to 4 concurrent image downloads.
    // 16 simultaneous downloads+decodes created massive transient memory spikes
    // (each decode allocates a full RGBA bitmap + network buffers).
    static let thumbnails = AsyncLimiter(limit: 4)
    private let limit: Int
    private var permits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(limit: Int) { self.limit = limit; self.permits = limit }
    func acquire() async {
        if permits > 0 { permits -= 1; return }
        await withCheckedContinuation { cont in waiters.append(cont) }
        // Resumed with a transferred permit; do not change permits here.
    }
    func release() {
        if !waiters.isEmpty {
            let cont = waiters.removeFirst()
            cont.resume()
        } else {
            permits = min(limit, permits + 1)
        }
    }
}

// MARK: - Custom Shimmer Effect

private struct NewsShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.gray.opacity(0.3),
                        Color.gray.opacity(0.5),
                        Color.gray.opacity(0.3)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .rotationEffect(.degrees(30))
                .offset(x: phase * 300)
            )
            .mask(content)
            .onAppear {
                // MEMORY FIX: Guard startup animations — this was the LAST unguarded shimmer.
                // Each CachingAsyncImage creates one of these. With 20+ images loading
                // simultaneously, the GeometryReader + LinearGradient per frame generated
                // ~39 MB/s of allocations (the observed steady-state leak rate).
                guard !shouldSuppressStartupAnimations() else { return }
                guard !globalAnimationsKilled else { return }
                DispatchQueue.main.async {
                    guard !globalAnimationsKilled else { return }
                    guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
                    withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                        phase = 1
                    }
                }
            }
    }
}

extension View {
    /// Applies a shimmer animation to placeholder content.
    func shimmeringEffect() -> some View {
        modifier(NewsShimmerModifier())
    }
}

// MARK: -- Thumbnail Caching

actor ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSURL, UIImage>()
    
    /// Thread-safe synchronous cache for instant View body lookups.
    /// NSCache is internally thread-safe, so a static instance can be
    /// safely read from any thread (main thread during body evaluation).
    /// Populated alongside the actor's private cache on every successful load.
    private static let syncCache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        // MEMORY FIX v12: Explicit limits prevent unbounded growth.
        // Without limits, NSCache relies on system heuristics which can be too aggressive
        // under memory pressure — evicting images that immediately get re-loaded, creating
        // a positive feedback loop (evict → re-download → more pressure → more evictions).
        cache.countLimit = 30
        cache.totalCostLimit = 20 * 1024 * 1024 // 20 MB
        return cache
    }()
    
    /// Synchronous in-memory check — safe to call from View.body on the main thread.
    /// Returns the cached UIImage if previously loaded, nil otherwise.
    nonisolated static func cachedImageSync(for url: URL?) -> UIImage? {
        guard let url else { return nil }
        return syncCache.object(forKey: url as NSURL)
    }
    
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        cfg.timeoutIntervalForRequest = 5  // Increased from 3s for better reliability
        cfg.timeoutIntervalForResource = 12 // Increased from 8s for larger images
        cfg.waitsForConnectivity = false    // Don't wait - fail fast
        // MEMORY FIX v3: Reduced from 4MB/30MB to 1MB/10MB
        cfg.urlCache = URLCache(
            memoryCapacity: 1 * 1024 * 1024,   // MEMORY FIX v3: 1MB memory
            diskCapacity: 10 * 1024 * 1024,    // MEMORY FIX v3: 10MB disk
            diskPath: "ThumbnailCache"
        )
        cfg.httpMaximumConnectionsPerHost = 4   // MEMORY FIX v12: Reduced from 16 to match AsyncLimiter
        return URLSession(configuration: cfg)
    }()
    
    /// CDNs that reliably work without referer - skip retry attempt
    /// Expanded list for better coverage and reliability
    private static let fastCDNs: Set<String> = [
        // Major crypto news image CDNs
        "images.cointelegraph.com", "s3.cointelegraph.com",
        "cdn.decrypt.co", "img.decrypt.co",
        "coindesk-coindesk-prod.cdn.arcpublishing.com",
        "static.coindesk.com", "images.coindeskassets.com", "www.coindesk.com",
        "static.theblock.co", "www.theblock.co",
        "blockworks.co",
        "cryptoslate.com", "img.cryptoslate.com",
        "newsbtc.com", "www.newsbtc.com",
        "beincrypto.com", "s32659.pcdn.co",
        "cryptopotato.com", "u.today", "bitcoinmagazine.com",
        "dailyhodl.com", "bitcoinist.com", "cryptonews.com",
        // Additional crypto news sites
        "bitcoinworld.co.in", "www.bitcoinworld.co.in",
        "ambcrypto.com", "finbold.com", "coingape.com",
        "zycrypto.com", "cryptopolitan.com",
        // Generic CDNs
        "cloudfront.net", "amazonaws.com",
        "wp.com", "i0.wp.com", "i1.wp.com", "i2.wp.com",
        "imgur.com", "i.imgur.com",
        "fastly.net", "akamaized.net",
        "cdninstagram.com", "fbcdn.net",
        // Image optimization services
        "imgix.net", "imagekit.io", "cloudinary.com",
        // Major news outlets
        "static.reuters.com", "assets.bwbx.io",
        "images.wsj.net", "images.axios.com",
        "static01.nyt.com", "i.guim.co.uk",
        "ichef.bbci.co.uk", "media.cnn.com",
        "media.npr.org", "s.yimg.com",
        "media.zenfs.com", "cdn.vox-cdn.com",
        "cdn.arstechnica.net", "static.politico.com",
        "i.ytimg.com", "img.youtube.com",
        // Google services
        "google.com", "gstatic.com",
        "t1.gstatic.com", "t2.gstatic.com", "t3.gstatic.com",
        // Cryptocurrency data providers
        "cryptocompare.com", "resources.cryptocompare.com",
        "images.cryptocompare.com"
    ]
    
    /// Hosts that are known to be slow or unreliable - use shorter timeout and no retry
    private static let slowHosts: Set<String> = [
        "cdn.jwplayer.com",      // Video thumbnails timeout frequently
        "timestabloid.com"       // Known slow site
    ]
    
    private func isFastCDN(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return Self.fastCDNs.contains { host.contains($0) }
    }
    
    private func isSlowHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return Self.slowHosts.contains { host.contains($0) }
    }
    
    init() {
        cache.countLimit = 20  // MEMORY FIX v12: Increased from 10 to 20 — too few caused eviction storms
        // MEMORY FIX v12: Increased from 2MB to 15MB. With estimated RGBA cost (not PNG),
        // a 600×400 image at 3x scale = 600*3*400*3*4 = ~26 MB. To hold at least a few
        // decoded images we need more headroom. NSCache auto-evicts under system memory pressure.
        cache.totalCostLimit = 15 * 1024 * 1024
    }
    
    /// Minimum image dimension for article thumbnails (reject tiny favicons)
    private static let minThumbnailDimension: CGFloat = 200
    
    /// Check if image data meets minimum dimension requirements
    /// Returns nil if image is too small, otherwise returns (width, height)
    private func getImageDimensions(_ data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        return (width, height)
    }
    
    /// Check if image dimensions meet minimum requirements for thumbnails
    private func meetsMinimumDimensions(_ data: Data, minPixel: CGFloat = minThumbnailDimension) -> Bool {
        guard let dims = getImageDimensions(data) else { return false }
        // Image must be at least minPixel on both sides to avoid blurry scaling
        return CGFloat(dims.width) >= minPixel && CGFloat(dims.height) >= minPixel
    }
    
    private func downsampleImageData(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(max(400, min(maxPixel, 2048))), // Min 400 for sharp thumbnails
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
    
    private func allowsReferer(for url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return true }
        // Some CDNs (Google s2, DuckDuckGo icons) may reject arbitrary referers; skip for those
        if host.contains("google.com") { return false }
        if host.contains("duckduckgo.com") { return false }
        return true
    }
    
    private func upgradeToHTTPS(_ url: URL) -> URL {
        if url.scheme?.lowercased() == "http" {
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            comps?.scheme = "https"
            if let https = comps?.url { return https }
        }
        return url
    }
    
    func loadImage(from url: URL?, referer: URL?, maxPixel: CGFloat = 600) async -> UIImage? {
        guard let url = url else { return nil }
        let secureURL = upgradeToHTTPS(url)
        let key = secureURL as NSURL
        if let img = cache.object(forKey: key) {
            Self.syncCache.setObject(img, forKey: key) // Keep sync cache warm
            return img
        }
        
        // Hero images (maxPixel > 1200) get longer timeouts since they're prominently displayed
        let isHeroImage = maxPixel > 1200
        
        func request(_ targetURL: URL, referer: URL?) -> URLRequest {
            var req = URLRequest(url: targetURL)
            req.httpMethod = "GET"
            // Timeout strategy (optimized for reliability):
            // - Fast CDNs: 4.0s (reliable, but give them enough time)
            // - Slow hosts: 2.5s (fail fast to allow fallback)
            // - Hero images: 8.0s (worth waiting for prominent display)
            // - Regular thumbnails: 5.0s (balanced for reliability)
            if isFastCDN(targetURL) {
                req.timeoutInterval = 4.0
            } else if isSlowHost(targetURL) {
                req.timeoutInterval = 2.5
            } else if isHeroImage {
                req.timeoutInterval = 8.0
            } else {
                req.timeoutInterval = 5.0
            }
            req.cachePolicy = .returnCacheDataElseLoad
            req.setValue("image/webp,image/*;q=0.9,*/*;q=0.5", forHTTPHeaderField: "Accept")
            req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            req.setValue("en-US,en;q=0.8", forHTTPHeaderField: "Accept-Language")
            if let r = referer, allowsReferer(for: targetURL) {
                req.setValue(r.absoluteString, forHTTPHeaderField: "Referer")
            }
            return req
        }
        
        // Determine retry strategy: fast CDNs and slow hosts don't need retry
        // Fast CDNs work reliably; slow hosts should fail fast to allow fallback
        // Hero images get an extra retry attempt
        let maxAttempts: Int
        if isFastCDN(secureURL) || isSlowHost(secureURL) {
            maxAttempts = 1
        } else if isHeroImage {
            maxAttempts = 3  // Extra retry for hero images
        } else {
            maxAttempts = 2
        }
        
        for attempt in 0..<maxAttempts {
            let useReferer = (attempt == 0)
            let req = request(secureURL, referer: useReferer ? referer : nil)
            
            // Acquire permit before network request
            await AsyncLimiter.thumbnails.acquire()
            
            // Perform network request and process result
            let result = await performImageRequest(req, secureURL: secureURL, maxPixel: maxPixel)
            
            // CRITICAL: Release permit immediately after network completes, BEFORE any continue/return
            await AsyncLimiter.thumbnails.release()
            
            switch result {
            case .success(let img):
                // MEMORY FIX v12: Use estimated byte cost from pixel dimensions instead of
                // calling img.pngData()?.count. pngData() encodes the ENTIRE image to PNG
                // just to measure the byte count — creating a 500KB-2MB temporary Data buffer
                // per cached image. With concurrent loads, these pile up before ARC releases them.
                let estimatedCost = Int(img.size.width * img.scale * img.size.height * img.scale * 4) // RGBA bytes
                cache.setObject(img, forKey: key, cost: estimatedCost)
                // Also populate the static sync cache for instant View body lookups
                Self.syncCache.setObject(img, forKey: key, cost: estimatedCost)
                return img
            case .retry403 where useReferer:
                // Try again without referer
                continue
            case .retry403, .invalidResponse, .networkError:
                // Continue to next attempt
                continue
            }
        }
        return nil
    }
    
    /// Result of a single image request attempt
    private enum ImageRequestResult {
        case success(UIImage)
        case retry403           // Got 403, should retry without referer
        case invalidResponse    // Non-image response or validation failed
        case networkError       // Network error occurred
    }
    
    /// Perform a single image request attempt (separated for proper permit management)
    private func performImageRequest(_ req: URLRequest, secureURL: URL, maxPixel: CGFloat) async -> ImageRequestResult {
        do {
            let (data, resp) = try await Self.session.data(for: req)
            
            // Check HTTP status code first
            if let http = resp as? HTTPURLResponse {
                if http.statusCode == 403 {
                    return .retry403
                }
                // Skip non-success responses (except 304 which means use cache)
                if http.statusCode != 304 && !(200..<300).contains(http.statusCode) {
                    return .invalidResponse
                }
            }
            
            if data.count < 64 { return .invalidResponse }
            
            // Guard against non-image payloads (e.g., HTML error pages) to avoid CGImageSource errors
            var isImageResponse = false
            if let http = resp as? HTTPURLResponse {
                let ct = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
                if ct.contains("image/") { isImageResponse = true }
            }
            let ext = secureURL.pathExtension.lowercased()
            let isImagePathExt = ["png","jpg","jpeg","webp","gif","heic","heif","ico"].contains(ext)
            
            // Trust known favicon services even without image content-type or extension
            let isGoogleFavicon = secureURL.host?.contains("google.com") == true && secureURL.path.contains("/s2/favicons")
            let isDuckDuckGoFavicon = secureURL.host?.contains("duckduckgo.com") == true && secureURL.path.contains("/ip3/")
            let isTrustedFaviconService = isGoogleFavicon || isDuckDuckGoFavicon
            
            // Trust CryptoCompare images
            let isCryptoCompareImage = secureURL.host?.contains("cryptocompare.com") == true
            
            // Trust other known crypto news CDNs
            let isTrustedNewsCDN = isTrustedImageHost(secureURL)
            
            if !(isImageResponse || isImagePathExt || isTrustedFaviconService || isCryptoCompareImage || isTrustedNewsCDN) {
                return .invalidResponse
            }
            
            // Dimension validation: reject tiny images for non-favicon URLs
            // Favicons are expected to be small; article images should be at least 200x200
            let isFaviconURL = isTrustedFaviconService || secureURL.pathExtension.lowercased() == "ico"
            if !isFaviconURL && !meetsMinimumDimensions(data) {
                // Image is too small for a good thumbnail - reject and let fallback chain continue
                return .invalidResponse
            }
            
            if let img = downsampleImageData(data, maxPixel: maxPixel) ?? UIImage(data: data) {
                return .success(img)
            }
            return .invalidResponse
        } catch {
            return .networkError
        }
    }
    
    /// Check if URL is from a trusted image host that should bypass content-type validation
    private func isTrustedImageHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let trustedHosts = [
            // Major crypto news outlets
            "cointelegraph.com", "decrypt.co", "coindesk.com", "theblock.co",
            "bitcoinmagazine.com", "cryptoslate.com", "newsbtc.com", "beincrypto.com",
            "cryptopotato.com", "u.today", "ambcrypto.com", "coingape.com",
            "dailyhodl.com", "bitcoinist.com", "cryptonews.com", "finbold.com",
            "cryptopolitan.com", "zycrypto.com", "bitcoinworld.co.in", "investing.com",
            "blockworks.co", "coinpedia.org", "cryptobriefing.com", "nulltx.com",
            // Generic CDNs
            "cloudfront.net", "amazonaws.com", "wp.com", "imgur.com",
            "fastly.net", "akamaized.net", "imgix.net", "imagekit.io", "cloudinary.com",
            "cdninstagram.com", "fbcdn.net", "twimg.com",
            // Image optimization services
            "imageproxy", "images.unsplash.com", "pbs.twimg.com",
            // Major news outlets
            "reuters.com", "bwbx.io", "wsj.net", "axios.com", "nyt.com",
            "bbci.co.uk", "cnn.com", "npr.org", "yimg.com", "zenfs.com"
        ]
        return trustedHosts.contains { host.contains($0) }
    }
}

struct CachingAsyncImage: View {
    let url: URL?
    let referer: URL?
    var maxPixel: CGFloat = 600
    var body: some View {
        CachingAsyncImageContent(url: url, referer: referer, maxPixel: maxPixel)
    }
}

// MARK: - Simplified Load State
/// Single source of truth for image loading state - replaces complex boolean flags
private enum ImageLoadState: Equatable {
    case loading
    case loaded(UIImage, isIcon: Bool)
    case failed
    
    var image: UIImage? {
        if case .loaded(let img, _) = self { return img }
        return nil
    }
    
    var isIcon: Bool {
        if case .loaded(_, let isIcon) = self { return isIcon }
        return false
    }
    
    var hasRealImage: Bool {
        if case .loaded(_, let isIcon) = self { return !isIcon }
        return false
    }
}

private struct CachingAsyncImageContent: View {
    let url: URL?
    let referer: URL?
    var maxPixel: CGFloat
    
    // Simplified state: single enum instead of multiple booleans
    @State private var loadState: ImageLoadState = .loading
    @State private var loadTask: Task<Void, Never>? = nil
    @State private var activeKey: String = ""
    // Track opacity for smooth transitions
    @State private var imageOpacity: Double = 0
    // Track shimmer opacity for smooth crossfade
    @State private var shimmerOpacity: Double = 1.0
    
    /// Whether this is a hero image (larger display, worth waiting longer)
    private var isHeroImage: Bool { maxPixel > 1200 }
    /// Timeouts: 12s for hero images, 10s for regular thumbnails (increased for mobile reliability)
    private var overallTimeout: UInt64 { isHeroImage ? 12_000_000_000 : 10_000_000_000 }

    private func makeKey() -> String {
        let a = url?.absoluteString ?? "nil"
        let b = referer?.absoluteString ?? "nil"
        return a + "|" + b
    }
    
    // MARK: - Shared Utilities (delegates to NewsImageUtilities)
    
    private func googleFavicon(for base: URL) -> URL? {
        NewsImageUtilities.googleFavicon(for: base, size: 256)
    }
    
    private func publisherLogoURL(for articleURL: URL) -> URL? {
        NewsImageUtilities.publisherLogoURL(for: articleURL)
    }
    
    private static func isLikelyIconURL(_ url: URL?) -> Bool {
        NewsImageUtilities.isLikelyIconURL(url)
    }
    
    /// Simplified image loading - single pass with clear fallback chain
    /// Priority: Real article image > Resolved og:image > Favicon
    private func loadImage(for key: String) async {
        if Task.isCancelled { return }
        
        let urlIsIcon = Self.isLikelyIconURL(self.url)
        let isGoogleFavicon = self.url?.host?.contains("google.com") == true && self.url?.path.contains("/s2/favicons") == true
        let isDDGFavicon = self.url?.host?.contains("duckduckgo.com") == true
        let isFaviconURL = isGoogleFavicon || isDDGFavicon || urlIsIcon
        
        // Step 1: Try primary thumbnail URL if it's a REAL image (not a favicon/icon)
        if let imgURL = self.url, !isFaviconURL {
            if let img = await ThumbnailCache.shared.loadImage(from: imgURL, referer: referer, maxPixel: maxPixel) {
                setLoadedState(img, isIcon: false, forKey: key)
                return
            }
        }
        
        // Step 2: ALWAYS try resolver to find og:image from article HTML
        // This is the key step for getting real article images when RSS doesn't include them
        if let articleURL = self.referer {
            if let resolved = await LinkThumbnailResolver.shared.resolve(for: articleURL),
               !Self.isLikelyIconURL(resolved) {
                if let img = await ThumbnailCache.shared.loadImage(from: resolved, referer: articleURL, maxPixel: maxPixel) {
                    setLoadedState(img, isIcon: false, forKey: key)
                    return
                }
            }
        }
        
        // Step 3: If we have an icon URL from the ViewModel, try loading it
        // (Only if we haven't already loaded a real image)
        if let imgURL = self.url, isFaviconURL {
            if let img = await ThumbnailCache.shared.loadImage(from: imgURL, referer: nil, maxPixel: maxPixel) {
                setLoadedState(img, isIcon: true, forKey: key)
                return
            }
        }
        
        // Step 4: Try Google favicon as fallback
        if let articleURL = self.referer, !isGoogleFavicon {
            if let faviconURL = NewsImageUtilities.googleFavicon(for: articleURL, size: 256) {
                if let img = await ThumbnailCache.shared.loadImage(from: faviconURL, referer: nil, maxPixel: maxPixel) {
                    setLoadedState(img, isIcon: true, forKey: key)
                    return
                }
            }
        }
        
        // Step 5: Try DuckDuckGo favicon as absolute last resort
        if let articleURL = self.referer, !isDDGFavicon {
            if let ddgFavicon = duckDuckGoFavicon(for: articleURL) {
                if let img = await ThumbnailCache.shared.loadImage(from: ddgFavicon, referer: nil, maxPixel: maxPixel) {
                    setLoadedState(img, isIcon: true, forKey: key)
                    return
                }
            }
        }
        
        // All attempts failed - animate transition to placeholder
        await MainActor.run {
            guard key == self.activeKey else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                self.loadState = .failed
                self.shimmerOpacity = 0.0
            }
        }
    }
    
    /// DuckDuckGo favicon service as backup
    private func duckDuckGoFavicon(for url: URL) -> URL? {
        guard let host = url.host else { return nil }
        let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return URL(string: "https://icons.duckduckgo.com/ip3/\(domain).ico")
    }
    
    /// Set loaded state with smooth crossfade animation
    @MainActor
    private func setLoadedState(_ image: UIImage, isIcon: Bool, forKey key: String) {
        guard key == self.activeKey else { return }
        
        // Don't downgrade from real image to icon
        if loadState.hasRealImage && isIcon { return }
        
        // Apply state change with animation
        loadState = .loaded(image, isIcon: isIcon)
        
        // Smooth crossfade: fade out shimmer while fading in image
        withAnimation(.easeInOut(duration: 0.3)) {
            imageOpacity = 1.0
            shimmerOpacity = 0.0
        }
    }
    
    /// Start loading with timeout
    private func startLoading() {
        let key = makeKey()
        activeKey = key
        
        // Fast path: if the sync cache already has this image, skip the async load entirely.
        // The body's sync cache check will render it instantly.
        if let cached = ThumbnailCache.cachedImageSync(for: url) {
            loadState = .loaded(cached, isIcon: Self.isLikelyIconURL(url))
            imageOpacity = 1.0
            shimmerOpacity = 0.0
            return
        }
        
        // MEMORY FIX v12: Defer image loading during startup suppression window.
        // Image downloads + RGBA decoding at 600px = ~1 MB per image. With fallback chains
        // (primary → og:image → favicon) creating 3-5 concurrent requests per image,
        // the transient memory spike can be 30+ MB. During the critical startup window
        // this pushes memory past the jetsam limit.
        // Instead, schedule a delayed retry after the suppression window expires.
        if shouldSuppressStartupAnimations() {
            loadState = .loading
            imageOpacity = 0
            shimmerOpacity = 1.0
            // Retry after suppression window (45s from app start)
            loadTask?.cancel()
            loadTask = Task { @MainActor in
                // Wait until suppression ends (check every 2s)
                while shouldSuppressStartupAnimations() && !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
                guard !Task.isCancelled, key == self.activeKey else { return }
                self.startLoadingNow(key: key)
            }
            return
        }
        
        startLoadingNow(key: key)
    }
    
    /// Perform the actual image loading (called after startup suppression check)
    private func startLoadingNow(key: String) {
        loadState = .loading
        imageOpacity = 0
        shimmerOpacity = 1.0
        loadTask?.cancel()
        
        loadTask = Task(priority: .userInitiated) {
            // Run image loading with timeout
            await withTaskGroup(of: Void.self) { group in
                // Main loading task
                group.addTask {
                    await self.loadImage(for: key)
                }
                
                // Timeout task
                group.addTask {
                    try? await Task.sleep(nanoseconds: self.overallTimeout)
                    if !Task.isCancelled {
                        await MainActor.run {
                            if key == self.activeKey && self.loadState == .loading {
                                // Animate the timeout failure for consistency
                                withAnimation(.easeOut(duration: 0.25)) {
                                    self.loadState = .failed
                                    self.shimmerOpacity = 0.0
                                }
                            }
                        }
                    }
                }
                
                // Wait for loading to complete (timeout will just set failed state)
                await group.next()
                group.cancelAll()
            }
        }
    }
    
    var body: some View {
        ZStack {
            // PERFORMANCE FIX: Check synchronous in-memory cache FIRST.
            // When SwiftUI recreates views (e.g. ForEach rebuild during coin picker
            // dismiss), new instances start in .loading state and show the shimmer.
            // By checking the sync cache directly in the body, previously-loaded
            // images render instantly with zero flicker.
            if let cached = ThumbnailCache.cachedImageSync(for: url) {
                Image(uiImage: cached)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else {
                // Background placeholder with shimmer (fades out when image loads)
                placeholderView
                    .opacity(shimmerOpacity)
                
                // Loaded image with fade-in animation
                if let img = loadState.image {
                    Image(uiImage: img)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .clipped()
                        .opacity(imageOpacity)
                        .transition(.opacity)
                }
                
                // Failed state overlay
                if case .failed = loadState {
                    failedView
                        .transition(.opacity)
                }
            }
        }
        .onAppear {
            startLoading()
        }
        .onChange(of: url) { oldValue, newValue in
            guard oldValue != newValue else { return }
            // Allow upgrade from icon to real image
            if loadState.hasRealImage { return }
            if let newURL = newValue, !Self.isLikelyIconURL(newURL) {
                startLoading()
            }
        }
        .onDisappear {
            loadTask?.cancel()
        }
    }
    
    // MARK: - Subviews
    
    private var placeholderView: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.15), Color(white: 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            LinearGradient(
                colors: [Color.white.opacity(0.03), Color.clear, Color.white.opacity(0.02)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .shimmeringEffect()
    }
    
    private var failedView: some View {
        ZStack {
            // Premium dark gradient background
            LinearGradient(
                colors: [Color(white: 0.14), Color(white: 0.08), Color(white: 0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Subtle gold accent overlay
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.83, blue: 0.40).opacity(0.06),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Icon with subtle styling
            VStack(spacing: 4) {
                Image(systemName: "newspaper.fill")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.white.opacity(0.35), Color.white.opacity(0.18)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.1), Color.white.opacity(0.03)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
    }
}

// Formatter for absolute dates
private let fullDateFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateFormat = "MMM d yyyy, h:mm a"
    return df
}()

/// Skeleton row view for loading state
struct SkeletonNewsRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 100, height: 60)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 20)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 14)
            }
        }
        .redacted(reason: .placeholder)
        .shimmeringEffect()
        .padding(.vertical, 2)
    }
}

// MARK: - RelativeTimeText View

/// Displays a relative time label that updates every minute.
struct RelativeTimeText: View {
    let date: Date
    @State private var now = Date()
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(NewsDate.relative(for: NewsDate.clampIfUnrealistic(date), now: now))
            .onReceive(timer) { tick in
                guard !CryptoSageAIApp.isEmergencyStopActive() else { return }
                // Timer already fires on main thread, no need for DispatchQueue.main.async
                now = tick
            }
            .accessibilityLabel(NewsDate.absoluteShort(for: date))
    }
}

// MARK: -- Error View

struct CryptoNewsErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(message)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundColor(.white)

            Button(action: onRetry) {
                Text("Retry")
                    .font(.caption2)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(Color.yellow)
                    .foregroundColor(.black)
                    .cornerRadius(6)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.red.opacity(0.8))
        .cornerRadius(8)
    }
}


// MARK: -- Row

struct CryptoNewsRow: View {
    @EnvironmentObject var viewModel: CryptoNewsFeedViewModel
    let article: CryptoNewsArticle

    var body: some View {
        UnifiedNewsRow(
            article: article,
            thumbnailURL: viewModel.thumbnailURL(for: article),
            showUnreadDot: !viewModel.isRead(article),
            isBookmarked: viewModel.isBookmarked(article)
        )
        .swipeActions(edge: .leading) {
            Button {
                viewModel.toggleRead(article)
            } label: {
                Label(viewModel.isRead(article) ? "Mark Unread" : "Mark Read",
                      systemImage: viewModel.isRead(article) ? "envelope.open" : "envelope.badge")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                viewModel.toggleBookmark(article)
            } label: {
                Image(systemName: viewModel.isBookmarked(article) ? "bookmark.fill" : "bookmark")
                    .font(.title2)
                    .accessibilityLabel(viewModel.isBookmarked(article) ? "Remove Bookmark" : "Bookmark")
            }
            .tint(.orange)

            Button {
                UIPasteboard.general.url = article.url
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.title2)
                    .accessibilityLabel("Copy Link")
            }
            .tint(.gray)

            Button {
                UIApplication.shared.open(article.url)
            } label: {
                Image(systemName: "safari")
                    .font(.title2)
                    .accessibilityLabel("Open in Safari")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button(action: { UIApplication.shared.open(article.url) }) {
                Label("Open in Safari", systemImage: "safari")
            }
            Button(action: { UIPasteboard.general.url = article.url }) {
                Label("Copy Link", systemImage: "doc.on.doc")
            }
            ShareLink(item: article.url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
        .padding(.vertical, 8)
    }
}


import SwiftUI

struct NewsWebView: UIViewRepresentable {
    let url: URL
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    func makeUIView(context: Context) -> WKWebView {
        // PERFORMANCE FIX: Trigger prewarmer to ensure WebKit processes are ready
        // This reduces first-load lag when opening news articles
        WebKitPrewarmer.shared.warmUpIfNeeded()
        
        let config = WKWebViewConfiguration()
        // PERFORMANCE FIX: Optimize for content viewing
        config.suppressesIncrementalRendering = true
        config.allowsInlineMediaPlayback = true
        // SECURITY: Prevent JavaScript popups
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        var target = url
        if target.scheme?.lowercased() == "http" {
            var comps = URLComponents(url: target, resolvingAgainstBaseURL: false)
            comps?.scheme = "https"
            if let upgraded = comps?.url { target = upgraded }
        }
        context.coordinator.initialHost = target.host?.lowercased()
        webView.load(URLRequest(url: target))
    }
    
    // SECURITY: Navigation delegate to prevent phishing by restricting cross-origin
    // navigations to Safari and blocking non-HTTPS loads.
    class Coordinator: NSObject, WKNavigationDelegate {
        var initialHost: String?
        
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            // Allow about: and data: (initial loads)
            if url.scheme == "about" || url.scheme == "data" {
                decisionHandler(.allow)
                return
            }
            // Only allow HTTPS
            guard url.scheme == "https" else {
                decisionHandler(.cancel)
                return
            }
            // Allow same-domain navigation (the article itself, plus its subresources)
            if let host = url.host?.lowercased(),
               let initial = initialHost,
               (host == initial || host.hasSuffix(".\(initial)") || initial.hasSuffix(".\(host)")) {
                decisionHandler(.allow)
                return
            }
            // For link clicks to external domains, open in Safari instead
            if navigationAction.navigationType == .linkActivated {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            // Allow subresource loads (images, scripts from CDNs, etc.)
            decisionHandler(.allow)
        }
    }
}

