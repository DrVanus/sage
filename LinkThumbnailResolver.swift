import Foundation
import UIKit

actor LinkThumbnailResolver {
    private var cache = [URL: URL?]()
    private let skipHTMLDomains = [
        "wikipedia.org",
        "en.wikipedia.org",
        "wiktionary.org",
        "en.wiktionary.org"
    ]

    private func httpsURL(_ url: URL) -> URL {
        if url.scheme?.lowercased() == "http" {
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            comps?.scheme = "https"
            if let u = comps?.url { return u }
        }
        return url
    }

    func resolve(for articleURL: URL) async -> URL? {
        // Normalize article URL to HTTPS to avoid ATS blocks
        let base = httpsURL(articleURL)

        if let cached = cache[articleURL] {
            return cached
        }

        if let diskCached = await ThumbnailCache.shared.load(forKey: articleURL.absoluteString) {
            cache[articleURL] = diskCached
            return diskCached
        }

        if let host = base.host?.lowercased(), skipHTMLDomains.contains(host) {
            cache[articleURL] = nil
            await ThumbnailCache.shared.save(nil, forKey: articleURL.absoluteString)
            return nil
        }

        var req = URLRequest(url: base)
        req.httpMethod = "HEAD"
        if let resp = try? await URLSession.shared.data(for: req).1 as? HTTPURLResponse,
           let contentType = resp.value(forHTTPHeaderField: "Content-Type"),
           contentType.starts(with: "image") {
            cache[articleURL] = base
            await ThumbnailCache.shared.save(base, forKey: articleURL.absoluteString)
            return base
        }

        let googleFaviconURL = googleFavicon(for: base)
        if await checkURLExists(googleFaviconURL) {
            cache[articleURL] = googleFaviconURL
            await ThumbnailCache.shared.save(googleFaviconURL, forKey: articleURL.absoluteString)
            return googleFaviconURL
        }

        for candidate in siteIconCandidates(for: base) {
            if await checkURLExists(candidate) {
                cache[articleURL] = candidate
                await ThumbnailCache.shared.save(candidate, forKey: articleURL.absoluteString)
                return candidate
            }
        }

        if let fallback = fallbackFavicon(for: base) {
            cache[articleURL] = fallback
            await ThumbnailCache.shared.save(fallback, forKey: articleURL.absoluteString)
            return fallback
        }

        cache[articleURL] = nil
        await ThumbnailCache.shared.save(nil, forKey: articleURL.absoluteString)
        return nil
    }

    private func googleFavicon(for base: URL) -> URL {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "www.google.com"
        comps.path = "/s2/favicons"
        comps.queryItems = [
            URLQueryItem(name: "domain", value: base.host)
        ]
        return comps.url!
    }

    private func siteIconCandidates(for base: URL) -> [URL] {
        var candidates: [URL] = []
        guard let host = base.host else { return candidates }

        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = host
        comps.path = "/favicon.ico"
        if let url = comps.url {
            candidates.append(url)
        }

        comps.path = "/apple-touch-icon.png"
        if let url = comps.url {
            candidates.append(url)
        }

        comps.path = "/apple-touch-icon-precomposed.png"
        if let url = comps.url {
            candidates.append(url)
        }

        comps.path = "/favicon.png"
        if let url = comps.url {
            candidates.append(url)
        }

        return candidates
    }

    private func fallbackFavicon(for base: URL) -> URL? {
        guard let host = base.host else { return nil }
        return URL(string: "https://\(host)/favicon.ico")
    }

    private func checkURLExists(_ url: URL) async -> Bool {
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            guard let httpResp = response as? HTTPURLResponse else { return false }
            return (200...299).contains(httpResp.statusCode)
        } catch {
            return false
        }
    }
}
