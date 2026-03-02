import Foundation
import CryptoKit
import Combine

// MARK: - ThreeCommas API Error

enum ThreeCommasError: LocalizedError {
    case invalidCredentials
    case unauthorized
    case insufficientPermissions
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(statusCode: Int)
    case networkError(Error)
    case decodingError(Error)
    case notConfigured
    case tradingNotConfigured
    
    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid API credentials. Please check your API key and secret."
        case .unauthorized:
            return "Unauthorized. Please verify your API credentials have the correct permissions."
        case .insufficientPermissions:
            return "API key lacks required permissions. Please use a key with trading permissions to control bots."
        case .rateLimited(let retryAfter):
            if let retry = retryAfter {
                return "Rate limited. Please try again in \(Int(retry)) seconds."
            }
            return "Rate limited. Please try again later."
        case .serverError(let code):
            return "Server error (HTTP \(code)). Please try again later."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError:
            return "Failed to parse server response."
        case .notConfigured:
            return "3Commas is not configured. Please add your API key and secret in settings."
        case .tradingNotConfigured:
            return "3Commas trading key is not configured. Please add a trading API key with bot control permissions."
        }
    }
}

// MARK: - ThreeCommas API Client

final class ThreeCommasAPI {
    static let shared = ThreeCommasAPI()
    
    // MARK: - Configuration
    
    /// Check if 3Commas read-only credentials are configured (for viewing accounts, bots, etc.)
    var isConfigured: Bool {
        !ThreeCommasConfig.readOnlyAPIKey.isEmpty && !ThreeCommasConfig.readOnlySecret.isEmpty
    }
    
    /// Check if 3Commas trading credentials are configured (for enabling/disabling bots)
    var isTradingConfigured: Bool {
        !ThreeCommasConfig.tradingAPIKey.isEmpty && !ThreeCommasConfig.tradingSecret.isEmpty
    }
    
    /// Check if trading is available (either trading key configured, or read-only key has trading permissions)
    /// Falls back to read-only key if trading key is not configured
    private var effectiveTradingAPIKey: String {
        let tradingKey = ThreeCommasConfig.tradingAPIKey
        return tradingKey.isEmpty ? ThreeCommasConfig.readOnlyAPIKey : tradingKey
    }
    
    private var effectiveTradingSecret: String {
        let tradingSecret = ThreeCommasConfig.tradingSecret
        return tradingSecret.isEmpty ? ThreeCommasConfig.readOnlySecret : tradingSecret
    }
    
    // MARK: - Session
    
    private lazy var session: URLSession = {
        // SECURITY: Ephemeral session prevents disk caching of trading bot data,
        // account balances, and API key-authenticated responses.
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        // SECURITY: Route through certificate pinning for MITM protection on trading API
        return CertificatePinningManager.shared.createPinnedSession(configuration: config)
    }()
    
    private init() {}
    
    // MARK: - Mock Data
    
    private static let mockAccounts: [Account] = [
        Account(id: 1001, name: "Binance Main", currency: "USDT"),
        Account(id: 1002, name: "Coinbase Pro", currency: "USD"),
        Account(id: 1003, name: "Kraken Trading", currency: "EUR")
    ]
    
    private static let mockBalances: [AccountBalance] = [
        AccountBalance(currency: "BTC", balance: 0.5),
        AccountBalance(currency: "ETH", balance: 2.5),
        AccountBalance(currency: "USDT", balance: 5000.0),
        AccountBalance(currency: "SOL", balance: 25.0),
        AccountBalance(currency: "DOGE", balance: 10000.0)
    ]
    
    // MARK: - Connection & Validation

    /// Test connection using API credentials
    /// Returns true if credentials are valid, false otherwise
    func connect(apiKey: String, apiSecret: String) async throws -> Bool {
        guard !apiKey.isEmpty, !apiSecret.isEmpty else {
            throw ThreeCommasError.invalidCredentials
        }
        
        // Build the verification request
        // 3Commas uses GET /public/api/ver1/accounts as a test endpoint
        let url = ThreeCommasConfig.baseURL.appendingPathComponent("public/api/ver1/accounts")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        
        // Add headers
        request.setValue(apiKey, forHTTPHeaderField: "APIKEY")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("CryptoSage/1.0", forHTTPHeaderField: "User-Agent")
        
        // Compute HMAC-SHA256 signature for the request
        let signature = computeSignature(
            secret: apiSecret,
            method: "GET",
            path: "/public/api/ver1/accounts",
            body: nil
        )
        request.setValue(signature, forHTTPHeaderField: "Signature")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ThreeCommasError.networkError(URLError(.badServerResponse))
            }
            
