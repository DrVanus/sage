import Foundation

/// Centralized helpers for article links: sanitization and redirect unwrapping.
/// Use these to ensure consistent behavior across the app when opening/copying URLs.
enum ArticleLink {
    /// Upgrade to https, strip tracking params, lowercase host.
    static func sanitize(_ url: URL) -> URL {
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if comps?.scheme?.lowercased() == "http" { comps?.scheme = "https" }
        let blocked = Set(["utm_source","utm_medium","utm_campaign","utm_term","utm_content","fbclid","gclid","igshid","mc_cid","mc_eid","si","s","ref","ref_src"])
        if let items = comps?.queryItems, !items.isEmpty {
            comps?.queryItems = items.filter { !blocked.contains($0.name.lowercased()) }
        }
        if var c = comps { c.host = c.host?.lowercased(); return c.url ?? url }
        return comps?.url ?? url
    }

    /// Unwrap known redirector links (Google, Google News, Facebook, Feedburner/Feedproxy).
    static func unwrapRedirectIfNeeded(_ url: URL) -> URL {
        guard let host = url.host?.lowercased() else { return url }
        // Google redirect: https://www.google.com/url?q=... or &url=...
        if host.contains("google.") {
            let path = url.path.lowercased()
            if path == "/url" || path.hasPrefix("/url") {
                if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let value = comps.queryItems?.first(where: { ["q","url"].contains($0.name.lowercased()) })?.value,
                   let dest = URL(string: value) {
                    return dest
                }
            }
            if host == "news.google.com" {
                if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let value = comps.queryItems?.first(where: { $0.name.lowercased() == "url" })?.value,
                   let dest = URL(string: value) {
                    return dest
                }
            }
        }
        // Facebook redirect: https://l.facebook.com/l.php?u=...
        if host.contains("l.facebook.com") {
            if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let value = comps.queryItems?.first(where: { $0.name.lowercased() == "u" })?.value,
               let dest = URL(string: value) {
                return dest
            }
        }
        // Feedburner / Feedproxy
        if host.contains("feedproxy.google.com") || host.contains("feeds.feedburner.com") {
            if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let value = comps.queryItems?.first(where: { $0.name.lowercased() == "url" })?.value,
               let dest = URL(string: value) {
                return dest
            }
        }
        return url
    }

    /// Unwrap known redirectors, then sanitize.
    static func sanitizeAndUnwrap(_ url: URL) -> URL {
        sanitize(unwrapRedirectIfNeeded(url))
    }

    /// Detect publisher root URLs (e.g., https://cointelegraph.com/)
    static func isPublisherRoot(_ url: URL) -> Bool {
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty
    }
}
