import SwiftUI
// MARK: - Price Alert Model

/// Types of alert conditions supported
enum AlertConditionType: String, Codable, CaseIterable {
    case priceAbove = "Price Above"
    case priceBelow = "Price Below"
    case percentChangeUp = "% Change Up"
    case percentChangeDown = "% Change Down"
    case rsiAbove = "RSI Above"
    case rsiBelow = "RSI Below"
    case volumeSpike = "Volume Spike"
    case portfolioChange = "Portfolio Change"
    case whaleMovement = "Whale Movement"
    
    var icon: String {
        switch self {
        case .priceAbove: return "arrow.up.circle.fill"
        case .priceBelow: return "arrow.down.circle.fill"
        case .percentChangeUp: return "percent"
        case .percentChangeDown: return "percent"
        case .rsiAbove, .rsiBelow: return "chart.line.uptrend.xyaxis"
        case .volumeSpike: return "chart.bar.fill"
        case .portfolioChange: return "briefcase.fill"
        case .whaleMovement: return "water.waves"
        }
    }
    
    var description: String {
        switch self {
        case .priceAbove: return "Alert when price rises above a threshold"
        case .priceBelow: return "Alert when price drops below a threshold"
        case .percentChangeUp: return "Alert when price increases by X% in Y hours"
        case .percentChangeDown: return "Alert when price decreases by X% in Y hours"
        case .rsiAbove: return "Alert when RSI crosses above a level"
        case .rsiBelow: return "Alert when RSI crosses below a level"
        case .volumeSpike: return "Alert on unusual volume (>2x average)"
        case .portfolioChange: return "Alert when portfolio value changes by X%"
        case .whaleMovement: return "Alert on large wallet movements"
        }
    }
    
    var requiresTimeframe: Bool {
        switch self {
        case .percentChangeUp, .percentChangeDown:
            return true
        default:
            return false
        }
    }
    
    var isAdvanced: Bool {
        switch self {
        case .priceAbove, .priceBelow:
            return false
        default:
            return true
        }
    }
    
    /// Conditions whose backend evaluation is not yet implemented
    var isComingSoon: Bool {
        switch self {
        case .whaleMovement, .portfolioChange:
            return true
        default:
            return false
        }
    }
}

/// Timeframe for percent change alerts
enum AlertTimeframe: Int, Codable, CaseIterable {
    case oneHour = 1
    case fourHours = 4
    case twentyFourHours = 24
    case sevenDays = 168
    
    var displayName: String {
        switch self {
        case .oneHour: return "1 Hour"
        case .fourHours: return "4 Hours"
        case .twentyFourHours: return "24 Hours"
        case .sevenDays: return "7 Days"
        }
    }
}

/// Alert frequency - how often the alert should trigger
enum AlertFrequency: String, Codable, CaseIterable {
    case oneTime = "One-time"
    case onceDaily = "Once per day"
    case always = "Always"
    
    var displayName: String { rawValue }
    
    var description: String {
        switch self {
        case .oneTime: return "Triggers once, then disables"
        case .onceDaily: return "Can trigger once per day"
        case .always: return "Triggers every time condition is met"
        }
    }
    
    var icon: String {
        switch self {
        case .oneTime: return "1.circle.fill"
        case .onceDaily: return "calendar.badge.clock"
        case .always: return "repeat.circle.fill"
        }
    }
}

struct PriceAlert: Identifiable, Codable, Equatable {
    let id: UUID
    let symbol: String
    let threshold: Double
    let isAbove: Bool
    let enablePush: Bool
    let enableEmail: Bool
    let enableTelegram: Bool
    
    // Advanced alert properties
    let conditionType: AlertConditionType
    let timeframe: AlertTimeframe?
    let createdAt: Date
    
    // For whale alerts
    let minWhaleAmount: Double?
    let walletAddress: String?
    
    // For volume alerts
    let volumeMultiplier: Double?
    
