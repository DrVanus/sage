import Foundation

public enum ExchangeHTTP {
    @inline(__always)
    private static func makeRequest(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url)
        r.timeoutInterval = 10
        r.cachePolicy = .reloadIgnoringLocalCacheData
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.setValue("CryptoSage/1.0", forHTTPHeaderField: "User-Agent")
        return r
    }

    /// Parse Retry-After header as seconds or HTTP-date.
    private static func retryAfterSeconds(_ http: HTTPURLResponse) -> TimeInterval? {
        for (k, v) in http.allHeaderFields {
            if let ks = (k as? String)?.lowercased(), ks == "retry-after" {
                if let s = v as? String {
                    if let secs = TimeInterval(s.trimmingCharacters(in: .whitespacesAndNewlines)) { return secs }
                    let df = DateFormatter()
                    df.locale = Locale(identifier: "en_US_POSIX")
                    df.timeZone = TimeZone(secondsFromGMT: 0)
                    df.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
                    if let date = df.date(from: s) { return max(0, date.timeIntervalSinceNow) }
                } else if let n = v as? NSNumber {
                    return n.doubleValue
                }
            }
        }
        return nil
    }

    /// Perform a GET with policy-aware fallback handling for Binance endpoints.
    /// - Parameters:
    ///   - initial: The initial URL to try (e.g., global REST base).
    ///   - session: The URLSession to use.
    ///   - buildFromEndpoints: Closure to build a URL from `ExchangeEndpoints` for retries/fallback.
    ///   - maxAttempts: Maximum attempts before giving up (default 3).
    /// - Returns: Data and HTTPURLResponse for a successful 2xx response.
    public static func getWithPolicyFallback(
        initial: URL,
        session: URLSession,
        buildFromEndpoints: @escaping (ExchangeEndpoints) -> URL,
        maxAttempts: Int = 3
    ) async throws -> (Data, HTTPURLResponse) {
        var currentURL = initial
        var lastError: Error?

        for _ in 0..<maxAttempts {
            do {
                let (data, response) = try await session.data(for: makeRequest(currentURL))
                guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }

                if (200...299).contains(http.statusCode) {
                    return (data, http)
                }

                if http.statusCode == 451 {
                    await ExchangeHostPolicy.shared.onHTTPStatus(451)
                    let endpoints = await ExchangeHostPolicy.shared.currentEndpoints()
                    currentURL = buildFromEndpoints(endpoints)
                    continue
                }
                if http.statusCode == 429 {
                    // Respect Retry-After when present, with sane caps
                    let wait = retryAfterSeconds(http) ?? 0.2
                    let capped = max(0.15, min(wait, 3.0))
                    try? await Task.sleep(nanoseconds: UInt64(capped * 1_000_000_000))
                    let endpoints = await ExchangeHostPolicy.shared.currentEndpoints()
                    currentURL = buildFromEndpoints(endpoints)
                    continue
                }
                if (500...599).contains(http.statusCode) {
                    // Small jittered backoff then switch to policy endpoints
                    try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.15...0.35) * 1_000_000_000))
                    let endpoints = await ExchangeHostPolicy.shared.currentEndpoints()
                    currentURL = buildFromEndpoints(endpoints)
                    continue
                }

                lastError = URLError(.badServerResponse)
                break
            } catch {
                lastError = error
                // On network errors, try policy endpoints next with a tiny backoff
                try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.10...0.25) * 1_000_000_000))
                let endpoints = await ExchangeHostPolicy.shared.currentEndpoints()
                currentURL = buildFromEndpoints(endpoints)
                continue
            }
        }

        if let e = lastError { throw e }
        throw URLError(.badServerResponse)
    }
}
