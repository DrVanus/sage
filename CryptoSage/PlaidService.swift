//
//  PlaidService.swift
//  CryptoSage
//
//  Created by CryptoSage on 1/19/26.
//  Service for Plaid Link SDK integration to connect brokerage accounts.
//
//  SETUP INSTRUCTIONS:
//  1. Add Plaid Link SDK via SPM: https://github.com/plaid/plaid-link-ios
//  2. Sign up at https://plaid.com and get your API keys
//  3. Configure your keys in APIConfig.swift
//  4. Set up your backend for token exchange (Plaid requires server-side token handling)
//

import Foundation
import SwiftUI

// MARK: - Plaid Configuration

/// Configuration for Plaid API
struct PlaidConfiguration {
    /// Plaid environment (sandbox, development, production)
    enum Environment: String {
        case sandbox
        case development
        case production
        
        var baseURL: String {
            switch self {
            case .sandbox: return "https://sandbox.plaid.com"
            case .development: return "https://development.plaid.com"
            case .production: return "https://production.plaid.com"
            }
        }
    }
    
    let clientId: String
    let secret: String
    let environment: Environment
    
    /// Default configuration (loads from APIConfig or environment)
    static var `default`: PlaidConfiguration {
        // Try to load from APIConfig if available
        let clientId = ProcessInfo.processInfo.environment["PLAID_CLIENT_ID"] ?? ""
        let secret = ProcessInfo.processInfo.environment["PLAID_SECRET"] ?? ""
        let envString = ProcessInfo.processInfo.environment["PLAID_ENV"] ?? "sandbox"
        let environment = Environment(rawValue: envString) ?? .sandbox
        
        return PlaidConfiguration(clientId: clientId, secret: secret, environment: environment)
    }
    
    var isConfigured: Bool {
        !clientId.isEmpty && !secret.isEmpty
    }
}

// MARK: - Plaid Models

/// Represents a connected Plaid account
struct PlaidAccount: Identifiable, Codable {
    let id: String
    let institutionId: String
    let institutionName: String
    let accountId: String
    let accountName: String
    let accountType: String       // "investment", "brokerage", "depository"
    let accountSubtype: String?   // "401k", "ira", "brokerage", etc.
    let mask: String?             // Last 4 digits
    let accessToken: String       // Encrypted access token
    let connectedAt: Date
    var lastSyncedAt: Date?
    
    /// Display name for the account
    var displayName: String {
        if let mask = mask {
            return "\(accountName) (...\(mask))"
        }
        return accountName
    }
}

/// Represents an investment holding from Plaid
struct PlaidInvestmentHolding: Codable {
    let accountId: String
    let securityId: String
    let quantity: Double
    let institutionPrice: Double
    let institutionPriceAsOf: Date?
    let institutionValue: Double
    let costBasis: Double?
    let isoCurrencyCode: String?
}

/// Represents a security from Plaid
struct PlaidSecurity: Codable {
    let securityId: String
    let isin: String?
    let cusip: String?
    let sedol: String?
    let tickerSymbol: String?
    let name: String?
    let type: String?             // "equity", "etf", "mutual fund", etc.
    let closePrice: Double?
    let closePriceAsOf: Date?
    let isoCurrencyCode: String?
}

/// Combined holding with security info
struct PlaidPortfolioHolding {
    let holding: PlaidInvestmentHolding
    let security: PlaidSecurity
    
    var ticker: String {
        security.tickerSymbol ?? security.name ?? "UNKNOWN"
    }
    
    var name: String {
        security.name ?? ticker
    }
    
    var assetType: AssetType {
        switch security.type?.lowercased() {
        case "etf": return .etf
        case "equity", "stock": return .stock
        default: return .stock
        }
    }
    
    /// Convert to a Holding for the portfolio
    func toHolding(source: String) -> Holding {
        Holding(
            ticker: ticker,
            companyName: name,
            shares: holding.quantity,
            currentPrice: holding.institutionPrice,
            costBasis: holding.costBasis ?? holding.institutionPrice,
            assetType: assetType,
            stockExchange: nil,
            isin: security.isin,
            imageUrl: nil,
            isFavorite: false,
            dailyChange: 0,
            purchaseDate: Date(),
            source: source
        )
    }
}

