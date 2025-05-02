import SwiftUI
// MARK: - Price Alert Model

struct PriceAlert: Identifiable, Codable {
    let id: UUID
    let symbol: String
    let threshold: Double
    let isAbove: Bool
    let enablePush: Bool
    let enableEmail: Bool
    let enableTelegram: Bool

    init(id: UUID = UUID(),
         symbol: String,
         threshold: Double,
         isAbove: Bool,
         enablePush: Bool,
         enableEmail: Bool,
         enableTelegram: Bool) {
        self.id = id
        self.symbol = symbol
        self.threshold = threshold
        self.isAbove = isAbove
        self.enablePush = enablePush
        self.enableEmail = enableEmail
        self.enableTelegram = enableTelegram
    }
}


import Foundation

// MARK: - Coin Models

// MARK: - CoinGecko Markets Model
struct CoinGeckoCoin: Identifiable, Codable {
    let id: String
    let symbol: String
    let name: String
    let image: String
    let currentPrice: Double
    let marketCap: Double
    let marketCapRank: Int
    let totalVolume: Double
    let priceChangePercentage1h: Double?
    let priceChangePercentage24h: Double?
    let priceChangePercentage7d: Double?
    let sparklineIn7d: SparklineIn7d?
    let maxSupply: Double?

    enum CodingKeys: String, CodingKey {
        case id, symbol, name, image
        case currentPrice = "current_price"
        case marketCap = "market_cap"
        case marketCapRank = "market_cap_rank"
        case totalVolume = "total_volume"
        case priceChangePercentage1h = "price_change_percentage_1h_in_currency"
        case priceChangePercentage24h = "price_change_percentage_24h_in_currency"
        case priceChangePercentage7d = "price_change_percentage_7d_in_currency"
        case sparklineIn7d = "sparkline_in_7d"
        case maxSupply = "max_supply"
    }
}

struct TrendingResponse: Codable {
    let coins: [TrendingCoinItem]
}

/// Sparkline data over 7 days from markets endpoint.
struct SparklineIn7d: Codable {
    let price: [Double]
}

struct TrendingCoinItem: Codable {
    let item: CoinGeckoCoin
}

// MARK: - Chat Message Model

/// Represents a single chat message from either the user or the AI.
struct ChatMessage: Identifiable, Codable {
    var id: UUID = UUID()
    var sender: String   // "user" or "ai"
    var text: String
    var timestamp: Date = Date()
    var isError: Bool = false
}

// MARK: - Portfolio Models

/// Represents a cryptocurrency holding in the portfolio.
struct Holding: Identifiable, Codable, Equatable {  // Conforms to Equatable
    var id: UUID = UUID()
    var coinName: String
    var coinSymbol: String
    var quantity: Double
    var currentPrice: Double
    var costBasis: Double
    var imageUrl: String?
    var isFavorite: Bool
    var dailyChange: Double
    /// Percentage change over the last 24 hours.
    var dailyChangePercent: Double {
        dailyChange
    }
    var purchaseDate: Date

    /// The current value of this holding.
    var currentValue: Double {
        return quantity * currentPrice
    }
    
    /// The profit or loss for this holding.
    var profitLoss: Double {
        return (currentPrice - costBasis) * quantity
    }
}

/// Unified Transaction model used in the app to represent both manual and exchange transactions.
struct Transaction: Identifiable, Codable {
    /// Unique identifier for the transaction.
    let id: UUID
    /// The symbol of the cryptocurrency (e.g., "BTC").
    let coinSymbol: String
    /// The quantity of cryptocurrency transacted.
    let quantity: Double
    /// The price per coin at the time of the transaction.
    let pricePerUnit: Double
    /// The date when the transaction occurred.
    let date: Date
    /// Indicates whether this is a buy transaction (true) or a sell (false).
    let isBuy: Bool
    /// Flag indicating if this transaction was manually entered (true) or synced from an exchange/wallet (false).
    let isManual: Bool
    
    /// Initializes a new Transaction.
    /// - Parameters:
    ///   - id: A unique identifier (defaults to a new UUID).
    ///   - coinSymbol: The cryptocurrency symbol.
    ///   - quantity: The quantity of cryptocurrency transacted.
    ///   - pricePerUnit: The price per coin at the time of the transaction.
    ///   - date: The transaction date.
    ///   - isBuy: True for a buy transaction, false for a sell.
    ///   - isManual: True if the transaction is user-entered, false if it’s synced (defaults to true).
    init(id: UUID = UUID(), coinSymbol: String, quantity: Double, pricePerUnit: Double, date: Date, isBuy: Bool, isManual: Bool = true) {
        self.id = id
        self.coinSymbol = coinSymbol
        self.quantity = quantity
        self.pricePerUnit = pricePerUnit
        self.date = date
        self.isBuy = isBuy
        self.isManual = isManual
    }
}

extension CoinGeckoCoin {
    var change1h: Double {
        return priceChangePercentage1h ?? 0.0
    }
    var change24h: Double {
        return priceChangePercentage24h ?? 0.0
    }
    var change7d: Double {
        return priceChangePercentage7d ?? 0.0
    }
}

// MARK: - Allocation Slice Model

/// Represents a single slice of the portfolio pie chart.
struct AllocationSlice: Identifiable {
    /// Unique identifier for SwiftUI lists.
    let id: UUID = UUID()
    /// Symbol for the coin (e.g., "BTC").
    let symbol: String
    /// Percentage of the total portfolio (0.0–1.0).
    let percent: Double
    /// Display color for this slice.
    let color: Color

    /// Initialize with symbol, percent, and color.
    init(symbol: String, percent: Double, color: Color) {
        self.symbol = symbol
        self.percent = percent
        self.color = color
    }
}
