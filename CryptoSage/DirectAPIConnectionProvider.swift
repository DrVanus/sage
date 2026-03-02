//
//  DirectAPIConnectionProvider.swift
//  CryptoSage
//
//  Direct API key connection provider for exchanges without OAuth.
//  Supports Binance, KuCoin, Bybit, OKX, and others.
//

import Foundation
import CryptoKit

// MARK: - API Key Configuration

/// Configuration for direct API connections
struct DirectAPIConfig {
    let id: String
    let name: String
    let baseURL: URL
    let accountEndpoint: String
    let requiresPassphrase: Bool
    let signatureMethod: SignatureMethod
    let testnetBaseURL: URL?
    
    enum SignatureMethod {
        case hmacSHA256
        case hmacSHA512
        case ed25519
        case none
    }
    
    /// Binance configuration
    static let binance = DirectAPIConfig(
        id: "binance",
        name: "Binance",
        baseURL: URL(string: "https://api.binance.com")!,
        accountEndpoint: "/api/v3/account",
        requiresPassphrase: false,
        signatureMethod: .hmacSHA256,
        testnetBaseURL: URL(string: "https://testnet.binance.vision")
    )
    
    /// Binance US configuration
    static let binanceUS = DirectAPIConfig(
        id: "binance_us",
        name: "Binance US",
        baseURL: URL(string: "https://api.binance.us")!,
        accountEndpoint: "/api/v3/account",
        requiresPassphrase: false,
        signatureMethod: .hmacSHA256,
        testnetBaseURL: nil
    )
    
    /// KuCoin configuration
    static let kucoin = DirectAPIConfig(
        id: "kucoin",
        name: "KuCoin",
        baseURL: URL(string: "https://api.kucoin.com")!,
        accountEndpoint: "/api/v1/accounts",
        requiresPassphrase: true,
        signatureMethod: .hmacSHA256,
        testnetBaseURL: nil
    )
    
    /// Bybit configuration
    static let bybit = DirectAPIConfig(
        id: "bybit",
        name: "Bybit",
        baseURL: URL(string: "https://api.bybit.com")!,
        accountEndpoint: "/v5/account/wallet-balance",
        requiresPassphrase: false,
        signatureMethod: .hmacSHA256,
        testnetBaseURL: URL(string: "https://api-testnet.bybit.com")
    )
    
    /// OKX configuration
    static let okx = DirectAPIConfig(
        id: "okx",
        name: "OKX",
        baseURL: URL(string: "https://www.okx.com")!,
        accountEndpoint: "/api/v5/account/balance",
        requiresPassphrase: true,
        signatureMethod: .hmacSHA256,
        testnetBaseURL: nil
    )
    
    /// HTX (formerly Huobi) configuration
    static let htx = DirectAPIConfig(
        id: "htx",
        name: "HTX",
        baseURL: URL(string: "https://api.huobi.pro")!,
        accountEndpoint: "/v1/account/accounts",
        requiresPassphrase: false,
        signatureMethod: .hmacSHA256,
        testnetBaseURL: nil
    )
    
    /// Gate.io configuration
    static let gateio = DirectAPIConfig(
        id: "gateio",
        name: "Gate.io",
        baseURL: URL(string: "https://api.gateio.ws")!,
        accountEndpoint: "/api/v4/spot/accounts",
        requiresPassphrase: false,
        signatureMethod: .hmacSHA256,
        testnetBaseURL: nil
    )
    
    /// MEXC configuration
    static let mexc = DirectAPIConfig(
        id: "mexc",
        name: "MEXC",
        baseURL: URL(string: "https://api.mexc.com")!,
        accountEndpoint: "/api/v3/account",
        requiresPassphrase: false,
        signatureMethod: .hmacSHA256,
        testnetBaseURL: nil
    )
    
    /// Bitstamp configuration
    static let bitstamp = DirectAPIConfig(
        id: "bitstamp",
        name: "Bitstamp",
        baseURL: URL(string: "https://www.bitstamp.net")!,
        accountEndpoint: "/api/v2/balance/",
        requiresPassphrase: false,
        signatureMethod: .hmacSHA256,
        testnetBaseURL: nil
    )
    
    /// Crypto.com configuration
    static let cryptocom = DirectAPIConfig(
        id: "cryptocom",
        name: "Crypto.com",
        baseURL: URL(string: "https://api.crypto.com/v2")!,
        accountEndpoint: "/private/get-account-summary",
        requiresPassphrase: false,
        signatureMethod: .hmacSHA256,
        testnetBaseURL: nil
    )
    
    /// Bitget configuration
    static let bitget = DirectAPIConfig(
        id: "bitget",
        name: "Bitget",
        baseURL: URL(string: "https://api.bitget.com")!,
        accountEndpoint: "/api/v2/spot/account/assets",
        requiresPassphrase: true,
        signatureMethod: .hmacSHA256,
        testnetBaseURL: nil
    )
    
    /// Bitfinex configuration
    static let bitfinex = DirectAPIConfig(
        id: "bitfinex",
        name: "Bitfinex",
        baseURL: URL(string: "https://api.bitfinex.com")!,
        accountEndpoint: "/v2/auth/r/wallets",
        requiresPassphrase: false,
        signatureMethod: .hmacSHA256,
        testnetBaseURL: nil
    )
    
    /// All configurations
    static let all: [String: DirectAPIConfig] = [
        "binance": binance,
        "binance_us": binanceUS,
        "kucoin": kucoin,
        "bybit": bybit,
        "okx": okx,
        "htx": htx,
        "huobi": htx, // Alias for legacy support
        "gateio": gateio,
        "gate.io": gateio, // Alias
        "mexc": mexc,
        "bitstamp": bitstamp,
        "cryptocom": cryptocom,
        "crypto.com": cryptocom, // Alias
        "bitget": bitget,
        "bitfinex": bitfinex
    ]
    
    static func get(_ id: String) -> DirectAPIConfig? {
        all[id.lowercased()]
    }
}

// MARK: - Stored API Credentials

