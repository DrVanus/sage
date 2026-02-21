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
    /// Uses IP-detected country code, with device locale as fallback
    var isUSUser: Bool {
        // Primary: Use IP-detected country
        if let code = countryCode?.uppercased() {
            return code == "US"
        }
        // Fallback: Check device locale/region
        if let regionCode = Locale.current.region?.identifier.uppercased() {
            return regionCode == "US"
        }
        // Default to false if we can't determine
        return false
    }
    
    /// Whether country has been definitively determined (not just locale fallback)
    var hasDetectedCountry: Bool {
        countryCode != nil
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
        
        // Try primary service first, then fallback
        tryGeoIPService(
            url: URL(string: "https://ipapi.co/json/")!,
            responseType: GeoIPResponse.self,
            serviceName: "ipapi.co"
        ) { [weak self] result in
            guard let self = self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            switch result {
            case .success(let countryCode):
                self.countryCode = countryCode
                #if DEBUG
                print("[ComplianceManager] Detected country via ipapi.co: \(countryCode)")
                #endif
                DispatchQueue.main.async { completion(nil) }
                
            case .failure:
                // Primary failed - try fallback service (ipwho.is — HTTPS, no key required)
                // SECURITY FIX: Replaced http://ip-api.com (plaintext HTTP) with HTTPS alternative.
                // The old URL was silently blocked by ATS (NSAllowsArbitraryLoads = false) anyway.
                self.tryGeoIPService(
                    url: URL(string: "https://ipwho.is/")!,
                    responseType: IPAPIResponse.self,
                    serviceName: "ipwho.is"
                ) { [weak self] fallbackResult in
                    guard let self = self else {
                        DispatchQueue.main.async { completion(nil) }
                        return
                    }
                    
                    switch fallbackResult {
                    case .success(let countryCode):
                        self.countryCode = countryCode
                        #if DEBUG
                        print("[ComplianceManager] Detected country via ipwho.is fallback: \(countryCode)")
                        #endif
                    case .failure:
                        #if DEBUG
                        print("[ComplianceManager] All geolocation services failed - skipping country detection")
                        #endif
                    }
                    DispatchQueue.main.async { completion(nil) }
                }
            }
        }
    }
    
    /// Generic helper to try a geolocation service
    private func tryGeoIPService<T: GeoIPDecodable>(
        url: URL,
        responseType: T.Type,
        serviceName: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        URLSession.shared.dataTask(with: url) { data, response, error in
            // Network error (including TLS errors)
            if let error = error {
                #if DEBUG
                print("[ComplianceManager] \(serviceName) network error: \(error.localizedDescription)")
                #endif
                completion(.failure(error))
                return
            }
            
            // Check HTTP status code
            if let httpResponse = response as? HTTPURLResponse {
                guard (200..<300).contains(httpResponse.statusCode) else {
                    #if DEBUG
                    print("[ComplianceManager] \(serviceName) HTTP \(httpResponse.statusCode)")
                    #endif
                    completion(.failure(NSError(domain: "ComplianceManager", code: httpResponse.statusCode, userInfo: nil)))
                    return
                }
            }
            
            guard let data = data, !data.isEmpty else {
                completion(.failure(NSError(domain: "ComplianceManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                return
            }
            
            // Validate that response looks like JSON before attempting decode
            guard let firstChar = String(data: data.prefix(1), encoding: .utf8), firstChar == "{" else {
                #if DEBUG
                let preview = String(data: data.prefix(100), encoding: .utf8) ?? "non-UTF8"
                print("[ComplianceManager] \(serviceName) response is not JSON: \(preview)")
                #endif
                completion(.failure(NSError(domain: "ComplianceManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Not JSON"])))
                return
            }
            
            do {
                let result = try JSONDecoder().decode(T.self, from: data)
                if let code = result.extractedCountryCode {
                    completion(.success(code))
                } else {
                    completion(.failure(NSError(domain: "ComplianceManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "No country code in response"])))
                }
            } catch {
                #if DEBUG
                print("[ComplianceManager] \(serviceName) JSON decode error: \(error.localizedDescription)")
                #endif
                completion(.failure(error))
            }
        }.resume()
    }
}

// MARK: - GeoIP Response Protocol
private protocol GeoIPDecodable: Decodable {
    var extractedCountryCode: String? { get }
}

// MARK: - GeoIP Response Structs

/// Response from ipapi.co
private struct GeoIPResponse: Codable, GeoIPDecodable {
    let ip: String?
    let country: String?
    let countryCode: String?

    enum CodingKeys: String, CodingKey {
        case ip
        case country
        case countryCode = "country_code"
    }
    
    var extractedCountryCode: String? {
        countryCode
    }
}

/// Response from ipwho.is (HTTPS fallback geo-IP service)
private struct IPAPIResponse: Codable, GeoIPDecodable {
    let success: Bool?
    let countryCode: String?
    
    enum CodingKeys: String, CodingKey {
        case success
        case countryCode = "country_code"
    }
    
    var extractedCountryCode: String? {
        // ipwho.is returns success: true/false
        guard success == true else { return nil }
        return countryCode
    }
}