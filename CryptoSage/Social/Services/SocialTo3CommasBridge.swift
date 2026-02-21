//
//  SocialTo3CommasBridge.swift
//  CryptoSage
//
//  Bridge for converting shared bot configurations from the Social marketplace
//  into 3Commas bot creation parameters for live trading.
//

import Foundation

// MARK: - Social to 3Commas Bridge

/// Converts shared bot configurations to 3Commas API parameters
public struct SocialTo3CommasBridge {
    
    // MARK: - Bot Creation Parameters
    
    /// Parameters for creating a 3Commas DCA bot
    public struct DCABotParams: Encodable {
        let name: String
        let accountId: Int
        let pairs: [String]
        let baseOrderVolume: Double
        let safetyOrderVolume: Double
        let takeProfit: Double
        let maxActiveDeals: Int
        let maxSafetyOrders: Int
        let priceDeviationPercent: Double
        let martingaleVolumeCoefficient: Double
        let martingaleStepCoefficient: Double
        let stopLossPercent: Double?
        let startOrderType: String
        let strategy: String
        
        enum CodingKeys: String, CodingKey {
            case name
            case accountId = "account_id"
            case pairs
            case baseOrderVolume = "base_order_volume"
            case safetyOrderVolume = "safety_order_volume"
            case takeProfit = "take_profit"
            case maxActiveDeals = "max_active_deals"
            case maxSafetyOrders = "max_safety_orders"
            case priceDeviationPercent = "price_deviation_to_open_safety_orders"
            case martingaleVolumeCoefficient = "martingale_volume_coefficient"
            case martingaleStepCoefficient = "martingale_step_coefficient"
            case stopLossPercent = "stop_loss_percentage"
            case startOrderType = "start_order_type"
            case strategy
        }
    }
    
    /// Parameters for creating a 3Commas Grid bot
    public struct GridBotParams: Encodable {
        let name: String
        let accountId: Int
        let pair: String
        let lowerPrice: Double
        let upperPrice: Double
        let gridLevels: Int
        let totalInvestment: Double
        let profitPerGrid: Double
        let stopLossPercent: Double?
        
        enum CodingKeys: String, CodingKey {
            case name
            case accountId = "account_id"
            case pair
            case lowerPrice = "lower_price"
            case upperPrice = "upper_price"
            case gridLevels = "grids_quantity"
            case totalInvestment = "investment_quote_currency"
            case profitPerGrid = "profit_per_grid"
            case stopLossPercent = "stop_loss_percentage"
        }
    }
    
    // MARK: - Conversion Methods
    
    /// Convert a SharedBotConfig to 3Commas bot creation parameters
    /// - Parameters:
    ///   - config: The shared bot configuration
    ///   - accountId: The 3Commas account ID to create the bot on
    ///   - customName: Optional custom name for the bot
    /// - Returns: The appropriate bot parameters for 3Commas API
    public static func convertToParams(
        from config: SharedBotConfig,
        accountId: Int,
        customName: String? = nil
    ) throws -> Any {
        let botName = customName ?? "Copy: \(config.name)"
        
        switch config.botType {
        case .dca:
            return try createDCAParams(from: config, accountId: accountId, name: botName)
        case .grid:
            return try createGridParams(from: config, accountId: accountId, name: botName)
        case .signal:
            // Signal bots use similar params to DCA
            return try createDCAParams(from: config, accountId: accountId, name: botName)
        case .derivatives:
            // Derivatives would need futures-specific params
            throw BridgeError.unsupportedBotType("Derivatives bots require futures account")
        case .predictionMarket:
            // Prediction market bots are not supported on 3Commas
            throw BridgeError.unsupportedBotType("Prediction market bots are not supported on 3Commas")
        }
    }
    
    /// Create DCA bot parameters from shared config
    private static func createDCAParams(
        from config: SharedBotConfig,
        accountId: Int,
        name: String
    ) throws -> DCABotParams {
        // Parse config values with defaults
        let baseOrderVolume = Double(config.config["baseOrderSize"] ?? "100") ?? 100.0
        let safetyOrderVolume = baseOrderVolume * 0.5 // Default safety order is half of base
        let takeProfit = Double(config.config["takeProfit"] ?? "2.5") ?? 2.5
        let maxOrders = Int(config.config["maxOrders"] ?? "5") ?? 5
        let priceDeviation = Double(config.config["priceDeviation"] ?? "1.5") ?? 1.5
        let stopLoss = config.config["stopLoss"].flatMap { Double($0) }
        
        // Build pair in 3Commas format (QUOTE_BASE)
        let pair = formatPairFor3Commas(config.tradingPair, exchange: config.exchange)
        
        return DCABotParams(
            name: name,
            accountId: accountId,
            pairs: [pair],
            baseOrderVolume: baseOrderVolume,
            safetyOrderVolume: safetyOrderVolume,
            takeProfit: takeProfit,
            maxActiveDeals: 1,
            maxSafetyOrders: maxOrders,
            priceDeviationPercent: priceDeviation,
            martingaleVolumeCoefficient: 1.5,
            martingaleStepCoefficient: 1.2,
            stopLossPercent: stopLoss,
            startOrderType: "limit",
            strategy: "long"
        )
    }
    
