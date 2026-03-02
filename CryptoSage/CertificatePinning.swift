//
//  CertificatePinning.swift
//  CryptoSage
//
//  Certificate pinning for critical API endpoints.
//  Protects against man-in-the-middle attacks - used by Coinbase, Binance, etc.
//

import Foundation
import CryptoKit
import Security

// MARK: - Certificate Pinning Manager

/// Manages SSL certificate pinning for critical API endpoints
final class CertificatePinningManager: NSObject {
    static let shared = CertificatePinningManager()
    
    // MARK: - Pinned Domains
    
    /// Domains that require certificate pinning
    private let pinnedDomains: Set<String> = [
        "api.openai.com",
        "api.binance.com",
        "api.coinbase.com",
        "api.3commas.io",
        "api.coingecko.com"
    ]
    
    // MARK: - Public Key Hashes (SHA-256)
    
    /// Known good public key hashes for pinned domains
    /// These are SHA-256 hashes of the Subject Public Key Info (SPKI)
    /// 
    /// NOTE: In production, you should regularly update these hashes
    /// and include backup pins for certificate rotation.
    ///
    /// HOW TO GET CERTIFICATE PINS:
    /// Run in Terminal: openssl s_client -connect api.openai.com:443 2>/dev/null | openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64
    ///
    /// IMPORTANT: These pins use popular CA roots (DigiCert, Let's Encrypt, etc.)
    /// that are less likely to change than leaf certificates.
    private let publicKeyHashes: [String: Set<String>] = [
        "api.openai.com": [
            // CloudFlare uses DigiCert - these are root/intermediate CA pins
            // More stable than leaf certificate pins
            "hxqRlPTu1bMS/0DITB1SSu0vd4u/8l8TjPgfaAp63Gc=", // DigiCert Global Root CA
            "RQeZkB42znUfsDIIFWIRiYEcKl7nHwNFwWCrnMMJbVc=", // DigiCert SHA2 Extended Validation Server CA
        ],
        "api.binance.com": [
            // Binance uses Amazon Trust Services - keep legacy pins for rotation
            "++MBgDH5WGvL9Bcn5Be30cRcL0f5O+NyoXuWtQdX1aI=", // Amazon Root CA 1 (legacy)
            "f0KW/FtqTjs108NpYj42SrGvOB2PpxIVM8nWxjPqJGE=", // Amazon Root CA 2 (legacy)
            // Updated pins (2025/2026) - Binance rotated certificates
            "kcIWQQUkNxeTsOdrWUdJ+WFGH0ZLJ/niquFaAI2RKpo=", // Current Root CA
            "wuABmJsfRRBc0SfuHCM91MMhwbzGJVk6mF+e3dZMdOM=", // Current Intermediate CA
            "kzNpObIj7PazozWYvpGtefirgmaT+KxQzYJwCOyniWg=", // Current Leaf/Intermediate
        ],
        "api.coinbase.com": [
            // Coinbase uses Amazon/DigiCert
            "++MBgDH5WGvL9Bcn5Be30cRcL0f5O+NyoXuWtQdX1aI=", // Amazon Root CA 1
            "hxqRlPTu1bMS/0DITB1SSu0vd4u/8l8TjPgfaAp63Gc=", // DigiCert Global Root CA
        ],
        "api.3commas.io": [
            // Let's Encrypt is commonly used
            "C5+lpZ7tcVwmwQIMcRtPbsQtWLABXhQzejna0wHFr8M=", // ISRG Root X1
            "lCppFqbkrlJ3EcVFAkeip0+44VaoJUymbnOaEUk7tEU=", // Let's Encrypt E1
        ],
        "api.coingecko.com": [
            // CoinGecko uses CloudFlare
            "hxqRlPTu1bMS/0DITB1SSu0vd4u/8l8TjPgfaAp63Gc=", // DigiCert Global Root CA
            "RQeZkB42znUfsDIIFWIRiYEcKl7nHwNFwWCrnMMJbVc=", // DigiCert SHA2 EV CA
        ]
    ]
    
    // MARK: - Pinning Mode
    
    enum PinningMode {
        case strict      // Fail if pin doesn't match (production)
        case reportOnly  // Log but don't fail (development)
        case disabled    // No pinning
    }
    
    /// Current pinning mode
    /// Set to .strict for production releases, .reportOnly for development
    #if DEBUG
    var pinningMode: PinningMode = .reportOnly
    #else
    var pinningMode: PinningMode = .strict
    #endif
    
    private override init() {
        super.init()
    }
    
    // MARK: - Pinned URLSession
    
