//
//  OAuthConnectionProvider.swift
//  CryptoSage
//
//  OAuth 2.0 connection provider for Coinbase, Kraken, and Gemini.
//  Uses PKCE (Proof Key for Code Exchange) for secure mobile authentication.
//

import Foundation
import AuthenticationServices
import CryptoKit

// MARK: - OAuth Configuration

/// Configuration for OAuth providers
struct OAuthConfig {
    let clientId: String
    let clientSecret: String?
    let authorizationURL: URL
    let tokenURL: URL
    let redirectURI: String
    let scopes: [String]
    
    /// Coinbase OAuth configuration
    static func coinbase(clientId: String, clientSecret: String? = nil) -> OAuthConfig {
        OAuthConfig(
            clientId: clientId,
            clientSecret: clientSecret,
            authorizationURL: URL(string: "https://www.coinbase.com/oauth/authorize")!,
            tokenURL: URL(string: "https://api.coinbase.com/oauth/token")!,
            redirectURI: "cryptosage://oauth/coinbase",
            scopes: ["wallet:accounts:read", "wallet:transactions:read", "wallet:user:read"]
        )
    }
    
    /// Kraken OAuth configuration
    static func kraken(clientId: String, clientSecret: String? = nil) -> OAuthConfig {
        OAuthConfig(
            clientId: clientId,
            clientSecret: clientSecret,
            authorizationURL: URL(string: "https://www.kraken.com/oauth/authorize")!,
            tokenURL: URL(string: "https://api.kraken.com/oauth/token")!,
            redirectURI: "cryptosage://oauth/kraken",
            scopes: ["read"]
        )
    }
    
    /// Gemini OAuth configuration
    static func gemini(clientId: String, clientSecret: String? = nil) -> OAuthConfig {
        OAuthConfig(
            clientId: clientId,
            clientSecret: clientSecret,
            authorizationURL: URL(string: "https://exchange.gemini.com/auth")!,
            tokenURL: URL(string: "https://api.gemini.com/v1/oauth/token")!,
            redirectURI: "cryptosage://oauth/gemini",
            scopes: ["balances:read", "history:read"]
        )
    }
}

// MARK: - OAuth Errors

/// Error thrown when OAuth token needs refresh
enum OAuthTokenError: Error {
    case tokenExpired(exchange: String)
    case refreshFailed(exchange: String, reason: String)
}

/// Error thrown when OAuth is not configured for an exchange
enum OAuthSetupError: LocalizedError {
    case notConfigured(exchangeName: String)
    
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "OAuth Setup Required"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .notConfigured(let name):
            return """
            To enable \(name) login:
            
            1. Register at \(developerPortalURL(for: name))
            2. Create an OAuth application
            3. Set redirect URI: cryptosage://oauth/\(name.lowercased())
            4. Add the Client ID to the app configuration
            """
        }
    }
    
    private func developerPortalURL(for exchange: String) -> String {
        switch exchange.lowercased() {
        case "coinbase":
            return "developers.coinbase.com"
        case "kraken":
            return "support.kraken.com/hc/en-us/articles/360001491786"
        case "gemini":
            return "exchange.gemini.com/settings/api"
        default:
            return "the exchange developer portal"
        }
    }
}

// MARK: - OAuth Token Storage

/// Stored OAuth token
struct OAuthToken: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let tokenType: String
    let scope: String?
    
    /// Token is considered expired if past expiry time
    var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() >= expiresAt
    }
    
    /// Token needs refresh if it will expire within 5 minutes
    /// This allows proactive refresh before actual expiry
    var needsRefresh: Bool {
        guard let expiresAt = expiresAt else { return false }
        let refreshBuffer: TimeInterval = 5 * 60 // 5 minutes
        return Date().addingTimeInterval(refreshBuffer) >= expiresAt
    }
    
    /// Time remaining until token expires (nil if no expiry)
    var timeUntilExpiry: TimeInterval? {
        guard let expiresAt = expiresAt else { return nil }
        return expiresAt.timeIntervalSince(Date())
    }
}

// MARK: - OAuth Connection Provider Implementation

/// OAuth connection provider for exchanges that support OAuth 2.0
final class OAuthConnectionProviderImpl: NSObject, ConnectionProvider, ASWebAuthenticationPresentationContextProviding {
    static let shared = OAuthConnectionProviderImpl()
    
    var connectionType: ConnectionType { .oauth }
    var supportedExchanges: [String] { ["coinbase", "kraken", "gemini"] }
    
    // MARK: - State
    