struct StoredAPICredentials: Codable {
    let apiKey: String
    let apiSecret: String
    let passphrase: String?
    let exchangeId: String
    let createdAt: Date
}

// MARK: - Direct API Connection Provider Implementation

final class DirectAPIConnectionProviderImpl: ConnectionProvider {
    static let shared = DirectAPIConnectionProviderImpl()
    // PERFORMANCE FIX: Cached ISO8601 formatter for API timestamp generation
    private static let _isoFormatter = ISO8601DateFormatter()
    
    var connectionType: ConnectionType { .apiKey }
    var supportedExchanges: [String] { Array(DirectAPIConfig.all.keys) }
    
    // MARK: - Session
    
    private lazy var session: URLSession = {
        // SECURITY: Ephemeral session prevents disk caching of exchange account data,
        // balances, and API key-authenticated responses.
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        return CertificatePinningManager.shared.createPinnedSession(configuration: config)
    }()
    
    // MARK: - ConnectionProvider Protocol
    
    func supports(exchangeId: String) -> Bool {
        DirectAPIConfig.all.keys.contains(exchangeId.lowercased())
    }
    
    func connect(exchangeId: String, credentials: ConnectionCredentials) async throws -> ConnectionResult {
        guard case .apiKey(let key, let secret, let passphrase) = credentials else {
            throw ConnectionError.invalidCredentials
        }
        
        guard let config = DirectAPIConfig.get(exchangeId) else {
            throw ConnectionError.unsupportedExchange
        }
        
        // Validate passphrase if required
        if config.requiresPassphrase && (passphrase?.isEmpty ?? true) {
            throw ConnectionError.invalidCredentials
        }
        
        // Validate credentials by making a real API call
        let isValid = try await validateCredentials(
            exchangeId: exchangeId,
            credentials: credentials
        )
        
        guard isValid else {
            throw ConnectionError.invalidCredentials
        }
        
        // Store credentials securely
        let storedCredentials = StoredAPICredentials(
            apiKey: key,
            apiSecret: secret,
            passphrase: passphrase,
            exchangeId: exchangeId,
            createdAt: Date()
        )
        saveCredentials(storedCredentials, for: exchangeId)
        
        // Generate account ID
        let accountId = "\(exchangeId)-\(UUID().uuidString.prefix(8))"
        
        // Fetch initial balances from real exchange API
        let balances = try await fetchBalances(accountId: accountId)
        
        return ConnectionResult(
            success: true,
            accountId: accountId,
            accountName: config.name,
            error: nil,
            balances: balances
        )
    }
    
    func disconnect(accountId: String) async throws {
        let parts = accountId.split(separator: "-")
        if let exchangeId = parts.first {
            removeCredentials(for: String(exchangeId))
        }
    }
    
    func fetchBalances(accountId: String) async throws -> [PortfolioBalance] {
        let parts = accountId.split(separator: "-")
        guard let exchangeId = parts.first else {
            throw ConnectionError.unknown("Invalid account ID")
        }
        
        guard let credentials = getCredentials(for: String(exchangeId)) else {
            throw ConnectionError.invalidCredentials
        }
        
        guard let config = DirectAPIConfig.get(credentials.exchangeId) else {
            throw ConnectionError.unsupportedExchange
        }
        
        switch config.id {
        case "binance", "binance_us":
            return try await fetchBinanceBalances(credentials: credentials, config: config)
        case "kucoin":
            return try await fetchKuCoinBalances(credentials: credentials, config: config)
        case "bybit":
            return try await fetchBybitBalances(credentials: credentials, config: config)
        case "okx":
            return try await fetchOKXBalances(credentials: credentials, config: config)
        case "htx":
            return try await fetchHTXBalances(credentials: credentials, config: config)
        case "gateio":
            return try await fetchGateIOBalances(credentials: credentials, config: config)
        case "mexc":
            return try await fetchMEXCBalances(credentials: credentials, config: config)
        case "bitstamp":
            return try await fetchBitstampBalances(credentials: credentials, config: config)
        case "cryptocom":
            return try await fetchCryptoComBalances(credentials: credentials, config: config)
        case "bitget":
            return try await fetchBitgetBalances(credentials: credentials, config: config)
        case "bitfinex":
            return try await fetchBitfinexBalances(credentials: credentials, config: config)
        default:
            throw ConnectionError.unsupportedExchange
        }
    }
    
    func validateCredentials(exchangeId: String, credentials: ConnectionCredentials) async throws -> Bool {
        guard case .apiKey(let key, let secret, let passphrase) = credentials else {
            return false
        }
        
        guard let config = DirectAPIConfig.get(exchangeId) else {
            return false
        }
        
        // Validate passphrase requirement
        if config.requiresPassphrase && (passphrase?.isEmpty ?? true) {
            return false
        }
        
        switch config.id {
        case "binance", "binance_us":
            return try await validateBinanceCredentials(key: key, secret: secret, config: config)
        case "kucoin":
            return try await validateKuCoinCredentials(key: key, secret: secret, passphrase: passphrase ?? "", config: config)
        case "bybit":
            return try await validateBybitCredentials(key: key, secret: secret, config: config)
        case "okx":
            return try await validateOKXCredentials(key: key, secret: secret, passphrase: passphrase ?? "", config: config)
        case "htx":
            return try await validateHTXCredentials(key: key, secret: secret, config: config)
        case "gateio":
            return try await validateGateIOCredentials(key: key, secret: secret, config: config)
        case "mexc":
            return try await validateMEXCCredentials(key: key, secret: secret, config: config)
        case "bitstamp":
            return try await validateBitstampCredentials(key: key, secret: secret, config: config)
        case "cryptocom":
            return try await validateCryptoComCredentials(key: key, secret: secret, config: config)
        case "bitget":
            return try await validateBitgetCredentials(key: key, secret: secret, passphrase: passphrase ?? "", config: config)
        case "bitfinex":
            return try await validateBitfinexCredentials(key: key, secret: secret, config: config)
        default:
            return false
        }
    }
    
    // MARK: - Credential Storage
    
