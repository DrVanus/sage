import Foundation

/// A lightweight RSS fetcher and parser for crypto news fallback.
/// Aggregates several well-known crypto RSS feeds and maps them to CryptoNewsArticle.
final class RSSFetcher: NSObject {
    // Expanded list of crypto RSS feeds for better coverage and redundancy
    private static let feedURLs: [URL] = [
        // Primary tier - most reliable
        URL(string: "https://www.coindesk.com/arc/outboundfeeds/rss/")!,
        URL(string: "https://cointelegraph.com/rss")!,
        URL(string: "https://decrypt.co/feed")!,
        // Note: theblock.co RSS discontinued (returns 404)
        // Secondary tier - good coverage
        URL(string: "https://www.newsbtc.com/feed/")!,
        URL(string: "https://cryptoslate.com/feed/")!,
        URL(string: "https://beincrypto.com/feed/")!,
        URL(string: "https://blockworks.co/feed/")!,
        URL(string: "https://coingape.com/feed/")!,
        URL(string: "https://bitcoinmagazine.com/feed")!,
        // Tertiary tier - additional sources
        URL(string: "https://ambcrypto.com/feed/")!,
        URL(string: "https://u.today/rss")!,
        URL(string: "https://cryptopotato.com/feed/")!,
        URL(string: "https://dailyhodl.com/feed/")!,
        URL(string: "https://cryptobriefing.com/feed/")!
    ]
    
