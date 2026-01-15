import Foundation

/// Resolves a canonical article URL for pages that sometimes link to a publisher root.
/// Fast, best‑effort: small range GET + parse common tags (og:url, canonical).
actor LinkCanonicalResolver {
    static let shared = LinkCanonicalResolver()

    private var cache: [URL: URL] = [:]
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        cfg.timeoutIntervalForRequest = 2.0
        cfg.timeoutIntervalForResource = 4.0
        cfg.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: cfg)
    }()

    func resolve(for url: URL) async -> URL? {
        if let c = cache[url] { return c }
        var target = url
        if target.scheme?.lowercased() == "http" {
            var comps = URLComponents(url: target, resolvingAgainstBaseURL: false)
            comps?.scheme = "https"
            target = comps?.url ?? target
        }
        guard target.scheme?.lowercased() == "https" else { return nil }

        var req = URLRequest(url: target)
        req.httpMethod = "GET"
        req.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        req.setValue("bytes=0-8191", forHTTPHeaderField: "Range")
        req.timeoutInterval = 2.0

        do {
            let (data, _) = try await session.data(for: req)
            guard let html = decodeHTML(data) else { return nil }
            if let s = extractCanonical(from: html, base: target) {
                cache[url] = s
                return s
            }
        } catch { }
        return nil
    }

    private func decodeHTML(_ data: Data) -> String? {
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .isoLatin1) { return s }
        if let s = String(data: data, encoding: .windowsCP1252) { return s }
        return nil
    }

    private func extractCanonical(from html: String, base: URL) -> URL? {
        let patterns = [
            "<meta[^>]*property=\\\"og:url\\\"[^>]*content=\\\"([^\\\"]+)\\\"",
            "<meta[^>]*content=\\\"([^\\\"]+)\\\"[^>]*property=\\\"og:url\\\"",
            "<link[^>]*rel=\\\"canonical\\\"[^>]*href=\\\"([^\\\"]+)\\\"",
            "<link[^>]*href=\\\"([^\\\"]+)\\\"[^>]*rel=\\\"canonical\\\"",
            // single-quote variants
            "<meta[^>]*property='og:url'[^>]*content='([^']+)'",
            "<meta[^>]*content='([^']+)'[^>]*property='og:url'",
            "<link[^>]*rel='canonical'[^>]*href='([^']+)'",
            "<link[^>]*href='([^']+)'[^>]*rel='canonical'"
        ]
        for pat in patterns {
            if let u = firstMatch(in: html, pattern: pat, base: base) { return u }
        }
        return nil
    }

    private func firstMatch(in text: String, pattern: String, base: URL) -> URL? {
        guard let rx = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        if let m = rx.firstMatch(in: text, options: [], range: range), m.numberOfRanges > 1 {
            if let r = Range(m.range(at: 1), in: text) {
                let s = String(text[r])
                if let abs = URL(string: s, relativeTo: base)?.absoluteURL {
                    // Enforce https and strip tracking
                    var comps = URLComponents(url: abs, resolvingAgainstBaseURL: false)
                    if comps?.scheme?.lowercased() == "http" { comps?.scheme = "https" }
                    let blocked = Set(["utm_source","utm_medium","utm_campaign","utm_term","utm_content","fbclid","gclid","igshid","mc_cid","mc_eid"])
                    if let items = comps?.queryItems, !items.isEmpty {
                        comps?.queryItems = items.filter { !blocked.contains($0.name.lowercased()) }
                    }
                    if var c = comps { c.host = c.host?.lowercased(); return c.url ?? abs }
                    return comps?.url ?? abs
                }
            }
        }
        return nil
    }
}
