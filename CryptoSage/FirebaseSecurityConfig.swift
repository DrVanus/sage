//
//  FirebaseSecurityConfig.swift
//  CryptoSage
//
//  Security configuration for Firebase communications.
//  Implements certificate pinning, request signing, and secure data handling.
//

import Foundation
import CryptoKit
import Security

// MARK: - Firebase Security Configuration

/// Security configuration for Firebase communications
enum FirebaseSecurityConfig {
    
    // MARK: - Certificate Pinning
    
    /// SHA-256 fingerprints of Firebase SSL certificates
    /// These should be updated if Firebase rotates their certificates
    /// To get current pins: openssl s_client -connect us-central1-cryptosage-ai.cloudfunctions.net:443 | openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl enc -base64
    static let pinnedCertificateHashes: Set<String> = [
        // Google Trust Services Root CA
        "cGuxAXyFXFkWm61cF4HPWX8S0srS9j0aSqN0k4AP+4A=",
        // GTS Root R1
        "hxqRlPTu1bMS/0DITB1SSu0vd4u/8l8TjPgfaAp63Gc=",
        // Google Cloud Functions certificate
        "jQJTbIh0grw0/1TkHSumWb+Fs0Ggogr621gT3PvPKG0=",
    ]
    
    // PERFORMANCE v26: Track if we've already logged the DEBUG pinning bypass
    private static var _hasLoggedPinningBypass = false
    
    /// Validate certificate against pinned hashes
    static func validateCertificate(_ trust: SecTrust) -> Bool {
        // Get the server certificate chain
        guard let certificateChain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              !certificateChain.isEmpty else {
            return false
        }
        
        // Check if any certificate in the chain matches our pins
        for certificate in certificateChain {
            let publicKey = SecCertificateCopyKey(certificate)
            if let key = publicKey,
               let publicKeyData = SecKeyCopyExternalRepresentation(key, nil) as Data? {
                let hash = SHA256.hash(data: publicKeyData)
                let hashString = Data(hash).base64EncodedString()
                
                if pinnedCertificateHashes.contains(hashString) {
                    return true
                }
            }
        }
        
        // In debug mode, allow unpinned certificates for local development
        #if DEBUG
        // PERFORMANCE v26: Only log once to avoid console spam (fires on every HTTPS request)
        if !_hasLoggedPinningBypass {
            _hasLoggedPinningBypass = true
            print("[FirebaseSecurity] WARNING: Certificate pinning bypassed in DEBUG mode")
        }
        return true
        #else
        return false
        #endif
    }
    
    // MARK: - Request Signing
    
    /// Generate a request signature for additional validation
    /// This can be verified server-side to ensure request integrity
    static func signRequest(
        endpoint: String,
        timestamp: Date,
        body: Data?
    ) -> String {
        // Get a device-specific key from Keychain
        let deviceKey = getOrCreateDeviceKey()
        
        // Build the signature payload
        var payload = endpoint + String(Int(timestamp.timeIntervalSince1970))
        if let body = body {
            payload += body.base64EncodedString()
        }
        
        // Generate HMAC signature
        let key = SymmetricKey(data: deviceKey)
        let signature = HMAC<SHA256>.authenticationCode(for: Data(payload.utf8), using: key)
        
        return Data(signature).base64EncodedString()
    }
    