    private var pendingState: String?
    private var pendingCodeVerifier: String?
    private var authSession: ASWebAuthenticationSession?
    
    // Stored OAuth configurations (set by the app when configured)
    private var storedConfigs: [String: OAuthConfig] = [:]
    
    // MARK: - Configuration Storage Keys
    
    private let configStorageKey = "CryptoSage.OAuthConfigs"
    private let tokenStorageKey = "CryptoSage.OAuthTokens"
    
    // MARK: - Check if OAuth is Configured
    
    /// Check if OAuth is configured for an exchange
    func isConfigured(for exchangeId: String) -> Bool {
        return getConfig(for: exchangeId) != nil
    }
    
    /// Get setup instructions for an exchange
    func getSetupInstructions(for exchangeId: String) -> String {
        let name = exchangeId.capitalized
        return """
        To connect \(name) with OAuth login:
        
        1. Go to \(getDeveloperPortalURL(for: exchangeId))
        2. Create a new OAuth application
        3. Set the redirect URI to: cryptosage://oauth/\(exchangeId.lowercased())
        4. Copy your Client ID
        5. Contact support to add it to the app
        
        Alternatively, you can use API keys if \(name) supports them.
        """
    }
    
    private func getDeveloperPortalURL(for exchangeId: String) -> String {
        switch exchangeId.lowercased() {
        case "coinbase":
            return "https://developers.coinbase.com"
        case "kraken":
            return "https://www.kraken.com/u/security/api"
        case "gemini":
            return "https://exchange.gemini.com/settings/api"
        default:
            return "the exchange developer portal"
        }
    }
    
    // MARK: - ConnectionProvider Protocol
    
    func supports(exchangeId: String) -> Bool {
        supportedExchanges.contains(exchangeId.lowercased())
    }
    
    func connect(exchangeId: String, credentials: ConnectionCredentials) async throws -> ConnectionResult {
        // If credentials are already provided (from OAuth flow), store them
        if case .oauth(let accessToken, let refreshToken, let expiresAt) = credentials {
            let token = OAuthToken(
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresAt: expiresAt,
                tokenType: "Bearer",
                scope: nil
            )
            saveToken(token, for: exchangeId)
            
            // Fetch initial balances
            let accountId = "\(exchangeId)-\(UUID().uuidString.prefix(8))"
            let balances = try await fetchBalances(accountId: accountId, exchangeId: exchangeId)
            
            return ConnectionResult(
                success: true,
                accountId: accountId,
                accountName: exchangeId.capitalized,
                error: nil,
                balances: balances
            )
        }
        
        throw ConnectionError.invalidCredentials
    }
    
    func disconnect(accountId: String) async throws {
        // Extract exchange ID from account ID
        let parts = accountId.split(separator: "-")
        if let exchangeId = parts.first {
            removeToken(for: String(exchangeId))
        }
    }
    
    func fetchBalances(accountId: String) async throws -> [PortfolioBalance] {
        // Extract exchange ID from account ID
        let parts = accountId.split(separator: "-")
        guard let exchangeId = parts.first else {
            throw ConnectionError.unknown("Invalid account ID")
        }
        
        return try await fetchBalances(accountId: accountId, exchangeId: String(exchangeId))
    }
    
    private func fetchBalances(accountId: String, exchangeId: String) async throws -> [PortfolioBalance] {
        guard var token = getToken(for: exchangeId) else {
            throw ConnectionError.invalidCredentials
        }
        
        // Proactively refresh token if it's expired or will expire soon
        if token.needsRefresh || token.isExpired {
            if let config = getConfig(for: exchangeId) {
                do {
                    token = try await refreshToken(token, config: config, exchangeId: exchangeId)
                } catch {
                    // If refresh fails but token isn't actually expired yet, try anyway
                    if token.isExpired {
                        throw error
                    }
                    #if DEBUG
                    print("⚠️ Proactive token refresh failed, using current token: \(error.localizedDescription)")
                    #endif
                }
            } else if token.isExpired {
                // No config available and token is expired - can't proceed
                throw ConnectionError.oauthFailed("Token expired and OAuth not configured. Please reconnect.")
            }
            // If no config but token not yet expired, continue with current token
        }
        
        // Fetch with automatic retry on token expiry
        do {
            switch exchangeId.lowercased() {
            case "coinbase":
                return try await fetchCoinbaseBalances(token: token)
            case "kraken":
                return try await fetchKrakenBalances(token: token)
            case "gemini":
                return try await fetchGeminiBalances(token: token)
            default:
                throw ConnectionError.unsupportedExchange
            }
        } catch _ as OAuthTokenError {
            // Token was rejected by API - attempt refresh and retry once
            guard let config = getConfig(for: exchangeId) else {
                throw ConnectionError.oauthFailed("Token invalid and OAuth not configured. Please reconnect.")
            }
            
            #if DEBUG
            print("🔄 Token rejected, attempting refresh for \(exchangeId)...")
            #endif
            let refreshedToken = try await refreshToken(token, config: config, exchangeId: exchangeId)
            
            // Retry with refreshed token
            switch exchangeId.lowercased() {
            case "coinbase":
                return try await fetchCoinbaseBalances(token: refreshedToken)
            case "kraken":
                return try await fetchKrakenBalances(token: refreshedToken)
            case "gemini":
                return try await fetchGeminiBalances(token: refreshedToken)
            default:
                throw ConnectionError.unsupportedExchange
            }
        }
    }
    
