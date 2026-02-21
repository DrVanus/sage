//
//  CoinbaseAdvancedTradeService.swift
//  CryptoSage
//
//  THIRD-PARTY CLIENT - Direct Coinbase Advanced Trade API Integration
//  ====================================================================
//  This service connects DIRECTLY to Coinbase's Advanced Trade API.
//  
//  Security Model:
//  - API keys stored in Apple's Secure Keychain
//  - All requests signed locally using HMAC-SHA256
//  - Direct device → Coinbase connection (no middleman)
//  
//  Coinbase API Capabilities:
//  - Spot Trading: Market, Limit, Stop orders
//  - Perpetual Futures (INTX): BTC-PERP, ETH-PERP with up to 50x leverage
//  - Account Management: Balances, portfolios
//  - Market Data: Prices, order books, candles
//  
//  Perpetual Futures (Coinbase INTX):
//  - Available to eligible US users via Coinbase International Exchange
//  - Symbols: BTC-PERP-INTX, ETH-PERP-INTX
//  - Leverage: Up to 50x (default 5x)
//  - Collateral: USDC, BTC, ETH
//  - Settlement: USDC every 5 minutes
//
//  API Documentation: https://docs.cdp.coinbase.com/advanced-trade/docs
//

import Foundation
import CommonCrypto

// MARK: - Coinbase Advanced Trade Models

/// Coinbase account with balance information
public struct CoinbaseAccount: Codable, Identifiable {
    public let uuid: String
    public let name: String
    public let currency: String
    public let availableBalance: CoinbaseBalance
    public let hold: CoinbaseBalance?
    public let type: String
    public let active: Bool
    
    public var id: String { uuid }
    
    public var totalBalance: Double {
        let available = Double(availableBalance.value) ?? 0
        let held = Double(hold?.value ?? "0") ?? 0
        return available + held
    }
    
    enum CodingKeys: String, CodingKey {
        case uuid
        case name
        case currency
        case availableBalance = "available_balance"
        case hold
        case type
        case active
    }
}

public struct CoinbaseBalance: Codable {
    public let value: String
    public let currency: String
}

/// Coinbase order response
public struct CoinbaseOrderResponse: Codable {
    public let success: Bool
    public let successResponse: CoinbaseSuccessOrder?
    public let errorResponse: CoinbaseErrorOrder?
    public let orderConfiguration: CoinbaseOrderConfig?
    
    enum CodingKeys: String, CodingKey {
        case success
        case successResponse = "success_response"
        case errorResponse = "error_response"
        case orderConfiguration = "order_configuration"
    }
}

public struct CoinbaseSuccessOrder: Codable {
    public let orderId: String
    public let productId: String
    public let side: String
    public let clientOrderId: String
    
    enum CodingKeys: String, CodingKey {
        case orderId = "order_id"
        case productId = "product_id"
        case side
        case clientOrderId = "client_order_id"
    }
}

public struct CoinbaseErrorOrder: Codable {
    public let error: String
    public let message: String
    public let errorDetails: String?
    public let previewFailureReason: String?
    
    enum CodingKeys: String, CodingKey {
        case error
        case message
        case errorDetails = "error_details"
        case previewFailureReason = "preview_failure_reason"
    }
}

public struct CoinbaseOrderConfig: Codable {
    public let marketMarketIoc: CoinbaseMarketConfig?
    public let limitLimitGtc: CoinbaseLimitConfig?
    
    enum CodingKeys: String, CodingKey {
        case marketMarketIoc = "market_market_ioc"
        case limitLimitGtc = "limit_limit_gtc"
    }
}

public struct CoinbaseMarketConfig: Codable {
    public let quoteSize: String?
    public let baseSize: String?
    
    enum CodingKeys: String, CodingKey {
        case quoteSize = "quote_size"
        case baseSize = "base_size"
    }
}

public struct CoinbaseLimitConfig: Codable {
    public let baseSize: String
    public let limitPrice: String
    public let postOnly: Bool
    