    /// Get or create a device-specific signing key
    private static func getOrCreateDeviceKey() -> Data {
        let keychainService = "CryptoSage.DeviceKey"
        let keychainAccount = "signing_key"
        
        // Try to read existing key
        if let existingKey = try? KeychainHelper.shared.readData(
            service: keychainService,
            account: keychainAccount
        ) {
            return existingKey
        }
        
        // Generate new key
        var keyData = Data(count: 32)
        let result = keyData.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, 32, ptr.baseAddress!)
        }
        
        guard result == errSecSuccess else {
            // Fallback to a deterministic key based on bundle and system info
            let bundleId = Bundle.main.bundleIdentifier ?? "com.cryptosage"
            let systemId = ProcessInfo.processInfo.hostName
            let fallbackSeed = "\(bundleId).\(systemId)"
            return Data(SHA256.hash(data: Data(fallbackSeed.utf8)))
        }
        
        // Store the key
        try? KeychainHelper.shared.saveData(
            keyData,
            service: keychainService,
            account: keychainAccount
        )
        
        return keyData
    }
    
    // MARK: - Data Encryption
    
    /// Encrypt sensitive data before storing
    static func encryptData(_ data: Data) throws -> Data {
        let key = try getEncryptionKey()
        let sealedBox = try AES.GCM.seal(data, using: key)
        
        guard let combined = sealedBox.combined else {
            throw SecurityError.encryptionFailed
        }
        
        return combined
    }
    
    /// Decrypt sensitive data
    static func decryptData(_ encryptedData: Data) throws -> Data {
        let key = try getEncryptionKey()
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        return try AES.GCM.open(sealedBox, using: key)
    }
    
    /// Get or create encryption key
    private static func getEncryptionKey() throws -> SymmetricKey {
        let keychainService = "CryptoSage.EncryptionKey"
        let keychainAccount = "data_key"
        
        // Try to read existing key
        if let existingKey = try? KeychainHelper.shared.readData(
            service: keychainService,
            account: keychainAccount
        ) {
            return SymmetricKey(data: existingKey)
        }
        
        // Generate new key
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        
        try KeychainHelper.shared.saveData(
            keyData,
            service: keychainService,
            account: keychainAccount
        )
        
        return key
    }
    
    // MARK: - Secure Data Deletion
    
    /// Securely delete all local security data
    static func wipeSecurityData() {
        let services = [
            "CryptoSage.DeviceKey",
            "CryptoSage.EncryptionKey",
            "CryptoSage.APIKeys",
            "CryptoSage.Auth",
        ]
        
        for service in services {
            try? KeychainHelper.shared.deleteAll(service: service)
        }
    }
}

// MARK: - Security Errors

enum SecurityError: LocalizedError {
    case encryptionFailed
    case decryptionFailed
    case keyGenerationFailed
    case certificatePinningFailed
    
    var errorDescription: String? {
        switch self {
        case .encryptionFailed:
            return "Failed to encrypt data"
        case .decryptionFailed:
            return "Failed to decrypt data"
        case .keyGenerationFailed:
            return "Failed to generate security key"
        case .certificatePinningFailed:
            return "Server certificate validation failed"
        }
    }
}

// MARK: - Secure URLSession Delegate

/// URLSession delegate that implements certificate pinning
class SecureURLSessionDelegate: NSObject, URLSessionDelegate {
    
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Only handle server trust challenges
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        // Check if this is a Firebase domain
        let host = challenge.protectionSpace.host
        let isFirebaseHost = host.contains("cloudfunctions.net") ||
                            host.contains("firebaseio.com") ||
                            host.contains("googleapis.com")
        
        if isFirebaseHost {
            // Validate certificate against pinned hashes
            if FirebaseSecurityConfig.validateCertificate(serverTrust) {
                let credential = URLCredential(trust: serverTrust)
                completionHandler(.useCredential, credential)
            } else {
                // Certificate pinning failed
                print("[FirebaseSecurity] ERROR: Certificate pinning validation failed for \(host)")
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        } else {
            // Non-Firebase hosts use default handling
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

// MARK: - KeychainHelper Extensions

extension KeychainHelper {
    
    /// Read raw data from Keychain
    func readData(service: String, account: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data else {
            throw KeychainError.unexpectedStatus(status)
        }
        
        return data
    }
    
    /// Save raw data to Keychain
    func saveData(_ data: Data, service: String, account: String) throws {
        // Try to update existing item
        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
        ]
        
        var status = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)
        
        if status == errSecItemNotFound {
            // Item doesn't exist, create it
            var addQuery = updateQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }
        
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
    
    /// Delete all items for a service
    func deleteAll(service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

// MARK: - Secure Request Configuration

extension FirebaseService {
    
    /// Create a secure URLSession with certificate pinning
    static func createSecureSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        
        // Set reasonable timeouts for mobile - prevents hanging on slow/unresponsive servers
        config.timeoutIntervalForRequest = 30  // 30 seconds for individual request
        config.timeoutIntervalForResource = 45 // 45 seconds total for resource
        
        // Set secure headers
        config.httpAdditionalHeaders = [
            "X-Client-Version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            "X-Platform": "iOS",
        ]
        
        return URLSession(
            configuration: config,
            delegate: SecureURLSessionDelegate(),
            delegateQueue: nil
        )
    }
}