    func validateCredentials(exchangeId: String, credentials: ConnectionCredentials) async throws -> Bool {
        guard case .oauth(let accessToken, _, _) = credentials else {
            return false
        }
        
        // Try to fetch user info to validate token
        switch exchangeId.lowercased() {
        case "coinbase":
            return try await validateCoinbaseToken(accessToken: accessToken)
        default:
            return !accessToken.isEmpty
        }
    }
    
    // MARK: - OAuth Flow
    
    /// Start the OAuth flow for an exchange
    /// Throws OAuthSetupError.notConfigured if OAuth is not set up
    @MainActor
    func startOAuthFlow(exchangeId: String) async throws -> ConnectionCredentials {
        guard let config = getConfig(for: exchangeId) else {
            // OAuth not configured - throw setup required error
            throw OAuthSetupError.notConfigured(exchangeName: exchangeId.capitalized)
        }
        
        // Generate PKCE code verifier and challenge
        let codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)
        
        // Generate state for CSRF protection
        let state = UUID().uuidString
        
        // Store for later verification
        pendingState = state
        pendingCodeVerifier = codeVerifier
        
        // Build authorization URL
        guard var components = URLComponents(url: config.authorizationURL, resolvingAgainstBaseURL: false) else {
            throw ConnectionError.oauthFailed("Failed to build URL")
        }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        
        guard let authURL = components.url else {
            throw ConnectionError.oauthFailed("Failed to build authorization URL")
        }
        
