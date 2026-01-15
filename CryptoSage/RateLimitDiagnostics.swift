// Debug-only utilities to surface rate-limit/blocked events to the UI.
// This file is compiled in Debug only; Release builds will tree-shake calls guarded by #if DEBUG in callsites.

#if DEBUG
import Foundation

public enum RateLimitDiagnostics {
    public struct Entry: Equatable, Hashable {
        public let host: String
        public let code: Int
        public let until: Date
    }

    public static let notification = Notification.Name("RateLimitDiagnostics.Ping")

    /// Record a rate-limit/blocked event for a host with an optional TTL. Posts a notification for UI overlays.
    /// - Parameters:
    ///   - host: e.g., "api.binance.com"; if nil, will use "unknown".
    ///   - code: HTTP status (e.g., 429/451) or POSIX code (e.g., 61 for connection refused).
    ///   - ttl: How long the block is expected to last; UI will cap display time.
    public static func record(host: String?, code: Int, ttl: TimeInterval) {
        let h = (host ?? "unknown").lowercased()
        let entry = Entry(host: h, code: code, until: Date().addingTimeInterval(max(1, ttl)))
        NotificationCenter.default.post(name: notification, object: nil, userInfo: [
            "host": entry.host,
            "code": entry.code,
            "until": entry.until
        ])
    }
}
#endif
