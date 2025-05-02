//
//  ComplianceManager.swift
//  CryptoSage
//
//  Created by DM on 5/30/25.
//


import Foundation

/// Manages user jurisdiction for compliance gating (e.g., US vs non-US vs UK/EEA)
final class ComplianceManager {
    static let shared = ComplianceManager()
    private let userDefaults = UserDefaults.standard
    private let countryKey = "com.cryptoSage.countryCode"
    private init() { }

    /// ISO 3166-1 alpha-2 country code for the user, fetched once or entered manually
    var countryCode: String? {
        get { userDefaults.string(forKey: countryKey) }
        set { userDefaults.setValue(newValue, forKey: countryKey) }
    }

    /// Indicates whether this user is in the United States
    var isUSUser: Bool {
        countryCode?.uppercased() == "US"
    }

    /// Indicates whether this user is in the European Economic Area (EEA)
    var isEEAUser: Bool {
        guard let code = countryCode?.uppercased() else { return false }
        // Simplified list of EEA country codes
        let eeaCodes: Set<String> = ["AT","BE","BG","HR","CY","CZ","DK","EE","FI","FR","DE",
                                    "GR","HU","IS","IE","IT","LV","LI","LT","LU","MT",
                                    "NL","NO","PL","PT","RO","SK","SI","ES","SE"]
        return eeaCodes.contains(code)
    }

    /// Call on app launch to auto-detect country via IP lookup (fallback to manual entry on failure)
    func detectUserCountry(completion: @escaping (Error?) -> Void) {
        guard countryCode == nil else {
            completion(nil)
            return
        }
        // Simple IP geolocation service
        let url = URL(string: "https://ipapi.co/json/")!
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(error) }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async { completion(NSError(domain: "Compliance", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data returned"])) }
                return
            }
            do {
                let result = try JSONDecoder().decode(GeoIPResponse.self, from: data)
                self.countryCode = result.countryCode
                DispatchQueue.main.async { completion(nil) }
            } catch {
                DispatchQueue.main.async { completion(error) }
            }
        }.resume()
    }
}

// MARK: - GeoIPResponse
private struct GeoIPResponse: Codable {
    let ip: String
    let country: String
    let countryCode: String

    enum CodingKeys: String, CodingKey {
        case ip
        case country
        case countryCode = "country_code"
    }
}