            switch httpResponse.statusCode {
            case 200..<300:
                // Try to decode to verify the response is valid
                _ = try? JSONDecoder().decode([Account].self, from: data)
                return true
            case 401, 403:
                throw ThreeCommasError.unauthorized
            case 429:
                let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                    .flatMap { TimeInterval($0) }
                throw ThreeCommasError.rateLimited(retryAfter: retryAfter)
            default:
                throw ThreeCommasError.serverError(statusCode: httpResponse.statusCode)
            }
        } catch let error as ThreeCommasError {
            throw error
        } catch {
            throw ThreeCommasError.networkError(error)
        }
    }
    
    /// Validate the currently configured credentials
    func validateCredentials() async throws -> Bool {
        let apiKey = ThreeCommasConfig.readOnlyAPIKey
        let apiSecret = ThreeCommasConfig.readOnlySecret
        return try await connect(apiKey: apiKey, apiSecret: apiSecret)
    }

    /// Fetch all 3Commas accounts asynchronously and decode to [Account]
    func listAccounts() async throws -> [Account] {
        guard isConfigured else {
            throw ThreeCommasError.notConfigured
        }
        
        let url = ThreeCommasConfig.baseURL.appendingPathComponent("public/api/ver1/accounts")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        
        let apiKey = ThreeCommasConfig.readOnlyAPIKey
        let apiSecret = ThreeCommasConfig.readOnlySecret
        
        request.setValue(apiKey, forHTTPHeaderField: "APIKEY")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("CryptoSage/1.0", forHTTPHeaderField: "User-Agent")
        
        let signature = computeSignature(
            secret: apiSecret,
            method: "GET",
            path: "/public/api/ver1/accounts",
            body: nil
        )
        request.setValue(signature, forHTTPHeaderField: "Signature")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ThreeCommasError.networkError(URLError(.badServerResponse))
            }
            
            guard (200..<300).contains(httpResponse.statusCode) else {
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    throw ThreeCommasError.unauthorized
                }
                throw ThreeCommasError.serverError(statusCode: httpResponse.statusCode)
            }
            
            return try JSONDecoder().decode([Account].self, from: data)
        } catch let error as ThreeCommasError {
            throw error
        } catch let error as DecodingError {
            throw ThreeCommasError.decodingError(error)
        } catch {
            throw ThreeCommasError.networkError(error)
        }
    }

    /// Fetch balances for a single 3Commas account ID asynchronously and decode to [AccountBalance]
    func loadAccountBalances(accountId: Int) async throws -> [AccountBalance] {
        guard isConfigured else {
            throw ThreeCommasError.notConfigured
        }
        
        let path = "/public/api/ver1/accounts/\(accountId)/account_table_data"
        let url = ThreeCommasConfig.baseURL.appendingPathComponent("public/api/ver1/accounts/\(accountId)/account_table_data")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        
        let apiKey = ThreeCommasConfig.readOnlyAPIKey
        let apiSecret = ThreeCommasConfig.readOnlySecret
        
        request.setValue(apiKey, forHTTPHeaderField: "APIKEY")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("CryptoSage/1.0", forHTTPHeaderField: "User-Agent")
        
        let signature = computeSignature(
            secret: apiSecret,
            method: "GET",
            path: path,
            body: nil
        )
        request.setValue(signature, forHTTPHeaderField: "Signature")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ThreeCommasError.networkError(URLError(.badServerResponse))
            }
            
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw ThreeCommasError.serverError(statusCode: httpResponse.statusCode)
            }
            
            return try JSONDecoder().decode([AccountBalance].self, from: data)
        } catch let error as ThreeCommasError {
            throw error
        } catch let error as DecodingError {
            throw ThreeCommasError.decodingError(error)
        } catch {
            throw ThreeCommasError.networkError(error)
        }
    }
    
    // MARK: - Signature Computation
    
    /// Compute HMAC-SHA256 signature for 3Commas API requests
    private func computeSignature(secret: String, method: String, path: String, body: Data?) -> String {
        // 3Commas signature format: HMAC-SHA256(secret, path + body)
        let bodyString = body.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let signatureData = (path + bodyString).data(using: .utf8) ?? Data()
        
        let secretKey = SymmetricKey(data: Data(secret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: signatureData, using: secretKey)
        return signature.map { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Bot Management API
    
    /// List all trading bots for the user
    /// - Parameter scope: Optional filter for bot scope (e.g., "enabled", "disabled")
    /// - Returns: Array of ThreeCommasBot objects
    func listBots(scope: String? = nil) async throws -> [ThreeCommasBot] {
        guard isConfigured else {
            throw ThreeCommasError.notConfigured
        }
        
        var path = "/public/api/ver1/bots"
        if let scope = scope {
            path += "?scope=\(scope)"
        }
        
        let url = ThreeCommasConfig.baseURL.appendingPathComponent("public/api/ver1/bots")
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw URLError(.badURL) }
        if let scope = scope {
            components.queryItems = [URLQueryItem(name: "scope", value: scope)]
        }
        
        guard let finalURL = components.url else {
            throw ThreeCommasError.networkError(URLError(.badURL))
        }
        
        var request = URLRequest(url: finalURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        
        let apiKey = ThreeCommasConfig.readOnlyAPIKey
        let apiSecret = ThreeCommasConfig.readOnlySecret
        
        request.setValue(apiKey, forHTTPHeaderField: "APIKEY")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("CryptoSage/1.0", forHTTPHeaderField: "User-Agent")
        
        let signature = computeSignature(
            secret: apiSecret,
            method: "GET",
            path: path,
            body: nil
        )
        request.setValue(signature, forHTTPHeaderField: "Signature")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ThreeCommasError.networkError(URLError(.badServerResponse))
            }
            
            guard (200..<300).contains(httpResponse.statusCode) else {
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    throw ThreeCommasError.unauthorized
                }
                if httpResponse.statusCode == 429 {
                    let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                        .flatMap { TimeInterval($0) }
                    throw ThreeCommasError.rateLimited(retryAfter: retryAfter)
                }
                throw ThreeCommasError.serverError(statusCode: httpResponse.statusCode)
            }
            
            let decoder = JSONDecoder()
            return try decoder.decode([ThreeCommasBot].self, from: data)
        } catch let error as ThreeCommasError {
            throw error
        } catch let error as DecodingError {
            throw ThreeCommasError.decodingError(error)
        } catch {
            throw ThreeCommasError.networkError(error)
        }
    }
    
    /// Get details of a specific bot
    /// - Parameter botId: The ID of the bot to fetch
    /// - Returns: ThreeCommasBot object
    func getBot(botId: Int) async throws -> ThreeCommasBot {
        guard isConfigured else {
            throw ThreeCommasError.notConfigured
        }
        
        let path = "/public/api/ver1/bots/\(botId)/show"
        let url = ThreeCommasConfig.baseURL.appendingPathComponent("public/api/ver1/bots/\(botId)/show")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        
        let apiKey = ThreeCommasConfig.readOnlyAPIKey
        let apiSecret = ThreeCommasConfig.readOnlySecret
        
        request.setValue(apiKey, forHTTPHeaderField: "APIKEY")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("CryptoSage/1.0", forHTTPHeaderField: "User-Agent")
        
        let signature = computeSignature(
            secret: apiSecret,
            method: "GET",
            path: path,
            body: nil
        )
        request.setValue(signature, forHTTPHeaderField: "Signature")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ThreeCommasError.networkError(URLError(.badServerResponse))
            }
            
            guard (200..<300).contains(httpResponse.statusCode) else {
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    throw ThreeCommasError.unauthorized
                }
                throw ThreeCommasError.serverError(statusCode: httpResponse.statusCode)
            }
            
            let decoder = JSONDecoder()
            return try decoder.decode(ThreeCommasBot.self, from: data)
        } catch let error as ThreeCommasError {
            throw error
        } catch let error as DecodingError {
            throw ThreeCommasError.decodingError(error)
        } catch {
            throw ThreeCommasError.networkError(error)
        }
    }
    
    /// Enable (start) a trading bot
    /// - Parameter botId: The ID of the bot to enable
    /// - Returns: Updated ThreeCommasBot object
    /// - Note: Requires trading API key with bot control permissions
    @discardableResult
    func enableBot(botId: Int) async throws -> ThreeCommasBot {
        // SAFETY: Block live bot operations when trading is disabled at app config level
        guard AppConfig.liveTradingEnabled else {
            throw ThreeCommasError.tradingNotConfigured
        }
        
        guard isConfigured else {
            throw ThreeCommasError.notConfigured
        }
        
        let path = "/public/api/ver1/bots/\(botId)/enable"
        let url = ThreeCommasConfig.baseURL.appendingPathComponent("public/api/ver1/bots/\(botId)/enable")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        
        // Use trading credentials for bot control operations
        let apiKey = effectiveTradingAPIKey
        let apiSecret = effectiveTradingSecret
        
        request.setValue(apiKey, forHTTPHeaderField: "APIKEY")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("CryptoSage/1.0", forHTTPHeaderField: "User-Agent")
        
        let signature = computeSignature(
            secret: apiSecret,
            method: "POST",
            path: path,
            body: nil
        )
        request.setValue(signature, forHTTPHeaderField: "Signature")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ThreeCommasError.networkError(URLError(.badServerResponse))
            }
            
            guard (200..<300).contains(httpResponse.statusCode) else {
                if httpResponse.statusCode == 401 {
                    throw ThreeCommasError.unauthorized
                }
                if httpResponse.statusCode == 403 {
                    // 403 typically means the API key lacks required permissions
                    throw ThreeCommasError.insufficientPermissions
                }
                throw ThreeCommasError.serverError(statusCode: httpResponse.statusCode)
            }
            
            let decoder = JSONDecoder()
            return try decoder.decode(ThreeCommasBot.self, from: data)
        } catch let error as ThreeCommasError {
            throw error
        } catch let error as DecodingError {
            throw ThreeCommasError.decodingError(error)
        } catch {
            throw ThreeCommasError.networkError(error)
        }
    }
    
    /// Disable (stop) a trading bot
    /// - Parameter botId: The ID of the bot to disable
    /// - Returns: Updated ThreeCommasBot object
    /// - Note: Requires trading API key with bot control permissions
    /// - Important: Disabling bots is ALWAYS allowed even when live trading is off.
    ///   This is a safety feature - you should always be able to STOP a running bot.
    @discardableResult
    func disableBot(botId: Int) async throws -> ThreeCommasBot {
        // No live trading check here - stopping a bot is always allowed for safety
        guard isConfigured else {
            throw ThreeCommasError.notConfigured
        }
        
        let path = "/public/api/ver1/bots/\(botId)/disable"
        let url = ThreeCommasConfig.baseURL.appendingPathComponent("public/api/ver1/bots/\(botId)/disable")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        
        // Use trading credentials for bot control operations
        let apiKey = effectiveTradingAPIKey
        let apiSecret = effectiveTradingSecret
        
        request.setValue(apiKey, forHTTPHeaderField: "APIKEY")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("CryptoSage/1.0", forHTTPHeaderField: "User-Agent")
        
        let signature = computeSignature(
            secret: apiSecret,
            method: "POST",
            path: path,
            body: nil
        )
        request.setValue(signature, forHTTPHeaderField: "Signature")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ThreeCommasError.networkError(URLError(.badServerResponse))
            }
            
            guard (200..<300).contains(httpResponse.statusCode) else {
                if httpResponse.statusCode == 401 {
                    throw ThreeCommasError.unauthorized
                }
                if httpResponse.statusCode == 403 {
                    // 403 typically means the API key lacks required permissions
                    throw ThreeCommasError.insufficientPermissions
                }
                throw ThreeCommasError.serverError(statusCode: httpResponse.statusCode)
            }
            
            let decoder = JSONDecoder()
            return try decoder.decode(ThreeCommasBot.self, from: data)
        } catch let error as ThreeCommasError {
            throw error
        } catch let error as DecodingError {
            throw ThreeCommasError.decodingError(error)
        } catch {
            throw ThreeCommasError.networkError(error)
        }
    }

    /// Create/start a new trading bot
    func startBot(
        side: TradeSide,
        orderType: OrderType,
        quantity: Double,
        slippage: Double
    ) async throws {
        // SAFETY: Block live bot operations when trading is disabled at app config level
        guard AppConfig.liveTradingEnabled else {
            throw ThreeCommasError.tradingNotConfigured
        }
        
        let url = ThreeCommasConfig.baseURL
            .appendingPathComponent("public/api/ver1/bots/create_trading_bot")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(ThreeCommasConfig.apiKey, forHTTPHeaderField: "APIKEY")
        // TODO: add signature header if required

        let payload: [String: Any] = [
            "pair": "\(side.rawValue)_\(orderType.rawValue)",
            "account_id": ThreeCommasConfig.accountId,
            "quantity": quantity,
            "slippage": slippage
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        // Compute HMAC-SHA256 signature
        let bodyData = request.httpBody ?? Data()
        let secretKey = SymmetricKey(data: Data(ThreeCommasConfig.tradingSecret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: bodyData, using: secretKey)
        let signatureHex = signature.map { String(format: "%02x", $0) }.joined()
        request.addValue(signatureHex, forHTTPHeaderField: "Signature")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        // SECURITY: Use pinned session for trading operations (sends signed credentials)
        _ = try await session.data(for: request)
    }

    /// Cancel/stop an existing trading bot
    /// - Important: Stopping bots is ALWAYS allowed even when live trading is off.
    ///   This is a safety feature - you should always be able to STOP a running bot.
    func stopBot(botId: Int) async throws {
        // No live trading check here - stopping a bot is always allowed for safety
        let url = ThreeCommasConfig.baseURL
            .appendingPathComponent("public/api/ver1/bots/cancel_trading_bot")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(ThreeCommasConfig.apiKey, forHTTPHeaderField: "APIKEY")

        let payload = ["id": botId]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        // Compute HMAC-SHA256 signature
        let bodyData = request.httpBody ?? Data()
        let secretKey = SymmetricKey(data: Data(ThreeCommasConfig.tradingSecret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: bodyData, using: secretKey)
        let signatureHex = signature.map { String(format: "%02x", $0) }.joined()
        request.addValue(signatureHex, forHTTPHeaderField: "Signature")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        // SECURITY: Use pinned session for trading operations (sends signed credentials)
        _ = try await session.data(for: request)
    }

    // MARK: - Market Data Fetching

    /// Fetches current USD prices for the given coin symbols via 3Commas public market_data endpoint.
    /// Symbols are uppercased and assumed to trade against USDT (e.g. "BTC" → "BTC_USDT").
    func getPrices(for symbols: [String]) -> AnyPublisher<[String: Double], Error> {
        // Return empty if no symbols
        guard !symbols.isEmpty else {
            return Just([:]).setFailureType(to: Error.self).eraseToAnyPublisher()
        }

        // Build comma-separated USDT pairs (e.g. "BTC_USDT,ETH_USDT")
        let pairs = symbols
            .map { "\($0.uppercased())_USDT" }
            .joined(separator: ",")

        // Construct URL with query parameter
        var components = URLComponents(url: ThreeCommasConfig.baseURL
                                        .appendingPathComponent("public/api/ver1/market_data"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "pairs", value: pairs)
        ]
        guard let url = components.url else {
            return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
        }

        // Prepare request with API key
        var request = URLRequest(url: url)
        request.setValue(ThreeCommasConfig.readOnlyAPIKey, forHTTPHeaderField: "APIKEY")

        // Fetch and decode
        return URLSession.shared.dataTaskPublisher(for: request)
            .map(\.data)
            .decode(type: MarketDataResponse.self, decoder: JSONDecoder())
            .map { response in
                response.data.reduce(into: [String: Double]()) { dict, item in
                    dict[item.symbol] = item.price
                }
            }
            .eraseToAnyPublisher()
    }

    /// Represents a single symbol-price entry in the market_data response.
    private struct MarketDataItem: Codable {
        let symbol: String
        let price: Double
    }

    /// Top-level wrapper for market_data response.
    private struct MarketDataResponse: Codable {
        let data: [MarketDataItem]
    }
}