    /// Dedicated session for RSS fetching with shorter timeouts
    private static let rssSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        config.waitsForConnectivity = false
        config.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: config)
    }()

    /// Maximum concurrent RSS feed fetches to prevent network saturation
    private static let maxConcurrentFeeds = 5
    
    // MARK: - Request Deduplication & Cancellation Protection
    /// Prevents duplicate concurrent RSS fetches
    private static var isFetching = false
    /// Last successful fetch time for throttling (only set on success)
    private static var lastFetchTime: Date?
    /// Minimum interval between fetches (seconds)
    private static let minFetchInterval: TimeInterval = 3.0
    /// Cache of last fetched articles for deduplication scenarios
    private static var cachedArticles: [CryptoNewsArticle] = []
    /// Continuations waiting for in-flight fetch to complete
    private static var pendingContinuations: [CheckedContinuation<[CryptoNewsArticle], Never>] = []
    /// Lock for thread-safe access to shared state
    private static let lock = NSLock()
    /// Flag to ensure first RSS fetch on app launch always completes (bypasses throttling)
    private static var hasCompletedFirstFetch = false

    // MARK: - Feed Health Tracking
    /// Tracks feeds that have failed recently to avoid blocking batch slots on chronically unreachable feeds.
    /// Key = feed host, Value = timestamp of last failure. Feeds are skipped if they failed within the cooldown period.
    private static var feedFailureTimes: [String: Date] = [:]
    /// How long to skip a feed after it fails (seconds). Prevents repeated 8s+ timeouts.
    private static let feedFailureCooldown: TimeInterval = 300 // 5 minutes
    
    /// Public fetch method - uses Task.detached to prevent parent cancellation from killing the fetch
    static func fetch(limit: Int = 30, before: Date? = nil) async -> [CryptoNewsArticle] {
        // Use detached task to prevent cancellation propagation from parent tasks
        return await Task.detached(priority: .userInitiated) {
            await fetchInternal(limit: limit, before: before)
        }.value
    }
    
    /// Internal fetch implementation - protected from parent task cancellation
    private static func fetchInternal(limit: Int, before: Date?) async -> [CryptoNewsArticle] {
        enum FetchDecision { case wait; case throttled([CryptoNewsArticle], TimeInterval); case proceed }
        
        let decision = lock.withLock { () -> FetchDecision in
            let isFirstFetch = !hasCompletedFirstFetch
            if isFetching {
                return .wait
            }
            if !isFirstFetch, let lastFetch = lastFetchTime, Date().timeIntervalSince(lastFetch) < minFetchInterval {
                return .throttled(cachedArticles, Date().timeIntervalSince(lastFetch))
            }
            isFetching = true
            if isFirstFetch {
                hasCompletedFirstFetch = true
                DebugLog.log("RSS", "First fetch on app launch - bypassing throttle")
            }
            return .proceed
        }
        
        switch decision {
        case .wait:
            DebugLog.log("RSS", "Waiting for in-flight fetch to complete")
            return await withCheckedContinuation { cont in
                lock.withLock { pendingContinuations.append(cont) }
            }
        case .throttled(let cached, let interval):
            DebugLog.log("RSS", "Throttled - fetched \(String(format: "%.1f", interval))s ago")
            if !cached.isEmpty {
                return Array(cached.prefix(limit))
            }
            // Cache empty, proceed with fetch anyway
            lock.withLock { isFetching = true }
        case .proceed:
            break
        }
        
        // Fetch completion handler to clean up and notify waiters
        func completeFetch(with articles: [CryptoNewsArticle]) {
            let waiters = lock.withLock {
                isFetching = false
                // Only update lastFetchTime if we got articles (Fix 6)
                if !articles.isEmpty {
                    cachedArticles = articles
                    lastFetchTime = Date()
                }
                let w = pendingContinuations
                pendingContinuations.removeAll()
                return w
            }
            // Resume all waiters with the result
            for cont in waiters {
                cont.resume(returning: Array(articles.prefix(limit)))
            }
        }
        
        DebugLog.log("RSS", "Fetching from \(feedURLs.count) feeds (max \(maxConcurrentFeeds) concurrent), limit=\(limit)")
        
        var all: [CryptoNewsArticle] = []
        var successfulFeeds = 0
        
        // Filter out feeds that have failed recently (avoid blocking batch slots with 8s+ timeouts)
        let now = Date()
        let healthyFeeds = lock.withLock {
            feedURLs.filter { url in
                guard let host = url.host, let failTime = feedFailureTimes[host] else { return true }
                return now.timeIntervalSince(failTime) >= feedFailureCooldown
            }
        }
        let skippedCount = feedURLs.count - healthyFeeds.count
        if skippedCount > 0 {
            DebugLog.log("RSS", "Skipping \(skippedCount) recently-failed feed(s)")
        }

        // Fetch feeds in batches to limit concurrency and prevent network saturation
        let batches = stride(from: 0, to: healthyFeeds.count, by: maxConcurrentFeeds).map {
            Array(healthyFeeds[$0..<min($0 + maxConcurrentFeeds, healthyFeeds.count)])
        }

        for batch in batches {
            await withTaskGroup(of: (String, [CryptoNewsArticle]).self) { group in
                for url in batch {
                    group.addTask {
                        let articles = await fetchSingle(url: url)
                        return (url.host ?? "unknown", articles)
                    }
                }
                for await (host, result) in group {
                    if !result.isEmpty {
                        successfulFeeds += 1
                        all.append(contentsOf: result)
                        // Clear failure tracking on success
                        lock.withLock { _ = feedFailureTimes.removeValue(forKey: host) }
                    }
                }
            }
            // Early exit if we have enough articles already
            if all.count >= limit * 2 { break }
        }
        
        DebugLog.log("RSS", "\(successfulFeeds)/\(feedURLs.count) feeds returned articles, total raw: \(all.count)")
        
        // Filter out articles with homepage-like URLs
        let validArticles = all.filter { !isHomepageLikeURL($0.url) }
        DebugLog.log("RSS", "Filtered \(validArticles.count)/\(all.count) articles (removed homepage URLs)")
        
        // Apply comprehensive quality filter using centralized NewsQualityFilter
        let qualityFiltered = validArticles.filter { art in
            NewsQualityFilter.passesQualityCheck(
                url: art.url,
                title: art.title,
                description: art.description,
                sourceName: art.sourceName
            )
        }
        DebugLog.log("RSS", "Quality filtered \(qualityFiltered.count)/\(validArticles.count) articles")
        
        // Deduplicate by URL and normalized title
        var seenURLs = Set<String>()
        var seenTitles = Set<String>()
        let unique = qualityFiltered.filter { art in
            // Skip if we've seen this exact URL
            if seenURLs.contains(art.id) { return false }
            seenURLs.insert(art.id)
            
            // Also dedupe by normalized title (handles cross-posts)
            let normalizedTitle = art.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if seenTitles.contains(normalizedTitle) { return false }
            seenTitles.insert(normalizedTitle)
            
            return true
        }
        
        // Sort newest first and cap to limit
        let sorted = unique.sorted(by: { $0.publishedAt > $1.publishedAt })
        
        // Complete the fetch - this caches results, updates timestamp (if successful), and notifies waiters
        completeFetch(with: sorted)
        
        if let b = before {
            // Use a small epsilon to avoid equality/tz rounding issues
            let cutoff = b.addingTimeInterval(-1)
            let filtered = sorted.filter { $0.publishedAt <= cutoff }
            DebugLog.log("RSS", "Returning \(min(filtered.count, limit)) articles (before cursor)")
            return Array(filtered.prefix(limit))
        } else {
            DebugLog.log("RSS", "Returning \(min(sorted.count, limit)) articles")
            return Array(sorted.prefix(limit))
        }
    }
    
    /// Check if a URL looks like a publisher homepage rather than an article
    private static func isHomepageLikeURL(_ url: URL) -> Bool {
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // Empty path = homepage
        if path.isEmpty { return true }
        // Single shallow path segment with no numbers is likely a section page
        let segments = path.split(separator: "/")
        if segments.count == 1 {
            let segment = String(segments[0]).lowercased()
            // Common section names
            let sectionNames: Set<String> = ["markets", "news", "latest", "crypto", "technology", "business", "finance", "cryptocurrency", "feed", "rss"]
            if sectionNames.contains(segment) { return true }
        }
        return false
    }

    private static func fetchSingle(url: URL, retryCount: Int = 0) async -> [CryptoNewsArticle] {
        let maxRetries = 1
        
        do {
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.timeoutInterval = 8
            req.setValue("application/rss+xml, application/atom+xml, application/xml, text/xml;q=0.9, */*;q=0.8", forHTTPHeaderField: "Accept")
            req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            req.setValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")
            
            let (data, response) = try await rssSession.data(for: req)
            
            if let http = response as? HTTPURLResponse {
                // Handle redirects and various success codes
                if (200..<300).contains(http.statusCode) {
                    // Success - parse the feed
                } else if http.statusCode == 301 || http.statusCode == 302 {
                    // Follow redirect manually if needed
                    if let location = http.value(forHTTPHeaderField: "Location"),
                       let redirectURL = URL(string: location) {
                        return await fetchSingle(url: redirectURL, retryCount: retryCount)
                    }
                    return []
                } else if http.statusCode >= 500 && retryCount < maxRetries {
                    // Server error - retry once after brief delay
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    return await fetchSingle(url: url, retryCount: retryCount + 1)
                } else {
                    DebugLog.log("RSS", "HTTP \(http.statusCode) from \(url.host ?? "unknown")")
                    return []
                }
            }
            
            let parser = RSSFeedParser(data: data, feedURL: url)
            let articles = parser.parse()
            
            if articles.isEmpty {
                DebugLog.log("RSS", "No articles parsed from \(url.host ?? "unknown") (data size: \(data.count))")
            } else {
                DebugLog.log("RSS", "Parsed \(articles.count) articles from \(url.host ?? "unknown")")
            }
            
            return articles
        } catch let error as URLError {
            // Retry on timeout if we haven't already
            if error.code == .timedOut && retryCount < maxRetries {
                return await fetchSingle(url: url, retryCount: retryCount + 1)
            }
            // Record failure so this feed is skipped for a cooldown period
            if let host = url.host {
                lock.withLock { feedFailureTimes[host] = Date() }
            }
            DebugLog.log("RSS", "URLError fetching \(url.host ?? "unknown"): \(error.localizedDescription) (will skip for 5min)")
            return []
        } catch {
            if let host = url.host {
                lock.withLock { feedFailureTimes[host] = Date() }
            }
            DebugLog.log("RSS", "Error fetching \(url.host ?? "unknown"): \(error.localizedDescription) (will skip for 5min)")
            return []
        }
    }
}

