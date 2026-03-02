//
//  FirebaseService.swift
//  CryptoSage
//
//  Created for CryptoSage AI backend integration.
//
//  Provides a Swift wrapper for Firebase Cloud Functions,
//  enabling secure API calls and shared AI content caching.
//

import Foundation
import Combine

// MARK: - Firebase Response Types

/// Response from market sentiment AI function
/// Enhanced with computed sentiment score and key factors
struct MarketSentimentResponse: Codable {
    let content: String              // AI-generated full analysis text (2-3 sentences)
    let summary: String?             // Short summary for card display (1 sentence, ~15 words)
    let score: Int?                  // 0-100 sentiment score (0=Extreme Fear, 100=Extreme Greed)
    let verdict: String?             // "Extreme Fear", "Fear", "Neutral", "Greed", "Extreme Greed"
    let confidence: Int?             // 0-100 confidence level
    let keyFactors: [String]?        // Key factors driving sentiment (2-4 short phrases)
    let cached: Bool
    let updatedAt: String
    let stale: Bool?
    let model: String?               // "gpt-4o" or "gpt-4o-mini" - for analytics tracking
    
    /// Returns the short summary for card display, with fallback to first sentence of content
    var displaySummary: String {
        if let summary = summary, !summary.isEmpty {
            return summary
        }
        // Fallback: extract first sentence from content
        let firstSentence = content.components(separatedBy: ".").first ?? content
        return firstSentence.trimmingCharacters(in: .whitespaces) + (firstSentence.hasSuffix(".") ? "" : ".")
    }
}

/// Response from coin insight AI function
struct CoinInsightResponse: Codable {
    let content: String
    let technicalSummary: String?
    let cached: Bool
    let updatedAt: String
    let model: String? // "gpt-4o" or "gpt-4o-mini" - for analytics tracking
}

/// Response from price prediction AI function
struct PricePredictionResponse: Codable {
    let prediction: String // "bullish", "bearish", "neutral"
    let confidence: Int
    let priceRange: PriceRange?
    let reasoning: String
    let cached: Bool
    let model: String? // "gpt-4o" or "gpt-4o-mini" - for analytics tracking
    let updatedAt: String
    
    struct PriceRange: Codable {
        let low: Double
        let high: Double
    }
}

/// Response from AI trading signal function
/// Shared across all users for the same coin - first request triggers AI, others get cached
struct TradingSignalResponse: Codable {
    let signal: String              // "BUY", "SELL", "HOLD"
    let confidence: String          // "High", "Medium", "Low"
    let confidenceScore: Int        // 10-90
    let reasoning: String           // AI natural language analysis
    let keyFactors: [String]        // Key technical reasons
    let sentimentScore: Double      // -1.0 to 1.0
    let riskLevel: String           // "Low", "Medium", "High"
    let cached: Bool
    let updatedAt: String
    let model: String?              // AI model used
}

/// Response from Fear & Greed commentary function
struct FearGreedCommentaryResponse: Codable {
    let commentary: String
    let cached: Bool
    let updatedAt: String
    let model: String? // "gpt-4o" or "gpt-4o-mini" - for analytics tracking
}

/// DeepSeek consultation analysis result
struct DeepSeekConsultation: Codable {
    let direction: String?                  // "bullish", "bearish", "neutral"
    let confidence: Int?                    // 1-100
    let shortTermOutlook: String?           // Next 24-48h
    let mediumTermOutlook: String?          // Next 1-2 weeks
    let keyLevels: DeepSeekKeyLevels?       // Support/resistance
    let risks: [String]?                    // Top risks
    let reasoning: String?                  // 2-3 sentence analysis
    let suggestedAction: String?            // Actionable recommendation
}

/// Key support/resistance levels from DeepSeek
struct DeepSeekKeyLevels: Codable {
    let support: [Double]?
    let resistance: [Double]?
}

/// Response from the consultDeepSeek Firebase function
struct DeepSeekConsultationResponse: Codable {
    let consultation: DeepSeekConsultation?
    let cached: Bool?
    let model: String?
    let reason: String?                     // "no_query_or_coins", "error", etc.
}

/// Response from price movement explanation function (Why is it moving?)
/// Shared across all users for the same coin - first request triggers AI, others get cached
struct PriceMovementExplanationResponse: Codable {
    let summary: String                    // 1-2 sentence explanation
    let reasons: [MovementReason]          // Array of possible reasons
    let btcChange24h: Double?              // Market context
    let ethChange24h: Double?              // Market context
    let fearGreedIndex: Int?               // Market sentiment
    let isMarketWideMove: Bool             // Whether this is correlated with market
    let cached: Bool
    let updatedAt: String
    let model: String?
    
    struct MovementReason: Codable {
        let category: String               // "news", "whale", "technical", "sentiment", "market", etc.
        let title: String
        let description: String
        let confidence: String             // "high", "medium", "low"
        let impact: String                 // "positive", "negative", "neutral"
    }
}

/// Response from portfolio insight function
struct PortfolioInsightResponse: Codable {
    let content: String
    let cached: Bool
    let usageRemaining: Int?
    let model: String? // "gpt-4o-mini" for personalized content
}

/// Response from CryptoSage AI Sentiment calculation
/// Real-time market sentiment computed server-side for consistency across all users
struct CryptoSageAISentimentResponse: Codable {
    let score: Int                  // 0-100 sentiment score
    let verdict: String             // "Extreme Fear", "Fear", "Neutral", "Greed", "Extreme Greed"
    let breadth: Int                // Market breadth (% of coins positive)
    let btc24h: Double              // BTC 24h change %
    let btc7d: Double               // BTC 7d change %
    let altMedian: Double           // Altcoin median 24h change %
    let volatility: Double          // Market volatility/dispersion
    let cached: Bool
    let updatedAt: String
    
    // Historical sentiment values (Firebase-stored, shared across all users)
    let yesterday: HistoricalSentiment?   // Score from 1 day ago
    let lastWeek: HistoricalSentiment?    // Score from 7 days ago
    let lastMonth: HistoricalSentiment?   // Score from 30 days ago
    
    /// Historical sentiment data point
    struct HistoricalSentiment: Codable {
        let score: Int
        let verdict: String
    }
}

/// Response from CoinGecko markets proxy
struct CoinGeckoMarketsResponse: Codable {
    let coins: [[String: AnyCodable]]
    let cached: Bool
    let stale: Bool?
    let updatedAt: String
}

/// Response from CoinGecko global proxy
struct CoinGeckoGlobalResponse: Codable {
    let global: [String: AnyCodable]
    let cached: Bool
    let stale: Bool?
    let updatedAt: String
}

/// Response from Binance 24hr tickers proxy
struct BinanceTickersResponse: Codable {
    let tickers: [[String: AnyCodable]]
    let cached: Bool
    let stale: Bool?
    let updatedAt: String
}

/// Response from order book depth proxy function
/// Provides order book data shared across all users (prevents rate limiting)
struct OrderBookDepthResponse: Codable {
    let symbol: String
    let bids: [[String]]        // [[price, qty], ...]
    let asks: [[String]]        // [[price, qty], ...]
    let lastUpdateId: Int?
    let timestamp: Int
    let cached: Bool
    let stale: Bool?
    let ageMs: Int?
    let source: String?         // "binance.us", "binance.com", "coinbase", "kraken", "kucoin"
}

/// Response from chart data cache function
/// Provides OHLCV candlestick data shared across all users
struct ChartDataResponse: Codable {
    let symbol: String
    let interval: String
    let points: [ChartCandlePoint]
    let cached: Bool
    let stale: Bool?
    let updatedAt: String
    let source: String?
    
    /// Individual candle data point
    struct ChartCandlePoint: Codable {
        let t: Double  // Timestamp (milliseconds)
        let o: Double  // Open
        let h: Double  // High
        let l: Double  // Low
        let c: Double  // Close
        let v: Double  // Volume
        