    enum CodingKeys: String, CodingKey {
        case baseSize = "base_size"
        case limitPrice = "limit_price"
        case postOnly = "post_only"
    }
}

/// Coinbase product (trading pair)
public struct CoinbaseProduct: Codable, Identifiable {
    public let productId: String
    public let price: String?
    public let pricePercentageChange24h: String?
    public let volume24h: String?
    public let baseCurrencyId: String
    public let quoteCurrencyId: String
    public let baseMinSize: String
    public let baseMaxSize: String
    public let quoteMinSize: String
    public let quoteMaxSize: String
    public let status: String
    
    public var id: String { productId }
    
    public var currentPrice: Double? {
        price.flatMap { Double($0) }
    }
    
    public var change24h: Double? {
        pricePercentageChange24h.flatMap { Double($0) }
    }
    
    enum CodingKeys: String, CodingKey {
        case productId = "product_id"
        case price
        case pricePercentageChange24h = "price_percentage_change_24h"
        case volume24h = "volume_24h"
        case baseCurrencyId = "base_currency_id"
        case quoteCurrencyId = "quote_currency_id"
        case baseMinSize = "base_min_size"
        case baseMaxSize = "base_max_size"
        case quoteMinSize = "quote_min_size"
        case quoteMaxSize = "quote_max_size"
        case status
    }
}

// MARK: - Coinbase Advanced Trade Service

