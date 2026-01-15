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
}