    // AI-Enhanced alert features
    let enableSentimentAnalysis: Bool
    let enableSmartTiming: Bool
    let enableAIVolumeSpike: Bool
    
    // Alert frequency (one-time, daily, always)
    let frequency: AlertFrequency
    
    // Last trigger date for frequency tracking
    var lastTriggeredAt: Date?
    
    // Price at the time the alert was created (for accurate progress bars)
    let creationPrice: Double?

    init(id: UUID = UUID(),
         symbol: String,
         threshold: Double,
         isAbove: Bool,
         enablePush: Bool,
         enableEmail: Bool,
         enableTelegram: Bool,
         conditionType: AlertConditionType = .priceAbove,
         timeframe: AlertTimeframe? = nil,
         minWhaleAmount: Double? = nil,
         walletAddress: String? = nil,
         volumeMultiplier: Double? = nil,
         enableSentimentAnalysis: Bool = false,
         enableSmartTiming: Bool = false,
         enableAIVolumeSpike: Bool = false,
         frequency: AlertFrequency = .oneTime,
         lastTriggeredAt: Date? = nil,
         creationPrice: Double? = nil) {
        self.id = id
        self.symbol = symbol
        self.threshold = threshold
        self.isAbove = isAbove
        self.enablePush = enablePush
        self.enableEmail = enableEmail
        self.enableTelegram = enableTelegram
        self.conditionType = conditionType
        self.timeframe = timeframe
        self.createdAt = Date()
        self.minWhaleAmount = minWhaleAmount
        self.walletAddress = walletAddress
        self.volumeMultiplier = volumeMultiplier
        self.enableSentimentAnalysis = enableSentimentAnalysis
        self.enableSmartTiming = enableSmartTiming
        self.enableAIVolumeSpike = enableAIVolumeSpike
        self.frequency = frequency
        self.lastTriggeredAt = lastTriggeredAt
        self.creationPrice = creationPrice
    }
    
    // Migration initializer for legacy alerts
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        symbol = try container.decode(String.self, forKey: .symbol)
        threshold = try container.decode(Double.self, forKey: .threshold)
        isAbove = try container.decode(Bool.self, forKey: .isAbove)
        enablePush = try container.decode(Bool.self, forKey: .enablePush)
        enableEmail = try container.decode(Bool.self, forKey: .enableEmail)
        enableTelegram = try container.decode(Bool.self, forKey: .enableTelegram)
        
        // Handle migration from old alerts without conditionType
        conditionType = (try? container.decode(AlertConditionType.self, forKey: .conditionType)) 
            ?? (isAbove ? .priceAbove : .priceBelow)
        timeframe = try? container.decode(AlertTimeframe.self, forKey: .timeframe)
        createdAt = (try? container.decode(Date.self, forKey: .createdAt)) ?? Date()
        minWhaleAmount = try? container.decode(Double.self, forKey: .minWhaleAmount)
        walletAddress = try? container.decode(String.self, forKey: .walletAddress)
        volumeMultiplier = try? container.decode(Double.self, forKey: .volumeMultiplier)
        
        // AI-Enhanced features (default to false for migration)
        enableSentimentAnalysis = (try? container.decode(Bool.self, forKey: .enableSentimentAnalysis)) ?? false
        enableSmartTiming = (try? container.decode(Bool.self, forKey: .enableSmartTiming)) ?? false
        enableAIVolumeSpike = (try? container.decode(Bool.self, forKey: .enableAIVolumeSpike)) ?? false
        
        // Frequency (default to one-time for migration)
        frequency = (try? container.decode(AlertFrequency.self, forKey: .frequency)) ?? .oneTime
        lastTriggeredAt = try? container.decode(Date.self, forKey: .lastTriggeredAt)
        