/// Direct API service for Coinbase Advanced Trade
/// All connections go directly to Coinbase - no backend involved
public actor CoinbaseAdvancedTradeService {
    public static let shared = CoinbaseAdvancedTradeService()
    private init() {}
    
    private let baseURL = URL(string: "https://api.coinbase.com")!
    
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()
    
    // MARK: - Account Operations
    
    /// Fetch all accounts with balances
    public func fetchAccounts() async throws -> [CoinbaseAccount] {
        let response: AccountsResponse = try await signedRequest(
            method: "GET",
            path: "/api/v3/brokerage/accounts",
            body: nil
        )
        return response.accounts
    }
    
    /// Get account balance for a specific currency
    public func getBalance(for currency: String) async throws -> Double {
        let accounts = try await fetchAccounts()
        if let account = accounts.first(where: { $0.currency.uppercased() == currency.uppercased() }) {
            return account.totalBalance
        }
        return 0
    }
    
    // MARK: - Order Operations
    
    /// Place a market order
    public func placeMarketOrder(
        productId: String,
        side: String,  // "BUY" or "SELL"
        size: Double,
        isSizeInQuote: Bool = false  // true = quote currency size (e.g., $100 of BTC), false = base currency size (e.g., 0.01 BTC)
    ) async throws -> CoinbaseOrderResponse {
        // SAFETY: Block live trading when disabled at app config level
        guard AppConfig.liveTradingEnabled else {
            throw CoinbaseError.apiError(message: AppConfig.liveTradingDisabledMessage)
        }
        guard TradingRiskAcknowledgmentManager.shared.canTrade else {
            throw CoinbaseError.orderRejected(reason: "Trading risk acknowledgment is required before live orders.")
        }
        if !isSizeInQuote {
            try await validateProductForOrder(productId: productId, baseSize: size)
        }
        
        let clientOrderId = UUID().uuidString
        
        var orderConfig: [String: Any] = [:]
        if isSizeInQuote {
            orderConfig["market_market_ioc"] = ["quote_size": formatSize(size)]
        } else {
            orderConfig["market_market_ioc"] = ["base_size": formatSize(size)]
        }
        
        let body: [String: Any] = [
            "client_order_id": clientOrderId,
            "product_id": productId.uppercased(),
            "side": side.uppercased(),
            "order_configuration": orderConfig
        ]
        
        return try await signedRequest(
            method: "POST",
            path: "/api/v3/brokerage/orders",
            body: body
        )
    }
    
    /// Place a limit order
    public func placeLimitOrder(
        productId: String,
        side: String,
        size: Double,
        price: Double,
        postOnly: Bool = false
    ) async throws -> CoinbaseOrderResponse {
        // SAFETY: Block live trading when disabled at app config level
        guard AppConfig.liveTradingEnabled else {
            throw CoinbaseError.apiError(message: AppConfig.liveTradingDisabledMessage)
        }
        guard TradingRiskAcknowledgmentManager.shared.canTrade else {
            throw CoinbaseError.orderRejected(reason: "Trading risk acknowledgment is required before live orders.")
        }
        try await validateProductForOrder(productId: productId, baseSize: size)
        
        let clientOrderId = UUID().uuidString
        
        let orderConfig: [String: Any] = [
            "limit_limit_gtc": [
                "base_size": formatSize(size),
                "limit_price": formatPrice(price),
                "post_only": postOnly
            ]
        ]
        
        let body: [String: Any] = [
            "client_order_id": clientOrderId,
            "product_id": productId.uppercased(),
            "side": side.uppercased(),
            "order_configuration": orderConfig
        ]
        
        return try await signedRequest(
            method: "POST",
            path: "/api/v3/brokerage/orders",
            body: body
        )
    }
    
    /// Cancel an order
    /// - Important: Canceling orders is ALWAYS allowed even when live trading is off.
    ///   This is a safety feature - you should always be able to cancel pending orders.
    public func cancelOrder(orderId: String) async throws -> Bool {
        // No live trading check here - canceling orders is always allowed for safety
        let body: [String: Any] = [
            "order_ids": [orderId]
        ]
        
        let _: CancelResponse = try await signedRequest(
            method: "POST",
            path: "/api/v3/brokerage/orders/batch_cancel",
            body: body
        )
        return true
    }
    
    /// Get open orders
    public func getOpenOrders(productId: String? = nil) async throws -> [CoinbaseOrder] {
        var path = "/api/v3/brokerage/orders/historical/batch?order_status=OPEN"
        if let productId = productId {
            path += "&product_id=\(productId)"
        }
        
        let response: OrdersResponse = try await signedRequest(
            method: "GET",
            path: path,
            body: nil
        )
        return response.orders
    }
    
    // MARK: - Market Data (Public - No Auth Required)
    
    /// Get all available products
    public func getProducts() async throws -> [CoinbaseProduct] {
        let url = baseURL.appendingPathComponent("/api/v3/brokerage/market/products")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CoinbaseError.apiError(message: "Failed to fetch products")
        }
        
        let decoded = try JSONDecoder().decode(ProductsResponse.self, from: data)
        return decoded.products
    }
    
    /// Get product details
    public func getProduct(productId: String) async throws -> CoinbaseProduct {
        let url = baseURL.appendingPathComponent("/api/v3/brokerage/market/products/\(productId)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CoinbaseError.apiError(message: "Failed to fetch product")
        }
        
        return try JSONDecoder().decode(CoinbaseProduct.self, from: data)
    }
    
    /// Test connection with credentials
    public func testConnection() async throws -> Bool {
        do {
            let _ = try await fetchAccounts()
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - Perpetual Futures (INTX) Operations
    
    /// Get perpetuals portfolio summary
    public func getPerpetualPortfolio() async throws -> CoinbasePerpPortfolio {
        return try await signedRequest(
            method: "GET",
            path: "/api/v3/brokerage/intx/portfolio",
            body: nil
        )
    }
    
    /// Get perpetuals balances (collateral)
    public func getPerpetualBalances() async throws -> CoinbasePerpBalances {
        return try await signedRequest(
            method: "GET",
            path: "/api/v3/brokerage/intx/balances",
            body: nil
        )
    }
    
    /// Get all open perpetual positions
    public func getPerpetualPositions(portfolioUuid: String) async throws -> [CoinbasePerpPosition] {
        let response: PerpPositionsResponse = try await signedRequest(
            method: "GET",
            path: "/api/v3/brokerage/intx/positions/\(portfolioUuid)",
            body: nil
        )
        return response.positions
    }
    
    /// Get specific perpetual position
    public func getPerpetualPosition(portfolioUuid: String, symbol: String) async throws -> CoinbasePerpPosition {
        return try await signedRequest(
            method: "GET",
            path: "/api/v3/brokerage/intx/positions/\(portfolioUuid)/\(symbol)",
            body: nil
        )
    }
    
    /// Place a perpetual futures market order
    public func placePerpMarketOrder(
        productId: String,  // e.g., "BTC-PERP-INTX"
        side: String,       // "BUY" or "SELL"
        size: Double,
        leverage: Double? = nil
    ) async throws -> CoinbaseOrderResponse {
        // SAFETY: Block live trading when disabled at app config level
        guard AppConfig.liveTradingEnabled else {
            throw CoinbaseError.apiError(message: AppConfig.liveTradingDisabledMessage)
        }
        guard TradingRiskAcknowledgmentManager.shared.canTrade else {
            throw CoinbaseError.orderRejected(reason: "Trading risk acknowledgment is required before live orders.")
        }
        _ = try await getPerpetualPortfolio()
        try await validateProductForOrder(productId: productId, baseSize: size)
        
        let clientOrderId = UUID().uuidString
        
        let orderConfig: [String: Any] = [
            "market_market_ioc": ["base_size": formatSize(size)]
        ]
        
        var body: [String: Any] = [
            "client_order_id": clientOrderId,
            "product_id": productId.uppercased(),
            "side": side.uppercased(),
            "order_configuration": orderConfig
        ]
        
        if let leverage = leverage {
            body["leverage"] = String(format: "%.1f", leverage)
        }
        
        return try await signedRequest(
            method: "POST",
            path: "/api/v3/brokerage/orders",
            body: body
        )
    }
    
    /// Place a perpetual futures limit order
    public func placePerpLimitOrder(
        productId: String,
        side: String,
        size: Double,
        price: Double,
        leverage: Double? = nil,
        postOnly: Bool = false
    ) async throws -> CoinbaseOrderResponse {
        // SAFETY: Block live trading when disabled at app config level
        guard AppConfig.liveTradingEnabled else {
            throw CoinbaseError.apiError(message: AppConfig.liveTradingDisabledMessage)
        }
        guard TradingRiskAcknowledgmentManager.shared.canTrade else {
            throw CoinbaseError.orderRejected(reason: "Trading risk acknowledgment is required before live orders.")
        }
        _ = try await getPerpetualPortfolio()
        try await validateProductForOrder(productId: productId, baseSize: size)
        
        let clientOrderId = UUID().uuidString
        
        let orderConfig: [String: Any] = [
            "limit_limit_gtc": [
                "base_size": formatSize(size),
                "limit_price": formatPrice(price),
                "post_only": postOnly
            ]
        ]
        
        var body: [String: Any] = [
            "client_order_id": clientOrderId,
            "product_id": productId.uppercased(),
            "side": side.uppercased(),
            "order_configuration": orderConfig
        ]
        
        if let leverage = leverage {
            body["leverage"] = String(format: "%.1f", leverage)
        }
        
        return try await signedRequest(
            method: "POST",
            path: "/api/v3/brokerage/orders",
            body: body
        )
    }
    
    /// Close a perpetual position
    public func closePerpPosition(
        productId: String,
        size: Double? = nil  // nil = close entire position
    ) async throws -> CoinbaseOrderResponse {
        // SAFETY: Block live trading when disabled at app config level
        guard AppConfig.liveTradingEnabled else {
            throw CoinbaseError.apiError(message: AppConfig.liveTradingDisabledMessage)
        }
        
        // To close, we need to place an opposite order
        // First get the current position to determine size and side
        let portfolio = try await getPerpetualPortfolio()
        let positions = try await getPerpetualPositions(portfolioUuid: portfolio.portfolioUuid)
        
        guard let position = positions.first(where: { $0.productId == productId }) else {
            throw CoinbaseError.orderRejected(reason: "No open position for \(productId)")
        }
        
        let closeSize = size ?? abs(position.netSize)
        let closeSide = position.netSize > 0 ? "SELL" : "BUY"
        
        return try await placePerpMarketOrder(
            productId: productId,
            side: closeSide,
            size: closeSize
        )
    }
    
    /// Allocate funds to perpetuals portfolio
    public func allocateToPerpetuals(
        portfolioUuid: String,
        symbol: String,  // e.g., "USDC"
        amount: Double
    ) async throws -> Bool {
        let body: [String: Any] = [
            "portfolio_uuid": portfolioUuid,
            "symbol": symbol,
            "amount": formatSize(amount)
        ]
        
        let _: AllocateResponse = try await signedRequest(
            method: "POST",
            path: "/api/v3/brokerage/intx/allocate",
            body: body
        )
        return true
    }
    
    /// Get available perpetual products
    public func getPerpetualProducts() async throws -> [CoinbaseProduct] {
        let allProducts = try await getProducts()
        return allProducts.filter { product in
            product.productId.contains("PERP") || product.productId.contains("INTX")
        }
    }
    
    // MARK: - Private Helpers
    
    private func validateProductForOrder(productId: String, baseSize: Double) async throws {
        let product = try await getProduct(productId: productId.uppercased())
        guard product.status.lowercased() == "online" else {
            throw CoinbaseError.orderRejected(reason: "\(productId) is not currently tradable (\(product.status))")
        }
        
        if let minSize = Double(product.baseMinSize), baseSize < minSize {
            throw CoinbaseError.orderRejected(reason: "Order size below minimum \(product.baseMinSize) \(product.baseCurrencyId)")
        }
        
        if let maxSize = Double(product.baseMaxSize), baseSize > maxSize {
            throw CoinbaseError.orderRejected(reason: "Order size exceeds maximum \(product.baseMaxSize) \(product.baseCurrencyId)")
        }
    }
    
    private func signedRequest<T: Decodable>(
        method: String,
        path: String,
        body: [String: Any]?
    ) async throws -> T {
        guard let credentials = TradingCredentialsManager.shared.loadCredentials(for: .coinbase) else {
            throw CoinbaseError.noCredentials
        }
        
        let timestamp = String(Int(Date().timeIntervalSince1970))
        
        // Create request body
        var bodyData: Data? = nil
        var bodyString = ""
        if let body = body {
            bodyData = try JSONSerialization.data(withJSONObject: body)
            bodyString = String(data: bodyData!, encoding: .utf8) ?? ""
        }
        
        // Create signature
        // CB-ACCESS-SIGN = base64(hmac-sha256(timestamp + method + requestPath + body))
        let message = timestamp + method + path + bodyString
        let signature = hmacSHA256Base64(message: message, key: credentials.apiSecret)
        
        // Build request
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        
        // Handle query parameters in path
        if let queryStart = path.firstIndex(of: "?") {
            let basePath = String(path[..<queryStart])
            let queryString = String(path[path.index(after: queryStart)...])
            components = URLComponents(url: baseURL.appendingPathComponent(basePath), resolvingAgainstBaseURL: false)!
            components.query = queryString
        }
        
        guard let url = components.url else {
            throw CoinbaseError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = bodyData
        
        // Set headers
        request.setValue(credentials.apiKey, forHTTPHeaderField: "CB-ACCESS-KEY")
        request.setValue(signature, forHTTPHeaderField: "CB-ACCESS-SIGN")
        request.setValue(timestamp, forHTTPHeaderField: "CB-ACCESS-TIMESTAMP")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CoinbaseError.invalidResponse
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            // Try to parse error message
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = json["message"] as? String {
                throw CoinbaseError.apiError(message: message)
            }
            throw CoinbaseError.apiError(message: "Request failed with status \(httpResponse.statusCode)")
        }
        
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    private func hmacSHA256Base64(message: String, key: String) -> String {
        guard let keyData = key.data(using: .utf8),
              let messageData = message.data(using: .utf8) else {
            return ""
        }
        
        var macData = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        macData.withUnsafeMutableBytes { macPtr in
            keyData.withUnsafeBytes { keyPtr in
                messageData.withUnsafeBytes { messagePtr in
                    CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256),
                           keyPtr.baseAddress, keyData.count,
                           messagePtr.baseAddress, messageData.count,
                           macPtr.baseAddress)
                }
            }
        }
        
        return macData.base64EncodedString()
    }
    
    private func formatSize(_ size: Double) -> String {
        if size < 0.00001 {
            return String(format: "%.10f", size)
        } else if size < 0.001 {
            return String(format: "%.8f", size)
        } else if size < 1 {
            return String(format: "%.6f", size)
        } else {
            return String(format: "%.4f", size)
        }
    }
    
    private func formatPrice(_ price: Double) -> String {
        if price < 0.01 {
            return String(format: "%.8f", price)
        } else if price < 1 {
            return String(format: "%.6f", price)
        } else if price < 100 {
            return String(format: "%.4f", price)
        } else {
            return String(format: "%.2f", price)
        }
    }
}

