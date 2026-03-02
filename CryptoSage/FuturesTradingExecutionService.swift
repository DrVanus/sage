//
//  FuturesTradingExecutionService.swift
//  CryptoSage
//
//  THIRD-PARTY CLIENT - Direct Exchange API Integration
//  =====================================================
//  This service connects DIRECTLY to exchange APIs from the user's device.
//  
//  Security Model:
//  - API keys are stored locally in Apple's Secure Keychain
//  - All requests go directly from device → exchange (no middleman)
//  - We NEVER store or transmit credentials through any backend server
//  - HMAC signatures are computed locally on-device
//  
//  Supported Exchanges:
//  - Binance Futures (USDT-M Perpetuals) - fapi.binance.com
//  - KuCoin Futures - futures.kucoin.com
//  - Bybit - api.bybit.com
//  
//  Note: Coinbase does NOT offer perpetual futures to US retail users.
//  Their "Coinbase International Exchange" requires institutional access.
//

import Foundation
import CommonCrypto

// MARK: - Futures Position Models

/// Represents an open futures position
public struct FuturesPosition: Codable, Identifiable, Equatable {
    public let id: String
    public let symbol: String
    public let positionSide: PositionSide      // LONG, SHORT, or BOTH
    public let positionAmount: Double          // Quantity (positive for long, negative for short in hedge mode)
    public let entryPrice: Double
    public let markPrice: Double
    public let unrealizedPnL: Double
    public let leverage: Int
    public let marginType: MarginMode          // ISOLATED or CROSS
    public let liquidationPrice: Double
    public let notionalValue: Double           // Position value in USDT
    public let isolatedMargin: Double?         // Only for isolated margin
    
    public var isLong: Bool { positionAmount > 0 || positionSide == .long }
    public var isShort: Bool { positionAmount < 0 || positionSide == .short }
    
    /// Percentage PnL based on entry price
    public var pnlPercent: Double {
        guard entryPrice > 0 else { return 0 }
        let pnlPerUnit = markPrice - entryPrice
        let direction: Double = isLong ? 1.0 : -1.0
        return (pnlPerUnit / entryPrice) * 100.0 * direction * Double(leverage)
    }
    
    public init(
        id: String,
        symbol: String,
        positionSide: PositionSide,
        positionAmount: Double,
        entryPrice: Double,
        markPrice: Double,
        unrealizedPnL: Double,
        leverage: Int,
        marginType: MarginMode,
        liquidationPrice: Double,
        notionalValue: Double,
        isolatedMargin: Double? = nil
    ) {
        self.id = id
        self.symbol = symbol
        self.positionSide = positionSide
        self.positionAmount = positionAmount
        self.entryPrice = entryPrice
        self.markPrice = markPrice
        self.unrealizedPnL = unrealizedPnL
        self.leverage = leverage
        self.marginType = marginType
        self.liquidationPrice = liquidationPrice
        self.notionalValue = notionalValue
        self.isolatedMargin = isolatedMargin
    }
}

/// Position side for futures trading
public enum PositionSide: String, Codable {
    case long = "LONG"
    case short = "SHORT"
    case both = "BOTH"      // Used in one-way mode
}

/// Margin mode for futures trading
public enum MarginMode: String, Codable {
    case isolated = "ISOLATED"
    case cross = "CROSS"
}

/// Futures account balance for a specific asset
public struct FuturesAssetBalance: Codable, Identifiable {
    public var id: String { asset }
    public let asset: String
    public let walletBalance: Double           // Total wallet balance
    public let availableBalance: Double        // Available for new positions
    public let crossUnPnL: Double              // Unrealized PnL in cross mode
    public let marginBalance: Double           // Margin balance
    
    public init(asset: String, walletBalance: Double, availableBalance: Double, crossUnPnL: Double, marginBalance: Double) {
        self.asset = asset
        self.walletBalance = walletBalance
        self.availableBalance = availableBalance
        self.crossUnPnL = crossUnPnL
        self.marginBalance = marginBalance
    }
}

/// Result of a futures order
public struct FuturesOrderResult: Codable {
    public let success: Bool
    public let orderId: String?
    public let clientOrderId: String?
    public let status: OrderStatus?
    public let filledQuantity: Double?
    public let averagePrice: Double?
    public let errorMessage: String?
    public let exchange: String
    public let timestamp: Date
    
    public init(
        success: Bool,
        orderId: String? = nil,
        clientOrderId: String? = nil,
        status: OrderStatus? = nil,
        filledQuantity: Double? = nil,
        averagePrice: Double? = nil,
        errorMessage: String? = nil,
        exchange: String,
        timestamp: Date = Date()
    ) {
        self.success = success
        self.orderId = orderId
        self.clientOrderId = clientOrderId
        self.status = status
        self.filledQuantity = filledQuantity
        self.averagePrice = averagePrice
        self.errorMessage = errorMessage
        self.exchange = exchange
        self.timestamp = timestamp
    }
}

