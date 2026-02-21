import Foundation

public enum PriceSourcePreference: String, CaseIterable {
    case auto
    case ws
    case manager
    case gecko
}

public enum AppSettings {
    private static let defaults = UserDefaults.standard
    private static let priceSourceKey = "priceSourcePreference"
    private static let compositeExchangesKey = "compositeAllowedExchanges"
    private static let preferredExchangePrefix = "preferredExchange_"
    private static let simulatorFullDataModeKey = "simulatorFullDataMode"

    public static var priceSourcePreference: PriceSourcePreference {
        get {
            if let raw = defaults.string(forKey: priceSourceKey),
               let pref = PriceSourcePreference(rawValue: raw) {
                return pref
            }
            return .auto
        }
        set {
            defaults.set(newValue.rawValue, forKey: priceSourceKey)
        }
    }

    public static func setCompositeAllowedExchanges(_ ids: [String]?) {
        if let ids = ids, !ids.isEmpty {
            defaults.set(ids, forKey: compositeExchangesKey)
        } else {
            defaults.removeObject(forKey: compositeExchangesKey)
        }
    }

    public static func compositeAllowedExchanges() -> [String]? {
        return defaults.stringArray(forKey: compositeExchangesKey)
    }

    /// Set or clear a preferred exchange for a specific asset symbol (e.g., BTC -> "coinbase").
    /// Pass nil to clear the preference and fall back to automatic selection.
    public static func setPreferredExchange(for symbol: String, exchangeID: String?) {
        let key = preferredExchangePrefix + symbol.uppercased()
        if let id = exchangeID, !id.isEmpty {
            defaults.set(id, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    /// Read a preferred exchange for a specific asset symbol, if any.
    /// Returns the exchange ID (e.g., "coinbase", "binance") or nil if not set.
    public static func preferredExchange(for symbol: String) -> String? {
        let key = preferredExchangePrefix + symbol.uppercased()
        return defaults.string(forKey: key)
    }

    /// Simulator startup/data behavior profile:
    /// - limited (default): allows one-shot core fetches but avoids high-frequency loops.
    /// - full: mimics device behavior for parity testing.
    public static var simulatorFullDataMode: Bool {
        get {
            #if targetEnvironment(simulator)
            return defaults.bool(forKey: simulatorFullDataModeKey)
            #else
            return false
            #endif
        }
        set {
            #if targetEnvironment(simulator)
            defaults.set(newValue, forKey: simulatorFullDataModeKey)
            #endif
        }
    }

    /// True when simulator should run the guarded, lower-pressure startup profile.
    public static var isSimulatorLimitedDataMode: Bool {
        #if targetEnvironment(simulator)
        return !simulatorFullDataMode
        #else
        return false
        #endif
    }
}