// MARK: - Response Types

private struct AccountsResponse: Decodable {
    let accounts: [CoinbaseAccount]
}

private struct ProductsResponse: Decodable {
    let products: [CoinbaseProduct]
}

private struct OrdersResponse: Decodable {
    let orders: [CoinbaseOrder]
}

private struct CancelResponse: Decodable {
    let results: [CancelResult]
}

private struct CancelResult: Decodable {
    let success: Bool
    let failureReason: String?
    let orderId: String
    
    enum CodingKeys: String, CodingKey {
        case success
        case failureReason = "failure_reason"
        case orderId = "order_id"
    }
}

public struct CoinbaseOrder: Codable, Identifiable {
    public let orderId: String
    public let productId: String
    public let side: String
    public let orderType: String
    public let status: String
    public let filledSize: String?
    public let filledValue: String?
    public let averageFilledPrice: String?
    public let createdTime: String
    
    public var id: String { orderId }
    
    enum CodingKeys: String, CodingKey {
        case orderId = "order_id"
        case productId = "product_id"
        case side
        case orderType = "order_type"
        case status
        case filledSize = "filled_size"
        case filledValue = "filled_value"
        case averageFilledPrice = "average_filled_price"
        case createdTime = "created_time"
    }
}

// MARK: - Perpetual Futures Models

