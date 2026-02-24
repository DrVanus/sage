//
//  CoinbaseJWTAuthService.swift
//  CryptoSage
//
//  JWT token generator for Coinbase Advanced Trade API
//  Uses ES256 signature (ECDSA with P-256 curve + SHA-256)
//

import Foundation
import CryptoKit

/// JWT token generator for Coinbase Advanced Trade API
/// Required for WebSocket feeds and premium API features
public actor CoinbaseJWTAuthService {
    public static let shared = CoinbaseJWTAuthService()
    private init() {}

    // JWT token cache (2-minute expiry per Coinbase docs)
    private var cachedToken: String?
    private var tokenExpiry: Date?

    /// Generate JWT token for API authentication
    /// - Returns: JWT token string valid for 2 minutes
    public func generateJWT() async throws -> String {
        // Check cache first
        if let token = cachedToken,
           let expiry = tokenExpiry,
           Date() < expiry {
            return token
        }

        // Load credentials from keychain
        guard let credentials = TradingCredentialsManager.shared.loadCredentials(for: .coinbase) else {
            throw CoinbaseError.noCredentials
        }

        // JWT Header (ES256 algorithm)
        let header: [String: Any] = [
            "alg": "ES256",
            "kid": credentials.apiKey,
            "typ": "JWT"
        ]

        // JWT Payload (claims)
        let now = Date()
        let expiry = now.addingTimeInterval(120) // 2 minutes
        let payload: [String: Any] = [
            "iss": "coinbase-cloud",
            "nbf": Int(now.timeIntervalSince1970),
            "exp": Int(expiry.timeIntervalSince1970),
            "sub": credentials.apiKey,
            "uri": "POST api.coinbase.com"
        ]

        // Encode header and payload as base64url
        let headerData = try JSONSerialization.data(withJSONObject: header)
        let payloadData = try JSONSerialization.data(withJSONObject: payload)

        let headerString = base64URLEncode(headerData)
        let payloadString = base64URLEncode(payloadData)

        // Create signature using ES256 (ECDSA with P-256 curve)
        let message = "\(headerString).\(payloadString)"
        let signature = try signES256(message: message, privateKey: credentials.apiSecret)

        // Construct JWT
        let jwt = "\(message).\(signature)"

        // Cache token
        self.cachedToken = jwt
        self.tokenExpiry = expiry.addingTimeInterval(-10) // Refresh 10s before expiry

        return jwt
    }

    /// Clear cached token (force refresh)
    public func invalidateToken() {
        cachedToken = nil
        tokenExpiry = nil
    }

    // MARK: - Private Helpers

    private func signES256(message: String, privateKey: String) throws -> String {
        // Convert PEM private key to CryptoKit PrivateKey
        let key = try parsePrivateKey(privateKey)

        // Sign message using ECDSA P-256
        let messageData = Data(message.utf8)
        let signature = try key.signature(for: messageData)

        // Encode signature as base64url
        return base64URLEncode(signature.rawRepresentation)
    }

    private func parsePrivateKey(_ pem: String) throws -> P256.Signing.PrivateKey {
        // Remove PEM headers/footers and decode base64
        let pemBody = pem
            .replacingOccurrences(of: "-----BEGIN EC PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END EC PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let keyData = Data(base64Encoded: pemBody) else {
            throw CoinbaseError.parseError
        }

        // Try to create P256 private key from DER or PEM data
        do {
            return try P256.Signing.PrivateKey(derRepresentation: keyData)
        } catch {
            // If DER fails, try PEM representation
            return try P256.Signing.PrivateKey(pemRepresentation: keyData)
        }
    }

    private func base64URLEncode(_ data: Data) -> String {
        var encoded = data.base64EncodedString()
        encoded = encoded.replacingOccurrences(of: "+", with: "-")
        encoded = encoded.replacingOccurrences(of: "/", with: "_")
        encoded = encoded.replacingOccurrences(of: "=", with: "")
        return encoded
    }
}
