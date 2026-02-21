import Foundation

/// Simple concurrency limiter to avoid spawning too many HTML/icon requests at once
actor SimpleLimiter {
    private let limit: Int
    private var current: Int = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(limit: Int) { self.limit = max(1, limit) }
    func acquire() async {
        if current < limit {
            current += 1
            return
        }
        await withCheckedContinuation { cont in
            waiters.append(cont)
        }
        current += 1
    }
    func release() {
        if !waiters.isEmpty {
            let cont = waiters.removeFirst()
            cont.resume()
        } else {
            current = max(0, current - 1)
        }
    }
}

/// Resolves a representative thumbnail image URL for an article URL by scraping
/// common meta tags (og:image, twitter:image) from the HTML document.
actor LinkThumbnailResolver {
    static let shared = LinkThumbnailResolver()
    private var cache: [URL: URL] = [:]
    private var negativeCache: Set<URL> = []
    private let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    private var diskCache: [String: String] = [:]   // articleURL.absoluteString -> imageURL.absoluteString
    private let cacheFileName = "thumb_cache.json"
    /// Domains to skip HTML fetching for - sites with aggressive anti-bot protection
    /// Note: Medium and Substack removed - they often have valid og:image tags
    private let skipHTMLDomains: Set<String> = [
        // Sites with anti-bot protection that reliably block scraping
        "seekingalpha.com",
        "finance.yahoo.com"
    ]
    
    /// Trusted CDNs that reliably serve images - skip HEAD validation entirely
    /// Many CDNs block HEAD requests but reliably serve images on GET
    private let trustedImageCDNs: Set<String> = [
        // Major crypto news image CDNs
        "images.cointelegraph.com", "s3.cointelegraph.com",
        "cdn.decrypt.co", "img.decrypt.co",
        "coindesk-coindesk-prod.cdn.arcpublishing.com",
        "static.coindesk.com", "www.coindesk.com",
        "images.coindeskassets.com",
        "static.theblock.co", "www.theblock.co",
        "blockworks.co",
        "cryptoslate.com", "img.cryptoslate.com",
        "newsbtc.com", "www.newsbtc.com",
        "beincrypto.com", "s32659.pcdn.co",
        "cryptopotato.com",
        "u.today",
        "bitcoinmagazine.com",
        "ambcrypto.com",
        "coingape.com",
        "cryptonews.com",
        "dailyhodl.com",
        "bitcoinist.com",
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
        "cryptocompare.com", "resources.cryptocompare.com"
    ]
    
    /// Circuit breaker: track domains that have failed recently to avoid repeated timeouts
    private var failedDomains: [String: Date] = [:]
    private let failedDomainCooldown: TimeInterval = 60 // 1 minute - reduced for faster recovery on mobile
    private static let limiter = SimpleLimiter(limit: 3) // MEMORY FIX v12: Reduced from 8 to 3 — each resolve downloads full HTML page
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        cfg.timeoutIntervalForRequest = 8  // Increased for mobile network reliability
        cfg.timeoutIntervalForResource = 15 // Increased for slower connections
        cfg.waitsForConnectivity = false
        cfg.httpMaximumConnectionsPerHost = 8 // Balanced connection limit
        return URLSession(configuration: cfg)
    }()

    init() {
        if let saved: [String: String] = CacheManager.shared.load([String: String].self, from: cacheFileName) {
            diskCache = saved
        }
    }

    func resolve(for articleURL: URL) async -> URL? {
        // Enforce ATS: upgrade the article URL to HTTPS and refuse non-HTTPS
        var base = articleURL
        if base.scheme?.lowercased() == "http" {
            if var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) {
                comps.scheme = "https"
                base = comps.url ?? base
            }
        } else if base.scheme == nil {
            if let https = URL(string: "https:" + base.absoluteString) { base = https }
        }
        guard base.scheme?.lowercased() == "https" else {
            // As a last resort, try returning a Google favicon (HTTPS)
            return googleFavicon(for: articleURL)
        }

        // 0) Prefer a previously resolved, non-icon image
        if let cached = cache[base], !isLikelySiteIcon(cached) {
            return cached
        }
        if let mapped = diskCache[base.absoluteString], let url = URL(string: mapped) {
            if !isLikelySiteIcon(url) {
                cache[base] = url
                return url
            }
            // If the cached mapping looks like a site icon, try to upgrade below
        }
        if negativeCache.contains(base) { return nil }
        // Check static blocklist and circuit breaker
        let host = base.host?.lowercased() ?? ""
        let shouldSkipHTML = skipHTMLDomains.contains(host) || isDomainInCooldown(host)
        
        if shouldSkipHTML {
            // Skip HTML resolve for known slow/blocked sites; try icons immediately
            if let icon = await firstReachableURL([googleFavicon(for: base)].compactMap { $0 }) {
                let final = sanitize(icon, base: base)
                cache[base] = final
                return final
            }
            // Fall through to default icon candidates
        }

        // Throttle resolver concurrency so we don't overwhelm the network on list loads
        await Self.limiter.acquire()
        defer { Task { await Self.limiter.release() } }

        // 1) Prefer extracting a real article image from HTML first (if not in blocklist)
        if !shouldSkipHTML {
            var req = URLRequest(url: base)
            req.httpMethod = "GET"
            req.timeoutInterval = 8.0 // Extended timeout for better og:image scraping success
            req.cachePolicy = .returnCacheDataElseLoad
            req.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
            req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            req.setValue("bytes=0-32767", forHTTPHeaderField: "Range") // Increased to 32KB to capture more meta tags
            do {
                let (data, _) = try await Self.session.data(for: req)
                if let html = decodeHTML(from: data), let url = extractImage(from: html, base: base) {
                    let final = sanitize(url, base: base)
                    cache[base] = final
                    diskCache[base.absoluteString] = final.absoluteString
                    saveDiskCache()
                    return final
                }
            } catch {
                // Record failure for circuit breaker
                recordDomainFailure(host)
            }
        }

        // 2) Fallback: try Google S2 favicon first, then a reduced set of site icon candidates
        var candidates: [URL] = []
        if let s2 = googleFavicon(for: base) { candidates.append(s2) }
        candidates.append(contentsOf: Array(siteIconCandidates(for: base).prefix(4))) // Reduced from 6 to minimize requests
        if let icon = await firstReachableURL(candidates) {
            let final = sanitize(icon, base: base)
            cache[base] = final
            // Intentionally do NOT persist to disk so a future resolve can upgrade to a real article image
            return final
        }

        // 3) Give up and remember negative result
        negativeCache.insert(base)
        return nil
    }

    private func saveDiskCache() {
        CacheManager.shared.save(diskCache, to: cacheFileName)
    }

    private func decodeHTML(from data: Data) -> String? {
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .isoLatin1) { return s }
        if let s = String(data: data, encoding: .windowsCP1252) { return s }
        return nil
    }

    private func firstReachableURL(_ candidates: [URL]) async -> URL? {
        if candidates.isEmpty { return nil }
        return await withTaskGroup(of: URL?.self) { group in
            for url in candidates {
                group.addTask { await self.headOK(url) ? url : nil }
            }
            for await result in group {
                if let ok = result { group.cancelAll(); return ok }
            }
            return nil
        }
    }

    private func googleFavicon(for base: URL) -> URL? {
        guard let host = base.host?.lowercased(), !host.isEmpty else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=256")
    }

    private func headOK(_ url: URL) async -> Bool {
        // Enforce ATS: upgrade to HTTPS and refuse non-HTTPS candidates
        var target = url
        if target.scheme?.lowercased() == "http" {
            if var comps = URLComponents(url: target, resolvingAgainstBaseURL: false) {
                comps.scheme = "https"
                target = comps.url ?? target
            }
        } else if target.scheme == nil {
            if let https = URL(string: "https:" + target.absoluteString) { target = https }
        }
        guard target.scheme?.lowercased() == "https" else {
            return false
        }
        
        // Skip validation for trusted CDNs - they reliably serve images
        if let host = target.host?.lowercased() {
            for cdn in trustedImageCDNs where host.contains(cdn) {
                // Still filter out obvious tiny icons
                if isLikelyTinyIconPath(target.path) || target.pathExtension.lowercased() == "ico" {
                    return false
                }
                return true
            }
        }

        // HEAD request with reasonable timeout
        var head = URLRequest(url: target)
        head.httpMethod = "HEAD"
        head.timeoutInterval = 4.0 // Increased for reliability
        head.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        head.setValue("image/*,*/*;q=0.5", forHTTPHeaderField: "Accept")
        do {
            let (_, resp) = try await Self.session.data(for: head)
            if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                let ct = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
                if ct.contains("image") {
                    // Filter out obviously tiny favicons to avoid blurry thumbnails
                    if let lenStr = http.value(forHTTPHeaderField: "Content-Length"), let len = Int(lenStr), len > 0 {
                        if len < 4000 && isLikelySiteIcon(target) { return false }
                    }
                    if isLikelyTinyIconPath(target.path) { return false }
                    return true
                }
                // Some servers omit content type on HEAD; accept by extension but avoid tiny icons
                if isImagePath(target) {
                    if isLikelyTinyIconPath(target.path) || target.pathExtension.lowercased() == "ico" { return false }
                    return true
                }
            }
        } catch { /* fall through to tiny GET */ }

        // Tiny GET of first byte as fallback
        var get = URLRequest(url: target)
        get.httpMethod = "GET"
        get.timeoutInterval = 5.0 // Increased for reliability
        get.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        get.setValue("image/*,*/*;q=0.5", forHTTPHeaderField: "Accept")
        get.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        do {
            let (_, resp) = try await Self.session.data(for: get)
            if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) || http.statusCode == 206 {
                let ct = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
                if ct.contains("image") {
                    if isLikelyTinyIconPath(target.path) || target.pathExtension.lowercased() == "ico" { return false }
                    return true
                }
                if isImagePath(target) {
                    if isLikelyTinyIconPath(target.path) || target.pathExtension.lowercased() == "ico" { return false }
                    return true
                }
                return false
            }
            return false
        } catch {
            return false
        }
    }

    private func siteIconCandidates(for base: URL) -> [URL] {
        guard let host = base.host else { return [] }
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = host
        // Reduced to 5 most common/reliable paths to minimize network requests
        // Prioritize larger icons that render well as thumbnails
        let paths = [
            "/apple-touch-icon.png",       // Most common, usually 180x180
            "/apple-touch-icon-180x180.png",
            "/android-chrome-512x512.png", // Largest common icon
            "/favicon.png",                // PNG preferred over ICO
            "/favicon.ico"                 // Last resort fallback
        ]
        return paths.compactMap { p in
            var c = comps
            c.path = p
            return c.url
        }
    }

    private func extractImage(from html: String, base: URL) -> URL? {
        // Try common meta tags (handle property/name and secure_url/src variants, single or double quotes, content before or after)
        let patterns = [
            // og:image (various shapes)
            "<meta[^>]*property=\\\"og:image\\\"[^>]*content=\\\"([^\\\"]+)\\\"",
            "<meta[^>]*name=\\\"og:image\\\"[^>]*content=\\\"([^\\\"]+)\\\"",
            "<meta[^>]*property=\\\"og:image:url\\\"[^>]*content=\\\"([^\\\"]+)\\\"",
            "<meta[^>]*property=\\\"og:image:secure_url\\\"[^>]*content=\\\"([^\\\"]+)\\\"",
            // twitter
            "<meta[^>]*name=\\\"twitter:image\\\"[^>]*content=\\\"([^\\\"]+)\\\"",
            "<meta[^>]*property=\\\"twitter:image\\\"[^>]*content=\\\"([^\\\"]+)\\\"",
            "<meta[^>]*name=\\\"twitter:image:src\\\"[^>]*content=\\\"([^\\\"]+)\\\"",
            // content-first variants
            "<meta[^>]*content=\\\"([^\\\"]+)\\\"[^>]*property=\\\"og:image(:secure_url|:url)?\\\"",
            "<meta[^>]*content=\\\"([^\\\"]+)\\\"[^>]*name=\\\"twitter:image(:src)?\\\"",
            // single-quote variants
            "<meta[^>]*property='og:image'[^>]*content='([^']+)'",
            "<meta[^>]*name='og:image'[^>]*content='([^']+)'",
            "<meta[^>]*property='og:image:url'[^>]*content='([^']+)'",
            "<meta[^>]*property='og:image:secure_url'[^>]*content='([^']+)'",
            "<meta[^>]*name='twitter:image'[^>]*content='([^']+)'",
            "<meta[^>]*property='twitter:image'[^>]*content='([^']+)'",
            "<meta[^>]*name='twitter:image:src'[^>]*content='([^']+)'",
            "<meta[^>]*content='([^']+)'[^>]*property='og:image(:secure_url|:url)?'",
            "<meta[^>]*content='([^']+)'[^>]*name='twitter:image(:src)?'",
            // link rel image_src
            "<link[^>]*rel=\\\"image_src\\\"[^>]*href=\\\"([^\\\"]+)\\\"",
            "<link[^>]*rel='image_src'[^>]*href='([^']+)'",
            // Common inline <img> fallback inside article bodies/snippets
            "<img[^>]*src=\\\"([^\\\"]+)\\\"",
            "<img[^>]*data-src=\\\"([^\\\"]+)\\\"",
            "<img[^>]*src='([^']+)'",
            "<img[^>]*data-src='([^']+)'"
        ]
        for pat in patterns {
            if let urlStr = firstMatch(in: html, pattern: pat) {
                if let absolute = URL(string: urlStr, relativeTo: base)?.absoluteURL { return absolute }
            }
        }
        // Try parsing srcset blocks to pick the largest candidate
        if let srcsetImage = parseSrcset(in: html, base: base) { return srcsetImage }
        // If we matched an //cdn.example.com path, make it https
        // (handled by sanitize later, but ensure URL init succeeds)

        // Try JSON-LD blocks for an image URL
        if let jsonImage = parseJSONLD(in: html, base: base) { return jsonImage }
        return nil
    }

    private func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        if let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1 {
            if let r = Range(match.range(at: 1), in: text) {
                return String(text[r])
            }
        }
        return nil
    }

    private func parseSrcset(in html: String, base: URL) -> URL? {
        // Capture srcset attributes from <img> or <source>
        let patterns = [
            "<img[^>]*srcset=\\\"([^\\\"]+)\\\"",
            "<img[^>]*srcset='([^']+)'",
            "<source[^>]*srcset=\\\"([^\\\"]+)\\\"",
            "<source[^>]*srcset='([^']+)'"
        ]
        for pat in patterns {
            guard let list = firstMatch(in: html, pattern: pat) else { continue }
            // Parse candidates of the form: URL [descriptor], separated by commas
            // e.g., https://cdn/img-400.jpg 400w, https://cdn/img-800.jpg 800w
            let parts = list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            var bestURL: URL? = nil
            var bestScore: Int = 0
            for part in parts {
                // Split into URL and optional descriptor
                let comps = part.split(separator: " ")
                guard let urlStr = comps.first else { continue }
                let abs = URL(string: String(urlStr), relativeTo: base)?.absoluteURL
                // Score by numeric descriptor if available, else by heuristic (prefer larger-looking filenames)
                var score = 0
                if comps.count > 1 {
                    let desc = comps[comps.count - 1].lowercased()
                    if desc.hasSuffix("w") || desc.hasSuffix("x") {
                        let digits = desc.trimmingCharacters(in: CharacterSet(charactersIn: "0123456789").inverted)
                        if let n = Int(digits) { score = n }
                    }
                }
                if score == 0 {
                    // Heuristic: prefer URLs containing large numbers like 800, 1200, 1600
                    let p = String(urlStr)
                    if p.contains("1200") { score = 1200 }
                    else if p.contains("1080") { score = 1080 }
                    else if p.contains("1024") { score = 1024 }
                    else if p.contains("800") { score = 800 }
                    else if p.contains("640") { score = 640 }
                }
                if let abs = abs {
                    // Skip obvious tiny icons
                    if isLikelyTinyIconPath(abs.path) || abs.pathExtension.lowercased() == "ico" { continue }
                    if score > bestScore { bestScore = score; bestURL = abs }
                }
            }
            if let u = bestURL { return u }
        }
        return nil
    }

    private func isImagePath(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["png","jpg","jpeg","webp","gif","ico"].contains(ext)
    }

    private func isLikelyTinyIconPath(_ path: String) -> Bool {
        let p = path.lowercased()
        let smallHints = ["16x16", "24x24", "32x32", "48x48", "favicon-16x16", "favicon-32x32"]
        return smallHints.contains { p.contains($0) }
    }

    private func isLikelySiteIcon(_ url: URL) -> Bool {
        let p = url.lastPathComponent.lowercased()
        let ext = url.pathExtension.lowercased()
        let path = url.path.lowercased()
        // Check specific icon patterns - less aggressive to avoid rejecting article images
        if p.contains("favicon") || p.contains("apple-touch-icon") || p.contains("touch-icon") || p.contains("site-icon") {
            return true
        }
        // Only match exact logo filenames, not paths containing "logo" as part of article content
        if p == "logo.png" || p == "logo.jpg" || p == "logo.webp" || p.hasPrefix("logo-") || p.hasPrefix("logo_") {
            return true
        }
        // Match explicit logo directories
        if path.contains("/logos/") || path.contains("/logo/") {
            return true
        }
        if isLikelyTinyIconPath(url.path) { return true }
        return ["ico", "svg"].contains(ext)
    }

    private func parseJSONLD(in html: String, base: URL) -> URL? {
        // Grab simple image fields from JSON-LD: "image": "..." or "image": { "url": "..." }
        let patterns = [
            "\\\"image\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"",
            "\\\"image\\\"\\s*:\\s*\\{[^}]*\\\"url\\\"\\s*:\\s*\\\"([^\\\"]+)\\\""
        ]
        for pat in patterns {
            if let s = firstMatch(in: html, pattern: pat) {
                if let absolute = URL(string: s, relativeTo: base)?.absoluteURL { return absolute }
            }
        }
        return nil
    }

    private func sanitize(_ url: URL, base: URL) -> URL {
        if url.scheme == "http" {
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            comps?.scheme = "https"
            return comps?.url ?? url
        }
        if url.scheme == nil {
            if let https = URL(string: "https:" + url.absoluteString) { return https }
        }
        // Remove common tracking params that sometimes cause 403s from CDNs
        if var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            let blocked = Set(["utm_source","utm_medium","utm_campaign","utm_term","utm_content","fbclid","gclid"]) 
            if let items = comps.queryItems, !items.isEmpty {
                comps.queryItems = items.filter { !blocked.contains($0.name.lowercased()) }
                if let cleaned = comps.url { return cleaned }
            }
        }
        return url
    }

    private func fallbackFavicon(for articleURL: URL) -> URL? {
        guard let host = articleURL.host else { return nil }
        var comps = URLComponents()
        comps.scheme = articleURL.scheme ?? "https"
        comps.host = host
        comps.path = "/favicon.ico"
        return comps.url
    }
    
    // MARK: - Circuit Breaker
    
    /// Check if a domain is currently in cooldown due to recent failures
    private func isDomainInCooldown(_ host: String) -> Bool {
        guard !host.isEmpty else { return false }
        if let failedAt = failedDomains[host] {
            return Date().timeIntervalSince(failedAt) < failedDomainCooldown
        }
        return false
    }
    
    /// Record a domain failure to trigger circuit breaker cooldown
    private func recordDomainFailure(_ host: String) {
        guard !host.isEmpty else { return }
        failedDomains[host] = Date()
        // Clean up old entries periodically to avoid memory growth
        if failedDomains.count > 100 {
            let cutoff = Date().addingTimeInterval(-failedDomainCooldown)
            failedDomains = failedDomains.filter { $0.value > cutoff }
        }
    }
}