// MARK: - Improved RSS Parser

private final class RSSFeedParser: NSObject, XMLParserDelegate {
    private let data: Data
    private let feedURL: URL
    private var parser: XMLParser!

    // Channel-level info
    private var channelTitle: String = ""

    // Current item accumulation
    private var currentItem: [String: String] = [:]
    private var currentElement: String = ""
    private var foundChars: String = ""
    private var items: [[String: String]] = []
    private var inItem: Bool = false  // Track if we're inside an <item> or <entry>

    init(data: Data, feedURL: URL) {
        self.data = data
        self.feedURL = feedURL
        super.init()
        self.parser = XMLParser(data: data)
        self.parser.delegate = self
        self.parser.shouldProcessNamespaces = true
    }

    func parse() -> [CryptoNewsArticle] {
        parser.parse()
        return items.compactMap { mapToArticle($0) }
    }

    /// Extract the best image URL from HTML content, prioritizing larger/hero images
    private func extractBestImageURL(from html: String) -> String? {
        // Priority order: og:image > large images > any image
        let patterns: [(String, Int)] = [
            // OpenGraph image (often the hero/featured image)
            ("<meta[^>]*property=[\"']og:image[\"'][^>]*content=[\"']([^\"']+)[\"']", 100),
            ("<meta[^>]*content=[\"']([^\"']+)[\"'][^>]*property=[\"']og:image[\"']", 100),
            // Twitter card image
            ("<meta[^>]*name=[\"']twitter:image[\"'][^>]*content=[\"']([^\"']+)[\"']", 90),
            // Explicit figure/picture elements (usually article images)
            ("<figure[^>]*>.*?<img[^>]*src=[\"']([^\"']+)[\"']", 80),
            ("<picture[^>]*>.*?<img[^>]*src=[\"']([^\"']+)[\"']", 80),
            // Images with article-related classes
            ("<img[^>]*class=[\"'][^\"']*(?:featured|hero|article|post|main|cover)[^\"']*[\"'][^>]*src=[\"']([^\"']+)[\"']", 70),
            // data-src for lazy loaded images
            ("<img[^>]*data-src=[\"']([^\"']+)[\"']", 60),
            // Standard img tags
            ("<img[^>]*src=[\"']([^\"']+)[\"']", 50),
        ]
        
        var bestMatch: (url: String, priority: Int)? = nil
        
        for (pattern, priority) in patterns {
            if let url = firstMatch(in: html, pattern: pattern) {
                // Skip tiny images (likely icons/tracking pixels)
                if isLikelySmallImage(url) { continue }
                // Skip data URIs
                if url.hasPrefix("data:") { continue }
                
                if bestMatch == nil || priority > bestMatch!.priority {
                    bestMatch = (url, priority)
                }
            }
        }
        
        return bestMatch?.url
    }
    
