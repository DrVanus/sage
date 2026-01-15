import Foundation

/// A lightweight RSS fetcher and parser for crypto news fallback.
/// Aggregates several well-known crypto RSS feeds and maps them to CryptoNewsArticle.
final class RSSFetcher: NSObject {
    // Common crypto RSS feeds
    private static let feedURLs: [URL] = [
        URL(string: "https://www.coindesk.com/arc/outboundfeeds/rss/")!,
        URL(string: "https://cointelegraph.com/rss")!,
        URL(string: "https://decrypt.co/feed")!,
        URL(string: "https://www.theblock.co/rss")!
    ]

    /// Fetches and parses RSS items across known feeds. Returns at most `limit` items.
    static func fetch(limit: Int = 30) async -> [CryptoNewsArticle] {
        var all: [CryptoNewsArticle] = []
        await withTaskGroup(of: [CryptoNewsArticle].self) { group in
            for url in feedURLs {
                group.addTask { await fetchSingle(url: url) }
            }
            for await result in group {
                all.append(contentsOf: result)
            }
        }
        // Deduplicate by URL
        var seen = Set<String>()
        let unique = all.filter { art in
            if seen.contains(art.id) { return false }
            seen.insert(art.id)
            return true
        }
        // Sort newest first and cap to limit
        return Array(unique.sorted(by: { $0.publishedAt > $1.publishedAt }).prefix(limit))
    }

    private static func fetchSingle(url: URL) async -> [CryptoNewsArticle] {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let parser = RSSFeedParser(data: data)
            return parser.parse()
        } catch {
            return []
        }
    }
}

// MARK: - Minimal RSS Parser

private final class RSSFeedParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var parser: XMLParser!

    // Channel-level info
    private var channelTitle: String = ""

    // Current item accumulation
    private var currentItem: [String: String] = [:]
    private var currentElement: String = ""
    private var foundChars: String = ""
    private var items: [[String: String]] = []

    init(data: Data) {
        self.data = data
        super.init()
        self.parser = XMLParser(data: data)
        self.parser.delegate = self
        self.parser.shouldProcessNamespaces = true
    }

    func parse() -> [CryptoNewsArticle] {
        parser.parse()
        return items.compactMap { mapToArticle($0) }
    }

    // MARK: XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        let name = elementName.lowercased()
        currentElement = name
        foundChars = ""
        if name == "item" { currentItem = [:] }
        // Images: enclosure or media:content / media:thumbnail
        if name == "enclosure", let url = attributeDict["url"], !url.isEmpty {
            currentItem["image"] = url
        }
        if name.contains("media:content") || name.contains(":content"), let url = attributeDict["url"], !url.isEmpty {
            currentItem["image"] = url
        }
        if name.contains("media:thumbnail") || name.contains(":thumbnail"), let url = attributeDict["url"], !url.isEmpty {
            currentItem["image"] = url
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        foundChars += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.lowercased()
        let trimmed = foundChars.trimmingCharacters(in: .whitespacesAndNewlines)
        if name == "title" {
            if currentItem.isEmpty {
                // channel title
                channelTitle = trimmed
            } else {
                currentItem["title"] = trimmed
            }
        } else if name == "link" {
            currentItem["link"] = trimmed
        } else if name == "guid" {
            // sometimes GUID is the canonical link
            if currentItem["link"] == nil { currentItem["link"] = trimmed }
        } else if name == "pubdate" || name == "published" || name == "updated" || name == "dc:date" {
            currentItem["pubDate"] = trimmed
        } else if name == "source" {
            currentItem["source"] = trimmed
        } else if name == "description" {
            currentItem["description"] = trimmed
        } else if name == "item" {
            items.append(currentItem)
            currentItem = [:]
        }
        foundChars = ""
    }

    // MARK: Mapping

    private func mapToArticle(_ item: [String: String]) -> CryptoNewsArticle? {
        guard let title = item["title"], !title.isEmpty else { return nil }
        guard let linkStr = item["link"], let url = URL(string: linkStr) else { return nil }
        let desc = item["description"]
        let img = URL(string: item["image"] ?? "")
        let source = item["source"]?.isEmpty == false ? item["source"]! : (channelTitle.isEmpty ? (url.host ?? "RSS") : channelTitle)
        let date = parseDate(item["pubDate"]) ?? Date()
        return CryptoNewsArticle(title: title, description: desc, url: url, urlToImage: img, sourceName: source, publishedAt: date)
    }

    private func parseDate(_ s: String?) -> Date? {
        guard let s = s, !s.isEmpty else { return nil }
        // Try ISO8601 first
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        if let d = iso.date(from: s) { return d }
        // Common RSS RFC822 formats
        let fmts = [
            "E, d MMM yyyy HH:mm:ss Z",
            "E, dd MMM yyyy HH:mm:ss Z",
            "E, d MMM yyyy HH:mm Z",
            "E, dd MMM yyyy HH:mm Z",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        ]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        for f in fmts {
            df.dateFormat = f
            if let d = df.date(from: s) { return d }
        }
        return nil
    }
}