    private func saveCredentials(_ credentials: StoredAPICredentials, for exchangeId: String) {
        do {
            let data = try JSONEncoder().encode(credentials)
            try KeychainHelper.shared.save(
                String(data: data, encoding: .utf8) ?? "",
                service: "CryptoSage.DirectAPI",
                account: exchangeId
            )
        } catch {
            print("❌ Failed to save API credentials: \(error)")
        }
    }
    
    private func getCredentials(for exchangeId: String) -> StoredAPICredentials? {
        do {
            let credString = try KeychainHelper.shared.read(
                service: "CryptoSage.DirectAPI",
                account: exchangeId
            )
            guard let data = credString.data(using: .utf8) else { return nil }
            return try JSONDecoder().decode(StoredAPICredentials.self, from: data)
        } catch {
            return nil
        }
    }
    
    private func removeCredentials(for exchangeId: String) {
        try? KeychainHelper.shared.delete(
            service: "CryptoSage.DirectAPI",
            account: exchangeId
        )
    }
    
    // MARK: - Signature Generation
    
    private func hmacSHA256(message: String, secret: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        return signature.map { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Binance API
    
    private func fetchBinanceBalances(credentials: StoredAPICredentials, config: DirectAPIConfig) async throws -> [PortfolioBalance] {
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let queryString = "timestamp=\(timestamp)"
        let signature = hmacSHA256(message: queryString, secret: credentials.apiSecret)
        
        let url = config.baseURL
            .appendingPathComponent(config.accountEndpoint)
            .absoluteString + "?\(queryString)&signature=\(signature)"
        
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "GET"
        request.setValue(credentials.apiKey, forHTTPHeaderField: "X-MBX-APIKEY")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConnectionError.networkError(URLError(.badServerResponse))
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw ConnectionError.invalidCredentials
            }
            if httpResponse.statusCode == 429 {
                throw ConnectionError.rateLimited
            }
            throw ConnectionError.serverError(httpResponse.statusCode)
        }
        
        struct BinanceBalance: Codable {
            let asset: String
            let free: String
            let locked: String
        }
        
        struct BinanceAccount: Codable {
            let balances: [BinanceBalance]
        }
        
        let account = try JSONDecoder().decode(BinanceAccount.self, from: data)
        
        return account.balances.compactMap { balance in
            let free = Double(balance.free) ?? 0
            let locked = Double(balance.locked) ?? 0
            let total = free + locked
            
            guard total > 0.00001 else { return nil }
            
            return PortfolioBalance(
                symbol: balance.asset,
                name: balance.asset,
                balance: total
            )
        }
    }
    
    private func validateBinanceCredentials(key: String, secret: String, config: DirectAPIConfig) async throws -> Bool {
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let queryString = "timestamp=\(timestamp)"
        let signature = hmacSHA256(message: queryString, secret: secret)
        
        // Use account info endpoint to validate
        let url = config.baseURL
            .appendingPathComponent("/api/v3/account")
            .absoluteString + "?\(queryString)&signature=\(signature)"
        
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "GET"
        request.setValue(key, forHTTPHeaderField: "X-MBX-APIKEY")
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        
        return (200..<300).contains(httpResponse.statusCode)
    }
    
    // MARK: - KuCoin API
    
