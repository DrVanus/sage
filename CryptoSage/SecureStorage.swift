//
//  SecureStorage.swift
//  CryptoSage
//
//  Provides encrypted storage for sensitive user data beyond what Keychain handles.
//  Uses Apple's CryptoKit for AES-GCM encryption.
//

import Foundation
import CryptoKit

/// Secure storage manager for encrypting sensitive data at rest
final class SecureStorage {
    static let shared = SecureStorage()
    
    // Key stored in Keychain for encrypting local data
    private let keychainService = "CryptoSage.DataEncryption"
    private let keychainAccount = "encryption_key"
    
    private init() {
        // Ensure we have an encryption key
        _ = getOrCreateEncryptionKey()
    }
    
    // MARK: - Encryption Key Management
    
    /// Get the encryption key from Keychain, or create one if it doesn't exist
    private func getOrCreateEncryptionKey() -> SymmetricKey {
        // Try to load existing key from Keychain
        if let keyData = try? KeychainHelper.shared.read(service: keychainService, account: keychainAccount),
           let data = Data(base64Encoded: keyData) {
            return SymmetricKey(data: data)
        }
        
        // Generate new key
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        let keyString = keyData.base64EncodedString()
        
        // Save to Keychain
        try? KeychainHelper.shared.save(keyString, service: keychainService, account: keychainAccount)
        
        return newKey
    }
    
    // MARK: - Public API
    
    /// Encrypt data using AES-GCM
    /// - Parameter data: Data to encrypt
    /// - Returns: Encrypted data (nonce + ciphertext + tag), or nil on failure
    func encrypt(_ data: Data) -> Data? {
        let key = getOrCreateEncryptionKey()
        
        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            return sealedBox.combined
        } catch {
            #if DEBUG
            print("❌ [SecureStorage] Encryption failed: \(error)")
            #endif
            return nil
        }
    }
    
    /// Decrypt data using AES-GCM
    /// - Parameter encryptedData: Data to decrypt (nonce + ciphertext + tag)
    /// - Returns: Decrypted data, or nil on failure
    func decrypt(_ encryptedData: Data) -> Data? {
        let key = getOrCreateEncryptionKey()
        
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            #if DEBUG
            print("❌ [SecureStorage] Decryption failed: \(error)")
            #endif
            return nil
        }
    }
    
    /// Encrypt a Codable object and save to Documents directory
    /// - Parameters:
    ///   - object: Object to encrypt and save
    ///   - filename: Filename (will have .encrypted extension)
    func saveEncrypted<T: Encodable>(_ object: T, to filename: String) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(object)
            
            guard let encrypted = encrypt(data) else {
                #if DEBUG
                print("❌ [SecureStorage] Failed to encrypt data for \(filename)")
                #endif
                return
            }
            
            let fileURL = getDocumentsURL().appendingPathComponent(filename + ".encrypted")
            try encrypted.write(to: fileURL, options: [.atomic, .completeFileProtection])
            
            #if DEBUG
            print("✅ [SecureStorage] Saved encrypted: \(filename)")
            #endif
        } catch {
            #if DEBUG
            print("❌ [SecureStorage] Save failed: \(error)")
            #endif
        }
    }
    
    /// Load and decrypt a Codable object from Documents directory
    /// - Parameters:
    ///   - type: Type to decode
    ///   - filename: Filename (without .encrypted extension)
    /// - Returns: Decoded object, or nil on failure
    func loadEncrypted<T: Decodable>(_ type: T.Type, from filename: String) -> T? {
        let fileURL = getDocumentsURL().appendingPathComponent(filename + ".encrypted")
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        do {
            let encryptedData = try Data(contentsOf: fileURL)
            
            guard let decrypted = decrypt(encryptedData) else {
                #if DEBUG
                print("❌ [SecureStorage] Failed to decrypt: \(filename)")
                #endif
                return nil
            }
            
            let decoder = JSONDecoder()
            return try decoder.decode(type, from: decrypted)
        } catch {
            #if DEBUG
            print("❌ [SecureStorage] Load failed: \(error)")
            #endif
            return nil
        }
    }
    
    /// Delete an encrypted file
    func deleteEncrypted(_ filename: String) {
        let fileURL = getDocumentsURL().appendingPathComponent(filename + ".encrypted")
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    /// Check if an encrypted file exists
    func encryptedFileExists(_ filename: String) -> Bool {
        let fileURL = getDocumentsURL().appendingPathComponent(filename + ".encrypted")
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
    
    // SAFETY FIX: Use safe directory accessor instead of force unwrap
    private func getDocumentsURL() -> URL {
        FileManager.documentsDirectory
    }
}

// MARK: - Convenience Extensions

extension SecureStorage {
    /// Encrypt a string
    func encryptString(_ string: String) -> Data? {
        guard let data = string.data(using: .utf8) else { return nil }
        return encrypt(data)
    }
    
    /// Decrypt data to a string
    func decryptToString(_ encryptedData: Data) -> String? {
        guard let decrypted = decrypt(encryptedData) else { return nil }
        return String(data: decrypted, encoding: .utf8)
    }
}

// MARK: - Security Notes
/*
 This implementation provides:
 
 1. AES-256-GCM encryption - Industry standard authenticated encryption
 2. Unique encryption key per device - Stored securely in Keychain
 3. File protection - Uses iOS .completeFileProtection for files at rest
 4. Key never leaves device - Encryption/decryption happens locally
 
 Use this for:
 - Cached portfolio values
 - Transaction history
 - Sensitive user preferences
 
 Do NOT use this for:
 - API keys (use Keychain directly via KeychainHelper)
 - Passwords (use Keychain)
 - Data that needs to sync across devices
*/
