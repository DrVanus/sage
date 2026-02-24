import Foundation

/// Basic trade direction for orders and bots
public enum TradeSide: String, Codable, CaseIterable {
    case buy = "BUY"
    case sell = "SELL"
}

/// Supported order types
public enum OrderType: String, Codable, CaseIterable {
    case market = "MARKET"
    case limit = "LIMIT"
    case stop = "STOP"
    case stopLimit = "STOP_LIMIT"
    case stopLoss = "STOP_LOSS"
}

/// Unified trading errors across all exchanges
public enum TradingError: LocalizedError {
    // Connection errors (Coinbase / general)
    case notConnected
    case connectionFailed

    // Order errors
    case orderFailed(String)
    case invalidAmount
    case insufficientBalance
    case riskNotAcknowledged
    case orderRejected(reason: String)

    // Exchange-specific errors
    case noCredentials(exchange: String)
    case apiError(message: String)
    case parseError
    case invalidSymbol

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to exchange. Please connect first."
        case .connectionFailed:
            return "Failed to connect to exchange. Check your API keys and internet connection."
        case .orderFailed(let message):
            return "Order failed: \(message)"
        case .invalidAmount:
            return "Invalid order amount"
        case .insufficientBalance:
            return "Insufficient balance for this order"
        case .riskNotAcknowledged:
            return "Trading risk acknowledgment required"
        case .orderRejected(let reason):
            return "Order rejected: \(reason)"
        case .noCredentials(let exchange):
            return "No trading credentials found for \(exchange). Please add your API keys in Settings."
        case .apiError(let message):
            return "API Error: \(message)"
        case .parseError:
            return "Failed to parse exchange response"
        case .invalidSymbol:
            return "Invalid trading symbol"
        }
    }
}