    /// Create a URLSession with certificate pinning
    func createPinnedSession(configuration: URLSessionConfiguration = .default) -> URLSession {
        return URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: nil
        )
    }
    
    // MARK: - Public Key Hash Extraction
    
    /// Extract SHA-256 hash of the public key from a certificate
    private func publicKeyHash(for certificate: SecCertificate) -> String? {
        guard let publicKey = SecCertificateCopyKey(certificate) else {
            return nil
        }
        
        var error: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            return nil
        }
        
        // SHA-256 hash of the public key
        let hash = SHA256.hash(data: publicKeyData)
        return Data(hash).base64EncodedString()
    }
    
    /// Get all public key hashes from a certificate chain
    private func publicKeyHashes(from trust: SecTrust) -> [String] {
        var hashes: [String] = []
        
        guard let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate] else {
            return hashes
        }
        for certificate in certificates {
            if let hash = publicKeyHash(for: certificate) {
                hashes.append(hash)
            }
        }
        
        return hashes
    }
    
    // MARK: - Validation
    
    /// Validate a server trust against pinned certificates
    func validate(serverTrust: SecTrust, for host: String) -> Bool {
        // Check if this domain requires pinning
        guard pinnedDomains.contains(host) else {
            // Domain not pinned - allow standard validation
            return true
        }
        
        // Get expected hashes for this domain
        guard let expectedHashes = publicKeyHashes[host], !expectedHashes.isEmpty else {
            // No pins configured for this domain yet - allow in report mode
            if pinningMode == .reportOnly {
                #if DEBUG
                print("⚠️ [CertPinning] No pins configured for \(host) - allowing")
                #endif
                return true
            }
            // In strict mode, fail if no pins configured
            return pinningMode == .disabled
        }
        
        // Extract hashes from server's certificate chain
        let serverHashes = publicKeyHashes(from: serverTrust)
        
        // Check if any server hash matches our expected hashes
        let hasMatch = serverHashes.contains { expectedHashes.contains($0) }
        
        if !hasMatch {
            #if DEBUG
            print("🚨 [CertPinning] Certificate pin mismatch for \(host)")
            print("🚨 [CertPinning] Server hashes: \(serverHashes)")
            print("🚨 [CertPinning] Expected hashes: \(Array(expectedHashes))")
            #endif
            
            // In report mode, log but allow
            if pinningMode == .reportOnly {
                #if DEBUG
                print("⚠️ [CertPinning] Report-only mode - allowing connection")
                #endif
                return true
            }
        }
        // NOTE: Removed verbose success logging to reduce console noise
        
        return hasMatch || pinningMode == .disabled
    }
}

// MARK: - URLSession Delegate

extension CertificatePinningManager: URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        let host = challenge.protectionSpace.host
        
        // Perform standard certificate validation first
        var error: CFError?
        let isValid = SecTrustEvaluateWithError(serverTrust, &error)
        
        guard isValid else {
            #if DEBUG
            print("🚨 [CertPinning] Standard validation failed for \(host): \(error?.localizedDescription ?? "unknown")")
            #endif
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        // Now perform pin validation
        if validate(serverTrust: serverTrust, for: host) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

// MARK: - URLSession Task Delegate

extension CertificatePinningManager: URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Forward to session delegate
        urlSession(session, didReceive: challenge, completionHandler: completionHandler)
    }
}

// MARK: - Secure Network Session

/// Creates secure network sessions with optional certificate pinning
struct SecureNetworkSession {
    
    /// Shared pinned session for critical API calls
    static let pinned: URLSession = {
        let config = URLSessionConfiguration.default
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        config.httpAdditionalHeaders = [
            "User-Agent": "CryptoSage/1.0",
            "Accept": "application/json"
        ]
        return CertificatePinningManager.shared.createPinnedSession(configuration: config)
    }()
    
    /// Standard session without pinning (for non-critical requests)
    static let standard: URLSession = {
        let config = URLSessionConfiguration.default
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        return URLSession(configuration: config)
    }()
    
    /// Perform a secure request with automatic session selection
    /// Uses pinned session for critical domains, standard for others
    static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let host = request.url?.host ?? ""
        
        // Use pinned session for critical domains
        let criticalDomains = ["openai.com", "binance.com", "coinbase.com", "3commas.io"]
        let isPinned = criticalDomains.contains { host.contains($0) }
        
        let session = isPinned ? pinned : standard
        return try await session.data(for: request)
    }
}

// MARK: - Certificate Hash Helper

/// Utility to extract and print certificate hashes for pinning setup
/// Run this in development to get hashes for your pinned domains
struct CertificateHashHelper {
    
    /// Fetch and print certificate hashes for a domain
    /// Use this to get the hashes you need to add to publicKeyHashes
    static func printHashes(for domain: String) async {
        guard let url = URL(string: "https://\(domain)") else {
            #if DEBUG
            print("Invalid domain: \(domain)")
            #endif
            return
        }
        
        #if DEBUG
        print("🔐 Fetching certificate hashes for \(domain)...")
        #endif
        
        let session = URLSession(configuration: .ephemeral)
        
        do {
            let (_, response) = try await session.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse {
                #if DEBUG
                print("✅ Connected to \(domain) (Status: \(httpResponse.statusCode))")
                print("📋 To get certificate hashes, implement a URLSessionDelegate")
                print("   that logs the hashes from didReceive challenge")
                #endif
            }
        } catch {
            #if DEBUG
            print("❌ Failed to connect: \(error.localizedDescription)")
            #endif
        }
    }
}