    /// Check if URL looks like a small/icon image
    private func isLikelySmallImage(_ url: String) -> Bool {
        let lower = url.lowercased()
        // Check for size indicators in URL
        if lower.contains("1x1") || lower.contains("pixel") || lower.contains("spacer") { return true }
        if lower.contains("favicon") || lower.contains("icon") || lower.contains("logo") { return true }
        // Check for tracking pixels
        if lower.contains("tracking") || lower.contains("analytics") || lower.contains("beacon") { return true }
        return false
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

    // MARK: XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        let name = elementName.lowercased()
        currentElement = name
        foundChars = ""
        if name == "item" || name == "entry" { 
            currentItem = [:] 
            inItem = true
        }
        if name == "link", let href = attributeDict["href"], !href.isEmpty {
            // Only use href if it looks like an article URL (has path depth)
            if let url = URL(string: href), url.pathComponents.count > 2 {
                currentItem["link"] = href
            } else if currentItem["link"] == nil {
                currentItem["link"] = href
            }
        }
        
        // Images: prioritize media:content and media:thumbnail over enclosure
        if name.contains("media:content") || name.contains(":content"), let url = attributeDict["url"], !url.isEmpty {
            if !isLikelySmallImage(url) {
                currentItem["image"] = url
            }
        }
        if name.contains("media:thumbnail") || name.contains(":thumbnail"), let url = attributeDict["url"], !url.isEmpty {
            if currentItem["image"] == nil && !isLikelySmallImage(url) {
                currentItem["image"] = url
            }
        }
        if name == "enclosure", let url = attributeDict["url"], !url.isEmpty {
            let type = attributeDict["type"]?.lowercased() ?? ""
            if type.contains("image") && currentItem["image"] == nil && !isLikelySmallImage(url) {
                currentItem["image"] = url
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        foundChars += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.lowercased()
        let trimmed = foundChars.trimmingCharacters(in: .whitespacesAndNewlines)
        if name == "title" {
            if inItem {
                // Item/entry title
                currentItem["title"] = trimmed
            } else {
                // Channel-level title
                channelTitle = trimmed
            }
        } else if name == "link" {
            // Prefer links with actual path depth (article URLs)
            if let url = URL(string: trimmed) {
                if url.pathComponents.count > 2 || currentItem["link"] == nil {
                    currentItem["link"] = trimmed
                }
            } else if currentItem["link"] == nil {
                currentItem["link"] = trimmed
            }
        } else if name == "guid" {
            // Use GUID as link only if it's a valid URL and we don't have a better one
            if currentItem["link"] == nil, let _ = URL(string: trimmed), trimmed.hasPrefix("http") {
                currentItem["link"] = trimmed
            }
        } else if name == "pubdate" || name == "published" || name == "dc:date" {
            if currentItem["published"] == nil { currentItem["published"] = trimmed }
        } else if name == "updated" {
            if currentItem["updated"] == nil { currentItem["updated"] = trimmed }
        } else if name == "source" || name == "dc:creator" || name == "author" {
            if currentItem["source"] == nil { currentItem["source"] = trimmed }
        } else if name == "description" {
            currentItem["description"] = trimmed
            if currentItem["image"] == nil, let img = extractBestImageURL(from: trimmed) {
                currentItem["image"] = img
            }
        } else if name == "summary" {
            if !trimmed.isEmpty && currentItem["description"] == nil {
                currentItem["description"] = trimmed
            }
            if currentItem["image"] == nil, let img = extractBestImageURL(from: trimmed) {
                currentItem["image"] = img
            }
        } else if name.contains("content:encoded") || name == "content" {
            // content:encoded often has the full HTML with images
            if currentItem["image"] == nil, let img = extractBestImageURL(from: trimmed) {
                currentItem["image"] = img
            }
            // Only use content as description if we don't have one
            if currentItem["description"] == nil && !trimmed.isEmpty {
                // Strip HTML for description
                let strippedDesc = trimmed.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if strippedDesc.count > 50 {
                    currentItem["description"] = String(strippedDesc.prefix(500))
                }
            }
        } else if name == "item" || name == "entry" {
            // Final image extraction attempt from description
            if currentItem["image"] == nil, let desc = currentItem["description"], let img = extractBestImageURL(from: desc) {
                currentItem["image"] = img
            }
            items.append(currentItem)
            currentItem = [:]
            inItem = false  // Reset flag when exiting item/entry
        }
        foundChars = ""
    }

    // MARK: Mapping

    private func mapToArticle(_ item: [String: String]) -> CryptoNewsArticle? {
        guard let title = item["title"], !title.isEmpty else { return nil }
        guard let linkStr = item["link"], let url = URL(string: linkStr) else { return nil }
        
        // Validate that the URL looks like an article (not a homepage)
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.isEmpty { return nil } // Skip homepage URLs
        
        let desc = item["description"]
        let imgStr = item["image"] ?? ""
        var img: URL? = nil
        if !imgStr.isEmpty {
            // Handle protocol-relative URLs
            var imgURL = imgStr
            if imgURL.hasPrefix("//") {
                imgURL = "https:" + imgURL
            }
            img = URL(string: imgURL, relativeTo: url)?.absoluteURL
            // Upgrade to HTTPS
            if img?.scheme?.lowercased() == "http" {
                var comps = URLComponents(url: img!, resolvingAgainstBaseURL: false)
                comps?.scheme = "https"
                img = comps?.url
            }
        }
        
        // Clean up source name
        var source = item["source"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if source.isEmpty {
            source = channelTitle.isEmpty ? (url.host ?? "RSS") : channelTitle
        }
        // Remove common suffixes
        source = source.replacingOccurrences(of: " - RSS", with: "")
            .replacingOccurrences(of: " RSS", with: "")
            .replacingOccurrences(of: " Feed", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let publishedStr = item["published"] ?? item["pubDate"]
        let updatedStr = item["updated"]
        let date = parseDate(publishedStr) ?? parseDate(item["pubDate"]) ?? parseDate(updatedStr) ?? Date()
        
        return CryptoNewsArticle(title: title, description: desc, url: url, urlToImage: img, sourceName: source, publishedAt: date)
    }

    private func parseDate(_ s: String?) -> Date? {
        guard let s = s, !s.isEmpty else { return nil }
        
        // Try ISO8601 with fractional seconds first
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withFullDate, .withFullTime, .withFractionalSeconds, .withColonSeparatorInTimeZone]
        if let d = isoFrac.date(from: s) { return d }
        
        // Try standard ISO8601
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        if let d = iso.date(from: s) { return d }
        
        // Common RSS RFC822 formats
        let fmts = [
            "E, d MMM yyyy HH:mm:ss Z",
            "E, dd MMM yyyy HH:mm:ss Z",
            "E, d MMM yyyy HH:mm:ss zzz",
            "E, dd MMM yyyy HH:mm:ss zzz",
            "E, d MMM yyyy HH:mm Z",
            "E, dd MMM yyyy HH:mm Z",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd HH:mm:ss"
        ]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        for f in fmts {
            df.dateFormat = f
            if let d = df.date(from: s) { return d }
        }
        return nil
    }
}