        // Creation price (nil for legacy alerts)
        creationPrice = try? container.decode(Double.self, forKey: .creationPrice)
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, symbol, threshold, isAbove, enablePush, enableEmail, enableTelegram
        case conditionType, timeframe, createdAt, minWhaleAmount, walletAddress, volumeMultiplier
        case enableSentimentAnalysis, enableSmartTiming, enableAIVolumeSpike
        case frequency, lastTriggeredAt, creationPrice
    }
    
    /// Whether this alert has any AI features enabled
    var hasAIFeatures: Bool {
        enableSentimentAnalysis || enableSmartTiming || enableAIVolumeSpike
    }
    
    /// Display label for the alert type
    var alertTypeLabel: String {
        if hasAIFeatures {
            return "AI-Enhanced"
        } else if conditionType.isAdvanced {
            return "Advanced"
        } else {
            return "Standard"
        }
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
    let currentPrice: Double?
    let marketCap: Double?
    let marketCapRank: Int?
    let totalVolume: Double?
    let priceChangePercentage1h: Double?
    let priceChangePercentage24h: Double?
    let priceChangePercentage7d: Double?
    let sparklineIn7d: SparklineIn7d?
    let maxSupply: Double?
    let circulatingSupply: Double?
    let totalSupply: Double?

    enum CodingKeys: String, CodingKey {
        case id, symbol, name, image
        case currentPrice = "current_price"
        case marketCap = "market_cap"
        case marketCapRank = "market_cap_rank"
        case totalVolume = "total_volume"
        case priceChangePercentage1h = "price_change_percentage_1h_in_currency"
        case priceChangePercentage24h = "price_change_percentage_24h_in_currency"
        case priceChangePercentage7d = "price_change_percentage_7d_in_currency"
        case priceChangePercentage1hAlt = "price_change_percentage_1h"
        case priceChangePercentage24hAlt = "price_change_percentage_24h"
        case priceChangePercentage7dAlt = "price_change_percentage_7d"
        case sparklineIn7d = "sparkline_in_7d"
        case maxSupply = "max_supply"
        case circulatingSupply = "circulating_supply"
        case totalSupply = "total_supply"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        symbol = try c.decode(String.self, forKey: .symbol)
        name = try c.decode(String.self, forKey: .name)
        image = (try? c.decode(String.self, forKey: .image)) ?? ""
        currentPrice = try? c.decode(Double.self, forKey: .currentPrice)
        marketCap = try? c.decode(Double.self, forKey: .marketCap)
        marketCapRank = try? c.decode(Int.self, forKey: .marketCapRank)
        totalVolume = try? c.decode(Double.self, forKey: .totalVolume)
        // Percent change fields with fallbacks
        if let v = try? c.decode(Double.self, forKey: .priceChangePercentage1h) {
            priceChangePercentage1h = v
        } else {
            priceChangePercentage1h = try? c.decode(Double.self, forKey: .priceChangePercentage1hAlt)
        }
        if let v = try? c.decode(Double.self, forKey: .priceChangePercentage24h) {
            priceChangePercentage24h = v
        } else {
            priceChangePercentage24h = try? c.decode(Double.self, forKey: .priceChangePercentage24hAlt)
        }
        if let v = try? c.decode(Double.self, forKey: .priceChangePercentage7d) {
            priceChangePercentage7d = v
        } else {
            priceChangePercentage7d = try? c.decode(Double.self, forKey: .priceChangePercentage7dAlt)
        }
        sparklineIn7d = try? c.decode(SparklineIn7d.self, forKey: .sparklineIn7d)
        maxSupply = try? c.decodeIfPresent(Double.self, forKey: .maxSupply)
        circulatingSupply = try? c.decodeIfPresent(Double.self, forKey: .circulatingSupply)
        totalSupply = try? c.decodeIfPresent(Double.self, forKey: .totalSupply)
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(symbol, forKey: .symbol)
        try c.encode(name, forKey: .name)
        try c.encode(image, forKey: .image)
        try c.encodeIfPresent(currentPrice, forKey: .currentPrice)
        try c.encodeIfPresent(marketCap, forKey: .marketCap)
        try c.encodeIfPresent(marketCapRank, forKey: .marketCapRank)
        try c.encodeIfPresent(totalVolume, forKey: .totalVolume)
        try c.encodeIfPresent(priceChangePercentage1h, forKey: .priceChangePercentage1h)
        try c.encodeIfPresent(priceChangePercentage24h, forKey: .priceChangePercentage24h)
        try c.encodeIfPresent(priceChangePercentage7d, forKey: .priceChangePercentage7d)
        try c.encodeIfPresent(sparklineIn7d, forKey: .sparklineIn7d)
        try c.encodeIfPresent(maxSupply, forKey: .maxSupply)
        try c.encodeIfPresent(circulatingSupply, forKey: .circulatingSupply)
        try c.encodeIfPresent(totalSupply, forKey: .totalSupply)
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
    var isUser: Bool = false  // Explicit flag for user vs AI message
    /// File path (in Documents) to an attached image for this message, if any. We avoid persisting raw Data in UserDefaults/JSON.
    var imagePath: String? = nil

    // Transient, non-persisted image data (used only at runtime when needed)
    var imageData: Data? = nil
    
    // Transient flag indicating this message is currently being streamed (shows typing cursor)
    var isStreaming: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, sender, text, timestamp, isError, isUser, imagePath
    }
    
    init(id: UUID = UUID(), sender: String, text: String, timestamp: Date = Date(), isError: Bool = false, isUser: Bool? = nil, imagePath: String? = nil, imageData: Data? = nil, isStreaming: Bool = false) {
        self.id = id
        self.sender = sender
        self.text = text
        self.timestamp = timestamp
        self.isError = isError
        // If isUser is not explicitly provided, derive from sender
        self.isUser = isUser ?? (sender.lowercased() == "user")
        self.imagePath = imagePath
        self.imageData = imageData
        self.isStreaming = isStreaming
    }
    
    // Custom decoder for backward compatibility with cached data missing newer fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        sender = try container.decode(String.self, forKey: .sender)
        text = try container.decode(String.self, forKey: .text)
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        isError = try container.decodeIfPresent(Bool.self, forKey: .isError) ?? false
        imagePath = try container.decodeIfPresent(String.self, forKey: .imagePath)
        // Derive isUser from sender if not present in cached JSON
        isUser = try container.decodeIfPresent(Bool.self, forKey: .isUser) ?? (sender.lowercased() == "user")
        // Transient fields - not persisted
        imageData = nil
        isStreaming = false
    }
}

