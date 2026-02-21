import Foundation

struct ThreeCommasConfig {
    // Prefer secure storage first
    private static let keychainService = "CryptoSage.3Commas"
    // Optional sidecar config file for development overrides
    private static let configPlistName = "CryptoSageConfig"
    
    // PERFORMANCE FIX: Track which keys have already been warned about to avoid log spam
    private static var warnedKeys: Set<String> = []

    // Load optional sidecar config once
    private static var configPlist: [String: Any]? = {
        if let url = Bundle.main.url(forResource: configPlistName, withExtension: "plist"),
           let data = try? Data(contentsOf: url),
           let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            return dict
        }
        return nil
    }()

    /// Fetch a String for a given key using the following order of precedence:
    /// 1) Keychain (service: `CryptoSage.3Commas`, account: key)
    /// 2) App Info dictionary (generated or manual Info.plist)
    /// 3) Optional CryptoSageConfig.plist bundled with the app
    /// 4) Fallback to empty string with a warning (logged once per key)
    private static func string(forKey key: String) -> String {
        // 1) Keychain
        if let kc = try? KeychainHelper.shared.read(service: keychainService, account: key), !kc.isEmpty {
            return kc
        }
        // 2) Info.plist (generated or manual)
        if let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty {
            return value
        }
        // 3) Sidecar config
        if let v = configPlist?[key] as? String, !v.isEmpty {
            return v
        }
        // 4) Warn ONCE per key and fallback
        if !warnedKeys.contains(key) {
            warnedKeys.insert(key)
            #if DEBUG
            print("⚠️ Warning: Missing or empty \(key) in Keychain/Info/CryptoSageConfig.plist")
            #endif
        }
        return ""
    }

    /// Read-only API key from secure/config sources
    static var readOnlyAPIKey: String { string(forKey: "3COMMAS_READ_ONLY_KEY") }

    /// Read-only secret
    static var readOnlySecret: String { string(forKey: "3COMMAS_READ_ONLY_SECRET") }

    /// Trading API key
    static var tradingAPIKey: String { string(forKey: "3COMMAS_TRADING_API_KEY") }

    /// Trading secret
    static var tradingSecret: String { string(forKey: "3COMMAS_TRADING_SECRET") }

    /// Alias for the trading API key
    static var apiKey: String { tradingAPIKey }

    /// 3Commas account ID (as Int)
    static var accountId: Int {
        let idString = string(forKey: "3COMMAS_ACCOUNT_ID")
        if let id = Int(idString) {
            return id
        } else {
            if !idString.isEmpty {
                print("⚠️ Warning: Invalid 3COMMAS_ACCOUNT_ID: \(idString)")
            }
            return 0
        }
    }

    /// Base URL for 3Commas API
    static let baseURL = URL(string: "https://api.3commas.io")!

    /// Convenience utility: seed Keychain with whatever values are currently resolvable
    /// from Info/sidecar config. Useful to migrate off embedded values.
    static func seedKeychainFromCurrentValues() {
        do {
            try KeychainHelper.shared.save(readOnlyAPIKey, service: keychainService, account: "3COMMAS_READ_ONLY_KEY")
            try KeychainHelper.shared.save(readOnlySecret, service: keychainService, account: "3COMMAS_READ_ONLY_SECRET")
            try KeychainHelper.shared.save(tradingAPIKey, service: keychainService, account: "3COMMAS_TRADING_API_KEY")
            try KeychainHelper.shared.save(tradingSecret, service: keychainService, account: "3COMMAS_TRADING_SECRET")
            try KeychainHelper.shared.save(String(accountId), service: keychainService, account: "3COMMAS_ACCOUNT_ID")
        } catch {
            print("⚠️ Warning: Failed to seed Keychain: \(error)")
        }
    }
}