        /// Convert timestamp to Date
        var date: Date {
            Date(timeIntervalSince1970: t / 1000)
        }
    }
}

/// Response from CoinGecko chart data cache function
/// Provides historical price/volume data for long timeframes (3Y, ALL)
struct CoinGeckoChartDataResponse: Codable {
    let coinId: String
    let days: AnyCodable  // Can be Int or "max"
    let prices: [PricePoint]
    let volumes: [VolumePoint]
    let cached: Bool
    let stale: Bool?
    let updatedAt: String
    
    struct PricePoint: Codable {
        let t: Double  // Timestamp (milliseconds)
        let p: Double  // Price
        
        var date: Date {
            Date(timeIntervalSince1970: t / 1000)
        }
    }
    
    struct VolumePoint: Codable {
        let t: Double  // Timestamp (milliseconds)
        let v: Double  // Volume
        
        var date: Date {
            Date(timeIntervalSince1970: t / 1000)
        }
    }
}

/// Response from commodity prices proxy
struct CommodityPricesResponse: Codable {
    let prices: [CommodityPrice]
    let cached: Bool
    let stale: Bool?
    let coalesced: Bool?
    let updatedAt: String
    
    struct CommodityPrice: Codable {
        let symbol: String
        let name: String
        let price: Double
        let changePercent: Double?
        let previousClose: Double?
        let open: Double?
        let high: Double?
        let low: Double?
        let volume: Double?
    }
}

/// Response from stock quotes Firebase proxy
/// Provides shared stock price data via Yahoo Finance through Firebase, avoiding client-side rate limits
struct StockQuotesResponse: Codable {
    let quotes: [StockQuoteData]
    let cached: Bool
    let stale: Bool?
    let coalesced: Bool?
    let updatedAt: String
    
    struct StockQuoteData: Codable {
        let symbol: String
        let name: String
        let price: Double
        let change: Double?
        let changePercent: Double?
        let previousClose: Double?
        let open: Double?
        let high: Double?
        let low: Double?
        let volume: Double?
        let marketCap: Double?
        let quoteType: String?
        let exchange: String?
        let currency: String?
    }
}

/// Response from stock sparkline history proxy
/// Provides shared historical close series for stocks/ETFs/commodities.
struct StockSparklinesResponse: Codable {
    let sparklines: [SparklineData]?
    let series: [SparklineData]?
    let data: [SparklineData]?
    let cached: Bool?
    let stale: Bool?
    let coalesced: Bool?
    let updatedAt: String?
    
    struct SparklineData: Codable {
        let symbol: String
        let prices: [Double]?
        let close: [Double]?
        let points: [Double]?
        
        var values: [Double] {
            prices ?? close ?? points ?? []
        }
    }
    
    var entries: [SparklineData] {
        sparklines ?? series ?? data ?? []
    }
}

/// Response from whale transactions proxy
/// Provides whale transaction data from Etherscan, Blockchair, Solscan
struct WhaleTransactionsResponse: Codable {
    let transactions: [WhaleTransactionData]
    let cached: Bool
    let stale: Bool?
    let coalesced: Bool?
    let updatedAt: String
    
    struct WhaleTransactionData: Codable {
        let id: String
        let blockchain: String
        let symbol: String
        let amount: Double
        let amountUSD: Double
        let fromAddress: String
        let toAddress: String
        let hash: String
        let timestamp: Int64
        let transactionType: String
        let dataSource: String
        let fromLabel: String?
        let toLabel: String?
        
        /// Convert timestamp to Date
        var date: Date {
            Date(timeIntervalSince1970: Double(timestamp) / 1000.0)
        }
    }
}

/// Response from upcoming events proxy
/// Provides crypto calendar events from CoinMarketCal and curated sources
struct UpcomingEventsResponse: Codable {
    let events: [CryptoEventData]
    let cached: Bool
    let stale: Bool?
    let coalesced: Bool?
    let updatedAt: String
    
    struct CryptoEventData: Codable {
        let id: String
        let title: String
        let date: String
        let category: String
        let impact: String
        let subtitle: String?
        let urlString: String?
        let coinSymbols: [String]
        let source: String
        
        /// Convert date string to Date
        var eventDate: Date? {
            let formatters = [
                ISO8601DateFormatter(),
            ]
            
            for formatter in formatters {
                if let date = formatter.date(from: self.date) {
                    return date
                }
            }
            
            // Try standard date formats
            let dateFormatter = DateFormatter()
            for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd"] {
                dateFormatter.dateFormat = format
                if let date = dateFormatter.date(from: self.date) {
                    return date
                }
            }
            
            return nil
        }
        
        /// URL if available
        var url: URL? {
            guard let s = urlString else { return nil }
            return URL(string: s)
        }
    }
}

/// Response from leaderboard proxy
struct LeaderboardResponse: Codable {
    let entries: [LeaderboardEntryData]
    let cached: Bool
    let message: String?
    let updatedAt: String
    
    struct LeaderboardEntryData: Codable {
        let userId: String
        let username: String
        let displayName: String
        let avatarURL: String?
        let rank: Int
        let score: Double
        let pnl: Double
        let pnlPercent: Double
        let winRate: Double
        let totalTrades: Int
        let tradingMode: String
    }
}

/// Response from Pump.fun meme coin proxy
/// Provides trending and recently launched meme coins from Solana
struct PumpFunTokensResponse: Codable {
    let tokens: [PumpFunTokenData]
    let type: String  // "recent", "trending", "graduated"
    let cached: Bool
    let stale: Bool?
    let updatedAt: String
    
    struct PumpFunTokenData: Codable {
        let mint: String
        let name: String
        let symbol: String
        let description: String?
        let imageUri: String?
        let createdTimestamp: Int64
        let marketCapSol: Double?
        let usdMarketCap: Double?
        let replyCount: Int?
        let lastReply: Int64?
        let creator: String?
        let raydiumPool: String?
        let complete: Bool?
        let isGraduated: Bool?
        
        /// Convert timestamp to Date
        var createdDate: Date {
            Date(timeIntervalSince1970: Double(createdTimestamp) / 1000.0)
        }
        
        /// Image URL if available
        var imageURL: URL? {
            guard let uri = imageUri else { return nil }
            return URL(string: uri)
        }
    }
}

/// Response from technical analysis summary function
/// Professional-grade technical analysis with 30+ indicators
/// CryptoSage source includes exclusive advanced features
struct TechnicalsSummaryResponse: Codable {
    // Core scores
    let score: Double           // 0-1 aggregate weighted score
    let verdict: String         // "Strong Sell", "Sell", "Neutral", "Buy", "Strong Buy"
    let confidence: Int?        // 0-100 confidence level based on indicator agreement
    let trendStrength: String?  // "Ranging", "Weak", "Moderate", "Strong", "Very Strong"
    let volatilityRegime: String? // "Low", "Normal", "High", "Extreme"
    
    // Context
    let symbol: String?         // Optional - may be added by iOS when missing
    let interval: String?       // Optional - may be added by iOS when missing
    let source: String?         // "cryptosage", "coinbase", "binance" - optional for backward compat
    let cached: Bool?
    let updatedAt: String?
    let indicatorCount: Int?    // Number of indicators used
    let stale: Bool?            // Whether data is from stale cache
    let coalesced: Bool?        // Whether request was coalesced
    
    /// Safe accessor for source with default value
    var effectiveSource: String {
        source ?? "unknown"
    }
    
    // Individual indicators
    let rsi: Double?
    let macd: MACDData?
    let stochastic: StochasticData?
    let ichimoku: IchimokuData?
    let bollingerBands: BollingerData?
    let hma: Double?            // Hull Moving Average
    let vwma: Double?           // Volume Weighted MA
    
    // CryptoSage-exclusive advanced indicators
    let parabolicSar: ParabolicSARData?
    let supertrend: SupertrendData?
    let divergences: DivergenceData?
    