// MARK: - Portfolio Models

/// Asset type for portfolio holdings - supports crypto, traditional securities, and commodities
enum AssetType: String, Codable, CaseIterable {
    case crypto
    case stock
    case etf
    case commodity
    
    var displayName: String {
        switch self {
        case .crypto: return "Crypto"
        case .stock: return "Stock"
        case .etf: return "ETF"
        case .commodity: return "Commodity"
        }
    }
    
    var icon: String {
        switch self {
        case .crypto: return "bitcoinsign.circle.fill"
        case .stock: return "chart.line.uptrend.xyaxis.circle.fill"
        case .etf: return "chart.pie.fill"
        case .commodity: return "scalemass.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .crypto: return .orange
        case .stock: return .blue
        case .etf: return .green
        case .commodity: return .yellow
        }
    }
}

/// Represents a holding in the portfolio (crypto, stock, or ETF).
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
    
    // MARK: - Asset Type Support
    
    /// The type of asset (crypto, stock, or ETF). Defaults to crypto for backward compatibility.
    var assetType: AssetType = .crypto
    
    /// Stock ticker symbol (e.g., "AAPL", "TSLA"). Used for stocks/ETFs.
    var ticker: String?
    
    /// Exchange where the stock is listed (e.g., "NYSE", "NASDAQ").
    var stockExchange: String?
    
    /// Company name for stocks (e.g., "Apple Inc.")
    var companyName: String?
    
    /// ISIN (International Securities Identification Number) for stocks
    var isin: String?
    
    /// Source of this holding (manual, plaid, coinbase, etc.)
    var source: String?

    /// The current value of this holding.
    /// Guarded against NaN/Infinity to prevent corrupted portfolio totals.
    var currentValue: Double {
        let val = quantity * currentPrice
        return val.isFinite ? val : 0
    }
    
    /// The profit or loss for this holding.
    var profitLoss: Double {
        let val = (currentPrice - costBasis) * quantity
        return val.isFinite ? val : 0
    }
    
    /// Profit/loss as a percentage
    var profitLossPercent: Double {
        guard costBasis > 0, costBasis.isFinite else { return 0 }
        guard currentPrice.isFinite else { return 0 }
        let result = ((currentPrice - costBasis) / costBasis) * 100
        return result.isFinite ? result : 0
    }
    
    /// Display name - uses companyName for stocks/commodities if available, otherwise coinName
    var displayName: String {
        if assetType == .stock || assetType == .etf || assetType == .commodity {
            return companyName ?? coinName
        }
        return coinName
    }
    
    /// Display symbol - uses ticker for stocks/commodities if available, otherwise coinSymbol
    var displaySymbol: String {
        if assetType == .stock || assetType == .etf || assetType == .commodity {
            return ticker ?? coinSymbol
        }
        return coinSymbol
    }
    
    /// Number of shares (alias for quantity, used for stocks)
    var shares: Double {
        get { quantity }
        set { quantity = newValue }
    }
    
    // MARK: - Initializers
    
    /// Default initializer for crypto holdings (backward compatible)
    init(id: UUID = UUID(),
         coinName: String,
         coinSymbol: String,
         quantity: Double,
         currentPrice: Double,
         costBasis: Double,
         imageUrl: String? = nil,
         isFavorite: Bool = false,
         dailyChange: Double = 0,
         purchaseDate: Date = Date()) {
        self.id = id
        self.coinName = coinName
        self.coinSymbol = coinSymbol
        self.quantity = quantity
        self.currentPrice = currentPrice
        self.costBasis = costBasis
        self.imageUrl = imageUrl
        self.isFavorite = isFavorite
        self.dailyChange = dailyChange
        self.purchaseDate = purchaseDate
        self.assetType = .crypto
    }
    
    /// Initializer for stock/ETF holdings
    init(id: UUID = UUID(),
         ticker: String,
         companyName: String,
         shares: Double,
         currentPrice: Double,
         costBasis: Double,
         assetType: AssetType,
         stockExchange: String? = nil,
         isin: String? = nil,
         imageUrl: String? = nil,
         isFavorite: Bool = false,
         dailyChange: Double = 0,
         purchaseDate: Date = Date(),
         source: String? = nil) {
        self.id = id
        self.coinName = companyName
        self.coinSymbol = ticker
        self.quantity = shares
        self.currentPrice = currentPrice
        self.costBasis = costBasis
        self.imageUrl = imageUrl
        self.isFavorite = isFavorite
        self.dailyChange = dailyChange
        self.purchaseDate = purchaseDate
        self.assetType = assetType
        self.ticker = ticker
        self.stockExchange = stockExchange
        self.companyName = companyName
        self.isin = isin
        self.source = source
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case id, coinName, coinSymbol, quantity, currentPrice, costBasis
        case imageUrl, isFavorite, dailyChange, purchaseDate
        case assetType, ticker, stockExchange, companyName, isin, source
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        coinName = try container.decode(String.self, forKey: .coinName)
        coinSymbol = try container.decode(String.self, forKey: .coinSymbol)
        quantity = try container.decode(Double.self, forKey: .quantity)
        currentPrice = try container.decode(Double.self, forKey: .currentPrice)
        costBasis = try container.decode(Double.self, forKey: .costBasis)
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        dailyChange = try container.decodeIfPresent(Double.self, forKey: .dailyChange) ?? 0
        purchaseDate = try container.decodeIfPresent(Date.self, forKey: .purchaseDate) ?? Date()
        // New fields with defaults for backward compatibility
        assetType = try container.decodeIfPresent(AssetType.self, forKey: .assetType) ?? .crypto
        ticker = try container.decodeIfPresent(String.self, forKey: .ticker)
        stockExchange = try container.decodeIfPresent(String.self, forKey: .stockExchange)
        companyName = try container.decodeIfPresent(String.self, forKey: .companyName)
        isin = try container.decodeIfPresent(String.self, forKey: .isin)
        source = try container.decodeIfPresent(String.self, forKey: .source)
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
    
    // MARK: - Asset Type Support
    
    /// The type of asset (crypto, stock, or ETF). Defaults to crypto for backward compatibility.
    var assetType: AssetType
    
    /// Stock ticker symbol (e.g., "AAPL"). Used for stocks/ETFs.
    var ticker: String?
    
    /// Company name for stocks (e.g., "Apple Inc.")
    var companyName: String?
    
    /// Transaction fees (if any)
    var fees: Double?
    
    /// Notes for this transaction
    var notes: String?
    
    /// Source of this transaction (manual, plaid, coinbase, etc.)
    var source: String?
    
    /// Total value of the transaction (quantity * pricePerUnit)
    var totalValue: Double {
        quantity * pricePerUnit
    }
    
    /// Total cost including fees
    var totalCost: Double {
        totalValue + (fees ?? 0)
    }
    
    /// Number of shares (alias for quantity, used for stocks)
    var shares: Double {
        quantity
    }
    
    /// Initializes a new Transaction for crypto (backward compatible).
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
        self.assetType = .crypto
    }
    
    /// Initializes a new Transaction for stocks/ETFs.
    init(id: UUID = UUID(),
         ticker: String,
         companyName: String,
         shares: Double,
         pricePerShare: Double,
         date: Date,
         isBuy: Bool,
         assetType: AssetType,
         fees: Double? = nil,
         notes: String? = nil,
         isManual: Bool = true,
         source: String? = nil) {
        self.id = id
        self.coinSymbol = ticker
        self.quantity = shares
        self.pricePerUnit = pricePerShare
        self.date = date
        self.isBuy = isBuy
        self.isManual = isManual
        self.assetType = assetType
        self.ticker = ticker
        self.companyName = companyName
        self.fees = fees
        self.notes = notes
        self.source = source
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case id, coinSymbol, quantity, pricePerUnit, date, isBuy, isManual
        case assetType, ticker, companyName, fees, notes, source
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        coinSymbol = try container.decode(String.self, forKey: .coinSymbol)
        quantity = try container.decode(Double.self, forKey: .quantity)
        pricePerUnit = try container.decode(Double.self, forKey: .pricePerUnit)
        date = try container.decode(Date.self, forKey: .date)
        isBuy = try container.decode(Bool.self, forKey: .isBuy)
        isManual = try container.decodeIfPresent(Bool.self, forKey: .isManual) ?? true
        // New fields with defaults for backward compatibility
        assetType = try container.decodeIfPresent(AssetType.self, forKey: .assetType) ?? .crypto
        ticker = try container.decodeIfPresent(String.self, forKey: .ticker)
        companyName = try container.decodeIfPresent(String.self, forKey: .companyName)
        fees = try container.decodeIfPresent(Double.self, forKey: .fees)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        source = try container.decodeIfPresent(String.self, forKey: .source)
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
// NOTE: The canonical allocation slice type is PortfolioViewModel.AllocationSlice
// (percent on a 0-100 scale). The standalone type below has been removed to avoid
// confusion and accidental misuse.