/// Coinbase perpetuals portfolio summary
public struct CoinbasePerpPortfolio: Codable {
    public let portfolioUuid: String
    public let collateral: String               // Total collateral value in USDC
    public let positionNotional: String         // Total position notional
    public let openPositionNotional: String     // Open position notional
    public let pendingFees: String
    public let borrow: String
    public let accruedInterest: String
    public let rollingDebt: String
    public let portfolioInitialMargin: String
    public let portfolioMaintenanceMargin: String
    public let liquidationPercentage: String?
    public let liquidationBuffer: String
    public let marginType: String?              // "CROSS" or "ISOLATED"
    public let marginFlags: String?
    public let liquidating: Bool?
    public let unrealizedPnl: String?
    public let buyingPower: String?
    
    public var collateralValue: Double { Double(collateral) ?? 0 }
    public var unrealizedPnlValue: Double { Double(unrealizedPnl ?? "0") ?? 0 }
    public var buyingPowerValue: Double { Double(buyingPower ?? "0") ?? 0 }
    
    enum CodingKeys: String, CodingKey {
        case portfolioUuid = "portfolio_uuid"
        case collateral
        case positionNotional = "position_notional"
        case openPositionNotional = "open_position_notional"
        case pendingFees = "pending_fees"
        case borrow
        case accruedInterest = "accrued_interest"
        case rollingDebt = "rolling_debt"
        case portfolioInitialMargin = "portfolio_initial_margin"
        case portfolioMaintenanceMargin = "portfolio_maintenance_margin"
        case liquidationPercentage = "liquidation_percentage"
        case liquidationBuffer = "liquidation_buffer"
        case marginType = "margin_type"
        case marginFlags = "margin_flags"
        case liquidating
        case unrealizedPnl = "unrealized_pnl"
        case buyingPower = "buying_power"
    }
}

