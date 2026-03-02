//
//  KeychainError.swift
//  CSAI1
//
//  Created by DM on 4/20/25.
//
//  Secure Keychain helper for storing sensitive credentials.
//  Uses kSecAttrAccessibleWhenUnlockedThisDeviceOnly for maximum security.
//

import Foundation
import Security

enum KeychainError: Error, LocalizedError {
    case unexpectedStatus(OSStatus)
    case encodingFailed
    case decodingFailed
    
    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "Keychain error: \(SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error (\(status))")"
        case .encodingFailed:
            return "Failed to encode data for keychain storage"
        case .decodingFailed:
            return "Failed to decode data from keychain"
        }
    }
}

final class KeychainHelper {
    static let shared = KeychainHelper()
    private init() {}
    
    /// Security attribute: Data is only accessible when the device is unlocked,
    /// and the data is not migrated to a new device (stays on this device only)
    private let accessAttribute = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

    /// Save a string value to the Keychain with enhanced security
    func save(_ value: String, service: String, account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        
        // First try to update existing item
        let query: [String: Any] = [
            kSecClass as String       : kSecClassGenericPassword,
            kSecAttrService as String : service,
            kSecAttrAccount as String : account,
        ]
        let update: [String: Any] = [
            kSecValueData as String   : data,
            kSecAttrAccessible as String : accessAttribute
        ]
        
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        
        if status == errSecSuccess { return }
        
        if status == errSecItemNotFound {
            // Item not found, add it with security attributes
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = accessAttribute
            
            status = SecItemAdd(addQuery as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw KeychainError.unexpectedStatus(status)
            }
        } else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Read a string value from the Keychain
    func read(service: String, account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String       : kSecClassGenericPassword,
            kSecAttrService as String : service,
            kSecAttrAccount as String : account,
            kSecReturnData as String  : true,
            kSecMatchLimit as String  : kSecMatchLimitOne
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        guard let data = item as? Data,
              let string = String(data: data, encoding: .utf8)
        else {
            throw KeychainError.decodingFailed
        }
        return string
    }

    /// Delete a value from the Keychain
    func delete(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String       : kSecClassGenericPassword,
            kSecAttrService as String : service,
            kSecAttrAccount as String : account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
    
    // MARK: - Raw Data API (for storing encoded objects like JSON)

    /// Save raw data to the Keychain with enhanced security
    func saveData(_ data: Data, service: String, account: String) throws {
        // First try to update existing item
        let query: [String: Any] = [
            kSecClass as String       : kSecClassGenericPassword,
            kSecAttrService as String : service,
            kSecAttrAccount as String : account,
        ]
        let update: [String: Any] = [
            kSecValueData as String   : data,
            kSecAttrAccessible as String : accessAttribute
        ]

        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)

        if status == errSecSuccess { return }

        if status == errSecItemNotFound {
            // Item not found, add it with security attributes
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = accessAttribute

            status = SecItemAdd(addQuery as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw KeychainError.unexpectedStatus(status)
            }
        } else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Read raw data from the Keychain
    func readData(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String       : kSecClassGenericPassword,
            kSecAttrService as String : service,
            kSecAttrAccount as String : account,
            kSecReturnData as String  : true,
            kSecMatchLimit as String  : kSecMatchLimitOne
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return data
    }

    /// Check if a keychain item exists (without retrieving the value)
    func exists(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String       : kSecClassGenericPassword,
            kSecAttrService as String : service,
            kSecAttrAccount as String : account,
            kSecReturnData as String  : false
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
}