/// Funding rate information for a perpetual contract
public struct FundingRate: Codable {
    public let symbol: String
    public let fundingRate: Double             // Current funding rate (e.g., 0.0001 = 0.01%)
    public let fundingTime: Date               // Next funding time
    public let markPrice: Double
    
    /// Formatted funding rate as percentage string
    public var formattedRate: String {
        let pct = fundingRate * 100
        return String(format: "%+.4f%%", pct)
    }
    
    /// Whether funding is positive (longs pay shorts)
    public var isPositive: Bool { fundingRate > 0 }
}

/// Open interest data for a perpetual futures contract
public struct OpenInterestData: Codable {
    public let symbol: String
    public let openInterest: Double           // Total OI in contracts
    public let openInterestValue: Double      // Total OI in USD (notional value)
    public let timestamp: Date
    
    /// Formatted open interest value as readable string
    public var formattedValue: String {
        if openInterestValue >= 1_000_000_000 {
            return String(format: "$%.2fB", openInterestValue / 1_000_000_000)
        } else if openInterestValue >= 1_000_000 {
            return String(format: "$%.2fM", openInterestValue / 1_000_000)
        } else {
            return String(format: "$%.0f", openInterestValue)
        }
    }
}

/// Long/Short account ratio data from Binance Futures
public struct LongShortRatioData: Codable {
    public let symbol: String
    public let longShortRatio: Double         // Ratio of long accounts to short accounts
    public let longAccount: Double            // Percentage of accounts that are long (0-1)
    public let shortAccount: Double           // Percentage of accounts that are short (0-1)
    public let timestamp: Date
    
    /// Formatted ratio string
    public var formattedRatio: String {
        return String(format: "%.2f", longShortRatio)
    }
    
    /// Sentiment interpretation
    public var sentiment: String {
        if longShortRatio > 2.0 {
            return "extreme_long"       // Very crowded long - contrarian bearish
        } else if longShortRatio > 1.5 {
            return "bullish_crowd"      // Moderately long
        } else if longShortRatio < 0.5 {
            return "extreme_short"      // Very crowded short - contrarian bullish
        } else if longShortRatio < 0.67 {
            return "bearish_crowd"      // Moderately short
        } else {
            return "balanced"
        }
    }
}

/// Top trader position ratio data (shows what smart money is doing)
public struct TopTraderRatioData: Codable {
    public let symbol: String
    public let longShortRatio: Double         // Ratio of top trader long positions to short
    public let longAccount: Double            // Percentage of top traders that are long
    public let shortAccount: Double           // Percentage of top traders that are short
    public let timestamp: Date
    
    /// Formatted ratio string
    public var formattedRatio: String {
        return String(format: "%.2f", longShortRatio)
    }
    
    /// Top trader positioning signal (follow the smart money)
    public var signal: String {
        if longShortRatio > 1.5 {
            return "top_traders_long"    // Top traders are long - bullish signal
        } else if longShortRatio < 0.67 {
            return "top_traders_short"   // Top traders are short - bearish signal
        } else {
            return "top_traders_neutral"
        }
    }
}

/// Taker buy/sell volume data (shows aggressive buyer vs seller activity)
public struct TakerBuySellData: Codable {
    public let symbol: String
    public let buySellRatio: Double           // Buy volume / Sell volume ratio
    public let buyVolume: Double              // Taker buy volume
    public let sellVolume: Double             // Taker sell volume
    public let timestamp: Date
    
    /// Formatted ratio string
    public var formattedRatio: String {
        return String(format: "%.2f", buySellRatio)
    }
    
    /// Aggressive buyer/seller signal
    public var signal: String {
        if buySellRatio > 1.2 {
            return "aggressive_buying"   // Buyers more aggressive - bullish
        } else if buySellRatio < 0.8 {
            return "aggressive_selling"  // Sellers more aggressive - bearish
        } else {
            return "balanced_flow"
        }
    }
}

/// Supported futures exchanges for direct API connection
public enum FuturesExchange: String, CaseIterable, Codable {
    case binanceFutures = "binance_futures"
    case kucoinFutures = "kucoin_futures"
    case bybit = "bybit"
    
    public var displayName: String {
        switch self {
        case .binanceFutures: return "Binance Futures"
        case .kucoinFutures: return "KuCoin Futures"
        case .bybit: return "Bybit"
        }
    }
    
    public var baseURL: URL {
        switch self {
        case .binanceFutures: return URL(string: "https://fapi.binance.com")!
        case .kucoinFutures: return URL(string: "https://api-futures.kucoin.com")!
        case .bybit: return URL(string: "https://api.bybit.com")!
        }
    }
    
