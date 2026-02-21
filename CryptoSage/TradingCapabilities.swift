import Foundation

/// Centralized capability matrix used by trading and derivatives flows.
/// Keeps UI affordances aligned with executable backend paths.
public enum TradingCapabilityMatrix {
    public struct Profile: Equatable {
        public let supportsLiveSpot: Bool
        public let supportsLiveDerivatives: Bool
        public let supportsLeverage: Bool
        public let supportsLiveShorting: Bool
        public let supportsPaperShorting: Bool
        
        public init(
            supportsLiveSpot: Bool,
            supportsLiveDerivatives: Bool,
            supportsLeverage: Bool,
            supportsLiveShorting: Bool,
            supportsPaperShorting: Bool
        ) {
            self.supportsLiveSpot = supportsLiveSpot
            self.supportsLiveDerivatives = supportsLiveDerivatives
            self.supportsLeverage = supportsLeverage
            self.supportsLiveShorting = supportsLiveShorting
            self.supportsPaperShorting = supportsPaperShorting
        }
    }
    
    /// Capability profile for each connected exchange.
    public static func profile(for exchange: TradingExchange) -> Profile {
        switch exchange {
        case .coinbase:
            return Profile(
                supportsLiveSpot: true,
                supportsLiveDerivatives: true,
                supportsLeverage: true,
                supportsLiveShorting: true,
                supportsPaperShorting: false
            )
        case .binance, .kucoin, .bybit, .okx:
            return Profile(
                supportsLiveSpot: true,
                supportsLiveDerivatives: true,
                supportsLeverage: true,
                supportsLiveShorting: true,
                supportsPaperShorting: false
            )
        case .binanceUS, .kraken:
            return Profile(
                supportsLiveSpot: true,
                supportsLiveDerivatives: false,
                supportsLeverage: false,
                supportsLiveShorting: false,
                supportsPaperShorting: false
            )
        }
    }
    
    /// App-level paper mode capability (current simulator behavior).
    public static let paperTradingProfile = Profile(
        supportsLiveSpot: false,
        supportsLiveDerivatives: false,
        supportsLeverage: false,
        supportsLiveShorting: false,
        supportsPaperShorting: false
    )
    
    /// Maps derivatives UI exchange identifiers to TradingExchange values.
    public static func tradingExchange(forDerivativesExchangeId id: String?) -> TradingExchange? {
        guard let id = id?.lowercased() else { return nil }
        switch id {
        case "coinbase":
            return .coinbase
        case "binance":
            return .binance
        case "kucoin":
            return .kucoin
        case "bybit":
            return .bybit
        case "okx":
            return .okx
        case "kraken":
            return .kraken
        case "binance_us", "binanceus":
            return .binanceUS
        default:
            return nil
        }
    }
}