    // CryptoSage-exclusive AI summary
    let aiSummary: String?      // AI-generated analysis text
    
    // Moving averages
    let sma: SMAData?
    let ema: EMAData?
    
    // Key levels
    let pivotPoints: PivotPointsData?
    let supportResistance: SupportResistanceData?
    
    // Detailed signals
    let signals: [IndicatorSignalData]?
    let maSummary: SignalSummary?
    let oscSummary: SignalSummary?
    
    // CryptoSage-exclusive indicator types
    struct ParabolicSARData: Codable {
        let value: Double?
        let trend: String?        // "bullish", "bearish"
        let reversalNear: Bool?   // Price close to SAR
    }
    
    struct SupertrendData: Codable {
        let value: Double?
        let trend: String?        // "bullish", "bearish"
        let trendDuration: Int?   // Bars since last trend change
    }
    
    struct DivergenceData: Codable {
        let rsiDivergence: String?   // "bullish", "bearish", "none"
        let macdDivergence: String?  // "bullish", "bearish", "none"
        let stochDivergence: String? // "bullish", "bearish", "none"
        let overallDivergence: String? // "bullish", "bearish", "none"
        let strength: String?        // "weak", "moderate", "strong"
    }
    
    struct MACDData: Codable {
        let macd: Double
        let signal: Double
        let histogram: Double
        let trend: String?  // "bullish", "bearish", "neutral"
    }
    
    struct StochasticData: Codable {
        let k: Double
        let d: Double
        let signal: String?  // "overbought", "oversold", "neutral"
    }
    
    struct IchimokuData: Codable {
        let tenkan: Double?
        let kijun: Double?
        let senkouA: Double?
        let senkouB: Double?
        let cloudTop: Double?
        let cloudBottom: Double?
        let priceVsCloud: String?  // "above", "below", "inside"
        let signal: String?        // "bullish", "bearish", "neutral"
    }
    
    struct BollingerData: Codable {
        let upper: Double?
        let middle: Double?
        let lower: Double?
        let bandwidth: Double?
        let percentB: Double?  // Where price is relative to bands (0-1)
    }
    
    struct SMAData: Codable {
        let sma10: Double?
        let sma20: Double?
        let sma30: Double?
        let sma50: Double?
        let sma100: Double?
        let sma200: Double?
    }
    
    struct EMAData: Codable {
        let ema10: Double?
        let ema20: Double?
        let ema30: Double?
        let ema50: Double?
        let ema100: Double?
        let ema200: Double?
    }
    
    struct PivotPointsData: Codable {
        let pivot: Double?
        let r1: Double?
        let r2: Double?
        let r3: Double?
        let s1: Double?
        let s2: Double?
        let s3: Double?
    }
    
    struct SupportResistanceData: Codable {
        let support: [Double]?
        let resistance: [Double]?
    }
    
    struct IndicatorSignalData: Codable {
        let name: String
        let category: String?  // "oscillator", "ma", "trend", "volume", "volatility"
        let signal: String     // "strong_sell", "sell", "neutral", "buy", "strong_buy"
        let value: String
        let weight: Int?       // 1-3 based on reliability
    }
    
    struct SignalSummary: Codable {
        let strongSell: Int?
        let sell: Int?
        let neutral: Int?
        let buy: Int?
        let strongBuy: Int?
    }
}

/// Individual Binance ticker data (parsed from response)
struct BinanceTicker {
    let symbol: String
    let lastPrice: Double
    let priceChangePercent: Double
    let volume: Double
    let quoteVolume: Double
    
    init?(from dict: [String: AnyCodable]) {
        guard let symbol = dict["symbol"]?.value as? String else { return nil }
        self.symbol = symbol
        self.lastPrice = Double(dict["lastPrice"]?.value as? String ?? "") ?? 0
        self.priceChangePercent = Double(dict["priceChangePercent"]?.value as? String ?? "") ?? 0
        self.volume = Double(dict["volume"]?.value as? String ?? "") ?? 0
        self.quoteVolume = Double(dict["quoteVolume"]?.value as? String ?? "") ?? 0
    }
}

// MARK: - Firebase Error Types

enum FirebaseServiceError: LocalizedError {
    case notConfigured
    case networkError(String)
    case authenticationRequired
    case rateLimitExceeded
    case serverError(String)
    case decodingError(String)
    case functionNotFound(String)  // 404 - function not deployed
    
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Firebase is not configured. Please check your GoogleService-Info.plist"
        case .networkError(let message):
            return "Network error: \(message)"
        case .authenticationRequired:
            return "Authentication required for this feature"
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please try again later."
        case .serverError(let message):
            return "Server error: \(message)"
        case .decodingError(let message):
            return "Failed to parse response: \(message)"
        case .functionNotFound(let name):
            return "Function '\(name)' not found. Please check deployment."
        }
    }
}

// MARK: - Firebase Service

/// Main service for interacting with Firebase Cloud Functions
/// Handles all server-side AI features and data caching
@MainActor
final class FirebaseService: ObservableObject {
    static let shared = FirebaseService()
    
    // MARK: - Configuration
    
    /// Firebase Cloud Functions base URL
    /// Replace with your actual project URL after deploying
    private var functionsBaseURL: String {
        // Check for custom URL in UserDefaults (for testing)
        if let customURL = UserDefaults.standard.string(forKey: "FirebaseFunctionsURL"),
           !customURL.isEmpty {
            return customURL
        }
        
        // Default to production URL
        // Format: https://{region}-{project-id}.cloudfunctions.net
        return "https://us-central1-cryptosage-ai.cloudfunctions.net"
    }
    
    /// Whether Firebase is configured and available
    @Published private(set) var isConfigured: Bool = false
    
    /// Current Firebase Auth user ID (if signed in)
    @Published private(set) var currentUserId: String? = nil
    
    /// Firebase Auth ID token for authenticated requests
    private var authToken: String? = nil
    
    // MARK: - Cache
    
    /// Local cache for responses to reduce network calls
    private var localCache: [String: (data: Data, timestamp: Date)] = [:]
    private let defaultLocalCacheDuration: TimeInterval = 300 // 5 minutes
    
    // MARK: - Initialization
    
    private init() {
        checkConfiguration()
    }
    