/// Coinbase perpetuals balances
public struct CoinbasePerpBalances: Codable {
    public let portfolioBalances: [CoinbasePerpBalance]
    
    enum CodingKeys: String, CodingKey {
        case portfolioBalances = "portfolio_balances"
    }
}

public struct CoinbasePerpBalance: Codable, Identifiable {
    public let asset: String                    // e.g., "USDC", "BTC", "ETH"
    public let quantity: String                 // Total quantity
    public let hold: String                     // Held for orders
    public let transferHold: String             // Held for transfers
    public let collateralValue: String          // Value in USDC
    public let maxWithdrawAmount: String?
    
    public var id: String { asset }
    public var quantityValue: Double { Double(quantity) ?? 0 }
    public var holdValue: Double { Double(hold) ?? 0 }
    public var available: Double { quantityValue - holdValue }
    
    enum CodingKeys: String, CodingKey {
        case asset
        case quantity
        case hold
        case transferHold = "transfer_hold"
        case collateralValue = "collateral_value"
        case maxWithdrawAmount = "max_withdraw_amount"
    }
}

/// Coinbase perpetual position
public struct CoinbasePerpPosition: Codable, Identifiable {
    public let productId: String                // e.g., "BTC-PERP-INTX"
    public let productUuid: String
    public let portfolioUuid: String
    public let symbol: String
    public let vwap: String?                    // Volume-weighted average price
    public let netSize: Double                  // Positive = long, negative = short
    public let buyOrderSize: String
    public let sellOrderSize: String
    public let imContribution: String           // Initial margin contribution
    public let unrealizedPnl: String
    public let markPrice: String
    public let liquidationPrice: String?
    public let leverage: String?
    public let imNotional: String?              // Initial margin notional
    public let mmNotional: String?              // Maintenance margin notional
    public let positionSide: String?            // "LONG", "SHORT", or "UNKNOWN"
    public let aggregatedPnl: String?
    