// MARK: - Plaid Link Token Response

private struct LinkTokenResponse: Codable {
    let linkToken: String
    let expiration: String
    let requestId: String
    
    enum CodingKeys: String, CodingKey {
        case linkToken = "link_token"
        case expiration
        case requestId = "request_id"
    }
}

// MARK: - Plaid Service Errors

enum PlaidServiceError: LocalizedError {
    case notConfigured
    case linkTokenFailed(String)
    case tokenExchangeFailed(String)
    case accountsFetchFailed(String)
    case holdingsFetchFailed(String)
    case networkError(Error)
    case invalidResponse
    case sdkNotInstalled
    
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Plaid is not configured. Please add your API keys."
        case .linkTokenFailed(let message):
            return "Failed to create link token: \(message)"
        case .tokenExchangeFailed(let message):
            return "Failed to exchange token: \(message)"
        case .accountsFetchFailed(let message):
            return "Failed to fetch accounts: \(message)"
        case .holdingsFetchFailed(let message):
            return "Failed to fetch holdings: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from Plaid"
        case .sdkNotInstalled:
            return "Plaid Link SDK is not installed. Please add it via Swift Package Manager."
        }
    }
}

// MARK: - Plaid Service

/// Service for managing Plaid brokerage connections
actor PlaidService {
    static let shared = PlaidService()
    
    private let configuration: PlaidConfiguration
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    
    // Persistence
    private let accountsFileURL: URL
    
    init(configuration: PlaidConfiguration = .default) {
        self.configuration = configuration
        
        // SECURITY: Ephemeral session prevents disk caching of bank account details,
        // balances, and transaction history from Plaid API responses.
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        self.session = URLSession(configuration: config)
        
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        
        // Setup persistence
        // SAFETY FIX: Use safe directory accessor instead of force unwrap
        let docs = FileManager.documentsDirectory
        self.accountsFileURL = docs.appendingPathComponent("plaid_accounts.json")
    }
    
    // MARK: - Configuration Check
    
    /// Check if Plaid is configured with valid credentials
    var isConfigured: Bool {
        configuration.isConfigured
    }
    
    /// Get setup instructions if not configured
    var setupInstructions: String {
        """
        To enable brokerage connections:
        
        1. Sign up at https://plaid.com
        2. Get your Client ID and Secret from the Plaid Dashboard
        3. Add Plaid Link iOS SDK to your project:
           - File > Add Package Dependencies
           - URL: https://github.com/plaid/plaid-link-ios
        4. Set environment variables or update APIConfig:
           - PLAID_CLIENT_ID
           - PLAID_SECRET
           - PLAID_ENV (sandbox/development/production)
        """
    }
    
    // MARK: - Link Token Creation
    
    /// Creates a link token for initializing Plaid Link
    /// Note: In production, this should be done server-side for security
    func createLinkToken(userId: String) async throws -> String {
        guard isConfigured else {
            throw PlaidServiceError.notConfigured
        }
        
        let url = URL(string: "\(configuration.environment.baseURL)/link/token/create")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "client_id": configuration.clientId,
            "secret": configuration.secret,
            "user": ["client_user_id": userId],
            "client_name": "CryptoSage",
            "products": ["investments"],
            "country_codes": ["US"],
            "language": "en",
            "redirect_uri": "cryptosage://plaid-link"  // Deep link for OAuth
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let http = response as? HTTPURLResponse else {
                throw PlaidServiceError.invalidResponse
            }
            
            if http.statusCode != 200 {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw PlaidServiceError.linkTokenFailed(errorMessage)
            }
            
            let tokenResponse = try decoder.decode(LinkTokenResponse.self, from: data)
            return tokenResponse.linkToken
            
        } catch let error as PlaidServiceError {
            throw error
        } catch {
            throw PlaidServiceError.networkError(error)
        }
    }
    
    // MARK: - Token Exchange
    
    /// Exchanges a public token for an access token after Plaid Link success
    /// Note: In production, this should be done server-side for security
    func exchangePublicToken(_ publicToken: String, institutionId: String, institutionName: String) async throws -> PlaidAccount {
        guard isConfigured else {
            throw PlaidServiceError.notConfigured
        }
        
        let url = URL(string: "\(configuration.environment.baseURL)/item/public_token/exchange")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "client_id": configuration.clientId,
            "secret": configuration.secret,
            "public_token": publicToken
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let http = response as? HTTPURLResponse else {
                throw PlaidServiceError.invalidResponse
            }
            
            if http.statusCode != 200 {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw PlaidServiceError.tokenExchangeFailed(errorMessage)
            }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let accessToken = json["access_token"] as? String,
                  let itemId = json["item_id"] as? String else {
                throw PlaidServiceError.invalidResponse
            }
            
            // Create account record
            let account = PlaidAccount(
                id: itemId,
                institutionId: institutionId,
                institutionName: institutionName,
                accountId: itemId,
                accountName: institutionName,
                accountType: "investment",
                accountSubtype: nil,
                mask: nil,
                accessToken: accessToken,  // In production, encrypt this
                connectedAt: Date(),
                lastSyncedAt: nil
            )
            
            return account
            
        } catch let error as PlaidServiceError {
            throw error
        } catch {
            throw PlaidServiceError.networkError(error)
        }
    }
    
    // MARK: - Fetch Holdings
    
    /// Fetches investment holdings for a connected account
    func fetchHoldings(for account: PlaidAccount) async throws -> [PlaidPortfolioHolding] {
        guard isConfigured else {
            throw PlaidServiceError.notConfigured
        }
        
        let url = URL(string: "\(configuration.environment.baseURL)/investments/holdings/get")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "client_id": configuration.clientId,
            "secret": configuration.secret,
            "access_token": account.accessToken
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let http = response as? HTTPURLResponse else {
                throw PlaidServiceError.invalidResponse
            }
            
            if http.statusCode != 200 {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw PlaidServiceError.holdingsFetchFailed(errorMessage)
            }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw PlaidServiceError.invalidResponse
            }
            
            // Parse holdings
            var holdingsMap: [String: PlaidInvestmentHolding] = [:]
            if let holdingsArray = json["holdings"] as? [[String: Any]] {
                for holdingData in holdingsArray {
                    if let holding = parseHolding(holdingData) {
                        holdingsMap[holding.securityId] = holding
                    }
                }
            }
            
            // Parse securities
            var securitiesMap: [String: PlaidSecurity] = [:]
            if let securitiesArray = json["securities"] as? [[String: Any]] {
                for securityData in securitiesArray {
                    if let security = parseSecurity(securityData) {
                        securitiesMap[security.securityId] = security
                    }
                }
            }
            
            // Combine holdings with securities
            var portfolioHoldings: [PlaidPortfolioHolding] = []
            for (securityId, holding) in holdingsMap {
                if let security = securitiesMap[securityId] {
                    portfolioHoldings.append(PlaidPortfolioHolding(holding: holding, security: security))
                }
            }
            
            return portfolioHoldings
            
        } catch let error as PlaidServiceError {
            throw error
        } catch {
            throw PlaidServiceError.networkError(error)
        }
    }
    
    // MARK: - Account Persistence
    
    /// Saves a connected account
    func saveAccount(_ account: PlaidAccount) async throws {
        var accounts = try await loadAccounts()
        
        // Update or add
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        
        let data = try encoder.encode(accounts)
        // SECURITY: .completeFileProtection ensures bank account data is encrypted
        // by iOS and inaccessible when the device is locked (AFU protection).
        try data.write(to: accountsFileURL, options: [.atomic, .completeFileProtection])
    }
    
    /// Loads all connected accounts
    func loadAccounts() async throws -> [PlaidAccount] {
        guard FileManager.default.fileExists(atPath: accountsFileURL.path) else {
            return []
        }
        
        let data = try Data(contentsOf: accountsFileURL)
        return try decoder.decode([PlaidAccount].self, from: data)
    }
    
    /// Removes a connected account
    func removeAccount(_ account: PlaidAccount) async throws {
        var accounts = try await loadAccounts()
        accounts.removeAll { $0.id == account.id }
        
        let data = try encoder.encode(accounts)
        // SECURITY: .completeFileProtection ensures bank account data is encrypted
        // by iOS and inaccessible when the device is locked (AFU protection).
        try data.write(to: accountsFileURL, options: [.atomic, .completeFileProtection])
    }
    
    // MARK: - Helpers
    
    private func parseHolding(_ data: [String: Any]) -> PlaidInvestmentHolding? {
        guard let accountId = data["account_id"] as? String,
              let securityId = data["security_id"] as? String,
              let quantity = data["quantity"] as? Double,
              let price = data["institution_price"] as? Double,
              let value = data["institution_value"] as? Double else {
            return nil
        }
        
        return PlaidInvestmentHolding(
            accountId: accountId,
            securityId: securityId,
            quantity: quantity,
            institutionPrice: price,
            institutionPriceAsOf: parseDate(data["institution_price_as_of"]),
            institutionValue: value,
            costBasis: data["cost_basis"] as? Double,
            isoCurrencyCode: data["iso_currency_code"] as? String
        )
    }
    
    private func parseSecurity(_ data: [String: Any]) -> PlaidSecurity? {
        guard let securityId = data["security_id"] as? String else {
            return nil
        }
        
        return PlaidSecurity(
            securityId: securityId,
            isin: data["isin"] as? String,
            cusip: data["cusip"] as? String,
            sedol: data["sedol"] as? String,
            tickerSymbol: data["ticker_symbol"] as? String,
            name: data["name"] as? String,
            type: data["type"] as? String,
            closePrice: data["close_price"] as? Double,
            closePriceAsOf: parseDate(data["close_price_as_of"]),
            isoCurrencyCode: data["iso_currency_code"] as? String
        )
    }
    
    private func parseDate(_ value: Any?) -> Date? {
        guard let dateString = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: dateString)
    }
}

