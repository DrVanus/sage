import Foundation

public enum ExchangeRegion: String, Codable {
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
    
    // BINANCE-US-FIX: Binance.US has been shut down. The "us" fallback now
    // points to a Binance global mirror (api4.binance.com) instead of the
    // dead api.binance.us endpoint. This avoids infinite timeout floods.
    public static let us = ExchangeEndpoints(
        restBase: URL(string: "https://api4.binance.com/api/v3")!,
        wsBase: URL(string: "wss://stream.binance.com:9443")!
    )
}

public actor ExchangeHostPolicy {
    public static let shared = ExchangeHostPolicy()

    private var region: ExchangeRegion
    private var lockedUntil: Date
    
    // Track consecutive 451 errors to detect geo-blocking faster
    private var consecutive451Count: Int = 0
    private let geoBlockThreshold: Int = 2
    
    // Persist geo-block status to disk
    private static let regionKey = "ExchangeHostPolicy.region"
    private static let lockedUntilKey = "ExchangeHostPolicy.lockedUntil"
    // BINANCE-US-FIX: Key to track that we've migrated away from dead Binance.US
    private static let migratedFromUSKey = "ExchangeHostPolicy.migratedFromUS_v2"
    
    private init() {
        // BINANCE-US-FIX: Always start with global. If a previous session
        // persisted "us" (pointing to the dead api.binance.us), auto-recover.
        let hasMigrated = UserDefaults.standard.bool(forKey: Self.migratedFromUSKey)
        
        if !hasMigrated {
            // One-time migration: clear any stale Binance.US lock
            UserDefaults.standard.removeObject(forKey: Self.regionKey)
            UserDefaults.standard.removeObject(forKey: Self.lockedUntilKey)
            UserDefaults.standard.set(true, forKey: Self.migratedFromUSKey)
            self.region = .global
            self.lockedUntil = .distantPast
        } else {
            // Load persisted region preference
            if let savedRegion = UserDefaults.standard.string(forKey: Self.regionKey),
               let region = ExchangeRegion(rawValue: savedRegion) {
                self.region = region
            } else {
                self.region = .global
            }
            
            // Load persisted lock time
            let savedLockedUntil = UserDefaults.standard.double(forKey: Self.lockedUntilKey)
            if savedLockedUntil > 0 {
                self.lockedUntil = Date(timeIntervalSince1970: savedLockedUntil)
            } else {
                self.lockedUntil = .distantPast
            }
        }
    }

    public func currentEndpoints(now: Date = .now) -> ExchangeEndpoints {
        if now >= lockedUntil {
            return region == .global ? .global : .us
        } else {
            return region == .global ? .global : .us
        }
    }

    public func currentRegion() -> ExchangeRegion { region }

    /// Call this when receiving an HTTP response to update policy if needed
    public func onHTTPStatus(_ status: Int, stickyFor seconds: TimeInterval = 3600, now: Date = .now) {
        if status == 451 {
            consecutive451Count += 1
            
            // Switch to "us" (which now points to a Binance mirror, not the dead Binance.US)
            if consecutive451Count >= geoBlockThreshold {
                region = .us
                let stickyPeriod = max(seconds, 86400.0)
                lockedUntil = now.addingTimeInterval(stickyPeriod)
                persist()
            }
        } else if status >= 200 && status < 300 {
            consecutive451Count = 0
        }
    }

    /// Manually force a region
    public func setRegion(_ newRegion: ExchangeRegion, stickyFor seconds: TimeInterval = 3600, now: Date = .now) {
        region = newRegion
        lockedUntil = now.addingTimeInterval(seconds)
        consecutive451Count = 0
        persist()
    }
    
    /// Check if global Binance (api.binance.com) is currently blocked
    public func isGlobalBinanceBlocked(now: Date = .now) -> Bool {
        return region == .us && now < lockedUntil
    }
    
    /// Force immediate switch to mirror region
    public func forceUSRegion(stickyFor seconds: TimeInterval = 86400, now: Date = .now) {
        region = .us
        lockedUntil = now.addingTimeInterval(seconds)
        consecutive451Count = 0
        persist()
    }
    
    /// Clear any persisted region preference (for testing/debugging)
    public func clearPersistedState() {
        region = .global
        lockedUntil = .distantPast
        consecutive451Count = 0
        UserDefaults.standard.removeObject(forKey: Self.regionKey)
        UserDefaults.standard.removeObject(forKey: Self.lockedUntilKey)
    }
    
    /// Persist current state to disk
    private func persist() {
        UserDefaults.standard.set(region.rawValue, forKey: Self.regionKey)
        UserDefaults.standard.set(lockedUntil.timeIntervalSince1970, forKey: Self.lockedUntilKey)
    }
}