    public var id: String { productId }
    public var isLong: Bool { netSize > 0 }
    public var isShort: Bool { netSize < 0 }
    public var unrealizedPnlValue: Double { Double(unrealizedPnl) ?? 0 }
    public var markPriceValue: Double { Double(markPrice) ?? 0 }
    public var liquidationPriceValue: Double? { liquidationPrice.flatMap { Double($0) } }
    public var leverageValue: Double { Double(leverage ?? "1") ?? 1 }
    
    enum CodingKeys: String, CodingKey {
        case productId = "product_id"
        case productUuid = "product_uuid"
        case portfolioUuid = "portfolio_uuid"
        case symbol
        case vwap
        case netSize = "net_size"
        case buyOrderSize = "buy_order_size"
        case sellOrderSize = "sell_order_size"
        case imContribution = "im_contribution"
        case unrealizedPnl = "unrealized_pnl"
        case markPrice = "mark_price"
        case liquidationPrice = "liquidation_price"
        case leverage
        case imNotional = "im_notional"
        case mmNotional = "mm_notional"
        case positionSide = "position_side"
        case aggregatedPnl = "aggregated_pnl"
    }
}

private struct PerpPositionsResponse: Decodable {
    let positions: [CoinbasePerpPosition]
}

private struct AllocateResponse: Decodable {
    let success: Bool?
}

// MARK: - Errors

public enum CoinbaseError: LocalizedError {
    case noCredentials
    case invalidResponse
    case invalidURL
    case parseError
    case apiError(message: String)
    case insufficientFunds
    case orderRejected(reason: String)
    
    public var errorDescription: String? {
        switch self {
        case .noCredentials:
            return "No Coinbase credentials found. Please add your API keys in Settings."
        case .invalidResponse:
            return "Invalid response from Coinbase"
        case .invalidURL:
            return "Invalid API URL"
        case .parseError:
            return "Failed to parse Coinbase response"
        case .apiError(let message):
            return "Coinbase API Error: \(message)"
        case .insufficientFunds:
            return "Insufficient funds for this order"
        case .orderRejected(let reason):
            return "Order rejected: \(reason)"
        }
    }
}
