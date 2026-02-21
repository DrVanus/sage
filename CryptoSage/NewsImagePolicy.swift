import Foundation

public struct NewsImagePolicy {
    /// A set of hosts that are considered problematic and should be blocked.
    public static let hostBlocklist: Set<String> = [
        "localhost",
        "127.0.0.1",
        "0.0.0.0",
        "example.com",
        "invalid",
        "ads.example",
        "tracking.example"
    ]

    /// Tracking parameters to strip from image URLs (these don't affect image content)
    private static let trackingParams: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
        "fbclid", "gclid", "igshid", "mc_cid", "mc_eid"
    ]
    
    /// Returns a normalized URL by stripping tracking query params and fragments,
    /// ensuring the scheme is http or https, and the host is not blocklisted.
    /// Image-related query parameters (sizing, format, quality) are preserved.
    /// - Parameter original: The original URL to normalize.
    /// - Returns: A normalized URL or nil if the URL is invalid or blocked.
    public static func normalizedURL(from original: URL) -> URL? {
        guard let host = original.host?.lowercased(),
              !host.isEmpty,
              !hostBlocklist.contains(host) else {
            return nil
        }
        guard let scheme = original.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        var components = URLComponents(url: original, resolvingAgainstBaseURL: false)
        // Only strip tracking parameters, preserve image-related params (sizing, format, etc.)
        if let items = components?.queryItems, !items.isEmpty {
            components?.queryItems = items.filter { !trackingParams.contains($0.name.lowercased()) }
            // If all items were filtered out, set to nil to avoid empty "?" in URL
            if components?.queryItems?.isEmpty == true {
                components?.queryItems = nil
            }
        }
        components?.fragment = nil
        return components?.url
    }

    /// Performs a HEAD request to the given URL to preflight check if the resource is a valid image.
    /// - Parameters:
    ///   - url: The URL to check.
    ///   - timeout: The timeout interval for the request (default is 6 seconds).
    /// - Returns: True if the response status is 200..299 and the content length is non-zero or content type is an image; false otherwise.
    public static func preflightHEAD(_ url: URL, timeout: TimeInterval = 6) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = timeout

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                return false
            }
            if let contentLengthString = httpResponse.value(forHTTPHeaderField: "Content-Length"),
               let contentLength = Int(contentLengthString),
               contentLength > 0 {
                return true
            }
            if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
               contentType.lowercased().hasPrefix("image/") {
                return true
            }
            return false
        } catch {
            return false
        }
    }
}