    /// Create Grid bot parameters from shared config
    private static func createGridParams(
        from config: SharedBotConfig,
        accountId: Int,
        name: String
    ) throws -> GridBotParams {
        // Parse config values
        guard let lowerPrice = Double(config.config["lowerPrice"] ?? "") else {
            throw BridgeError.missingRequiredParam("lowerPrice")
        }
        guard let upperPrice = Double(config.config["upperPrice"] ?? "") else {
            throw BridgeError.missingRequiredParam("upperPrice")
        }
        
        let gridLevels = Int(config.config["gridLevels"] ?? "10") ?? 10
        let orderVolume = Double(config.config["orderVolume"] ?? "50") ?? 50.0
        let totalInvestment = orderVolume * Double(gridLevels)
        let profitPerGrid = Double(config.config["takeProfit"] ?? "1.0") ?? 1.0
        let stopLoss = config.config["stopLoss"].flatMap { Double($0) }
        
        let pair = formatPairFor3Commas(config.tradingPair, exchange: config.exchange)
        
        return GridBotParams(
            name: name,
            accountId: accountId,
            pair: pair,
            lowerPrice: lowerPrice,
            upperPrice: upperPrice,
            gridLevels: gridLevels,
            totalInvestment: totalInvestment,
            profitPerGrid: profitPerGrid,
            stopLossPercent: stopLoss
        )
    }
    
    /// Map SharedBotType to 3Commas bot strategy type
    public static func mapBotType(_ type: SharedBotType) -> ThreeCommasBotType {
        switch type {
        case .dca:
            return .simple  // DCA is "simple" strategy in 3Commas
        case .grid:
            return .gordon  // Grid is "gordon" strategy in 3Commas
        case .signal:
            return .simple  // Signal bots are also simple strategy
        case .derivatives:
            return .simple  // Futures would need separate handling
        case .predictionMarket:
            return .simple  // Prediction bots default to simple (not actually used on 3Commas)
        }
    }
    
    /// Format trading pair for 3Commas API (QUOTE_BASE format)
    public static func formatPairFor3Commas(_ pair: String, exchange: String) -> String {
        // Remove any existing separators and standardize
        let cleaned = pair.uppercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "/", with: "")
        
        // Common quote currencies to identify
        let quotes = ["USDT", "USDC", "USD", "BTC", "ETH", "EUR", "BUSD"]
        
        for quote in quotes {
            if cleaned.hasSuffix(quote) {
                let base = String(cleaned.dropLast(quote.count))
                // 3Commas uses QUOTE_BASE format
                return "\(quote)_\(base)"
            }
        }
        
        // Fallback: assume last 4 chars are quote (e.g., BTCUSDT -> USDT_BTC)
        if cleaned.count > 4 {
            let base = String(cleaned.dropLast(4))
            let quote = String(cleaned.suffix(4))
            return "\(quote)_\(base)"
        }
        
        return pair
    }
    
    /// Validate that a shared bot config can be converted to 3Commas
    public static func validateConfig(_ config: SharedBotConfig) -> [String] {
        var errors: [String] = []
        
        // Check bot type support
        if config.botType == .derivatives {
            errors.append("Derivatives bots require a futures-enabled 3Commas account")
        }
        
        if config.botType == .predictionMarket {
            errors.append("Prediction market bots are not supported on 3Commas")
        }
        
        // Check for grid bot requirements
        if config.botType == .grid {
            if config.config["lowerPrice"] == nil {
                errors.append("Grid bot requires lower price")
            }
            if config.config["upperPrice"] == nil {
                errors.append("Grid bot requires upper price")
            }
        }
        
        // Check exchange compatibility
        let supportedExchanges = ["Binance", "Coinbase", "KuCoin", "Bybit", "Kraken", "OKX"]
        if !supportedExchanges.contains(where: { config.exchange.lowercased().contains($0.lowercased()) }) {
            errors.append("Exchange '\(config.exchange)' may not be fully supported by 3Commas")
        }
        
        return errors
    }
}

// MARK: - Bridge Errors

public enum BridgeError: LocalizedError {
    case unsupportedBotType(String)
    case missingRequiredParam(String)
    case invalidConfig(String)
    case apiError(String)
    
    public var errorDescription: String? {
        switch self {
        case .unsupportedBotType(let message):
            return "Unsupported bot type: \(message)"
        case .missingRequiredParam(let param):
            return "Missing required parameter: \(param)"
        case .invalidConfig(let message):
            return "Invalid configuration: \(message)"
        case .apiError(let message):
            return "3Commas API error: \(message)"
        }
    }
}

// MARK: - Future: Live Bot Creation

/// Extension for actual 3Commas bot creation (requires ThreeCommasAPI integration)
public extension SocialTo3CommasBridge {
    
    /// Create a live bot on 3Commas from a shared bot configuration
    /// - Note: This is a placeholder for future implementation when 3Commas API
    ///         supports bot creation endpoints
    static func createLiveBot(
        from config: SharedBotConfig,
        accountId: Int,
        customName: String? = nil
    ) async throws -> Int {
        // Validate configuration
        let errors = validateConfig(config)
        if !errors.isEmpty {
            throw BridgeError.invalidConfig(errors.joined(separator: "; "))
        }
        
        // Convert to params
        _ = try convertToParams(from: config, accountId: accountId, customName: customName)
        
        // TODO: When 3Commas API supports bot creation, implement here:
        // let response = try await ThreeCommasAPI.shared.createBot(params: params)
        // return response.bot.id
        
        // For now, throw not implemented error
        throw BridgeError.apiError("Live bot creation not yet implemented. Please create bots directly in 3Commas.")
    }
}