    /// Check if Firebase is properly configured
    private func checkConfiguration() {
        // Check if GoogleService-Info.plist exists
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            isConfigured = true
            #if DEBUG
            print("[FirebaseService] Firebase configured successfully")
            #endif
        } else {
            isConfigured = false
            #if DEBUG
            print("[FirebaseService] WARNING: GoogleService-Info.plist not found - Firebase features disabled")
            #endif
        }
    }
    
    /// Set the current user's auth token (called after Apple Sign-In)
    func setAuthToken(_ token: String?, userId: String?) {
        self.authToken = token
        self.currentUserId = userId
    }
    
    /// Clear auth state on sign out
    func clearAuth() {
        self.authToken = nil
        self.currentUserId = nil
    }
    
    // MARK: - Shared AI Features (No Auth Required)
    
    /// Get market sentiment AI analysis (shared across all users)
    func getMarketSentiment() async throws -> MarketSentimentResponse {
        return try await callFunction(
            name: "getMarketSentiment",
            data: [:],
            responseType: MarketSentimentResponse.self
        )
    }
    
    /// Get CryptoSage AI Sentiment score (shared across all users)
    /// This provides a consistent sentiment score calculated server-side from live market data.
    /// All users see the same score at any given time.
    func getCryptoSageAISentiment() async throws -> CryptoSageAISentimentResponse {
        return try await callFunction(
            name: "getCryptoSageAISentiment",
            data: [:],
            responseType: CryptoSageAISentimentResponse.self
        )
    }
    
    /// Get AI insight for a specific coin (shared across all users)
    /// - Parameter assetType: Optional asset type hint (e.g., "commodity", "stock", "crypto").
    ///   When provided, the backend can tailor its prompt so the AI doesn't misinterpret
    ///   commodities or stocks as cryptocurrency tokens.
    func getCoinInsight(
        coinId: String,
        coinName: String?,
        symbol: String,
        price: Double?,
        change24h: Double?,
        change7d: Double?,
        marketCap: Double?,
        volume24h: Double?,
        assetType: String? = nil
    ) async throws -> CoinInsightResponse {
        var data: [String: Any] = [
            "coinId": coinId,
            "coinName": coinName ?? symbol,
            "symbol": symbol,
            "price": price ?? 0,
            "change24h": change24h ?? 0,
            "change7d": change7d ?? 0,
            "marketCap": marketCap ?? 0,
            "volume24h": volume24h ?? 0
        ]
        
        // Include asset type when provided so the AI prompt can distinguish
        // commodities / stocks from crypto tokens
        if let assetType = assetType {
            data["assetType"] = assetType
        }
        
        return try await callFunction(
            name: "getCoinInsight",
            data: data,
            responseType: CoinInsightResponse.self
        )
    }
    
    /// Get AI explanation for why a coin is moving (shared across all users)
    /// First user triggers AI generation, subsequent users get cached result
    /// Cache key: {symbol}_{hourBucket} - explanations cached for ~2 hours
    func getPriceMovementExplanation(
        symbol: String,
        coinName: String,
        currentPrice: Double,
        change24h: Double,
        change7d: Double,
        volume24h: Double,
        btcChange24h: Double?,
        ethChange24h: Double?,
        fearGreedIndex: Int?,
        smartMoneyScore: Int?,
        exchangeFlowSentiment: String?,
        marketRegime: String?
    ) async throws -> PriceMovementExplanationResponse {
        var data: [String: Any] = [
            "symbol": symbol.uppercased(),
            "coinName": coinName,
            "currentPrice": currentPrice,
            "change24h": change24h,
            "change7d": change7d,
            "volume24h": volume24h
        ]
        
        // Add optional market context
        if let btc = btcChange24h { data["btcChange24h"] = btc }
        if let eth = ethChange24h { data["ethChange24h"] = eth }
        if let fgi = fearGreedIndex { data["fearGreedIndex"] = fgi }
        if let smi = smartMoneyScore { data["smartMoneyScore"] = smi }
        if let flow = exchangeFlowSentiment { data["exchangeFlowSentiment"] = flow }
        if let regime = marketRegime { data["marketRegime"] = regime }
        
        return try await callFunction(
            name: "getPriceMovementExplanation",
            data: data,
            responseType: PriceMovementExplanationResponse.self
        )
    }
    
    /// Get AI price prediction for a coin (shared across all users)
    func getPricePrediction(
        coinId: String,
        symbol: String,
        timeframe: String, // "24h", "7d", "30d"
        currentPrice: Double?,
        technicalIndicators: [String: Any]?,
        fearGreedIndex: Int?
    ) async throws -> PricePredictionResponse {
        var data: [String: Any] = [
            "coinId": coinId,
            "symbol": symbol,
            "timeframe": timeframe,
            "currentPrice": currentPrice ?? 0
        ]
        
        if let indicators = technicalIndicators {
            data["technicalIndicators"] = indicators
        }
        if let fgi = fearGreedIndex {
            data["fearGreedIndex"] = fgi
        }
        
        return try await callFunction(
            name: "getPricePrediction",
            data: data,
            responseType: PricePredictionResponse.self
        )
    }
    
    // MARK: - AI Trading Signal
    
    /// Get AI-powered trading signal for a coin (BUY/SELL/HOLD)
    /// Shared across all users - cached in Firestore for 30 minutes
    func getTradingSignal(
        coinId: String,
        symbol: String,
        currentPrice: Double?,
        change24h: Double?,
        change7d: Double?,
        technicalIndicators: [String: Any]?,
        fearGreedIndex: Int?
    ) async throws -> TradingSignalResponse {
        var data: [String: Any] = [
            "coinId": coinId,
            "symbol": symbol,
        ]
        
        if let price = currentPrice {
            data["currentPrice"] = price
        }
        if let c24h = change24h {
            data["change24h"] = c24h
        }
        if let c7d = change7d {
            data["change7d"] = c7d
        }
        if let indicators = technicalIndicators {
            data["technicalIndicators"] = indicators
        }
        if let fgi = fearGreedIndex {
            data["fearGreedIndex"] = fgi
        }
        
        return try await callFunction(
            name: "getTradingSignal",
            data: data,
            responseType: TradingSignalResponse.self
        )
    }
    
    /// Response from recording a prediction outcome
    struct RecordPredictionOutcomeResponse: Codable {
        let success: Bool
        let outcomeId: String?
        let message: String?
        let targetDate: String?
    }
    
    /// Record a prediction outcome for global accuracy tracking
    /// Called when a user views a prediction - enables system-wide learning
    /// Note: This is fire-and-forget, failures are silent to not impact UX
    func recordPredictionOutcome(
        coinId: String,
        symbol: String,
        timeframe: String,
        direction: String,
        confidence: Int,
        priceAtPrediction: Double,
        priceLow: Double?,
        priceHigh: Double?
    ) async {
        // Fire and forget - don't block on accuracy tracking
        do {
            var data: [String: Any] = [
                "coinId": coinId,
                "symbol": symbol,
                "timeframe": timeframe,
                "direction": direction,
                "confidence": confidence,
                "priceAtPrediction": priceAtPrediction
            ]
            
            if let low = priceLow {
                data["priceLow"] = low
            }
            if let high = priceHigh {
                data["priceHigh"] = high
            }
            
            let _: RecordPredictionOutcomeResponse = try await callFunction(
                name: "recordPredictionOutcome",
                data: data,
                responseType: RecordPredictionOutcomeResponse.self
            )
            
            #if DEBUG
            print("[FirebaseService] Prediction outcome recorded for \(symbol) \(timeframe)")
            #endif
        } catch {
            // Silent failure - don't impact user experience for analytics
            #if DEBUG
            print("[FirebaseService] Failed to record prediction outcome: \(error.localizedDescription)")
            #endif
        }
    }
    
    /// Response from global accuracy metrics
    struct GlobalAccuracyMetricsResponse: Codable {
        let totalPredictions: Int
        let directionsCorrect: Int?
        let withinRangeCount: Int?
        let directionAccuracyPercent: Double
        let rangeAccuracyPercent: Double
        let averageError: Double
        let timeframeAccuracy: [String: Double]?
        let directionBreakdown: [String: Double]?
        let confidenceAccuracy: [String: Double]?
        let hasData: Bool
        let lastUpdated: String
    }
    
    /// Fetch global accuracy metrics from Firebase
    /// Returns aggregated accuracy data from all users' predictions
    func getGlobalAccuracyMetrics() async throws -> GlobalAccuracyMetricsResponse {
        return try await callFunction(
            name: "getGlobalAccuracyMetrics",
            data: [:],
            responseType: GlobalAccuracyMetricsResponse.self
        )
    }
    
    // MARK: - DeepSeek Consultation (Multi-AI)
    
    /// Consult DeepSeek for crypto-specific analysis to augment ChatGPT responses.
    /// This is the "multi-AI consultation" bridge — ChatGPT calls this before responding
    /// to financial queries so it can incorporate DeepSeek's crypto-specialist opinion.
    ///
    /// Returns nil consultation if DeepSeek is unavailable or the query doesn't need it.
    /// This is non-blocking and gracefully degrades — ChatGPT can always proceed without it.
    func consultDeepSeek(
        query: String,
        coins: [[String: Any]],
        marketContext: String = ""
    ) async -> DeepSeekConsultationResponse? {
        do {
            let data: [String: Any] = [
                "query": String(query.prefix(500)),
                "coins": coins,
                "marketContext": String(marketContext.prefix(1000))
            ]
            
            let response: DeepSeekConsultationResponse = try await callFunction(
                name: "consultDeepSeek",
                data: data,
                responseType: DeepSeekConsultationResponse.self
            )
            
            return response
        } catch {
            // DeepSeek consultation is non-critical — fail silently
            #if DEBUG
            print("[FirebaseService] DeepSeek consultation failed: \(error.localizedDescription)")
            #endif
            return nil
        }
    }
    
    /// Get Fear & Greed AI commentary (shared across all users)
    func getFearGreedCommentary(value: Int, classification: String?) async throws -> FearGreedCommentaryResponse {
        var data: [String: Any] = ["value": value]
        if let classification = classification {
            data["classification"] = classification
        }
        
        return try await callFunction(
            name: "getFearGreedCommentary",
            data: data,
            responseType: FearGreedCommentaryResponse.self
        )
    }
    
    /// Get technical analysis summary (shared across all users)
    /// Returns pre-computed indicators from Firebase for consistent cross-user data
    /// DEPRECATED: Use getTechnicalsFromSource for source-specific analysis
    func getTechnicalsSummary(symbol: String, interval: String) async throws -> TechnicalsSummaryResponse {
        let data: [String: Any] = [
            "symbol": symbol,
            "interval": interval
        ]
        
        return try await callFunction(
            name: "getTechnicalsSummary",
            data: data,
            responseType: TechnicalsSummaryResponse.self
        )
    }
    
    /// Get technical analysis from any source with shared caching
    /// Routes all sources (CryptoSage, Coinbase, Binance) through Firebase
    /// - CryptoSage: 30+ indicators with AI summary and divergence detection
    /// - Coinbase/Binance: Basic 15 indicator analysis
    /// All sources use shared Firestore caching for consistency across users
    func getTechnicalsFromSource(symbol: String, interval: String, source: String) async throws -> TechnicalsSummaryResponse {
        let data: [String: Any] = [
            "symbol": symbol,
            "interval": interval,
            "source": source  // "cryptosage", "coinbase", or "binance"
        ]
        
        #if DEBUG
        print("[FirebaseService] getTechnicalsFromSource: symbol=\(symbol), interval=\(interval), source=\(source)")
        #endif
        
        return try await callFunction(
            name: "getTechnicalsFromSource",
            data: data,
            responseType: TechnicalsSummaryResponse.self
        )
    }
    
    // MARK: - AI Chat (Works for All Users)
    
    /// Chat response from Firebase
    struct ChatResponse: Codable {
        let response: String
        let model: String?
        let tokens: Int?
    }
    
    /// Send a chat message through Firebase backend
    /// This works for ALL users - no local API key required
    func sendChatMessage(
        message: String,
        history: [[String: String]]? = nil,
        systemPrompt: String? = nil
    ) async throws -> ChatResponse {
        guard isConfigured else {
            #if DEBUG
            print("[FirebaseService] sendChatMessage failed: not configured")
            #endif
            throw FirebaseServiceError.notConfigured
        }
        
        var data: [String: Any] = ["message": message]
        
        if let history = history {
            data["history"] = history
        }
        
        // Include system prompt with portfolio/market context
        if let systemPrompt = systemPrompt {
            data["systemPrompt"] = systemPrompt
        }
        
        do {
            let response = try await callFunction(
                name: "sendChatMessage",
                data: data,
                responseType: ChatResponse.self
            )
            #if DEBUG
            print("[FirebaseService] sendChatMessage succeeded (response: \(response.response.prefix(60))...)")
            #endif
            return response
        } catch {
            #if DEBUG
            print("[FirebaseService] sendChatMessage failed: \(error.localizedDescription)")
            #endif
            throw error
        }
    }
    
    /// Send a chat message with streaming response
    /// Uses Server-Sent Events for real-time streaming
    func streamChatMessage(
        message: String,
        history: [[String: String]]? = nil,
        systemPrompt: String? = nil,
        onChunk: @escaping (String) -> Void
    ) async throws -> String {
        guard isConfigured else {
            throw FirebaseServiceError.notConfigured
        }
        
        // Build the streaming endpoint URL
        let streamURL = "\(functionsBaseURL)/streamChatMessage"
        guard let url = URL(string: streamURL) else {
            throw FirebaseServiceError.networkError("Invalid URL")
        }
        
        // Build request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(Bundle.main.bundleIdentifier ?? "com.cryptosage", forHTTPHeaderField: "X-Bundle-ID")
        
        // Build request body
        var body: [String: Any] = ["message": message]
        if let history = history {
            body["history"] = history
        }
        // Include system prompt with portfolio/market context
        if let systemPrompt = systemPrompt {
            body["systemPrompt"] = systemPrompt
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        // Create streaming session
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 90
        config.timeoutIntervalForResource = 90
        let session = URLSession(configuration: config)
        
        #if DEBUG
        print("[FirebaseService] Starting streaming request to \(url.absoluteString)")
        #endif
        
        // Make streaming request
        let (bytes, response) = try await session.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            #if DEBUG
            print("[FirebaseService] Invalid response - not HTTP")
            #endif
            throw FirebaseServiceError.networkError("Invalid response")
        }
        
        #if DEBUG
        print("[FirebaseService] HTTP status: \(httpResponse.statusCode)")
        #endif
        
        guard (200...299).contains(httpResponse.statusCode) else {
            #if DEBUG
            print("[FirebaseService] HTTP error: \(httpResponse.statusCode)")
            #endif
            throw FirebaseServiceError.serverError("HTTP \(httpResponse.statusCode)")
        }
        
        var fullText = ""
        var chunkCount = 0
        var lineCount = 0
        
        // Process SSE stream
        for try await line in bytes.lines {
            lineCount += 1
            
            // SSE format: "data: {...}\n"
            guard line.hasPrefix("data: ") else {
                #if DEBUG
                if lineCount <= 3 {
                    print("[FirebaseService] Skipping non-data line #\(lineCount): \(line.prefix(50))...")
                }
                #endif
                continue
            }
            let jsonString = String(line.dropFirst(6))
            
            guard !jsonString.isEmpty,
                  let jsonData = jsonString.data(using: .utf8) else { continue }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    // Check for error
                    if let error = json["error"] as? String {
                        #if DEBUG
                        print("[FirebaseService] Server error in stream: \(error)")
                        #endif
                        throw FirebaseServiceError.serverError(error)
                    }
                    
                    // Get content chunk
                    if let content = json["content"] as? String, !content.isEmpty {
                        chunkCount += 1
                        fullText += content
                        
                        #if DEBUG
                        if chunkCount <= 3 {
                            print("[FirebaseService] Chunk #\(chunkCount): +\(content.count) chars, total: \(fullText.count)")
                        }
                        #endif
                        
                        // Update UI on main thread and yield to allow SwiftUI to render
                        await MainActor.run {
                            onChunk(fullText)
                        }
                        // Small yield to prevent UI update batching - allows progressive text appearance
                        await Task.yield()
                    }
                    
                    // Check if done
                    if json["done"] as? Bool == true {
                        #if DEBUG
                        print("[FirebaseService] Stream complete, \(chunkCount) chunks received")
                        #endif
                        break
                    }
                }
            } catch let parseError as FirebaseServiceError {
                throw parseError
            } catch {
                // Skip malformed chunks
                #if DEBUG
                print("[FirebaseService] Skipping malformed chunk: \(error.localizedDescription)")
                #endif
                continue
            }
        }
        
        #if DEBUG
        print("[FirebaseService] Streaming finished, total lines: \(lineCount), chunks: \(chunkCount), chars: \(fullText.count)")
        #endif

        return fullText
    }
    
    // MARK: - Personalized AI Features (Auth Required)
    
    /// Get personalized portfolio insight (requires authentication)
    func getPortfolioInsight(
        holdings: [[String: Any]],
        totalValue: Double,
        btcDominance: Double?,
        marketCap: Double?
    ) async throws -> PortfolioInsightResponse {
        // This requires authentication
        guard currentUserId != nil else {
            throw FirebaseServiceError.authenticationRequired
        }
        
        var data: [String: Any] = [
            "holdings": holdings,
            "totalValue": totalValue
        ]
        
        if let btcDom = btcDominance {
            data["btcDominance"] = btcDom
        }
        if let mc = marketCap {
            data["marketCap"] = mc
        }
        
        return try await callFunction(
            name: "getPortfolioInsight",
            data: data,
            responseType: PortfolioInsightResponse.self,
            requiresAuth: true
        )
    }
    
    // MARK: - Market Data Proxy
    
    /// Get CoinGecko markets data via Firebase proxy (with caching)
    func getCoinGeckoMarkets(page: Int = 1, perPage: Int = 100, sparkline: Bool = true) async throws -> CoinGeckoMarketsResponse {
        let data: [String: Any] = [
            "page": page,
            "perPage": perPage,
            "sparkline": sparkline
        ]
        
        return try await callFunction(
            name: "getCoinGeckoMarkets",
            data: data,
            responseType: CoinGeckoMarketsResponse.self
        )
    }
    
    /// Get CoinGecko global data via Firebase proxy (with caching)
    func getCoinGeckoGlobal() async throws -> CoinGeckoGlobalResponse {
        return try await callFunction(
            name: "getCoinGeckoGlobal",
            data: [:],
            responseType: CoinGeckoGlobalResponse.self
        )
    }
    
    /// Get Binance 24hr tickers via Firebase proxy (with 30-second caching)
    /// This provides real-time price data shared across all users
    /// - Parameter symbols: Optional array of symbols to fetch (e.g., ["BTCUSDT", "ETHUSDT"]).
    ///                      If empty/nil, fetches all USDT pairs.
    func getBinanceTickers(symbols: [String]? = nil) async throws -> BinanceTickersResponse {
        var data: [String: Any] = [:]
        if let symbols = symbols, !symbols.isEmpty {
            data["symbols"] = symbols
        }
        
        return try await callFunction(
            name: "getBinance24hrTickers",
            data: data,
            responseType: BinanceTickersResponse.self
        )
    }
    
    // MARK: - Chart Data Cache (All Users Get Same Data)
    
    /// Get chart candlestick data via Firebase cache
    /// This provides OHLCV data shared across all users, reducing API calls
    /// - Parameters:
    ///   - symbol: Trading symbol (e.g., "BTC", "ETH")
    ///   - interval: Chart interval (e.g., "1m", "5m", "1h", "1d", "1w", "1M")
    ///   - limit: Optional number of candles to request (capped at 1000 server-side)
    /// - Returns: ChartDataResponse with cached OHLCV points
    func getChartData(symbol: String, interval: String, limit: Int? = nil) async throws -> ChartDataResponse {
        var data: [String: Any] = [
            "symbol": symbol,
            "interval": interval
        ]
        if let limit = limit {
            data["limit"] = limit
        }
        
        return try await callFunction(
            name: "getChartData",
            data: data,
            responseType: ChartDataResponse.self
        )
    }
    
    // MARK: - Order Book (Scalable Proxy)
    
    /// Get order book depth data via Firebase proxy (with 500ms caching)
    /// SCALABILITY: This prevents rate limiting by caching order book data server-side.
    /// All users viewing the same coin get identical data from a single API call.
    /// - Parameters:
    ///   - symbol: Trading pair base symbol (e.g., "BTC", "ETH")
    ///   - limit: Depth limit (5, 10, 20, 50, 100) - defaults to 20
    ///   - exchange: Preferred exchange (binance, coinbase, kraken, kucoin) - defaults to binance
    /// - Returns: OrderBookDepthResponse with bids/asks arrays
    func getOrderBookDepth(symbol: String, limit: Int = 20, exchange: String? = nil) async throws -> OrderBookDepthResponse {
        var data: [String: Any] = [
            "symbol": symbol.uppercased(),
            "limit": limit
        ]
        
        // EXCHANGE SELECTION: Pass exchange preference to Firebase proxy
        if let exchange = exchange {
            data["exchange"] = exchange.lowercased()
        }
        
        return try await callFunction(
            name: "getOrderBookDepth",
            data: data,
            responseType: OrderBookDepthResponse.self
        )
    }
    
    /// Get historical chart data from CoinGecko via Firebase cache
    /// Used for long timeframes (3Y, ALL) where Binance has limited data
    /// - Parameters:
    ///   - coinId: CoinGecko coin ID (e.g., "bitcoin", "ethereum")
    ///   - days: Number of days or "max" for all available data
    /// - Returns: CoinGeckoChartDataResponse with price and volume history
    func getChartDataCoinGecko(coinId: String, days: Any) async throws -> CoinGeckoChartDataResponse {
        let data: [String: Any] = [
            "coinId": coinId,
            "days": days
        ]
        
        return try await callFunction(
            name: "getChartDataCoinGecko",
            data: data,
            responseType: CoinGeckoChartDataResponse.self
        )
    }
    
    /// Convenience method to get parsed Binance tickers
    func getParsedBinanceTickers(symbols: [String]? = nil) async throws -> [BinanceTicker] {
        let response = try await getBinanceTickers(symbols: symbols)
        return response.tickers.compactMap { BinanceTicker(from: $0) }
    }
    
    // MARK: - Commodity Prices
    
    /// Get commodity prices via Firebase proxy (with 60-second caching)
    /// This provides shared commodity price data across all users, avoiding rate limits
    /// - Parameter symbols: Optional array of Yahoo Finance symbols (e.g., ["GC=F", "SI=F"]).
    ///                      If empty/nil, fetches all standard commodities.
    func getCommodityPrices(symbols: [String]? = nil) async throws -> CommodityPricesResponse {
        var data: [String: Any] = [:]
        if let symbols = symbols, !symbols.isEmpty {
            data["symbols"] = symbols
        }
        
        return try await callFunction(
            name: "getCommodityPrices",
            data: data,
            responseType: CommodityPricesResponse.self
        )
    }
    
    // MARK: - Stock Quotes
    
    /// Get stock quotes via Firebase proxy (with 30-second caching)
    /// This provides shared stock quote data across all users, avoiding Yahoo Finance rate limits.
    /// Stocks go through the same Firebase proxy pattern as commodities.
    /// - Parameter symbols: Array of Yahoo Finance stock symbols (e.g., ["AAPL", "MSFT", "TSLA"])
    /// - Returns: StockQuotesResponse with quote data
    func getStockQuotes(symbols: [String]) async throws -> StockQuotesResponse {
        guard !symbols.isEmpty else {
            throw FirebaseServiceError.networkError("No symbols provided")
        }
        
        let data: [String: Any] = ["symbols": symbols]
        
        return try await callFunction(
            name: "getStockQuotes",
            data: data,
            responseType: StockQuotesResponse.self
        )
    }
    
    /// Get stock sparkline history via Firebase proxy (shared across all users)
    /// - Parameters:
    ///   - symbols: Array of Yahoo Finance symbols (e.g., ["AAPL", "MSFT", "GC=F"])
    ///   - range: Yahoo range string (default: "1d")
    ///   - interval: Yahoo interval string (default: "5m")
    /// - Returns: StockSparklinesResponse containing one series per symbol
    func getStockSparklines(
        symbols: [String],
        range: String = "1d",
        interval: String = "5m"
    ) async throws -> StockSparklinesResponse {
        guard !symbols.isEmpty else {
            throw FirebaseServiceError.networkError("No symbols provided")
        }
        
        let data: [String: Any] = [
            "symbols": symbols,
            "range": range,
            "interval": interval
        ]
        
        return try await callFunction(
            name: "getStockSparklines",
            data: data,
            responseType: StockSparklinesResponse.self
        )
    }
    
    /// Get Pump.fun meme coin tokens via Firebase proxy
    /// - Parameter type: Token type - "recent", "trending", or "graduated"
    /// - Returns: PumpFunTokensResponse with token data
    func getPumpFunTokens(type: String = "recent") async throws -> PumpFunTokensResponse {
        let data: [String: Any] = [
            "type": type
        ]
        
        return try await callFunction(
            name: "getPumpFunTokens",
            data: data,
            responseType: PumpFunTokensResponse.self
        )
    }
    
    // MARK: - Whale Tracking
    
    /// Get whale transactions via Firebase proxy (with caching)
    /// This provides shared whale data across all users, preventing rate limiting
    /// - Parameters:
    ///   - minAmountUSD: Minimum transaction amount in USD (default: 100000)
    ///   - blockchains: Array of blockchains to fetch from (default: all)
    /// - Returns: WhaleTransactionsResponse with transaction data
    func getWhaleTransactions(
        minAmountUSD: Double = 100000,
        blockchains: [String] = ["ethereum", "bitcoin", "solana"]
    ) async throws -> WhaleTransactionsResponse {
        let data: [String: Any] = [
            "minAmountUSD": minAmountUSD,
            "blockchains": blockchains
        ]
        
        return try await callFunction(
            name: "getWhaleTransactions",
            data: data,
            responseType: WhaleTransactionsResponse.self
        )
    }
    
    // MARK: - Crypto Events / Calendar
    
    /// Get upcoming crypto events via Firebase proxy (with caching)
    /// Combines CoinMarketCal data with known recurring events (FOMC, CPI, etc.)
    /// - Returns: UpcomingEventsResponse with event data
    func getUpcomingEvents() async throws -> UpcomingEventsResponse {
        return try await callFunction(
            name: "getUpcomingEvents",
            data: [:],
            responseType: UpcomingEventsResponse.self
        )
    }
    
    // MARK: - Leaderboard
    
    /// Get leaderboard data via Firebase (for shared rankings)
    /// Note: Demo data is generated client-side, this is for future server aggregation
    /// - Parameters:
    ///   - category: Ranking category (pnl, pnlPercent, winRate, etc.)
    ///   - period: Time period (week, month, all)
    ///   - tradingMode: Trading mode (paper, live)
    ///   - limit: Max entries to return
    /// - Returns: LeaderboardResponse with ranking data
    func getLeaderboard(
        category: String = "pnl",
        period: String = "month",
        tradingMode: String = "paper",
        limit: Int = 50
    ) async throws -> LeaderboardResponse {
        let data: [String: Any] = [
            "category": category,
            "period": period,
            "tradingMode": tradingMode,
            "limit": limit
        ]
        
        return try await callFunction(
            name: "getLeaderboard",
            data: data,
            responseType: LeaderboardResponse.self
        )
    }
    
    // MARK: - Secure Session
    
    /// Secure URLSession with certificate pinning
    private lazy var secureSession: URLSession = {
        return FirebaseService.createSecureSession()
    }()
    
    // MARK: - Private Helpers
    
    /// Helper struct for parsing Firebase callable function responses
    private struct FirebaseResponse<T: Decodable>: Decodable {
        let result: T
    }
    
    /// Call a Firebase Cloud Function
    /// Tracks recent 503 errors to apply progressive backoff across all functions.
    /// Prevents thundering herd when multiple services hit rate limits simultaneously.
    private var recent503Count: Int = 0
    private var last503At: Date = .distantPast
    
    private func callFunction<T: Codable>(
        name: String,
        data: [String: Any],
        responseType: T.Type,
        requiresAuth: Bool = false
    ) async throws -> T {
        #if DEBUG
        print("[FirebaseService] callFunction: \(name)")
        #endif
        guard isConfigured else {
            #if DEBUG
            print("[FirebaseService] callFunction failed: not configured")
            #endif
            throw FirebaseServiceError.notConfigured
        }
        
        // Check local cache first (function-specific TTL)
        let cacheKey = "\(name)_\(data.description.hashValue)"
        let effectiveCacheDuration = cacheDuration(for: name)
        if let cached = localCache[cacheKey],
           Date().timeIntervalSince(cached.timestamp) < effectiveCacheDuration {
            if let decoded = try? JSONDecoder().decode(T.self, from: cached.data) {
                #if DEBUG
                print("[FirebaseService] callFunction: returning cached response")
                #endif
                return decoded
            }
        }
        
        // RATE LIMIT FIX: If we've seen recent 503s, add progressive backoff
        // This prevents all services from hammering the server simultaneously after rate limits.
        // PERFORMANCE: Chart data and market data are exempted — users expect instant response
        // when switching timeframes, and these functions rarely cause 503s themselves.
        let now = Date()
        let isHighPriorityFunction = name == "getChartData" || name == "getChartDataCoinGecko"
            || name == "getCoinGeckoMarkets" || name == "getCoinGeckoGlobal"
        if recent503Count > 0 && now.timeIntervalSince(last503At) < 30.0 && !isHighPriorityFunction {
            let backoffSeconds = min(Double(recent503Count) * 2.0, 10.0) // 2s, 4s, 6s, ... up to 10s
            #if DEBUG
            print("[FirebaseService] Rate limit backoff: waiting \(String(format: "%.1f", backoffSeconds))s before \(name) (recent 503s: \(recent503Count))")
            #endif
            try? await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
        }
        
        // Build URL
        guard let url = URL(string: "\(functionsBaseURL)/\(name)") else {
            #if DEBUG
            print("[FirebaseService] callFunction failed: invalid URL")
            #endif
            throw FirebaseServiceError.networkError("Invalid URL")
        }
        #if DEBUG
        print("[FirebaseService] callFunction URL: \(url.absoluteString)")
        #endif
        
        // Build request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add security headers
        let timestamp = Date()
        request.setValue(String(Int(timestamp.timeIntervalSince1970)), forHTTPHeaderField: "X-Request-Timestamp")
        request.setValue(Bundle.main.bundleIdentifier ?? "com.cryptosage", forHTTPHeaderField: "X-Bundle-ID")
        
        // Add auth header if required
        if requiresAuth, let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if requiresAuth {
            throw FirebaseServiceError.authenticationRequired
        }
        
        // Wrap data in the expected format for callable functions
        let requestBody: [String: Any] = ["data": data]
        let bodyData = try JSONSerialization.data(withJSONObject: requestBody)
        request.httpBody = bodyData
        
        // Add request signature for integrity
        let signature = FirebaseSecurityConfig.signRequest(endpoint: name, timestamp: timestamp, body: bodyData)
        request.setValue(signature, forHTTPHeaderField: "X-Request-Signature")
        
        // Make request using secure session with certificate pinning
        #if DEBUG
        print("[FirebaseService] Making request to \(name)...")
        #endif
        let (responseData, response) = try await secureSession.data(for: request)
        
        // Check HTTP status
        guard let httpResponse = response as? HTTPURLResponse else {
            #if DEBUG
            print("[FirebaseService] Invalid HTTP response for \(name)")
            #endif
            throw FirebaseServiceError.networkError("Invalid response")
        }
        
        #if DEBUG
        print("[FirebaseService] HTTP status: \(httpResponse.statusCode) for \(name)")
        #endif
        
        switch httpResponse.statusCode {
        case 200:
            // Clear 503 counter on success (decay)
            if recent503Count > 0 { recent503Count = max(0, recent503Count - 1) }
            break
        case 401:
            #if DEBUG
            print("[FirebaseService] Authentication required for \(name)")
            #endif
            throw FirebaseServiceError.authenticationRequired
        case 404:
            // Function not deployed - fail fast so caller can use fallback immediately
            #if DEBUG
            print("[FirebaseService] Function '\(name)' not found (404) - skipping to fallback")
            #endif
            throw FirebaseServiceError.functionNotFound(name)
        case 429:
            recent503Count += 1
            last503At = Date()
            #if DEBUG
            print("[FirebaseService] Rate limit exceeded for \(name)")
            #endif
            throw FirebaseServiceError.rateLimitExceeded
        case 500...599:
            // RATE LIMIT FIX: Track 503s specifically for backoff
            if httpResponse.statusCode == 503 {
                recent503Count += 1
                last503At = Date()
            }
            let errorMessage = String(data: responseData, encoding: .utf8) ?? "Unknown server error"
            #if DEBUG
            print("[FirebaseService] Server error for \(name): \(errorMessage)")
            #endif
            throw FirebaseServiceError.serverError(errorMessage)
        default:
            let errorMessage = String(data: responseData, encoding: .utf8) ?? "Request failed"
            #if DEBUG
            print("[FirebaseService] HTTP error \(httpResponse.statusCode) for \(name): \(errorMessage)")
            #endif
            throw FirebaseServiceError.networkError(errorMessage)
        }
        
        // Parse response - Firebase wraps the result in {"result": ...}
        do {
            let decoded = try JSONDecoder().decode(FirebaseResponse<T>.self, from: responseData)
            
            // Cache the result
            if let resultData = try? JSONEncoder().encode(decoded.result) {
                localCache[cacheKey] = (data: resultData, timestamp: Date())
            }
            
            #if DEBUG
            print("[FirebaseService] Successfully decoded response for \(name)")
            #endif
            return decoded.result
        } catch {
            #if DEBUG
            print("[FirebaseService] Decoding error for \(name): \(error.localizedDescription)")
            #endif
            // Try decoding directly (for some error responses)
            if let decoded = try? JSONDecoder().decode(T.self, from: responseData) {
                return decoded
            }
            throw FirebaseServiceError.decodingError(error.localizedDescription)
        }
    }

    private func cacheDuration(for functionName: String) -> TimeInterval {
        switch functionName {
        case "getCoinGeckoMarkets":
            return 20   // Keep markets responsive to live movement
        case "getCoinGeckoGlobal":
            return 30   // Global values can be slightly less frequent
        default:
            return defaultLocalCacheDuration
        }
    }
    
    /// Clear local cache
    func clearLocalCache() {
        localCache.removeAll()
    }
    
    // MARK: - Privacy & GDPR Compliance
    
    /// Export all user data (GDPR Right to Data Portability)
    func exportUserData() async throws -> UserDataExport {
        guard currentUserId != nil else {
            throw FirebaseServiceError.authenticationRequired
        }
        
        return try await callFunction(
            name: "exportUserData",
            data: [:],
            responseType: UserDataExport.self,
            requiresAuth: true
        )
    }
    
    /// Delete all user data (GDPR Right to Erasure)
    /// WARNING: This is irreversible
    func deleteUserData(confirmDeletion: String = "DELETE_ALL_MY_DATA") async throws -> DataDeletionResponse {
        guard currentUserId != nil else {
            throw FirebaseServiceError.authenticationRequired
        }
        
        return try await callFunction(
            name: "deleteUserData",
            data: ["confirmDeletion": confirmDeletion],
            responseType: DataDeletionResponse.self,
            requiresAuth: true
        )
    }
    
    /// Update consent preferences
    func updateConsent(
        analytics: Bool? = nil,
        marketing: Bool? = nil,
        personalizedAds: Bool? = nil,
        dataSharing: Bool? = nil
    ) async throws -> ConsentResponse {
        guard currentUserId != nil else {
            throw FirebaseServiceError.authenticationRequired
        }
        
        var data: [String: Any] = [:]
        if let analytics = analytics { data["analytics"] = analytics }
        if let marketing = marketing { data["marketing"] = marketing }
        if let personalizedAds = personalizedAds { data["personalizedAds"] = personalizedAds }
        if let dataSharing = dataSharing { data["dataSharing"] = dataSharing }
        
        return try await callFunction(
            name: "updateConsent",
            data: data,
            responseType: ConsentResponse.self,
            requiresAuth: true
        )
    }
    
    /// Get current consent status
    func getConsentStatus() async throws -> ConsentStatusResponse {
        guard currentUserId != nil else {
            throw FirebaseServiceError.authenticationRequired
        }
        
        return try await callFunction(
            name: "getConsentStatus",
            data: [:],
            responseType: ConsentStatusResponse.self,
            requiresAuth: true
        )
    }
}

