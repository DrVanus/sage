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

    /// Returns a normalized URL by stripping query items and fragments,
    /// ensuring the scheme is http or https, and the host is not blocklisted.
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
        components?.query = nil
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
            let (response, _) = try await URLSession.shared.data(for: request)
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