        // Start authentication session
        return try await withCheckedThrowingContinuation { continuation in
            let scheme = URL(string: config.redirectURI)?.scheme ?? "cryptosage"
            
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: scheme
            ) { [weak self] callbackURL, error in
                guard let self = self else {
                    continuation.resume(throwing: ConnectionError.oauthCancelled)
                    return
                }
                
                if let error = error {
                    if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: ConnectionError.oauthCancelled)
                    } else {
                        continuation.resume(throwing: ConnectionError.oauthFailed(error.localizedDescription))
                    }
                    return
                }
                
                guard let callbackURL = callbackURL else {
                    continuation.resume(throwing: ConnectionError.oauthFailed("No callback URL received"))
                    return
                }
                
                // Parse callback URL
                Task {
                    do {
                        let credentials = try await self.handleOAuthCallback(
                            url: callbackURL,
                            exchangeId: exchangeId,
                            config: config
                        )
                        continuation.resume(returning: credentials)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            
            self.authSession = session
            
            if !session.start() {
                continuation.resume(throwing: ConnectionError.oauthFailed("Failed to start authentication session"))
            }
        }
    }
    
    /// Handle OAuth callback URL
    private func handleOAuthCallback(url: URL, exchangeId: String, config: OAuthConfig) async throws -> ConnectionCredentials {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            throw ConnectionError.oauthFailed("Invalid callback URL")
        }
        
        // Check for error
        if let error = queryItems.first(where: { $0.name == "error" })?.value {
            let description = queryItems.first(where: { $0.name == "error_description" })?.value ?? error
            throw ConnectionError.oauthFailed(description)
        }
        
        // Get authorization code
        guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
            throw ConnectionError.oauthFailed("No authorization code received")
        }
        
        // Verify state
        if let state = queryItems.first(where: { $0.name == "state" })?.value {
            guard state == pendingState else {
                throw ConnectionError.oauthFailed("State mismatch - possible CSRF attack")
            }
        }
        
        // Exchange code for tokens
        let token = try await exchangeCodeForToken(
            code: code,
            config: config,
            codeVerifier: pendingCodeVerifier ?? ""
        )
        
        // Save token
        saveToken(token, for: exchangeId)
        
        // Clear pending state
        pendingState = nil
        pendingCodeVerifier = nil
        
        return .oauth(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            expiresAt: token.expiresAt
        )
    }
    
    /// Exchange authorization code for access token
    private func exchangeCodeForToken(code: String, config: OAuthConfig, codeVerifier: String) async throws -> OAuthToken {
        var request = URLRequest(url: config.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        var bodyParams = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": config.redirectURI,
            "client_id": config.clientId,
            "code_verifier": codeVerifier
        ]
        
        if let clientSecret = config.clientSecret {
            bodyParams["client_secret"] = clientSecret
        }
        
        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConnectionError.networkError(URLError(.badServerResponse))
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorDescription = errorJson["error_description"] as? String {
                throw ConnectionError.oauthFailed(errorDescription)
            }
            throw ConnectionError.serverError(httpResponse.statusCode)
        }
        
        struct TokenResponse: Codable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Int?
            let token_type: String
            let scope: String?
        }
        
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        
        return OAuthToken(
            accessToken: tokenResponse.access_token,
            refreshToken: tokenResponse.refresh_token,
            expiresAt: tokenResponse.expires_in.map { Date().addingTimeInterval(TimeInterval($0)) },
            tokenType: tokenResponse.token_type,
            scope: tokenResponse.scope
        )
    }
    
    /// Refresh an expired OAuth token using the refresh token
    private func refreshToken(_ token: OAuthToken, config: OAuthConfig, exchangeId: String) async throws -> OAuthToken {
        guard let refreshToken = token.refreshToken else {
            throw ConnectionError.oauthFailed("No refresh token available. Please reconnect.")
        }
        
        var request = URLRequest(url: config.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        var bodyParams = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": config.clientId
        ]
        
        if let clientSecret = config.clientSecret {
            bodyParams["client_secret"] = clientSecret
        }
        
        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConnectionError.networkError(URLError(.badServerResponse))
        }
        
        // If refresh fails with 400/401, the refresh token is invalid - need to re-authenticate
        if httpResponse.statusCode == 400 || httpResponse.statusCode == 401 {
            // Remove the invalid token
            removeToken(for: exchangeId)
            throw ConnectionError.oauthFailed("Session expired. Please reconnect your \(exchangeId.capitalized) account.")
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorDescription = errorJson["error_description"] as? String {
                throw ConnectionError.oauthFailed(errorDescription)
            }
            throw ConnectionError.serverError(httpResponse.statusCode)
        }
        
        struct TokenResponse: Codable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Int?
            let token_type: String
            let scope: String?
        }
        
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        
        // Use new refresh token if provided, otherwise keep the old one
        let newRefreshToken = tokenResponse.refresh_token ?? refreshToken
        
        let newToken = OAuthToken(
            accessToken: tokenResponse.access_token,
            refreshToken: newRefreshToken,
            expiresAt: tokenResponse.expires_in.map { Date().addingTimeInterval(TimeInterval($0)) },
            tokenType: tokenResponse.token_type,
            scope: tokenResponse.scope ?? token.scope
        )
        
        // Save the refreshed token
        saveToken(newToken, for: exchangeId)
        
        #if DEBUG
        print("✅ OAuth token refreshed for \(exchangeId)")
        #endif
        
        return newToken
    }
    
    // MARK: - PKCE Helpers
    
    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    // MARK: - Token Storage
    
    private func saveToken(_ token: OAuthToken, for exchangeId: String) {
        do {
            let data = try JSONEncoder().encode(token)
            try KeychainHelper.shared.save(
                String(data: data, encoding: .utf8) ?? "",
                service: "CryptoSage.OAuth",
                account: exchangeId
            )
        } catch {
            #if DEBUG
            print("❌ Failed to save OAuth token: \(error)")
            #endif
        }
    }
    
    private func getToken(for exchangeId: String) -> OAuthToken? {
        do {
            let tokenString = try KeychainHelper.shared.read(
                service: "CryptoSage.OAuth",
                account: exchangeId
            )
            guard let data = tokenString.data(using: .utf8) else { return nil }
            return try JSONDecoder().decode(OAuthToken.self, from: data)
        } catch {
            return nil
        }
    }
    
    private func removeToken(for exchangeId: String) {
        try? KeychainHelper.shared.delete(
            service: "CryptoSage.OAuth",
            account: exchangeId
        )
    }
    
    // MARK: - Config Storage
    
    /// Set OAuth configuration for an exchange (call this when setting up the app)
    func setConfig(_ config: OAuthConfig, for exchangeId: String) {
        storedConfigs[exchangeId.lowercased()] = config
    }
    
    private func getConfig(for exchangeId: String) -> OAuthConfig? {
        // Check stored configs first
        if let config = storedConfigs[exchangeId.lowercased()] {
            return config
        }
        
        // Could also check Info.plist or secure storage here
        // For now, return nil if not configured
        return nil
    }
    
    // MARK: - Exchange-Specific API Calls
    
    private func fetchCoinbaseBalances(token: OAuthToken) async throws -> [PortfolioBalance] {
        var request = URLRequest(url: URL(string: "https://api.coinbase.com/v2/accounts")!)
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("2023-01-01", forHTTPHeaderField: "CB-VERSION")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConnectionError.networkError(URLError(.badServerResponse))
        }
        
        if httpResponse.statusCode == 401 {
            // Token is invalid - signal that refresh is needed
            throw OAuthTokenError.tokenExpired(exchange: "coinbase")
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ConnectionError.serverError(httpResponse.statusCode)
        }
        
        struct CoinbaseAccount: Codable {
            let id: String
            let name: String
            let balance: Balance
            
            struct Balance: Codable {
                let amount: String
                let currency: String
            }
        }
        
        struct CoinbaseResponse: Codable {
            let data: [CoinbaseAccount]
        }
        
        let coinbaseResponse = try JSONDecoder().decode(CoinbaseResponse.self, from: data)
        
        return coinbaseResponse.data.compactMap { account in
            guard let balance = Double(account.balance.amount), balance > 0 else { return nil }
            return PortfolioBalance(
                id: account.id,
                symbol: account.balance.currency,
                name: account.name,
                balance: balance
            )
        }
    }
    
    private func fetchKrakenBalances(token: OAuthToken) async throws -> [PortfolioBalance] {
        // Kraken API implementation - requires OAuth setup
        var request = URLRequest(url: URL(string: "https://api.kraken.com/0/private/Balance")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConnectionError.networkError(URLError(.badServerResponse))
        }
        
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw OAuthTokenError.tokenExpired(exchange: "kraken")
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ConnectionError.serverError(httpResponse.statusCode)
        }
        
        struct KrakenResponse: Codable {
            let error: [String]
            let result: [String: String]?
        }
        
        let krakenResponse = try JSONDecoder().decode(KrakenResponse.self, from: data)
        
        // Check for permission errors which indicate token issues
        if krakenResponse.error.contains(where: { $0.contains("Permission") || $0.contains("Invalid") }) {
            throw OAuthTokenError.tokenExpired(exchange: "kraken")
        }
        
        guard krakenResponse.error.isEmpty, let balances = krakenResponse.result else {
            throw ConnectionError.oauthFailed(krakenResponse.error.joined(separator: ", "))
        }
        
        return balances.compactMap { symbol, amountStr in
            guard let amount = Double(amountStr), amount > 0.00001 else { return nil }
            return PortfolioBalance(
                symbol: symbol,
                name: symbol,
                balance: amount
            )
        }
    }
    
    private func fetchGeminiBalances(token: OAuthToken) async throws -> [PortfolioBalance] {
        // Gemini API implementation
        var request = URLRequest(url: URL(string: "https://api.gemini.com/v1/balances")!)
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConnectionError.networkError(URLError(.badServerResponse))
        }
        
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw OAuthTokenError.tokenExpired(exchange: "gemini")
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ConnectionError.serverError(httpResponse.statusCode)
        }
        
        struct GeminiBalance: Codable {
            let currency: String
            let amount: String
            let available: String
        }
        
        let geminiBalances = try JSONDecoder().decode([GeminiBalance].self, from: data)
        
        return geminiBalances.compactMap { balance in
            guard let amount = Double(balance.amount), amount > 0.00001 else { return nil }
            return PortfolioBalance(
                symbol: balance.currency,
                name: balance.currency,
                balance: amount
            )
        }
    }
    
    private func validateCoinbaseToken(accessToken: String) async throws -> Bool {
        var request = URLRequest(url: URL(string: "https://api.coinbase.com/v2/user")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("2023-01-01", forHTTPHeaderField: "CB-VERSION")
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        
        return (200..<300).contains(httpResponse.statusCode)
    }
    
    // MARK: - ASWebAuthenticationPresentationContextProviding
    
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Return the key window for presenting the authentication UI
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return UIWindow()
        }
        return window
    }
}

// MARK: - Replace Stub with Implementation

extension OAuthConnectionProvider {
    /// Override the stub methods to use the real implementation
    static var implementation: OAuthConnectionProviderImpl {
        OAuthConnectionProviderImpl.shared
    }
}