// MARK: - Privacy Response Types

/// Response from user data export
struct UserDataExport: Codable {
    let success: Bool
    let data: [String: AnyCodable]?
    let exportedAt: String
}

/// Response from data deletion
struct DataDeletionResponse: Codable {
    let success: Bool
    let message: String
    let deletedAt: String
}

/// Response from consent update
struct ConsentResponse: Codable {
    let success: Bool
    let updatedConsent: [String: AnyCodable]?
}

/// Response from consent status check
struct ConsentStatusResponse: Codable {
    let success: Bool
    let consent: ConsentPreferences
    
    struct ConsentPreferences: Codable {
        let analyticsConsent: Bool?
        let marketingConsent: Bool?
        let personalizedAdsConsent: Bool?
        let dataSharingConsent: Bool?
    }
}

// MARK: - Helper: AnyCodable for dynamic JSON

/// A type-erased Codable value for handling dynamic JSON
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unable to decode value")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unable to encode value"))
        }
    }
}

// MARK: - Web Search & Article Reading

extension FirebaseService {
    /// Web search response
    struct WebSearchResponse: Codable {
        struct SearchResult: Codable {
            let title: String
            let url: String
            let content: String
            let publishedDate: String?
        }
        
        let query: String
        let answer: String?
        let results: [SearchResult]
        let dailyUsed: Int?
        let dailyLimit: Int?
    }
    