    /// Maximum leverage supported by this exchange
    public var maxLeverage: Int {
        switch self {
        case .binanceFutures: return 125
        case .kucoinFutures: return 100
        case .bybit: return 100
        }
    }
    
    /// Whether this exchange is available for US users
    public var availableInUS: Bool {
        switch self {
        case .binanceFutures: return false  // Binance Futures not for US
        case .kucoinFutures: return false   // KuCoin not officially for US
        case .bybit: return false           // Bybit not for US
        }
    }
    
    /// Maps to TradingExchange for credential lookup
    public var tradingExchange: TradingExchange {
        switch self {
        case .binanceFutures: return .binance
        case .kucoinFutures: return .kucoin
        case .bybit: return .bybit
        }
    }
}

// MARK: - Futures Trading Execution Service

/// Main service for executing leveraged futures trades
/// DIRECT API CONNECTION - No backend server involved
public actor FuturesTradingExecutionService {
    public static let shared = FuturesTradingExecutionService()
    private init() {}
    
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()
    
    // Current active exchange for futures trading
    private var activeExchange: FuturesExchange = .binanceFutures
    
    /// Set the active futures exchange
    public func setActiveExchange(_ exchange: FuturesExchange) {
        activeExchange = exchange
    }
    
    /// Get the current active exchange
    public func getActiveExchange() -> FuturesExchange {
        return activeExchange
    }
    
    /// Check which futures exchanges have credentials configured
    public func getAvailableExchanges() -> [FuturesExchange] {
        return FuturesExchange.allCases.filter { exchange in
            TradingCredentialsManager.shared.hasCredentials(for: exchange.tradingExchange)
        }
    }
    
    // MARK: - Exchange Base URLs (for reference, actual URL comes from FuturesExchange enum)
    
    private var currentBaseURL: URL {
        activeExchange.baseURL
    }
    
    // MARK: - Public API
    
    /// Set leverage for a symbol
    /// - Parameters:
    ///   - symbol: Trading pair symbol (e.g., "BTCUSDT")
    ///   - leverage: Leverage value (1-125)
    /// - Returns: True if successful
    public func setLeverage(symbol: String, leverage: Int) async throws -> Bool {
        guard let credentials = TradingCredentialsManager.shared.loadCredentials(for: activeExchange.tradingExchange) else {
            throw FuturesError.noCredentials
        }
        
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let params = [
            ("symbol", symbol.uppercased()),
            ("leverage", String(min(max(leverage, 1), 125))),
            ("timestamp", String(timestamp))
        ]
        
        let queryString = params.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        let signature = hmacSHA256(message: queryString, key: credentials.apiSecret)
        let signedQuery = queryString + "&signature=\(signature)"
        
        let url = currentBaseURL.appendingPathComponent("/fapi/v1/leverage")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = signedQuery.data(using: .utf8)
        request.setValue(credentials.apiKey, forHTTPHeaderField: "X-MBX-APIKEY")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FuturesError.invalidResponse
        }
        
        if httpResponse.statusCode == 200 {
            return true
        }
        
        let errorMsg = parseErrorMessage(data: data, statusCode: httpResponse.statusCode)
        throw FuturesError.apiError(message: errorMsg)
    }
    
    /// Set margin type (isolated or cross) for a symbol
    public func setMarginType(symbol: String, marginType: MarginMode) async throws -> Bool {
        guard let credentials = TradingCredentialsManager.shared.loadCredentials(for: activeExchange.tradingExchange) else {
            throw FuturesError.noCredentials
        }
        
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let params = [
            ("symbol", symbol.uppercased()),
            ("marginType", marginType.rawValue),
            ("timestamp", String(timestamp))
        ]
        
        let queryString = params.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        let signature = hmacSHA256(message: queryString, key: credentials.apiSecret)
        let signedQuery = queryString + "&signature=\(signature)"
        
        let url = currentBaseURL.appendingPathComponent("/fapi/v1/marginType")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = signedQuery.data(using: .utf8)
        request.setValue(credentials.apiKey, forHTTPHeaderField: "X-MBX-APIKEY")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FuturesError.invalidResponse
        }
        
        // 200 = success, or -4046 means margin type is already set (which is fine)
        if httpResponse.statusCode == 200 {
            return true
        }
        
        // Check if error is "No need to change margin type" which is acceptable
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let code = json["code"] as? Int,
           code == -4046 {
            return true // Already set to this margin type
        }
        
        let errorMsg = parseErrorMessage(data: data, statusCode: httpResponse.statusCode)
        throw FuturesError.apiError(message: errorMsg)
    }
    
    /// Submit a futures market order
    public func submitMarketOrder(
        symbol: String,
        side: TradeSide,
        quantity: Double,
        positionSide: PositionSide = .both,
        reduceOnly: Bool = false
    ) async throws -> FuturesOrderResult {
        return try await submitFuturesOrder(
            symbol: symbol,
            side: side,
            type: .market,
            quantity: quantity,
            price: nil,
            positionSide: positionSide,
            reduceOnly: reduceOnly
        )
    }
    
    /// Submit a futures limit order
    public func submitLimitOrder(
        symbol: String,
        side: TradeSide,
        quantity: Double,
        price: Double,
        positionSide: PositionSide = .both,
        reduceOnly: Bool = false,
        timeInForce: String = "GTC"
    ) async throws -> FuturesOrderResult {
        return try await submitFuturesOrder(
            symbol: symbol,
            side: side,
            type: .limit,
            quantity: quantity,
            price: price,
            positionSide: positionSide,
            reduceOnly: reduceOnly,
            timeInForce: timeInForce
        )
    }
    
    /// Submit a stop-market order (triggers at stop price, executes as market)
    public func submitStopMarketOrder(
        symbol: String,
        side: TradeSide,
        quantity: Double,
        stopPrice: Double,
        positionSide: PositionSide = .both,
        reduceOnly: Bool = true
    ) async throws -> FuturesOrderResult {
        // SAFETY: Block live futures trading when disabled
        guard AppConfig.liveTradingEnabled else {
            return FuturesOrderResult(success: false, errorMessage: AppConfig.liveTradingDisabledMessage, exchange: "Binance Futures")
        }
        
        guard let credentials = TradingCredentialsManager.shared.loadCredentials(for: activeExchange.tradingExchange) else {
            return FuturesOrderResult(success: false, errorMessage: "No credentials found", exchange: "Binance Futures")
        }
        
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        var params: [(String, String)] = [
            ("symbol", symbol.uppercased()),
            ("side", side.rawValue),
            ("type", "STOP_MARKET"),
            ("quantity", formatQuantity(quantity)),
            ("stopPrice", formatPrice(stopPrice)),
            ("positionSide", positionSide.rawValue),
            ("timestamp", String(timestamp))
        ]
        
        if reduceOnly {
            params.append(("reduceOnly", "true"))
        }
        
        return try await executeOrder(credentials: credentials, params: params)
    }
    
    /// Submit a take-profit market order
    public func submitTakeProfitOrder(
        symbol: String,
        side: TradeSide,
        quantity: Double,
        stopPrice: Double,
        positionSide: PositionSide = .both,
        reduceOnly: Bool = true
    ) async throws -> FuturesOrderResult {
        // SAFETY: Block live futures trading when disabled
        guard AppConfig.liveTradingEnabled else {
            return FuturesOrderResult(success: false, errorMessage: AppConfig.liveTradingDisabledMessage, exchange: "Binance Futures")
        }
        
        guard let credentials = TradingCredentialsManager.shared.loadCredentials(for: activeExchange.tradingExchange) else {
            return FuturesOrderResult(success: false, errorMessage: "No credentials found", exchange: "Binance Futures")
        }
        
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        var params: [(String, String)] = [
            ("symbol", symbol.uppercased()),
            ("side", side.rawValue),
            ("type", "TAKE_PROFIT_MARKET"),
            ("quantity", formatQuantity(quantity)),
            ("stopPrice", formatPrice(stopPrice)),
            ("positionSide", positionSide.rawValue),
            ("timestamp", String(timestamp))
        ]
        
        if reduceOnly {
            params.append(("reduceOnly", "true"))
        }
        
        return try await executeOrder(credentials: credentials, params: params)
    }
    
    /// Close an entire position
    /// - Important: Closing positions is ALWAYS allowed even when live trading is off.
    ///   This is a safety feature - you should always be able to close positions to limit losses.
    public func closePosition(symbol: String, positionSide: PositionSide = .both) async throws -> FuturesOrderResult {
        // No live trading check here - closing positions is always allowed for safety
        
        // Get current position to determine quantity and direction
        let positions = try await fetchPositions(symbol: symbol)
        guard let position = positions.first(where: { 
            $0.symbol.uppercased() == symbol.uppercased() && 
            abs($0.positionAmount) > 0 
        }) else {
            return FuturesOrderResult(
                success: false,
                errorMessage: "No open position found for \(symbol)",
                exchange: "Binance Futures"
            )
        }
        
        // Close by placing opposite order
        let closeSide: TradeSide = position.isLong ? .sell : .buy
        let quantity = abs(position.positionAmount)
        
        return try await submitMarketOrder(
            symbol: symbol,
            side: closeSide,
            quantity: quantity,
            positionSide: positionSide,
            reduceOnly: true
        )
    }
    
    /// Fetch all futures account balances
    public func fetchBalances() async throws -> [FuturesAssetBalance] {
        guard let credentials = TradingCredentialsManager.shared.loadCredentials(for: activeExchange.tradingExchange) else {
            throw FuturesError.noCredentials
        }
        
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let queryString = "timestamp=\(timestamp)"
        let signature = hmacSHA256(message: queryString, key: credentials.apiSecret)
        let signedQuery = queryString + "&signature=\(signature)"
        
        var components = URLComponents(url: currentBaseURL.appendingPathComponent("/fapi/v2/balance"), resolvingAgainstBaseURL: false)!
        components.query = signedQuery
        
        guard let url = components.url else {
            throw FuturesError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(credentials.apiKey, forHTTPHeaderField: "X-MBX-APIKEY")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorMsg = parseErrorMessage(data: data, statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
            throw FuturesError.apiError(message: errorMsg)
        }
        
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw FuturesError.parseError
        }
        
        return jsonArray.compactMap { item -> FuturesAssetBalance? in
            guard let asset = item["asset"] as? String,
                  let walletBalanceStr = item["balance"] as? String,
                  let availableBalanceStr = item["availableBalance"] as? String,
                  let crossUnPnLStr = item["crossUnPnl"] as? String,
                  let marginBalanceStr = item["marginBalance"] as? String ?? item["balance"] as? String,
                  let walletBalance = Double(walletBalanceStr),
                  let availableBalance = Double(availableBalanceStr),
                  walletBalance > 0 || availableBalance > 0 else {
                return nil
            }
            
            return FuturesAssetBalance(
                asset: asset,
                walletBalance: walletBalance,
                availableBalance: availableBalance,
                crossUnPnL: Double(crossUnPnLStr) ?? 0,
                marginBalance: Double(marginBalanceStr) ?? walletBalance
            )
        }
    }
    
    /// Fetch open positions
    public func fetchPositions(symbol: String? = nil) async throws -> [FuturesPosition] {
        guard let credentials = TradingCredentialsManager.shared.loadCredentials(for: activeExchange.tradingExchange) else {
            throw FuturesError.noCredentials
        }
        
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        var queryString = "timestamp=\(timestamp)"
        if let symbol = symbol {
            queryString = "symbol=\(symbol.uppercased())&\(queryString)"
        }
        
        let signature = hmacSHA256(message: queryString, key: credentials.apiSecret)
        let signedQuery = queryString + "&signature=\(signature)"
        
        var components = URLComponents(url: currentBaseURL.appendingPathComponent("/fapi/v2/positionRisk"), resolvingAgainstBaseURL: false)!
        components.query = signedQuery
        
        guard let url = components.url else {
            throw FuturesError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(credentials.apiKey, forHTTPHeaderField: "X-MBX-APIKEY")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorMsg = parseErrorMessage(data: data, statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
            throw FuturesError.apiError(message: errorMsg)
        }
        
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw FuturesError.parseError
        }
        
        return jsonArray.compactMap { item -> FuturesPosition? in
            guard let symbolStr = item["symbol"] as? String,
                  let positionAmtStr = item["positionAmt"] as? String,
                  let entryPriceStr = item["entryPrice"] as? String,
                  let markPriceStr = item["markPrice"] as? String,
                  let unRealizedProfitStr = item["unRealizedProfit"] as? String,
                  let leverageStr = item["leverage"] as? String,
                  let positionAmount = Double(positionAmtStr),
                  let entryPrice = Double(entryPriceStr),
                  let markPrice = Double(markPriceStr),
                  let unrealizedPnL = Double(unRealizedProfitStr),
                  let leverage = Int(leverageStr) else {
                return nil
            }
            
            // Skip positions with 0 amount
            guard abs(positionAmount) > 0 else { return nil }
            
            let positionSideStr = item["positionSide"] as? String ?? "BOTH"
            let marginTypeStr = item["marginType"] as? String ?? "cross"
            let liquidationPriceStr = item["liquidationPrice"] as? String ?? "0"
            let notionalStr = item["notional"] as? String ?? "0"
            let isolatedMarginStr = item["isolatedMargin"] as? String
            
            return FuturesPosition(
                id: "\(symbolStr)_\(positionSideStr)",
                symbol: symbolStr,
                positionSide: PositionSide(rawValue: positionSideStr) ?? .both,
                positionAmount: positionAmount,
                entryPrice: entryPrice,
                markPrice: markPrice,
                unrealizedPnL: unrealizedPnL,
                leverage: leverage,
                marginType: MarginMode(rawValue: marginTypeStr.uppercased()) ?? .cross,
                liquidationPrice: Double(liquidationPriceStr) ?? 0,
                notionalValue: abs(Double(notionalStr) ?? 0),
                isolatedMargin: isolatedMarginStr.flatMap { Double($0) }
            )
        }
    }
    
    /// Fetch current funding rate for a symbol
    public func fetchFundingRate(symbol: String) async throws -> FundingRate {
        let url = currentBaseURL.appendingPathComponent("/fapi/v1/premiumIndex")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "symbol", value: symbol.uppercased())]
        
        guard let requestURL = components.url else {
            throw FuturesError.invalidURL
        }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw FuturesError.apiError(message: "Failed to fetch funding rate")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let symbolStr = json["symbol"] as? String,
              let fundingRateStr = json["lastFundingRate"] as? String,
              let fundingTimeMs = json["nextFundingTime"] as? Int64,
              let markPriceStr = json["markPrice"] as? String,
              let fundingRate = Double(fundingRateStr),
              let markPrice = Double(markPriceStr) else {
            throw FuturesError.parseError
        }
        
        return FundingRate(
            symbol: symbolStr,
            fundingRate: fundingRate,
            fundingTime: Date(timeIntervalSince1970: Double(fundingTimeMs) / 1000),
            markPrice: markPrice
        )
    }
    
    /// Fetch current open interest for a symbol
    /// Uses Binance Futures public endpoint (no auth required)
    public func fetchOpenInterest(symbol: String) async throws -> OpenInterestData {
        let url = currentBaseURL.appendingPathComponent("/fapi/v1/openInterest")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "symbol", value: symbol.uppercased())]
        
        guard let requestURL = components.url else {
            throw FuturesError.invalidURL
        }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw FuturesError.apiError(message: "Failed to fetch open interest")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let symbolStr = json["symbol"] as? String,
              let openInterestStr = json["openInterest"] as? String,
              let openInterest = Double(openInterestStr),
              let timeMs = json["time"] as? Int64 else {
            throw FuturesError.parseError
        }
        
        // Fetch mark price to calculate notional value
        // We already have fetchFundingRate which returns mark price
        let markPrice: Double
        do {
            let fundingData = try await fetchFundingRate(symbol: symbol)
            markPrice = fundingData.markPrice
        } catch {
            // Fallback: estimate from the symbol (won't have exact price)
            markPrice = 0
        }
        
        let openInterestValue = openInterest * markPrice
        
        return OpenInterestData(
            symbol: symbolStr,
            openInterest: openInterest,
            openInterestValue: openInterestValue,
            timestamp: Date(timeIntervalSince1970: Double(timeMs) / 1000)
        )
    }
    
    /// Fetch global long/short account ratio
    /// Uses Binance Futures public endpoint (no auth required)
    public func fetchLongShortRatio(symbol: String) async throws -> LongShortRatioData {
        // Use fapi.binance.com for this endpoint
        let baseURL = URL(string: "https://fapi.binance.com")!
        let url = baseURL.appendingPathComponent("/futures/data/globalLongShortAccountRatio")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "symbol", value: symbol.uppercased()),
            URLQueryItem(name: "period", value: "5m"),  // 5 minute periods
            URLQueryItem(name: "limit", value: "1")     // Just get the latest
        ]
        
        guard let requestURL = components.url else {
            throw FuturesError.invalidURL
        }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw FuturesError.apiError(message: "Failed to fetch long/short ratio")
        }
        
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let json = jsonArray.first,
              let longShortRatioStr = json["longShortRatio"] as? String,
              let longAccountStr = json["longAccount"] as? String,
              let shortAccountStr = json["shortAccount"] as? String,
              let timestampMs = json["timestamp"] as? Int64,
              let longShortRatio = Double(longShortRatioStr),
              let longAccount = Double(longAccountStr),
              let shortAccount = Double(shortAccountStr) else {
            throw FuturesError.parseError
        }
        
        return LongShortRatioData(
            symbol: symbol.uppercased(),
            longShortRatio: longShortRatio,
            longAccount: longAccount,
            shortAccount: shortAccount,
            timestamp: Date(timeIntervalSince1970: Double(timestampMs) / 1000)
        )
    }
    
    /// Fetch top trader long/short position ratio (smart money indicator)
    /// Uses Binance Futures public endpoint (no auth required)
    public func fetchTopTraderRatio(symbol: String) async throws -> TopTraderRatioData {
        let baseURL = URL(string: "https://fapi.binance.com")!
        let url = baseURL.appendingPathComponent("/futures/data/topLongShortPositionRatio")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "symbol", value: symbol.uppercased()),
            URLQueryItem(name: "period", value: "5m"),
            URLQueryItem(name: "limit", value: "1")
        ]
        
        guard let requestURL = components.url else {
            throw FuturesError.invalidURL
        }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw FuturesError.apiError(message: "Failed to fetch top trader ratio")
        }
        
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let json = jsonArray.first,
              let longShortRatioStr = json["longShortRatio"] as? String,
              let longAccountStr = json["longAccount"] as? String,
              let shortAccountStr = json["shortAccount"] as? String,
              let timestampMs = json["timestamp"] as? Int64,
              let longShortRatio = Double(longShortRatioStr),
              let longAccount = Double(longAccountStr),
              let shortAccount = Double(shortAccountStr) else {
            throw FuturesError.parseError
        }
        
        return TopTraderRatioData(
            symbol: symbol.uppercased(),
            longShortRatio: longShortRatio,
            longAccount: longAccount,
            shortAccount: shortAccount,
            timestamp: Date(timeIntervalSince1970: Double(timestampMs) / 1000)
        )
    }
    
    /// Fetch taker buy/sell volume ratio (shows aggressive buying vs selling)
    /// Uses Binance Futures public endpoint (no auth required)
    public func fetchTakerBuySellRatio(symbol: String) async throws -> TakerBuySellData {
        let baseURL = URL(string: "https://fapi.binance.com")!
        let url = baseURL.appendingPathComponent("/futures/data/takerlongshortRatio")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "symbol", value: symbol.uppercased()),
            URLQueryItem(name: "period", value: "5m"),
            URLQueryItem(name: "limit", value: "1")
        ]
        
        guard let requestURL = components.url else {
            throw FuturesError.invalidURL
        }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw FuturesError.apiError(message: "Failed to fetch taker buy/sell ratio")
        }
        
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let json = jsonArray.first,
              let buySellRatioStr = json["buySellRatio"] as? String,
              let buyVolStr = json["buyVol"] as? String,
              let sellVolStr = json["sellVol"] as? String,
              let timestampMs = json["timestamp"] as? Int64,
              let buySellRatio = Double(buySellRatioStr),
              let buyVol = Double(buyVolStr),
              let sellVol = Double(sellVolStr) else {
            throw FuturesError.parseError
        }
        
        return TakerBuySellData(
            symbol: symbol.uppercased(),
            buySellRatio: buySellRatio,
            buyVolume: buyVol,
            sellVolume: sellVol,
            timestamp: Date(timeIntervalSince1970: Double(timestampMs) / 1000)
        )
    }
    
    /// Cancel a futures order
    public func cancelOrder(symbol: String, orderId: String) async throws -> Bool {
        guard let credentials = TradingCredentialsManager.shared.loadCredentials(for: activeExchange.tradingExchange) else {
            throw FuturesError.noCredentials
        }
        
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let params = [
            ("symbol", symbol.uppercased()),
            ("orderId", orderId),
            ("timestamp", String(timestamp))
        ]
        
        let queryString = params.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        let signature = hmacSHA256(message: queryString, key: credentials.apiSecret)
        let signedQuery = queryString + "&signature=\(signature)"
        
        let url = currentBaseURL.appendingPathComponent("/fapi/v1/order")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.httpBody = signedQuery.data(using: .utf8)
        request.setValue(credentials.apiKey, forHTTPHeaderField: "X-MBX-APIKEY")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FuturesError.invalidResponse
        }
        
        if httpResponse.statusCode == 200 {
            return true
        }
        
        let errorMsg = parseErrorMessage(data: data, statusCode: httpResponse.statusCode)
        throw FuturesError.apiError(message: errorMsg)
    }
    
    /// Cancel all open orders for a symbol
    public func cancelAllOrders(symbol: String) async throws -> Bool {
        guard let credentials = TradingCredentialsManager.shared.loadCredentials(for: activeExchange.tradingExchange) else {
            throw FuturesError.noCredentials
        }
        
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let params = [
            ("symbol", symbol.uppercased()),
            ("timestamp", String(timestamp))
        ]
        
        let queryString = params.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        let signature = hmacSHA256(message: queryString, key: credentials.apiSecret)
        let signedQuery = queryString + "&signature=\(signature)"
        
        let url = currentBaseURL.appendingPathComponent("/fapi/v1/allOpenOrders")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.httpBody = signedQuery.data(using: .utf8)
        request.setValue(credentials.apiKey, forHTTPHeaderField: "X-MBX-APIKEY")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FuturesError.invalidResponse
        }
        
        return httpResponse.statusCode == 200
    }
    
    /// Test connection to Binance Futures
    public func testConnection() async throws -> Bool {
        guard let credentials = TradingCredentialsManager.shared.loadCredentials(for: activeExchange.tradingExchange) else {
            return false
        }
        
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let queryString = "timestamp=\(timestamp)"
        let signature = hmacSHA256(message: queryString, key: credentials.apiSecret)
        let signedQuery = queryString + "&signature=\(signature)"
        
        guard var components = URLComponents(url: currentBaseURL.appendingPathComponent("/fapi/v2/account"), resolvingAgainstBaseURL: false) else { return false }
        components.query = signedQuery

        guard let url = components.url else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(credentials.apiKey, forHTTPHeaderField: "X-MBX-APIKEY")
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else { return false }
        return httpResponse.statusCode == 200
    }
    
    // MARK: - Private Implementation
    
    private func submitFuturesOrder(
        symbol: String,
        side: TradeSide,
        type: OrderType,
        quantity: Double,
        price: Double?,
        positionSide: PositionSide,
        reduceOnly: Bool,
        timeInForce: String = "GTC"
    ) async throws -> FuturesOrderResult {
        // SAFETY: Block live futures trading when disabled at app config level
        guard AppConfig.liveTradingEnabled else {
            return FuturesOrderResult(
                success: false,
                errorMessage: AppConfig.liveTradingDisabledMessage,
                exchange: "Binance Futures"
            )
        }
        
        guard let credentials = TradingCredentialsManager.shared.loadCredentials(for: activeExchange.tradingExchange) else {
            return FuturesOrderResult(
                success: false,
                errorMessage: "No Binance credentials found. Please add your API keys in Settings.",
                exchange: "Binance Futures"
            )
        }
        
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        var params: [(String, String)] = [
            ("symbol", symbol.uppercased()),
            ("side", side.rawValue),
            ("type", type.rawValue),
            ("quantity", formatQuantity(quantity)),
            ("positionSide", positionSide.rawValue),
            ("timestamp", String(timestamp))
        ]
        
        if type == .limit, let price = price {
            params.append(("price", formatPrice(price)))
            params.append(("timeInForce", timeInForce))
        }
        
        if reduceOnly {
            params.append(("reduceOnly", "true"))
        }
        
        return try await executeOrder(credentials: credentials, params: params)
    }
    
    private func executeOrder(credentials: TradingCredentials, params: [(String, String)]) async throws -> FuturesOrderResult {
        let queryString = params.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        let signature = hmacSHA256(message: queryString, key: credentials.apiSecret)
        let signedQuery = queryString + "&signature=\(signature)"
        
        let url = currentBaseURL.appendingPathComponent("/fapi/v1/order")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = signedQuery.data(using: .utf8)
        request.setValue(credentials.apiKey, forHTTPHeaderField: "X-MBX-APIKEY")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return FuturesOrderResult(success: false, errorMessage: "Invalid response", exchange: "Binance Futures")
        }
        
        if httpResponse.statusCode == 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let orderId = json["orderId"] as? Int64
                let clientOrderId = json["clientOrderId"] as? String
                let status = json["status"] as? String
                let executedQty = (json["executedQty"] as? String).flatMap { Double($0) }
                let avgPrice = (json["avgPrice"] as? String).flatMap { Double($0) }
                
                return FuturesOrderResult(
                    success: true,
                    orderId: orderId.map { String($0) },
                    clientOrderId: clientOrderId,
                    status: OrderStatus(rawValue: status ?? "NEW"),
                    filledQuantity: executedQty,
                    averagePrice: avgPrice,
                    exchange: "Binance Futures"
                )
            }
        }
        
        let errorMsg = parseErrorMessage(data: data, statusCode: httpResponse.statusCode)
        return FuturesOrderResult(success: false, errorMessage: errorMsg, exchange: "Binance Futures")
    }
    
    // MARK: - Helpers
    
    private func formatQuantity(_ quantity: Double) -> String {
        if quantity < 0.001 {
            return String(format: "%.8f", quantity)
        } else if quantity < 1 {
            return String(format: "%.6f", quantity)
        } else if quantity < 1000 {
            return String(format: "%.4f", quantity)
        } else {
            return String(format: "%.2f", quantity)
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
    
    private func hmacSHA256(message: String, key: String) -> String {
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
        
        return macData.map { String(format: "%02hhx", $0) }.joined()
    }
    
    private func parseErrorMessage(data: Data, statusCode: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let msg = json["msg"] as? String { return msg }
            if let message = json["message"] as? String { return message }
            if let error = json["error"] as? String { return error }
        }
        return "Request failed with status code \(statusCode)"
    }
}

// MARK: - Futures Errors

public enum FuturesError: LocalizedError {
    case noCredentials
    case invalidResponse
    case invalidURL
    case parseError
    case apiError(message: String)
    case insufficientBalance
    case positionNotFound
    case leverageOutOfRange
    
    public var errorDescription: String? {
        switch self {
        case .noCredentials:
            return "No Binance credentials found. Please add your Futures API keys in Settings."
        case .invalidResponse:
            return "Invalid response from exchange"
        case .invalidURL:
            return "Invalid API URL"
        case .parseError:
            return "Failed to parse exchange response"
        case .apiError(let message):
            return "API Error: \(message)"
        case .insufficientBalance:
            return "Insufficient margin balance for this order"
        case .positionNotFound:
            return "No open position found"
        case .leverageOutOfRange:
            return "Leverage must be between 1 and 125"
        }
    }
}
