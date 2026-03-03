// ArticleURLResolver.swift
// Shared canonical URL resolver for news articles

import Foundation
import os.log

private let newsLog = OSLog(subsystem: "com.cryptosage.news", category: "resolver")

final class ArticleURLResolver {
    static let shared = ArticleURLResolver()
    private init() {}

    // MARK: Public API
    func resolve(url: URL) async -> URL? {
        let start = sanitizedForResolver(unwrapRedirectIfNeeded(url))

        // Try HEAD first (fast), then GET a small byte range to parse canonical
        let attempts: [URLRequest] = [
            makeRequest(url: start, method: "HEAD"),
            makeRequest(url: start, method: "GET", range: 0..<8192)
        ].compactMap { $0 }

        for req in attempts {
            if let u = await perform(req: req) { return u }
        }

        // As a final attempt, GET a small document and parse HTML
        if let final = await fetchAndParseHTML(url: start) { return final }
        ResolverDebug.warn("Resolver failed for: \(start.absoluteString)")
        return nil
    }

    // MARK: Internals
    private func makeRequest(url: URL, method: String, range: Range<Int>? = nil) -> URLRequest? {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 6
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148", forHTTPHeaderField: "User-Agent")
        if let r = range { req.setValue("bytes=\(r.lowerBound)-\(r.upperBound)", forHTTPHeaderField: "Range") }
        return req
    }

    private func perform(req: URLRequest) async -> URL? {
        for _ in 0..<2 { // retry once on timeout
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let u = extractCanonical(from: data, response: resp) {
                    ResolverDebug.log("Resolved via \(req.httpMethod ?? "?") to: \(u.absoluteString)")
                    return u
                }
                if let http = resp as? HTTPURLResponse,
                   let loc = http.value(forHTTPHeaderField: "Location"),
                   let u = URL(string: loc) {
                    ResolverDebug.log("Following Location to: \(u.absoluteString)")
                    return sanitizedForResolver(unwrapRedirectIfNeeded(u))
                }
            } catch let e as URLError {
                if e.code == .timedOut {
                    ResolverDebug.warn("Timeout on \(req.httpMethod ?? "?") for: \(req.url?.absoluteString ?? "?")")
                    continue
                }
            } catch {
                break
            }
        }
        return nil
    }

    private func fetchAndParseHTML(url: URL) async -> URL? {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 6
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148", forHTTPHeaderField: "User-Agent")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let u = extractCanonical(from: data, response: resp) {
                ResolverDebug.log("Resolved via HTML parse to: \(u.absoluteString)")
                return u
            }
        } catch {
            // ERROR HANDLING FIX: Log errors for debugging
            #if DEBUG
            print("[ArticleURLResolver] URL resolution error: \(error.localizedDescription)")
            #endif
        }
        return nil
    }

    private func extractCanonical(from data: Data?, response: URLResponse) -> URL? {
        if let data, data.count > 0, let html = String(data: data, encoding: .utf8) {
            if let canon = parseCanonical(fromHTML: html) { return canon }
            if let og = parseOGURL(fromHTML: html) { return og }
        }
        if let u = response.url {
            ResolverDebug.log("Falling back to response URL: \(u.absoluteString)")
            return sanitizedForResolver(unwrapRedirectIfNeeded(u))
        }
        return nil
    }

    // MARK: HTML scanners
    private func parseCanonical(fromHTML html: String) -> URL? {
        if let relRange = html.range(of: "rel=\"canonical\"", options: [.caseInsensitive]) {
            let prefix = html[..<relRange.lowerBound]
            if let hrefStart = prefix.range(of: "href=\"", options: [.backwards, .caseInsensitive]) {
                let rest = html[hrefStart.upperBound...]
                if let end = rest.firstIndex(of: "\"") {
                    let urlStr = String(rest[..<end])
                    if let u = URL(string: urlStr) { return sanitizedForResolver(unwrapRedirectIfNeeded(u)) }
                }
            }
        }
        return nil
    }

    private func parseOGURL(fromHTML html: String) -> URL? {
        if let propRange = html.range(of: "property=\"og:url\"", options: [.caseInsensitive]) {
            let suffix = html[propRange.upperBound...]
            if let contentStart = suffix.range(of: "content=\"", options: [.caseInsensitive]) {
                let rest = suffix[contentStart.upperBound...]
                if let end = rest.firstIndex(of: "\"") {
                    let urlStr = String(rest[..<end])
                    if let u = URL(string: urlStr) { return sanitizedForResolver(unwrapRedirectIfNeeded(u)) }
                }
            }
        }
        return nil
    }

    // MARK: Sanitization helpers (scoped to resolver)
    private func sanitizedForResolver(_ url: URL) -> URL {
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if comps?.scheme?.lowercased() == "http" { comps?.scheme = "https" }
        let blocked = Set(["utm_source","utm_medium","utm_campaign","utm_term","utm_content","fbclid","gclid","igshid","mc_cid","mc_eid","si","s","ref","ref_src"])
        if let items = comps?.queryItems, !items.isEmpty {
            comps?.queryItems = items.filter { !blocked.contains($0.name.lowercased()) }
        }
        // no-op logging to avoid noise
        if var c = comps { c.host = c.host?.lowercased(); return c.url ?? url }
        return comps?.url ?? url
    }

    private func unwrapRedirectIfNeeded(_ url: URL) -> URL {
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
}

struct ResolverDebug {
    static func log(_ message: String) {
        os_log("%{public}@", log: newsLog, type: .debug, message)
    }
    static func warn(_ message: String) {
        os_log("%{private}@", log: newsLog, type: .error, message)
    }
}