    /// Read article response
    struct ReadArticleResponse: Codable {
        let title: String
        let url: String
        let content: String
        let dailyUsed: Int?
        let dailyLimit: Int?
    }
    
    /// Perform a web search using Firebase backend
    /// Rate limited by subscription tier (no user API key needed)
    func webSearch(query: String) async throws -> WebSearchResponse {
        guard isConfigured else {
            throw FirebaseServiceError.notConfigured
        }
        
        let data: [String: Any] = ["query": query]
        
        return try await callFunction(
            name: "webSearch",
            data: data,
            responseType: WebSearchResponse.self
        )
    }
    
    /// Read article content from a URL using Firebase backend
    /// Rate limited by subscription tier
    func readArticle(url: String) async throws -> ReadArticleResponse {
        guard isConfigured else {
            throw FirebaseServiceError.notConfigured
        }
        
        let data: [String: Any] = ["url": url]
        
        return try await callFunction(
            name: "readArticle",
            data: data,
            responseType: ReadArticleResponse.self
        )
    }
    
    /// Format web search results for AI consumption
    func formatWebSearchForAI(_ response: WebSearchResponse) -> String {
        var output = ""
        
        if let answer = response.answer, !answer.isEmpty {
            output += "Summary:\n\(answer)\n\n"
        }
        
        if !response.results.isEmpty {
            output += "Sources:\n"
            for (index, result) in response.results.enumerated() {
                output += "\n[\(index + 1)] \(result.title)\n"
                output += "URL: \(result.url)\n"
                output += "\(result.content)\n"
                if let date = result.publishedDate {
                    output += "Published: \(date)\n"
                }
            }
        }
        
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Feature Flag

extension FirebaseService {
    /// Check if Firebase features should be used
    /// Returns false if not configured or if user has opted out
    var shouldUseFirebase: Bool {
        guard isConfigured else { return false }
        
        // Allow users to disable Firebase via settings
        let userDisabled = UserDefaults.standard.bool(forKey: "Firebase.Disabled")
        return !userDisabled
    }
    
    /// Whether to use Firebase for AI features vs direct OpenAI calls
    /// Firebase is preferred for shared content (market sentiment, coin insights)
    /// Direct calls may still be used for personalized content when user is not signed in
    var useFirebaseForAI: Bool {
        return shouldUseFirebase
    }
    
    /// Whether web search is available (via Firebase)
    var hasWebSearchCapability: Bool {
        return shouldUseFirebase
    }
}