    private func fetchKuCoinBalances(credentials: StoredAPICredentials, config: DirectAPIConfig) async throws -> [PortfolioBalance] {
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let method = "GET"
        let endpoint = config.accountEndpoint
        
        // KuCoin signature: timestamp + method + endpoint
        let signatureString = timestamp + method + endpoint
        let signature = hmacSHA256(message: signatureString, secret: credentials.apiSecret)
        let signatureBase64 = Data(signature.utf8).base64EncodedString()
        
        let passphraseSignature = hmacSHA256(message: credentials.passphrase ?? "", secret: credentials.apiSecret)
        let passphraseBase64 = Data(passphraseSignature.utf8).base64EncodedString()
        
        var request = URLRequest(url: config.baseURL.appendingPathComponent(endpoint))
        request.httpMethod = method
        request.setValue(credentials.apiKey, forHTTPHeaderField: "KC-API-KEY")
        request.setValue(signatureBase64, forHTTPHeaderField: "KC-API-SIGN")
        request.setValue(timestamp, forHTTPHeaderField: "KC-API-TIMESTAMP")
        request.setValue(passphraseBase64, forHTTPHeaderField: "KC-API-PASSPHRASE")
        request.setValue("2", forHTTPHeaderField: "KC-API-KEY-VERSION")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConnectionError.networkError(URLError(.badServerResponse))
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw ConnectionError.invalidCredentials
            }
            throw ConnectionError.serverError(httpResponse.statusCode)
        }
        
        struct KuCoinAccount: Codable {
            let id: String
            let currency: String
            let balance: String
            let available: String
        }
        
        struct KuCoinResponse: Codable {
            let code: String
            let data: [KuCoinAccount]
        }
        
        let kucoinResponse = try JSONDecoder().decode(KuCoinResponse.self, from: data)
        
        return kucoinResponse.data.compactMap { account in
            guard let balance = Double(account.balance), balance > 0 else { return nil }
            return PortfolioBalance(
                id: account.id,
                symbol: account.currency,
                name: account.currency,
                balance: balance
            )
        }
    }
    
    private func validateKuCoinCredentials(key: String, secret: String, passphrase: String, config: DirectAPIConfig) async throws -> Bool {
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let method = "GET"
        let endpoint = config.accountEndpoint
        
        let signatureString = timestamp + method + endpoint
        let signature = hmacSHA256(message: signatureString, secret: secret)
        let signatureBase64 = Data(signature.utf8).base64EncodedString()
        
        let passphraseSignature = hmacSHA256(message: passphrase, secret: secret)
        let passphraseBase64 = Data(passphraseSignature.utf8).base64EncodedString()
        
        var request = URLRequest(url: config.baseURL.appendingPathComponent(endpoint))
        request.httpMethod = method
        request.setValue(key, forHTTPHeaderField: "KC-API-KEY")
        request.setValue(signatureBase64, forHTTPHeaderField: "KC-API-SIGN")
        request.setValue(timestamp, forHTTPHeaderField: "KC-API-TIMESTAMP")
        request.setValue(passphraseBase64, forHTTPHeaderField: "KC-API-PASSPHRASE")
        request.setValue("2", forHTTPHeaderField: "KC-API-KEY-VERSION")
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        
        return (200..<300).contains(httpResponse.statusCode)
    }
    
    // MARK: - Bybit API
    
    private func fetchBybitBalances(credentials: StoredAPICredentials, config: DirectAPIConfig) async throws -> [PortfolioBalance] {
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let recvWindow = "5000"
        
        // Bybit V5 signature
        let paramStr = "accountType=UNIFIED"
        let signPayload = timestamp + credentials.apiKey + recvWindow + paramStr
        let signature = hmacSHA256(message: signPayload, secret: credentials.apiSecret)
        
        guard var components = URLComponents(url: config.baseURL.appendingPathComponent(config.accountEndpoint), resolvingAgainstBaseURL: false) else { return false }
        components.queryItems = [URLQueryItem(name: "accountType", value: "UNIFIED")]

        guard let url = components.url else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(credentials.apiKey, forHTTPHeaderField: "X-BAPI-API-KEY")
        request.setValue(timestamp, forHTTPHeaderField: "X-BAPI-TIMESTAMP")
        request.setValue(signature, forHTTPHeaderField: "X-BAPI-SIGN")
        request.setValue(recvWindow, forHTTPHeaderField: "X-BAPI-RECV-WINDOW")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConnectionError.networkError(URLError(.badServerResponse))
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw ConnectionError.invalidCredentials
            }
            throw ConnectionError.serverError(httpResponse.statusCode)
        }
        
        struct BybitCoin: Codable {
            let coin: String
            let walletBalance: String
        }
        
        struct BybitAccount: Codable {
            let coin: [BybitCoin]
        }
        
        struct BybitResult: Codable {
            let list: [BybitAccount]
        }
        
        struct BybitResponse: Codable {
            let retCode: Int
            let result: BybitResult
        }
        
        let bybitResponse = try JSONDecoder().decode(BybitResponse.self, from: data)
        
        guard bybitResponse.retCode == 0, let account = bybitResponse.result.list.first else {
            return []
        }
        
        return account.coin.compactMap { coin in
            guard let balance = Double(coin.walletBalance), balance > 0.00001 else { return nil }
            return PortfolioBalance(
                symbol: coin.coin,
                name: coin.coin,
                balance: balance
            )
        }
    }
    
    private func validateBybitCredentials(key: String, secret: String, config: DirectAPIConfig) async throws -> Bool {
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let recvWindow = "5000"
        
        let paramStr = "accountType=UNIFIED"
        let signPayload = timestamp + key + recvWindow + paramStr
        let signature = hmacSHA256(message: signPayload, secret: secret)
        
        guard var components = URLComponents(url: config.baseURL.appendingPathComponent(config.accountEndpoint), resolvingAgainstBaseURL: false) else { return false }
        components.queryItems = [URLQueryItem(name: "accountType", value: "UNIFIED")]

        guard let url = components.url else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(key, forHTTPHeaderField: "X-BAPI-API-KEY")
        request.setValue(timestamp, forHTTPHeaderField: "X-BAPI-TIMESTAMP")
        request.setValue(signature, forHTTPHeaderField: "X-BAPI-SIGN")
        request.setValue(recvWindow, forHTTPHeaderField: "X-BAPI-RECV-WINDOW")
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        
        return (200..<300).contains(httpResponse.statusCode)
    }
    
    // MARK: - OKX API
    
    private func fetchOKXBalances(credentials: StoredAPICredentials, config: DirectAPIConfig) async throws -> [PortfolioBalance] {
        let timestamp = Self._isoFormatter.string(from: Date())
        let method = "GET"
        let requestPath = config.accountEndpoint
        
        // OKX signature: timestamp + method + requestPath + body
        let signatureString = timestamp + method + requestPath
        let signatureData = Data(signatureString.utf8)
        let key = SymmetricKey(data: Data(credentials.apiSecret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: signatureData, using: key)
        let signatureBase64 = Data(signature).base64EncodedString()
        
        var request = URLRequest(url: config.baseURL.appendingPathComponent(requestPath))
        request.httpMethod = method
        request.setValue(credentials.apiKey, forHTTPHeaderField: "OK-ACCESS-KEY")
        request.setValue(signatureBase64, forHTTPHeaderField: "OK-ACCESS-SIGN")
        request.setValue(timestamp, forHTTPHeaderField: "OK-ACCESS-TIMESTAMP")
        request.setValue(credentials.passphrase ?? "", forHTTPHeaderField: "OK-ACCESS-PASSPHRASE")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConnectionError.networkError(URLError(.badServerResponse))
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw ConnectionError.invalidCredentials
            }
            throw ConnectionError.serverError(httpResponse.statusCode)
        }
        
        struct OKXBalance: Codable {
            let ccy: String
            let bal: String
        }
        
        struct OKXData: Codable {
            let details: [OKXBalance]
        }
        
        struct OKXResponse: Codable {
            let code: String
            let data: [OKXData]
        }
        
        let okxResponse = try JSONDecoder().decode(OKXResponse.self, from: data)
        
        guard okxResponse.code == "0", let balanceData = okxResponse.data.first else {
            return []
        }
        
        return balanceData.details.compactMap { balance in
            guard let bal = Double(balance.bal), bal > 0.00001 else { return nil }
            return PortfolioBalance(
                symbol: balance.ccy,
                name: balance.ccy,
                balance: bal
            )
        }
    }
    
    private func validateOKXCredentials(key: String, secret: String, passphrase: String, config: DirectAPIConfig) async throws -> Bool {
        let timestamp = Self._isoFormatter.string(from: Date())
        let method = "GET"
        let requestPath = config.accountEndpoint
        
        let signatureString = timestamp + method + requestPath
        let signatureData = Data(signatureString.utf8)
        let keyData = SymmetricKey(data: Data(secret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: signatureData, using: keyData)
        let signatureBase64 = Data(signature).base64EncodedString()
        
        var request = URLRequest(url: config.baseURL.appendingPathComponent(requestPath))
        request.httpMethod = method
        request.setValue(key, forHTTPHeaderField: "OK-ACCESS-KEY")
        request.setValue(signatureBase64, forHTTPHeaderField: "OK-ACCESS-SIGN")
        request.setValue(timestamp, forHTTPHeaderField: "OK-ACCESS-TIMESTAMP")
        request.setValue(passphrase, forHTTPHeaderField: "OK-ACCESS-PASSPHRASE")
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        
        return (200..<300).contains(httpResponse.statusCode)
    }
    
    // MARK: - HTX (Huobi) API
    
    private func fetchHTXBalances(credentials: StoredAPICredentials, config: DirectAPIConfig) async throws -> [PortfolioBalance] {
        // First, get account ID
        let accountId = try await getHTXAccountId(credentials: credentials, config: config)
        
        // Then fetch balances for that account
        let timestamp = Self._isoFormatter.string(from: Date()).replacingOccurrences(of: ":", with: "%3A")
        let method = "GET"
        let endpoint = "/v1/account/accounts/\(accountId)/balance"
        
        // Build signature payload
        var params: [(String, String)] = [
            ("AccessKeyId", credentials.apiKey),
            ("SignatureMethod", "HmacSHA256"),
            ("SignatureVersion", "2"),
            ("Timestamp", timestamp)
        ]
        params.sort { $0.0 < $1.0 }
        
        let paramString = params.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        let host = "api.huobi.pro"
        let preSign = "\(method)\n\(host)\n\(endpoint)\n\(paramString)"
        
        let key = SymmetricKey(data: Data(credentials.apiSecret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(preSign.utf8), using: key)
        let signatureBase64 = Data(signature).base64EncodedString()
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        let urlString = "https://\(host)\(endpoint)?\(paramString)&Signature=\(signatureBase64)"
        
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConnectionError.networkError(URLError(.badServerResponse))
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw ConnectionError.invalidCredentials
            }
            throw ConnectionError.serverError(httpResponse.statusCode)
        }
        
        struct HTXBalance: Codable {
            let currency: String
            let type: String
            let balance: String
        }
        
        struct HTXAccountBalance: Codable {
            let list: [HTXBalance]
        }
        
        struct HTXResponse: Codable {
            let status: String
            let data: HTXAccountBalance?
        }
        
        let htxResponse = try JSONDecoder().decode(HTXResponse.self, from: data)
        
        guard htxResponse.status == "ok", let balanceData = htxResponse.data else {
            return []
        }
        
        // Combine trade and frozen balances
        var balanceMap: [String: Double] = [:]
        for balance in balanceData.list {
            let amount = Double(balance.balance) ?? 0
            if amount > 0 {
                balanceMap[balance.currency.uppercased(), default: 0] += amount
            }
        }
        
        return balanceMap.compactMap { currency, total in
            guard total > 0.00001 else { return nil }
            return PortfolioBalance(
                symbol: currency,
                name: currency,
                balance: total
            )
        }
    }
    
    private func getHTXAccountId(credentials: StoredAPICredentials, config: DirectAPIConfig) async throws -> Int {
        let timestamp = Self._isoFormatter.string(from: Date()).replacingOccurrences(of: ":", with: "%3A")
        let method = "GET"
        let endpoint = "/v1/account/accounts"
        
        var params: [(String, String)] = [
            ("AccessKeyId", credentials.apiKey),
            ("SignatureMethod", "HmacSHA256"),
            ("SignatureVersion", "2"),
            ("Timestamp", timestamp)
        ]
        params.sort { $0.0 < $1.0 }
        
        let paramString = params.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        let host = "api.huobi.pro"
        let preSign = "\(method)\n\(host)\n\(endpoint)\n\(paramString)"
        
        let key = SymmetricKey(data: Data(credentials.apiSecret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(preSign.utf8), using: key)
        let signatureBase64 = Data(signature).base64EncodedString()
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        let urlString = "https://\(host)\(endpoint)?\(paramString)&Signature=\(signatureBase64)"
        
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw ConnectionError.invalidCredentials
        }
        
        struct HTXAccount: Codable {
            let id: Int
            let type: String
            let state: String
        }
        
        struct HTXAccountsResponse: Codable {
            let status: String
            let data: [HTXAccount]?
        }
        
        let accountsResponse = try JSONDecoder().decode(HTXAccountsResponse.self, from: data)
        
        guard accountsResponse.status == "ok",
              let accounts = accountsResponse.data,
              let spotAccount = accounts.first(where: { $0.type == "spot" && $0.state == "working" }) else {
            throw ConnectionError.unknown("No spot account found")
        }
        
        return spotAccount.id
    }
    
    private func validateHTXCredentials(key: String, secret: String, config: DirectAPIConfig) async throws -> Bool {
        let timestamp = Self._isoFormatter.string(from: Date()).replacingOccurrences(of: ":", with: "%3A")
        let method = "GET"
        let endpoint = "/v1/account/accounts"
        
        var params: [(String, String)] = [
            ("AccessKeyId", key),
            ("SignatureMethod", "HmacSHA256"),
            ("SignatureVersion", "2"),
            ("Timestamp", timestamp)
        ]
        params.sort { $0.0 < $1.0 }
        
        let paramString = params.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        let host = "api.huobi.pro"
        let preSign = "\(method)\n\(host)\n\(endpoint)\n\(paramString)"
        
        let keyData = SymmetricKey(data: Data(secret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(preSign.utf8), using: keyData)
        let signatureBase64 = Data(signature).base64EncodedString()
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        let urlString = "https://\(host)\(endpoint)?\(paramString)&Signature=\(signatureBase64)"
        
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        
        if (200..<300).contains(httpResponse.statusCode) {
            // Also check the response status
            struct HTXResponse: Codable {
                let status: String
            }
            if let htxResponse = try? JSONDecoder().decode(HTXResponse.self, from: data) {
                return htxResponse.status == "ok"
            }
        }
        
        return false
    }
    
    // MARK: - Gate.io API
    
    private func fetchGateIOBalances(credentials: StoredAPICredentials, config: DirectAPIConfig) async throws -> [PortfolioBalance] {
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let method = "GET"
        let endpoint = config.accountEndpoint
        let queryString = ""
        let bodyHash = SHA512.hash(data: Data()).map { String(format: "%02x", $0) }.joined()
        
        // Gate.io signature: method\nurl\nquery_string\nhashed_body\ntimestamp
        let signatureString = "\(method)\n\(endpoint)\n\(queryString)\n\(bodyHash)\n\(timestamp)"
        
        let key = SymmetricKey(data: Data(credentials.apiSecret.utf8))
        let signature = HMAC<SHA512>.authenticationCode(for: Data(signatureString.utf8), using: key)
        let signatureHex = signature.map { String(format: "%02x", $0) }.joined()
        
        var request = URLRequest(url: config.baseURL.appendingPathComponent(endpoint))
        request.httpMethod = method
        request.setValue(credentials.apiKey, forHTTPHeaderField: "KEY")
        request.setValue(signatureHex, forHTTPHeaderField: "SIGN")
        request.setValue(timestamp, forHTTPHeaderField: "Timestamp")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConnectionError.networkError(URLError(.badServerResponse))
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw ConnectionError.invalidCredentials
            }
            throw ConnectionError.serverError(httpResponse.statusCode)
        }
        
        struct GateIOBalance: Codable {
            let currency: String
            let available: String
            let locked: String
        }
        
        let gateBalances = try JSONDecoder().decode([GateIOBalance].self, from: data)
        
        return gateBalances.compactMap { balance in
            let available = Double(balance.available) ?? 0
            let locked = Double(balance.locked) ?? 0
            let total = available + locked
            
            guard total > 0.00001 else { return nil }
            
            return PortfolioBalance(
                symbol: balance.currency,
                name: balance.currency,
                balance: total
            )
        }
    }
    
    private func validateGateIOCredentials(key: String, secret: String, config: DirectAPIConfig) async throws -> Bool {
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let method = "GET"
        let endpoint = config.accountEndpoint
        let queryString = ""
        let bodyHash = SHA512.hash(data: Data()).map { String(format: "%02x", $0) }.joined()
        
        let signatureString = "\(method)\n\(endpoint)\n\(queryString)\n\(bodyHash)\n\(timestamp)"
        
        let keyData = SymmetricKey(data: Data(secret.utf8))
        let signature = HMAC<SHA512>.authenticationCode(for: Data(signatureString.utf8), using: keyData)
        let signatureHex = signature.map { String(format: "%02x", $0) }.joined()
        
        var request = URLRequest(url: config.baseURL.appendingPathComponent(endpoint))
        request.httpMethod = method
        request.setValue(key, forHTTPHeaderField: "KEY")
        request.setValue(signatureHex, forHTTPHeaderField: "SIGN")
        request.setValue(timestamp, forHTTPHeaderField: "Timestamp")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        
        return (200..<300).contains(httpResponse.statusCode)
    }
    
    // MARK: - MEXC API
    
    private func fetchMEXCBalances(credentials: StoredAPICredentials, config: DirectAPIConfig) async throws -> [PortfolioBalance] {
        // MEXC uses Binance-compatible API
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let queryString = "timestamp=\(timestamp)"
        let signature = hmacSHA256(message: queryString, secret: credentials.apiSecret)
        
        let url = config.baseURL
            .appendingPathComponent(config.accountEndpoint)
            .absoluteString + "?\(queryString)&signature=\(signature)"
        
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "GET"
        request.setValue(credentials.apiKey, forHTTPHeaderField: "X-MEXC-APIKEY")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConnectionError.networkError(URLError(.badServerResponse))
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw ConnectionError.invalidCredentials
            }
            if httpResponse.statusCode == 429 {
                throw ConnectionError.rateLimited
            }
            throw ConnectionError.serverError(httpResponse.statusCode)
        }
        
        struct MEXCBalance: Codable {
            let asset: String
            let free: String
            let locked: String
        }
        
        struct MEXCAccount: Codable {
            let balances: [MEXCBalance]
        }
        
        let account = try JSONDecoder().decode(MEXCAccount.self, from: data)
        
        return account.balances.compactMap { balance in
            let free = Double(balance.free) ?? 0
            let locked = Double(balance.locked) ?? 0
            let total = free + locked
            
            guard total > 0.00001 else { return nil }
            
            return PortfolioBalance(
                symbol: balance.asset,
                name: balance.asset,
                balance: total
            )
        }
    }
    
    private func validateMEXCCredentials(key: String, secret: String, config: DirectAPIConfig) async throws -> Bool {
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let queryString = "timestamp=\(timestamp)"
        let signature = hmacSHA256(message: queryString, secret: secret)
        
        let url = config.baseURL
            .appendingPathComponent(config.accountEndpoint)
            .absoluteString + "?\(queryString)&signature=\(signature)"
        
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "GET"
        request.setValue(key, forHTTPHeaderField: "X-MEXC-APIKEY")
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        
        return (200..<300).contains(httpResponse.statusCode)
    }
    
    // MARK: - Bitstamp API
    
    private func fetchBitstampBalances(credentials: StoredAPICredentials, config: DirectAPIConfig) async throws -> [PortfolioBalance] {
        let nonce = UUID().uuidString
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let contentType = "application/x-www-form-urlencoded"
        let method = "POST"
        let host = "www.bitstamp.net"
        let path = config.accountEndpoint
        let body = ""
        
        // Bitstamp V2 Auth: BITSTAMP api_key:signature:nonce:timestamp:version
        // signature = HMAC-SHA256(nonce + timestamp + host + method + path + contentType + body)
        let messageToSign = nonce + timestamp + host + method + path + contentType + body
        
        let key = SymmetricKey(data: Data(credentials.apiSecret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(messageToSign.utf8), using: key)
        let signatureHex = signature.map { String(format: "%02x", $0) }.joined()
        
        let authHeader = "BITSTAMP \(credentials.apiKey):\(signatureHex):\(nonce):\(timestamp):v2"
        
        var request = URLRequest(url: config.baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue(authHeader, forHTTPHeaderField: "X-Auth")
        request.setValue(nonce, forHTTPHeaderField: "X-Auth-Nonce")
        request.setValue(timestamp, forHTTPHeaderField: "X-Auth-Timestamp")
        request.setValue("v2", forHTTPHeaderField: "X-Auth-Version")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConnectionError.networkError(URLError(.badServerResponse))
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw ConnectionError.invalidCredentials
            }
            throw ConnectionError.serverError(httpResponse.statusCode)
        }
        
        // Bitstamp returns a flat dictionary with currency_balance, currency_available, etc.
        guard let balanceDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        
        // Extract balances - Bitstamp uses keys like "btc_balance", "eth_balance", etc.
        var balances: [PortfolioBalance] = []
        let currencies = Set(balanceDict.keys.compactMap { key -> String? in
            guard key.hasSuffix("_balance") else { return nil }
            return String(key.dropLast(8)) // Remove "_balance"
        })
        
        for currency in currencies {
            guard let balanceStr = balanceDict["\(currency)_balance"] as? String,
                  let balance = Double(balanceStr),
                  balance > 0.00001 else {
                continue
            }
            
            balances.append(PortfolioBalance(
                symbol: currency.uppercased(),
                name: currency.uppercased(),
                balance: balance
            ))
        }
        
        return balances
    }
    
    private func validateBitstampCredentials(key: String, secret: String, config: DirectAPIConfig) async throws -> Bool {
        let nonce = UUID().uuidString
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let contentType = "application/x-www-form-urlencoded"
        let method = "POST"
        let host = "www.bitstamp.net"
        let path = config.accountEndpoint
        let body = ""
        
        let messageToSign = nonce + timestamp + host + method + path + contentType + body
        
        let keyData = SymmetricKey(data: Data(secret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(messageToSign.utf8), using: keyData)
        let signatureHex = signature.map { String(format: "%02x", $0) }.joined()
        
        let authHeader = "BITSTAMP \(key):\(signatureHex):\(nonce):\(timestamp):v2"
        
        var request = URLRequest(url: config.baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue(authHeader, forHTTPHeaderField: "X-Auth")
        request.setValue(nonce, forHTTPHeaderField: "X-Auth-Nonce")
        request.setValue(timestamp, forHTTPHeaderField: "X-Auth-Timestamp")
        request.setValue("v2", forHTTPHeaderField: "X-Auth-Version")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        
        return (200..<300).contains(httpResponse.statusCode)
    }
    
    // MARK: - Crypto.com API
    
    private func fetchCryptoComBalances(credentials: StoredAPICredentials, config: DirectAPIConfig) async throws -> [PortfolioBalance] {
        let nonce = String(Int(Date().timeIntervalSince1970 * 1000))
        let id = Int.random(in: 1...999999)
        
        let requestBody: [String: Any] = [
            "id": id,
            "method": "private/get-account-summary",
            "api_key": credentials.apiKey,
            "params": [:],
            "nonce": nonce
        ]
        
        // Crypto.com signature: method + id + api_key + params_string + nonce
        let paramString = "" // Empty params
        let signPayload = "private/get-account-summary\(id)\(credentials.apiKey)\(paramString)\(nonce)"
        let signature = hmacSHA256(message: signPayload, secret: credentials.apiSecret)
        
        var bodyWithSig = requestBody
        bodyWithSig["sig"] = signature
        
        var request = URLRequest(url: config.baseURL.appendingPathComponent(config.accountEndpoint))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: bodyWithSig)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConnectionError.networkError(URLError(.badServerResponse))
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw ConnectionError.invalidCredentials
            }
            throw ConnectionError.serverError(httpResponse.statusCode)
        }
        
        struct CryptoComBalance: Codable {
            let currency: String
            let balance: Double
            let available: Double
        }
        
        struct CryptoComResult: Codable {
            let accounts: [CryptoComBalance]
        }
        
        struct CryptoComResponse: Codable {
            let code: Int
            let result: CryptoComResult?
        }
        
        let cryptoResponse = try JSONDecoder().decode(CryptoComResponse.self, from: data)
        
        guard cryptoResponse.code == 0, let result = cryptoResponse.result else {
            return []
        }
        
        return result.accounts.compactMap { account in
            guard account.balance > 0.00001 else { return nil }
            return PortfolioBalance(
                symbol: account.currency,
                name: account.currency,
                balance: account.balance
            )
        }
    }
    
    private func validateCryptoComCredentials(key: String, secret: String, config: DirectAPIConfig) async throws -> Bool {
        let nonce = String(Int(Date().timeIntervalSince1970 * 1000))
        let id = Int.random(in: 1...999999)
        
        let requestBody: [String: Any] = [
            "id": id,
            "method": "private/get-account-summary",
            "api_key": key,
            "params": [:],
            "nonce": nonce
        ]
        
        let paramString = ""
        let signPayload = "private/get-account-summary\(id)\(key)\(paramString)\(nonce)"
        let signature = hmacSHA256(message: signPayload, secret: secret)
        
        var bodyWithSig = requestBody
        bodyWithSig["sig"] = signature
        
        var request = URLRequest(url: config.baseURL.appendingPathComponent(config.accountEndpoint))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: bodyWithSig)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        
        if (200..<300).contains(httpResponse.statusCode) {
            struct CryptoComResponse: Codable {
                let code: Int
            }
            if let cryptoResponse = try? JSONDecoder().decode(CryptoComResponse.self, from: data) {
                return cryptoResponse.code == 0
            }
        }
        
        return false
    }
    
    // MARK: - Bitget API
    
    private func fetchBitgetBalances(credentials: StoredAPICredentials, config: DirectAPIConfig) async throws -> [PortfolioBalance] {
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let method = "GET"
        let endpoint = config.accountEndpoint
        
        // Bitget signature: timestamp + method + requestPath + queryString + body
        let signPayload = timestamp + method + endpoint
        let signature = hmacSHA256(message: signPayload, secret: credentials.apiSecret)
        let signatureBase64 = Data(signature.utf8).base64EncodedString()
        
        var request = URLRequest(url: config.baseURL.appendingPathComponent(endpoint))
        request.httpMethod = method
        request.setValue(credentials.apiKey, forHTTPHeaderField: "ACCESS-KEY")
        request.setValue(signatureBase64, forHTTPHeaderField: "ACCESS-SIGN")
        request.setValue(timestamp, forHTTPHeaderField: "ACCESS-TIMESTAMP")
        request.setValue(credentials.passphrase ?? "", forHTTPHeaderField: "ACCESS-PASSPHRASE")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConnectionError.networkError(URLError(.badServerResponse))
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw ConnectionError.invalidCredentials
            }
            throw ConnectionError.serverError(httpResponse.statusCode)
        }
        
        struct BitgetAsset: Codable {
            let coin: String
            let available: String
            let frozen: String?
            let locked: String?
        }
        
        struct BitgetResponse: Codable {
            let code: String
            let data: [BitgetAsset]?
        }
        
        let bitgetResponse = try JSONDecoder().decode(BitgetResponse.self, from: data)
        
        guard bitgetResponse.code == "00000", let assets = bitgetResponse.data else {
            return []
        }
        
        return assets.compactMap { asset in
            let available = Double(asset.available) ?? 0
            let frozen = Double(asset.frozen ?? "0") ?? 0
            let locked = Double(asset.locked ?? "0") ?? 0
            let total = available + frozen + locked
            
            guard total > 0.00001 else { return nil }
            
            return PortfolioBalance(
                symbol: asset.coin,
                name: asset.coin,
                balance: total
            )
        }
    }
    
    private func validateBitgetCredentials(key: String, secret: String, passphrase: String, config: DirectAPIConfig) async throws -> Bool {
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let method = "GET"
        let endpoint = config.accountEndpoint
        
        let signPayload = timestamp + method + endpoint
        let signature = hmacSHA256(message: signPayload, secret: secret)
        let signatureBase64 = Data(signature.utf8).base64EncodedString()
        
        var request = URLRequest(url: config.baseURL.appendingPathComponent(endpoint))
        request.httpMethod = method
        request.setValue(key, forHTTPHeaderField: "ACCESS-KEY")
        request.setValue(signatureBase64, forHTTPHeaderField: "ACCESS-SIGN")
        request.setValue(timestamp, forHTTPHeaderField: "ACCESS-TIMESTAMP")
        request.setValue(passphrase, forHTTPHeaderField: "ACCESS-PASSPHRASE")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        
        if (200..<300).contains(httpResponse.statusCode) {
            struct BitgetResponse: Codable {
                let code: String
            }
            if let bitgetResponse = try? JSONDecoder().decode(BitgetResponse.self, from: data) {
                return bitgetResponse.code == "00000"
            }
        }
        
        return false
    }
    
    // MARK: - Bitfinex API
    
    private func fetchBitfinexBalances(credentials: StoredAPICredentials, config: DirectAPIConfig) async throws -> [PortfolioBalance] {
        let nonce = String(Int(Date().timeIntervalSince1970 * 1000000))
        let endpoint = config.accountEndpoint
        let body = "{}"
        
        // Bitfinex signature: /api + endpoint + nonce + body
        let signPayload = "/api\(endpoint)\(nonce)\(body)"
        let signature = hmacSHA384(message: signPayload, secret: credentials.apiSecret)
        
        var request = URLRequest(url: config.baseURL.appendingPathComponent(endpoint))
        request.httpMethod = "POST"
        request.setValue(credentials.apiKey, forHTTPHeaderField: "bfx-apikey")
        request.setValue(nonce, forHTTPHeaderField: "bfx-nonce")
        request.setValue(signature, forHTTPHeaderField: "bfx-signature")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConnectionError.networkError(URLError(.badServerResponse))
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw ConnectionError.invalidCredentials
            }
            throw ConnectionError.serverError(httpResponse.statusCode)
        }
        
        // Bitfinex returns array of [WALLET_TYPE, CURRENCY, BALANCE, UNSETTLED_INTEREST, AVAILABLE_BALANCE, ...]
        guard let wallets = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else {
            return []
        }
        
        var balanceMap: [String: Double] = [:]
        
        for wallet in wallets {
            guard wallet.count >= 3,
                  let currency = wallet[1] as? String,
                  let balance = wallet[2] as? Double,
                  balance > 0.00001 else {
                continue
            }
            
            // Aggregate balances from different wallet types (exchange, margin, funding)
            balanceMap[currency, default: 0] += balance
        }
        
        return balanceMap.compactMap { currency, total in
            guard total > 0.00001 else { return nil }
            return PortfolioBalance(
                symbol: currency,
                name: currency,
                balance: total
            )
        }
    }
    
    private func validateBitfinexCredentials(key: String, secret: String, config: DirectAPIConfig) async throws -> Bool {
        let nonce = String(Int(Date().timeIntervalSince1970 * 1000000))
        let endpoint = config.accountEndpoint
        let body = "{}"
        
        let signPayload = "/api\(endpoint)\(nonce)\(body)"
        let signature = hmacSHA384(message: signPayload, secret: secret)
        
        var request = URLRequest(url: config.baseURL.appendingPathComponent(endpoint))
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "bfx-apikey")
        request.setValue(nonce, forHTTPHeaderField: "bfx-nonce")
        request.setValue(signature, forHTTPHeaderField: "bfx-signature")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        
        return (200..<300).contains(httpResponse.statusCode)
    }
    
    // MARK: - Additional Signature Helpers
    
    private func hmacSHA384(message: String, secret: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let signature = HMAC<SHA384>.authenticationCode(for: Data(message.utf8), using: key)
        return signature.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Replace Stub with Implementation

extension DirectAPIConnectionProvider {
    /// Override the stub methods to use the real implementation
    static var implementation: DirectAPIConnectionProviderImpl {
        DirectAPIConnectionProviderImpl.shared
    }
}
