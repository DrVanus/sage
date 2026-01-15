import Foundation

/// Resolves a representative thumbnail image URL for an article URL by scraping
/// common meta tags (og:image, twitter:image) from the HTML document.
actor LinkThumbnailResolver {
    static let shared = LinkThumbnailResolver()
    private var cache: [URL: URL] = [:]

    func resolve(for articleURL: URL) async -> URL? {
        if let cached = cache[articleURL] { return cached }
        var req = URLRequest(url: articleURL)
        req.httpMethod = "GET"
        req.timeoutInterval = 8
        req.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        req.setValue("CryptoSage/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let html = String(data: data, encoding: .utf8) else { return nil }
            if let url = extractImage(from: html, base: articleURL) {
                cache[articleURL] = url
                return url
            }
        } catch { }
        return nil
    }

    private func extractImage(from html: String, base: URL) -> URL? {
        // Look for common meta tags
        let patterns = [
            "<meta[^>]*property=\\\"og:image\\\"[^>]*content=\\\"([^\\\"]+)\\\"",
            "<meta[^>]*name=\\\"og:image\\\"[^>]*content=\\\"([^\\\"]+)\\\"",
            "<meta[^>]*name=\\\"twitter:image\\\"[^>]*content=\\\"([^\\\"]+)\\\"",
            "<meta[^>]*property=\\\"twitter:image\\\"[^>]*content=\\\"([^\\\"]+)\\\""
        ]
        for pat in patterns {
            if let urlStr = firstMatch(in: html, pattern: pat) {
                if let absolute = URL(string: urlStr, relativeTo: base)?.absoluteURL {
                    return absolute
                }
            }
        }
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
}