// MARK: - Supported Brokerages

/// List of brokerages that work well with Plaid
struct SupportedBrokerage: Identifiable {
    let id: String
    let name: String
    let logo: String?  // SF Symbol or asset name
    let plaidInstitutionId: String
    let notes: String?
    
    static let popular: [SupportedBrokerage] = [
        SupportedBrokerage(id: "fidelity", name: "Fidelity", logo: "building.columns.fill", plaidInstitutionId: "ins_7", notes: "Via Fidelity Access"),
        SupportedBrokerage(id: "schwab", name: "Charles Schwab", logo: "building.columns.fill", plaidInstitutionId: "ins_10", notes: nil),
        SupportedBrokerage(id: "vanguard", name: "Vanguard", logo: "chart.line.uptrend.xyaxis", plaidInstitutionId: "ins_11", notes: nil),
        SupportedBrokerage(id: "robinhood", name: "Robinhood", logo: "leaf.fill", plaidInstitutionId: "ins_54", notes: "Connection may vary"),
        SupportedBrokerage(id: "td_ameritrade", name: "TD Ameritrade", logo: "chart.bar.fill", plaidInstitutionId: "ins_17", notes: "Now part of Schwab"),
        SupportedBrokerage(id: "etrade", name: "E*TRADE", logo: "star.fill", plaidInstitutionId: "ins_4", notes: nil),
        SupportedBrokerage(id: "merrill", name: "Merrill Edge", logo: "m.circle.fill", plaidInstitutionId: "ins_1", notes: nil),
        SupportedBrokerage(id: "interactive", name: "Interactive Brokers", logo: "globe", plaidInstitutionId: "ins_16", notes: nil),
        SupportedBrokerage(id: "webull", name: "Webull", logo: "w.circle.fill", plaidInstitutionId: "ins_56", notes: "Limited support"),
        SupportedBrokerage(id: "sofi", name: "SoFi Invest", logo: "s.circle.fill", plaidInstitutionId: "ins_57", notes: nil)
    ]
}

// MARK: - Plaid Link Handler Protocol

/// Protocol for handling Plaid Link callbacks
/// Implement this in your view controller or coordinator
protocol PlaidLinkHandler: AnyObject {
    func plaidLinkDidSucceed(publicToken: String, metadata: [String: Any])
    func plaidLinkDidFail(error: Error)
    func plaidLinkDidExit(metadata: [String: Any]?)
}
