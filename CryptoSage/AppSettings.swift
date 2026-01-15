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
}
