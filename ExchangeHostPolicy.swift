import Foundation

public enum ExchangeRegion {
    case global
    case us
}

public struct ExchangeEndpoints {
    public let restBase: URL
    public let wsBase: URL

    public static let global = ExchangeEndpoints(
        restBase: URL(string: "https://api.binance.com/api/v3")!,
        wsBase: URL(string: "wss://stream.binance.com:9443")!
    )
    public static let us = ExchangeEndpoints(
        restBase: URL(string: "https://api.binance.us/api/v3")!,
        wsBase: URL(string: "wss://stream.binance.us:9443")!
    )
}

public actor ExchangeHostPolicy {
    public static let shared = ExchangeHostPolicy()

    private var region: ExchangeRegion = .global
    private var lockedUntil: Date = .distantPast

    public func currentEndpoints(now: Date = .now) -> ExchangeEndpoints {
        if now >= lockedUntil {
            // lock expired, keep current region but allow override via onHTTPStatus
            return region == .global ? .global : .us
        } else {
            // lock active, respect pinned region
            return region == .global ? .global : .us
        }
    }

    public func currentRegion() -> ExchangeRegion { region }

    /// Call this when receiving an HTTP response to update policy if needed
    public func onHTTPStatus(_ status: Int, stickyFor seconds: TimeInterval = 3600, now: Date = .now) {
        if status == 451 {
            region = .us
            lockedUntil = now.addingTimeInterval(seconds)
        }
    }

    /// Manually force a region (e.g., user override)
    public func setRegion(_ newRegion: ExchangeRegion, stickyFor seconds: TimeInterval = 3600, now: Date = .now) {
        region = newRegion
        lockedUntil = now.addingTimeInterval(seconds)
    }
}
